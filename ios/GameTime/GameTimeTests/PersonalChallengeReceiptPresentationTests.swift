import Foundation
import XCTest

@testable import GameTime

final class PersonalChallengeReceiptPresentationTests: XCTestCase {
    func testDailyDefaultReceiptKeepsThreeGroupsAndTestOnlyProtection()
        throws
    {
        let draft = PersonalChallengeDraft(
            cadence: .daily,
            targetSteps: 10_000,
            commitmentAmountMinor: 1_000,
            timezone: "America/Chicago",
            startsAt: chicagoDate(year: 2026, month: 8, day: 14, hour: 0)
        )

        let presentation = PersonalChallengeReceiptPresentation(
            draft: draft,
            startsImmediately: false,
            settlementMode: .testOnly,
            paymentMethodSaved: false,
            hasSavedDraft: false
        )

        XCTAssertEqual(
            presentation.groups.map(\.title),
            ["Your challenge", "When it starts", "Payment protection"]
        )
        XCTAssertTrue(
            presentation.groups.allSatisfy { $0.facts.count <= 4 }
        )
        XCTAssertEqual(
            try fact(.howItCounts, in: .challenge, from: presentation).value,
            "Every day"
        )
        XCTAssertEqual(
            try fact(.goal, in: .challenge, from: presentation).value,
            "10,000 steps a day"
        )
        XCTAssertEqual(
            try fact(.amount, in: .challenge, from: presentation).value,
            "$10.00"
        )
        XCTAssertEqual(
            try fact(.length, in: .challenge, from: presentation).value,
            "Seven full days"
        )
        XCTAssertEqual(
            try fact(.dayOne, in: .start, from: presentation).value,
            "Midnight to midnight"
        )
        XCTAssertEqual(
            try fact(.finalCheck, in: .start, from: presentation).value,
            "24 hours after your last day"
        )
        XCTAssertEqual(
            try fact(.paymentMode, in: .payment, from: presentation).value,
            EnvironmentDisclosureCopy.testOnly
        )
        XCTAssertEqual(
            try fact(.missingData, in: .payment, from: presentation).value,
            "Never counts as a miss"
        )
        XCTAssertEqual(
            presentation.dayOneExplanation,
            "Seven full days. Day one runs midnight to midnight."
        )
    }

    func testCumulativeStartNowSandboxReceiptFreezesAmountAndProtection()
        throws
    {
        let draft = PersonalChallengeDraft(
            cadence: .cumulative,
            targetSteps: 70_000,
            commitmentAmountMinor: 5_000,
            timezone: "America/Chicago",
            startsAt: chicagoDate(
                year: 2026,
                month: 8,
                day: 13,
                hour: 15,
                minute: 37
            )
        )

        let presentation = PersonalChallengeReceiptPresentation(
            draft: draft,
            startsImmediately: true,
            settlementMode: .stripeSandbox,
            paymentMethodSaved: true,
            hasSavedDraft: true
        )

        XCTAssertTrue(
            presentation.groups.allSatisfy { $0.facts.count <= 4 }
        )
        XCTAssertEqual(
            try group(.payment, from: presentation).facts.count,
            4
        )
        XCTAssertEqual(
            try fact(.howItCounts, in: .challenge, from: presentation).value,
            "Week total"
        )
        XCTAssertEqual(
            try fact(.amount, in: .challenge, from: presentation).value,
            "$50.00"
        )
        XCTAssertEqual(
            try fact(.length, in: .challenge, from: presentation).value,
            "Seven days, counting from midnight today"
        )
        XCTAssertEqual(
            try fact(.starts, in: .start, from: presentation).value,
            "Now — today counts from midnight"
        )
        XCTAssertEqual(
            try fact(.dayOne, in: .start, from: presentation).value,
            "Eligible steps since midnight today count"
        )
        XCTAssertEqual(
            try fact(.paymentMode, in: .payment, from: presentation).value,
            "Test method saved — no real money moves."
        )
        XCTAssertEqual(
            try fact(.zeroOutcomes, in: .payment, from: presentation).value,
            "Goal met, or step data missing or unclear"
        )
        XCTAssertEqual(
            try fact(.confirmedMiss, in: .payment, from: presentation).value,
            "One $50.00 test charge, only after review"
        )
        XCTAssertEqual(
            try fact(.review, in: .payment, from: presentation).value,
            "Seven days — settlement paused"
        )
        XCTAssertEqual(
            try detail(.savedDraft, from: presentation).text,
            "GameTime saved exactly what you picked on this phone so you can safely retry or delete it."
        )
    }

    func testAmountProtectionTracksModeAndSelectedAmount() {
        XCTAssertEqual(
            PersonalCommitmentProtectionPresentation(
                amountMinor: 2_000,
                settlementMode: .testOnly
            ).text,
            "$20.00 test commitment. No money will be charged. Missing or unclear step data never counts as a miss."
        )
        XCTAssertEqual(
            PersonalCommitmentProtectionPresentation(
                amountMinor: 4_000,
                settlementMode: .stripeSandbox
            ).text,
            "Your test charge is $0 when you meet your goal or step data is missing or unclear. Only a confirmed miss after review can create one $40.00 test charge."
        )
    }

    func testReceiptCopyDoesNotExposeTechnicalOrInternalLanguage() {
        let draft = PersonalChallengeDraft(
            cadence: .cumulative,
            targetSteps: 70_000,
            commitmentAmountMinor: 3_000,
            timezone: "America/Chicago",
            startsAt: chicagoDate(year: 2026, month: 8, day: 14, hour: 0)
        )
        let presentation = PersonalChallengeReceiptPresentation(
            draft: draft,
            startsImmediately: false,
            settlementMode: .stripeSandbox,
            paymentMethodSaved: true,
            hasSavedDraft: true
        )
        let visibleCopy = (
            presentation.groups.flatMap { group in
                [group.title]
                    + group.facts.flatMap { [$0.label, $0.value] }
            }
                + presentation.details.flatMap { [$0.title, $0.text] }
        ).joined(separator: "\n").lowercased()

        XCTAssertFalse(visibleCopy.contains("inconclusive"))
        XCTAssertFalse(visibleCopy.contains("off-session"))
        XCTAssertFalse(visibleCopy.contains("draft reference"))
        XCTAssertFalse(visibleCopy.contains("setupintent"))
        XCTAssertFalse(visibleCopy.contains("paymentintent"))
    }

    private func group(
        _ id: PersonalChallengeReceiptPresentation.Group.Identifier,
        from presentation: PersonalChallengeReceiptPresentation
    ) throws -> PersonalChallengeReceiptPresentation.Group {
        try XCTUnwrap(presentation.groups.first { $0.id == id })
    }

    private func fact(
        _ id: PersonalChallengeReceiptPresentation.Fact.Identifier,
        in groupID: PersonalChallengeReceiptPresentation.Group.Identifier,
        from presentation: PersonalChallengeReceiptPresentation
    ) throws -> PersonalChallengeReceiptPresentation.Fact {
        try XCTUnwrap(
            try group(groupID, from: presentation).facts.first { $0.id == id }
        )
    }

    private func detail(
        _ id: PersonalChallengeReceiptPresentation.Detail.Identifier,
        from presentation: PersonalChallengeReceiptPresentation
    ) throws -> PersonalChallengeReceiptPresentation.Detail {
        try XCTUnwrap(presentation.details.first { $0.id == id })
    }

    private func chicagoDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar.date(
            from: DateComponents(
                year: year,
                month: month,
                day: day,
                hour: hour,
                minute: minute
            )
        )!
    }
}
