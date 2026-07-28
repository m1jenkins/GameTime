import SwiftUI

/// The screen you open ten times a day mid-duel. The rope is the whole point;
/// everything else supports it.
struct ContestDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    let contestID: UUID

    private var contest: ContestCard? {
        model.contests.first { $0.id == contestID }
    }

    var body: some View {
        Group {
            if let contest {
                content(contest)
            } else {
                unavailable
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func content(_ contest: ContestCard) -> some View {
        let standing = model.standing(for: contest.id)

        return TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(spacing: 0) {
                GlassNavRow(backTitle: backTitle, back: { dismiss() }) {
                    if contest.status == .active {
                        AmberPill(
                            systemImage: "clock",
                            text: DuelClock.remainingText(
                                until: contest.endsAt,
                                now: context.date
                            )
                        )
                    } else {
                        AmberPill(
                            systemImage: "clock",
                            text: statusPillText(contest)
                        )
                    }
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 13) {
                        titleBlock(contest, standing: standing)

                        HeroRopeCard(
                            contest: contest,
                            standing: standing,
                            myInitials: model.profile?.initials ?? "?",
                            now: context.date
                        )

                        statCards(contest, standing: standing)

                        if !standing.events.isEmpty {
                            RopeTimeline(events: standing.events)
                        }
                    }
                    .padding(.horizontal, GlassArenaLayout.detailPadding)
                    .padding(.top, 6)
                    .padding(.bottom, 18)
                    .frame(maxWidth: GlassArenaMetrics.contentCap)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .glassArenaBackground(.duelDetail, lift: lift(standing))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar(contest, standing: standing)
            }
        }
    }

    private var backTitle: String {
        router.selectedTab == .today ? "Today" : "Duels"
    }

    private func statusPillText(_ contest: ContestCard) -> String {
        switch contest.status {
        case .pending: contest.myStatus == .invited ? "Your move" : "Not started"
        case .active: DuelClock.remainingText(until: contest.endsAt)
        case .finalized: "Settled"
        case .cancelled: "Called off"
        }
    }

    private func lift(_ standing: DuelStanding) -> (yours: CGFloat, theirs: CGFloat)? {
        guard standing.hasProgress else { return nil }
        let combined = standing.myProgress + standing.theirProgress
        guard combined > 0 else { return nil }
        return (
            yours: CGFloat(standing.myProgress / combined),
            theirs: CGFloat(standing.theirProgress / combined)
        )
    }

    // MARK: Title

    private func titleBlock(
        _ contest: ContestCard,
        standing: DuelStanding
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(contest.title)
                .font(GlassArenaFont.display(31, .heavy))
                .foregroundStyle(GlassArena.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(contest.termsLine(charityName: standing.charityName))
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.muted)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    // MARK: Stats

    @ViewBuilder
    private func statCards(
        _ contest: ContestCard,
        standing: DuelStanding
    ) -> some View {
        let display = contest.display
        let opponentName = standing.opponent?.firstName

        HStack(spacing: 11) {
            GlassStatCard(
                systemImage: "bolt",
                label: opponentName.map { "\($0)'s best" } ?? "Their best",
                value: standing.opponentBest
                    .map { display.measurement($0.value) } ?? "—",
                qualifier: standing.opponentBest?.dayLabel
            )
            GlassStatCard(
                systemImage: "clock",
                label: "Your streak",
                value: standing.yourStreakDays
                    .map { "\($0) day\($0 == 1 ? "" : "s")" } ?? "—",
                qualifier: standing.yourStreakDays == nil ? nil : "hit"
            )
        }
    }

    // MARK: Action bar

    @ViewBuilder
    private func actionBar(
        _ contest: ContestCard,
        standing: DuelStanding
    ) -> some View {
        if contest.myStatus == .invited {
            HStack(spacing: 10) {
                Button {
                    router.presentedSheet = .acceptInvitation(contest.id)
                } label: {
                    Label(
                        "Take it — \(contest.stakeCompactText)",
                        systemImage: "checkmark"
                    )
                }
                .buttonStyle(GlassPrimaryButtonStyle(height: 56, fontSize: 17))
                .disabled(
                    !model.configuration.contestMutationsEnabled
                        || model.isMutating
                )
                .accessibilityIdentifier("detail.accept")

                Button("Nope") {
                    Task {
                        await model.declineInvitation(contestID: contest.id)
                        dismiss()
                    }
                }
                .buttonStyle(GlassQuietButtonStyle(height: 56, cornerRadius: 20))
                .frame(width: 96)
                .disabled(
                    !model.configuration.contestMutationsEnabled
                        || model.isMutating
                )
                .accessibilityIdentifier("detail.decline")
            }
            .padding(.horizontal, GlassArenaLayout.detailPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
        } else if contest.status == .finalized {
            Button {
                appendResultRoute(contest.id)
            } label: {
                Label("See the receipt", systemImage: "checkmark.seal")
            }
            .buttonStyle(GlassPrimaryButtonStyle(height: 56, fontSize: 17))
            .padding(.horizontal, GlassArenaLayout.detailPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .accessibilityIdentifier("detail.result")
        } else {
            HStack(spacing: 10) {
                Button {
                    openTrashTalk(contest, standing: standing)
                } label: {
                    Label("Talk trash", systemImage: "bubble.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GlassDarkButtonStyle())
                .accessibilityIdentifier("detail.talk-trash")

                ShareLink(item: shareSummary(contest, standing: standing)) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(GlassArena.ink)
                        .frame(width: 56, height: 56)
                        .glassPane(.standard, cornerRadius: 20)
                }
                .accessibilityIdentifier("detail.share")
                .accessibilityLabel("Share this duel")
            }
            .padding(.horizontal, GlassArenaLayout.detailPadding)
            .padding(.top, 12)
            .padding(.bottom, 8)
        }
    }

    private func appendResultRoute(_ id: UUID) {
        if router.selectedTab == .today {
            router.todayPath.append(.result(id))
        } else {
            router.duelsPath.append(.result(id))
        }
    }

    /// There is no in-app messaging, so "Talk trash" hands a pre-composed line
    /// to Messages and lets you pick who gets it.
    private func openTrashTalk(
        _ contest: ContestCard,
        standing: DuelStanding
    ) {
        let body = trashTalk(contest, standing: standing)
        guard
            let encoded = body.addingPercentEncoding(
                withAllowedCharacters: .alphanumerics
            ),
            let url = URL(string: "sms:&body=\(encoded)")
        else {
            return
        }
        openURL(url)
    }

    private func trashTalk(
        _ contest: ContestCard,
        standing: DuelStanding
    ) -> String {
        guard standing.hasProgress else {
            return "\(contest.title) is live. Hope you stretched."
        }
        let copy = DeficitCopy(standing: standing, metric: contest.metric)
        if standing.isAhead {
            return
                "\(copy.magnitude) up on \(contest.title). The rope isn't coming back."
        }
        if standing.isLevel {
            return "Dead even on \(contest.title). Blink first."
        }
        return
            "\(copy.magnitude) back on \(contest.title). Enjoy it while it lasts."
    }

    private func shareSummary(
        _ contest: ContestCard,
        standing: DuelStanding
    ) -> String {
        let display = contest.display
        let them = standing.opponent?.firstName ?? "them"
        return
            "\(contest.title): me \(display.measurement(standing.myProgress)), \(them) \(display.measurement(standing.theirProgress)). \(contest.stakeCompactText) on the line."
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "bolt.slash")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(GlassArena.mutedLight)
            Text("This duel is gone")
                .font(GlassArenaFont.display(24, .heavy))
                .foregroundStyle(GlassArena.ink)
            Text("Pull to refresh the list and try again.")
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.inkTertiary)
            Button("Back") { dismiss() }
                .buttonStyle(GlassSecondaryButtonStyle())
                .frame(maxWidth: 200)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassArenaBackground(.duelDetail)
    }
}

// MARK: - Hero rope card

/// The rope at full size: both athletes, both scores, the cord with its tension
/// ticks and weave, and the gap stated as a daily pace.
struct HeroRopeCard: View {
    let contest: ContestCard
    let standing: DuelStanding
    let myInitials: String
    var now = Date()

    private var display: MetricDisplay { contest.display }

    var body: some View {
        VStack(spacing: 22) {
            avatarRow
            scoreRow
            DuelRope(
                standing: standing,
                metric: contest.metric,
                size: .hero
            )
            if standing.hasProgress {
                DeficitCallout(
                    standing: standing,
                    contest: contest,
                    now: now
                )
                .padding(.top, -6)
            } else {
                Text("No progress synced yet — the rope sits at parity.")
                    .font(GlassArenaFont.text(14))
                    .foregroundStyle(GlassArena.inkTertiary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, -6)
            }

            if let lastSyncedAt = standing.lastSyncedAt,
                DuelClock.isStale(lastSyncedAt, now: now)
            {
                StaleHealthRow(lastSyncedAt: lastSyncedAt, now: now)
                    .padding(.top, -10)
            }
        }
        .padding(.top, 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 22)
        .glassPane(.hero, cornerRadius: 36)
    }

    private var avatarRow: some View {
        HStack {
            athlete(
                initials: myInitials,
                name: "You",
                side: .you
            )
            Text("VS")
                .font(GlassArenaFont.display(13, .heavy))
                .tracking(1.8)
                .foregroundStyle(GlassArena.mutedLightest)
                .frame(maxWidth: .infinity)
            athlete(
                initials: standing.opponent?.initials ?? "?",
                name: standing.opponent?.firstName ?? "Them",
                side: .them
            )
        }
    }

    private func athlete(
        initials: String,
        name: String,
        side: GlassAvatar.Side
    ) -> some View {
        VStack(spacing: 7) {
            GlassAvatar(
                initials: initials,
                size: 54,
                side: side,
                ringWidth: 2.5,
                showsGlow: true
            )
            Text(name)
                .font(GlassArenaFont.text(13, .bold))
                .foregroundStyle(GlassArena.ink)
        }
        .frame(width: 96)
        .accessibilityElement(children: .combine)
    }

    private var scoreRow: some View {
        GeometryReader { proxy in
            let scoreSize = GlassArenaMetrics.heroScore(width: proxy.size.width)
            HStack(alignment: .bottom) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(display.number(standing.myProgress))
                        .font(GlassArenaFont.display(scoreSize, .heavy))
                        .foregroundStyle(GlassArena.teal900)
                    Text(display.unit)
                        .font(GlassArenaFont.text(14, .semibold))
                        .foregroundStyle(GlassArena.mutedLight)
                }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(display.unit)
                        .font(GlassArenaFont.text(14, .semibold))
                        .foregroundStyle(GlassArena.mutedLight)
                    Text(display.number(standing.theirProgress))
                        .font(GlassArenaFont.display(scoreSize, .heavy))
                        .foregroundStyle(GlassArena.violet800)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        // Tucked under the avatars, as drawn.
        .frame(height: 44)
        .padding(.top, -8)
    }
}

// MARK: - Friend detail

struct FriendshipDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    let userID: UUID

    private var card: FriendshipCard? {
        model.friendshipCards.first { $0.otherUserID == userID }
    }

    var body: some View {
        Group {
            if let card {
                content(card)
            } else {
                unavailable
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private func content(_ card: FriendshipCard) -> some View {
        VStack(spacing: 0) {
            GlassNavRow(
                backTitle: router.selectedTab == .today ? "Today" : "Friends",
                back: { dismiss() }
            ) {
                EmptyView()
            }

            ScrollView {
                VStack(spacing: 15) {
                    VStack(spacing: 10) {
                        GlassAvatar(
                            initials: card.profileCard.initials,
                            size: 72,
                            side: .them
                        )
                        Text(card.displayName)
                            .font(GlassArenaFont.display(26, .heavy))
                            .foregroundStyle(GlassArena.ink)
                        Text("@\(card.handle)")
                            .font(GlassArenaFont.text(14))
                            .foregroundStyle(GlassArena.mutedLight)
                        Text(
                            card.status == .accepted
                                ? "On your roster"
                                : "Waiting on a reply"
                        )
                        .font(GlassArenaFont.text(12, .bold))
                        .tracking(0.8)
                        .foregroundStyle(
                            card.status == .accepted
                                ? GlassArena.teal900
                                : GlassArena.amber800
                        )
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(
                                (card.status == .accepted
                                    ? GlassArena.teal700
                                    : GlassArena.amber400)
                                    .opacity(0.16)
                            )
                        )
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    .glassPane(.hero, cornerRadius: 32)

                    if card.status == .accepted {
                        Button {
                            router.presentedSheet = .createDuel
                        } label: {
                            Label("Duel \(card.profileCard.firstName)", systemImage: "bolt.fill")
                        }
                        .buttonStyle(GlassPrimaryButtonStyle(height: 54))
                        .disabled(!model.canStartDuel)
                        .accessibilityIdentifier("friend.duel")
                    } else if card.direction(for: model.userID ?? UUID())
                        == .incoming
                    {
                        Button {
                            Task {
                                await model.acceptFriendship(
                                    with: card.otherUserID
                                )
                            }
                        } label: {
                            Label("Add \(card.profileCard.firstName)", systemImage: "checkmark")
                        }
                        .buttonStyle(GlassPrimaryButtonStyle(height: 54))
                        .disabled(model.isMutating)
                    }

                    Button(
                        card.status == .accepted
                            ? "Remove friend"
                            : "Cancel request"
                    ) {
                        Task {
                            await model.removeFriendship(
                                with: card.otherUserID
                            )
                            dismiss()
                        }
                    }
                    .font(GlassArenaFont.text(15, .semibold))
                    .foregroundStyle(GlassArena.destructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .disabled(model.isMutating)
                }
                .padding(.horizontal, GlassArenaLayout.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, GlassArenaLayout.scrollBottomInset)
                .frame(maxWidth: GlassArenaMetrics.contentCap)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassArenaBackground(.today)
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(GlassArena.mutedLight)
            Text("Not on your roster")
                .font(GlassArenaFont.display(24, .heavy))
                .foregroundStyle(GlassArena.ink)
            Text("This may have changed since the last refresh.")
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.inkTertiary)
            Button("Back") { dismiss() }
                .buttonStyle(GlassSecondaryButtonStyle())
                .frame(maxWidth: 200)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassArenaBackground(.today)
    }
}
