import SwiftUI
import UIKit

// Floodlight 9.3, adopted September 27, 2026: light is Aero Toned, dark is
// Floodlit at Toned depth, both painted from one token set. The values come
// from `.lavish/floodlight-refinement-2026-09-27/round-9-3/` (its `--gt-*`
// CSS and DESIGN.md token table). FloodlightThemeTests reads that CSS back, so
// a value here can't drift from the adopted page.

/// A color as the adopted CSS writes it: sRGB channels (0–255) and an alpha.
struct FloodlightRGBA: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static func hex(_ value: UInt32, alpha: Double = 1) -> Self {
        .init(red: Double((value >> 16) & 255), green: Double((value >> 8) & 255), blue: Double(value & 255), alpha: alpha)
    }
    static func rgba(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) -> Self {
        .init(red: red, green: green, blue: blue, alpha: alpha)
    }
    static let white = hex(0xFFFFFF)
    static let black = hex(0x000000)

    var color: Color { Color(.sRGB, red: red / 255, green: green / 255, blue: blue / 255, opacity: alpha) }
    var uiColor: UIColor { UIColor(red: red / 255, green: green / 255, blue: blue / 255, alpha: alpha) }
    func opacity(_ value: Double) -> Self { .init(red: red, green: green, blue: blue, alpha: alpha * value) }

    /// The review page's `mix()`: a straight blend of the sRGB channels.
    func mixed(with other: Self, _ amount: Double) -> Self {
        .init(red: red + (other.red - red) * amount, green: green + (other.green - green) * amount,
              blue: blue + (other.blue - blue) * amount, alpha: alpha + (other.alpha - alpha) * amount)
    }

    /// CSS `color-mix(in oklab, self, other amount)`, used for initials on people.
    func mixedInOKLab(with other: Self, _ amount: Double) -> Self {
        let a = oklab, b = other.oklab
        return Self.fromOKLab((a.0 + (b.0 - a.0) * amount, a.1 + (b.1 - a.1) * amount, a.2 + (b.2 - a.2) * amount),
                              alpha: alpha + (other.alpha - alpha) * amount)
    }

    private static func linear(_ channel: Double) -> Double {
        let c = channel / 255
        return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    private static func encoded(_ linear: Double) -> Double {
        let c = linear <= 0.0031308 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
        return min(255, max(0, c * 255))
    }
    private var oklab: (Double, Double, Double) {
        let r = Self.linear(red), g = Self.linear(green), b = Self.linear(blue)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }
    private static func fromOKLab(_ lab: (Double, Double, Double), alpha: Double) -> Self {
        let l = pow(lab.0 + 0.3963377774 * lab.1 + 0.2158037573 * lab.2, 3)
        let m = pow(lab.0 - 0.1055613458 * lab.1 - 0.0638541728 * lab.2, 3)
        let s = pow(lab.0 - 0.0894841775 * lab.1 - 1.2914855480 * lab.2, 3)
        return .init(red: encoded(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                     green: encoded(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                     blue: encoded(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s), alpha: alpha)
    }
}

/// One `--gt-*` color token. The raw value is the CSS name; the case name is the
/// SwiftUI asset name from the round's token table, in lower camel case.
enum FloodlightToken: String, CaseIterable, Sendable {
    // Surfaces
    case ground
    case backdrop1 = "backdrop-1", backdrop2 = "backdrop-2", backdrop3 = "backdrop-3", backdrop4 = "backdrop-4"
    // Hero card: the one lit surface per screen
    case heroTop = "hero-top", heroBottom = "hero-bottom", heroEdge = "hero-edge"
    case heroHighlight = "hero-highlight", heroGlow = "hero-glow"
    // Quiet card: everything else
    case card, cardEdge = "card-edge", cardHighlight = "card-highlight", well, wellEdge = "well-edge"
    // Chrome
    case bar, barEdge = "bar-edge", sheet, scrim, statusScrolled = "status-scrolled"
    // Text
    case ink, muted, heroMuted = "hero-muted", faint, line
    // Accent
    case accent, brand
    // Button
    case button, buttonInk = "button-ink"
    // Dial
    case plateTop = "plate-top", plateMid = "plate-mid", plateBottom = "plate-bottom"
    case plateRimTop = "plate-rim-top", plateRimBottom = "plate-rim-bottom", plateLight = "plate-light"
    case track, trackEdge = "track-edge", tick, tickMajor = "tick-major"
    case arcHighlight = "arc-highlight", arcTail = "arc-tail"
    // Pot
    case potTop = "pot-top", potMid = "pot-mid", potBottom = "pot-bottom"
    case potRimTop = "pot-rim-top", potRimBottom = "pot-rim-bottom", potShine = "pot-shine"
    case potLabel = "pot-label", potInk = "pot-ink", potBarTop = "pot-bar-top", potBarBottom = "pot-bar-bottom"
    // People, in fixed roster slots. Slot 0 is always the person using the app.
    case memberYou = "member-you", memberSam = "member-sam", memberJordan = "member-jordan"
    case memberPriya = "member-priya", memberMaya = "member-maya", memberTheo = "member-theo"
    // Each person's stroke on the dial (9.3 deepens light arcs to 3:1 on their tracks)
    case arcYou = "arc-you", arcSam = "arc-sam", arcJordan = "arc-jordan"
    case arcPriya = "arc-priya", arcMaya = "arc-maya", arcTheo = "arc-theo"
    // Added after 9.3 on the same look: 9.4's "Couldn't confirm" and round 10's text link.
    case unconfirmed, unconfirmedInk = "unconfirmed-ink", unconfirmedWash = "unconfirmed-wash", link

    /// Tokens that round 9.3's adopted table defines; the rest come from later rounds.
    var adoptedIn93: Bool { ![.unconfirmed, .unconfirmedInk, .unconfirmedWash, .link].contains(self) }

    var values: (light: FloodlightRGBA, dark: FloodlightRGBA) {
        switch self {
        case .ground: (.hex(0xF6F8FB), .hex(0x0E161A))
        case .backdrop1: (.hex(0x6CC2F4), .hex(0x2A3E48))
        case .backdrop2: (.hex(0xA6DDFA), .hex(0x1E2E36))
        case .backdrop3: (.hex(0xD6EFFC), .hex(0x162329))
        case .backdrop4: (.hex(0xEBF4FA), .hex(0x111B20))
        case .heroTop: (.rgba(255, 255, 255, 0.86), .hex(0x22343D))
        case .heroBottom: (.rgba(255, 255, 255, 0.52), .hex(0x18252B))
        case .heroEdge: (.rgba(255, 255, 255, 0.96), .rgba(255, 255, 255, 0.07))
        case .heroHighlight: (.hex(0xFFFFFF), .rgba(255, 255, 255, 0.16))
        case .heroGlow: (.rgba(255, 255, 255, 0), .rgba(150, 214, 245, 0.12))
        case .card: (.hex(0xFFFFFF), .hex(0x172227))
        case .cardEdge: (.rgba(10, 45, 68, 0.07), .rgba(255, 255, 255, 0.05))
        case .cardHighlight: (.rgba(255, 255, 255, 0), .rgba(255, 255, 255, 0.07))
        case .well: (.hex(0xEEF3F7), .hex(0x213038))
        case .wellEdge: (.rgba(10, 45, 68, 0.09), .rgba(255, 255, 255, 0.06))
        case .bar: (.hex(0xFFFFFF), .hex(0x121B20))
        case .barEdge: (.rgba(10, 45, 68, 0.08), .rgba(255, 255, 255, 0.07))
        case .sheet: (.hex(0xFFFFFF), .hex(0x162026))
        case .scrim: (.rgba(8, 48, 78, 0.3), .rgba(3, 7, 9, 0.62))
        case .statusScrolled: (.rgba(246, 248, 251, 0.94), .rgba(14, 22, 26, 0.94))
        case .ink: (.hex(0x0A2D44), .hex(0xEEF4F7))
        case .muted: (.hex(0x3E6278), .hex(0x9FB2BB))
        case .heroMuted: (.hex(0x365A70), .hex(0xD2DDE2))
        case .faint: (.hex(0x5A7B8F), .hex(0x8FA3AD))
        case .line: (.rgba(10, 45, 68, 0.12), .rgba(255, 255, 255, 0.08))
        case .accent: (.hex(0x0E86E0), .hex(0xBFEBFF))
        case .brand: (.hex(0xE2461E), .hex(0xFF6B45))
        case .button: (.hex(0x0F63B6), .hex(0x1D6CBE))
        case .buttonInk: (.hex(0xFFFFFF), .hex(0xFFFFFF))
        case .plateTop: (.rgba(255, 255, 255, 0.96), .hex(0x2A3E48))
        case .plateMid: (.rgba(238, 248, 255, 0.86), .hex(0x17242B))
        case .plateBottom: (.rgba(213, 237, 251, 0.84), .hex(0x0C1418))
        case .plateRimTop: (.hex(0xFFFFFF), .rgba(200, 236, 255, 0.4))
        case .plateRimBottom: (.hex(0xA9D6F0), .rgba(200, 236, 255, 0))
        case .plateLight: (.rgba(255, 255, 255, 0.4), .rgba(191, 235, 255, 0.07))
        case .track: (.hex(0xFFFFFF), .hex(0x050A0D))
        case .trackEdge: (.rgba(10, 70, 112, 0.2), .rgba(255, 255, 255, 0.055))
        case .tick: (.rgba(10, 45, 68, 0.3), .rgba(205, 230, 242, 0.4))
        case .tickMajor: (.rgba(10, 45, 68, 0.78), .rgba(236, 248, 255, 0.92))
        case .arcHighlight: (.rgba(255, 255, 255, 0.26), .rgba(255, 255, 255, 0.12))
        case .arcTail: (.hex(0xFFFFFF), .hex(0x0B1418))
        case .potTop: (.hex(0x1770C4), .hex(0x215D99))
        case .potMid: (.hex(0x1569BD), .hex(0x164477))
        case .potBottom: (.hex(0x0A4F99), .hex(0x072549))
        case .potRimTop: (.hex(0xFFFFFF), .hex(0xA9C0DB))
        case .potRimBottom: (.hex(0xC7E4F5), .hex(0x0D1723))
        case .potShine: (.rgba(255, 255, 255, 0.3), .rgba(255, 255, 255, 0.24))
        case .potLabel: (.hex(0xFFFFFF), .rgba(220, 233, 249, 0.92))
        case .potInk: (.hex(0xFFFFFF), .hex(0xFFFFFF))
        case .potBarTop: (.hex(0x1A79CC), .hex(0x1E5790))
        case .potBarBottom: (.hex(0x0A55A6), .hex(0x08284F))
        case .memberYou: (.hex(0xFF6428), .hex(0xFF8B5E))
        case .memberSam: (.hex(0x1C98F4), .hex(0x55B2F7))
        case .memberJordan: (.hex(0x27B155), .hex(0x5DC580))
        case .memberPriya: (.hex(0x9357F6), .hex(0xAE81F8))
        case .memberMaya: (.hex(0xF2A00C), .hex(0xF5B849))
        case .memberTheo: (.hex(0xF24A93), .hex(0xF577AE))
        case .arcYou: (.hex(0xD94000), .hex(0xFF8B5E))
        case .arcSam: (.hex(0x0074CD), .hex(0x55B2F7))
        case .arcJordan: (.hex(0x008429), .hex(0x5DC580))
        case .arcPriya: (.hex(0x894CEA), .hex(0xAE81F8))
        case .arcMaya: (.hex(0xA95C00), .hex(0xF5B849))
        case .arcTheo: (.hex(0xDA3180), .hex(0xF577AE))
        case .unconfirmed: (.hex(0x0E6FC0), .hex(0x8CCBF2))
        case .unconfirmedInk: (.hex(0xFFFFFF), .hex(0x0B1A22))
        case .unconfirmedWash: (.hex(0xEEF6FD), .hex(0x15262F))
        case .link: (.hex(0x0F63B6), .hex(0xBFEBFF))
        }
    }

    func rgba(_ scheme: ColorScheme) -> FloodlightRGBA { scheme == .dark ? values.dark : values.light }

    /// Resolves with the view's appearance, like an asset color with Any and Dark values.
    var color: Color { Self.colors[self]! }
    private static let colors: [FloodlightToken: Color] = Dictionary(uniqueKeysWithValues: allCases.map { token in
        let (light, dark) = token.values
        let resolved = UIColor { $0.userInterfaceStyle == .dark ? dark.uiColor : light.uiColor }
        return (token, Color(uiColor: resolved))
    })

    static let memberSlots: [FloodlightToken] = [.memberYou, .memberSam, .memberJordan, .memberPriya, .memberMaya, .memberTheo]
    static let arcSlots: [FloodlightToken] = [.arcYou, .arcSam, .arcJordan, .arcPriya, .arcMaya, .arcTheo]
    static func member(_ slot: Int) -> FloodlightToken { memberSlots[((slot % 6) + 6) % 6] }
    static func arc(_ slot: Int) -> FloodlightToken { arcSlots[((slot % 6) + 6) % 6] }
}

/// The number rows of the token table.
enum FloodlightNumber: String, CaseIterable, Sendable {
    case backdropArt = "backdrop-art", arcBloom = "arc-bloom", arcTailMix = "arc-tail-mix", arcDim = "arc-dim"
    var values: (light: Double, dark: Double) {
        switch self {
        case .backdropArt: (0.32, 0.3)
        case .arcBloom: (0.2, 0.34)
        case .arcTailMix: (0.16, 0.3)
        case .arcDim: (0.88, 0.88)
        }
    }
    func value(_ scheme: ColorScheme) -> Double { scheme == .dark ? values.dark : values.light }
}

/// Paint the adopted page takes from its material layer (Aero at Toned depth in
/// light, Floodlit at Toned depth in dark) rather than from the token table:
/// grooves, coins, drop shadows, glass and the neutral outcome figures.
enum FloodlightMaterial {
    typealias Pair = (light: FloodlightRGBA, dark: FloodlightRGBA)
    static let groove: Pair = (.rgba(10, 60, 100, 0.13), .hex(0x060C0F))
    static let grooveShade: Pair = (.rgba(10, 60, 100, 0.3), .rgba(0, 0, 0, 0.8))
    static let barDim: Pair = (.hex(0xFFFFFF), .hex(0x0B1418))
    static let coin: Pair = (.hex(0xF1F8FC), .hex(0xB9CBD3))
    static let coinHighlight: Pair = (.hex(0xFFFFFF), .hex(0xFFFFFF))
    static let coinLow: Pair = (.hex(0xCFE5F3), .hex(0x6D838D))
    static let coinRing: Pair = (.hex(0xFFFFFF), .rgba(255, 255, 255, 0.45))
    static let coinInk: Pair = (.hex(0x0A2D44), .hex(0x0B1519))
    static let noFill: Pair = (.hex(0x6E93AA), .hex(0x58707B))
    static let pipPast: Pair = (.hex(0x7FB3D3), .hex(0x5E7480))
    static let drop: Pair = (.rgba(16, 84, 136, 0.5), .rgba(0, 0, 0, 0.75))
    static let tokenDrop: Pair = (.rgba(12, 70, 120, 0.24), .rgba(0, 0, 0, 0.45))
    static let plateDrop: Pair = (.rgba(14, 88, 142, 0.2), .rgba(0, 0, 0, 0.62))
    static let hubDrop: Pair = (.rgba(10, 70, 130, 0.3), .rgba(0, 0, 0, 0.7))
    static let glass: Pair = (.rgba(255, 255, 255, 0.58), .rgba(255, 255, 255, 0.06))
    static let glassEdge: Pair = (.rgba(255, 255, 255, 0.96), .rgba(255, 255, 255, 0.12))
    /// Initials on a dark-mode person: one dark ink for every member color.
    static let tokenInkDark = FloodlightRGBA.hex(0x0A1317)
    static let neutral: (light: [FloodlightRGBA], dark: [FloodlightRGBA]) = ([.hex(0xB9D6E8), .hex(0x90BCD7)], [.hex(0xA2B5BE), .hex(0x7D939D)])
    static let neutralDim: (light: [FloodlightRGBA], dark: [FloodlightRGBA]) = ([.hex(0xB9C6CE), .hex(0x9DADB7)], [.hex(0x72858E), .hex(0x56676F)])

    static func value(_ pair: Pair, _ scheme: ColorScheme) -> FloodlightRGBA { scheme == .dark ? pair.dark : pair.light }
    static func color(_ pair: Pair) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? pair.dark.uiColor : pair.light.uiColor })
    }
    /// Initials on a person's color: the color darkened in light, dark ink in
    /// dark. The page darkens light initials 64%, which leaves Priya's purple at
    /// 4.18:1; 78% keeps every color at 4.5:1 or better for small text.
    static func initialsInk(_ member: FloodlightRGBA, _ scheme: ColorScheme) -> FloodlightRGBA {
        scheme == .dark ? tokenInkDark : member.mixedInOKLab(with: .black, 0.78)
    }
}

