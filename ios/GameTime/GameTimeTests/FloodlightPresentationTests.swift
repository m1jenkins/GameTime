#if DEBUG
import XCTest

@testable import GameTime

/// What the Floodlight friend-goal screens say and count, from saved rows only.
/// Strings are COPY.md's "Friend-goal pot and Floodlight screens" rows.
@MainActor final class FloodlightPresentationTests: XCTestCase {
    private let you = LiveDesignFixtures.actorID
    private var active: ChallengeV1 { LiveDesignFixtureClient.seedRow(LiveDesignFixtures.activeID)! }
    private var invitation: ChallengeV1 { LiveDesignFixtureClient.seedRow(LiveDesignFixtures.invitationID)! }

    private func copy(_ row: ChallengeV1, policy: String? = nil, status: String? = nil,
                      members: [ChallengeV1.Member]? = nil) -> ChallengeV1 {
        .init(sourcePolicyVersion: row.sourcePolicyVersion, counts: row.counts, id: row.id, creatorId: row.creatorId,
              policy: policy ?? row.policy, config: row.config, status: status ?? row.status, revision: row.revision,
              agreementVersion: row.agreementVersion, serverTime: row.serverTime, socialHidden: row.socialHidden,
              agreement: row.agreement, members: members ?? row.members, notice: row.notice, reviews: row.reviews, final: row.final)
    }
    private func member(_ source: ChallengeV1.Member, value: Int? = nil, at: Date? = nil, consented: Bool? = nil,
                        exited: Bool? = nil, target: Int? = nil) -> ChallengeV1.Member {
        .init(actorId: source.actorId, username: source.username, target: target ?? source.target, selected: source.selected,
              exited: exited ?? source.exited, consented: consented ?? source.consented,
              fact: value.map { .init(value: $0, state: "value", recordedAt: .init(date: at ?? Date()), revision: 1) } ?? source.fact)
    }
    private func withFact(_ row: ChallengeV1, _ id: UUID, value: Int, secondsAgo: TimeInterval) -> ChallengeV1 {
        copy(row, members: row.members.map { $0.actorId == id ? member($0, value: value, at: row.serverTime.date.addingTimeInterval(-secondsAgo)) : $0 })
    }

    func testOnlyProductSupportedStatesGetTheFloodlightPages() {
        XCTAssertEqual(FloodlightChallengeFacts.layout(active, actor: you), .challenge)
        XCTAssertEqual(FloodlightChallengeFacts.layout(copy(active, status: "syncing"), actor: you), .challenge)
        XCTAssertEqual(FloodlightChallengeFacts.layout(invitation, actor: you), .invitation)
        let agreed = copy(invitation, members: invitation.members.map { member($0, consented: true) })
        XCTAssertEqual(FloodlightChallengeFacts.layout(agreed, actor: you), .legacy, "Waiting for the group keeps its page")
        XCTAssertEqual(FloodlightChallengeFacts.layout(copy(active, status: "review"), actor: you), .legacy)
        XCTAssertEqual(FloodlightChallengeFacts.layout(copy(active, status: "final"), actor: you), .legacy)
        XCTAssertEqual(FloodlightChallengeFacts.layout(copy(active, policy: "friend_distance_leaderboard_v1",
            members: active.members.map { .init(actorId: $0.actorId, username: $0.username, target: nil, selected: true, exited: false, consented: true, fact: $0.fact) }), actor: you), .legacy)
        let left = copy(active, members: active.members.map { $0.actorId == you ? member($0, exited: true) : $0 })
        XCTAssertEqual(FloodlightChallengeFacts.layout(left, actor: you), .legacy)
        XCTAssertEqual(FloodlightChallengeFacts.layout(active, actor: UUID()), .legacy)
        XCTAssertEqual(FloodlightChallengeFacts.layout(LiveDesignFixtureClient.seedRow(LiveDesignFixtures.runsID)!, actor: you), .legacy)
    }

    func testThePotCountsOnlyPeopleWhoAgreedAndAreStillIn() {
        XCTAssertEqual(FloodlightChallengeFacts.potCents(active), 8_000)
        XCTAssertEqual(FloodlightChallengeFacts.potSpoken(active), "Pot: $80 in simulated stakes, $20 each.")
        XCTAssertEqual(FloodlightChallengeFacts.potCents(invitation), 2_000, "Only Jordan has agreed")
        let someoneLeft = copy(active, members: active.members.map { $0.actorId == LiveDesignFixtures.jordanID ? member($0, exited: true) : $0 })
        XCTAssertEqual(FloodlightChallengeFacts.potCents(someoneLeft), 6_000)
        XCTAssertFalse(FloodlightChallengeFacts.people(someoneLeft, actor: you).contains { $0.actorId == LiveDesignFixtures.jordanID })
        XCTAssertEqual(FloodlightChallengeFacts.slots(someoneLeft, actor: you)[LiveDesignFixtures.priyaID], 3, "Colors never shift when someone leaves")
    }

