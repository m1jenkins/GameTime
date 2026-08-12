import CryptoKit
import GameTimeCore
import XCTest

@testable import GameTime

@MainActor
final class SupabaseMetricUploadClientTests: XCTestCase {
  private let ownerA = UUID(
    uuidString: "a1000000-0000-0000-0000-000000000001"
  )!
  private let ownerB = UUID(
    uuidString: "b2000000-0000-0000-0000-000000000002"
  )!
  private let contestID = UUID(
    uuidString: "c3000000-0000-0000-0000-000000000003"
  )!
  private let batchID = UUID(
    uuidString: "d4000000-0000-0000-0000-000000000004"
  )!

  func testPrepareHashesExactBodyAndPersistsRegisteredKeyByOwner()
    async throws
  {
    let session = MetricTransportSessionFake(ownerID: ownerA)
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    let challenge = Data((0..<32).map(UInt8.init))
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "challenge": challenge.base64EncodedString(),
            "expiresInSeconds": 600,
          ])
        )
      ),
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "registered": true,
            "environment": "development",
          ])
        )
      ),
    ])
    let client = try makeClient(
      session: session,
      appAttest: appAttest,
      stateStore: stateStore,
      transport: transport
    )
    let body = exactMetricBody()

    let material = try await client.prepare(
      ownerID: ownerA,
      body: body
    )

    XCTAssertEqual(
      material,
      MetricSignedMaterial(
        keyID: appAttest.generatedKeyID,
        assertion: appAttest.assertion
      )
    )
    XCTAssertEqual(
      appAttest.attestationHashes,
      [sha256(challenge)]
    )
    XCTAssertEqual(
      appAttest.assertionHashes,
      [sha256(body)]
    )
    XCTAssertEqual(
      stateStore.states[ownerA],
      MetricAppAttestState(
        ownerID: ownerA,
        keyID: appAttest.generatedKeyID,
        registered: true,
        environment: .development
      )
    )
    XCTAssertNil(stateStore.states[ownerB])
    XCTAssertEqual(stateStore.savedOwners, [ownerA])
    XCTAssertEqual(stateStore.registeredOwners, [ownerA])
    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertEqual(
      transport.requests[0].url?.path,
      "/functions/v1/attest-device/challenge"
    )
    XCTAssertEqual(
      transport.requests[1].url?.path,
      "/functions/v1/attest-device"
    )

    let registrationBody = try XCTUnwrap(
      transport.requests[1].httpBody
    )
    let registration = try XCTUnwrap(
      JSONSerialization.jsonObject(with: registrationBody)
        as? [String: String]
    )
    XCTAssertEqual(
      registration["keyId"],
      appAttest.generatedKeyID
    )
    XCTAssertEqual(
      registration["attestation"],
      appAttest.attestation.base64EncodedString()
    )
    XCTAssertFalse(registrationBody.containsSubdata(body))
  }

  func testLostInitialRegistrationResponseRelaunchReplaysExactPersistedBody()
    async throws
  {
    let suiteName = "GameTimeTests.MetricAppAttest.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let session = MetricTransportSessionFake(ownerID: ownerA)
    let firstAppAttest = MetricTransportAppAttestFake()
    let challenge = Data((32..<64).map(UInt8.init))
    let firstTransport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "challenge": challenge.base64EncodedString(),
            "expiresInSeconds": 600,
          ])
        )
      ),
      .failure(
        MetricTransportRawError(
          description: "registration response was lost"
        )
      ),
    ])
    let firstStore = UserDefaultsMetricAppAttestStateStore(
      defaults: defaults
    )
    let requestTime = Date(timeIntervalSince1970: 1_785_888_000)
    let firstClient = try makeClient(
      session: session,
      appAttest: firstAppAttest,
      stateStore: firstStore,
      transport: firstTransport,
      now: { requestTime }
    )
    let metricBody = exactMetricBody()

    do {
      _ = try await firstClient.prepare(
        ownerID: ownerA,
        body: metricBody
      )
      XCTFail("Expected the committed registration response to be lost")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .networkUnavailable
      )
    }

    XCTAssertEqual(firstTransport.requests.count, 2)
    let firstRegistrationBody = try XCTUnwrap(
      firstTransport.requests[1].httpBody
    )
    let persistedBeforeRelaunch = try XCTUnwrap(
      firstStore.state(for: ownerA)
    )
    XCTAssertFalse(persistedBeforeRelaunch.registered)
    XCTAssertEqual(
      persistedBeforeRelaunch.pendingRegistrationBody,
      firstRegistrationBody
    )
    XCTAssertEqual(
      persistedBeforeRelaunch.pendingRegistrationExpiresAt,
      requestTime.addingTimeInterval(10 * 60)
    )
    XCTAssertEqual(
      firstAppAttest.attestationHashes,
      [sha256(challenge)]
    )
    XCTAssertTrue(firstAppAttest.assertionHashes.isEmpty)

    let relaunchedStore = UserDefaultsMetricAppAttestStateStore(
      defaults: defaults
    )
    let relaunchedAppAttest = MetricTransportAppAttestFake()
    let relaunchedTransport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "registered": true,
            "environment": "development",
          ])
        )
      )
    ])
    let relaunchedClient = try makeClient(
      session: session,
      appAttest: relaunchedAppAttest,
      stateStore: relaunchedStore,
      transport: relaunchedTransport,
      now: { requestTime.addingTimeInterval(60) }
    )

    let material = try await relaunchedClient.prepare(
      ownerID: ownerA,
      body: metricBody
    )

    XCTAssertEqual(
      material,
      MetricSignedMaterial(
        keyID: firstAppAttest.generatedKeyID,
        assertion: relaunchedAppAttest.assertion
      )
    )
    XCTAssertEqual(relaunchedTransport.requests.count, 1)
    XCTAssertEqual(
      relaunchedTransport.requests[0].url?.path,
      "/functions/v1/attest-device"
    )
    XCTAssertEqual(
      relaunchedTransport.requests[0].httpBody,
      firstRegistrationBody
    )
    XCTAssertEqual(relaunchedAppAttest.generateKeyCallCount, 0)
    XCTAssertTrue(relaunchedAppAttest.attestationHashes.isEmpty)
    XCTAssertEqual(
      relaunchedAppAttest.assertionHashes,
      [sha256(metricBody)]
    )

    let registeredAfterReplay = try XCTUnwrap(
      relaunchedStore.state(for: ownerA)
    )
    XCTAssertTrue(registeredAfterReplay.registered)
    XCTAssertNil(registeredAfterReplay.pendingRegistrationBody)
  }

  func testExpiredPendingRegistrationRotatesKeyBeforeFreshAttestation()
    async throws
  {
    let suiteName = "GameTimeTests.MetricAppAttest.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let now = Date(timeIntervalSince1970: 1_785_889_000)
    let oldKeyID = Data("expired-app-attest-key".utf8)
      .base64EncodedString()
    let expiredBody = try registrationBody(
      keyID: oldKeyID,
      attestation: Data("expired exact attestation".utf8)
    )
    let store = UserDefaultsMetricAppAttestStateStore(defaults: defaults)
    try store.saveGeneratedKey(
      oldKeyID,
      environment: .development,
      ownerID: ownerA
    )
    try store.savePendingRegistrationBody(
      expiredBody,
      expiresAt: now.addingTimeInterval(-1),
      keyID: oldKeyID,
      ownerID: ownerA
    )

    let challenge = Data((64..<96).map(UInt8.init))
    let appAttest = MetricTransportAppAttestFake()
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "challenge": challenge.base64EncodedString(),
            "expiresInSeconds": 600,
          ])
        )
      ),
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "registered": true,
            "environment": "development",
          ])
        )
      ),
    ])
    let client = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: appAttest,
      stateStore: store,
      transport: transport,
      now: { now }
    )

    let material = try await client.prepare(
      ownerID: ownerA,
      body: exactMetricBody()
    )

    XCTAssertEqual(appAttest.generateKeyCallCount, 1)
    XCTAssertEqual(appAttest.attestationHashes, [sha256(challenge)])
    XCTAssertEqual(material.keyID, appAttest.generatedKeyID)
    XCTAssertEqual(transport.requests.count, 2)
    XCTAssertEqual(
      transport.requests.map(\.url?.path),
      [
        "/functions/v1/attest-device/challenge",
        "/functions/v1/attest-device",
      ]
    )
    let replacementBody = try XCTUnwrap(transport.requests[1].httpBody)
    XCTAssertNotEqual(replacementBody, expiredBody)
    let replacementDocument = try XCTUnwrap(
      JSONSerialization.jsonObject(with: replacementBody)
        as? [String: String]
    )
    XCTAssertEqual(
      replacementDocument["keyId"],
      appAttest.generatedKeyID
    )

    let registered = try XCTUnwrap(store.state(for: ownerA))
    XCTAssertEqual(registered.keyID, appAttest.generatedKeyID)
    XCTAssertTrue(registered.registered)
    XCTAssertNil(registered.pendingRegistrationBody)
    XCTAssertNil(registered.pendingRegistrationExpiresAt)
  }

  func testUnexpiredUnauthorizedRegistrationKeepsExactBodyAndKey()
    async throws
  {
    let suiteName = "GameTimeTests.MetricAppAttest.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let now = Date(timeIntervalSince1970: 1_785_889_000)
    let appAttest = MetricTransportAppAttestFake()
    let pendingBody = try registrationBody(
      keyID: appAttest.generatedKeyID,
      attestation: Data("unexpired exact attestation".utf8)
    )
    let expiresAt = now.addingTimeInterval(60)
    let store = UserDefaultsMetricAppAttestStateStore(defaults: defaults)
    try store.saveGeneratedKey(
      appAttest.generatedKeyID,
      environment: .development,
      ownerID: ownerA
    )
    try store.savePendingRegistrationBody(
      pendingBody,
      expiresAt: expiresAt,
      keyID: appAttest.generatedKeyID,
      ownerID: ownerA
    )
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 401,
          body: Data("categorical unauthorized".utf8)
        )
      )
    ])
    let client = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: appAttest,
      stateStore: store,
      transport: transport,
      now: { now }
    )

    do {
      _ = try await client.prepare(
        ownerID: ownerA,
        body: exactMetricBody()
      )
      XCTFail("Expected the unexpired registration retry to fail closed")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .registrationRefused
      )
    }

    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests[0].httpBody, pendingBody)
    XCTAssertEqual(appAttest.generateKeyCallCount, 0)
    XCTAssertTrue(appAttest.attestationHashes.isEmpty)
    XCTAssertTrue(appAttest.assertionHashes.isEmpty)
    let retained = try XCTUnwrap(store.state(for: ownerA))
    XCTAssertEqual(retained.keyID, appAttest.generatedKeyID)
    XCTAssertEqual(retained.pendingRegistrationBody, pendingBody)
    XCTAssertEqual(retained.pendingRegistrationExpiresAt, expiresAt)
  }

  /// The refusal that started this: an attestation the server could not verify
  /// arrives as 401, and reporting it as an expired session sends somebody to
  /// the sign-in screen to fix a device that cannot attest.
  func testUnverifiableAttestationIsNotReportedAsASignInProblem()
    async throws
  {
    for message in [
      "the attestation could not be verified",
      "the receipt could not be verified",
    ] {
      let surfaced = try await registrationRefusal(
        statusCode: 401,
        body: try jsonData([
          "error": "unauthorized",
          "message": message,
        ])
      )
      XCTAssertEqual(surfaced, .attestationRejected)
      XCTAssertEqual(
        surfaced.errorDescription,
        MetricUploadClientError.attestationRejected.errorDescription
      )
    }
  }

  func testInactiveAccountIsNotReportedAsASignInProblem() async throws {
    let surfaced = try await registrationRefusal(
      statusCode: 403,
      body: try jsonData([
        "error": "forbidden",
        "message": "this account is not active",
      ])
    )
    XCTAssertEqual(surfaced, .accountNotActive)
  }

  func testMetricAssertionRefusalIsReportedAsAttestationRejected()
    async throws
  {
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    stateStore.seedRegistered(
      ownerID: ownerA,
      keyID: appAttest.generatedKeyID
    )
    let client = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: appAttest,
      stateStore: stateStore,
      transport: MetricTransportHTTPFake(outcomes: [
        .response(
          MetricUploadHTTPResponse(
            statusCode: 401,
            body: try jsonData([
              "error": "unauthorized",
              "message": "the assertion could not be verified",
            ])
          )
        )
      ])
    )

    do {
      _ = try await client.send(
        ownerID: ownerA,
        upload: signedUpload(
          keyID: appAttest.generatedKeyID,
          assertion: appAttest.assertion
        )
      )
      XCTFail("Expected the refused assertion to fail closed")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .attestationRejected
      )
    }
  }

  func testRejectedCurrentKeyIsDurablyInvalidatedAndNextPrepareRegistersNewKey()
    async throws
  {
    let suiteName = "GameTimeTests.MetricAppAttest.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let rejectedKeyID = Data("rejected-current-key".utf8)
      .base64EncodedString()
    let initialStore = UserDefaultsMetricAppAttestStateStore(
      defaults: defaults
    )
    try initialStore.saveGeneratedKey(
      rejectedKeyID,
      environment: .development,
      ownerID: ownerA
    )
    try initialStore.markRegistered(
      keyID: rejectedKeyID,
      environment: .development,
      ownerID: ownerA
    )
    try initialStore.saveGeneratedKey(
      rejectedKeyID,
      environment: .development,
      ownerID: ownerB
    )
    try initialStore.markRegistered(
      keyID: rejectedKeyID,
      environment: .development,
      ownerID: ownerB
    )

    let rejectedUpload = signedUpload(
      keyID: rejectedKeyID,
      assertion: Data("rejected saved assertion".utf8)
    )
    let initialAppAttest = MetricTransportAppAttestFake()
    let initialTransport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 401,
          body: try jsonData([
            "error": "unauthorized",
            "message": "the assertion could not be verified",
          ])
        )
      )
    ])
    let initialClient = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: initialAppAttest,
      stateStore: initialStore,
      transport: initialTransport
    )

    do {
      _ = try await initialClient.send(
        ownerID: ownerA,
        upload: rejectedUpload
      )
      XCTFail("Expected the saved assertion to be rejected")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .attestationRejected
      )
    }

    XCTAssertEqual(initialTransport.requests.count, 1)
    XCTAssertEqual(initialTransport.requests[0].httpBody, rejectedUpload.body)
    XCTAssertEqual(
      initialTransport.requests[0].value(
        forHTTPHeaderField: "x-gametime-key-id"
      ),
      rejectedKeyID
    )
    XCTAssertTrue(initialAppAttest.assertionHashes.isEmpty)

    // A new store instance models relaunch: invalidation must be persisted,
    // not merely remembered by the client that received the refusal.
    let relaunchedStore = UserDefaultsMetricAppAttestStateStore(
      defaults: defaults
    )
    XCTAssertNil(try relaunchedStore.state(for: ownerA))
    XCTAssertEqual(
      try relaunchedStore.state(for: ownerB),
      MetricAppAttestState(
        ownerID: ownerB,
        keyID: rejectedKeyID,
        registered: true,
        environment: .development
      )
    )

    let replacementAppAttest = MetricTransportAppAttestFake()
    XCTAssertNotEqual(replacementAppAttest.generatedKeyID, rejectedKeyID)
    let challenge = Data(repeating: 0x44, count: 32)
    let replacementTransport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "challenge": challenge.base64EncodedString(),
            "expiresInSeconds": 600,
          ])
        )
      ),
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "registered": true,
            "environment": "development",
          ])
        )
      ),
    ])
    let relaunchedClient = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: replacementAppAttest,
      stateStore: relaunchedStore,
      transport: replacementTransport
    )
    let freshBody = exactMetricBody(
      sourceBundleID: "com.private.health.source.after-key-recovery"
    )
    XCTAssertNotEqual(freshBody, rejectedUpload.body)

    let replacement = try await relaunchedClient.prepare(
      ownerID: ownerA,
      body: freshBody
    )

    XCTAssertEqual(replacement.keyID, replacementAppAttest.generatedKeyID)
    XCTAssertEqual(replacementAppAttest.generateKeyCallCount, 1)
    XCTAssertEqual(
      replacementAppAttest.assertionHashes,
      [sha256(freshBody)]
    )
    XCTAssertEqual(replacementTransport.requests.count, 2)
    XCTAssertEqual(
      try relaunchedStore.state(for: ownerA),
      MetricAppAttestState(
        ownerID: ownerA,
        keyID: replacementAppAttest.generatedKeyID,
        registered: true,
        environment: .development
      )
    )
  }

  func testRejectedOlderQueuedKeyDoesNotInvalidateNewerCurrentKey()
    async throws
  {
    let suiteName = "GameTimeTests.MetricAppAttest.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let staleKeyID = Data("older-queued-key".utf8)
      .base64EncodedString()
    let appAttest = MetricTransportAppAttestFake()
    let currentKeyID = appAttest.generatedKeyID
    let stateStore = UserDefaultsMetricAppAttestStateStore(
      defaults: defaults
    )
    try stateStore.saveGeneratedKey(
      currentKeyID,
      environment: .development,
      ownerID: ownerA
    )
    try stateStore.markRegistered(
      keyID: currentKeyID,
      environment: .development,
      ownerID: ownerA
    )
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 401,
          body: try jsonData([
            "error": "unauthorized",
            "message": "the assertion could not be verified",
          ])
        )
      )
    ])
    let client = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: appAttest,
      stateStore: stateStore,
      transport: transport
    )

    do {
      _ = try await client.send(
        ownerID: ownerA,
        upload: signedUpload(
          keyID: staleKeyID,
          assertion: Data("older saved assertion".utf8)
        )
      )
      XCTFail("Expected the older saved assertion to be rejected")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .attestationRejected
      )
    }

    XCTAssertEqual(
      try stateStore.state(for: ownerA),
      MetricAppAttestState(
        ownerID: ownerA,
        keyID: currentKeyID,
        registered: true,
        environment: .development
      )
    )

    let freshBody = exactMetricBody(
      sourceBundleID: "com.private.health.source.with-current-key"
    )
    let signed = try await client.prepare(
      ownerID: ownerA,
      body: freshBody
    )

    XCTAssertEqual(signed.keyID, currentKeyID)
    XCTAssertEqual(appAttest.generateKeyCallCount, 0)
    XCTAssertEqual(appAttest.assertionHashes, [sha256(freshBody)])
    XCTAssertEqual(transport.requests.count, 1)
  }

  /// A token the service will not accept is not a device without a session.
  /// Both used to read "sign in again", which is advice that cannot work when
  /// a fresh token is refused for the same reason the last one was.
  func testRefusedTokenIsDistinctFromHavingNoSession() async throws {
    let refused = try await registrationRefusal(
      statusCode: 401,
      body: try jsonData([
        "error": "unauthorized",
        "message": "sign in again",
      ])
    )
    XCTAssertEqual(refused, .tokenRefusedByService)

    let client = try makeClient(
      session: MetricTransportSessionFake(ownerID: nil),
      appAttest: MetricTransportAppAttestFake(),
      stateStore: MetricTransportStateStoreFake(),
      transport: MetricTransportHTTPFake(outcomes: [])
    )
    do {
      _ = try await client.prepare(
        ownerID: ownerA,
        body: exactMetricBody()
      )
      XCTFail("Expected a signed-out device to fail closed")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .authenticationRequired
      )
    }
    XCTAssertNotEqual(
      MetricUploadClientError.tokenRefusedByService.errorDescription,
      MetricUploadClientError.authenticationRequired.errorDescription
    )
  }

  /// A refresh that could not be completed is not a refused account. Saying
  /// "sign in again" there asks for credentials when the connection is what
  /// failed, and it is retryable where a refused account is not.
  func testUnfinishedSessionRefreshIsNotReportedAsASignInProblem()
    async throws
  {
    let session = MetricTransportSessionFake(ownerID: ownerA)
    session.refreshFailure = .sessionRefreshFailed
    let transport = MetricTransportHTTPFake(outcomes: [])
    let client = try makeClient(
      session: session,
      appAttest: MetricTransportAppAttestFake(),
      stateStore: MetricTransportStateStoreFake(),
      transport: transport
    )

    do {
      _ = try await client.prepare(
        ownerID: ownerA,
        body: exactMetricBody()
      )
      XCTFail("Expected the unfinished refresh to fail closed")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .sessionRefreshFailed
      )
    }
    XCTAssertTrue(transport.requests.isEmpty)
    XCTAssertGreaterThan(session.validSessionCallCount, 0)
  }

  /// Every request carries a token read at the moment it is sent, so a token
  /// that was refreshed mid-flight is the one that reaches the server.
  func testEachRequestCarriesTheTokenReadWhenItWasSent() async throws {
    let appAttest = MetricTransportAppAttestFake()
    let session = MetricTransportSessionFake(ownerID: ownerA)
    session.accessToken = "stale-access-token"
    let challenge = Data(repeating: 0x5A, count: 32)
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "challenge": challenge.base64EncodedString(),
            "expiresInSeconds": 600,
          ])
        )
      ),
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "registered": true,
            "environment": "development",
          ])
        )
      ),
    ])
    // The SDK refreshes a stored token that has expired, so the value read
    // before the challenge need not be the value read before registration.
    appAttest.onGenerateKey = { session.accessToken = "refreshed-access-token" }
    let client = try makeClient(
      session: session,
      appAttest: appAttest,
      stateStore: MetricTransportStateStoreFake(),
      transport: transport
    )

    _ = try await client.prepare(
      ownerID: ownerA,
      body: exactMetricBody()
    )

    XCTAssertEqual(transport.requests.count, 2)
    for request in transport.requests {
      XCTAssertEqual(
        request.value(forHTTPHeaderField: "Authorization"),
        "Bearer refreshed-access-token"
      )
    }
  }

  private func registrationRefusal(
    statusCode: Int,
    body: Data
  ) async throws -> MetricUploadClientError {
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    let client = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: appAttest,
      stateStore: stateStore,
      transport: MetricTransportHTTPFake(outcomes: [
        .response(
          MetricUploadHTTPResponse(
            statusCode: statusCode,
            body: body
          )
        )
      ])
    )

    do {
      _ = try await client.prepare(
        ownerID: ownerA,
        body: exactMetricBody()
      )
      XCTFail("Expected the refused registration to fail closed")
      return .invalidServerResponse
    } catch let error as MetricUploadClientError {
      return error
    }
  }

  func testExpiredKeyRotationStopsOnAccountSwitchWithoutChangingState()
    async throws
  {
    let suiteName = "GameTimeTests.MetricAppAttest.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let now = Date(timeIntervalSince1970: 1_785_889_000)
    let oldKeyID = Data("account-switch-expired-key".utf8)
      .base64EncodedString()
    let expiredBody = try registrationBody(
      keyID: oldKeyID,
      attestation: Data("account switch exact attestation".utf8)
    )
    let store = UserDefaultsMetricAppAttestStateStore(defaults: defaults)
    try store.saveGeneratedKey(
      oldKeyID,
      environment: .development,
      ownerID: ownerA
    )
    try store.savePendingRegistrationBody(
      expiredBody,
      expiresAt: now.addingTimeInterval(-1),
      keyID: oldKeyID,
      ownerID: ownerA
    )
    let session = MetricTransportSessionFake(ownerID: ownerA)
    let appAttest = MetricTransportAppAttestFake()
    appAttest.onGenerateKey = {
      session.ownerID = self.ownerB
    }
    let transport = MetricTransportHTTPFake(outcomes: [])
    let client = try makeClient(
      session: session,
      appAttest: appAttest,
      stateStore: store,
      transport: transport,
      now: { now }
    )

    do {
      _ = try await client.prepare(
        ownerID: ownerA,
        body: exactMetricBody()
      )
      XCTFail("Expected the account switch to stop key rotation")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .accountChanged
      )
    }

    XCTAssertEqual(appAttest.generateKeyCallCount, 1)
    XCTAssertTrue(transport.requests.isEmpty)
    let retained = try XCTUnwrap(store.state(for: ownerA))
    XCTAssertEqual(retained.keyID, oldKeyID)
    XCTAssertEqual(retained.pendingRegistrationBody, expiredBody)
    XCTAssertNil(try store.state(for: ownerB))
  }

  func testPendingRegistrationPersistenceIsAccountIsolatedAndRejectsConflict()
    throws
  {
    let suiteName = "GameTimeTests.MetricAppAttest.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    defaults.removePersistentDomain(forName: suiteName)
    defer {
      defaults.removePersistentDomain(forName: suiteName)
    }

    let store = UserDefaultsMetricAppAttestStateStore(defaults: defaults)
    let keyA = MetricTransportAppAttestFake.defaultKeyID
    let keyB = Data("second-account-app-attest-key".utf8)
      .base64EncodedString()
    let bodyA = try registrationBody(
      keyID: keyA,
      attestation: Data("first exact attestation".utf8)
    )
    let conflictingBodyA = try registrationBody(
      keyID: keyA,
      attestation: Data("different attestation".utf8)
    )
    let bodyB = try registrationBody(
      keyID: keyB,
      attestation: Data("second account attestation".utf8)
    )
    let expiresAt = Date(timeIntervalSince1970: 1_785_888_600)

    try store.saveGeneratedKey(
      keyA,
      environment: .development,
      ownerID: ownerA
    )
    try store.saveGeneratedKey(
      keyB,
      environment: .development,
      ownerID: ownerB
    )
    try store.savePendingRegistrationBody(
      bodyA,
      expiresAt: expiresAt,
      keyID: keyA,
      ownerID: ownerA
    )
    try store.savePendingRegistrationBody(
      bodyA,
      expiresAt: expiresAt,
      keyID: keyA,
      ownerID: ownerA
    )

    XCTAssertEqual(
      try store.state(for: ownerA)?.pendingRegistrationBody,
      bodyA
    )
    XCTAssertNil(
      try store.state(for: ownerB)?.pendingRegistrationBody
    )

    XCTAssertThrowsError(
      try store.savePendingRegistrationBody(
        conflictingBodyA,
        expiresAt: expiresAt,
        keyID: keyA,
        ownerID: ownerA
      )
    )
    XCTAssertEqual(
      try store.state(for: ownerA)?.pendingRegistrationBody,
      bodyA
    )

    try store.savePendingRegistrationBody(
      bodyB,
      expiresAt: expiresAt,
      keyID: keyB,
      ownerID: ownerB
    )
    XCTAssertEqual(
      try store.state(for: ownerA)?.pendingRegistrationBody,
      bodyA
    )
    XCTAssertEqual(
      try store.state(for: ownerB)?.pendingRegistrationBody,
      bodyB
    )
  }

  func testSendPreservesExactBodyAndAssertionForFirstWriteAndReplay()
    async throws
  {
    let session = MetricTransportSessionFake(ownerID: ownerA)
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    stateStore.seedRegistered(
      ownerID: ownerA,
      keyID: appAttest.generatedKeyID
    )
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        try ingestResponse(statusCode: 201, replayed: false)
      ),
      .response(
        try ingestResponse(statusCode: 200, replayed: true)
      ),
    ])
    let client = try makeClient(
      session: session,
      appAttest: appAttest,
      stateStore: stateStore,
      transport: transport
    )
    let upload = signedUpload(
      keyID: appAttest.generatedKeyID,
      assertion: appAttest.assertion
    )

    let first = try await client.send(
      ownerID: ownerA,
      upload: upload
    )
    let replay = try await client.send(
      ownerID: ownerA,
      upload: upload
    )

    XCTAssertEqual(
      first,
      MetricUploadReceipt(
        batchID: batchID,
        replayed: false,
        observationCount: 1
      )
    )
    XCTAssertEqual(
      replay,
      MetricUploadReceipt(
        batchID: batchID,
        replayed: true,
        observationCount: 1
      )
    )
    XCTAssertEqual(transport.requests.count, 2)
    for request in transport.requests {
      XCTAssertEqual(request.httpBody, upload.body)
      XCTAssertEqual(
        request.value(
          forHTTPHeaderField: "x-gametime-key-id"
        ),
        appAttest.generatedKeyID
      )
      XCTAssertEqual(
        request.value(
          forHTTPHeaderField: "x-gametime-assertion"
        ),
        appAttest.assertion.base64EncodedString()
      )
      XCTAssertEqual(
        request.value(forHTTPHeaderField: "Authorization"),
        "Bearer metric-transport-access-token"
      )
      XCTAssertEqual(
        request.value(forHTTPHeaderField: "apikey"),
        "sb_publishable_metric_transport_test"
      )
      XCTAssertEqual(
        request.url?.path,
        "/functions/v1/ingest-metrics"
      )
    }
    XCTAssertEqual(
      transport.requests[0].httpBody,
      transport.requests[1].httpBody
    )
    XCTAssertEqual(
      transport.requests[0].value(
        forHTTPHeaderField: "x-gametime-assertion"
      ),
      transport.requests[1].value(
        forHTTPHeaderField: "x-gametime-assertion"
      )
    )
  }

  func testSendRefusesAMismatchedObservationCount()
    async throws
  {
    let session = MetricTransportSessionFake(ownerID: ownerA)
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    stateStore.seedRegistered(
      ownerID: ownerA,
      keyID: appAttest.generatedKeyID
    )
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        try ingestResponse(
          statusCode: 201,
          replayed: false,
          observationCount: 2
        )
      )
    ])
    let client = try makeClient(
      session: session,
      appAttest: appAttest,
      stateStore: stateStore,
      transport: transport
    )

    do {
      _ = try await client.send(
        ownerID: ownerA,
        upload: signedUpload(
          keyID: appAttest.generatedKeyID,
          assertion: appAttest.assertion
        )
      )
      XCTFail("Expected the mismatched response to fail")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .invalidServerResponse
      )
    }
  }

  func testAccountSwitchBeforeWorkFailsWithoutTouchingDeviceOrNetwork()
    async throws
  {
    let session = MetricTransportSessionFake(ownerID: ownerB)
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    let transport = MetricTransportHTTPFake(outcomes: [])
    let client = try makeClient(
      session: session,
      appAttest: appAttest,
      stateStore: stateStore,
      transport: transport
    )

    do {
      _ = try await client.prepare(
        ownerID: ownerA,
        body: exactMetricBody()
      )
      XCTFail("Expected the stale owner to fail closed")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .accountChanged
      )
    }

    XCTAssertEqual(appAttest.generateKeyCallCount, 0)
    XCTAssertTrue(appAttest.assertionHashes.isEmpty)
    XCTAssertTrue(stateStore.states.isEmpty)
    XCTAssertTrue(transport.requests.isEmpty)
  }

  func testAccountSwitchAfterAwaitedAssertionAndHTTPResponseFailsClosed()
    async throws
  {
    let assertionSession = MetricTransportSessionFake(ownerID: ownerA)
    let assertionAppAttest = MetricTransportAppAttestFake()
    let assertionStateStore = MetricTransportStateStoreFake()
    assertionStateStore.seedRegistered(
      ownerID: ownerA,
      keyID: assertionAppAttest.generatedKeyID
    )
    assertionAppAttest.onGenerateAssertion = {
      assertionSession.ownerID = self.ownerB
    }
    let assertionClient = try makeClient(
      session: assertionSession,
      appAttest: assertionAppAttest,
      stateStore: assertionStateStore,
      transport: MetricTransportHTTPFake(outcomes: [])
    )

    do {
      _ = try await assertionClient.prepare(
        ownerID: ownerA,
        body: exactMetricBody()
      )
      XCTFail("Expected an account switch after assertion generation")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .accountChanged
      )
    }

    let sendSession = MetricTransportSessionFake(ownerID: ownerA)
    let sendAppAttest = MetricTransportAppAttestFake()
    let sendStateStore = MetricTransportStateStoreFake()
    sendStateStore.seedRegistered(
      ownerID: ownerA,
      keyID: sendAppAttest.generatedKeyID
    )
    let sendTransport = MetricTransportHTTPFake(outcomes: [
      .response(
        try ingestResponse(statusCode: 201, replayed: false)
      )
    ])
    sendTransport.onSend = {
      sendSession.ownerID = self.ownerB
    }
    let sendClient = try makeClient(
      session: sendSession,
      appAttest: sendAppAttest,
      stateStore: sendStateStore,
      transport: sendTransport
    )

    do {
      _ = try await sendClient.send(
        ownerID: ownerA,
        upload: signedUpload(
          keyID: sendAppAttest.generatedKeyID,
          assertion: sendAppAttest.assertion
        )
      )
      XCTFail("Expected an account switch after the response")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .accountChanged
      )
    }
    XCTAssertEqual(sendTransport.requests.count, 1)
  }

  func testRotatedLocalKeyStillSendsTheOriginalSavedProof()
    async throws
  {
    let session = MetricTransportSessionFake(ownerID: ownerA)
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    let otherKeyID = Data("other-owner-key".utf8)
      .base64EncodedString()
    stateStore.seedRegistered(
      ownerID: ownerA,
      keyID: otherKeyID
    )
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        try ingestResponse(statusCode: 201, replayed: false)
      )
    ])
    let client = try makeClient(
      session: session,
      appAttest: appAttest,
      stateStore: stateStore,
      transport: transport
    )

    let receipt = try await client.send(
      ownerID: ownerA,
      upload: signedUpload(
        keyID: appAttest.generatedKeyID,
        assertion: appAttest.assertion
      )
    )

    XCTAssertEqual(receipt.batchID, batchID)
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(
      transport.requests.first?.value(
        forHTTPHeaderField: "x-gametime-key-id"
      ),
      appAttest.generatedKeyID
    )
  }

  func testLegacyDevelopmentUploadSendsOriginalProofWithoutResigning()
    async throws
  {
    let appAttest = MetricTransportAppAttestFake()
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        try ingestResponse(statusCode: 201, replayed: false)
      )
    ])
    let client = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: appAttest,
      stateStore: MetricTransportStateStoreFake(),
      transport: transport
    )
    let upload = signedUpload(
      keyID: appAttest.generatedKeyID,
      assertion: appAttest.assertion,
      environment: nil
    )

    let receipt = try await client.send(ownerID: ownerA, upload: upload)

    XCTAssertEqual(receipt.batchID, batchID)
    XCTAssertEqual(transport.requests.count, 1)
    XCTAssertEqual(transport.requests.first?.httpBody, upload.body)
    XCTAssertEqual(
      transport.requests.first?.value(
        forHTTPHeaderField: "x-gametime-key-id"
      ),
      upload.keyID
    )
    XCTAssertEqual(
      transport.requests.first?.value(
        forHTTPHeaderField: "x-gametime-assertion"
      ),
      upload.assertion?.base64EncodedString()
    )
    XCTAssertTrue(appAttest.assertionHashes.isEmpty)
  }

  func testRawResponseTransportErrorBodyAndSourceNeverSurface()
    async throws
  {
    let rawResponseSentinel = "RAW_SERVER_RESPONSE_SENTINEL_9371"
    let rawErrorSentinel = "RAW_TRANSPORT_ERROR_SENTINEL_6204"
    let sourceSentinel = "com.private.health.source.sentinel"
    let assertionSentinel = Data(
      "PRIVATE_ASSERTION_SENTINEL".utf8
    )
    let upload = signedUpload(
      keyID: MetricTransportAppAttestFake.defaultKeyID,
      assertion: assertionSentinel,
      sourceBundleID: sourceSentinel
    )
    let bodySentinel = try XCTUnwrap(
      String(data: upload.body, encoding: .utf8)
    )

    let responseError = try await surfacedError(
      transportOutcome: .response(
        MetricUploadHTTPResponse(
          statusCode: 500,
          body: Data(
            """
            \(rawResponseSentinel)
            \(sourceSentinel)
            \(bodySentinel)
            """.utf8
          )
        )
      ),
      upload: upload
    )
    assertCategorical(
      responseError,
      equals: .serviceUnavailable,
      excludes: [
        rawResponseSentinel,
        rawErrorSentinel,
        sourceSentinel,
        bodySentinel,
        assertionSentinel.base64EncodedString(),
      ]
    )

    let transportError = try await surfacedError(
      transportOutcome: .failure(
        MetricTransportRawError(
          description: """
            \(rawErrorSentinel)
            \(rawResponseSentinel)
            \(sourceSentinel)
            \(bodySentinel)
            """
        )
      ),
      upload: upload
    )
    assertCategorical(
      transportError,
      equals: .networkUnavailable,
      excludes: [
        rawResponseSentinel,
        rawErrorSentinel,
        sourceSentinel,
        bodySentinel,
        assertionSentinel.base64EncodedString(),
      ]
    )
  }

  func testReleaseRegistersAndPersistsAProductionAppAttestKey() async throws {
    let session = MetricTransportSessionFake(ownerID: ownerA)
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    let challenge = Data(repeating: 0x42, count: 32)
    let transport = MetricTransportHTTPFake(outcomes: [
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "challenge": challenge.base64EncodedString(),
            "expiresInSeconds": 600,
          ])
        )
      ),
      .response(
        MetricUploadHTTPResponse(
          statusCode: 200,
          body: try jsonData([
            "registered": true,
            "environment": "production",
          ])
        )
      ),
    ])
    let client = try makeClient(
      session: session,
      appAttest: appAttest,
      stateStore: stateStore,
      transport: transport,
      environment: .release
    )

    _ = try await client.prepare(
      ownerID: ownerA,
      body: exactMetricBody()
    )

    XCTAssertEqual(stateStore.states[ownerA]?.environment, .production)
    XCTAssertEqual(stateStore.states[ownerA]?.registered, true)
    XCTAssertEqual(
      appAttest.attestationHashes,
      [sha256(challenge)]
    )
  }

  func testRegistrationRefusesAnEnvironmentMismatchInEitherDirection()
    async throws
  {
    let cases: [(AppEnvironment, String)] = [
      (.staging, "production"),
      (.release, "development"),
    ]

    for (environment, responseEnvironment) in cases {
      let session = MetricTransportSessionFake(ownerID: ownerA)
      let appAttest = MetricTransportAppAttestFake()
      let stateStore = MetricTransportStateStoreFake()
      let challenge = Data(repeating: 0x24, count: 32)
      let transport = MetricTransportHTTPFake(outcomes: [
        .response(
          MetricUploadHTTPResponse(
            statusCode: 200,
            body: try jsonData([
              "challenge": challenge.base64EncodedString(),
              "expiresInSeconds": 600,
            ])
          )
        ),
        .response(
          MetricUploadHTTPResponse(
            statusCode: 200,
            body: try jsonData([
              "registered": true,
              "environment": responseEnvironment,
            ])
          )
        ),
      ])
      let client = try makeClient(
        session: session,
        appAttest: appAttest,
        stateStore: stateStore,
        transport: transport,
        environment: environment
      )

      do {
        _ = try await client.prepare(
          ownerID: ownerA,
          body: exactMetricBody()
        )
        XCTFail("Expected the App Attest environment mismatch to fail closed")
      } catch {
        XCTAssertEqual(
          error as? MetricUploadClientError,
          .invalidServerResponse
        )
      }
      XCTAssertEqual(stateStore.states[ownerA]?.registered, false)
      XCTAssertEqual(
        stateStore.states[ownerA]?.environment,
        environment == .release ? .production : .development
      )
    }
  }

  func testReleaseRotatesLegacyAndDevelopmentKeysBeforeSigning()
    async throws
  {
    let oldKeyID = Data("old-development-app-attest-key".utf8)
      .base64EncodedString()

    for priorEnvironment in [
      nil,
      AppAttestEnvironment.development,
    ] as [AppAttestEnvironment?] {
      let session = MetricTransportSessionFake(ownerID: ownerA)
      let appAttest = MetricTransportAppAttestFake()
      let stateStore = MetricTransportStateStoreFake()
      stateStore.seedRegistered(
        ownerID: ownerA,
        keyID: oldKeyID,
        environment: priorEnvironment
      )
      let challenge = Data(repeating: 0x33, count: 32)
      let transport = MetricTransportHTTPFake(outcomes: [
        .response(
          MetricUploadHTTPResponse(
            statusCode: 200,
            body: try jsonData([
              "challenge": challenge.base64EncodedString(),
              "expiresInSeconds": 600,
            ])
          )
        ),
        .response(
          MetricUploadHTTPResponse(
            statusCode: 200,
            body: try jsonData([
              "registered": true,
              "environment": "production",
            ])
          )
        ),
      ])
      let client = try makeClient(
        session: session,
        appAttest: appAttest,
        stateStore: stateStore,
        transport: transport,
        environment: .release
      )

      _ = try await client.prepare(
        ownerID: ownerA,
        body: exactMetricBody()
      )

      XCTAssertEqual(appAttest.generateKeyCallCount, 1)
      XCTAssertEqual(
        stateStore.states[ownerA],
        MetricAppAttestState(
          ownerID: ownerA,
          keyID: appAttest.generatedKeyID,
          registered: true,
          environment: .production
        )
      )
      XCTAssertEqual(transport.requests.count, 2)
    }
  }

  func testReleaseMigratesTheActualLegacyUserDefaultsRecord()
    async throws
  {
    let suiteName = "GameTimeMetricLegacy-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    addTeardownBlock {
      defaults.removePersistentDomain(forName: suiteName)
    }
    let oldKeyID = Data("legacy-app-attest-key".utf8)
      .base64EncodedString()
    let legacyData = try JSONSerialization.data(
      withJSONObject: [
        "ownerID": ownerA.uuidString,
        "keyID": oldKeyID,
        "registered": true,
      ],
      options: [.sortedKeys]
    )
    defaults.set(
      legacyData,
      forKey:
        "GameTime.metricAppAttest.v1."
        + ownerA.uuidString.lowercased()
    )
    let store = UserDefaultsMetricAppAttestStateStore(defaults: defaults)
    XCTAssertNil(try store.state(for: ownerA)?.environment)

    let challenge = Data(repeating: 0x45, count: 32)
    let appAttest = MetricTransportAppAttestFake()
    let client = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: appAttest,
      stateStore: store,
      transport: MetricTransportHTTPFake(outcomes: [
        .response(
          MetricUploadHTTPResponse(
            statusCode: 200,
            body: try jsonData([
              "challenge": challenge.base64EncodedString(),
              "expiresInSeconds": 600,
            ])
          )
        ),
        .response(
          MetricUploadHTTPResponse(
            statusCode: 200,
            body: try jsonData([
              "registered": true,
              "environment": "production",
            ])
          )
        ),
      ]),
      environment: .release
    )

    _ = try await client.prepare(
      ownerID: ownerA,
      body: exactMetricBody()
    )

    let migrated = try XCTUnwrap(try store.state(for: ownerA))
    XCTAssertEqual(migrated.keyID, appAttest.generatedKeyID)
    XCTAssertEqual(migrated.environment, .production)
    XCTAssertTrue(migrated.registered)
  }

  func testReleaseRejectsADevelopmentSignedQueuedUpload()
    async throws
  {
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    stateStore.seedRegistered(
      ownerID: ownerA,
      keyID: appAttest.generatedKeyID,
      environment: .development
    )
    let transport = MetricTransportHTTPFake(outcomes: [])
    let client = try makeClient(
      session: MetricTransportSessionFake(ownerID: ownerA),
      appAttest: appAttest,
      stateStore: stateStore,
      transport: transport,
      environment: .release
    )

    do {
      _ = try await client.send(
        ownerID: ownerA,
        upload: signedUpload(
          keyID: appAttest.generatedKeyID,
          assertion: appAttest.assertion,
          environment: .development
        )
      )
      XCTFail("Expected a development key to be unusable in Release")
    } catch {
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .savedEvidenceFromDifferentEnvironment
      )
    }
    XCTAssertTrue(transport.requests.isEmpty)
  }

  func testDebugConstructionFailsClosedWithoutAppAttestUpload() {
    XCTAssertThrowsError(
      try SupabaseMetricUploadClient(
        configuration: configuration(.debug),
        sessionProvider: MetricTransportSessionFake(
          ownerID: ownerA
        ),
        appAttest: MetricTransportAppAttestFake(),
        stateStore: MetricTransportStateStoreFake(),
        transport: MetricTransportHTTPFake(outcomes: [])
      )
    ) { error in
      XCTAssertEqual(
        error as? MetricUploadClientError,
        .stagingOnly
      )
      XCTAssertEqual(
        error.localizedDescription,
        MetricUploadClientError.stagingOnly.errorDescription
      )
    }
  }

  private func makeClient(
    session: MetricTransportSessionFake,
    appAttest: MetricTransportAppAttestFake,
    stateStore: any MetricAppAttestStateStoring,
    transport: MetricTransportHTTPFake,
    environment: AppEnvironment = .staging,
    now: @escaping () -> Date = Date.init
  ) throws -> SupabaseMetricUploadClient {
    try SupabaseMetricUploadClient(
      configuration: configuration(environment),
      sessionProvider: session,
      appAttest: appAttest,
      stateStore: stateStore,
      transport: transport,
      now: now
    )
  }

  private func configuration(
    _ environment: AppEnvironment
  ) -> AppConfiguration {
    AppConfiguration(
      environment: environment,
      supabaseURL: URL(
        string: "https://metrictransport.supabase.co"
      )!,
      supabasePublishableKey:
        "sb_publishable_metric_transport_test",
      contestMutationsEnabled: false
    )
  }

  private func exactMetricBody(
    sourceBundleID: String = "com.private.health.source.sentinel"
  ) -> Data {
    Data(
      """
      {
        "observations": [{
          "sourceBundleId": "\(sourceBundleID)",
          "sampleCount": 7,
          "value": 9371,
          "provenance": "device",
          "bucketStart": "2026-08-03T00:00:00.000Z",
          "metric": "steps"
        }],
        "observedAt": "2026-08-03T01:02:03.456Z",
        "clientBatchId": "\(batchID.uuidString.lowercased())",
        "contestId": "\(contestID.uuidString.lowercased())"
      }
      """.utf8
    )
  }

  private func signedUpload(
    keyID: String,
    assertion: Data,
    sourceBundleID: String = "com.private.health.source.sentinel",
    environment: AppAttestEnvironment? = .development
  ) -> PendingMetricUpload {
    PendingMetricUpload(
      clientBatchId: batchID,
      contestId: contestID,
      body: exactMetricBody(sourceBundleID: sourceBundleID),
      keyID: keyID,
      assertion: assertion,
      attestEnvironment: environment
    )
  }

  private func ingestResponse(
    statusCode: Int,
    replayed: Bool,
    observationCount: Int = 1
  ) throws -> MetricUploadHTTPResponse {
    MetricUploadHTTPResponse(
      statusCode: statusCode,
      body: try jsonData([
        "batchId": batchID.uuidString.lowercased(),
        "observationCount": observationCount,
        "replayed": replayed,
      ])
    )
  }

  private func jsonData(
    _ object: [String: Any]
  ) throws -> Data {
    try JSONSerialization.data(
      withJSONObject: object,
      options: [.sortedKeys]
    )
  }

  private func registrationBody(
    keyID: String,
    attestation: Data
  ) throws -> Data {
    try jsonData([
      "keyId": keyID,
      "attestation": attestation.base64EncodedString(),
    ])
  }

  private func sha256(_ data: Data) -> Data {
    Data(SHA256.hash(data: data))
  }

  private func surfacedError(
    transportOutcome: MetricTransportOutcome,
    upload: PendingMetricUpload
  ) async throws -> MetricUploadClientError {
    let session = MetricTransportSessionFake(ownerID: ownerA)
    let appAttest = MetricTransportAppAttestFake()
    let stateStore = MetricTransportStateStoreFake()
    stateStore.seedRegistered(
      ownerID: ownerA,
      keyID: appAttest.generatedKeyID
    )
    let client = try makeClient(
      session: session,
      appAttest: appAttest,
      stateStore: stateStore,
      transport: MetricTransportHTTPFake(
        outcomes: [transportOutcome]
      )
    )

    do {
      _ = try await client.send(
        ownerID: ownerA,
        upload: upload
      )
      XCTFail("Expected a categorical transport error")
      return .invalidServerResponse
    } catch let error as MetricUploadClientError {
      return error
    }
  }

  private func assertCategorical(
    _ error: MetricUploadClientError,
    equals expected: MetricUploadClientError,
    excludes sentinels: [String],
    file: StaticString = #filePath,
    line: UInt = #line
  ) {
    XCTAssertEqual(error, expected, file: file, line: line)
    let description = error.localizedDescription
    XCTAssertEqual(
      description,
      expected.errorDescription,
      file: file,
      line: line
    )
    for sentinel in sentinels {
      XCTAssertFalse(
        description.contains(sentinel),
        "Categorical error exposed a raw sentinel",
        file: file,
        line: line
      )
    }
  }
}

