import Foundation

/// Timestamp implementation shared with duels; every incoming PostgreSQL microsecond survives.
typealias PerformanceCommitmentInstant = DuelInstant

enum PerformanceCommitmentModelError: Error { case invalidResponse }

enum PerformanceCommitmentCodec {
    static func decoder() -> JSONDecoder { JSONDecoder() }
    static func isDigest(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) }
    }
    static func requireKeys(_ decoder: any Decoder, _ expected: [String]) throws {
        let values = try decoder.container(keyedBy: WireKey.self)
        guard Set(values.allKeys.map(\.stringValue)) == Set(expected) else {
            throw PerformanceCommitmentModelError.invalidResponse
        }
    }
    private struct WireKey: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
}

struct PerformanceCommitmentPolicySpecification: Codable, Equatable, Sendable {
    static let policyVersion = "performance-commitment-fixture-5k-v1"
    let source: String
    let sport: String
    let distanceMeters: Int
    let timingBasis: String
    let precisionMS: Int
    let comparator: String
    let targetMinSeconds: Int
    let targetMaxSeconds: Int
    let durationBasis: String
    let minimumDurationHours: Int
    let maximumDurationHours: Int
    let startWithinHours: Int
    let attemptWindow: String
    let attempts: String
    let success: String
    let slowerLaterAttempt: String
    let milestones: String
    let resultsAfterDeadlineHours: Int
    let disputeAfterDurableNoticeHours: Int
    let reviewAfterFilingHours: Int
    let finalityAfterDeadlineHours: Int
    let miss: String
    let missingOrAmbiguousProof: String
    let reviewTimeout: String
    let corrections: String
    let prestartCancellation: String
    let withdrawalOrInjury: String
    let accountDeletion: String
    let mode: String
    let currency: String
    let commitmentCents: Int
    let feeCents: Int
    let forfeitureRecipient: String
    let payee: String?
    let confirmedMissDisposition: String
    let redeemable: Bool
    let consentVersion: String

    enum CodingKeys: String, CodingKey, CaseIterable {
        case source = "source"
        case sport = "sport"
        case distanceMeters = "distance_meters"
        case timingBasis = "timing_basis"
        case precisionMS = "precision_ms"
        case comparator = "comparator"
        case targetMinSeconds = "target_min_seconds"
        case targetMaxSeconds = "target_max_seconds"
        case durationBasis = "duration_basis"
        case minimumDurationHours = "minimum_duration_hours"
        case maximumDurationHours = "maximum_duration_hours"
        case startWithinHours = "start_within_hours"
        case attemptWindow = "attempt_window"
        case attempts = "attempts"
        case success = "success"
        case slowerLaterAttempt = "slower_later_attempt"
        case milestones = "milestones"
        case resultsAfterDeadlineHours = "results_after_deadline_hours"
        case disputeAfterDurableNoticeHours = "dispute_after_durable_notice_hours"
        case reviewAfterFilingHours = "review_after_filing_hours"
        case finalityAfterDeadlineHours = "finality_after_deadline_hours"
        case miss = "miss"
        case missingOrAmbiguousProof = "missing_or_ambiguous_proof"
        case reviewTimeout = "review_timeout"
        case corrections = "corrections"
        case prestartCancellation = "prestart_cancellation"
        case withdrawalOrInjury = "withdrawal_or_injury"
        case accountDeletion = "account_deletion"
        case mode = "mode"
        case currency = "currency"
        case commitmentCents = "commitment_cents"
        case feeCents = "fee_cents"
        case forfeitureRecipient = "forfeiture_recipient"
        case payee = "payee"
        case confirmedMissDisposition = "confirmed_miss_disposition"
        case redeemable = "redeemable"
        case consentVersion = "consent_version"
    }

