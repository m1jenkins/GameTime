import SwiftUI

/// Every duel in one list, sorted by who needs attention.
struct DuelsView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var showingDiscardConfirmation = false

    private var segmentItems: [GlassSegmentedControl<DuelsSegment>.Item] {
        DuelsSegment.allCases.map { segment in
            .init(
                segment: segment,
                title: segment.title,
                badge: segment == .invites ? model.invitations.count : nil
            )
        }
    }

    var body: some View {
        @Bindable var router = router

        ZStack(alignment: .bottom) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                GlassArenaScreenScaffold(
                    screen: .duels,
                    identifier: "screen.duels",
                    spacing: 13
                ) {
                    titleRow

                    GlassSegmentedControl(
                        items: segmentItems,
                        selection: $router.duelsSegment
                    )

                    if case .failed(let message) = model.loadState {
                        GlassRetryRow(message: message) {
                            Task { await model.refresh() }
                        }
                    }

                    if !model.configuration.contestMutationsEnabled {
                        lockedNotice
                    }

                    // The saved-request card always shows: it gates starting a
                    // second duel, so it cannot hide behind a segment.
                    if model.pendingDuel != nil
                        || model.hasPendingDuelRecoveryIssue
                    {
                        SavedRequestCard(
                            showingDiscardConfirmation:
                                $showingDiscardConfirmation
                        )
                    }

                    segmentContent(now: context.date)
                }
            }

            floatingCreateButton
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

    // MARK: Title

    private var titleRow: some View {
        HStack(alignment: .center) {
            Text("Duels")
                .font(GlassArenaFont.display(33, .heavy))
                .foregroundStyle(GlassArena.ink)
            Spacer()
            HStack(spacing: 5) {
                Text("\(model.record.won)W")
                    .font(GlassArenaFont.display(15, .heavy))
                    .foregroundStyle(GlassArena.teal900)
                Text("·")
                    .font(GlassArenaFont.text(14))
                    .foregroundStyle(GlassArena.hairline)
                Text("\(model.record.lost)L")
                    .font(GlassArenaFont.display(15, .heavy))
                    .foregroundStyle(GlassArena.mutedLighter)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Record: \(model.record.won) won, \(model.record.lost) lost"
            )
        }
        .padding(.horizontal, 4)
    }

    private var lockedNotice: some View {
        HStack(spacing: 9) {
            Image(systemName: "lock.shield")
                .font(.system(size: 14, weight: .semibold))
            Text(
                "Duel changes are locked in Release until the evidence and App Attest slice ships."
            )
            .font(GlassArenaFont.text(13))
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(GlassArena.inkTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .glassPane(.recessed, cornerRadius: 24)
    }

    // MARK: Segments

    @ViewBuilder
    private func segmentContent(now: Date) -> some View {
        switch router.duelsSegment {
        case .live:
            let live = model.activeAndUpcomingContests
            if live.isEmpty {
                emptySegment(
                    title: "No live duels.",
                    message:
                        "Start one and the rope shows up here the moment they take it."
                )
            } else {
                ForEach(live) { contest in
                    liveCard(contest, now: now)
                }
            }
        case .invites:
            if model.invitations.isEmpty {
                emptySegment(
                    title: "Nothing waiting.",
                    message: "Invitations from your roster land here."
                )
            } else {
                ForEach(model.invitations) { invitation in
                    invitationCard(invitation)
                }
            }
        case .done:
            let completed = model.completedContests
            if completed.isEmpty {
                emptySegment(
                    title: "No history yet.",
                    message: "Settled duels and their receipts collect here."
                )
            } else {
                ForEach(Array(completed.enumerated()), id: \.element.id) {
                    index, contest in
                    completedRow(
                        contest,
                        isLast: index == completed.count - 1
                    )
                }
            }
        }
    }

    private func emptySegment(title: String, message: String) -> some View {
        EmptyDuelsCard(
            title: title,
            message: message,
            actionTitle: "Start a duel",
            isEnabled: model.canStartDuel
        ) {
            router.presentedSheet = .createDuel
        }
    }

    // MARK: Cards

    private func liveCard(_ contest: ContestCard, now: Date) -> some View {
        let standing = model.standing(for: contest.id)
        let opponent = model.opponent(for: contest)

        return Button {
            router.duelsPath.append(.contest(contest.id))
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contest.title)
                            .font(GlassArenaFont.display(20, .heavy))
                            .foregroundStyle(GlassArena.ink)
                            .multilineTextAlignment(.leading)
                        Text(
                            contest.listSubtitle(
                                opponentFirstName: opponent?.firstName
                            )
                        )
                        .font(GlassArenaFont.text(13))
                        .foregroundStyle(GlassArena.muted)
                        .multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    AmberPill(
                        systemImage: "clock",
                        text: DuelClock.shortRemaining(
                            until: contest.endsAt,
                            now: now
                        ),
                        fontSize: 12
                    )
                }

                DuelRope(
                    standing: standing,
                    metric: contest.metric,
                    size: .small
                )

                HStack {
                    Text(
                        standing.hasProgress
                            ? DeficitCopy(
                                standing: standing,
                                metric: contest.metric
                            ).headline
                            : "Waiting on Health"
                    )
                    .font(GlassArenaFont.text(13, .semibold))
                    .foregroundStyle(
                        standing.hasProgress
                            ? (standing.isAhead
                                ? GlassArena.teal900
                                : GlassArena.violet800)
                            : GlassArena.mutedLight
                    )
                    Spacer()
                    Text(contest.stakeCompactText)
                        .font(GlassArenaFont.display(16, .heavy))
                        .foregroundStyle(GlassArena.amber700)
                }
            }
            .padding(18)
            .glassPane(.hero, cornerRadius: 30)
        }
        .buttonStyle(GlassCardButtonStyle())
        .accessibilityIdentifier("duels.live")
    }

    private func invitationCard(_ invitation: ContestCard) -> some View {
        let opponent = model.opponent(for: invitation)
        let display = invitation.display

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(invitation.title)
                        .font(GlassArenaFont.display(20, .heavy))
                        .foregroundStyle(GlassArena.ink)
                    Text(
                        opponent.map {
                            "from \($0.firstName) · \(invitation.targetLine)"
                        } ?? invitation.targetLine
                    )
                    .font(GlassArenaFont.text(13))
                    .foregroundStyle(GlassArena.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("Your move")
                    .font(GlassArenaFont.text(12, .bold))
                    .foregroundStyle(GlassArena.amber800)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(GlassArena.amber400.opacity(0.22))
                    )
            }

            HStack(spacing: 8) {
                Button {
                    router.presentedSheet = .acceptInvitation(invitation.id)
                } label: {
                    Label(
                        "Take it — \(invitation.stakeCompactText)",
                        systemImage: "checkmark"
                    )
                }
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        height: 44,
                        cornerRadius: 16,
                        fontSize: 15
                    )
                )
                .disabled(
                    !model.configuration.contestMutationsEnabled
                        || model.isMutating
                )
                .accessibilityIdentifier("duels.invitation-accept")

                Button("Nope") {
                    Task {
                        await model.declineInvitation(
                            contestID: invitation.id
                        )
                    }
                }
                .buttonStyle(GlassQuietButtonStyle())
                .frame(width: 92)
                .disabled(
                    !model.configuration.contestMutationsEnabled
                        || model.isMutating
                )
                .accessibilityIdentifier("duels.invitation-decline")
            }
        }
        .padding(18)
        .glassPane(
            .standard,
            cornerRadius: 30,
            borderColor: GlassArena.amber400.opacity(0.42)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            router.duelsPath.append(.contest(invitation.id))
        }
    }

    private func completedRow(
        _ contest: ContestCard,
        isLast: Bool
    ) -> some View {
        let didWin = model.didWin(contest)
        return Button {
            router.duelsPath.append(.result(contest.id))
        } label: {
            CompletedDuelRow(
                title: contest.title,
                outcome: model.settlementSummary(for: contest),
                didWin: didWin,
                winTint: .teal,
                // Only a win has a receipt worth pushing into.
                showsChevron: didWin == true,
                slidesUnderTabBar: isLast
            )
        }
        .buttonStyle(GlassCardButtonStyle())
        .accessibilityIdentifier("duels.completed")
    }

    // MARK: Floating action

    private var floatingCreateButton: some View {
        Button {
            router.presentedSheet = .createDuel
        } label: {
            HStack(spacing: 9) {
                Image(systemName: model.pendingDuel == nil
                    ? "plus"
                    : "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(GlassArena.teal500)
                Text(
                    model.pendingDuel == nil
                        ? "Start a duel"
                        : "Review saved duel"
                )
                .font(GlassArenaFont.display(16, .bold))
                .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .frame(height: 52)
            .background {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .fill(GlassArena.darkButton)
                    .overlay {
                        RoundedRectangle(cornerRadius: 19, style: .continuous)
                            .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                    }
                    .shadow(
                        color: Color(glassArenaHex: 0x101816, opacity: 0.5),
                        radius: 15,
                        y: 14
                    )
            }
        }
        .buttonStyle(GlassCardButtonStyle())
        .disabled(!model.canStartDuel)
        .opacity(model.canStartDuel ? 1 : 0.5)
        // Hovers 20pt above the tab bar.
        .padding(
            .bottom,
            GlassArenaLayout.tabBarHeight
                + GlassArenaLayout.tabBarBottomPadding + 20
        )
        .accessibilityIdentifier("challenge.create")
    }
}

// MARK: - Saved request

/// A duel request that was saved before the network call and never confirmed.
/// GameTime never retries it automatically, so this card is the only way it
/// moves.
private struct SavedRequestCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Binding var showingDiscardConfirmation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                model.hasPendingDuelRecoveryIssue
                    ? "Protected storage needs attention"
                    : "Explicit retry required"
            )
            .font(GlassArenaFont.text(12, .bold))
            .tracking(0.8)
            .foregroundStyle(GlassArena.amber800)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(GlassArena.amber400.opacity(0.22))
            )

            if let pendingDuel = model.pendingDuel {
                Text(pendingDuel.terms.title)
                    .font(GlassArenaFont.display(20, .heavy))
                    .foregroundStyle(GlassArena.ink)
            }

            Text(explanation)
                .font(GlassArenaFont.text(13))
                .foregroundStyle(GlassArena.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if model.hasPendingDuelRecoveryIssue {
                Button("Try protected storage again") {
                    Task { await model.retryPendingDuelRecovery() }
                }
                .buttonStyle(
                    GlassSecondaryButtonStyle(height: 46, cornerRadius: 16)
                )
                .disabled(model.isMutating)
                .accessibilityIdentifier("duel.pending.retry-storage")
            }

            if model.pendingDuel != nil {
                Button {
                    router.presentedSheet = .createDuel
                } label: {
                    Label("Review saved duel", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        height: 48,
                        cornerRadius: 16,
                        fontSize: 16
                    )
                )
                .disabled(
                    model.isMutating || model.hasPendingDuelRecoveryIssue
                )
                .accessibilityIdentifier("duel.pending.resume")
            }

            Button(
                model.pendingDuel == nil
                    ? "Discard unreadable local retry"
                    : "Discard local retry record"
            ) {
                showingDiscardConfirmation = true
            }
            .font(GlassArenaFont.text(14, .semibold))
            .foregroundStyle(GlassArena.destructive)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .disabled(model.isMutating)
            .accessibilityIdentifier("duel.pending.discard-list")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPane(
            .standard,
            cornerRadius: 28,
            borderColor: GlassArena.amber400.opacity(0.44)
        )
    }

    private var explanation: String {
        if model.hasPendingDuelRecoveryIssue {
            return model.pendingDuel == nil
                ? "GameTime could not validate protected retry storage. New duel requests stay locked to avoid accidental duplicates."
                : "GameTime kept the saved request, but protected storage must recover before it can be retried safely."
        }
        return
            "GameTime kept the exact immutable terms and request ID after an unconfirmed response. It will never retry automatically."
    }
}
