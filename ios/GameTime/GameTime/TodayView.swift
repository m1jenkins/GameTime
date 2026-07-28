import SwiftUI

/// Lands you in your current standing and surfaces the one or two things needing
/// a response. The headline is a live taunt, not a greeting.
struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private var headlineContest: ContestCard? { model.headlineContest }

    private var headlineStanding: DuelStanding? {
        headlineContest.map { model.standing(for: $0.id) }
    }

    /// Both curves lift with their athlete's share, so the background carries
    /// the same story as the rope.
    private var substrateLift: (yours: CGFloat, theirs: CGFloat)? {
        guard let standing = headlineStanding, standing.hasProgress else {
            return nil
        }
        let combined = standing.myProgress + standing.theirProgress
        guard combined > 0 else { return nil }
        return (
            yours: CGFloat(standing.myProgress / combined),
            theirs: CGFloat(standing.theirProgress / combined)
        )
    }

    private var isLoadingFirstTime: Bool {
        model.loadState == .loading && model.contests.isEmpty
            && model.friendshipCards.isEmpty
    }

    private var hasNothingWaiting: Bool {
        model.incomingFriendships.isEmpty && model.invitations.isEmpty
    }

    var body: some View {
        // A slow tick: the countdown is coarse, so it never redraws per second.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            GlassArenaScreenScaffold(
                screen: .today,
                lift: substrateLift,
                identifier: "screen.today"
            ) {
                header(now: context.date)

                if case .failed(let message) = model.loadState {
                    GlassRetryRow(message: message) {
                        Task { await model.refresh() }
                    }
                }

                if isLoadingFirstTime {
                    HeroDuelCardPlaceholder()
                } else if let headlineContest, let headlineStanding {
                    Button {
                        router.todayPath.append(.contest(headlineContest.id))
                    } label: {
                        HeroDuelCard(
                            contest: headlineContest,
                            standing: headlineStanding,
                            myInitials: model.profile?.initials ?? "You",
                            now: context.date
                        )
                    }
                    .buttonStyle(GlassCardButtonStyle())
                    .accessibilityIdentifier("today.hero-duel")
                } else if !isLoadingFirstTime {
                    EmptyDuelsCard(
                        title: "Nobody's challenged you.",
                        message:
                            "Pick a friend, pick a number, put something on it.",
                        actionTitle: "Start a duel",
                        isEnabled: model.canStartDuel
                    ) {
                        router.presentedSheet = .createDuel
                    }
                }

                if !hasNothingWaiting {
                    SectionEyebrow(text: "Waiting on you")
                        .padding(.leading, 8)
                        .padding(.top, 2)
                }

                ForEach(model.invitations) { invitation in
                    inviteCard(invitation)
                }

                ForEach(model.incomingFriendships) { card in
                    FriendRequestRow(
                        displayName: card.displayName,
                        handle: card.handle,
                        actionTitle: "Add",
                        isEnabled: !model.isMutating,
                        action: {
                            Task {
                                await model.acceptFriendship(
                                    with: card.otherUserID
                                )
                            }
                        },
                        tap: {
                            router.todayPath.append(
                                .friendship(card.otherUserID)
                            )
                        }
                    )
                }

                completedRows
            }
        }
    }

    // MARK: Header

    private func header(now: Date) -> some View {
        HStack(alignment: .bottom) {
            GlassScreenTitle(
                eyebrow: DuelClock.todayEyebrow(
                    nextEnd: headlineContest?.endsAt,
                    now: now
                ),
                title: headlineStanding?.headline ?? "Rope's up."
            )
            Spacer(minLength: 12)
            GlassAvatar(
                initials: model.profile?.initials ?? "?",
                size: 42,
                side: .you
            )
        }
        .padding(.horizontal, 4)
    }

    // MARK: Rows

    private func inviteCard(_ invitation: ContestCard) -> some View {
        let opponent = model.opponent(for: invitation)
        let display = invitation.display
        let days = max(
            1,
            Int(
                (invitation.endsAt.timeIntervalSince(invitation.startsAt)
                    / 86_400).rounded()
            )
        )
        // No identifier on the card itself: SwiftUI pushes it down onto the
        // buttons inside and would clobber their own.
        return InviteCard(
            initials: opponent?.initials ?? "?",
            title: opponent.map { "\($0.firstName) threw down" }
                ?? invitation.title,
            terms:
                "\(invitation.targetLine) · \(days) day\(days == 1 ? "" : "s") · \(invitation.stakeCompactText)",
            acceptTitle: "Take it",
            isEnabled: model.configuration.contestMutationsEnabled
                && !model.isMutating,
            accept: {
                router.presentedSheet = .acceptInvitation(invitation.id)
            },
            decline: {
                Task {
                    await model.declineInvitation(contestID: invitation.id)
                }
            }
        )
    }

    @ViewBuilder
    private var completedRows: some View {
        let completed = Array(model.completedContests.prefix(1))
        ForEach(Array(completed.enumerated()), id: \.element.id) { _, contest in
            Button {
                router.todayPath.append(.result(contest.id))
            } label: {
                CompletedDuelRow(
                    title: contest.title,
                    outcome: model.settlementSummary(for: contest),
                    didWin: model.didWin(contest),
                    slidesUnderTabBar: true
                )
            }
            .buttonStyle(GlassCardButtonStyle())
            .accessibilityIdentifier("today.completed")
        }
    }
}

