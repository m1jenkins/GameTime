#if DEBUG || STAGING
import Foundation

/// Shared by two fixture clients to exercise the native pair flow. The local
/// database remains the authority for admission, locking and SQL behavior.
@MainActor
final class FixtureDuelBackend {
    var enabled = true
    var offline = false
    var loseNextResponse = false
    var now: Date
    var activeActors: Set<UUID>
    let event: DuelEvent
    private(set) var rows: [UUID: DuelAgreement] = [:]
    var notices: [UUID: [DuelNotice]] = [:]
    var cases: [UUID: [UUID: [DuelReviewCase]]] = [:]
    var results: [UUID: DuelFinalResult] = [:]
    var returns: [UUID: [UUID: Int]] = [:]
    var closures: [UUID: (actor: UUID, kind: DuelSafeExitKind, at: DuelInstant)] = [:]
    var suppressed: Set<UUID> = []
    private var receipts: [String: (DuelMutation, UUID)] = [:]

    init(actors: Set<UUID>, now: Date = Date()) {
        activeActors = actors
        self.now = now
        event = DuelEvent(id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            policyVersion: "duel-fixture-5k-v1", eventName: "Fictional local 5K",
            course: "fixture_course_5k_v1", wave: "fixture_common_wave_v1",
            startsAt: now.addingTimeInterval(7 * 86400),
            endsAt: now.addingTimeInterval(7 * 86400 + 7200), displayTimezone: "America/Chicago")
    }

    func submit(_ request: PendingDuelRequest) throws -> UUID {
        guard !offline else { throw DuelClientError.unavailable }
        try request.validate(for: request.actorID)
        guard activeActors.contains(request.actorID) else { throw DuelClientError.accessDenied }
        let key = "\(request.actorID):\(request.requestID)"
        if let (operation, id) = receipts[key] {
            guard operation == request.operation else { throw DuelClientError.invalidTerms }
            return id
        }
        let id: UUID
        switch request.operation {
        case let .create(invitee, eventID, policy, consent):
            id = try create(invitee: invitee, eventID: eventID, policy: policy, consent: consent, actor: request.actorID)
        case let .rematch(previous, eventID, policy, consent):
            let old = try detail(previous, actor: request.actorID)
            guard results[previous] != nil, !suppressed.contains(previous) else { throw DuelClientError.lifecycle }
            guard eventID != old.eventID else { throw DuelClientError.invalidTerms }
            let invitee = old.creatorID == request.actorID ? old.inviteeID : old.creatorID
            id = try create(invitee: invitee, eventID: eventID, policy: policy, consent: consent, actor: request.actorID)
        case .issueLink(let challenge):
            let row = try detail(challenge, actor: request.actorID)
            guard enabled, row.creatorID == request.actorID, !suppressed.contains(challenge),
                  activeActors.contains(row.inviteeID) else { throw DuelClientError.accessDenied }
            guard row.status == .invited, now < row.acceptBy else { throw DuelClientError.lifecycle }
            id = challenge
            links[id] = DuelInvitationLink(challengeId: id, token: UUID(),
                expiresAt: DuelInstant(date: min(row.acceptBy, now.addingTimeInterval(86400))))
        case .revokeLink(let challenge, let token):
            let row = try detail(challenge, actor: request.actorID)
            guard row.creatorID == request.actorID else { throw DuelClientError.accessDenied }
            id = challenge
            if links[id]?.token == token { links[id] = nil }
        case .accept(let challenge, let policy, let digest):
            let row = try detail(challenge, actor: request.actorID)
            guard enabled else { throw DuelClientError.accessDenied }
            guard row.canAccept(actorID: request.actorID, now: now) else { throw DuelClientError.lifecycle }
            guard row.policyVersion == policy, row.termsDigest == digest else { throw DuelClientError.invalidTerms }
            guard !hasSlot(request.actorID) else { throw DuelClientError.slotOccupied }
            id = challenge
            let people = row.participants.map { person in
                person.actorID == request.actorID
                    ? participant(id, request.actorID, "invitee", now, policy, digest) : person
            }
            rows[id] = replacing(row, status: .scheduled, participants: people)
        case .decline(let challenge):
            let row = try detail(challenge, actor: request.actorID)
            guard request.actorID == row.inviteeID, row.status == .invited else { throw DuelClientError.lifecycle }
            id = challenge
            let people = row.participants.map { person in
                person.actorID == request.actorID
                    ? DuelParticipant(challengeID: id, actorID: request.actorID, role: "invitee",
                        acceptedAt: nil, consentPolicyVersion: nil, consentTermsDigest: nil, declinedAt: now) : person
            }
            rows[id] = replacing(row, status: .declined, reason: "declined", participants: people)
        case .fileReview(let challenge, let revision, let reason):
            let life = try lifecycle(challenge, actor: request.actorID)
            guard life.notices.contains(where: { $0.proofRevision == revision && $0.canFileReview }) else {
                throw DuelClientError.lifecycle
            }
            guard !(cases[challenge]?[request.actorID] ?? []).contains(where: { $0.proofRevision == revision }) else {
                throw DuelClientError.reviewAlreadyFiled
            }
            id = UUID()
            cases[challenge, default: [:]][request.actorID, default: []].append(
                DuelReviewCase(id: id, proofRevision: revision, reason: reason,
                    filedAt: DuelInstant(date: now), reviewDueAt: DuelInstant(date: now.addingTimeInterval(168 * 3600)),
                    decision: nil, decidedAt: nil))
        case .exit(let challenge, let kind):
            let life = try lifecycle(challenge, actor: request.actorID)
            guard life.canExit else { throw DuelClientError.lifecycle }
            id = challenge
            closures[id] = (request.actorID, kind, DuelInstant(date: now))
        case .cancel(let challenge):
            guard results[challenge] == nil, closures[challenge] == nil else { throw DuelClientError.lifecycle }
            let row = try detail(challenge, actor: request.actorID)
            guard row.canCancel(actorID: request.actorID, now: now) else { throw DuelClientError.lifecycle }
            id = challenge
            rows[id] = replacing(row, status: .cancelled, reason: "participant_cancelled")
        }
        receipts[key] = (request.operation, id)
        if loseNextResponse {
            loseNextResponse = false
            throw DuelClientError.unavailable
        }
        return id
    }

