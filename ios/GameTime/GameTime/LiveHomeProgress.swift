import GameTimeCore
import SwiftUI

/// Home under the lit card: a note on how the challenge is going, a bar for each
/// day, a few numbers and what changed. The note and numbers use the saved
/// total; the bars use this phone's last complete Apple Health reading. Nothing
/// here mentions money, and a light day is never treated as a failure.
struct LiveHomeProgress: View {
    let row: ChallengeV1
    let actor: UUID?
    var health: ChallengeHealthFlowStore?
    @Environment(\.dynamicTypeSize) private var typeSize

    /// Goals with a number to reach, while they're scheduled or running.
    static func shows(_ row: ChallengeV1) -> Bool {
        row.format.hasTarget && row.format.metric != .timed && ["scheduled", "active"].contains(row.status)
    }

    static func progress(_ row: ChallengeV1, actor: UUID?, counted: [ChallengeHealthCountedSpan]?) -> ChallengeDayProgress? {
        guard let own = row.own(actor), let target = own.target, target > 0 else { return nil }
        return ChallengeDayProgress(start: row.config.startsAt.date, end: row.config.endsAt.date, dayCount: row.config.days,
                                    timeZone: TimeZone(identifier: row.config.timezone) ?? .current, now: row.serverTime.date,
                                    target: target, total: row.savedScore(own), counted: counted)
    }

    var body: some View {
        let counted = health?.states[row.id]?.counted
        if let progress = Self.progress(row, actor: actor, counted: counted) {
            let copy = LiveHomeProgressCopy(row: row, actor: actor, progress: progress)
            VStack(alignment: .leading, spacing: 12) {
                if let note = copy.note { noteCard(note, progress: progress) }
                LiveHomeDayBars(copy: copy, progress: progress, hasReading: counted != nil)
                if progress.best != nil { stats(copy, progress: progress) }
                let feed = copy.feed
                if !feed.isEmpty { feedCard(feed) }
            }
        }
    }

