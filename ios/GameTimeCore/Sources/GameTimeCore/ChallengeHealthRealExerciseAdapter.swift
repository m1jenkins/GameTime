import Foundation

/// V1 can read and normalize Apple Exercise Time quantities on the iPhone,
/// but does not accept them. HealthKit exposes no public causal lineage from a
/// quantity sample to the workout or activity that earned it. In particular,
/// it cannot exclude credit derived from manual, imported, or third-party
/// activity. Keep this explicit unavailable result separate from a read error.
public struct ChallengeHealthAppleWatchExerciseAdapter: ChallengeHealthAdapter {
    public let metric = ChallengeHealthMetric.exerciseSeconds

    public init() {}

    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        var issues: Set<ChallengeHealthIssue> = [.exerciseCausalLineageUnavailable]
        var concerns: Set<WeeklySourceConcern> = []
        guard snapshot.request.binding.metric == metric,
              snapshot.request.binding.realSourcePolicy == .appleWatchExerciseV1 else {
            issues.insert(.realSourcePolicyMismatch)
            return unavailable(snapshot, issues, concerns)
        }
        guard snapshot.evidence == .boundedSnapshot || snapshot.evidence == .limitedHistory
                || snapshot.evidence == .boundedSnapshotAfterDeletion,
              snapshot.observedAt.timeIntervalSince1970.isFinite,
              snapshot.sourceFreshness.map({ $0 <= snapshot.observedAt }) ?? true,
              Set(snapshot.records.map(\.id)).isDisjoint(with: snapshot.deletedRecordIDs) else {
            issues.insert(.invalidSnapshot)
            return unavailable(snapshot, issues, concerns)
        }
        if let previous, (previous.request.binding != snapshot.request.binding
            || previous.request.queryWindow != snapshot.request.queryWindow
            || previous.request.purpose != snapshot.request.purpose
            || previous.observedAt > snapshot.observedAt) {
            issues.insert(.invalidSnapshot)
            return unavailable(snapshot, issues, concerns)
        }

        let capture = WeeklySourceCapture(accountID: snapshot.request.binding.actorID,
                                          metric: metric.rawMetric,
                                          window: snapshot.request.queryWindow.interval,
                                          observedAt: snapshot.observedAt,
                                          state: snapshot.evidence == .truncated ? .truncated : .successfulQuery,
                                          records: snapshot.records)
        do {
            concerns = try WeeklySourceFeasibility.assess(capture, replacing: previous.map {
                WeeklySourceCapture(accountID: $0.request.binding.actorID, metric: metric.rawMetric,
                                    window: $0.request.queryWindow.interval, observedAt: $0.observedAt,
                                    state: $0.evidence == .truncated ? .truncated : .successfulQuery,
                                    records: $0.records)
            }).concerns
        } catch {
            issues.insert(.invalidSnapshot)
            return unavailable(snapshot, issues, concerns)
        }
        if concerns.contains(.recordsNoLongerVisible) { issues.insert(.lostVisibility) }

        for record in snapshot.records {
            guard record.metric == metric.rawMetric,
                  record.value.isFinite, record.value >= 0,
                  record.start >= snapshot.request.queryWindow.interval.start,
                  record.end <= snapshot.request.queryWindow.interval.end else {
                issues.insert(.normalizationUnresolved)
                continue
            }
            if record.value > 0 && record.start == record.end {
                issues.insert(.reconciliationUnresolved)
            }
            guard let source = record.sourceBundleIdentifier,
                  let product = record.sourceProductType else {
                issues.insert(.realSourceProvenanceUnavailable)
                continue
            }
            if record.wasUserEntered == true || !isHealthSource(source) || product.hasPrefix("iPhone") {
                issues.insert(.sourceExplicitlyRejected)
            } else if !isWatchProduct(product) {
                issues.insert(.realSourceProvenanceUnavailable)
            }
            // Normalization is intentionally exercised even though the
            // unavailable policy never exposes a value.
            // The retained local record type explicitly carries minutes.
            // Convert once before flooring the proposed normalized seconds.
            let floored = (record.value * 60).rounded(.down)
            if Int64(exactly: floored) == nil { issues.insert(.normalizationUnresolved) }
        }
        return unavailable(snapshot, issues, concerns)
    }

    private func unavailable(_ snapshot: ChallengeHealthSnapshot, _ issues: Set<ChallengeHealthIssue>,
                             _ concerns: Set<WeeklySourceConcern>) -> ChallengeHealthEvaluation {
        ChallengeHealthEvaluation(readiness: .unsupported, activity: nil, evidence: snapshot.evidence,
                                  issues: issues, diagnosticConcerns: concerns, syntheticOnly: false,
                                  acceptsRealSourceObservation: false, permitsRealConsent: false,
                                  permitsRealIngestion: false, supportsConfirmedMiss: false)
    }

    private func isHealthSource(_ value: String) -> Bool {
        value == "com.apple.health" || value.hasPrefix("com.apple.health.")
    }
    private func isWatchProduct(_ value: String) -> Bool {
        let parts = value.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].hasPrefix("Watch") else { return false }
        return asciiDigits(parts[0].dropFirst(5)) && asciiDigits(parts[1])
    }
    private func asciiDigits(_ value: Substring) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { (48...57).contains($0.value) }
    }
}
