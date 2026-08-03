import SwiftUI

struct ChallengesView: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showingDiscardConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                TestCommitmentDisclosure()
                loadState
                pendingRecovery

                if let current = store.openChallenge {
                    DaybreakSectionLabel(text: "Current challenge")
                    PersonalChallengeCard(challenge: current) {
                        router.challengesPath.append(
                            .personalChallenge(current.id)
                        )
                    }
                }

                if !store.history.isEmpty {
                    DaybreakSectionLabel(text: "Completed history")
                    ForEach(store.history) { challenge in
                        PersonalChallengeCard(challenge: challenge) {
                            router.challengesPath.append(
                                .personalChallenge(challenge.id)
                            )
                        }
                    }
                }

                if store.challenges.isEmpty, store.loadState != .loading {
                    DaybreakCard {
                        EmptyTrustState(
                            title: "No personal challenges yet",
                            message:
                                "Your current seven-day commitment and completed history will appear here.",
                            systemImage: "flag.checkered"
                        )
                    }
                }

                if store.openChallenge == nil {
                    Button("Create a personal challenge") {
                        router.presentedSheet = .createPersonalChallenge
                    }
                    .buttonStyle(TrustPrimaryButtonStyle())
                    .disabled(!store.canCreate)
                    .accessibilityIdentifier("personal.create")
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .daybreakScreenChrome()
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await store.refresh() }
        .confirmationDialog(
            "Discard the local retry record?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard local retry", role: .destructive) {
                Task { _ = await store.discardPendingCreation() }
            }
            Button("Keep saved request", role: .cancel) {}
        } message: {
            Text(
                "This removes only the exact on-device retry record. It does not cancel a challenge the server may already have created."
            )
        }
    }

    @ViewBuilder
    private var loadState: some View {
        switch store.loadState {
        case .loading, .failed:
            DaybreakCard {
                InlineLoadStateView(
                    state: store.loadState,
                    retry: { Task { await store.refresh() } }
                )
            }
        case .idle, .loaded, .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private var pendingRecovery: some View {
        if let pending = store.pendingCreation {
            DaybreakSectionLabel(text: "Saved request")
            DaybreakCard(tone: .pledge) {
                VStack(alignment: .leading, spacing: 11) {
                    TrustStatusPill(
                        text: store.hasPendingCreationRecoveryIssue
                            ? "Protected storage needs attention"
                            : "Exact retry ready",
                        kind: .action
                    )
                    Text(pending.request.cadence == .daily
                        ? "\(pending.request.targetSteps.formatted()) steps each day"
                        : "\(pending.request.targetSteps.formatted()) steps total")
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 20,
                                relativeTo: .headline
                            )
                        )
                    Text(
                        "GameTime kept the exact personal terms and request ID for a safe retry."
                    )
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    Button("Review saved request") {
                        router.presentedSheet = .createPersonalChallenge
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(store.hasPendingCreationRecoveryIssue)
                    .accessibilityIdentifier("personal.pending.resume")
                    Button("Discard local retry", role: .destructive) {
                        showingDiscardConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else if store.hasPendingCreationRecoveryIssue {
            PersonalEligibilityHoldCard(hold: nil)
            Button("Retry protected storage") {
                Task { await store.retryPendingCreationRecovery() }
            }
            .buttonStyle(TrustSecondaryButtonStyle())
        }
    }
}
