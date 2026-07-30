import Foundation

/// One byte-exact metric request waiting to be sent or acknowledged.
///
/// The body is the exact value produced by `EncodedMetricRequest`. App Attest
/// signs its SHA-256 digest, so neither the body nor attached assertion material
/// may be reconstructed for a retry. This value is `Codable` so an app target can
/// persist it before attempting a network request and restore it after relaunch.
public struct PendingMetricUpload: Sendable, Hashable, Identifiable, Codable {
  public var id: UUID { clientBatchId }

  public let clientBatchId: UUID
  public let contestId: UUID
  public let body: Data
  /// Apple's Base64 key identifier exactly as `generateKey()` returned it.
  public private(set) var keyID: String?
  /// The exact CBOR assertion bytes generated for `body`.
  public private(set) var assertion: Data?
  public private(set) var attempts: Int

  public init(
    clientBatchId: UUID,
    contestId: UUID,
    body: Data,
    keyID: String? = nil,
    assertion: Data? = nil,
    attempts: Int = 0
  ) {
    self.clientBatchId = clientBatchId
    self.contestId = contestId
    self.body = body
    self.keyID = keyID
    self.assertion = assertion
    self.attempts = attempts
  }

  fileprivate mutating func attach(
    keyID: String,
    assertion: Data
  ) {
    self.keyID = keyID
    self.assertion = assertion
  }

  fileprivate mutating func recordAttempt() {
    guard attempts < Int.max else { return }
    attempts += 1
  }
}

public enum MetricUploadEnqueueResult: Sendable, Hashable {
  case enqueued
  case alreadyQueued
  /// The id is already pending for a different contest or exact body.
  case conflictingPayload
  /// No existing request was evicted. The caller must retry after making room.
  case capacityReached
}

public enum MetricUploadSigningResult: Sendable, Hashable {
  case attached
  case alreadyAttached
  /// The request already carries different key or assertion bytes.
  case conflictingMaterial
  /// A key identifier and assertion must both contain bytes.
  case invalidMaterial
  case uploadNotFound
}

/// A persisted queue snapshot is rejected rather than silently repaired.
public enum MetricUploadQueueRestorationError: Error, Sendable, Hashable {
  case capacityExceeded
  case duplicateId(UUID)
  case negativeAttempts(UUID)
  case emptyBody(UUID)
  case bodyTooLarge(UUID)
  case incompleteSignedMaterial(UUID)
  case emptyKeyID(UUID)
  case emptyAssertion(UUID)
}

/// A bounded FIFO queue of byte-exact metric upload requests.
///
/// Unlike `IngestQueue`, this queue sits after metric payload encoding. It never
/// re-encodes semantic buckets and never evicts an existing request. HealthKit
/// can be queried again, but a body that may already have been committed and an
/// App Attest assertion whose counter may already have been consumed are the
/// idempotent retry record and must survive intact.
public struct MetricUploadQueue: Sendable {
  public static let defaultCapacity = 64

  public let capacity: Int
  private var uploads: [PendingMetricUpload] = []

  /// New requests refused after the queue reached its explicit bound.
  public private(set) var refusedForCapacity = 0

  public init(capacity: Int = MetricUploadQueue.defaultCapacity) {
    precondition(capacity > 0, "a queue that cannot hold anything is not a queue")
    self.capacity = capacity
  }

  /// Restores requests persisted by the app target without changing their
  /// order, bodies, signing material, or attempt counts.
  public init(
    capacity: Int = MetricUploadQueue.defaultCapacity,
    restoring persisted: [PendingMetricUpload]
  ) throws {
    precondition(capacity > 0, "a queue that cannot hold anything is not a queue")
    guard persisted.count <= capacity else {
      throw MetricUploadQueueRestorationError.capacityExceeded
    }

    var ids: Set<UUID> = []
    for upload in persisted {
      try Self.validate(upload)
      guard ids.insert(upload.clientBatchId).inserted else {
        throw MetricUploadQueueRestorationError.duplicateId(
          upload.clientBatchId
        )
      }
    }

    self.capacity = capacity
    self.uploads = persisted
  }

