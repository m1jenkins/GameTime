import Foundation

struct UserProfile: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let handle: String
    let displayName: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case timezone
    }

    var initials: String {
        let words =
            displayName
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
        let value = words.compactMap(\.first).map(String.init).joined()
        return value.isEmpty ? String(handle.prefix(2)).uppercased() : value.uppercased()
    }
}

struct ProfileCard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let handle: String
    let displayName: String

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
    }

    var initials: String {
        UserProfile(
            id: id,
            handle: handle,
            displayName: displayName,
            timezone: "UTC"
        ).initials
    }
}

enum FriendshipStatus: String, Codable, Sendable {
    case pending
    case accepted
}

struct FriendshipCard: Codable, Equatable, Identifiable, Sendable {
    let otherUserID: UUID
    let handle: String
    let displayName: String
    let status: FriendshipStatus
    let requestedBy: UUID
    let createdAt: Date
    let updatedAt: Date
    let acceptedAt: Date?

    enum CodingKeys: String, CodingKey {
        case otherUserID = "other_user_id"
        case handle
        case displayName = "display_name"
        case status
        case requestedBy = "requested_by"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case acceptedAt = "accepted_at"
    }

    var id: UUID { otherUserID }

    func direction(for callerID: UUID) -> FriendshipDirection {
        guard status == .pending else { return .accepted }
        return requestedBy == callerID ? .outgoing : .incoming
    }

    var profileCard: ProfileCard {
        ProfileCard(id: otherUserID, handle: handle, displayName: displayName)
    }
}

enum FriendshipDirection: Equatable, Sendable {
    case incoming
    case outgoing
    case accepted
}

enum ExactHandleSubmission {
    static func normalized(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("@") {
            value.removeFirst()
        }
        guard
            value.range(
                of: #"^[A-Za-z][A-Za-z0-9_]{2,29}$"#,
                options: .regularExpression
            ) != nil
        else {
            return nil
        }
        return value
    }
}

enum ContestMetric: String, Codable, CaseIterable, Identifiable, Sendable {
    case steps
    case distanceMeters = "distance_meters"
    case activeEnergyKilocalories = "active_energy_kcal"
    case exerciseMinutes = "exercise_minutes"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .steps: "Steps"
        case .distanceMeters: "Distance"
        case .activeEnergyKilocalories: "Active energy"
        case .exerciseMinutes: "Exercise minutes"
        }
    }

    var unit: String {
        switch self {
        case .steps: "steps"
        case .distanceMeters: "m"
        case .activeEnergyKilocalories: "kcal"
        case .exerciseMinutes: "min"
        }
    }

    var suggestedTarget: Double {
        switch self {
        case .steps: 10_000
        case .distanceMeters: 5_000
        case .activeEnergyKilocalories: 500
        case .exerciseMinutes: 30
        }
    }
}

enum ContestCadence: String, Codable, CaseIterable, Identifiable, Sendable {
    case daily
    case cumulative

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum ContestTieBreak: String, Codable, CaseIterable, Identifiable, Sendable {
    case integrityScore = "integrity_score"
    case earliestToTarget = "earliest_to_target"
    case bothDonate = "both_donate"
    case void

    var id: String { rawValue }

    var title: String {
        switch self {
        case .integrityScore: "Verified data"
        case .earliestToTarget: "First to target"
        case .bothDonate: "Both pledge"
        case .void: "No pledge"
        }
    }
}

enum ContestStatus: String, Codable, Sendable {
    case pending
    case active
    case cancelled
    case finalized
}

enum ContestParticipantStatus: String, Codable, Sendable {
    case invited
    case accepted
    case declined
    case withdrawn
    case lapsed
}

struct Charity: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let slug: String
}

struct ContestCard: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let createdBy: UUID?
    let metric: ContestMetric
    let cadence: ContestCadence
    let targetValue: Double
    let stakeAmountCents: Int
    let tieBreak: ContestTieBreak
    let startsAt: Date
    let endsAt: Date
    let status: ContestStatus
    let myStatus: ContestParticipantStatus

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdBy = "created_by"
        case metric
        case cadence
        case targetValue = "target_value"
        case stakeAmountCents = "stake_amount_cents"
        case tieBreak = "tie_break"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
        case myStatus = "my_status"
    }

    var stakeText: String {
        (Double(stakeAmountCents) / 100)
            .formatted(.currency(code: "USD"))
    }

    var targetText: String {
        "\(targetValue.formatted(.number.precision(.fractionLength(0...2)))) \(metric.unit)"
    }
}

enum ChallengeStandingsPhase: String, Codable, Sendable {
    case provisional
    case final
}