    var links: [UUID: DuelInvitationLink] = [:]
    var rematchEvent: DuelEvent {
        DuelEvent(id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            policyVersion: event.policyVersion, eventName: event.eventName, course: event.course,
            wave: event.wave, startsAt: now.addingTimeInterval(7 * 86400),
            endsAt: now.addingTimeInterval(7 * 86400 + 7200), displayTimezone: event.displayTimezone)
    }

    private func create(invitee: UUID, eventID: UUID, policy: String, consent: Bool, actor: UUID) throws -> UUID {
        guard let event = [event, rematchEvent].first(where: { $0.id == eventID }) else { throw DuelClientError.invalidTerms }
        guard enabled, activeActors.contains(invitee) else { throw DuelClientError.accessDenied }
        guard eventID == event.id, policy == event.policyVersion, consent,
            event.isAvailable(at: now) else { throw DuelClientError.invalidTerms }
        guard !hasSlot(actor) else { throw DuelClientError.slotOccupied }
        let id = UUID()
        let terms = DuelTerms(agreementVersion: 1, policyVersion: policy,
            policy: .simulated5K, creatorID: actor, inviteeID: invitee,
            event: event, createdAt: now,
            acceptBy: min(now.addingTimeInterval(72 * 3600), event.startsAt.addingTimeInterval(-3600)),
            resultsDueAt: event.endsAt.addingTimeInterval(72 * 3600),
            finalityDueAt: event.endsAt.addingTimeInterval(720 * 3600))
        // Opaque fictional server value, never a Swift hash of terms.
        let digest = String(repeating: id.uuidString.replacingOccurrences(of: "-", with: "").lowercased(), count: 2)
        rows[id] = DuelAgreement(id: id, creatorID: actor, inviteeID: invitee,
            eventID: eventID, policyVersion: policy, createdAt: now, startsAt: event.startsAt,
            acceptBy: terms.acceptBy, terms: terms, termsDigest: digest, status: .invited,
            closedAt: nil, closeReason: nil, expiryDue: false, participants: [
                participant(id, actor, "creator", now, policy, digest),
                participant(id, invitee, "invitee", nil, nil, nil)
            ])
        return id
    }

