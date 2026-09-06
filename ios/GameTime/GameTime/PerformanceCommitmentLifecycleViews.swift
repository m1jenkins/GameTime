#if DEBUG || STAGING
import SwiftUI

struct CommitmentLifecycleSections: View {
    let store: PerformanceCommitmentStore
    let agreement: PerformanceCommitmentAgreement
    let onReview: (PerformanceCommitmentNotice) -> Void
    let onClose: (PerformanceCommitmentCloseReason) -> Void
    private var lifecycle: PerformanceCommitmentLifecycle? { store.lifecycles[agreement.id] }
    private var zone: String { agreement.displayTimezone }

    var body: some View {
        if let lifecycle {
            if let final = lifecycle.finalResult {
                Section("Confirmed result") {
                    Text(final.outcome.title).font(.headline)
                        .accessibilityIdentifier("commitment.final-result")
                    Text(final.outcome.explanation)
                    fact("Confirmed", final.finalizedAt)
                    Text("This result is final. Later corrections stay in support history and cannot change it here.")
                }
            } else if let closure = lifecycle.closure {
                Section("Goal ended") {
                    Text(closure.reason.receiptText).font(.headline)
                        .accessibilityIdentifier("commitment.close-receipt")
                    fact("Saved", closure.recordedAt)
                    Text("Your exit is saved. You don’t need to send it again. Refresh for the confirmed result and simulated return.")
                }
            } else {
                Section("Your progress") {
                    Text(lifecycle.notices.isEmpty ? agreement.statusText : lifecycle.progressText)
                        .accessibilityIdentifier("commitment.status")
                    Text("A missing result does not mean you missed your goal.")
                    fact("Race results due", agreement.terms.resultsDueAt)
                }
            }
            Section("Simulated amount") {
                if let simulation = lifecycle.simulation {
                    Text("Simulated return recorded: \(money(simulation.returnedCents)).")
                        .accessibilityIdentifier("commitment.simulated-return")
                    Text("Simulated amount lost: \(money(simulation.lostCents)).")
                        .accessibilityIdentifier("commitment.simulated-loss")
                    fact("Recorded", simulation.recordedAt)
                    Text("No real money moved, and you don’t owe anything. Nothing can be paid out or redeemed.")
                } else {
                    Text(lifecycle.finalResult == nil
                        ? "No simulated return or loss is recorded yet."
                        : "Result confirmed — simulated amount update pending.")
                        .accessibilityIdentifier("commitment.simulation-pending")
                    Text("Refresh to check again. No real money moves.")
                }
            }
            if !lifecycle.notices.isEmpty {
                Section("Saved result updates") {
                    Text("Each correction has its own review deadline. Earlier updates stay here; only the confirmed result is final. Opening this page does not start or extend a review window.")
                    ForEach(lifecycle.notices.sorted { $0.proofRevision > $1.proofRevision }) { notice in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(notice.id == lifecycle.latestNotice?.id ? "Latest result update" : "Earlier result update")
                                .font(.headline)
                            Text(notice.outcome.title)
                            Text(notice.outcome.explanation)
                            fact("Notice saved", notice.recordedAt)
                            fact("Ask for review before", min(notice.disputeClosesAt, agreement.terms.finalityDueAt))
                            if agreement.terms.finalityDueAt < notice.disputeClosesAt {
                                fact("Full seven-day window ends", notice.disputeClosesAt)
                                Text("The final result deadline comes first. If there isn’t time for full review, you don’t lose the simulated amount.")
                            }
                            if lifecycle.finalResult == nil && !lifecycle.reviews.contains(where: { $0.proofRevision == notice.id }) {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    Button("Ask for review") { onReview(notice) }
                                        .disabled(!store.canFileReview(agreement.id, revision: notice.id, at: context.date))
                                        .accessibilityIdentifier("commitment.ask-review.\(notice.id)")
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("commitment.notice.\(notice.id)")
                    }
                }
            }
            if !lifecycle.reviews.isEmpty {
                Section("Your review requests") {
                    ForEach(lifecycle.reviews) { review in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(review.statusText).font(.headline)
                                .accessibilityIdentifier("commitment.review-receipt")
                            Text(review.reason.title)
                            fact("Requested", review.filedAt)
                            if let notice = lifecycle.notices.first(where: { $0.id == review.proofRevision }) {
                                fact("For the update saved", notice.recordedAt)
                            }
                            if let resolution = review.resolution { fact("Reviewed", resolution.recordedAt) }
                            else if lifecycle.finalResult == nil {
                                Text("The result is not final. If review runs out of time, you don’t lose your simulated amount.")
                                fact("Review time ends", review.reviewDueAt)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            if lifecycle.finalResult == nil && lifecycle.closure == nil {
                Section("Need to stop?") {
                    Text("You can end this goal without losing the simulated amount.")
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        ForEach(PerformanceCommitmentCloseReason.ownerSelectable, id: \.self) { reason in
                            if store.canClose(agreement.id, reason: reason, at: context.date) {
                                Button(reason.title, role: .destructive) { onClose(reason) }
                                    .accessibilityIdentifier("commitment.close.\(reason.rawValue)")
                            }
                        }
                    }
                }
            }
            if !lifecycle.supportReceipts.isEmpty {
                Section("Support history") {
                    Text("These updates do not change your confirmed result or simulated amount.")
                    ForEach(lifecycle.supportReceipts) { receipt in
                        VStack(alignment: .leading) {
                            Text(receipt.category.title)
                            fact("Saved", receipt.recordedAt)
                        }
                    }
                }
            }
        } else {
            Section("Result updates") {
                Text("We couldn’t confirm your result status. Refresh this goal to try again.")
                    .accessibilityIdentifier("commitment.lifecycle-unavailable")
            }
        }
    }
    private func fact(_ label: String, _ instant: PerformanceCommitmentInstant) -> some View {
        Text("\(label): \(instant.text(zone: zone))")
    }
    private func money(_ cents: Int) -> String { (Decimal(cents) / 100).formatted(.currency(code: "USD")) }
}

private extension PerformanceCommitmentSupportCategory {
    var title: String {
        switch self {
        case .resultCorrection: "Result correction received"
        case .identityCorrection: "Runner correction received"
        case .missingResult: "Missing result report received"
        }
    }
}

private extension PerformanceCommitmentCloseReason {
    var receiptText: String {
        switch self {
        case .cancel: "Goal cancelled"
        case .withdrawal: "Withdrawal saved"
        case .injury: "Injury reported"
        case .accountDeleted: "Account deleted"
        }
    }
}
#endif
