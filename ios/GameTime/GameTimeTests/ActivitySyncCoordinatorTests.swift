import GameTimeCore
import XCTest

@testable import GameTime

@MainActor
final class ActivitySyncCoordinatorTests: XCTestCase {
  private let ownerA = UUID(
    uuidString: "a1000000-0000-0000-0000-000000000001"
  )!
  private let ownerB = UUID(
    uuidString: "b2000000-0000-0000-0000-000000000002"
  )!
  private let contestID = UUID(
    uuidString: "c3000000-0000-0000-0000-000000000003"
  )!
  /// 2026-08-03T00:00:00Z, clear of a daylight-saving transition.
  private let epoch = Date(timeIntervalSince1970: 1_785_888_000)

  func testRetirementOnlyAbandonsSpecifiedContest() async throws {
    let store = FilePendingMetricUploadStore(
      directoryURL: try makeTemporaryDirectory()
    )
    let otherContestID = UUID()
    let retiredBatchID = UUID()
    let retainedBatchID = UUID()
    _ = try await store.enqueue(
      ownerID: ownerA,
      contestID: contestID,
      request: try makeEncodedRequest(
        contestID: contestID,
        batchID: retiredBatchID,
        value: 100
      )
    )
    _ = try await store.enqueue(
      ownerID: ownerA,
      contestID: otherContestID,
      request: try makeEncodedRequest(
        contestID: otherContestID,
        batchID: retainedBatchID,
        value: 200
      )
    )
    let coordinator = ActivitySyncCoordinator(
      activity: ActivityClientFake(samples: []),
      uploads: MetricUploadClientFake(),
      pendingUploads: store
    )

    try await coordinator.retirePendingUploads(
      for: ownerA,
      contestID: contestID
    )

    let remaining = try await store.pending(for: ownerA)
    XCTAssertEqual(remaining.map(\.contestId), [otherContestID])
    XCTAssertEqual(remaining.map(\.clientBatchId), [retainedBatchID])
  }

  func testDeniedOrEmptyHealthReadDoesNotClaimDenialOrSend()
    async throws
  {
    // HealthKit intentionally makes a read denial indistinguishable from
    // an authorized query with no matching samples. Model both as the
    // empty result HealthKit returns, without inventing a denied state.
    let activity = ActivityClientFake(samples: [])
    let uploads = MetricUploadClientFake()
    let diagnostics = ActivitySyncDiagnosticsSpy()
    let store = FilePendingMetricUploadStore(
      directoryURL: try makeTemporaryDirectory()
    )
    let coordinator = ActivitySyncCoordinator(
      activity: activity,
      uploads: uploads,
      pendingUploads: store,
      diagnostics: diagnostics
    )
    let contest = makeContest()

    let outcome = try await coordinator.sync(
      ownerID: ownerA,
      contest: contest,
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )
    let pending = try await store.pending(for: ownerA)

    XCTAssertEqual(outcome, .noReadableData)
    XCTAssertEqual(
      activity.queriedWindows,
      [
        DateInterval(start: contest.startsAt, end: contest.endsAt)
      ])
    XCTAssertTrue(uploads.preparedBodies.isEmpty)
    XCTAssertTrue(uploads.sentUploads.isEmpty)
    XCTAssertTrue(pending.isEmpty)
    XCTAssertEqual(
      diagnostics.events,
      [.sampleQueryCompleted, .noReadableBuckets]
    )
  }

  func testUnavailableHealthAuthorizationIsCategoricalAndDoesNotQuery()
    async throws
  {
    let activity = ActivityClientFake(
      authorizationOutcome: .healthDataUnavailable,
      samples: []
    )
    let diagnostics = ActivitySyncDiagnosticsSpy()
    let coordinator = ActivitySyncCoordinator(
      activity: activity,
      uploads: MetricUploadClientFake(),
      pendingUploads: FilePendingMetricUploadStore(
        directoryURL: try makeTemporaryDirectory()
      ),
      diagnostics: diagnostics
    )

    let outcome = try await coordinator.requestAuthorization()

    XCTAssertEqual(outcome, .healthDataUnavailable)
    XCTAssertEqual(activity.authorizationRequestCount, 1)
    XCTAssertTrue(activity.queriedWindows.isEmpty)
    XCTAssertEqual(diagnostics.events, [.authorizationUnavailable])
  }