// MARK: - Hero duel card

/// Today's duel card: who is where, the rope, and the gap in human terms.
struct HeroDuelCard: View {
    let contest: ContestCard
    let standing: DuelStanding
    let myInitials: String
    var now = Date()

    private var display: MetricDisplay { contest.display }

    private var comparison: String {
        DeficitCopy.humanComparison(
            gap: abs(standing.deficit),
            metric: contest.metric,
            isBehind: !standing.isAhead
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                DuelEyebrow(text: contest.title)
                Spacer(minLength: 8)
                AmberPill(
                    text: contest.stakeCompactText,
                    fontSize: 14,
                    isDisplayFont: true
                )
            }

            athleteRow

            DuelRope(
                standing: standing,
                metric: contest.metric,
                size: .medium
            )

            if standing.hasProgress {
                HStack(spacing: 7) {
                    Text(
                        DeficitCopy(
                            standing: standing,
                            metric: contest.metric
                        ).shortHeadline
                    )
                    .font(GlassArenaFont.display(15, .heavy))
                    .foregroundStyle(
                        standing.isAhead
                            ? GlassArena.teal900
                            : GlassArena.violet800
                    )
                    Text("— \(comparison)")
                        .font(GlassArenaFont.text(14))
                        .foregroundStyle(GlassArena.inkTertiary)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
            } else {
                Text("Waiting on Apple Health to report the first numbers.")
                    .font(GlassArenaFont.text(14))
                    .foregroundStyle(GlassArena.inkTertiary)
                    .frame(maxWidth: .infinity)
            }

            if let lastSyncedAt = standing.lastSyncedAt,
                DuelClock.isStale(lastSyncedAt, now: now)
            {
                StaleHealthRow(lastSyncedAt: lastSyncedAt, now: now)
            }
        }
        .padding(.top, 20)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .glassPane(.hero, cornerRadius: 34)
    }

    private var athleteRow: some View {
        HStack(alignment: .bottom) {
            HStack(spacing: 9) {
                GlassAvatar(
                    initials: myInitials,
                    size: 38,
                    side: .you,
                    ringWidth: 2
                )
                scoreBlock(
                    name: "You",
                    value: standing.myProgress,
                    alignment: .leading
                )
            }

            Spacer(minLength: 8)

            HStack(spacing: 9) {
                scoreBlock(
                    name: standing.opponent?.firstName ?? "Them",
                    value: standing.theirProgress,
                    alignment: .trailing
                )
                GlassAvatar(
                    initials: standing.opponent?.initials ?? "?",
                    size: 38,
                    side: .them,
                    ringWidth: 2
                )
            }
        }
    }

    private func scoreBlock(
        name: String,
        value: Double,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(name)
                .font(GlassArenaFont.text(12, .semibold))
                .foregroundStyle(GlassArena.mutedLight)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(display.number(value))
                    .font(GlassArenaFont.display(24, .heavy))
                    .foregroundStyle(GlassArena.ink)
                Text(display.unit)
                    .font(GlassArenaFont.text(13, .semibold))
                    .foregroundStyle(GlassArena.mutedLight)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name), \(display.measurement(value))")
    }
}

/// Loading renders the pane's full structure with values as shimmering blocks.
struct HeroDuelCardPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                ShimmerBlock(width: 130, height: 13)
                Spacer()
                ShimmerBlock(width: 44, height: 22, cornerRadius: 11)
            }
            HStack {
                ShimmerBlock(width: 38, height: 38, cornerRadius: 19)
                ShimmerBlock(width: 74, height: 26)
                Spacer()
                ShimmerBlock(width: 74, height: 26)
                ShimmerBlock(width: 38, height: 38, cornerRadius: 19)
            }
            ShimmerBlock(height: 14, cornerRadius: 7)
                .padding(.vertical, 12)
            ShimmerBlock(width: 190, height: 15)
                .frame(maxWidth: .infinity)
        }
        .padding(.top, 20)
        .padding(.horizontal, 18)
        .padding(.bottom, 18)
        .glassPane(.hero, cornerRadius: 34)
        .accessibilityIdentifier("state.loading")
        .accessibilityLabel("Loading your duel")
    }
}
