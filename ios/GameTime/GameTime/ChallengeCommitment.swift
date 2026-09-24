import Foundation

/// D144: an optional Stripe sandbox commitment on a Personal Steps or Outdoor
/// run goal. The card is saved before consent; one test charge is made only
/// after a confirmed miss. Server state decides everything shown here.
enum ChallengeCommitment {
    static let dollars: ClosedRange<Int> = 1...50
    static let policies: Set<String> = ["personal_steps_goal_v1", "personal_distance_goal_v1"]

    struct Availability: Decodable, Equatable {
        let available: Bool
        let reason: String?
    }

    struct Setup: Decodable, Equatable {
        let setupId: UUID
        let publishableKey: String?
        let setupIntentClientSecret: String?
        let status: String
        var saved: Bool { status == "succeeded" }
    }

    struct Status: Decodable, Equatable {
        let challengeId: UUID
        let amountCents: Int
        let state: String
        let failureCode: String?
    }

    /// Sentences follow the sandbox payment copy in docs/COPY.md.
    static func consent(amountCents: Int) -> String {
        "By starting, you agree that GameTime may create one \(challengeMoney(amountCents)) test charge, kept by GameTime, only if your full Apple Health total for this goal falls short after the review window. Missing or partial activity never counts as a miss."
    }
    static let banner = "Payment test mode — no real money moves."
    static let addCard = "Add your test payment method before you start."
    static let cardSaved = "Test method saved. No test charge exists."

    static func sentence(_ status: Status) -> String {
        switch status.state {
        case "committed": return "Your \(challengeMoney(status.amountCents)) test commitment is set. Nothing is charged unless you miss."
        case "not_charged": return "No test charge — $0."
        case "charge_processing": return "Processing one \(challengeMoney(status.amountCents)) test charge."
        case "charged": return "Test charge complete — sandbox transaction recorded."
        case "charge_needs_attention", "charge_failed":
            return "Test payment needs your attention. We won’t try again automatically."
        default: return "Payment test status could not be confirmed. Reference: \(status.state)"
        }
    }

    static func refusal(_ reason: String?) -> String {
        switch reason {
        case "challenge_commitment_limit": return "You already have a goal with money on it. You can add money to another goal once that one ends."
        case "challenge_commitment_unpaid": return "A test payment needs your attention first. Open that goal’s payment status to see what happened."
        case "challenge_commitment_unavailable", nil: return "Putting money on a goal isn’t available for your account yet."
        default: return "We couldn’t save your test payment method. Try again when you’re ready. Reference: \(reason ?? "unknown")"
        }
    }
}

extension ChallengeV1 {
    /// True when this goal's agreed terms carry a D144 test payment commitment.
    var hasCommitment: Bool { agreement?.terms?["commitment"] != nil }
}
