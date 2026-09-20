import Foundation

/// Conservative whole-workout outdoor running policy. The source tuple and
/// workout fields are local inputs only; no raw workout/source data leaves it.
public struct ChallengeHealthAppleWorkoutDistanceAdapter: ChallengeHealthAdapter {
    public let metric = ChallengeHealthMetric.runningMillimeters
    public init() {}

    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        evaluate(snapshot, replacing: previous, policy: .appleWorkoutOutdoorDistanceV1, timed: false)
    }
}

public struct ChallengeHealthAppleWorkoutTimedAdapter: ChallengeHealthAdapter {
    public let metric = ChallengeHealthMetric.timedRunElapsedSeconds
    public init() {}

    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        ChallengeHealthAppleWorkoutEvaluator.evaluate(snapshot, replacing: previous,
                                                       metric: metric, policy: .appleWorkoutOutdoorTimedV1,
                                                       timed: true)
    }
}

private extension ChallengeHealthAppleWorkoutDistanceAdapter {
    func evaluate(_ snapshot: ChallengeHealthSnapshot, replacing previous: ChallengeHealthSnapshot?,
                  policy: ChallengeHealthRealSourcePolicy, timed: Bool) -> ChallengeHealthEvaluation {
        ChallengeHealthAppleWorkoutEvaluator.evaluate(snapshot, replacing: previous, metric: metric,
                                                       policy: policy, timed: timed)
    }
}

private enum ChallengeHealthAppleWorkoutEvaluator {
    static func evaluate(_ snapshot: ChallengeHealthSnapshot, replacing previous: ChallengeHealthSnapshot?,
                         metric: ChallengeHealthMetric, policy: ChallengeHealthRealSourcePolicy,
                         timed: Bool) -> ChallengeHealthEvaluation {
        var issues: Set<ChallengeHealthIssue> = []
        func result(_ activity: ChallengeHealthValue? = nil, _ accepted: Bool = false) -> ChallengeHealthEvaluation {
            let blocked = !issues.subtracting([.sourceExplicitlyRejected, .deletionObserved]).isEmpty
            let usable = accepted && !blocked
            return ChallengeHealthEvaluation(readiness: blocked ? .staleOrIncomplete : (activity == nil ? .noEligibleDataYet : .ready),
              activity: activity, evidence: snapshot.evidence, issues: issues, diagnosticConcerns: [], syntheticOnly: false,
              acceptsRealSourceObservation: usable, permitsRealConsent: usable && snapshot.request.purpose == .readinessHistory,
              permitsRealIngestion: usable, supportsConfirmedMiss: false)
        }
        guard snapshot.request.binding.metric == metric, snapshot.request.binding.realSourcePolicy == policy else {
            issues.insert(.realSourcePolicyMismatch); return result()
        }
        guard snapshot.evidence == .boundedSnapshot || snapshot.evidence == .limitedHistory
                || snapshot.evidence == .boundedSnapshotAfterDeletion,
              snapshot.deletedRecordIDs.isEmpty || snapshot.evidence == .boundedSnapshotAfterDeletion else {
            issues.insert(.incompleteEvidence); return result()
        }
        guard
              snapshot.observedAt.timeIntervalSince1970.isFinite,
              Set(snapshot.records.map(\.id)).isDisjoint(with: snapshot.deletedRecordIDs),
              snapshot.sourceFreshness.map({ $0.timeIntervalSince1970.isFinite && $0 <= snapshot.observedAt }) ?? false,
              snapshot.earliestAuthorizedSampleDate.map({ $0.timeIntervalSince1970.isFinite && $0 <= snapshot.observedAt }) ?? true else {
            issues.insert(.invalidSnapshot); return result()
        }
        if let previous, (previous.request.binding != snapshot.request.binding || previous.request.queryWindow != snapshot.request.queryWindow
            || previous.request.purpose != snapshot.request.purpose || previous.observedAt > snapshot.observedAt) {
            issues.insert(.invalidSnapshot); return result()
        }
        if snapshot.request.purpose == .readinessHistory &&
            (snapshot.request.queryWindow.interval.end > snapshot.observedAt
                || snapshot.evidence == .limitedHistory
                || snapshot.earliestAuthorizedSampleDate.map({ $0 > snapshot.request.queryWindow.interval.start }) == true
                || !hasRequiredCalendarDayHistory(snapshot.request, days: timed ? 90 : 30)) {
            issues.insert(.historyLimited)
        }
        if !snapshot.deletedRecordIDs.isEmpty { issues.insert(.deletionObserved) }
        var records: [WeeklySourceRecord] = []
        var identities: [UUID: WeeklySourceRecord] = [:]
        for r in snapshot.records {
            if let existing = identities[r.id] {
                if existing != r { issues.insert(.reconciliationUnresolved) }
                continue
            }
            identities[r.id] = r
            guard r.metric == .runningDistanceMillimeters, r.value.isFinite, r.value > 0,
                  r.start < r.end else { issues.insert(.boundaryUnresolved); continue }
            // The reader can observe an active frozen window only through its
            // observation instant. A sample ending later cannot be counted or
            // silently treated as an ordinary boundary-crossing workout.
            guard r.end <= snapshot.observedAt else { issues.insert(.boundaryUnresolved); continue }
            // Whole workout policy excludes a crossing run; it does not make
            // otherwise complete in-window workouts unresolved.
            guard r.start >= snapshot.request.queryWindow.interval.start,
                  r.end <= snapshot.request.queryWindow.interval.end else { continue }
            guard r.wasUserEntered != true, r.workoutActivityType == "running", r.wasIndoorWorkout == false,
                  isWorkoutSource(r.sourceBundleIdentifier), isWatch(r.sourceProductType) else {
                if r.sourceBundleIdentifier == nil || r.sourceProductType == nil || r.workoutActivityType == nil || r.wasIndoorWorkout == nil {
                    issues.insert(.realSourceProvenanceUnavailable)
                } else if r.wasUserEntered == true || r.workoutActivityType != "running" || r.wasIndoorWorkout == true
                            || isExplicitlyRejectedSource(r.sourceBundleIdentifier)
                            || isIPhone(r.sourceProductType) {
                    issues.insert(.sourceExplicitlyRejected)
                } else {
                    issues.insert(.realSourceProvenanceUnavailable)
                }
                continue
            }
            records.append(r)
        }
        guard !issues.contains(.boundaryUnresolved), !issues.contains(.realSourceProvenanceUnavailable),
              !issues.contains(.reconciliationUnresolved) else { return result() }
        if let previous {
            let priorIDs = Set(previous.records.map(\.id))
            let present = Set(snapshot.records.map(\.id))
            let missing = priorIDs.subtracting(present).subtracting(snapshot.deletedRecordIDs)
            let explained = Set((previous.records).compactMap { old -> UUID? in
                guard missing.contains(old.id), hasHigherSyncRevision(old, snapshot.records) else { return nil }
                return old.id
            })
            if !missing.subtracting(explained).isEmpty { issues.insert(.lostVisibility); return result() }
        }
        // A sync identity selects only its unique confirmed highest revision.
        var selected: [WeeklySourceRecord] = []
        let groups = Dictionary(grouping: records) { r -> String? in
            guard let s = r.sourceBundleIdentifier, let id = r.syncIdentifier else { return nil }
            return s + "\u{0}" + id
        }
        selected.append(contentsOf: groups[nil] ?? [])
        for (key, revisions) in groups where key != nil {
            guard revisions.allSatisfy({ ($0.syncVersion ?? -1) >= 0 }),
                  let high = revisions.compactMap(\.syncVersion).max(),
                  revisions.filter({ $0.syncVersion == high }).count == 1,
                  let newest = revisions.first(where: { $0.syncVersion == high }) else {
                issues.insert(.reconciliationUnresolved); return result()
            }
            selected.append(newest)
        }
        let ordered = selected.sorted { $0.start < $1.start }
        for pair in zip(ordered, ordered.dropFirst()) where pair.1.start < pair.0.end {
            issues.insert(.reconciliationUnresolved); return result()
        }
        if ordered.isEmpty, issues.contains(.deletionObserved) { return result(nil, true) }
        if timed {
            guard let target = snapshot.request.binding.selectedDistanceMillimeters else {
                issues.insert(.timedQualificationUnresolved); return result()
            }
            let qualifying = ordered.compactMap { record -> Int64? in
                // Compare the raw whole-workout distance before any floor.
                guard record.value >= Double(target), record.value * 100 <= Double(target) * 102 else { return nil }
                let elapsed = record.end.timeIntervalSince(record.start).rounded(.up)
                guard let seconds = Int64(exactly: elapsed), seconds > 0 else { return nil }
                return seconds
            }
            guard let best = qualifying.min(),
                  let activity = try? ChallengeHealthValue(metric: metric, integerValue: best) else {
                issues.insert(.timedQualificationUnresolved); return result()
            }
            return result(activity, true)
        }
        let total = ordered.reduce(0.0) { $0 + $1.value }
        guard total.isFinite, let value = Int64(exactly: total.rounded(.down)), value > 0,
              let activity = try? ChallengeHealthValue(metric: metric, integerValue: value) else {
            issues.insert(.normalizationUnresolved); return result()
        }
        return result(activity, true)
    }

