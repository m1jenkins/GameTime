import Foundation

// Everything the rope needs, derived once. Today, Duels and Duel detail all
// render the same split, so the split, the deficit and the pace to flip it are
// computed here rather than three times.

// MARK: - Metric display

/// Contest metrics are stored in base units (distance in metres) but read in
/// human units (kilometres). This converts and formats for display.
struct MetricDisplay {
    let metric: ContestMetric

    var unit: String {
        switch metric {
        case .steps: "steps"
        case .distanceMeters: "km"
        case .activeEnergyKilocalories: "kcal"
        case .exerciseMinutes: "min"
        }
    }

    /// Short unit for tucking beside a large numeral.
    var tightUnit: String {
        metric == .steps ? "steps" : unit
    }

    private var scale: Double {
        metric == .distanceMeters ? 0.001 : 1
    }

    private var fractionDigits: Int {
        metric == .distanceMeters ? 1 : 0
    }

    func converted(_ raw: Double) -> Double {
        raw * scale
    }

    /// The numeral alone — "6.4", "8,000".
    ///
    /// Distances keep one decimal so progress reads consistently ("4.0 km", not
    /// "4 km"). Round targets drop it, so a 10 000 m target reads "10 km".
    func number(_ raw: Double, dropsTrailingZero: Bool = false) -> String {
        let value = converted(raw)
        guard metric == .distanceMeters else {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        if dropsTrailingZero, value == value.rounded() {
            return value.formatted(.number.precision(.fractionLength(0)))
        }
        return value.formatted(
            .number.precision(.fractionLength(fractionDigits))
        )
    }

    /// Numeral and unit — "6.4 km", "8,000 steps".
    func measurement(
        _ raw: Double,
        dropsTrailingZero: Bool = false
    ) -> String {
        "\(number(raw, dropsTrailingZero: dropsTrailingZero)) \(unit)"
    }
}

extension ProfileCard {
    /// The design addresses people by first name — "vs Marcus", "Marcus threw
    /// down".
    var firstName: String {
        displayName
            .split(whereSeparator: \.isWhitespace)
            .first
            .map(String.init) ?? displayName
    }
}

extension ContestCard {
    var display: MetricDisplay { MetricDisplay(metric: metric) }

    /// "$10" rather than "$10.00" — whole-dollar stakes lose the cents.
    var stakeCompactText: String {
        let dollars = Double(stakeAmountCents) / 100
        guard dollars == dollars.rounded() else { return stakeText }
        return dollars.formatted(
            .currency(code: "USD").precision(.fractionLength(0))
        )
    }

    /// "10 km cumulative" — the target as the terms state it.
    var targetLine: String {
        "\(display.measurement(targetValue, dropsTrailingZero: true)) \(cadence.title.lowercased())"
    }

    /// "10 km cumulative · $10 · Trail Fund" — the terms restated in one plain
    /// line. The charity is only known when a standing supplies it.
    func termsLine(charityName: String?) -> String {
        var parts = [targetLine, stakeCompactText]
        if let charityName {
            parts.append(charityName)
        }
        return parts.joined(separator: " · ")
    }

    /// "vs Marcus · 10 km cumulative" for the list row.
    func listSubtitle(opponentFirstName: String?) -> String {
        guard let opponentFirstName else { return targetLine }
        return "vs \(opponentFirstName) · \(targetLine)"
    }
}

// MARK: - Timeline

/// One entry in the "Rope moved" timeline. The arrow direction encodes who
/// gained ground.
struct RopeEvent: Identifiable, Equatable, Sendable {
    enum Direction: Equatable, Sendable {
        /// They pulled the rope their way.
        case theyPulled
        /// You clawed it back.
        case youPulled
        /// The duel opened.
        case opened
    }

    let id: UUID
    let direction: Direction
    /// Bolded actor at the head of the sentence, when the event has one.
    let actor: String?
    let detail: String
    /// Coarse relative age — "3d", "2h".
    let age: String

