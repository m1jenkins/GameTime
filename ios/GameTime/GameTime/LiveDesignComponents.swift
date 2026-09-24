import SwiftUI

/// Keeps the approved point sizes at the default setting while following the
/// person's text-size preference, including SwiftUI environment overrides.
private struct LiveFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let italic: Bool

    init(size: CGFloat, relativeTo: Font.TextStyle?, weight: Font.Weight,
         design: Font.Design, italic: Bool) {
        let defaultStyle: Font.TextStyle = switch size {
        case ...12: .caption
        case ...15: .subheadline
        case ...17: .body
        case ...20: .title3
        case ...24: .title2
        case ...28: .title
        default: .largeTitle
        }
        _size = ScaledMetric(wrappedValue: size, relativeTo: relativeTo ?? defaultStyle)
        self.weight = weight
        self.design = design
        self.italic = italic
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight, design: design)
        content.font(italic ? font.italic() : font)
    }
}

extension View {
    func liveFont(size: CGFloat, relativeTo: Font.TextStyle? = nil,
                  weight: Font.Weight = .regular, design: Font.Design = .default,
                  italic: Bool = false) -> some View {
        modifier(LiveFontModifier(size: size, relativeTo: relativeTo,
                                  weight: weight, design: design, italic: italic))
    }
}

/// Shared native tokens for the approved Home, agreement, library and record.
struct LiveCardModifier: ViewModifier {
    var radius: CGFloat = 24
    var material = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        content.background {
            RoundedRectangle(cornerRadius: radius)
                .fill(LinearGradient(colors: material && !reduceTransparency
                    ? [.white.opacity(0.85), SignalTheme.soft.opacity(0.72)]
                    : [Color(red: 244/255, green: 246/255, blue: 248/255), SignalTheme.soft],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
                .background {
                    if material && !reduceTransparency {
                        RoundedRectangle(cornerRadius: radius).fill(.ultraThinMaterial)
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(SignalTheme.divider.opacity(material ? 0.6 : 0.3), lineWidth: 0.75) }
        }
    }
}

struct LiveMetric: View {
    let value: String
    let unit: String
    var size: CGFloat = 104
    @ScaledMetric(relativeTo: .largeTitle) private var scale = 1.0
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let fontSize = size * min(scale, 1.5)
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            Text(value).font(.system(size: fontSize, weight: .black).italic())
                .tracking(-fontSize * 0.085).monospacedDigit().padding(.trailing, 5)
                .lineLimit(1).minimumScaleFactor(0.5).layoutPriority(1)
            if !unit.isEmpty {
                Text(unit).font(.system(size: (size >= 90 ? 23 : size >= 60 ? 17 : 14) * min(scale, 1.4), weight: .medium))
                    .tracking(-0.5).foregroundStyle(SignalTheme.textSecondary).fixedSize()
            }
        }
        .foregroundStyle(SignalTheme.textPrimary)
        .accessibilityElement(children: .combine)
    }
}

struct LiveStateChip: View {
    let text: String
    var warning = false
    var neutral = false
    private var color: Color { warning ? SignalTheme.danger : neutral ? SignalTheme.textSecondary : SignalTheme.accent }
    var body: some View {
        HStack(spacing: 4) {
            if text.localizedCaseInsensitiveContains("met") || text == "Done" {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold))
            } else if text == "On track" || text == "Behind" { Circle().fill(color).frame(width: 4, height: 4) }
            Text(text).liveFont(size: 11, weight: .semibold).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(color).padding(.horizontal, 8).padding(.vertical, 5)
        .background(color.opacity(neutral ? 0.065 : 0.045), in: Capsule())
        .overlay { Capsule().strokeBorder(color.opacity(neutral ? 0 : 0.1), lineWidth: 0.8) }
    }
}

struct LivePrimaryButtonStyle: ButtonStyle {
    var height: CGFloat = 54
    var radius: CGFloat = 16
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.liveFont(size: 17, weight: .semibold)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: height).padding(.horizontal, 16)
            .foregroundStyle(enabled ? Color.white : SignalTheme.textSecondary)
            .background(enabled ? SignalTheme.accent : SignalTheme.soft, in: RoundedRectangle(cornerRadius: radius))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct LiveRoundButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 19, weight: .medium))
                .foregroundStyle(SignalTheme.textPrimary).frame(width: 44, height: 44)
                .modifier(LiveControlGlass(reduceTransparency: reduceTransparency))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
