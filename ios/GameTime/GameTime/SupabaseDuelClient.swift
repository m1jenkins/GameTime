import Foundation
import Supabase

@MainActor
final class SupabaseDuelClient: DuelClient {
    private let enabled: Bool
    private let currentActor: @MainActor () -> UUID?
    private let rpc: @MainActor (String, [String: DuelParameter]) async throws -> Data
    private let readTable: @MainActor (String) async throws -> Data

    init(client: SupabaseClient, enabled: Bool) {
        self.enabled = enabled
        currentActor = { client.auth.currentSession?.user.id }
        rpc = { name, parameters in
            try await client.rpc(name, params: parameters).execute().data
        }
        readTable = { name in
            try await client.from(name).select().limit(100).execute().data
        }
    }

    /// A transport seam for wire-contract and session-switch tests.
    init(enabled: Bool, currentActor: @escaping @MainActor () -> UUID?,
         rpc: @escaping @MainActor (String, [String: DuelParameter]) async throws -> Data,
         readTable: @escaping @MainActor (String) async throws -> Data) {
        self.enabled = enabled
        self.currentActor = currentActor
        self.rpc = rpc
        self.readTable = readTable
    }

    func catalog(actorID: UUID) async throws -> DuelCatalog {
        try check(actorID)
        do {
            let policyData = try await readTable("duel_policy_versions")
            try check(actorID)
            let eventData = try await readTable("duel_event_fixtures")
            try check(actorID)
            return DuelCatalog(
                events: try decode([DuelEvent].self, eventData),
                policies: try decode([DuelPolicy].self, policyData)
            )
        } catch { throw map(error) }
    }

    func list(actorID: UUID, before: DuelAgreement?) async throws -> [DuelAgreement] {
        var parameters: [String: DuelParameter] = ["p_limit": .integer(50)]
        if let before {
            // Preserve subsecond creation precision in the pagination cursor.
            parameters["p_before"] = .string(before.createdAtWireValue ?? before.createdAt.formatted(
                .iso8601.time(includingFractionalSeconds: true)))
            parameters["p_before_id"] = .string(before.id.uuidString.lowercased())
        }
        let data = try await send("list_my_duels_v1", parameters, actorID)
        let rows = try decode([DuelAgreement].self, data)
        for row in rows { try row.validate(for: actorID) }
        return rows
    }

    func detail(id: UUID, actorID: UUID) async throws -> DuelAgreement {
        let data = try await send("get_duel_v1", [
            "p_challenge_id": .string(id.uuidString.lowercased())
        ], actorID)
        let row = try decode(DuelAgreement.self, data)
        try row.validate(for: actorID)
        guard row.id == id else { throw DuelClientError.invalidResponse }
        return row
    }

    func lifecycle(id: UUID, actorID: UUID) async throws -> DuelLifecycle {
        let data = try await send("get_duel_lifecycle_v1", [
            "p_challenge_id": .string(id.uuidString.lowercased())
        ], actorID)
        let row = try decode(DuelLifecycle.self, data)
        guard row.challengeId == id else { throw DuelClientError.invalidResponse }
        return row
    }

    func invitationLink(id: UUID, actorID: UUID) async throws -> DuelInvitationLink? {
        let data = try await send("get_my_duel_link_v1", ["p_challenge_id": .string(id.uuidString.lowercased())], actorID)
        let link = try decode(DuelInvitationLink?.self, data)
        guard link == nil || link?.challengeId == id else { throw DuelClientError.invalidResponse }
        return link
    }

    func resolveInvitation(token: UUID, actorID: UUID) async throws -> UUID {
        let data = try await send("resolve_duel_link_v1", ["p_token": .string(token.uuidString.lowercased())], actorID)
        return try decode(DuelInvitationDestination.self, data).challengeId
    }

    func submit(_ request: PendingDuelRequest) async throws -> UUID {
        try request.validate(for: request.actorID)
        do {
            return try decode(UUID.self, await send(
                request.operation.rpc,
                request.operation.parameters(requestID: request.requestID), request.actorID
            ))
        } catch {
            if (error as? DuelClientError) == .slotOccupied {
                switch request.operation {
                case .fileReview: throw DuelClientError.reviewAlreadyFiled
                case .exit: throw DuelClientError.exitAlreadySaved
                default: break
                }
            }
            throw error
        }
    }

    private func check(_ actorID: UUID) throws {
        guard enabled else { throw DuelClientError.accessDenied }
        guard currentActor() == actorID else { throw DuelClientError.accountChanged }
    }

    private func send(_ name: String, _ parameters: [String: DuelParameter], _ actorID: UUID) async throws -> Data {
        try check(actorID)
        do {
            let data = try await rpc(name, parameters)
            try check(actorID)
            return data
        } catch { throw map(error) }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        guard data.count <= 2_000_000 else { throw DuelClientError.invalidResponse }
        do { return try DuelCodec.decoder().decode(type, from: data) }
        catch { throw DuelClientError.invalidResponse }
    }

    private func map(_ error: Error) -> DuelClientError {
        if let error = error as? DuelClientError { return error }
        if let error = error as? PostgrestError { return .sqlState(error.code) }
        return .unavailable
    }
}
