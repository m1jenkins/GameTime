import SwiftUI

// The two-layer background that makes the glass read as glass. Every screen has
// ambient blobs drifting behind a data substrate — two area curves standing for
// the two athletes' cumulative progress. Panes sit at only ~22–34% white, so the
// curves show through them. Flattening either layer collapses the aesthetic.

// MARK: - Data substrate

/// One athlete's cumulative-progress curve, drawn in the handoff's 393 x 852
/// design space and stretched to fill (the source SVG uses
/// `preserveAspectRatio="none"`, so the non-uniform scale is intentional).
///
/// `lift` raises the curve as that athlete gains ground, which is what makes the
/// background the data rather than decoration.
struct SubstrateCurve: Shape {
    struct Segment {
        let control1: CGPoint
        let control2: CGPoint
        let end: CGPoint
    }

    static let designSize = CGSize(width: 393, height: 852)
    /// How far the curve travels between no progress and a runaway lead.
    static let liftRange: CGFloat = 44

    let start: CGPoint
    let segments: [Segment]
    var lift: CGFloat
    var closesToBottom: Bool

    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / Self.designSize.width
        let scaleY = rect.height / Self.designSize.height
        let rise = lift * Self.liftRange

        func map(_ point: CGPoint) -> CGPoint {
            CGPoint(
                x: rect.minX + point.x * scaleX,
                y: rect.minY + (point.y - rise) * scaleY
            )
        }