private struct LiveControlGlass: ViewModifier {
    let reduceTransparency: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular.interactive(), in: .circle)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(SignalTheme.divider.opacity(0.6), lineWidth: 0.75) }
        } else {
            content.background(SignalTheme.surface, in: Circle())
                .overlay { Circle().strokeBorder(SignalTheme.divider, lineWidth: 1) }
        }
    }
}

struct LiveAvatar: View {
    let username: String
    var actorID: UUID? = nil
    var size: CGFloat = 32
    private var fixturePortrait: String? {
        #if DEBUG
        if LiveDesignFixtures.enabled, let actorID { return LiveDesignFixtures.portraitName(for: actorID) }
        #endif
        return nil
    }
    private var position: (CGFloat, CGFloat) {
        switch fixturePortrait { case "sam": (1, 0); case "jordan": (0, 1); case "priya": (1, 1); default: (0, 0) }
    }
    var body: some View {
        Group {
            if fixturePortrait != nil {
                Image("LiveFriendAtlas").resizable().frame(width: size * 2, height: size * 2)
                    .offset(x: -position.0 * size, y: -position.1 * size)
                    .frame(width: size, height: size, alignment: .topLeading).clipped()
            } else {
                Text(initials).font(.system(size: size * 0.35, weight: .semibold))
                    .foregroundStyle(SignalTheme.textSecondary).frame(width: size, height: size)
                    .background(SignalTheme.soft)
            }
        }.clipShape(Circle()).accessibilityLabel(username)
    }
    private var initials: String {
        let words = username.split(whereSeparator: { $0.isWhitespace || $0 == "_" })
        return words.count > 1 ? words.prefix(2).compactMap(\.first).map(String.init).joined().uppercased() : String(username.prefix(2)).uppercased()
    }
}

struct LiveFaceStack: View {
    let people: [ChallengeV1.Member]
    var body: some View {
        HStack(spacing: -9) {
            ForEach(people.prefix(4)) { person in
                LiveAvatar(username: person.username, actorID: person.actorId, size: 27)
                    .padding(2).background(SignalTheme.canvas, in: Circle())
            }
        }.accessibilityElement(children: .combine)
    }
}

struct LiveProgressRail: View {
    let progress: Double?
    var height: CGFloat = 20
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(SignalTheme.progressTrack)
                if let progress {
                    Capsule().fill(SignalTheme.accent).frame(width: geometry.size.width * min(1, max(0, progress)))
                }
            }
        }.frame(height: height).accessibilityHidden(true)
    }
}

