import SwiftUI

/// Create a duel, then read the terms back before they freeze.
struct CreateDuelFlow: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var draft = DuelDraft()
    @State private var days = 3
    @State private var reviewedTerms: DuelTerms?
    @State private var showingDiscardConfirmation = false

    private var activeReviewedTerms: DuelTerms? {
        model.pendingDuel?.terms ?? reviewedTerms
    }

    var body: some View {
        NavigationStack {
            Group {
                if let activeReviewedTerms {
                    review(terms: activeReviewedTerms)
                } else {
                    editor
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isMutating)
                        .tint(GlassArena.teal800)
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .interactiveDismissDisabled(model.isMutating)
        .confirmationDialog(
            "Discard the local retry record?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard local retry", role: .destructive) {
                Task {
                    if await model.discardPendingDuel() {
                        reviewedTerms = nil
                        resetDraft()
                    }
                }
            }
            Button("Keep saved request", role: .cancel) {}
        } message: {
            Text(
                "This deletes only the on-device retry record; it does not cancel a contest or invitation the server may already have created. Starting over after a committed request can create a second duel."
            )
        }
    }

    // MARK: Editor

    private var editor: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                Text("Pick a fight.")
                    .font(GlassArenaFont.display(31, .heavy))
                    .foregroundStyle(GlassArena.ink)
                    .padding(.horizontal, 4)

                opponentCard
                nameCard
                metricCard
                targetCard
                stakeCard

                Button {
                    commitDates()
                    do {
                        reviewedTerms = try draft.validated()
                    } catch {
                        model.presentedError = error.localizedDescription
                    }
                } label: {
                    Text("Read it back to me")
                }
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        height: 56,
                        cornerRadius: 20,
                        fontSize: 17
                    )
                )
                .accessibilityIdentifier("duel.review")
                .padding(.top, 4)
            }
            .padding(.horizontal, GlassArenaLayout.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 32)
            .frame(maxWidth: GlassArenaMetrics.contentCap)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .glassArenaBackground(.duels)
        .navigationTitle("New duel")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if draft.inviteeID == nil {
                draft.inviteeID = model.acceptedFriendships.first?.otherUserID
            }
            if draft.charityID == nil {
                draft.charityID = model.charities.first?.id
            }
        }
    }

    private var opponentCard: some View {
        GlassCardSection(title: "Who") {
            if model.acceptedFriendships.isEmpty {
                Text(
                    "Add a friend first — a duel needs someone on the other end."
                )
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowRow(spacing: 8) {
                    ForEach(model.acceptedFriendships) { card in
                        GlassChip(
                            title: card.profileCard.firstName,
                            systemImage: draft.inviteeID == card.otherUserID
                                ? "checkmark"
                                : nil,
                            isSelected: draft.inviteeID == card.otherUserID
                        ) {
                            draft.inviteeID = card.otherUserID
                        }
                    }
                    GlassChip(
                        title: "Invite",
                        systemImage: "plus",
                        isSelected: false,
                        isDashed: true
                    ) {
                        dismiss()
                        router.selectedTab = .friends
                    }
                }
                .accessibilityIdentifier("duel.opponent")
            }
        }
    }

    private var nameCard: some View {
        GlassCardSection(title: "Call it something") {
            GlassTextField(
                placeholder: "Weekend distance",
                text: $draft.title,
                accessibilityID: "duel.title",
                accessibilityName: "Duel title"
            )
        }
    }

    private var metricCard: some View {
        GlassCardSection(title: "What counts") {
            FlowRow(spacing: 8) {
                ForEach(ContestMetric.allCases) { metric in
                    GlassChip(
                        title: metric.title,
                        isSelected: draft.metric == metric
                    ) {
                        let previous = draft.metric
                        draft.metric = metric
                        if draft.targetValue == previous.suggestedTarget {
                            draft.targetValue = metric.suggestedTarget
                        }
                    }
                }
            }
        }
    }

    private var targetCard: some View {
        let display = draft.metric.display
        let bounds = draft.metric.targetBounds

        return GlassCardSection(title: "How much") {
            HStack(spacing: 8) {
                GlassChip(title: "Total", isSelected: draft.cadence == .cumulative) {
                    draft.cadence = .cumulative
                }
                GlassChip(title: "Daily", isSelected: draft.cadence == .daily) {
                    draft.cadence = .daily
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(display.number(draft.targetValue, dropsTrailingZero: true))
                    .font(GlassArenaFont.display(30, .heavy))
                    .foregroundStyle(GlassArena.ink)
                Text(display.unit)
                    .font(GlassArenaFont.text(15, .semibold))
                    .foregroundStyle(GlassArena.mutedLight)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                "Target \(display.measurement(draft.targetValue))"
            )

            Slider(
                value: $draft.targetValue,
                in: bounds,
                step: draft.metric.targetStep
            )
            .tint(GlassArena.teal800)
            .accessibilityIdentifier("duel.target")
            .accessibilityLabel("Target")

            HStack {
                ambitionLabel("Doable", isActive: ambition == 0)
                Spacer()
                ambitionLabel("Ambitious", isActive: ambition == 1)
                Spacer()
                ambitionLabel("Delusional", isActive: ambition == 2)
            }

            Rectangle()
                .fill(GlassArena.hairline.opacity(0.4))
                .frame(height: 1)

            HStack {
                Text("Runs")
                    .font(GlassArenaFont.text(14))
                    .foregroundStyle(GlassArena.mutedLight)
                Spacer()
                GlassStepper(
                    value: "\(days) day\(days == 1 ? "" : "s")",
                    tint: GlassArena.ink,
                    fontSize: 20,
                    valueWidth: 84,
                    decrementLabel: "Shorten the duel",
                    incrementLabel: "Lengthen the duel",
                    canDecrement: days > 1,
                    canIncrement: days < 30,
                    decrement: { days = max(1, days - 1) },
                    increment: { days = min(30, days + 1) }
                )
            }
        }
    }

    /// Which third of the target range the slider sits in.
    private var ambition: Int {
        let bounds = draft.metric.targetBounds
        let span = bounds.upperBound - bounds.lowerBound
        guard span > 0 else { return 0 }
        let fraction = (draft.targetValue - bounds.lowerBound) / span
        if fraction < 0.34 { return 0 }
        if fraction < 0.7 { return 1 }
        return 2
    }

    private func ambitionLabel(_ text: String, isActive: Bool) -> some View {
        Text(text.uppercased())
            .font(GlassArenaFont.text(10.5, .bold))
            .tracking(0.7)
            .foregroundStyle(
                isActive ? GlassArena.teal900 : GlassArena.mutedLightest
            )
    }

    private var stakeCard: some View {
        GlassCardSection(
            title: "On the line",
            footnote:
                "Whoever loses pays the winner's charity. GameTime never touches the money."
        ) {
            HStack {
                Spacer()
                GlassStepper(
                    value: stakeText,
                    decrementLabel: "Lower the stake",
                    incrementLabel: "Raise the stake",
                    canDecrement: draft.stakeAmountCents > 100,
                    canIncrement: draft.stakeAmountCents < 100_000,
                    decrement: {
                        draft.stakeAmountCents = max(
                            100,
                            draft.stakeAmountCents - 100
                        )
                    },
                    increment: {
                        draft.stakeAmountCents = min(
                            100_000,
                            draft.stakeAmountCents + 100
                        )
                    }
                )
                Spacer()
            }

            if !model.charities.isEmpty {
                Rectangle()
                    .fill(GlassArena.hairline.opacity(0.4))
                    .frame(height: 1)
                Text("Goes to")
                    .font(GlassArenaFont.text(13))
                    .foregroundStyle(GlassArena.mutedLight)
                FlowRow(spacing: 8) {
                    ForEach(model.charities) { charity in
                        GlassChip(
                            title: charity.name,
                            isSelected: draft.charityID == charity.id
                        ) {
                            draft.charityID = charity.id
                        }
                    }
                }
                .accessibilityIdentifier("duel.charity")
            }
        }
    }

    private var stakeText: String {
        (Double(draft.stakeAmountCents) / 100).formatted(
            .currency(code: "USD").precision(.fractionLength(0))
        )
    }

    /// The editor picks a duration; the draft still carries exact timestamps.
    private func commitDates() {
        let start = Date().addingTimeInterval(86_400)
        draft.startsAt = start
        draft.endsAt = start.addingTimeInterval(Double(days) * 86_400)
    }

    // MARK: Review

    private func review(terms: DuelTerms) -> some View {
        let display = MetricDisplay(metric: terms.metric)
        let isSavedRequest = model.pendingDuel?.terms.requestID == terms.requestID

        return ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Last look")
                        .font(GlassArenaFont.display(31, .heavy))
                        .foregroundStyle(GlassArena.ink)
                    Text(
                        "These terms freeze the moment you send them. Neither of you can move the target after that."
                    )
                    .font(GlassArenaFont.text(14))
                    .foregroundStyle(GlassArena.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                GlassCardSection(title: "Immutable terms", tier: .hero) {
                    TermRow(
                        label: "Opponent",
                        value: opponentName(for: terms.inviteeID)
                    )
                    TermRow(label: "Metric", value: terms.metric.title)
                    TermRow(
                        label: "Target",
                        value:
                            "\(display.measurement(terms.targetValue, dropsTrailingZero: true)) \(terms.cadence == .daily ? "a day" : "total")"
                    )
                    TermRow(label: "Runs", value: runsText(terms))
                    TermRow(
                        label: "On the line",
                        value: (Double(terms.stakeAmountCents) / 100)
                            .formatted(
                                .currency(code: "USD")
                                    .precision(.fractionLength(0))
                            ),
                        emphasis: GlassArena.amber700
                    )
                    TermRow(
                        label: "Goes to",
                        value: charityName(for: terms.charityID)
                    )
                    TermRow(
                        label: "If it's a tie",
                        value: tieBreakText(terms.tieBreak)
                    )
                    Rectangle()
                        .fill(GlassArena.hairline.opacity(0.4))
                        .frame(height: 1)
                    TermRow(
                        label: "Receipt",
                        value: terms.requestID.uuidString.lowercased(),
                        emphasis: GlassArena.inkSecondary,
                        isMonospaced: true
                    )
                    .accessibilityIdentifier("duel.request-id")
                }

                Button {
                    Task {
                        if await model.createDuel(terms) != nil {
                            router.selectedTab = .duels
                            // A duel you created is one you have already
                            // accepted, so it lands in Live awaiting their
                            // reply — not in your own Invites.
                            router.duelsSegment = .live
                            dismiss()
                        }
                    }
                } label: {
                    if model.isMutating {
                        ProgressView()
                            .tint(GlassArena.tealInk)
                            .accessibilityLabel("Sending duel")
                    } else {
                        Text("Send it")
                    }
                }
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        height: 56,
                        cornerRadius: 20,
                        fontSize: 18
                    )
                )
                .disabled(model.isMutating)
                .accessibilityIdentifier("duel.submit")

                if isSavedRequest {
                    Button("Discard local retry record") {
                        showingDiscardConfirmation = true
                    }
                    .font(GlassArenaFont.text(14, .semibold))
                    .foregroundStyle(GlassArena.destructive)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .disabled(model.isMutating)
                    .accessibilityIdentifier("duel.pending.discard-review")
                } else {
                    Button("Back to edit") {
                        reviewedTerms = nil
                    }
                    .buttonStyle(
                        GlassSecondaryButtonStyle(height: 50, cornerRadius: 18)
                    )
                    .disabled(model.isMutating)
                }

                Text(
                    isSavedRequest
                        ? "This saved retry survives a relaunch. Sending reuses the same receipt and terms — GameTime never retries it on its own."
                        : "GameTime saves these terms and this receipt on your device first, so a dropped signal can't send the same duel twice."
                )
                .font(GlassArenaFont.text(12))
                .foregroundStyle(GlassArena.mutedLight)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            }
            .padding(.horizontal, GlassArenaLayout.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 32)
            .frame(maxWidth: GlassArenaMetrics.contentCap)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .glassArenaBackground(.duelDetail)
        .navigationTitle("Last look")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func runsText(_ terms: DuelTerms) -> String {
        let dayCount = max(
            1,
            Int(
                (terms.endsAt.timeIntervalSince(terms.startsAt) / 86_400)
                    .rounded()
            )
        )
        return
            "\(dayCount) day\(dayCount == 1 ? "" : "s") from \(terms.startsAt.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func tieBreakText(_ tieBreak: ContestTieBreak) -> String {
        switch tieBreak {
        case .integrityScore: "Cleanest data wins"
        case .earliestToTarget: "First to the target wins"
        case .bothDonate: "You both pay"
        case .void: "Nobody pays"
        }
    }

    private func opponentName(for id: UUID) -> String {
        model.acceptedFriendships.first { $0.otherUserID == id }?
            .displayName ?? "Account \(id.uuidString.lowercased())"
    }

    private func charityName(for id: UUID) -> String {
        model.charities.first { $0.id == id }?.name
            ?? "Charity \(id.uuidString.lowercased())"
    }

    private func resetDraft() {
        draft = DuelDraft()
        days = 3
        draft.inviteeID = model.acceptedFriendships.first?.otherUserID
        draft.charityID = model.charities.first?.id
    }
}

