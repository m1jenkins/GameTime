import Foundation

enum PersonalChallengeCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case cumulative

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .cumulative: "Cumulative"
        }
    }

    var defaultTargetSteps: Int {
        switch self {
        case .daily: 10_000
        case .cumulative: 70_000
        }
    }
}

enum PersonalSettlementMode: String, Codable, Sendable {
    case testOnly = "test_only"
}

enum PersonalChallengeStatus: String, Codable, Sendable {
    case scheduled
    case active
    case awaitingEvidence = "awaiting_evidence"
    case cancelled
    case completed

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        switch try container.decode(String.self) {
        case "scheduled", "pending": self = .scheduled
        case "active": self = .active
        case "awaiting_evidence", "grace": self = .awaitingEvidence
        case "cancelled": self = .cancelled
        case "completed", "finalized": self = .completed
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported personal challenge status."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var isOpen: Bool {
        switch self {
        case .scheduled, .active, .awaitingEvidence: true
        case .cancelled, .completed: false
        }
    }

}

/// A display-only lifecycle state. The service continues to own the persisted
/// status; this adds the honest client presentation needed while a closed
/// evidence window is waiting for service assessment.
enum PersonalChallengePresentationStatus: Equatable, Sendable {
    case scheduled
    case active
    case awaitingEvidence
    case resultPending
    case cancelled
    case completed

    init(_ status: PersonalChallengeStatus) {
        switch status {
        case .scheduled: self = .scheduled
        case .active: self = .active
        case .awaitingEvidence: self = .awaitingEvidence
        case .cancelled: self = .cancelled
        case .completed: self = .completed
        }
    }
}

enum PersonalOutcomeKind: String, Codable, Sendable {
    case metGoal = "met_goal"
    case missedGoal = "missed_goal"
    case inconclusive
}

enum PersonalEvidenceState: String, Codable, Sendable {
    case future
    case inProgress = "in_progress"
    case pending
    case complete
    case incomplete
    case missing
    case quarantined
    case conflicting
    case unresolved
    case outageWaived = "outage_waived"
}

enum PersonalTermsDateFormatter {
    static func dateTime(
        _ date: Date,
        timezoneIdentifier: String
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                timeZone: timeZone(timezoneIdentifier)
            )
        )
    }

    static func day(
        _ date: Date,
        timezoneIdentifier: String
    ) -> String {
        date.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .omitted,
                timeZone: timeZone(timezoneIdentifier)
            )
        )
    }

    private static func timeZone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier) ?? TimeZone(secondsFromGMT: 0)!
    }
}

enum PersonalDiagnosticStatus: String, Codable, Sendable {
    case notRun = "not_run"
    case trusted
    case noPositiveTrustedSample = "no_positive_trusted_sample"
    case unavailable
    case failed
}

struct PersonalChallengeDraft: Equatable, Sendable {
    static let allowedCommitmentAmountsMinor = [1_000, 2_000, 3_000, 4_000, 5_000]
    static let targetRange = 1...1_000_000

    var cadence: PersonalChallengeCadence = .daily
    var targetSteps = PersonalChallengeCadence.daily.defaultTargetSteps
    var commitmentAmountMinor = 1_000
    var timezone = TimeZone.current.identifier

    static func initial(
        profileTimezone: String?,
        deviceTimezone: String = TimeZone.current.identifier
    ) -> PersonalChallengeDraft {
        let frozenTimezone: String
        if let profileTimezone,
            TimeZone(identifier: profileTimezone) != nil
        {
            frozenTimezone = profileTimezone
        } else {
            frozenTimezone = deviceTimezone
        }
        return PersonalChallengeDraft(timezone: frozenTimezone)
    }

    mutating func selectCadence(_ newCadence: PersonalChallengeCadence) {
        let oldDefault = cadence.defaultTargetSteps
        cadence = newCadence
        if targetSteps == oldDefault {
            targetSteps = newCadence.defaultTargetSteps
        }
    }

