import Foundation
import SwiftUI

/// The week read as a pace: how far ahead or behind the steps-a-day rate you
/// are, what each day did, and what is left to walk.
///
/// Every number a screen shows is worked out here, once, from the same day
/// records the progress bar and the timeline read. Nothing is recomputed in a
/// view body, and nothing invents a second scoring rule — a day that the
/// service could not confirm stays uncounted here too.
struct PersonalPaceSummary: Equatable {
    /// How a single day turned out, in the terms the chart draws.
    enum Verdict: Equatable {
        case future
        case today
        case metGoal
        case underGoal
        /// Our problem, so it never counts against the person.
        case waived
        case waiting
        case problem
    }

    enum Tone: Equatable {
        case positive
        case action
    }

    struct Day: Identifiable, Equatable {
        let id: String
        let position: Int
        let shortLabel: String
        let longLabel: String
        let steps: Int
        let verdict: Verdict
        let evidenceState: PersonalEvidenceState
    }

    struct Tile: Identifiable, Equatable {
        let id: String
        let label: String
        let value: String
        let caption: String
    }

    let days: [Day]
    let dayGoal: Int
    let barCeiling: Double
    let goalLineText: String
    let headline: String
    let headlineTone: Tone
    let headlineCaption: String
    let dayCountText: String
    let tiles: [Tile]

    init(detail: PersonalChallengeDetail) {
        self.init(
            detail: detail,
            records: detail.progress.days,
            total: detail.progress.trustedSteps,
            remaining: detail.progress.remainingSteps
        )
    }

    init(
        detail: PersonalChallengeDetail,
        progress displayedProgress: PersonalDisplayedProgress
    ) {
        let records = displayedProgress.days.map { day in
            let evidenceState: PersonalEvidenceState
            switch day.state {
            case .future:
                evidenceState = .future
            case .current:
                evidenceState = .inProgress
            case .complete:
                evidenceState = .complete
            }
            return PersonalDayProgress(
                localDate: day.localDate,
                trustedSteps: Double(day.totalSteps),
                targetSteps: day.targetSteps,
                evidenceState: evidenceState,
                metTarget: day.metTarget
            )
        }
        self.init(
            detail: detail,
            records: records,
            total: displayedProgress.totalSteps,
            remaining: displayedProgress.remainingSteps
        )
    }

    private init(
        detail: PersonalChallengeDetail,
        records: [PersonalDayProgress],
        total: Int,
        remaining: Int
    ) {
        let terms = detail.terms
        let dayCount = max(records.count, 1)
        let goal =
            terms.cadence == .daily
            ? terms.targetSteps
            : Int(
                (Double(terms.targetSteps) / Double(dayCount)).rounded()
            )
        dayGoal = max(0, goal)

        let labeller = PersonalWeekdayLabeller(
            timezoneIdentifier: terms.timezone
        )
        days = records.enumerated().map { position, record in
            let labels = labeller.labels(
                for: record.localDate,
                position: position
            )
            return Day(
                id: record.localDate,
                position: position,
                shortLabel: labels.short,
                longLabel: labels.long,
                steps: record.displayedTrustedSteps,
                verdict: Self.verdict(for: record, dayGoal: goal),
                evidenceState: record.evidenceState
            )
        }

        let highestDay = days.map(\.steps).max() ?? 0
        barCeiling = max(
            Double(dayGoal) * 1.3,
            Double(highestDay) * 1.06,
            1
        )
        goalLineText = "\(dayGoal.formatted()) a day"

        let elapsed = days.filter { $0.verdict != .future }.count
        let upcoming = days.filter { $0.verdict == .future }
        dayCountText =
            elapsed == 0
            ? "\(dayCount) days"
            : "Day \(elapsed) of \(dayCount)"

        let goalDays = days.filter { $0.verdict == .metGoal }.count
        // A day we couldn't confirm never counts against the person, so it
        // stays out of both halves of the pace comparison. Leaving it in
        // would put a number on screen that says they are behind because our
        // data went missing.
        let counted = days.filter {
            $0.verdict == .metGoal || $0.verdict == .underGoal
                || $0.verdict == .today
        }
        let countedSteps = counted.reduce(0) { $0 + $1.steps }
        // Once the last day is behind them, "where you need to be" is a
        // question about the past. Every line below shifts tense with it.
        let isFinished = elapsed > 0 && upcoming.isEmpty
        let headlineParts: (String, Tone, String)
        switch terms.cadence {
        case .cumulative:
            headlineParts = Self.weekHeadline(
                countedSteps: countedSteps,
                countedDays: counted.count,
                dayGoal: dayGoal,
                isFinished: isFinished
            )
        case .daily:
            headlineParts = Self.dayHeadline(
                targetSteps: terms.targetSteps,
                records: records,
                elapsed: elapsed,
                dayCount: dayCount,
                goalDays: goalDays,
                isFinished: isFinished
            )
        }
        headline = headlineParts.0
        headlineTone = headlineParts.1
        headlineCaption = headlineParts.2

        tiles = Self.makeTiles(
            cadence: terms.cadence,
            total: total,
            // The service owns what is still owed on the goal; a second
            // subtraction here would be a second scoring rule.
            remaining: max(0, remaining),
            countedSteps: countedSteps,
            countedDays: counted.count,
            elapsed: elapsed,
            goalDays: goalDays,
            upcoming: upcoming,
            isFinished: isFinished
        )
    }