    private func noteCard(_ note: LiveHomeProgressCopy.Note, progress: ChallengeDayProgress) -> some View {
        let notConnected = progress.standing == .noUpdate && health?.states[row.id]?.readiness == .notConnected
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: note.symbol).font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(note.calm ? Floodlight.unconfirmed : Floodlight.member(0))
                    .frame(width: 34, height: 34)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Floodlight.well))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title).floodlightFont(15, weight: .semibold).foregroundStyle(Floodlight.ink)
                    if let detail = note.detail {
                        Text(detail).floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            if notConnected, let health {
                Button("Connect Apple Health") {
                    Task { if await health.connectAppleHealth() { await health.refresh(row.id) } }
                }
                .buttonStyle(FloodlightCalmButtonStyle(height: 44))
                .accessibilityIdentifier("live.home.connect")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floodlightCard(radius: 18)
        .accessibilityIdentifier("live.home.note")
    }

    private func stats(_ copy: LiveHomeProgressCopy, progress: ChallengeDayProgress) -> some View {
        let tiles = copy.stats
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        return layout {
            ForEach(tiles, id: \.label) { tile in
                VStack(alignment: .leading, spacing: 3) {
                    Text(tile.value).floodlightFont(22, weight: .bold, condensed: true, maxScale: 1.4).monospacedDigit()
                        .foregroundStyle(Floodlight.ink).lineLimit(1).minimumScaleFactor(0.7)
                    Text(tile.label).floodlightFont(11.5, weight: .medium).foregroundStyle(Floodlight.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 11).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .floodlightCard(radius: 14)
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("live.home.stats")
    }

    private func feedCard(_ feed: [LiveHomeProgressCopy.FeedRow]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            FloodlightLabel("What's new").padding(.bottom, 4)
            ForEach(Array(feed.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Circle().fill(item.calm ? Floodlight.unconfirmed : item.quiet ? Floodlight.faint : Floodlight.member(0))
                        .frame(width: 8, height: 8).accessibilityHidden(true)
                    Text(item.text).floodlightFont(13.5, weight: .medium).foregroundStyle(Floodlight.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if let time = item.time {
                        Text(time).floodlightFont(11.5, weight: .medium).foregroundStyle(Floodlight.faint)
                    }
                }
                .padding(.vertical, 8)
                .overlay(alignment: .top) { if index > 0 { Rectangle().fill(Floodlight.line).frame(height: 1) } }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floodlightCard(radius: 18)
        .accessibilityIdentifier("live.home.feed")
    }
}

/// A bar for each challenge day against an even daily pace. Days ahead, and
/// days this phone hasn't read, are dashed outlines rather than zero bars.
struct LiveHomeDayBars: View {
    let copy: LiveHomeProgressCopy
    let progress: ChallengeDayProgress
    let hasReading: Bool
    private let plot: CGFloat = 112

    var body: some View {
        let days = progress.days
        let peak = Double(max(days.compactMap(\.value).max() ?? 0, Int(Double(progress.dailyPace) * 1.35), 1))
        let compact = days.count <= 7
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                FloodlightLabel(compact ? "Your week" : "Your days")
                Spacer(minLength: 8)
                Text(copy.paceLabel).floodlightFont(12, weight: .medium).foregroundStyle(Floodlight.faint)
            }
            ZStack(alignment: .bottom) {
                // The even daily pace, dashed across the plot.
                GeometryReader { proxy in
                    let y = proxy.size.height - (proxy.size.height - 18) * CGFloat(Double(progress.dailyPace) / peak)
                    Path { path in path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: proxy.size.width, y: y)) }
                        .stroke(Floodlight.accent.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                HStack(alignment: .bottom, spacing: compact ? 12 : 3) {
                    ForEach(days, id: \.index) { day in
                        bar(day, peak: peak, compact: compact)
                    }
                }
                if !hasReading { Text(copy.emptyBars).floodlightFont(12, weight: .medium).foregroundStyle(Floodlight.muted)
                    .multilineTextAlignment(.center).padding(.horizontal, 12).padding(.bottom, plot * 0.42) }
            }
            .frame(height: plot)
            .overlay(alignment: .bottom) { Rectangle().fill(Floodlight.line).frame(height: 1) }
            if compact {
                HStack(spacing: 12) {
                    ForEach(days, id: \.index) { day in
                        Text(copy.dayLabel(day))
                            .floodlightFont(10.5, weight: day.isToday ? .semibold : .medium)
                            .foregroundStyle(day.isToday ? Floodlight.ink : Floodlight.muted)
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else if let first = days.first, let last = days.last {
                // Longer challenges: the first and last dates under the ends.
                HStack {
                    Text(copy.dayLabel(first))
                    Spacer(minLength: 8)
                    Text(copy.dayLabel(last))
                }
                .floodlightFont(10.5, weight: .medium).foregroundStyle(Floodlight.muted)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floodlightCard(radius: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(copy.barsSpoken)
        .accessibilityIdentifier("live.home.days")
    }

    @ViewBuilder private func bar(_ day: ChallengeDayProgress.Day, peak: Double, compact: Bool) -> some View {
        let you = Floodlight.member(0)
        VStack(spacing: 4) {
            if let value = day.value, value > 0 {
                if compact { Text(copy.short(value)).floodlightFont(10, weight: .medium).foregroundStyle(Floodlight.muted).lineLimit(1).fixedSize() }
                RoundedRectangle(cornerRadius: compact ? 6 : 3, style: .continuous)
                    .fill(you.opacity(day.isToday ? 0.55 : 1))
                    .overlay { if day.isToday { RoundedRectangle(cornerRadius: compact ? 6 : 3, style: .continuous).strokeBorder(you, lineWidth: 1.5) } }
                    .frame(height: max(6, (plot - 18) * CGFloat(Double(value) / peak)))
            } else {
                RoundedRectangle(cornerRadius: compact ? 6 : 3, style: .continuous)
                    .strokeBorder(Floodlight.faint.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .frame(height: 18)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

/// Home's words for a challenge in progress, from `ChallengeDayProgress`.
/// Amounts are rounded up for "about" lines so they're easy to read.
struct LiveHomeProgressCopy {
    struct Note: Equatable { let title: String; let detail: String?; let symbol: String; let calm: Bool }
    struct Stat: Equatable { let value: String; let label: String }
    struct FeedRow: Equatable { let text: String; let time: String?; var calm = false; var quiet = false }

    let row: ChallengeV1
    let actor: UUID?
    let progress: ChallengeDayProgress
    private var metric: ChallengeV1Policy.Metric { row.format.metric }
    private var zone: TimeZone { TimeZone(identifier: row.config.timezone) ?? .current }

    /// "46,300 steps", "12.4 km", "45 min".
    func amount(_ value: Int) -> String { FloodlightChallengeFacts.goal(row, value) }
    /// Rounded up to a friendly step: 100 steps, a whole minute, 0.1 km.
    func about(_ value: Int) -> String {
        let step = switch metric { case .steps: value >= 1_000 ? 100 : 1; case .exercise: 60; case .distance: 100_000; case .timed: 1 }
        return amount((value + step - 1) / step * step)
    }
    /// The number on a bar: "16.4K" for steps, otherwise the unit's number.
    func short(_ value: Int) -> String {
        metric == .steps && value >= 1_000
            ? value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)))
            : LiveChallengePresentation.value(value, metric: metric)
    }
    private var noun: String {
        switch metric { case .steps: "steps"; case .exercise: "activity minutes"; case .distance, .timed: "runs" }
    }
    private func daysLeft(_ count: Int) -> String { count == 1 ? "1 day left" : "\(count) days left" }
    private func weekday(_ date: Date) -> String {
        let format = DateFormatter(); format.timeZone = zone; format.setLocalizedDateFormatFromTemplate("EEEE")
        return format.string(from: date)
    }

    var note: Note? {
        switch progress.standing {
        case .upcoming:
            let when: String
            switch progress.daysUntilStart {
            case 0: when = "today"
            case 1: when = "tomorrow"
            case 2...6: when = weekday(row.config.startsAt.date)
            default:
                let format = DateFormatter(); format.timeZone = zone; format.setLocalizedDateFormatFromTemplate("MMMd")
                when = format.string(from: row.config.startsAt.date)
            }
            return Note(title: "Your challenge starts \(when).",
                        detail: "About \(about(progress.dailyPace)) a day reaches \(amount(progress.target)).",
                        symbol: "clock", calm: true)
        case .noUpdate:
            // This phone counted something the saved total doesn't show yet.
            if progress.best != nil { return Note(title: "We're saving your latest \(noun).", detail: nil, symbol: "arrow.triangle.2.circlepath", calm: true) }
            let detail = row.sourcePolicyVersion != nil
                ? "You need an Apple Watch that records to Apple Health on this iPhone. Activity recorded only by iPhone doesn't count."
                : "Your total shows up here after your first update."
            return Note(title: "We haven't counted any \(noun) yet.", detail: detail, symbol: "heart", calm: true)
        case .reached:
            return Note(title: "You reached your goal.", detail: "Everything from here is a bonus.", symbol: "checkmark", calm: false)
        case .ahead, .short:
            let remaining = progress.remaining ?? 0
            let left = progress.daysLeft
            let perDay = progress.neededPerDay.map { "About \(about($0)) a day gets you there." }
            if left <= 1 { return Note(title: "Last day: \(amount(remaining)) to go.", detail: nil, symbol: "flag", calm: false) }
            if progress.standing == .ahead {
                return Note(title: "You're ahead of pace with \(daysLeft(left)).",
                            detail: ["\(amount(remaining)) to go.", perDay].compactMap { $0 }.joined(separator: " "),
                            symbol: "chart.line.uptrend.xyaxis", calm: false)
            }
            return Note(title: "\(amount(remaining)) to go with \(daysLeft(left)).", detail: perDay, symbol: "figure.walk", calm: false)
        case .finished:
            return nil
        }
    }

    var paceLabel: String { "About \(about(progress.dailyPace)) a day" }
    var emptyBars: String {
        progress.standing == .upcoming ? "Your daily \(noun) show up here." : "Your daily \(noun) show up here after we check Apple Health on this phone."
    }
    /// "Sat" or "Today" in a week; "Oct 10" at the ends of a longer challenge.
    func dayLabel(_ day: ChallengeDayProgress.Day) -> String {
        let format = DateFormatter(); format.timeZone = zone
        if progress.days.count <= 7 {
            if day.isToday { return "Today" }
            format.setLocalizedDateFormatFromTemplate("EEE")
        } else {
            format.setLocalizedDateFormatFromTemplate("MMMd")
        }
        return format.string(from: day.start)
    }
    var barsSpoken: String {
        var parts = ["Your \(noun) each day. About \(about(progress.dailyPace)) a day reaches your goal."]
        for day in progress.days where !day.isFuture {
            let name = day.isToday ? "Today" : weekday(day.start)
            parts.append(day.value.map { "\(name), \(amount($0))\(day.isToday ? " so far" : "")." } ?? "\(name), not checked yet.")
        }
        return parts.joined(separator: " ")
    }

    var stats: [Stat] {
        var tiles: [Stat] = []
        if let best = progress.best, let value = best.value {
            let format = DateFormatter(); format.timeZone = zone; format.setLocalizedDateFormatFromTemplate("EEE")
            tiles.append(Stat(value: LiveChallengePresentation.value(value, metric: metric), label: "Best day (\(format.string(from: best.start)))"))
        }
        if let average = progress.finishedDayAverage {
            tiles.append(Stat(value: LiveChallengePresentation.value(average, metric: metric), label: "Daily average"))
        }
        if progress.daysLeft > 0 { tiles.append(Stat(value: progress.daysLeft.formatted(), label: progress.daysLeft == 1 ? "Day left" : "Days left")) }
        return tiles
    }

    var feed: [FeedRow] {
        guard progress.standing != .upcoming, let own = row.own(actor) else { return [] }
        var rows: [FeedRow] = []
        if let sync = FloodlightChallengeFacts.syncTime(row, own, actor: actor) {
            rows.append(FeedRow(text: row.sourcePolicyVersion != nil ? "We updated your total from Apple Health." : "We updated your total.",
                                time: sync.short, calm: true))
        }
        if let total = progress.total, total < progress.target,
           let quarter = [3, 2, 1].first(where: { total * 4 >= progress.target * $0 }) {
            let words = [1: "A quarter of the way.", 2: "Halfway there.", 3: "Three quarters of the way."][quarter] ?? ""
            rows.append(FeedRow(text: "You passed \(amount(progress.target * quarter / 4)). \(words)", time: nil))
        }
        if let light = progress.days.last(where: { !$0.isToday && !$0.isFuture && $0.value != nil }),
           let value = light.value, Double(value) < Double(progress.dailyPace) * 0.5 {
            rows.append(FeedRow(text: "\(weekday(light.start)) was lighter. Rest days are normal.", time: nil, quiet: true))
        }
        if progress.days.filter({ ($0.value ?? 0) > 0 }).count >= 2, let best = progress.best {
            rows.append(FeedRow(text: "\(best.isToday ? "Today" : weekday(best.start)) is your best day so far, with \(amount(best.value ?? 0)).",
                                time: nil))
        }
        return Array(rows.prefix(3))
    }
}
