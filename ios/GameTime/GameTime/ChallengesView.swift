import SwiftUI

struct ChallengesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private var history: [ContestCard] {
        model.contests.filter {
            $0.status == .cancelled || $0.status == .finalized
        }
    }

    var body: some View {
        List {
            if !model.configuration.contestMutationsEnabled {
                Section {
                    Label(
                        "Contest changes are locked in Release until the evidence and App Attest slice is complete.",
                        systemImage: "lock.shield"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .listRowBackground(CompetitiveTrustTheme.raisedInk)
            }

            if !model.invitations.isEmpty {
                Section("Invitations") {
                    ForEach(model.invitations) { contest in
                        ContestCardRow(contest: contest) {
                            router.challengesPath.append(.contest(contest.id))
                        }
                        .challengeListRow()
                    }
                }
            }

            if !model.activeAndUpcomingContests.isEmpty {
                Section("Your duels") {
                    ForEach(model.activeAndUpcomingContests) { contest in
                        ContestCardRow(contest: contest) {
                            router.challengesPath.append(.contest(contest.id))
                        }
                        .challengeListRow()
                    }
                }
            }

            if !history.isEmpty {
                Section("History") {
                    ForEach(history) { contest in
                        ContestCardRow(contest: contest) {
                            router.challengesPath.append(.contest(contest.id))
                        }
                        .challengeListRow()
                    }
                }
            }

            if model.contests.isEmpty, model.loadState != .loading {
                EmptyTrustState(
                    title: "No duels yet",
                    message:
                        "Create a one-to-one challenge with an accepted friend. Terms stay fixed after submission.",
                    systemImage: "flag.checkered"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                Button {
                    router.presentedSheet = .createDuel
                } label: {
                    Label("Create a duel", systemImage: "plus")
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(
                    !model.configuration.contestMutationsEnabled
                        || model.acceptedFriendships.isEmpty
                )
                .accessibilityIdentifier("challenge.create")
                .listRowBackground(Color.clear)
            } footer: {
                if model.acceptedFriendships.isEmpty {
                    Text("Accept a friendship before creating a duel.")
                } else {
                    Text(
                        "M8.1 sends one invitation. No group contest or real pledge is enabled."
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .trustScreenBackground()
        .navigationTitle("Challenges")
        .refreshable {
            await model.refresh()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentedSheet = .createDuel
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(
                    !model.configuration.contestMutationsEnabled
                        || model.acceptedFriendships.isEmpty
                )
                .accessibilityLabel("Create a duel")
            }
        }
    }
}

private extension View {
    func challengeListRow() -> some View {
        padding(.vertical, 3)
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
