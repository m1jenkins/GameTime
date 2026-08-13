import SwiftUI

struct TodayView: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                loadState

                if let challenge = store.openChallenge {
                    currentChallenge(challenge)
                } else if
                    store.hasVerifiedCreationState
                {
                    createCard
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .daybreakScreenChrome()
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await store.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide)))
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: 26,
                            relativeTo: .title2
                        )
                    )
                Text(Date.now.formatted(.dateTime.month(.wide).day()))
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 6)
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

    private func currentChallenge(
        _ summary: PersonalChallengeSummary
    ) -> some View {
        VStack(spacing: 12) {
            DaybreakSectionLabel(text: "Your week")
            DaybreakCard(tone: .inverse) {
                VStack(alignment: .leading, spacing: 15) {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            PersonalStatusPill(
                                status: summary.presentationStatus(at: Date()),
                                outcome: summary.outcome?.kind
                            )
                            Text(summary.terms.commitmentText)
                                .font(
                                    CompetitiveTrustTheme.displayFont(
                                        size: 22,
                                        relativeTo: .headline
                                    )
                                )
                        }
                    } else {
                        HStack {
                            PersonalStatusPill(
                                status: summary.presentationStatus(at: Date()),
                                outcome: summary.outcome?.kind
                            )
                            Spacer(minLength: 8)
                            Text(summary.terms.commitmentText)
                                .font(
                                    CompetitiveTrustTheme.displayFont(
                                        size: 22,
                                        relativeTo: .headline
                                    )
                                )
                        }
                    }
                    Text(summary.terms.targetText)
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 28,
                                relativeTo: .title
                            )
                        )
                        .tracking(-0.7)
                    if let progress = store.displayedProgress(for: summary) {
                        PersonalProgressBar(
                            progress: progress,
                            terms: summary.terms
                        )
                        .colorScheme(.dark)
                    }
                    PersonalHealthProgressStatus(
                        progress: store.displayedProgress(for: summary),
                        terms: summary.terms,
                        status: summary.presentationStatus(at: Date()),
                        policy: summary.stepDataPolicy,
                        outcome: summary.outcome
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
            }

            if let progress = store.displayedProgress(for: summary),
                !progress.days.isEmpty
            {
                DaybreakSectionLabel(text: "Day by day")
                DaybreakCard {
                    PersonalSevenDayTimeline(days: progress.days)
                }
            }
        }
        .task(id: summary.id) {
            await store.loadDetail(challengeID: summary.id)
        }
    }

    private var createCard: some View {
        DaybreakCard {
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
        }
    }
}
