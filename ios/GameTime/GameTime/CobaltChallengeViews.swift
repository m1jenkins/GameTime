import SwiftUI

struct CobaltNotice<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(CompetitiveTrustTheme.selection, in: RoundedRectangle(cornerRadius: 12))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2).fill(CompetitiveTrustTheme.brand).frame(width: 3)
            }
    }
}

struct CobaltHomeHeader: View {
    let create: () -> Void
    let refresh: () -> Void
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            let layout = typeSize > .large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                wordmark
                if typeSize <= .large { Spacer(minLength: 0) }
                createButton
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(greeting).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline).foregroundStyle(CompetitiveTrustTheme.textSecondary)
            }
        }
    }
    private var wordmark: some View {
        Text("GameTime").modifier(CobaltDisplay(size: 40))
            .accessibilityAddTraits(.isHeader).accessibilityIdentifier("beta.home.heading")
            .accessibilityAction(named: Text("Refresh"), refresh)
    }
    @ViewBuilder private var createButton: some View {
        if #available(iOS 26, *), !reduceTransparency {
            Button(action: create) { createLabel }
                .buttonStyle(.plain).foregroundStyle(CompetitiveTrustTheme.brand)
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityLabel("New challenge")
                .accessibilityIdentifier("beta.home.create")
        } else {
            Button(action: create) { createLabel }
                .buttonStyle(.plain).foregroundStyle(CompetitiveTrustTheme.brand)
                .background(CompetitiveTrustTheme.selection, in: Capsule())
                .accessibilityLabel("New challenge").accessibilityIdentifier("beta.home.create")
        }
    }
    private var createLabel: some View {
        Label("New challenge", systemImage: "plus").font(.subheadline.weight(.medium))
            .padding(.horizontal, 14).frame(minHeight: 44).contentShape(Capsule())
    }
}

struct CobaltParticipantRow: View {
    let row: ChallengeV1
    let person: ChallengeV1.Member
    let actor: UUID?
    var onBrand = false
    var showsState = false
    var showsMetric = true
    @Environment(\.dynamicTypeSize) private var typeSize
    private var isYou: Bool { person.actorId == actor }
    private var redacted: Bool { person.exited && !isYou }
    private var name: String { isYou ? "You" : redacted ? "Former participant" : person.username }
    private var foreground: Color { onBrand ? .white : CompetitiveTrustTheme.textPrimary }
    private var secondary: Color { onBrand ? .white : CompetitiveTrustTheme.textSecondary }
    private var score: String {
        ChallengePresentation.value(person, actor: actor).map { row.format.metric.display($0) }
            ?? (person.fact == nil ? "No update yet" : "Activity unavailable")
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if typeSize.isAccessibilitySize {
                identity
                if showsMetric { value.frame(maxWidth: .infinity, alignment: .leading) }
            } else {
                HStack(spacing: 12) { identity; Spacer(minLength: 4); if showsMetric { value } }
            }
            if showsState {
                Text(person.exited ? "Left" : person.consented ? "Agreed" : person.selected ? "Selected" : "Requested")
                    .font(.subheadline).foregroundStyle(secondary)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isYou ? (onBrand ? Color.white.opacity(0.12) : CompetitiveTrustTheme.selection) : .clear,
                    in: RoundedRectangle(cornerRadius: 8))
        .overlay(alignment: .leading) {
            if isYou { RoundedRectangle(cornerRadius: 2).fill(onBrand ? .white : CompetitiveTrustTheme.brand).frame(width: 3) }
        }
        .foregroundStyle(foreground)
        .accessibilityElement(children: .combine)
    }
    private var identity: some View {
        HStack(spacing: 10) {
            if !row.format.hasTarget {
                Text(ChallengePresentation.rank(person, in: row, actor: actor).map(String.init) ?? "—")
                    .font(.body.bold().monospacedDigit()).frame(minWidth: 18)
                    .accessibilityLabel(ChallengePresentation.rank(person, in: row, actor: actor).map { "Rank \($0)" } ?? "Not ranked")
            }
            if !typeSize.isAccessibilitySize {
                Group {
                    if redacted { Image(systemName: "person") }
                    else { Text(String(person.username.prefix(1)).uppercased()) }
                }
                .font(.subheadline.bold()).frame(width: 32, height: 32)
                .foregroundStyle(onBrand ? CompetitiveTrustTheme.feature : CompetitiveTrustTheme.textPrimary)
                .background(onBrand ? Color.white.opacity(0.88) : CompetitiveTrustTheme.progressTrack, in: Circle())
                .accessibilityHidden(true)
            }
            Text(name).font(.body.weight(isYou ? .bold : .medium))
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
        }
    }
    private var value: some View {
        Group {
            if !redacted, let value = ChallengePresentation.value(person, actor: actor) {
                CobaltMetricValue(value: value, metric: row.format.metric, size: onBrand ? 32 : 30)
            } else {
                Text(redacted ? "Activity hidden" : score).font(.body.weight(.semibold))
            }
        }.multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct CobaltFeaturedChallenge: View {
    let row: ChallengeV1
    let actor: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(ChallengePresentation.featuredTitle(row)).modifier(CobaltDisplay(size: 48))
                .fixedSize(horizontal: false, vertical: true)
            let friends = row.members.filter { !$0.exited && $0.actorId != actor }.count
            Text(friends == 1 ? "You + 1 friend" : "You + \(friends) friends")
                .font(.body.weight(.medium))
            Text("Ends \(ChallengePresentation.endDate(row))").font(.subheadline)
            if row.format.metric == .timed, let distance = row.config.distanceMm {
                Text("Whole run: \(ChallengeV1Policy.Metric.distance.display(distance))").font(.subheadline)
            }
            if row.format.competition == .leaderboard && !row.socialHidden {
                VStack(spacing: 0) {
                    ForEach(row.rankedMembers) { member in
                        CobaltParticipantRow(row: row, person: member, actor: actor, onBrand: true)
                    }
                }.padding(.top, 8)
            } else if let own = row.own(actor) {
                CobaltGoalProgress(row: row, member: own, actor: actor, onBrand: true)
            }
            Text("\(challengeMoney(row.config.amountCents)) simulated each · No real money moves")
                .font(.caption).padding(.top, 4)
        }
        .foregroundStyle(.white).padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CompetitiveTrustTheme.feature, in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }
}

