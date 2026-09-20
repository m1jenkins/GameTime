import Foundation
import GameTimeCore
import HealthKit

/// Bounded whole-workout reader. It keeps the original frozen request while an
/// active window is read only through the observation instant. Anchored changes
/// supply actual deletion UUIDs; an absent workout is never treated as deleted.
@MainActor
final class ChallengeHealthAppleWorkoutReader: ChallengeHealthStore {
  private let querying: any ChallengeHealthAppleWorkoutQuerying
  private var activeScope: ChallengeHealthAppleWorkoutScope?
  private var ledger = ChallengeHealthAppleWorkoutLedger()
  private var generation: UInt64 = 0
  private var attempt: UInt64 = 0

  init(healthStore: HKHealthStore = HKHealthStore()) {
    querying = ChallengeHealthHealthKitWorkoutQueryCoordinator(healthStore: healthStore)
  }

  init(querying: any ChallengeHealthAppleWorkoutQuerying) { self.querying = querying }

  func read(_ request: ChallengeHealthReadRequest) async -> ChallengeHealthStoreOutcome {
    guard request.binding.metric == .runningMillimeters || request.binding.metric == .timedRunElapsedSeconds else {
      return .unavailable(.queryFailed)
    }
    guard querying.isHealthDataAvailable else { return .unavailable(.protectedDataUnavailable) }
    let scope = ChallengeHealthAppleWorkoutScope(request: request)
    guard let ticket = begin(scope) else { return .unavailable(.cancelled) }

    let observedAt = Date()
    let requested = request.queryWindow.interval
    let end = min(requested.end, observedAt)
    guard end > requested.start else {
      return .snapshot(snapshot(request: request, records: [], deletedRecordIDs: [], observedAt: observedAt,
                                evidence: .boundedSnapshot))
    }
    let interval = DateInterval(start: requested.start, end: end)
    do {
      let bounded = try await querying.boundedWorkouts(in: interval)
      try Task.checkCancellation()
      guard isCurrent(ticket, scope: scope) else { return .unavailable(.cancelled) }
      let changes = try await querying.anchoredWorkoutChanges(in: interval, after: ledger.anchor)
      try Task.checkCancellation()
      guard isCurrent(ticket, scope: scope) else { return .unavailable(.cancelled) }
      let merged = ledger.merge(boundedRecords: bounded.records, additions: changes.additions,
                                deletedRecordIDs: changes.deletedRecordIDs, nextAnchor: changes.nextAnchor,
                                changesWereTruncated: changes.wasTruncated)
      let truncated = bounded.wasTruncated || merged.wasTruncated
        || merged.records.count > WeeklySourceFeasibility.maximumRecords
      return .snapshot(snapshot(request: request,
                                records: Array(merged.records.prefix(WeeklySourceFeasibility.maximumRecords)),
                                deletedRecordIDs: merged.deletedRecordIDs, observedAt: observedAt,
                                evidence: truncated ? .truncated : merged.evidence))
    } catch is CancellationError {
      return .unavailable(.cancelled)
    } catch {
      return .unavailable(.queryFailed)
    }
  }

  private func begin(_ scope: ChallengeHealthAppleWorkoutScope) -> (UInt64, UInt64)? {
    guard !Task.isCancelled else { return nil }
    if activeScope != scope {
      activeScope = scope
      ledger = ChallengeHealthAppleWorkoutLedger()
      guard generation < UInt64.max else { return nil }
      generation += 1
      attempt = 0
    }
    guard attempt < UInt64.max else { return nil }
    attempt += 1
    return (generation, attempt)
  }

  private func isCurrent(_ ticket: (UInt64, UInt64), scope: ChallengeHealthAppleWorkoutScope) -> Bool {
    !Task.isCancelled && activeScope == scope && generation == ticket.0 && attempt == ticket.1
  }

  private func snapshot(request: ChallengeHealthReadRequest, records: [WeeklySourceRecord],
                        deletedRecordIDs: Set<UUID>, observedAt: Date,
                        evidence: ChallengeHealthEvidence) -> ChallengeHealthSnapshot {
    ChallengeHealthSnapshot(request: request, records: records, deletedRecordIDs: deletedRecordIDs,
      observedAt: observedAt, sourceFreshness: observedAt, earliestAuthorizedSampleDate: nil, evidence: evidence)
  }
}

