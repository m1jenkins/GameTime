import SwiftUI
import UIKit

/// The approved create/invite palette, scoped to these screens so existing
/// challenge and historical agreement presentation remains independent.
enum SignalCreationTheme {
    static let contentInset = SignalTheme.contentInset
    private static func color(_ light: UInt32, dark: Color, highContrast: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            if traits.userInterfaceStyle == .dark { return UIColor(dark).resolvedColor(with: traits) }
            let rgb = traits.accessibilityContrast == .high ? highContrast ?? light : light
            return UIColor(red: CGFloat((rgb >> 16) & 255) / 255,
                           green: CGFloat((rgb >> 8) & 255) / 255,
                           blue: CGFloat(rgb & 255) / 255, alpha: 1)
        })
    }
    static let canvas = color(0xFAFBFC, dark: SignalTheme.canvas)
    static let surface = color(0xFFFFFF, dark: SignalTheme.surface)
    static let soft = color(0xF0F2F5, dark: SignalTheme.soft)
    static let textPrimary = color(0x111318, dark: SignalTheme.textPrimary)
    static let accent = color(0x245BFF, dark: SignalTheme.accent)
    static let textSecondary = color(0x606975, dark: SignalTheme.textSecondary, highContrast: 0x111318)
    static let divider = color(0xDCE1E8, dark: SignalTheme.divider, highContrast: 0x758298)
    static let onAccent = SignalTheme.onAccent
    static let selection = color(0xEBF0FF, dark: SignalTheme.selection)
    static let danger = SignalTheme.danger
}

struct SignalCreationPrimaryStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 18)
            .foregroundStyle(enabled ? SignalCreationTheme.onAccent : SignalCreationTheme.textSecondary)
            .background(enabled ? SignalCreationTheme.accent : SignalCreationTheme.soft,
                        in: RoundedRectangle(cornerRadius: 18))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}
