#if DEBUG
import XCTest
@testable import GameTime

@MainActor
final class LiveChallengePresentationTests: XCTestCase {
    private let actor = LiveDesignFixtures.actorID

    func testMissingUnconfirmedAndSavedZeroStayDistinct() async throws {
        let original = try await active()
        let unknown = replacing(original, members: [member(target: 20_000_000, fact: nil)])
        XCTAssertEqual(LiveChallengePresentation.state(unknown, actor: actor), "No update yet")
        XCTAssertNil(LiveChallengePresentation.progress(unknown, actor: actor))
        XCTAssertEqual(LiveChallengePresentation.remaining(unknown, actor: actor), "Waiting for activity")
        XCTAssertEqual(LiveChallengePresentation.value(nil, metric: .distance), "—")

        let unconfirmed = replacing(original, members: [member(target: 20_000_000,
            fact: .init(value: 6_400_000, state: "missing", recordedAt: original.serverTime, revision: 1))])
        XCTAssertNil(unconfirmed.savedScore(try XCTUnwrap(unconfirmed.own(actor))))
        XCTAssertEqual(LiveChallengePresentation.state(unconfirmed, actor: actor), "No update yet")
        XCTAssertNil(LiveChallengePresentation.progress(unconfirmed, actor: actor))

        let zero = replacing(original, members: [member(target: 20_000_000,
            fact: .init(value: 0, state: "value", recordedAt: original.serverTime, revision: 1))])
        XCTAssertEqual(zero.savedScore(try XCTUnwrap(zero.own(actor))), 0)
        XCTAssertEqual(LiveChallengePresentation.progress(zero, actor: actor), 0)
        XCTAssertEqual(LiveChallengePresentation.remaining(zero, actor: actor), "20 km to go")
        XCTAssertNotEqual(LiveChallengePresentation.state(zero, actor: actor), "No update yet")
        XCTAssertNotEqual(LiveChallengePresentation.state(zero, actor: actor), "Missed")
    }

    func testRealPartialOrOldSavedActivityDoesNotEstablishBehind() async throws {
        let original = try await active()
        // Use a non-fixture ID: the approved fictional screenshot may explicitly
        // demonstrate a pace estimate; ordinary partial Health data may not.
        let partial = replacing(original, id: UUID(), members: [member(target: 20_000_000,
            fact: .init(value: 1_200_000, state: "value", recordedAt: original.serverTime, revision: 1))])
        XCTAssertNotEqual(LiveChallengePresentation.state(partial, actor: actor), "Behind")
        let old = replacing(original, id: UUID(), members: [member(target: 20_000_000,
            fact: .init(value: 1_200_000, state: "value", recordedAt: original.config.startsAt, revision: 1))])
        XCTAssertNotEqual(LiveChallengePresentation.state(old, actor: actor), "Behind")
        let reached = replacing(original, id: UUID(), members: [member(target: 20_000_000,
            fact: .init(value: 22_000_000, state: "value", recordedAt: original.serverTime, revision: 1))])
        XCTAssertEqual(LiveChallengePresentation.state(reached, actor: actor), "Done")
        XCTAssertEqual(LiveChallengePresentation.progress(reached, actor: actor), 1)
        XCTAssertEqual(LiveChallengePresentation.remaining(reached, actor: actor), "Goal reached")
    }

    func testOnlyFinalOwnResultCanBePresentedAsMissed() async throws {
        let original = try await active()
        let missed = allocation("missed")
        let notice = ChallengeV1.Notice(revision: 1, recordedAt: original.serverTime,
            reviewBy: .init(date: original.serverTime.date.addingTimeInterval(48 * 3_600)), result: missed)
        let provisional = replacing(original, status: "review", notice: notice)
        XCTAssertEqual(LiveChallengePresentation.state(provisional, actor: actor), "In review")
        XCTAssertEqual(LiveChallengePresentation.outcome(provisional, actor: actor), "In review")
        let final = replacing(original, status: "final", final: .init(recordedAt: original.serverTime, result: missed))
        XCTAssertEqual(LiveChallengePresentation.outcome(final, actor: actor), "Missed")
        let void = replacing(original, status: "void")
        XCTAssertEqual(LiveChallengePresentation.outcome(void, actor: actor), "Didn’t count")
        let exited = replacing(final, members: [member(target: 20_000_000, fact: nil, exited: true)])
        XCTAssertEqual(LiveChallengePresentation.outcome(exited, actor: actor), "Closed early")
    }