struct CobaltGoalProgress: View {
    let row: ChallengeV1
    let member: ChallengeV1.Member
    let actor: UUID?
    var onBrand = false
    private var foreground: Color { onBrand ? .white : CompetitiveTrustTheme.textPrimary }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !["lobby_open", "consent_pending", "scheduled", "published_open"].contains(row.status) {
                if let value = ChallengePresentation.value(member, actor: actor) {
                    CobaltMetricValue(value: value, metric: row.format.metric,
                                      target: row.format.metric == .timed ? nil : member.target)
                } else {
                    Text(member.fact == nil ? "No update yet" : "Activity unavailable").font(.title3.bold())
                }
            }
            if let target = member.target,
               row.format.metric == .timed || ChallengePresentation.value(member, actor: actor) == nil {
                Text(row.format.metric == .timed ? "Time to beat: \(row.format.metric.display(target))" : "Goal: \(row.format.metric.display(target))")
                    .font(.subheadline)
            } else if row.format.hasTarget && member.target == nil {
                Text("Goal not chosen").font(.subheadline)
            }
            if let ratio = ChallengePresentation.progress(member, in: row, actor: actor) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2).fill(onBrand ? Color.white.opacity(0.25) : CompetitiveTrustTheme.progressTrack)
                        RoundedRectangle(cornerRadius: 2).fill(onBrand ? .white : CompetitiveTrustTheme.brand)
                            .frame(width: geometry.size.width * ratio)
                    }
                }.frame(height: 12).accessibilityHidden(true)
            }
            if row.format.metric == .timed, let distance = row.config.distanceMm {
                Text("Whole run: \(ChallengeV1Policy.Metric.distance.display(distance))").font(.subheadline)
                Text("Finish strictly under your agreed time. Pauses count.").font(.footnote)
            }
        }.foregroundStyle(foreground)
    }
}

