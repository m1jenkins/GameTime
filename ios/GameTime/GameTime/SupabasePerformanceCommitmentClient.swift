import Foundation
import Supabase

/// An in-memory identity only. Never encoded into a pending request or cache.
struct PerformanceCommitmentClientSession: Equatable {
    let actorID: UUID
    let identity: String
}

/// Reject redirects so an explicitly chosen loopback endpoint cannot forward
/// credentials or a mutation to another server.
private final class PerformanceCommitmentNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

@MainActor
final class SupabasePerformanceCommitmentClient: PerformanceCommitmentClient {
    private let enabled: Bool
    private let currentSession: @MainActor () -> PerformanceCommitmentClientSession?
    private let rpc: @MainActor (String, Data) async throws -> Data

    convenience init(client: SupabaseClient, enabled: Bool, localURL: URL, publishableKey: String) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        let session = URLSession(configuration: configuration, delegate: PerformanceCommitmentNoRedirect(), delegateQueue: nil)
        self.init(enabled: enabled && publishableKey.hasPrefix("sb_publishable_"), localURL: localURL, currentSession: {
            guard let value = client.auth.currentSession, value.expiresAt > Date().timeIntervalSince1970 else { return nil }
            return PerformanceCommitmentClientSession(actorID: value.user.id, identity: value.accessToken)
        }, rpc: { name, body in
            guard let auth = client.auth.currentSession, auth.expiresAt > Date().timeIntervalSince1970 else {
                throw PerformanceCommitmentClientError.accountChanged
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
            guard let response = response as? HTTPURLResponse else { throw PerformanceCommitmentClientError.invalidResponse }
            guard (200...299).contains(response.statusCode) else {
                let payload = try? JSONDecoder().decode(RPCError.self, from: data)
                if response.statusCode == 401 || response.statusCode == 403 {
                    throw PerformanceCommitmentClientError.accessDenied
                }
                throw PerformanceCommitmentClientError.sqlState(payload?.code)
            }
            return data
        })
    }

    /// The seam retains the same loopback/build gate as the real transport.
    init(enabled: Bool, localURL: URL, currentSession: @escaping @MainActor () -> PerformanceCommitmentClientSession?,
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

    func preview(_ draft: PerformanceCommitmentDraft, actorID: UUID) async throws -> PerformanceCommitmentPreview {
        try draft.validate()
        let row = try decode(PerformanceCommitmentPreview.self, await send("preview_performance_commitment_v1",
            body: PerformanceCommitmentParameter.body(draft.parameters), actorID: actorID))
        do { try row.validate(for: actorID) } catch { throw PerformanceCommitmentClientError.invalidResponse }
        guard draft.matches(row.terms) else { throw PerformanceCommitmentClientError.invalidResponse }
        return row
    }
    func list(actorID: UUID, before: PerformanceCommitmentAgreement?) async throws -> [PerformanceCommitmentAgreement] {
        var parameters: [String: PerformanceCommitmentParameter] = ["p_limit": .integer(50)]
        if let before {
            try before.validate(for: actorID)
            parameters["p_before"] = .string(before.createdAt.rawValue)
            parameters["p_before_id"] = .string(before.id.uuidString.lowercased())
        }
        let rows = try decode([PerformanceCommitmentAgreement].self, await send("list_my_performance_commitments_v1",
            body: PerformanceCommitmentParameter.body(parameters), actorID: actorID))
        do { for row in rows { try row.validate(for: actorID) } }
        catch { throw PerformanceCommitmentClientError.invalidResponse }
        guard rows.count <= 50, Set(rows.map(\.id)).count == rows.count else { throw PerformanceCommitmentClientError.invalidResponse }
        return rows
    }
    func detail(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentAgreement {
        let row = try decode(PerformanceCommitmentAgreement.self, await send("get_performance_commitment_v1",
            body: idBody(id), actorID: actorID))
        do { try row.validate(for: actorID) } catch { throw PerformanceCommitmentClientError.invalidResponse }
        guard row.id == id else { throw PerformanceCommitmentClientError.invalidResponse }
        return row
    }
    func lifecycle(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentLifecycle {
        let row = try decode(PerformanceCommitmentLifecycle.self, await send("get_commitment_lifecycle_v1",
            body: idBody(id), actorID: actorID))
        guard row.commitmentID == id else { throw PerformanceCommitmentClientError.invalidResponse }
        return row
    }
    func submit(_ request: PendingPerformanceCommitmentRequest) async throws -> PerformanceCommitmentMutationReceipt {
        try request.validate(for: request.actorID)
        do {
            let data = try await send(request.operation.rpc, body: request.requestBody, actorID: request.actorID)
            switch request.operation {
            case .fileReview: return .review(try decode(PerformanceCommitmentReviewReceipt.self, data))
            case .create, .close:
                let id = try decode(UUID.self, data)
                guard request.operation.commitmentID == nil || request.operation.commitmentID == id else {
                    throw PerformanceCommitmentClientError.invalidResponse
                }
                return .commitment(id)
            }
        } catch {
            if error as? PerformanceCommitmentClientError == .slotOccupied,
               case .fileReview = request.operation { throw PerformanceCommitmentClientError.reviewAlreadyFiled }
            throw error
        }
    }
    private func send(_ name: String, body: Data, actorID: UUID) async throws -> Data {
        guard enabled else { throw PerformanceCommitmentClientError.accessDenied }
        guard let binding = currentSession(), binding.actorID == actorID else { throw PerformanceCommitmentClientError.accountChanged }
        do {
            let data = try await rpc(name, body)
            guard currentSession() == binding else { throw PerformanceCommitmentClientError.accountChanged }
            return data
        } catch {
            guard currentSession() == binding else { throw PerformanceCommitmentClientError.accountChanged }
            throw (error as? PerformanceCommitmentClientError) ?? .unavailable
        }
    }
    private func idBody(_ id: UUID) throws -> Data {
        try PerformanceCommitmentParameter.body(["p_commitment_id": .string(id.uuidString.lowercased())])
    }
    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard data.count <= 2_000_000 else { throw PerformanceCommitmentClientError.invalidResponse }
        do { return try JSONDecoder().decode(type, from: data) }
        catch { throw PerformanceCommitmentClientError.invalidResponse }
    }
    private struct RPCError: Decodable { let code: String? }
}
