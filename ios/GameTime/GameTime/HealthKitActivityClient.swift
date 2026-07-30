import Foundation
import GameTimeCore
import HealthKit

/// HealthKit does not disclose whether read access was denied. A completed
/// request means only that HealthKit processed the authorization sheet; an empty
/// query may represent no samples or samples the person did not authorize.
enum ActivityAuthorizationOutcome: Equatable, Sendable {
  case requestCompleted
  case healthDataUnavailable
}

enum ActivityClientError: LocalizedError, Equatable, Sendable {
  case healthDataUnavailable
  case invalidChallengeWindow
  case authorizationRequestFailed
  case sampleQueryFailed

  var errorDescription: String? {
    switch self {
    case .healthDataUnavailable:
      "Activity data is unavailable on this device."
    case .invalidChallengeWindow:
      "The challenge activity window is invalid."
    case .authorizationRequestFailed:
      "GameTime could not complete the activity permission request."
    case .sampleQueryFailed:
      "GameTime could not read activity for this challenge."
    }
  }
}

@MainActor
protocol ActivityClient: AnyObject {
  func requestStepReadAuthorization() async throws
    -> ActivityAuthorizationOutcome

  func stepBuckets(
    overlapping challengeWindow: DateInterval,
    timeZoneSchedule: ContestTimeZoneSchedule,
    asOf: Date
  ) async throws -> [HourlyBucket]
}

/// A framework-free snapshot of the HealthKit fields used by GameTimeCore.
///
/// Keeping HealthKit objects out of this value makes provenance decisions and
/// the statistics-to-ledger adapter independently testable.
struct ActivityStepSample: Equatable, Sendable, HealthSampleDescriptor {
  // Infer the core metric type from a core value so the app target's separate
  // presentation enum cannot shadow it.
  let metric = HourlyBucket(
    metric: .steps,
    bucketStart: .distantPast,
    provenance: .unknown,
    value: 0,
    sampleCount: 0
  ).metric
  let start: Date
  let end: Date
  let value: Double
  let wasUserEntered: Bool
  let sourceBundleIdentifier: String?
  let deviceManufacturer: String?
  let deviceModel: String?

  var provenance: MetricProvenance {
    ProvenanceClassifier.classify(self)
  }
}

struct ActivityStepStatistic: Equatable, Sendable {
  let start: Date
  let end: Date
  let value: Double
}

private struct ActivityStepIntervalKey: Hashable, Sendable {
  let start: Date
  let end: Date

  init(_ interval: DateInterval) {
    start = interval.start
    end = interval.end
  }

  init(_ statistic: ActivityStepStatistic) {
    start = statistic.start
    end = statistic.end
  }
}

struct ActivityStepStatisticsQueryPlan: Equatable, Sendable {
  let intervals: [DateInterval]
  let intervalSeconds: Int

  var start: Date { intervals[0].start }
  var end: Date { intervals[intervals.count - 1].end }
}

enum HealthKitStepStatisticsPlanner {
  static func plans(
    for intervals: [DateInterval]
  ) -> [ActivityStepStatisticsQueryPlan] {
    var plans: [ActivityStepStatisticsQueryPlan] = []

    for interval in intervals.sorted(by: { $0.start < $1.start }) {
      let roundedDuration = interval.duration.rounded()
      guard
        interval.duration.isFinite,
        interval.duration > 0,
        abs(interval.duration - roundedDuration) < 0.000_001,
        let seconds = Int(exactly: roundedDuration),
        seconds > 0
      else {
        return []
      }

      if let last = plans.last,
        last.intervalSeconds == seconds,
        last.end == interval.start
      {
        plans[plans.count - 1] = ActivityStepStatisticsQueryPlan(
          intervals: last.intervals + [interval],
          intervalSeconds: seconds
        )
      } else {
        plans.append(
          ActivityStepStatisticsQueryPlan(
            intervals: [interval],
            intervalSeconds: seconds
          )
        )
      }
    }

    return plans
  }
}

