import XCTest

@testable import GameTime

final class PersonalTodayHeroTests: XCTestCase {
    func testWeekRowFollowsFrozenChallengeDatesInsteadOfASundayCalendar() {
        let row = makeWeekRow(
            startLocalDate: "2026-08-05",
            steps: [11_000, 9_000, 7_350, 0, 0, 0, 0],
            states: [
                .complete, .complete, .current, .future, .future, .future,
                .future,
            ]
        )

        XCTAssertEqual(
            row.days.map(\.localDate),
            [
                "2026-08-05",
                "2026-08-06",
                "2026-08-07",
                "2026-08-08",
                "2026-08-09",
                "2026-08-10",
                "2026-08-11",
            ]
        )
        XCTAssertFalse(
            row.days.map(\.localDate).contains("2026-08-02"),
            "A Sunday-start calendar week would begin on 2026-08-02."
        )
        XCTAssertEqual(row.days.map(\.position), Array(0..<7))
    }

    func testWeekRowMarksMetTodayAndUpcomingByShape() {
        let row = makeWeekRow(
            startLocalDate: "2026-08-05",
            steps: [11_000, 9_000, 7_350, 0, 0, 0, 0],
            states: [
                .complete, .complete, .current, .future, .future, .future,
                .future,
            ]
        )

        XCTAssertEqual(
            row.days.map(\.mark),
            [
                .met,
                .underGoal,
                .today,
                .upcoming,
                .upcoming,
                .upcoming,
                .upcoming,
            ]
        )
    }

    func testWeekRowSpeaksEachDayInTheSameWordsAsThePaceChart() {
        let fixture = makeHeroFixture(
            startLocalDate: "2026-08-05",
            steps: [11_000, 9_000, 7_350, 0, 0, 0, 0],
            states: [
                .complete, .complete, .current, .future, .future, .future,
                .future,
            ]
        )
        let expected = fixture.pace.days.map { day in
            let text = fixture.pace.detailText(for: day)
            return (day.longLabel, text.value, text.caption)
        }

        XCTAssertEqual(fixture.week.days.count, expected.count)
        for (day, parts) in zip(fixture.week.days, expected) {
            XCTAssertEqual(day.accessibilityLabel, "\(parts.0), \(parts.1)")
            XCTAssertEqual(day.accessibilityValue, parts.2)
        }
        XCTAssertTrue(fixture.week.days[0].accessibilityLabel.contains("11,000 steps"))
        XCTAssertTrue(fixture.week.days[2].accessibilityLabel.contains("7,350 steps"))
    }

    func testTodayHeroUsesDailyStepsRemainingAndAQuietReceipt() {
        let fixture = makeHeroFixture(
            startLocalDate: "2026-08-10",
            steps: [10_482, 7_350, 0, 0, 0, 0, 0],
            states: [
                .complete, .current, .future, .future, .future, .future,
                .future,
            ],
            weekTotal: 17_832
        )
        let hero = fixture.hero

        XCTAssertEqual(hero.displayedSteps, 7_350)
        XCTAssertNotEqual(hero.displayedSteps, 17_832)
        XCTAssertEqual(hero.stepsText, "7,350 steps today")
        XCTAssertEqual(hero.remainingText, "2,650 to today’s goal")
        XCTAssertEqual(
            hero.receiptText,
            "\(fixture.terms.commitmentText) · Every day · Day 2 of 7"
        )
        XCTAssertEqual(hero.openActionTitle, "See this week")
        XCTAssertEqual(
            hero.week.days.map(\.localDate).first,
            "2026-08-10"
        )
    }

    func testCumulativeHeroKeepsTheWeekTotalAndCadenceReceipt() {
        let fixture = makeHeroFixture(
            startLocalDate: "2026-08-05",
            steps: [8_000, 8_000, 8_000, 0, 0, 0, 0],
            states: [
                .complete, .complete, .current, .future, .future, .future,
                .future,
            ],
            cadence: .cumulative,
            targetSteps: 70_000,
            weekTotal: 24_000
        )
        let hero = fixture.hero

        XCTAssertEqual(hero.displayedSteps, 24_000)
        XCTAssertEqual(hero.stepsText, "24,000 steps this week")
        XCTAssertEqual(hero.remainingText, "46,000 to this week’s goal")
        XCTAssertEqual(
            hero.receiptText,
            "\(fixture.terms.commitmentText) · Week total · Day 3 of 7"
        )
    }

    func testDidNotCountDaysUseADistinctMarkFromUpcoming() {
        let pace = PersonalPaceSummary(
            detail: makePaceDetail(
                cadence: .cumulative,
                targetSteps: 70_000,
                steps: [11_240, 0, 4_000, 12_040, 7_200, 0, 0],
                states: [
                    .complete, .missing, .quarantined, .outageWaived,
                    .inProgress, .pending, .future,
                ],
                metTargets: Array(repeating: nil, count: 7)
            )
        )
        let row = PersonalChallengeWeekRow(pace: pace)

        XCTAssertEqual(
            row.days.map(\.mark),
            [
                .met,
                .didNotCount,
                .didNotCount,
                .didNotCount,
                .today,
                .waiting,
                .upcoming,
            ]
        )
    }

    private func makeWeekRow(
        startLocalDate: String,
        steps: [Int],
        states: [PersonalDisplayedDayState]
    ) -> PersonalChallengeWeekRow {
        makeHeroFixture(
            startLocalDate: startLocalDate,
            steps: steps,
            states: states
        ).week
    }