enum ChallengeStandingsReason: String, Codable, Sendable {
    case live
    case awaitingIngest = "awaiting_ingest"
    case underReview = "under_review"
    case final
}

enum ChallengeResultKind: String, Codable, Sendable {
    case winner
    case allDonate = "all_donate"
    case void
    case inconclusive
}

enum ChallengeResultReason: String, Codable, Sendable {
    case soleQualifier = "sole_qualifier"
    case earliestToTarget = "earliest_to_target"
    case integrityScore = "integrity_score"
    case bothDonate = "both_donate"
    case noQualifyingParticipant = "no_qualifying_participant"
    case tieBreakVoid = "tie_break_void"
    case tieBreakInconclusive = "tie_break_inconclusive"
    case reviewTimeout = "review_timeout"
}

enum ChallengeObligationKind: String, Codable, Sendable {
    case loserToWinnerCharity = "loser_to_winner_charity"
    case selfDirected = "self_directed"
}

struct ChallengeResult: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: ChallengeResultKind
    let reason: ChallengeResultReason
    let winnerParticipantID: UUID?
    let evidenceCutoff: Date
    let finalizedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case reason
        case winnerParticipantID = "winner_participant_id"
        case evidenceCutoff = "evidence_cutoff"
        case finalizedAt = "finalized_at"
    }
}

struct ChallengeIntegrityRationale: Codable, Equatable, Identifiable, Sendable {
    let code: String
    let summary: String
    let points: Double

    var id: String { code }
}

struct ChallengeObligation: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let kind: ChallengeObligationKind
    let amountCents: Int
    let charityID: UUID
    let charityName: String
    let charitySlug: String
    let destinationOwnerID: UUID
    let resultDisputeClosesAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case amountCents = "amount_cents"
        case charityID = "charity_id"
        case charityName = "charity_name"
        case charitySlug = "charity_slug"
        case destinationOwnerID = "destination_owner_id"
        case resultDisputeClosesAt = "result_dispute_closes_at"
    }

    var amountText: String {
        (Double(amountCents) / 100)
            .formatted(.currency(code: "USD"))
    }
}

struct ChallengeStanding: Codable, Equatable, Identifiable, Sendable {
    let participantID: UUID
    let displayName: String
    let handle: String?
    let displayOrder: Int
    let rank: Int
    let qualified: Bool
    let total: Double
    let qualifyingDays: Int
    let scoreableDays: Int
    let dayRate: Double
    let reachedTargetAt: Date?
    let integrityScore: Double?
    let integrityFlags: [String]?
    let rationale: [ChallengeIntegrityRationale]?
    let obligation: ChallengeObligation?

    enum CodingKeys: String, CodingKey {
        case participantID = "participant_id"
        case displayName = "display_name"
        case handle
        case displayOrder = "display_order"
        case rank
        case qualified
        case total
        case qualifyingDays = "qualifying_days"
        case scoreableDays = "scoreable_days"
        case dayRate = "day_rate"
        case reachedTargetAt = "reached_target_at"
        case integrityScore = "integrity_score"
        case integrityFlags = "integrity_flags"
        case rationale
        case obligation
    }

    var id: UUID { participantID }

    func totalText(metric: ContestMetric) -> String {
        "\(total.formatted(.number.precision(.fractionLength(0...2)))) \(metric.unit)"
    }
}

struct ChallengeStandings: Codable, Equatable, Sendable {
    let contestID: UUID
    let snapshotID: UUID
    let phase: ChallengeStandingsPhase
    let reason: ChallengeStandingsReason
    let asOf: Date
    let scoringVersion: String
    let integrityConfigurationVersion: String
    let result: ChallengeResult?
    let standings: [ChallengeStanding]

    enum CodingKeys: String, CodingKey {
        case contestID = "contest_id"
        case snapshotID = "snapshot_id"
        case phase
        case reason
        case asOf = "as_of"
        case scoringVersion = "scoring_version"
        case integrityConfigurationVersion =
            "integrity_configuration_version"
        case result
        case standings
    }
}

struct ChallengeDraft: Equatable, Sendable {
    var title = ""
    var inviteeIDs: Set<UUID> = []
    var metric: ContestMetric = .steps
    var cadence: ContestCadence = .cumulative
    var targetValue = ContestMetric.steps.suggestedTarget
    var stakeAmountCents = 500
    var startsAt = Date().addingTimeInterval(86_400)
    var endsAt = Date().addingTimeInterval(3 * 86_400)
    var timezone = TimeZone.current.identifier
    var charityID: UUID?
    var tieBreak: ContestTieBreak = .integrityScore

