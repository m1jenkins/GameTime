import SwiftUI
import UIKit

enum CompetitiveTrustTheme {
    // MARK: - Daybreak Ledger tokens
    // Light: paper canvas, pine action, money stays ink.
    // Dark: near-black canvas, graphite surfaces, pine stays pine.

    static let pine = Color(
        red: 31.0 / 255.0,
        green: 92.0 / 255.0,
        blue: 69.0 / 255.0
    )

    static let onPine = Color(
        red: 244.0 / 255.0,
        green: 240.0 / 255.0,
        blue: 232.0 / 255.0
    )

    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 20.0 / 255.0, green: 19.0 / 255.0, blue: 17.0 / 255.0, alpha: 1)
            : UIColor(red: 244.0 / 255.0, green: 240.0 / 255.0, blue: 232.0 / 255.0, alpha: 1)
    })

    static let paperSunk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 26.0 / 255.0, green: 25.0 / 255.0, blue: 23.0 / 255.0, alpha: 1)
            : UIColor(red: 235.0 / 255.0, green: 230.0 / 255.0, blue: 220.0 / 255.0, alpha: 1)
    })

    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 28.0 / 255.0, green: 27.0 / 255.0, blue: 25.0 / 255.0, alpha: 1)
            : UIColor.white
    })

    static let hairlineDivider = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 58.0 / 255.0, green: 55.0 / 255.0, blue: 47.0 / 255.0, alpha: 1)
            : UIColor(red: 230.0 / 255.0, green: 225.0 / 255.0, blue: 216.0 / 255.0, alpha: 1)
    })

    static let primaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 244.0 / 255.0, green: 240.0 / 255.0, blue: 232.0 / 255.0, alpha: 1)
            : UIColor(red: 26.0 / 255.0, green: 31.0 / 255.0, blue: 24.0 / 255.0, alpha: 1)
    })

    static let secondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 163.0 / 255.0, green: 156.0 / 255.0, blue: 148.0 / 255.0, alpha: 1)
            : UIColor(red: 107.0 / 255.0, green: 100.0 / 255.0, blue: 92.0 / 255.0, alpha: 1)
    })

    static let tertiaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 122.0 / 255.0, green: 116.0 / 255.0, blue: 108.0 / 255.0, alpha: 1)
            : UIColor(red: 138.0 / 255.0, green: 131.0 / 255.0, blue: 122.0 / 255.0, alpha: 1)
    })

    static let disabledText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 90.0 / 255.0, green: 86.0 / 255.0, blue: 80.0 / 255.0, alpha: 1)
            : UIColor(red: 167.0 / 255.0, green: 160.0 / 255.0, blue: 151.0 / 255.0, alpha: 1)
    })

    static let pineInk = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 127.0 / 255.0, green: 184.0 / 255.0, blue: 154.0 / 255.0, alpha: 1)
            : UIColor(red: 31.0 / 255.0, green: 92.0 / 255.0, blue: 69.0 / 255.0, alpha: 1)
    })

    static let behindPace = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 212.0 / 255.0, green: 160.0 / 255.0, blue: 90.0 / 255.0, alpha: 1)
            : UIColor(red: 138.0 / 255.0, green: 90.0 / 255.0, blue: 26.0 / 255.0, alpha: 1)
    })

    static let attention = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 214.0 / 255.0, green: 132.0 / 255.0, blue: 108.0 / 255.0, alpha: 1)
            : UIColor(red: 139.0 / 255.0, green: 62.0 / 255.0, blue: 42.0 / 255.0, alpha: 1)
    })

    static let didNotCount = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 154.0 / 255.0, green: 162.0 / 255.0, blue: 172.0 / 255.0, alpha: 1)
            : UIColor(red: 92.0 / 255.0, green: 101.0 / 255.0, blue: 112.0 / 255.0, alpha: 1)
    })

    static let money = primaryText
    static let ink = primaryText
    static let darkBackground = paper
    static let graphiteSurface = card

    static var signalOrange: Color { pine }
    static var athleticGreen: Color { pine }

    static let guide = hairlineDivider
    static let border = hairlineDivider
    static let strongBorder = hairlineDivider
    static let rail = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 42.0 / 255.0, green: 40.0 / 255.0, blue: 36.0 / 255.0, alpha: 1)
            : UIColor(red: 230.0 / 255.0, green: 225.0 / 255.0, blue: 216.0 / 255.0, alpha: 1)
    })

    static let coral = pine
    static let coralPressed = Color(
        red: 24.0 / 255.0,
        green: 70.0 / 255.0,
        blue: 52.0 / 255.0
    )
    static let coralInk = pineInk
    static let coralTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 28.0 / 255.0, green: 42.0 / 255.0, blue: 36.0 / 255.0, alpha: 1)
            : UIColor(red: 228.0 / 255.0, green: 239.0 / 255.0, blue: 233.0 / 255.0, alpha: 1)
    })
    static let coralTintStrong = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 36.0 / 255.0, green: 58.0 / 255.0, blue: 48.0 / 255.0, alpha: 1)
            : UIColor(red: 210.0 / 255.0, green: 228.0 / 255.0, blue: 218.0 / 255.0, alpha: 1)
    })

    static let sun = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 58.0 / 255.0, green: 48.0 / 255.0, blue: 32.0 / 255.0, alpha: 1)
            : UIColor(red: 232.0 / 255.0, green: 220.0 / 255.0, blue: 200.0 / 255.0, alpha: 1)
    })
    static let sunInk = behindPace
    static let sunTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 42.0 / 255.0, green: 36.0 / 255.0, blue: 26.0 / 255.0, alpha: 1)
            : UIColor(red: 243.0 / 255.0, green: 234.0 / 255.0, blue: 216.0 / 255.0, alpha: 1)
    })

    static let mint = pine
    static let mintInk = pineInk

    static let inverseSecondaryText = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 122.0 / 255.0, green: 116.0 / 255.0, blue: 108.0 / 255.0, alpha: 1)
            : UIColor(red: 107.0 / 255.0, green: 100.0 / 255.0, blue: 92.0 / 255.0, alpha: 1)
    })

    static let actionCoral = pineInk

    private static let participantRamp: [Color] = [
        pine,
        behindPace,
        Color(red: 92.0 / 255.0, green: 101.0 / 255.0, blue: 112.0 / 255.0),
        Color(red: 74.0 / 255.0, green: 98.0 / 255.0, blue: 88.0 / 255.0),
        Color(red: 139.0 / 255.0, green: 62.0 / 255.0, blue: 42.0 / 255.0),
        sunInk,
        Color(red: 70.0 / 255.0, green: 84.0 / 255.0, blue: 72.0 / 255.0),
    ]

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
            return pine
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

    // MARK: - Typography (SF Pro, tabular figures for counts)
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
enum DaybreakAppearance {
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
        navigationBar.tintColor = UIColor(CompetitiveTrustTheme.pine)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(CompetitiveTrustTheme.paper)
        tabAppearance.shadowColor = UIColor(CompetitiveTrustTheme.hairlineDivider)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(CompetitiveTrustTheme.secondaryText),
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(CompetitiveTrustTheme.pine),
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
                CompetitiveTrustTheme.pine
            )
            itemAppearance.selected.titleTextAttributes = selectedAttributes
        }

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabAppearance
        tabBar.scrollEdgeAppearance = tabAppearance
    }
}