    func testRosterSlotsPutYouFirstAndKeepRosterOrder() {
        let slots = FloodlightChallengeFacts.slots(active, actor: you)
        XCTAssertEqual(slots[you], 0)
        XCTAssertEqual(slots[LiveDesignFixtures.samID], 1)
        XCTAssertEqual(slots[LiveDesignFixtures.jordanID], 2)
        XCTAssertEqual(slots[LiveDesignFixtures.priyaID], 3)
        XCTAssertEqual(FloodlightChallengeFacts.people(active, actor: you).map(\.actorId),
                       [you, LiveDesignFixtures.samID, LiveDesignFixtures.jordanID, LiveDesignFixtures.priyaID])
        let lanes = FloodlightChallengeFacts.lanes(active, actor: you)
        XCTAssertEqual(lanes.map(\.fraction), [0.32, 0.39, 0.08, 1.0])
        XCTAssertEqual(lanes.map(\.met), [false, false, false, true])
    }

    func testGoalsMetSoFarNeverRanksAnyone() {
        XCTAssertEqual(FloodlightChallengeFacts.metLine(active, actor: you), "Priya reached their goal.")
        let three = withFact(withFact(active, you, value: 20_000_000, secondsAgo: 60), LiveDesignFixtures.samID, value: 20_400_000, secondsAgo: 60)
        XCTAssertEqual(FloodlightChallengeFacts.metLine(three, actor: you), "You, Sam and Priya reached your goals.")
        let others = withFact(active, LiveDesignFixtures.samID, value: 20_000_000, secondsAgo: 60)
        XCTAssertEqual(FloodlightChallengeFacts.metLine(others, actor: you), "Sam and Priya reached their goals.")
        let all = withFact(withFact(three, LiveDesignFixtures.jordanID, value: 15_000_000, secondsAgo: 60), you, value: 20_000_000, secondsAgo: 60)
        XCTAssertEqual(FloodlightChallengeFacts.metLine(all, actor: you), "Everyone reached their goal.")
        let nobody = withFact(active, LiveDesignFixtures.priyaID, value: 9_000_000, secondsAgo: 60)
        XCTAssertNil(FloodlightChallengeFacts.metLine(nobody, actor: you))
    }

    func testSpokenProgressStakeAndDay() {
        let sam = active.members.first { $0.actorId == LiveDesignFixtures.samID }!
        XCTAssertEqual(FloodlightChallengeFacts.spoken(active, sam, actor: you), "Sam, 7.8 of 20 kilometres, 39 percent of their goal.")
        let own = active.own(you)!
        XCTAssertEqual(FloodlightChallengeFacts.spoken(active, own, actor: you), "You, 6.4 of 20 kilometres, 32 percent of your goal.")
        let priya = active.members.first { $0.actorId == LiveDesignFixtures.priyaID }!
        XCTAssertEqual(FloodlightChallengeFacts.spoken(active, priya, actor: you), "Priya, 10 of 10 kilometres, 100 percent of their goal, goal reached.")
        XCTAssertEqual(FloodlightChallengeFacts.stakeSpoken(active, actor: you),
                       "Your simulated stake, $20. Reach 20 kilometres and it comes back after results are final. Show how the pot works.")
        let day = FloodlightChallengeFacts.day(active)
        XCTAssertEqual(day.index, 1)
        XCTAssertEqual(day.spoken, "Tuesday, day 2 of 7. Ends Sunday.")
        XCTAssertEqual(FloodlightChallengeFacts.goal(active, 20_000_000), "20 km")
        XCTAssertEqual(FloodlightChallengeFacts.value(active, own), "6.4")
    }