    static func isWatch(_ value: String?) -> Bool {
        guard let value else { return false }
        let p = value.split(separator: ",", omittingEmptySubsequences: false)
        return p.count == 2 && p[0].hasPrefix("Watch") && digits(p[0].dropFirst(5)) && digits(p[1])
    }
    static func isWorkoutSource(_ value: String?) -> Bool {
        guard let value else { return false }
        return value == "com.apple.health"
            || (value.hasPrefix("com.apple.health.") && value.count > "com.apple.health.".count)
    }
    static func isExplicitlyRejectedSource(_ value: String?) -> Bool {
        value.map { !isWorkoutSource($0) } ?? false
    }
    static func isIPhone(_ value: String?) -> Bool {
        value?.hasPrefix("iPhone") == true
    }
    static func digits(_ value: Substring) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }
    static func hasHigherSyncRevision(_ old: WeeklySourceRecord, _ records: [WeeklySourceRecord]) -> Bool {
        guard let source = old.sourceBundleIdentifier, let sync = old.syncIdentifier, let version = old.syncVersion else { return false }
        return records.contains { $0.sourceBundleIdentifier == source && $0.syncIdentifier == sync && ($0.syncVersion ?? version) > version }
    }
    static func hasRequiredCalendarDayHistory(_ request: ChallengeHealthReadRequest, days: Int) -> Bool {
        guard let zone = TimeZone(identifier: request.queryWindow.timeZoneIdentifier) else { return false }
        var calendar = Calendar(identifier: request.queryWindow.calendar == .gregorian ? .gregorian : .iso8601)
        calendar.timeZone = zone
        guard let start = calendar.date(byAdding: .day, value: -days, to: request.queryWindow.interval.end) else { return false }
        return request.queryWindow.interval.start <= start
    }
}