private struct ChallengeHealthAppleWorkoutScope: Equatable {
  let binding: ChallengeHealthBinding
  let queryWindow: ChallengeHealthWindow
  let purpose: ChallengeHealthReadRequest.Purpose
  init(request: ChallengeHealthReadRequest) {
    binding = request.binding
    queryWindow = request.queryWindow
    purpose = request.purpose
  }
}

/// In-memory only. A bounded snapshot is always the base; anchored changes
/// never claim visibility of a whole window by themselves.
struct ChallengeHealthAppleWorkoutLedger {
  private(set) var anchor: HKQueryAnchor?

  mutating func merge(boundedRecords: [WeeklySourceRecord], additions: [WeeklySourceRecord],
                      deletedRecordIDs: Set<UUID>, nextAnchor: HKQueryAnchor?,
                      changesWereTruncated: Bool = false) -> ChallengeHealthAppleWorkoutMergedSnapshot {
    var records = boundedRecords
    var firstRecordByID: [UUID: WeeklySourceRecord] = [:]
    for record in boundedRecords where firstRecordByID[record.id] == nil { firstRecordByID[record.id] = record }
    for addition in additions {
      if let existing = firstRecordByID[addition.id] {
        if existing != addition { records.append(addition) }
      } else {
        firstRecordByID[addition.id] = addition
        records.append(addition)
      }
    }
    if !deletedRecordIDs.isEmpty { records.removeAll { deletedRecordIDs.contains($0.id) } }
    let outgoingDeleted = deletedRecordIDs.subtracting(records.map(\.id))
    anchor = nextAnchor
    return ChallengeHealthAppleWorkoutMergedSnapshot(records: records, deletedRecordIDs: outgoingDeleted,
      evidence: outgoingDeleted.isEmpty ? .boundedSnapshot : .boundedSnapshotAfterDeletion,
      wasTruncated: changesWereTruncated)
  }
}

struct ChallengeHealthAppleWorkoutMergedSnapshot {
  let records: [WeeklySourceRecord]
  let deletedRecordIDs: Set<UUID>
  let evidence: ChallengeHealthEvidence
  let wasTruncated: Bool
}

struct ChallengeHealthAppleWorkoutBoundedRecords {
  let records: [WeeklySourceRecord]
  let wasTruncated: Bool
}

@MainActor
protocol ChallengeHealthAppleWorkoutQuerying: AnyObject {
  var isHealthDataAvailable: Bool { get }
  func boundedWorkouts(in interval: DateInterval) async throws -> ChallengeHealthAppleWorkoutBoundedRecords
  func anchoredWorkoutChanges(in interval: DateInterval, after anchor: HKQueryAnchor?) async throws
    -> ChallengeHealthAppleWorkoutAnchoredChanges
}

@MainActor
struct ChallengeHealthAppleWorkoutAnchoredChanges {
  let additions: [WeeklySourceRecord]
  let deletedRecordIDs: Set<UUID>
  let nextAnchor: HKQueryAnchor?
  let wasTruncated: Bool
}

@MainActor
private final class ChallengeHealthHealthKitWorkoutQueryCoordinator: ChallengeHealthAppleWorkoutQuerying {
  private let healthStore: HKHealthStore
  init(healthStore: HKHealthStore) { self.healthStore = healthStore }
  var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  func boundedWorkouts(in interval: DateInterval) async throws -> ChallengeHealthAppleWorkoutBoundedRecords {
    let workouts = try await workouts(predicate: Self.predicate(for: interval), limit: WeeklySourceFeasibility.maximumRecords + 1)
    return ChallengeHealthAppleWorkoutBoundedRecords(records: workouts.compactMap(Self.record),
      wasTruncated: workouts.count > WeeklySourceFeasibility.maximumRecords)
  }

