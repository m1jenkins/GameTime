import Foundation

/// One stretch of activity a challenge counted, in the challenge's unit (steps,
/// or seconds of exercise). Times and amounts only: no source, device or record id.
public struct ChallengeHealthCountedSpan: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let value: Double
    public init(start: Date, end: Date, value: Double) {
        self.start = start; self.end = end; self.value = value
    }
}

/// Home's picture of a challenge's days: what each day counted on this phone
/// and where the saved total stands against an even daily pace. Display only:
/// it never decides a result, and a day this phone hasn't read is unknown, not zero.
public struct ChallengeDayProgress: Equatable, Sendable {
    public struct Day: Equatable, Sendable {
        public let index: Int
        public let start: Date
        /// nil when this phone has nothing counted for the day yet.
        public let value: Int?
        public let isToday: Bool
        public let isFuture: Bool
    }
    public enum Standing: Equatable, Sendable {
        case upcoming, noUpdate, reached, ahead, short, finished
    }

    public let days: [Day]
    public let target: Int
    public let total: Int?
    public let standing: Standing
    /// Calendar days until the first day; 0 once it has started.
    public let daysUntilStart: Int
    /// Challenge days left, today included; 0 once it has ended.
    public let daysLeft: Int

    /// The even share of the goal for one day, rounded up.
    public var dailyPace: Int { Self.share(target, days.count) }
    public var remaining: Int? { total.map { max(0, target - $0) } }
    /// The even share of what's left over the days left, rounded up.
    public var neededPerDay: Int? {
        guard let remaining, remaining > 0, daysLeft > 0 else { return nil }
        return Self.share(remaining, daysLeft)
    }
    /// The day with the most counted, earliest on a tie; nil before anything counts.
    public var best: Day? {
        days.reduce(nil as Day?) { best, day in
            guard let value = day.value, value > 0 else { return best }
            return value > (best?.value ?? 0) ? day : best
        }
    }
    /// Average of the finished days this phone has read; today and later are left out.
    public var finishedDayAverage: Int? {
        let finished = days.filter { !$0.isToday && !$0.isFuture }.compactMap(\.value)
        guard !finished.isEmpty else { return nil }
        return Int((Double(finished.reduce(0, +)) / Double(finished.count)).rounded())
    }

    /// `counted` is nil when this phone has no complete reading for the
    /// challenge; days up to today are then unknown rather than empty.
    public init(start: Date, end: Date, dayCount: Int, timeZone: TimeZone, now: Date,
                target: Int, total: Int?, counted: [ChallengeHealthCountedSpan]?) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let first = calendar.startOfDay(for: start)
        let count = max(1, dayCount)
        let starts = (0...count).map { calendar.date(byAdding: .day, value: $0, to: first) ?? first }
        var sums = [Double](repeating: 0, count: count)
        for span in counted ?? [] {
            guard let index = (0..<count).first(where: { span.start >= starts[$0] && span.start < starts[$0 + 1] }) else { continue }
            sums[index] += span.value
        }
        days = (0..<count).map { index in
            let isFuture = now < starts[index]
            let isToday = !isFuture && now < starts[index + 1]
            let value = counted == nil || isFuture ? nil : Int(sums[index].rounded(.down))
            return Day(index: index, start: starts[index], value: value, isToday: isToday, isFuture: isFuture)
        }
        self.target = target
        self.total = total
        if now < start {
            standing = .upcoming
            daysUntilStart = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: first).day ?? 0)
            daysLeft = count
        } else if now >= end {
            standing = .finished
            daysUntilStart = 0
            daysLeft = 0
        } else {
            daysUntilStart = 0
            daysLeft = count - (days.firstIndex(where: \.isToday) ?? (count - 1))
            if let total {
                let elapsed = now.timeIntervalSince(start) / max(1, end.timeIntervalSince(start))
                standing = total >= target ? .reached : Double(total) >= Double(target) * elapsed ? .ahead : .short
            } else {
                standing = .noUpdate
            }
        }
    }

    private static func share(_ amount: Int, _ parts: Int) -> Int {
        Int((Double(amount) / Double(max(1, parts))).rounded(.up))
    }
}
