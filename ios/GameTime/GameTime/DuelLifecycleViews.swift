#if DEBUG || STAGING
import SwiftUI

struct DuelLifecycleSections: View {
    let store: DuelStore
    let agreement: DuelAgreement
    let actorID: UUID
    let onReview: (DuelNotice) -> Void
    let onExit: (DuelSafeExitKind) -> Void
    private var lifecycle: DuelLifecycle? { store.lifecycles[agreement.id] }
    private var zone: String { agreement.terms.event.displayTimezone }

    var body: some View {
        if let lifecycle {
            if lifecycle.contactSuppressed {
                Section("Your updates") {
                    Text("Contact details and shared results are hidden. You can still see your own review requests and simulated return.")
                        .accessibilityIdentifier("duel.contact-hidden")
                }
            }
            if let final = lifecycle.finalResult {
                Section("Confirmed result") {
                    Text(final.outcome.title(actorID: actorID)).font(.headline)
                        .accessibilityIdentifier("duel.final-result")
                    Text(final.outcome.explanation)
                    fact("Confirmed", final.finalizedAt)
                    Text("This result is final. Later corrections need support and cannot change it here.")
                }
            } else if let closure = lifecycle.closure {
                Section("Duel exit saved") {
                    Text(closure.isOwn ? "Your exit is saved. You do not need to send it again." : "An exit is saved for this duel.")
                        .accessibilityIdentifier("duel.exit-receipt")
                    fact("Saved", closure.recordedAt)
                    Text("Neither runner loses a simulated stake. Refresh for the confirmed result and simulated return.")
                }
            } else if !lifecycle.contactSuppressed && lifecycle.notices.isEmpty && agreement.status == .scheduled {
                Section("Progress") {
                    Text(lifecycle.activatedAt == nil ? "You both agreed. Refresh after the race for progress." : "We’re waiting for the race results.")
                    Text("A missing result does not mean you lost.")
                    Text("Race results due: \(DuelCodec.dateText(agreement.terms.resultsDueAt, zone: zone))")
                    Text("Refresh this duel to check for a saved result notice.")
                }
            }
            Section("Simulated return") {
                if let cents = lifecycle.simulatedReturnCents {
                    Text("Simulated return recorded: \((Decimal(cents) / 100).formatted(.currency(code: "USD"))).")
                        .accessibilityIdentifier("duel.simulated-return")
                    Text("Nothing can be paid out or redeemed. No real money moved.")
                } else {
                    Text(lifecycle.finalResult == nil ? "No simulated return is recorded yet." : "Result confirmed — simulated return update pending.")
                        .accessibilityIdentifier("duel.return-pending")
                    Text("Refresh to check again. No real money moves.")
                }
            }
            if !lifecycle.notices.isEmpty {
                Section("Saved result updates") {
                    Text("Each correction has its own review deadline. Earlier updates stay here; only the confirmed result is final.")
                    ForEach(lifecycle.notices.sorted { $0.proofRevision > $1.proofRevision }) { notice in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(notice.id == lifecycle.latestNotice?.id ? "Latest result update" : "Earlier result update")
                                .font(.headline)
                            Text(notice.outcome.title(actorID: actorID))
                            Text(notice.outcome.explanation)
                            fact("Notice saved", notice.recordedAt)
                            fact("Ask for review before", notice.disputeClosesAt)
                            Text("The deadline itself is too late. The final result deadline also applies.")
                            if lifecycle.finalResult == nil && !lifecycle.reviews.contains(where: { $0.proofRevision == notice.id }) {
                                TimelineView(.periodic(from: .now, by: 1)) { context in
                                    if store.canFileReview(agreement.id, revision: notice.id, at: context.date) {
                                        Button("Ask for review") { onReview(notice) }
                                            .accessibilityIdentifier("duel.ask-review.\(notice.id)")
                                    } else {
                                        Text("Review is unavailable for this update. Refresh for the latest status.")
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("duel.notice.\(notice.id)")
                    }
                }
            }
            if !lifecycle.reviews.isEmpty {
                Section("Your review requests") {
                    ForEach(lifecycle.reviews) { review in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(review.statusText).font(.headline)
                                .accessibilityIdentifier("duel.review-receipt")
                            Text(review.reason.title)
                            fact("Requested", review.filedAt)
                            if let notice = lifecycle.notices.first(where: { $0.id == review.proofRevision }) {
                                fact("For the update saved", notice.recordedAt)
                            }
                            if let decided = review.decidedAt { fact("Reviewed", decided) }
                            else if lifecycle.finalResult == nil {
                                Text("The result is not final. If review runs out of time, neither runner loses a simulated stake.")
                                fact("Review time ends", review.reviewDueAt)
                            } else {
                                Text("This request remains in your history. See the confirmed result above.")
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
            if lifecycle.canExit {
                Section("Need to stop?") {
                    Text("You can withdraw or report an injury. Neither runner loses a simulated stake.")
                    ForEach(DuelSafeExitKind.allCases, id: \.self) { kind in
                        Button(kind.title, role: .destructive) { onExit(kind) }
                            .accessibilityIdentifier("duel.exit.\(kind.rawValue)")
                            .disabled(!store.canExit(agreement.id))
                    }
                }
            }
        } else {
            Section("Result updates") {
                Text(store.lifecycleErrors[agreement.id] ?? "Loading your result updates…")
                    .accessibilityIdentifier("duel.lifecycle-unavailable")
            }
        }
        Section {
            Text("Final result deadline: \(DuelCodec.dateText(agreement.terms.finalityDueAt, zone: zone))")
            Button("Refresh result updates") { Task { await store.refreshDetail(agreement.id) } }
                .accessibilityIdentifier("duel.refresh-results")
                .disabled(store.isSending || store.isLoading)
        }

    }

    private func fact(_ label: String, _ instant: DuelInstant) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.subheadline.weight(.semibold))
            Text(instant.text(zone: zone))
        }
    }
}

struct DuelParticipantReviewView: View {
    let store: DuelStore
    let agreement: DuelAgreement
    let notice: DuelNotice
    @State private var reason: DuelReviewReason?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                DuelDisclosure()
                Section("The result you want reviewed") {
                    Text("Update saved \(notice.recordedAt.text(zone: agreement.terms.event.displayTimezone))")
                    Text("Ask before \(notice.disputeClosesAt.text(zone: agreement.terms.event.displayTimezone)). The deadline itself is too late.")
                    Text("Final result deadline: \(DuelCodec.dateText(agreement.terms.finalityDueAt, zone: agreement.terms.event.displayTimezone))")
                    Text("Choose what needs checking. Your request goes to an independent reviewer.")
                }
                Section("What needs checking?") {
                    ForEach(DuelReviewReason.allCases, id: \.self) { choice in
                        Button { reason = choice } label: {
                            HStack {
                                Text(choice.title)
                                Spacer()
                                if reason == choice { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }
                            .frame(minHeight: 44)
                        }
                        .accessibilityIdentifier("duel.review-reason.\(choice.rawValue)")
                        .accessibilityAddTraits(reason == choice ? .isSelected : [])
                    }
                }
                Section {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Button("Send review request") {
                            guard let reason else { return }
                            Task {
                                await store.submit(.fileReview(challengeID: agreement.id, revision: notice.id, reason: reason))
                                dismiss()
                            }
                        }
                        .accessibilityIdentifier("duel.send-review")
                        .disabled(reason == nil || !store.canFileReview(agreement.id, revision: notice.id, at: context.date))
                    }
                }
            }
            .navigationTitle("Ask for review")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .interactiveDismissDisabled(store.isSending)
        }
    }
}
#endif
