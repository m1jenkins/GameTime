import SwiftUI

/// Create and invite read the shared palette under their original names.
enum SignalCreationTheme {
    static let contentInset = SignalTheme.contentInset
    static let canvas = SignalTheme.canvas
    static let surface = SignalTheme.surface
    static let soft = SignalTheme.soft
    static let textPrimary = SignalTheme.textPrimary
    static let accent = SignalTheme.accent
    static let textSecondary = SignalTheme.textSecondary
    static let divider = SignalTheme.divider
    static let onAccent = SignalTheme.onAccent
    static let selection = SignalTheme.selection
    static let danger = SignalTheme.danger
}

/// Creation's sheet header keeps its existing control identifiers.
struct SignalCreationChrome: View {
    let title: String
    let showsBack: Bool
    let back: () -> Void
    let close: () -> Void

    var body: some View {
        LiveSheetHeader(title: title, back: showsBack ? back : nil, close: close,
                        backIdentifier: "beta.create.back", closeIdentifier: "beta.create.close")
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
