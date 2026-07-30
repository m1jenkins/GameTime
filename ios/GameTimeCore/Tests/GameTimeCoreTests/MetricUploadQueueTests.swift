import Foundation
import Testing

@testable import GameTimeCore

@Suite("Metric upload queue")
struct MetricUploadQueueTests {
  static let contest = UUID(
    uuidString: "a0000001-0000-0000-0000-000000000001"
  )!
  static let otherContest = UUID(
    uuidString: "a0000002-0000-0000-0000-000000000002"
  )!
  static let epoch = Date(timeIntervalSince1970: 1_785_888_000)

  static func batchId(_ n: Int) -> UUID {
    UUID(
      uuidString: String(
        format: "b%07d-0000-0000-0000-000000000000",
        n
      )
    )!
  }

  static func request(
    id: UUID,
    value: Double = 500
  ) throws -> EncodedMetricRequest {
    try EncodedMetricRequest(
      payload: AttestedMetricPayload(
        contestId: contest,
        clientBatchId: id,
        observedAt: epoch.addingTimeInterval(7_323.123),
        observations: [
          HourlyBucket(
            metric: .steps,
            bucketStart: epoch,
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

  @Test("a retry retains exact body and signing bytes")
  func retryByteIdentity() throws {
    let request = try Self.request(id: Self.batchId(1))
    let assertion = Data([0xa3, 0x01, 0x02, 0x03])
    var queue = MetricUploadQueue()

    #expect(queue.enqueue(contestId: Self.contest, request: request) == .enqueued)
    #expect(
      queue.attachSignedMaterial(
        to: request.clientBatchId,
        keyID: "AbC+/==",
        assertion: assertion
      ) == .attached
    )
    queue.recordAttempt(request.clientBatchId)
    queue.recordAttempt(request.clientBatchId)

    #expect(queue.next?.body == request.body)
    #expect(queue.next?.keyID == "AbC+/==")
    #expect(queue.next?.assertion == assertion)
    #expect(queue.next?.attempts == 2)
  }

  @Test("same id and payload are idempotent")
  func identicalEnqueueIsSafe() throws {
    let request = try Self.request(id: Self.batchId(1))
    var queue = MetricUploadQueue()

    #expect(queue.enqueue(contestId: Self.contest, request: request) == .enqueued)
    #expect(
      queue.enqueue(contestId: Self.contest, request: request)
        == .alreadyQueued
    )
    #expect(queue.count == 1)
    #expect(queue.next?.body == request.body)
  }

  @Test("same id with changed contest or body conflicts")
  func changedPayloadConflicts() throws {
    let id = Self.batchId(1)
    let original = try Self.request(id: id)
    let changed = try Self.request(id: id, value: 999)
    var queue = MetricUploadQueue()

    #expect(queue.enqueue(contestId: Self.contest, request: original) == .enqueued)
    #expect(
      queue.enqueue(contestId: Self.otherContest, request: original)
        == .conflictingPayload
    )
    #expect(
      queue.enqueue(contestId: Self.contest, request: changed)
        == .conflictingPayload
    )
    #expect(queue.count == 1)
    #expect(queue.next?.contestId == Self.contest)
    #expect(queue.next?.body == original.body)
  }

  @Test("signed material attaches idempotently and conflicts loudly")
  func signedMaterialConflictRules() throws {
    let request = try Self.request(id: Self.batchId(1))
    let firstAssertion = Data([0x01, 0x02])
    var queue = MetricUploadQueue()
    queue.enqueue(contestId: Self.contest, request: request)

    #expect(
      queue.attachSignedMaterial(
        to: request.clientBatchId,
        keyID: "verbatim/key+id==",
        assertion: firstAssertion
      ) == .attached
    )
    #expect(
      queue.attachSignedMaterial(
        to: request.clientBatchId,
        keyID: "verbatim/key+id==",
        assertion: firstAssertion
      ) == .alreadyAttached
    )
    #expect(
      queue.attachSignedMaterial(
        to: request.clientBatchId,
        keyID: "different",
        assertion: firstAssertion
      ) == .conflictingMaterial
    )
    #expect(
      queue.attachSignedMaterial(
        to: request.clientBatchId,
        keyID: "verbatim/key+id==",
        assertion: Data([0xff])
      ) == .conflictingMaterial
    )

    #expect(queue.next?.keyID == "verbatim/key+id==")
    #expect(queue.next?.assertion == firstAssertion)
  }

  @Test("invalid signing input and unknown ids do not mutate the queue")
  func invalidSigningMaterialIsRefused() throws {
    let request = try Self.request(id: Self.batchId(1))
    var queue = MetricUploadQueue()
    queue.enqueue(contestId: Self.contest, request: request)

    #expect(
      queue.attachSignedMaterial(
        to: request.clientBatchId,
        keyID: "",
        assertion: Data([0x01])
      ) == .invalidMaterial
    )
    #expect(
      queue.attachSignedMaterial(
        to: request.clientBatchId,
        keyID: "key",
        assertion: Data()
      ) == .invalidMaterial
    )
    #expect(
      queue.attachSignedMaterial(
        to: Self.batchId(99),
        keyID: "key",
        assertion: Data([0x01])
      ) == .uploadNotFound
    )
    #expect(queue.next?.keyID == nil)
    #expect(queue.next?.assertion == nil)
  }

  @Test("sending is FIFO and acknowledgements remove only their id")
  func fifoAndAcknowledgement() throws {
    var queue = MetricUploadQueue()
    for n in 1...3 {
      queue.enqueue(
        contestId: Self.contest,
        request: try Self.request(id: Self.batchId(n))
      )
    }

    #expect(queue.pending.map(\.clientBatchId) == (1...3).map(Self.batchId))
    #expect(queue.next?.clientBatchId == Self.batchId(1))

    queue.acknowledge(Self.batchId(2))
    #expect(
      queue.pending.map(\.clientBatchId) == [
        Self.batchId(1), Self.batchId(3),
      ])
    queue.acknowledge(Self.batchId(99))
    #expect(queue.count == 2)
  }

  @Test("abandon removes only a permanently refused request")
  func abandonRemovesRequest() throws {
    var queue = MetricUploadQueue()
    queue.enqueue(
      contestId: Self.contest,
      request: try Self.request(id: Self.batchId(1))
    )

    queue.abandon(Self.batchId(1))
    #expect(queue.isEmpty)
  }

  @Test("capacity refuses new uploads without evicting old ones")
  func capacityDoesNotEvict() throws {
    var queue = MetricUploadQueue(capacity: 2)
    for n in 1...3 {
      queue.enqueue(
        contestId: Self.contest,
        request: try Self.request(id: Self.batchId(n))
      )
    }

    #expect(queue.count == 2)
    #expect(
      queue.pending.map(\.clientBatchId) == [
        Self.batchId(1), Self.batchId(2),
      ])
    #expect(queue.refusedForCapacity == 1)
  }

  @Test("exact bytes order signing material and attempts survive persistence")
  func persistenceRoundTripIsExact() throws {
    var original = MetricUploadQueue()
    let first = try Self.request(id: Self.batchId(1))
    let second = try Self.request(id: Self.batchId(2))
    original.enqueue(contestId: Self.contest, request: first)
    original.enqueue(contestId: Self.otherContest, request: second)
    original.attachSignedMaterial(
      to: first.clientBatchId,
      keyID: "AbC+/==",
      assertion: Data([0xde, 0xad, 0xbe, 0xef])
    )
    original.recordAttempt(first.clientBatchId)

    let persisted = try JSONEncoder().encode(original.pending)
    let decoded = try JSONDecoder().decode(
      [PendingMetricUpload].self,
      from: persisted
    )
    let restored = try MetricUploadQueue(restoring: decoded)

    #expect(restored.pending == original.pending)
    #expect(restored.pending.map(\.body) == [first.body, second.body])
    #expect(restored.next?.keyID == "AbC+/==")
    #expect(restored.next?.assertion == Data([0xde, 0xad, 0xbe, 0xef]))
    #expect(restored.next?.attempts == 1)
  }

  @Test("restoration rejects capacity overflow and duplicate ids")
  func invalidRestorationShapeFails() throws {
    let request = try Self.request(id: Self.batchId(1))
    let pending = PendingMetricUpload(
      clientBatchId: request.clientBatchId,
      contestId: Self.contest,
      body: request.body
    )

    #expect(throws: MetricUploadQueueRestorationError.capacityExceeded) {
      _ = try MetricUploadQueue(
        capacity: 1,
        restoring: [pending, pending]
      )
    }
    #expect(
      throws: MetricUploadQueueRestorationError.duplicateId(
        request.clientBatchId
      )
    ) {
      _ = try MetricUploadQueue(
        capacity: 2,
        restoring: [pending, pending]
      )
    }
  }

  @Test("restoration rejects invalid attempts and body bounds")
  func invalidRestoredBodyFails() {
    let id = Self.batchId(1)

    #expect(
      throws: MetricUploadQueueRestorationError.negativeAttempts(id)
    ) {
      _ = try MetricUploadQueue(restoring: [
        PendingMetricUpload(
          clientBatchId: id,
          contestId: Self.contest,
          body: Data([0x01]),
          attempts: -1
        )
      ])
    }
    #expect(throws: MetricUploadQueueRestorationError.emptyBody(id)) {
      _ = try MetricUploadQueue(restoring: [
        PendingMetricUpload(
          clientBatchId: id,
          contestId: Self.contest,
          body: Data()
        )
      ])
    }
    #expect(throws: MetricUploadQueueRestorationError.bodyTooLarge(id)) {
      _ = try MetricUploadQueue(restoring: [
        PendingMetricUpload(
          clientBatchId: id,
          contestId: Self.contest,
          body: Data(
            repeating: 0,
            count: EncodedMetricRequest.maximumBodyBytes + 1
          )
        )
      ])
    }
  }

  @Test("restoration rejects incomplete or empty signed material")
  func invalidRestoredSignedMaterialFails() {
    let id = Self.batchId(1)

    #expect(
      throws:
        MetricUploadQueueRestorationError
        .incompleteSignedMaterial(id)
    ) {
      _ = try MetricUploadQueue(restoring: [
        PendingMetricUpload(
          clientBatchId: id,
          contestId: Self.contest,
          body: Data([0x01]),
          keyID: "key"
        )
      ])
    }
    #expect(throws: MetricUploadQueueRestorationError.emptyKeyID(id)) {
      _ = try MetricUploadQueue(restoring: [
        PendingMetricUpload(
          clientBatchId: id,
          contestId: Self.contest,
          body: Data([0x01]),
          keyID: "",
          assertion: Data([0x01])
        )
      ])
    }
    #expect(throws: MetricUploadQueueRestorationError.emptyAssertion(id)) {
      _ = try MetricUploadQueue(restoring: [
        PendingMetricUpload(
          clientBatchId: id,
          contestId: Self.contest,
          body: Data([0x01]),
          keyID: "key",
          assertion: Data()
        )
      ])
    }
  }

  @Test("the queue is a Sendable value type")
  func queueCrossesIsolationAndCopiesIndependently() async throws {
    var queue = MetricUploadQueue()
    queue.enqueue(
      contestId: Self.contest,
      request: try Self.request(id: Self.batchId(1))
    )

    var copy = queue
    copy.acknowledge(Self.batchId(1))
    let count = await Task.detached { [queue] in queue.count }.value

    #expect(count == 1)
    #expect(queue.count == 1)
    #expect(copy.isEmpty)
  }
}
