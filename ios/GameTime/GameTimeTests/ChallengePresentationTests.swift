import XCTest
@testable import GameTime

final class ChallengePresentationTests: XCTestCase {
    func testUnknownAndDepartedActivityCannotBecomeARankOrProgress() {
        let actor = UUID()
        let unresolved = member(actor, 80, state: "unresolved")
        let departed = member(UUID(), 200, exited: true)
        let complete = member(UUID(), 100)
        let row = challenge("friend_steps_leaderboard_v1", [unresolved, departed, complete])
        XCTAssertNil(ChallengePresentation.value(unresolved, actor: actor))
        XCTAssertNil(ChallengePresentation.rank(unresolved, in: row, actor: actor))
        XCTAssertNil(ChallengePresentation.value(departed, actor: actor))
        XCTAssertNil(ChallengePresentation.rank(departed, in: row, actor: actor))
        XCTAssertEqual(ChallengePresentation.rank(complete, in: row, actor: actor), 1)
        XCTAssertNil(ChallengePresentation.progress(unresolved, in: challenge("personal_steps_goal_v1", [unresolved]), actor: actor))
    }
    func testTiesShareRankAndTimedRunsSortLowerFirst() {
        let people = [member(UUID(), 350), member(UUID(), 350), member(UUID(), 400)]
        let timed = challenge("friend_timed_leaderboard_v1", people)
        XCTAssertEqual(people.map { ChallengePresentation.rank($0, in: timed, actor: nil) }, [1, 1, 3])
        let steps = challenge("friend_steps_leaderboard_v1", people)
        XCTAssertEqual(people.map { ChallengePresentation.rank($0, in: steps, actor: nil) }, [2, 2, 1])
    }
    func testOnlyCumulativeGoalsHaveProgressAndZeroIsDistinctFromMissing() {
        let actor = UUID()
        let own = member(actor, 95 * 60, target: 150 * 60)
        let exercise = challenge("personal_exercise_goal_v1", [own])
        XCTAssertEqual(ChallengePresentation.progress(own, in: exercise, actor: actor)!, 95.0 / 150, accuracy: 0.00001)
        XCTAssertNil(ChallengePresentation.progress(own, in: challenge("personal_timed_goal_v1", [own]), actor: actor))
        XCTAssertNil(ChallengePresentation.progress(own, in: challenge("friend_exercise_leaderboard_v1", [own]), actor: actor))
        let zero = member(actor, 0, target: 100)
        XCTAssertEqual(ChallengePresentation.progress(zero, in: challenge("personal_steps_goal_v1", [zero]), actor: actor), 0)
        let corrected = member(actor, 30, target: 100)
        XCTAssertEqual(ChallengePresentation.progress(corrected, in: challenge("personal_steps_goal_v1", [corrected]), actor: actor), 0.3)
    }
    private func member(_ actor: UUID, _ value: Int?, state: String = "complete", exited: Bool = false, target: Int? = nil) -> ChallengeV1.Member {
        .init(actorId: actor, username: "Fictional person", target: target, selected: true, exited: exited, consented: true,
              fact: .init(value: value, state: state, recordedAt: .init(date: Date()), revision: 1))
    }
    private func challenge(_ policy: String, _ members: [ChallengeV1.Member]) -> ChallengeV1 {
        let start = ChallengeInstant(date: Date(timeIntervalSince1970: 1788757200))
        let end = ChallengeInstant(date: start.date.addingTimeInterval(7 * 86400))
        return .init(id: UUID(), creatorId: members.first?.id, policy: policy,
                     config: .init(startDate: "2026-09-07", days: 7, timezone: "America/Chicago", amountCents: 2000,
                                   distanceMm: policy.contains("timed") ? 1_000_000 : nil,
                                   startsAt: start, endsAt: end, syncBy: end, correctionsBy: end, noticeDue: end),
                     status: "active", revision: 1, agreementVersion: 1, serverTime: start, socialHidden: false,
                     agreement: nil, members: members, notice: nil, reviews: [], final: nil)
    }
}
