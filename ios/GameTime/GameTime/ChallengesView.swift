import SwiftUI

// Daybreak challenge list imported from the Claude Design source.
struct ChallengesView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var showingDiscardConfirmation = false

    private var running: [ContestCard] {
        model.activeAndUpcomingContests.filter {
            $0.status == .active
        }
    }

    private var startingSoon: [ContestCard] {
        model.activeAndUpcomingContests.filter {
            $0.status == .pending
        }
    }

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
        ScrollView {
            LazyVStack(spacing: 11) {
                releaseLockCard
                pendingRecoveryCard

                challengeSection(
                    label: "Needs your answer",
                    contests: model.invitations
                )
                challengeSection(
                    label: "Running",
                    contests: running
                )
                challengeSection(
                    label: "Starting soon",
                    contests: startingSoon
                )
                challengeSection(
                    label: "History",
                    contests: history
                )

                if model.contests.isEmpty,
                    model.loadState != .loading
                {
                    DaybreakCard {
                        EmptyTrustState(
                            title: "No challenges yet",
                            message:
                                "Create a challenge with one or more accepted friends. Terms stay fixed after submission.",
                            systemImage: "flag.checkered"
                        )
                    }
                }

                createChallengeControl
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .background(CompetitiveTrustTheme.paper.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .navigationTitle("Challenges")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(
            CompetitiveTrustTheme.paper,
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
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
                    .font(.system(size: 15, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(
                        CompetitiveTrustTheme.coralTint,
                        in: Circle()
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
                "This deletes only the on-device retry record; it does not cancel a challenge or invitation the server may already have created. Starting over after a committed request can create a second challenge."
            )
        }
    }

    @ViewBuilder
    private var releaseLockCard: some View {
        if !model.configuration.contestMutationsEnabled {
            DaybreakCard {
                Label(
                    "Challenge changes are locked in Release until the evidence and App Attest slice is complete.",
                    systemImage: "lock.shield"
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 13,
                        relativeTo: .subheadline
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private var pendingRecoveryCard: some View {
        if let pendingChallenge = model.pendingChallenge {
            DaybreakSectionLabel(text: "Saved request")
            DaybreakCard {
                VStack(alignment: .leading, spacing: 11) {
                    TrustStatusPill(
                        text: model.hasPendingChallengeRecoveryIssue
                            ? "Protected storage needs attention"
                            : "Explicit retry required",
                        kind: .action
                    )
                    Text(pendingChallenge.terms.title)
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 20,
                                relativeTo: .headline
                            )
                        )
                    Text(
                        "\(pendingChallenge.terms.inviteeIDs.count) \(pendingChallenge.terms.inviteeIDs.count == 1 ? "friend" : "friends") invited"
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 12,
                            relativeTo: .caption,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    Text(
                        model.hasPendingChallengeRecoveryIssue
                            ? "GameTime kept the saved request, but protected storage must recover before it can be retried safely."
                            : "GameTime kept the exact immutable terms and request ID after an unconfirmed response. It will never retry automatically."
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)

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
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline,
                            weight: .bold
                        )
                    )
                    .disabled(model.isMutating)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(
                        "challenge.pending.discard-list"
                    )
                }
            }
        } else if model.hasPendingChallengeRecoveryIssue {
            DaybreakSectionLabel(text: "Saved request needs attention")
            DaybreakCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        "GameTime could not validate protected retry storage. New challenge requests stay locked to avoid accidental duplicates.",
                        systemImage: "exclamationmark.shield"
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)

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

                    Button(
                        "Discard unreadable local retry",
                        role: .destructive
                    ) {
                        showingDiscardConfirmation = true
                    }
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline,
                            weight: .bold
                        )
                    )
                    .disabled(model.isMutating)
                    .frame(maxWidth: .infinity)
                    .accessibilityIdentifier(
                        "challenge.pending.discard-list"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func challengeSection(
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
                    router.challengesPath.append(
                        .contest(contest.id)
                    )
                }
            }
        }
    }

    private var createChallengeControl: some View {
        VStack(alignment: .leading, spacing: 9) {
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

            Text(createFooterText)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .lineSpacing(2)
                .padding(.horizontal, 6)
        }
        .padding(.top, 6)
    }

    private var createFooterText: String {
        if model.hasPendingChallengeRecoveryIssue {
            return "Discard the unreadable retry only after confirming you want to abandon its idempotency key."
        }
        if model.pendingChallenge != nil {
            return "Resume reuses the saved request UUID and terms. A second challenge stays blocked until this request is confirmed or discarded."
        }
        if model.acceptedFriendships.isEmpty {
            return "Accept a friendship before creating a challenge."
        }
        return "Choose up to \(ChallengeTerms.maximumInvitees) friends. One atomic request creates the challenge and every invitation. No real pledge is enabled."
    }
}
