import Foundation

struct ChallengeV1Policy: Equatable, Hashable, Identifiable, Sendable {
    enum Mode: String, CaseIterable, Sendable { case friend, personal, community
        var title: String { switch self { case .friend: "With friends"; case .personal: "Personal goal"; case .community: "Community" } }
    }
    enum Metric: String, CaseIterable, Sendable { case steps, exercise, distance, timed
        var title: String { switch self { case .steps: "Steps"; case .exercise: "Exercise time"; case .distance: "Running distance"; case .timed: "Timed run" } }
        var symbol: String { switch self { case .steps: "shoeprints.fill"; case .exercise: "clock"; case .distance: "figure.run"; case .timed: "stopwatch" } }
        var targetPrompt: String { switch self { case .steps: "Total steps"; case .exercise: "Total minutes:seconds"; case .distance: "Total kilometres"; case .timed: "Time to beat, minutes:seconds" } }
        var inputHelp: String {
            switch self {
            case .steps: "Enter a whole number of steps from 1 to 1,000,000,000."
            case .exercise, .timed: "Enter minutes and seconds, such as 30:00. Seconds must be 00–59, and the time must be greater than zero."
            case .distance: "Enter kilometres greater than zero and up to 1,000, using a decimal point, such as 1.5. Use no more than six decimal places."
            }
        }
        func display(_ value: Int) -> String {
            switch self {
            case .steps: "\(value.formatted()) steps"
            case .exercise, .timed: "\((value / 60).formatted()) min \(value % 60) sec"
            case .distance: "\(NSDecimalNumber(decimal: Decimal(value) / 1_000_000).stringValue) km"
            }
        }
        func parse(_ text: String) -> Int? {
            let raw = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let result: Int?
            switch self {
            case .steps: result = raw.allSatisfy(\.isNumber) ? Int(raw) : nil
            case .exercise, .timed:
                let parts = raw.split(separator: ":", omittingEmptySubsequences: false)
                if parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
                   let minutes = Int(parts[0]), let seconds = Int(parts[1]), (0..<60).contains(seconds), minutes <= 16_666_666 {
                    result = minutes * 60 + seconds
                } else { result = nil }
            case .distance:
                if raw.range(of: "^[0-9]+(?:\\.[0-9]{1,6})?$", options: .regularExpression) != nil,
                   let number = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) {
                    let mm = number * 1_000_000
                    result = mm <= 1_000_000_000 ? NSDecimalNumber(decimal: mm).intValue : nil
                } else { result = nil }
            }
            return result.flatMap { (1...1_000_000_000).contains($0) ? $0 : nil }
        }
    }
    enum Competition: String, CaseIterable, Sendable { case goal, leaderboard
        var title: String { self == .goal ? "Meet your goal" : "Best result wins" }
    }
    let mode: Mode; let metric: Metric; let competition: Competition
    var id: String { "\(mode.rawValue)_\(metric.rawValue)_\(competition.rawValue)_v1" }
    init?(rawValue: String) {
        let parts = rawValue.split(separator: "_")
        guard parts.count == 4, parts[3] == "v1", let mode = Mode(rawValue: String(parts[0])),
              let metric = Metric(rawValue: String(parts[1])), let competition = Competition(rawValue: String(parts[2])),
              (mode == .friend || (mode == .personal && competition == .goal) || (mode == .community && metric == .steps && competition == .goal)) else { return nil }
        self.mode = mode; self.metric = metric; self.competition = competition
    }
    static let all: [Self] = Mode.allCases.flatMap { mode in Metric.allCases.flatMap { metric in
        Competition.allCases.compactMap { Self(rawValue: "\(mode.rawValue)_\(metric.rawValue)_\($0.rawValue)_v1") }
    } }
    var hasTarget: Bool { competition == .goal }
    var title: String { mode == .personal ? "Your \(metric.title.lowercased()) goal" : mode == .community ? "Community steps" : "\(metric.title) \(hasTarget ? "together" : "challenge")" }
    var scoring: String {
        if competition == .leaderboard {
            return metric == .timed ? "Your fastest eligible whole run wins. Equal times share the win. There is no target time." : "The highest eligible total wins. Equal totals share the win. There is no qualifying target."
        }
        return metric == .timed ? "Finish an eligible whole run strictly under your agreed time. A time equal to your goal does not meet it. Pauses count toward elapsed time." : "Reach at least your agreed total during the challenge to meet your goal."
    }
    var missing: String {
        if competition == .leaderboard { return "If any remaining result is missing or unclear, the challenge doesn’t count and all simulated entries return." }
        if mode == .personal { return "A missing or unclear result never proves a missed goal. Your simulated entry returns if the result cannot be confirmed." }
        return "A missing or unclear result never proves a missed goal. We return that person’s simulated entry and score the remaining results only if the agreed minimum remains."
    }
    var allocation: String {
        if competition == .leaderboard { return "Winners split the remaining simulated pool evenly. Any indivisible remainder stays unallocated." }
        if mode == .personal { return "Meeting your goal returns your simulated entry. A confirmed miss leaves it unallocated. Nothing can be paid out or redeemed." }
        return "People who meet their goals recover their entries and share confirmed misses evenly. Any remainder and an all-miss pool stay unallocated."
    }
}

/// On-device arithmetic only. Accepted source adapters must provide eligible
/// history before calling this; no baseline or route enters a request payload.
enum ChallengeV1Suggestion {
    static func value(policy: ChallengeV1Policy, days: Int, eligible28DayTotal: Int?, best90DayElapsedSeconds: Int?) -> Int? {
        guard policy.hasTarget, policy.mode != .community, (1...30).contains(days) else { return nil }
        let value: Int64
        if policy.metric == .timed {
            guard let best = best90DayElapsedSeconds, (1...1_000_000_000).contains(best) else { return nil }
            value = Int64(best) * 98 / 100
        } else {
            guard let total = eligible28DayTotal, (1...1_000_000_000).contains(total) else { return nil }
            value = (Int64(total) * Int64(days) * 110 + 2799) / 2800
        }
        return (1...1_000_000_000).contains(value) ? Int(value) : nil
    }
}
