import SwiftUI

struct ChallengesView: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showingDiscardConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                TestCommitmentDisclosure(
                    settlementMode:
                        store.configuration.personalSettlementMode
                )
                loadState
                pendingRecovery

                if let current = store.openChallenge {
                    DaybreakSectionLabel(text: "Your challenge")
                    PersonalChallengeCard(challenge: current) {
                        router.challengesPath.append(
                            .personalChallenge(current.id)
                        )
                    }
                }

                if !store.history.isEmpty {
                    DaybreakSectionLabel(text: "Finished")
                    ForEach(store.history) { challenge in
                        PersonalChallengeCard(challenge: challenge) {
                            router.challengesPath.append(
                                .personalChallenge(challenge.id)
                            )
                        }
                    }
                }

                if store.loadState == .empty {
                    DaybreakCard {
                        EmptyTrustState(
                            title: "No challenges yet",
                            message:
                                "The week you’re working on, and every week you’ve finished, will show up here.",
                            systemImage: "flag.checkered"
                        )
                    }
                }

                if store.hasVerifiedCreationState,
                    store.openChallenge == nil
                {
                    Button("Start a challenge") {
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
            "Delete this draft?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete draft", role: .destructive) {
                Task { _ = await store.discardPendingCreation() }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(
                "This deletes the copy saved on your phone. If your challenge already started, it keeps running."
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
            DaybreakSectionLabel(text: "Unfinished setup")
            DaybreakCard(tone: .pledge) {
                VStack(alignment: .leading, spacing: 11) {
                    TrustStatusPill(
                        text: store.hasPendingCreationRecoveryIssue
                            ? "Needs attention"
                            : "Ready to finish",
                        kind: .action
                    )
                    Text(pending.request.cadence == .daily
                        ? "\(pending.request.targetSteps.formatted()) steps a day"
                        : "\(pending.request.targetSteps.formatted()) steps this week")
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 20,
                                relativeTo: .headline
                            )
                        )
                    Text(
                        "We saved exactly what you picked, so you can pick up where you left off."
                    )
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    Button("Continue setup") {
                        router.presentedSheet = .createPersonalChallenge
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(store.hasPendingCreationRecoveryIssue)
                    .accessibilityIdentifier("personal.pending.resume")
                    Button("Delete draft", role: .destructive) {
                        showingDiscardConfirmation = true
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        } else if store.hasPendingCreationRecoveryIssue {
            PersonalEligibilityHoldCard(hold: nil)
            Button("Try saving again") {
                Task { await store.retryPendingCreationRecovery() }
            }
            .buttonStyle(TrustSecondaryButtonStyle())
        }
    }
}
