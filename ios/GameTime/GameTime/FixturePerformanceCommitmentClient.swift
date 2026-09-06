#if DEBUG || STAGING
import Foundation
import CryptoKit

/// Fictional local presentation data. This client is never a source of official results.
@MainActor
final class FixturePerformanceCommitmentClient: PerformanceCommitmentClient {
    var enabled = true
    var offline = false
    var loseNextResponse = false
    private let currentActor: @MainActor () -> UUID?
    private var agreements: [UUID: PerformanceCommitmentAgreement] = [:]
    private var lifecycles: [UUID: PerformanceCommitmentLifecycle] = [:]
    private struct RequestKey: Hashable { let actorID: UUID; let requestID: UUID }
    private var receipts: [RequestKey: (PendingPerformanceCommitmentRequest, PerformanceCommitmentMutationReceipt)] = [:]

    init(currentActor: @escaping @MainActor () -> UUID?, arguments: [String] = []) {
        self.currentActor = currentActor
        let scenario = ["correction", "final", "settlement", "closed"].first {
            arguments.contains("--fixture-commitment-" + $0)
        }
        if let scenario, let actor = currentActor() { seed(actor: actor, scenario: scenario) }
        enabled = !arguments.contains("--fixture-commitment-gate-off")
        offline = arguments.contains("--fixture-commitment-offline")
        loseNextResponse = arguments.contains("--fixture-commitment-lost-response")
    }

