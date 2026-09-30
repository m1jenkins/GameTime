import SwiftUI

/// Creation keeps its native actions and draft; these are the Round 13 pieces
/// around that same flow.
struct FloodlightCreationChrome: View {
    let title: String
    let showsBack: Bool
    let back: () -> Void
    let close: () -> Void
    var body: some View {
        HStack(spacing: 8) {
            if showsBack {
                FloodlightNavButton(symbol: "chevron.left", label: "Back", action: back)
                    .accessibilityIdentifier("beta.create.back")
            } else { Color.clear.frame(width: 44, height: 44).accessibilityHidden(true) }
            Text(title).floodlightFont(15, weight: .semibold).foregroundStyle(Floodlight.ink)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
            FloodlightNavButton(symbol: "xmark", label: "Close", action: close)
                .accessibilityIdentifier("beta.create.close")
        }
        .padding(.horizontal, 16).padding(.top, 2).padding(.bottom, 8)
    }
}

struct FloodlightCreationProgress: View {
    let labels: [String]
    let current: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    private var selected: Int { min(max(0, current), max(0, labels.count - 1)) }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(labels.indices, id: \.self) { step($0) }
                }
            } else {
                HStack(spacing: 6) {
                    ForEach(labels.indices, id: \.self) { index in
                        step(index)
                        if index < labels.count - 1 {
                            Capsule().fill(index < selected ? Floodlight.muted : Floodlight.line)
                                .frame(width: 6, height: 2).accessibilityHidden(true)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(labels.isEmpty ? "" : "Step \(selected + 1) of \(labels.count), \(labels[selected])")
    }

    private func step(_ index: Int) -> some View {
        HStack(spacing: 6) {
            Group {
                if index < selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .semibold)) }
                else { Text(String(index + 1)).floodlightFont(13, weight: .bold, condensed: true) }
            }
            .frame(width: 24, height: 24)
            .foregroundStyle(index == selected ? Floodlight.buttonInk : Floodlight.ink)
            .background(Circle().fill(index == selected ? Floodlight.button : Floodlight.card))
            .overlay(Circle().strokeBorder(index == selected ? .clear : Floodlight.cardEdge, lineWidth: 1))
            Text(labels[index]).floodlightFont(12, weight: .semibold)
                .foregroundStyle(index == selected ? Floodlight.ink : Floodlight.heroMuted)
                .fixedSize(horizontal: true, vertical: true)
        }
    }
}

struct FloodlightCreationBackdrop: View {
    var body: some View {
        Floodlight.ground
            .overlay(alignment: .top) { FloodlightSky().frame(height: 490) }
            .ignoresSafeArea()
    }
}

struct FloodlightCreationIcon: View {
    let symbol: String
    var size: CGFloat = 36
    var body: some View {
        Image(systemName: symbol).font(.system(size: 18, weight: .regular)).foregroundStyle(Floodlight.link)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: 12).fill(Floodlight.well))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Floodlight.wellEdge, lineWidth: 1))
            .accessibilityHidden(true)
    }
}

struct FloodlightCreationActivityChoices: View {
    @Binding var selection: ChallengeV1Policy.Metric
    let metrics: [ChallengeV1Policy.Metric]
    let title: (ChallengeV1Policy.Metric) -> String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
            ForEach(metrics, id: \.self) { metric in
                Button { selection = metric } label: {
                    HStack(spacing: 7) {
                        Image(systemName: metric.symbol).font(.system(size: 17)).foregroundStyle(Floodlight.link)
                            .frame(width: 20).accessibilityHidden(true)
                        Text(title(metric)).floodlightFont(14.5, weight: .semibold).foregroundStyle(Floodlight.ink)
                            .lineLimit(typeSize <= .large ? 1 : nil)
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 50)
                    .background(RoundedRectangle(cornerRadius: 16).fill(selection == metric ? Floodlight.card : Floodlight.well))
                    .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selection == metric ? Floodlight.link : Floodlight.wellEdge,
                                                                                lineWidth: selection == metric ? 2 : 1))
                }
                .buttonStyle(.plain).accessibilityLabel(title(metric)).accessibilityAddTraits(selection == metric ? .isSelected : [])
                .accessibilityIdentifier("beta.create.metric." + metric.rawValue)
            }
        }
    }
}

