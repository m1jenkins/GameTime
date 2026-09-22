import SwiftUI
import UIKit

/// Native button styles supply the optical treatment; solid modes retain shape and size.
struct SignalNativeAction: ViewModifier {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency, contrast != .increased {
            if primary { content.foregroundStyle(enabled ? SignalTheme.onAccent : SignalTheme.textPrimary).buttonStyle(.glassProminent).tint(SignalTheme.accent).buttonBorderShape(.capsule) }
            else { content.buttonStyle(.glass).buttonBorderShape(.capsule) }
        } else {
            content.buttonStyle(SignalSolidCapsuleStyle(primary: primary))
        }
    }
}
private struct SignalSolidCapsuleStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 16).padding(.vertical, 8)
            .foregroundStyle(enabled ? (primary ? SignalTheme.onAccent : SignalTheme.textPrimary) : SignalTheme.textSecondary)
            .background(enabled && primary ? SignalTheme.accent : SignalTheme.soft, in: Capsule())
            .overlay(Capsule().stroke(enabled && primary ? SignalTheme.accent : SignalTheme.divider))
            .opacity(enabled && configuration.isPressed ? 0.8 : 1)
    }
}
struct SignalNavigationAction: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) { content }
        else {
            content.buttonStyle(.plain).frame(width: 44, height: 44)
                .background(SignalTheme.soft, in: Circle()).overlay(Circle().stroke(SignalTheme.divider))
        }
    }
}
struct SignalCircleAction: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency, contrast != .increased {
            content.buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            content.padding(8).buttonStyle(.plain)
                .background(SignalTheme.soft, in: Circle()).overlay(Circle().stroke(SignalTheme.divider))
        }
    }
}
struct SignalActivityChoices: View {
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 21
    @ScaledMetric(relativeTo: .body) private var symbolWidth: CGFloat = 25
    @Binding var selection: ChallengeV1Policy.Metric
    var metrics: [ChallengeV1Policy.Metric] = Array(ChallengeV1Policy.Metric.allCases)
    var title: (ChallengeV1Policy.Metric) -> String = { $0.title }
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: textSize >= .xxxLarge ? 1 : 2), spacing: 10) {
            ForEach(metrics, id: \.self) { metric in
                Button { selection = metric } label: {
                    HStack(spacing: 9) {
                        Image(systemName: metric.symbol)
                            .font(.system(size: symbolSize, weight: .regular))
                            .symbolRenderingMode(.monochrome)
                            .frame(width: symbolWidth).accessibilityHidden(true)
                        Text(title(metric)).font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.foregroundStyle(selection == metric ? SignalCreationTheme.accent : SignalCreationTheme.textSecondary)
                        .padding(.horizontal, 13).padding(.vertical, 15)
                        .frame(maxWidth: .infinity, minHeight: 58)
                        .background(selection == metric ? SignalCreationTheme.selection : SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 17))
                        .overlay {
                            RoundedRectangle(cornerRadius: 17)
                                .stroke(selection == metric ? SignalCreationTheme.accent : SignalCreationTheme.divider.opacity(0.5), lineWidth: selection == metric ? 1.5 : 0.5)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 17))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == metric ? .isSelected : [])
                    .accessibilityIdentifier("beta.create.metric." + metric.rawValue)
            }
        }.accessibilityElement(children: .contain).accessibilityLabel("Activity")
    }
}
struct SignalNumberEntry: View {
    @Binding var text: String
    let title: String
    let unit: String
    let id: String
    let keyboard: UIKeyboardType
    var prefix = ""
    var focusChanged: ((Bool) -> Void)? = nil
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 84
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title).font(.subheadline.weight(.medium)).foregroundStyle(SignalCreationTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if focused {
                    Button("Done") { focused = false }.accessibilityIdentifier("beta.create.input.done").font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44).buttonStyle(.plain).foregroundStyle(SignalCreationTheme.accent)
                }
            }.frame(minHeight: 44)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !prefix.isEmpty { Text(prefix).accessibilityHidden(true) }
                TextField("—", text: $text).keyboardType(keyboard).textFieldStyle(.plain)
                    .accessibilityLabel(title).accessibilityHint(unit).accessibilityIdentifier(id)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done).focused($focused).onSubmit { focused = false }
            }.font(.system(size: numberSize, weight: .heavy).italic()).monospacedDigit().tracking(-2)
                .padding(.trailing, 6).padding(.bottom, 8)
            Text(unit).font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(SignalCreationTheme.divider).frame(height: 1) }
        }.foregroundStyle(SignalCreationTheme.textPrimary)
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 18)
            .background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 24))
            .id(id)
            .onChange(of: focused) { _, value in focusChanged?(value) }
    }
    private var numberSize: CGFloat {
        let length = max(1, text.count + prefix.count)
        return min(size, 120) * max(0.5, min(1, 5 / CGFloat(length)))
    }
}