    func preview(_ draft: PerformanceCommitmentDraft, actorID: UUID) async throws -> PerformanceCommitmentPreview {
        try check(actorID)
        guard enabled else { throw PerformanceCommitmentClientError.accessDenied }
        let result = makePreview(draft, actor: actorID)
        try result.validate(for: actorID)
        return result
    }
    func list(actorID: UUID, before: PerformanceCommitmentAgreement?) async throws -> [PerformanceCommitmentAgreement] {
        try check(actorID)
        return agreements.values.filter { row in
            row.actorID == actorID && (before.map { row.createdAt < $0.createdAt
                || (row.createdAt == $0.createdAt && row.id.uuidString < $0.id.uuidString) } ?? true)
        }.sorted { lhs, rhs in
            lhs.createdAt == rhs.createdAt ? lhs.id.uuidString > rhs.id.uuidString : lhs.createdAt > rhs.createdAt
        }.prefix(50).map { current($0) }
    }
    func detail(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentAgreement {
        try check(actorID)
        guard let row = agreements[id], row.actorID == actorID else { throw PerformanceCommitmentClientError.accessDenied }
        return current(row)
    }
    func lifecycle(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentLifecycle {
        let agreement = try await detail(id: id, actorID: actorID)
        let now = PerformanceCommitmentInstant(date: Date())
        let saved = lifecycles[id]
        let notices = (saved?.notices ?? []).map { notice in
            PerformanceCommitmentNotice(proofRevision: notice.proofRevision, recordedAt: notice.recordedAt,
                outcome: notice.outcome, disputeClosesAt: notice.disputeClosesAt,
                canFileReview: agreement.status == .open && saved?.finalResult == nil && now < notice.disputeClosesAt
                    && now < agreement.terms.finalityDueAt && !(saved?.reviews.contains { $0.proofRevision == notice.proofRevision } ?? false))
        }
        return PerformanceCommitmentLifecycle(commitmentID: id, serverNow: now, activation: saved?.activation,
            closure: agreement.closeReason.map { PerformanceCommitmentClosure(reason: $0, recordedAt: agreement.closedAt!) },
            notices: notices, reviews: saved?.reviews ?? [], finalResult: saved?.finalResult,
            simulation: saved?.simulation, supportReceipts: saved?.supportReceipts ?? [])
    }

    func submit(_ request: PendingPerformanceCommitmentRequest) async throws -> PerformanceCommitmentMutationReceipt {
        try check(request.actorID)
        try request.validate(for: request.actorID)
        let key = RequestKey(actorID: request.actorID, requestID: request.requestID)
        if let (saved, receipt) = receipts[key] {
            guard saved.actorID == request.actorID, saved.requestBody == request.requestBody else {
                throw PerformanceCommitmentClientError.invalidTerms
            }
            return receipt
        }
        let receipt: PerformanceCommitmentMutationReceipt
        switch request.operation {
        case .create(let draft, let digest, let consent):
            guard enabled else { throw PerformanceCommitmentClientError.accessDenied }
            guard consent, !agreements.values.contains(where: {
                $0.actorID == request.actorID && $0.status == .open && lifecycles[$0.id]?.finalResult == nil
            }) else { throw PerformanceCommitmentClientError.slotOccupied }
            let preview = makePreview(draft, actor: request.actorID)
            try preview.validate(for: request.actorID)
            guard preview.termsDigest == digest else { throw PerformanceCommitmentClientError.invalidTerms }
            let row = makeAgreement(preview: preview, createdAt: preview.serverNow)
            agreements[row.id] = row
            receipt = .commitment(row.id)
        case .close(let id, let reason):
            let row = try await detail(id: id, actorID: request.actorID)
            let now = PerformanceCommitmentInstant(date: Date())
            guard row.status == .open, lifecycles[id]?.finalResult == nil, reason != .accountDeleted,
                  reason != .cancel || now < row.startsAt,
                  reason != .withdrawal || now >= row.startsAt else { throw PerformanceCommitmentClientError.lifecycle }
            agreements[id] = current(row, closedAt: now, reason: reason)
            receipt = .commitment(id)
        case .fileReview(let id, let revision, let reason):
            let life = try await lifecycle(id: id, actorID: request.actorID)
            guard life.notices.contains(where: { $0.proofRevision == revision && $0.canFileReview }) else {
                throw PerformanceCommitmentClientError.lifecycle
            }
            let review = PerformanceCommitmentReviewCase(caseID: UUID(), proofRevision: revision, reason: reason,
                filedAt: life.serverNow, reviewDueAt: shifted(life.serverNow, days: 7), resolution: nil)
            lifecycles[id] = PerformanceCommitmentLifecycle(commitmentID: id, serverNow: life.serverNow,
                activation: life.activation, closure: life.closure, notices: life.notices,
                reviews: life.reviews + [review], finalResult: life.finalResult, simulation: life.simulation, supportReceipts: life.supportReceipts)
            receipt = .review(PerformanceCommitmentReviewReceipt(caseID: review.caseID, recordedAt: review.filedAt))
        }
        receipts[key] = (request, receipt)
        if loseNextResponse {
            loseNextResponse = false
            throw PerformanceCommitmentClientError.unavailable
        }
        return receipt
    }

    private func check(_ actor: UUID) throws {
        guard currentActor() == actor else { throw PerformanceCommitmentClientError.accountChanged }
        guard !offline else { throw PerformanceCommitmentClientError.unavailable }
    }
    private func shifted(_ instant: PerformanceCommitmentInstant, days: Double) -> PerformanceCommitmentInstant {
        PerformanceCommitmentInstant(date: instant.date.addingTimeInterval(days * 86400))
    }
    private func makePreview(_ draft: PerformanceCommitmentDraft, actor: UUID) -> PerformanceCommitmentPreview {
        let terms = PerformanceCommitmentTerms(agreementVersion: 1, actorID: actor, policyVersion: draft.policyVersion,
            policy: .simulated5K, targetMS: draft.targetSeconds * 1000, startsAt: draft.startsAt,
            deadlineAt: draft.deadlineAt, displayTimezone: draft.displayTimezone,
            resultsDueAt: shifted(draft.deadlineAt, days: 3), finalityDueAt: shifted(draft.deadlineAt, days: 30))
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let digest = SHA256.hash(data: try! encoder.encode(terms)).map { String(format: "%02x", $0) }.joined()
        return PerformanceCommitmentPreview(terms: terms, termsDigest: digest, serverNow: PerformanceCommitmentInstant(date: Date()))
    }
    private func makeAgreement(preview: PerformanceCommitmentPreview, createdAt: PerformanceCommitmentInstant) -> PerformanceCommitmentAgreement {
        let id = UUID()
        let t = preview.terms
        let row = PerformanceCommitmentAgreement(id: id, actorID: t.actorID, policyVersion: t.policyVersion,
            createdAt: createdAt, startsAt: t.startsAt, deadlineAt: t.deadlineAt, displayTimezone: t.displayTimezone,
            targetSeconds: t.targetMS / 1000, terms: t, termsDigest: preview.termsDigest, status: .open,
            closedAt: nil, closeReason: nil,
            consent: PerformanceCommitmentConsent(commitmentID: id, actorID: t.actorID, acceptedAt: createdAt,
                policyVersion: t.policyVersion, termsDigest: preview.termsDigest), serverNow: createdAt, phase: .scheduled)
        return current(row)
    }
    private func current(_ row: PerformanceCommitmentAgreement, closedAt: PerformanceCommitmentInstant? = nil,
                         reason: PerformanceCommitmentCloseReason? = nil) -> PerformanceCommitmentAgreement {
        let now = PerformanceCommitmentInstant(date: Date())
        let closed = closedAt ?? row.closedAt
        let status: PerformanceCommitmentStatus = closed.map { $0 < row.startsAt ? .cancelled : .withdrawn } ?? .open
        let phase: PerformanceCommitmentPhase = closed == nil
            ? (now < row.startsAt ? .scheduled : (now < row.deadlineAt ? .active : .awaitingProof))
            : (status == .cancelled ? .cancelled : .withdrawn)
        return PerformanceCommitmentAgreement(id: row.id, actorID: row.actorID, policyVersion: row.policyVersion,
            createdAt: row.createdAt, startsAt: row.startsAt, deadlineAt: row.deadlineAt, displayTimezone: row.displayTimezone,
            targetSeconds: row.targetSeconds, terms: row.terms, termsDigest: row.termsDigest, status: status,
            closedAt: closed, closeReason: reason ?? row.closeReason, consent: row.consent, serverNow: now, phase: phase)
    }
    private func seed(actor: UUID, scenario: String) {
        let now = PerformanceCommitmentInstant(date: Date())
        let draft = PerformanceCommitmentDraft(targetSeconds: 1500, startsAt: shifted(now, days: -44),
            deadlineAt: shifted(now, days: -16), displayTimezone: "America/Chicago")
        let row = makeAgreement(preview: makePreview(draft, actor: actor), createdAt: shifted(now, days: -45))
        agreements[row.id] = row
        if scenario == "closed" {
            agreements[row.id] = current(row, closedAt: shifted(now, days: -20), reason: .injury)
            return
        }
        let finalScenario = scenario == "final" || scenario == "settlement"
        let noticeTime = shifted(now, days: finalScenario ? -10 : -2)
        let first = PerformanceCommitmentNotice(proofRevision: 1, recordedAt: noticeTime,
            outcome: PerformanceCommitmentOutcome(kind: "inconclusive", reason: "unresolved_proof"),
            disputeClosesAt: shifted(noticeTime, days: 7), canFileReview: !finalScenario)
        let corrected = PerformanceCommitmentNotice(proofRevision: 2, recordedAt: shifted(noticeTime, days: 1),
            outcome: PerformanceCommitmentOutcome(kind: "success", reason: "strict_target_met", attemptID: UUID()),
            disputeClosesAt: shifted(noticeTime, days: 8), canFileReview: !finalScenario)
        let final = finalScenario ? PerformanceCommitmentFinalResult(version: "performance-fixture-official-5k-v1",
            commitmentID: row.id, termsDigest: row.termsDigest, proofRevision: 2, finalizedAt: shifted(now, days: -1),
            outcome: corrected.outcome) : nil
        let simulation = scenario == "settlement" ? PerformanceCommitmentSimulation(commitmentID: row.id,
            returnedCents: 2000, lostCents: 0, feeCents: 0, mode: "simulated", redeemable: false,
            forfeitureRecipient: "unselected", payee: nil, recordedAt: shifted(now, days: -0.5)) : nil
        lifecycles[row.id] = PerformanceCommitmentLifecycle(commitmentID: row.id, serverNow: now,
            activation: row.startsAt, closure: nil, notices: [first, corrected], reviews: [],
            finalResult: final, simulation: simulation, supportReceipts: [])
    }
}
#endif