    /// The day the card opens on: today if the week is running, otherwise the
    /// most recent day that has something to say.
    var defaultDayID: String? {
        if let today = days.first(where: { $0.verdict == .today }) {
            return today.id
        }
        if let last = days.last(where: { $0.verdict != .future }) {
            return last.id
        }
        return days.first?.id
    }

    func day(id: String?) -> Day? {
        guard let id, let match = days.first(where: { $0.id == id }) else {
            return days.first(where: { $0.id == defaultDayID })
        }
        return match
    }

    /// What the panel under the chart says about one day.
    func detailText(for day: Day) -> (value: String, caption: String) {
        let goalText = "\(dayGoal.formatted())-step day"
        switch day.verdict {
        case .future:
            return (
                "Not here yet",
                "Day \(day.position + 1) of \(days.count)"
            )
        case .today:
            let remaining = max(0, dayGoal - day.steps)
            return (
                "\(day.steps.formatted()) steps",
                remaining > 0
                    ? "Still counting. \(remaining.formatted()) to go for a \(goalText)."
                    : "Still counting. You have already passed a \(goalText)."
            )
        case .metGoal:
            let over = day.steps - dayGoal
            return (
                "\(day.steps.formatted()) steps",
                over > 0
                    ? "\(over.formatted()) over a \(goalText)"
                    : "Right on a \(goalText)"
            )
        case .underGoal:
            return (
                "\(day.steps.formatted()) steps",
                "\(max(0, dayGoal - day.steps).formatted()) under a \(goalText)"
            )
        case .waived:
            return (
                "\(day.steps.formatted()) steps",
                "This was a problem on our end, so it doesn’t count against you."
            )
        case .waiting:
            return (
                "\(day.steps.formatted()) steps",
                "We’re still waiting for this day’s steps."
            )
        case .problem:
            return (
                "\(day.steps.formatted()) steps",
                Self.problemCaption(day.evidenceState)
            )
        }
    }

    private static func verdict(
        for record: PersonalDayProgress,
        dayGoal: Int
    ) -> Verdict {
        switch record.evidenceState {
        case .future:
            return .future
        case .inProgress:
            return .today
        case .pending:
            return .waiting
        case .outageWaived:
            return .waived
        case .incomplete, .missing, .quarantined, .conflicting, .unresolved:
            return .problem
        case .complete:
            if let metTarget = record.metTarget {
                return metTarget ? .metGoal : .underGoal
            }
            return record.displayedTrustedSteps >= dayGoal
                ? .metGoal
                : .underGoal
        }
    }

