import Foundation

enum PerformanceCommitmentReviewReason: String, Codable, CaseIterable, Sendable {
    case wrongResult = "wrong_result", wrongIdentity = "wrong_identity", missingResult = "missing_result"
    var title: String {
        switch self {
        case .wrongResult: "My result is wrong"
        case .wrongIdentity: "This result belongs to someone else"
        case .missingResult: "My result is missing"
        }
    }
}

struct PerformanceCommitmentOutcome: Codable, Equatable, Sendable {
    let kind: String
    let reason: String
    let attemptID: UUID?

    enum CodingKeys: String, CodingKey { case kind, reason, attemptID = "attemptId" }
    init(kind: String, reason: String, attemptID: UUID? = nil) {
        self.kind = kind
        self.reason = reason
        self.attemptID = attemptID
    }
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        kind = try values.decode(String.self, forKey: .kind)
        reason = try values.decode(String.self, forKey: .reason)
        try PerformanceCommitmentCodec.requireKeys(decoder, kind == "success" ? ["kind", "reason", "attemptId"] : ["kind", "reason"])
        attemptID = try values.decodeIfPresent(UUID.self, forKey: .attemptID)
        try validate()
    }

    func validate() throws {
        let reasons: [String: Set<String>] = [
            "success": ["strict_target_met"],
            "miss": ["confirmed_attempt_set", "explicit_no_attempts"],
            "inconclusive": ["unresolved_proof", "review_timeout", "review_inconclusive", "finality_timeout"],
            "closed": ["cancel", "withdrawal", "injury", "account_deleted"]
        ]
        guard reasons[kind]?.contains(reason) == true, (kind == "success") == (attemptID != nil)
        else { throw PerformanceCommitmentModelError.invalidResponse }
    }

    var title: String {
        switch kind {
        case "success": "Goal met"
        case "miss": "Goal missed"
        case "closed": "Goal closed"
        default: "This goal didn’t count"
        }
    }
    var explanation: String {
        switch reason {
        case "strict_target_met": "An official 5K time is strictly under your target. A slower later attempt doesn’t undo it."
        case "confirmed_attempt_set": "You confirmed your complete set of attempts, and none met your target."
        case "explicit_no_attempts": "You confirmed that you made no attempts during the agreed time."
        case "unresolved_proof": "We couldn’t confirm this result. Missing results alone don’t mean you missed your goal."
        case "review_timeout": "We couldn’t finish the review in time. You don’t lose your simulated amount."
        case "review_inconclusive": "Review found that this goal should not count. You don’t lose your simulated amount."
        case "finality_timeout": "We couldn’t finish confirming your result in time. You don’t lose your simulated amount."
        case "cancel": "You cancelled before the start. You don’t lose your simulated amount."
        case "withdrawal": "You withdrew from this goal. You don’t lose your simulated amount."
        case "injury": "You reported an injury. You don’t lose your simulated amount."
        case "account_deleted": "Your account was deleted. You don’t lose your simulated amount."
        default: "We couldn’t read this result. Refresh your goal to try again."
        }
    }
}

struct PerformanceCommitmentNotice: Codable, Equatable, Identifiable, Sendable {
    var id: Int { proofRevision }
    let proofRevision: Int
    let recordedAt: PerformanceCommitmentInstant
    let outcome: PerformanceCommitmentOutcome
    let disputeClosesAt: PerformanceCommitmentInstant
    let canFileReview: Bool
    enum CodingKeys: String, CodingKey {
        case proofRevision = "proof_revision", recordedAt = "recorded_at", outcome
        case disputeClosesAt = "dispute_closes_at", canFileReview = "can_file_review"
    }
}

