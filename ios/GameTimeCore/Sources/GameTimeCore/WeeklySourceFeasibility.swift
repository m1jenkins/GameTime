import Foundation

/// Diagnostic inputs for new weekly formats. These never enter Personal or a
/// qualification evaluator. Metadata describes what was read, not sensor proof.
public enum WeeklySourceMetric: String, Sendable, CaseIterable {
    case steps
    case appleExerciseMinutes
    case runningDistanceMillimeters
}

public struct WeeklySourceRecord: Equatable, Sendable {
    public let id: UUID
    public let metric: WeeklySourceMetric
    public let start: Date
    public let end: Date
    public let value: Double
    public let sourceBundleIdentifier: String?
    public let sourceVersion: String?
    public let deviceManufacturer: String?
    public let deviceModel: String?
    /// nil is missing metadata, never equivalent to an explicit false.
    public let wasUserEntered: Bool?
    public let syncIdentifier: String?
    public let syncVersion: Int?
    /// Workout duration may omit pauses. Never substitutes for end - start.
    public let reportedWorkoutDurationSeconds: Double?

    public init(
        id: UUID, metric: WeeklySourceMetric, start: Date, end: Date,
        value: Double, sourceBundleIdentifier: String? = nil,
        sourceVersion: String? = nil, deviceManufacturer: String? = nil,
        deviceModel: String? = nil, wasUserEntered: Bool? = nil,
        syncIdentifier: String? = nil, syncVersion: Int? = nil,
        reportedWorkoutDurationSeconds: Double? = nil
    ) {
        self.id = id
        self.metric = metric
        self.start = start
        self.end = end
        self.value = value
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.sourceVersion = sourceVersion
        self.deviceManufacturer = deviceManufacturer
        self.deviceModel = deviceModel
        self.wasUserEntered = wasUserEntered
        self.syncIdentifier = syncIdentifier
        self.syncVersion = syncVersion
        self.reportedWorkoutDurationSeconds = reportedWorkoutDurationSeconds
    }
}

public enum WeeklySourceReadState: String, Sendable {
    case disabled
    case successfulQuery
    case unavailable
    case failed
    case truncated
}

public struct WeeklySourceCapture: Equatable, Sendable {
    public let accountID: UUID
    public let metric: WeeklySourceMetric
    public let window: DateInterval
    public let observedAt: Date
    public let state: WeeklySourceReadState
    public let records: [WeeklySourceRecord]

    public init(
        accountID: UUID, metric: WeeklySourceMetric, window: DateInterval,
        observedAt: Date, state: WeeklySourceReadState, records: [WeeklySourceRecord]
    ) {
        self.accountID = accountID
        self.metric = metric
        self.window = window
        self.observedAt = observedAt
        self.state = state
        self.records = records
    }
}

public enum WeeklySourceConcern: String, Sendable, Hashable {
    case sourceNotValidated
    case readAccessAndCompletenessUnknown
    case manualEntry
    case manualMarkerAbsent
    case sourceMetadataAbsent
    case overlappingRecords
    case possibleReimport
    case queryTruncated
    case queryFailedOrUnavailable
    case recordsNoLongerVisible
    case lateArrivals
    case exerciseLineageUnverified
    case runningAccuracyUnverified
    case intervalCrossesWindow
}

public struct WeeklySourceAssessment: Equatable, Sendable {
    public let distinctRecordCount: Int
    public let explicitlyManualCount: Int
    public let repeatedUUIDCount: Int
    public let concerns: Set<WeeklySourceConcern>
    /// Deliberately cannot be changed by a caller or a metadata flag.
    public var availableForQualification: Bool { false }
    public var supportsConfirmedMiss: Bool { false }
    /// Summing raw samples double-counts overlapping devices/imports. No total
    /// is offered until a separately accepted reconciliation policy exists.
    public var qualifyingTotal: Double? { nil }
}

public enum WeeklySourceFeasibilityError: Error, Equatable {
    case invalidCapture
    case mismatchedAccountOrWindow
    case conflictingRecordIdentity
}

public enum WeeklySourceFeasibility {
    /// Resource guard for local diagnostics; neither a health target nor proof
    /// that the query returned all records.
    public static let maximumRecords = 5_000

