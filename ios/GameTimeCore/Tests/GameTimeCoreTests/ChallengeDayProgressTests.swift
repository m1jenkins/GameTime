import Foundation
import Testing
@testable import GameTimeCore

@Suite("Challenge day-by-day progress for Home")
struct ChallengeDayProgressTests {
    private let zone = TimeZone(identifier: "America/Chicago")!
    /// Midnight Saturday, October 10, 2026 in Chicago.
    private let start = Date(timeIntervalSince1970: 1_791_608_400)
    private func at(day: Double, hour: Double) -> Date { start.addingTimeInterval(day * 86_400 + hour * 3_600) }
    private func span(day: Double, hour: Double, _ value: Double) -> ChallengeHealthCountedSpan {
        ChallengeHealthCountedSpan(start: at(day: day, hour: hour), end: at(day: day, hour: hour + 0.25), value: value)
    }
    private func progress(now: Date, total: Int?, counted: [ChallengeHealthCountedSpan]?) -> ChallengeDayProgress {
        ChallengeDayProgress(start: start, end: at(day: 7, hour: 0), dayCount: 7, timeZone: zone, now: now,
                             target: 100_000, total: total, counted: counted)
    }

    @Test("before the start every day is empty and the pace is an even share")
    func upcoming() {
        let week = progress(now: at(day: -1, hour: 10), total: nil, counted: nil)
        #expect(week.standing == .upcoming)
        #expect(week.daysUntilStart == 1)
        #expect(week.daysLeft == 7)
        #expect(week.dailyPace == 14_286)
        #expect(week.days.count == 7 && week.days.allSatisfy { $0.isFuture && $0.value == nil })
        #expect(week.best == nil && week.finishedDayAverage == nil)
    }

    @Test("counted activity lands on its local day and later days stay unknown")
    func buckets() {
        let counted = [span(day: 0, hour: 9, 10_000.6), span(day: 0, hour: 18, 6_420), span(day: 1, hour: 12, 18_900),
                       span(day: 2, hour: 8, 7_130), span(day: 3, hour: 9, 11_250)]
        let week = progress(now: at(day: 3, hour: 14), total: 53_700, counted: counted)
        #expect(week.days.map(\.value) == [16_420, 18_900, 7_130, 11_250, nil, nil, nil])
        #expect(week.days[3].isToday && !week.days[3].isFuture)
        #expect(week.days[4].isFuture)
        #expect(week.daysLeft == 4)
        #expect(week.best?.index == 1)
        #expect(week.finishedDayAverage == 14_150)
        #expect(week.standing == .ahead)
        #expect(week.remaining == 46_300)
        #expect(week.neededPerDay == 11_575)
    }

    @Test("without a reading, days so far are unknown, not zero")
    func noReading() {
        let week = progress(now: at(day: 2, hour: 12), total: nil, counted: nil)
        #expect(week.standing == .noUpdate)
        #expect(week.days.allSatisfy { $0.value == nil })
        let empty = progress(now: at(day: 2, hour: 12), total: nil, counted: [])
        #expect(empty.days.map(\.value) == [0, 0, 0, nil, nil, nil, nil])
        #expect(empty.best == nil)
    }

    @Test("standing follows the saved total against the elapsed share of the goal")
    func standing() {
        #expect(progress(now: at(day: 3, hour: 12), total: 40_000, counted: nil).standing == .short)
        #expect(progress(now: at(day: 3, hour: 12), total: 100_000, counted: nil).standing == .reached)
        #expect(progress(now: at(day: 3, hour: 12), total: 100_000, counted: nil).neededPerDay == nil)
        let last = progress(now: at(day: 6, hour: 20), total: 92_000, counted: nil)
        #expect(last.daysLeft == 1 && last.neededPerDay == 8_000)
        #expect(progress(now: at(day: 7, hour: 1), total: 92_000, counted: nil).standing == .finished)
    }
}
