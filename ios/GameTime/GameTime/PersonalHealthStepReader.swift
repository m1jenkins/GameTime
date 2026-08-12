import Foundation
import HealthKit

enum PersonalHealthStepReaderError: LocalizedError, Equatable, Sendable {
    case unavailable
    case invalidChallenge
    case authorizationFailed
    case queryFailed

    var errorDescription: String? {
        switch self {
        case .unavailable:
            "Apple Health isn’t available on this device."
        case .invalidChallenge:
            "This challenge has an invalid step window."
        case .authorizationFailed:
            "GameTime couldn’t finish connecting to Apple Health."
        case .queryFailed:
            "GameTime couldn’t update your steps from Apple Health."
        }
    }
}

struct PersonalHealthDayQuery: Equatable, Sendable {
    let localDate: String
    let interval: DateInterval?
}

struct PersonalHealthSnapshotPlan: Equatable, Sendable {
    let queryThrough: Date
    let days: [PersonalHealthDayQuery]
}

enum PersonalHealthSnapshotPlanner {
    static func plan(
        terms: FrozenPersonalTerms,
        observedAt: Date
    ) throws -> PersonalHealthSnapshotPlan {
        guard terms.endsAt > terms.startsAt,
            TimeZone(identifier: terms.timezone) != nil
        else { throw PersonalHealthStepReaderError.invalidChallenge }

        let calendar = PersonalChallengeStart.calendar(terms.timezone)
        let firstDay = calendar.startOfDay(for: terms.startsAt)
        let queryThrough = min(observedAt, terms.endsAt)
        let days = try (0..<7).map { offset -> PersonalHealthDayQuery in
            guard
                let dayStart = calendar.date(
                    byAdding: .day,
                    value: offset,
                    to: firstDay
                ),
                let nextDay = calendar.date(
                    byAdding: .day,
                    value: 1,
                    to: dayStart
                )
            else { throw PersonalHealthStepReaderError.invalidChallenge }
            let start = max(dayStart, terms.startsAt)
            let end = min(nextDay, min(terms.endsAt, queryThrough))
            return PersonalHealthDayQuery(
                localDate: localDate(dayStart, calendar: calendar),
                interval: end > start
                    ? DateInterval(start: start, end: end)
                    : nil
            )
        }
        return PersonalHealthSnapshotPlan(
            queryThrough: queryThrough,
            days: days
        )
    }

    private static func localDate(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }
}

@MainActor
protocol PersonalHealthStepReading: AnyObject {
    func requestAuthorization() async throws -> ActivityAuthorizationOutcome
    func readSnapshot(
        challengeID: UUID,
        terms: FrozenPersonalTerms,
        termsFingerprint: String,
        observedAt: Date
    ) async throws -> PersonalStepSnapshot
}

@MainActor
protocol HealthKitDailyStepStatisticsQuerying: AnyObject {
    func cumulativeSteps(
        type: HKQuantityType,
        interval: DateInterval
    ) async throws -> Double
}

@MainActor
final class HealthKitDailyStepStatisticsQuery: HealthKitDailyStepStatisticsQuerying {
    static let statisticsOptions: HKStatisticsOptions = .cumulativeSum
    private let healthStore: HKHealthStore

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
    }

    func cumulativeSteps(
        type: HKQuantityType,
        interval: DateInterval
    ) async throws -> Double {
        let predicate = Self.predicate(for: interval)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: Self.statisticsOptions
            ) { _, statistics, error in
                guard error == nil else {
                    continuation.resume(
                        throwing: PersonalHealthStepReaderError.queryFailed
                    )
                    return
                }
                let total = statistics?.sumQuantity()?.doubleValue(
                    for: .count()
                ) ?? 0
                continuation.resume(returning: total)
            }
            healthStore.execute(query)
        }
    }

    /// Locked v2 policy: HealthKit merges every writer and GameTime excludes
    /// only samples explicitly marked as manually entered.
    static func predicate(for interval: DateInterval) -> NSCompoundPredicate {
        let date = HKQuery.predicateForSamples(
            withStart: interval.start,
            end: interval.end,
            options: [.strictStartDate, .strictEndDate]
        )
        let wasManuallyEntered = HKQuery.predicateForObjects(
            withMetadataKey: HKMetadataKeyWasUserEntered,
            operatorType: .equalTo,
            value: true
        )
        return NSCompoundPredicate(
            andPredicateWithSubpredicates: [
                date,
                NSCompoundPredicate(
                    notPredicateWithSubpredicate: wasManuallyEntered
                ),
            ]
        )
    }
}

@MainActor
final class HealthKitPersonalHealthStepReader: PersonalHealthStepReading {
    private let healthStore: HKHealthStore
    private let statistics: any HealthKitDailyStepStatisticsQuerying

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
        statistics = HealthKitDailyStepStatisticsQuery(
            healthStore: healthStore
        )
    }

    init(
        healthStore: HKHealthStore,
        statistics: any HealthKitDailyStepStatisticsQuerying
    ) {
        self.healthStore = healthStore
        self.statistics = statistics
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        guard HKHealthStore.isHealthDataAvailable() else {
            return .healthDataUnavailable
        }
        do {
            try await healthStore.requestAuthorization(
                toShare: [],
                read: [try stepType()]
            )
            return .requestCompleted
        } catch {
            throw PersonalHealthStepReaderError.authorizationFailed
        }
    }

    func readSnapshot(
        challengeID: UUID,
        terms: FrozenPersonalTerms,
        termsFingerprint: String,
        observedAt: Date = Date()
    ) async throws -> PersonalStepSnapshot {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw PersonalHealthStepReaderError.unavailable
        }
        let plan = try PersonalHealthSnapshotPlanner.plan(
            terms: terms,
            observedAt: observedAt
        )
        let type = try stepType()
        var days: [PersonalStepSnapshot.Day] = []
        days.reserveCapacity(7)
        for day in plan.days {
            try Task.checkCancellation()
            let value: Double
            if let interval = day.interval {
                value = try await statistics.cumulativeSteps(
                    type: type,
                    interval: interval
                )
            } else {
                value = 0
            }
            guard value.isFinite, value >= 0 else {
                throw PersonalHealthStepReaderError.queryFailed
            }
            let total = value >= Double(Int.max)
                ? Int.max
                : Int(value.rounded(.towardZero))
            days.append(
                PersonalStepSnapshot.Day(
                    localDate: day.localDate,
                    totalSteps: total
                )
            )
        }
        return PersonalStepSnapshot(
            challengeID: challengeID,
            termsFingerprint: termsFingerprint,
            observedAt: observedAt,
            queryThrough: plan.queryThrough,
            dailyProgress: days
        )
    }

    private func stepType() throws -> HKQuantityType {
        guard let type = HKObjectType.quantityType(
            forIdentifier: .stepCount
        ) else { throw PersonalHealthStepReaderError.unavailable }
        return type
    }
}

@MainActor
final class DisabledPersonalHealthStepReader: PersonalHealthStepReading {
    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        .healthDataUnavailable
    }

    func readSnapshot(
        challengeID: UUID,
        terms: FrozenPersonalTerms,
        termsFingerprint: String,
        observedAt: Date
    ) async throws -> PersonalStepSnapshot {
        _ = (challengeID, terms, termsFingerprint, observedAt)
        throw PersonalHealthStepReaderError.unavailable
    }
}