    public static func assess(
        _ capture: WeeklySourceCapture,
        replacing previous: WeeklySourceCapture? = nil
    ) throws -> WeeklySourceAssessment {
        guard capture.window.start < capture.window.end,
            capture.observedAt.timeIntervalSince1970.isFinite,
            capture.window.start.timeIntervalSince1970.isFinite,
            capture.window.end.timeIntervalSince1970.isFinite,
            capture.records.count <= maximumRecords,
            capture.state == .successfulQuery || capture.state == .truncated || capture.records.isEmpty
        else { throw WeeklySourceFeasibilityError.invalidCapture }
        if let previous {
            guard previous.accountID == capture.accountID,
                previous.metric == capture.metric,
                previous.window == capture.window,
                previous.observedAt <= capture.observedAt
            else { throw WeeklySourceFeasibilityError.mismatchedAccountOrWindow }
            // An invalid prior snapshot must not become a trusted comparison.
            _ = try assess(previous)
        }

        var concerns: Set<WeeklySourceConcern> = [
            .sourceNotValidated, .readAccessAndCompletenessUnknown
        ]
        if capture.metric == .appleExerciseMinutes { concerns.insert(.exerciseLineageUnverified) }
        if capture.metric == .runningDistanceMillimeters { concerns.insert(.runningAccuracyUnverified) }
        if capture.state == .truncated { concerns.insert(.queryTruncated) }
        if capture.state == .failed || capture.state == .unavailable {
            concerns.insert(.queryFailedOrUnavailable)
        }

        var unique: [UUID: WeeklySourceRecord] = [:]
        var repeated = 0
        for record in capture.records {
            guard record.metric == capture.metric,
                record.start.timeIntervalSince1970.isFinite,
                record.end.timeIntervalSince1970.isFinite,
                record.start <= record.end,
                record.end >= capture.window.start, record.start < capture.window.end,
                record.start == record.end || record.end > capture.window.start,
                record.end <= capture.observedAt,
                record.value.isFinite, record.value >= 0,
                record.syncVersion.map({ $0 >= 0 }) ?? true,
                record.reportedWorkoutDurationSeconds.map({ $0.isFinite && $0 >= 0 }) ?? true
            else { throw WeeklySourceFeasibilityError.invalidCapture }
            if let prior = unique[record.id] {
                guard prior == record else { throw WeeklySourceFeasibilityError.conflictingRecordIdentity }
                repeated += 1
            } else { unique[record.id] = record }
        }

        var syncIdentities = Set<String>()
        let ordered = unique.values.sorted {
            $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start
        }
        var greatestEnd: Date?
        for record in ordered {
            if record.wasUserEntered == true { concerns.insert(.manualEntry) }
            if record.wasUserEntered == nil { concerns.insert(.manualMarkerAbsent) }
            if record.sourceBundleIdentifier?.isEmpty != false || record.deviceManufacturer?.isEmpty != false {
                concerns.insert(.sourceMetadataAbsent)
            }
            if record.start < capture.window.start || record.end > capture.window.end {
                concerns.insert(.intervalCrossesWindow)
            }
            if let greatestEnd, record.start < greatestEnd { concerns.insert(.overlappingRecords) }
            greatestEnd = max(greatestEnd ?? record.end, record.end)
            if let source = record.sourceBundleIdentifier, let syncID = record.syncIdentifier {
                // Length framing avoids accidental ambiguity in arbitrary IDs.
                let key = "\(source.utf8.count):\(source)\(syncID)"
                if !syncIdentities.insert(key).inserted { concerns.insert(.possibleReimport) }
            }
        }

        if let previous, previous.state == .successfulQuery, capture.state == .successfulQuery {
            let oldIDs = Set(previous.records.map(\.id))
            let newIDs = Set(unique.keys)
            // Lost visibility may be deletion, permission change or a different
            // query result. It is not automatically a confirmed deletion.
            if !oldIDs.subtracting(newIDs).isEmpty { concerns.insert(.recordsNoLongerVisible) }
            if ordered.contains(where: { !oldIDs.contains($0.id) && $0.end <= previous.observedAt }) {
                concerns.insert(.lateArrivals)
            }
        }
        return WeeklySourceAssessment(
            distinctRecordCount: unique.count,
            explicitlyManualCount: ordered.filter { $0.wasUserEntered == true }.count,
            repeatedUUIDCount: repeated, concerns: concerns
        )
    }
}
