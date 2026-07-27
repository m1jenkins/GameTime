import SwiftUI

struct ChallengesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var showingDiscardConfirmation = false

    private var history: [ContestCard] {
        model.contests.filter {
            $0.status == .cancelled || $0.status == .finalized
        }
    }

    private var canOpenDuelFlow: Bool {
        model.configuration.contestMutationsEnabled
            && !model.hasPendingDuelRecoveryIssue
            && (model.pendingDuel != nil
                || !model.acceptedFriendships.isEmpty)
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

            if let pendingDuel = model.pendingDuel {
                Section("Saved request") {
                    VStack(alignment: .leading, spacing: 10) {
                        TrustStatusPill(
                            text: model.hasPendingDuelRecoveryIssue
                                ? "Protected storage needs attention"
                                : "Explicit retry required",
                            kind: .action
                        )
                        Text(pendingDuel.terms.title)
                            .font(.headline)
                        Text(
                            model.hasPendingDuelRecoveryIssue
                                ? "GameTime kept the saved request, but protected storage must recover before it can be retried safely."
                                : "GameTime kept the exact immutable terms and request ID after an unconfirmed response. It will never retry automatically."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if model.hasPendingDuelRecoveryIssue {
                            Button("Try protected storage again") {
                                Task {
                                    await model.retryPendingDuelRecovery()
                                }
                            }
                            .buttonStyle(TrustSecondaryButtonStyle())
                            .disabled(model.isMutating)
                            .accessibilityIdentifier(
                                "duel.pending.retry-storage"
                            )
                        }

                        Button {
                            router.presentedSheet = .createDuel
                        } label: {
                            Label(
                                "Review saved duel",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .buttonStyle(TrustPrimaryButtonStyle())
                        .disabled(
                            model.isMutating
                                || model.hasPendingDuelRecoveryIssue
                        )
                        .accessibilityIdentifier("duel.pending.resume")

                        Button(
                            "Discard local retry record",
                            role: .destructive
                        ) {
                            showingDiscardConfirmation = true
                        }
                        .disabled(model.isMutating)
                        .accessibilityIdentifier(
                            "duel.pending.discard-list"
                        )
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(CompetitiveTrustTheme.raisedInk)
            } else if model.hasPendingDuelRecoveryIssue {
                Section("Saved request needs attention") {
                    Label(
                        "GameTime could not validate protected retry storage. New duel requests stay locked to avoid accidental duplicates.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Button("Try protected storage again") {
                        Task {
                            await model.retryPendingDuelRecovery()
                        }
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(model.isMutating)
                    .accessibilityIdentifier("duel.pending.retry-storage")

                    Button(
                        "Discard unreadable local retry",
                        role: .destructive
                    ) {
                        showingDiscardConfirmation = true
                    }
                    .disabled(model.isMutating)
                    .accessibilityIdentifier("duel.pending.discard-list")
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
                    Label(
                        model.pendingDuel == nil
                            ? "Create a duel"
                            : "Review saved duel",
                        systemImage: model.pendingDuel == nil
                            ? "plus"
                            : "arrow.clockwise"
                    )
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(!canOpenDuelFlow)
                .accessibilityIdentifier("challenge.create")
                .listRowBackground(Color.clear)
            } footer: {
                if model.hasPendingDuelRecoveryIssue {
                    Text(
                        "Discard the unreadable retry only after confirming you want to abandon its idempotency key."
                    )
                } else if model.pendingDuel != nil {
                    Text(
                        "Resume reuses the saved request UUID and terms. Starting a second duel is blocked until this request is confirmed or discarded."
                    )
                } else if model.acceptedFriendships.isEmpty {
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
                    Image(
                        systemName: model.pendingDuel == nil
                            ? "plus"
                            : "arrow.clockwise"
                    )
                }
                .disabled(!canOpenDuelFlow)
                .accessibilityLabel(
                    model.pendingDuel == nil
                        ? "Create a duel"
                        : "Review saved duel"
                )
            }
        }
        .confirmationDialog(
            "Discard the local retry record?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard local retry", role: .destructive) {
                Task {
                    _ = await model.discardPendingDuel()
                }
            }
            Button("Keep saved request", role: .cancel) {}
        } message: {
            Text(
                "This deletes only the on-device retry record; it does not cancel a contest or invitation the server may already have created. Starting over after a committed request can create a second duel."
            )
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
