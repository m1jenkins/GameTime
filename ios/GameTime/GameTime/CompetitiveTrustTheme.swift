import SwiftUI
import UIKit

enum CompetitiveTrustTheme {
    // One semantic palette, with aliases for historical consumers during migration.
    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
    static let canvas = adaptive(0xFFFFFF, 0x0C1220)
    static let surface = adaptive(0xFFFFFF, 0x151E2E)
    static let textPrimary = adaptive(0x101724, 0xF5F7FC)
    static let textSecondary = adaptive(0x526176, 0xB3C0D5)
    static let brand = adaptive(0x0752F5, 0x9BB5FF)
    static let feature = Color(red: 7 / 255, green: 82 / 255, blue: 245 / 255)
    static let onBrand = Color.white
    static let selection = adaptive(0xEAF0FF, 0x253759)
    static let divider = adaptive(0xE1E7F0, 0x34425A)
    static let progressTrack = adaptive(0xE1E7F0, 0x34425A)
    static let error = adaptive(0xB22D40, 0xFFADBA)
    static let warning = adaptive(0x775200, 0xE9C784)
    static let success = adaptive(0x216A52, 0x99D9C0)
    static let warningSurface = adaptive(0xF8F1E2, 0x332B1F)

    static let paper = canvas
    static let paperSunk = progressTrack
    static let card = surface
    static let primaryText = textPrimary
    static let secondaryText = textSecondary
    static let tertiaryText = textSecondary
    static let disabledText = textSecondary
    static let hairlineDivider = divider
    static let guide = divider
    static let border = divider
    static let strongBorder = divider
    static let rail = progressTrack
    static let darkBackground = canvas
    static let graphiteSurface = surface
    static let signalOrange = brand
    static let athleticGreen = success
    static let coral = brand
    static let coralPressed = adaptive(0x1B38AA, 0xBED0FF)
    static let coralInk = brand
    static let coralTint = selection
    static let coralTintStrong = selection
    static let actionCoral = brand
    static let sun = warningSurface
    static let sunInk = warning
    static let sunTint = warningSurface
    static let mint = success
    static let mintInk = success
    static let inverseSecondaryText = Color.white.opacity(0.9)
    static let ink = canvas
    static let raisedInk = surface
    static let teal = brand
    static let amber = warning
    static let subdued = textSecondary

    static func participantColor(for participantID: UUID, participantIDs: [UUID], currentUserID: UUID?) -> Color {
        participantID == currentUserID ? brand : textSecondary
    }
    static func avatarColor(for id: UUID) -> Color { textSecondary }

    // Registered bundled font names verified with CoreText; licenses ship in Resources.
    // Custom fonts scale relative to each caller's semantic text role.
    static func displayFont(size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        .custom("BarlowCondensed-BlackItalic", size: size, relativeTo: textStyle)
    }
    static func uiFont(size: CGFloat, relativeTo textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .custom("HankenGrotesk-Regular", size: size, relativeTo: textStyle).weight(weight)
    }
    static func tabularFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("HankenGrotesk-Regular", size: size, relativeTo: .title).weight(weight).monospacedDigit()
    }
    static func monoFont(size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .custom("Menlo-Regular", size: size, relativeTo: .caption).weight(weight)
    }

}

@MainActor
enum AthleticAppearance {
    static func install() {
        if #available(iOS 26, *) { return }
        let navigationAppearance = UINavigationBarAppearance()
        navigationAppearance.configureWithOpaqueBackground()
        navigationAppearance.backgroundColor = UIColor(
            CompetitiveTrustTheme.paper
        )
        navigationAppearance.shadowColor = UIColor(CompetitiveTrustTheme.hairlineDivider)

        let largeTitleDescriptor = UIFont.systemFont(
            ofSize: 34,
            weight: .bold
        ).fontDescriptor.withDesign(.default)
        let inlineTitleDescriptor = UIFont.systemFont(
            ofSize: 17,
            weight: .bold
        ).fontDescriptor.withDesign(.default)

        navigationAppearance.largeTitleTextAttributes = [
            .font: largeTitleDescriptor.map {
                UIFont(descriptor: $0, size: 34)
            } ?? UIFont.systemFont(ofSize: 34, weight: .bold),
            .foregroundColor: UIColor(CompetitiveTrustTheme.primaryText),
        ]
        navigationAppearance.titleTextAttributes = [
            .font: inlineTitleDescriptor.map {
                UIFont(descriptor: $0, size: 17)
            } ?? UIFont.systemFont(ofSize: 17, weight: .bold),
            .foregroundColor: UIColor(CompetitiveTrustTheme.primaryText),
        ]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = navigationAppearance
        navigationBar.compactAppearance = navigationAppearance
        navigationBar.scrollEdgeAppearance = navigationAppearance
        navigationBar.tintColor = UIColor(CompetitiveTrustTheme.signalOrange)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(CompetitiveTrustTheme.paper)
        tabAppearance.shadowColor = UIColor(CompetitiveTrustTheme.hairlineDivider)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(CompetitiveTrustTheme.secondaryText),
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(CompetitiveTrustTheme.signalOrange),
        ]