    init(from decoder: any Decoder) throws {
        try PerformanceCommitmentCodec.requireKeys(decoder, CodingKeys.allCases.map(\.rawValue))
        let values = try decoder.container(keyedBy: CodingKeys.self)
        source = try values.decode(String.self, forKey: .source)
        sport = try values.decode(String.self, forKey: .sport)
        distanceMeters = try values.decode(Int.self, forKey: .distanceMeters)
        timingBasis = try values.decode(String.self, forKey: .timingBasis)
        precisionMS = try values.decode(Int.self, forKey: .precisionMS)
        comparator = try values.decode(String.self, forKey: .comparator)
        targetMinSeconds = try values.decode(Int.self, forKey: .targetMinSeconds)
        targetMaxSeconds = try values.decode(Int.self, forKey: .targetMaxSeconds)
        durationBasis = try values.decode(String.self, forKey: .durationBasis)
        minimumDurationHours = try values.decode(Int.self, forKey: .minimumDurationHours)
        maximumDurationHours = try values.decode(Int.self, forKey: .maximumDurationHours)
        startWithinHours = try values.decode(Int.self, forKey: .startWithinHours)
        attemptWindow = try values.decode(String.self, forKey: .attemptWindow)
        attempts = try values.decode(String.self, forKey: .attempts)
        success = try values.decode(String.self, forKey: .success)
        slowerLaterAttempt = try values.decode(String.self, forKey: .slowerLaterAttempt)
        milestones = try values.decode(String.self, forKey: .milestones)
        resultsAfterDeadlineHours = try values.decode(Int.self, forKey: .resultsAfterDeadlineHours)
        disputeAfterDurableNoticeHours = try values.decode(Int.self, forKey: .disputeAfterDurableNoticeHours)
        reviewAfterFilingHours = try values.decode(Int.self, forKey: .reviewAfterFilingHours)
        finalityAfterDeadlineHours = try values.decode(Int.self, forKey: .finalityAfterDeadlineHours)
        miss = try values.decode(String.self, forKey: .miss)
        missingOrAmbiguousProof = try values.decode(String.self, forKey: .missingOrAmbiguousProof)
        reviewTimeout = try values.decode(String.self, forKey: .reviewTimeout)
        corrections = try values.decode(String.self, forKey: .corrections)
        prestartCancellation = try values.decode(String.self, forKey: .prestartCancellation)
        withdrawalOrInjury = try values.decode(String.self, forKey: .withdrawalOrInjury)
        accountDeletion = try values.decode(String.self, forKey: .accountDeletion)
        mode = try values.decode(String.self, forKey: .mode)
        currency = try values.decode(String.self, forKey: .currency)
        commitmentCents = try values.decode(Int.self, forKey: .commitmentCents)
        feeCents = try values.decode(Int.self, forKey: .feeCents)
        forfeitureRecipient = try values.decode(String.self, forKey: .forfeitureRecipient)
        guard try values.decodeNil(forKey: .payee) else { throw PerformanceCommitmentModelError.invalidResponse }
        payee = nil
        confirmedMissDisposition = try values.decode(String.self, forKey: .confirmedMissDisposition)
        redeemable = try values.decode(Bool.self, forKey: .redeemable)
        consentVersion = try values.decode(String.self, forKey: .consentVersion)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(source, forKey: .source)
        try values.encode(sport, forKey: .sport)
        try values.encode(distanceMeters, forKey: .distanceMeters)
        try values.encode(timingBasis, forKey: .timingBasis)
        try values.encode(precisionMS, forKey: .precisionMS)
        try values.encode(comparator, forKey: .comparator)
        try values.encode(targetMinSeconds, forKey: .targetMinSeconds)
        try values.encode(targetMaxSeconds, forKey: .targetMaxSeconds)
        try values.encode(durationBasis, forKey: .durationBasis)
        try values.encode(minimumDurationHours, forKey: .minimumDurationHours)
        try values.encode(maximumDurationHours, forKey: .maximumDurationHours)
        try values.encode(startWithinHours, forKey: .startWithinHours)
        try values.encode(attemptWindow, forKey: .attemptWindow)
        try values.encode(attempts, forKey: .attempts)
        try values.encode(success, forKey: .success)
        try values.encode(slowerLaterAttempt, forKey: .slowerLaterAttempt)
        try values.encode(milestones, forKey: .milestones)
        try values.encode(resultsAfterDeadlineHours, forKey: .resultsAfterDeadlineHours)
        try values.encode(disputeAfterDurableNoticeHours, forKey: .disputeAfterDurableNoticeHours)
        try values.encode(reviewAfterFilingHours, forKey: .reviewAfterFilingHours)
        try values.encode(finalityAfterDeadlineHours, forKey: .finalityAfterDeadlineHours)
        try values.encode(miss, forKey: .miss)
        try values.encode(missingOrAmbiguousProof, forKey: .missingOrAmbiguousProof)
        try values.encode(reviewTimeout, forKey: .reviewTimeout)
        try values.encode(corrections, forKey: .corrections)
        try values.encode(prestartCancellation, forKey: .prestartCancellation)
        try values.encode(withdrawalOrInjury, forKey: .withdrawalOrInjury)
        try values.encode(accountDeletion, forKey: .accountDeletion)
        try values.encode(mode, forKey: .mode)
        try values.encode(currency, forKey: .currency)
        try values.encode(commitmentCents, forKey: .commitmentCents)
        try values.encode(feeCents, forKey: .feeCents)
        try values.encode(forfeitureRecipient, forKey: .forfeitureRecipient)
        try values.encodeNil(forKey: .payee)
        try values.encode(confirmedMissDisposition, forKey: .confirmedMissDisposition)
        try values.encode(redeemable, forKey: .redeemable)
        try values.encode(consentVersion, forKey: .consentVersion)
    }