typealias AthleticAppearance = DaybreakAppearance

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
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
            .foregroundStyle(
                CompetitiveTrustTheme.onPine.opacity(isEnabled ? 1 : 0.72)
            )
            .background(
                CompetitiveTrustTheme.pine.opacity(
                    isEnabled ? 1 : 0.42
                ),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
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
            CompetitiveTrustTheme.onPine
        case .secondary:
            CompetitiveTrustTheme.pineInk
        case .quiet:
            CompetitiveTrustTheme.secondaryText
        }
    }

    private var background: Color {
        switch tone {
        case .primary:
            CompetitiveTrustTheme.pine
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
    var color: Color = CompetitiveTrustTheme.pine
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
            .foregroundStyle(CompetitiveTrustTheme.onPine)
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
            CompetitiveTrustTheme.pine
        case .pledge:
            CompetitiveTrustTheme.sunInk
        }
    }

    private var background: Color {
        switch kind {
        case .verified, .positive:
            CompetitiveTrustTheme.pine.opacity(0.12)
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
                    .fill(CompetitiveTrustTheme.pine)
                    .frame(width: 8, height: 8)
                    .opacity(liveDotIsDimmed ? 0.35 : 1)
            }

            Text(text)
        }
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 12,
                relativeTo: .caption,
                weight: .bold
            )
        )
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
            isDemo ? CompetitiveTrustTheme.onPine : CompetitiveTrustTheme.primaryText
        )
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(
            isDemo
                ? CompetitiveTrustTheme.pine
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
                        : CompetitiveTrustTheme.pine
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
