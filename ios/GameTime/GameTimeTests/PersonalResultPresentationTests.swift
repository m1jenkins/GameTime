import Foundation
import XCTest

@testable import GameTime

final class PersonalResultPresentationTests: XCTestCase {
    private let publishedAt = Date(timeIntervalSince1970: 1_780_000_000)

    func testSandboxMetAndMissingResultsPromiseZeroTestCharge() {
        let met = presentation(kind: .metGoal, reason: "target_reached")
        XCTAssertEqual(met.title, "Goal met — $0 test charge.")
        XCTAssertNil(met.reviewDeadline)

        let missing = presentation(
            kind: .inconclusive,
            reason: "missing_health_data"
        )
        XCTAssertEqual(
            missing.title,
            "This one didn’t count — $0 test charge."
        )
        XCTAssertEqual(
            missing.details.first,
            "Missing or unclear step data never counts as a miss."
        )
        XCTAssertNil(missing.reviewDeadline)
    }

    func testSandboxMissNamesOpenDeadlineAndFrozenAmount() throws {
        let presentation = self.presentation(
            kind: .missedGoal,
            reason: "target_missed_complete_evidence",
            now: publishedAt.addingTimeInterval(60)
        )
        let deadline = try XCTUnwrap(presentation.reviewDeadline)

        XCTAssertEqual(
            presentation.title,
            "Goal missed — review open. Settlement is paused."
        )
        XCTAssertEqual(
            deadline,
            publishedAt.addingTimeInterval(7 * 86_400)
        )
        XCTAssertTrue(presentation.details[0].contains("Ask us to review"))
        XCTAssertEqual(
            presentation.details[1],
            "Only a confirmed miss after review can create one $20.00 test charge."
        )
    }

    func testExpiredSandboxMissDoesNotInferPaymentState() {
        let presentation = self.presentation(
            kind: .missedGoal,
            reason: "target_missed_complete_evidence",
            now: publishedAt.addingTimeInterval(8 * 86_400)
        )

        XCTAssertEqual(presentation.title, "Goal missed.")
        XCTAssertEqual(presentation.details, [])
        XCTAssertFalse(presentation.title.localizedCaseInsensitiveContains("charge"))
        XCTAssertFalse(presentation.title.localizedCaseInsensitiveContains("waiv"))
        XCTAssertFalse(presentation.title.localizedCaseInsensitiveContains("process"))
    }

    func testEveryTestOnlyOutcomeClosesWithNoMoneyCharged() {
        for kind in [
            PersonalOutcomeKind.metGoal,
            .missedGoal,
            .inconclusive,
        ] {
            let presentation = self.presentation(
                settlementMode: .testOnly,
                kind: kind,
                reason: "missing_health_data"
            )
            XCTAssertTrue(
                presentation.title.localizedCaseInsensitiveContains(
                    "no money charged"
                )
            )
            XCTAssertNil(presentation.reviewDeadline)
        }
    }

    private func presentation(
        settlementMode: PersonalSettlementMode = .stripeSandbox,
        kind: PersonalOutcomeKind,
        reason: String,
        now: Date? = nil
    ) -> PersonalResultPresentation {
        let challengeID = UUID(
            uuidString: "19191919-1919-1919-1919-191919191919"
        )!
        let terms = FrozenPersonalTerms(
            challengeID: challengeID,
            userID: nil,
            cadence: .cumulative,
            targetSteps: 70_000,
            commitmentAmountMinor: 2_000,
            currency: "USD",
            settlementMode: settlementMode,
            termsVersion: settlementMode == .stripeSandbox
                ? "personal-stripe-sandbox-v1"
                : "personal-v2",
            timezone: "America/Chicago",
            agreementAt: publishedAt.addingTimeInterval(-9 * 86_400),
            startsAt: publishedAt.addingTimeInterval(-8 * 86_400),
            endsAt: publishedAt.addingTimeInterval(-86_400),
            evidenceCutoff: publishedAt.addingTimeInterval(-60),
            closedAt: publishedAt
        )
        let outcome = PersonalOutcome(
            id: UUID(),
            kind: kind,
            reasonCode: reason,
            evidenceCutoff: terms.evidenceCutoff,
            publishedAt: publishedAt
        )
        return PersonalResultPresentation(
            terms: terms,
            outcome: outcome,
            now: now ?? publishedAt
        )
    }
}