    private static func problemCaption(
        _ state: PersonalEvidenceState
    ) -> String {
        switch state {
        case .incomplete:
            "Some of this day’s steps never arrived, so it won’t count either way."
        case .missing:
            "We never received steps for this day, so it won’t count either way."
        case .quarantined:
            "We couldn’t use this day’s steps, so it won’t count either way."
        case .conflicting:
            "This day’s steps didn’t add up, so it won’t count either way."
        case .unresolved:
            "We’re still sorting out this day’s steps."
        case .future, .inProgress, .pending, .complete, .outageWaived:
            "We’re still sorting out this day’s steps."
        }
    }

    private static func weekHeadline(
        countedSteps: Int,
        countedDays: Int,
        dayGoal: Int,
        isFinished: Bool
    ) -> (String, Tone, String) {
        guard countedDays > 0 else {
            return (
                dayGoal.formatted(),
                .positive,
                "steps a day keeps you on track"
            )
        }
        let delta = countedSteps - (dayGoal * countedDays)
        if delta >= 0 {
            return (
                "+\(delta.formatted())",
                .positive,
                isFinished
                    ? "steps more than you needed"
                    : "steps ahead of where you need to be"
            )
        }
        return (
            "−\(abs(delta).formatted())",
            .action,
            isFinished
                ? "steps short of what you needed"
                : "steps behind where you need to be"
        )
    }

    private static func dayHeadline(
        targetSteps: Int,
        records: [PersonalDayProgress],
        elapsed: Int,
        dayCount: Int,
        goalDays: Int,
        isFinished: Bool
    ) -> (String, Tone, String) {
        guard elapsed > 0 else {
            return (
                targetSteps.formatted(),
                .positive,
                "steps a day, every day"
            )
        }
        if isFinished {
            return (
                "\(goalDays) of \(dayCount)",
                goalDays == dayCount ? .positive : .action,
                "days you hit your goal"
            )
        }
        let remaining = PersonalProgress.dailyRemainingSteps(
            targetSteps: targetSteps,
            days: records
        )
        if remaining == 0 {
            return ("Goal met", .positive, "you’ve hit today’s goal")
        }
        return (remaining.formatted(), .action, "steps to go today")
    }

    private static func makeTiles(
        cadence: PersonalChallengeCadence,
        total: Int,
        remaining: Int,
        countedSteps: Int,
        countedDays: Int,
        elapsed: Int,
        goalDays: Int,
        upcoming: [Day],
        isFinished: Bool
    ) -> [Tile] {
        let average = countedDays > 0 ? countedSteps / countedDays : 0
        let averageTile = Tile(
            id: "average",
            label: "Average",
            value: average.formatted(),
            caption: isFinished ? "steps a day" : "steps a day so far"
        )
        let leftTile = Tile(
            id: "left",
            label: "Left",
            value: upcoming.isEmpty
                ? "0 days"
                : (upcoming.count == 1 ? "1 day" : "\(upcoming.count) days"),
            caption: upcoming.isEmpty
                ? "your last day is done"
                : dayNames(upcoming)
        )

        switch cadence {
        case .cumulative:
            let finishTile: Tile
            if remaining == 0 {
                finishTile = Tile(
                    id: "finish",
                    label: "To finish",
                    value: "Done",
                    caption: "you reached your goal"
                )
            } else if upcoming.isEmpty {
                finishTile = Tile(
                    id: "finish",
                    label: "To finish",
                    value: remaining.formatted(),
                    caption: "steps short at the end"
                )
            } else {
                let perDay = Int(
                    (Double(remaining) / Double(upcoming.count)).rounded(.up)
                )
                finishTile = Tile(
                    id: "finish",
                    label: "To finish",
                    value: perDay.formatted(),
                    caption: "a day, \(dayNames(upcoming))"
                )
            }
            return [finishTile, averageTile, leftTile]
        case .daily:
            let weekTotalTile = Tile(
                id: "week-total",
                label: "Week total",
                value: total.formatted(),
                caption: isFinished
                    ? "steps across seven days"
                    : "steps so far"
            )
            // A finished week already says its goal-day count in the
            // headline, so give the tile something new to carry.
            if isFinished {
                return [weekTotalTile, averageTile, leftTile]
            }
            let goalDaysTile = Tile(
                id: "goal-days",
                label: "Goal days",
                value: "\(goalDays) of \(elapsed)",
                caption: "days you hit so far"
            )
            return [goalDaysTile, weekTotalTile, leftTile]
        }
    }

