import Foundation
import GameTimeCore
import XCTest

@testable import GameTime

final class ChallengeHealthAppleWatchStepsLedgerTests: XCTestCase {
  func testExplicitAnchoredDeletionProducesOnlyADeletionSnapshot() {
    let record = stepRecord(1)
    var ledger = ChallengeHealthAppleWatchStepsLedger()
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
    var ledger = ChallengeHealthAppleWatchStepsLedger()
    let record = stepRecord(1)
    _ = ledger.merge(boundedRecords: [record], additions: [], deletedRecordIDs: [], nextAnchor: nil)
    let vanished = ledger.merge(boundedRecords: [], additions: [], deletedRecordIDs: [], nextAnchor: nil)
    XCTAssertEqual(vanished.evidence, .boundedSnapshot)
    XCTAssertTrue(vanished.deletedRecordIDs.isEmpty)
  }

  func testConflictingAnchoredIdentityIsPreservedForTheCoreAdapterToReject() {
    var ledger = ChallengeHealthAppleWatchStepsLedger()
    let record = stepRecord(1, value: 10)
    let conflict = stepRecord(1, value: 20)
    let merged = ledger.merge(
      boundedRecords: [record], additions: [conflict], deletedRecordIDs: [], nextAnchor: nil
    )
    XCTAssertEqual(merged.records, [record, conflict])
  }

  func testAnchoredChangeTruncationIsRetainedAfterDeletesShrinkTheSnapshot() {
    var ledger = ChallengeHealthAppleWatchStepsLedger()
    let merged = ledger.merge(
      boundedRecords: [], additions: [], deletedRecordIDs: [stepRecord(1).id], nextAnchor: nil,
      changesWereTruncated: true
    )
    XCTAssertTrue(merged.wasTruncated)
    XCTAssertLessThan(merged.records.count, WeeklySourceFeasibility.maximumRecords)
  }

  private func stepRecord(_ value: Int, value stepValue: Double = 100) -> WeeklySourceRecord {
    WeeklySourceRecord(
      id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", value))!,
      metric: .steps,
      start: Date(timeIntervalSince1970: 1_800_000_000),
      end: Date(timeIntervalSince1970: 1_800_000_060),
      value: stepValue,
      sourceBundleIdentifier: "com.apple.health",
      sourceProductType: "Watch7,1",
      wasUserEntered: false
    )
  }
}