/// A goal stays editable in its original units; formatting never rewrites the draft.
struct SignalCreationGoalEntry: View {
    @Binding var text: String
    let metric: ChallengeV1Policy.Metric
    let duration: Int?
    let sourceLabel: String?
    let id: String
    var focusChanged: ((Bool) -> Void)? = nil
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var distanceSize: CGFloat = 108
    @ScaledMetric(relativeTo: .largeTitle) private var stepsSize: CGFloat = 68
    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 76
    @ScaledMetric(relativeTo: .title2) private var unitSize: CGFloat = 25
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var footerSize: CGFloat = 12
    @State private var availableWidth: CGFloat = 280
    @FocusState private var focused: Bool

    private var title: String {
        switch metric {
        case .steps: "Your steps"
        case .distance: "Your distance"
        case .exercise: "Your activity minutes"
        case .timed: "Time to beat"
        }
    }
    private var unit: String {
        switch metric {
        case .steps: "steps"
        case .distance: "km"
        case .exercise, .timed: "min:sec"
        }
    }
    private var keyboard: UIKeyboardType {
        switch metric {
        case .steps: .numberPad
        case .distance: .decimalPad
        case .exercise, .timed: .numbersAndPunctuation
        }
    }
    private var period: String {
        guard let duration else { return "During your selected dates" }
        return duration == 1 ? "Over 1 day" : "Over \(duration) days"
    }
    private var baseSize: CGFloat {
        min(metric == .distance ? distanceSize : metric == .steps ? stepsSize : timeSize, 140)
    }
    private var fieldSpace: CGFloat {
        guard !typeSize.isAccessibilitySize else { return availableWidth }
        let width = (unit as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: unitSize, weight: .medium)]).width
        return max(44, availableWidth - width - 10)
    }
    private var numberSize: CGFloat {
        // Long values shrink to fit before the editable field scrolls. The raw
        // text and its allowed precision remain owned by the creation draft.
        max(24, min(baseSize, baseSize * fieldSpace / max(1, textWidth(at: baseSize) + 8)))
    }
    private func textWidth(at size: CGFloat) -> CGFloat {
        let font = UIFont.monospacedDigitSystemFont(ofSize: size, weight: .heavy)
        let descriptor = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(.traitItalic)) ?? font.fontDescriptor
        return ((text.isEmpty ? "—" : text) as NSString).size(withAttributes: [
            .font: UIFont(descriptor: descriptor, size: size), .kern: tracking(at: size)
        ]).width
    }
    private func tracking(at size: CGFloat) -> CGFloat { size * (metric == .distance ? -0.085 : -0.065) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(title).font(.system(size: labelSize, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if focused {
                    Button("Done") { focused = false }
                        .font(.system(size: labelSize, weight: .semibold))
                        .frame(minWidth: 44, minHeight: 44).buttonStyle(.plain)
                        .foregroundStyle(SignalCreationTheme.accent)
                        .accessibilityIdentifier("beta.create.input.done")
                } else {
                    Image(systemName: "pencil").font(.system(size: 17, weight: .regular))
                        .accessibilityHidden(true)
                }
            }.foregroundStyle(SignalCreationTheme.textSecondary)
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) { numberField; unitLabel }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) { numberField; unitLabel }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4).padding(.bottom, 10)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { availableWidth = max(44, $0) }
            let footerLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            footerLayout {
                Text(period).frame(maxWidth: .infinity, alignment: .leading)
                if let sourceLabel { Text(sourceLabel) }
            }
            .font(.system(size: footerSize)).foregroundStyle(SignalCreationTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)
            .overlay(alignment: .top) { Rectangle().fill(SignalCreationTheme.divider).frame(height: 1) }
        }
        .padding(.horizontal, 20).padding(.top, 19).padding(.bottom, 16)
        .background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 24))
        .overlay { RoundedRectangle(cornerRadius: 24).stroke(SignalCreationTheme.divider.opacity(0.35), lineWidth: 0.5) }
        .id(id)
        .onChange(of: focused) { _, value in focusChanged?(value) }
    }
    private var numberField: some View {
        TextField("—", text: $text)
            .keyboardType(keyboard).textFieldStyle(.plain)
            .font(.system(size: numberSize, weight: .heavy).italic()).monospacedDigit()
            .tracking(tracking(at: numberSize))
            .foregroundStyle(SignalCreationTheme.textPrimary)
            .frame(width: min(fieldSpace, max(44, textWidth(at: numberSize) + 8)))
            .frame(minHeight: 44)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(.done).focused($focused).onSubmit { focused = false }
            .accessibilityLabel(title).accessibilityHint(metric.inputHelp).accessibilityIdentifier(id)
    }
    private var unitLabel: some View {
        Text(unit).font(.system(size: unitSize, weight: .medium)).tracking(-0.6)
            .foregroundStyle(SignalCreationTheme.textSecondary).fixedSize()
            .accessibilityHidden(true)
    }
}

