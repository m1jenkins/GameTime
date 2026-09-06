import Foundation
import Supabase

/// An in-memory identity only. Never encoded into a pending request or cache.
struct WeeklyClientSession: Equatable {
    let actorID: UUID
    let identity: String
}

/// Reject redirects so an explicitly chosen loopback endpoint cannot forward
/// credentials or a mutation to another server.
private final class WeeklyNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class SupabaseWeeklyClient: WeeklyClient {
    private let enabled: Bool
    private let currentSession: @MainActor () -> WeeklyClientSession?
    private let rpc: @MainActor (String, Data) async throws -> Data

    convenience init(client: SupabaseClient, enabled: Bool, localURL: URL, publishableKey: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: WeeklyNoRedirect(), delegateQueue: nil)
        self.init(enabled: enabled && publishableKey.hasPrefix("sb_publishable_"), localURL: localURL, currentSession: {
            guard let value = client.auth.currentSession, value.expiresAt > Date().timeIntervalSince1970 else { return nil }
            return WeeklyClientSession(actorID: value.user.id, identity: value.accessToken)
        }, rpc: { name, body in
            guard let auth = client.auth.currentSession, auth.expiresAt > Date().timeIntervalSince1970 else {
                throw WeeklyClientError.accountChanged
            }
            var request = URLRequest(url: localURL.appendingPathComponent("rest/v1/rpc/\(name)"))
            request.httpMethod = "POST"
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue(publishableKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(auth.accessToken)", forHTTPHeaderField: "Authorization")
            // One transport attempt only. Retrying a saved mutation requires a
            // separate explicit user action, even after a transient HTTP error.
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw WeeklyClientError.invalidResponse }
            guard (200...299).contains(response.statusCode) else {
                let payload = try? JSONDecoder().decode(RPCError.self, from: data)
                if response.statusCode == 401 || response.statusCode == 403 {
                    throw WeeklyClientError.accessDenied
                }
                throw WeeklyClientError.sqlState(payload?.code)
            }
            return data
        })
    }

    /// The seam retains the same loopback/build gate as the real transport.
    init(enabled: Bool, localURL: URL, currentSession: @escaping @MainActor () -> WeeklyClientSession?,
         rpc: @escaping @MainActor (String, Data) async throws -> Data) {
        #if DEBUG || STAGING
        self.enabled = enabled && Self.isExplicitLoopback(localURL)
        #else
        self.enabled = false
        #endif
        self.currentSession = currentSession
        self.rpc = rpc
    }

    nonisolated static func isExplicitLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http", let port = url.port, (1...65535).contains(port),
              ["127.0.0.1", "localhost", "[::1]", "::1"].contains(url.host?.lowercased() ?? ""),
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.isEmpty || url.path == "/" else { return false }
        return true
    }

    func preview(_ draft: WeeklyDraft, actorID: UUID) async throws -> WeeklyPreview {
        try draft.validate(actorID: actorID)
        let result = try decode(WeeklyPreview.self, await send("preview_weekly_friend_v1", body: WeeklyJSON.data(draft.parameters), actorID: actorID))
        try result.validate(actorID: actorID, draft: draft)
        return result
    }
    func list(actorID: UUID) async throws -> [WeeklyChallenge] {
        let rows = try decode([WeeklyChallenge].self, await send("list_my_weekly_v1", body: Data("{}".utf8), actorID: actorID))
        guard rows.count <= 50, Set(rows.map(\.id)).count == rows.count else { throw WeeklyClientError.invalidResponse }
        for row in rows { try row.validate(for: actorID) }
        return rows
    }
    func detail(id: UUID, actorID: UUID) async throws -> WeeklyChallenge {
        let row = try decode(WeeklyChallenge.self, await send("get_weekly_v1", body: idBody(id), actorID: actorID))
        try row.validate(for: actorID)
        guard row.id == id else { throw WeeklyClientError.invalidResponse }
        return row
    }
    func cohorts(actorID: UUID) async throws -> [WeeklyCohort] {
        let rows = try decode([WeeklyCohort].self, await send("list_weekly_cohorts_v1", body: Data("{}".utf8), actorID: actorID))
        guard rows.count <= 10, Set(rows.map(\.id)).count == rows.count else { throw WeeklyClientError.invalidResponse }
        for row in rows { try row.validate() }
        return rows
    }
    func preferences(actorID: UUID) async throws -> WeeklyPreferences {
        try decode(WeeklyPreferences.self, await send("get_weekly_preferences_v1", body: Data("{}".utf8), actorID: actorID))
    }
    func submit(_ request: PendingWeeklyRequest) async throws -> UUID {
        try request.validate(for: request.actorID)
        return try decode(UUID.self, await send(request.operation.rpc, body: request.requestBody, actorID: request.actorID))
    }
    func resolveRequest(_ request: PendingWeeklyRequest) async throws -> WeeklyRequestResolution {
        try request.validate(for: request.actorID)
        let value = try decode(WeeklyRequestResolution.self, await send("resolve_weekly_request_v1",
            body: WeeklyJSON.data(.object(["p_request_id": .string(request.requestID.uuidString.lowercased())])), actorID: request.actorID))
        guard (value.state == "committed" && value.receiptID != nil) || (value.state == "cancelled" && value.receiptID == nil) else { throw WeeklyClientError.invalidResponse }
        return value
    }
    func sharing(id: UUID, actorID: UUID) async throws -> [WeeklySharing] {
        let rows = try decode([WeeklySharing].self, await send("list_weekly_sharing_v1", body: idBody(id), actorID: actorID))
        guard rows.count <= 128, Set(rows.map(\.id)).count == rows.count else { throw WeeklyClientError.invalidResponse }
        return rows
    }
    func followRequests(actorID: UUID) async throws -> [WeeklyFollowRequest] {
        let rows = try decode([WeeklyFollowRequest].self, await send("list_weekly_follow_requests_v1", body: Data("{}".utf8), actorID: actorID))
        guard rows.count <= 100, Set(rows.map(\.id)).count == rows.count,
              rows.allSatisfy({ $0.ownerID != actorID && $0.state == "pending" && $0.policyVersion == "weekly-display-sharing-v1" }) else { throw WeeklyClientError.invalidResponse }
        return rows
    }
    func sharedProgress(actorID: UUID) async throws -> [WeeklySharedProgress] {
        let rows = try decode([WeeklySharedProgress].self, await send("list_shared_weekly_progress_v1", body: Data("{}".utf8), actorID: actorID))
        guard rows.count <= 100, Set(rows.map(\.id)).count == rows.count else { throw WeeklyClientError.invalidResponse }
        for row in rows { try row.validate() }
        return rows
    }
    func recordPilotEvent(actorID: UUID, challengeID: UUID?, event: String, phase: String, requestID: UUID) async throws {
        guard ["rule_preview", "consent", "invitation", "cohort_join", "progress_refresh", "result_view", "review", "withdrawal", "next_week", "sharing"].contains(event),
              ["intent", "exposure", "outcome"].contains(phase) else { throw WeeklyClientError.invalidTerms }
        let body = WeeklyJSON.object(["p_request_id": .string(requestID.uuidString.lowercased()),
            "p_challenge_id": challengeID.map { .string($0.uuidString.lowercased()) } ?? .null,
            "p_event": .string(event), "p_phase": .string(phase)])
        let id = try decode(UUID.self, await send("record_weekly_pilot_event_v1", body: WeeklyJSON.data(body), actorID: actorID))
        guard id == requestID else { throw WeeklyClientError.invalidResponse }
    }

    private func send(_ name: String, body: Data, actorID: UUID) async throws -> Data {
        guard enabled else { throw WeeklyClientError.accessDenied }
        guard let binding = currentSession(), binding.actorID == actorID else { throw WeeklyClientError.accountChanged }
        do {
            let data = try await rpc(name, body)
            guard currentSession() == binding else { throw WeeklyClientError.accountChanged }
            return data
        } catch {
            guard currentSession() == binding else { throw WeeklyClientError.accountChanged }
            throw (error as? WeeklyClientError) ?? .unavailable
        }
    }
    private func idBody(_ id: UUID) throws -> Data {
        try WeeklyJSON.data(.object(["p_challenge_id": .string(id.uuidString.lowercased())]))
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard data.count <= 2_000_000 else { throw WeeklyClientError.invalidResponse }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw WeeklyClientError.invalidResponse }
    }
    private struct RPCError: Decodable { let code: String? }
}
