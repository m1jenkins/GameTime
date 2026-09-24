import SwiftUI
import UIKit

/// Signal's native semantic palette. Information is always opaque; material is
/// reserved for controls and the selected-day readout. UIKit resolves contrast
/// as well as appearance so sheets and system navigation use the same colors.
enum SignalTheme {
    private static func adaptive(_ light: UInt32, _ dark: UInt32,
                                 highContrastLight: UInt32? = nil,
                                 highContrastDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let darkMode = traits.userInterfaceStyle == .dark
            let increased = traits.accessibilityContrast == .high
            let rgb = darkMode
                ? (increased ? highContrastDark ?? dark : dark)
                : (increased ? highContrastLight ?? light : light)
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }

    // Native content uses the study's surface, without its desktop surround.
    static let canvas = adaptive(0xFAFBFC, 0xFAFBFC)
    static let surface = adaptive(0xFFFFFF, 0xFFFFFF)
    static let soft = adaptive(0xF0F2F5, 0xF0F2F5)
    static let textPrimary = adaptive(0x111318, 0x111318)
    static let textSecondary = adaptive(0x606975, 0x606975,
                                        highContrastLight: 0x111318, highContrastDark: 0x111318)
    static let accent = adaptive(0x245BFF, 0x245BFF)
    static let onAccent = adaptive(0xFFFFFF, 0xFFFFFF)
    static let selection = adaptive(0xF4F7FF, 0xF4F7FF)
    static let divider = adaptive(0xDCE1E8, 0xDCE1E8,
                                  highContrastLight: 0x758298, highContrastDark: 0x8592A6)
    static let progressTrack = adaptive(0xDCE1E8, 0xDCE1E8)
    static let bar = adaptive(0x727B88, 0x727B88)
    static let danger = adaptive(0x9A6700, 0x9A6700)
    static let contentInset: CGFloat = 20

    static func participantColor(for participantID: UUID, participantIDs: [UUID], currentUserID: UUID?) -> Color {
        participantID == currentUserID ? accent : bar
    }
    static func avatarColor(for id: UUID) -> Color { textSecondary }

    // Normalize retained screens to the semantic system scale. Large numeric
    // readouts use SignalMetricTypography for their own scaled base size.
    static func displayFont(size: CGFloat, relativeTo textStyle: Font.TextStyle) -> Font {
        .system(textStyle, design: .default).weight(.semibold)
    }
    static func uiFont(size: CGFloat, relativeTo textStyle: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(textStyle, design: .default).weight(weight)
    }
    static func tabularFont(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size >= 30 ? .largeTitle : size >= 20 ? .title2 : size >= 16 ? .body : .caption,
                design: .default).weight(weight).monospacedDigit()
    }
    static func monoFont(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(.caption, design: .default).weight(weight).monospacedDigit()
    }
}

@MainActor enum SignalAppearance {
    static func install() {
        // iOS 26+ supplies native Liquid Glass navigation. Earlier systems use
        // solid chrome with the same semantic colors and system typography.
        if #available(iOS 26, *) { return }
        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(SignalTheme.canvas)
        navigation.shadowColor = UIColor(SignalTheme.divider)
        navigation.titleTextAttributes = [.foregroundColor: UIColor(SignalTheme.textPrimary)]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(SignalTheme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().tintColor = UIColor(SignalTheme.accent)

        let tabs = UITabBarAppearance()
        tabs.configureWithOpaqueBackground()
        tabs.backgroundColor = UIColor(SignalTheme.canvas)
        tabs.shadowColor = UIColor(SignalTheme.divider)
        for item in [tabs.stackedLayoutAppearance, tabs.inlineLayoutAppearance, tabs.compactInlineLayoutAppearance] {
            item.normal.iconColor = UIColor(SignalTheme.textSecondary)
            item.normal.titleTextAttributes = [.foregroundColor: UIColor(SignalTheme.textSecondary)]
            item.selected.iconColor = UIColor(SignalTheme.accent)
            item.selected.titleTextAttributes = [.foregroundColor: UIColor(SignalTheme.accent)]
        }
        UITabBar.appearance().standardAppearance = tabs
        UITabBar.appearance().scrollEdgeAppearance = tabs
    }
}

struct SignalSectionModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SignalTheme.canvas)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SignalTheme.divider)
                    .frame(height: 1)
                    .accessibilityHidden(true)
            }
    }
}

/// A container has no material of its own; only its actual controls get glass.
struct SignalGlassGroup: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: 16) { content }
        } else { content }
    }
}

extension View {
    func signalSection() -> some View { modifier(SignalSectionModifier()) }
    func signalScreenBackground() -> some View {
        scrollContentBackground(.hidden).background(SignalTheme.canvas)
    }
    @ViewBuilder func signalScreenChrome() -> some View {
        if #available(iOS 26, *) {
            background(SignalTheme.canvas.ignoresSafeArea())
        } else {
            background(SignalTheme.canvas.ignoresSafeArea())
                .toolbarBackground(SignalTheme.canvas, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
        }
    }
    @ViewBuilder func signalTabChrome() -> some View {
        if #available(iOS 26, *) {
            toolbarBackground(.automatic, for: .tabBar)
        } else {
            toolbarBackground(SignalTheme.canvas, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
        }
    }
    func signalTabScrollClearance() -> some View {
        contentMargins(.bottom, 32, for: .scrollContent)
    }
    func signalTappableRow() -> some View {
        frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
    }
}

