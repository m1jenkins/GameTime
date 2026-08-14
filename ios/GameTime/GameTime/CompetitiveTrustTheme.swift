import SwiftUI
import UIKit

enum CompetitiveTrustTheme {
    // MARK: - R1 Athletic Design System Primary Tokens
    static let darkBackground = Color(red: 0.0, green: 0.0, blue: 0.0) // #000000
    static let graphiteSurface = Color(red: 0.0706, green: 0.0706, blue: 0.0706) // #121212
    static let signalOrange = Color(red: 0.9882, green: 0.3216, blue: 0.0) // #FC5200
    static let athleticGreen = Color(red: 0.0, green: 0.8157, blue: 0.5176) // #00D084

    // Sharp neutral hairline dividers: #2C2C2E (dark) / #E5E5EA (light)
    static let hairlineDivider = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.1725, green: 0.1725, blue: 0.1804, alpha: 1.0)
            : UIColor(red: 0.8980, green: 0.8980, blue: 0.9176, alpha: 1.0)
    })

    // MARK: - Adaptive Surfaces & Palette Aliases
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.black
            : UIColor(red: 0.949, green: 0.949, blue: 0.969, alpha: 1.0)
    })

    static let paperSunk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.0706, green: 0.0706, blue: 0.0706, alpha: 1.0)
            : UIColor(red: 0.898, green: 0.898, blue: 0.918, alpha: 1.0)
    })

    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.0706, green: 0.0706, blue: 0.0706, alpha: 1.0)
            : UIColor.white
    })

    // Text hierarchy
    static let primaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor.white
            : UIColor(red: 0.110, green: 0.082, blue: 0.137, alpha: 1.0)
    })

    static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.5569, green: 0.5569, blue: 0.5765, alpha: 1.0)
            : UIColor(red: 0.4235, green: 0.4235, blue: 0.4392, alpha: 1.0)
    })

    static let tertiaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.3882, green: 0.3882, blue: 0.4000, alpha: 1.0)
            : UIColor(red: 0.3650, green: 0.3220, blue: 0.4040, alpha: 1.0)
    })

    static let disabledText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.2824, green: 0.2824, blue: 0.2902, alpha: 1.0)
            : UIColor(red: 0.6550, green: 0.6160, blue: 0.6860, alpha: 1.0)
    })

    static let guide = hairlineDivider
    static let border = hairlineDivider
    static let strongBorder = hairlineDivider
    static let rail = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.1098, green: 0.1098, blue: 0.1176, alpha: 1.0)
            : UIColor(red: 0.8980, green: 0.8980, blue: 0.9176, alpha: 1.0)
    })

    // Accent Roles
    static let coral = signalOrange
    static let coralPressed = Color(red: 0.8157, green: 0.2627, blue: 0.0)
    static let coralInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.9882, green: 0.3216, blue: 0.0, alpha: 1.0)
            : UIColor(red: 0.7686, green: 0.2314, blue: 0.0, alpha: 1.0)
    })
    static let coralTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.1725, green: 0.0784, blue: 0.0314, alpha: 1.0)
            : UIColor(red: 1.0000, green: 0.9412, blue: 0.9020, alpha: 1.0)
    })
    static let coralTintStrong = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.2392, green: 0.1059, blue: 0.0431, alpha: 1.0)
            : UIColor(red: 1.0000, green: 0.8784, blue: 0.8196, alpha: 1.0)
    })

    static let sun = Color(red: 1.00, green: 0.7137, blue: 0.1529)
    static let sunInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 1.00, green: 0.7137, blue: 0.1529, alpha: 1.0)
            : UIColor(red: 0.4784, green: 0.3294, blue: 0.0, alpha: 1.0)
    })
    static let sunTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.1725, green: 0.1333, blue: 0.0314, alpha: 1.0)
            : UIColor(red: 1.0000, green: 0.9725, blue: 0.9020, alpha: 1.0)
    })

    static let mint = athleticGreen
    static let mintInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.0, green: 0.8157, blue: 0.5176, alpha: 1.0)
            : UIColor(red: 0.0, green: 0.4902, blue: 0.3020, alpha: 1.0)
    })

    static let inverseSecondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.3882, green: 0.3882, blue: 0.4000, alpha: 1.0)
            : UIColor(red: 0.3882, green: 0.3882, blue: 0.4000, alpha: 1.0)
    })

    static let actionCoral = coralInk

    private static let participantRamp: [Color] = [
        signalOrange,
        athleticGreen,
        Color(red: 0.486, green: 0.361, blue: 0.988),
        Color(red: 0.059, green: 0.710, blue: 0.808),
        Color(red: 0.925, green: 0.282, blue: 0.600),
        sun,
        Color(red: 0.298, green: 0.431, blue: 0.961),
    ]

    static let ink = paper
    static let raisedInk = card
    static let divider = border
    static let teal = coral
    static let amber = sun
    static let subdued = secondaryText

    static func participantColor(
        for participantID: UUID,
        participantIDs: [UUID],
        currentUserID: UUID?
    ) -> Color {
        if participantID == currentUserID {
            return signalOrange
        }

        let otherIDs = participantIDs
            .filter { $0 != currentUserID }
            .uniqued()
            .sorted { $0.uuidString < $1.uuidString }
        guard let index = otherIDs.firstIndex(of: participantID) else {
            return participantRamp[0]
        }
        return participantRamp[index % participantRamp.count]
    }

    static func avatarColor(for id: UUID) -> Color {
        let index = id.uuidString.utf8.reduce(0) { partialResult, byte in
            (partialResult + Int(byte)) % participantRamp.count
        }
        return participantRamp[index]
    }

    // MARK: - Athletic Typography (SF Pro Display & Monospaced Digits)
    static func displayFont(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }

    static func uiFont(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        weight: Font.Weight = .regular
    ) -> Font {
        .system(size: size, weight: weight, design: .default)
    }

    static func tabularFont(
        size: CGFloat,
        weight: Font.Weight = .bold
    ) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }

    static func monoFont(
        size: CGFloat,
        weight: Font.Weight = .bold
    ) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }
}

@MainActor
enum AthleticAppearance {
    static func install() {
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
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
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

    func daybreakScreenChrome() -> some View {
        background(CompetitiveTrustTheme.paper.ignoresSafeArea())
            .toolbarBackground(
                CompetitiveTrustTheme.paper,
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
    }

    func athleticScreenChrome() -> some View {
        daybreakScreenChrome()
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
            .foregroundStyle(Color.black.opacity(isEnabled ? 1 : 0.72))
            .background(
                CompetitiveTrustTheme.signalOrange.opacity(
                    isEnabled ? 1 : 0.42
                ),
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                if tone == .secondary || tone == .quiet {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
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
            .black
        case .secondary:
            CompetitiveTrustTheme.signalOrange
        case .quiet:
            CompetitiveTrustTheme.secondaryText
        }
    }

    private var background: Color {
        switch tone {
        case .primary:
            CompetitiveTrustTheme.signalOrange
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
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(color.opacity(muted ? 0.46 : 1), in: Circle())
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
