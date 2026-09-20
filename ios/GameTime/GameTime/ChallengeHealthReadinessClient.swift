import Foundation
import GameTimeCore
import Supabase

enum ChallengeHealthReadinessClientError: LocalizedError, Equatable {
  case unavailable, accountChanged, busy, storage, refused
  var errorDescription: String? {
    switch self {
    case .unavailable: "We can’t confirm your activity setup right now. Try again in a moment."
    case .accountChanged: "Your sign-in changed. Open your challenge and try again."
    case .busy: "We’re already confirming your activity setup. Check your challenge in a moment."
    case .storage: "We couldn’t save this confirmation on your phone. Unlock your phone and try again."
    case .refused: "We couldn’t confirm your activity setup. Refresh your challenge and try again."
    }
  }
}

@MainActor
final class ChallengeHealthReadinessFileStore {
  let directory: URL
  init(directory: URL) { self.directory = directory }
  static func applicationSupport() throws -> Self {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw ChallengeHealthReadinessClientError.storage
    }
    return Self(directory: base.appendingPathComponent("GameTime/ChallengeHealthReadiness", isDirectory: true))
  }
  func load(actor: UUID) throws -> ChallengeHealthReadinessJournal {
    let file = url(actor)
    guard FileManager.default.fileExists(atPath: file.path) else { return ChallengeHealthReadinessJournal(actorID: actor) }
    do { return try ChallengeHealthReadinessJournal(restoring: Data(contentsOf: file), actorID: actor) }
    catch { throw ChallengeHealthReadinessClientError.storage }
  }
  func save(_ journal: ChallengeHealthReadinessJournal) throws {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var directory = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
      try directory.setResourceValues(values)
      var file = url(journal.actorID)
      try journal.encoded().write(to: file, options: [.atomic, .completeFileProtection])
      try file.setResourceValues(values)
    } catch { throw ChallengeHealthReadinessClientError.storage }
  }
  func clear(actor: UUID) throws {
    let file = url(actor)
    if FileManager.default.fileExists(atPath: file.path) {
      do { try FileManager.default.removeItem(at: file) }
      catch { throw ChallengeHealthReadinessClientError.storage }
    }
  }
  private func url(_ actor: UUID) -> URL {
    directory.appendingPathComponent(actor.uuidString.lowercased() + ".json")
  }
}

private final class ChallengeHealthReadinessNoRedirect: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Default-off receipt transport used by the Health flow. Exact signed bytes
/// survive response loss and stay recoverable when new signing is disabled.
@MainActor
final class ChallengeHealthReadinessClient {
  private let permitsNewRequests: Bool
  private let store: ChallengeHealthReadinessFileStore
  private let coordinator: ChallengeHealthTransportCoordinator
  private let binding: @MainActor () -> WeeklyClientSession?
  private let prepareSession: @MainActor (UUID) async throws -> Void
  private let sign: @MainActor (UUID, Data) async throws -> MetricSignedMaterial
  private let send: @MainActor (ChallengeHealthSignedReadinessRequest, WeeklyClientSession) async throws -> Data
  private let environment: AppAttestEnvironment
  private var generation = UUID()
  private var busy = false

  init(enabled: Bool = false, environment: AppAttestEnvironment,
       coordinator: ChallengeHealthTransportCoordinator,
       binding: @escaping @MainActor () -> WeeklyClientSession?,
       prepareSession: @escaping @MainActor (UUID) async throws -> Void = { _ in },
       sign: @escaping @MainActor (UUID, Data) async throws -> MetricSignedMaterial,
       send: @escaping @MainActor (ChallengeHealthSignedReadinessRequest, WeeklyClientSession) async throws -> Data) {
    permitsNewRequests = enabled; self.environment = environment; self.store = coordinator.readinessStore; self.coordinator = coordinator
    self.binding = binding; self.prepareSession = prepareSession; self.sign = sign; self.send = send
    coordinator.register(.readiness) { [weak self] actor in
      guard let self else { throw ChallengeHealthTransportCoordinator.Failure.missingWriter }
      return try self.store.load(actor: actor).pending.map { signed in
        let request = try ChallengeHealthReadinessRequest(restoring: signed.exactBody)
        return ChallengeHealthTransportCoordinator.Pending(kind: .readiness, id: request.requestID,
          keyID: signed.keyID, assertion: signed.assertion, body: signed.exactBody) { [weak self] in
            guard let self else { throw ChallengeHealthTransportCoordinator.Failure.missingWriter }
            let epoch = self.generation
            guard let session = self.binding(), session.actorID == actor else { throw ChallengeHealthReadinessClientError.accountChanged }
            var journal = try self.store.load(actor: actor)
            try await self.transmit(signed, request: request, journal: &journal, epoch: epoch, session: session)
          }
      }
    }
  }

