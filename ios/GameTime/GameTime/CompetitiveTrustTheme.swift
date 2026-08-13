import SwiftUI
import UIKit

enum CompetitiveTrustTheme {
    // Daybreak replaces the original teal-on-ink treatment with warm paper.
    // The legacy names remain as aliases so non-challenge screens can migrate
    // without duplicating a second palette.
    static let paper = Color(red: 1.00, green: 0.969, blue: 0.941)
    static let paperSunk = Color(red: 0.969, green: 0.925, blue: 0.886)
    static let card = Color.white
    static let primaryText = Color(red: 0.110, green: 0.082, blue: 0.137)
    static let secondaryText = Color(red: 0.431, green: 0.392, blue: 0.471)
    // The lightest text token still clears 4.5:1 on both Daybreak paper and
    // white cards. Keep lighter values for borders and decoration only.
    static let tertiaryText = Color(red: 0.470, green: 0.435, blue: 0.500)
    static let disabledText = Color(red: 0.655, green: 0.616, blue: 0.686)
    static let guide = Color(red: 0.788, green: 0.749, blue: 0.820)
    static let border = Color(red: 0.949, green: 0.902, blue: 0.855)
    static let strongBorder = Color(red: 0.894, green: 0.827, blue: 0.769)
    static let rail = Color(red: 0.945, green: 0.922, blue: 0.965)

    static let coral = Color(red: 0.980, green: 0.340, blue: 0.255)
    static let coralPressed = Color(red: 0.910, green: 0.267, blue: 0.184)
    static let coralInk = Color(red: 0.780, green: 0.180, blue: 0.105)
    static let coralTint = Color(red: 1.00, green: 0.941, blue: 0.929)
    static let coralTintStrong = Color(red: 0.969, green: 0.871, blue: 0.851)

    static let sun = Color(red: 1.00, green: 0.714, blue: 0.153)
    static let sunInk = Color(red: 0.541, green: 0.384, blue: 0.00)
    static let sunTint = Color(red: 1.00, green: 0.941, blue: 0.800)

    static let mint = Color(red: 0.071, green: 0.753, blue: 0.541)
    static let mintInk = Color(red: 0.020, green: 0.460, blue: 0.320)

    static let minimumHitTarget: CGFloat = 44

    private static let participantRamp: [Color] = [
        Color(red: 0.486, green: 0.361, blue: 0.988),
        Color(red: 1.00, green: 0.620, blue: 0.106),
        mint,
        Color(red: 0.059, green: 0.710, blue: 0.808),
        Color(red: 0.925, green: 0.282, blue: 0.600),
        Color(red: 0.961, green: 0.773, blue: 0.094),
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
            return coral
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

    static func displayFont(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle
    ) -> Font {
        .custom(
            "BricolageGrotesque-96ptExtraBold",
            size: size,
            relativeTo: textStyle
        )
    }

    static func uiFont(
        size: CGFloat,
        relativeTo textStyle: Font.TextStyle,
        weight: Font.Weight = .regular
    ) -> Font {
        .custom(
            "HankenGrotesk-Regular",
            size: size,
            relativeTo: textStyle
        )
        .weight(weight)
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
        navigationAppearance.shadowColor = .clear
        navigationAppearance.largeTitleTextAttributes = [
            .foregroundColor: UIColor(CompetitiveTrustTheme.primaryText),
        ]
        navigationAppearance.titleTextAttributes = [
            .foregroundColor: UIColor(CompetitiveTrustTheme.primaryText),
        ]

        let navigationBar = UINavigationBar.appearance()
        navigationBar.standardAppearance = navigationAppearance
        navigationBar.compactAppearance = navigationAppearance
        navigationBar.scrollEdgeAppearance = navigationAppearance
        navigationBar.tintColor = UIColor(CompetitiveTrustTheme.coralInk)

        let tabAppearance = UITabBarAppearance()
        tabAppearance.configureWithOpaqueBackground()
        tabAppearance.backgroundColor = UIColor(CompetitiveTrustTheme.paper)
        tabAppearance.shadowColor = UIColor(CompetitiveTrustTheme.border)

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(CompetitiveTrustTheme.tertiaryText),
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(CompetitiveTrustTheme.coralInk),
        ]

        for itemAppearance in [
            tabAppearance.stackedLayoutAppearance,
            tabAppearance.inlineLayoutAppearance,
            tabAppearance.compactInlineLayoutAppearance,
        ] {
            itemAppearance.normal.iconColor = UIColor(
                CompetitiveTrustTheme.tertiaryText
            )
            itemAppearance.normal.titleTextAttributes = normalAttributes
            itemAppearance.selected.iconColor = UIColor(
                CompetitiveTrustTheme.coralInk
            )
            itemAppearance.selected.titleTextAttributes = selectedAttributes
        }

        let tabBar = UITabBar.appearance()
        tabBar.standardAppearance = tabAppearance
        tabBar.scrollEdgeAppearance = tabAppearance
    }
}

private extension Sequence where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}