    func validated(requestID: UUID = UUID()) throws
        -> PersonalChallengeCreationRequest
    {
        guard Self.targetRange.contains(targetSteps) else {
            throw PersonalChallengeValidationError.invalidTarget
        }
        guard Self.allowedCommitmentAmountsMinor.contains(commitmentAmountMinor) else {
            throw PersonalChallengeValidationError.invalidCommitment
        }
        guard !timezone.isEmpty, TimeZone(identifier: timezone) != nil else {
            throw PersonalChallengeValidationError.invalidTimezone
        }
        return PersonalChallengeCreationRequest(
            requestID: requestID,
            cadence: cadence,
            targetSteps: targetSteps,
            commitmentAmountMinor: commitmentAmountMinor,
            timezone: timezone
        )
    }
}

struct PersonalChallengeCreationRequest: Codable, Equatable, Sendable {
    let requestID: UUID
    let cadence: PersonalChallengeCadence
    let targetSteps: Int
    let commitmentAmountMinor: Int
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case requestID
        case cadence
        case targetSteps
        case commitmentAmountMinor
        case timezone
    }
}

enum PersonalChallengeValidationError: LocalizedError, Equatable, Sendable {
    case invalidTarget
    case invalidCommitment
    case invalidTimezone

    var errorDescription: String? {
        switch self {
        case .invalidTarget:
            "Enter a whole-number step target from 1 to 1,000,000."
        case .invalidCommitment:
            "Choose a test commitment from $10, $20, $30, $40, or $50."
        case .invalidTimezone:
            "GameTime could not identify a valid IANA timezone."
        }
    }
}

struct FrozenPersonalTerms: Codable, Equatable, Sendable {
    let challengeID: UUID
    let userID: UUID?
    let cadence: PersonalChallengeCadence
    let targetSteps: Int
    let commitmentAmountMinor: Int
    let currency: String
    let settlementMode: PersonalSettlementMode
    let termsVersion: String
    let timezone: String
    let agreementAt: Date
    let startsAt: Date
    let endsAt: Date
    let evidenceCutoff: Date
    let closedAt: Date?

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case userID = "user_id"
        case cadence
        case targetSteps = "target_steps"
        case commitmentAmountMinor = "commitment_amount_minor"
        case currency
        case settlementMode = "settlement_mode"
        case termsVersion = "terms_version"
        case timezone
        case agreementAt = "agreement_at"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case evidenceCutoff = "evidence_cutoff"
        case closedAt = "closed_at"
    }

    var commitmentText: String {
        (Double(commitmentAmountMinor) / 100)
            .formatted(.currency(code: currency))
    }

    var targetText: String {
        cadence == .daily
            ? "\(targetSteps.formatted()) steps per day"
            : "\(targetSteps.formatted()) steps total"
    }
}

struct PersonalDayProgress: Codable, Equatable, Identifiable, Sendable {
    let localDate: String
    /// The service keeps authoritative step totals as `numeric(20,2)`.
    /// Preserve that precision when decoding; UI-only whole-step presentation
    /// must not become a second scoring rule.
    let trustedSteps: Double
    let targetSteps: Int?
    let evidenceState: PersonalEvidenceState
    let metTarget: Bool?

    var id: String { localDate }

    var displayedTrustedSteps: Int {
        guard trustedSteps.isFinite, trustedSteps > 0 else { return 0 }
        let wholeSteps = trustedSteps.rounded(.towardZero)
        guard wholeSteps < Double(Int.max) else { return Int.max }
        return Int(wholeSteps)
    }

    enum CodingKeys: String, CodingKey {
        case localDate = "local_date"
        case trustedSteps = "trusted_steps"
        case targetSteps = "target_steps"
        case evidenceState = "evidence_state"
        case metTarget = "met_target"
    }
}

struct PersonalProgress: Codable, Equatable, Sendable {
    let trustedSteps: Int
    let remainingSteps: Int
    let qualifyingDays: Int
    let completedDays: Int
    let days: [PersonalDayProgress]
    let evidenceState: PersonalEvidenceState
    let lastTrustedSyncAt: Date?
    let pendingUploadCount: Int
    let coveredBucketCount: Int
    let expectedBucketCount: Int

    enum CodingKeys: String, CodingKey {
        case trustedSteps = "trusted_steps"
        case remainingSteps = "remaining_steps"
        case qualifyingDays = "qualifying_days"
        case completedDays = "completed_days"
        case days
        case evidenceState = "evidence_state"
        case lastTrustedSyncAt = "last_trusted_sync_at"
        case pendingUploadCount = "pending_upload_count"
        case coveredBucketCount = "covered_bucket_count"
        case expectedBucketCount = "expected_bucket_count"
    }