    private init() {
        source = "fixture_official_5k_v1"
        sport = "outdoor_running"
        distanceMeters = 5000
        timingBasis = "organizer_chip"
        precisionMS = 1000
        comparator = "lt"
        targetMinSeconds = 1
        targetMaxSeconds = 86400
        durationBasis = "elapsed_utc"
        minimumDurationHours = 672
        maximumDurationHours = 2160
        startWithinHours = 720
        attemptWindow = "start_inclusive_finish_exclusive"
        attempts = "multiple_nominated_events"
        success = "any_qualifying_attempt"
        slowerLaterAttempt = "does_not_undo_success"
        milestones = "not_qualifying_proof"
        resultsAfterDeadlineHours = 72
        disputeAfterDurableNoticeHours = 168
        reviewAfterFilingHours = 168
        finalityAfterDeadlineHours = 720
        miss = "complete_confirmed_attempt_set_or_explicit_no_attempt_acknowledgement_after_review"
        missingOrAmbiguousProof = "review_then_inconclusive_zero_consequence"
        reviewTimeout = "inconclusive_zero_consequence"
        corrections = "append_only_no_automatic_new_consequence"
        prestartCancellation = "zero_consequence"
        withdrawalOrInjury = "zero_consequence"
        accountDeletion = "close_unfinalized_zero_consequence_retain_agreement"
        mode = "simulated"
        currency = "USD"
        commitmentCents = 2000
        feeCents = 0
        forfeitureRecipient = "unselected"
        payee = nil
        confirmedMissDisposition = "simulated_loss_no_payee_no_transfer"
        redeemable = false
        consentVersion = "performance-commitment-simulated-consent-v1"
    }

    static let simulated5K = Self()
}

struct PerformanceCommitmentTerms: Codable, Equatable, Sendable {
    let agreementVersion: Int
    let actorID: UUID
    let policyVersion: String
    let policy: PerformanceCommitmentPolicySpecification
    let targetMS: Int
    let startsAt: PerformanceCommitmentInstant
    let deadlineAt: PerformanceCommitmentInstant
    let displayTimezone: String
    let resultsDueAt: PerformanceCommitmentInstant
    let finalityDueAt: PerformanceCommitmentInstant

    enum CodingKeys: String, CodingKey {
        case agreementVersion = "agreement_version", actorID = "actor_id", policyVersion = "policy_version"
        case policy, targetMS = "target_ms", startsAt = "starts_at", deadlineAt = "deadline_at"
        case displayTimezone = "display_timezone", resultsDueAt = "results_due_at", finalityDueAt = "finality_due_at"
    }

