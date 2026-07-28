import SwiftUI

// The "Glass Arena" design system: translucent panes over warm colour, with
// teal standing for you and violet for whoever you are up against.
//
// Sizes here are the literal point values from the design handoff, which was
// drawn at 393 x 852 (iPhone 15/16 logical width). `GlassArenaMetrics` scales
// the two display sizes the handoff calls out for narrower devices.

extension Color {
    init(glassArenaHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

enum GlassArena {
    // MARK: Ink and neutrals

    static let ink = Color(glassArenaHex: 0x10201F)
    static let inkSecondary = Color(glassArenaHex: 0x3C4B49)
    static let inkTertiary = Color(glassArenaHex: 0x5F726F)
    static let muted = Color(glassArenaHex: 0x667876)
    static let mutedLight = Color(glassArenaHex: 0x7B8D8A)
    static let mutedLighter = Color(glassArenaHex: 0x8794A0)
    static let mutedGlyph = Color(glassArenaHex: 0x8B9A98)
    static let mutedLightest = Color(glassArenaHex: 0x9EAEAB)
    static let hairline = Color(glassArenaHex: 0xB9C5C3)
    static let desaturatedScore = Color(glassArenaHex: 0x95A2A0)

    // MARK: Teal — you

    static let teal400 = Color(glassArenaHex: 0x3BE0C4)
    static let teal500 = Color(glassArenaHex: 0x25D3B5)
    static let teal700 = Color(glassArenaHex: 0x1AB89E)
    static let teal800 = Color(glassArenaHex: 0x0E9C86)
    static let teal850 = Color(glassArenaHex: 0x0B8B77)
    static let teal900 = Color(glassArenaHex: 0x0B7A69)
    static let teal950 = Color(glassArenaHex: 0x0B5F52)
    static let tealInk = Color(glassArenaHex: 0x04302A)

    // MARK: Violet — your opponent

    static let violet400 = Color(glassArenaHex: 0x9E80FF)
    static let violet450 = Color(glassArenaHex: 0x8B6BFF)
    static let violet500 = Color(glassArenaHex: 0x7A5AF8)
    static let violet600 = Color(glassArenaHex: 0x6B49F0)
    static let violet700 = Color(glassArenaHex: 0x5B3AE0)
    static let violet800 = Color(glassArenaHex: 0x4B33B8)
    static let violet850 = Color(glassArenaHex: 0x5F4A9E)

    // MARK: Amber — the stake

    static let amber400 = Color(glassArenaHex: 0xF0A333)
    static let amber600 = Color(glassArenaHex: 0xE08C0B)
    static let amber700 = Color(glassArenaHex: 0xC87A0C)
    static let amber800 = Color(glassArenaHex: 0x8A5A05)
    static let amberInk = Color(glassArenaHex: 0x3D2604)

    static let destructive = Color(glassArenaHex: 0xB05656)
    static let darkButtonTop = Color(glassArenaHex: 0x26312F)
    static let darkButtonBottom = Color(glassArenaHex: 0x0F1715)

    /// Tint used for the knot glyph and other "which way is the rope moving"
    /// accents.
    static let knotGlyph = amber600

    // MARK: Gradients

    static let tealButton = LinearGradient(
        colors: [teal500, teal800],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let darkButton = LinearGradient(
        colors: [darkButtonTop, darkButtonBottom],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let yourCord = LinearGradient(
        colors: [teal400, teal850],
        startPoint: .top,
        endPoint: .bottom
    )

    static let theirCord = LinearGradient(
        colors: [violet400, violet700],
        startPoint: .top,
        endPoint: .bottom
    )

    static let knot = LinearGradient(
        colors: [.white, Color(glassArenaHex: 0xEDF2F1)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Screen backgrounds

enum GlassArenaScreen {
    case today
    case duels
    case duelDetail
    case result

    /// A 170° gradient across three warm-neutral stops — near-vertical with a
    /// slight rightward lean, matching the handoff's `linear-gradient(170deg, …)`.
    var gradient: LinearGradient {
        LinearGradient(
            stops: stops,
            startPoint: UnitPoint(x: 0.42, y: 0),
            endPoint: UnitPoint(x: 0.58, y: 1)
        )
    }

    private var stops: [Gradient.Stop] {
        switch self {
        case .today, .duels:
            [
                .init(color: Color(glassArenaHex: 0xF6F2EC), location: 0),
                .init(color: Color(glassArenaHex: 0xEDF3F1), location: 0.46),
                .init(color: Color(glassArenaHex: 0xF2ECF6), location: 1),
            ]
        case .duelDetail:
            [
                .init(color: Color(glassArenaHex: 0xF1EDE7), location: 0),
                .init(color: Color(glassArenaHex: 0xE9F1EF), location: 0.44),
                .init(color: Color(glassArenaHex: 0xEFEAF6), location: 1),
            ]
        case .result:
            [
                .init(color: Color(glassArenaHex: 0xF1F7F2), location: 0),
                .init(color: Color(glassArenaHex: 0xE9F4EF), location: 0.44),
                .init(color: Color(glassArenaHex: 0xF5F0E6), location: 1),
            ]
        }
    }
}

// MARK: - Typography

enum GlassArenaFont {
    /// Display face — screen titles, numbers, scores, button labels, money.
    /// The handoff's Bricolage Grotesque is not bundled, so this uses its
    /// documented substitute: the rounded system design at heavy weights.
    static func display(
        _ size: CGFloat,
        _ weight: Font.Weight = .heavy
    ) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Text face — body, labels, captions, list rows.
    static func text(
        _ size: CGFloat,
        _ weight: Font.Weight = .regular
    ) -> Font {
        .system(size: size, weight: weight)
    }

    /// Multi-line display headings sit at roughly 1.08 line height in the
    /// design, tighter than the system default. Stop there — going lower clips
    /// descenders on the heavy weights.
    static func displayLineSpacing(_ size: CGFloat) -> CGFloat {
        -size * 0.12
    }
}

/// The two display sizes the handoff asks to reduce on narrower devices before
/// touching padding, plus the iPad content cap.
enum GlassArenaMetrics {
    static let designWidth: CGFloat = 393
    static let contentCap: CGFloat = 440

    static func heroScore(width: CGFloat) -> CGFloat {
        width < designWidth ? 38 : 44
    }

    static func resultHeadline(width: CGFloat) -> CGFloat {
        width < designWidth ? 54 : 66
    }
}

// MARK: - Glass

/// The four glass levels from the handoff. Each maps to a real system material
/// rather than a numeric blur, then adds the intended bright top edge, soft
/// bottom edge, hairline outline and drop shadow.
enum GlassTier {
    /// Rope card, result card — brightest and thickest.
    case hero
    /// Stat cards, timeline, invite cards.
    case standard
    /// Completed and past rows — reads as inactive.
    case recessed
    /// The tab bar.
    case chrome

    fileprivate var material: Material {
        switch self {
        case .hero, .chrome: .thinMaterial
        case .standard, .recessed: .ultraThinMaterial
        }
    }

    /// White wash over the material, brighter at the top-left. Kept low enough
    /// that the substrate curves still read through the lower half of a pane —
    /// flattening these to opaque white kills the whole effect.
    fileprivate var tint: (top: Double, bottom: Double) {
        switch self {
        case .hero: (0.66, 0.24)
        case .standard: (0.54, 0.18)
        case .recessed: (0.42, 0.13)
        case .chrome: (0.60, 0.28)
        }
    }

    /// The hairline outline, bright along the top edge and softer below.
    fileprivate var border: (top: Double, bottom: Double) {
        switch self {
        case .hero: (1.0, 0.40)
        case .standard: (0.96, 0.34)
        case .recessed: (0.80, 0.28)
        case .chrome: (0.98, 0.52)
        }
    }

    fileprivate var borderWidth: CGFloat {
        self == .hero ? 1.5 : 1
    }

    fileprivate var shadows: [GlassShadow] {
        switch self {
        case .hero:
            [GlassShadow(color: .init(glassArenaHex: 0x142834, opacity: 0.34), radius: 20, y: 16)]
        case .standard:
            [GlassShadow(color: .init(glassArenaHex: 0x142834, opacity: 0.22), radius: 12, y: 9)]
        case .recessed:
            []
        case .chrome:
            [
                GlassShadow(color: .init(glassArenaHex: 0x142834, opacity: 0.16), radius: 11, y: -2),
                GlassShadow(color: .init(glassArenaHex: 0x142834, opacity: 0.30), radius: 13, y: 10),
            ]
        }
    }

    /// Hero panes add an outer contact line so they read as sitting *on* the
    /// background rather than being cut out of it.
    fileprivate var hasContactLine: Bool {
        self == .hero || self == .chrome
    }
}

fileprivate struct GlassShadow {
    let color: Color
    let radius: CGFloat
    var x: CGFloat = 0
    var y: CGFloat
}

/// A rounded rectangle that can drop its bottom edge, so the last card in a
/// scrolling list can slide under the tab bar with only its top corners rounded.
struct GlassPaneShape: InsettableShape {
    var cornerRadius: CGFloat
    var topCornersOnly: Bool
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let radius = max(0, cornerRadius - insetAmount)
        if topCornersOnly {
            return Path(
                UIBezierPath(
                    roundedRect: bounds,
                    byRoundingCorners: [.topLeft, .topRight],
                    cornerRadii: CGSize(width: radius, height: radius)
                ).cgPath
            )
        }
        return Path(
            roundedRect: bounds,
            cornerRadius: radius,
            style: .continuous
        )
    }

    func inset(by amount: CGFloat) -> GlassPaneShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}

/// The pane's outline. A pane that slides under the tab bar leaves its bottom
/// edge open, matching the design's `border-bottom: none`, so the card reads as
/// continuing beneath the chrome rather than stopping there.
private struct GlassPaneBorder: Shape {
    let cornerRadius: CGFloat
    let topCornersOnly: Bool
    let lineWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let bounds = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        let radius = max(0, cornerRadius - lineWidth / 2)
        guard topCornersOnly else {
            return Path(
                roundedRect: bounds,
                cornerRadius: radius,
                style: .continuous
            )
        }
        let corner = min(radius, min(bounds.width, bounds.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: bounds.minX, y: bounds.maxY))
        path.addLine(to: CGPoint(x: bounds.minX, y: bounds.minY + corner))
        path.addQuadCurve(
            to: CGPoint(x: bounds.minX + corner, y: bounds.minY),
            control: CGPoint(x: bounds.minX, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: bounds.maxX - corner, y: bounds.minY))
        path.addQuadCurve(
            to: CGPoint(x: bounds.maxX, y: bounds.minY + corner),
            control: CGPoint(x: bounds.maxX, y: bounds.minY)
        )
        path.addLine(to: CGPoint(x: bounds.maxX, y: bounds.maxY))
        return path
    }
}

private struct GlassPaneModifier: ViewModifier {
    let tier: GlassTier
    let cornerRadius: CGFloat
    let topCornersOnly: Bool
    let borderOverride: Color?

    private var shape: GlassPaneShape {
        GlassPaneShape(
            cornerRadius: cornerRadius,
            topCornersOnly: topCornersOnly
        )
    }

    func body(content: Content) -> some View {
        content
            .background {
                shape
                    .fill(tier.material)
                    .overlay {
                        shape.fill(
                            LinearGradient(
                                colors: [
                                    .white.opacity(tier.tint.top),
                                    .white.opacity(tier.tint.bottom),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    }
                    .compositingGroup()
                    .glassArenaShadows(tier.shadows)
            }
            .overlay {
                border(lineWidth: tier.borderWidth)
                    .stroke(borderStyle, lineWidth: tier.borderWidth)
            }
            .overlay {
                if tier.hasContactLine {
                    border(lineWidth: 0.5)
                        .stroke(
                            Color(glassArenaHex: 0x142834, opacity: 0.05),
                            lineWidth: 0.5
                        )
                }
            }
    }

    private func border(lineWidth: CGFloat) -> GlassPaneBorder {
        GlassPaneBorder(
            cornerRadius: cornerRadius,
            topCornersOnly: topCornersOnly,
            lineWidth: lineWidth
        )
    }

    private var borderStyle: AnyShapeStyle {
        if let borderOverride {
            return AnyShapeStyle(borderOverride)
        }
        return AnyShapeStyle(
            LinearGradient(
                colors: [
                    .white.opacity(tier.border.top),
                    .white.opacity(tier.border.bottom),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

private extension View {
    @ViewBuilder
    func glassArenaShadows(_ shadows: [GlassShadow]) -> some View {
        switch shadows.count {
        case 0:
            self
        case 1:
            shadow(
                color: shadows[0].color,
                radius: shadows[0].radius,
                x: shadows[0].x,
                y: shadows[0].y
            )
        default:
            shadow(
                color: shadows[0].color,
                radius: shadows[0].radius,
                x: shadows[0].x,
                y: shadows[0].y
            )
            .shadow(
                color: shadows[1].color,
                radius: shadows[1].radius,
                x: shadows[1].x,
                y: shadows[1].y
            )
        }
    }
}

extension View {
    /// Wraps the view in a glass pane at the given tier.
    ///
    /// - Parameters:
    ///   - borderColor: replaces the white hairline — used by invite cards,
    ///     which carry an amber outline so "waiting on you" reads at a glance.
    ///   - topCornersOnly: for the final card in a list, which slides under the
    ///     tab bar so real content passes beneath the translucent chrome.
    func glassPane(
        _ tier: GlassTier,
        cornerRadius: CGFloat,
        topCornersOnly: Bool = false,
        borderColor: Color? = nil
    ) -> some View {
        modifier(
            GlassPaneModifier(
                tier: tier,
                cornerRadius: cornerRadius,
                topCornersOnly: topCornersOnly,
                borderOverride: borderColor
            )
        )
    }
}

// MARK: - Pressed state

/// Cards scale to 0.985 with a light haptic; the handoff asks for this on every
/// tappable pane.
struct GlassCardButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.985
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.14),
                value: configuration.isPressed
            )
            .onChange(of: configuration.isPressed) { _, isPressed in
                if isPressed { GlassArenaHaptics.light() }
            }
    }
}

enum GlassArenaHaptics {
    static func light() {
        #if canImport(UIKit) && !targetEnvironment(macCatalyst)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }
}

// MARK: - Buttons

/// Teal gradient, ink-on-teal label — "Take it", "Run it back", "Let's go".
struct GlassPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = 52
    var cornerRadius: CGFloat = 20
    var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GlassArenaFont.display(fontSize, .bold))
            .foregroundStyle(
                GlassArena.tealInk.opacity(isEnabled ? 1 : 0.45)
            )
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(GlassArena.tealButton)
                .opacity(isEnabled ? 1 : 0.45)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(.white.opacity(0.45), lineWidth: 1)
                    .mask(
                        LinearGradient(
                            colors: [.white, .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                }
                .shadow(
                    color: GlassArena.teal800.opacity(isEnabled ? 0.55 : 0),
                    radius: 14,
                    y: 12
                )
            }
            .brightness(configuration.isPressed ? -0.06 : 0)
    }
}

/// The dark gradient pair — "Talk trash" and "Start a duel".
struct GlassDarkButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var height: CGFloat = 56
    var cornerRadius: CGFloat = 20
    var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GlassArenaFont.display(fontSize, .bold))
            .foregroundStyle(.white.opacity(isEnabled ? 1 : 0.5))
            .frame(height: height)
            .background {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(GlassArena.darkButton)
                .overlay {
                    RoundedRectangle(
                        cornerRadius: cornerRadius,
                        style: .continuous
                    )
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                }
                .shadow(
                    color: Color(glassArenaHex: 0x101816, opacity: 0.45),
                    radius: 13,
                    y: 11
                )
            }
            .brightness(configuration.isPressed ? -0.06 : 0)
    }
}

/// Glass-backed secondary — "Share the receipt", the share square.
struct GlassSecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = 52
    var cornerRadius: CGFloat = 20

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GlassArenaFont.text(16, .semibold))
            .foregroundStyle(GlassArena.inkSecondary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .glassPane(.standard, cornerRadius: cornerRadius)
            .brightness(configuration.isPressed ? -0.04 : 0)
    }
}

/// The low-contrast decline — "Nope".
struct GlassQuietButtonStyle: ButtonStyle {
    var height: CGFloat = 44
    var cornerRadius: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(GlassArenaFont.text(15, .semibold))
            .foregroundStyle(GlassArena.inkTertiary)
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(
                    cornerRadius: cornerRadius,
                    style: .continuous
                )
                .fill(GlassArena.ink.opacity(configuration.isPressed ? 0.10 : 0.055))
            }
    }
}