  convenience init(sdk: SupabaseClient, origin: URL, publishableKey: String,
                   signer: any AppAttestedBodySigning, environment: AppAttestEnvironment,
                   coordinator: ChallengeHealthTransportCoordinator,
                   enabled: Bool = false,
                   permitsHTTPS: Bool = false) throws {
    var allowed = permitsHTTPS && SupabaseChallengeV1Client.isHTTPSOrigin(origin)
    #if DEBUG || STAGING
    allowed = allowed || SupabaseWeeklyClient.isExplicitLoopback(origin)
    #endif
    guard allowed, !publishableKey.isEmpty else { throw ChallengeHealthReadinessClientError.unavailable }
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil; configuration.httpCookieStorage = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    let transport = URLSession(configuration: configuration, delegate: ChallengeHealthReadinessNoRedirect(), delegateQueue: nil)
    self.init(enabled: enabled, environment: environment, coordinator: coordinator, binding: {
      guard let session = sdk.auth.currentSession, session.expiresAt > Date().timeIntervalSince1970 else { return nil }
      return WeeklyClientSession(actorID: session.user.id, identity: session.accessToken)
    }, prepareSession: { actor in
      guard let prior = sdk.auth.currentSession, prior.user.id == actor,
            let priorID = Self.sessionID(prior.accessToken),
            let fresh = try await sdk.validSession(), fresh.user.id == actor,
            Self.sessionID(fresh.accessToken) == priorID,
            sdk.auth.currentSession?.accessToken == fresh.accessToken else {
        throw ChallengeHealthReadinessClientError.accountChanged
      }
    }, sign: { actor, body in try await signer.sign(ownerID: actor, body: body) }, send: { signed, session in
      var request = URLRequest(url: origin.appendingPathComponent("functions/v1/ingest-challenge-health"))
      request.httpMethod = "POST"; request.httpBody = signed.exactBody
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(publishableKey, forHTTPHeaderField: "apikey")
      request.setValue("Bearer \(session.identity)", forHTTPHeaderField: "Authorization")
      request.setValue(signed.keyID, forHTTPHeaderField: "x-gametime-key-id")
      request.setValue(signed.assertion.base64EncodedString(), forHTTPHeaderField: "x-gametime-assertion")
      let (data, response) = try await transport.data(for: request)
      guard let http = response as? HTTPURLResponse, data.count <= 1024 else { throw ChallengeHealthReadinessClientError.unavailable }
      if http.statusCode == 401 { throw ChallengeHealthReadinessClientError.accountChanged }
      guard http.statusCode == 200 else { throw ChallengeHealthReadinessClientError.refused }
      return data
    })
  }

  func invalidate() { generation = UUID() }
  func clear(actor: UUID) throws { invalidate(); try store.clear(actor: actor) }

  func submit(_ request: ChallengeHealthReadinessRequest, validate: @MainActor () throws -> Void = {}) async throws {
    guard !busy else { throw ChallengeHealthReadinessClientError.busy }
    try await coordinator.begin(actor: request.actorID)
    busy = true; defer { busy = false }
    defer { coordinator.release(actor: request.actorID) }
    let epoch = generation
    try await prepareSession(request.actorID)
    guard generation == epoch, let session = binding(), session.actorID == request.actorID else {
      throw ChallengeHealthReadinessClientError.accountChanged
    }
    try check(epoch, session)
    var journal = try store.load(actor: request.actorID)
    let matchingSaved = journal.pending.first(where: {
      (try? ChallengeHealthReadinessRequest(restoring: $0.exactBody).requestID) == request.requestID
    })
    if let saved = matchingSaved {
      guard saved.exactBody == request.exactBytes else { throw ChallengeHealthReadinessRequestError.requestConflict }
    }
    try await coordinator.recover(actor: request.actorID)
    try check(epoch, session)
    journal = try store.load(actor: request.actorID)
    if matchingSaved != nil { return }
    guard permitsNewRequests else { throw ChallengeHealthReadinessClientError.unavailable }
    try validate()
    let material = try await sign(request.actorID, request.exactBytes)
    try validate()
    try check(epoch, session)
    try coordinator.validateNewSignature(keyID: material.keyID, assertion: material.assertion)
    guard material.environment == environment else { throw ChallengeHealthReadinessRequestError.invalidSignature }
    let signed = try ChallengeHealthSignedReadinessRequest(request: request, keyID: material.keyID,
                                                            assertion: material.assertion,
                                                            environment: material.environment.rawValue)
    try journal.enqueue(signed); try store.save(journal)
    try await transmit(signed, request: request, journal: &journal, epoch: epoch, session: session)
  }

  func retry(actor: UUID) async throws {
    guard !busy else { throw ChallengeHealthReadinessClientError.busy }
    try await coordinator.begin(actor: actor)
    busy = true; defer { busy = false }
    defer { coordinator.release(actor: actor) }
    let epoch = generation
    try await prepareSession(actor)
    guard generation == epoch, let session = binding(), session.actorID == actor else { throw ChallengeHealthReadinessClientError.accountChanged }
    try check(epoch, session)
    try await coordinator.recover(actor: actor)
    try check(epoch, session)
  }

  private func transmit(_ signed: ChallengeHealthSignedReadinessRequest,
                        request: ChallengeHealthReadinessRequest,
                        journal: inout ChallengeHealthReadinessJournal,
                        epoch: UUID, session: WeeklyClientSession) async throws {
    try check(epoch, session)
    guard signed.environment == environment.rawValue else { throw ChallengeHealthReadinessRequestError.invalidSignature }
    let receipt = try await send(signed, session)
    try check(epoch, session)
    try journal.acknowledge(request, receipt: receipt); try store.save(journal)
  }

  private func check(_ epoch: UUID, _ session: WeeklyClientSession) throws {
    try Task.checkCancellation()
    try coordinator.check(actor: session.actorID)
    guard generation == epoch, binding() == session else { throw ChallengeHealthReadinessClientError.accountChanged }
  }

  private static func sessionID(_ token: String) -> UUID? {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
    guard let data = Data(base64Encoded: payload),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = object["session_id"] as? String else { return nil }
    return UUID(uuidString: id)
  }
}
