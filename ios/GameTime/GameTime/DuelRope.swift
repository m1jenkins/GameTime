import SwiftUI

// The tug-of-war rope: one cord, two segments, a sliding knot. This is the app's
// defining visual and the only place a duel's standing is drawn.
//
// The knot sits at your share of combined progress. The centre marks parity. The
// arrow in the knot points toward whoever is winning.

// MARK: - Hatch

/// The diagonal weave over each cord segment. Yours leans one way and theirs the
/// other, so the weave leans into the centre.
private struct HatchPattern: Shape {
    var spacing: CGFloat = 8
    var stripeWidth: CGFloat = 3
    /// Lean direction — mirrored between the two segments.
    var leansRight: Bool
    /// Slow crawl toward the winning side.
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // A 25° lean off vertical reads as a weave without turning into stripes.
        let slant = rect.height * 0.466 * (leansRight ? 1 : -1)
        let margin = abs(slant) + spacing
        var path = Path()
        var x = rect.minX - margin + phase.truncatingRemainder(dividingBy: spacing)
        while x < rect.maxX + margin {
            path.move(to: CGPoint(x: x, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + stripeWidth, y: rect.maxY))
            path.addLine(to: CGPoint(x: x + stripeWidth + slant, y: rect.minY))
            path.addLine(to: CGPoint(x: x + slant, y: rect.minY))
            path.closeSubpath()
            x += spacing
        }
        return path
    }
}

// MARK: - Sizes

enum RopeSize {
    /// Duel detail — the hero. Tension ticks, hatch and glyph.
    case hero
    /// Today's duel card.
    case medium
    /// A row in the Duels list.
    case small
    /// The settled rope on the Result screen.
    case result

    var containerHeight: CGFloat {
        switch self {
        case .hero: 52
        case .medium: 38
        case .small: 32
        case .result: 26
        }
    }

    var cordHeight: CGFloat {
        switch self {
        case .hero: 20
        case .medium, .small: 14
        case .result: 12
        }
    }

    var knotSize: CGFloat {
        switch self {
        case .hero: 40
        case .medium: 30
        case .small, .result: 26
        }
    }

    var knotRadius: CGFloat {
        switch self {
        case .hero: 15
        case .medium: 11
        case .small, .result: 10
        }
    }

    var glyphSize: CGFloat {
        switch self {
        case .hero: 17
        case .medium: 13
        case .result: 13
        case .small: 0
        }
    }

    var showsTicks: Bool { self == .hero }
    var showsHatch: Bool { self == .hero }
    var showsGlyph: Bool { self != .small }
    /// The hero marks parity with a taller centre tick instead of a line.
    var showsParityLine: Bool { self == .medium }
}

/// A live rope, or a settled one pinned to whoever took it.
enum RopeOutcome: Equatable {
    case live
    case won
    case lost

    var isSettled: Bool { self != .live }
}

// MARK: - Knot

private struct RopeKnot: View {
    let size: CGFloat
    let cornerRadius: CGFloat
    let glyph: String?
    let glyphSize: CGFloat
    let glyphColor: Color

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(GlassArena.knot)
            .frame(width: size, height: size)
            .overlay {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white,
                            Color(glassArenaHex: 0x142834, opacity: 0.06),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            }
            .overlay {
                if let glyph {
                    Image(systemName: glyph)
                        .font(
                            .system(
                                size: glyphSize,
                                weight: .heavy
                            )
                        )
                        .foregroundStyle(glyphColor)
                }
            }
            .shadow(
                color: Color(glassArenaHex: 0x142834, opacity: 0.60),
                radius: 13,
                y: 12
            )
    }
}

// MARK: - Tension ticks

private struct TensionTicks: View {
    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                let isCentre = index == 3
                Rectangle()
                    .fill(
                        GlassArena.ink.opacity(isCentre ? 0.30 : 0.14)
                    )
                    .frame(width: 1, height: isCentre ? 9 : 6)
                if index < 6 { Spacer(minLength: 0) }
            }
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, alignment: .top)
    }
}

// MARK: - The rope

