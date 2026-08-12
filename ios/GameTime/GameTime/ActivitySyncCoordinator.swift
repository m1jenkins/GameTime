import Foundation
import GameTimeCore

enum ActivitySyncOutcome: Equatable, Sendable {
  /// `stepTotal` is the exact value confirmed during this explicit sync.
  case synced(replayed: Bool, stepTotal: Double)
  /// A previously signed request without a new step total was accepted.
  case savedRequestAccepted
  /// Saved evidence came from an App Attest environment this build cannot
  /// trust. It was removed and must be read again while the window is open.
  case savedRequestUnavailable
  /// `stepTotal` is the exact value still retained in durable request bodies.
  case queuedForRetry(stepTotal: Double)
  /// An empty read does not prove denial. It can also mean no samples exist.
  case noReadableData
}

enum ActivitySyncDiagnosticEvent: String, Equatable, Sendable {
  case authorizationRequestCompleted
  case authorizationUnavailable
  case sampleQueryCompleted
  case noReadableBuckets
  case exactRequestQueued
  case signedMaterialSaved
  case foreignEnvironmentRequestDiscarded
  case rejectedSavedRequestDiscarded
  case rejectedCurrentRequestDiscarded
  case uploadAttemptStarted
  case retryRetained
  case permanentRequestDiscarded
  case uploadAccepted
  case replayAccepted
}

@MainActor
protocol ActivitySyncDiagnostics: AnyObject {
  func record(_ event: ActivitySyncDiagnosticEvent)
}

@MainActor
final class NoOpActivitySyncDiagnostics: ActivitySyncDiagnostics {
  func record(_ event: ActivitySyncDiagnosticEvent) {
    _ = event
  }
}

@MainActor
protocol ActivitySyncing: AnyObject {
  func requestAuthorization() async throws
    -> ActivityAuthorizationOutcome
  func pendingUploadCount(for ownerID: UUID) async throws -> Int
  func pendingContestID(for ownerID: UUID) async throws -> UUID?
  func retirePendingUploads(
    for ownerID: UUID,
    contestID: UUID
  ) async throws
  func sync(
    ownerID: UUID,
    contest: ContestCard,
    asOf: Date
  ) async throws -> ActivitySyncOutcome
}

extension ActivitySyncing {
  func pendingContestID(for ownerID: UUID) async throws -> UUID? {
    _ = ownerID
    return nil
  }

  func retirePendingUploads(
    for ownerID: UUID,
    contestID: UUID
  ) async throws {
    _ = (ownerID, contestID)
  }
}

enum ActivitySyncError: LocalizedError, Equatable, Sendable {
  case stagingOnly
  case challengeNotEligible
  case invalidChallengeWindow
  case missingParticipantTimeZone
  case invalidTimeZoneSchedule
  case queueAtCapacity
  case conflictingQueuedRequest
  case conflictingSignedMaterial
  case queuedRequestUnavailable
  case pendingUploadForDifferentChallenge

  var errorDescription: String? {
    switch self {
    case .stagingOnly:
      "Activity updates aren’t available yet."
    case .challengeNotEligible:
      "Only an active steps challenge can sync."
    case .invalidChallengeWindow:
      "Something is wrong with this challenge’s dates."
    case .missingParticipantTimeZone:
      "We couldn’t work out your challenge’s time zone."
    case .invalidTimeZoneSchedule:
      "We couldn’t confirm your challenge’s time zone."
    case .queueAtCapacity:
      "There are saved steps still waiting to send. Sort those out first."
    case .conflictingQueuedRequest:
      "This doesn’t match the steps already waiting to send."
    case .conflictingSignedMaterial:
      "This doesn’t match what your phone saved earlier."
    case .queuedRequestUnavailable:
      "We couldn’t restore the steps saved on your phone."
    case .pendingUploadForDifferentChallenge:
      "Sync the other challenge first — it has steps still waiting."
    }
  }
}

@MainActor
final class ActivitySyncCoordinator: ActivitySyncing {
  private let activity: any ActivityClient
  private let uploads: any MetricUploadClient
  private let pendingUploads: any PendingMetricUploadStore
  private let diagnostics: any ActivitySyncDiagnostics