@MainActor
private final class MetricTransportSessionFake:
  MetricUploadSessionProviding
{
  var ownerID: UUID?
  var accessToken = "metric-transport-access-token"
  /// Set to simulate a refresh that could not be completed, which is not the
  /// same outcome as nobody being signed in.
  var refreshFailure: MetricUploadClientError?

  private(set) var validSessionCallCount = 0

  init(ownerID: UUID?) {
    self.ownerID = ownerID
  }

  func validSession() async throws -> MetricUploadSession? {
    validSessionCallCount += 1
    if let refreshFailure { throw refreshFailure }
    guard let ownerID else { return nil }
    return MetricUploadSession(
      ownerID: ownerID,
      accessToken: accessToken
    )
  }
}

@MainActor
private final class MetricTransportAppAttestFake:
  MetricAppAttestProviding
{
  static let defaultKeyID = Data("metric-app-attest-key".utf8)
    .base64EncodedString()

  var isSupported = true
  var generatedKeyID = MetricTransportAppAttestFake.defaultKeyID
  var attestation = Data("metric-attestation".utf8)
  var assertion = Data("metric-assertion".utf8)
  var onGenerateKey: (() -> Void)?
  var onGenerateAssertion: (() -> Void)?

  private(set) var generateKeyCallCount = 0
  private(set) var attestationHashes: [Data] = []
  private(set) var assertionHashes: [Data] = []

  func generateKey() async throws -> String {
    generateKeyCallCount += 1
    onGenerateKey?()
    return generatedKeyID
  }

  func attestKey(
    _ keyID: String,
    clientDataHash: Data
  ) async throws -> Data {
    XCTAssertEqual(keyID, generatedKeyID)
    attestationHashes.append(clientDataHash)
    return attestation
  }

  func generateAssertion(
    _ keyID: String,
    clientDataHash: Data
  ) async throws -> Data {
    XCTAssertEqual(keyID, generatedKeyID)
    assertionHashes.append(clientDataHash)
    onGenerateAssertion?()
    return assertion
  }
}

