import Foundation

public enum ChallengeHealthMetric: String, CaseIterable, Sendable, Encodable {
    case steps, exerciseSeconds, runningMillimeters, timedRunElapsedSeconds

    public var unit: ChallengeHealthUnit {
        switch self {
        case .steps: .count
        case .exerciseSeconds, .timedRunElapsedSeconds: .seconds
        case .runningMillimeters: .millimeters
        }
    }

    var rawMetric: WeeklySourceMetric {
        switch self {
        case .steps: .steps
        case .exerciseSeconds: .appleExerciseMinutes
        case .runningMillimeters, .timedRunElapsedSeconds: .runningDistanceMillimeters
        }
    }
}

public enum ChallengeHealthUnit: String, Sendable, Encodable {
    case count, seconds, millimeters
}

public enum ChallengeHealthContractError: Error, Equatable {
    case invalidWindow, invalidAgreement, invalidValue, invalidRevision
    case bindingMismatch, requestIDConflict, invalidDeletionEvidence, generationExhausted
}

/// Boundaries are supplied by the agreement/calendar owner, never recalculated
/// with the device's current calendar or timezone. The interval is [start, end).
public struct ChallengeHealthWindow: Equatable, Sendable, Encodable {
    public enum CalendarName: String, Sendable, Encodable { case gregorian, iso8601 }
    public let startMicroseconds: Int64
    public let endMicroseconds: Int64
    public let timeZoneIdentifier: String
    public let calendar: CalendarName

    public init(startMicroseconds: Int64, endMicroseconds: Int64,
                timeZoneIdentifier: String, calendar: CalendarName) throws {
        guard startMicroseconds < endMicroseconds,
              TimeZone(identifier: timeZoneIdentifier) != nil,
              Double(startMicroseconds) / 1_000_000 < Double(endMicroseconds) / 1_000_000
        else { throw ChallengeHealthContractError.invalidWindow }
        self.startMicroseconds = startMicroseconds
        self.endMicroseconds = endMicroseconds
        self.timeZoneIdentifier = timeZoneIdentifier
        self.calendar = calendar
    }

    public var interval: DateInterval {
        DateInterval(start: Date(timeIntervalSince1970: Double(startMicroseconds) / 1_000_000),
                     end: Date(timeIntervalSince1970: Double(endMicroseconds) / 1_000_000))
    }
}

/// This is an identifier for an UNACCEPTED policy, not an acceptance capability.
/// A successful store read cannot construct an accepted source policy.
public struct ChallengeHealthSourcePolicy: Equatable, Sendable, Encodable {
    public let identifier = "challenge-health-unaccepted"
    public let version = 1
    public static let unaccepted = Self()
    private init() {}
    public var acceptsRealSources: Bool { false }
}

/// A separately versioned identity for a real-source adapter. This is a frozen
/// agreement input, not an authorization or a transport capability. V1 has
/// its own Watch-origin source-revision tuple rules and fails closed outside
/// those rules. It does not assert that a particular currently paired Watch
/// supplied a sample.
public struct ChallengeHealthRealSourcePolicy: Equatable, Sendable, Encodable {
    public let identifier: String
    public let version: Int
    public let metric: ChallengeHealthMetric

    private init(identifier: String, version: Int, metric: ChallengeHealthMetric) {
        self.identifier = identifier
        self.version = version
        self.metric = metric
    }

    public static let appleWatchAutomaticStepsV1 = Self(
        identifier: "apple_watch_steps_v1",
        version: 1,
        metric: .steps
    )
    /// The reader can normalize Apple Exercise Time, but public HealthKit
    /// cannot prove the workout/activity lineage that generated it.
    public static let appleWatchExerciseV1 = Self(
        identifier: "apple_watch_exercise_v1",
        version: 1,
        metric: .exerciseSeconds
    )
    /// V2 accepts unknown causal lineage as disclosed in new agreements. All
    /// other Watch provenance and reconciliation requirements remain enforced.
    public static let appleWatchExerciseCreditV2 = Self(
        identifier: "apple_watch_exercise_credit_v2", version: 2, metric: .exerciseSeconds
    )
    public static let appleWorkoutOutdoorDistanceV1 = Self(
        identifier: "apple_workout_outdoor_distance_v1", version: 1, metric: .runningMillimeters
    )
    public static let appleWorkoutOutdoorTimedV1 = Self(
        identifier: "apple_workout_outdoor_timed_v1", version: 1, metric: .timedRunElapsedSeconds
    )
}

public struct ChallengeHealthBinding: Equatable, Sendable, Encodable {
    public let actorID: UUID
    public let challengeID: UUID
    public let agreementVersion: Int
    public let termsDigest: String
    public let metric: ChallengeHealthMetric
    public let challengeWindow: ChallengeHealthWindow
    public let sourcePolicy: ChallengeHealthSourcePolicy
    /// nil keeps the historical synthetic/unaccepted contract exactly closed.
    public let realSourcePolicy: ChallengeHealthRealSourcePolicy?
    /// Frozen `config.distance_mm` for real timed V1; nil preserves history.
    public let selectedDistanceMillimeters: Int64?

