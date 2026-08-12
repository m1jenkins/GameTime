import CryptoKit
import DeviceCheck
import Foundation
import GameTimeCore
import Supabase

struct MetricSignedMaterial: Equatable, Sendable {
  let keyID: String
  let assertion: Data
  let environment: AppAttestEnvironment

  init(
    keyID: String,
    assertion: Data,
    environment: AppAttestEnvironment = .development
  ) {
    self.keyID = keyID
    self.assertion = assertion
    self.environment = environment
  }
}

@MainActor
protocol AppAttestedBodySigning: AnyObject {
  func sign(ownerID: UUID, body: Data) async throws -> MetricSignedMaterial
  func invalidateRejectedKey(ownerID: UUID, keyID: String) throws
}

struct MetricUploadReceipt: Equatable, Sendable {
  let batchID: UUID
  let replayed: Bool
  let observationCount: Int
}

@MainActor
protocol MetricUploadClient: AnyObject {
  var expectedAttestationEnvironment: AppAttestEnvironment? { get }

  func prepare(
    ownerID: UUID,
    body: Data
  ) async throws -> MetricSignedMaterial

  func send(
    ownerID: UUID,
    upload: PendingMetricUpload
  ) async throws -> MetricUploadReceipt
}

extension MetricUploadClient {
  var expectedAttestationEnvironment: AppAttestEnvironment? { nil }
}

enum MetricUploadClientError: LocalizedError, Equatable, Sendable {
  case stagingOnly
  case authenticationRequired
  case tokenRefusedByService
  case sessionRefreshFailed
  case accountChanged
  case operationInProgress
  case appAttestUnsupported
  case keyStateUnavailable
  case savedSignatureNeedsRefresh
  case savedEvidenceFromDifferentEnvironment
  case invalidMetricBody
  case deviceRegistrationUnavailable
  case attestationRejected
  case accountNotActive
  case registrationRefused
  case assertionUnavailable
  case unsignedUpload
  case networkUnavailable
  case serviceUnavailable
  case uploadVerificationFailed
  case uploadConflict
  case uploadRejected
  case invalidServerResponse

  var errorDescription: String? {
    switch self {
    case .stagingOnly:
      "Step syncing isn’t available yet."
    case .authenticationRequired:
      "Sign in again to sync your steps."
    case .tokenRefusedByService:
      "We couldn’t verify this account. Contact support before trying again."
    case .sessionRefreshFailed:
      "We couldn’t refresh your sign-in. Check your connection and try again."
    case .accountChanged:
      "You signed in with a different account. Sync your steps again."
    case .operationInProgress:
      "Already syncing — hang tight."
    case .appAttestUnsupported:
      "This device can’t prove your steps came from it."
    case .keyStateUnavailable:
      "We couldn’t read this device’s setup."
    case .savedSignatureNeedsRefresh:
      "GameTime needs to refresh the secure signature on saved steps."
    case .savedEvidenceFromDifferentEnvironment:
      "Steps saved on this phone couldn’t be confirmed. Sync your steps again."
    case .invalidMetricBody:
      "Something is wrong with the steps waiting to send."
    case .deviceRegistrationUnavailable:
      "We couldn’t set this device up for step syncing."
    case .attestationRejected:
      "We couldn’t verify this device. This isn’t a sign-in problem."
    case .accountNotActive:
      "This account isn’t active."
    case .registrationRefused:
      "GameTime wouldn’t register this device."
    case .assertionUnavailable:
      "We couldn’t verify those steps."
    case .unsignedUpload:
      "The steps waiting to send haven’t been verified yet."
    case .networkUnavailable:
      "We couldn’t reach GameTime. Check your connection and try again."
    case .serviceUnavailable:
      "GameTime is unavailable right now. Try again in a moment."
    case .uploadVerificationFailed:
      "GameTime couldn’t verify those steps."
    case .uploadConflict:
      "Those steps clash with ones we already have."
    case .uploadRejected:
      "GameTime wouldn’t accept those steps."
    case .invalidServerResponse:
      "Something came back wrong from GameTime. Try again."
    }
  }
}

/// Which check refused a 401 or 403 from an attested endpoint.
///
/// The functions answer with `{ error, message }` and a fixed message per
/// check; the detail behind it stays in the function log
/// (`supabase/functions/_shared/http.ts`). Three quite different failures
/// arrive as 401 — a rejected token, a rejected attestation, and a rejected
/// receipt — so reading the message is the only thing that keeps a device that
/// cannot attest from being reported as an account that must sign in again.
enum AttestedEndpointRefusal: Equatable, Sendable {
  case authentication
  case attestation
  case accountNotActive
  case unspecified

  private static let maximumBodyBytes = 64 * 1024

