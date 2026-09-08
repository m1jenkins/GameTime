import Foundation
import Observation

@MainActor @Observable final class ChallengeV1Store {
    private(set) var actor: UUID?
    private(set) var challenges: [ChallengeV1] = []
    private(set) var pending: ChallengeV1Request?
    private(set) var error: String?
    private(set) var fresh = false
    private(set) var busy = false
    private(set) var lastReceipt: ChallengeV1Receipt?
    private var generation = UUID()
    private var refreshGeneration = UUID()
    private let auth: any AuthClient
    let client: any ChallengeV1Client
    let requests: ChallengeV1RequestStore
    init(auth: any AuthClient, client: any ChallengeV1Client, requests: ChallengeV1RequestStore) {
        self.auth = auth; self.client = client; self.requests = requests
    }
    func setActor(_ actor: UUID?) {
        self.actor = actor; generation = UUID(); refreshGeneration = UUID()
        challenges = []; pending = nil; error = nil; fresh = false; busy = false; lastReceipt = nil
    }
    func hide() { generation = UUID(); refreshGeneration = UUID(); challenges = []; fresh = false; busy = false }
    func refresh() async {
        guard let actor else { return }
        let ticket = generation; let refresh = UUID(); refreshGeneration = refresh; fresh = false
        do {
            let authenticated = await auth.currentUserID()
            guard ticket == generation, refresh == refreshGeneration else { return }
            guard authenticated == actor else { setActor(nil); return }
            let saved = try await requests.load(actor)
            let rows = try await client.list(actor: actor)
            let finalActor = await auth.currentUserID()
            // Recheck after the final await: held auth cannot restore superseded social content.
            guard ticket == generation, refresh == refreshGeneration else { return }
            guard finalActor == actor else { setActor(nil); return }
            challenges = rows; pending = saved; fresh = true; error = nil
        } catch {
            guard ticket == generation, refresh == refreshGeneration else { return }
            if (error as? ChallengeV1Error) == .accountChanged { setActor(nil) }
            else { self.error = (error as? ChallengeV1Error ?? .unavailable).localizedDescription }
        }
    }
    func submit(op: String, challenge: ChallengeV1? = nil, fields: [String: ChallengeJSON] = [:]) async {
        guard let actor, !busy, pending == nil, challenge == nil || fresh else { return }
        var payload = fields; payload["op"] = .string(op)
        if let challenge {
            payload["id"] = .string(challenge.id.uuidString.lowercased()); payload["revision"] = .integer(challenge.revision)
        }
        let request = ChallengeV1Request(actor: actor, payload: .object(payload))
        await perform(request, abandon: false)
    }
    func retry() async { if let pending, !busy { await perform(pending, abandon: false) } }
    func abandon() async { if let pending, !busy { await perform(pending, abandon: true) } }
    private func perform(_ request: ChallengeV1Request, abandon: Bool) async {
        guard request.actorId == actor else { return }
        let ticket = generation; busy = true; error = nil
        defer { if ticket == generation { busy = false } }
        do {
            try await requests.save(request)
            guard ticket == generation else { return }
            pending = request
            let receipt = try await (abandon ? client.abandon(request) : client.submit(request))
            guard ticket == generation else { return }
            try await requests.remove(request)
            guard ticket == generation else { return }
            pending = nil; lastReceipt = receipt
            await refresh()
        } catch {
            guard ticket == generation else { return }
            fresh = false
            self.error = (error as? ChallengeV1Error ?? .unavailable).localizedDescription
            if (error as? ChallengeV1Error) == .accountChanged { challenges = []; fresh = false }
        }
    }
    var ordered: [ChallengeV1] {
        challenges.sorted { left, right in
            func rank(_ row: ChallengeV1) -> Int {
                if row.status == "review" { return 0 }
                if row.status == "consent_pending" { return 1 }
                if row.status == "active" || row.status == "syncing" { return 2 }
                if row.status == "scheduled" || row.status == "lobby_open" { return 3 }
                return 4
            }
            let a = rank(left), b = rank(right)
            if a != b { return a < b }
            let x = left.notice?.reviewBy ?? (a == 2 ? left.config.endsAt : left.config.startsAt)
            let y = right.notice?.reviewBy ?? (b == 2 ? right.config.endsAt : right.config.startsAt)
            return x == y ? left.id.uuidString < right.id.uuidString : x < y
        }
    }
}
