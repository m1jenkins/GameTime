import GameTimeCore
import XCTest

@testable import GameTime

final class PendingMetricUploadStoreTests: XCTestCase {
  private let ownerID = UUID(
    uuidString: "10000000-0000-0000-0000-000000000001"
  )!
  private let otherOwnerID = UUID(
    uuidString: "20000000-0000-0000-0000-000000000002"
  )!
  private let contestID = UUID(
    uuidString: "30000000-0000-0000-0000-000000000003"
  )!
  private let batchID = UUID(
    uuidString: "40000000-0000-0000-0000-000000000004"
  )!

  func testOfflineQueueRestoresExactBytesSigningMaterialAndAttempts()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let firstStore = FilePendingMetricUploadStore(
      directoryURL: directory
    )
    let request = try makeRequest()
    let assertion = Data([0xde, 0xad, 0xbe, 0xef])

    let enqueueResult = try await firstStore.enqueue(
      ownerID: ownerID,
      contestID: contestID,
      request: request
    )
    XCTAssertEqual(enqueueResult, .enqueued)
    let signingResult = try await firstStore.attachSignedMaterial(
      ownerID: ownerID,
      batchID: batchID,
      keyID: "verbatim/key+id==",
      assertion: assertion
    )
    XCTAssertEqual(signingResult, .attached)
    try await firstStore.recordAttempt(
      ownerID: ownerID,
      batchID: batchID
    )

    let relaunchedStore = FilePendingMetricUploadStore(
      directoryURL: directory
    )
    let relaunchedUploads = try await relaunchedStore.pending(
      for: ownerID
    )
    let restored = try XCTUnwrap(relaunchedUploads.first)
    XCTAssertEqual(restored.clientBatchId, batchID)
    XCTAssertEqual(restored.contestId, contestID)
    XCTAssertEqual(restored.body, request.body)
    XCTAssertEqual(restored.keyID, "verbatim/key+id==")
    XCTAssertEqual(restored.assertion, assertion)
    XCTAssertEqual(restored.attempts, 1)

    let fileURL = await relaunchedStore.fileURL(for: ownerID)
    XCTAssertEqual(
      try fileURL.resourceValues(
        forKeys: [.isExcludedFromBackupKey]
      ).isExcludedFromBackup,
      true
    )
  }

  func testQueueIsAccountIsolatedAndCrossAccountAcknowledgeIsNoOp()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let store = FilePendingMetricUploadStore(directoryURL: directory)
    let request = try makeRequest()
    _ = try await store.enqueue(
      ownerID: ownerID,
      contestID: contestID,
      request: request
    )

    let otherUploads = try await store.pending(for: otherOwnerID)
    XCTAssertTrue(otherUploads.isEmpty)
    try await store.acknowledge(
      ownerID: otherOwnerID,
      batchID: batchID
    )
    let ownerUploads = try await store.pending(for: ownerID)
    XCTAssertEqual(ownerUploads.map(\.clientBatchId), [batchID])

    let ownerURL = await store.fileURL(for: ownerID)
    let otherURL = await store.fileURL(for: otherOwnerID)
    try FileManager.default.copyItem(at: ownerURL, to: otherURL)
    do {
      _ = try await store.pending(for: otherOwnerID)
      XCTFail("Expected copied cross-account data to fail closed")
    } catch {
      XCTAssertEqual(
        error as? PendingMetricUploadStoreError,
        .ownerMismatch
      )
    }
  }

  func testDuplicateBodyIsIdempotentAndChangedBodyConflicts()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let store = FilePendingMetricUploadStore(directoryURL: directory)
    let request = try makeRequest()
    let changedRequest = try makeRequest(value: 999)

    let firstResult = try await store.enqueue(
      ownerID: ownerID,
      contestID: contestID,
      request: request
    )
    XCTAssertEqual(firstResult, .enqueued)
    let duplicateResult = try await store.enqueue(
      ownerID: ownerID,
      contestID: contestID,
      request: request
    )
    XCTAssertEqual(duplicateResult, .alreadyQueued)
    let conflictResult = try await store.enqueue(
      ownerID: ownerID,
      contestID: contestID,
      request: changedRequest
    )
    XCTAssertEqual(conflictResult, .conflictingPayload)
    let pendingBeforeAck = try await store.pending(for: ownerID)
    XCTAssertEqual(pendingBeforeAck.count, 1)

    try await store.acknowledge(
      ownerID: ownerID,
      batchID: batchID
    )
    let pendingAfterAck = try await store.pending(for: ownerID)
    XCTAssertTrue(pendingAfterAck.isEmpty)
  }

  private func makeRequest(
    value: Double = 500
  ) throws -> EncodedMetricRequest {
    try EncodedMetricRequest(
      payload: AttestedMetricPayload(
        contestId: contestID,
        clientBatchId: batchID,
        observedAt: Date(
          timeIntervalSince1970: 1_785_891_723.123
        ),
        observations: [
          HourlyBucket(
            metric: .steps,
            bucketStart: Date(
              timeIntervalSince1970: 1_785_888_000
            ),
            provenance: .device,
            value: value,
            sampleCount: 4,
            sourceBundleIdentifier: "com.apple.health",
            deviceModel: "Watch"
          )
        ]
      )
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "GameTimeMetricStoreTests-\(UUID().uuidString)",
        isDirectory: true
      )
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    addTeardownBlock {
      try? FileManager.default.removeItem(at: directory)
    }
    return directory
  }
}