        for itemAppearance in [
            tabAppearance.stackedLayoutAppearance,
            tabAppearance.inlineLayoutAppearance,
            tabAppearance.compactInlineLayoutAppearance,
        ] {
            itemAppearance.normal.iconColor = UIColor(
                CompetitiveTrustTheme.secondaryText
            )
            itemAppearance.normal.titleTextAttributes = normalAttributes
            itemAppearance.selected.iconColor = UIColor(
                CompetitiveTrustTheme.signalOrange
            )
            itemAppearance.selected.titleTextAttributes = selectedAttributes
        }

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabAppearance
        tabBar.scrollEdgeAppearance = tabAppearance
    }
}

typealias DaybreakAppearance = AthleticAppearance

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

struct TrustCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(14)
            .background(
                CompetitiveTrustTheme.card,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
            }
    }
}

extension View {
    func trustCard() -> some View {
        modifier(TrustCardModifier())
    }

    func trustScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(CompetitiveTrustTheme.paper)
    }

    @ViewBuilder func daybreakScreenChrome() -> some View {
        if #available(iOS 26, *) {
            background(CompetitiveTrustTheme.canvas.ignoresSafeArea())
        } else {
            background(CompetitiveTrustTheme.canvas.ignoresSafeArea())
                .toolbarBackground(CompetitiveTrustTheme.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    func athleticScreenChrome() -> some View {
        daybreakScreenChrome()
    }

    @ViewBuilder func daybreakTabChrome() -> some View {
        if #available(iOS 26, *) {
            toolbarBackground(.automatic, for: .tabBar)
        } else {
            toolbarBackground(CompetitiveTrustTheme.canvas, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }

    /// Keeps the last tab-hosted action or card above the floating tab bar.
    func daybreakTabScrollClearance() -> some View {
        contentMargins(.bottom, 88, for: .scrollContent)
    }

    func daybreakTappableRow() -> some View {
        frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
    }
}

struct TrustPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 16,
                    relativeTo: .headline,
                    weight: .bold
                )
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.horizontal, 20)
            .foregroundStyle(CompetitiveTrustTheme.onBrand.opacity(isEnabled ? 1 : 0.72))
            .background(
                CompetitiveTrustTheme.feature.opacity(
                    isEnabled ? 1 : 0.42
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.98
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

struct TrustSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 15,
                    relativeTo: .headline,
                    weight: .bold
                )
            )
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .padding(.horizontal, 18)
            .foregroundStyle(
                CompetitiveTrustTheme.primaryText.opacity(isEnabled ? 1 : 0.45)
            )
            .background(
                CompetitiveTrustTheme.card.opacity(
                    configuration.isPressed ? 0.72 : 1
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
            }
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.98
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

struct SunPillButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 14,
                    relativeTo: .subheadline,
                    weight: .bold
                )
            )
            .foregroundStyle(
                CompetitiveTrustTheme.primaryText.opacity(isEnabled ? 1 : 0.45)
            )
            .padding(.horizontal, 17)
            .frame(minHeight: 44)
            .background(
                CompetitiveTrustTheme.sun.opacity(isEnabled ? 1 : 0.45),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.98
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }
}

struct TrustCompactButtonStyle: ButtonStyle {
    enum Tone {
        case primary
        case secondary
        case quiet
    }

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var tone: Tone = .secondary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: 13,
                    relativeTo: .subheadline,
                    weight: .bold
                )
            )
            .foregroundStyle(foreground.opacity(isEnabled ? 1 : 0.48))
            .padding(.horizontal, 15)
            .frame(minHeight: 44)
            .background(
                background.opacity(
                    isEnabled
                        ? (configuration.isPressed ? 0.72 : 1)
                        : 0.5
                ),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                if tone == .secondary || tone == .quiet {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
                }
            }
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.97
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }

    private var foreground: Color {
        switch tone {
        case .primary:
            CompetitiveTrustTheme.onBrand
        case .secondary:
            CompetitiveTrustTheme.signalOrange
        case .quiet:
            CompetitiveTrustTheme.secondaryText
        }
    }

    private var background: Color {
        switch tone {
        case .primary:
            CompetitiveTrustTheme.feature
        case .secondary:
            CompetitiveTrustTheme.coralTint
        case .quiet:
            CompetitiveTrustTheme.card
        }
    }
}

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 44
    var color: Color = CompetitiveTrustTheme.signalOrange
    var muted = false

    var body: some View {
        Text(initials)
            .font(
                CompetitiveTrustTheme.uiFont(
                    size: max(9, size * 0.35),
                    relativeTo: .headline,
                    weight: .bold
                )
            )
            .foregroundStyle(CompetitiveTrustTheme.textPrimary)
            .frame(width: size, height: size)
            .background(CompetitiveTrustTheme.progressTrack, in: Circle())
            .accessibilityHidden(true)
    }
}

