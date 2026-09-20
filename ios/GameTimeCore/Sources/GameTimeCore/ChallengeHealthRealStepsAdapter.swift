import Foundation

/// The V1 real-source seam for steps. It deliberately does not reuse the
/// synthetic adapter and requires its separately frozen V1 policy.
///
/// V1 accepts only the adopted Health-system source namespace and the frozen
/// `Watch<digits>,<digits>` product-type grammar. The tuple establishes
/// system-origin on a Watch; device names, manufacturer, and a missing manual
/// marker do not. Product types outside that grammar fail closed. This is a
/// versioned device-family interpretation, not a record of physical testing.
public struct ChallengeHealthAppleWatchStepsAdapter: ChallengeHealthAdapter {
    public let metric = ChallengeHealthMetric.steps
    public init() {}
    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        ChallengeHealthWatchQuantityAdapter(policy: .appleWatchAutomaticStepsV1, scale: 1)
            .evaluate(snapshot, replacing: previous)
    }
}

/// Shared reconciliation mechanics; callers freeze the source/metric and scale.
/// Strict Exercise v1 does not use this accepted quantity seam.
struct ChallengeHealthWatchQuantityAdapter: ChallengeHealthAdapter {
    let policy: ChallengeHealthRealSourcePolicy
    let scale: Double
    var metric: ChallengeHealthMetric { policy.metric }
    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        var issues: Set<ChallengeHealthIssue> = []
        var concerns: Set<WeeklySourceConcern> = []

        func result(_ activity: ChallengeHealthValue? = nil,
                    acceptsReal: Bool = false,
                    permitsIngestion: Bool = false) -> ChallengeHealthEvaluation {
            let readiness: ChallengeHealthReadiness
            let blockers = issues.subtracting([
                .historyLimited, .deletionObserved, .sourceExplicitlyRejected
            ])
            if !blockers.isEmpty { readiness = .staleOrIncomplete }
            else if activity != nil { readiness = .ready }
            else { readiness = .noEligibleDataYet }
            return ChallengeHealthEvaluation(
                readiness: readiness,
                activity: activity,
                evidence: snapshot.evidence,
                issues: issues,
                diagnosticConcerns: concerns,
                syntheticOnly: false,
                acceptsRealSourceObservation: acceptsReal,
                permitsRealConsent: readiness == .ready && acceptsReal
                    && snapshot.request.purpose == .readinessHistory
                    && Self.hasRequiredThirtyCalendarDayHistory(snapshot.request),
                permitsRealIngestion: permitsIngestion,
                supportsConfirmedMiss: false
            )
        }