@MainActor
private final class MetricTransportStateStoreFake:
  MetricAppAttestStateStoring
{
  private(set) var states: [UUID: MetricAppAttestState] = [:]
  private(set) var savedOwners: [UUID] = []
  private(set) var registeredOwners: [UUID] = []

  func state(
    for ownerID: UUID
  ) throws -> MetricAppAttestState? {
    states[ownerID]
  }

  func saveGeneratedKey(
    _ keyID: String,
    environment: AppAttestEnvironment,
    ownerID: UUID
  ) throws {
    savedOwners.append(ownerID)
    states[ownerID] = MetricAppAttestState(
      ownerID: ownerID,
      keyID: keyID,
      registered: false,
      environment: environment
    )
  }

  func savePendingRegistrationBody(
    _ body: Data,
    expiresAt: Date,
    keyID: String,
    ownerID: UUID
  ) throws {
    guard
      let existing = states[ownerID],
      existing.keyID == keyID,
      existing.registered == false
    else {
      throw MetricTransportStateError.keyMismatch
    }
    if let pending = existing.pendingRegistrationBody {
      guard
        pending == body,
        existing.pendingRegistrationExpiresAt == expiresAt
      else {
        throw MetricTransportStateError.registrationConflict
      }
      return
    }
    states[ownerID] = MetricAppAttestState(
      ownerID: ownerID,
      keyID: keyID,
      registered: false,
      environment: existing.environment,
      pendingRegistrationBody: body,
      pendingRegistrationExpiresAt: expiresAt
    )
  }

  func replaceKey(
    _ newKeyID: String,
    replacing oldKeyID: String,
    environment: AppAttestEnvironment,
    ownerID: UUID
  ) throws {
    guard
      let existing = states[ownerID],
      existing.keyID == oldKeyID,
      newKeyID != oldKeyID
    else {
      throw MetricTransportStateError.keyMismatch
    }
    states[ownerID] = MetricAppAttestState(
      ownerID: ownerID,
      keyID: newKeyID,
      registered: false,
      environment: environment
    )
  }

  func markRegistered(
    keyID: String,
    environment: AppAttestEnvironment,
    ownerID: UUID
  ) throws {
    guard
      states[ownerID]?.keyID == keyID,
      states[ownerID]?.environment == environment
    else {
      throw MetricTransportStateError.keyMismatch
    }
    registeredOwners.append(ownerID)
    states[ownerID] = MetricAppAttestState(
      ownerID: ownerID,
      keyID: keyID,
      registered: true,
      environment: environment
    )
  }

  func invalidateCurrentKey(
    rejectedKeyID: String,
    ownerID: UUID
  ) throws {
    guard states[ownerID]?.keyID == rejectedKeyID else {
      return
    }
    states[ownerID] = nil
  }

  func seedRegistered(
    ownerID: UUID,
    keyID: String,
    environment: AppAttestEnvironment? = .development
  ) {
    states[ownerID] = MetricAppAttestState(
      ownerID: ownerID,
      keyID: keyID,
      registered: true,
      environment: environment
    )
  }
}

@MainActor
private final class MetricTransportHTTPFake: MetricUploadHTTPTransport {
  private var outcomes: [MetricTransportOutcome]
  var onSend: (() -> Void)?
  private(set) var requests: [URLRequest] = []

  init(outcomes: [MetricTransportOutcome]) {
    self.outcomes = outcomes
  }

  func send(
    _ request: URLRequest
  ) async throws -> MetricUploadHTTPResponse {
    requests.append(request)
    onSend?()
    guard !outcomes.isEmpty else {
      throw MetricTransportRawError(
        description: "No deterministic response was configured."
      )
    }
    switch outcomes.removeFirst() {
    case .response(let response):
      return response
    case .failure(let error):
      throw error
    }
  }
}

private enum MetricTransportOutcome {
  case response(MetricUploadHTTPResponse)
  case failure(any Error)
}

private struct MetricTransportRawError: LocalizedError {
  let description: String

  var errorDescription: String? { description }
}

private enum MetricTransportStateError: Error {
  case keyMismatch
  case registrationConflict
}

extension Data {
  fileprivate func containsSubdata(_ other: Data) -> Bool {
    range(of: other) != nil
  }
}
