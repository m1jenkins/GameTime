import Foundation
import GameTimeCore
import Supabase

enum ChallengeHealthUploadClientError: LocalizedError, Equatable {
  case unavailable, accountChanged, busy, storage, refused
  var errorDescription: String? {
    switch self {
    case .unavailable: "We couldn’t update your activity. Try again in a moment."
    case .accountChanged: "Your sign-in changed. Open your challenge and try again."
    case .busy: "We’re already updating your activity. Check your challenge in a moment."
    case .storage: "We couldn’t save this update on your phone. Unlock your phone and try again."
    case .refused: "We couldn’t accept this update. Refresh your challenge and try again."
    }
  }
}

/// Raw Health records never enter this store. Each account has a protected,
/// non-backup journal of normalized bodies, signatures and acknowledged heads.
@MainActor
final class ChallengeHealthUploadFileStore {
  let directory: URL
  init(directory: URL) { self.directory = directory }

  static func applicationSupport() throws -> ChallengeHealthUploadFileStore {
    guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
      throw ChallengeHealthUploadClientError.storage
    }
    return ChallengeHealthUploadFileStore(directory: base.appendingPathComponent("GameTime/ChallengeHealthUploads", isDirectory: true))
  }

  func load(actor: UUID) throws -> ChallengeHealthUploadJournal {
    let file = url(actor)
    guard FileManager.default.fileExists(atPath: file.path) else { return ChallengeHealthUploadJournal(actorID: actor) }
    do { return try ChallengeHealthUploadJournal(restoring: Data(contentsOf: file), actorID: actor) }
    catch { throw ChallengeHealthUploadClientError.storage }
  }

  func save(_ journal: ChallengeHealthUploadJournal) throws {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      var folder = directory
      var values = URLResourceValues(); values.isExcludedFromBackup = true
      try folder.setResourceValues(values)
      var file = url(journal.actorID)
      try journal.encoded().write(to: file, options: [.atomic, .completeFileProtection])
      try file.setResourceValues(values)
    } catch { throw ChallengeHealthUploadClientError.storage }
  }

  func clear(actor: UUID) throws {
    let file = url(actor)
    if FileManager.default.fileExists(atPath: file.path) {
      do { try FileManager.default.removeItem(at: file) }
      catch { throw ChallengeHealthUploadClientError.storage }
    }
  }

  private func url(_ actor: UUID) -> URL { directory.appendingPathComponent(actor.uuidString.lowercased() + ".json") }
}

