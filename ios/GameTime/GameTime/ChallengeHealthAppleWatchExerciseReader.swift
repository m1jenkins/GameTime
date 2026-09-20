import Foundation
import GameTimeCore
import HealthKit

/// iPhone-side bounded reader for versioned Apple Watch Exercise credit. The Watch contributes
/// only through Apple Health on this iPhone. No sample, source, device, route,
/// or history data leaves this reader.
@MainActor
final class ChallengeHealthAppleWatchExerciseReader: ChallengeHealthStore {
  private let querying: any ChallengeHealthAppleWatchExerciseQuerying
  private var activeScope: ChallengeHealthAppleWatchExerciseScope?
  private var ledger = ChallengeHealthAppleWatchExerciseLedger()
  private var generation: UInt64 = 0
  private var attempt: UInt64 = 0

  init(healthStore: HKHealthStore = HKHealthStore()) {
    querying = ChallengeHealthHealthKitExerciseQueryCoordinator(healthStore: healthStore)
  }

  init(querying: any ChallengeHealthAppleWatchExerciseQuerying) {
    self.querying = querying
  }

  func read(_ request: ChallengeHealthReadRequest) async -> ChallengeHealthStoreOutcome {
    guard request.binding.metric == .exerciseSeconds else { return .unavailable(.queryFailed) }
    guard querying.isHealthDataAvailable else { return .unavailable(.protectedDataUnavailable) }
    let scope = ChallengeHealthAppleWatchExerciseScope(request: request)
    guard let ticket = begin(scope) else { return .unavailable(.cancelled) }

    let observedAt = Date()
    let requested = request.queryWindow.interval
    let end = min(requested.end, observedAt)
    guard end > requested.start else {
      return .snapshot(snapshot(request: request, records: [], deletedRecordIDs: [], observedAt: observedAt, evidence: .boundedSnapshot))
    }
    let interval = DateInterval(start: requested.start, end: end)
    do {
      // A bounded query remains the snapshot base. The anchored query only
      // carries changes after it; anchors alone never claim a whole window.
      let bounded = try await querying.boundedExercise(in: interval)
      try Task.checkCancellation()
      guard isCurrent(ticket, scope: scope) else { return .unavailable(.cancelled) }
      let changes = try await querying.anchoredExerciseChanges(in: interval, after: ledger.anchor)
      try Task.checkCancellation()
      guard isCurrent(ticket, scope: scope) else { return .unavailable(.cancelled) }
      let merged = ledger.merge(boundedRecords: bounded, additions: changes.additions,
                                deletedRecordIDs: changes.deletedRecordIDs, nextAnchor: changes.nextAnchor,
                                changesWereTruncated: changes.wasTruncated)
      let truncated = merged.wasTruncated || merged.records.count > WeeklySourceFeasibility.maximumRecords
      return .snapshot(snapshot(
        request: request,
        records: Array(merged.records.prefix(WeeklySourceFeasibility.maximumRecords)),
        deletedRecordIDs: merged.deletedRecordIDs,
        observedAt: observedAt,
        evidence: truncated ? .truncated : merged.evidence
      ))
    } catch is CancellationError {
      return .unavailable(.cancelled)
    } catch {
      // Health read denial remains indistinguishable from empty data. Do not
      // expose framework errors or infer authorization/completeness.
      return .unavailable(.queryFailed)
    }
  }

  private func begin(_ scope: ChallengeHealthAppleWatchExerciseScope) -> (UInt64, UInt64)? {
    guard !Task.isCancelled else { return nil }
    // Actor, terms, policy, metric, exact window, and purpose fence raw local
    // state. Switching away and back deliberately starts a new ledger.
    if activeScope != scope {
      activeScope = scope
      ledger = ChallengeHealthAppleWatchExerciseLedger()
      guard generation < UInt64.max else { return nil }
      generation += 1
      attempt = 0
    }
    guard attempt < UInt64.max else { return nil }
    attempt += 1
    return (generation, attempt)
  }

  private func isCurrent(_ ticket: (UInt64, UInt64),
                         scope: ChallengeHealthAppleWatchExerciseScope) -> Bool {
    !Task.isCancelled && activeScope == scope && generation == ticket.0 && attempt == ticket.1
  }

  private func snapshot(request: ChallengeHealthReadRequest, records: [WeeklySourceRecord],
                        deletedRecordIDs: Set<UUID>, observedAt: Date,
                        evidence: ChallengeHealthEvidence) -> ChallengeHealthSnapshot {
    ChallengeHealthSnapshot(
      request: request, records: records, deletedRecordIDs: deletedRecordIDs,
      observedAt: observedAt, sourceFreshness: observedAt,
      earliestAuthorizedSampleDate: nil, evidence: evidence
    )
  }
}