    /// Tile captions get two short lines at 10pt, so spell out a few day
    /// names and point at the finish line beyond that.
    private static func dayNames(_ days: [Day]) -> String {
        guard let last = days.last else { return "" }
        if days.count > 3 {
            return "through \(last.shortLabel)"
        }
        return days.map(\.shortLabel).formatted(.list(type: .and))
    }
}

/// Turns a `2026-08-10`-style local date into the weekday a person would say,
/// in the timezone the challenge froze into.
private struct PersonalWeekdayLabeller {
    private let parser = DateFormatter()
    private let short = DateFormatter()
    private let long = DateFormatter()

    init(timezoneIdentifier: String) {
        let timezone = TimeZone(identifier: timezoneIdentifier)
            ?? TimeZone(secondsFromGMT: 0)!
        parser.locale = Locale(identifier: "en_US_POSIX")
        parser.timeZone = timezone
        parser.dateFormat = "yyyy-MM-dd"
        for formatter in [short, long] {
            formatter.locale = .autoupdatingCurrent
            formatter.timeZone = timezone
        }
        short.setLocalizedDateFormatFromTemplate("EEE")
        long.setLocalizedDateFormatFromTemplate("EEEE")
    }

    func labels(
        for localDate: String,
        position: Int
    ) -> (short: String, long: String) {
        guard let date = parser.date(from: localDate) else {
            let fallback = "Day \(position + 1)"
            return (fallback, fallback)
        }
        return (short.string(from: date), long.string(from: date))
    }
}

/// The week as a chart you can tap: a bar for every day against the
/// steps-a-day rate that gets you there, and a panel for the day you picked.
struct PersonalPaceCard: View {
    let summary: PersonalPaceSummary

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDayID: String?

    private let chartHeight: CGFloat = 132
    private let barScale: CGFloat = 128
    private let barSpacing: CGFloat = 7

