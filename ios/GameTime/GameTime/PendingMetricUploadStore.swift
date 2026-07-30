import Foundation
import GameTimeCore

protocol PendingMetricUploadStore: AnyObject, Sendable {
  func pending(for ownerID: UUID) async throws -> [PendingMetricUpload]
  func enqueue(
    ownerID: UUID,
    contestID: UUID,
    request: EncodedMetricRequest
  ) async throws -> MetricUploadEnqueueResult
  func attachSignedMaterial(
    ownerID: UUID,
    batchID: UUID,
    keyID: String,
    assertion: Data
  ) async throws -> MetricUploadSigningResult
  func recordAttempt(ownerID: UUID, batchID: UUID) async throws
  func acknowledge(ownerID: UUID, batchID: UUID) async throws
  func abandon(ownerID: UUID, batchID: UUID) async throws
}

enum PendingMetricUploadStoreError: LocalizedError, Equatable, Sendable {
  case applicationSupportUnavailable
  case corruptData
  case unsupportedVersion(Int)
  case ownerMismatch
  case invalidQueue
  case unavailable

  var errorDescription: String? {
    switch self {
    case .applicationSupportUnavailable:
      "GameTime could not locate protected app storage."
    case .corruptData:
      "Saved activity retry data is unreadable."
    case .unsupportedVersion(let version):
      "Saved activity retry data uses unsupported version \(version)."
    case .ownerMismatch:
      "Saved activity retry data belongs to a different account."
    case .invalidQueue:
      "Saved activity retry data failed validation."
    case .unavailable:
      "Protected activity retry storage is unavailable."
    }
  }
}

private struct PendingMetricUploadEnvelope: Codable, Sendable {
  static let currentVersion = 1

  let version: Int
  let ownerID: UUID
  let uploads: [PendingMetricUpload]

  enum CodingKeys: String, CodingKey {
    case version
    case ownerID = "owner_id"
    case uploads
  }
}

actor FilePendingMetricUploadStore: PendingMetricUploadStore {
  private let directoryURL: URL
  private let capacity: Int

  init(
    directoryURL: URL,
    capacity: Int = MetricUploadQueue.defaultCapacity
  ) {
    precondition(capacity > 0)
    self.directoryURL = directoryURL
    self.capacity = capacity
  }

  static func applicationSupport() throws -> FilePendingMetricUploadStore {
    guard
      let applicationSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw PendingMetricUploadStoreError
        .applicationSupportUnavailable
    }
    return FilePendingMetricUploadStore(
      directoryURL:
        applicationSupport
        .appendingPathComponent("GameTime", isDirectory: true)
        .appendingPathComponent(
          "PendingMetricUploads",
          isDirectory: true
        )
    )
  }

  func pending(for ownerID: UUID) throws -> [PendingMetricUpload] {
    try loadQueue(for: ownerID).pending
  }

  func enqueue(
    ownerID: UUID,
    contestID: UUID,
    request: EncodedMetricRequest
  ) throws -> MetricUploadEnqueueResult {
    var queue = try loadQueue(for: ownerID)
    let result = queue.enqueue(
      contestId: contestID,
      request: request
    )
    switch result {
    case .enqueued:
      try persist(queue, for: ownerID)
    case .alreadyQueued, .conflictingPayload, .capacityReached:
      break
    }
    return result
  }

  func attachSignedMaterial(
    ownerID: UUID,
    batchID: UUID,
    keyID: String,
    assertion: Data
  ) throws -> MetricUploadSigningResult {
    var queue = try loadQueue(for: ownerID)
    let result = queue.attachSignedMaterial(
      to: batchID,
      keyID: keyID,
      assertion: assertion
    )
    switch result {
    case .attached:
      try persist(queue, for: ownerID)
    case .alreadyAttached, .conflictingMaterial, .invalidMaterial,
      .uploadNotFound:
      break
    }
    return result
  }

  func recordAttempt(ownerID: UUID, batchID: UUID) throws {
    var queue = try loadQueue(for: ownerID)
    guard
      queue.pending.contains(where: {
        $0.clientBatchId == batchID
      })
    else {
      return
    }
    queue.recordAttempt(batchID)
    try persist(queue, for: ownerID)
  }

  func acknowledge(ownerID: UUID, batchID: UUID) throws {
    var queue = try loadQueue(for: ownerID)
    guard
      queue.pending.contains(where: {
        $0.clientBatchId == batchID
      })
    else {
      return
    }
    queue.acknowledge(batchID)
    try persist(queue, for: ownerID)
  }

  func abandon(ownerID: UUID, batchID: UUID) throws {
    var queue = try loadQueue(for: ownerID)
    guard
      queue.pending.contains(where: {
        $0.clientBatchId == batchID
      })
    else {
      return
    }
    queue.abandon(batchID)
    try persist(queue, for: ownerID)
  }

  func fileURL(for ownerID: UUID) -> URL {
    directoryURL.appendingPathComponent(
      "\(ownerID.uuidString.lowercased()).json",
      isDirectory: false
    )
  }

  private func loadQueue(
    for ownerID: UUID
  ) throws -> MetricUploadQueue {
    let url = fileURL(for: ownerID)
    guard FileManager.default.fileExists(atPath: url.path) else {
      return MetricUploadQueue(capacity: capacity)
    }

    do {
      let envelope = try decoder().decode(
        PendingMetricUploadEnvelope.self,
        from: Data(contentsOf: url)
      )
      guard
        envelope.version
          == PendingMetricUploadEnvelope.currentVersion
      else {
        throw PendingMetricUploadStoreError.unsupportedVersion(
          envelope.version
        )
      }
      guard envelope.ownerID == ownerID else {
        throw PendingMetricUploadStoreError.ownerMismatch
      }
      do {
        return try MetricUploadQueue(
          capacity: capacity,
          restoring: envelope.uploads
        )
      } catch {
        throw PendingMetricUploadStoreError.invalidQueue
      }
    } catch let error as PendingMetricUploadStoreError {
      throw error
    } catch is DecodingError {
      throw PendingMetricUploadStoreError.corruptData
    } catch {
      throw PendingMetricUploadStoreError.unavailable
    }
  }

  private func persist(
    _ queue: MetricUploadQueue,
    for ownerID: UUID
  ) throws {
    let url = fileURL(for: ownerID)
    if queue.isEmpty {
      guard FileManager.default.fileExists(atPath: url.path) else {
        return
      }
      do {
        try FileManager.default.removeItem(at: url)
        return
      } catch {
        throw PendingMetricUploadStoreError.unavailable
      }
    }

    do {
      try FileManager.default.createDirectory(
        at: directoryURL,
        withIntermediateDirectories: true
      )
      try excludeFromBackup(directoryURL)
      let envelope = PendingMetricUploadEnvelope(
        version: PendingMetricUploadEnvelope.currentVersion,
        ownerID: ownerID,
        uploads: queue.pending
      )
      let data = try encoder().encode(envelope)
      try data.write(
        to: url,
        options: [.atomic, .completeFileProtection]
      )
      try excludeFromBackup(url)
    } catch let error as PendingMetricUploadStoreError {
      throw error
    } catch {
      throw PendingMetricUploadStoreError.unavailable
    }
  }

  private func excludeFromBackup(_ url: URL) throws {
    var protectedURL = url
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    do {
      try protectedURL.setResourceValues(values)
    } catch {
      throw PendingMetricUploadStoreError.unavailable
    }
  }

  private func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    return encoder
  }

  private func decoder() -> JSONDecoder {
    JSONDecoder()
  }
}
