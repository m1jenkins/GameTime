import SwiftUI

/// The shared saved-goal readout keeps the athletic figure and secondary unit
/// together without adding another card inside the confirmation hero.
struct SignalCreationMetricReadout: View {
    let value: Int
    let metric: ChallengeV1Policy.Metric
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var metricSize: CGFloat = 88

    private var number: String {
        switch metric {
        case .steps: value.formatted()
        case .distance: (Decimal(value) / 1_000_000).formatted(.number.precision(.fractionLength(0...6)))
        case .exercise, .timed: "\(value / 60):\(String(format: "%02d", value % 60))"
        }
    }

    private var unit: String {
        switch metric {
        case .steps: "steps"
        case .distance: "km"
        case .exercise, .timed: "min:sec"
        }
    }

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(number)
                .font(.system(size: min(metricSize, 120) * (metric == .steps ? 0.72 : 1), weight: .heavy).italic())
                .monospacedDigit().tracking(-4).padding(.trailing, 5)
                .lineLimit(1).minimumScaleFactor(0.4)
            Text(unit).font(.title2.weight(.medium))
                .foregroundStyle(SignalCreationTheme.textSecondary).fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.display(value))
    }
}
