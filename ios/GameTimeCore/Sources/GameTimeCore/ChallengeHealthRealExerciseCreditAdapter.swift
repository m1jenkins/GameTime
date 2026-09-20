import Foundation

/// New agreements explicitly accept unknown *causal* origin of Apple Exercise
/// credit. Source/device uncertainty, manual markers and reconciliation still
/// obey the frozen Watch rules. This never establishes a confirmed miss.
public struct ChallengeHealthAppleWatchExerciseCreditAdapter: ChallengeHealthAdapter {
    public let metric = ChallengeHealthMetric.exerciseSeconds
    public init() {}
    public func evaluate(_ snapshot: ChallengeHealthSnapshot,
                         replacing previous: ChallengeHealthSnapshot? = nil) -> ChallengeHealthEvaluation {
        // Reconcile raw minutes first, then floor the single total × 60.
        ChallengeHealthWatchQuantityAdapter(policy: .appleWatchExerciseCreditV2, scale: 60)
            .evaluate(snapshot, replacing: previous)
    }
}