/// Identical layout and selected/disabled semantics with glass and solid modes.
/// Applied after the control's typography, padding and minimum hit area.
struct SignalControlMaterial: ViewModifier {
    var primary = false
    var interactive = true
    var cornerRadius: CGFloat = 26
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency, contrast != .increased {
            content.glassEffect(
                interactive
                    ? .regular.tint(primary ? SignalTheme.accent : .clear).interactive()
                    : .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            content.background(primary ? SignalTheme.accent : SignalTheme.soft,
                               in: RoundedRectangle(cornerRadius: cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(primary ? SignalTheme.accent : SignalTheme.divider, lineWidth: 1)
                }
        }
    }
}

private struct SignalButtonBody: View {
    let configuration: ButtonStyleConfiguration
    var primary = false
    var compact = false
    var expands = true
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .font(compact ? .subheadline.weight(.semibold) : .headline)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, compact ? 16 : 20)
            .padding(.vertical, 12)
            .frame(maxWidth: expands ? .infinity : nil, minHeight: compact ? 44 : 50)
            .foregroundStyle(configuration.role == .destructive ? SignalTheme.danger
                             : primary ? SignalTheme.onAccent : SignalTheme.textPrimary)
            .modifier(SignalControlMaterial(primary: primary && configuration.role != .destructive))
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
struct SignalPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { SignalButtonBody(configuration: configuration, primary: true) }
}
struct SignalSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { SignalButtonBody(configuration: configuration) }
}
struct SignalPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { SignalButtonBody(configuration: configuration, compact: true, expands: false) }
}
struct SignalCompactButtonStyle: ButtonStyle {
    enum Tone { case primary, secondary, quiet }
    var tone: Tone = .secondary
    func makeBody(configuration: Configuration) -> some View {
        SignalButtonBody(configuration: configuration, primary: tone == .primary, compact: true, expands: false)
    }
}

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 44
    var color: Color = SignalTheme.accent
    var muted = false
    var body: some View {
        Image(systemName: "person")
            .font(.body).foregroundStyle(SignalTheme.textSecondary)
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct SignalStatusTag: View {
    enum Kind: Equatable { case verified, action, neutral, live, pledge, positive }
    let text: String
    let kind: Kind
    var body: some View {
        Text(text).font(.caption.weight(.semibold))
            .foregroundStyle(kind == .neutral || kind == .pledge ? SignalTheme.textSecondary : SignalTheme.accent)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(kind == .neutral || kind == .pledge ? SignalTheme.soft : SignalTheme.selection,
                        in: RoundedRectangle(cornerRadius: 5))
    }
}

enum EnvironmentDisclosureCopy {
    static let testOnly = "Test commitment — no money will be charged."
    static let stripeSandbox = "Payment test mode — no real money moves."
    static let demo = "Demo mode — no money will be charged. Nothing here leaves your phone."
    static func message(for settlementMode: PersonalSettlementMode) -> String {
        switch settlementMode {
        case .testOnly: testOnly
        case .stripeSandbox: stripeSandbox
        }
    }
}
struct EnvironmentDisclosureBanner: View {
    let settlementMode: PersonalSettlementMode
    var isDemo = false
    private var message: String {
        isDemo ? EnvironmentDisclosureCopy.demo : EnvironmentDisclosureCopy.message(for: settlementMode)
    }
    var body: some View {
        Label(message, systemImage: isDemo ? "play.circle" : "info.circle")
            .font(.caption).foregroundStyle(SignalTheme.textSecondary)
            .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 8)
            .background(SignalTheme.soft)
            .accessibilityElement(children: .ignore).accessibilityLabel(message)
            .accessibilityIdentifier("personal.environment-disclosure")
    }
}
private struct SignalSecondaryForegroundKey: EnvironmentKey {
    static let defaultValue = SignalTheme.textSecondary
}
extension EnvironmentValues {
    var signalSecondaryForeground: Color {
        get { self[SignalSecondaryForegroundKey.self] }
        set { self[SignalSecondaryForegroundKey.self] = newValue }
    }
}
struct SignalAsyncStatus: View {
    @Environment(\.signalSecondaryForeground) private var secondaryForeground
    let message: String
    var onDarkSurface = false
    var body: some View {
        HStack(spacing: 9) {
            ProgressView().tint(onDarkSurface ? SignalTheme.onAccent : SignalTheme.accent)
            Text(message).font(.subheadline)
        }
        .foregroundStyle(onDarkSurface ? SignalTheme.onAccent : secondaryForeground)
        .frame(minHeight: 44).accessibilityElement(children: .combine).accessibilityLabel(message)
    }
}
@MainActor enum SignalAccessibility {
    static func announce(_ message: String) { UIAccessibility.post(notification: .announcement, argument: message) }
}

struct SignalDisplay: ViewModifier {
    @ScaledMetric private var size: CGFloat
    init(size: CGFloat) { _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle) }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .semibold)).tracking(-0.6)
    }
}
struct SignalMetricTypography: ViewModifier {
    @ScaledMetric private var size: CGFloat
    init(size: CGFloat) { _size = ScaledMetric(wrappedValue: size, relativeTo: .largeTitle) }
    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: .medium)).monospacedDigit().tracking(-0.8)
    }
}

/// Retained native journeys share Signal's open, opaque section presentation.
/// List keeps native focus, pickers, refresh, and accessibility behavior.
struct SignalList<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        List { content.listRowBackground(SignalTheme.canvas) }
            .listStyle(.plain).scrollContentBackground(.hidden)
            .background(SignalTheme.canvas).tint(SignalTheme.accent)
    }
}
struct SignalForm<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View { SignalList { content } }
}

struct SignalSimulationBanner: View {
    var body: some View {
        Text("Simulated stakes — no real money moves.")
            .font(.caption).foregroundStyle(SignalTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity).padding(.horizontal, 16).padding(.vertical, 8)
            .layoutPriority(1)
            .background(SignalTheme.soft).accessibilityIdentifier("beta.environment-disclosure")
    }
}
