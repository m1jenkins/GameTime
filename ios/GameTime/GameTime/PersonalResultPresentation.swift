import Foundation

/// Copy for a finished challenge, derived only from the frozen terms and the
/// outcome the existing challenge DTO already carries. Payment provider state
/// deliberately does not enter this presentation.
struct PersonalResultPresentation: Equatable {
    static let reviewWindow: TimeInterval = 7 * 86_400

    let title: String
    let details: [String]
    let reviewDeadline: Date?

    init(
        terms: FrozenPersonalTerms,
        outcome: PersonalOutcome,
        now: Date
    ) {
        switch terms.settlementMode {
        case .testOnly:
            reviewDeadline = nil
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
                reviewDeadline = nil
            case .inconclusive:
                title = "This one didn’t count — $0 test charge."
                details = Self.unclearDetails(for: outcome)
                reviewDeadline = nil
            case .missedGoal:
                let deadline = outcome.publishedAt.addingTimeInterval(
                    Self.reviewWindow
                )
                reviewDeadline = deadline
                if now < deadline {
                    title =
                        "Goal missed — review open. Settlement is paused."
                    details = [
                        "Ask us to review this result by \(PersonalTermsDateFormatter.dateTime(deadline, timezoneIdentifier: terms.timezone)).",
                        "Only a confirmed miss after review can create one \(terms.commitmentText) test charge.",
                    ]
                } else {
                    title = "Goal missed."
                    details = []
                }
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
