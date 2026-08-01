import SwiftUI

private struct LegacyContestDetailView: View {
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
                        if let maxParticipants = contest.maxParticipants {
                            TermRow(
                                label: "Closed roster",
                                value: "\(maxParticipants) people"
                            )
                        }
                        if let timeZone = contest.participantTimeZone {
                            TermRow(
                                label: "Your frozen timezone",
                                value: timeZone
                            )
                        }
                    }
                    .listRowBackground(CompetitiveTrustTheme.raisedInk)

                    if model.configuration.activitySyncEnabled,
                        contest.metric == .steps,
                        contest.myStatus == .accepted,
                        contest.status == .active
                    {
                        Section {
                            Button("Enable Activity") {
                                Task {
                                    await model.enableActivity()
                                }
                            }
                            .accessibilityIdentifier(
                                "activity.enable"
                            )
                            .disabled(model.isActivityMutating)

                            Button("Sync Activity") {
                                Task {
                                    await model.syncActivity(
                                        contestID: contest.id
                                    )
                                }
                            }
                            .buttonStyle(TrustPrimaryButtonStyle())
                            .accessibilityIdentifier(
                                "activity.sync"
                            )
                            .disabled(model.isActivityMutating)

                            if let outcome =
                                model.activityAuthorizationOutcome
                            {
                                Label(
                                    authorizationMessage(outcome),
                                    systemImage: outcome
                                        == .requestCompleted
                                        ? "checkmark.shield"
                                        : "heart.slash"
                                )
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            }

                            if let message = model.activitySyncState(
                                for: contest.id
                            ).message {
                                Text(message)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .accessibilityIdentifier(
                                        "activity.status"
                                    )
                            }

                            if model.pendingActivityUploadCount > 0 {
                                Label(
                                    "Saved activity retry: \(model.pendingActivityUploadCount)",
                                    systemImage: "arrow.clockwise.circle"
                                )
                                .font(.footnote)
                                .foregroundStyle(
                                    CompetitiveTrustTheme.amber
                                )
                                .accessibilityIdentifier(
                                    "activity.pending-count"
                                )
                            }
                        } header: {
                            Text("Activity")
                        } footer: {
                            Text(
                                "GameTime reads steps only when you tap Sync Activity. It uses HealthKit’s merged Apple-device total so iPhone and Watch overlap is not counted twice. Manual and third-party entries are excluded."
                            )
                        }
                        .listRowBackground(
                            CompetitiveTrustTheme.raisedInk
                        )
                    }

                    #if STAGING
                    Section("Staging acceptance") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Challenge ID")
                                .foregroundStyle(.secondary)
                            Text(contest.id.uuidString.lowercased())
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("staging.challenge-id")
                        TermRow(
                            label: "Challenge state",
                            value: contest.status.rawValue
                        )
                        TermRow(
                            label: "Your roster state",
                            value: contest.myStatus.rawValue
                        )
                        TermRow(
                            label: "Loaded roster",
                            value:
                                "\(contest.resolvedParticipants.count) people"
                        )
                        ForEach(
                            contest.resolvedParticipants
                        ) { participant in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(participant.status.rawValue.capitalized)
                                    .foregroundStyle(.secondary)
                                Text(
                                    participant.userID.uuidString.lowercased()
                                )
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .listRowBackground(CompetitiveTrustTheme.raisedInk)
                    #endif

                    if contest.myStatus == .accepted {
                        if contest.status == .active
                            || contest.status == .finalized
                        {
                            ChallengeStandingsSection(
                                contest: contest,
                                currentUserID: model.userID,
                                standings: model.standings(
                                    for: contest.id
                                ),
                                loadState: model.standingsLoadState(
                                    for: contest.id
                                ),
                                hasReacted: model.standings(
                                    for: contest.id
                                ).map {
                                    model.hasSentComebackReaction(
                                        snapshotID: $0.snapshotID
                                    )
                                } ?? false,
                                isSendingReaction: model
                                    .reactingStandingsSnapshotID
                                    == model.standings(
                                        for: contest.id
                                    )?.snapshotID,
                                retry: {
                                    Task {
                                        await model.loadStandings(
                                            contestID: contest.id
                                        )
                                    }
                                },
                                sendReaction: {
                                    guard
                                        let snapshotID = model.standings(
                                            for: contest.id
                                        )?.snapshotID
                                    else {
                                        return
                                    }
                                    Task {
                                        await model.sendComebackReaction(
                                            contestID: contest.id,
                                            snapshotID: snapshotID
                                        )
                                    }
                                }
                            )
                        } else if contest.status == .pending {
                            Section("Standings") {
                                Label(
                                    "Standings open when the challenge starts.",
                                    systemImage: "clock"
                                )
                                .foregroundStyle(.secondary)
                            }
                            .listRowBackground(
                                CompetitiveTrustTheme.raisedInk
                            )
                        }
                    }

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
                .refreshable {
                    await model.refresh()
                    await model.loadStandings(contestID: contest.id)
                }
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
        .navigationTitle("Challenge")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: contest?.status.rawValue) {
            guard
                let contest,
                contest.myStatus == .accepted,
                contest.status == .active || contest.status == .finalized
            else {
                return
            }
            await model.loadStandings(contestID: contest.id)
        }
    }

    private func authorizationMessage(
        _ outcome: ActivityAuthorizationOutcome
    ) -> String {
        switch outcome {
        case .requestCompleted:
            "Permission request completed. Read access may still be limited."
        case .healthDataUnavailable:
            "Health data is unavailable on this device."
        }
    }
}