  /// Messages the deployed handlers send. Kept as literals rather than matched
  /// loosely: an unrecognised message stays `.unspecified` instead of being
  /// filed under whichever case its wording happens to resemble.
  private static let known: [String: AttestedEndpointRefusal] = [
    // attest-device and activity-diagnostic, on any unacceptable token.
    "sign in again": .authentication,
    // attest-device registration.
    "the attestation could not be verified": .attestation,
    "the receipt could not be verified": .attestation,
    // activity-diagnostic and personal-sync-coverage.
    "the assertion could not be verified": .attestation,
    // assert_active_actor, which answers 403 rather than 401.
    "this account is not active": .accountNotActive,
  ]

  static func decode(_ body: Data) -> AttestedEndpointRefusal {
    guard
      body.count <= maximumBodyBytes,
      let document = try? JSONDecoder().decode(
        FailureDocument.self,
        from: body
      )
    else {
      return .unspecified
    }
    return known[document.message] ?? .unspecified
  }

  private struct FailureDocument: Decodable {
    let message: String
  }
}

@MainActor
final class DisabledMetricUploadClient: MetricUploadClient {
  func prepare(
    ownerID: UUID,
    body: Data
  ) async throws -> MetricSignedMaterial {
    _ = ownerID
    _ = body
    throw MetricUploadClientError.stagingOnly
  }

  func send(
    ownerID: UUID,
    upload: PendingMetricUpload
  ) async throws -> MetricUploadReceipt {
    _ = ownerID
    _ = upload
    throw MetricUploadClientError.stagingOnly
  }
}

struct MetricUploadSession: Equatable, Sendable {
  let ownerID: UUID
  let accessToken: String
}

@MainActor
protocol MetricUploadSessionProviding: AnyObject {
  /// A session whose access token is valid *now*, refreshing a stored token
  /// that has already expired.
  ///
  /// `SupabaseClient.auth.currentSession` is the stored session, and the SDK
  /// documents it as possibly expired. Every request in this file is built by
  /// hand rather than made through the SDK, so nothing else refreshes the
  /// token on the way out: reading the stored one sends an expired JWT to an
  /// Edge Function, which answers 401, which the app then reported as "sign in
  /// again" to somebody who was signed in the whole time.
  ///
  /// Returns nil when signing in again is the only way forward. A refresh that
  /// merely could not be completed throws instead, because that one is worth
  /// retrying.
  func validSession() async throws -> MetricUploadSession?
}

@MainActor
protocol MetricAppAttestProviding: AnyObject {
  var isSupported: Bool { get }

  func generateKey() async throws -> String
  func attestKey(
    _ keyID: String,
    clientDataHash: Data
  ) async throws -> Data
  func generateAssertion(
    _ keyID: String,
    clientDataHash: Data
  ) async throws -> Data
}

struct MetricUploadHTTPResponse: Equatable, Sendable {
  let statusCode: Int
  let body: Data
}

@MainActor
protocol MetricUploadHTTPTransport: AnyObject {
  func send(_ request: URLRequest) async throws -> MetricUploadHTTPResponse
}

struct MetricAppAttestState: Codable, Equatable, Sendable {
  let ownerID: UUID
  let keyID: String
  let registered: Bool
  /// Nil only for state written by builds that predate environment binding.
  let environment: AppAttestEnvironment?
  let pendingRegistrationBody: Data?
  let pendingRegistrationExpiresAt: Date?

  init(
    ownerID: UUID,
    keyID: String,
    registered: Bool,
    environment: AppAttestEnvironment? = nil,
    pendingRegistrationBody: Data? = nil,
    pendingRegistrationExpiresAt: Date? = nil
  ) {
    self.ownerID = ownerID
    self.keyID = keyID
    self.registered = registered
    self.environment = environment
    self.pendingRegistrationBody = pendingRegistrationBody
    self.pendingRegistrationExpiresAt = pendingRegistrationExpiresAt
  }
}

@MainActor
protocol MetricAppAttestStateStoring: AnyObject {
  func state(for ownerID: UUID) throws -> MetricAppAttestState?
  func saveGeneratedKey(
    _ keyID: String,
    environment: AppAttestEnvironment,
    ownerID: UUID
  ) throws
  func savePendingRegistrationBody(
    _ body: Data,
    expiresAt: Date,
    keyID: String,
    ownerID: UUID
  ) throws
  func replaceKey(
    _ newKeyID: String,
    replacing oldKeyID: String,
    environment: AppAttestEnvironment,
    ownerID: UUID
  ) throws
  func markRegistered(
    keyID: String,
    environment: AppAttestEnvironment,
    ownerID: UUID
  ) throws
  func invalidateCurrentKey(
    rejectedKeyID: String,
    ownerID: UUID
  ) throws
}