enum HealthKitStepSampleAdapter {
  static func samples(
    from samples: [HKSample],
    overlapping challengeWindow: DateInterval
  ) -> [ActivityStepSample] {
    samples.compactMap {
      guard let quantitySample = $0 as? HKQuantitySample else {
        return nil
      }
      return sample(
        from: quantitySample,
        overlapping: challengeWindow
      )
    }
  }

  static func pairedSamples(
    from samples: [HKQuantitySample],
    overlapping challengeWindow: DateInterval
  ) -> [(sample: HKQuantitySample, descriptor: ActivityStepSample)] {
    samples.compactMap { quantitySample in
      guard
        let descriptor = sample(
          from: quantitySample,
          overlapping: challengeWindow
        )
      else {
        return nil
      }
      return (quantitySample, descriptor)
    }
  }

  private static func sample(
    from quantitySample: HKQuantitySample,
    overlapping challengeWindow: DateInterval
  ) -> ActivityStepSample? {
    guard
      overlaps(
        start: quantitySample.startDate,
        end: quantitySample.endDate,
        interval: challengeWindow
      )
    else {
      return nil
    }

    return ActivityStepSample(
      start: quantitySample.startDate,
      end: quantitySample.endDate,
      value: quantitySample.quantity.doubleValue(
        for: .count()
      ),
      wasUserEntered: quantitySample.metadata?[
        HKMetadataKeyWasUserEntered
      ] as? Bool ?? false,
      sourceBundleIdentifier: quantitySample.sourceRevision
        .source.bundleIdentifier,
      deviceManufacturer: quantitySample.device?.manufacturer,
      deviceModel: quantitySample.device?.model
    )
  }

  fileprivate static func overlaps(
    start: Date,
    end: Date,
    interval: DateInterval
  ) -> Bool {
    let isInstantaneous = start == end
    let overlapsStart =
      end > interval.start
      || (isInstantaneous && start == interval.start)
    return overlapsStart && start < interval.end
  }
}

/// Converts HealthKit's source-merged statistics into the ledger's device row.
///
/// A raw sum of iPhone and Apple Watch samples double-counts periods where both
/// devices recorded the same walk. HealthKit's cumulative statistics merge
/// those sources using the person's Health source priority. GameTime requests
/// that merged value only for raw samples independently classified as genuine
/// Apple-device observations. Manual, unknown, and third-party contributions
/// are deliberately excluded from this first steps slice.
enum HealthKitStepStatisticsAdapter {
  static func buckets(
    statistics: [ActivityStepStatistic],
    expectedIntervals: [DateInterval],
    deviceSamples: [ActivityStepSample]
  ) -> [HourlyBucket] {
    let expected = Set(
      expectedIntervals.map(ActivityStepIntervalKey.init)
    )
    let groupedStatistics = Dictionary(
      grouping: statistics,
      by: ActivityStepIntervalKey.init
    )

    return expectedIntervals.compactMap { interval in
      let key = ActivityStepIntervalKey(interval)
      guard
        expected.contains(key),
        let matches = groupedStatistics[key],
        matches.count == 1,
        let statistic = matches.first,
        statistic.value.isFinite,
        statistic.value > 0
      else {
        return nil
      }

      let contributors = deviceSamples.filter {
        $0.provenance == .device
          && HealthKitStepSampleAdapter.overlaps(
            start: $0.start,
            end: $0.end,
            interval: interval
          )
      }
      guard
        !contributors.isEmpty,
        contributors.count <= 100_000
      else {
        return nil
      }

      return HourlyBucket(
        metric: .steps,
        bucketStart: interval.start,
        provenance: .device,
        value: (statistic.value * 100).rounded() / 100,
        sampleCount: contributors.count,
        sourceBundleIdentifier: agreedValue(
          contributors.map(\.sourceBundleIdentifier)
        ),
        deviceModel: agreedValue(
          contributors.map(\.deviceModel)
        )
      )
    }
  }