        guard snapshot.request.binding.metric == metric else {
            issues.insert(.metricMismatch)
            return result()
        }
        guard snapshot.request.binding.realSourcePolicy == policy else {
            issues.insert(.realSourcePolicyMismatch)
            return result()
        }
        if let previous {
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
        let isBoundedSnapshot = snapshot.evidence == .boundedSnapshot
            || snapshot.evidence == .limitedHistory
            || snapshot.evidence == .boundedSnapshotAfterDeletion
        guard isBoundedSnapshot else {
            issues.insert(.incompleteEvidence)
            return result()
        }
        if snapshot.request.purpose == .readinessHistory,
           (snapshot.request.queryWindow.interval.end > snapshot.observedAt
            || snapshot.evidence == .limitedHistory
            || snapshot.earliestAuthorizedSampleDate.map({ $0 > snapshot.request.queryWindow.interval.start }) == true
            || !Self.hasRequiredThirtyCalendarDayHistory(snapshot.request)) {
            issues.insert(.historyLimited)
        }
        if !snapshot.deletedRecordIDs.isEmpty { issues.insert(.deletionObserved) }

        func capture(_ input: ChallengeHealthSnapshot) -> WeeklySourceCapture {
            WeeklySourceCapture(
                accountID: input.request.binding.actorID,
                metric: metric.rawMetric,
                window: input.request.queryWindow.interval,
                observedAt: input.observedAt,
                state: input.evidence == .truncated ? .truncated : .successfulQuery,
                records: input.records
            )
        }
        do {
            concerns = try WeeklySourceFeasibility.assess(
                capture(snapshot),
                replacing: previous.map(capture)
            ).concerns
        } catch {
            issues.insert(.invalidSnapshot)
            return result()
        }
        if concerns.contains(.recordsNoLongerVisible) {
            let oldIDs = Set(previous?.records.map(\.id) ?? [])
            let remainingIDs = Set(snapshot.records.map(\.id))
            let missing = oldIDs.subtracting(remainingIDs).subtracting(snapshot.deletedRecordIDs)
            let superseded: Set<UUID> = Set((previous?.records ?? []).compactMap { prior in
                guard missing.contains(prior.id), Self.hasConfirmedHigherSyncRevision(
                    replacing: prior, in: snapshot.records
                ) else { return nil }
                return prior.id
            })
            if !missing.subtracting(superseded).isEmpty {
                issues.insert(.lostVisibility)
            }
        }
        if snapshot.sourceFreshness == nil { issues.insert(.freshnessUnresolved) }

        // Exact UUID duplicates have been validated by WeeklySourceFeasibility
        // before this pass. Known rejected records are excluded. Unknown
        // provenance blocks the whole observation instead of being guessed.
        // Nil and false manual markers are permitted only after the source
        // revision tuple independently proves the accepted Watch writer.
        var uniqueRecords: [UUID: WeeklySourceRecord] = [:]
        var eligibleRecords: [UUID: WeeklySourceRecord] = [:]
        for record in snapshot.records where uniqueRecords[record.id] == nil {
            uniqueRecords[record.id] = record
            if record.wasUserEntered == true {
                issues.insert(.sourceExplicitlyRejected)
                continue
            }
            guard let source = record.sourceBundleIdentifier, !source.isEmpty,
                  let productType = record.sourceProductType, !productType.isEmpty else {
                issues.insert(.realSourceProvenanceUnavailable)
                continue
            }
            if !Self.isAppleHealthSystemSource(source) || (Self.isIPhoneProductType(productType) || (policy == .appleWatchExerciseCreditV2 && Self.isIdentifiableUnsupportedProduct(productType))) {
                issues.insert(.sourceExplicitlyRejected)
                continue
            }
            guard Self.isAppleWatchProductType(productType) else {
                issues.insert(.realSourceProvenanceUnavailable)
                continue
            }
            guard record.start >= snapshot.request.queryWindow.interval.start,
                  record.end <= snapshot.request.queryWindow.interval.end else {
                issues.insert(.boundaryUnresolved)
                continue
            }
            // Point quantities cannot establish disjoint attribution when two
            // Watches report at the same instant. Never aggregate a positive
            // point sample by guessing which Watch supplied the steps.
            if record.value > 0, record.start == record.end {
                issues.insert(.reconciliationUnresolved)
                continue
            }
            eligibleRecords[record.id] = record
        }
        guard !issues.contains(.realSourceProvenanceUnavailable),
              !issues.contains(.boundaryUnresolved) else {
            return result()
        }
        guard !issues.contains(.reconciliationUnresolved) else { return result() }

        // A source-controlled sync identifier can represent a superseded
        // revision only when every revision has a distinct nonnegative version.
        // Without that proof, reimports stay unresolved and never double count.
        var selected: [WeeklySourceRecord] = []
        let groups = Dictionary(grouping: Array(eligibleRecords.values)) { record -> String? in
            guard let source = record.sourceBundleIdentifier,
                  let syncID = record.syncIdentifier else { return nil }
            return "\(source.utf8.count):\(source)\(syncID)"
        }
        for record in groups[nil] ?? [] { selected.append(record) }
        for (key, revisions) in groups where key != nil {
            guard revisions.allSatisfy({ $0.syncVersion != nil }),
                  let highestVersion = revisions.compactMap(\.syncVersion).max(),
                  revisions.filter({ $0.syncVersion == highestVersion }).count == 1,
                  let latest = revisions.first(where: { $0.syncVersion == highestVersion }) else {
                issues.insert(.reconciliationUnresolved)
                return result()
            }
            selected.append(latest)
        }
        let ordered = selected.sorted {
            $0.start == $1.start ? $0.id.uuidString < $1.id.uuidString : $0.start < $1.start
        }
        var greatestEnd: Date?
        for record in ordered {
            if let greatestEnd, record.start < greatestEnd {
                issues.insert(.reconciliationUnresolved)
                return result()
            }
            greatestEnd = max(greatestEnd ?? record.end, record.end)
        }
        var total = 0.0
        for record in ordered {
            total += record.value
            guard total.isFinite else {
                issues.insert(.normalizationUnresolved)
                return result()
            }
        }
        let floored = (total * scale).rounded(.down)
        let activityValue = Int64(exactly: floored)
        guard floored > 0, let activityValue,
              let activity = try? ChallengeHealthValue(metric: metric, integerValue: activityValue) else {
            // An explicit anchored tombstone is a replacement, even when the
            // now-bounded window has no positive remaining records. A plain
            // empty snapshot still remains an absent observation.
            if issues.contains(.deletionObserved),
               !issues.contains(.lostVisibility),
               !issues.contains(.freshnessUnresolved),
               !issues.contains(.historyLimited) {
                return result(nil, acceptsReal: true, permitsIngestion: true)
            }
            return result()
        }
        let cannotEmit = issues.contains(.lostVisibility)
            || issues.contains(.freshnessUnresolved)
            || issues.contains(.incompleteEvidence)
            || issues.contains(.historyLimited)
        guard !cannotEmit else { return result() }
        // Challenge-window activity may be uploadable even though the separate
        // readiness-history check is not ready. This still cannot confirm a
        // miss or make any external transport run by itself.
        return result(activity, acceptsReal: true, permitsIngestion: true)
    }