    func validated(now: Date = Date()) throws -> ChallengeTerms {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let canonicalStartsAt = startsAt.canonicalizedToMilliseconds()
        let canonicalEndsAt = endsAt.canonicalizedToMilliseconds()
        guard (1...80).contains(cleanTitle.count) else {
            throw ChallengeValidationError.invalidTitle
        }
        guard !inviteeIDs.isEmpty else {
            throw ChallengeValidationError.missingFriends
        }
        guard inviteeIDs.count <= ChallengeTerms.maximumInvitees else {
            throw ChallengeValidationError.tooManyFriends
        }
        guard targetValue.isFinite, targetValue > 0 else {
            throw ChallengeValidationError.invalidTarget
        }
        guard (100...1_000_000).contains(stakeAmountCents) else {
            throw ChallengeValidationError.invalidStake
        }
        guard canonicalStartsAt > now else {
            throw ChallengeValidationError.startMustBeFuture
        }
        guard canonicalEndsAt > canonicalStartsAt else {
            throw ChallengeValidationError.endMustFollowStart
        }
        guard
            canonicalEndsAt
                <= canonicalStartsAt.addingTimeInterval(366 * 86_400)
        else {
            throw ChallengeValidationError.windowTooLong
        }
        guard
            cadence != .daily
                || canonicalEndsAt
                    >= canonicalStartsAt.addingTimeInterval(86_400)
        else {
            throw ChallengeValidationError.dailyNeedsFullDay
        }
        guard !timezone.isEmpty, TimeZone(identifier: timezone) != nil else {
            throw ChallengeValidationError.invalidTimezone
        }
        guard let charityID else {
            throw ChallengeValidationError.missingCharity
        }

        return ChallengeTerms(
            requestID: UUID(),
            title: cleanTitle,
            inviteeIDs: Array(inviteeIDs),
            metric: metric,
            cadence: cadence,
            targetValue: targetValue,
            stakeAmountCents: stakeAmountCents,
            startsAt: canonicalStartsAt,
            endsAt: canonicalEndsAt,
            timezone: timezone,
            charityID: charityID,
            tieBreak: tieBreak
        )
    }
}

extension Date {
    func canonicalizedToMilliseconds() -> Date {
        let milliseconds = (timeIntervalSince1970 * 1_000).rounded(.down)
        return Date(timeIntervalSince1970: milliseconds / 1_000)
    }

    var isCanonicalMillisecondTimestamp: Bool {
        self == canonicalizedToMilliseconds()
    }
}

struct ChallengeTerms: Codable, Equatable, Sendable {
    static let maximumInvitees = 19

    let requestID: UUID
    let title: String
    let inviteeIDs: [UUID]
    let metric: ContestMetric
    let cadence: ContestCadence
    let targetValue: Double
    let stakeAmountCents: Int
    let startsAt: Date
    let endsAt: Date
    let timezone: String
    let charityID: UUID
    let tieBreak: ContestTieBreak

    var maxParticipants: Int {
        inviteeIDs.count + 1
    }

    enum CodingKeys: String, CodingKey {
        case requestID
        case title
        case inviteeIDs
        case metric
        case cadence
        case targetValue
        case stakeAmountCents
        case startsAtBitPattern
        case endsAtBitPattern
        case timezone
        case charityID
        case tieBreak
    }