    init(
        id: UUID = UUID(),
        direction: Direction,
        actor: String?,
        detail: String,
        age: String
    ) {
        self.id = id
        self.direction = direction
        self.actor = actor
        self.detail = detail
        self.age = age
    }
}

// MARK: - Standing

/// Live progress for one duel, plus the supporting numbers the detail screen
/// shows. Progress comes from Apple Health; a typed number never counts.
struct DuelStanding: Equatable, Sendable {
    /// Nil when the roster has not been resolved — the rope then shows both
    /// sides unknown rather than inventing a 50/50 result.
    var opponent: ProfileCard?
    var myProgress: Double
    var theirProgress: Double
    /// Drives the stale-health banner. Nil means progress was never synced.
    var lastSyncedAt: Date?
    /// "His best · 4.0 km Fri" — one stat about them.
    var opponentBest: (value: Double, dayLabel: String)?
    /// "Your streak · 3 days hit" — one stat about you.
    var yourStreakDays: Int?
    var events: [RopeEvent]
    /// The charity the winner nominated, when known.
    var charityName: String?

    init(
        opponent: ProfileCard? = nil,
        myProgress: Double = 0,
        theirProgress: Double = 0,
        lastSyncedAt: Date? = nil,
        opponentBest: (value: Double, dayLabel: String)? = nil,
        yourStreakDays: Int? = nil,
        events: [RopeEvent] = [],
        charityName: String? = nil
    ) {
        self.opponent = opponent
        self.myProgress = myProgress
        self.theirProgress = theirProgress
        self.lastSyncedAt = lastSyncedAt
        self.opponentBest = opponentBest
        self.yourStreakDays = yourStreakDays
        self.events = events
        self.charityName = charityName
    }

    static func == (lhs: DuelStanding, rhs: DuelStanding) -> Bool {
        lhs.opponent == rhs.opponent
            && lhs.myProgress == rhs.myProgress
            && lhs.theirProgress == rhs.theirProgress
            && lhs.lastSyncedAt == rhs.lastSyncedAt
            && lhs.opponentBest?.value == rhs.opponentBest?.value
            && lhs.opponentBest?.dayLabel == rhs.opponentBest?.dayLabel
            && lhs.yourStreakDays == rhs.yourStreakDays
            && lhs.events == rhs.events
            && lhs.charityName == rhs.charityName
    }

    /// True once Apple Health has reported anything for either side.
    var hasProgress: Bool {
        lastSyncedAt != nil && (myProgress > 0 || theirProgress > 0)
    }

    /// Your share of combined progress — where the knot sits. Parity when
    /// neither side has moved.
    var split: Double {
        let combined = myProgress + theirProgress
        guard combined > 0 else { return 0.5 }
        return myProgress / combined
    }

    /// Positive when they are ahead.
    var deficit: Double {
        theirProgress - myProgress
    }

    var isAhead: Bool { myProgress > theirProgress }
    var isLevel: Bool { myProgress == theirProgress }

    /// The live taunt at the top of Today. Not a greeting.
    var headline: String {
        if !hasProgress { return "Rope's up." }
        if isLevel { return "Dead even." }
        return isAhead ? "You're up." : "You're behind."
    }

    /// What you need per day to reach the target — "1.8/day to flip it".
    func paceToWin(target: Double, daysLeft: Int) -> Double? {
        guard daysLeft > 0 else { return nil }
        let remaining = target - myProgress
        guard remaining > 0 else { return nil }
        return remaining / Double(daysLeft)
    }
}

// MARK: - Deficit copy

/// The deficit callout under every rope, and Today's one-line comparison. The
/// gap is always framed in human terms — never a percentage.
struct DeficitCopy {
    let magnitude: String
    /// "behind" / "up" / "level".
    let direction: String
    let isBehind: Bool
    let isLevel: Bool