struct SignalCreationProgress: View {
    let labels: [String]
    let current: Int
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption) private var circleSize: CGFloat = 19
    @ScaledMetric(relativeTo: .caption) private var labelSize: CGFloat = 11
    @ScaledMetric(relativeTo: .caption2) private var numberSize: CGFloat = 10
    private var selected: Int { min(max(current, 0), max(labels.count - 1, 0)) }

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(labels.indices, id: \.self) { index in step(index, singleLine: false) }
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        ForEach(labels.indices, id: \.self) { index in
                            step(index, singleLine: true).layoutPriority(1)
                            if index < labels.count - 1 {
                                Rectangle().fill(SignalCreationTheme.divider)
                                    .frame(minWidth: 12, maxWidth: .infinity).frame(height: 1)
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(labels.indices, id: \.self) { index in step(index, singleLine: false) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(labels.isEmpty ? "" : "Step \(selected + 1) of \(labels.count), \(labels[selected])")
    }

    private func step(_ index: Int, singleLine: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if index < selected {
                    Image(systemName: "checkmark").font(.system(size: numberSize, weight: .semibold))
                        .symbolRenderingMode(.monochrome)
                } else {
                    Text(String(index + 1)).font(.system(size: numberSize, weight: .semibold)).monospacedDigit()
                }
            }
            .frame(width: circleSize, height: circleSize)
            .foregroundStyle(index == selected ? SignalCreationTheme.onAccent : index < selected ? SignalCreationTheme.accent : SignalCreationTheme.textSecondary)
            .background(index == selected ? SignalCreationTheme.accent : index < selected ? SignalCreationTheme.selection : SignalCreationTheme.soft, in: Circle())
            Text(labels[index]).font(.system(size: labelSize, weight: index == selected ? .semibold : .medium))
                .foregroundStyle(index <= selected ? SignalCreationTheme.accent : SignalCreationTheme.textSecondary)
                .lineLimit(singleLine ? 1 : nil)
                .fixedSize(horizontal: singleLine, vertical: true)
        }
    }
}

struct SignalCreationFact: View {
    let symbol: String
    let title: String
    let detail: String
    @ScaledMetric(relativeTo: .body) private var symbolSize: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var symbolWidth: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: symbolSize, weight: .regular))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(SignalCreationTheme.accent)
                .frame(width: symbolWidth, height: symbolWidth)
                .background(SignalCreationTheme.selection, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.caption).foregroundStyle(SignalCreationTheme.textSecondary)
                Text(detail).font(.subheadline.weight(.semibold)).foregroundStyle(SignalCreationTheme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [SignalCreationTheme.surface, SignalCreationTheme.soft], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).stroke(SignalCreationTheme.divider.opacity(0.65), lineWidth: 0.75) }
        .accessibilityElement(children: .combine)
    }
}