struct DuelRope: View {
    let standing: DuelStanding
    let metric: ContestMetric
    var size: RopeSize = .hero
    /// A settled rope is one colour and pins the knot to whoever took it.
    var outcome: RopeOutcome = .live
    /// Fires when the settled rope finishes filling, so the Result screen can
    /// haptic and bring in the settlement row behind it.
    var onFillComplete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Animated separately from `standing.split` so the rope can settle from
    /// parity on appear and spring to each new value after that.
    @State private var displayedSplit: Double = 0.5
    @State private var hatchPhase: CGFloat = 0
    @State private var isRevealingExactValues = false

    private var display: MetricDisplay { MetricDisplay(metric: metric) }

    private var winnerSide: RopeEvent.Direction? {
        if standing.isLevel { return nil }
        return standing.isAhead ? .youPulled : .theyPulled
    }

    /// The arrow points toward whoever is winning — left when that is you.
    private var knotGlyph: String? {
        guard size.showsGlyph else { return nil }
        if outcome.isSettled { return "checkmark" }
        switch winnerSide {
        case .youPulled: return "arrow.left"
        case .theyPulled: return "arrow.right"
        default: return nil
        }
    }

    private var knotGlyphColor: Color {
        switch outcome {
        case .live: GlassArena.knotGlyph
        case .won: GlassArena.teal800
        case .lost: GlassArena.violet800
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if size.showsTicks {
                TensionTicks()
                Spacer(minLength: 0)
            }

            GeometryReader { proxy in
                cord(width: proxy.size.width)
            }
            .frame(height: max(size.cordHeight, size.knotSize))

            if size.showsTicks { Spacer(minLength: 0) }
        }
        .frame(height: size.containerHeight)
        .onAppear(perform: settleOnAppear)
        .onChange(of: targetSplit) { _, newValue in
            // Reduce Motion keeps this one — the knot's travel carries meaning.
            withAnimation(.spring(response: 0.5, dampingFraction: 0.68)) {
                displayedSplit = newValue
            }
        }
        .onChange(of: reduceMotion) { _, _ in startHatchCrawl() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private func settleOnAppear() {
        // Settle from parity so the user sees the rope find its position.
        let duration = outcome.isSettled ? 0.7 : 0.6
        withAnimation(.easeOut(duration: duration)) {
            displayedSplit = targetSplit
        }
        startHatchCrawl()

        guard let onFillComplete else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            onFillComplete()
        }
    }

    private var targetSplit: Double {
        switch outcome {
        case .live: standing.split
        case .won: 1
        case .lost: 0
        }
    }

    @ViewBuilder
    private func cord(width: CGFloat) -> some View {
        let yourWidth = max(0, min(width, width * displayedSplit))

        ZStack(alignment: .leading) {
            // Their share fills the track; yours is drawn over the left of it.
            Capsule()
                .fill(
                    outcome == .won
                        ? GlassArena.yourCord
                        : GlassArena.theirCord
                )
                .overlay {
                    if size.showsHatch && !outcome.isSettled {
                        HatchPattern(leansRight: false, phase: -hatchPhase)
                            .fill(.white.opacity(0.22))
                    }
                }
                .frame(height: size.cordHeight)

            Capsule()
                .fill(GlassArena.yourCord)
                .overlay {
                    if size.showsHatch {
                        HatchPattern(leansRight: true, phase: hatchPhase)
                            .fill(.white.opacity(0.24))
                    }
                }
                .frame(width: yourWidth, height: size.cordHeight)
                .clipShape(Capsule())

            if size.showsParityLine && !outcome.isSettled {
                Rectangle()
                    .fill(GlassArena.ink.opacity(0.20))
                    .frame(width: 1.5, height: size.cordHeight - 4)
                    .offset(x: width / 2 - 0.75)
            }

            knot(width: width, yourWidth: yourWidth)
        }
        .frame(height: max(size.cordHeight, size.knotSize))
        // An inset top shadow and a bright bottom lip, so the cord reads as a
        // rope in a channel rather than a slider track. Centred to match the
        // cord fills, which sit in the middle of the taller knot row.
        .overlay {
            Capsule()
                .fill(
                    LinearGradient(
                        stops: [
                            .init(
                                color: Color(
                                    glassArenaHex: 0x142834,
                                    opacity: 0.24
                                ),
                                location: 0
                            ),
                            .init(color: .clear, location: 0.42),
                            .init(color: .white.opacity(0.38), location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(height: size.cordHeight)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func knot(width: CGFloat, yourWidth: CGFloat) -> some View {
        // A settled rope deliberately hangs half the knot past the winner's edge.
        let x: CGFloat =
            switch outcome {
            case .won: width
            case .lost: 0
            case .live:
                min(
                    max(yourWidth, size.knotSize / 2),
                    max(size.knotSize / 2, width - size.knotSize / 2)
                )
            }

        RopeKnot(
            size: size.knotSize,
            cornerRadius: size.knotRadius,
            glyph: knotGlyph,
            glyphSize: size.glyphSize,
            glyphColor: knotGlyphColor
        )
        .position(x: x, y: max(size.cordHeight, size.knotSize) / 2)
        .overlay(alignment: .top) {
            if isRevealingExactValues {
                exactValues
                    .offset(y: -34)
            }
        }
        .onLongPressGesture(minimumDuration: 0.35) {
        } onPressingChanged: { isPressing in
            // Pressing and holding the knot reveals the exact numbers.
            withAnimation(.easeOut(duration: 0.15)) {
                isRevealingExactValues = isPressing
            }
        }
    }

    private var exactValues: some View {
        HStack(spacing: 6) {
            Text(display.measurement(standing.myProgress))
                .foregroundStyle(GlassArena.teal900)
            Text("vs")
                .foregroundStyle(GlassArena.mutedLightest)
            Text(display.measurement(standing.theirProgress))
                .foregroundStyle(GlassArena.violet800)
        }
        .font(GlassArenaFont.display(13, .bold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassPane(.hero, cornerRadius: 12)
        .fixedSize()
    }

    private func startHatchCrawl() {
        hatchPhase = 0
        guard !reduceMotion, size.showsHatch, !outcome.isSettled else { return }
        // Roughly 1pt/s toward the winning side.
        let direction: CGFloat = standing.isAhead ? -1 : 1
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            hatchPhase = 8 * direction
        }
    }

    private var accessibilityLabel: String {
        let you = display.measurement(standing.myProgress)
        let them = display.measurement(standing.theirProgress)
        switch outcome {
        case .won: return "You took it. \(you) to \(them)."
        case .lost:
            let name = standing.opponent?.firstName ?? "Your opponent"
            return "\(name) took it. \(them) to \(you)."
        case .live: break
        }
        guard standing.hasProgress else {
            return "Rope at parity. No progress synced yet."
        }
        let name = standing.opponent?.displayName ?? "Your opponent"
        if standing.isLevel {
            return "Level. You \(you), \(name) \(them)."
        }
        let state = standing.isAhead ? "ahead" : "behind"
        return "You are \(state). You \(you), \(name) \(them)."
    }
}

// MARK: - Deficit callout

/// Sits below every rope: the gap, and what it takes per day to flip it.
struct DeficitCallout: View {
    let standing: DuelStanding
    let contest: ContestCard
    var now = Date()

    private var copy: DeficitCopy {
        DeficitCopy(standing: standing, metric: contest.metric)
    }

    private var tint: (background: Color, icon: Color, headline: Color, detail: Color) {
        if standing.isAhead {
            return (
                GlassArena.teal700.opacity(0.12),
                GlassArena.teal800,
                GlassArena.teal900,
                GlassArena.teal950
            )
        }
        return (
            GlassArena.violet500.opacity(0.12),
            GlassArena.violet800,
            GlassArena.violet800,
            GlassArena.violet850
        )
    }

    private var paceText: String? {
        let days = DuelClock.daysLeft(until: contest.endsAt, now: now)
        guard
            let pace = standing.paceToWin(
                target: contest.targetValue,
                daysLeft: days
            )
        else {
            return nil
        }
        let display = MetricDisplay(metric: contest.metric)
        let verb = standing.isAhead ? "to close it out" : "to flip it"
        return "· \(display.number(pace))/day \(verb)"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint.icon)
            Text(copy.headline)
                .font(GlassArenaFont.display(16, .heavy))
                .foregroundStyle(tint.headline)
            if let paceText {
                Text(paceText)
                    .font(GlassArenaFont.text(14, .medium))
                    .foregroundStyle(tint.detail)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.background)
        )
        .accessibilityElement(children: .combine)
    }
}