/// Request UUID changes do not split a refresh ledger. This has no Codable
/// conformance and the reader clears it whenever the frozen identity changes.
private struct ChallengeHealthAppleWatchExerciseScope: Equatable {
  let actorID: UUID
  let challengeID: UUID
  let agreementVersion: Int
  let termsDigest: String
  let realSourcePolicy: ChallengeHealthRealSourcePolicy?
  let metric: ChallengeHealthMetric
  let queryWindow: ChallengeHealthWindow
  let purpose: ChallengeHealthReadRequest.Purpose

  init(request: ChallengeHealthReadRequest) {
    actorID = request.binding.actorID
    challengeID = request.binding.challengeID
    agreementVersion = request.binding.agreementVersion
    termsDigest = request.binding.termsDigest
    realSourcePolicy = request.binding.realSourcePolicy
    metric = request.binding.metric
    queryWindow = request.queryWindow
    purpose = request.purpose
  }
}

/// Anchors and raw known records are in-memory only. A fresh bounded read is
/// still required to build every returned snapshot.
struct ChallengeHealthAppleWatchExerciseLedger {
  private(set) var anchor: HKQueryAnchor?
  private var knownRecords: [UUID: WeeklySourceRecord] = [:]

  mutating func merge(boundedRecords: [WeeklySourceRecord], additions: [WeeklySourceRecord],
                      deletedRecordIDs: Set<UUID>, nextAnchor: HKQueryAnchor?,
                      changesWereTruncated: Bool = false)
    -> ChallengeHealthAppleWatchExerciseMergedSnapshot {
    var records = boundedRecords
    var firstRecordByID: [UUID: WeeklySourceRecord] = [:]
    for record in boundedRecords where firstRecordByID[record.id] == nil {
      firstRecordByID[record.id] = record
    }
    for addition in additions {
      if let existing = firstRecordByID[addition.id] {
        // Preserve a conflicting identity for the core adapter to reject.
        if existing != addition { records.append(addition) }
      } else {
        firstRecordByID[addition.id] = addition
        records.append(addition)
      }
    }
    // A returned deleted UUID is explicit evidence. A UUID simply absent from
    // the bounded base is left absent without a tombstone, so the core marks
    // that loss of visibility unresolved against its previous snapshot.
    if !deletedRecordIDs.isEmpty {
      records.removeAll { deletedRecordIDs.contains($0.id) }
    }
    let outgoingDeleted = deletedRecordIDs.subtracting(records.map(\.id))
    knownRecords.removeAll(keepingCapacity: true)
    for record in records.prefix(WeeklySourceFeasibility.maximumRecords)
      where knownRecords[record.id] == nil {
      knownRecords[record.id] = record
    }
    anchor = nextAnchor
    return ChallengeHealthAppleWatchExerciseMergedSnapshot(
      records: records,
      deletedRecordIDs: outgoingDeleted,
      evidence: outgoingDeleted.isEmpty ? .boundedSnapshot : .boundedSnapshotAfterDeletion,
      wasTruncated: changesWereTruncated
    )
  }
}

struct ChallengeHealthAppleWatchExerciseMergedSnapshot {
  let records: [WeeklySourceRecord]
  let deletedRecordIDs: Set<UUID>
  let evidence: ChallengeHealthEvidence
  let wasTruncated: Bool
}

@MainActor
protocol ChallengeHealthAppleWatchExerciseQuerying: AnyObject {
  var isHealthDataAvailable: Bool { get }
  func boundedExercise(in interval: DateInterval) async throws -> [WeeklySourceRecord]
  func anchoredExerciseChanges(in interval: DateInterval, after anchor: HKQueryAnchor?) async throws
    -> ChallengeHealthAppleWatchAnchoredExerciseChanges
}

@MainActor
struct ChallengeHealthAppleWatchAnchoredExerciseChanges {
  let additions: [WeeklySourceRecord]
  let deletedRecordIDs: Set<UUID>
  let nextAnchor: HKQueryAnchor?
  let wasTruncated: Bool
}

@MainActor
private final class ChallengeHealthHealthKitExerciseQueryCoordinator: ChallengeHealthAppleWatchExerciseQuerying {
  private let healthStore: HKHealthStore
  init(healthStore: HKHealthStore) { self.healthStore = healthStore }
  var isHealthDataAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