struct SignalCreationMetric: View {
    let value: Int
    let metric: ChallengeV1Policy.Metric
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 80
    @Environment(\.dynamicTypeSize) private var typeSize
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Your goal").font(.subheadline.weight(.medium)).foregroundStyle(SignalCreationTheme.textSecondary)
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { numberLabel; unitLabel }
                } else {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) { numberLabel.fixedSize(); unitLabel }
                        VStack(alignment: .leading, spacing: 4) { numberLabel; unitLabel }
                    }
                }
            }
            .accessibilityElement(children: .ignore).accessibilityLabel(metric.display(value))
        }
        .foregroundStyle(SignalCreationTheme.textPrimary)
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .background(SignalCreationTheme.soft, in: RoundedRectangle(cornerRadius: 24))
    }
    private var numberLabel: some View {
        Text(number).font(.system(size: min(size, 120), weight: .heavy).italic())
            .monospacedDigit().tracking(-2).padding(.trailing, 5)
            .lineLimit(1).minimumScaleFactor(0.25)
    }
    private var unitLabel: some View {
        Text(unit).font(.title3.weight(.medium)).foregroundStyle(SignalCreationTheme.textSecondary)
            .fixedSize()
    }
}
enum SignalTimeZone {
    static func name(_ id: String) -> String {
        guard let zone = TimeZone(identifier: id) else { return id }
        let city = id.split(separator: "/").last.map(String.init)?.replacingOccurrences(of: "_", with: " ") ?? id
        let name = zone.localizedName(for: .generic, locale: .current) ?? city
        return city == name || id == "UTC" ? name : "\(name) · \(city)"
    }
}

enum ChallengeTimedDistanceCopy {
    /// The real timed source compares raw distance before normalization. Keep
    /// the 102% boundary exact even when it falls between whole millimetres.
    static func range(_ millimetres: Int) -> String {
        let upperKilometres = Decimal(millimetres) * 102 / 100_000_000
        return ChallengeV1Policy.Metric.distance.display(millimetres)
            + " to " + NSDecimalNumber(decimal: upperKilometres).stringValue + " km"
    }
}

struct SignalTimeZonePicker: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var zones: [String] {
        let all = Set(TimeZone.knownTimeZoneIdentifiers + [selection, "UTC"]).sorted { SignalTimeZone.name($0) < SignalTimeZone.name($1) }
        return search.isEmpty ? all : all.filter { SignalTimeZone.name($0).localizedCaseInsensitiveContains(search) || $0.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List(zones, id: \.self) { id in
                Button { selection = id; dismiss() } label: {
                    HStack {
                        Text(SignalTimeZone.name(id)).foregroundStyle(SignalTheme.textPrimary)
                        Spacer()
                        if selection == id { Image(systemName: "checkmark").accessibilityHidden(true) }
                    }.frame(minHeight: 44)
                }.accessibilityAddTraits(selection == id ? .isSelected : []).accessibilityIdentifier("beta.create.zone." + id)
            }.searchable(text: $search, prompt: "Search cities or time zones")
                .listStyle(.plain).signalScreenBackground().navigationTitle("Time zone")
                .navigationBarTitleDisplayMode(.inline).tint(SignalTheme.accent)
    }
}

/// Edits stay local until the person saves, so dismissing this sheet leaves the agreement intact.
struct SignalAmountEditor: View {
    @State private var value: String
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    let save: (String) -> Void

    init(value: String, save: @escaping (String) -> Void) {
        _value = State(initialValue: value)
        self.save = save
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    SignalNumberEntry(text: $value, title: "Simulated amount", unit: "USD · $1–$500", id: "beta.create.amount", keyboard: .numberPad, prefix: "$")
                    Text("No real money moves. Nothing can be paid out or redeemed.").font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                    if let error { Text(error).foregroundStyle(SignalCreationTheme.danger).accessibilityIdentifier("beta.create.amount.error") }
                    Button {
                        guard ChallengeCreationDraft.integer(value, in: 1...500) != nil else {
                            error = "Enter a whole-dollar amount from $1 to $500."
                            return
                        }
                        save(value)
                        dismiss()
                    } label: { Text("Save amount").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
                    .buttonStyle(SignalCreationPrimaryStyle()).accessibilityIdentifier("beta.create.amount.save")
                }.padding(SignalCreationTheme.contentInset)
            }.background(SignalCreationTheme.canvas).foregroundStyle(SignalCreationTheme.textPrimary)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Amount").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(SignalCreationTheme.accent)
    }
}