  func testStepSamplePreservesProvenanceMetadataAndBucketsInSteps()
    throws
  {
    let sample = makeSample(
      start: epoch.addingTimeInterval(15 * 60),
      end: epoch.addingTimeInterval(45 * 60),
      value: 600,
      source: "com.apple.health",
      manufacturer: "Apple Inc.",
      model: "Watch7,5"
    )
    let manual = makeSample(
      start: epoch.addingTimeInterval(20 * 60),
      end: epoch.addingTimeInterval(20 * 60),
      value: 25,
      wasUserEntered: true,
      source: "com.apple.health",
      manufacturer: "Apple Inc.",
      model: "iPhone"
    )
    let thirdParty = makeSample(
      start: epoch.addingTimeInterval(25 * 60),
      end: epoch.addingTimeInterval(25 * 60),
      value: 30,
      source: "com.example.runner",
      manufacturer: "Apple Inc.",
      model: "Watch"
    )

    XCTAssertEqual(sample.metric.rawValue, "steps")
    XCTAssertEqual(sample.provenance, .device)
    XCTAssertEqual(manual.provenance, .manual)
    XCTAssertEqual(thirdParty.provenance, .thirdParty)

    let buckets = HourlyBucketer(
      timeZone: try XCTUnwrap(TimeZone(identifier: "UTC"))
    ).buckets(
      from: [sample],
      window: DateInterval(
        start: epoch,
        end: epoch.addingTimeInterval(2 * 3_600)
      ),
      asOf: epoch.addingTimeInterval(3 * 3_600)
    )
    let bucket = try XCTUnwrap(buckets.first)

    XCTAssertEqual(buckets.count, 1)
    XCTAssertEqual(bucket.metric.rawValue, "steps")
    XCTAssertEqual(bucket.bucketStart, epoch)
    XCTAssertEqual(bucket.provenance, .device)
    XCTAssertEqual(bucket.value, 600)
    XCTAssertEqual(bucket.sampleCount, 1)
    XCTAssertEqual(
      bucket.sourceBundleIdentifier,
      "com.apple.health"
    )
    XCTAssertEqual(bucket.deviceModel, "Watch7,5")
  }

  func testFrozenTimezoneAlignmentAndChallengeWindowBoundariesFilterBuckets()
    throws
  {
    let timeZone = try XCTUnwrap(
      TimeZone(identifier: "Asia/Kolkata")
    )
    let window = DateInterval(
      start: epoch.addingTimeInterval(30 * 60),
      end: epoch.addingTimeInterval(2 * 3_600 + 30 * 60)
    )
    let samples = [
      // Its Kolkata hour starts before the challenge window.
      makeSample(
        start: epoch.addingTimeInterval(60),
        value: 100
      ),
      // Kolkata local hours begin at :30 UTC. These two are wholly in.
      makeSample(
        start: epoch.addingTimeInterval(31 * 60),
        value: 200
      ),
      makeSample(
        start: epoch.addingTimeInterval(91 * 60),
        value: 300
      ),
      // Its hour begins exactly at the half-open window end.
      makeSample(
        start: epoch.addingTimeInterval(151 * 60),
        value: 400
      ),
    ]

    let buckets = HourlyBucketer(timeZone: timeZone).buckets(
      from: samples,
      window: window,
      asOf: epoch.addingTimeInterval(5 * 3_600)
    )

    XCTAssertEqual(
      buckets.map(\.bucketStart),
      [
        epoch.addingTimeInterval(30 * 60),
        epoch.addingTimeInterval(90 * 60),
      ]
    )
    XCTAssertEqual(buckets.map(\.value), [200, 300])
  }

  func testLostResponseRelaunchRetriesExactBodyAndAssertionThenAcceptsReplay()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let firstStore = FilePendingMetricUploadStore(
      directoryURL: directory
    )
    let assertion = Data([0xa3, 0x01, 0xde, 0xad, 0xbe, 0xef])
    let firstUploads = MetricUploadClientFake(
      signedMaterial: MetricSignedMaterial(
        keyID: "verbatim/key+id==",
        assertion: assertion
      ),
      sendError: .networkUnavailable
    )
    let firstActivity = ActivityClientFake(
      samples: [
        makeSample(
          start: epoch.addingTimeInterval(15 * 60),
          end: epoch.addingTimeInterval(45 * 60),
          value: 1_234,
          source: "com.apple.health",
          manufacturer: "Apple Inc.",
          model: "Watch"
        )
      ]
    )
    let firstCoordinator = ActivitySyncCoordinator(
      activity: firstActivity,
      uploads: firstUploads,
      pendingUploads: firstStore
    )