    func testTimedGoalIsStrictAndDoesNotUseDistanceProgress() async throws {
        let original = try await active()
        let window = ChallengeV1.Window(startDate: original.config.startDate, days: original.config.days,
            timezone: original.config.timezone, amountCents: original.config.amountCents, distanceMm: 5_000_000,
            startsAt: original.config.startsAt, endsAt: original.config.endsAt, syncBy: original.config.syncBy,
            correctionsBy: original.config.correctionsBy, noticeDue: original.config.noticeDue)
        let equal = replacing(original, policy: "personal_timed_goal_v1", config: window, members: [member(target: 1_800,
            fact: .init(value: 1_800, state: "value", recordedAt: original.serverTime, revision: 1))])
        XCTAssertEqual(LiveChallengePresentation.state(equal, actor: actor), "In progress")
        XCTAssertEqual(LiveChallengePresentation.remaining(equal, actor: actor), "Time includes pauses")
        XCTAssertNil(LiveChallengePresentation.progress(equal, actor: actor))
        let faster = replacing(equal, members: [member(target: 1_800,
            fact: .init(value: 1_799, state: "value", recordedAt: original.serverTime, revision: 1))])
        XCTAssertEqual(LiveChallengePresentation.state(faster, actor: actor), "Goal reached")
        XCTAssertEqual(LiveChallengePresentation.value(1_799, metric: .timed), "29:59")
    }

    func testAgreedTargetLabelsPreserveDistanceAndSecondPrecision() async throws {
        let original = try await active()
        let preciseDistance = replacing(original, members: [member(target: 1_234_567, fact: nil)])
        XCTAssertEqual(LiveChallengePresentation.goal(preciseDistance, actor: actor), "1.234567 km goal")
        let smallestDistance = replacing(original, members: [member(target: 1, fact: nil)])
        XCTAssertEqual(LiveChallengePresentation.goal(smallestDistance, actor: actor), "0.000001 km goal")
        let minutes = replacing(original, policy: "personal_exercise_goal_v1", members: [member(target: 62, fact: nil)])
        XCTAssertEqual(LiveChallengePresentation.goal(minutes, actor: actor), "1 min 2 sec goal")
        XCTAssertEqual(LiveChallengePresentation.ends(original), "Ends Sunday")
    }

    func testLoadedRecordScopeDoesNotTurnMissingPagesIntoZeroOrACompleteTotal() async throws {
        let client = LiveDesignFixtureClient()
        let rows = try await client.list(actor: actor)
        var pages = Dictionary(uniqueKeysWithValues: ChallengeV1Section.allCases.map { section in
            (section, ChallengeV1SectionState(rows: rows.filter { section.includes($0, actor: actor) },
                cursor: nil, projectionRevision: UUID(), serverTime: LiveDesignFixtures.now,
                receivedAt: 100, error: nil, fresh: true))
        })
        let complete = ChallengeProfileSnapshot(actor: actor, sections: pages, now: 100)
        XCTAssertEqual(complete.finished.count, 3)
        XCTAssertEqual(complete.countText(complete.finished.count), "3")
        XCTAssertEqual(LiveChallengePresentation.goalsMet(in: complete), 2)
        XCTAssertEqual(complete.countText(LiveChallengePresentation.goalsMet(in: complete)), "2")
        pages[.history]?.cursor = .object(["page": .integer(2)])
        let partial = ChallengeProfileSnapshot(actor: actor, sections: pages, now: 100)
        XCTAssertEqual(partial.countText(partial.finished.count), "3+")
        XCTAssertEqual(partial.countText(0), "—")
        pages[.history]?.fresh = false
        let stale = ChallengeProfileSnapshot(actor: actor, sections: pages, now: 100)
        XCTAssertEqual(stale.countText(stale.finished.count), "—")
        let switched = ChallengeProfileSnapshot(actor: UUID(), sections: pages, now: 100)
        XCTAssertTrue(switched.rows.isEmpty)
    }

