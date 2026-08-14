import SwiftUI

struct ChallengesView: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppRouter.self) private var router
    @State private var showingDiscardConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                loadState
                PendingPersonalCancellationRecoveryCard(
                    contactSupport: { router.openAccountSupport() }
                )
                pendingRecovery

                if let current = store.openChallenge {
                    AthleticSectionHeader(text: "Your challenge")
                    PersonalChallengeCard(challenge: current) {
                        router.challengesPath.append(
                            .personalChallenge(current.id)
                        )
                    }
                }

                if !store.history.isEmpty {
                    AthleticSectionHeader(text: "Finished")
                    ForEach(store.history) { challenge in
                        PersonalChallengeCard(challenge: challenge) {
                            router.challengesPath.append(
                                .personalChallenge(challenge.id)
                            )
                        }
                    }
                }

                if store.loadState == .empty {
                    EmptyTrustState(
                        title: "No challenges yet",
                        message:
                            "The week you’re working on, and every week you’ve finished, will show up here.",
                        systemImage: "flag.checkered"
                    )
                    .trustCard()
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
        }
        .daybreakTabScrollClearance()
        .daybreakScreenChrome()
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refreshWithAnnouncement()
        }
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
            InlineLoadStateView(
                state: store.loadState,
                retry: { Task { await refreshWithAnnouncement() } }
            )
            .trustCard()
        case .idle, .loaded, .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private var pendingRecovery: some View {
        if let pending = store.pendingCreation {
            AthleticSectionHeader(text: "Unfinished setup")
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
            .trustCard()
        } else if store.hasPendingCreationRecoveryIssue {
            EmptyTrustState(
                title: "Saved setup needs attention",
                message: "GameTime couldn’t safely open the setup saved on this phone.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .trustCard()
            Button("Try saving again") {
                Task { await store.retryPendingCreationRecovery() }
            }
            .buttonStyle(TrustSecondaryButtonStyle())
        }
    }

    private func refreshWithAnnouncement() async {
        await store.refresh()
        PersonalAccessibilityAnnouncements.postRefreshResult(
            loadState: store.loadState,
            healthError: store.stepProgress.lastHealthError
        )
    }
}

struct AthleticSectionHeader: View {
    let text: String

    var body: some View {
        Text(text)
            .textCase(.uppercase)
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 11,
                    relativeTo: .caption,
                    weight: .bold
                )
            )
            .tracking(1.05)
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.top, 4)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}