  init(
    activity: any ActivityClient,
    uploads: any MetricUploadClient,
    pendingUploads: any PendingMetricUploadStore,
    diagnostics: any ActivitySyncDiagnostics = NoOpActivitySyncDiagnostics()
  ) {
    self.activity = activity
    self.uploads = uploads
    self.pendingUploads = pendingUploads
    self.diagnostics = diagnostics
  }

  func requestAuthorization() async throws
    -> ActivityAuthorizationOutcome
  {
    let outcome = try await activity.requestStepReadAuthorization()
    switch outcome {
    case .requestCompleted:
      diagnostics.record(.authorizationRequestCompleted)
    case .healthDataUnavailable:
      diagnostics.record(.authorizationUnavailable)
    }
    return outcome
  }

  func pendingUploadCount(for ownerID: UUID) async throws -> Int {
    try await pendingUploads.pending(for: ownerID).count
  }

  func pendingContestID(for ownerID: UUID) async throws -> UUID? {
    let ids = Set(
      try await pendingUploads.pending(for: ownerID).map(\.contestId)
    )
    guard ids.count <= 1 else {
      throw ActivitySyncError.pendingUploadForDifferentChallenge
    }
    return ids.first
  }

  func retirePendingUploads(
    for ownerID: UUID,
    contestID: UUID
  ) async throws {
    let uploads = try await pendingUploads.pending(for: ownerID)
    for upload in uploads where upload.contestId == contestID {
      try await pendingUploads.abandon(
        ownerID: ownerID,
        batchID: upload.clientBatchId
      )
    }
  }

  func sync(
    ownerID: UUID,
    contest: ContestCard,
    asOf: Date
  ) async throws -> ActivitySyncOutcome {
    guard
      contest.metric == .steps,
      contest.myStatus == .accepted,
      contest.status == .active
    else {
      throw ActivitySyncError.challengeNotEligible
    }

    let existingUploads = try await pendingUploads.pending(
      for: ownerID
    )
    if !existingUploads.isEmpty {
      guard
        existingUploads.allSatisfy({
          $0.contestId == contest.id
        })
      else {
        throw ActivitySyncError.pendingUploadForDifferentChallenge
      }
      guard let expectedEnvironment =
        uploads.expectedAttestationEnvironment
      else {
        throw ActivitySyncError.stagingOnly
      }
      let foreignUploads = existingUploads.filter {
        !Self.savedUpload(
          $0,
          isTrustedBy: expectedEnvironment
        )
      }
      if !foreignUploads.isEmpty {
        for upload in foreignUploads {
          try await pendingUploads.abandon(
            ownerID: ownerID,
            batchID: upload.clientBatchId
          )
          diagnostics.record(.foreignEnvironmentRequestDiscarded)
        }
        return .savedRequestUnavailable
      }
      return try await deliverPendingUploads(
        ownerID: ownerID,
        contestID: contest.id
      )
    }

    return try await syncFresh(
      ownerID: ownerID,
      contest: contest,
      asOf: asOf,
      retryRejectedCurrentKey: true
    )
  }