@MainActor
final class SupabaseMetricUploadClient: MetricUploadClient,
  AppAttestedBodySigning
{
  private static let maximumResponseBytes = 64 * 1024

  private let sessionProvider: any MetricUploadSessionProviding
  private let appAttest: any MetricAppAttestProviding
  private let stateStore: any MetricAppAttestStateStoring
  private let transport: any MetricUploadHTTPTransport
  private let supabaseURL: URL
  private let publishableKey: String
  private let expectedEnvironment: AppAttestEnvironment
  private let now: () -> Date
  private var ownersBeingPrepared: Set<UUID> = []

  var expectedAttestationEnvironment: AppAttestEnvironment? {
    expectedEnvironment
  }

  convenience init(
    client: SupabaseClient,
    configuration: AppConfiguration
  ) throws {
    try self.init(
      configuration: configuration,
      sessionProvider: SupabaseMetricUploadSessionProvider(client: client),
      appAttest: DeviceMetricAppAttestProvider(),
      stateStore: UserDefaultsMetricAppAttestStateStore(),
      transport: URLSessionMetricUploadHTTPTransport()
    )
  }

  init(
    configuration: AppConfiguration,
    sessionProvider: any MetricUploadSessionProviding,
    appAttest: any MetricAppAttestProviding,
    stateStore: any MetricAppAttestStateStoring,
    transport: any MetricUploadHTTPTransport,
    now: @escaping () -> Date = Date.init
  ) throws {
    guard
      configuration.attestedUploadEnabled,
      let expectedEnvironment = configuration.expectedAppAttestEnvironment
    else {
      throw MetricUploadClientError.stagingOnly
    }
    self.sessionProvider = sessionProvider
    self.appAttest = appAttest
    self.stateStore = stateStore
    self.transport = transport
    self.now = now
    supabaseURL = configuration.supabaseURL
    publishableKey = configuration.supabasePublishableKey
    self.expectedEnvironment = expectedEnvironment
  }

  func prepare(
    ownerID: UUID,
    body: Data
  ) async throws -> MetricSignedMaterial {
    _ = try metricIdentity(in: body)
    return try await sign(ownerID: ownerID, body: body)
  }

  func sign(
    ownerID: UUID,
    body: Data
  ) async throws -> MetricSignedMaterial {
    guard !body.isEmpty, body.count <= 64 * 1024 else {
      throw MetricUploadClientError.invalidMetricBody
    }
    guard ownersBeingPrepared.insert(ownerID).inserted else {
      throw MetricUploadClientError.operationInProgress
    }
    defer { ownersBeingPrepared.remove(ownerID) }

    try await requireValidSession(ownerID: ownerID)
    guard appAttest.isSupported else {
      throw MetricUploadClientError.appAttestUnsupported
    }

    let state = try await loadOrGenerateState(ownerID: ownerID)
    let keyID = try await registerIfNeeded(
      state: state,
      ownerID: ownerID
    )

    try await requireValidSession(ownerID: ownerID)
    let assertion: Data
    do {
      assertion = try await appAttest.generateAssertion(
        keyID,
        clientDataHash: Self.sha256(body)
      )
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw MetricUploadClientError.assertionUnavailable
    }
    try await requireValidSession(ownerID: ownerID)
    guard !assertion.isEmpty else {
      throw MetricUploadClientError.assertionUnavailable
    }

    return MetricSignedMaterial(
      keyID: keyID,
      assertion: assertion,
      environment: expectedEnvironment
    )
  }

  func invalidateRejectedKey(
    ownerID: UUID,
    keyID: String
  ) throws {
    do {
      try stateStore.invalidateCurrentKey(
        rejectedKeyID: keyID,
        ownerID: ownerID
      )
    } catch {
      throw MetricUploadClientError.keyStateUnavailable
    }
  }

  func send(
    ownerID: UUID,
    upload: PendingMetricUpload
  ) async throws -> MetricUploadReceipt {
    let identity = try metricIdentity(in: upload.body)
    guard
      identity.clientBatchID == upload.clientBatchId,
      identity.contestID == upload.contestId
    else {
      throw MetricUploadClientError.invalidMetricBody
    }
    guard
      let keyID = upload.keyID,
      !keyID.isEmpty,
      let assertion = upload.assertion,
      !assertion.isEmpty
    else {
      throw MetricUploadClientError.unsignedUpload
    }
    let savedEnvironmentMatches =
      upload.attestEnvironment == expectedEnvironment
      || (
        upload.attestEnvironment == nil
          && expectedEnvironment == .development
      )
    guard savedEnvironmentMatches else {
      throw MetricUploadClientError
        .savedEvidenceFromDifferentEnvironment
    }

    let session = try await requireValidSession(ownerID: ownerID)
    guard Self.isValidKeyID(keyID) else {
      throw MetricUploadClientError.invalidMetricBody
    }
    // The server is authoritative for a saved key's owner, environment, and
    // assertion counter. A rotated local key must not cause this build to
    // re-sign bytes that an older build wrote. Legacy nil metadata is accepted
    // only by Development, where the original key and assertion are still sent
    // exactly as saved. Production refuses that unknown provenance above.
    var request = try makeRequest(
      endpoint: .ingestMetrics,
      accessToken: session.accessToken,
      body: upload.body
    )
    request.setValue(
      keyID,
      forHTTPHeaderField: "x-gametime-key-id"
    )
    request.setValue(
      assertion.base64EncodedString(),
      forHTTPHeaderField: "x-gametime-assertion"
    )

    let response = try await response(for: request)
    try await requireValidSession(ownerID: ownerID)
    do {
      try requireMetricSuccess(response)
    } catch MetricUploadClientError.attestationRejected {
      // Keep the rejected request immutable. Clearing only the matching
      // current key lets a later, freshly built request register a new key,
      // while a delayed refusal for an older queued key cannot erase a newer
      // registration.
      try invalidateRejectedKey(ownerID: ownerID, keyID: keyID)
      throw MetricUploadClientError.attestationRejected
    }

    guard
      response.body.count <= Self.maximumResponseBytes,
      let document = try? JSONDecoder().decode(
        MetricIngestDocument.self,
        from: response.body
      ),
      document.batchID == upload.clientBatchId,
      document.observationCount == identity.observationCount,
      (response.statusCode == 201 && document.replayed == false)
        || (response.statusCode == 200 && document.replayed == true)
    else {
      throw MetricUploadClientError.invalidServerResponse
    }

    return MetricUploadReceipt(
      batchID: document.batchID,
      replayed: document.replayed,
      observationCount: document.observationCount
    )
  }

  private func loadOrGenerateState(
    ownerID: UUID
  ) async throws -> MetricAppAttestState {
    try await requireValidSession(ownerID: ownerID)
    let existing: MetricAppAttestState?
    do {
      existing = try stateStore.state(for: ownerID)
    } catch {
      throw MetricUploadClientError.keyStateUnavailable
    }
    if let existing {
      guard existing.environment == expectedEnvironment else {
        return try await replaceKey(
          state: existing,
          ownerID: ownerID
        )
      }
      return existing
    }

    try await requireValidSession(ownerID: ownerID)
    let keyID: String
    do {
      keyID = try await appAttest.generateKey()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw MetricUploadClientError.keyStateUnavailable
    }
    try await requireValidSession(ownerID: ownerID)
    guard Self.isValidKeyID(keyID) else {
      throw MetricUploadClientError.keyStateUnavailable
    }
    do {
      try stateStore.saveGeneratedKey(
        keyID,
        environment: expectedEnvironment,
        ownerID: ownerID
      )
    } catch {
      throw MetricUploadClientError.keyStateUnavailable
    }
    return MetricAppAttestState(
      ownerID: ownerID,
      keyID: keyID,
      registered: false,
      environment: expectedEnvironment
    )
  }

  private func registerIfNeeded(
    state: MetricAppAttestState,
    ownerID: UUID
  ) async throws -> String {
    guard
      state.ownerID == ownerID,
      state.environment == expectedEnvironment,
      Self.isValidKeyID(state.keyID)
    else {
      throw MetricUploadClientError.keyStateUnavailable
    }
    guard state.registered == false else {
      return state.keyID
    }

    let registrationBody: Data
    if let pendingRegistrationBody = state.pendingRegistrationBody {
      guard
        let expiresAt = state.pendingRegistrationExpiresAt,
        expiresAt.timeIntervalSinceReferenceDate.isFinite
      else {
        throw MetricUploadClientError.keyStateUnavailable
      }
      if now() >= expiresAt {
        let replacement = try await replaceExpiredRegistrationKey(
          state: state,
          ownerID: ownerID
        )
        return try await registerIfNeeded(
          state: replacement,
          ownerID: ownerID
        )
      }
      guard
        MetricAppAttestRegistrationBody.isValid(
          pendingRegistrationBody,
          keyID: state.keyID
        )
      else {
        throw MetricUploadClientError.keyStateUnavailable
      }
      registrationBody = pendingRegistrationBody
    } else {
      guard state.pendingRegistrationExpiresAt == nil else {
        throw MetricUploadClientError.keyStateUnavailable
      }
      let challengeSession = try await requireValidSession(ownerID: ownerID)
      let challengeRequest = try makeRequest(
        endpoint: .attestChallenge,
        accessToken: challengeSession.accessToken
      )
      let challengeResponse = try await response(for: challengeRequest)
      let challengeReceivedAt = now()
      try await requireValidSession(ownerID: ownerID)
      try requireRegistrationSuccess(
        challengeResponse,
        isChallenge: true
      )
      guard
        challengeResponse.body.count <= Self.maximumResponseBytes,
        let document = try? JSONDecoder().decode(
          AttestChallengeDocument.self,
          from: challengeResponse.body
        ),
        document.expiresInSeconds > 0,
        let challenge = Data(base64Encoded: document.challenge),
        challenge.count == 32
      else {
        throw MetricUploadClientError.invalidServerResponse
      }
      let replayLifetime = min(
        TimeInterval(document.expiresInSeconds),
        MetricAppAttestRegistrationBody.maximumReplayLifetime
      )
      let registrationExpiresAt = challengeReceivedAt.addingTimeInterval(
        replayLifetime
      )
      guard registrationExpiresAt.timeIntervalSinceReferenceDate.isFinite else {
        throw MetricUploadClientError.invalidServerResponse
      }

      try await requireValidSession(ownerID: ownerID)
      let attestation: Data
      do {
        attestation = try await appAttest.attestKey(
          state.keyID,
          clientDataHash: Self.sha256(challenge)
        )
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        throw MetricUploadClientError.deviceRegistrationUnavailable
      }
      try await requireValidSession(ownerID: ownerID)
      guard !attestation.isEmpty else {
        throw MetricUploadClientError.deviceRegistrationUnavailable
      }

      do {
        registrationBody = try MetricAppAttestRegistrationBody.encode(
          keyID: state.keyID,
          attestation: attestation
        )
        try stateStore.savePendingRegistrationBody(
          registrationBody,
          expiresAt: registrationExpiresAt,
          keyID: state.keyID,
          ownerID: ownerID
        )
      } catch {
        throw MetricUploadClientError.keyStateUnavailable
      }
    }

    let registrationSession = try await requireValidSession(ownerID: ownerID)
    let registrationRequest = try makeRequest(
      endpoint: .attestDevice,
      accessToken: registrationSession.accessToken,
      body: registrationBody
    )
    let registrationResponse = try await response(for: registrationRequest)
    try await requireValidSession(ownerID: ownerID)
    try requireRegistrationSuccess(
      registrationResponse,
      isChallenge: false
    )
    guard
      registrationResponse.body.count <= Self.maximumResponseBytes,
      let document = try? JSONDecoder().decode(
        AttestRegistrationResponse.self,
        from: registrationResponse.body
      ),
      document.registered,
      document.environment == expectedEnvironment
    else {
      throw MetricUploadClientError.invalidServerResponse
    }

    do {
      try stateStore.markRegistered(
        keyID: state.keyID,
        environment: expectedEnvironment,
        ownerID: ownerID
      )
    } catch {
      throw MetricUploadClientError.keyStateUnavailable
    }
    return state.keyID
  }

  private func replaceExpiredRegistrationKey(
    state: MetricAppAttestState,
    ownerID: UUID
  ) async throws -> MetricAppAttestState {
    try await requireValidSession(ownerID: ownerID)
    guard
      state.ownerID == ownerID,
      state.registered == false,
      state.pendingRegistrationBody != nil,
      state.pendingRegistrationExpiresAt != nil
    else {
      throw MetricUploadClientError.keyStateUnavailable
    }

    return try await replaceKey(state: state, ownerID: ownerID)
  }

  /// App Attest sandbox and production keys are separate. Rotate any legacy or
  /// mismatched state before it can sign a request in the current environment.
  private func replaceKey(
    state: MetricAppAttestState,
    ownerID: UUID
  ) async throws -> MetricAppAttestState {
    try await requireValidSession(ownerID: ownerID)
    guard
      state.ownerID == ownerID,
      Self.isValidKeyID(state.keyID)
    else {
      throw MetricUploadClientError.keyStateUnavailable
    }

    let replacementKeyID: String
    do {
      replacementKeyID = try await appAttest.generateKey()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw MetricUploadClientError.keyStateUnavailable
    }
    try await requireValidSession(ownerID: ownerID)
    guard
      Self.isValidKeyID(replacementKeyID),
      replacementKeyID != state.keyID
    else {
      throw MetricUploadClientError.keyStateUnavailable
    }
    do {
      try stateStore.replaceKey(
        replacementKeyID,
        replacing: state.keyID,
        environment: expectedEnvironment,
        ownerID: ownerID
      )
    } catch {
      throw MetricUploadClientError.keyStateUnavailable
    }
    return MetricAppAttestState(
      ownerID: ownerID,
      keyID: replacementKeyID,
      registered: false,
      environment: expectedEnvironment
    )
  }

  private func metricIdentity(
    in body: Data
  ) throws -> MetricBodyIdentity {
    guard
      !body.isEmpty,
      body.count <= EncodedMetricRequest.maximumBodyBytes,
      let identity = try? JSONDecoder().decode(
        MetricBodyIdentity.self,
        from: body
      )
    else {
      throw MetricUploadClientError.invalidMetricBody
    }
    return identity
  }

  @discardableResult
  private func requireValidSession(
    ownerID: UUID
  ) async throws -> MetricUploadSession {
    guard let session = try await sessionProvider.validSession() else {
      throw MetricUploadClientError.authenticationRequired
    }
    guard session.ownerID == ownerID else {
      throw MetricUploadClientError.accountChanged
    }
    guard !session.accessToken.isEmpty else {
      throw MetricUploadClientError.authenticationRequired
    }
    return session
  }

  private func makeRequest(
    endpoint: MetricUploadEndpoint,
    accessToken: String,
    body: Data? = nil
  ) throws -> URLRequest {
    let url: URL
    do {
      url = try MetricUploadEndpointBuilder.url(
        for: endpoint,
        supabaseURL: supabaseURL
      )
    } catch {
      throw MetricUploadClientError.serviceUnavailable
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue(
      "application/json",
      forHTTPHeaderField: "Content-Type"
    )
    request.setValue(
      "application/json",
      forHTTPHeaderField: "Accept"
    )
    request.setValue(
      publishableKey,
      forHTTPHeaderField: "apikey"
    )
    request.setValue(
      "Bearer \(accessToken)",
      forHTTPHeaderField: "Authorization"
    )
    return request
  }

  private func response(
    for request: URLRequest
  ) async throws -> MetricUploadHTTPResponse {
    do {
      return try await transport.send(request)
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw MetricUploadClientError.networkUnavailable
    }
  }

  private func requireRegistrationSuccess(
    _ response: MetricUploadHTTPResponse,
    isChallenge: Bool
  ) throws {
    guard response.statusCode != 401, response.statusCode != 403 else {
      // None of these is a device that has no session — that case never gets
      // this far. A token the service will not accept is its own outcome:
      // signing in again reissues the same kind of token and changes nothing.
      let failure: MetricUploadClientError =
        switch AttestedEndpointRefusal.decode(response.body) {
        case .authentication: .tokenRefusedByService
        case .attestation: .attestationRejected
        case .accountNotActive: .accountNotActive
        case .unspecified: .registrationRefused
        }
      throw failure
    }
    guard response.statusCode < 500 else {
      throw MetricUploadClientError.serviceUnavailable
    }
    guard response.statusCode == 200 else {
      throw isChallenge
        ? MetricUploadClientError.serviceUnavailable
        : MetricUploadClientError.deviceRegistrationUnavailable
    }
  }

  private func requireMetricSuccess(
    _ response: MetricUploadHTTPResponse
  ) throws {
    switch response.statusCode {
    case 200, 201:
      return
    case 401, 403:
      let failure: MetricUploadClientError =
        switch AttestedEndpointRefusal.decode(response.body) {
        case .authentication: .tokenRefusedByService
        case .attestation: .attestationRejected
        case .accountNotActive: .accountNotActive
        case .unspecified: .uploadVerificationFailed
        }
      throw failure
    case 409:
      throw MetricUploadClientError.uploadConflict
    case 500...599:
      throw MetricUploadClientError.serviceUnavailable
    default:
      throw MetricUploadClientError.uploadRejected
    }
  }

  private static func sha256(_ data: Data) -> Data {
    Data(SHA256.hash(data: data))
  }

  private static func isValidKeyID(_ keyID: String) -> Bool {
    !keyID.isEmpty
      && keyID.utf8.count <= 128
      && Data(base64Encoded: keyID) != nil
  }

}

@MainActor
private final class SupabaseMetricUploadSessionProvider:
  MetricUploadSessionProviding
{
  private let client: SupabaseClient

  init(client: SupabaseClient) {
    self.client = client
  }

  func validSession() async throws -> MetricUploadSession? {
    let session: Session?
    do {
      session = try await client.validSession()
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      // A refresh that could not be completed is not a refused account, and
      // the retry disposition differs: this one is worth attempting again.
      throw MetricUploadClientError.sessionRefreshFailed
    }
    guard let session else { return nil }
    return MetricUploadSession(
      ownerID: session.user.id,
      accessToken: session.accessToken
    )
  }
}

@MainActor
private final class DeviceMetricAppAttestProvider: MetricAppAttestProviding {
  private let service: DCAppAttestService

  init(service: DCAppAttestService = .shared) {
    self.service = service
  }

  var isSupported: Bool {
    service.isSupported
  }

  func generateKey() async throws -> String {
    try await service.generateKey()
  }

  func attestKey(
    _ keyID: String,
    clientDataHash: Data
  ) async throws -> Data {
    try await service.attestKey(
      keyID,
      clientDataHash: clientDataHash
    )
  }

  func generateAssertion(
    _ keyID: String,
    clientDataHash: Data
  ) async throws -> Data {
    try await service.generateAssertion(
      keyID,
      clientDataHash: clientDataHash
    )
  }
}

@MainActor
private final class URLSessionMetricUploadHTTPTransport:
  MetricUploadHTTPTransport
{
  private let session: URLSession

  init(session: URLSession = .shared) {
    self.session = session
  }

  func send(
    _ request: URLRequest
  ) async throws -> MetricUploadHTTPResponse {
    let (body, response) = try await session.data(for: request)
    guard let response = response as? HTTPURLResponse else {
      throw MetricUploadTransportError.invalidResponse
    }
    return MetricUploadHTTPResponse(
      statusCode: response.statusCode,
      body: body
    )
  }
}

@MainActor
final class UserDefaultsMetricAppAttestStateStore:
  MetricAppAttestStateStoring
{
  private static let keyPrefix = "GameTime.metricAppAttest.v1."

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func state(
    for ownerID: UUID
  ) throws -> MetricAppAttestState? {
    guard let data = defaults.data(forKey: storageKey(ownerID)) else {
      return nil
    }
    let state = try JSONDecoder().decode(
      MetricAppAttestState.self,
      from: data
    )
    let registrationStateIsValid: Bool
    if state.registered {
      registrationStateIsValid =
        state.pendingRegistrationBody == nil
        && state.pendingRegistrationExpiresAt == nil
    } else if let pending = state.pendingRegistrationBody,
      let expiresAt = state.pendingRegistrationExpiresAt
    {
      registrationStateIsValid =
        expiresAt.timeIntervalSinceReferenceDate.isFinite
        && MetricAppAttestRegistrationBody.isValid(
          pending,
          keyID: state.keyID
        )
    } else if state.pendingRegistrationBody == nil,
      state.pendingRegistrationExpiresAt == nil
    {
      registrationStateIsValid = true
    } else {
      registrationStateIsValid = false
    }
    guard
      state.ownerID == ownerID,
      !state.keyID.isEmpty,
      state.keyID.utf8.count <= 128,
      Data(base64Encoded: state.keyID) != nil,
      registrationStateIsValid
    else {
      throw MetricAppAttestStateStoreError.invalidState
    }
    return state
  }

  func saveGeneratedKey(
    _ keyID: String,
    environment: AppAttestEnvironment,
    ownerID: UUID
  ) throws {
    guard
      !keyID.isEmpty,
      keyID.utf8.count <= 128,
      Data(base64Encoded: keyID) != nil
    else {
      throw MetricAppAttestStateStoreError.invalidState
    }
    if let existing = try state(for: ownerID) {
      guard
        existing.keyID == keyID,
        existing.registered == false,
        existing.environment == environment
      else {
        throw MetricAppAttestStateStoreError.conflict
      }
      return
    }
    try save(
      MetricAppAttestState(
        ownerID: ownerID,
        keyID: keyID,
        registered: false,
        environment: environment
      )
    )
  }

  func savePendingRegistrationBody(
    _ body: Data,
    expiresAt: Date,
    keyID: String,
    ownerID: UUID
  ) throws {
    guard
      MetricAppAttestRegistrationBody.isValid(body, keyID: keyID),
      expiresAt.timeIntervalSinceReferenceDate.isFinite,
      let existing = try state(for: ownerID),
      existing.keyID == keyID,
      existing.registered == false
    else {
      throw MetricAppAttestStateStoreError.invalidState
    }
    if let pending = existing.pendingRegistrationBody {
      guard
        pending == body,
        existing.pendingRegistrationExpiresAt == expiresAt
      else {
        throw MetricAppAttestStateStoreError.conflict
      }
      return
    }
    try save(
      MetricAppAttestState(
        ownerID: ownerID,
        keyID: keyID,
        registered: false,
        environment: existing.environment,
        pendingRegistrationBody: body,
        pendingRegistrationExpiresAt: expiresAt
      )
    )
  }

  func replaceKey(
    _ newKeyID: String,
    replacing oldKeyID: String,
    environment: AppAttestEnvironment,
    ownerID: UUID
  ) throws {
    guard
      !newKeyID.isEmpty,
      newKeyID.utf8.count <= 128,
      Data(base64Encoded: newKeyID) != nil,
      newKeyID != oldKeyID,
      let existing = try state(for: ownerID),
      existing.keyID == oldKeyID
    else {
      throw MetricAppAttestStateStoreError.conflict
    }
    try save(
      MetricAppAttestState(
        ownerID: ownerID,
        keyID: newKeyID,
        registered: false,
        environment: environment
      )
    )
  }

  func markRegistered(
    keyID: String,
    environment: AppAttestEnvironment,
    ownerID: UUID
  ) throws {
    guard
      let existing = try state(for: ownerID),
      existing.keyID == keyID,
      existing.environment == environment
    else {
      throw MetricAppAttestStateStoreError.conflict
    }
    guard existing.registered == false else {
      return
    }
    try save(
      MetricAppAttestState(
        ownerID: ownerID,
        keyID: keyID,
        registered: true,
        environment: environment
      )
    )
  }

  func invalidateCurrentKey(
    rejectedKeyID: String,
    ownerID: UUID
  ) throws {
    guard
      let existing = try state(for: ownerID),
      existing.ownerID == ownerID,
      existing.keyID == rejectedKeyID
    else {
      return
    }
    // This read/compare/remove sequence is synchronous and isolated to the
    // main actor, so another request cannot replace the key between the
    // comparison and removal.
    defaults.removeObject(forKey: storageKey(ownerID))
  }

  private func save(
    _ state: MetricAppAttestState
  ) throws {
    let data = try JSONEncoder().encode(state)
    defaults.set(data, forKey: storageKey(state.ownerID))
  }

  private func storageKey(_ ownerID: UUID) -> String {
    Self.keyPrefix + ownerID.uuidString.lowercased()
  }
}

private enum MetricUploadEndpoint {
  case attestChallenge
  case attestDevice
  case ingestMetrics

  var pathComponents: [String] {
    switch self {
    case .attestChallenge:
      ["attest-device", "challenge"]
    case .attestDevice:
      ["attest-device"]
    case .ingestMetrics:
      ["ingest-metrics"]
    }
  }
}

private enum MetricUploadEndpointBuilder {
  static func url(
    for endpoint: MetricUploadEndpoint,
    supabaseURL: URL
  ) throws -> URL {
    guard
      var components = URLComponents(
        url: supabaseURL,
        resolvingAgainstBaseURL: false
      )
    else {
      throw MetricUploadTransportError.invalidURL
    }

    var pathComponents = components.path
      .split(separator: "/", omittingEmptySubsequences: true)
      .map(String.init)
    let functionsSuffix = ["functions", "v1"]
    if Array(pathComponents.suffix(functionsSuffix.count))
      != functionsSuffix
    {
      pathComponents.append(contentsOf: functionsSuffix)
    }
    pathComponents.append(contentsOf: endpoint.pathComponents)

    components.path = "/" + pathComponents.joined(separator: "/")
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
      throw MetricUploadTransportError.invalidURL
    }
    return url
  }
}

