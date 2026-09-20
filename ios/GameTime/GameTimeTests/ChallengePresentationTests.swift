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
    func testReceivedScoreRanksSavedPartialValuesWithUnknownAndLateUnranked() throws {
        for metric in ChallengeV1Policy.Metric.allCases {
            let policy = "friend_\(metric.rawValue)_leaderboard_v2"
            let template = challenge(policy, [])
            let at = template.config.correctionsBy
            let values: [Int?] = [100, 40, nil, 9999]
            let members = values.enumerated().map { index, value in
                ChallengeV1.Member(actorId: UUID(), username: "Person", target: nil, selected: true, exited: false, consented: true,
                    fact: .init(value: value, state: value == nil ? "unresolved" : "value",
                        recordedAt: index == 3 ? .init(date: at.date.addingTimeInterval(1)) : at, revision: 1))
            }
            var row = challenge(policy, members)
            row.sourcePolicyVersion = ChallengeHealthBindingMapper.selectedSource(metric)?.identifier
            let expected = metric == .timed ? [2, 1, nil, nil] : [1, 2, nil, nil]
            XCTAssertEqual(members.map { ChallengePresentation.rank($0, in: row, actor: nil) }, expected)
            XCTAssertNil(row.savedScore(members[2])); XCTAssertNil(row.savedScore(members[3]))
            XCTAssertTrue(row.format.missing.contains("unranked"))
            XCTAssertNil(ChallengeV1Suggestion.value(policy: row.format, days: 7, eligible28DayTotal: 100, best90DayElapsedSeconds: 100))
        }
        XCTAssertNil(ChallengeV1Policy(rawValue: "personal_steps_leaderboard_v2"))
        XCTAssertNil(ChallengeV1Policy(rawValue: "friend_steps_goal_v2"))
        XCTAssertFalse(ChallengeV1Policy(rawValue: "friend_steps_leaderboard_v1")!.usesReceivedScores)
    }
    func testVoidResultKeepsServerSavedScoreVisibleWithoutRankingIt() throws {
        let actor = UUID()
        let template = challenge("friend_steps_leaderboard_v2", [])
        let own = ChallengeV1.Member(actorId: actor, username: "You", target: nil, selected: true, exited: false, consented: true,
            fact: .init(value: 40, state: "value", recordedAt: template.config.correctionsBy, revision: 1))
        let final = ChallengeV1.Final(recordedAt: template.config.correctionsBy,
            result: .init(outcome: "void", participants: [actor.uuidString.lowercased(): .init(status: "void", returnedCents: 2000)],
                own: nil, entryCents: 2000, unallocatedCents: 0, simulation: "nonredeemable"))
        var row = challenge("friend_steps_leaderboard_v2", [own], final: final)
        row.sourcePolicyVersion = "apple_watch_steps_v1"
        XCTAssertEqual(row.savedScore(own), 40, "A void does not erase the score the server saved")
        XCTAssertNil(ChallengePresentation.rank(own, in: row, actor: actor))
    }
    private func member(_ actor: UUID, _ value: Int?, state: String = "complete", exited: Bool = false, target: Int? = nil) -> ChallengeV1.Member {
        .init(actorId: actor, username: "Fictional person", target: target, selected: true, exited: exited, consented: true,
              fact: .init(value: value, state: state, recordedAt: .init(date: Date()), revision: 1))
    }
    private func challenge(_ policy: String, _ members: [ChallengeV1.Member], final: ChallengeV1.Final? = nil) -> ChallengeV1 {
        let start = ChallengeInstant(date: Date(timeIntervalSince1970: 1788757200))
        let end = ChallengeInstant(date: start.date.addingTimeInterval(7 * 86400))
        return .init(id: UUID(), creatorId: members.first?.id, policy: policy,
                     config: .init(startDate: "2026-09-07", days: 7, timezone: "America/Chicago", amountCents: 2000,
                                   distanceMm: policy.contains("timed") ? 1_000_000 : nil,
                                   startsAt: start, endsAt: end, syncBy: end, correctionsBy: end, noticeDue: end),
                     status: "active", revision: 1, agreementVersion: 1, serverTime: start, socialHidden: false,
                     agreement: nil, members: members, notice: nil, reviews: [], final: final)
    }
}