    func invitationLink(_ id: UUID, actor: UUID) throws -> DuelInvitationLink? {
        let row = try detail(id, actor: actor)
        guard row.creatorID == actor, !suppressed.contains(id), activeActors.contains(row.inviteeID) else {
            throw DuelClientError.accessDenied
        }
        guard row.status == .invited, now < row.acceptBy,
              let link = links[id], now < link.expiresAt.date else { return nil }
        return link
    }

    func resolveInvitation(_ token: UUID, actor: UUID) throws -> UUID {
        guard let link = links.values.first(where: { $0.token == token }) else { throw DuelClientError.accessDenied }
        let row = try detail(link.challengeId, actor: actor)
        guard row.inviteeID == actor, row.status == .invited, now < row.acceptBy,
              now < link.expiresAt.date, !suppressed.contains(row.id),
              activeActors.contains(row.creatorID) else { throw DuelClientError.accessDenied }
        return row.id
    }

    func detail(_ id: UUID, actor: UUID) throws -> DuelAgreement {
        guard !offline else { throw DuelClientError.unavailable }
        guard activeActors.contains(actor), let row = rows[id],
            [row.creatorID, row.inviteeID].contains(actor) else { throw DuelClientError.accessDenied }
        return replacing(row, status: row.status, reason: row.closeReason)
    }

    func lifecycle(_ id: UUID, actor: UUID) throws -> DuelLifecycle {
        let row = try detail(id, actor: actor)
        let hidden = suppressed.contains(id) || !activeActors.contains(row.creatorID) || !activeActors.contains(row.inviteeID)
        let ownCases = cases[id]?[actor] ?? []
        let final = results[id]
        let closure = closures[id]
        return DuelLifecycle(challengeId: id, termsDigest: row.termsDigest, contactSuppressed: hidden,
            activatedAt: row.status == .scheduled && now >= row.startsAt ? DuelInstant(date: row.startsAt) : nil,
            notices: hidden ? [] : (notices[id] ?? []).map { notice in
                DuelNotice(proofRevision: notice.proofRevision, recordedAt: notice.recordedAt, outcome: notice.outcome,
                    disputeClosesAt: notice.disputeClosesAt, canFileReview: final == nil
                        && now < notice.disputeClosesAt.date && now < row.terms.finalityDueAt
                        && !ownCases.contains { $0.proofRevision == notice.proofRevision })
            }, reviews: ownCases, finalResult: hidden ? nil : final, simulatedReturnCents: returns[id]?[actor],
            serverNow: DuelInstant(date: now), canExit: row.status == .scheduled && final == nil && closure == nil
                && now < row.terms.finalityDueAt,
            closure: closure.flatMap { value in
                hidden && value.actor != actor ? nil : DuelClosure(kind: value.kind.rawValue,
                    recordedAt: value.at, isOwn: value.actor == actor)
            })
    }

    func seedLifecycle(_ id: UUID, scenario: String) throws {
        guard let row = rows[id] else { throw DuelClientError.accessDenied }
        now = Date()
        let first = DuelInstant(date: now.addingTimeInterval(-86400))
        let second = DuelInstant(date: now.addingTimeInterval(-3600))
        notices[id] = [DuelNotice(proofRevision: 1, recordedAt: first,
            outcome: DuelOutcome(kind: "winner", reason: "faster_chip", winnerId: row.creatorID),
            disputeClosesAt: DuelInstant(date: first.date.addingTimeInterval(168 * 3600)), canFileReview: true)]
        if ["correction", "final", "settlement", "blocked"].contains(scenario) {
            notices[id]?.append(DuelNotice(proofRevision: 2, recordedAt: second,
                outcome: DuelOutcome(kind: "winner", reason: "faster_chip", winnerId: row.inviteeID),
                disputeClosesAt: DuelInstant(date: second.date.addingTimeInterval(168 * 3600)), canFileReview: true))
        }
        if ["final", "settlement"].contains(scenario) {
            // Fictional final fixtures are moved beyond the full corrected window.
            now = now.addingTimeInterval(8 * 86400)
            results[id] = DuelFinalResult(version: "duel-fixture-official-5k-v1", challengeId: id,
                termsDigest: row.termsDigest, proofRevision: 2, finalizedAt: DuelInstant(date: now),
                outcome: notices[id]!.last!.outcome)
            if scenario == "settlement" { returns[id] = [row.creatorID: 0, row.inviteeID: 4000] }
        }
        if scenario == "blocked" { suppressed.insert(id) }
    }

