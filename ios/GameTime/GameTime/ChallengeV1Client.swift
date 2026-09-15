import Foundation
import Supabase

@MainActor protocol ChallengeV1Client: AnyObject {
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page
    func list(actor: UUID) async throws -> [ChallengeV1]
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T
}
extension ChallengeV1Client {
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        guard cursor == nil else { throw ChallengeV1Error.invalidResponse }
        let rows = try await list(actor: actor).filter { section.includes($0, actor: actor) }
        return ChallengeV1Page(section: section, projectionRevision: UUID(), serverTime: ChallengeInstant(date: Date()), expiresAt: ChallengeInstant(date: Date().addingTimeInterval(120)), rows: rows, nextCursor: nil)
    }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON] = [:], actor: UUID, as type: T.Type) async throws -> T { throw ChallengeV1Error.unavailable }
}
private final class ChallengeNoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

@MainActor final class SupabaseChallengeV1Client: ChallengeV1Client {
    private let enabled: Bool
    private let binding: @MainActor () -> WeeklyClientSession?
    private let rpc: @MainActor (String, Data) async throws -> Data
    convenience init(sdk: SupabaseClient, url: URL, key: String) {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        let transport = URLSession(configuration: config, delegate: ChallengeNoRedirect(), delegateQueue: nil)
        self.init(url: url, enabled: key.hasPrefix("sb_publishable_"), binding: {
            guard let s = sdk.auth.currentSession, s.expiresAt > Date().timeIntervalSince1970 else { return nil }
            return WeeklyClientSession(actorID: s.user.id, identity: s.accessToken)
        }, rpc: { name, body in
            guard let s = sdk.auth.currentSession, s.expiresAt > Date().timeIntervalSince1970 else { throw ChallengeV1Error.accountChanged }
            var req = URLRequest(url: url.appendingPathComponent("rest/v1/rpc/\(name)"))
            req.httpMethod = "POST"; req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue(key, forHTTPHeaderField: "apikey")
            req.setValue("Bearer \(s.accessToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await transport.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw ChallengeV1Error.unavailable }
            if http.statusCode == 401 { throw ChallengeV1Error.accountChanged }
            guard (200...299).contains(http.statusCode) else {
                let error = try? JSONDecoder().decode(ServerError.self, from: data)
                if error?.message == "challenge_session_required" { throw ChallengeV1Error.accountChanged }
                throw ChallengeV1Error.server(error?.message ?? "unavailable")
            }
            return data
        })
    }
    init(url: URL, enabled: Bool = true, binding: @escaping @MainActor () -> WeeklyClientSession?,
         rpc: @escaping @MainActor (String, Data) async throws -> Data) {
        #if DEBUG || STAGING
        self.enabled = enabled && SupabaseWeeklyClient.isExplicitLoopback(url)
        #else
        self.enabled = false
        #endif
        self.binding = binding; self.rpc = rpc
    }
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        let body = try ChallengeJSON.data(.object(["p_section": .string(section.rawValue), "p_cursor": cursor ?? .null, "p_limit": .integer(10)]))
        let page: ChallengeV1Page = try decode(await send("challenge_section_v1", body, actor))
        guard page.section == section, page.rows.count <= 10, Set(page.rows.map(\.id)).count == page.rows.count else { throw ChallengeV1Error.invalidResponse }
        for row in page.rows { try row.validate(actor: actor) }
        return page
    }
    func list(actor: UUID) async throws -> [ChallengeV1] {
        let rows: [ChallengeV1] = try decode(await send("challenge_list_v1", Data("{}".utf8), actor))
        guard rows.count <= 100, Set(rows.map(\.id)).count == rows.count else { throw ChallengeV1Error.invalidResponse }
        for row in rows { try row.validate(actor: actor) }
        return rows
    }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 {
        let row: ChallengeV1 = try decode(await send("challenge_detail_v1", ChallengeJSON.data(.object(["p_id": .string(id.uuidString.lowercased())])), actor))
        guard row.id == id else { throw ChallengeV1Error.invalidResponse }; try row.validate(actor: actor); return row
    }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        try decode(await send("challenge_command_v1", request.body, request.actorId))
    }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        try decode(await send("challenge_stop_command_v1", request.body, request.actorId))
    }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON] = [:], actor: UUID, as type: T.Type) async throws -> T {
        guard ["challenge_access_status_v1", "challenge_personal_preview_v1", "challenge_community_catalog_v1", "challenge_operator_cases_v1"].contains(name) else { throw ChallengeV1Error.unavailable }
        return try decode(await send(name, ChallengeJSON.data(.object(fields)), actor))
    }
    private func send(_ name: String, _ body: Data, _ actor: UUID) async throws -> Data {
        guard enabled else { throw ChallengeV1Error.unavailable }
        guard let before = binding(), before.actorID == actor else { throw ChallengeV1Error.accountChanged }
        do {
            let data = try await rpc(name, body)
            guard binding() == before else { throw ChallengeV1Error.accountChanged }
            guard data.count <= 2_000_000 else { throw ChallengeV1Error.invalidResponse }
            // SQL attempt quotas also return structured errors to direct RPC
            // adapters, preserving the counter when a lookup is rejected.
            if let error = try? JSONDecoder().decode(ServerError.self, from: data) {
                if error.message == "challenge_session_required" { throw ChallengeV1Error.accountChanged }
                throw ChallengeV1Error.server(error.message)
            }
            return data
        } catch {
            guard binding() == before else { throw ChallengeV1Error.accountChanged }
            throw (error as? ChallengeV1Error) ?? .unavailable
        }
    }
    private func decode<T: Decodable>(_ data: Data) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        do { return try decoder.decode(T.self, from: data) } catch { throw ChallengeV1Error.invalidResponse }
    }
    private struct ServerError: Decodable { let message: String }
}

actor ChallengeV1RequestStore {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    func load(_ actor: UUID) throws -> ChallengeV1Request? {
        let file = path(actor)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let data = try Data(contentsOf: file)
            guard data.count <= 32768 else { throw ChallengeV1Error.storage }
            let request = try JSONDecoder().decode(ChallengeV1Request.self, from: data)
            guard request.actorId == actor else { throw ChallengeV1Error.storage }
            _ = try request.body
            return request
        } catch { throw ChallengeV1Error.storage }
    }
    func save(_ request: ChallengeV1Request) throws {
        if let prior = try load(request.actorId), prior != request { throw ChallengeV1Error.storage }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(request).write(to: path(request.actorId), options: [.atomic, .completeFileProtection])
            var dir = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
        } catch { throw ChallengeV1Error.storage }
    }
    func remove(_ request: ChallengeV1Request) throws {
        guard try load(request.actorId) == request else { return }
        do { try FileManager.default.removeItem(at: path(request.actorId)) } catch { throw ChallengeV1Error.storage }
    }
    func removeAll(for actor: UUID) throws {
        for file in [path(actor), issuedLinksPath(actor)]
        where FileManager.default.fileExists(atPath: file.path) {
            do { try FileManager.default.removeItem(at: file) }
            catch { throw ChallengeV1Error.storage }
        }
    }
    private func path(_ actor: UUID) -> URL { directory.appendingPathComponent(actor.uuidString.lowercased()+".json") }
}

/// No transport or fabricated data. Installing the new UI does not admit hosted challenges.
@MainActor final class UnavailableChallengeV1Client: ChallengeV1Client {
    func list(actor: UUID) async throws -> [ChallengeV1] { throw ChallengeV1Error.unavailable }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 { throw ChallengeV1Error.unavailable }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
}
