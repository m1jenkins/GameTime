#if DEBUG || STAGING
import Foundation
import GameTimeCore
import HealthKit

/// Unwired local investigation helper, excluded from Release. Instantiation
/// defaults off; no permission, observer, upload or qualification is automatic.
/// A caller must hold the capture in memory and clear it on account changes.
@MainActor
final class WeeklyHealthSourceProbe {
    private let healthStore: HKHealthStore
    private let localInvestigationEnabled: Bool

    init(localInvestigationEnabled: Bool = false, healthStore: HKHealthStore = HKHealthStore()) {
        self.localInvestigationEnabled = localInvestigationEnabled
        self.healthStore = healthStore
    }

    enum ProbeError: Error {
        case disabled
        case unavailable
        case invalidWindow
    }

    /// Only the investigator's explicit request calls this. Completion does
    /// not disclose read permission or establish complete capture.
    func requestReadAuthorization(for metric: WeeklySourceMetric) async throws {
        guard localInvestigationEnabled else { throw ProbeError.disabled }
        guard HKHealthStore.isHealthDataAvailable() else { throw ProbeError.unavailable }
        var readTypes: Set<HKObjectType> = [sampleType(for: metric)]
        if metric == .runningDistanceMillimeters {
            readTypes.insert(HKQuantityType(.distanceWalkingRunning))
        }
        try await healthStore.requestAuthorization(toShare: [], read: readTypes)
    }

    func capture(
        accountID: UUID, metric: WeeklySourceMetric,
        window: DateInterval, observedAt: Date
    ) async throws -> WeeklySourceCapture {
        guard window.start < window.end,
            window.start.timeIntervalSince1970.isFinite,
            window.end.timeIntervalSince1970.isFinite,
            observedAt.timeIntervalSince1970.isFinite
        else { throw ProbeError.invalidWindow }
        func result(_ state: WeeklySourceReadState, _ records: [WeeklySourceRecord] = []) -> WeeklySourceCapture {
            WeeklySourceCapture(
                accountID: accountID, metric: metric, window: window,
                observedAt: observedAt, state: state, records: records
            )
        }
        guard localInvestigationEnabled else { return result(.disabled) }
        guard HKHealthStore.isHealthDataAvailable() else { return result(.unavailable) }
        // Include boundary-straddling samples for diagnosis, without prorating
        // them or allowing them to qualify. Restrict to finished samples.
        guard observedAt > window.start else { return result(.successfulQuery) }
        let interval = HKQuery.predicateForSamples(
            withStart: window.start, end: min(window.end, observedAt), options: []
        )
        let finished = HKQuery.predicateForSamples(withStart: nil, end: observedAt, options: .strictEndDate)
        var predicates = [interval, finished]
        if metric == .runningDistanceMillimeters {
            predicates.append(HKQuery.predicateForWorkouts(with: .running))
        }
        do {
            let records = try await read(
                type: sampleType(for: metric), metric: metric,
                predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            )
            try Task.checkCancellation()
            let truncated = records.count > WeeklySourceFeasibility.maximumRecords
            let visible = records.filter {
                $0.start < window.end && $0.end <= observedAt &&
                    ($0.start == $0.end ? $0.start >= window.start : $0.end > window.start)
            }
            return result(
                truncated ? .truncated : .successfulQuery,
                Array(visible.prefix(WeeklySourceFeasibility.maximumRecords))
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // No raw error, sample metadata or IDs are logged or uploaded.
            return result(.failed)
        }
    }

    private func sampleType(for metric: WeeklySourceMetric) -> HKSampleType {
        switch metric {
        case .steps: HKQuantityType(.stepCount)
        case .appleExerciseMinutes: HKQuantityType(.appleExerciseTime)
        case .runningDistanceMillimeters: HKObjectType.workoutType()
        }
    }

    private func read(
        type: HKSampleType, metric: WeeklySourceMetric, predicate: NSPredicate
    ) async throws -> [WeeklySourceRecord] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: type, predicate: predicate,
                limit: WeeklySourceFeasibility.maximumRecords + 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                var records: [WeeklySourceRecord] = []
                for sample in samples ?? [] {
                    let value: Double
                    if let quantity = sample as? HKQuantitySample {
                        value = quantity.quantity.doubleValue(for: metric == .steps ? .count() : .minute())
                    } else if let workout = sample as? HKWorkout,
                        let distance = workout.statistics(for: HKQuantityType(.distanceWalkingRunning))?.sumQuantity() {
                        value = distance.doubleValue(for: .meter()) * 1_000
                    } else {
                        // A workout with absent distance must not become zero.
                        continuation.resume(throwing: ProbeError.unavailable)
                        return
                    }
                    records.append(WeeklySourceRecord(
                        id: sample.uuid, metric: metric,
                        start: sample.startDate, end: sample.endDate, value: value,
                        sourceBundleIdentifier: sample.sourceRevision.source.bundleIdentifier,
                        sourceVersion: sample.sourceRevision.version,
                        deviceManufacturer: sample.device?.manufacturer,
                        deviceModel: sample.device?.model,
                        wasUserEntered: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool,
                        syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
                        syncVersion: sample.metadata?[HKMetadataKeySyncVersion] as? Int,
                        reportedWorkoutDurationSeconds: (sample as? HKWorkout)?.duration
                    ))
                }
                continuation.resume(returning: records)
            }
            healthStore.execute(query)
        }
    }
}
#endif
