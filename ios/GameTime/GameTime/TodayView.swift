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
            VStack(alignment: .leading, spacing: 16) {
                if let progress, let paceSummary {
                    let hero = PersonalTodayHeroPresentation(
                        terms: summary.terms,
                        progress: progress,
                        pace: paceSummary
                    )
                    heroMetric(hero)
                    Text(hero.remainingText)
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 15,
                                relativeTo: .subheadline,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                        .accessibilityIdentifier("personal.progress.remaining")
                    PersonalProgressBar(
                        progress: progress,
                        terms: summary.terms,
                        showsFacts: false
                    )
                    PersonalWeekRow(row: hero.week) { _ in
                        openChallenge(summary.id)
                    }
                    Text(hero.receiptText)
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 13,
                                relativeTo: .footnote,
                                weight: .semibold
                            )
                        )
                        .foregroundStyle(CompetitiveTrustTheme.money)
                        .fixedSize(horizontal: false, vertical: true)
                    PersonalHealthProgressStatus(
                        presentation: healthPresentation,
                        policy: summary.stepDataPolicy
                    )
                    Button(hero.openActionTitle) {
                        openChallenge(summary.id)
                    }
                    .buttonStyle(TrustPrimaryButtonStyle())
                    .accessibilityIdentifier("personal.today.open")
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
                    PersonalHealthProgressStatus(
                        presentation: healthPresentation,
                        policy: summary.stepDataPolicy
                    )
                    Button("See this week") {
                        openChallenge(summary.id)
                    }
                    .buttonStyle(TrustPrimaryButtonStyle())
                    .accessibilityIdentifier("personal.today.open")
                }
            }
            .trustCard()
        }
        .task(id: summary.id) {
            await store.loadDetail(challengeID: summary.id)
        }
    }

    private func heroMetric(_ hero: PersonalTodayHeroPresentation) -> some View {
        let number = hero.displayedSteps.formatted()
        let size: CGFloat = dynamicTypeSize.isAccessibilitySize ? 34 : 44
        let numberText = Text(number)
            .font(CompetitiveTrustTheme.tabularFont(size: size, weight: .bold))
            .foregroundStyle(CompetitiveTrustTheme.primaryText)
        let metric: Text
        if hero.stepsText.hasPrefix(number) {
            let suffix = String(hero.stepsText.dropFirst(number.count))
            metric = numberText
                + Text(suffix)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 16,
                        relativeTo: .callout,
                        weight: .semibold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        } else {
            metric = Text(hero.stepsText)
                .font(
                    CompetitiveTrustTheme.tabularFont(
                        size: dynamicTypeSize.isAccessibilitySize ? 20 : 28,
                        weight: .bold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.primaryText)
        }
        return metric
            .tracking(-0.8)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("personal.progress.steps")
    }

    private func openChallenge(_ challengeID: UUID) {
        router.todayPath.append(.personalChallenge(challengeID))
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
