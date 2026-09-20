import Foundation

/// Local planning suggestions are deliberately separate from eligibility,
/// readiness, source acceptance, and any result. They never create a fact or
/// a leaderboard recommendation.
public enum ChallengeHealthSuggestions {
    /// The adopted Personal steps suggestion: 28-day total scaled to the
    /// requested calendar-day count with a 10% buffer, rounded upward.
    public static func personalSteps(totalOverTwentyEightDays: Int64,
                                     requestedCalendarDays: Int) -> Int64? {
        guard totalOverTwentyEightDays >= 0, requestedCalendarDays > 0 else { return nil }
        let suggestion = (Double(totalOverTwentyEightDays) * Double(requestedCalendarDays) / 28 * 1.10)
            .rounded(.up)
        guard suggestion.isFinite, suggestion <= Double(Int64.max) else { return nil }
        return Int64(exactly: suggestion)
    }

    /// Ranking contexts receive no local target suggestion.
    public static func leaderboardSteps() -> Int64? { nil }

    /// Exercise Time uses the same local 28-day planning formula. Its source
    /// policy remains unavailable; this never creates a Health observation.
    public static func personalExerciseSeconds(totalOverTwentyEightDays: Int64,
                                               requestedCalendarDays: Int) -> Int64? {
        personalSteps(totalOverTwentyEightDays: totalOverTwentyEightDays,
                      requestedCalendarDays: requestedCalendarDays)
    }

    /// Cumulative outdoor-running suggestions use the same adopted 28-day
    /// scaling as steps and remain local planning only.
    public static func personalCumulativeRunningMillimeters(totalOverTwentyEightDays: Int64,
                                                            requestedCalendarDays: Int) -> Int64? {
        personalSteps(totalOverTwentyEightDays: totalOverTwentyEightDays,
                      requestedCalendarDays: requestedCalendarDays)
    }

    /// A timed-run suggestion uses the best comparable whole workout in the
    /// preceding 90-day history, with a five-percent improvement buffer.
    public static func personalTimedRunSeconds(bestComparableSeconds: Int64) -> Int64? {
        guard bestComparableSeconds > 0 else { return nil }
        let suggestion = (Double(bestComparableSeconds) * 0.95).rounded(.down)
        guard suggestion.isFinite, suggestion > 0, suggestion <= Double(Int64.max) else { return nil }
        return Int64(exactly: suggestion)
    }
}
