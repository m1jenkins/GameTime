import Foundation

public enum ChallengeHealthReadiness: String, CaseIterable, Sendable {
    case unsupported, notConnected, checking, ready, noEligibleDataYet
    case temporarilyUnavailable, staleOrIncomplete
}

public enum ChallengeHealthIssue: String, Hashable, Sendable {
    case sourcePolicyUnaccepted, invalidSnapshot, metricMismatch, normalizationUnresolved
    case reconciliationUnresolved, boundaryUnresolved, timedQualificationUnresolved
    case incompleteEvidence, historyLimited, freshnessUnresolved, historyRequired
    case lostVisibility, deletionObserved
}

public struct ChallengeHealthEvaluation: Equatable, Sendable {
    public let readiness: ChallengeHealthReadiness
    /// A synthetic positive observation is separate from completeness and readiness.
    public let activity: ChallengeHealthValue?
    public let evidence: ChallengeHealthEvidence
    public let issues: Set<ChallengeHealthIssue>
    public let diagnosticConcerns: Set<WeeklySourceConcern>
    public let syntheticOnly: Bool
    public var permitsRealConsent: Bool { false }
    public var permitsRealIngestion: Bool { false }
    public var supportsConfirmedMiss: Bool { false }
}

public protocol ChallengeHealthAdapter: Sendable {
    var metric: ChallengeHealthMetric { get }
    func evaluate(_ snapshot: ChallengeHealthSnapshot,
                  replacing previous: ChallengeHealthSnapshot?) -> ChallengeHealthEvaluation
}

// Internal, explicit fixture decisions are reachable by @testable tests only.
// They are NOT source rules, a configurable allowlist or a real policy factory.
struct ChallengeHealthSyntheticPolicy: Sendable {
    enum Decision: Sendable {
        case exclude
        case contribution(Int64)
        case qualifyingWholeTimedRun
    }
    let decisions: [UUID: Decision]
    let resolvesReconciliation: Bool
    let freshThrough: Date
}

public struct ChallengeHealthStepsAdapter: ChallengeHealthAdapter {
    public let metric = ChallengeHealthMetric.steps
    private let fixture: ChallengeHealthSyntheticPolicy?
    public init() { fixture = nil }
    init(fixture: ChallengeHealthSyntheticPolicy) { self.fixture = fixture }
    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        ChallengeHealthAdapterEngine.evaluate(snapshot, previous: previous, metric: metric, fixture: fixture)
    }
}

public struct ChallengeHealthExerciseAdapter: ChallengeHealthAdapter {
    public let metric = ChallengeHealthMetric.exerciseSeconds
    private let fixture: ChallengeHealthSyntheticPolicy?
    public init() { fixture = nil }
    init(fixture: ChallengeHealthSyntheticPolicy) { self.fixture = fixture }
    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        ChallengeHealthAdapterEngine.evaluate(snapshot, previous: previous, metric: metric, fixture: fixture)
    }
}

public struct ChallengeHealthRunningDistanceAdapter: ChallengeHealthAdapter {
    public let metric = ChallengeHealthMetric.runningMillimeters
    private let fixture: ChallengeHealthSyntheticPolicy?
    public init() { fixture = nil }
    init(fixture: ChallengeHealthSyntheticPolicy) { self.fixture = fixture }
    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        ChallengeHealthAdapterEngine.evaluate(snapshot, previous: previous, metric: metric, fixture: fixture)
    }
}

public struct ChallengeHealthTimedRunAdapter: ChallengeHealthAdapter {
    public let metric = ChallengeHealthMetric.timedRunElapsedSeconds
    private let fixture: ChallengeHealthSyntheticPolicy?
    public init() { fixture = nil }
    init(fixture: ChallengeHealthSyntheticPolicy) { self.fixture = fixture }
    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        ChallengeHealthAdapterEngine.evaluate(snapshot, previous: previous, metric: metric, fixture: fixture)
    }
}

