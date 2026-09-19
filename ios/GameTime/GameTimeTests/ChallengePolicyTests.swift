import XCTest
@testable import GameTime

final class ChallengePolicyTests: XCTestCase {
    func testCanonicalUnitsAndStrictInputBounds() {
        XCTAssertEqual(ChallengeV1Policy.all.count, 13)
        XCTAssertEqual(Set(ChallengeV1Policy.all.map(\.id)).count, 13)
        XCTAssertNil(ChallengeV1Policy(rawValue: "personal_timed_leaderboard_v1"))
        XCTAssertEqual(ChallengeV1Policy.Metric.distance.parse("1.609344"), 1_609_344)
        XCTAssertEqual(ChallengeV1Policy.Metric.distance.display(1_609_344), "1.609344 km")
        XCTAssertNil(ChallengeV1Policy.Metric.distance.parse("1.0000001"))
        XCTAssertEqual(ChallengeV1Policy.Metric.exercise.parse("300:59"), 18_059)
        XCTAssertEqual(ChallengeV1Policy.Metric.timed.parse("6:00"), 360)
        XCTAssertNil(ChallengeV1Policy.Metric.timed.parse("6:60"))
        XCTAssertNil(ChallengeV1Policy.Metric.steps.parse("1.5"))
        XCTAssertNil(ChallengeV1Policy.Metric.steps.parse("0"))
    }
    func testOnDeviceSuggestionUsesExactRoundingAndNeverLeaderboards() {
        for policy in ChallengeV1Policy.all {
            let value = ChallengeV1Suggestion.value(policy: policy, days: 7, eligible28DayTotal: 101, best90DayElapsedSeconds: 361)
            XCTAssertEqual(value, !policy.hasTarget || policy.mode == .community ? nil : policy.metric == .timed ? 353 : 28)
            XCTAssertNil(ChallengeV1Suggestion.value(policy: policy, days: 7, eligible28DayTotal: nil, best90DayElapsedSeconds: nil))
        }
    }
    func testInvitationParserRejectsAmbiguousAndHostedLocators() {
        let links = ChallengeInvitation()
        let token = String(repeating: "a", count: 64)
        XCTAssertEqual(links.token(from: "gametime-beta://challenge-invite/" + token), token)
        for prefix in ["https://example.com/", "gametime-beta://user@challenge-invite/", "gametime-beta://challenge-invite:12/", "gametime-beta://other/"] {
            XCTAssertNil(links.token(from: prefix + token))
        }
        XCTAssertNil(links.token(from: "gametime-beta://challenge-invite/" + token + "?redirect=1"))
    }
    #if DEBUG
    @MainActor func testInvitationSurvivesRelaunchWithoutFetchingDetails() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = ChallengeInvitationIntent(directory: directory)
        let url = try XCTUnwrap(URL(string: "gametime-beta://challenge-invite/" + String(repeating: "b", count: 64)))
        first.receive(url)
        XCTAssertEqual(ChallengeInvitationIntent(directory: directory).link, url.absoluteString)
        first.clear()
        XCTAssertTrue(ChallengeInvitationIntent(directory: directory).link.isEmpty)
    }
    #endif
}
