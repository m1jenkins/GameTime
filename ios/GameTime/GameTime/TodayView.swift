import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        List {
            Section {
                InlineLoadStateView(
                    state: model.loadState,
                    retry: { Task { await model.refresh() } }
                )
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)

            if !model.incomingFriendships.isEmpty {
                Section("Friend requests") {
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
                        .listRowBackground(
                            CompetitiveTrustTheme.raisedInk
                        )
                    }
                }
            }

            if !model.invitations.isEmpty {
                Section("Challenge invitations") {
                    ForEach(model.invitations) { contest in
                        VStack(spacing: 10) {
                            ContestCardRow(contest: contest) {
                                router.todayPath.append(.contest(contest.id))
                            }
                            Button("Review and accept") {
                                router.presentedSheet = .acceptInvitation(
                                    contest.id
                                )
                            }
                            .buttonStyle(TrustSecondaryButtonStyle())
                            .disabled(
                                !model.configuration.contestMutationsEnabled
                            )
                            .accessibilityLabel(
                                "Review and accept \(contest.title)"
                            )
                        }
                        .padding(.vertical, 6)
                        .listRowInsets(
                            EdgeInsets(
                                top: 6,
                                leading: 16,
                                bottom: 6,
                                trailing: 16
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            if !model.activeAndUpcomingContests.isEmpty {
                Section("Active and upcoming") {
                    ForEach(model.activeAndUpcomingContests) { contest in
                        ContestCardRow(contest: contest) {
                            router.todayPath.append(.contest(contest.id))
                        }
                        .padding(.vertical, 3)
                        .listRowInsets(
                            EdgeInsets(
                                top: 4,
                                leading: 16,
                                bottom: 4,
                                trailing: 16
                            )
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                }
            }

            if model.incomingFriendships.isEmpty,
                model.invitations.isEmpty,
                model.activeAndUpcomingContests.isEmpty,
                model.loadState != .loading
            {
                EmptyTrustState(
                    title: "You’re clear for today",
                    message:
                        "Friend requests and challenge invitations will appear here before ongoing contests.",
                    systemImage: "checkmark.shield"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }
        }
        .listStyle(.insetGrouped)
        .trustScreenBackground()
        .navigationTitle("Today")
        .refreshable {
            await model.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("Refresh live state")
            }
        }
    }
}