    let firstOutcome = try await firstCoordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )
    let storedAfterLoss = try await firstStore.pending(for: ownerA)
    let firstSent = try XCTUnwrap(firstUploads.sentUploads.first)
    let retained = try XCTUnwrap(storedAfterLoss.first)

    XCTAssertEqual(
      firstOutcome,
      .queuedForRetry(stepTotal: 1_234)
    )
    XCTAssertEqual(storedAfterLoss.count, 1)
    XCTAssertEqual(retained.clientBatchId, firstSent.clientBatchId)
    XCTAssertEqual(retained.body, firstSent.body)
    XCTAssertEqual(retained.keyID, "verbatim/key+id==")
    XCTAssertEqual(retained.assertion, assertion)
    XCTAssertEqual(retained.attempts, 1)

    let relaunchedStore = FilePendingMetricUploadStore(
      directoryURL: directory
    )
    let replayUploads = MetricUploadClientFake(replayed: true)
    let relaunchedActivity = ActivityClientFake(samples: [])
    let relaunchedCoordinator = ActivitySyncCoordinator(
      activity: relaunchedActivity,
      uploads: replayUploads,
      pendingUploads: relaunchedStore
    )

    let replayOutcome = try await relaunchedCoordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(5 * 3_600)
    )
    let secondSent = try XCTUnwrap(replayUploads.sentUploads.first)
    let remaining = try await relaunchedStore.pending(for: ownerA)

    XCTAssertEqual(
      replayOutcome,
      .synced(replayed: true, stepTotal: 1_234)
    )
    XCTAssertTrue(relaunchedActivity.queriedWindows.isEmpty)
    XCTAssertTrue(replayUploads.preparedBodies.isEmpty)
    XCTAssertEqual(secondSent.clientBatchId, firstSent.clientBatchId)
    XCTAssertEqual(secondSent.contestId, firstSent.contestId)
    XCTAssertEqual(secondSent.body, firstSent.body)
    XCTAssertEqual(secondSent.keyID, firstSent.keyID)
    XCTAssertEqual(secondSent.assertion, firstSent.assertion)
    XCTAssertTrue(remaining.isEmpty)
  }

  func testSavedSignatureRefreshNeverReplacesTheFrozenProof()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let store = FilePendingMetricUploadStore(directoryURL: directory)
    let oldAssertion = Data([0x01, 0x02])
    let firstUploads = MetricUploadClientFake(
      signedMaterial: MetricSignedMaterial(
        keyID: "development-key",
        assertion: oldAssertion
      ),
      sendError: .networkUnavailable
    )
    let firstCoordinator = ActivitySyncCoordinator(
      activity: ActivityClientFake(
        samples: [
          makeSample(
            start: epoch.addingTimeInterval(15 * 60),
            value: 321
          )
        ]
      ),
      uploads: firstUploads,
      pendingUploads: store
    )
    _ = try await firstCoordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )
    let storedBeforeUpgrade = try await store.pending(for: ownerA)
    let frozenBody = try XCTUnwrap(storedBeforeUpgrade.first?.body)

    let upgradedUploads = MetricUploadClientFake(
      signedMaterial: MetricSignedMaterial(
        keyID: "production-key",
        assertion: Data([0x03, 0x04])
      ),
      sendError: .savedSignatureNeedsRefresh,
      replayed: true
    )
    let replayActivity = ActivityClientFake(samples: [])
    let upgradedCoordinator = ActivitySyncCoordinator(
      activity: replayActivity,
      uploads: upgradedUploads,
      pendingUploads: store
    )

    let outcome = try await upgradedCoordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(5 * 3_600)
    )

    XCTAssertEqual(outcome, .savedRequestUnavailable)
    XCTAssertTrue(upgradedUploads.preparedBodies.isEmpty)
    XCTAssertEqual(upgradedUploads.sentUploads.map(\.body), [frozenBody])
    XCTAssertEqual(
      upgradedUploads.sentUploads.map(\.keyID),
      ["development-key"]
    )
    XCTAssertEqual(
      upgradedUploads.sentUploads.map(\.assertion),
      [oldAssertion]
    )
    let remaining = try await store.pending(for: ownerA)
    XCTAssertTrue(remaining.isEmpty)
    XCTAssertTrue(replayActivity.queriedWindows.isEmpty)
  }

  func testProductionDiscardsDevelopmentEvidenceBeforeFreshRead()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let store = FilePendingMetricUploadStore(directoryURL: directory)
    let developmentUploads = MetricUploadClientFake(
      signedMaterial: MetricSignedMaterial(
        keyID: "development-key",
        assertion: Data([0x01]),
        environment: .development
      ),
      sendError: .networkUnavailable
    )
    let stagedCoordinator = ActivitySyncCoordinator(
      activity: ActivityClientFake(
        samples: [
          makeSample(
            start: epoch.addingTimeInterval(15 * 60),
            value: 321
          )
        ]
      ),
      uploads: developmentUploads,
      pendingUploads: store
    )
    _ = try await stagedCoordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )

    let productionUploads = MetricUploadClientFake(
      signedMaterial: MetricSignedMaterial(
        keyID: "production-key",
        assertion: Data([0x02]),
        environment: .production
      )
    )
    let productionActivity = ActivityClientFake(
      samples: [
        makeSample(
          start: epoch.addingTimeInterval(15 * 60),
          value: 321
        )
      ]
    )
    let productionCoordinator = ActivitySyncCoordinator(
      activity: productionActivity,
      uploads: productionUploads,
      pendingUploads: store
    )

    let discarded = try await productionCoordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(5 * 3_600)
    )

    XCTAssertEqual(discarded, .savedRequestUnavailable)
    XCTAssertTrue(productionUploads.preparedBodies.isEmpty)
    XCTAssertTrue(productionUploads.sentUploads.isEmpty)
    XCTAssertTrue(productionActivity.queriedWindows.isEmpty)
    let remainingAfterDiscard = try await store.pending(for: ownerA)
    XCTAssertTrue(remainingAfterDiscard.isEmpty)

    let fresh = try await productionCoordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(5 * 3_600)
    )

    XCTAssertEqual(
      fresh,
      .synced(replayed: false, stepTotal: 321)
    )
    XCTAssertEqual(productionActivity.queriedWindows.count, 1)
    XCTAssertEqual(
      productionUploads.sentUploads.map(\.attestEnvironment),
      [.production]
    )
  }

  func testRejectedProductionProofIsNeverResignedOverOldBytes()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let store = FilePendingMetricUploadStore(directoryURL: directory)
    let oldProductionUploads = MetricUploadClientFake(
      signedMaterial: MetricSignedMaterial(
        keyID: "old-production-key",
        assertion: Data([0x01]),
        environment: .production
      ),
      sendError: .networkUnavailable
    )
    let initialActivity = ActivityClientFake(
      samples: [
        makeSample(
          start: epoch.addingTimeInterval(15 * 60),
          value: 321
        )
      ]
    )
    let initialCoordinator = ActivitySyncCoordinator(
      activity: initialActivity,
      uploads: oldProductionUploads,
      pendingUploads: store
    )
    _ = try await initialCoordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )

    let currentProductionUploads = MetricUploadClientFake(
      signedMaterial: MetricSignedMaterial(
        keyID: "current-production-key",
        assertion: Data([0x02]),
        environment: .production
      ),
      sendErrors: [.attestationRejected, nil]
    )
    let freshActivity = ActivityClientFake(
      samples: [
        makeSample(
          start: epoch.addingTimeInterval(15 * 60),
          value: 321
        )
      ]
    )
    let coordinator = ActivitySyncCoordinator(
      activity: freshActivity,
      uploads: currentProductionUploads,
      pendingUploads: store
    )

    let refused = try await coordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(5 * 3_600)
    )

    XCTAssertEqual(refused, .savedRequestUnavailable)
    XCTAssertTrue(currentProductionUploads.preparedBodies.isEmpty)
    XCTAssertEqual(
      currentProductionUploads.sentUploads.map(\.keyID),
      ["old-production-key"]
    )
    XCTAssertTrue(freshActivity.queriedWindows.isEmpty)

    let fresh = try await coordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(5 * 3_600)
    )

    XCTAssertEqual(
      fresh,
      .synced(replayed: false, stepTotal: 321)
    )
    XCTAssertEqual(currentProductionUploads.preparedBodies.count, 1)
    XCTAssertEqual(
      currentProductionUploads.sentUploads.last?.keyID,
      "current-production-key"
    )
  }

  func testFreshlySignedRejectedProofRetriesWithANewHealthRead()
    async throws
  {
    let activity = ActivityClientFake(
      samples: [
        makeSample(
          start: epoch.addingTimeInterval(15 * 60),
          value: 321
        )
      ]
    )
    let uploads = MetricUploadClientFake(
      sendErrors: [.attestationRejected, nil]
    )
    let store = FilePendingMetricUploadStore(
      directoryURL: try makeTemporaryDirectory()
    )
    let coordinator = ActivitySyncCoordinator(
      activity: activity,
      uploads: uploads,
      pendingUploads: store
    )

    let outcome = try await coordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(5 * 3_600)
    )

    XCTAssertEqual(
      outcome,
      .synced(replayed: false, stepTotal: 321)
    )
    XCTAssertEqual(activity.queriedWindows.count, 2)
    XCTAssertEqual(uploads.preparedBodies.count, 2)
    XCTAssertEqual(uploads.sentUploads.count, 2)
    XCTAssertNotEqual(
      uploads.sentUploads[0].clientBatchId,
      uploads.sentUploads[1].clientBatchId
    )
    XCTAssertNotEqual(
      uploads.preparedBodies[0],
      uploads.preparedBodies[1]
    )
    let remaining = try await store.pending(for: ownerA)
    XCTAssertTrue(remaining.isEmpty)
  }

  func testRepeatedFreshProofRejectionIsNotReportedAsAnOlderRequest()
    async throws
  {
    let activity = ActivityClientFake(
      samples: [
        makeSample(
          start: epoch.addingTimeInterval(15 * 60),
          value: 321
        )
      ]
    )
    let uploads = MetricUploadClientFake(
      sendErrors: [.attestationRejected, .attestationRejected]
    )
    let store = FilePendingMetricUploadStore(
      directoryURL: try makeTemporaryDirectory()
    )
    let coordinator = ActivitySyncCoordinator(
      activity: activity,
      uploads: uploads,
      pendingUploads: store
    )

    do {
      _ = try await coordinator.sync(
        ownerID: ownerA,
        contest: makeContest(),
        asOf: epoch.addingTimeInterval(5 * 3_600)
      )
      XCTFail("a second current-key rejection must remain visible")
    } catch let error as MetricUploadClientError {
      XCTAssertEqual(error, .attestationRejected)
    }

    XCTAssertEqual(activity.queriedWindows.count, 2)
    XCTAssertEqual(uploads.preparedBodies.count, 2)
    XCTAssertEqual(uploads.sentUploads.count, 2)
    let remaining = try await store.pending(for: ownerA)
    XCTAssertTrue(remaining.isEmpty)
  }

  func testLargeStepHistoryIsChunkedAndFullyDelivered()
    async throws
  {
    let bucketCount =
      EncodedMetricRequest.maximumObservationCount + 1
    let buckets = (0..<bucketCount).map { index in
      HourlyBucket(
        metric: .steps,
        bucketStart: epoch.addingTimeInterval(
          Double(index) * 3_600
        ),
        provenance: .device,
        value: Double(index + 1),
        sampleCount: 1,
        sourceBundleIdentifier: "com.apple.health",
        deviceModel: "iPhone"
      )
    }
    let activity = ActivityClientFake(
      samples: [],
      buckets: buckets
    )
    let uploads = MetricUploadClientFake()
    let store = FilePendingMetricUploadStore(
      directoryURL: try makeTemporaryDirectory()
    )
    let coordinator = ActivitySyncCoordinator(
      activity: activity,
      uploads: uploads,
      pendingUploads: store
    )

    let outcome = try await coordinator.sync(
      ownerID: ownerA,
      contest: makeContest(
        durationHours: Double(bucketCount + 1)
      ),
      asOf: epoch.addingTimeInterval(
        Double(bucketCount + 1) * 3_600
      )
    )
    let observationCounts = try uploads.sentUploads.map {
      let document = try XCTUnwrap(
        JSONSerialization.jsonObject(
          with: $0.body
        ) as? [String: Any]
      )
      return try XCTUnwrap(
        document["observations"] as? [Any]
      ).count
    }

    XCTAssertEqual(
      outcome,
      .synced(replayed: false, stepTotal: 2_003_001)
    )
    XCTAssertEqual(uploads.preparedBodies.count, 2)
    XCTAssertEqual(uploads.sentUploads.count, 2)
    XCTAssertEqual(
      observationCounts,
      [EncodedMetricRequest.maximumObservationCount, 1]
    )
    let remaining = try await store.pending(for: ownerA)
    XCTAssertTrue(remaining.isEmpty)
  }

  func testPermanentUploadRejectionDoesNotBlockFutureStepSync()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let store = FilePendingMetricUploadStore(
      directoryURL: directory
    )
    let diagnostics = ActivitySyncDiagnosticsSpy()
    let rejected = ActivitySyncCoordinator(
      activity: ActivityClientFake(
        samples: [
          makeSample(
            start: epoch.addingTimeInterval(10 * 60),
            value: 250
          )
        ]
      ),
      uploads: MetricUploadClientFake(
        sendError: .uploadRejected
      ),
      pendingUploads: store,
      diagnostics: diagnostics
    )

    do {
      _ = try await rejected.sync(
        ownerID: ownerA,
        contest: makeContest(),
        asOf: epoch.addingTimeInterval(4 * 3_600)
      )
      XCTFail("Expected a permanent server refusal")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .uploadRejected
      )
    }

    let pendingAfterRejection = try await store.pending(
      for: ownerA
    )
    XCTAssertTrue(pendingAfterRejection.isEmpty)
    XCTAssertEqual(
      diagnostics.events.last,
      .permanentRequestDiscarded
    )

    let recovered = ActivitySyncCoordinator(
      activity: ActivityClientFake(
        samples: [
          makeSample(
            start: epoch.addingTimeInterval(20 * 60),
            value: 300
          )
        ]
      ),
      uploads: MetricUploadClientFake(),
      pendingUploads: store
    )
    let outcome = try await recovered.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )

    XCTAssertEqual(
      outcome,
      .synced(replayed: false, stepTotal: 300)
    )
    let pendingAfterRecovery = try await store.pending(
      for: ownerA
    )
    XCTAssertTrue(pendingAfterRecovery.isEmpty)
  }

  func testAccountBCannotSeeSendOrAcknowledgeAccountAsPendingUpload()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let store = FilePendingMetricUploadStore(directoryURL: directory)
    let ownerAUploads = MetricUploadClientFake(
      sendError: .networkUnavailable
    )
    let ownerACoordinator = ActivitySyncCoordinator(
      activity: ActivityClientFake(
        samples: [
          makeSample(
            start: epoch.addingTimeInterval(10 * 60),
            value: 250
          )
        ]
      ),
      uploads: ownerAUploads,
      pendingUploads: store
    )
    _ = try await ownerACoordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )

    let ownerBActivity = ActivityClientFake(samples: [])
    let ownerBUploads = MetricUploadClientFake(replayed: true)
    let ownerBCoordinator = ActivitySyncCoordinator(
      activity: ownerBActivity,
      uploads: ownerBUploads,
      pendingUploads: store
    )
    let ownerACountBefore =
      try await ownerBCoordinator
      .pendingUploadCount(for: ownerA)
    let ownerBCount = try await ownerBCoordinator.pendingUploadCount(
      for: ownerB
    )
    let ownerBOutcome = try await ownerBCoordinator.sync(
      ownerID: ownerB,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )
    let ownerAPendingAfter = try await store.pending(for: ownerA)

    XCTAssertEqual(ownerACountBefore, 1)
    XCTAssertEqual(ownerBCount, 0)
    XCTAssertEqual(ownerBOutcome, .noReadableData)
    XCTAssertTrue(ownerBUploads.preparedBodies.isEmpty)
    XCTAssertTrue(ownerBUploads.sentUploads.isEmpty)
    XCTAssertEqual(ownerAPendingAfter.count, 1)
  }

  func testPendingUploadForDifferentChallengeBlocksWithoutSendingOrQuerying()
    async throws
  {
    let directory = try makeTemporaryDirectory()
    let store = FilePendingMetricUploadStore(directoryURL: directory)
    let challengeA = makeContest()
    let challengeB = makeContest(
      id: UUID(
        uuidString: "d4000000-0000-0000-0000-000000000004"
      )!
    )
    let challengeAUploads = MetricUploadClientFake(
      sendError: .networkUnavailable
    )
    let challengeACoordinator = ActivitySyncCoordinator(
      activity: ActivityClientFake(
        samples: [
          makeSample(
            start: epoch.addingTimeInterval(10 * 60),
            value: 250
          )
        ]
      ),
      uploads: challengeAUploads,
      pendingUploads: store
    )
    let challengeAOutcome = try await challengeACoordinator.sync(
      ownerID: ownerA,
      contest: challengeA,
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )
    let pendingBefore = try await store.pending(for: ownerA)

    let challengeBActivity = ActivityClientFake(
      samples: [
        makeSample(
          start: epoch.addingTimeInterval(20 * 60),
          value: 500
        )
      ]
    )
    let challengeBUploads = MetricUploadClientFake()
    let challengeBCoordinator = ActivitySyncCoordinator(
      activity: challengeBActivity,
      uploads: challengeBUploads,
      pendingUploads: store
    )

    do {
      _ = try await challengeBCoordinator.sync(
        ownerID: ownerA,
        contest: challengeB,
        asOf: epoch.addingTimeInterval(4 * 3_600)
      )
      XCTFail("Expected the unrelated challenge retry to block sync")
    } catch {
      XCTAssertEqual(
        error as? ActivitySyncError,
        .pendingUploadForDifferentChallenge
      )
    }

    let pendingAfter = try await store.pending(for: ownerA)
    XCTAssertEqual(
      challengeAOutcome,
      .queuedForRetry(stepTotal: 250)
    )
    XCTAssertEqual(pendingBefore.count, 1)
    XCTAssertEqual(pendingAfter, pendingBefore)
    XCTAssertEqual(pendingAfter.first?.contestId, challengeA.id)
    XCTAssertTrue(challengeBActivity.queriedWindows.isEmpty)
    XCTAssertTrue(challengeBUploads.preparedBodies.isEmpty)
    XCTAssertTrue(challengeBUploads.sentUploads.isEmpty)
  }

  func testDiagnosticsAreCategoricalAndExcludeRawHealthOrPayloadValues()
    async throws
  {
    let sentinelValue = 9_876_543.21
    let sentinelSource = "com.example.private-health-sentinel"
    let diagnostics = ActivitySyncDiagnosticsSpy()
    let uploads = MetricUploadClientFake()
    let coordinator = ActivitySyncCoordinator(
      activity: ActivityClientFake(
        samples: [
          makeSample(
            start: epoch.addingTimeInterval(10 * 60),
            value: sentinelValue,
            source: sentinelSource,
            manufacturer: "Private Manufacturer",
            model: "Private Model"
          )
        ]
      ),
      uploads: uploads,
      pendingUploads: FilePendingMetricUploadStore(
        directoryURL: try makeTemporaryDirectory()
      ),
      diagnostics: diagnostics
    )

    let outcome = try await coordinator.sync(
      ownerID: ownerA,
      contest: makeContest(),
      asOf: epoch.addingTimeInterval(4 * 3_600)
    )
    let preparedBody = try XCTUnwrap(uploads.preparedBodies.first)
    let bodyText = try XCTUnwrap(
      String(data: preparedBody, encoding: .utf8)
    )
    let diagnosticText = diagnostics.events
      .map(\.rawValue)
      .joined(separator: "|")

    XCTAssertEqual(
      outcome,
      .synced(
        replayed: false,
        stepTotal: sentinelValue
      )
    )
    XCTAssertTrue(bodyText.contains(sentinelSource))
    XCTAssertTrue(bodyText.contains("9876543.21"))
    XCTAssertEqual(
      diagnostics.events,
      [
        .sampleQueryCompleted,
        .exactRequestQueued,
        .signedMaterialSaved,
        .uploadAttemptStarted,
        .uploadAccepted,
      ]
    )
    XCTAssertFalse(diagnosticText.contains(sentinelSource))
    XCTAssertFalse(diagnosticText.contains("9876543.21"))
    XCTAssertFalse(diagnosticText.contains(bodyText))
    XCTAssertFalse(
      diagnosticText.contains(preparedBody.base64EncodedString())
    )
  }

  func testCoordinatorRejectsInactiveUnacceptedAndNonStepChallenges()
    async throws
  {
    let activity = ActivityClientFake(samples: [])
    let uploads = MetricUploadClientFake()
    let coordinator = ActivitySyncCoordinator(
      activity: activity,
      uploads: uploads,
      pendingUploads: FilePendingMetricUploadStore(
        directoryURL: try makeTemporaryDirectory()
      )
    )

    await assertChallengeRejected(
      makeContest(status: .pending),
      by: coordinator
    )
    await assertChallengeRejected(
      makeContest(participantStatus: .invited),
      by: coordinator
    )
    await assertChallengeRejected(
      makeContest(metric: .distanceMeters),
      by: coordinator
    )

    XCTAssertTrue(activity.queriedWindows.isEmpty)
    XCTAssertTrue(uploads.preparedBodies.isEmpty)
    XCTAssertTrue(uploads.sentUploads.isEmpty)
  }

  private func assertChallengeRejected(
    _ contest: ContestCard,
    by coordinator: ActivitySyncCoordinator,
    file: StaticString = #filePath,
    line: UInt = #line
  ) async {
    do {
      _ = try await coordinator.sync(
        ownerID: ownerA,
        contest: contest,
        asOf: epoch.addingTimeInterval(4 * 3_600)
      )
      XCTFail(
        "Expected ineligible challenge to be rejected",
        file: file,
        line: line
      )
    } catch {
      XCTAssertEqual(
        error as? ActivitySyncError,
        .challengeNotEligible,
        file: file,
        line: line
      )
    }
  }

  private func makeContest(
    id: UUID? = nil,
    metric: GameTime.ContestMetric = .steps,
    status: ContestStatus = .active,
    participantStatus: ContestParticipantStatus = .accepted,
    durationHours: Double = 3
  ) -> ContestCard {
    ContestCard(
      id: id ?? contestID,
      title: "Steps only",
      createdBy: ownerA,
      metric: metric,
      cadence: .cumulative,
      targetValue: 10_000,
      stakeAmountCents: 500,
      tieBreak: .integrityScore,
      startsAt: epoch,
      endsAt: epoch.addingTimeInterval(durationHours * 3_600),
      status: status,
      myStatus: participantStatus,
      maxParticipants: 2,
      participantTimeZone: "UTC",
      timeZoneChanges: [],
      participants: []
    )
  }

  private func makeSample(
    start: Date,
    end: Date? = nil,
    value: Double,
    wasUserEntered: Bool = false,
    source: String? = "com.apple.health",
    manufacturer: String? = "Apple Inc.",
    model: String? = "iPhone"
  ) -> ActivityStepSample {
    ActivityStepSample(
      start: start,
      end: end ?? start,
      value: value,
      wasUserEntered: wasUserEntered,
      sourceBundleIdentifier: source,
      deviceManufacturer: manufacturer,
      deviceModel: model
    )
  }

  private func makeEncodedRequest(
    contestID: UUID,
    batchID: UUID,
    value: Double
  ) throws -> EncodedMetricRequest {
    try EncodedMetricRequest(
      payload: AttestedMetricPayload(
        contestId: contestID,
        clientBatchId: batchID,
        observedAt: epoch.addingTimeInterval(3_600),
        observations: [
          HourlyBucket(
            metric: .steps,
            bucketStart: epoch,
            provenance: .device,
            value: value,
            sampleCount: 1,
            sourceBundleIdentifier: "com.apple.health",
            deviceModel: "iPhone"
          )
        ]
      )
    )
  }

  private func makeTemporaryDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(
        "GameTimeActivitySyncTests-\(UUID().uuidString)",
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

@MainActor
private final class ActivityClientFake: ActivityClient {
  private let authorizationOutcome: ActivityAuthorizationOutcome
  private let samples: [ActivityStepSample]
  private let buckets: [HourlyBucket]?

  private(set) var authorizationRequestCount = 0
  private(set) var queriedWindows: [DateInterval] = []

  init(
    authorizationOutcome: ActivityAuthorizationOutcome = .requestCompleted,
    samples: [ActivityStepSample],
    buckets: [HourlyBucket]? = nil
  ) {
    self.authorizationOutcome = authorizationOutcome
    self.samples = samples
    self.buckets = buckets
  }

  func requestStepReadAuthorization() async throws
    -> ActivityAuthorizationOutcome
  {
    authorizationRequestCount += 1
    return authorizationOutcome
  }

  func stepBuckets(
    overlapping challengeWindow: DateInterval,
    timeZoneSchedule: ContestTimeZoneSchedule,
    asOf: Date
  ) async throws -> [HourlyBucket] {
    queriedWindows.append(challengeWindow)
    if let buckets {
      return buckets
    }
    return HourlyBucketer(
      timeZoneSchedule: timeZoneSchedule
    ).buckets(
      from: samples,
      window: challengeWindow,
      asOf: asOf
    )
  }
}

@MainActor
private final class MetricUploadClientFake: MetricUploadClient {
  private let signedMaterial: MetricSignedMaterial
  private var sendErrors: [MetricUploadClientError?]
  private let replayed: Bool

  private(set) var preparedOwners: [UUID] = []
  private(set) var preparedBodies: [Data] = []
  private(set) var sentOwners: [UUID] = []
  private(set) var sentUploads: [PendingMetricUpload] = []

  var expectedAttestationEnvironment: AppAttestEnvironment? {
    signedMaterial.environment
  }

  init(
    signedMaterial: MetricSignedMaterial = MetricSignedMaterial(
      keyID: "test-key",
      assertion: Data([0x01, 0x02, 0x03])
    ),
    sendError: MetricUploadClientError? = nil,
    sendErrors: [MetricUploadClientError?]? = nil,
    replayed: Bool = false
  ) {
    self.signedMaterial = signedMaterial
    self.sendErrors = sendErrors ?? [sendError]
    self.replayed = replayed
  }

  func prepare(
    ownerID: UUID,
    body: Data
  ) async throws -> MetricSignedMaterial {
    preparedOwners.append(ownerID)
    preparedBodies.append(body)
    return signedMaterial
  }

  func send(
    ownerID: UUID,
    upload: PendingMetricUpload
  ) async throws -> MetricUploadReceipt {
    sentOwners.append(ownerID)
    sentUploads.append(upload)
    if !sendErrors.isEmpty, let sendError = sendErrors.removeFirst() {
      throw sendError
    }
    return MetricUploadReceipt(
      batchID: upload.clientBatchId,
      replayed: replayed,
      observationCount: 1
    )
  }
}

@MainActor
private final class ActivitySyncDiagnosticsSpy: ActivitySyncDiagnostics {
  private(set) var events: [ActivitySyncDiagnosticEvent] = []

  func record(_ event: ActivitySyncDiagnosticEvent) {
    events.append(event)
  }
}