    static let empty = PersonalProgress(
        trustedSteps: 0,
        remainingSteps: 0,
        qualifyingDays: 0,
        completedDays: 0,
        days: [],
        evidenceState: .pending,
        lastTrustedSyncAt: nil,
        pendingUploadCount: 0,
        coveredBucketCount: 0,
        expectedBucketCount: 0
    )

    static func dailyRemainingSteps(
        targetSteps: Int,
        days: [PersonalDayProgress]
    ) -> Int {
        let relevantDay = days.first(where: {
            $0.evidenceState == .inProgress
        }) ?? days.last(where: {
            switch $0.evidenceState {
            case .future:
                false
            case .inProgress, .pending, .complete, .incomplete, .missing,
                .quarantined, .conflicting, .unresolved, .outageWaived:
                true
            }
        })
        return max(
            0,
            targetSteps - (relevantDay?.displayedTrustedSteps ?? 0)
        )
    }

    static func aggregateEvidenceState(
        days: [PersonalDayProgress],
        coveredBucketCount: Int,
        expectedBucketCount: Int
    ) -> PersonalEvidenceState {
        let precedence: [PersonalEvidenceState] = [
            .quarantined,
            .conflicting,
            .unresolved,
            .missing,
            .incomplete,
            .outageWaived,
        ]
        if let exceptional = precedence.first(where: { state in
            days.contains(where: { $0.evidenceState == state })
        }) {
            return exceptional
        }
        return expectedBucketCount > 0
            && coveredBucketCount >= expectedBucketCount
            ? .complete
            : .pending
    }
}

struct PersonalOutcome: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: PersonalOutcomeKind
    let reasonCode: String
    let evidenceCutoff: Date
    let publishedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case reasonCode = "reason_code"
        case evidenceCutoff = "evidence_cutoff"
        case publishedAt = "published_at"
    }
}

struct PersonalChallengeSummary: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let status: PersonalChallengeStatus
    let terms: FrozenPersonalTerms
    let progress: PersonalProgress?
    let outcome: PersonalOutcome?

    enum CodingKeys: String, CodingKey {
        case id
        case challengeID = "challenge_id"
        case status
        case terms
        case progress
        case outcome
    }

    init(
        id: UUID,
        status: PersonalChallengeStatus,
        terms: FrozenPersonalTerms,
        progress: PersonalProgress? = nil,
        outcome: PersonalOutcome? = nil
    ) {
        self.id = id
        self.status = status
        self.terms = terms
        self.progress = progress
        self.outcome = outcome
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) {
            id = decodedID
        } else {
            id = try container.decode(UUID.self, forKey: .challengeID)
        }
        status = try container.decode(PersonalChallengeStatus.self, forKey: .status)
        terms = try container.decode(FrozenPersonalTerms.self, forKey: .terms)
        progress = try container.decodeIfPresent(PersonalProgress.self, forKey: .progress)
        outcome = try container.decodeIfPresent(PersonalOutcome.self, forKey: .outcome)
        guard terms.challengeID == id, terms.settlementMode == .testOnly else {
            throw DecodingError.dataCorruptedError(
                forKey: .terms,
                in: container,
                debugDescription: "Personal terms do not match the challenge or Stage A."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encode(terms, forKey: .terms)
        try container.encodeIfPresent(progress, forKey: .progress)
        try container.encodeIfPresent(outcome, forKey: .outcome)
    }

    func permitsActivitySync(at date: Date) -> Bool {
        guard date >= terms.startsAt, date < terms.evidenceCutoff else {
            return false
        }
        return status == .active || status == .awaitingEvidence
    }

    func presentationStatus(at date: Date) -> PersonalChallengePresentationStatus {
        if outcome == nil,
            status.isOpen,
            date >= terms.evidenceCutoff
        {
            return .resultPending
        }
        if status == .active,
            date >= terms.endsAt,
            date < terms.evidenceCutoff
        {
            return .awaitingEvidence
        }
        return PersonalChallengePresentationStatus(status)
    }
}