struct ContestStandingsView: View {
    @Environment(AppModel.self) private var model
    let contestID: UUID

    private var contest: ContestCard? {
        model.contests.first { $0.id == contestID }
    }

    private var standings: ChallengeStandings? {
        model.standings(for: contestID)
    }

    var body: some View {
        Group {
            if let contest,
                contest.myStatus == .accepted,
                contest.status == .active || contest.status == .finalized
            {
                List {
                    ChallengeStandingsSection(
                        contest: contest,
                        currentUserID: model.userID,
                        standings: standings,
                        loadState: model.standingsLoadState(
                            for: contest.id
                        ),
                        hasReacted: standings.map {
                            model.hasSentComebackReaction(
                                snapshotID: $0.snapshotID
                            )
                        } ?? false,
                        isSendingReaction:
                            model.reactingStandingsSnapshotID
                            == standings?.snapshotID,
                        retry: {
                            Task {
                                await model.loadStandings(
                                    contestID: contest.id
                                )
                            }
                        },
                        sendReaction: {
                            guard let snapshotID = standings?.snapshotID
                            else {
                                return
                            }
                            Task {
                                await model.sendComebackReaction(
                                    contestID: contest.id,
                                    snapshotID: snapshotID
                                )
                            }
                        }
                    )
                }
                .trustScreenBackground()
                .refreshable {
                    await model.refresh()
                    await model.loadStandings(contestID: contest.id)
                }
            } else {
                ContentUnavailableView(
                    "Standings unavailable",
                    systemImage: "chart.bar.xaxis",
                    description: Text(
                        "This challenge is not active or is no longer available to this account."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(CompetitiveTrustTheme.ink)
            }
        }
        .navigationTitle("Standings")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: contest?.status.rawValue) {
            guard let contest else { return }
            await model.loadStandings(contestID: contest.id)
        }
    }
}

private struct ChallengeStandingsSection: View {
    let contest: ContestCard
    let currentUserID: UUID?
    let standings: ChallengeStandings?
    let loadState: ScreenLoadState
    let hasReacted: Bool
    let isSendingReaction: Bool
    let retry: () -> Void
    let sendReaction: () -> Void