/// The UI uses acknowledged values and server result states, never a phone-only
/// total or an inferred missed goal. Fixture labels are compiled out of Release.
enum LiveChallengePresentation {
    @MainActor static func title(_ row: ChallengeV1, locale: Locale = .current) -> String {
        #if DEBUG
        if LiveDesignFixtures.enabled, let title = LiveDesignFixtures.displayTitle(for: row.id) { return title }
        #endif
        guard row.format.hasTarget else { return row.title }
        let date = DateFormatter(); date.locale = locale; date.timeZone = TimeZone(identifier: row.config.timezone); date.dateFormat = "MMMM"
        let activity = switch row.format.metric { case .distance, .timed: "runs"; case .steps: "steps"; case .exercise: "activity" }
        return date.string(from: row.config.startsAt.date) + " " + activity
    }
    static func value(_ value: Int?, metric: ChallengeV1Policy.Metric) -> String {
        guard let value else { return "—" }
        switch metric {
        case .steps: return value.formatted()
        case .distance: return (Decimal(value) / 1_000_000).formatted(.number.precision(.fractionLength(0...2)))
        case .exercise: return (Decimal(value) / 60).formatted(.number.precision(.fractionLength(0...1)))
        case .timed: return "\(value / 60):\(String(format: "%02d", value % 60))"
        }
    }
    static func money(_ cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "USD").precision(.fractionLength(cents % 100 == 0 ? 0 : 2)))
    }
    static func unit(_ metric: ChallengeV1Policy.Metric) -> String {
        switch metric { case .steps: "steps"; case .distance: "km"; case .exercise: "min"; case .timed: "min:sec" }
    }
    static func goal(_ row: ChallengeV1, actor: UUID?) -> String {
        guard let target = row.own(actor)?.target else { return "Saved result" }
        return "\(row.format.metric.display(target)) goal"
    }
    @MainActor static func state(_ row: ChallengeV1, actor: UUID?) -> String {
        guard let member = row.own(actor) else { return "No update yet" }
        return state(row, member: member)
    }
    @MainActor static func state(_ row: ChallengeV1, member: ChallengeV1.Member) -> String {
        if member.exited { return "Closed early" }
        if row.isClosed { return outcome(row, actor: member.actorId) }
        if row.status == "consent_pending" { return "Invited" }
        if row.status == "lobby_open" { return "Choosing goals" }
        if row.status == "scheduled" { return "Starts soon" }
        if row.status == "review" { return "In review" }
        guard let score = row.savedScore(member) else { return "No update yet" }
        guard let target = member.target, target > 0 else { return "Saved" }
        if row.format.metric == .timed { return score < target ? "Goal reached" : "In progress" }
        if score >= target { return "Done" }
        let total = row.config.endsAt.date.timeIntervalSince(row.config.startsAt.date)
        let elapsed = row.serverTime.date.timeIntervalSince(row.config.startsAt.date)
        if Double(score) / Double(target) >= min(1, max(0, elapsed / max(1, total))) { return "On track" }
        #if DEBUG
        if LiveDesignFixtures.enabled { return "Behind" }
        #endif
        // A saved Health total is a lower bound, not proof that all activity arrived.
        return "In progress"
    }
    static func progress(_ row: ChallengeV1, actor: UUID?) -> Double? {
        guard let member = row.own(actor), let score = row.savedScore(member), let target = member.target,
              target > 0, row.format.metric != .timed else { return nil }
        return min(1, max(0, Double(score) / Double(target)))
    }
    static func remaining(_ row: ChallengeV1, actor: UUID?) -> String {
        guard let member = row.own(actor), let score = row.savedScore(member), let target = member.target else { return "Waiting for activity" }
        if row.format.metric == .timed { return score < target ? "Goal reached" : "Time includes pauses" }
        let remaining = max(0, target - score)
        return remaining == 0 ? "Goal reached" : "\(value(remaining, metric: row.format.metric)) \(unit(row.format.metric)) to go"
    }
    static func outcome(_ row: ChallengeV1, actor: UUID?) -> String {
        guard let member = row.own(actor) else { return "Result unavailable" }
        if member.exited { return "Closed early" }
        guard let final = row.final else { return row.isClosed ? "Didn’t count" : "In review" }
        let own = final.result.participants?[member.actorId.uuidString.lowercased()] ?? final.result.own
        switch own?.status {
        case "met":
            let people = row.members.filter { $0.selected && $0.consented && !$0.exited }
            let allMet = people.count > 1 && people.allSatisfy { final.result.participants?[$0.actorId.uuidString.lowercased()]?.status == "met" }
            return allMet ? (people.count == 2 ? "Both goals met" : "All goals met") : "Your goal met"
        case "missed": return "Missed"
        case "winner": return "Result confirmed"
        case "placed": return "Result confirmed"
        default: return "Didn’t count"
        }
    }
    static func ends(_ row: ChallengeV1) -> String {
        let format = DateFormatter(); format.timeZone = TimeZone(identifier: row.config.timezone); format.dateFormat = "EEEE"
        return (row.serverTime >= row.config.endsAt ? "Ended " : "Ends ") + format.string(from: row.config.endsAt.date.addingTimeInterval(-1))
    }
    static func source(_ row: ChallengeV1) -> String {
        switch row.sourcePolicyVersion {
        case "apple_watch_outdoor_run_distance_v1": "Apple Watch outdoor runs"
        case "apple_watch_steps_v1": "Apple Watch steps"
        case "apple_watch_exercise_credit_v2": "Apple Watch Activity minutes"
        case "apple_watch_timed_run_v1": "Apple Watch outdoor runs"
        case nil: "Saved challenge activity"
        default: row.format.metric == .distance || row.format.metric == .timed ? "Apple Watch outdoor runs" : "Apple Watch activity"
        }
    }
}