/// Short names for the tokens views use most.
enum Floodlight {
    static let ground = FloodlightToken.ground.color
    static let card = FloodlightToken.card.color
    static let cardEdge = FloodlightToken.cardEdge.color
    static let well = FloodlightToken.well.color
    static let wellEdge = FloodlightToken.wellEdge.color
    static let bar = FloodlightToken.bar.color
    static let barEdge = FloodlightToken.barEdge.color
    static let sheet = FloodlightToken.sheet.color
    static let ink = FloodlightToken.ink.color
    static let muted = FloodlightToken.muted.color
    static let heroMuted = FloodlightToken.heroMuted.color
    static let faint = FloodlightToken.faint.color
    static let line = FloodlightToken.line.color
    static let accent = FloodlightToken.accent.color
    static let brand = FloodlightToken.brand.color
    static let button = FloodlightToken.button.color
    static let buttonInk = FloodlightToken.buttonInk.color
    static let link = FloodlightToken.link.color
    static let unconfirmed = FloodlightToken.unconfirmed.color
    static let unconfirmedWash = FloodlightToken.unconfirmedWash.color
    static let statusScrolled = FloodlightToken.statusScrolled.color
    static let groove = FloodlightMaterial.color(FloodlightMaterial.groove)
    static let glass = FloodlightMaterial.color(FloodlightMaterial.glass)
    static let glassEdge = FloodlightMaterial.color(FloodlightMaterial.glassEdge)
    static func member(_ slot: Int) -> Color { FloodlightToken.member(slot).color }
}