private enum ChallengeHealthAdapterEngine {
    static func evaluate(_ snapshot: ChallengeHealthSnapshot, previous: ChallengeHealthSnapshot?,
                         metric: ChallengeHealthMetric,
                         fixture: ChallengeHealthSyntheticPolicy?) -> ChallengeHealthEvaluation {
        var issues: Set<ChallengeHealthIssue> = []
        var concerns: Set<WeeklySourceConcern> = []
        func result(_ activity: ChallengeHealthValue? = nil) -> ChallengeHealthEvaluation {
            let readiness: ChallengeHealthReadiness
            let blocking = issues.subtracting([.historyLimited, .deletionObserved])
            if blocking == [.sourcePolicyUnaccepted] && snapshot.records.isEmpty {
                readiness = .noEligibleDataYet
            } else if !blocking.isEmpty { readiness = .staleOrIncomplete }
            else if activity != nil { readiness = .ready }
            else { readiness = .noEligibleDataYet }
            return ChallengeHealthEvaluation(readiness: readiness, activity: activity,
                evidence: snapshot.evidence, issues: issues, diagnosticConcerns: concerns,
                syntheticOnly: fixture != nil)
        }
        guard snapshot.request.binding.metric == metric else {
            issues.insert(.metricMismatch)
            return result()
        }
        if let previous {
            // Request IDs can change on refresh; actor, terms, metric and frozen windows cannot.
            guard previous.request.binding == snapshot.request.binding,
                  previous.request.queryWindow == snapshot.request.queryWindow,
                  previous.request.purpose == snapshot.request.purpose,
                  previous.observedAt <= snapshot.observedAt else {
                issues.insert(.invalidSnapshot)
                return result()
            }
        }
        guard snapshot.observedAt.timeIntervalSince1970.isFinite,
              snapshot.sourceFreshness.map({ $0.timeIntervalSince1970.isFinite && $0 <= snapshot.observedAt }) ?? true,
              snapshot.earliestAuthorizedSampleDate.map({ $0.timeIntervalSince1970.isFinite && $0 <= snapshot.observedAt }) ?? true,
              Set(snapshot.records.map(\.id)).isDisjoint(with: snapshot.deletedRecordIDs),
              snapshot.deletedRecordIDs.isEmpty || snapshot.evidence == .explicitDeletion
                || snapshot.evidence == .anchoredChanges || snapshot.evidence == .boundedSnapshotAfterDeletion,
              snapshot.evidence != .boundedSnapshotAfterDeletion || !snapshot.deletedRecordIDs.isEmpty
        else {
            issues.insert(.invalidSnapshot)
            return result()
        }
        func capture(_ input: ChallengeHealthSnapshot) -> WeeklySourceCapture {
            WeeklySourceCapture(accountID: input.request.binding.actorID, metric: metric.rawMetric,
                window: input.request.queryWindow.interval, observedAt: input.observedAt,
                state: input.evidence == .truncated ? .truncated : .successfulQuery, records: input.records)
        }
        let isSnapshot = snapshot.evidence == .boundedSnapshot || snapshot.evidence == .limitedHistory
            || snapshot.evidence == .boundedSnapshotAfterDeletion
        do {
            concerns = try WeeklySourceFeasibility.assess(capture(snapshot),
                replacing: isSnapshot ? previous.map(capture) : nil).concerns
        } catch {
            issues.insert(.invalidSnapshot)
            return result()
        }
        if concerns.contains(.recordsNoLongerVisible) {
            let missing = Set(previous?.records.map(\.id) ?? []).subtracting(snapshot.records.map(\.id))
            if !missing.subtracting(snapshot.deletedRecordIDs).isEmpty { issues.insert(.lostVisibility) }
        }
        if !snapshot.deletedRecordIDs.isEmpty { issues.insert(.deletionObserved) }
        if !isSnapshot {
            issues.insert(.incompleteEvidence)
            return result()
        }
        if snapshot.evidence == .limitedHistory { issues.insert(.historyLimited) }
        if let earliest = snapshot.earliestAuthorizedSampleDate, earliest > snapshot.request.queryWindow.interval.start {
            issues.insert(.historyLimited)
        }
        if snapshot.request.purpose != .readinessHistory { issues.insert(.historyRequired) }
        guard let fixture else {
            issues.insert(.sourcePolicyUnaccepted)
            return result()
        }
        if snapshot.sourceFreshness == nil || !fixture.freshThrough.timeIntervalSince1970.isFinite
            || snapshot.observedAt > fixture.freshThrough {
            issues.insert(.freshnessUnresolved)
        }
        if (concerns.contains(.overlappingRecords) || concerns.contains(.possibleReimport))
            && !fixture.resolvesReconciliation {
            issues.insert(.reconciliationUnresolved)
            return result()
        }
        // Exact duplicate UUIDs have already been validated as identical. No
        // source preference, sync-version winner or overlap algorithm is inferred.
        var seen: Set<UUID> = []
        var values: [Int64] = []
        for record in snapshot.records where seen.insert(record.id).inserted {
            guard let decision = fixture.decisions[record.id] else {
                issues.insert(.normalizationUnresolved)
                return result()
            }
            if case .exclude = decision { continue }
            guard record.start >= snapshot.request.queryWindow.interval.start,
                  record.end <= snapshot.request.queryWindow.interval.end else {
                issues.insert(.boundaryUnresolved)
                return result()
            }
            switch (metric, decision) {
            case (.timedRunElapsedSeconds, .qualifyingWholeTimedRun):
                // Distance qualification is an explicit synthetic decision. No
                // distance tolerance is assumed. Active duration never replaces elapsed.
                let elapsed = record.end.timeIntervalSince(record.start)
                guard record.value > 0, elapsed > 0,
                      let seconds = Int64(exactly: elapsed) else {
                    issues.insert(.normalizationUnresolved)
                    return result()
                }
                values.append(seconds)
            case (.timedRunElapsedSeconds, _):
                issues.insert(.timedQualificationUnresolved)
                return result()
            case (_, .contribution(let value)) where value >= 0:
                values.append(value)
            default:
                issues.insert(.normalizationUnresolved)
                return result()
            }
        }
        guard !values.isEmpty else { return result() }
        let total: Int64
        if metric == .timedRunElapsedSeconds { total = values.min()! }
        else {
            var sum: Int64 = 0
            for value in values {
                let addition = sum.addingReportingOverflow(value)
                guard !addition.overflow else {
                    issues.insert(.normalizationUnresolved)
                    return result()
                }
                sum = addition.partialValue
            }
            total = sum
        }
        // Zero is not positive eligible history and cannot establish readiness.
        guard total > 0 else { return result() }
        return result(try? ChallengeHealthValue(metric: metric, integerValue: total))
    }
}