    var targetText: String { "Run 5K in under \(targetTimeText)" }
    var targetTimeText: String {
        let seconds = targetMS / 1000
        return seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
            : String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    func validate(for actorID: UUID) throws {
        let hour: Int64 = 3_600_000_000
        let duration = deadlineAt.microseconds - startsAt.microseconds
        guard self.actorID == actorID, agreementVersion == 1,
              policyVersion == PerformanceCommitmentPolicySpecification.policyVersion,
              policy == .simulated5K, (1000...86_400_000).contains(targetMS), targetMS.isMultiple(of: 1000),
              (672 * hour...2160 * hour).contains(duration), TimeZone(identifier: displayTimezone) != nil,
              resultsDueAt.microseconds - deadlineAt.microseconds == 72 * hour,
              finalityDueAt.microseconds - deadlineAt.microseconds == 720 * hour
        else { throw PerformanceCommitmentModelError.invalidResponse }
    }
}

struct PerformanceCommitmentPreview: Codable, Equatable, Sendable {
    let terms: PerformanceCommitmentTerms
    let termsDigest: String
    let serverNow: PerformanceCommitmentInstant

    enum CodingKeys: String, CodingKey {
        case terms, termsDigest = "terms_digest", serverNow = "server_now"
    }

    func validate(for actorID: UUID) throws {
        try terms.validate(for: actorID)
        guard PerformanceCommitmentCodec.isDigest(termsDigest), serverNow < terms.startsAt,
              terms.startsAt.microseconds - serverNow.microseconds <= 720 * 3_600_000_000
        else { throw PerformanceCommitmentModelError.invalidResponse }
    }
}

enum PerformanceCommitmentStatus: String, Codable, Sendable { case open, cancelled, withdrawn }
enum PerformanceCommitmentPhase: String, Codable, Sendable {
    case scheduled, active, awaitingProof = "awaiting_proof", cancelled, withdrawn
    var title: String {
        switch self {
        case .scheduled: "Starts soon"
        case .active: "Goal in progress"
        case .awaitingProof: "We’re waiting for the race results."
        case .cancelled: "Goal cancelled"
        case .withdrawn: "Goal ended after withdrawal"
        }
    }
}

enum PerformanceCommitmentCloseReason: String, Codable, CaseIterable, Sendable {
    case cancel, withdrawal, injury, accountDeleted = "account_deleted"
    static let ownerSelectable: [Self] = [.cancel, .withdrawal, .injury]
    var title: String {
        switch self {
        case .cancel: "Cancel goal"
        case .withdrawal: "Withdraw from goal"
        case .injury: "Report an injury"
        case .accountDeleted: "Account deleted"
        }
    }
}

struct PerformanceCommitmentConsent: Codable, Equatable, Sendable {
    let commitmentID: UUID
    let actorID: UUID
    let acceptedAt: PerformanceCommitmentInstant
    let policyVersion: String
    let termsDigest: String
    enum CodingKeys: String, CodingKey {
        case commitmentID = "commitment_id", actorID = "actor_id", acceptedAt = "accepted_at"
        case policyVersion = "policy_version", termsDigest = "terms_digest"
    }
}

/// The agreement remains `open` after operational finality. Read its separate
/// lifecycle before offering actions or describing a result.
struct PerformanceCommitmentAgreement: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let actorID: UUID
    let policyVersion: String
    let createdAt: PerformanceCommitmentInstant
    let startsAt: PerformanceCommitmentInstant
    let deadlineAt: PerformanceCommitmentInstant
    let displayTimezone: String
    let targetSeconds: Int
    let terms: PerformanceCommitmentTerms
    let termsDigest: String
    let status: PerformanceCommitmentStatus
    let closedAt: PerformanceCommitmentInstant?
    let closeReason: PerformanceCommitmentCloseReason?
    let consent: PerformanceCommitmentConsent
    let serverNow: PerformanceCommitmentInstant
    let phase: PerformanceCommitmentPhase

    var statusText: String { phase.title }

    enum CodingKeys: String, CodingKey {
        case id, actorID = "actor_id", policyVersion = "policy_version", createdAt = "created_at"
        case startsAt = "starts_at", deadlineAt = "deadline_at", displayTimezone = "display_timezone"
        case targetSeconds = "target_seconds", terms, termsDigest = "terms_digest", status
        case closedAt = "closed_at", closeReason = "close_reason", consent, serverNow = "server_now", phase
    }