    var body: some View {
        DaybreakCard {
            VStack(alignment: .leading, spacing: 16) {
                header
                chartAndLabels
                selectedDay
            }
        }
    }

    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 9) {
                    headlineCopy
                    dayCountChip
                }
            } else {
                HStack(alignment: .bottom, spacing: 10) {
                    headlineCopy
                    Spacer(minLength: 8)
                    dayCountChip
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var headlineCopy: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.headline)
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 38,
                        relativeTo: .largeTitle
                    )
                )
                .tracking(-0.8)
                .foregroundStyle(headlineColor)
                .lineLimit(
                    dynamicTypeSize.isAccessibilitySize ? nil : 1
                )
                .minimumScaleFactor(
                    dynamicTypeSize.isAccessibilitySize ? 1 : 0.6
                )
            Text(summary.headlineCaption)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 13,
                        relativeTo: .footnote,
                        weight: .semibold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
    }

    private var dayCountChip: some View {
        HStack(spacing: 6) {
            Image(
                systemName: summary.headlineTone == .positive
                    ? "arrow.up.right"
                    : "arrow.down.right"
            )
            .foregroundStyle(headlineColor)
            .accessibilityHidden(true)
            Text(summary.dayCountText)
        }
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 12,
                relativeTo: .caption,
                weight: .bold
            )
        )
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(CompetitiveTrustTheme.paperSunk, in: Capsule())
        .fixedSize(horizontal: false, vertical: true)
    }

    private var chartAndLabels: some View {
        ScrollView(.horizontal) {
            VStack(spacing: 8) {
                chart
                dayLabels
            }
            .frame(minWidth: chartMinimumWidth)
        }
        .scrollIndicators(.hidden)
        .accessibilityIdentifier("personal.pace.chart")
    }

    private var chart: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(summary.days) { day in
                bar(for: day)
            }
        }
        .frame(height: chartHeight)
        .overlay(alignment: .bottom) {
            goalGuide
                .offset(y: -goalHeight)
                .allowsHitTesting(false)
        }
    }

    private var goalGuide: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(summary.goalLineText)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 10,
                        relativeTo: .caption2,
                        weight: .bold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
            PaceGuideLine()
                .stroke(
                    CompetitiveTrustTheme.strongBorder,
                    style: StrokeStyle(lineWidth: 1, dash: [4, 4])
                )
                .frame(height: 1)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityHidden(true)
    }

    private func bar(for day: PersonalPaceSummary.Day) -> some View {
        let isSelected = day.id == resolvedDay?.id
        let text = summary.detailText(for: day)
        return Button {
            select(day)
        } label: {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(fill(for: day.verdict))
                    .frame(height: barHeight(for: day))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(
                                cornerRadius: 9,
                                style: .continuous
                            )
                            .inset(by: -2.5)
                            .stroke(
                                CompetitiveTrustTheme.primaryText,
                                lineWidth: 2
                            )
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(minWidth: CompetitiveTrustTheme.minimumHitTarget)
        .accessibilityLabel("\(day.longLabel), \(text.value)")
        .accessibilityValue(text.caption)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityIdentifier("personal.pace.day.\(day.position)")
    }

    private var dayLabels: some View {
        HStack(spacing: barSpacing) {
            ForEach(summary.days) { day in
                Text(day.shortLabel)
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11,
                            relativeTo: .caption,
                            weight: .bold
                        )
                    )
                    .foregroundStyle(
                        day.id == resolvedDay?.id
                            ? CompetitiveTrustTheme.primaryText
                            : CompetitiveTrustTheme.tertiaryText
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(
                        minWidth: CompetitiveTrustTheme.minimumHitTarget,
                        maxWidth: .infinity
                    )
            }
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var selectedDay: some View {
        if let day = resolvedDay {
            let text = summary.detailText(for: day)
            VStack(spacing: 0) {
                Divider().overlay(CompetitiveTrustTheme.border)
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(day.longLabel)
                            .textCase(.uppercase)
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 12,
                                    relativeTo: .caption,
                                    weight: .bold
                                )
                            )
                            .tracking(0.6)
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                        Text(text.value)
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 24,
                                    relativeTo: .title2
                                )
                            )
                            .tracking(-0.5)
                        Text(text.caption)
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 12.5,
                                    relativeTo: .footnote
                                )
                            )
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                            .fixedSize(
                                horizontal: false,
                                vertical: true
                            )
                    }
                    Spacer(minLength: 8)
                    if !dynamicTypeSize.isAccessibilitySize {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(CompetitiveTrustTheme.coralInk)
                            .frame(width: 38, height: 38)
                            .background(
                                CompetitiveTrustTheme.paperSunk,
                                in: Circle()
                            )
                            .accessibilityHidden(true)
                    }
                }
                .padding(.top, 14)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("personal.pace.selected-day")
        }
    }

    private var resolvedDay: PersonalPaceSummary.Day? {
        summary.day(id: selectedDayID)
    }

    private var headlineColor: Color {
        summary.headlineTone == .positive
            ? CompetitiveTrustTheme.mintInk
            : CompetitiveTrustTheme.coralInk
    }

    private var chartMinimumWidth: CGFloat {
        let count = CGFloat(summary.days.count)
        return count * CompetitiveTrustTheme.minimumHitTarget
            + max(0, count - 1) * barSpacing
    }

    private var goalHeight: CGFloat {
        guard summary.barCeiling > 0 else { return 0 }
        return CGFloat(Double(summary.dayGoal) / summary.barCeiling) * barScale
    }

    private func barHeight(for day: PersonalPaceSummary.Day) -> CGFloat {
        guard day.verdict != .future else { return 5 }
        guard summary.barCeiling > 0 else { return 8 }
        let scaled =
            CGFloat(Double(day.steps) / summary.barCeiling) * barScale
        return max(8, min(barScale, scaled))
    }

    private func fill(for verdict: PersonalPaceSummary.Verdict) -> Color {
        switch verdict {
        case .future, .waiting:
            CompetitiveTrustTheme.rail
        case .today:
            CompetitiveTrustTheme.coral
        case .metGoal, .waived:
            CompetitiveTrustTheme.mintInk
        case .underGoal:
            CompetitiveTrustTheme.coralPressed
        case .problem:
            CompetitiveTrustTheme.sunInk
        }
    }

    private func select(_ day: PersonalPaceSummary.Day) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            selectedDayID = day.id
        }
    }
}