// MARK: - Surfaces

/// The one lit surface per screen: frosted white on the sky in light, a
/// top-highlight slate card in dark. No backdrop blur in dark.
struct FloodlightHeroSurface: ViewModifier {
    var radius: CGFloat = 22
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    if scheme == .light && !reduceTransparency { shape.fill(.ultraThinMaterial) }
                    if scheme == .light && reduceTransparency { shape.fill(FloodlightToken.card.color) }
                    shape.fill(LinearGradient(colors: [FloodlightToken.heroTop.color, FloodlightToken.heroBottom.color],
                                              startPoint: .top, endPoint: .bottom))
                    if scheme == .dark {
                        shape.fill(RadialGradient(colors: [FloodlightToken.heroGlow.color, .clear],
                                                  center: UnitPoint(x: 0.5, y: -0.1), startRadius: 0, endRadius: 260))
                    }
                }
                .shadow(color: scheme == .dark ? .black.opacity(0.42) : Color(red: 18 / 255, green: 92 / 255, blue: 146 / 255).opacity(0.22),
                        radius: 12, x: 0, y: 10)
            }
            .overlay {
                shape.strokeBorder(FloodlightToken.heroEdge.color, lineWidth: 1)
                FloodlightTopHighlight(radius: radius, color: FloodlightToken.heroHighlight.color)
            }
    }
}

