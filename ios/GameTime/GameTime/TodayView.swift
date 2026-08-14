import SwiftUI

struct TodayView: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                loadState
                PendingPersonalCancellationRecoveryCard(
                    contactSupport: { router.openAccountSupport() }
                )

                if let challenge = store.openChallenge {
                    currentChallenge(challenge)
                } else if store.hasVerifiedCreationState {
                    createCard
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
        }
        .daybreakTabScrollClearance()
        .daybreakScreenChrome()
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await refreshWithAnnouncement()
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

    private func currentChallenge(
        _ summary: PersonalChallengeSummary
    ) -> some View {
        let now = Date()
        let progress = store.displayedProgress(for: summary, now: now)
        let status = summary.presentationStatus(at: now)
        let healthPresentation = PersonalHealthProgressPresentation(
            progress: progress,
            terms: summary.terms,
            status: status,
            outcome: summary.outcome,
            uploadDelayed: summary.id == store.stepProgress.challengeID
                && store.stepProgress.lastUploadError != nil,
            now: now
        )
        let paceSummary: PersonalPaceSummary? = {
            if let progress {
                return PersonalPaceSummary(
                    terms: summary.terms,
                    progress: progress
                )
            }
            return nil
        }()

        return VStack(spacing: 12) {
            // Hero Performance Block & Stakes/Sync HUD
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center) {
                    PersonalStatusPill(
                        status: status,
                        outcome: summary.outcome?.kind
                    )
                    Spacer(minLength: 8)
                    Text(summary.terms.commitmentText)
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 20,
                                relativeTo: .headline
                            )
                        )
                        .foregroundStyle(CompetitiveTrustTheme.signalOrange)
                }

                VStack(alignment: .leading, spacing: 4) {
                    if let progress {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(progress.totalSteps.formatted())
                                .font(
                                    CompetitiveTrustTheme.tabularFont(
                                        size: dynamicTypeSize.isAccessibilitySize
                                            ? 30
                                            : 40,
                                        weight: .bold
                                    )
                                )
                                .tracking(-0.8)
                            Text("/ \(summary.terms.targetSteps.formatted()) steps")
                                .font(
                                    CompetitiveTrustTheme.tabularFont(
                                        size: 16,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    CompetitiveTrustTheme.secondaryText
                                )
                        }
                    } else {
                        Text(summary.terms.targetText)
                            .font(
                                CompetitiveTrustTheme.tabularFont(
                                    size: dynamicTypeSize.isAccessibilitySize
                                        ? 20
                                        : 28,
                                    weight: .bold
                                )
                            )
                            .tracking(-0.7)
                    }

                    if let paceSummary {
                        HStack(spacing: 6) {
                            Text(paceSummary.headline)
                                .font(
                                    CompetitiveTrustTheme.tabularFont(
                                        size: 14,
                                        weight: .bold
                                    )
                                )
                                .foregroundStyle(
                                    paceSummary.headlineTone == .positive
                                        ? CompetitiveTrustTheme.athleticGreen
                                        : CompetitiveTrustTheme.signalOrange
                                )
                            Text(paceSummary.headlineCaption)
                                .font(
                                    CompetitiveTrustTheme.uiFont(
                                        size: 12.5,
                                        relativeTo: .caption,
                                        weight: .semibold
                                    )
                                )
                                .foregroundStyle(
                                    CompetitiveTrustTheme.secondaryText
                                )
                        }
                    }
                }

                if let progress {
                    PersonalProgressBar(
                        progress: progress,
                        terms: summary.terms
                    )
                    .colorScheme(.dark)
                }

                Divider().overlay(CompetitiveTrustTheme.hairlineDivider)

                PersonalHealthProgressStatus(
                    presentation: healthPresentation,
                    policy: summary.stepDataPolicy
                )
                .colorScheme(.dark)

                Button("See details") {
                    router.todayPath.append(
                        .personalChallenge(summary.id)
                    )
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .accessibilityIdentifier("personal.today.open")
            }
            .trustCard()

            if let paceSummary {
                PersonalPaceCard(summary: paceSummary)
                PersonalPaceTiles(tiles: paceSummary.tiles)
            }
        }
        .task(id: summary.id) {
            await store.loadDetail(challengeID: summary.id)
        }
    }

    private var createCard: some View {
        VStack(alignment: .leading, spacing: 15) {
            EmptyTrustState(
                title: "Make this week count",
                message:
                    "Pick one step goal and stick to it for seven days. Your challenge starts at the next midnight in your saved time zone.",
                systemImage: "figure.walk"
            )
            Button("Start a challenge") {
                router.presentedSheet = .createPersonalChallenge
            }
            .buttonStyle(TrustPrimaryButtonStyle())
            .disabled(!store.canCreate)
            .accessibilityIdentifier("personal.create")
        }
        .trustCard()
    }

    private func refreshWithAnnouncement() async {
        await store.refresh()
        PersonalAccessibilityAnnouncements.postRefreshResult(
            loadState: store.loadState,
            healthError: store.stepProgress.lastHealthError
        )
    }
}