    func deleteActor(_ actor: UUID) {
        activeActors.remove(actor)
        for row in rows.values where [row.creatorID, row.inviteeID].contains(actor)
            && row.closedAt == nil && now < row.startsAt {
            rows[row.id] = replacing(row, status: .cancelled, reason: "account_deleted")
        }
    }

    private func hasSlot(_ actor: UUID) -> Bool {
        rows.values.contains { row in
            row.closedAt == nil && results[row.id] == nil && (row.creatorID == actor || (row.inviteeID == actor && row.status == .scheduled))
        }
    }

    private func participant(_ challenge: UUID, _ actor: UUID, _ role: String,
                             _ accepted: Date?, _ policy: String?, _ digest: String?) -> DuelParticipant {
        DuelParticipant(challengeID: challenge, actorID: actor, role: role,
            acceptedAt: accepted, consentPolicyVersion: policy, consentTermsDigest: digest, declinedAt: nil)
    }

    private func replacing(_ row: DuelAgreement, status: DuelStatus, reason: String? = nil,
                           participants: [DuelParticipant]? = nil) -> DuelAgreement {
        DuelAgreement(id: row.id, creatorID: row.creatorID, inviteeID: row.inviteeID,
            eventID: row.eventID, policyVersion: row.policyVersion, createdAt: row.createdAt,
            startsAt: row.startsAt, acceptBy: row.acceptBy, terms: row.terms,
            termsDigest: row.termsDigest, status: status,
            closedAt: reason == nil ? nil : (row.closedAt ?? now), closeReason: reason,
            expiryDue: status == .invited && now >= row.acceptBy, participants: participants ?? row.participants)
    }
}

@MainActor
final class FixtureDuelClient: DuelClient {
    let backend: FixtureDuelBackend
    private let currentActor: @MainActor () -> UUID?
    init(backend: FixtureDuelBackend, currentActor: @escaping @MainActor () -> UUID?) {
        self.backend = backend
        self.currentActor = currentActor
    }

    func catalog(actorID: UUID) async throws -> DuelCatalog {
        try check(actorID)
        return DuelCatalog(events: [backend.event, backend.rematchEvent], policies: [
            DuelPolicy(version: backend.event.policyVersion, specification: .simulated5K)
        ])
    }

    func list(actorID: UUID, before: DuelAgreement?) async throws -> [DuelAgreement] {
        try check(actorID)
        return try backend.rows.values
            .filter { [ $0.creatorID, $0.inviteeID ].contains(actorID) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString > $1.id.uuidString : $0.createdAt > $1.createdAt }
            .filter { row in
                guard let before else { return true }
                return row.createdAt < before.createdAt
                    || (row.createdAt == before.createdAt && row.id.uuidString < before.id.uuidString)
            }
            .prefix(50).map { try backend.detail($0.id, actor: actorID) }
    }

    func detail(id: UUID, actorID: UUID) async throws -> DuelAgreement {
        try check(actorID)
        return try backend.detail(id, actor: actorID)
    }

    func lifecycle(id: UUID, actorID: UUID) async throws -> DuelLifecycle {
        try check(actorID)
        return try backend.lifecycle(id, actor: actorID)
    }

    func invitationLink(id: UUID, actorID: UUID) async throws -> DuelInvitationLink? {
        try check(actorID)
        return try backend.invitationLink(id, actor: actorID)
    }

    func resolveInvitation(token: UUID, actorID: UUID) async throws -> UUID {
        try check(actorID)
        return try backend.resolveInvitation(token, actor: actorID)
    }

    func submit(_ request: PendingDuelRequest) async throws -> UUID {
        try check(request.actorID)
        return try backend.submit(request)
    }

    private func check(_ actor: UUID) throws {
        guard currentActor() == actor else { throw DuelClientError.accountChanged }
        guard !backend.offline else { throw DuelClientError.unavailable }
        guard backend.activeActors.contains(actor) else { throw DuelClientError.accessDenied }
    }
}
#endif
