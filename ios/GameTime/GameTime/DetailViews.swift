import SwiftUI

struct ContestDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    let contestID: UUID

    private var contest: ContestCard? {
        model.contests.first { $0.id == contestID }
    }

    var body: some View {
        Group {
            if let contest {
                List {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            TrustStatusPill(
                                text: contest.myStatus == .invited
                                    ? "Action needed"
                                    : contest.status.rawValue.capitalized,
                                kind: contest.myStatus == .invited
                                    ? .action
                                    : .verified
                            )
                            Text(contest.title)
                                .font(.title2.bold())
                            Text(
                                "These terms are immutable after submission."
                            )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(CompetitiveTrustTheme.raisedInk)

                    Section("Terms") {
                        TermRow(label: "Metric", value: contest.metric.title)
                        TermRow(label: "Cadence", value: contest.cadence.title)
                        TermRow(label: "Target", value: contest.targetText)
                        TermRow(
                            label: "Test pledge",
                            value: contest.stakeText,
                            emphasis: CompetitiveTrustTheme.amber
                        )
                        TermRow(
                            label: "Starts",
                            value: contest.startsAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        TermRow(
                            label: "Ends",
                            value: contest.endsAt.formatted(
                                date: .abbreviated,
                                time: .shortened
                            )
                        )
                        TermRow(
                            label: "Tie-break",
                            value: contest.tieBreak.title
                        )
                    }
                    .listRowBackground(CompetitiveTrustTheme.raisedInk)

                    if contest.myStatus == .invited {
                        Section {
                            Button("Review and accept") {
                                router.presentedSheet = .acceptInvitation(
                                    contest.id
                                )
                            }
                            .buttonStyle(TrustPrimaryButtonStyle())
                            .disabled(
                                !model.configuration.contestMutationsEnabled
                            )

                            Button("Decline", role: .destructive) {
                                Task {
                                    await model.declineInvitation(
                                        contestID: contest.id
                                    )
                                }
                            }
                            .disabled(
                                !model.configuration.contestMutationsEnabled
                            )
                            .frame(maxWidth: .infinity)
                        } footer: {
                            Text(
                                "Accepting freezes your timezone and charity nomination for this contest."
                            )
                        }
                        .listRowBackground(Color.clear)
                    }
                }
                .trustScreenBackground()
            } else {
                ContentUnavailableView(
                    "Contest unavailable",
                    systemImage: "flag.slash",
                    description: Text(
                        "Refresh to load the current contest state."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CompetitiveTrustTheme.ink)
            }
        }
        .navigationTitle("Duel")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct FriendshipDetailView: View {
    @Environment(AppModel.self) private var model
    let userID: UUID

    private var card: FriendshipCard? {
        model.friendshipCards.first { $0.otherUserID == userID }
    }

    var body: some View {
        Group {
            if let card {
                List {
                    Section {
                        VStack(spacing: 12) {
                            InitialsAvatar(
                                initials: card.profileCard.initials,
                                size: 72
                            )
                            Text(card.displayName)
                                .font(.title2.bold())
                            Text("@\(card.handle)")
                                .foregroundStyle(.secondary)
                            TrustStatusPill(
                                text: card.status == .accepted
                                    ? "Friend"
                                    : "Pending",
                                kind: card.status == .accepted
                                    ? .verified
                                    : .action
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .listRowBackground(CompetitiveTrustTheme.raisedInk)

                    Section {
                        if card.status == .pending,
                            card.direction(
                                for: model.userID ?? UUID()
                            ) == .incoming
                        {
                            Button("Accept request") {
                                Task {
                                    await model.acceptFriendship(
                                        with: card.otherUserID
                                    )
                                }
                            }
                            .buttonStyle(TrustPrimaryButtonStyle())
                        }

                        Button(
                            card.status == .accepted
                                ? "Remove friend"
                                : "Remove request",
                            role: .destructive
                        ) {
                            Task {
                                await model.removeFriendship(
                                    with: card.otherUserID
                                )
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .listRowBackground(Color.clear)
                }
                .trustScreenBackground()
            } else {
                ContentUnavailableView(
                    "Relationship unavailable",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text(
                        "It may have changed since the last refresh."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CompetitiveTrustTheme.ink)
            }
        }
        .navigationTitle("Friend")
        .navigationBarTitleDisplayMode(.inline)
    }
}