  private func syncFresh(
    ownerID: UUID,
    contest: ContestCard,
    asOf: Date,
    retryRejectedCurrentKey: Bool
  ) async throws -> ActivitySyncOutcome {
    guard contest.endsAt > contest.startsAt else {
      throw ActivitySyncError.invalidChallengeWindow
    }
    guard let timeZone = contest.participantTimeZone else {
      throw ActivitySyncError.missingParticipantTimeZone
    }

    let schedule: ContestTimeZoneSchedule
    do {
      schedule = try ContestTimeZoneSchedule(
        initialTimeZoneIdentifier: timeZone,
        changes: contest.resolvedTimeZoneChanges.map {
          ContestTimeZoneChange(
            fromTimeZoneIdentifier: $0.fromTimeZone,
            toTimeZoneIdentifier: $0.toTimeZone,
            effectiveAt: $0.effectiveAt
          )
        }
      )
    } catch {
      throw ActivitySyncError.invalidTimeZoneSchedule
    }

    let window = DateInterval(
      start: contest.startsAt,
      end: contest.endsAt
    )
    let buckets = try await activity.stepBuckets(
      overlapping: window,
      timeZoneSchedule: schedule,
      asOf: asOf
    )
    diagnostics.record(.sampleQueryCompleted)

    guard !buckets.isEmpty else {
      diagnostics.record(.noReadableBuckets)
      return .noReadableData
    }

    guard let expectedEnvironment =
      uploads.expectedAttestationEnvironment
    else {
      throw ActivitySyncError.stagingOnly
    }
    let requests = try encodedRequests(
      contestID: contest.id,
      buckets: buckets,
      observedAt: asOf
    )
    for request in requests {
      let enqueueResult = try await pendingUploads.enqueue(
        ownerID: ownerID,
        contestID: contest.id,
        request: request,
        environment: expectedEnvironment
      )
      switch enqueueResult {
      case .enqueued, .alreadyQueued:
        diagnostics.record(.exactRequestQueued)
      case .conflictingPayload:
        throw ActivitySyncError.conflictingQueuedRequest
      case .capacityReached:
        throw ActivitySyncError.queueAtCapacity
      }
    }

    do {
      return try await deliverPendingUploads(
        ownerID: ownerID,
        contestID: contest.id
      )
    } catch let error as MetricUploadClientError
      where error == .attestationRejected
    {
      // The client has invalidated the key that signed this just-created
      // request. Remove every body from this read and perform one bounded new
      // Health read; old bytes are never signed under the replacement key.
      for request in requests {
        try await pendingUploads.abandon(
          ownerID: ownerID,
          batchID: request.clientBatchId
        )
      }
      guard retryRejectedCurrentKey else { throw error }
      return try await syncFresh(
        ownerID: ownerID,
        contest: contest,
        asOf: asOf,
        retryRejectedCurrentKey: false
      )
    }
  }

  private func encodedRequests(
    contestID: UUID,
    buckets: [HourlyBucket],
    observedAt: Date
  ) throws -> [EncodedMetricRequest] {
    var requests: [EncodedMetricRequest] = []
    var startIndex = buckets.startIndex

    while startIndex < buckets.endIndex {
      var count = min(
        EncodedMetricRequest.maximumObservationCount,
        buckets.distance(
          from: startIndex,
          to: buckets.endIndex
        )
      )

      while count > 0 {
        let endIndex = buckets.index(
          startIndex,
          offsetBy: count
        )
        var semanticQueue = IngestQueue(capacity: 1)
        guard
          let batch = semanticQueue.enqueue(
            contestId: contestID,
            buckets: Array(buckets[startIndex..<endIndex]),
            observedAt: observedAt,
            clientBatchId: UUID()
          )
        else {
          throw ActivitySyncError.queuedRequestUnavailable
        }

        do {
          requests.append(
            try EncodedMetricRequest(
              payload: AttestedMetricPayload(batch: batch)
            )
          )
          startIndex = endIndex
          break
        } catch MetricPayloadEncodingError.bodyTooLarge {
          guard count > 1 else {
            throw MetricPayloadEncodingError.bodyTooLarge
          }
          count = max(1, count / 2)
        }
      }
    }

    return requests
  }

  private func deliverPendingUploads(
    ownerID: UUID,
    contestID: UUID
  ) async throws -> ActivitySyncOutcome {
    var acceptedReplay = false
    var confirmedStepTotal = 0.0

    while let queued = try await pendingUploads.pending(
      for: ownerID
    ).first {
      guard queued.contestId == contestID else {
        throw ActivitySyncError.pendingUploadForDifferentChallenge
      }
      let requestStepTotal = try stepTotal(
        in: queued,
        contestID: contestID
      )
      let outcome = try await deliver(
        queued,
        ownerID: ownerID
      )
      switch outcome {
      case .accepted(let replayed):
        acceptedReplay = acceptedReplay || replayed
        confirmedStepTotal += requestStepTotal
      case .retainedForRetry:
        let retained = try await pendingUploads.pending(
          for: ownerID
        )
        return .queuedForRetry(
          stepTotal: try retainedStepTotal(
            in: retained,
            contestID: contestID
          )
        )
      case .savedRequestUnavailable:
        return .savedRequestUnavailable
      }
    }

    return .synced(
      replayed: acceptedReplay,
      stepTotal: confirmedStepTotal
    )
  }