    public init(actorID: UUID, challengeID: UUID, agreementVersion: Int,
                termsDigest: String, metric: ChallengeHealthMetric,
                challengeWindow: ChallengeHealthWindow) throws {
        guard agreementVersion > 0, termsDigest.utf8.count == 64,
              termsDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw ChallengeHealthContractError.invalidAgreement }
        self.actorID = actorID
        self.challengeID = challengeID
        self.agreementVersion = agreementVersion
        self.termsDigest = termsDigest
        self.metric = metric
        self.challengeWindow = challengeWindow
        self.sourcePolicy = .unaccepted
        self.realSourcePolicy = nil
        self.selectedDistanceMillimeters = nil
    }

    public init(actorID: UUID, challengeID: UUID, agreementVersion: Int,
                termsDigest: String, metric: ChallengeHealthMetric,
                challengeWindow: ChallengeHealthWindow,
                realSourcePolicy: ChallengeHealthRealSourcePolicy,
                selectedDistanceMillimeters: Int64? = nil) throws {
        guard realSourcePolicy.metric == metric else {
            throw ChallengeHealthContractError.invalidAgreement
        }
        guard agreementVersion > 0, termsDigest.utf8.count == 64,
              termsDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
        else { throw ChallengeHealthContractError.invalidAgreement }
        self.actorID = actorID
        self.challengeID = challengeID
        self.agreementVersion = agreementVersion
        self.termsDigest = termsDigest
        self.metric = metric
        self.challengeWindow = challengeWindow
        self.sourcePolicy = .unaccepted
        self.realSourcePolicy = realSourcePolicy
        guard selectedDistanceMillimeters == nil || (1...1_000_000_000).contains(selectedDistanceMillimeters!),
              realSourcePolicy != .appleWorkoutOutdoorTimedV1 || selectedDistanceMillimeters != nil else {
            throw ChallengeHealthContractError.invalidAgreement
        }
        self.selectedDistanceMillimeters = selectedDistanceMillimeters
    }
}

/// Raw history is local only. This request intentionally has no serialization.
public struct ChallengeHealthReadRequest: Equatable, Sendable {
    public enum Purpose: Equatable, Sendable { case readinessHistory, suggestionHistory, challengeActivity }
    public let binding: ChallengeHealthBinding
    public let deviceRequestID: UUID
    public let queryWindow: ChallengeHealthWindow
    public let purpose: Purpose

    public init(binding: ChallengeHealthBinding, deviceRequestID: UUID,
                queryWindow: ChallengeHealthWindow, purpose: Purpose) throws {
        guard queryWindow.timeZoneIdentifier == binding.challengeWindow.timeZoneIdentifier,
              queryWindow.calendar == binding.challengeWindow.calendar,
              purpose != .challengeActivity
                ? queryWindow.endMicroseconds <= binding.challengeWindow.startMicroseconds
                : queryWindow == binding.challengeWindow
        else { throw ChallengeHealthContractError.invalidWindow }
        self.binding = binding
        self.deviceRequestID = deviceRequestID
        self.queryWindow = queryWindow
        self.purpose = purpose
    }
}

/// Evidence categories describe observations, never a client assertion of full
/// read access or completeness. Even boundedSnapshot cannot prove a miss.
public enum ChallengeHealthEvidence: String, Sendable, Encodable {
    case unknown, boundedSnapshot, boundedSnapshotAfterDeletion, limitedHistory, anchoredChanges
    case observerInvalidation, truncated, explicitDeletion, lostVisibility
}

/// Reuses the existing non-Codable diagnostic record so nil/manual metadata,
/// source/sync identity and active workout duration keep their original meaning.
/// No routes or serialization capability are introduced here.
public struct ChallengeHealthSnapshot: Equatable, Sendable {
    public let request: ChallengeHealthReadRequest
    public let records: [WeeklySourceRecord]
    public let deletedRecordIDs: Set<UUID>
    public let observedAt: Date
    public let sourceFreshness: Date?
    /// Positive limited-history information only. nil means unknown, NOT full access.
    public let earliestAuthorizedSampleDate: Date?
    public let evidence: ChallengeHealthEvidence

    public init(request: ChallengeHealthReadRequest, records: [WeeklySourceRecord],
                deletedRecordIDs: Set<UUID> = [], observedAt: Date,
                sourceFreshness: Date? = nil, earliestAuthorizedSampleDate: Date? = nil,
                evidence: ChallengeHealthEvidence) {
        self.request = request
        self.records = records
        self.deletedRecordIDs = deletedRecordIDs
        self.observedAt = observedAt
        self.sourceFreshness = sourceFreshness
        self.earliestAuthorizedSampleDate = earliestAuthorizedSampleDate
        self.evidence = evidence
    }
}

public enum ChallengeHealthStoreFailure: String, Sendable {
    case protectedDataUnavailable, offline, queryFailed, cancelled
}

public enum ChallengeHealthStoreOutcome: Equatable, Sendable {
    case snapshot(ChallengeHealthSnapshot)
    case unavailable(ChallengeHealthStoreFailure)
}

/// Transport only. Implementations return observations; they cannot grant access,
/// reconcile overlapping writers or turn absent records into zero/deletion.
public protocol ChallengeHealthStore: Sendable {
    func read(_ request: ChallengeHealthReadRequest) async -> ChallengeHealthStoreOutcome
}

public struct ChallengeHealthValue: Equatable, Sendable, Encodable {
    public let metric: ChallengeHealthMetric
    public let integerValue: Int64
    public var unit: ChallengeHealthUnit { metric.unit }

    public init(metric: ChallengeHealthMetric, integerValue: Int64) throws {
        guard integerValue >= 0, metric != .timedRunElapsedSeconds || integerValue > 0
        else { throw ChallengeHealthContractError.invalidValue }
        self.metric = metric
        self.integerValue = integerValue
    }
}
