import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private var running: [ContestCard] {
        model.activeAndUpcomingContests.filter { $0.status == .active }
    }

    private var startingSoon: [ContestCard] {
        model.activeAndUpcomingContests.filter { $0.status == .pending }
    }

    private var actionCount: Int {
        model.incomingFriendships.count + model.invitations.count
    }

    private var isEmpty: Bool {
        model.incomingFriendships.isEmpty
            && model.invitations.isEmpty
            && model.activeAndUpcomingContests.isEmpty
            && model.loadState != .loading
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 11) {
                subtitle
                loadStateCard
                friendRequests
                challengeInvitations
                contestSection(label: "Running", contests: running)
                contestSection(
                    label: "Starting soon",
                    contests: startingSoon
                )
                emptyState
            }
            .padding(.horizontal, 18)
            .padding(.top, 2)
            .padding(.bottom, 28)
        }
        .daybreakScreenChrome()
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await model.refresh()
        }
    }

    private var subtitle: some View {
        HStack(spacing: 12) {
            Text(subtitleText)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 12.5,
                        relativeTo: .caption,
                        weight: .semibold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            Spacer(minLength: 8)
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(CompetitiveTrustTheme.coralInk)
                    .frame(width: 34, height: 34)
                    .background(
                        CompetitiveTrustTheme.coralTint,
                        in: Circle()
                    )
            }
            .accessibilityLabel("Refresh live state")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }

    private var subtitleText: String {
        if actionCount == 1 {
            return "One thing needs you"
        }
        if actionCount > 1 {
            return "\(actionCount) things need you"
        }
        return Date.now.formatted(
            .dateTime.weekday(.wide).month(.wide).day()
        )
    }

    @ViewBuilder
    private var loadStateCard: some View {
        switch model.loadState {
        case .loading, .failed:
            DaybreakCard {
                InlineLoadStateView(
                    state: model.loadState,
                    retry: { Task { await model.refresh() } }
                )
            }
        case .idle, .loaded, .empty:
            EmptyView()
        }
    }

    @ViewBuilder
    private var friendRequests: some View {
        if !model.incomingFriendships.isEmpty {
            DaybreakSectionLabel(text: "Friend requests")
            DaybreakCard {
                VStack(spacing: 0) {
                    ForEach(model.incomingFriendships) { card in
                        FriendshipCardRow(
                            card: card,
                            actionTitle: "Accept",
                            action: {
                                Task {
                                    await model.acceptFriendship(
                                        with: card.otherUserID
                                    )
                                }
                            }
                        )
                        .contentShape(Rectangle())
                        .onTapGesture {
                            router.todayPath.append(
                                .friendship(card.otherUserID)
                            )
                        }
                        .padding(.vertical, 9)

                        if card.id != model.incomingFriendships.last?.id {
                            Divider()
                                .overlay(CompetitiveTrustTheme.border)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var challengeInvitations: some View {
        if !model.invitations.isEmpty {
            DaybreakSectionLabel(text: "Challenge invitations")
            ForEach(model.invitations) { contest in
                VStack(spacing: 9) {
                    ContestCardRow(
                        contest: contest,
                        currentUserID: model.userID
                    ) {
                        router.todayPath.append(.contest(contest.id))
                    }

                    Button("Review and accept") {
                        router.presentedSheet = .acceptInvitation(
                            contest.id
                        )
                    }
                    .buttonStyle(TrustPrimaryButtonStyle())
                    .disabled(
                        !model.configuration.contestMutationsEnabled
                    )
                    .accessibilityLabel(
                        "Review and accept \(contest.title)"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func contestSection(
        label: String,
        contests: [ContestCard]
    ) -> some View {
        if !contests.isEmpty {
            DaybreakSectionLabel(text: label)
            ForEach(contests) { contest in
                ContestCardRow(
                    contest: contest,
                    currentUserID: model.userID
                ) {
                    router.todayPath.append(.contest(contest.id))
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isEmpty {
            DaybreakCard {
                VStack(spacing: 16) {
                    EmptyTrustState(
                        title: "You’re clear for today",
                        message:
                            "Friend requests and challenge invitations land here before your running challenges.",
                        systemImage: "checkmark"
                    )

                    if model.configuration.contestMutationsEnabled,
                        !model.acceptedFriendships.isEmpty
                    {
                        Button("Start a challenge") {
                            router.presentedSheet = .createChallenge
                        }
                        .buttonStyle(TrustPrimaryButtonStyle())
                    } else {
                        Button("Find a friend") {
                            router.selectedTab = .friends
                        }
                        .buttonStyle(TrustSecondaryButtonStyle())
                    }
                }
            }
        }
    }
}
