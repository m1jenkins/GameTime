import SwiftUI

/// The payoff. One celebratory moment with the settlement stated plainly.
///
/// A win and a loss get identical choreography — no confetti, no consolation
/// copy. The number differences carry it.
struct DuelResultView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let contestID: UUID

    @State private var headlineScale: CGFloat = 0.94
    @State private var hasRevealedSettlement = false

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
        let didWin = model.didWin(contest)
        let opponentName = standing.opponent?.firstName ?? "They"

        return VStack(spacing: 0) {
            GlassNavRow(backTitle: "Duels", back: { dismiss() }) {
                EmptyView()
            }

            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 20) {
                        VStack(spacing: 10) {
                            DuelEyebrow(
                                text: contest.title,
                                fontSize: 12,
                                tracking: 1.2,
                                isChip: true
                            )
                            headline(
                                didWin: didWin,
                                opponentName: opponentName,
                                width: proxy.size.width
                            )
                        }

                        resultCard(
                            contest,
                            standing: standing,
                            didWin: didWin,
                            opponentName: opponentName
                        )

                        actions(contest, standing: standing, didWin: didWin)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 24)
                    // Vertically centred when it fits, scrollable when it
                    // doesn't.
                    .frame(minHeight: proxy.size.height, alignment: .center)
                    .frame(maxWidth: GlassArenaMetrics.contentCap)
                    .frame(maxWidth: .infinity)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassArenaBackground(.result)
        .onAppear {
            guard !reduceMotion else {
                headlineScale = 1
                hasRevealedSettlement = true
                return
            }
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                headlineScale = 1
            }
        }
    }

    // MARK: Headline

    private func headline(
        didWin: Bool?,
        opponentName: String,
        width: CGFloat
    ) -> some View {
        let size = GlassArenaMetrics.resultHeadline(width: width)
        return Text(headlineText(didWin: didWin, opponentName: opponentName))
            .font(GlassArenaFont.display(size, .heavy))
            .foregroundStyle(GlassArena.ink)
            .multilineTextAlignment(.center)
            .lineSpacing(GlassArenaFont.displayLineSpacing(size))
            .minimumScaleFactor(0.7)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .scaleEffect(headlineScale)
            .accessibilityAddTraits(.isHeader)
    }

    private func headlineText(didWin: Bool?, opponentName: String) -> String {
        switch didWin {
        case true: "You took\nit."
        case false: "\(opponentName) took\nit."
        case nil: "It's\nsettled."
        }
    }

    // MARK: Result card

    private func resultCard(
        _ contest: ContestCard,
        standing: DuelStanding,
        didWin: Bool?,
        opponentName: String
    ) -> some View {
        let display = contest.display
        // The winner reads on the left, whoever that is.
        let youWon = didWin == true

        return VStack(spacing: 20) {
            HStack(alignment: .bottom) {
                scoreColumn(
                    initials: youWon
                        ? (model.profile?.initials ?? "?")
                        : (standing.opponent?.initials ?? "?"),
                    name: youWon ? "You" : opponentName,
                    side: youWon ? .you : .them,
                    value: youWon ? standing.myProgress : standing.theirProgress,
                    display: display,
                    target: contest.targetValue,
                    isWinner: true,
                    alignment: .leading
                )

                Text("VS")
                    .font(GlassArenaFont.display(14, .heavy))
                    .tracking(1.7)
                    .foregroundStyle(GlassArena.hairline)
                    .padding(.bottom, 26)
                    .frame(maxWidth: .infinity)

                scoreColumn(
                    initials: youWon
                        ? (standing.opponent?.initials ?? "?")
                        : (model.profile?.initials ?? "?"),
                    name: youWon ? opponentName : "You",
                    side: youWon ? .them : .you,
                    value: youWon ? standing.theirProgress : standing.myProgress,
                    display: display,
                    target: contest.targetValue,
                    isWinner: false,
                    alignment: .trailing
                )
            }

            DuelRope(
                standing: standing,
                metric: contest.metric,
                size: .result,
                outcome: youWon ? .won : .lost,
                onFillComplete: {
                    GlassArenaHaptics.light()
                    withAnimation(.easeOut(duration: 0.3)) {
                        hasRevealedSettlement = true
                    }
                }
            )

            settlementRow(
                contest,
                standing: standing,
                didWin: didWin,
                opponentName: opponentName
            )
            .opacity(hasRevealedSettlement ? 1 : 0)
            .offset(y: hasRevealedSettlement ? 0 : 8)
        }
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .glassPane(.hero, cornerRadius: 36)
    }

    private func scoreColumn(
        initials: String,
        name: String,
        side: GlassAvatar.Side,
        value: Double,
        display: MetricDisplay,
        target: Double,
        isWinner: Bool,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 7) {
            HStack(spacing: 7) {
                if alignment == .trailing {
                    Text(name)
                        .font(GlassArenaFont.text(13, .bold))
                        .foregroundStyle(
                            isWinner
                                ? side.text
                                : GlassArena.mutedLighter
                        )
                }
                GlassAvatar(
                    initials: initials,
                    size: 30,
                    side: side,
                    ringWidth: 2,
                    isDesaturated: !isWinner
                )
                if alignment == .leading {
                    Text(name)
                        .font(GlassArenaFont.text(13, .bold))
                        .foregroundStyle(
                            isWinner
                                ? side.text
                                : GlassArena.mutedLighter
                        )
                }
            }

            Text(display.number(value))
                .font(GlassArenaFont.display(42, .heavy))
                .foregroundStyle(
                    isWinner ? GlassArena.ink : GlassArena.desaturatedScore
                )

            Text(
                "\(display.unit) · \(value >= target ? "target hit" : (isWinner ? "ahead" : "short"))"
            )
            .font(GlassArenaFont.text(13))
            .foregroundStyle(
                isWinner ? GlassArena.mutedLight : GlassArena.mutedLightest
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(name), \(display.measurement(value))\(isWinner ? ", winner" : "")"
        )
    }

    private func settlementRow(
        _ contest: ContestCard,
        standing: DuelStanding,
        didWin: Bool?,
        opponentName: String
    ) -> some View {
        HStack(spacing: 14) {
            Text(contest.stakeCompactText)
                .font(GlassArenaFont.display(17, .heavy))
                .foregroundStyle(GlassArena.amber800)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(GlassArena.amber400.opacity(0.20))
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(
                    settlementHeadline(
                        contest,
                        standing: standing,
                        didWin: didWin,
                        opponentName: opponentName
                    )
                )
                .font(GlassArenaFont.text(16, .bold))
                .foregroundStyle(GlassArena.ink)
                .fixedSize(horizontal: false, vertical: true)

                Text(
                    didWin == true
                        ? "The charity you picked. Enjoy that."
                        : "The charity they picked. Pay up."
                )
                .font(GlassArenaFont.text(13))
                .foregroundStyle(GlassArena.mutedLight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private func settlementHeadline(
        _ contest: ContestCard,
        standing: DuelStanding,
        didWin: Bool?,
        opponentName: String
    ) -> String {
        let charity = standing.charityName ?? "the winner's charity"
        switch didWin {
        case true:
            return
                "\(opponentName) owes \(charity) \(contest.stakeCompactText)"
        case false:
            return "You owe \(charity) \(contest.stakeCompactText)"
        case nil:
            return "Nothing owed on this one"
        }
    }

    // MARK: Actions

    private func actions(
        _ contest: ContestCard,
        standing: DuelStanding,
        didWin: Bool?
    ) -> some View {
        // Rematch is the primary action on both a win and a loss.
        VStack(spacing: 10) {
            Button {
                router.presentedSheet = .createDuel
            } label: {
                Label("Run it back", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(
                GlassPrimaryButtonStyle(
                    height: 58,
                    cornerRadius: 22,
                    fontSize: 19
                )
            )
            .disabled(!model.canStartDuel)
            .accessibilityIdentifier("result.rematch")

            ShareLink(
                item: receipt(
                    contest,
                    standing: standing,
                    didWin: didWin
                )
            ) {
                Label("Share the receipt", systemImage: "square.and.arrow.up")
                    .font(GlassArenaFont.text(16, .semibold))
                    .foregroundStyle(GlassArena.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .glassPane(.standard, cornerRadius: 20)
            }
            .accessibilityIdentifier("result.share")
        }
    }

    private func receipt(
        _ contest: ContestCard,
        standing: DuelStanding,
        didWin: Bool?
    ) -> String {
        let display = contest.display
        let them = standing.opponent?.firstName ?? "them"
        let charity = standing.charityName ?? "their charity"
        let outcome =
            switch didWin {
            case true:
                "I took it. \(them) owes \(charity) \(contest.stakeCompactText)."
            case false:
                "\(them) took it. I owe \(charity) \(contest.stakeCompactText)."
            case nil:
                "It's settled."
            }
        return
            "\(contest.title): \(display.measurement(standing.myProgress)) to \(display.measurement(standing.theirProgress)). \(outcome)"
    }

    private var unavailable: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.trianglebadge.exclamationmark")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(GlassArena.mutedLight)
            Text("No receipt here")
                .font(GlassArenaFont.display(24, .heavy))
                .foregroundStyle(GlassArena.ink)
            Text("Refresh the list and try again.")
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.inkTertiary)
            Button("Back") { dismiss() }
                .buttonStyle(GlassSecondaryButtonStyle())
                .frame(maxWidth: 200)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassArenaBackground(.result)
    }
}