    private func makeHeroFixture(
        startLocalDate: String,
        steps: [Int],
        states: [PersonalDisplayedDayState],
        cadence: PersonalChallengeCadence = .daily,
        targetSteps: Int = 10_000,
        weekTotal: Int? = nil
    ) -> (
        terms: FrozenPersonalTerms,
        pace: PersonalPaceSummary,
        week: PersonalChallengeWeekRow,
        hero: PersonalTodayHeroPresentation
    ) {
        let terms = makeTerms(
            startLocalDate: startLocalDate,
            cadence: cadence,
            targetSteps: targetSteps
        )
        let total = weekTotal ?? steps.reduce(0, +)
        let remaining: Int
        if cadence == .daily {
            let currentIndex = states.firstIndex(of: .current) ?? 0
            remaining = max(0, targetSteps - steps[currentIndex])
        } else {
            remaining = max(0, targetSteps - total)
        }
        let progress = makeProgress(
            startLocalDate: startLocalDate,
            steps: steps,
            states: states,
            weekTotal: total,
            remainingSteps: remaining,
            dailyTarget: cadence == .daily ? targetSteps : nil
        )
        let pace = PersonalPaceSummary(terms: terms, progress: progress)
        let week = PersonalChallengeWeekRow(pace: pace)
        let hero = PersonalTodayHeroPresentation(
            terms: terms,
            progress: progress,
            pace: pace
        )
        return (terms, pace, week, hero)
    }

    private func makeProgress(
        startLocalDate: String,
        steps: [Int],
        states: [PersonalDisplayedDayState],
        weekTotal: Int,
        remainingSteps: Int,
        dailyTarget: Int? = 10_000
    ) -> PersonalDisplayedProgress {
        let dates = localDates(from: startLocalDate, count: steps.count)
        let days = zip(zip(dates, steps), states).map { pair, state in
            PersonalDisplayedDay(
                localDate: pair.0,
                totalSteps: pair.1,
                targetSteps: dailyTarget,
                state: state,
                metTarget: state == .future
                    ? nil
                    : dailyTarget.map { pair.1 >= $0 }
            )
        }
        return PersonalDisplayedProgress(
            totalSteps: weekTotal,
            remainingSteps: remainingSteps,
            qualifyingDays: days.filter { $0.metTarget == true }.count,
            completedDays: days.filter { $0.state == .complete }.count,
            days: days,
            observedAt: Date(),
            snapshotUpdatedAt: Date(),
            source: .serverSnapshot,
            isStale: false,
            isFrozen: false
        )
    }

    private func makeTerms(
        startLocalDate: String,
        cadence: PersonalChallengeCadence,
        targetSteps: Int
    ) -> FrozenPersonalTerms {
        let challengeID = UUID(
            uuidString: "43434343-4343-4343-4343-434343434343"
        )!
        let start = date(from: startLocalDate)
        return FrozenPersonalTerms(
            challengeID: challengeID,
            userID: nil,
            cadence: cadence,
            targetSteps: targetSteps,
            commitmentAmountMinor: 2_000,
            currency: "USD",
            settlementMode: .testOnly,
            termsVersion: "personal-v2",
            timezone: "America/Chicago",
            agreementAt: start.addingTimeInterval(-86_400),
            startsAt: start,
            endsAt: start.addingTimeInterval(7 * 86_400),
            evidenceCutoff: start.addingTimeInterval(8 * 86_400),
            closedAt: nil
        )
    }

    private func makePaceDetail(
        cadence: PersonalChallengeCadence,
        targetSteps: Int,
        steps: [Int],
        states: [PersonalEvidenceState],
        metTargets: [Bool?]
    ) -> PersonalChallengeDetail {
        let challengeID = UUID(
            uuidString: "44444444-4444-4444-4444-444444444444"
        )!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let start = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 3)
        )!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let days = steps.indices.map { index in
            PersonalDayProgress(
                localDate: formatter.string(
                    from: calendar.date(
                        byAdding: .day,
                        value: index,
                        to: start
                    )!
                ),
                trustedSteps: Double(steps[index]),
                targetSteps: cadence == .daily ? targetSteps : nil,
                evidenceState: states[index],
                metTarget: metTargets[index]
            )
        }
        let total = steps.reduce(0, +)
        return PersonalChallengeDetail(
            id: challengeID,
            status: .active,
            terms: FrozenPersonalTerms(
                challengeID: challengeID,
                userID: UUID(
                    uuidString: "55555555-5555-5555-5555-555555555555"
                )!,
                cadence: cadence,
                targetSteps: targetSteps,
                commitmentAmountMinor: 2_000,
                currency: "USD",
                settlementMode: .testOnly,
                termsVersion: "personal-v1",
                timezone: "America/Chicago",
                agreementAt: start.addingTimeInterval(-86_400),
                startsAt: start,
                endsAt: calendar.date(byAdding: .day, value: 7, to: start)!,
                evidenceCutoff: calendar.date(
                    byAdding: .day,
                    value: 8,
                    to: start
                )!,
                closedAt: nil
            ),
            progress: PersonalProgress(
                trustedSteps: total,
                remainingSteps: cadence == .daily
                    ? PersonalProgress.dailyRemainingSteps(
                        targetSteps: targetSteps,
                        days: days
                    )
                    : max(0, targetSteps - total),
                qualifyingDays: metTargets.filter { $0 == true }.count,
                completedDays: states.filter { $0 != .future }.count,
                days: days,
                evidenceState: .inProgress,
                lastTrustedSyncAt: start,
                pendingUploadCount: 0,
                coveredBucketCount: 47,
                expectedBucketCount: 48
            )
        )
    }

    private func localDates(from startLocalDate: String, count: Int) -> [String] {
        (0..<count).map { offset in
            let start = date(from: startLocalDate)
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Chicago")!
            let next = calendar.date(byAdding: .day, value: offset, to: start)!
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter.string(from: next)
        }
    }

    private func date(from localDate: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: localDate)!
    }
}