  private static func agreedValue(
    _ values: [String?]
  ) -> String? {
    let present = values.compactMap { $0 }
    guard
      present.count == values.count,
      Set(present).count == 1
    else {
      return nil
    }
    return present.first
  }
}

@MainActor
final class HealthKitActivityClient: ActivityClient {
  private let healthStore: HKHealthStore

  init(healthStore: HKHealthStore = HKHealthStore()) {
    self.healthStore = healthStore
  }

  func requestStepReadAuthorization() async throws
    -> ActivityAuthorizationOutcome
  {
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
      // Do not surface HealthKit's underlying error or infer read denial.
      throw ActivityClientError.authorizationRequestFailed
    }
  }

  func stepBuckets(
    overlapping challengeWindow: DateInterval,
    timeZoneSchedule: ContestTimeZoneSchedule,
    asOf: Date
  ) async throws -> [HourlyBucket] {
    guard HKHealthStore.isHealthDataAvailable() else {
      throw ActivityClientError.healthDataUnavailable
    }
    guard challengeWindow.duration > 0 else {
      throw ActivityClientError.invalidChallengeWindow
    }

    let intervals = HourlyBucketer(
      timeZoneSchedule: timeZoneSchedule
    ).completedBucketIntervals(
      in: challengeWindow,
      asOf: asOf
    )
    guard !intervals.isEmpty else { return [] }

    let plans = HealthKitStepStatisticsPlanner.plans(
      for: intervals
    )
    guard
      !plans.isEmpty,
      plans.flatMap(\.intervals) == intervals
    else {
      throw ActivityClientError.sampleQueryFailed
    }

    let quantityType = try stepType()
    let queryWindow = DateInterval(
      start: intervals[0].start,
      end: intervals[intervals.count - 1].end
    )
    let quantitySamples = try await stepSamples(
      quantityType: quantityType,
      overlapping: queryWindow
    )
    let pairedSamples = HealthKitStepSampleAdapter.pairedSamples(
      from: quantitySamples,
      overlapping: queryWindow
    )
    let devicePairs = pairedSamples.filter {
      $0.descriptor.provenance == .device
    }
    guard !devicePairs.isEmpty else { return [] }

    let sourceRevisions = Set(
      devicePairs.map { $0.sample.sourceRevision }
    )
    let devices = Set(
      devicePairs.compactMap { $0.sample.device }
    )
    guard
      !sourceRevisions.isEmpty,
      !devices.isEmpty
    else {
      return []
    }

    let statistics = try await mergedDeviceStepStatistics(
      quantityType: quantityType,
      plans: plans,
      sourceRevisions: sourceRevisions,
      devices: devices
    )
    return HealthKitStepStatisticsAdapter.buckets(
      statistics: statistics,
      expectedIntervals: intervals,
      deviceSamples: devicePairs.map(\.descriptor)
    )
  }

  private func stepSamples(
    quantityType: HKQuantityType,
    overlapping window: DateInterval
  ) async throws -> [HKQuantitySample] {
    let predicate = HKQuery.predicateForSamples(
      withStart: window.start,
      end: window.end,
      options: []
    )
    let sortDescriptors = [
      NSSortDescriptor(
        key: HKSampleSortIdentifierStartDate,
        ascending: true
      ),
      NSSortDescriptor(
        key: HKSampleSortIdentifierEndDate,
        ascending: true
      ),
    ]

    return try await withCheckedThrowingContinuation { continuation in
      let query = HKSampleQuery(
        sampleType: quantityType,
        predicate: predicate,
        limit: HKObjectQueryNoLimit,
        sortDescriptors: sortDescriptors
      ) { _, samples, error in
        guard error == nil else {
          continuation.resume(
            throwing: ActivityClientError.sampleQueryFailed
          )
          return
        }
        guard
          let quantitySamples = samples as? [HKQuantitySample]
        else {
          continuation.resume(
            throwing: ActivityClientError.sampleQueryFailed
          )
          return
        }
        continuation.resume(returning: quantitySamples)
      }
      healthStore.execute(query)
    }
  }

  private func mergedDeviceStepStatistics(
    quantityType: HKQuantityType,
    plans: [ActivityStepStatisticsQueryPlan],
    sourceRevisions: Set<HKSourceRevision>,
    devices: Set<HKDevice>
  ) async throws -> [ActivityStepStatistic] {
    var statistics: [ActivityStepStatistic] = []
    for plan in plans {
      statistics.append(
        contentsOf: try await mergedDeviceStepStatistics(
          quantityType: quantityType,
          plan: plan,
          sourceRevisions: sourceRevisions,
          devices: devices
        )
      )
    }
    return statistics
  }

  private func mergedDeviceStepStatistics(
    quantityType: HKQuantityType,
    plan: ActivityStepStatisticsQueryPlan,
    sourceRevisions: Set<HKSourceRevision>,
    devices: Set<HKDevice>
  ) async throws -> [ActivityStepStatistic] {
    let datePredicate = HKQuery.predicateForSamples(
      withStart: plan.start,
      end: plan.end,
      options: []
    )
    let sourcePredicate = HKQuery.predicateForObjects(
      from: sourceRevisions
    )
    let devicePredicate = HKQuery.predicateForObjects(
      from: devices
    )
    let manualPredicate = HKQuery.predicateForObjects(
      withMetadataKey: HKMetadataKeyWasUserEntered,
      operatorType: .equalTo,
      value: true
    )
    let predicate = NSCompoundPredicate(
      andPredicateWithSubpredicates: [
        datePredicate,
        sourcePredicate,
        devicePredicate,
        NSCompoundPredicate(
          notPredicateWithSubpredicate: manualPredicate
        ),
      ]
    )
    let expected = Set(
      plan.intervals.map(ActivityStepIntervalKey.init)
    )

    return try await withCheckedThrowingContinuation { continuation in
      let query = HKStatisticsCollectionQuery(
        quantityType: quantityType,
        quantitySamplePredicate: predicate,
        options: .cumulativeSum,
        anchorDate: plan.start,
        intervalComponents: DateComponents(
          second: plan.intervalSeconds
        )
      )
      query.initialResultsHandler = { _, collection, error in
        guard error == nil, let collection else {
          continuation.resume(
            throwing: ActivityClientError.sampleQueryFailed
          )
          return
        }

        var results: [ActivityStepStatistic] = []
        collection.enumerateStatistics(
          from: plan.start,
          to: plan.end
        ) { statistic, _ in
          let interval = DateInterval(
            start: statistic.startDate,
            end: statistic.endDate
          )
          guard
            expected.contains(ActivityStepIntervalKey(interval)),
            let quantity = statistic.sumQuantity()
          else {
            return
          }
          results.append(
            ActivityStepStatistic(
              start: interval.start,
              end: interval.end,
              value: quantity.doubleValue(for: .count())
            )
          )
        }
        continuation.resume(returning: results)
      }
      healthStore.execute(query)
    }
  }

  private func stepType() throws -> HKQuantityType {
    guard
      let type = HKObjectType.quantityType(forIdentifier: .stepCount)
    else {
      throw ActivityClientError.healthDataUnavailable
    }
    return type
  }
}

/// Used when the integration is intentionally absent, including non-staging
/// dependency injection. It never requests HealthKit access.
@MainActor
final class DisabledActivityClient: ActivityClient {
  func requestStepReadAuthorization() async throws
    -> ActivityAuthorizationOutcome
  {
    .healthDataUnavailable
  }

  func stepBuckets(
    overlapping challengeWindow: DateInterval,
    timeZoneSchedule: ContestTimeZoneSchedule,
    asOf: Date
  ) async throws -> [HourlyBucket] {
    _ = challengeWindow
    _ = timeZoneSchedule
    _ = asOf
    throw ActivityClientError.healthDataUnavailable
  }
}
