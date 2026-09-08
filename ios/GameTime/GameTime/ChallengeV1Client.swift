import Foundation
import Supabase

@MainActor protocol ChallengeV1Client: AnyObject {
    func list(actor: UUID) async throws -> [ChallengeV1]
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt
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
        try decode(await send("challenge_mutate_v1", request.body, request.actorId))
    }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        try decode(await send("challenge_abandon_v1", request.body, request.actorId))
    }
    private func send(_ name: String, _ body: Data, _ actor: UUID) async throws -> Data {
        guard enabled else { throw ChallengeV1Error.unavailable }
        guard let before = binding(), before.actorID == actor else { throw ChallengeV1Error.accountChanged }
        do {
            let data = try await rpc(name, body)
            guard binding() == before else { throw ChallengeV1Error.accountChanged }
            guard data.count <= 2_000_000 else { throw ChallengeV1Error.invalidResponse }
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
    private func path(_ actor: UUID) -> URL { directory.appendingPathComponent(actor.uuidString.lowercased()+".json") }
}
