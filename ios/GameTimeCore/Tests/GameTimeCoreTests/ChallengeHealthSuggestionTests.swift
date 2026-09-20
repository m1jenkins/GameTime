import Testing
@testable import GameTimeCore

@Suite("Challenge Health local suggestions")
struct ChallengeHealthSuggestionTests {
    @Test("steps use the adopted 28-day scaling and upward rounding")
    func personalSteps() {
        #expect(ChallengeHealthSuggestions.personalSteps(
            totalOverTwentyEightDays: 28_001,
            requestedCalendarDays: 7
        ) == 7_701)
        #expect(ChallengeHealthSuggestions.personalExerciseSeconds(
            totalOverTwentyEightDays: 28_001, requestedCalendarDays: 7
        ) == 7_701)
    }

    @Test("ranking has no suggestion and invalid inputs fail closed")
    func noLeaderboardSuggestion() {
        #expect(ChallengeHealthSuggestions.leaderboardSteps() == nil)
        #expect(ChallengeHealthSuggestions.personalSteps(
            totalOverTwentyEightDays: -1, requestedCalendarDays: 7
        ) == nil)
    }

    @Test("running uses 28-day scaling and timed uses a floor of the best comparable run")
    func runningSuggestions() {
        #expect(ChallengeHealthSuggestions.personalCumulativeRunningMillimeters(
            totalOverTwentyEightDays: 28_001, requestedCalendarDays: 7
        ) == 7_701)
        #expect(ChallengeHealthSuggestions.personalTimedRunSeconds(bestComparableSeconds: 601) == 570)
        #expect(ChallengeHealthSuggestions.personalTimedRunSeconds(bestComparableSeconds: 0) == nil)
    }
}