enum PerformanceCommitmentReviewDecision: String, Codable, Sendable { case uphold, inconclusive }
struct PerformanceCommitmentReviewResolution: Codable, Equatable, Sendable {
    let decision: PerformanceCommitmentReviewDecision
    let recordedAt: PerformanceCommitmentInstant
    enum CodingKeys: String, CodingKey { case decision, recordedAt = "recorded_at" }
}
struct PerformanceCommitmentReviewCase: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { caseID }
    let caseID: UUID
    let proofRevision: Int
    let reason: PerformanceCommitmentReviewReason
    let filedAt: PerformanceCommitmentInstant
    let reviewDueAt: PerformanceCommitmentInstant
    let resolution: PerformanceCommitmentReviewResolution?
    enum CodingKeys: String, CodingKey {
        case caseID = "case_id", proofRevision = "proof_revision", reason, filedAt = "filed_at"
        case reviewDueAt = "review_due_at", resolution
    }
    var statusText: String {
        switch resolution?.decision {
        case .uphold: "Review complete — result upheld"
        case .inconclusive: "Review complete — goal won’t count"
        case nil: "Your review request is saved"
        }
    }
}
struct PerformanceCommitmentReviewReceipt: Codable, Equatable, Sendable {
    let caseID: UUID
    let recordedAt: PerformanceCommitmentInstant
    enum CodingKeys: String, CodingKey { case caseID = "case_id", recordedAt = "recorded_at" }
}
struct PerformanceCommitmentFinalResult: Codable, Equatable, Sendable {
    let version: String
    let commitmentID: UUID
    let termsDigest: String
    let proofRevision: Int
    let finalizedAt: PerformanceCommitmentInstant
    let outcome: PerformanceCommitmentOutcome
    enum CodingKeys: String, CodingKey {
        case version, commitmentID = "commitmentId", termsDigest, proofRevision, finalizedAt, outcome
    }
}
struct PerformanceCommitmentClosure: Codable, Equatable, Sendable {
    let reason: PerformanceCommitmentCloseReason
    let recordedAt: PerformanceCommitmentInstant
    enum CodingKeys: String, CodingKey { case reason, recordedAt = "recorded_at" }
}

/// Present only an appended record. A final result does not imply simulation exists.
struct PerformanceCommitmentSimulation: Codable, Equatable, Sendable {
    let commitmentID: UUID
    let returnedCents: Int
    let lostCents: Int
    let feeCents: Int
    let mode: String
    let redeemable: Bool
    let forfeitureRecipient: String
    let payee: UUID?
    let recordedAt: PerformanceCommitmentInstant
    enum CodingKeys: String, CodingKey {
        case commitmentID = "commitment_id", returnedCents = "returned_cents", lostCents = "lost_cents"
        case feeCents = "fee_cents", mode, redeemable, forfeitureRecipient = "forfeiture_recipient", payee
        case recordedAt = "recorded_at"
    }
}

enum PerformanceCommitmentSupportCategory: String, Codable, Sendable {
    case resultCorrection = "result_correction", identityCorrection = "identity_correction", missingResult = "missing_result"
}
struct PerformanceCommitmentSupportReceipt: Codable, Equatable, Identifiable, Sendable {
    var id: UUID { supportID }
    let supportID: UUID
    let category: PerformanceCommitmentSupportCategory
    let recordedAt: PerformanceCommitmentInstant
    enum CodingKeys: String, CodingKey { case supportID = "support_id", category, recordedAt = "recorded_at" }
}

struct PerformanceCommitmentLifecycle: Codable, Equatable, Sendable {
    let commitmentID: UUID
    let serverNow: PerformanceCommitmentInstant
    let activation: PerformanceCommitmentInstant?
    let closure: PerformanceCommitmentClosure?
    let notices: [PerformanceCommitmentNotice]
    let reviews: [PerformanceCommitmentReviewCase]
    let finalResult: PerformanceCommitmentFinalResult?
    let simulation: PerformanceCommitmentSimulation?
    let supportReceipts: [PerformanceCommitmentSupportReceipt]
    enum CodingKeys: String, CodingKey {
        case commitmentID = "commitment_id", serverNow = "server_now", activation, closure, notices, reviews
        case finalResult = "final_result", simulation, supportReceipts = "support_receipts"
    }

