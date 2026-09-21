import SwiftUI

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
    @ScaledMetric(relativeTo: .body) private var symbolWidth: CGFloat = 24
    @Binding var selection: ChallengeV1Policy.Metric
    @Environment(\.dynamicTypeSize) private var textSize
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: textSize.isAccessibilitySize ? 1 : 2), spacing: 6) {
            ForEach(ChallengeV1Policy.Metric.allCases, id: \.self) { metric in
                Button { selection = metric } label: {
                    HStack(spacing: 8) {
                        Image(systemName: metric.symbol).frame(width: symbolWidth).accessibilityHidden(true)
                        Text(metric.title).font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading)
                        if selection == metric { Image(systemName: "checkmark").font(.caption.bold()).accessibilityHidden(true) }
                    }.foregroundStyle(selection == metric ? SignalTheme.accent : SignalTheme.textPrimary)
                        .padding(12).frame(maxWidth: .infinity, minHeight: 56)
                        .background(selection == metric ? SignalTheme.selection : .clear, in: RoundedRectangle(cornerRadius: 20))
                        .overlay { if selection == metric { RoundedRectangle(cornerRadius: 20).stroke(SignalTheme.accent, lineWidth: 1) } }
                        .contentShape(RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).accessibilityAddTraits(selection == metric ? .isSelected : [])
                    .accessibilityIdentifier("beta.create.metric." + metric.rawValue)
            }
        }.padding(6).modifier(SignalControlMaterial(interactive: false, cornerRadius: 26))
            .accessibilityElement(children: .contain).accessibilityLabel("Activity")
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
    @ScaledMetric(relativeTo: .largeTitle) private var size: CGFloat = 64
    @FocusState private var focused: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.headline).foregroundStyle(SignalTheme.textSecondary)
                Spacer()
                if focused {
                    Button("Done") { focused = false }.accessibilityIdentifier("beta.create.input.done").font(.subheadline.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44).buttonStyle(.plain).foregroundStyle(SignalTheme.accent)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if !prefix.isEmpty { Text(prefix).accessibilityHidden(true) }
                TextField("—", text: $text).keyboardType(keyboard).textFieldStyle(.plain)
                    .accessibilityLabel(title).accessibilityHint(unit).accessibilityIdentifier(id)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done).focused($focused).onSubmit { focused = false }
            }.font(.system(size: min(size, 100), weight: .medium)).monospacedDigit()
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(SignalTheme.divider).frame(height: 1) }
            Text(unit).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
        }.foregroundStyle(SignalTheme.textPrimary)
            .id(id)
            .onChange(of: focused) { _, value in focusChanged?(value) }
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
                    Text("No real money moves. Nothing can be paid out or redeemed.").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                    if let error { Text(error).foregroundStyle(SignalTheme.danger).accessibilityIdentifier("beta.create.amount.error") }
                    Button {
                        guard ChallengeCreationDraft.integer(value, in: 1...500) != nil else {
                            error = "Enter a whole-dollar amount from $1 to $500."
                            return
                        }
                        save(value)
                        dismiss()
                    } label: { Text("Save amount").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }
                    .modifier(SignalNativeAction(primary: true)).accessibilityIdentifier("beta.create.amount.save")
                }.padding(SignalTheme.contentInset)
            }.background(SignalTheme.canvas).foregroundStyle(SignalTheme.textPrimary)
                .scrollDismissesKeyboard(.interactively)
                .navigationTitle("Amount").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }.tint(SignalTheme.accent)
    }
}