    var body: some View {
        Section {
            if let standings {
                phaseHeader(standings)

                if standings.phase == .provisional,
                    standings.standings.first(where: {
                        $0.participantID == currentUserID
                    })?.rank ?? 1 > 1
                {
                    comebackReaction
                }

                if let result = standings.result {
                    resultSummary(result, standings: standings)
                }

                ForEach(standings.standings) { standing in
                    ChallengeStandingRow(
                        contest: contest,
                        standing: standing,
                        isCurrentUser: standing.participantID
                            == currentUserID,
                        phase: standings.phase
                    )
                }

                if case .loading = loadState {
                    Label(
                        "Refreshing standings…",
                        systemImage: "arrow.clockwise"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else if case .failed = loadState {
                    InlineLoadStateView(state: loadState, retry: retry)
                }
            } else {
                emptyContent
            }
        } header: {
            Text(
                standings?.phase == .final
                    ? "Final rankings"
                    : "Standings"
            )
        } footer: {
            if let standings {
                Text(
                    "Scored with \(standings.scoringVersion) · Integrity \(standings.integrityConfigurationVersion)"
                )
            }
        }
        .listRowBackground(CompetitiveTrustTheme.raisedInk)
    }

    private var comebackReaction: some View {
        Button(action: sendReaction) {
            Label(
                hasReacted ? "Reaction sent" : "I’m coming back",
                systemImage: hasReacted
                    ? "checkmark.circle.fill"
                    : "bubble.left.and.bubble.right.fill"
            )
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(TrustSecondaryButtonStyle())
        .disabled(hasReacted || isSendingReaction)
        .accessibilityIdentifier("standings.reaction.comeback")
        .accessibilityHint(
            hasReacted
                ? "Your reaction was sent."
                : "Sends a comeback reaction to this challenge."
        )
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch loadState {
        case .idle, .loading:
            HStack(spacing: 10) {
                ProgressView()
                Text("Loading standings…")
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("standings.loading")
        case .empty, .loaded:
            Label(
                contest.status == .finalized
                    ? "Final standings aren’t available yet."
                    : "Trusted progress has not been published yet.",
                systemImage: "chart.bar.xaxis"
            )
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("standings.empty")
        case .failed:
            InlineLoadStateView(state: loadState, retry: retry)
        }
    }

    private func phaseHeader(_ standings: ChallengeStandings) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TrustStatusPill(
                    text: standings.phase == .final ? "Final" : "Provisional",
                    kind: standings.phase == .final ? .verified : .action
                )
                .accessibilityIdentifier("standings.phase")
                Spacer()
                Text(
                    standings.asOf,
                    format: .dateTime.month(.abbreviated).day().hour().minute()
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Text(reasonMessage(for: standings.reason))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func resultSummary(
        _ result: ChallengeResult,
        standings: ChallengeStandings
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(
                resultTitle(result, standings: standings),
                systemImage: "flag.checkered"
            )
            .font(.headline)
            Text(resultReason(result.reason))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(
                "Evidence closed \(result.evidenceCutoff.formatted(date: .abbreviated, time: .shortened))."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("standings.result")
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

    private func reasonMessage(for reason: ChallengeStandingsReason) -> String {
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

    private func resultReason(_ reason: ChallengeResultReason) -> String {
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
}

private struct ChallengeStandingRow: View {
    let contest: ContestCard
    let standing: ChallengeStanding
    let isCurrentUser: Bool
    let phase: ChallengeStandingsPhase

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("#\(standing.rank)")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(CompetitiveTrustTheme.teal)
                    .frame(minWidth: 30, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(standing.displayName)
                            .font(.headline)
                        if isCurrentUser {
                            TrustStatusPill(text: "You", kind: .neutral)
                        }
                    }
                    if let handle = standing.handle {
                        Text("@\(handle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(standing.totalText(metric: contest.metric))
                        .font(.headline.monospacedDigit())
                    Text(standing.qualified ? "Qualified" : "Not qualified")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(
                            standing.qualified
                                ? CompetitiveTrustTheme.teal
                                : Color.secondary
                        )
                }
            }

            progressDetail

            integrityDetails

            if let obligation = standing.obligation {
                VStack(alignment: .leading, spacing: 5) {
                    Label(
                        "Pledge \(obligation.amountText) to \(obligation.charityName)",
                        systemImage: "heart.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CompetitiveTrustTheme.amber)
                    .accessibilityIdentifier(
                        "standings.obligation.\(standing.participantID.uuidString.lowercased())"
                    )
                    Text(
                        "Pending result review until \(obligation.resultDisputeClosesAt.formatted(date: .abbreviated, time: .shortened))."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.top, 3)
            }
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier(
            "standings.row.\(standing.participantID.uuidString.lowercased())"
        )
    }

    @ViewBuilder
    private var progressDetail: some View {
        if contest.cadence == .daily {
            Text(
                "\(standing.qualifyingDays) of \(standing.scoreableDays) scoreable days · \(standing.dayRate.formatted(.percent.precision(.fractionLength(0)))) day rate"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        } else if phase == .final {
            if let reachedTargetAt = standing.reachedTargetAt {
                Text(
                    "Reached target \(reachedTargetAt.formatted(date: .abbreviated, time: .shortened))"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Target was not reached.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var integrityDetails: some View {
        if let score = standing.integrityScore {
            VStack(alignment: .leading, spacing: 4) {
                Label(
                    "Integrity \(score.formatted(.number.precision(.fractionLength(0...2))))",
                    systemImage: "checkmark.shield"
                )
                .font(.caption.weight(.semibold))

                if let flags = standing.integrityFlags, !flags.isEmpty {
                    Text(
                        "Flags: \(flags.map(humanized).joined(separator: ", "))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                } else {
                    Text("No integrity flags")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let rationale = standing.rationale {
                    ForEach(rationale) { item in
                        Text(
                            "\(item.summary) (\(item.points.formatted(.number.precision(.fractionLength(0...2)))) points)"
                        )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } else if phase == .provisional {
            Label(
                "Integrity detail stays private until final.",
                systemImage: "lock"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func humanized(_ value: String) -> String {
        value.replacingOccurrences(of: "_", with: " ")
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
