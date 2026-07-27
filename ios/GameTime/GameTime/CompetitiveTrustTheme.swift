import SwiftUI
import UIKit

enum CompetitiveTrustTheme {
    static let ink = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.03, green: 0.08, blue: 0.10, alpha: 1)
                : UIColor(red: 0.95, green: 0.97, blue: 0.97, alpha: 1)
        }
    )
    static let raisedInk = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.06, green: 0.13, blue: 0.16, alpha: 1)
                : UIColor.white
        }
    )
    static let divider = Color(
        uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.10)
                : UIColor.black.withAlphaComponent(0.08)
        }
    )
    static let teal = Color(
        red: 0.10,
        green: 0.72,
        blue: 0.62
    )
    static let amber = Color(
        red: 0.94,
        green: 0.64,
        blue: 0.20
    )
    static let subdued = Color.secondary
}

struct TrustCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(
                CompetitiveTrustTheme.raisedInk,
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(CompetitiveTrustTheme.divider, lineWidth: 1)
            }
    }
}

extension View {
    func trustCard() -> some View {
        modifier(TrustCardModifier())
    }

    func trustScreenBackground() -> some View {
        scrollContentBackground(.hidden)
            .background(CompetitiveTrustTheme.ink)
    }
}

struct TrustPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(Color.black.opacity(isEnabled ? 0.9 : 0.45))
            .background(
                CompetitiveTrustTheme.teal.opacity(isEnabled ? 1 : 0.45),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
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
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(CompetitiveTrustTheme.teal)
            .background(
                CompetitiveTrustTheme.teal.opacity(
                    configuration.isPressed ? 0.20 : 0.10
                ),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

struct InitialsAvatar: View {
    let initials: String
    var size: CGFloat = 44

    var body: some View {
        Text(initials)
            .font(.system(.headline, design: .rounded, weight: .bold))
            .foregroundStyle(CompetitiveTrustTheme.teal)
            .frame(width: size, height: size)
            .background(
                CompetitiveTrustTheme.teal.opacity(0.13),
                in: Circle()
            )
            .accessibilityHidden(true)
    }
}

struct TrustStatusPill: View {
    enum Kind {
        case verified
        case action
        case neutral
    }

    let text: String
    let kind: Kind

    private var color: Color {
        switch kind {
        case .verified: CompetitiveTrustTheme.teal
        case .action: CompetitiveTrustTheme.amber
        case .neutral: .secondary
        }
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct TestEnvironmentBanner: View {
    var body: some View {
        Label(
            "Test environment — no real pledge",
            systemImage: "exclamationmark.shield.fill"
        )
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.black.opacity(0.82))
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(CompetitiveTrustTheme.amber)
        .accessibilityLabel(
            "Test environment. No real pledge."
        )
    }
}