  private func deliver(
    _ queued: PendingMetricUpload,
    ownerID: UUID
  ) async throws -> PendingDeliveryOutcome {
    var upload = queued
    let hadSavedSignedMaterial =
      queued.keyID != nil && queued.assertion != nil

    if upload.keyID == nil, upload.assertion == nil {
      let material: MetricSignedMaterial
      do {
        material = try await uploads.prepare(
          ownerID: ownerID,
          body: upload.body
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch let error as MetricUploadClientError {
        switch error.failureDisposition {
        case .retry:
          diagnostics.record(.retryRetained)
          return .retainedForRetry
        case .retain:
          throw error
        case .abandon:
          try await pendingUploads.abandon(
            ownerID: ownerID,
            batchID: upload.clientBatchId
          )
          diagnostics.record(.permanentRequestDiscarded)
          throw error
        }
      }

      let signingResult =
        try await pendingUploads
        .attachSignedMaterial(
          ownerID: ownerID,
          batchID: upload.clientBatchId,
          keyID: material.keyID,
          assertion: material.assertion,
          environment: material.environment
        )
      switch signingResult {
      case .attached, .alreadyAttached:
        diagnostics.record(.signedMaterialSaved)
      case .conflictingMaterial, .invalidMaterial:
        throw ActivitySyncError.conflictingSignedMaterial
      case .uploadNotFound:
        throw ActivitySyncError.queuedRequestUnavailable
      }

      guard
        let restored = try await pendingUploads.pending(
          for: ownerID
        ).first(where: {
          $0.clientBatchId == upload.clientBatchId
        })
      else {
        throw ActivitySyncError.queuedRequestUnavailable
      }
      upload = restored
    } else if upload.keyID == nil || upload.assertion == nil {
      throw ActivitySyncError.conflictingSignedMaterial
    }

    var receipt: MetricUploadReceipt?
    while receipt == nil {
      try await pendingUploads.recordAttempt(
        ownerID: ownerID,
        batchID: upload.clientBatchId
      )
      diagnostics.record(.uploadAttemptStarted)

      do {
        receipt = try await uploads.send(
          ownerID: ownerID,
          upload: upload
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch MetricUploadClientError
        .savedEvidenceFromDifferentEnvironment
      {
        try await pendingUploads.abandon(
          ownerID: ownerID,
          batchID: upload.clientBatchId
        )
        diagnostics.record(.foreignEnvironmentRequestDiscarded)
        return .savedRequestUnavailable
      } catch let error as MetricUploadClientError
        where error == .attestationRejected
          || error == .savedSignatureNeedsRefresh
      {
        // The original saved proof was refused by the authoritative server.
        // Never replace it with a fresh signature over old bytes. A request
        // signed during this invocation is a current failure, though, and must
        // not be mislabeled as evidence from an older build.
        try await pendingUploads.abandon(
          ownerID: ownerID,
          batchID: upload.clientBatchId
        )
        if hadSavedSignedMaterial {
          diagnostics.record(.rejectedSavedRequestDiscarded)
          return .savedRequestUnavailable
        }
        diagnostics.record(.rejectedCurrentRequestDiscarded)
        throw error
      } catch let error as MetricUploadClientError {
        switch error.failureDisposition {
        case .retry:
          diagnostics.record(.retryRetained)
          return .retainedForRetry
        case .retain:
          throw error
        case .abandon:
          try await pendingUploads.abandon(
            ownerID: ownerID,
            batchID: upload.clientBatchId
          )
          diagnostics.record(.permanentRequestDiscarded)
          throw error
        }
      }
    }
    guard let receipt else {
      throw MetricUploadClientError.invalidServerResponse
    }
    guard receipt.batchID == upload.clientBatchId else {
      throw MetricUploadClientError.invalidServerResponse
    }

    try await pendingUploads.acknowledge(
      ownerID: ownerID,
      batchID: upload.clientBatchId
    )
    diagnostics.record(
      receipt.replayed ? .replayAccepted : .uploadAccepted
    )
    return .accepted(replayed: receipt.replayed)
  }

  private static func savedUpload(
    _ upload: PendingMetricUpload,
    isTrustedBy expectedEnvironment: AppAttestEnvironment
  ) -> Bool {
    if upload.attestEnvironment == expectedEnvironment {
      return true
    }
    // The legacy queue format predates Release uploads. Its nil marker may be
    // retained inside Development, but must never cross into Production.
    return upload.attestEnvironment == nil
      && expectedEnvironment == .development
  }

  private func retainedStepTotal(
    in uploads: [PendingMetricUpload],
    contestID: UUID
  ) throws -> Double {
    try uploads.reduce(into: 0.0) { total, upload in
      guard upload.contestId == contestID else {
        throw ActivitySyncError.pendingUploadForDifferentChallenge
      }
      total += try stepTotal(
        in: upload,
        contestID: contestID
      )
      guard total.isFinite else {
        throw ActivitySyncError.queuedRequestUnavailable
      }
    }
  }

  private func stepTotal(
    in upload: PendingMetricUpload,
    contestID: UUID
  ) throws -> Double {
    let document: QueuedStepDocument
    do {
      document = try JSONDecoder().decode(
        QueuedStepDocument.self,
        from: upload.body
      )
    } catch {
      throw ActivitySyncError.queuedRequestUnavailable
    }
    guard
      document.contestID == contestID,
      !document.observations.isEmpty
    else {
      throw ActivitySyncError.queuedRequestUnavailable
    }

    return try document.observations.reduce(into: 0.0) {
      total,
      observation in
      guard
        observation.metric == ContestMetric.steps.rawValue,
        observation.value.isFinite,
        observation.value >= 0
      else {
        throw ActivitySyncError.queuedRequestUnavailable
      }
      total += observation.value
      guard total.isFinite else {
        throw ActivitySyncError.queuedRequestUnavailable
      }
    }
  }
}

private enum PendingDeliveryOutcome {
  case accepted(replayed: Bool)
  case retainedForRetry
  case savedRequestUnavailable
}

private struct QueuedStepDocument: Decodable {
  let contestID: UUID
  let observations: [Observation]

  enum CodingKeys: String, CodingKey {
    case contestID = "contestId"
    case observations
  }

  struct Observation: Decodable {
    let metric: String
    let value: Double
  }
}

private enum MetricUploadFailureDisposition {
  case retry
  case retain
  case abandon
}

extension MetricUploadClientError {
  fileprivate var failureDisposition: MetricUploadFailureDisposition {
    switch self {
    case .networkUnavailable, .serviceUnavailable,
      .deviceRegistrationUnavailable, .assertionUnavailable,
      .operationInProgress, .uploadVerificationFailed,
      .invalidServerResponse, .sessionRefreshFailed:
      .retry
    case .stagingOnly, .authenticationRequired, .tokenRefusedByService,
      .accountChanged, .appAttestUnsupported, .keyStateUnavailable,
      .savedSignatureNeedsRefresh,
      .savedEvidenceFromDifferentEnvironment, .attestationRejected,
      .accountNotActive,
      .registrationRefused:
      .retain
    case .invalidMetricBody, .unsignedUpload, .uploadConflict,
      .uploadRejected:
      .abandon
    }
  }
}

@MainActor
final class DisabledActivitySyncCoordinator: ActivitySyncing {
  func requestAuthorization() async throws
    -> ActivityAuthorizationOutcome
  {
    throw ActivitySyncError.stagingOnly
  }

  func pendingUploadCount(for ownerID: UUID) async throws -> Int {
    _ = ownerID
    return 0
  }

  func retirePendingUploads(
    for ownerID: UUID,
    contestID: UUID
  ) async throws {
    _ = (ownerID, contestID)
  }

  func sync(
    ownerID: UUID,
    contest: ContestCard,
    asOf: Date
  ) async throws -> ActivitySyncOutcome {
    _ = ownerID
    _ = contest
    _ = asOf
    throw ActivitySyncError.stagingOnly
  }
}
