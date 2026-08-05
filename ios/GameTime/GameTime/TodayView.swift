import SwiftUI

struct TodayView: View {
    @Environment(PersonalAccountabilityStore.self) private var store
    @Environment(AppRouter.self) private var router
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                header
                TestCommitmentDisclosure(
                    settlementMode:
                        store.configuration.personalSettlementMode
                )
                loadState

                if store.eligibilityHoldActive {
                    PersonalEligibilityHoldCard(hold: store.eligibilityHold)
                }

                if let challenge = store.openChallenge {
                    currentChallenge(challenge)
                } else if store.loadState != .loading {
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
            Spacer(minLength: 8)
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CompetitiveTrustTheme.coralInk)
                    .frame(width: 36, height: 36)
                    .background(CompetitiveTrustTheme.coralTint, in: Circle())
            }
            .accessibilityLabel("Refresh your progress")
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
                    if let progress = summary.progress {
                        PersonalProgressBar(
                            progress: progress,
                            terms: summary.terms
                        )
                        .colorScheme(.dark)
                    }
                    Button("See details") {
                        router.todayPath.append(
                            .personalChallenge(summary.id)
                        )
                    }
                    .buttonStyle(TrustPrimaryButtonStyle())
                    .accessibilityIdentifier("personal.today.open")
                }
            }

            if let progress = summary.progress, !progress.days.isEmpty {
                DaybreakSectionLabel(text: "Day by day")
                DaybreakCard {
                    PersonalSevenDayTimeline(days: progress.days)
                }
            }

            syncCard(summary)
        }
        .task(id: summary.id) {
            await store.loadDetail(challengeID: summary.id)
        }
    }

    private func syncCard(_ summary: PersonalChallengeSummary) -> some View {
        DaybreakCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Step syncing", systemImage: "heart.text.square.fill")
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 18,
                                relativeTo: .headline
                            )
                        )
                    Spacer(minLength: 8)
                    TrustStatusPill(
                        text: syncStatus(summary),
                        kind: summary.progress?.lastTrustedSyncAt == nil
                            ? .action
                            : .verified
                    )
                }
                if let date = summary.progress?.lastTrustedSyncAt {
                    Text("Last synced \(date.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                } else {
                    Text("We haven’t received your steps yet.")
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
                if let message = store.syncState(for: summary.id).message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
                Button("Sync my steps") {
                    Task { await store.sync(challengeID: summary.id) }
                }
                .buttonStyle(TrustSecondaryButtonStyle())
                .disabled(
                    !summary.permitsActivitySync(at: Date())
                        || !store.configuration.activitySyncEnabled
                        || store.isSyncingActivity
                )
                .accessibilityIdentifier("personal.sync")
            }
        }
    }

    private func syncStatus(_ summary: PersonalChallengeSummary) -> String {
        if summary.progress?.pendingUploadCount ?? 0 > 0
            || store.pendingActivityUploadCount > 0
        {
            return "Waiting to send"
        }
        return summary.progress?.lastTrustedSyncAt == nil
            ? "Not synced"
            : "Up to date"
    }

    private var createCard: some View {
        DaybreakCard {
            VStack(alignment: .leading, spacing: 15) {
                EmptyTrustState(
                    title: "Make this week count",
                    message:
                        "Pick one step goal and stick to it for seven days. You’ll start at midnight tonight unless you choose another time.",
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
