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

    private var canOpenChallengeFlow: Bool {
        model.configuration.contestMutationsEnabled
            && !model.hasPendingChallengeRecoveryIssue
            && (model.pendingChallenge != nil
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

            if let pendingChallenge = model.pendingChallenge {
                Section("Saved request") {
                    VStack(alignment: .leading, spacing: 10) {
                        TrustStatusPill(
                            text: model.hasPendingChallengeRecoveryIssue
                                ? "Protected storage needs attention"
                                : "Explicit retry required",
                            kind: .action
                        )
                        Text(pendingChallenge.terms.title)
                            .font(.headline)
                        Text(
                            "\(pendingChallenge.terms.inviteeIDs.count) \(pendingChallenge.terms.inviteeIDs.count == 1 ? "friend" : "friends") invited"
                        )
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        Text(
                            model.hasPendingChallengeRecoveryIssue
                                ? "GameTime kept the saved request, but protected storage must recover before it can be retried safely."
                                : "GameTime kept the exact immutable terms and request ID after an unconfirmed response. It will never retry automatically."
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if model.hasPendingChallengeRecoveryIssue {
                            Button("Try protected storage again") {
                                Task {
                                    await model.retryPendingChallengeRecovery()
                                }
                            }
                            .buttonStyle(TrustSecondaryButtonStyle())
                            .disabled(model.isMutating)
                            .accessibilityIdentifier(
                                "challenge.pending.retry-storage"
                            )
                        }

                        Button {
                            router.presentedSheet = .createChallenge
                        } label: {
                            Label(
                                "Review saved challenge",
                                systemImage: "arrow.clockwise"
                            )
                        }
                        .buttonStyle(TrustPrimaryButtonStyle())
                        .disabled(
                            model.isMutating
                                || model.hasPendingChallengeRecoveryIssue
                        )
                        .accessibilityIdentifier("challenge.pending.resume")

                        Button(
                            "Discard local retry record",
                            role: .destructive
                        ) {
                            showingDiscardConfirmation = true
                        }
                        .disabled(model.isMutating)
                        .accessibilityIdentifier(
                            "challenge.pending.discard-list"
                        )
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(CompetitiveTrustTheme.raisedInk)
            } else if model.hasPendingChallengeRecoveryIssue {
                Section("Saved request needs attention") {
                    Label(
                        "GameTime could not validate protected retry storage. New challenge requests stay locked to avoid accidental duplicates.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    Button("Try protected storage again") {
                        Task {
                            await model.retryPendingChallengeRecovery()
                        }
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(model.isMutating)
                    .accessibilityIdentifier("challenge.pending.retry-storage")

                    Button(
                        "Discard unreadable local retry",
                        role: .destructive
                    ) {
                        showingDiscardConfirmation = true
                    }
                    .disabled(model.isMutating)
                    .accessibilityIdentifier("challenge.pending.discard-list")
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
                Section("Your challenges") {
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
                    title: "No challenges yet",
                    message:
                        "Create a challenge with one or more accepted friends. Terms stay fixed after submission.",
                    systemImage: "flag.checkered"
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            }

            Section {
                Button {
                    router.presentedSheet = .createChallenge
                } label: {
                    Label(
                        model.pendingChallenge == nil
                            ? "Create a challenge"
                            : "Review saved challenge",
                        systemImage: model.pendingChallenge == nil
                            ? "plus"
                            : "arrow.clockwise"
                    )
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(!canOpenChallengeFlow)
                .accessibilityIdentifier("challenge.create")
                .listRowBackground(Color.clear)
            } footer: {
                if model.hasPendingChallengeRecoveryIssue {
                    Text(
                        "Discard the unreadable retry only after confirming you want to abandon its idempotency key."
                    )
                } else if model.pendingChallenge != nil {
                    Text(
                        "Resume reuses the saved request UUID and terms. Starting a second challenge is blocked until this request is confirmed or discarded."
                    )
                } else if model.acceptedFriendships.isEmpty {
                    Text("Accept a friendship before creating a challenge.")
                } else {
                    Text(
                        "Choose up to \(ChallengeTerms.maximumInvitees) friends. One atomic request creates the challenge and every invitation. No real pledge is enabled."
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
                    router.presentedSheet = .createChallenge
                } label: {
                    Image(
                        systemName: model.pendingChallenge == nil
                            ? "plus"
                            : "arrow.clockwise"
                    )
                }
                .disabled(!canOpenChallengeFlow)
                .accessibilityLabel(
                    model.pendingChallenge == nil
                        ? "Create a challenge"
                        : "Review saved challenge"
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
                    _ = await model.discardPendingChallenge()
                }
            }
            Button("Keep saved request", role: .cancel) {}
        } message: {
            Text(
                "This deletes only the on-device retry record; it does not cancel a contest or invitation the server may already have created. Starting over after a committed request can create a second challenge."
            )
        }
    }
}

extension View {
    fileprivate func challengeListRow() -> some View {
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
