#if DEBUG
import GameTimeCore
import XCTest
@testable import GameTime

@MainActor
final class LiveHomeProgressTests: XCTestCase {
    private let actor = LiveDesignFixtures.actorID
    /// October Steps: 100,000 steps, Saturday Oct 10 to Friday Oct 16, Chicago.
    private let start = try! ChallengeInstant("2026-10-10T00:00:00-05:00").date

    func testBeforeTheStartSaysWhenAndTheEvenDailyShare() async throws {
        let copy = try await makeCopy(now: start.addingTimeInterval(-14 * 3_600), total: nil)
        XCTAssertEqual(copy.progress.standing, .upcoming)
        XCTAssertEqual(copy.note?.title, "Your challenge starts tomorrow.")
        XCTAssertEqual(copy.note?.detail, "About 14,300 steps a day reaches 100,000 steps.")
        XCTAssertEqual(copy.paceLabel, "About 14,300 steps a day")
        XCTAssertEqual(copy.emptyBars, "Your daily steps show up here.")
        XCTAssertTrue(copy.feed.isEmpty)
        XCTAssertEqual(copy.dayLabel(copy.progress.days[0]), "Sat")
    }

    func testAheadOfPaceShowsWhatsLeftAndAnEvenShare() async throws {
        let counted = [span(day: 0, 16_420), span(day: 1, 18_900), span(day: 2, 7_130), span(day: 3, 11_250)]
        let copy = try await makeCopy(now: at(day: 3, hour: 14), total: 53_700, counted: counted)
        XCTAssertEqual(copy.note?.title, "You're ahead of pace with 4 days left.")
        XCTAssertEqual(copy.note?.detail, "46,300 steps to go. About 11,600 steps a day gets you there.")
        XCTAssertEqual(copy.stats.map(\.label), ["Best day (Sun)", "Daily average", "Days left"])
        XCTAssertEqual(copy.stats.map(\.value), ["18,900", "14,150", "4"])
        let feed = copy.feed.map(\.text)
        XCTAssertTrue(feed.contains("You passed 50,000 steps. Halfway there."), "\(feed)")
        XCTAssertTrue(feed.contains("Monday was lighter. Rest days are normal."), "\(feed)")
        XCTAssertLessThanOrEqual(feed.count, 3)
        XCTAssertEqual(copy.dayLabel(copy.progress.days[3]), "Tue")
        // The retired shell was called Today, and Home's render test rejects it.
        XCTAssertFalse(copy.barsSpoken.contains("Today"))
    }

    func testShortOfPaceNeverSaysBehindOrMentionsMoney() async throws {
        let copy = try await makeCopy(now: at(day: 3, hour: 12), total: 40_000)
        XCTAssertEqual(copy.note?.title, "60,000 steps to go with 4 days left.")
        XCTAssertEqual(copy.note?.detail, "About 15,000 steps a day gets you there.")
        let last = try await makeCopy(now: at(day: 6, hour: 18), total: 92_000)
        XCTAssertEqual(last.note?.title, "Last day: 8,000 steps to go.")
        XCTAssertNil(last.note?.detail)
        var texts: [String] = []
        for item in [copy, last] {
            texts += [item.note?.title, item.note?.detail].compactMap { $0 } + item.feed.map(\.text)
        }
        for text in texts {
            XCTAssertFalse(text.localizedCaseInsensitiveContains("behind"), text)
            XCTAssertFalse(text.contains("$"), text)
            XCTAssertFalse(text.localizedCaseInsensitiveContains("streak"), text)
        }
    }

    func testALightDayIsNormalAndReachingTheGoalSaysSo() async throws {
        let light = try await makeCopy(now: at(day: 3, hour: 12), total: 30_000,
                                   counted: [span(day: 0, 15_000), span(day: 1, 13_000), span(day: 2, 2_000)])
        XCTAssertTrue(light.feed.map(\.text).contains("Monday was lighter. Rest days are normal."))
        let reached = try await makeCopy(now: at(day: 5, hour: 12), total: 101_000)
        XCTAssertEqual(reached.note?.title, "You reached your goal.")
    }

    func testNoSavedTotalExplainsWhatCountsInsteadOfAMiss() async throws {
        let copy = try await makeCopy(now: at(day: 2, hour: 12), total: nil)
        XCTAssertEqual(copy.progress.standing, .noUpdate)
        XCTAssertEqual(copy.note?.title, "We haven't counted any steps yet.")
        XCTAssertTrue(copy.progress.days.allSatisfy { $0.value == nil })
        XCTAssertTrue(copy.feed.isEmpty)
        let saving = try await makeCopy(now: at(day: 2, hour: 12), total: nil, counted: [span(day: 0, 9_000)])
        XCTAssertEqual(saving.note?.title, "We're saving your latest steps.")
    }

    // MARK: - Fixtures

    private func at(day: Double, hour: Double) -> Date { start.addingTimeInterval(day * 86_400 + hour * 3_600) }
    private func span(day: Double, _ value: Double) -> ChallengeHealthCountedSpan {
        ChallengeHealthCountedSpan(start: at(day: day, hour: 9), end: at(day: day, hour: 9.5), value: value)
    }
    private func makeCopy(now: Date, total: Int?, counted: [ChallengeHealthCountedSpan]? = nil) async throws -> LiveHomeProgressCopy {
        let row = try await row(now: now, total: total)
        let progress = try XCTUnwrap(LiveHomeProgress.progress(row, actor: actor, counted: counted))
        return LiveHomeProgressCopy(row: row, actor: actor, progress: progress)
    }
    private func row(now: Date, total: Int?) async throws -> ChallengeV1 {
        let original = try await LiveDesignFixtureClient().detail(LiveDesignFixtures.activeID, actor: actor)
        let end = at(day: 7, hour: 0)
        let config = ChallengeV1.Window(startDate: "2026-10-10", days: 7, timezone: "America/Chicago", amountCents: 0,
            startsAt: .init(date: start), endsAt: .init(date: end), syncBy: .init(date: end.addingTimeInterval(86_400)),
            correctionsBy: .init(date: end.addingTimeInterval(2 * 86_400)), noticeDue: .init(date: end.addingTimeInterval(3 * 86_400)))
        let fact = total.map { ChallengeV1.Fact(value: $0, state: original.sourcePolicyVersion == nil ? "complete" : "value",
                                                recordedAt: .init(date: now.addingTimeInterval(-600)), revision: 1) }
        let member = ChallengeV1.Member(actorId: actor, username: "alexlee", target: 100_000, selected: true,
                                        exited: false, consented: true, fact: fact)
        return ChallengeV1(sourcePolicyVersion: original.sourcePolicyVersion, counts: nil, id: UUID(), creatorId: actor,
            policy: "personal_steps_goal_v1", config: config, status: now < start ? "scheduled" : "active",
            revision: original.revision, agreementVersion: original.agreementVersion, serverTime: .init(date: now),
            socialHidden: false, agreement: original.agreement, members: [member], notice: nil, reviews: [], final: nil)
    }
}
#endif
