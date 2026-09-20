import Foundation
import GameTimeCore
import HealthKit
import XCTest
@testable import GameTime

@MainActor
final class ChallengeHealthAppleWatchExerciseReaderTests: XCTestCase {
  func testInProgressWindowCapsTheReadButPreservesTheFrozenRequest() async throws {
    let now = Date()
    let fake = ExerciseQueryFake(records: [exercise(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(-30))])
    let reader = ChallengeHealthAppleWatchExerciseReader(querying: fake)
    let request = try request(actor: id(1), start: now.addingTimeInterval(-120), end: now.addingTimeInterval(120))

    let outcome = await reader.read(request)
    guard case let .snapshot(snapshot) = outcome else { return XCTFail("expected a bounded snapshot") }
    XCTAssertEqual(snapshot.request, request)
    XCTAssertLessThan(fake.intervals[0].end, request.queryWindow.interval.end)
    XCTAssertLessThanOrEqual(fake.intervals[0].end, snapshot.observedAt)
    XCTAssertEqual(snapshot.records.count, 1)
  }

  func testAnchoredDeletionAndAnOrdinaryDisappearanceRemainDistinct() {
    let record = exercise()
    var ledger = ChallengeHealthAppleWatchExerciseLedger()
    _ = ledger.merge(boundedRecords: [record], additions: [], deletedRecordIDs: [], nextAnchor: nil)

    let vanished = ledger.merge(boundedRecords: [], additions: [], deletedRecordIDs: [], nextAnchor: nil)
    XCTAssertEqual(vanished.evidence, .boundedSnapshot)
    XCTAssertTrue(vanished.deletedRecordIDs.isEmpty)

    let deleted = ledger.merge(boundedRecords: [], additions: [], deletedRecordIDs: [record.id], nextAnchor: nil)
    XCTAssertEqual(deleted.evidence, .boundedSnapshotAfterDeletion)
    XCTAssertEqual(deleted.deletedRecordIDs, [record.id])
  }

  func testRawQueryTruncationRemainsIncompleteAfterWorkoutFiltering() async throws {
    let now = Date()
    let fake = ExerciseQueryFake(records: [exercise(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(-30))])
    fake.wasTruncated = true
    let reader = ChallengeHealthAppleWatchExerciseReader(querying: fake)
    let outcome = await reader.read(try request(actor: id(1), start: now.addingTimeInterval(-120),
                                                end: now.addingTimeInterval(-1)))
    guard case let .snapshot(snapshot) = outcome else { return XCTFail("expected a snapshot") }
    XCTAssertEqual(snapshot.evidence, .truncated)
  }

  func testCancellationAndAccountScopeChangeFenceAWaitingRead() async throws {
    let now = Date()
    let fake = ExerciseQueryFake(records: [exercise(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(-30))])
    fake.suspendNextBoundedRead()
    let reader = ChallengeHealthAppleWatchExerciseReader(querying: fake)
    let firstRequest = try request(actor: id(1), start: now.addingTimeInterval(-120), end: now.addingTimeInterval(120))
    let first = Task { await reader.read(firstRequest) }
    await fake.waitForBoundedRead()
    let secondRequest = try request(actor: id(2), start: now.addingTimeInterval(-120), end: now.addingTimeInterval(120))
    guard case .snapshot = await reader.read(secondRequest) else { return XCTFail("second account should read") }
    fake.resumeFirstBoundedRead()
    let firstOutcome = await first.value
    XCTAssertEqual(firstOutcome, .unavailable(.cancelled))

    fake.suspendNextBoundedRead()
    let cancelled = Task { await reader.read(secondRequest) }
    await fake.waitForBoundedRead()
    cancelled.cancel()
    let cancelledOutcome = await cancelled.value
    XCTAssertEqual(cancelledOutcome, .unavailable(.cancelled))
  }

  private func request(actor: UUID, start: Date, end: Date) throws -> ChallengeHealthReadRequest {
    let challenge = try window(start: start, end: end)
    let binding = try ChallengeHealthBinding(actorID: actor, challengeID: id(9), agreementVersion: 1,
      termsDigest: String(repeating: "a", count: 64), metric: .exerciseSeconds, challengeWindow: challenge,
      realSourcePolicy: .appleWatchExerciseCreditV2)
    return try ChallengeHealthReadRequest(binding: binding, deviceRequestID: UUID(), queryWindow: challenge,
                                          purpose: .challengeActivity)
  }

  private func window(start: Date, end: Date) throws -> ChallengeHealthWindow {
    return try ChallengeHealthWindow(startMicroseconds: Int64((start.timeIntervalSince1970 * 1_000_000).rounded()),
      endMicroseconds: Int64((end.timeIntervalSince1970 * 1_000_000).rounded()),
      timeZoneIdentifier: "UTC", calendar: .gregorian)
  }

  private func exercise(start: Date = Date(timeIntervalSince1970: 1_800_000_000),
                   end: Date = Date(timeIntervalSince1970: 1_800_000_060)) -> WeeklySourceRecord {
    return WeeklySourceRecord(id: id(10), metric: .appleExerciseMinutes, start: start, end: end, value: 1_000,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1", wasUserEntered: false)
  }

  private func id(_ number: Int) -> UUID {
    return UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
  }
}

@MainActor
private final class ExerciseQueryFake: ChallengeHealthAppleWatchExerciseQuerying {
  let isHealthDataAvailable = true
  var records: [WeeklySourceRecord]
  var intervals: [DateInterval] = []
  var wasTruncated = false
  private var suspendNext = false
  private var waiting = false
  private var pending: CheckedContinuation<[WeeklySourceRecord], Error>?
  private var started: CheckedContinuation<Void, Never>?

  init(records: [WeeklySourceRecord]) { self.records = records }

  func boundedExercise(in interval: DateInterval) async throws -> [WeeklySourceRecord] {
    intervals.append(interval)
    started?.resume(); started = nil
    if suspendNext {
      suspendNext = false; waiting = true
      return try await withTaskCancellationHandler(operation: {
        try await withCheckedThrowingContinuation { pending = $0 }
      }, onCancel: { Task { @MainActor in self.cancelPending() } })
    }
    return wasTruncated ? Array(repeating: records[0], count: WeeklySourceFeasibility.maximumRecords + 1) : records
  }

  func anchoredExerciseChanges(in interval: DateInterval, after anchor: HKQueryAnchor?) async throws
    -> ChallengeHealthAppleWatchAnchoredExerciseChanges {
    .init(additions: [], deletedRecordIDs: [], nextAnchor: nil, wasTruncated: false)
  }

  func waitForBoundedRead() async {
    if waiting { return }
    await withCheckedContinuation { started = $0 }
  }

  func resumeFirstBoundedRead() {
    let value = records
    pending?.resume(returning: value); pending = nil
    waiting = false
  }

  func suspendNextBoundedRead() { suspendNext = true }

  private func cancelPending() {
    pending?.resume(throwing: CancellationError()); pending = nil
    waiting = false
  }
}
