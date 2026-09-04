import XCTest

@testable import GameTime

final class PersonalChallengeHistoryCardTests: XCTestCase {
    func testActiveDailyCardLeadsWithTheGoalAndKeepsMoneyAsAReceipt() {
        let fixture = makeCard(
            status: .active,
            startLocalDate: "2026-08-10",
            nowLocalDate: "2026-08-12"
        )
        let card = fixture.card

        XCTAssertEqual(card.statusText, "In progress")
        XCTAssertEqual(card.targetText, "10,000 steps a day")
        XCTAssertEqual(card.targetText, fixture.challenge.terms.targetText)
        XCTAssertEqual(
            card.receiptText,
            "\(fixture.challenge.terms.commitmentText) · Every day"
        )
        XCTAssertFalse(
            card.receiptText.contains("steps"),
            "The receipt is money and cadence, not a second goal line."
        )
        XCTAssertEqual(
            card.dateSummary,
            "Ends \(PersonalTermsDateFormatter.day(fixture.challenge.terms.endsAt, timezoneIdentifier: fixture.challenge.terms.timezone))"
        )
        XCTAssertTrue(card.showsProgress)
        XCTAssertTrue(card.showsHealth)
    }

    func testCumulativeCardReceiptUsesWeekTotalCadence() {
        let fixture = makeCard(
            status: .active,
            startLocalDate: "2026-08-05",
            nowLocalDate: "2026-08-07",
            cadence: .cumulative,
            targetSteps: 70_000
        )

        XCTAssertEqual(
            fixture.card.targetText,
            "70,000 steps this week"
        )
        XCTAssertEqual(
            fixture.card.receiptText,
            "\(fixture.challenge.terms.commitmentText) · Week total"
        )
        XCTAssertTrue(fixture.card.showsProgress)
    }

    func testCompletedGoalMetCardHidesLiveProgressAndKeepsHumaneCopy() {
        let fixture = makeCard(
            status: .completed,
            startLocalDate: "2026-08-03",
            nowLocalDate: "2026-08-12",
            outcomeKind: .metGoal,
            progressIsFrozen: true
        )
        let card = fixture.card

        XCTAssertEqual(card.statusText, "Goal met")
        XCTAssertEqual(card.targetText, "10,000 steps a day")
        XCTAssertEqual(
            card.receiptText,
            "\(fixture.challenge.terms.commitmentText) · Every day"
        )
        XCTAssertEqual(
            card.dateSummary,
            "Completed \(PersonalTermsDateFormatter.day(fixture.challenge.terms.closedAt ?? fixture.challenge.terms.evidenceCutoff, timezoneIdentifier: fixture.challenge.terms.timezone))"
        )
        XCTAssertFalse(
            card.showsProgress,
            "Finished weeks are a receipt, not a live progress HUD."
        )
        XCTAssertFalse(
            card.showsHealth,
            "Frozen Health provenance lives on the week detail, not the history row."
        )
    }

    func testDidNotCountUsesTheHumaneStatusAndSurfacesMissingHealth() {
        let fixture = makeCard(
            status: .completed,
            startLocalDate: "2026-08-03",
            nowLocalDate: "2026-08-12",
            outcomeKind: .inconclusive,
            outcomeReason: "missing_health_data",
            includeProgress: false
        )

        XCTAssertEqual(fixture.card.statusText, "Didn’t count")
        XCTAssertFalse(fixture.card.showsProgress)
        XCTAssertTrue(
            fixture.card.showsHealth,
            "Missing final Apple Health data must stay visible on the history card."
        )
    }

    func testScheduledCardNamesTheStartDay() {
        let fixture = makeCard(
            status: .scheduled,
            startLocalDate: "2026-08-20",
            nowLocalDate: "2026-08-12",
            includeProgress: false
        )

        XCTAssertEqual(fixture.card.statusText, "Scheduled")
        XCTAssertEqual(
            fixture.card.dateSummary,
            "Starts \(PersonalTermsDateFormatter.day(fixture.challenge.terms.startsAt, timezoneIdentifier: fixture.challenge.terms.timezone))"
        )
        XCTAssertFalse(fixture.card.showsProgress)
        XCTAssertTrue(fixture.card.showsHealth)
    }

    private func makeCard(
        status: PersonalChallengeStatus,
        startLocalDate: String,
        nowLocalDate: String,
        cadence: PersonalChallengeCadence = .daily,
        targetSteps: Int = 10_000,
        outcomeKind: PersonalOutcomeKind? = nil,
        outcomeReason: String = "target_reached_complete_evidence",
        includeProgress: Bool = true,
        progressIsFrozen: Bool = false
    ) -> (
        challenge: PersonalChallengeSummary,
        card: PersonalChallengeHistoryCardPresentation
    ) {
        let challengeID = UUID(
            uuidString: "18181818-1818-1818-1818-181818181818"
        )!
        let start = date(from: startLocalDate)
        let now = date(from: nowLocalDate)
        let closedAt = status == .completed || status == .cancelled
            ? start.addingTimeInterval(7 * 86_400)
            : nil
        let terms = FrozenPersonalTerms(
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
            closedAt: closedAt
        )
        let outcome = outcomeKind.map { kind in
            PersonalOutcome(
                id: challengeID,
                kind: kind,
                reasonCode: outcomeReason,
                evidenceCutoff: terms.evidenceCutoff,
                publishedAt: closedAt ?? terms.evidenceCutoff
            )
        }
        let challenge = PersonalChallengeSummary(
            id: challengeID,
            status: status,
            terms: terms,
            outcome: outcome,
            stepDataPolicy: .healthKitNonmanualDailyV1
        )
        let progress: PersonalDisplayedProgress?
        if includeProgress {
            progress = PersonalDisplayedProgress(
                totalSteps: 17_832,
                remainingSteps: cadence == .daily
                    ? 2_650
                    : max(0, targetSteps - 17_832),
                qualifyingDays: 1,
                completedDays: 1,
                days: [
                    PersonalDisplayedDay(
                        localDate: startLocalDate,
                        totalSteps: 10_482,
                        targetSteps: cadence == .daily ? targetSteps : nil,
                        state: .complete,
                        metTarget: cadence == .daily ? true : nil
                    ),
                ],
                observedAt: now,
                snapshotUpdatedAt: now,
                source: progressIsFrozen ? .frozenResult : .serverSnapshot,
                isStale: false,
                isFrozen: progressIsFrozen
            )
        } else {
            progress = nil
        }
        let card = PersonalChallengeHistoryCardPresentation(
            challenge: challenge,
            progress: progress,
            uploadDelayed: false,
            now: now
        )
        return (challenge, card)
    }

    private func date(from localDate: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "America/Chicago")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: localDate)!
    }
}