struct TrustCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(
                CompetitiveTrustTheme.card,
                in: RoundedRectangle(cornerRadius: 24, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(CompetitiveTrustTheme.border, lineWidth: 1)
            }
            .shadow(
                color: CompetitiveTrustTheme.primaryText.opacity(0.05),
                radius: 7,
                y: 3
            )
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
            .environment(\.colorScheme, .light)
            .toolbarBackground(
                CompetitiveTrustTheme.paper,
                for: .navigationBar
            )
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
    }

    /// Expands the effective hit region while allowing compact visual
    /// treatments to remain visually compact.
    func minimumInteractiveSize() -> some View {
        frame(
            minWidth: CompetitiveTrustTheme.minimumHitTarget,
            minHeight: CompetitiveTrustTheme.minimumHitTarget
        )
        .contentShape(Rectangle())
    }
}

@MainActor
enum GameTimeAccessibility {
    static func announce(_ message: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: message
        )
    }

    static func focusFirstElement() {
        guard UIAccessibility.isVoiceOverRunning else { return }
        UIAccessibility.post(notification: .screenChanged, argument: nil)
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
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.72))
            .background(
                CompetitiveTrustTheme.coralInk.opacity(isEnabled ? 1 : 0.42),
                in: Capsule()
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
            .frame(minHeight: 42)
            .padding(.horizontal, 18)
            .foregroundStyle(
                CompetitiveTrustTheme.coralInk.opacity(isEnabled ? 1 : 0.45)
            )
            .background(
                CompetitiveTrustTheme.coralTint.opacity(
                    configuration.isPressed ? 0.72 : 1
                ),
                in: Capsule()
            )
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.98
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
            .padding(.vertical, 1)
            .contentShape(Rectangle())
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
            .frame(minHeight: 40)
            .background(
                CompetitiveTrustTheme.sun.opacity(isEnabled ? 1 : 0.45),
                in: Capsule()
            )
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.98
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
            .padding(.vertical, 2)
            .contentShape(Rectangle())
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
            .frame(minHeight: 36)
            .background(
                background.opacity(
                    isEnabled
                        ? (configuration.isPressed ? 0.72 : 1)
                        : 0.5
                ),
                in: Capsule()
            )
            .scaleEffect(
                reduceMotion || !configuration.isPressed ? 1 : 0.97
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        switch tone {
        case .primary:
            .white
        case .secondary:
            CompetitiveTrustTheme.coralInk
        case .quiet:
            CompetitiveTrustTheme.secondaryText
        }
    }

    private var background: Color {
        switch tone {
        case .primary:
            CompetitiveTrustTheme.coralInk
        case .secondary:
            CompetitiveTrustTheme.coralTint
        case .quiet:
            CompetitiveTrustTheme.primaryText.opacity(0.055)
        }
    }
}

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 44
    var color: Color = CompetitiveTrustTheme.coral
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
            .lineLimit(1)
            .minimumScaleFactor(0.5)
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var liveDotIsDimmed = false

    let text: String
    let kind: Kind

    private var color: Color {
        switch kind {
        case .verified, .positive:
            colorScheme == .dark
                ? CompetitiveTrustTheme.mint
                : CompetitiveTrustTheme.mintInk
        case .action:
            CompetitiveTrustTheme.coralInk
        case .neutral:
            colorScheme == .dark
                ? Color.white.opacity(0.82)
                : CompetitiveTrustTheme.secondaryText
        case .live:
            colorScheme == .dark
                ? CompetitiveTrustTheme.coral
                : CompetitiveTrustTheme.coralInk
        case .pledge:
            CompetitiveTrustTheme.sunInk
        }
    }

    private var background: Color {
        switch kind {
        case .verified, .positive:
            CompetitiveTrustTheme.mint.opacity(0.12)
        case .action:
            CompetitiveTrustTheme.coralTint
        case .neutral:
            colorScheme == .dark
                ? Color.white.opacity(0.12)
                : CompetitiveTrustTheme.primaryText.opacity(0.06)
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
                    .fill(CompetitiveTrustTheme.coral)
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
        .padding(.horizontal, kind == .live ? 0 : 10)
        .padding(.vertical, kind == .live ? 0 : 5)
        .background(background, in: Capsule())
        .onAppear {
            updateLiveDotAnimation()
        }
        .onChange(of: reduceMotion) {
            updateLiveDotAnimation()
        }
    }

    private func updateLiveDotAnimation() {
        guard kind == .live else { return }
        if reduceMotion {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                liveDotIsDimmed = false
            }
        } else {
            withAnimation(
                .easeInOut(duration: 1).repeatForever(autoreverses: true)
            ) {
                liveDotIsDimmed = true
            }
        }
    }
}

struct TestEnvironmentBanner: View {
    let settlementMode: PersonalSettlementMode

    private var message: String {
        switch settlementMode {
        case .testOnly:
            "Test commitment — no money will be charged."
        case .stripeSandbox:
            "Payment test mode — no real money moves."
        }
    }

    var body: some View {
        Label(
            message,
            systemImage: "exclamationmark.shield.fill"
        )
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 12,
                relativeTo: .caption,
                weight: .bold
            )
        )
        .foregroundStyle(CompetitiveTrustTheme.primaryText)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(CompetitiveTrustTheme.sun)
        .accessibilityLabel(message)
    }
}
