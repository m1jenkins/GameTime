import SwiftUI

// Shared pieces used by the form and list screens: the terms table, glass form
// fields, roster rows, and the staging banner.

// MARK: - Terms

/// One row of the immutable-terms table.
struct TermRow: View {
    let label: String
    let value: String
    var emphasis: Color = GlassArena.ink
    var isMonospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.mutedLight)
            Spacer(minLength: 12)
            Text(value)
                .font(
                    isMonospaced
                        ? .system(size: 12, weight: .medium, design: .monospaced)
                        : GlassArenaFont.text(14, .semibold)
                )
                .foregroundStyle(emphasis)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A glass card holding a labelled group of rows, with hairlines between them.
struct GlassCardSection<Content: View>: View {
    var title: String?
    var footnote: String?
    var tier: GlassTier = .standard
    var cornerRadius: CGFloat = 28
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                SectionEyebrow(text: title, fontSize: 11, tracking: 0.9)
            }
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            if let footnote {
                Text(footnote)
                    .font(GlassArenaFont.text(12))
                    .foregroundStyle(GlassArena.mutedLight)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .glassPane(tier, cornerRadius: cornerRadius)
    }
}

// MARK: - Form fields

/// A glass text field. `prefix` carries the `@` in front of a handle.
struct GlassTextField: View {
    let placeholder: String
    @Binding var text: String
    var prefix: String?
    var accessibilityID: String?
    var accessibilityName: String?
    var isLowercase = false
    var submitLabel: SubmitLabel = .done
    var onSubmit: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            if let prefix {
                Text(prefix)
                    .font(GlassArenaFont.text(16, .semibold))
                    .foregroundStyle(GlassArena.mutedLight)
            }
            TextField(placeholder, text: $text)
                .font(GlassArenaFont.text(16, .medium))
                .foregroundStyle(GlassArena.ink)
                .textInputAutocapitalization(isLowercase ? .never : .words)
                .autocorrectionDisabled(isLowercase)
                .submitLabel(submitLabel)
                .onSubmit { onSubmit?() }
                .accessibilityIdentifier(accessibilityID ?? placeholder)
                .accessibilityLabel(accessibilityName ?? placeholder)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .glassPane(.standard, cornerRadius: 18)
    }
}

/// A selectable chip — metrics, cadence, the chosen opponent.
struct GlassChip: View {
    let title: String
    var systemImage: String?
    var isSelected: Bool
    var isDashed = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .bold))
                }
                Text(title)
                    .font(GlassArenaFont.text(14, isSelected ? .bold : .semibold))
            }
            .foregroundStyle(
                isSelected ? GlassArena.tealInk : GlassArena.inkSecondary
            )
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background {
                if isSelected {
                    Capsule().fill(GlassArena.tealButton)
                } else if isDashed {
                    Capsule().strokeBorder(
                        GlassArena.mutedLight.opacity(0.55),
                        style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                    )
                } else {
                    Capsule()
                        .fill(.white.opacity(0.5))
                        .overlay {
                            Capsule().strokeBorder(
                                .white.opacity(0.8),
                                lineWidth: 1
                            )
                        }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// A −/+ stepper for the stake.
struct GlassStepper: View {
    let value: String
    var tint: Color = GlassArena.amber700
    var fontSize: CGFloat = 24
    var valueWidth: CGFloat = 92
    var decrementLabel = "Decrease"
    var incrementLabel = "Increase"
    var canDecrement = true
    var canIncrement = true
    let decrement: () -> Void
    let increment: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            button("minus", action: decrement, isEnabled: canDecrement)
                .accessibilityLabel(decrementLabel)
            Text(value)
                .font(GlassArenaFont.display(fontSize, .heavy))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minWidth: valueWidth)
            button("plus", action: increment, isEnabled: canIncrement)
                .accessibilityLabel(incrementLabel)
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue(value)
    }

    private func button(
        _ symbol: String,
        action: @escaping () -> Void,
        isEnabled: Bool
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .heavy))
                .foregroundStyle(GlassArena.inkSecondary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .fill(GlassArena.ink.opacity(0.055))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

// MARK: - Roster

/// A row in "Your roster", or a pending request in either direction.
struct RosterRow: View {
    let displayName: String
    let handle: String
    var side: GlassAvatar.Side = .them
    var actionTitle: String?
    var isDestructiveAction = false
    var isEnabled = true
    var action: (() -> Void)?
    var tap: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            GlassAvatar(
                initials: ProfileCard(
                    id: UUID(),
                    handle: handle,
                    displayName: displayName
                ).initials,
                size: 40,
                side: side
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(GlassArenaFont.text(15, .bold))
                    .foregroundStyle(GlassArena.ink)
                Text("@\(handle)")
                    .font(GlassArenaFont.text(13))
                    .foregroundStyle(GlassArena.mutedLight)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)

            if let actionTitle, let action {
                Button(action: action) {
                    if isDestructiveAction {
                        Text(actionTitle)
                            .font(GlassArenaFont.text(14, .semibold))
                            .foregroundStyle(GlassArena.inkTertiary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(
                                    cornerRadius: 14,
                                    style: .continuous
                                )
                                .fill(GlassArena.ink.opacity(0.055))
                            )
                    } else {
                        TealChip(text: actionTitle)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!isEnabled)
                .accessibilityLabel("\(actionTitle) \(displayName)")
            }
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 18)
        .glassPane(.standard, cornerRadius: 26)
        .contentShape(Rectangle())
        .onTapGesture { tap?() }
    }
}

// MARK: - Staging banner

/// Staging only: this is not a real pledge.
struct TestEnvironmentBanner: View {
    var body: some View {
        Label(
            "Staging — no real pledge",
            systemImage: "exclamationmark.shield.fill"
        )
        .font(GlassArenaFont.text(12, .bold))
        .foregroundStyle(GlassArena.amberInk)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(GlassArena.amber400)
        .accessibilityLabel("Staging environment. No real pledge.")
    }
}