private struct MetricBodyIdentity: Decodable {
  let contestID: UUID
  let clientBatchID: UUID
  let observations: [Observation]

  var observationCount: Int { observations.count }

  enum CodingKeys: String, CodingKey {
    case contestID = "contestId"
    case clientBatchID = "clientBatchId"
    case observations
  }

  struct Observation: Decodable {}
}

private struct AttestChallengeDocument: Decodable {
  let challenge: String
  let expiresInSeconds: Int
}

private struct AttestRegistrationDocument: Codable {
  let keyID: String
  let attestation: String

  enum CodingKeys: String, CodingKey {
    case keyID = "keyId"
    case attestation
  }
}

private enum MetricAppAttestRegistrationBody {
  static let maximumBytes = 64 * 1024
  // The backend accepts the derived challenge for its current and immediately
  // previous ten-minute window. Ten minutes from receipt is the conservative
  // interval in which these exact bytes remain replayable across every boundary.
  static let maximumReplayLifetime: TimeInterval = 10 * 60

  static func encode(
    keyID: String,
    attestation: Data
  ) throws -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [
      .sortedKeys,
      .withoutEscapingSlashes,
    ]
    let body = try encoder.encode(
      AttestRegistrationDocument(
        keyID: keyID,
        attestation: attestation.base64EncodedString()
      )
    )
    guard isValid(body, keyID: keyID) else {
      throw MetricAppAttestStateStoreError.invalidState
    }
    return body
  }

  static func isValid(
    _ body: Data,
    keyID: String
  ) -> Bool {
    guard
      !body.isEmpty,
      body.count <= maximumBytes,
      let document = try? JSONDecoder().decode(
        AttestRegistrationDocument.self,
        from: body
      ),
      document.keyID == keyID,
      !document.attestation.isEmpty,
      let attestation = Data(base64Encoded: document.attestation),
      !attestation.isEmpty
    else {
      return false
    }
    return true
  }
}

private struct AttestRegistrationResponse: Decodable {
  let registered: Bool
  let environment: AppAttestEnvironment
}

private struct MetricIngestDocument: Decodable {
  let batchID: UUID
  let observationCount: Int
  let replayed: Bool

  enum CodingKeys: String, CodingKey {
    case batchID = "batchId"
    case observationCount
    case replayed
  }
}

private enum MetricUploadTransportError: Error {
  case invalidURL
  case invalidResponse
}

private enum MetricAppAttestStateStoreError: Error {
  case invalidState
  case conflict
}
