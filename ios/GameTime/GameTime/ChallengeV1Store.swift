import Foundation
import Observation

@MainActor @Observable final class ChallengeV1Store {
    private(set) var actor: UUID?
    private(set) var sections: [ChallengeV1Section: ChallengeV1SectionState] = [:]
    private var detailRows: [UUID: ChallengeV1] = [:]
    private var detailReadAt: [UUID: TimeInterval] = [:]
    private let now: @MainActor () -> TimeInterval
    var challenges: [ChallengeV1] {
        var unique: [UUID: ChallengeV1] = [:]
        for section in ChallengeV1Section.allCases {
            for row in sections[section]?.rows ?? [] { if unique[row.id] == nil { unique[row.id] = row } }
        }
        for row in detailRows.values { if unique[row.id] == nil { unique[row.id] = row } }
        return unique.values.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    private(set) var access: ChallengeV1Access?
    private(set) var communities: [ChallengeV1Community] = []
    private(set) var entryError: String?
    private(set) var entryFresh = false
    private(set) var pending: ChallengeV1Request?
    private(set) var error: String?
    private(set) var fresh = false
    private(set) var busy = false
    private(set) var lastReceipt: ChallengeV1Receipt?
    private var visible = true
    private var generation = UUID()
    private var refreshGeneration = UUID()
    private let auth: any AuthClient
    let client: any ChallengeV1Client
    let requests: ChallengeV1RequestStore
    init(auth: any AuthClient, client: any ChallengeV1Client, requests: ChallengeV1RequestStore, now: @escaping @MainActor () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
        self.auth = auth; self.client = client; self.requests = requests
    }
    func setActor(_ actor: UUID?) {
        self.actor = actor; visible = true; generation = UUID(); refreshGeneration = UUID()
        access = nil; communities = []; entryFresh = false; entryError = nil
        sections = [:]; detailRows = [:]; detailReadAt = [:]; pending = nil; error = nil; fresh = false; busy = false; lastReceipt = nil
    }
    func hide() { visible = false; access = nil; communities = []; entryFresh = false; generation = UUID(); refreshGeneration = UUID(); sections = [:]; detailRows = [:]; detailReadAt = [:]; fresh = false; busy = false }
    func show() async { visible = true; await refresh() }
    func refresh() async {
        guard visible, let actor else { return }
        let ticket = generation; let refresh = UUID(); refreshGeneration = refresh
        purgeExpiredContent()
        do {
            let authenticated = await auth.currentUserID()
            guard ticket == generation, refresh == refreshGeneration else { return }
            guard authenticated == actor else { setActor(nil); return }
            let saved = try await requests.load(actor)
            guard ticket == generation, refresh == refreshGeneration else { return }
            pending = saved; error = nil
            for section in ChallengeV1Section.allCases {
                let requestedAt = now()
                do {
                    let page = try await client.page(section, cursor: nil, actor: actor)
                    let finalActor = await auth.currentUserID()
                    // Check after the final await, including each independent page.
                    guard ticket == generation, refresh == refreshGeneration else { return }
                    guard finalActor == actor else { setActor(nil); return }
                    guard now() - requestedAt < 60 else { throw ChallengeV1Error.unavailable }
                    sections[section] = ChallengeV1SectionState(rows: page.rows, cursor: page.nextCursor, projectionRevision: page.projectionRevision, serverTime: page.serverTime, receivedAt: now(), error: nil, fresh: true)
                    for row in page.rows { detailRows.removeValue(forKey: row.id); detailReadAt.removeValue(forKey: row.id) }
                } catch {
                    guard ticket == generation, refresh == refreshGeneration else { return }
                    if (error as? ChallengeV1Error) == .accountChanged { setActor(nil); return }
                    // The watchdog may have expired this section while the request
                    // was held. Read its current state instead of restoring a copy.
                    purgeExpiredContent()
                    var state = sections[section] ?? ChallengeV1SectionState()
                    state.fresh = false
                    state.error = (error as? ChallengeV1Error ?? .unavailable).localizedDescription
                    sections[section] = state; self.error = state.error
                }
            }
            purgeExpiredContent()
            fresh = ChallengeV1Section.allCases.allSatisfy { sections[$0]?.fresh == true }
            await refreshEntry(ticket: ticket, refresh: refresh, actor: actor)
        } catch {
            guard ticket == generation, refresh == refreshGeneration else { return }
            if (error as? ChallengeV1Error) == .accountChanged { setActor(nil) }
            else {
                fresh = false; entryFresh = false; detailReadAt = [:]
                for section in ChallengeV1Section.allCases { sections[section]?.fresh = false }
                self.error = (error as? ChallengeV1Error ?? .unavailable).localizedDescription
            }
        }
    }
    func loadMore(_ section: ChallengeV1Section) async {
        guard let actor, let cursor = sections[section]?.cursor, !busy else { return }
        let ticket = generation; let refresh = refreshGeneration
        let revision = sections[section]?.projectionRevision
        let requestedAt = now()
        do {
            let page = try await client.page(section, cursor: cursor, actor: actor)
            let authenticated = await auth.currentUserID()
            guard ticket == generation, refresh == refreshGeneration, revision == sections[section]?.projectionRevision else { return }
            guard authenticated == actor else { setActor(nil); return }
            guard now() - requestedAt < 60 else { throw ChallengeV1Error.unavailable }
            guard page.projectionRevision == revision else { throw ChallengeV1Error.invalidResponse }
            var state = sections[section] ?? ChallengeV1SectionState()
            let existing = Set(state.rows.map(\.id))
            state.rows.append(contentsOf: page.rows.filter { !existing.contains($0.id) })
            state.cursor = page.nextCursor; state.serverTime = page.serverTime
            // A later page does not extend earlier rows' visibility lifetime.
            sections[section] = state
            purgeExpiredContent()
        } catch {
            guard ticket == generation, refresh == refreshGeneration else { return }
            if (error as? ChallengeV1Error) == .accountChanged { setActor(nil) }
            else { sections[section]?.error = (error as? ChallengeV1Error ?? .unavailable).localizedDescription; sections[section]?.fresh = false; fresh = false }
        }
    }
    func loadDetail(_ id: UUID) async {
        guard let actor else { return }
        let ticket = generation; let refresh = refreshGeneration
        let requestedAt = now()
        do {
            let row = try await client.detail(id, actor: actor)
            let authenticated = await auth.currentUserID()
            guard ticket == generation, refresh == refreshGeneration else { return }
            guard authenticated == actor else { setActor(nil); return }
            guard now() - requestedAt < 60 else { throw ChallengeV1Error.unavailable }
            for section in ChallengeV1Section.allCases {
                if let index = sections[section]?.rows.firstIndex(where: { $0.id == id }) { sections[section]?.rows[index] = row }
            }
            detailRows[id] = row; detailReadAt[id] = now(); error = nil
        } catch {
            guard ticket == generation, refresh == refreshGeneration else { return }
            if (error as? ChallengeV1Error) == .accountChanged { setActor(nil) }
            else { detailRows.removeValue(forKey: id); detailReadAt.removeValue(forKey: id); self.error = (error as? ChallengeV1Error ?? .unavailable).localizedDescription }
        }
    }
    func isFresh(_ row: ChallengeV1) -> Bool {
        if detailRows[row.id]?.revision == row.revision, let read = detailReadAt[row.id], (now() - read) < 60 { return true }
        return sections.values.contains { state in state.fresh && state.receivedAt.map { (now() - $0) < 60 } == true && state.rows.contains { $0.id == row.id && $0.revision == row.revision } }
    }
    func purgeExpiredContent() {
        for section in ChallengeV1Section.allCases {
            if let read = sections[section]?.receivedAt, (now() - read) >= 60 {
                sections[section]?.rows = []; sections[section]?.cursor = nil; sections[section]?.fresh = false
                sections[section]?.error = "This view is out of date. Refresh to see the latest details."
                fresh = false
            }
        }
        for (id, read) in detailReadAt where (now() - read) >= 60 { detailRows.removeValue(forKey: id); detailReadAt.removeValue(forKey: id) }
    }
    func watchVisibility() async {
        var ticks = 0
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard visible else { continue }
            let ticket = generation; let current = await auth.currentUserID()
            guard !Task.isCancelled else { return }
            if ticket == generation && current != actor { setActor(nil); return }
            purgeExpiredContent(); ticks += 1
            if ticks % 6 == 0 && !busy { await refresh() }
        }
    }
    private func refreshEntry(ticket: UUID, refresh: UUID, actor: UUID) async {
        entryFresh = false
        do {
            let access: ChallengeV1Access = try await client.read("challenge_access_status_v1", fields: [:], actor: actor, as: ChallengeV1Access.self)
            let authenticated = await auth.currentUserID()
            guard ticket == generation, refresh == refreshGeneration else { return }
            guard authenticated == actor else { setActor(nil); return }
            self.access = access
            if access.suspended {
                for section in ChallengeV1Section.allCases { sections[section]?.rows.removeAll { !$0.socialHidden } }
                detailRows = detailRows.filter { $0.value.socialHidden }; fresh = false
            }
            let rows: [ChallengeV1Community] = try await client.read("challenge_community_catalog_v1", fields: [:], actor: actor, as: [ChallengeV1Community].self)
            let finalActor = await auth.currentUserID()
            guard ticket == generation, refresh == refreshGeneration else { return }
            guard finalActor == actor else { setActor(nil); return }
            communities = rows; entryFresh = true; entryError = nil
        } catch {
            guard ticket == generation, refresh == refreshGeneration else { return }
            if (error as? ChallengeV1Error) == .accountChanged { setActor(nil) }
            else { entryError = (error as? ChallengeV1Error ?? .unavailable).localizedDescription }
        }
    }
    func submit(op: String, challenge: ChallengeV1? = nil, fields: [String: ChallengeJSON] = [:]) async {
        guard let actor, !busy, pending == nil, challenge.map { isFresh($0) } ?? true else { return }
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
            if (error as? ChallengeV1Error) == .accountChanged { setActor(nil) }
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