struct CobaltChallengeSummary: View {
    let row: ChallengeV1
    let actor: UUID?
    @Environment(\.dynamicTypeSize) private var typeSize
    private var rowLayout: AnyLayout {
        typeSize > .large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) :
            AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
    }
    private var personal: Bool { row.format.mode == .personal && row.own(actor)?.exited == false }
    private var title: String {
        if personal && row.format.metric == .exercise { return "Your exercise goal" }
        return row.title
    }
    private var nextGoal: String {
        guard let target = row.own(actor)?.target else { return row.title }
        switch row.format.metric {
        case .distance: return "Run \(row.format.metric.display(target))"
        case .steps: return "\(row.format.metric.display(target))"
        case .exercise: return "Exercise for \(CobaltMetricValue.compact(target, metric: .exercise))"
        case .timed: return row.title
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if personal && row.status == "scheduled" && row.format.metric != .timed {
                Text("Your next goal").font(.subheadline).foregroundStyle(CompetitiveTrustTheme.textSecondary)
                rowLayout {
                    nextTitle
                    if typeSize <= .large { Spacer(minLength: 0) }
                    HStack { dates; chevron }
                }
            } else {
                rowLayout {
                    heading
                    if typeSize <= .large { Spacer(minLength: 0) }
                    dates
                }
                if !["active", "scheduled"].contains(row.status) || row.own(actor)?.exited == true {
                    Text(row.own(actor)?.exited == true ? "You left this challenge" : row.statusText)
                        .font(.subheadline).foregroundStyle(CompetitiveTrustTheme.textSecondary)
                }
                if personal && row.status == "active", let own = row.own(actor) {
                    CobaltGoalProgress(row: row, member: own, actor: actor)
                } else if let own = row.own(actor) {
                    if let value = ChallengePresentation.value(own, actor: actor) {
                        Text("Your activity: \(row.format.metric.display(value))").font(.body.monospacedDigit())
                    }
                    if row.format.hasTarget, let target = own.target {
                        Text("Your goal: \(row.format.metric.display(target))").font(.body)
                    }
                }
            }
        }.padding(.vertical, 12).foregroundStyle(CompetitiveTrustTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(CompetitiveTrustTheme.divider).frame(height: 1) }
            .accessibilityElement(children: .combine)
            .accessibilityValue(row.status == "scheduled" ? "Upcoming" : "")
    }
    private var nextTitle: some View { Text(nextGoal).font(.title2.bold()).fixedSize(horizontal: false, vertical: true) }
    private var heading: some View { Text(title).font(.headline).fixedSize(horizontal: false, vertical: true) }
    private var dates: some View {
        Text(ChallengePresentation.dates(row)).font(.subheadline)
            .foregroundStyle(CompetitiveTrustTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
    }
    private var chevron: some View { Image(systemName: "chevron.right").font(.footnote.bold()).accessibilityHidden(true) }
}

struct CobaltMetricValue: View {
    let value: Int
    let metric: ChallengeV1Policy.Metric
    var size: CGFloat = 54
    var target: Int? = nil
    private static func parts(_ value: Int, metric: ChallengeV1Policy.Metric) -> (String, String) {
        switch metric {
        case .steps: (value.formatted(), "steps")
        case .distance: (NSDecimalNumber(decimal: Decimal(value) / 1_000_000).stringValue, "km")
        case .exercise, .timed:
            value % 60 == 0 ? ((value / 60).formatted(), "min") : ("\(value / 60):\(String(format: "%02d", value % 60))", "min:sec")
        }
    }
    static func compact(_ value: Int, metric: ChallengeV1Policy.Metric) -> String {
        let parts = parts(value, metric: metric)
        return "\(parts.0) \(parts.1)"
    }
    private var suffix: String {
        let current = Self.parts(value, metric: metric)
        guard let target else { return current.1 }
        let goal = Self.parts(target, metric: metric)
        return (current.1 == goal.1 ? "" : current.1 + " ") + "of \(goal.0) \(goal.1)"
    }
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 6) { number; unit }
            VStack(alignment: .leading, spacing: 4) { number; unit }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel(metric.display(value) + (target.map { " of " + metric.display($0) } ?? ""))
    }
    private var number: some View { Text(Self.parts(value, metric: metric).0).modifier(CobaltDisplay(size: size)) }
    private var unit: some View { Text(suffix).font(target == nil ? .subheadline : .title3) }
}

struct CobaltNavigationMaterial: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if #available(iOS 26, *), !reduceTransparency {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.background(CompetitiveTrustTheme.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay { RoundedRectangle(cornerRadius: 20).stroke(CompetitiveTrustTheme.divider) }
        }
    }
}
