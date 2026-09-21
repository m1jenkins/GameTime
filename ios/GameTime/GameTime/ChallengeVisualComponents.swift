import Foundation
import SwiftUI

struct SignalSectionLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.headline)
            .foregroundStyle(SignalTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            .accessibilityLabel(text)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Quiet, growing sections for account, forms and supporting content.
struct SignalOpenSection<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 16)
            .foregroundStyle(SignalTheme.textPrimary)
            .overlay(alignment: .bottom) {
                Rectangle().fill(SignalTheme.divider).frame(height: 1)
                    .accessibilityHidden(true)
            }
    }
}

enum SignalSectionTone: Equatable {
    case standard
    case inverse
    case pledge
}

struct SignalSection<Content: View>: View {
    let tone: SignalSectionTone
    let content: Content

    init(
        tone: SignalSectionTone = .standard,
        @ViewBuilder content: () -> Content
    ) {
        self.tone = tone
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.signalSecondaryForeground, tone == .inverse ? SignalTheme.onAccent : SignalTheme.textSecondary)
            .padding(.vertical, 18)
            .padding(.horizontal, tone == .standard ? 0 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(tone == .inverse ? SignalTheme.onAccent : SignalTheme.textPrimary)
            .background(tone == .inverse ? SignalTheme.accent : tone == .pledge ? SignalTheme.soft : SignalTheme.canvas)
            .overlay(alignment: .bottom) {
                if tone == .standard {
                    Rectangle()
                        .fill(SignalTheme.divider)
                        .frame(height: 1)
                        .accessibilityHidden(true)
                }
            }
    }
}

extension ContestMetric {
    func daybreakDisplayText(
        value: Double,
        compact: Bool = false
    ) -> String {
        switch self {
        case .distanceMeters:
            let miles = value / 1_609.344
            return "\(miles.formatted(.number.precision(.fractionLength(0...2)))) mi"
        case .steps:
            return compact
                ? "\(value.formatted(.number.notation(.compactName)))"
                : "\(value.formatted(.number.precision(.fractionLength(0)))) steps"
        case .activeEnergyKilocalories:
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) kcal"
        case .exerciseMinutes:
            return "\(value.formatted(.number.precision(.fractionLength(0...1)))) min"
        }
    }
}

extension ContestCard {
    var daybreakTargetText: String {
        metric.daybreakDisplayText(value: targetValue)
    }

    var daybreakGoalLabel: String {
        let target = metric.daybreakDisplayText(
            value: targetValue,
            compact: true
        )
        return cadence == .daily ? "Goal \(target)/day" : "Goal \(target)"
    }

    var daybreakWindowText: String {
        let dayCount = max(
            1,
            Calendar.current.dateComponents(
                [.day],
                from: startsAt,
                to: endsAt
            ).day ?? 1
        )
        return dayCount == 1 ? "1 day" : "\(dayCount) days"
    }
}