  func boundedExercise(in interval: DateInterval) async throws -> [WeeklySourceRecord] {
    let samples = try await samples(predicate: Self.predicate(for: interval), limit: WeeklySourceFeasibility.maximumRecords + 1)
    return samples.compactMap(Self.record(from:))
  }

  func anchoredExerciseChanges(in interval: DateInterval, after anchor: HKQueryAnchor?) async throws
    -> ChallengeHealthAppleWatchAnchoredExerciseChanges {
    let continuation = ChallengeHealthQueryContinuation<ChallengeHealthAppleWatchAnchoredExerciseChanges>()
    let query = HKAnchoredObjectQuery(
      type: HKQuantityType(.appleExerciseTime), predicate: Self.predicate(for: interval),
      anchor: anchor, limit: WeeklySourceFeasibility.maximumRecords + 1
    ) { _, added, deleted, nextAnchor, error in
      if let error { continuation.finish(.init(.failure(error))); return }
      let additions = added ?? []
      let deleted = deleted ?? []
      continuation.finish(.init(.success(ChallengeHealthAppleWatchAnchoredExerciseChanges(
        additions: additions.compactMap(Self.record(from:)),
        deletedRecordIDs: Set(deleted.map(\.uuid)), nextAnchor: nextAnchor,
        wasTruncated: additions.count + deleted.count > WeeklySourceFeasibility.maximumRecords
      ))))
    }
    return try await execute(query, continuation: continuation)
  }

  private static func predicate(for interval: DateInterval) -> NSPredicate {
    // Include samples that overlap the bounded interval. The core adapter
    // rejects a crossing record; excluding it here would silently treat an
    // ambiguous contribution as absent.
    HKQuery.predicateForSamples(withStart: interval.start, end: interval.end, options: [])
  }

  private func samples(predicate: NSPredicate, limit: Int) async throws -> [HKSample] {
    let continuation = ChallengeHealthQueryContinuation<[HKSample]>()
    let query = HKSampleQuery(
      sampleType: HKQuantityType(.appleExerciseTime), predicate: predicate, limit: limit,
      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
    ) { _, samples, error in
      continuation.finish(.init(error.map(Result.failure) ?? .success(samples ?? [])))
    }
    return try await execute(query, continuation: continuation)
  }

  private func execute<Value>(_ query: HKQuery,
                              continuation: ChallengeHealthQueryContinuation<Value>) async throws -> Value {
    try await withTaskCancellationHandler(
      operation: {
        try await withCheckedThrowingContinuation { result in
          continuation.install(result)
          if Task.isCancelled { continuation.cancel() } else { healthStore.execute(query) }
        }
      },
      onCancel: { [healthStore] in
        continuation.cancel()
        Task { @MainActor in healthStore.stop(query) }
      }
    )
  }

  nonisolated private static func record(from sample: HKSample) -> WeeklySourceRecord? {
    guard let quantity = sample as? HKQuantitySample else { return nil }
    let revision = sample.sourceRevision
    let version = revision.operatingSystemVersion
    return WeeklySourceRecord(
      id: sample.uuid, metric: .appleExerciseMinutes, start: sample.startDate, end: sample.endDate,
      value: quantity.quantity.doubleValue(for: .minute()),
      sourceBundleIdentifier: revision.source.bundleIdentifier, sourceVersion: revision.version,
      sourceProductType: revision.productType,
      sourceOperatingSystemVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
      deviceManufacturer: sample.device?.manufacturer, deviceModel: sample.device?.model,
      wasUserEntered: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool,
      syncIdentifier: sample.metadata?[HKMetadataKeySyncIdentifier] as? String,
      syncVersion: sample.metadata?[HKMetadataKeySyncVersion] as? Int
    )
  }
}

private struct ChallengeHealthUnsafeTransfer<Value>: @unchecked Sendable {
  let value: Value
  init(_ value: Value) { self.value = value }
}

private final class ChallengeHealthQueryContinuation<Value>: @unchecked Sendable {
  private let lock = NSLock()
  private var result: CheckedContinuation<Value, Error>?
  private var cancelled = false
  func install(_ result: CheckedContinuation<Value, Error>) {
    lock.lock()
    if cancelled { lock.unlock(); result.resume(throwing: CancellationError()); return }
    self.result = result; lock.unlock()
  }
  func finish(_ completion: ChallengeHealthUnsafeTransfer<Result<Value, Error>>) {
    lock.lock(); let result = self.result; self.result = nil; lock.unlock()
    result?.resume(with: completion.value)
  }
  func cancel() {
    lock.lock(); cancelled = true; let result = self.result; self.result = nil; lock.unlock()
    result?.resume(throwing: CancellationError())
  }
}