  public var pending: [PendingMetricUpload] { uploads }
  public var next: PendingMetricUpload? { uploads.first }
  public var count: Int { uploads.count }
  public var isEmpty: Bool { uploads.isEmpty }

  /// Queues an exact body produced by `EncodedMetricRequest`.
  ///
  /// Repeating an id is idempotent only when both its contest and bytes agree.
  /// Changed content is a conflict rather than a silent "first write wins".
  @discardableResult
  public mutating func enqueue(
    contestId: UUID,
    request: EncodedMetricRequest
  ) -> MetricUploadEnqueueResult {
    if let existing = uploads.first(where: {
      $0.clientBatchId == request.clientBatchId
    }) {
      return existing.contestId == contestId && existing.body == request.body
        ? .alreadyQueued
        : .conflictingPayload
    }

    guard uploads.count < capacity else {
      refusedForCapacity += 1
      return .capacityReached
    }

    uploads.append(
      PendingMetricUpload(
        clientBatchId: request.clientBatchId,
        contestId: contestId,
        body: request.body
      )
    )
    return .enqueued
  }

  /// Attaches App Attest material without decoding, normalizing, or regenerating
  /// it. Retrying the same attachment is a no-op; changing either value fails.
  @discardableResult
  public mutating func attachSignedMaterial(
    to clientBatchId: UUID,
    keyID: String,
    assertion: Data
  ) -> MetricUploadSigningResult {
    guard !keyID.isEmpty, !assertion.isEmpty else {
      return .invalidMaterial
    }
    guard
      let index = uploads.firstIndex(where: {
        $0.clientBatchId == clientBatchId
      })
    else {
      return .uploadNotFound
    }

    switch (uploads[index].keyID, uploads[index].assertion) {
    case (nil, nil):
      uploads[index].attach(keyID: keyID, assertion: assertion)
      return .attached
    case (.some(let existingKeyID), .some(let existingAssertion)):
      return existingKeyID == keyID && existingAssertion == assertion
        ? .alreadyAttached
        : .conflictingMaterial
    case (.some, nil), (nil, .some):
      // Construction and restoration reject this state. Keep this branch
      // defensive so a future internal mutation cannot silently repair it.
      return .conflictingMaterial
    }
  }

  public mutating func recordAttempt(_ clientBatchId: UUID) {
    guard
      let index = uploads.firstIndex(where: {
        $0.clientBatchId == clientBatchId
      })
    else {
      return
    }
    uploads[index].recordAttempt()
  }

  /// Removes a request accepted either as a first write or an idempotent replay.
  public mutating func acknowledge(_ clientBatchId: UUID) {
    uploads.removeAll { $0.clientBatchId == clientBatchId }
  }

  /// Removes a request the server will never accept.
  public mutating func abandon(_ clientBatchId: UUID) {
    uploads.removeAll { $0.clientBatchId == clientBatchId }
  }

  private static func validate(
    _ upload: PendingMetricUpload
  ) throws {
    guard upload.attempts >= 0 else {
      throw MetricUploadQueueRestorationError.negativeAttempts(
        upload.clientBatchId
      )
    }
    guard !upload.body.isEmpty else {
      throw MetricUploadQueueRestorationError.emptyBody(
        upload.clientBatchId
      )
    }
    guard upload.body.count <= EncodedMetricRequest.maximumBodyBytes else {
      throw MetricUploadQueueRestorationError.bodyTooLarge(
        upload.clientBatchId
      )
    }

    switch (upload.keyID, upload.assertion) {
    case (nil, nil):
      return
    case (.some(let keyID), .some(let assertion)):
      guard !keyID.isEmpty else {
        throw MetricUploadQueueRestorationError.emptyKeyID(
          upload.clientBatchId
        )
      }
      guard !assertion.isEmpty else {
        throw MetricUploadQueueRestorationError.emptyAssertion(
          upload.clientBatchId
        )
      }
    case (.some, nil), (nil, .some):
      throw MetricUploadQueueRestorationError.incompleteSignedMaterial(
        upload.clientBatchId
      )
    }
  }
}