    func validate(agreement: PerformanceCommitmentAgreement, actorID: UUID) throws {
        try agreement.validate(for: actorID)
        let reviewWindow: Int64 = 168 * 3_600_000_000
        guard commitmentID == agreement.id, serverNow >= agreement.createdAt,
              Set(notices.map(\.proofRevision)).count == notices.count,
              Set(reviews.map(\.caseID)).count == reviews.count,
              Set(reviews.map(\.proofRevision)).count == reviews.count,
              Set(supportReceipts.map(\.supportID)).count == supportReceipts.count,
              closure?.reason == agreement.closeReason, closure?.recordedAt == agreement.closedAt
        else { throw PerformanceCommitmentModelError.invalidResponse }
        if let activation {
            guard activation >= agreement.startsAt, activation <= serverNow else { throw PerformanceCommitmentModelError.invalidResponse }
        }
        if let closure {
            guard closure.recordedAt <= serverNow else { throw PerformanceCommitmentModelError.invalidResponse }
        }
        for notice in notices {
            try notice.outcome.validate()
            let canFile = agreement.status == .open && finalResult == nil
                && serverNow >= notice.recordedAt && serverNow < notice.disputeClosesAt
                && serverNow < agreement.terms.finalityDueAt && !reviews.contains { $0.proofRevision == notice.proofRevision }
            guard notice.proofRevision >= 0, notice.recordedAt >= agreement.terms.resultsDueAt,
                  notice.recordedAt < agreement.terms.finalityDueAt, notice.recordedAt <= serverNow,
                  notice.disputeClosesAt.microseconds - notice.recordedAt.microseconds == reviewWindow,
                  notice.canFileReview == canFile, notice.outcome.kind != "closed"
            else { throw PerformanceCommitmentModelError.invalidResponse }
            if notice.outcome.kind == "success" || notice.outcome.reason == "confirmed_attempt_set" {
                guard notice.proofRevision > 0 else { throw PerformanceCommitmentModelError.invalidResponse }
            }
        }
        for review in reviews {
            guard let notice = notices.first(where: { $0.proofRevision == review.proofRevision }),
                  review.filedAt >= notice.recordedAt, review.filedAt < notice.disputeClosesAt,
                  review.filedAt < agreement.terms.finalityDueAt, review.filedAt <= serverNow,
                  review.reviewDueAt.microseconds - review.filedAt.microseconds == reviewWindow
            else { throw PerformanceCommitmentModelError.invalidResponse }
            if let resolution = review.resolution {
                guard resolution.recordedAt >= review.filedAt, resolution.recordedAt < review.reviewDueAt,
                      resolution.recordedAt < agreement.terms.finalityDueAt, resolution.recordedAt <= serverNow
                else { throw PerformanceCommitmentModelError.invalidResponse }
            }
        }
        if let final = finalResult {
            try final.outcome.validate()
            guard final.version == "performance-fixture-official-5k-v1", final.commitmentID == commitmentID,
                  final.termsDigest == agreement.termsDigest, final.proofRevision >= 0,
                  final.finalizedAt >= agreement.createdAt, final.finalizedAt <= serverNow,
                  notices.allSatisfy({ $0.recordedAt <= final.finalizedAt && $0.proofRevision <= final.proofRevision }),
                  reviews.allSatisfy({ $0.filedAt <= final.finalizedAt && ($0.resolution?.recordedAt ?? $0.filedAt) <= final.finalizedAt })
            else { throw PerformanceCommitmentModelError.invalidResponse }
            if final.outcome.kind == "closed" {
                guard let closure, final.outcome.reason == closure.reason.rawValue, final.finalizedAt >= closure.recordedAt
                else { throw PerformanceCommitmentModelError.invalidResponse }
            } else {
                guard agreement.status == .open, final.finalizedAt >= agreement.terms.resultsDueAt
                else { throw PerformanceCommitmentModelError.invalidResponse }
            }
            if final.outcome.kind == "success" || final.outcome.kind == "miss" {
                guard let notice = notices.first(where: { $0.proofRevision == final.proofRevision }),
                      final.finalizedAt >= notice.disputeClosesAt,
                      reviews.allSatisfy({ $0.resolution?.decision == .uphold }),
                      final.outcome.reason == "explicit_no_attempts" || final.proofRevision > 0
                else { throw PerformanceCommitmentModelError.invalidResponse }
            }
            if let simulation {
                let lost = final.outcome.kind == "miss" ? 2000 : 0
                guard simulation.commitmentID == commitmentID, simulation.returnedCents == 2000 - lost,
                      simulation.lostCents == lost, simulation.feeCents == 0,
                      simulation.mode == "simulated", !simulation.redeemable,
                      simulation.forfeitureRecipient == "unselected", simulation.payee == nil,
                      simulation.recordedAt >= final.finalizedAt, simulation.recordedAt <= serverNow
                else { throw PerformanceCommitmentModelError.invalidResponse }
            }
            guard supportReceipts.allSatisfy({ $0.recordedAt >= final.finalizedAt && $0.recordedAt <= serverNow })
            else { throw PerformanceCommitmentModelError.invalidResponse }
        } else if simulation != nil || !supportReceipts.isEmpty {
            throw PerformanceCommitmentModelError.invalidResponse
        }
    }

