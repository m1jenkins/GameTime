import SwiftUI

struct SignalNotice<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 9))
    }
}

struct SignalHomeHeader: View {
    let create: () -> Void
    let refresh: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text("GameTime").font(.title2.weight(.semibold)).tracking(-0.6)
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("beta.home.heading")
                    .accessibilityAction(named: Text("Refresh"), refresh)
                Spacer(minLength: 12)
                Button(action: create) {
                    Image(systemName: "plus").font(.title3)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }.buttonStyle(.plain).foregroundStyle(SignalTheme.textPrimary)
                    .modifier(SignalControlMaterial(cornerRadius: 22))
                    .accessibilityLabel("New challenge").accessibilityIdentifier("beta.home.create")
            }
            let layout = typeSize > .large
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout {
                Text("Today").font(.largeTitle.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if typeSize <= .large { Spacer(minLength: 0) }
                Text(Date(), format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            }
        }.padding(.bottom, 4)
    }
}

struct SignalParticipantRow: View {
    let row: ChallengeV1
    let person: ChallengeV1.Member
    let actor: UUID?
    var showsState = false
    var showsMetric = true
    @Environment(\.dynamicTypeSize) private var typeSize
    private var isYou: Bool { person.actorId == actor }
    private var redacted: Bool { person.exited && !isYou }
    private var name: String { isYou ? "You" : redacted ? "Former participant" : person.username }
    private var foreground: Color { SignalTheme.textPrimary }
    private var secondary: Color { SignalTheme.textSecondary }
    private var score: String {
        (row.format.usesReceivedScores ? row.savedScore(person) : ChallengePresentation.value(person, actor: actor)).map { row.format.metric.display($0) }
            ?? (row.format.usesReceivedScores ? "Unranked" : person.fact == nil ? "No update yet" : "Activity unavailable")
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
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(foreground)
        .accessibilityElement(children: .combine)
    }
    private var identity: some View {
        HStack(spacing: 10) {
            if row.showsRanking {
                Text(ChallengePresentation.rank(person, in: row, actor: actor).map(String.init) ?? "—")
                    .font(.body.bold().monospacedDigit()).frame(minWidth: 18)
                    .accessibilityLabel(ChallengePresentation.rank(person, in: row, actor: actor).map { "Rank \($0)" } ?? "Not ranked")
            }
            Text(name).font(.body.weight(isYou ? .bold : .medium))
                .fixedSize(horizontal: false, vertical: true).layoutPriority(1)
        }
    }
    private var value: some View {
        Group {
            if !redacted, let value = (row.format.usesReceivedScores ? row.savedScore(person) : ChallengePresentation.value(person, actor: actor)) {
                SignalMetricValue(value: value, metric: row.format.metric, size: 24)
            } else {
                Text(redacted ? "Activity hidden" : score).font(.body.weight(.semibold))
            }
        }.multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct SignalFeaturedChallenge: View {
    let row: ChallengeV1
    let actor: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ChallengePresentation.featuredTitle(row)).font(.title2.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            let friends = row.members.filter { !$0.exited && $0.actorId != actor }.count
            Text(friends == 1 ? "You + 1 friend" : "You + \(friends) friends")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            Text("Ends \(ChallengePresentation.endDate(row))")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            if row.format.metric == .timed, let distance = row.config.distanceMm {
                Text("Whole run: \(ChallengeV1Policy.Metric.distance.display(distance))").font(.subheadline)
            }
            if row.showsRanking && !row.socialHidden {
                VStack(spacing: 0) {
                    ForEach(row.rankedMembers) { member in
                        SignalParticipantRow(row: row, person: member, actor: actor)
                        Divider().overlay(SignalTheme.divider)
                    }
                }
            } else if let own = row.own(actor) {
                SignalGoalProgress(row: row, member: own, actor: actor)
            }
            Text("\(challengeMoney(row.config.amountCents)) simulated each · No real money moves")
                .font(.caption).foregroundStyle(SignalTheme.textSecondary)
        }
        .foregroundStyle(SignalTheme.textPrimary).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SignalTheme.canvas)
        .accessibilityElement(children: .combine)
    }
}

struct SignalGoalProgress: View {
    var onAccent = false
    let row: ChallengeV1
    let member: ChallengeV1.Member
    let actor: UUID?
    private var foreground: Color { onAccent ? SignalTheme.onAccent : SignalTheme.textPrimary }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !["lobby_open", "consent_pending", "scheduled", "published_open"].contains(row.status) {
                if let value = ChallengePresentation.value(member, actor: actor) {
                    SignalMetricValue(value: value, metric: row.format.metric,
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
                        RoundedRectangle(cornerRadius: 2).fill(onAccent ? SignalTheme.onAccent.opacity(0.25) : SignalTheme.progressTrack)
                        RoundedRectangle(cornerRadius: 2).fill(onAccent ? SignalTheme.onAccent : SignalTheme.accent)
                            .frame(width: geometry.size.width * ratio)
                    }
                }.frame(height: 5).accessibilityHidden(true)
            }
            if row.format.metric == .timed, let distance = row.config.distanceMm {
                Text("Whole run: \(ChallengeV1Policy.Metric.distance.display(distance))").font(.subheadline)
                Text(row.format.usesReceivedScores
                    ? "Your fastest eligible saved run counts. Pauses count."
                    : "Finish strictly under your agreed time. Pauses count.").font(.footnote)
            }
        }.foregroundStyle(foreground)
    }
}

