import SwiftUI
import StripePaymentSheet

/// The optional "Put money on it" step on a personal goal review (D144).
/// Saving a card never charges it; the server charges once only after a
/// confirmed miss.
struct ChallengeCommitmentSection: View {
    @Bindable var draft: ChallengeCreationDraft
    let store: ChallengeV1Store
    @State private var sheet: PaymentSheet?
    @State private var showingSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Put money on it", isOn: $draft.commits)
                .font(.body).accessibilityIdentifier("beta.personal.commitment")
            if draft.commits {
                Text(ChallengeCommitment.banner)
                    .font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                if draft.commitmentSaved {
                    Label(ChallengeCommitment.cardSaved, systemImage: "creditcard")
                        .font(.subheadline).accessibilityIdentifier("beta.personal.commitment.saved")
                } else {
                    Text(ChallengeCommitment.addCard).font(.subheadline)
                    Button {
                        Task { await start() }
                    } label: {
                        Text(draft.savingCard ? "Saving…" : "Add test payment method")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(LiveSecondaryButtonStyle())
                    .disabled(draft.savingCard)
                    .accessibilityIdentifier("beta.personal.commitment.add")
                }
            }
        }
        .background {
            if let sheet {
                Color.clear.paymentSheet(isPresented: $showingSheet, paymentSheet: sheet, onCompletion: finish)
            }
        }
    }

    private func start() async {
        guard let setup = await draft.saveCard(store: store) else {
            if let error = draft.error { SignalAccessibility.announce(error) }
            return
        }
        guard let key = setup.publishableKey, let secret = setup.setupIntentClientSecret else {
            draft.error = "We couldn’t reach the payment test service. Check your connection, then try again."
            return
        }
        var configuration = PaymentSheet.Configuration()
        configuration.apiClient = STPAPIClient(publishableKey: key)
        configuration.merchantDisplayName = GameTimePublicIdentity.name
        configuration.primaryButtonLabel = "Save test payment method"
        configuration.allowsDelayedPaymentMethods = false
        sheet = PaymentSheet(setupIntentClientSecret: secret, configuration: configuration)
        await Task.yield()
        showingSheet = true
    }

    private func finish(_ result: PaymentSheetResult) {
        switch result {
        case .completed:
            // Re-read the setup from Stripe through the server; the sheet's own
            // result is never taken as proof the card was saved.
            Task {
                _ = await draft.saveCard(store: store)
                SignalAccessibility.announce(draft.commitmentSaved ? ChallengeCommitment.cardSaved : draft.error ?? "")
            }
        case .canceled:
            break
        case .failed:
            draft.error = "Stripe couldn’t save that test payment method. Try again when you’re ready."
        }
    }
}

/// Payment test status for a committed goal, read from the server.
struct ChallengeCommitmentStatusCard: View {
    let store: ChallengeV1Store
    let challengeID: UUID
    @State private var status: ChallengeCommitment.Status?

    var body: some View {
        VStack(spacing: 0) {
            if let status {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Payment test status").font(.subheadline.weight(.semibold))
                    Text(ChallengeCommitment.sentence(status)).font(.subheadline)
                    Text(ChallengeCommitment.banner).font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .modifier(LiveCardModifier(radius: 18, material: true))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("beta.personal.commitment.status")
            }
        }
        .task(id: challengeID) {
            guard let actor = store.actor else { return }
            status = try? await store.client.read("challenge_commitment_status_v1",
                                                  fields: ["p_challenge_id": .string(challengeID.uuidString.lowercased())],
                                                  actor: actor, as: ChallengeCommitment.Status.self)
        }
    }
}