// MARK: - Accept an invitation

struct AcceptInvitationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    let contestID: UUID
    @State private var charityID: UUID?

    private var contest: ContestCard? {
        model.contests.first { $0.id == contestID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let contest {
                    content(contest)
                } else {
                    unavailable
                }
            }
            .navigationTitle("Their terms")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(model.isMutating)
                        .tint(GlassArena.teal800)
                }
            }
            .onAppear {
                charityID = charityID ?? model.charities.first?.id
            }
        }
        .interactiveDismissDisabled(model.isMutating)
    }

    private func content(_ contest: ContestCard) -> some View {
        let standing = model.standing(for: contest.id)
        let opponent = model.opponent(for: contest)
        let display = contest.display

        return ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(
                        opponent.map { "\($0.firstName) threw down." }
                            ?? "You've been challenged."
                    )
                    .font(GlassArenaFont.display(31, .heavy))
                    .foregroundStyle(GlassArena.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "Taking it freezes these terms for both of you. Nothing moves after that."
                    )
                    .font(GlassArenaFont.text(14))
                    .foregroundStyle(GlassArena.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 4)

                GlassCardSection(title: "Immutable terms", tier: .hero) {
                    TermRow(label: "Duel", value: contest.title)
                    TermRow(label: "Metric", value: contest.metric.title)
                    TermRow(
                        label: "Target",
                        value:
                            "\(display.measurement(contest.targetValue, dropsTrailingZero: true)) \(contest.cadence == .daily ? "a day" : "total")"
                    )
                    TermRow(
                        label: "On the line",
                        value: contest.stakeCompactText,
                        emphasis: GlassArena.amber700
                    )
                    TermRow(
                        label: "If it's a tie",
                        value: contest.tieBreak.title
                    )
                }

                GlassCardSection(
                    title: "Your charity",
                    footnote:
                        "If you win, this is where their money goes. Your timezone (\(model.profile?.timezone ?? "UTC")) freezes too."
                ) {
                    FlowRow(spacing: 8) {
                        ForEach(model.charities) { charity in
                            GlassChip(
                                title: charity.name,
                                isSelected: charityID == charity.id
                            ) {
                                charityID = charity.id
                            }
                        }
                    }
                    .accessibilityIdentifier("invitation.charity")
                }

                Button {
                    guard let charityID else { return }
                    Task {
                        await model.acceptInvitation(
                            contestID: contest.id,
                            charityID: charityID
                        )
                        if model.contests.first(where: { $0.id == contest.id })?
                            .myStatus == .accepted
                        {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isMutating {
                        ProgressView()
                            .tint(GlassArena.tealInk)
                            .accessibilityLabel("Taking the duel")
                    } else {
                        Label(
                            "Take it — \(contest.stakeCompactText)",
                            systemImage: "checkmark"
                        )
                    }
                }
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        height: 56,
                        cornerRadius: 20,
                        fontSize: 18
                    )
                )
                .disabled(charityID == nil || model.isMutating)
                .accessibilityIdentifier("invitation.accept")

                Button("Nope") {
                    Task {
                        await model.declineInvitation(contestID: contest.id)
                        dismiss()
                    }
                }
                .buttonStyle(GlassQuietButtonStyle(height: 50, cornerRadius: 18))
                .disabled(model.isMutating)
                .accessibilityIdentifier("invitation.decline")

                if standing.opponent == nil {
                    Text(
                        "The roster hasn't loaded yet, so the rope will start at parity."
                    )
                    .font(GlassArenaFont.text(12))
                    .foregroundStyle(GlassArena.mutedLight)
                    .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, GlassArenaLayout.screenPadding)
            .padding(.top, 6)
            .padding(.bottom, 32)
            .frame(maxWidth: GlassArenaMetrics.contentCap)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .glassArenaBackground(.duelDetail)
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "envelope.badge")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(GlassArena.mutedLight)
            Text("This invitation is gone")
                .font(GlassArenaFont.display(24, .heavy))
                .foregroundStyle(GlassArena.ink)
            Text("Close this and refresh the list.")
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.inkTertiary)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassArenaBackground(.duelDetail)
    }
}

// MARK: - Metric targets

extension ContestMetric {
    var display: MetricDisplay { MetricDisplay(metric: self) }

    /// The slider's range, spanning "doable" to "delusional".
    var targetBounds: ClosedRange<Double> {
        let suggested = suggestedTarget
        return (suggested * 0.4)...(suggested * 3)
    }

    var targetStep: Double {
        switch self {
        case .steps: 500
        case .distanceMeters: 500
        case .activeEnergyKilocalories: 25
        case .exerciseMinutes: 5
        }
    }
}

// MARK: - Flow layout

/// Wraps chips onto as many lines as they need.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(
            width: maxWidth == .infinity ? x : maxWidth,
            height: y + lineHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