private final class ChallengeHealthNoRedirect: NSObject, URLSessionTaskDelegate {
  func urlSession(_ session: URLSession, task: URLSessionTask,
                  willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                  completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

/// Minimal P8 wire transport, connected by P9 through the shared delivery lease.
/// Checked-in gates refuse new facts while preserving exact response recovery.
@MainActor
final class ChallengeHealthUploadClient {
  private let permitsNewUploads: Bool
  private let store: ChallengeHealthUploadFileStore
  private let coordinator: ChallengeHealthTransportCoordinator
  private let binding: @MainActor () -> WeeklyClientSession?
  private let prepareSession: @MainActor (UUID) async throws -> Void
  private let sign: @MainActor (UUID, Data) async throws -> MetricSignedMaterial
  private let send: @MainActor (ChallengeHealthSignedUpload, WeeklyClientSession) async throws -> Data
  private let environment: AppAttestEnvironment
  private let privateAccountMode: Bool
  private var generation = UUID()
  private var busy = false

  init(enabled: Bool = false, environment: AppAttestEnvironment,
       privateAccountMode: Bool = false,
       coordinator: ChallengeHealthTransportCoordinator,
       binding: @escaping @MainActor () -> WeeklyClientSession?,
       prepareSession: @escaping @MainActor (UUID) async throws -> Void = { _ in },
       sign: @escaping @MainActor (UUID, Data) async throws -> MetricSignedMaterial,
       send: @escaping @MainActor (ChallengeHealthSignedUpload, WeeklyClientSession) async throws -> Data) {
    self.permitsNewUploads = enabled; self.environment = environment; self.store = coordinator.uploadStore; self.coordinator = coordinator
    self.privateAccountMode = privateAccountMode
    self.binding = binding; self.prepareSession = prepareSession; self.sign = sign; self.send = send
    coordinator.register(.upload) { [weak self] actor in
      guard let self else { throw ChallengeHealthTransportCoordinator.Failure.missingWriter }
      return try self.store.load(actor: actor).pending.map { signed in
        let request = try ChallengeHealthUploadRequest(restoring: signed.exactBody)
        return ChallengeHealthTransportCoordinator.Pending(kind: .upload, id: request.requestID,
          keyID: signed.keyID, assertion: signed.assertion, body: signed.exactBody,
          requiresDeviceVerification: !signed.isPrivateAccount) { [weak self] in
            guard let self else { throw ChallengeHealthTransportCoordinator.Failure.missingWriter }
            let epoch = self.generation
            guard let session = self.binding(), session.actorID == actor else { throw ChallengeHealthUploadClientError.accountChanged }
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
                   privateAccountMode: Bool = false,
                   permitsHTTPS: Bool = false) throws {
    var allowed = permitsHTTPS && SupabaseChallengeV1Client.isHTTPSOrigin(origin)
    #if DEBUG || STAGING
    allowed = allowed || SupabaseWeeklyClient.isExplicitLoopback(origin)
    #endif
    guard allowed, !publishableKey.isEmpty else { throw ChallengeHealthUploadClientError.unavailable }
    let config = URLSessionConfiguration.ephemeral
    config.urlCache = nil; config.httpCookieStorage = nil
    config.requestCachePolicy = .reloadIgnoringLocalCacheData
    let transport = URLSession(configuration: config, delegate: ChallengeHealthNoRedirect(), delegateQueue: nil)
    self.init(enabled: enabled, environment: environment, privateAccountMode: privateAccountMode, coordinator: coordinator, binding: {
      guard let s = sdk.auth.currentSession, s.expiresAt > Date().timeIntervalSince1970 else { return nil }
      return WeeklyClientSession(actorID: s.user.id, identity: s.accessToken)
    }, prepareSession: { actor in
      guard let prior = sdk.auth.currentSession, prior.user.id == actor,
            let priorID = Self.sessionID(prior.accessToken),
            let fresh = try await sdk.validSession(), fresh.user.id == actor,
            Self.sessionID(fresh.accessToken) == priorID,
            sdk.auth.currentSession?.accessToken == fresh.accessToken else {
        throw ChallengeHealthUploadClientError.accountChanged
      }
    }, sign: { actor, body in try await signer.sign(ownerID: actor, body: body) }, send: { upload, session in
      var request = URLRequest(url: origin.appendingPathComponent("functions/v1/ingest-challenge-health"))
      request.httpMethod = "POST"; request.httpBody = upload.exactBody
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.setValue(publishableKey, forHTTPHeaderField: "apikey")
      request.setValue("Bearer \(session.identity)", forHTTPHeaderField: "Authorization")
      if !upload.isPrivateAccount {
        request.setValue(upload.keyID, forHTTPHeaderField: "x-gametime-key-id")
        request.setValue(upload.assertion.base64EncodedString(), forHTTPHeaderField: "x-gametime-assertion")
      }
      let (data, response) = try await transport.data(for: request)
      guard let http = response as? HTTPURLResponse, data.count <= 4096 else { throw ChallengeHealthUploadClientError.unavailable }
      guard http.statusCode == 200 else { throw ChallengeHealthUploadClientError.refused }
      return data
    })
  }

  /// Call on sign-out, account replacement or cancellation. Any operation
  /// already awaiting the signer/network is fenced out when it returns.
  func invalidate() { generation = UUID() }

  func clear(actor: UUID) throws { invalidate(); try store.clear(actor: actor) }

  func submit(_ request: ChallengeHealthUploadRequest, confirmedServerRevision: Int? = nil, validate: @MainActor () throws -> Void = {}) async throws {
    guard !busy else { throw ChallengeHealthUploadClientError.busy }
    try await coordinator.begin(actor: request.actorID)
    busy = true; defer { busy = false }
    defer { coordinator.release(actor: request.actorID) }
    let epoch = generation
    try await prepareSession(request.actorID)
    guard generation == epoch, let session = binding(), session.actorID == request.actorID else {
      throw ChallengeHealthUploadClientError.accountChanged
    }
    try check(epoch, session)
    var journal = try store.load(actor: request.actorID)
    let matchingSaved = journal.pending.first(where: {
      (try? ChallengeHealthUploadRequest(restoring: $0.exactBody).requestID) == request.requestID
    })
    if let saved = matchingSaved {
      guard saved.exactBody == request.exactBytes else { throw ChallengeHealthUploadError.requestConflict }
      guard !privateAccountMode || saved.isPrivateAccount else { throw ChallengeHealthUploadClientError.refused }
    }
    try await coordinator.recover(actor: request.actorID, includingDeviceVerifiedRequests: !privateAccountMode)
    try check(epoch, session)
    journal = try store.load(actor: request.actorID)
    if matchingSaved != nil { return }
    if let confirmedServerRevision { try journal.reconcileServerHead(for: request, revision: confirmedServerRevision) }
    guard permitsNewUploads else { throw ChallengeHealthUploadClientError.unavailable }
    try validate()
    let upload: ChallengeHealthSignedUpload
    if privateAccountMode {
      upload = try ChallengeHealthSignedUpload(privateAccountRequest: request)
    } else {
      let material = try await sign(request.actorID, request.exactBytes)
      try validate()
      try check(epoch, session)
      try coordinator.validateNewSignature(keyID: material.keyID, assertion: material.assertion)
      guard material.environment == environment else { throw ChallengeHealthUploadError.invalidSignature }
      upload = try ChallengeHealthSignedUpload(request: request, keyID: material.keyID,
        assertion: material.assertion, environment: material.environment.rawValue)
    }
    try validate()
    try check(epoch, session)
    try journal.enqueue(upload)
    try store.save(journal) // durable before the first network attempt
    try await transmit(upload, request: request, journal: &journal, epoch: epoch, session: session)
  }

  func retry(actor: UUID) async throws {
    guard !busy else { throw ChallengeHealthUploadClientError.busy }
    try await coordinator.begin(actor: actor)
    busy = true; defer { busy = false }
    defer { coordinator.release(actor: actor) }
    let epoch = generation
    try await prepareSession(actor)
    guard generation == epoch, let session = binding(), session.actorID == actor else { throw ChallengeHealthUploadClientError.accountChanged }
    try check(epoch, session)
    try await coordinator.recover(actor: actor, includingDeviceVerifiedRequests: !privateAccountMode)
    try check(epoch, session)
  }

  private func transmit(_ upload: ChallengeHealthSignedUpload, request: ChallengeHealthUploadRequest,
                        journal: inout ChallengeHealthUploadJournal, epoch: UUID,
                        session: WeeklyClientSession) async throws {
    try check(epoch, session)
    guard upload.isPrivateAccount ? privateAccountMode : upload.environment == environment.rawValue else {
      throw ChallengeHealthUploadError.invalidSignature
    }
    let receipt = try await send(upload, session)
    try check(epoch, session)
    try journal.acknowledge(request, receipt: receipt)
    try store.save(journal)
  }

  private func check(_ epoch: UUID, _ session: WeeklyClientSession) throws {
    try Task.checkCancellation()
    try coordinator.check(actor: session.actorID)
    guard epoch == generation, binding() == session else { throw ChallengeHealthUploadClientError.accountChanged }
  }

  private static func sessionID(_ token: String) -> UUID? {
    let parts = token.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count == 3 else { return nil }
    var value = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
    value += String(repeating: "=", count: (4 - value.count % 4) % 4)
    guard let data = Data(base64Encoded: value), let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let session = object["session_id"] as? String else { return nil }
    return UUID(uuidString: session)
  }
}
