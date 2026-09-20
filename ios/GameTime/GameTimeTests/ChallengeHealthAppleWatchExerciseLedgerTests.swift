import Foundation
import GameTimeCore
import XCTest

@testable import GameTime

final class ChallengeHealthAppleWatchExerciseLedgerTests: XCTestCase {
  func testExplicitAnchoredDeletionProducesOnlyADeletionSnapshot() {
    let record = exerciseRecord(1)
    var ledger = ChallengeHealthAppleWatchExerciseLedger()
    let first = ledger.merge(
      boundedRecords: [record], additions: [], deletedRecordIDs: [], nextAnchor: nil
    )
    XCTAssertEqual(first.evidence, .boundedSnapshot)
    XCTAssertEqual(first.records, [record])

    let deleted = ledger.merge(
      boundedRecords: [], additions: [], deletedRecordIDs: [record.id], nextAnchor: nil
    )
    XCTAssertEqual(deleted.evidence, .boundedSnapshotAfterDeletion)
    XCTAssertTrue(deleted.records.isEmpty)
    XCTAssertEqual(deleted.deletedRecordIDs, Set([record.id]))
  }

  func testARecordVanishingWithoutAnchoredDeletionStaysAnOrdinarySnapshot() {
    var ledger = ChallengeHealthAppleWatchExerciseLedger()
    let record = exerciseRecord(1)
    _ = ledger.merge(boundedRecords: [record], additions: [], deletedRecordIDs: [], nextAnchor: nil)
    let vanished = ledger.merge(boundedRecords: [], additions: [], deletedRecordIDs: [], nextAnchor: nil)
    XCTAssertEqual(vanished.evidence, .boundedSnapshot)
    XCTAssertTrue(vanished.deletedRecordIDs.isEmpty)
  }

  func testConflictingAnchoredIdentityIsPreservedForTheCoreAdapterToReject() {
    var ledger = ChallengeHealthAppleWatchExerciseLedger()
    let record = exerciseRecord(1, value: 10)
    let conflict = exerciseRecord(1, value: 20)
    let merged = ledger.merge(
      boundedRecords: [record], additions: [conflict], deletedRecordIDs: [], nextAnchor: nil
    )
    XCTAssertEqual(merged.records, [record, conflict])
  }

  func testAnchoredChangeTruncationIsRetainedAfterDeletesShrinkTheSnapshot() {
    var ledger = ChallengeHealthAppleWatchExerciseLedger()
    let merged = ledger.merge(
      boundedRecords: [], additions: [], deletedRecordIDs: [exerciseRecord(1).id], nextAnchor: nil,
      changesWereTruncated: true
    )
    XCTAssertTrue(merged.wasTruncated)
    XCTAssertLessThan(merged.records.count, WeeklySourceFeasibility.maximumRecords)
  }

  private func exerciseRecord(_ value: Int, value minutes: Double = 100) -> WeeklySourceRecord {
    WeeklySourceRecord(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!,
      metric: .appleExerciseMinutes,
      start: Date(timeIntervalSince1970: 1_800_000_000),
      end: Date(timeIntervalSince1970: 1_800_000_060),
      value: minutes,
      sourceBundleIdentifier: "com.apple.health",
      sourceProductType: "Watch7,1",
      wasUserEntered: false
    )
  }
}
