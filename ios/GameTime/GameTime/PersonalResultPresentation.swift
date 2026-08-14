import Foundation

/// Copy for a finished challenge, derived only from the frozen terms and the
/// outcome the existing challenge DTO already carries. Payment provider state
/// deliberately does not enter this presentation.
struct PersonalResultPresentation: Equatable {
    let title: String
    let details: [String]

    init(
        terms: FrozenPersonalTerms,
        outcome: PersonalOutcome
    ) {
        switch terms.settlementMode {
        case .testOnly:
            switch outcome.kind {
            case .metGoal:
                title = "Goal met — no money charged."
                details = ["Your steps added up and you got there. Nice work."]
            case .missedGoal:
                title = "Goal missed — no money charged."
                details = ["This test-only challenge is closed."]
            case .inconclusive:
                title = "This one didn’t count — no money charged."
                details = Self.unclearDetails(for: outcome)
            }
        case .stripeSandbox:
            switch outcome.kind {
            case .metGoal:
                title = "Goal met — $0 test charge."
                details = ["Your steps added up and you got there. Nice work."]
            case .inconclusive:
                title = "This one didn’t count — $0 test charge."
                details = Self.unclearDetails(for: outcome)
            case .missedGoal:
                // Result truth and payment truth arrive through separate
                // authoritative reads. The payment-status card owns review and
                // settlement wording so this presentation never infers either
                // from the result publication time.
                title = "Goal missed."
                details = []
            }
        }
    }

    private static func unclearDetails(
        for outcome: PersonalOutcome
    ) -> [String] {
        var details = [
            "Missing or unclear step data never counts as a miss."
        ]
        if let reason = PersonalReasonText.sentence(for: outcome.reasonCode) {
            details.append(reason)
        }
        return details
    }
}
