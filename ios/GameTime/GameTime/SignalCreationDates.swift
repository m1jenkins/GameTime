import SwiftUI

/// Inclusive calendar dates summarize the editable window; the agreement still
/// owns its exact midnight boundaries and the existing date editor.
struct SignalCreationDateCard: View {
    let start: Date
    let duration: Int?
    let calendar: Calendar
    let timeZoneID: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var headingSize: CGFloat = 15
    @ScaledMetric(relativeTo: .title3) private var dateSize: CGFloat = 21
    @ScaledMetric(relativeTo: .caption) private var captionSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption) private var daySize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var dayHeight: CGFloat = 28

    private var lastDay: Date? {
        guard let duration, (1...30).contains(duration) else { return nil }
        return calendar.date(byAdding: .day, value: duration - 1, to: start)
    }
    private var days: [Date] {
        guard let duration, (1...7).contains(duration) else { return [] }
        return (0..<duration).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var count: String {
        guard let duration, (1...30).contains(duration) else { return "Choose your dates" }
        return duration == 1 ? "1 day" : "\(duration) days"
    }
    private var zoneName: String {
        guard let zone = TimeZone(identifier: timeZoneID) else { return SignalTimeZone.name(timeZoneID) }
        return zone.localizedName(for: .generic, locale: .current) ?? SignalTimeZone.name(timeZoneID)
    }
    private var year: String {
        let first = formatted(start, template: "yyyy")
        guard let lastDay else { return first }
        let last = formatted(lastDay, template: "yyyy")
        return first == last ? first : "\(first)–\(last)"
    }
    private var accessibilityDates: String {
        guard let lastDay else { return "Your dates. Choose 1 to 30 full days." }
        return "Your dates. Starts \(formatted(start, template: "EEEE MMMM d yyyy")). Ends \(formatted(lastDay, template: "EEEE MMMM d yyyy")). \(count). \(zoneName)."
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Your dates").font(.system(size: headingSize, weight: .semibold)).tracking(-0.25)
                Spacer(minLength: 12)
                Text(count).font(.system(size: captionSize)).foregroundStyle(SignalCreationTheme.textSecondary)
            }
            Button(action: action) {
                VStack(spacing: 15) {
                    if let lastDay {
                        endpoints(lastDay: lastDay)
                        if !days.isEmpty, !typeSize.isAccessibilitySize { dayStrip }
                    } else {
                        Label("Choose your dates", systemImage: "calendar")
                            .font(.system(size: headingSize, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(LinearGradient(colors: [SignalCreationTheme.surface, SignalCreationTheme.soft], startPoint: .topLeading, endPoint: .bottomTrailing),
                            in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(SignalCreationTheme.divider.opacity(0.65), lineWidth: 0.75) }
                .contentShape(RoundedRectangle(cornerRadius: 20))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityDates)
            .accessibilityHint("Edit the start date, duration and time zone")
            .accessibilityIdentifier("beta.create.dates")
            Label("\(year) · \(zoneName)", systemImage: "calendar")
                .font(.system(size: captionSize))
                .foregroundStyle(SignalCreationTheme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(SignalCreationTheme.textPrimary)
    }

    @ViewBuilder private func endpoints(lastDay: Date) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                endpoint(start, prefix: "Starts", alignment: .leading)
                endpoint(lastDay, prefix: "Ends", alignment: .leading)
            }.frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: 9) {
                endpoint(start, prefix: "Starts", alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.right").font(.system(size: 19, weight: .regular))
                    .foregroundStyle(SignalCreationTheme.textSecondary).accessibilityHidden(true)
                endpoint(lastDay, prefix: "Ends", alignment: .trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
    private func endpoint(_ date: Date, prefix: String, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 6) {
            Text("\(prefix) \(formatted(date, template: "EEE"))")
                .font(.system(size: captionSize)).foregroundStyle(SignalCreationTheme.textSecondary)
            Text(formatted(date, template: "MMM d"))
                .font(.system(size: dateSize, weight: .bold)).tracking(-0.65)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private var dayStrip: some View {
        HStack(spacing: 0) {
            ForEach(days.indices, id: \.self) { index in
                let edge = index == 0 || index == days.count - 1
                VStack(spacing: 7) {
                    Text(formatted(days[index], template: "EEEEE"))
                        .font(.system(size: captionSize)).foregroundStyle(SignalCreationTheme.textSecondary)
                    Text(formatted(days[index], template: "d"))
                        .font(.system(size: daySize, weight: .medium)).monospacedDigit()
                        .frame(maxWidth: .infinity).frame(height: dayHeight)
                        .foregroundStyle(edge ? SignalCreationTheme.onAccent : SignalCreationTheme.accent)
                        .background {
                            if edge { RoundedRectangle(cornerRadius: 9).fill(SignalCreationTheme.accent) }
                            else { Rectangle().fill(SignalCreationTheme.selection) }
                        }
                }.frame(maxWidth: .infinity)
            }
        }.accessibilityHidden(true)
    }
    private func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