    init(standing: DuelStanding, metric: ContestMetric) {
        let display = MetricDisplay(metric: metric)
        let gap = abs(standing.deficit)
        magnitude = display.measurement(gap)
        isLevel = standing.isLevel
        isBehind = !standing.isAhead && !standing.isLevel
        direction = isLevel ? "level" : (isBehind ? "behind" : "up")
    }

    /// "0.7 km behind" — the callout's leading phrase.
    var headline: String {
        isLevel ? "Neck and neck" : "\(magnitude) \(direction)"
    }

    /// "0.7 km back" — Today's tighter variant.
    var shortHeadline: String {
        if isLevel { return "Neck and neck" }
        return isBehind ? "\(magnitude) back" : "\(magnitude) up"
    }

    /// "that's one podcast" — the gap in something you can picture.
    static func humanComparison(
        gap: Double,
        metric: ContestMetric,
        isBehind: Bool
    ) -> String {
        guard isBehind else { return "keep it there" }
        switch metric {
        case .distanceMeters:
            let km = gap / 1_000
            if km < 0.5 { return "that's one lap" }
            if km < 1.5 { return "that's one podcast" }
            if km < 4 { return "that's a warm-up" }
            return "that's a real run"
        case .steps:
            if gap < 1_500 { return "that's a walk to lunch" }
            if gap < 4_000 { return "that's one podcast" }
            return "that's an evening walk"
        case .activeEnergyKilocalories:
            if gap < 100 { return "that's a warm-up" }
            if gap < 300 { return "that's one class" }
            return "that's a full session"
        case .exerciseMinutes:
            if gap < 10 { return "that's a warm-up" }
            if gap < 25 { return "that's one podcast" }
            return "that's a full session"
        }
    }
}

// MARK: - Time remaining

/// Coarse countdowns, deliberately not second-accurate so the view can redraw
/// on a slow tick.
enum DuelClock {
    /// "2d 4h left", "4h left", "Ends soon".
    static func remainingText(until end: Date, now: Date = Date()) -> String {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return "Ended" }
        let days = Int(seconds) / 86_400
        let hours = (Int(seconds) % 86_400) / 3_600
        if days > 0 {
            return hours > 0 ? "\(days)d \(hours)h left" : "\(days)d left"
        }
        if hours > 0 { return "\(hours)h left" }
        return "Ends soon"
    }

    /// The compact pill on list rows — "2d", "4h".
    static func shortRemaining(until end: Date, now: Date = Date()) -> String {
        let seconds = end.timeIntervalSince(now)
        guard seconds > 0 else { return "Done" }
        let days = Int(seconds) / 86_400
        if days > 0 { return "\(days)d" }
        return "\(max(1, Int(seconds) / 3_600))h"
    }

    /// Whole days left, floored, for the pace calculation.
    static func daysLeft(until end: Date, now: Date = Date()) -> Int {
        max(0, Int(end.timeIntervalSince(now)) / 86_400)
    }

    /// "Tuesday · 2 days left" — Today's eyebrow.
    static func todayEyebrow(nextEnd: Date?, now: Date = Date()) -> String {
        let weekday = now.formatted(.dateTime.weekday(.wide))
        guard let nextEnd, nextEnd > now else { return weekday }
        let days = daysLeft(until: nextEnd, now: now)
        if days == 0 { return "\(weekday) · ends today" }
        return "\(weekday) · \(days) day\(days == 1 ? "" : "s") left"
    }

    /// "last synced 4h ago" for the stale-health row.
    static func syncAge(from date: Date, now: Date = Date()) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        let hours = Int(seconds) / 3_600
        if hours >= 24 { return "\(hours / 24)d ago" }
        if hours >= 1 { return "\(hours)h ago" }
        return "\(max(1, Int(seconds) / 60))m ago"
    }

    /// Health data older than this shows the inline amber staleness row.
    static let staleThreshold: TimeInterval = 2 * 3_600

    static func isStale(_ date: Date?, now: Date = Date()) -> Bool {
        guard let date else { return false }
        return now.timeIntervalSince(date) > staleThreshold
    }
}
