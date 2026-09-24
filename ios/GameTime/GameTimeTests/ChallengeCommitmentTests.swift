import XCTest
@testable import GameTime

/// D144 copy and draft rules for putting test money on a personal goal.
@MainActor final class ChallengeCommitmentTests: XCTestCase {
    private let banned = ["trusted", "evidence", "coverage", "frozen terms", "cadence", "diagnostic", "attestation",
                          "inconclusive", "waived", "surface", "protected storage", "handle", "Staging", "Debug",
                          "HealthKit", "App Attest", "Supabase", "Edge Function", "SetupIntent", "PaymentIntent",
                          "webhook", "idempotency", "forfeit", "failure"]

    private var sentences: [String] {
        let states = ["committed", "not_charged", "charge_processing", "charged", "charge_needs_attention", "charge_failed"]
        return [ChallengeCommitment.consent(amountCents: 2_000), ChallengeCommitment.banner, ChallengeCommitment.addCard,
                ChallengeCommitment.cardSaved]
            + states.map { ChallengeCommitment.sentence(.init(challengeId: UUID(), amountCents: 2_000, state: $0, failureCode: nil)) }
            + ["challenge_commitment_limit", "challenge_commitment_unpaid", "challenge_commitment_unavailable"].map { ChallengeCommitment.refusal($0) }
            + ["challenge_commitment_card_required", "challenge_commitment_amount_mismatch", "challenge_commitment_policy_unavailable"]
                .map { ChallengeV1Error.server($0).localizedDescription }
    }

    func testCopyAvoidsInternalVocabulary() {
        for sentence in sentences {
            for word in banned {
                XCTAssertFalse(sentence.localizedCaseInsensitiveContains(word), "\"\(word)\" in: \(sentence)")
            }
            XCTAssertFalse(sentence.contains("challenge_commitment"), "raw reason code in: \(sentence)")
        }
    }

    func testConsentNamesAmountTriggerRecipientAndMissingDataPromise() {
        let consent = ChallengeCommitment.consent(amountCents: 2_000)
        XCTAssertTrue(consent.contains("$20.00"))
        XCTAssertTrue(consent.contains("one"))
        XCTAssertTrue(consent.contains("kept by GameTime"))
        XCTAssertTrue(consent.contains("after the review window"))
        XCTAssertTrue(consent.contains("Missing or partial activity never counts as a miss."))
        XCTAssertTrue(ChallengeCommitment.banner.contains("no real money moves"))
    }

    func testCommitmentLimitsAmountAndOnlyAppliesToAvailableGoals() {
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"))
        draft.dollars = "100"
        XCTAssertEqual(draft.wholeDollars, 100)
        XCTAssertFalse(draft.canCommit, "not offered until the server says it is available")
        draft.commits = true
        XCTAssertNil(draft.wholeDollars, "a test commitment is capped at $50")
        draft.dollars = "50"
        XCTAssertEqual(draft.wholeDollars, 50)
        XCTAssertFalse(draft.commitmentSaved)
        draft.commits = false
        draft.dollars = "100"
        XCTAssertEqual(draft.wholeDollars, 100)
    }
}