  func anchoredWorkoutChanges(in interval: DateInterval, after anchor: HKQueryAnchor?) async throws
    -> ChallengeHealthAppleWorkoutAnchoredChanges {
    let continuation = ChallengeHealthWorkoutQueryContinuation<ChallengeHealthAppleWorkoutAnchoredChanges>()
    let query = HKAnchoredObjectQuery(type: HKObjectType.workoutType(), predicate: Self.predicate(for: interval),
      anchor: anchor, limit: WeeklySourceFeasibility.maximumRecords + 1) { _, added, deleted, nextAnchor, error in
        if let error { continuation.finish(.init(.failure(error))); return }
        let additions = (added ?? []).compactMap { $0 as? HKWorkout }
        let deletions = deleted ?? []
        continuation.finish(.init(.success(ChallengeHealthAppleWorkoutAnchoredChanges(
          additions: additions.compactMap(Self.record), deletedRecordIDs: Set(deletions.map(\.uuid)),
          nextAnchor: nextAnchor, wasTruncated: additions.count + deletions.count > WeeklySourceFeasibility.maximumRecords
        ))))
      }
    return try await execute(query, continuation: continuation)
  }

  private static func predicate(for interval: DateInterval) -> NSPredicate {
    HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
  }

  private func workouts(predicate: NSPredicate, limit: Int) async throws -> [HKWorkout] {
    let continuation = ChallengeHealthWorkoutQueryContinuation<[HKWorkout]>()
    let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: limit,
      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
        if let error { continuation.finish(.init(.failure(error))); return }
        continuation.finish(.init(.success((samples ?? []).compactMap { $0 as? HKWorkout })))
      }
    return try await execute(query, continuation: continuation)
  }

  private func execute<Value>(_ query: HKQuery,
                              continuation: ChallengeHealthWorkoutQueryContinuation<Value>) async throws -> Value {
    try await withTaskCancellationHandler(operation: {
      try await withCheckedThrowingContinuation { result in
        continuation.install(result)
        if Task.isCancelled { continuation.cancel() } else { healthStore.execute(query) }
      }
    }, onCancel: { [healthStore] in
      continuation.cancel()
      Task { @MainActor in healthStore.stop(query) }
    })
  }

  nonisolated private static func record(_ workout: HKWorkout) -> WeeklySourceRecord? {
    guard workout.workoutActivityType == .running, let distance = workout.totalDistance else { return nil }
    let revision = workout.sourceRevision; let os = revision.operatingSystemVersion
    return WeeklySourceRecord(id: workout.uuid, metric: .runningDistanceMillimeters,
      start: workout.startDate, end: workout.endDate,
      value: distance.doubleValue(for: .meterUnit(with: .milli)),
      sourceBundleIdentifier: revision.source.bundleIdentifier, sourceVersion: revision.version,
      sourceProductType: revision.productType,
      sourceOperatingSystemVersion: "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
      deviceManufacturer: workout.device?.manufacturer, deviceModel: workout.device?.model,
      wasUserEntered: workout.metadata?[HKMetadataKeyWasUserEntered] as? Bool,
      syncIdentifier: workout.metadata?[HKMetadataKeySyncIdentifier] as? String,
      syncVersion: workout.metadata?[HKMetadataKeySyncVersion] as? Int,
      reportedWorkoutDurationSeconds: workout.duration, workoutActivityType: "running",
      wasIndoorWorkout: workout.metadata?[HKMetadataKeyIndoorWorkout] as? Bool)
  }
}

private struct ChallengeHealthWorkoutUnsafeTransfer<Value>: @unchecked Sendable {
  let value: Value
  init(_ value: Value) { self.value = value }
}

private final class ChallengeHealthWorkoutQueryContinuation<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var result: CheckedContinuation<Value, Error>?
  private var cancelled = false
  func install(_ result: CheckedContinuation<Value, Error>) {
    lock.lock()
    if cancelled { lock.unlock(); result.resume(throwing: CancellationError()); return }
    self.result = result; lock.unlock()
  }
  func finish(_ completion: ChallengeHealthWorkoutUnsafeTransfer<Result<Value, Error>>) {
    lock.lock(); let result = self.result; self.result = nil; lock.unlock()
    result?.resume(with: completion.value)
  }
  func cancel() {
    lock.lock(); cancelled = true; let result = self.result; self.result = nil; lock.unlock()
    result?.resume(throwing: CancellationError())
  }
}