struct PersonalChallengeDetail: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let status: PersonalChallengeStatus
    let terms: FrozenPersonalTerms
    let progress: PersonalProgress
    let outcome: PersonalOutcome?

    enum CodingKeys: String, CodingKey {
        case id
        case challengeID = "challenge_id"
        case status
        case terms
        case progress
        case outcome
    }

    init(
        id: UUID,
        status: PersonalChallengeStatus,
        terms: FrozenPersonalTerms,
        progress: PersonalProgress,
        outcome: PersonalOutcome? = nil
    ) {
        self.id = id
        self.status = status
        self.terms = terms
        self.progress = progress
        self.outcome = outcome
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decodedID = try container.decodeIfPresent(UUID.self, forKey: .id) {
            id = decodedID
        } else {
            id = try container.decode(UUID.self, forKey: .challengeID)
        }
        status = try container.decode(PersonalChallengeStatus.self, forKey: .status)
        terms = try container.decode(FrozenPersonalTerms.self, forKey: .terms)
        progress = try container.decodeIfPresent(PersonalProgress.self, forKey: .progress)
            ?? .empty
        outcome = try container.decodeIfPresent(PersonalOutcome.self, forKey: .outcome)
        guard terms.challengeID == id, terms.settlementMode == .testOnly else {
            throw DecodingError.dataCorruptedError(
                forKey: .terms,
                in: container,
                debugDescription: "Personal terms do not match the challenge or Stage A."
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(status, forKey: .status)
        try container.encode(terms, forKey: .terms)
        try container.encode(progress, forKey: .progress)
        try container.encodeIfPresent(outcome, forKey: .outcome)
    }

    func permitsActivitySync(at date: Date) -> Bool {
        guard date >= terms.startsAt, date < terms.evidenceCutoff else {
            return false
        }
        return status == .active || status == .awaitingEvidence
    }

    func presentationStatus(at date: Date) -> PersonalChallengePresentationStatus {
        if outcome == nil,
            status.isOpen,
            date >= terms.evidenceCutoff
        {
            return .resultPending
        }
        if status == .active,
            date >= terms.endsAt,
            date < terms.evidenceCutoff
        {
            return .awaitingEvidence
        }
        return PersonalChallengePresentationStatus(status)
    }
}

struct PersonalEligibilityHold: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let reasonCode: String
    let createdAt: Date
    let clearedAt: Date?
    let clearedByDiagnosticID: UUID?

    enum CodingKeys: String, CodingKey {
        case id
        case reasonCode = "reason_code"
        case createdAt = "created_at"
        case clearedAt = "cleared_at"
        case clearedByDiagnosticID = "cleared_by_diagnostic_id"
    }

    var isActive: Bool { clearedAt == nil }
}

struct TrustedActivityDiagnostic: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let status: PersonalDiagnosticStatus
    let performedAt: Date
    let trustedQueriedHourCount: Int
    let positiveTrustedSampleCount: Int
    let clearsEligibilityHold: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case status
        case performedAt = "performed_at"
        case trustedQueriedHourCount = "trusted_queried_hour_count"
        case positiveTrustedSampleCount = "positive_trusted_sample_count"
        case clearsEligibilityHold = "clears_eligibility_hold"
    }

    var isTrusted: Bool {
        status == .trusted && positiveTrustedSampleCount > 0
    }
}

struct PersonalAccountabilitySnapshot: Codable, Equatable, Sendable {
    let challenges: [PersonalChallengeSummary]
    let latestDiagnostic: TrustedActivityDiagnostic?
    let eligibilityHold: PersonalEligibilityHold?
    let eligibilityHoldActive: Bool

    init(
        challenges: [PersonalChallengeSummary],
        latestDiagnostic: TrustedActivityDiagnostic?,
        eligibilityHold: PersonalEligibilityHold?,
        eligibilityHoldActive: Bool? = nil
    ) {
        self.challenges = challenges
        self.latestDiagnostic = latestDiagnostic
        self.eligibilityHold = eligibilityHold
        self.eligibilityHoldActive = eligibilityHoldActive
            ?? eligibilityHold?.isActive
            ?? false
    }

    enum CodingKeys: String, CodingKey {
        case challenges
        case latestDiagnostic = "latest_diagnostic"
        case eligibilityHold = "eligibility_hold"
        case eligibilityHoldActive = "eligibility_hold_active"
    }
}