struct TrustStatusPill: View {
    enum Kind: Equatable {
        case verified
        case action
        case neutral
        case live
        case pledge
        case positive
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var liveDotIsDimmed = false

    let text: String
    let kind: Kind

    private var color: Color {
        switch kind {
        case .verified, .positive:
            CompetitiveTrustTheme.mintInk
        case .action:
            CompetitiveTrustTheme.coralInk
        case .neutral:
            CompetitiveTrustTheme.secondaryText
        case .live:
            CompetitiveTrustTheme.signalOrange
        case .pledge:
            CompetitiveTrustTheme.sunInk
        }
    }

    private var background: Color {
        switch kind {
        case .verified, .positive:
            CompetitiveTrustTheme.athleticGreen.opacity(0.12)
        case .action:
            CompetitiveTrustTheme.coralTint
        case .neutral:
            CompetitiveTrustTheme.card
        case .live:
            .clear
        case .pledge:
            CompetitiveTrustTheme.sunTint
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if kind == .live {
                Circle()
                    .fill(CompetitiveTrustTheme.signalOrange)
                    .frame(width: 8, height: 8)
                    .opacity(liveDotIsDimmed ? 0.35 : 1)
            }

            Text(text)
                .textCase(kind == .live ? .uppercase : nil)
        }
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 12,
                relativeTo: .caption,
                weight: .bold
            )
        )
        .tracking(kind == .live ? 0.7 : 0)
        .foregroundStyle(color)
        .padding(.horizontal, kind == .live ? 0 : 8)
        .padding(.vertical, kind == .live ? 0 : 4)
        .background(
            background,
            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
        )
        .overlay {
            if kind != .live {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(CompetitiveTrustTheme.hairlineDivider, lineWidth: 1)
            }
        }
        .onAppear {
            guard kind == .live, !reduceMotion else { return }
            withAnimation(
                .easeInOut(duration: 1).repeatForever(autoreverses: true)
            ) {
                liveDotIsDimmed = true
            }
        }
    }
}

enum EnvironmentDisclosureCopy {
    static let testOnly =
        "Test commitment — no money will be charged."
    static let stripeSandbox =
        "Payment test mode — no real money moves."
    static let demo =
        "Demo mode — no money will be charged. Nothing here leaves your phone."

    static func message(for settlementMode: PersonalSettlementMode) -> String {
        switch settlementMode {
        case .testOnly:
            testOnly
        case .stripeSandbox:
            stripeSandbox
        }
    }
}

struct EnvironmentDisclosureBanner: View {
    let settlementMode: PersonalSettlementMode
    var isDemo = false

    private var message: String {
        isDemo
            ? EnvironmentDisclosureCopy.demo
            : EnvironmentDisclosureCopy.message(for: settlementMode)
    }

    var body: some View {
        Label(
            message,
            systemImage: isDemo
                ? "play.circle.fill"
                : "exclamationmark.shield.fill"
        )
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 12,
                relativeTo: .caption,
                weight: .bold
            )
        )
        .foregroundStyle(
            isDemo ? Color.white : CompetitiveTrustTheme.primaryText
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            isDemo
                ? CompetitiveTrustTheme.signalOrange
                : CompetitiveTrustTheme.sun
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .accessibilityIdentifier("personal.environment-disclosure")
    }
}

private struct DaybreakSecondaryForegroundKey: EnvironmentKey {
    static let defaultValue = CompetitiveTrustTheme.secondaryText
}

extension EnvironmentValues {
    var daybreakSecondaryForeground: Color {
        get { self[DaybreakSecondaryForegroundKey.self] }
        set { self[DaybreakSecondaryForegroundKey.self] = newValue }
    }
}

struct DaybreakAsyncStatus: View {
    @Environment(\.daybreakSecondaryForeground)
    private var secondaryForeground

    let message: String
    var onDarkSurface = false

    var body: some View {
        HStack(spacing: 9) {
            ProgressView()
                .tint(
                    onDarkSurface
                        ? CompetitiveTrustTheme.inverseSecondaryText
                        : CompetitiveTrustTheme.signalOrange
                )
            Text(message)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 14,
                        relativeTo: .subheadline,
                        weight: .bold
                    )
                )
        }
        .foregroundStyle(
            onDarkSurface
                ? CompetitiveTrustTheme.inverseSecondaryText
                : secondaryForeground
        )
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(message)
    }
}

@MainActor
enum DaybreakAccessibility {
    static func announce(_ message: String) {
        UIAccessibility.post(notification: .announcement, argument: message)
    }
}

/// Native condensed display type, scaled by the surrounding Dynamic Type setting.
struct CobaltDisplay: ViewModifier {
    private let size: CGFloat
    private let italic: Bool
    init(size: CGFloat, italic: Bool = true) {
        self.size = size
        self.italic = italic
    }
    func body(content: Content) -> some View {
        content.font(.custom(italic ? "BarlowCondensed-BlackItalic" : "BarlowCondensed-Black", size: size, relativeTo: .largeTitle))
            .monospacedDigit()
    }
}