    var latestNotice: PerformanceCommitmentNotice? { notices.max { $0.proofRevision < $1.proofRevision } }
    var progressText: String {
        if finalResult != nil { return "Result confirmed" }
        if closure != nil { return "Goal exit saved — result update pending" }
        if let latestNotice {
            return reviews.contains { $0.proofRevision == latestNotice.proofRevision && $0.resolution == nil }
                ? "Review requested — result not final" : "Result update — review before confirmation"
        }
        return "No result update is saved yet"
    }
}


extension PerformanceCommitmentLifecycle {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        commitmentID = try values.decode(UUID.self, forKey: .commitmentID)
        serverNow = try values.decode(PerformanceCommitmentInstant.self, forKey: .serverNow)
        activation = try values.decode(PerformanceCommitmentInstant?.self, forKey: .activation)
        closure = try values.decode(PerformanceCommitmentClosure?.self, forKey: .closure)
        notices = try values.decode([PerformanceCommitmentNotice].self, forKey: .notices)
        reviews = try values.decode([PerformanceCommitmentReviewCase].self, forKey: .reviews)
        finalResult = try values.decode(PerformanceCommitmentFinalResult?.self, forKey: .finalResult)
        simulation = try values.decode(PerformanceCommitmentSimulation?.self, forKey: .simulation)
        supportReceipts = try values.decode([PerformanceCommitmentSupportReceipt].self, forKey: .supportReceipts)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(commitmentID, forKey: .commitmentID)
        try values.encode(serverNow, forKey: .serverNow)
        try values.encode(activation, forKey: .activation)
        try values.encode(closure, forKey: .closure)
        try values.encode(notices, forKey: .notices)
        try values.encode(reviews, forKey: .reviews)
        try values.encode(finalResult, forKey: .finalResult)
        try values.encode(simulation, forKey: .simulation)
        try values.encode(supportReceipts, forKey: .supportReceipts)
    }
}


extension PerformanceCommitmentReviewCase {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        caseID = try values.decode(UUID.self, forKey: .caseID)
        proofRevision = try values.decode(Int.self, forKey: .proofRevision)
        reason = try values.decode(PerformanceCommitmentReviewReason.self, forKey: .reason)
        filedAt = try values.decode(PerformanceCommitmentInstant.self, forKey: .filedAt)
        reviewDueAt = try values.decode(PerformanceCommitmentInstant.self, forKey: .reviewDueAt)
        resolution = try values.decode(PerformanceCommitmentReviewResolution?.self, forKey: .resolution)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(caseID, forKey: .caseID)
        try values.encode(proofRevision, forKey: .proofRevision)
        try values.encode(reason, forKey: .reason)
        try values.encode(filedAt, forKey: .filedAt)
        try values.encode(reviewDueAt, forKey: .reviewDueAt)
        try values.encode(resolution, forKey: .resolution)
    }
}


extension PerformanceCommitmentSimulation {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        commitmentID = try values.decode(UUID.self, forKey: .commitmentID)
        returnedCents = try values.decode(Int.self, forKey: .returnedCents)
        lostCents = try values.decode(Int.self, forKey: .lostCents)
        feeCents = try values.decode(Int.self, forKey: .feeCents)
        mode = try values.decode(String.self, forKey: .mode)
        redeemable = try values.decode(Bool.self, forKey: .redeemable)
        forfeitureRecipient = try values.decode(String.self, forKey: .forfeitureRecipient)
        payee = try values.decode(UUID?.self, forKey: .payee)
        recordedAt = try values.decode(PerformanceCommitmentInstant.self, forKey: .recordedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(commitmentID, forKey: .commitmentID)
        try values.encode(returnedCents, forKey: .returnedCents)
        try values.encode(lostCents, forKey: .lostCents)
        try values.encode(feeCents, forKey: .feeCents)
        try values.encode(mode, forKey: .mode)
        try values.encode(redeemable, forKey: .redeemable)
        try values.encode(forfeitureRecipient, forKey: .forfeitureRecipient)
        try values.encode(payee, forKey: .payee)
        try values.encode(recordedAt, forKey: .recordedAt)
    }
}