struct SignalChallengeSummary: View {
    let row: ChallengeV1
    let actor: UUID?
    private var title: String { row.title }
    private var own: ChallengeV1.Member? { row.own(actor) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.footnote.bold()).foregroundStyle(SignalTheme.textSecondary)
                    .accessibilityHidden(true)
            }
            if let own, !own.exited {
                if ["active", "syncing"].contains(row.status), let value = ChallengePresentation.value(own, actor: actor) {
                    SignalMetricValue(value: value, metric: row.format.metric, size: 32,
                                      target: row.format.metric == .timed ? nil : own.target)
                } else if ["scheduled", "consent_pending", "lobby_open"].contains(row.status), let target = own.target {
                    Text(row.format.metric == .timed ? "Time to beat: \(row.format.metric.display(target))" : row.format.metric.display(target))
                        .font(.title2.weight(.medium)).monospacedDigit().fixedSize(horizontal: false, vertical: true)
                } else if ["active", "syncing"].contains(row.status) {
                    Text(own.fact == nil ? "No update yet" : "Activity unavailable").font(.subheadline)
                }
            }
            Text(ChallengePresentation.dates(row)).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            if row.status != "active" && row.status != "scheduled" || own?.exited == true {
                Text(own?.exited == true ? "You left this challenge" : row.statusText)
                    .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            }
        }.padding(.vertical, 20).foregroundStyle(SignalTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Rectangle().fill(SignalTheme.divider).frame(height: 1) }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityValue(row.status == "scheduled" ? "Upcoming" : "")
    }
}

struct SignalMetricValue: View {
    let value: Int
    let metric: ChallengeV1Policy.Metric
    var size: CGFloat = 64
    var target: Int? = nil
    private static func parts(_ value: Int, metric: ChallengeV1Policy.Metric) -> (String, String) {
        switch metric {
        case .steps: (value.formatted(), "steps")
        case .distance: ((Decimal(value) / 1_000_000).formatted(.number.precision(.fractionLength(0...6))), "km")
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
    private var number: some View { ViewThatFits(in: .horizontal) {
            Text(Self.parts(value, metric: metric).0).modifier(SignalMetricTypography(size: size)).fixedSize()
            Text(Self.parts(value, metric: metric).0).font(.largeTitle.weight(.medium)).monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        } }
    private var unit: some View { Text(suffix).font(target == nil ? .subheadline : .title3) }
}


/// Dates retain the actual agreed boundaries, including the exclusive end.
/// The native layout reflows instead of copying fixed browser columns.
struct SignalDateSpan: View {
    static func duration(_ days: Int) -> String { days == 1 ? "1 full day" : "\(days) full days" }
    let window: ChallengeV1.Window
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    boundary("Starts", date: window.startsAt)
                    Image(systemName: "arrow.right").padding(.top, 24).accessibilityHidden(true)
                    boundary("Ends, not included", date: window.endsAt)
                }
                VStack(alignment: .leading, spacing: 16) {
                    boundary("Starts", date: window.startsAt)
                    boundary("Ends, not included", date: window.endsAt)
                }
            }
            Text("\(Self.duration(window.days)) · \(SignalTimeZone.name(window.timezone))")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 8)
    }
    private func boundary(_ title: String, date: ChallengeInstant) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(SignalTheme.textSecondary)
            Text(dateLabel(date, template: "MMM d yyyy"))
                .font(.headline)
            Text(dateLabel(date, template: "h:mm a z")).font(.caption).foregroundStyle(SignalTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .ignore)
            .accessibilityLabel(title + ", " + date.text(zone: window.timezone))
    }
    private func dateLabel(_ instant: ChallengeInstant, template: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: window.timezone)
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: instant.date)
    }
}

struct SignalFactRow: View {
    let label: String
    let value: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize > .xxxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 16))
        layout {
            Text(label).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            if typeSize <= .xxxLarge { Spacer(minLength: 0) }
            Text(value).font(.subheadline.weight(.medium)).monospacedDigit()
                .multilineTextAlignment(typeSize > .xxxLarge ? .leading : .trailing)
                .fixedSize(horizontal: false, vertical: true)
        }.padding(.vertical, 15).frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider().overlay(SignalTheme.divider) }
            .accessibilityElement(children: .combine)
    }
}

struct SignalTargetBand: View {
    let value: Int
    let metric: ChallengeV1Policy.Metric
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your goal").font(.subheadline)
            SignalMetricValue(value: value, metric: metric)
        }.padding(SignalTheme.contentInset).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(SignalTheme.onAccent).background(SignalTheme.accent)
            .padding(.horizontal, -SignalTheme.contentInset)
    }
}