    func testUpdateTimesAreShortOnScreenAndFullForVoiceOver() throws {
        let own = try XCTUnwrap(FloodlightChallengeFacts.syncTime(active, active.own(you)!, actor: you))
        XCTAssertEqual(own.short, "1 min ago")
        XCTAssertEqual(own.spoken, "Updated from Apple Health 1 min ago")
        XCTAssertFalse(own.late)
        let sam = active.members.first { $0.actorId == LiveDesignFixtures.samID }!
        XCTAssertEqual(FloodlightChallengeFacts.syncTime(active, sam, actor: you)?.spoken, "Updated 1 min ago")
        let now = withFact(active, you, value: 6_400_000, secondsAgo: 20)
        XCTAssertEqual(FloodlightChallengeFacts.syncTime(now, now.own(you)!, actor: you)?.short, "Just now")
        let hours = withFact(active, you, value: 6_400_000, secondsAgo: 2 * 3600 + 60)
        XCTAssertEqual(FloodlightChallengeFacts.syncTime(hours, hours.own(you)!, actor: you)?.short, "2 h ago")
        let late = withFact(active, LiveDesignFixtures.jordanID, value: 1_200_000, secondsAgo: 15 * 3600 + 31 * 60)
        let jordan = try XCTUnwrap(FloodlightChallengeFacts.syncTime(late, late.members.first { $0.actorId == LiveDesignFixtures.jordanID }!, actor: you))
        XCTAssertTrue(jordan.late)
        XCTAssertTrue(jordan.short.hasPrefix("Yesterday, "), jordan.short)
        XCTAssertTrue(jordan.spoken.hasPrefix("Updated yesterday at "), jordan.spoken)
        XCTAssertTrue(FloodlightChallengeFacts.lanes(late, actor: you)[2].late)
        let missing = copy(active, members: active.members.map { $0.actorId == you ? .init(actorId: you, username: $0.username, target: $0.target, selected: true, exited: false, consented: true, fact: nil) : $0 })
        XCTAssertNil(FloodlightChallengeFacts.syncTime(missing, missing.own(you)!, actor: you))
        XCTAssertNil(FloodlightChallengeFacts.fraction(missing, missing.own(you)!), "No saved update is not zero progress")
        XCTAssertEqual(FloodlightChallengeFacts.spoken(missing, missing.own(you)!, actor: you), "You, no update yet.")
    }

    func testOutcomeWordingFollowsTheHeadCount() {
        let pair = FloodlightChallengeFacts.outcomes(pair: true)
        XCTAssertEqual(pair.map(\.title), ["Both reach it", "One reaches it", "Both miss", "Couldn’t confirm"])
        XCTAssertEqual(pair.map(\.short), ["Both stakes back", "They get both stakes", "No one collects", "Stakes back · Challenge won’t count"])
        XCTAssertEqual(pair.last?.long, "If we can’t confirm a result from Apple Health, both stakes come back and the challenge won’t count.")
        let group = FloodlightChallengeFacts.outcomes(pair: false)
        XCTAssertEqual(group.map(\.title), ["Everyone reaches it", "Some reach it", "Everyone misses", "Couldn’t confirm"])
        XCTAssertEqual(group.map(\.short), ["All stakes back", "They split missed stakes", "No one collects", "Stake back, not a miss"])
        XCTAssertEqual(group[1].long, "They get their stakes back and split missed stakes evenly. Cents that don’t split evenly go to no one.")
        for outcome in pair + group {
            for banned in ["forfeit", "lost", "Neither back"] { XCTAssertFalse((outcome.short + outcome.long).contains(banned)) }
        }
        // A pair sentence is wrong for three or more people.
        for outcome in group { XCTAssertFalse((outcome.short + outcome.long).localizedCaseInsensitiveContains("both")) }
    }

    func testInvitationHeaderSeatsAndFacts() {
        XCTAssertEqual(FloodlightChallengeFacts.seatLine(invitation, actor: you), "Jordan agreed. Your seat fills when you agree.")
        let nobody = copy(invitation, members: invitation.members.map { member($0, consented: false) })
        XCTAssertEqual(FloodlightChallengeFacts.seatLine(nobody, actor: you), "Your seat fills when you agree.")
        XCTAssertEqual(FloodlightChallengeFacts.potCents(nobody), 0)
        let header = FloodlightChallengeFacts.goalHeader(invitation, actor: you)
        XCTAssertEqual(header?.goal, "20 km")
        XCTAssertEqual(header?.label, "each")
        XCTAssertEqual(header?.spoken, "You and Jordan: 20 km each.")
        let different = copy(invitation, members: invitation.members.map { $0.actorId == you ? $0 : member($0, target: 15_000_000) })
        XCTAssertEqual(FloodlightChallengeFacts.goalHeader(different, actor: you)?.label, "your goal")
        let seats = FloodlightChallengeFacts.seats(invitation, actor: you)
        XCTAssertEqual(seats.map(\.agreed), [true, false], "People who agreed sit first")
        XCTAssertEqual(seats.map(\.slot), [1, 0])
        XCTAssertEqual(FloodlightChallengeFacts.sourceFact(invitation), "Outdoor runs on Apple Watch")
    }
}
#endif
