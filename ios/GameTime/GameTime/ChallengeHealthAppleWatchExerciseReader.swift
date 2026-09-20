import Foundation
import GameTimeCore
import HealthKit

/// Local-only Apple Exercise Time reader. This reader intentionally has no
/// upload path: the core Exercise policy remains unavailable until HealthKit
/// exposes causal workout/activity lineage.
@MainActor
final class ChallengeHealthAppleWatchExerciseReader: ChallengeHealthStore {
  private let querying: any ChallengeHealthAppleWatchExerciseQuerying

  init(healthStore: HKHealthStore = HKHealthStore()) {
    querying = ChallengeHealthHealthKitExerciseQueryCoordinator(healthStore: healthStore)
  }

  init(querying: any ChallengeHealthAppleWatchExerciseQuerying) { self.querying = querying }

  func read(_ request: ChallengeHealthReadRequest) async -> ChallengeHealthStoreOutcome {
    guard request.binding.metric == .exerciseSeconds else { return .unavailable(.queryFailed) }
    guard querying.isHealthDataAvailable else { return .unavailable(.protectedDataUnavailable) }
    let observedAt = Date()
    let interval = request.queryWindow.interval
    guard interval.end <= observedAt else { return .unavailable(.queryFailed) }
    do {
      let records = try await querying.exercise(in: interval)
      try Task.checkCancellation()
      let truncated = records.count > WeeklySourceFeasibility.maximumRecords
      return .snapshot(ChallengeHealthSnapshot(
        request: request,
        records: Array(records.prefix(WeeklySourceFeasibility.maximumRecords)),
        deletedRecordIDs: [], observedAt: observedAt, sourceFreshness: observedAt,
        earliestAuthorizedSampleDate: nil, evidence: truncated ? .truncated : .boundedSnapshot
      ))
    } catch is CancellationError { return .unavailable(.cancelled) }
      catch { return .unavailable(.queryFailed) }
  }
}

@MainActor
protocol ChallengeHealthAppleWatchExerciseQuerying: AnyObject {
  var isHealthDataAvailable: Bool { get }
  func exercise(in interval: DateInterval) async throws -> [WeeklySourceRecord]
}

@MainActor
private final class ChallengeHealthHealthKitExerciseQueryCoordinator: ChallengeHealthAppleWatchExerciseQuerying {
  private let healthStore: HKHealthStore
  init(healthStore: HKHealthStore) { self.healthStore = healthStore }
  var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  func exercise(in interval: DateInterval) async throws -> [WeeklySourceRecord] {
    let predicate = HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
    return try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(sampleType: HKQuantityType(.appleExerciseTime), predicate: predicate,
                                limit: WeeklySourceFeasibility.maximumRecords + 1,
                                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) {
        _, samples, error in
        if let error { continuation.resume(throwing: error); return }
        continuation.resume(returning: (samples ?? []).compactMap(Self.record))
      }
      healthStore.execute(query)
    }
  }

  nonisolated private static func record(_ sample: HKSample) -> WeeklySourceRecord? {
    guard let quantity = sample as? HKQuantitySample else { return nil }
    let revision = sample.sourceRevision
    let os = revision.operatingSystemVersion
    return WeeklySourceRecord(
      id: sample.uuid, metric: .appleExerciseMinutes, start: sample.startDate, end: sample.endDate,
      value: quantity.quantity.doubleValue(for: .minute()), sourceBundleIdentifier: revision.source.bundleIdentifier,
      sourceVersion: revision.version, sourceProductType: revision.productType,
      sourceOperatingSystemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
      deviceManufacturer: sample.device?.manufacturer, deviceModel: sample.device?.model,
      wasUserEntered: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool,
      syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
      syncVersion: sample.metadata?[HKMetadataKeySyncVersion] as? Int
    )
  }
}
