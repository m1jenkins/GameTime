import SwiftUI

struct ChallengeDetailScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    let contest: ContestCard

    private var standings: ChallengeStandings? {
        model.standings(for: contest.id)
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 11) {
                content
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(CompetitiveTrustTheme.paper.ignoresSafeArea())
        .environment(\.colorScheme, .light)
        .navigationTitle(contest.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(
            CompetitiveTrustTheme.paper,
            for: .navigationBar
        )
        .toolbarBackground(.visible, for: .navigationBar)
        .refreshable {
            await model.refresh()
            if contest.myStatus == .accepted,
                contest.status == .active || contest.status == .finalized
            {
                await model.loadStandings(contestID: contest.id)
            }
        }
        .task(id: contest.status.rawValue) {
            guard
                contest.myStatus == .accepted,
                contest.status == .active || contest.status == .finalized
            else {
                return
            }
            await model.loadStandings(contestID: contest.id)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch contest.status {
        case .active:
            activeContent
        case .pending:
            upcomingContent
        case .finalized:
            finalContent
        case .cancelled:
            cancelledContent
        }

        stagingAcceptance
    }

    @ViewBuilder
    private var activeContent: some View {
        if let standings {
            overviewCard(
                standings: standings,
                statusText: "Live",
                statusKind: .live,
                contextText: remainingTimeText,
                headline: activeHeadline(standings),
                supportingText: activeSupportingText(standings)
            )

            remainingCard(standings)
            standingsDetails(standings)
        } else {
            standingsLoadCard
        }

        if canSyncActivity {
            activityAccessCard
        }

        termsFooter(
            prefix: "Live ordering, not a prediction."
        )
    }

    @ViewBuilder
    private var finalContent: some View {
        if let standings {
            overviewCard(
                standings: standings,
                statusText: "Final",
                statusKind: .positive,
                contextText: "Ended \(contest.endsAt.formatted(date: .abbreviated, time: .omitted))",
                headline: finalHeadline(standings),
                supportingText: finalSupportingText(standings)
            )
            standingsDetails(standings)
        } else {
            standingsLoadCard
        }

        termsFooter(prefix: "Result inputs are frozen.")
    }

    private var upcomingContent: some View {
        Group {
            DaybreakCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        TrustStatusPill(
                            text: contest.myStatus == .invited
                                ? "Action needed"
                                : "Starting soon",
                            kind: contest.myStatus == .invited
                                ? .action
                                : .neutral
                        )
                        Spacer()
                        TrustStatusPill(
                            text: "\(contest.stakeText) each",
                            kind: .pledge
                        )
                    }

                    ChallengeCountdown(
                        startsAt: contest.startsAt,
                        timeZoneName: contest.participantTimeZone
                            ?? model.profile?.timezone
                    )

                    ChallengeZeroField(
                        laneCount: max(
                            contest.resolvedParticipants.count,
                            contest.maxParticipants ?? 2
                        ),
                        goalLabel: contest.daybreakGoalLabel
                    )
                }
            }

            rosterCard

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    statTiles
                }
                VStack(spacing: 8) {
                    statTiles
                }
            }

            if contest.myStatus == .invited {
                invitationActions
            }

            termsFooter(prefix: "Terms are frozen.")
        }
    }

    private var cancelledContent: some View {
        DaybreakCard {
            VStack(alignment: .leading, spacing: 12) {
                TrustStatusPill(text: "Cancelled", kind: .neutral)
                Text("This challenge is closed.")
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: 27,
                            relativeTo: .title2
                        )
                    )
                    .tracking(-0.8)
                Text(
                    "The frozen terms remain here for reference. No test pledge is due."
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 14,
                        relativeTo: .subheadline
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func overviewCard(
        standings: ChallengeStandings,
        statusText: String,
        statusKind: TrustStatusPill.Kind,
        contextText: String,
        headline: String,
        supportingText: String
    ) -> some View {
        DaybreakCard {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    TrustStatusPill(
                        text: statusText,
                        kind: statusKind
                    )
                    Text(contextText)
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 12,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                    Spacer()
                    TrustStatusPill(
                        text: "\(contest.stakeText) each",
                        kind: .pledge
                    )
                }

                Text(headline)
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: fieldParticipants(standings).count > 3
                                ? 26
                                : 29,
                            relativeTo: .title
                        )
                    )
                    .tracking(-0.95)
                    .lineSpacing(1)
                    .padding(.top, 14)

                Text(supportingText)
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 14,
                            relativeTo: .subheadline
                        )
                    )
                    .foregroundStyle(
                        CompetitiveTrustTheme.secondaryText
                    )
                    .lineSpacing(2)
                    .padding(.top, 6)
                    .padding(.bottom, 18)

                ChallengeField(
                    participants: fieldParticipants(standings),
                    paceProgress: contest.status == .active
                        ? fieldPaceProgress
                        : nil,
                    goalLabel: contest.daybreakGoalLabel,
                    dense: fieldParticipants(standings).count > 3
                )
            }
        }
    }

    @ViewBuilder
    private func remainingCard(
        _ standings: ChallengeStandings
    ) -> some View {
        DaybreakCard(tone: .inverse) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(remainingHeadline(standings))
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 17,
                                relativeTo: .headline
                            )
                        )
                    Text(remainingSupportingText(standings))
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 12.5,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(Color.white.opacity(0.62))
                }

                Spacer(minLength: 6)

                if canSyncActivity {
                    Button("Sync") {
                        Task {
                            await model.syncActivity(
                                contestID: contest.id
                            )
                        }
                    }
                    .buttonStyle(SunPillButtonStyle())
                    .disabled(model.isActivityMutating)
                    .accessibilityIdentifier("activity.sync")
                }
            }
        }
    }

    private var activityAccessCard: some View {
        DaybreakCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Activity")
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 17,
                                relativeTo: .headline
                            )
                        )
                    Spacer()
                    Button("Enable Activity") {
                        Task {
                            await model.enableActivity()
                        }
                    }
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .caption,
                            weight: .bold
                        )
                    )
                    .disabled(model.isActivityMutating)
                    .accessibilityIdentifier("activity.enable")
                }

                if let outcome = model.activityAuthorizationOutcome {
                    Label(
                        authorizationMessage(outcome),
                        systemImage: outcome == .requestCompleted
                            ? "checkmark.shield"
                            : "heart.slash"
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 12,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }

                if let message = model.activitySyncState(
                    for: contest.id
                ).message {
                    Text(message)
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 12,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                        .accessibilityIdentifier("activity.status")
                }

                if model.pendingActivityUploadCount > 0 {
                    Label(
                        "Saved activity retry: \(model.pendingActivityUploadCount)",
                        systemImage: "arrow.clockwise.circle"
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 12,
                            relativeTo: .caption,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.sunInk)
                    .accessibilityIdentifier("activity.pending-count")
                }

                Text(
                    "GameTime reads steps only when you tap Sync. Apple-device overlap is merged; manual and third-party entries are excluded."
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
        }
    }

    @ViewBuilder
    private func standingsDetails(
        _ standings: ChallengeStandings
    ) -> some View {
        DaybreakCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(
                        standings.phase == .final
                            ? "Final rankings"
                            : "Standings"
                    )
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: 18,
                            relativeTo: .headline
                        )
                    )
                    Spacer()
                    TrustStatusPill(
                        text: standings.phase == .final
                            ? "Final"
                            : "Provisional",
                        kind: standings.phase == .final
                            ? .positive
                            : .action
                    )
                    .accessibilityIdentifier("standings.phase")
                }

                Text(reasonMessage(standings.reason))
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)

                if standings.phase == .provisional,
                    currentStanding(in: standings)?.rank ?? 1 > 1
                {
                    comebackButton(standings)
                }

                if let result = standings.result {
                    resultSummary(result, standings: standings)
                }

                ForEach(
                    Array(
                        standings.standings
                            .sorted { $0.displayOrder < $1.displayOrder }
                            .enumerated()
                    ),
                    id: \.element.id
                ) { index, standing in
                    if index > 0 {
                        Divider()
                            .overlay(CompetitiveTrustTheme.border)
                    }
                    standingRow(
                        standing,
                        phase: standings.phase
                    )
                }

                Text(
                    "Updated \(standings.asOf.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · \(standings.scoringVersion)"
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 10.5,
                        relativeTo: .caption2
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            }
        }
    }

    private func comebackButton(
        _ standings: ChallengeStandings
    ) -> some View {
        let hasReacted = model.hasSentComebackReaction(
            snapshotID: standings.snapshotID
        )
        let isSending = model.reactingStandingsSnapshotID
            == standings.snapshotID

        return Button {
            Task {
                await model.sendComebackReaction(
                    contestID: contest.id,
                    snapshotID: standings.snapshotID
                )
            }
        } label: {
            Label(
                hasReacted ? "Reaction sent" : "I’m coming back",
                systemImage: hasReacted
                    ? "checkmark.circle.fill"
                    : "bubble.left.and.bubble.right.fill"
            )
        }
        .buttonStyle(TrustSecondaryButtonStyle())
        .disabled(hasReacted || isSending)
        .accessibilityIdentifier("standings.reaction.comeback")
    }

    @ViewBuilder
    private func resultSummary(
        _ result: ChallengeResult,
        standings: ChallengeStandings
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                resultTitle(result, standings: standings),
                systemImage: "flag.checkered"
            )
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 15,
                    relativeTo: .headline,
                    weight: .bold
                )
            )
            Text(resultReason(result.reason))
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 12.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            CompetitiveTrustTheme.sunTint,
            in: RoundedRectangle(cornerRadius: 16, style: .continuous)
        )
        .accessibilityIdentifier("standings.result")
    }

    @ViewBuilder
    private func standingRow(
        _ standing: ChallengeStanding,
        phase: ChallengeStandingsPhase
    ) -> some View {
        let isCurrentUser = standing.participantID == model.userID
        let participantIDs = contest.resolvedParticipants.map(\.userID)
        let color = CompetitiveTrustTheme.participantColor(
            for: standing.participantID,
            participantIDs: participantIDs,
            currentUserID: model.userID
        )

        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 10) {
                Text("#\(standing.rank)")
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: 18,
                            relativeTo: .headline
                        )
                    )
                    .foregroundStyle(color)
                    .frame(minWidth: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(
                            isCurrentUser
                                ? "You"
                                : standing.displayName
                        )
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 14,
                                relativeTo: .subheadline,
                                weight: .bold
                            )
                        )
                        if isCurrentUser {
                            TrustStatusPill(
                                text: "You",
                                kind: .neutral
                            )
                        }
                    }
                    if let handle = standing.handle {
                        Text("@\(handle)")
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 11,
                                    relativeTo: .caption
                                )
                            )
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    Text(
                        contest.metric.daybreakDisplayText(
                            value: standing.total
                        )
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 14,
                            relativeTo: .subheadline,
                            weight: .bold
                        )
                    )
                    .monospacedDigit()
                    Text(
                        standing.qualified
                            ? "Target cleared"
                            : "Target open"
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 10.5,
                            relativeTo: .caption2,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        standing.qualified
                            ? CompetitiveTrustTheme.mintInk
                            : CompetitiveTrustTheme.secondaryText
                    )
                }
            }

            if contest.cadence == .daily {
                Text(
                    "\(standing.qualifyingDays) of \(standing.scoreableDays) scoreable days · \(standing.dayRate.formatted(.percent.precision(.fractionLength(0)))) day rate"
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            } else if phase == .final {
                Text(
                    standing.reachedTargetAt.map {
                        "Reached target \($0.formatted(date: .abbreviated, time: .shortened))"
                    } ?? "Target was not reached."
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }

            integrityDetails(standing, phase: phase)

            if let obligation = standing.obligation {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "Pledge \(obligation.amountText) to \(obligation.charityName)",
                        systemImage: "heart.circle.fill"
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 13,
                            relativeTo: .subheadline,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.sunInk)
                    .accessibilityIdentifier(
                        "standings.obligation.\(standing.participantID.uuidString.lowercased())"
                    )
                    Text(
                        "Pending result review until \(obligation.resultDisputeClosesAt.formatted(date: .abbreviated, time: .shortened))."
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
        .accessibilityIdentifier(
            "standings.row.\(standing.participantID.uuidString.lowercased())"
        )
    }

    @ViewBuilder
    private func integrityDetails(
        _ standing: ChallengeStanding,
        phase: ChallengeStandingsPhase
    ) -> some View {
        if standing.integrityScore != nil {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    phase == .final
                        ? "Verified progress"
                        : "Your progress checks passed",
                    systemImage: "checkmark.shield"
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption,
                        weight: .bold
                    )
                )

                if let flags = standing.integrityFlags, !flags.isEmpty {
                    Text(
                        "Flags: \(flags.map(humanized).joined(separator: ", "))"
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                } else {
                    Text("No integrity flags")
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 11,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                }

                if let rationale = standing.rationale {
                    ForEach(rationale) { item in
                        Text(item.summary)
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 11,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                    }
                }
            }
        } else if phase == .provisional {
            Label(
                "Integrity detail stays private until final.",
                systemImage: "lock"
            )
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 11.5,
                    relativeTo: .caption
                )
            )
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
    }

    private var standingsLoadCard: some View {
        DaybreakCard {
            switch model.standingsLoadState(for: contest.id) {
            case .idle, .loading:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(CompetitiveTrustTheme.coral)
                    Text("Loading trusted progress…")
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                }
                .accessibilityIdentifier("standings.loading")
            case .empty, .loaded:
                Label(
                    contest.status == .finalized
                        ? "Final standings aren’t available yet."
                        : "Trusted progress has not been published yet.",
                    systemImage: "chart.bar.xaxis"
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .accessibilityIdentifier("standings.empty")
            case .failed(let message):
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        message,
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    Button("Try again") {
                        Task {
                            await model.loadStandings(
                                contestID: contest.id
                            )
                        }
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                }
            }
        }
    }

    private var rosterCard: some View {
        let participants = contest.resolvedParticipants
        let acceptedCount = participants.filter {
            $0.status == .accepted
        }.count
        let pendingCount = participants.filter {
            $0.status == .invited
        }.count

        return DaybreakCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text(
                        "\(acceptedCount) of \(max(participants.count, contest.maxParticipants ?? participants.count)) are in"
                    )
                    .font(
                        CompetitiveTrustTheme.displayFont(
                            size: 17,
                            relativeTo: .headline
                        )
                    )
                    Spacer()
                    if pendingCount > 0 {
                        Text(
                            "\(pendingCount) \(pendingCount == 1 ? "hasn’t" : "haven’t") answered"
                        )
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 12,
                                relativeTo: .caption,
                                weight: .bold
                            )
                        )
                        .foregroundStyle(CompetitiveTrustTheme.sunInk)
                    }
                }

                ChallengeRosterFlowLayout(
                    participants: participants.enumerated().map {
                        rosterItem(
                            participant: $0.element,
                            index: $0.offset
                        )
                    }
                )

                if pendingCount > 0 {
                    Text(
                        "If they don’t answer before the start, the challenge opens without them."
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11.5,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var statTiles: some View {
        ChallengeStatTile(
            label: "Target",
            value: contest.metric.daybreakDisplayText(
                value: contest.targetValue,
                compact: true
            ),
            caption: contest.cadence == .daily
                ? "\(contest.metric.unit) each day"
                : "\(contest.metric.unit) total"
        )
        ChallengeStatTile(
            label: "Window",
            value: contest.daybreakWindowText,
            caption:
                "\(contest.startsAt.formatted(.dateTime.month(.abbreviated).day())) – \(contest.endsAt.formatted(.dateTime.month(.abbreviated).day()))"
        )
        ChallengeStatTile(
            label: "Pledge",
            value: contest.stakeText,
            caption: "each, if you miss",
            pledge: true
        )
    }

    private var invitationActions: some View {
        DaybreakCard {
            VStack(spacing: 10) {
                Button("Review and accept") {
                    router.presentedSheet = .acceptInvitation(contest.id)
                }
                .buttonStyle(TrustPrimaryButtonStyle())
                .disabled(!model.configuration.contestMutationsEnabled)

                Button("Decline", role: .destructive) {
                    Task {
                        await model.declineInvitation(
                            contestID: contest.id
                        )
                    }
                }
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 14,
                        relativeTo: .subheadline,
                        weight: .bold
                    )
                )
                .disabled(!model.configuration.contestMutationsEnabled)
                .frame(maxWidth: .infinity)

                Text(
                    "Accepting freezes your timezone and charity nomination for this challenge."
                )
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
        }
    }

    private func termsFooter(prefix: String) -> some View {
        Text(
            "\(prefix) \(contest.daybreakTargetText) · \(contest.cadence.title.lowercased()) · ends \(contest.endsAt.formatted(.dateTime.month(.abbreviated).day().hour().minute())) · \(contest.tieBreak.title) ›"
        )
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 11.5,
                relativeTo: .caption
            )
        )
        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        .lineSpacing(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var stagingAcceptance: some View {
        #if STAGING
        DaybreakCard {
            VStack(alignment: .leading, spacing: 10) {
                DaybreakSectionLabel(text: "Staging acceptance")
                    .padding(.horizontal, -6)
                    .padding(.top, -4)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Challenge ID")
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                    Text(contest.id.uuidString.lowercased())
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("staging.challenge-id")
                compactTerm(
                    label: "Challenge state",
                    value: contest.status.rawValue
                )
                compactTerm(
                    label: "Your roster state",
                    value: contest.myStatus.rawValue
                )
                compactTerm(
                    label: "Loaded roster",
                    value: "\(contest.resolvedParticipants.count) people"
                )
                ForEach(contest.resolvedParticipants) { participant in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(participant.status.rawValue.capitalized)
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                        Text(
                            participant.userID.uuidString.lowercased()
                        )
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 12,
                    relativeTo: .caption
                )
            )
        }
        #endif
    }

    private func compactTerm(
        label: String,
        value: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .multilineTextAlignment(.trailing)
        }
    }

    private var fieldPaceProgress: Double? {
        guard contest.cadence == .cumulative else { return nil }
        let duration = contest.endsAt.timeIntervalSince(contest.startsAt)
        guard duration > 0 else { return nil }
        return min(
            max(
                Date().timeIntervalSince(contest.startsAt) / duration,
                0
            ),
            1
        )
    }

    private func fieldParticipants(
        _ standings: ChallengeStandings
    ) -> [ChallengeFieldParticipant] {
        let sorted = standings.standings.sorted {
            $0.displayOrder < $1.displayOrder
        }
        let participantIDs = sorted.map(\.participantID)

        return sorted.map { standing in
            let progress = contest.cadence == .daily
                ? standing.dayRate
                : standing.total / max(contest.targetValue, 1)
            let isCurrentUser = standing.participantID == model.userID
            return ChallengeFieldParticipant(
                id: standing.participantID,
                name: isCurrentUser
                    ? "You"
                    : firstName(standing.displayName),
                initials: initials(
                    name: standing.displayName,
                    fallback: standing.handle
                ),
                progress: progress,
                value: contest.metric.daybreakDisplayText(
                    value: standing.total,
                    compact: true
                ),
                note: fieldNote(standing),
                color: CompetitiveTrustTheme.participantColor(
                    for: standing.participantID,
                    participantIDs: participantIDs,
                    currentUserID: model.userID
                ),
                isCurrentUser: isCurrentUser
            )
        }
    }

    private func fieldNote(
        _ standing: ChallengeStanding
    ) -> String {
        if contest.status == .finalized {
            return standing.qualified
                ? "Target cleared"
                : "Target not cleared"
        }
        if contest.cadence == .daily {
            return "\(standing.qualifyingDays) of \(standing.scoreableDays) days cleared"
        }
        let paceTarget = contest.targetValue * (fieldPaceProgress ?? 0)
        let delta = standing.total - paceTarget
        let amount = contest.metric.daybreakDisplayText(
            value: abs(delta)
        )
        return delta >= 0
            ? "\(amount) ahead of pace"
            : "\(amount) behind pace"
    }

    private func activeHeadline(
        _ standings: ChallengeStandings
    ) -> String {
        let ranked = standings.standings.sorted { $0.rank < $1.rank }
        guard let current = currentStanding(in: standings) else {
            return "The field is moving."
        }

        if ranked.count == 2,
            let leader = ranked.first,
            let trailing = ranked.last
        {
            let delta = abs(leader.total - trailing.total)
            if delta < 0.001 {
                return "You’re level."
            }
            let name = leader.participantID == model.userID
                ? "You’re"
                : "\(firstName(leader.displayName)) is"
            return "\(name) up \(contest.metric.daybreakDisplayText(value: delta))."
        }

        let paceTarget = contest.targetValue * (fieldPaceProgress ?? 0)
        let delta = current.total - paceTarget
        let paceText: String
        if abs(delta) < 0.001 {
            paceText = "right on pace"
        } else if delta > 0 {
            paceText =
                "\(contest.metric.daybreakDisplayText(value: delta)) up on pace"
        } else {
            paceText =
                "\(contest.metric.daybreakDisplayText(value: abs(delta))) behind pace"
        }
        return "You’re \(ordinal(current.rank)), and \(paceText)."
    }

    private func activeSupportingText(
        _ standings: ChallengeStandings
    ) -> String {
        let currentNote = currentStanding(in: standings).map(fieldNote)
            ?? "Your progress is waiting to sync."
        let clearedCount = standings.standings.filter(\.qualified).count
        let clearingText = clearedCount == 0
            ? "No one has cleared the target yet."
            : "\(clearedCount) \(clearedCount == 1 ? "person has" : "people have") cleared the target."
        return "\(currentNote). \(clearingText)"
    }

    private func finalHeadline(
        _ standings: ChallengeStandings
    ) -> String {
        guard let result = standings.result else {
            return "The result is frozen."
        }
        return resultTitle(result, standings: standings)
    }

    private func finalSupportingText(
        _ standings: ChallengeStandings
    ) -> String {
        guard let result = standings.result else {
            return "Ranks and result inputs are frozen."
        }
        return resultReason(result.reason)
    }

    private func remainingHeadline(
        _ standings: ChallengeStandings
    ) -> String {
        guard let current = currentStanding(in: standings) else {
            return "Sync to see what’s left"
        }
        if contest.cadence == .daily {
            return "\(current.qualifyingDays) days cleared"
        }
        let remaining = max(0, contest.targetValue - current.total)
        if remaining == 0 {
            return "You cleared the target"
        }
        return "\(contest.metric.daybreakDisplayText(value: remaining)) to clear it"
    }

    private func remainingSupportingText(
        _ standings: ChallengeStandings
    ) -> String {
        guard let current = currentStanding(in: standings) else {
            return "Trusted progress will appear after a sync."
        }
        if contest.cadence == .daily {
            let remainingDays = max(
                0,
                current.scoreableDays - current.qualifyingDays
            )
            return "\(remainingDays) scoreable \(remainingDays == 1 ? "day" : "days") still open."
        }
        let remaining = max(0, contest.targetValue - current.total)
        guard remaining > 0 else {
            return "The challenge remains live until the window closes."
        }
        let days = max(
            1,
            Int(
                ceil(
                    contest.endsAt.timeIntervalSinceNow / 86_400
                )
            )
        )
        let perDay = remaining / Double(days)
        return "About \(contest.metric.daybreakDisplayText(value: perDay)) a day for the rest of the window."
    }

    private var remainingTimeText: String {
        let interval = max(0, Int(contest.endsAt.timeIntervalSinceNow))
        let days = interval / 86_400
        let hours = (interval % 86_400) / 3_600
        if days > 0 {
            return "\(days)d \(hours)h left"
        }
        let minutes = (interval % 3_600) / 60
        return hours > 0
            ? "\(hours)h \(minutes)m left"
            : "\(minutes)m left"
    }

    private var canSyncActivity: Bool {
        model.configuration.activitySyncEnabled
            && contest.metric == .steps
            && contest.myStatus == .accepted
            && contest.status == .active
    }

    private func currentStanding(
        in standings: ChallengeStandings
    ) -> ChallengeStanding? {
        standings.standings.first {
            $0.participantID == model.userID
        }
    }

    private func resultTitle(
        _ result: ChallengeResult,
        standings: ChallengeStandings
    ) -> String {
        switch result.kind {
        case .winner:
            let winner = standings.standings.first {
                $0.participantID == result.winnerParticipantID
            }
            return "Winner: \(winner?.displayName ?? "Participant")"
        case .allDonate:
            return "Everyone has a pledge"
        case .void:
            return "No pledge is due"
        case .inconclusive:
            return "Result inconclusive"
        }
    }

    private func reasonMessage(
        _ reason: ChallengeStandingsReason
    ) -> String {
        switch reason {
        case .live:
            return "Live ordering only — not a predicted winner."
        case .awaitingIngest:
            return "Waiting for the evidence grace period to close."
        case .underReview:
            return "Evidence is under review; ordering may change."
        case .final:
            return "Ranks and result inputs are frozen."
        }
    }

    private func resultReason(
        _ reason: ChallengeResultReason
    ) -> String {
        switch reason {
        case .soleQualifier:
            return "Only one participant met the qualification rules."
        case .earliestToTarget:
            return "The winner reached the target first."
        case .integrityScore:
            return "The integrity score resolved the tie."
        case .bothDonate:
            return "The challenge terms require every participant to pledge."
        case .noQualifyingParticipant:
            return "No participant met the qualification rules."
        case .tieBreakVoid:
            return "The configured tie-break voided the pledge."
        case .tieBreakInconclusive:
            return "The configured tie-break could not resolve the result."
        case .reviewTimeout:
            return "The evidence review window expired without a winner."
        }
    }

    private func authorizationMessage(
        _ outcome: ActivityAuthorizationOutcome
    ) -> String {
        switch outcome {
        case .requestCompleted:
            return "Permission request completed. Read access may still be limited."
        case .healthDataUnavailable:
            return "Health data is unavailable on this device."
        }
    }

    private func rosterItem(
        participant: ContestParticipantCard,
        index: Int
    ) -> ChallengeRosterItem {
        let displayName = participantName(
            participant.userID,
            fallbackIndex: index
        )
        let participantIDs = contest.resolvedParticipants.map(\.userID)
        return ChallengeRosterItem(
            id: participant.userID,
            initials: initials(name: displayName, fallback: nil),
            name: participant.userID == model.userID
                ? "You"
                : firstName(displayName),
            color: CompetitiveTrustTheme.participantColor(
                for: participant.userID,
                participantIDs: participantIDs,
                currentUserID: model.userID
            ),
            isPending: participant.status == .invited
        )
    }

    private func participantName(
        _ id: UUID,
        fallbackIndex: Int
    ) -> String {
        if id == model.userID {
            return model.profile?.displayName ?? "You"
        }
        if let friend = model.friendshipCards.first(where: {
            $0.otherUserID == id
        }) {
            return friend.displayName
        }
        return "Participant \(fallbackIndex + 1)"
    }

    private func initials(
        name: String,
        fallback: String?
    ) -> String {
        let letters = name
            .split(whereSeparator: \.isWhitespace)
            .prefix(2)
            .compactMap(\.first)
            .map(String.init)
            .joined()
            .uppercased()
        if !letters.isEmpty {
            return letters
        }
        return String((fallback ?? "?").prefix(2)).uppercased()
    }

    private func firstName(_ displayName: String) -> String {
        displayName.split(whereSeparator: \.isWhitespace).first
            .map(String.init) ?? displayName
    }

    private func ordinal(_ value: Int) -> String {
        let remainder100 = value % 100
        if (11...13).contains(remainder100) {
            return "\(value)th"
        }
        switch value % 10 {
        case 1: return "\(value)st"
        case 2: return "\(value)nd"
        case 3: return "\(value)rd"
        default: return "\(value)th"
        }
    }

    private func humanized(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
    }
}

struct ContestDetailView: View {
    @Environment(AppModel.self) private var model

    let contestID: UUID

    private var contest: ContestCard? {
        model.contests.first { $0.id == contestID }
    }

    var body: some View {
        Group {
            if let contest {
                ChallengeDetailScreen(contest: contest)
            } else {
                ContentUnavailableView(
                    "Challenge unavailable",
                    systemImage: "flag.slash",
                    description: Text(
                        "Refresh to load the current challenge state."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    CompetitiveTrustTheme.paper.ignoresSafeArea()
                )
            }
        }
        .environment(\.colorScheme, .light)
    }
}

private struct ChallengeRosterItem: Identifiable {
    let id: UUID
    let initials: String
    let name: String
    let color: Color
    let isPending: Bool
}

private struct ChallengeRosterFlowLayout: View {
    let participants: [ChallengeRosterItem]

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(participants) { participant in
                ChallengeRosterChip(
                    initials: participant.initials,
                    name: participant.name,
                    color: participant.color,
                    isPending: participant.isPending
                )
            }
        }
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(
            width: proposal.width ?? x,
            height: y + rowHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