private struct PaceGuideLine: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}

/// The three numbers that sit under the chart.
struct PersonalPaceTiles: View {
    let tiles: [PersonalPaceSummary.Tile]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 9) { content }
        } else {
            HStack(alignment: .top, spacing: 9) { content }
        }
    }

    private var content: some View {
        ForEach(tiles) { tile in
            ChallengeStatTile(
                label: tile.label,
                value: tile.value,
                caption: tile.caption
            )
            .accessibilityIdentifier("personal.pace.\(tile.id)")
        }
    }
}

/// What you signed up for, folded away until someone asks for it. The terms
/// themselves never change — only how much room they take up.
struct PersonalChallengeDetailsCard: View {
    let terms: FrozenPersonalTerms

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingTerms = false

    var body: some View {
        DaybreakCard {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(
                        reduceMotion ? nil : .easeOut(duration: 0.2)
                    ) {
                        isShowingTerms.toggle()
                    }
                } label: {
                    header
                }
                .buttonStyle(.plain)
                .minimumInteractiveSize()
                .accessibilityIdentifier("personal.details")
                .accessibilityLabel("Challenge details")
                .accessibilityValue(isShowingTerms ? "Showing" : "Hidden")
                .accessibilityHint(
                    isShowingTerms
                        ? "Hides what you signed up for"
                        : "Shows what you signed up for"
                )
                .accessibilityAddTraits(.isHeader)

                if isShowingTerms {
                    VStack(spacing: 0) {
                        Divider().overlay(CompetitiveTrustTheme.border)
                        termRow("How it counts", terms.cadence.title)
                        divider
                        termRow("Goal", terms.targetText)
                        divider
                        termRow("Amount", terms.commitmentText)
                        divider
                        termRow("Time zone", terms.timezone)
                        divider
                        termRow(
                            "Starts",
                            PersonalTermsDateFormatter.dateTime(
                                terms.startsAt,
                                timezoneIdentifier: terms.timezone
                            )
                        )
                        divider
                        termRow(
                            "Ends",
                            PersonalTermsDateFormatter.dateTime(
                                terms.endsAt,
                                timezoneIdentifier: terms.timezone
                            )
                        )
                        divider
                        termRow(
                            "Updates through",
                            PersonalTermsDateFormatter.dateTime(
                                terms.evidenceCutoff,
                                timezoneIdentifier: terms.timezone
                            )
                        )
                    }
                    .padding(.top, 12)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.text")
                .font(.system(size: 17))
                .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Challenge details")
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 14,
                            relativeTo: .subheadline,
                            weight: .bold
                        )
                    )
                Text(summaryLine)
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11.5,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Text(isShowingTerms ? "Hide" : "Show")
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 12,
                        relativeTo: .caption,
                        weight: .bold
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.coralInk)
        }
        .contentShape(Rectangle())
    }

    private var summaryLine: String {
        let ends = PersonalTermsDateFormatter.day(
            terms.endsAt,
            timezoneIdentifier: terms.timezone
        )
        return "\(terms.cadence.title) · \(terms.commitmentText) · ends \(ends)"
    }

    private func termRow(_ label: String, _ value: String) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 5) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                    Spacer(minLength: 8)
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 11)
        .accessibilityElement(children: .combine)
    }

    private var divider: some View {
        Divider().overlay(CompetitiveTrustTheme.border)
    }
}