    func validate(for actorID: UUID) throws {
        try terms.validate(for: actorID)
        guard self.actorID == actorID, policyVersion == terms.policyVersion,
              PerformanceCommitmentCodec.isDigest(termsDigest), (1...86_400).contains(targetSeconds),
              targetSeconds * 1000 == terms.targetMS,
              startsAt == terms.startsAt, deadlineAt == terms.deadlineAt, displayTimezone == terms.displayTimezone,
              startsAt > createdAt, startsAt.microseconds - createdAt.microseconds <= 720 * 3_600_000_000,
              createdAt <= serverNow, (status == .open) == (closedAt == nil), (closedAt == nil) == (closeReason == nil),
              consent.commitmentID == id, consent.actorID == actorID, consent.acceptedAt == createdAt,
              consent.policyVersion == policyVersion, consent.termsDigest == termsDigest
        else { throw PerformanceCommitmentModelError.invalidResponse }
        if let closedAt {
            guard createdAt <= closedAt, closedAt <= serverNow,
                  (status == .cancelled) == (closedAt < startsAt),
                  closeReason != .cancel || closedAt < startsAt,
                  closeReason != .withdrawal || closedAt >= startsAt
            else { throw PerformanceCommitmentModelError.invalidResponse }
        }
        let expectedPhase: PerformanceCommitmentPhase = switch status {
        case .cancelled: .cancelled
        case .withdrawn: .withdrawn
        case .open: serverNow < startsAt ? .scheduled : (serverNow < deadlineAt ? .active : .awaitingProof)
        }
        guard phase == expectedPhase else { throw PerformanceCommitmentModelError.invalidResponse }
    }
}


extension PerformanceCommitmentAgreement {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        actorID = try values.decode(UUID.self, forKey: .actorID)
        policyVersion = try values.decode(String.self, forKey: .policyVersion)
        createdAt = try values.decode(PerformanceCommitmentInstant.self, forKey: .createdAt)
        startsAt = try values.decode(PerformanceCommitmentInstant.self, forKey: .startsAt)
        deadlineAt = try values.decode(PerformanceCommitmentInstant.self, forKey: .deadlineAt)
        displayTimezone = try values.decode(String.self, forKey: .displayTimezone)
        targetSeconds = try values.decode(Int.self, forKey: .targetSeconds)
        terms = try values.decode(PerformanceCommitmentTerms.self, forKey: .terms)
        termsDigest = try values.decode(String.self, forKey: .termsDigest)
        status = try values.decode(PerformanceCommitmentStatus.self, forKey: .status)
        closedAt = try values.decode(PerformanceCommitmentInstant?.self, forKey: .closedAt)
        closeReason = try values.decode(PerformanceCommitmentCloseReason?.self, forKey: .closeReason)
        consent = try values.decode(PerformanceCommitmentConsent.self, forKey: .consent)
        serverNow = try values.decode(PerformanceCommitmentInstant.self, forKey: .serverNow)
        phase = try values.decode(PerformanceCommitmentPhase.self, forKey: .phase)
    }

    func encode(to encoder: any Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id)
        try values.encode(actorID, forKey: .actorID)
        try values.encode(policyVersion, forKey: .policyVersion)
        try values.encode(createdAt, forKey: .createdAt)
        try values.encode(startsAt, forKey: .startsAt)
        try values.encode(deadlineAt, forKey: .deadlineAt)
        try values.encode(displayTimezone, forKey: .displayTimezone)
        try values.encode(targetSeconds, forKey: .targetSeconds)
        try values.encode(terms, forKey: .terms)
        try values.encode(termsDigest, forKey: .termsDigest)
        try values.encode(status, forKey: .status)
        try values.encode(closedAt, forKey: .closedAt)
        try values.encode(closeReason, forKey: .closeReason)
        try values.encode(consent, forKey: .consent)
        try values.encode(serverNow, forKey: .serverNow)
        try values.encode(phase, forKey: .phase)
    }
}