    private static func isAppleHealthSystemSource(_ bundleIdentifier: String?) -> Bool {
        bundleIdentifier == "com.apple.health"
            || bundleIdentifier?.hasPrefix("com.apple.health.") == true
    }

    private static func isIdentifiableUnsupportedProduct(_ value: String) -> Bool {
        ["iPad", "iPod", "Mac", "AppleTV", "AudioAccessory", "RealityDevice", "Vision"].contains { value.hasPrefix($0) }
    }

    private static func isIPhoneProductType(_ productType: String) -> Bool {
        productType.hasPrefix("iPhone")
    }

    private static func hasRequiredThirtyCalendarDayHistory(_ request: ChallengeHealthReadRequest) -> Bool {
        let timeZone = TimeZone(identifier: request.queryWindow.timeZoneIdentifier)
        guard let timeZone else { return false }
        var calendar: Calendar
        switch request.queryWindow.calendar {
        case .gregorian: calendar = Calendar(identifier: .gregorian)
        case .iso8601: calendar = Calendar(identifier: .iso8601)
        }
        calendar.timeZone = timeZone
        guard let minimumStart = calendar.date(
            byAdding: .day,
            value: -30,
            to: request.queryWindow.interval.end
        ) else { return false }
        return request.queryWindow.interval.start <= minimumStart
    }

    private static func hasConfirmedHigherSyncRevision(replacing prior: WeeklySourceRecord,
                                                       in records: [WeeklySourceRecord]) -> Bool {
        guard let source = prior.sourceBundleIdentifier,
              let syncID = prior.syncIdentifier,
              let version = prior.syncVersion else { return false }
        return records.contains {
            $0.sourceBundleIdentifier == source
                && $0.syncIdentifier == syncID
                && ($0.syncVersion ?? version) > version
        }
    }

    /// Product type is not an Apple-published closed enum. V1 freezes this
    /// `WatchN,N` device-family grammar and rejects every value outside it.
    private static func isAppleWatchProductType(_ productType: String) -> Bool {
        let components = productType.split(separator: ",", omittingEmptySubsequences: false)
        guard components.count == 2,
              components[0].hasPrefix("Watch"),
              !components[0].dropFirst("Watch".count).isEmpty,
              !components[1].isEmpty else { return false }
        return hasOnlyASCIIDigits(components[0].dropFirst("Watch".count))
            && hasOnlyASCIIDigits(components[1])
    }

    private static func hasOnlyASCIIDigits(_ value: Substring) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }
}