        var path = Path()
        path.move(to: map(start))
        for segment in segments {
            path.addCurve(
                to: map(segment.end),
                control1: map(segment.control1),
                control2: map(segment.control2)
            )
        }
        if closesToBottom {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

extension SubstrateCurve {
    static func curve(
        _ start: CGPoint,
        _ segments: [Segment],
        lift: CGFloat = 0,
        closesToBottom: Bool = true
    ) -> SubstrateCurve {
        SubstrateCurve(
            start: start,
            segments: segments,
            lift: lift,
            closesToBottom: closesToBottom
        )
    }

    private static func segment(
        _ c1: (CGFloat, CGFloat),
        _ c2: (CGFloat, CGFloat),
        _ end: (CGFloat, CGFloat)
    ) -> Segment {
        Segment(
            control1: CGPoint(x: c1.0, y: c1.1),
            control2: CGPoint(x: c2.0, y: c2.1),
            end: CGPoint(x: end.0, y: end.1)
        )
    }

    // The four screens' drawn curve pairs, read straight off the design.

    static func todayBehind(lift: CGFloat) -> SubstrateCurve {
        curve(
            CGPoint(x: 0, y: 700),
            [
                segment((60, 660), (90, 610), (140, 588)),
                segment((200, 562), (236, 500), (290, 452)),
                segment((330, 416), (366, 396), (393, 384)),
            ],
            lift: lift
        )
    }

    static func todayFront(lift: CGFloat) -> SubstrateCurve {
        curve(
            CGPoint(x: 0, y: 748),
            [
                segment((70, 722), (96, 678), (150, 650)),
                segment((214, 618), (250, 566), (300, 522)),
                segment((338, 490), (368, 470), (393, 458)),
            ],
            lift: lift
        )
    }

    static func detailBehind(lift: CGFloat) -> SubstrateCurve {
        curve(
            CGPoint(x: 0, y: 660),
            [
                segment((56, 636), (88, 588), (138, 560)),
                segment((198, 526), (232, 468), (288, 420)),
                segment((330, 384), (366, 362), (393, 350)),
            ],
            lift: lift
        )
    }

    static func detailFront(lift: CGFloat) -> SubstrateCurve {
        curve(
            CGPoint(x: 0, y: 716),
            [
                segment((66, 692), (94, 648), (148, 618)),
                segment((212, 582), (248, 528), (300, 486)),
                segment((338, 456), (368, 436), (393, 424)),
            ],
            lift: lift
        )
    }

    static func duelsBehind(lift: CGFloat) -> SubstrateCurve {
        curve(
            CGPoint(x: 0, y: 690),
            [
                segment((60, 668), (92, 620), (142, 592)),
                segment((202, 560), (236, 504), (292, 458)),
                segment((332, 424), (366, 404), (393, 392)),
            ],
            lift: lift
        )
    }

    static func duelsFront(lift: CGFloat) -> SubstrateCurve {
        curve(
            CGPoint(x: 0, y: 742),
            [
                segment((68, 718), (96, 674), (150, 644)),
                segment((214, 610), (250, 556), (302, 514)),
                segment((340, 484), (368, 464), (393, 452)),
            ],
            lift: lift
        )
    }

    static func resultBehind(lift: CGFloat) -> SubstrateCurve {
        curve(
            CGPoint(x: 0, y: 700),
            [
                segment((60, 690), (92, 660), (142, 630)),
                segment((202, 594), (236, 520), (292, 452)),
                segment((332, 404), (366, 372), (393, 356)),
            ],
            lift: lift
        )
    }

    static func resultFront(lift: CGFloat) -> SubstrateCurve {
        curve(
            CGPoint(x: 0, y: 736),
            [
                segment((68, 726), (96, 700), (150, 678)),
                segment((214, 652), (250, 610), (302, 578)),
                segment((340, 554), (368, 540), (393, 532)),
            ],
            lift: lift
        )
    }
}

// MARK: - Ambient blobs

private struct AmbientBlob: Identifiable {
    enum Anchor {
        case topLeading(x: CGFloat, y: CGFloat)
        case topTrailing(x: CGFloat, y: CGFloat)
        case bottomLeading(x: CGFloat, y: CGFloat)
        case bottomTrailing(x: CGFloat, y: CGFloat)

        var alignment: Alignment {
            switch self {
            case .topLeading: .topLeading
            case .topTrailing: .topTrailing
            case .bottomLeading: .bottomLeading
            case .bottomTrailing: .bottomTrailing
            }
        }

        /// Insets in the handoff are CSS `left/right/top/bottom`; flip the sign
        /// on the trailing and bottom edges to get a SwiftUI offset.
        var offset: CGSize {
            switch self {
            case .topLeading(let x, let y): CGSize(width: x, height: y)
            case .topTrailing(let x, let y): CGSize(width: -x, height: y)
            case .bottomLeading(let x, let y): CGSize(width: x, height: -y)
            case .bottomTrailing(let x, let y): CGSize(width: -x, height: -y)
            }
        }
    }

    let id = UUID()
    let color: Color
    let size: CGFloat
    let anchor: Anchor
    let blur: CGFloat
    let opacity: Double
    /// Full out-and-back period, as authored in CSS.
    let period: Double
    /// The handoff's `reverse` blobs, drifting the opposite way so the three
    /// never synchronise.
    let mirrored: Bool
}

private struct AmbientBlobView: View {
    let blob: AmbientBlob
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drifting = false

    var body: some View {
        let direction: CGFloat = blob.mirrored ? -1 : 1
        Circle()
            .fill(blob.color)
            .frame(width: blob.size, height: blob.size)
            .blur(radius: blob.blur)
            .opacity(blob.opacity)
            .scaleEffect(drifting ? 1.06 : 1)
            .offset(
                x: blob.anchor.offset.width + (drifting ? 14 * direction : 0),
                y: blob.anchor.offset.height + (drifting ? -18 * direction : 0)
            )
            .frame(
                maxWidth: .infinity,
                maxHeight: .infinity,
                alignment: blob.anchor.alignment
            )
            .animation(
                reduceMotion
                    ? nil
                    : .easeInOut(duration: blob.period / 2)
                        .repeatForever(autoreverses: true),
                value: drifting
            )
            .onAppear {
                guard !reduceMotion else { return }
                drifting = true
            }
    }
}

// MARK: - Screen background

/// A screen's substrate pair: which colours, at what opacity, and whether the
/// curves are also stroked (Duel detail only).
struct SubstrateStyle {
    let behindColor: Color
    let frontColor: Color
    let behindStroke: Color?
    let frontStroke: Color?
    let behind: (CGFloat) -> SubstrateCurve
    let front: (CGFloat) -> SubstrateCurve
    /// True when the *front* curve is yours. On Result the teal curve is drawn
    /// first, so the layer order flips.
    let frontIsYours: Bool
}

extension GlassArenaScreen {
    fileprivate var blobs: [AmbientBlob] {
        switch self {
        case .today:
            [
                AmbientBlob(
                    color: GlassArena.teal700,
                    size: 380,
                    anchor: .topLeading(x: -120, y: 20),
                    blur: 76,
                    opacity: 0.29,
                    period: 15,
                    mirrored: false
                ),
                AmbientBlob(
                    color: GlassArena.violet500,
                    size: 340,
                    anchor: .topTrailing(x: -110, y: 300),
                    blur: 80,
                    opacity: 0.19,
                    period: 19,
                    mirrored: true
                ),
                AmbientBlob(
                    color: GlassArena.amber400,
                    size: 300,
                    anchor: .bottomLeading(x: 40, y: -100),
                    blur: 76,
                    opacity: 0.21,
                    period: 17,
                    mirrored: false
                ),
            ]
        case .duels:
            [
                AmbientBlob(
                    color: GlassArena.amber400,
                    size: 340,
                    anchor: .topTrailing(x: -100, y: 40),
                    blur: 76,
                    opacity: 0.27,
                    period: 16,
                    mirrored: false
                ),
                AmbientBlob(
                    color: GlassArena.teal700,
                    size: 360,
                    anchor: .topLeading(x: -110, y: 330),
                    blur: 74,
                    opacity: 0.29,
                    period: 20,
                    mirrored: true
                ),
                AmbientBlob(
                    color: GlassArena.violet500,
                    size: 300,
                    anchor: .bottomTrailing(x: 10, y: -110),
                    blur: 78,
                    opacity: 0.22,
                    period: 18,
                    mirrored: false
                ),
            ]
        case .duelDetail:
            [
                AmbientBlob(
                    color: GlassArena.teal700,
                    size: 420,
                    anchor: .topLeading(x: -150, y: 150),
                    blur: 72,
                    opacity: 0.35,
                    period: 15,
                    mirrored: false
                ),
                AmbientBlob(
                    color: GlassArena.violet500,
                    size: 420,
                    anchor: .topTrailing(x: -150, y: 110),
                    blur: 72,
                    opacity: 0.27,
                    period: 18,
                    mirrored: true
                ),
                AmbientBlob(
                    color: GlassArena.amber400,
                    size: 320,
                    anchor: .bottomLeading(x: 40, y: -120),
                    blur: 78,
                    opacity: 0.27,
                    period: 20,
                    mirrored: false
                ),
            ]
        case .result:
            [
                AmbientBlob(
                    color: GlassArena.teal700,
                    size: 460,
                    anchor: .topLeading(x: -40, y: -90),
                    blur: 74,
                    opacity: 0.21,
                    period: 15,
                    mirrored: false
                ),
                AmbientBlob(
                    color: GlassArena.amber400,
                    size: 340,
                    anchor: .topTrailing(x: -110, y: 330),
                    blur: 78,
                    opacity: 0.21,
                    period: 19,
                    mirrored: true
                ),
                AmbientBlob(
                    color: GlassArena.violet500,
                    size: 300,
                    anchor: .bottomLeading(x: -70, y: -120),
                    blur: 78,
                    opacity: 0.19,
                    period: 17,
                    mirrored: false
                ),
            ]
        }
    }

    fileprivate var substrate: SubstrateStyle {
        switch self {
        case .today:
            SubstrateStyle(
                behindColor: GlassArena.violet500.opacity(0.10),
                frontColor: GlassArena.teal700.opacity(0.14),
                behindStroke: nil,
                frontStroke: nil,
                behind: SubstrateCurve.todayBehind,
                front: SubstrateCurve.todayFront,
                frontIsYours: true
            )
        case .duels:
            SubstrateStyle(
                behindColor: GlassArena.amber400.opacity(0.10),
                frontColor: GlassArena.teal700.opacity(0.13),
                behindStroke: nil,
                frontStroke: nil,
                behind: SubstrateCurve.duelsBehind,
                front: SubstrateCurve.duelsFront,
                frontIsYours: true
            )
        case .duelDetail:
            SubstrateStyle(
                behindColor: GlassArena.violet500.opacity(0.13),
                frontColor: GlassArena.teal700.opacity(0.15),
                behindStroke: GlassArena.violet600.opacity(0.30),
                frontStroke: GlassArena.teal800.opacity(0.34),
                behind: SubstrateCurve.detailBehind,
                front: SubstrateCurve.detailFront,
                frontIsYours: true
            )
        case .result:
            SubstrateStyle(
                behindColor: GlassArena.teal700.opacity(0.13),
                frontColor: GlassArena.violet500.opacity(0.10),
                behindStroke: nil,
                frontStroke: nil,
                behind: SubstrateCurve.resultBehind,
                front: SubstrateCurve.resultFront,
                frontIsYours: false
            )
        }
    }
}

private struct GlassArenaBackgroundModifier: ViewModifier {
    let screen: GlassArenaScreen
    /// Your share and your opponent's share of combined progress, lifting the
    /// two curves. Nil until progress is known, which parks both at the drawn
    /// position.
    let lift: (yours: CGFloat, theirs: CGFloat)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                screen.gradient

                ZStack {
                    ForEach(screen.blobs) { blob in
                        AmbientBlobView(blob: blob)
                    }
                }

                substrateLayer
            }
            .clipped()
            .ignoresSafeArea()
        }
    }

    private var yourLift: CGFloat { lift?.yours ?? 0 }
    private var theirLift: CGFloat { lift?.theirs ?? 0 }

    @ViewBuilder
    private var substrateLayer: some View {
        let style = screen.substrate
        let behindLift = style.frontIsYours ? theirLift : yourLift
        let frontLift = style.frontIsYours ? yourLift : theirLift

        ZStack {
            style.behind(behindLift).fill(style.behindColor)
            if let stroke = style.behindStroke {
                style.behind(behindLift)
                    .stroke(stroke, lineWidth: 2)
            }
            style.front(frontLift).fill(style.frontColor)
            if let stroke = style.frontStroke {
                style.front(frontLift)
                    .stroke(stroke, lineWidth: 2)
            }
        }
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: yourLift
        )
        .animation(
            reduceMotion ? nil : .easeInOut(duration: 0.4),
            value: theirLift
        )
    }
}

extension View {
    /// Places the warm gradient, drifting ambient blobs and data substrate
    /// behind the view.
    ///
    /// - Parameter lift: the two athletes' shares of combined progress, which
    ///   raise their curves. Omit when progress is unknown.
    func glassArenaBackground(
        _ screen: GlassArenaScreen,
        lift: (yours: CGFloat, theirs: CGFloat)? = nil
    ) -> some View {
        modifier(
            GlassArenaBackgroundModifier(screen: screen, lift: lift)
        )
    }
}