struct FloodlightCreationDateCard: View {
    let start: Date
    let duration: Int?
    let calendar: Calendar
    let timeZoneID: String
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var last: Date? { duration.flatMap { calendar.date(byAdding: .day, value: $0 - 1, to: start) } }
    private var count: String { duration.map { $0 == 1 ? "1 day" : "\($0) days" } ?? "Choose your dates" }
    static func zoneName(_ id: String) -> String {
        TimeZone(identifier: id)?.localizedName(for: .generic, locale: .current) ?? SignalTimeZone.name(id)
    }
    private func formatted(_ date: Date, _ template: String) -> String {
        let formatter = DateFormatter(); formatter.calendar = calendar; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                FloodlightLabel("Your dates")
                Spacer(minLength: 12)
                Text(count).floodlightFont(13, weight: .semibold).foregroundStyle(Floodlight.ink)
            }
            Button(action: action) {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    endpoint(start, prefix: "Starts")
                    Image(systemName: "arrow.right").font(.system(size: 18)).foregroundStyle(Floodlight.muted).accessibilityHidden(true)
                    if let last { endpoint(last, prefix: "Ends") }
                }
            }
            .buttonStyle(.plain).accessibilityElement(children: .ignore)
            .accessibilityLabel("Your dates. Starts \(formatted(start, "EEEE MMMM d yyyy")). Ends \(formatted(last ?? start, "EEEE MMMM d yyyy")). \(count). \(Self.zoneName(timeZoneID)).")
            .accessibilityHint("Edit the start date, duration and time zone").accessibilityIdentifier("beta.create.dates")
            Rectangle().fill(Floodlight.line).frame(height: 1)
            Button(action: action) {
                HStack(spacing: 10) {
                    Image(systemName: "globe").font(.system(size: 14)).accessibilityHidden(true)
                    Text("Time zone").floodlightFont(13, weight: .medium)
                    Spacer(minLength: 8)
                    Text(Self.zoneName(timeZoneID)).floodlightFont(13, weight: .semibold).foregroundStyle(Floodlight.link)
                        .fixedSize(horizontal: false, vertical: true)
                    Image(systemName: "chevron.right").font(.system(size: 12)).accessibilityHidden(true)
                }
                .foregroundStyle(Floodlight.muted).frame(minHeight: 32)
            }
            .buttonStyle(.plain).accessibilityLabel("Time zone, " + Self.zoneName(timeZoneID))
        }
        .padding(15).padding(.bottom, 5).floodlightCard()
    }
    private func endpoint(_ date: Date, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(prefix) \(formatted(date, "EEE"))").floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted)
            Text(formatted(date, "MMM d")).floodlightFont(25, weight: .bold, condensed: true).foregroundStyle(Floodlight.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 13).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 15).fill(Floodlight.well))
    }
}

/// The pot counts the creator's saved entry. Merely choosing a friend paints
/// their color in a dashed seat; it never adds their amount to the pot.
struct FloodlightCreationPot: View {
    let cents: Int
    let initials: String
    var selectedSlots: [Int] = []
    var caption = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Canvas { context, size in paint(&context, size: size) }
            .aspectRatio(200 / 192, contentMode: .fit).accessibilityHidden(true)
    }
    private func paint(_ context: inout GraphicsContext, size: CGSize) {
        let scale = size.width / 200
        context.scaleBy(x: scale, y: scale)
        let muted = FloodlightToken.muted.rgba(scheme)
        let orbit: CGFloat = 76
        context.stroke(Path(ellipseIn: CGRect(x: 24, y: 20, width: 152, height: 152)), with: .color(muted.opacity(0.35).color),
                       style: StrokeStyle(lineWidth: 1.2, dash: [2, 5]))
        FloodlightPotPainter(center: CGPoint(x: 100, y: 96), radius: 44, rim: 3, amountSize: 34,
                             cents: cents, caption: caption ? 8 : nil, scheme: scheme).paint(&context)
        for index in 0..<6 {
            let angle = (Double(index) * 60 - 90) * .pi / 180
            let point = CGPoint(x: 100 + CGFloat(cos(angle)) * orbit, y: 96 + CGFloat(sin(angle)) * orbit)
            let circle = Path(ellipseIn: CGRect(x: point.x - 17, y: point.y - 17, width: 34, height: 34))
            if index == 0 {
                let member = FloodlightToken.memberYou.rgba(scheme)
                context.fill(circle, with: .color(member.color))
                let text = context.resolve(Text(initials).font(.custom(FloodlightFonts.face(.bold, condensed: false), fixedSize: 12))
                    .foregroundColor(FloodlightMaterial.initialsInk(member, scheme).color))
                context.draw(text, at: point, anchor: .center)
            } else {
                context.stroke(circle, with: .color(muted.color), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                if index <= selectedSlots.count {
                    let center = Path(ellipseIn: CGRect(x: point.x - 10, y: point.y - 10, width: 20, height: 20))
                    context.fill(center, with: .color(FloodlightToken.member(selectedSlots[index - 1]).rgba(scheme).color))
                } else {
                    var plus = Path(); plus.move(to: CGPoint(x: point.x - 6, y: point.y)); plus.addLine(to: CGPoint(x: point.x + 6, y: point.y))
                    plus.move(to: CGPoint(x: point.x, y: point.y - 6)); plus.addLine(to: CGPoint(x: point.x, y: point.y + 6))
                    context.stroke(plus, with: .color(muted.color), style: StrokeStyle(lineWidth: 1.7, lineCap: .round))
                }
            }
        }
    }
}

struct FloodlightCreationRulesStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 0) {
            Button { configuration.isExpanded.toggle() } label: {
                configuration.label
            }
            .buttonStyle(FloodlightRowButtonStyle())
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded { configuration.content }
        }
    }
}
