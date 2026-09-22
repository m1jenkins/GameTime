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

struct SignalCreationChrome: View {
    let title: String
    let showsBack: Bool
    let back: () -> Void
    let close: () -> Void
    @ScaledMetric(relativeTo: .headline) private var titleSize: CGFloat = 18

    var body: some View {
        HStack(spacing: 12) {
            if showsBack {
                Button(action: back) { Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44) }
                    .accessibilityLabel("Back").accessibilityIdentifier("beta.create.back")
            }
            Text(title).font(.system(size: titleSize, weight: .bold)).tracking(-0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(title.isEmpty)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 16, weight: .medium)).frame(width: 44, height: 44)
                    .background(SignalCreationTheme.soft.opacity(0.75), in: Circle())
            }.accessibilityLabel("Close").accessibilityIdentifier("beta.create.close")
        }.buttonStyle(.plain).foregroundStyle(SignalCreationTheme.textPrimary)
            .padding(.horizontal, SignalCreationTheme.contentInset).padding(.vertical, 6)
            .background(SignalCreationTheme.canvas)
    }
}

struct SignalCreationAgreementRow: View {
    let symbol: String
    let title: String
    let detail: String
    @ScaledMetric(relativeTo: .caption) private var titleSize: CGFloat = 11
    @ScaledMetric(relativeTo: .subheadline) private var detailSize: CGFloat = 13
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 22, weight: .regular))
                .foregroundStyle(SignalCreationTheme.accent).frame(width: 28, height: 32).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: titleSize)).foregroundStyle(SignalCreationTheme.textSecondary)
                Text(detail).font(.system(size: detailSize, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(SignalCreationTheme.textPrimary).padding(.horizontal, 14).padding(.vertical, 13)
            .background(SignalCreationTheme.soft.opacity(0.65), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SignalCreationTextActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.caption.weight(.medium))
            .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
            .foregroundStyle(SignalCreationTheme.accent)
            .opacity(configuration.isPressed ? 0.65 : 1)
    }
}