    init(
        requestID: UUID,
        title: String,
        inviteeIDs: [UUID],
        metric: ContestMetric,
        cadence: ContestCadence,
        targetValue: Double,
        stakeAmountCents: Int,
        startsAt: Date,
        endsAt: Date,
        timezone: String,
        charityID: UUID,
        tieBreak: ContestTieBreak
    ) {
        self.requestID = requestID
        self.title = title
        self.inviteeIDs = Self.canonicalInviteeIDs(inviteeIDs)
        self.metric = metric
        self.cadence = cadence
        self.targetValue = targetValue
        self.stakeAmountCents = stakeAmountCents
        self.startsAt = startsAt.canonicalizedToMilliseconds()
        self.endsAt = endsAt.canonicalizedToMilliseconds()
        self.timezone = timezone
        self.charityID = charityID
        self.tieBreak = tieBreak
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        title = try container.decode(String.self, forKey: .title)
        inviteeIDs = Self.canonicalInviteeIDs(
            try container.decode([UUID].self, forKey: .inviteeIDs)
        )
        metric = try container.decode(ContestMetric.self, forKey: .metric)
        cadence = try container.decode(ContestCadence.self, forKey: .cadence)
        targetValue = try container.decode(Double.self, forKey: .targetValue)
        stakeAmountCents = try container.decode(
            Int.self,
            forKey: .stakeAmountCents
        )
        startsAt = Date(
            timeIntervalSinceReferenceDate: Double(
                bitPattern: try container.decode(
                    UInt64.self,
                    forKey: .startsAtBitPattern
                )
            )
        )
        endsAt = Date(
            timeIntervalSinceReferenceDate: Double(
                bitPattern: try container.decode(
                    UInt64.self,
                    forKey: .endsAtBitPattern
                )
            )
        )
        timezone = try container.decode(String.self, forKey: .timezone)
        charityID = try container.decode(UUID.self, forKey: .charityID)
        tieBreak = try container.decode(
            ContestTieBreak.self,
            forKey: .tieBreak
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(title, forKey: .title)
        try container.encode(inviteeIDs, forKey: .inviteeIDs)
        try container.encode(metric, forKey: .metric)
        try container.encode(cadence, forKey: .cadence)
        try container.encode(targetValue, forKey: .targetValue)
        try container.encode(stakeAmountCents, forKey: .stakeAmountCents)
        try container.encode(
            startsAt.timeIntervalSinceReferenceDate.bitPattern,
            forKey: .startsAtBitPattern
        )
        try container.encode(
            endsAt.timeIntervalSinceReferenceDate.bitPattern,
            forKey: .endsAtBitPattern
        )
        try container.encode(timezone, forKey: .timezone)
        try container.encode(charityID, forKey: .charityID)
        try container.encode(tieBreak, forKey: .tieBreak)
    }

    private static func canonicalInviteeIDs(_ ids: [UUID]) -> [UUID] {
        ids.sorted {
            $0.uuidString.lowercased() < $1.uuidString.lowercased()
        }
    }
}

enum ChallengeValidationError: LocalizedError, Equatable, Sendable {
    case invalidTitle
    case missingFriends
    case tooManyFriends
    case invalidTarget
    case invalidStake
    case startMustBeFuture
    case endMustFollowStart
    case windowTooLong
    case dailyNeedsFullDay
    case invalidTimezone
    case missingCharity

    var errorDescription: String? {
        switch self {
        case .invalidTitle: "Use a title between 1 and 80 characters."
        case .missingFriends: "Choose at least one friend for this challenge."
        case .tooManyFriends:
            "Choose no more than \(ChallengeTerms.maximumInvitees) friends."
        case .invalidTarget: "Enter a target greater than zero."
        case .invalidStake: "The test pledge must be between $1 and $10,000."
        case .startMustBeFuture: "Choose a future start time."
        case .endMustFollowStart: "The end time must follow the start time."
        case .windowTooLong: "A challenge cannot run longer than 366 days."
        case .dailyNeedsFullDay: "A daily challenge must include at least one full day."
        case .invalidTimezone: "Choose a valid timezone."
        case .missingCharity: "Choose a charity before review."
        }
    }
}

enum ScreenLoadState: Equatable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case failed(String)
}

enum AppMutationError: LocalizedError, Equatable, Sendable {
    case offline
    case cancelled
    case duplicateRequestChanged
    case handleUnavailable
    case localPersistence
    case permissionDenied
    case invalidInput(String)
    case server(String)

    static func map(_ error: Error) -> AppMutationError {
        if error is CancellationError {
            return .cancelled
        }
        if error is PendingChallengeStoreError {
            return .localPersistence
        }

        let message = String(describing: error).lowercased()
        if message.contains("network")
            || message.contains("offline")
            || message.contains("not connected")
        {
            return .offline
        }
        if message.contains("request uuid already used") {
            return .duplicateRequestChanged
        }
        if message.contains("profiles_handle_key")
            || message.contains("duplicate key")
        {
            return .handleUnavailable
        }
        if message.contains("permission")
            || message.contains("42501")
            || message.contains("not eligible")
        {
            return .permissionDenied
        }
        if message.contains("22023") || message.contains("invalid") {
            return .invalidInput(String(describing: error))
        }
        return .server(String(describing: error))
    }

    var errorDescription: String? {
        switch self {
        case .offline: "You appear to be offline. Your request was not submitted."
        case .cancelled: nil
        case .duplicateRequestChanged:
            "That request was already used with different challenge terms. Start a new challenge."
        case .handleUnavailable: "That exact handle is unavailable."
        case .localPersistence:
            "GameTime couldn’t safely update the saved challenge retry. It was not automatically retried."
        case .permissionDenied: "That action is no longer available."
        case .invalidInput:
            "Check the request details and try again."
        case .server:
            "GameTime couldn’t complete that request. Try again."
        }
    }

    var isUnknownServerFailure: Bool {
        if case .server = self {
            return true
        }
        return false
    }
}