/// Lists, tiles, outcome cards and facts: a flat card with a hairline and a soft drop.
struct FloodlightQuietCard: ViewModifier {
    var radius: CGFloat = 22
    var fill: Color = FloodlightToken.card.color
    var dashedEdge: Color? = nil
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                shape.fill(fill)
                    .shadow(color: scheme == .dark ? .black.opacity(0.3) : Color(red: 10 / 255, green: 45 / 255, blue: 68 / 255).opacity(0.05), radius: 1, x: 0, y: 1)
                    .shadow(color: scheme == .dark ? .black.opacity(0.35) : Color(red: 18 / 255, green: 72 / 255, blue: 120 / 255).opacity(0.1), radius: 8, x: 0, y: 7)
            }
            .overlay {
                if let dashedEdge {
                    shape.strokeBorder(dashedEdge, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                } else {
                    shape.strokeBorder(FloodlightToken.cardEdge.color, lineWidth: 1)
                    FloodlightTopHighlight(radius: radius, color: FloodlightToken.cardHighlight.color)
                }
            }
    }
}

/// The inset `0 1px 0` highlight along a card's top edge.
private struct FloodlightTopHighlight: View {
    let radius: CGFloat
    let color: Color
    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .inset(by: 1)
            .stroke(LinearGradient(stops: [.init(color: color, location: 0), .init(color: .clear, location: 0.08)],
                                   startPoint: .top, endPoint: .bottom), lineWidth: 1)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

extension View {
    func floodlightHero(radius: CGFloat = 22) -> some View { modifier(FloodlightHeroSurface(radius: radius)) }
    func floodlightCard(radius: CGFloat = 22, fill: Color = FloodlightToken.card.color, dashedEdge: Color? = nil) -> some View {
        modifier(FloodlightQuietCard(radius: radius, fill: fill, dashedEdge: dashedEdge))
    }
}

// MARK: - Backdrop

/// The sky (light) or floodlight beams (dark) behind a screen's hero only. It
/// fades into the ground at its bottom edge.
struct FloodlightSky: View {
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: FloodlightToken.backdrop1.color, location: 0),
                .init(color: FloodlightToken.backdrop2.color, location: 0.26),
                .init(color: FloodlightToken.backdrop3.color, location: 0.56),
                .init(color: FloodlightToken.backdrop4.color, location: 0.8),
                .init(color: FloodlightToken.ground.color, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            Canvas { context, size in paintArt(&context, size) }
                .mask(LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.5),
                                             .init(color: .clear, location: 0.9)], startPoint: .top, endPoint: .bottom))
        }
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    /// The page's 400 × 844 art, scaled to cover the width and pinned to the top.
    private func paintArt(_ context: inout GraphicsContext, _ size: CGSize) {
        let scale = max(size.width / 400, size.height / 844)
        context.translateBy(x: (size.width - 400 * scale) / 2, y: 0)
        context.scaleBy(x: scale, y: scale)
        let art = FloodlightNumber.backdropArt.value(scheme)
        if scheme == .dark {
            var bloom = context
            bloom.opacity = 0.85
            bloom.scaleBy(x: 1, y: 520 / 400)
            bloom.fill(Path(CGRect(x: 0, y: 0, width: 400, height: 400)), with: .radialGradient(
                Gradient(colors: [FloodlightRGBA.hex(0x9ED8F5, alpha: 0.32).color, FloodlightRGBA.hex(0x9ED8F5, alpha: 0).color]),
                center: CGPoint(x: 200, y: 0), startRadius: 0, endRadius: 240))
            var beams = context
            beams.opacity = art
            beams.addFilter(.blur(radius: 9))
            let beam = Gradient(colors: [FloodlightRGBA.hex(0xCFEFFF, alpha: 0.2).color, FloodlightRGBA.hex(0xCFEFFF, alpha: 0).color])
            for points in [[(18.0, -20.0), (70, -20), (250, 560), (-60, 560)], [(330, -20), (382, -20), (460, 560), (150, 560)]] {
                var path = Path()
                path.addLines(points.map { CGPoint(x: $0.0, y: $0.1) }); path.closeSubpath()
                beams.fill(path, with: .linearGradient(beam, startPoint: CGPoint(x: 0, y: -20), endPoint: CGPoint(x: 0, y: 560)))
            }
        } else {
            let swoosh = Gradient(stops: [.init(color: .white.opacity(0), location: 0), .init(color: .white.opacity(0.75), location: 0.45),
                                          .init(color: .white.opacity(0), location: 1)])
            var first = Path()
            first.move(to: CGPoint(x: -40, y: 250))
            first.addCurve(to: CGPoint(x: 460, y: 190), control1: CGPoint(x: 90, y: 160), control2: CGPoint(x: 260, y: 330))
            first.addLine(to: CGPoint(x: 460, y: 236))
            first.addCurve(to: CGPoint(x: -40, y: 300), control1: CGPoint(x: 270, y: 372), control2: CGPoint(x: 90, y: 214))
            first.closeSubpath()
            var second = Path()
            second.move(to: CGPoint(x: -40, y: 312))
            second.addCurve(to: CGPoint(x: 460, y: 280), control1: CGPoint(x: 120, y: 240), control2: CGPoint(x: 250, y: 400))
            second.addLine(to: CGPoint(x: 460, y: 300))
            second.addCurve(to: CGPoint(x: -40, y: 334), control1: CGPoint(x: 250, y: 424), control2: CGPoint(x: 120, y: 270))
            second.closeSubpath()
            for (path, opacity) in [(first, art), (second, art * 0.625)] {
                var layer = context
                layer.opacity = opacity
                layer.fill(path, with: .linearGradient(swoosh, startPoint: CGPoint(x: -40, y: 0), endPoint: CGPoint(x: 460, y: 0)))
            }
            var flare = context
            flare.opacity = 0.5
            flare.fill(Path(ellipseIn: CGRect(x: 232, y: -84, width: 240, height: 240)), with: .radialGradient(
                Gradient(stops: [.init(color: .white.opacity(0.95), location: 0),
                                 .init(color: FloodlightRGBA.hex(0xE9F8FF, alpha: 0.5).color, location: 0.35),
                                 .init(color: FloodlightRGBA.hex(0xE9F8FF, alpha: 0).color, location: 1)]),
                center: CGPoint(x: 352, y: 36), startRadius: 0, endRadius: 120))
        }
    }
}