    func testGoalsMetRequiresOwnExplicitFinalGoalOutcomeAndContinuedParticipation() async throws {
        let original = try await active()
        let confirmed = ChallengeV1.Final(recordedAt: original.serverTime, result: allocation("met"))
        let ownOnly = ChallengeV1.Final(recordedAt: original.serverTime,
            result: .init(outcome: "scored", participants: nil, own: .init(status: "met", returnedCents: 2_000),
                          entryCents: 2_000, unallocatedCents: 0, simulation: "nonredeemable"))
        let otherOnly = ChallengeV1.Final(recordedAt: original.serverTime,
            result: .init(outcome: "scored", participants: [LiveDesignFixtures.samID.uuidString.lowercased(): .init(status: "met", returnedCents: 2_000)],
                          own: nil, entryCents: 2_000, unallocatedCents: 0, simulation: "nonredeemable"))
        let rows = [
            replacing(original, id: UUID(), status: "final", final: confirmed),
            replacing(original, id: UUID(), status: "final", members: [member(target: 20_000_000, fact: nil, selected: false)], final: confirmed),
            replacing(original, id: UUID(), status: "final", members: [member(target: 20_000_000, fact: nil, consented: false)], final: confirmed),
            replacing(original, id: UUID(), status: "final", members: [member(target: 20_000_000, fact: nil, exited: true)], final: confirmed),
            replacing(original, id: UUID(), status: "final"),
            replacing(original, id: UUID(), status: "void", final: confirmed),
            replacing(original, id: UUID(), status: "final", final: otherOnly),
            replacing(original, id: UUID(), status: "final", final: ownOnly),
            replacing(original, id: UUID(), status: "final", final: ownOnly, socialHidden: true),
            replacing(original, id: UUID(), policy: "friend_distance_leaderboard_v1", status: "final", final: confirmed)
        ]
        let pages = Dictionary(uniqueKeysWithValues: ChallengeV1Section.allCases.map { section in
            (section, ChallengeV1SectionState(rows: section == .history ? rows : [],
                cursor: nil, projectionRevision: UUID(), serverTime: original.serverTime,
                receivedAt: 100, error: nil, fresh: true))
        })
        let snapshot = ChallengeProfileSnapshot(actor: actor, sections: pages, now: 100)
        XCTAssertEqual(snapshot.finished.count, rows.count)
        XCTAssertEqual(LiveChallengePresentation.goalsMet(in: snapshot), 2,
                       "Only the ordinary own met result and the private own-result projection qualify")
    }

    private func active() async throws -> ChallengeV1 {
        try await LiveDesignFixtureClient().detail(LiveDesignFixtures.activeID, actor: actor)
    }
    private func member(target: Int?, fact: ChallengeV1.Fact?, exited: Bool = false,
                        selected: Bool = true, consented: Bool = true) -> ChallengeV1.Member {
        .init(actorId: actor, username: "alexlee", target: target, selected: selected, exited: exited, consented: consented, fact: fact)
    }
    private func allocation(_ status: String) -> ChallengeV1.Allocation {
        .init(outcome: "scored", participants: [actor.uuidString.lowercased(): .init(status: status, returnedCents: status == "met" ? 2_000 : 0)],
              own: nil, entryCents: 2_000, unallocatedCents: status == "met" ? 0 : 2_000, simulation: "nonredeemable")
    }
    private func replacing(_ row: ChallengeV1, id: UUID? = nil, policy: String? = nil, config: ChallengeV1.Window? = nil,
                           status: String? = nil, members: [ChallengeV1.Member]? = nil,
                           notice: ChallengeV1.Notice? = nil, final: ChallengeV1.Final? = nil,
                           socialHidden: Bool? = nil) -> ChallengeV1 {
        .init(sourcePolicyVersion: row.sourcePolicyVersion, counts: row.counts, id: id ?? row.id, creatorId: row.creatorId,
              policy: policy ?? row.policy, config: config ?? row.config, status: status ?? row.status,
              revision: row.revision, agreementVersion: row.agreementVersion, serverTime: row.serverTime,
              socialHidden: socialHidden ?? row.socialHidden, agreement: row.agreement, members: members ?? row.members,
              notice: notice, reviews: row.reviews, final: final)
    }
}
#endif
