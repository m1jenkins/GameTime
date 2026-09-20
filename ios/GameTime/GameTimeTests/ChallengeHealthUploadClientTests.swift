import Foundation
import GameTimeCore
import Testing
@testable import GameTime

@Suite("Real Health upload recovery and session fences") @MainActor
struct ChallengeHealthUploadClientTests {
  let actor = UUID(uuidString: "aaaaaaaa-1111-1111-1111-111111111111")!
  func request() throws -> ChallengeHealthUploadRequest {
    let window = try ChallengeHealthWindow(startMicroseconds: 1_800_000_000_000000,
      endMicroseconds: 1_800_086_400_000000, timeZoneIdentifier: "UTC", calendar: .gregorian)
    let binding = try ChallengeHealthBinding(actorID: actor, challengeID: UUID(), agreementVersion: 1,
      termsDigest: String(repeating: "a", count: 64), metric: .steps, challengeWindow: window,
      realSourcePolicy: .appleWatchAutomaticStepsV1)
    return try ChallengeHealthUploadRequest(binding: binding, requestID: UUID(), revision: 1,
      previousRevision: nil, replacement: .value(ChallengeHealthValue(metric: .steps, integerValue: 123)),
      observedAtMicroseconds: window.endMicroseconds, queriedThroughMicroseconds: window.endMicroseconds)
  }
  func store() -> ChallengeHealthUploadFileStore {
    ChallengeHealthUploadFileStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent("p8-upload-" + UUID().uuidString))
  }
  func coordinator(_ uploadStore: ChallengeHealthUploadFileStore) -> ChallengeHealthTransportCoordinator {
    ChallengeHealthTransportCoordinator(uploadStore: uploadStore,
      readinessStore: ChallengeHealthReadinessFileStore(directory: uploadStore.directory.appendingPathComponent("readiness")))
  }
  func material() -> MetricSignedMaterial {
    MetricSignedMaterial(keyID: Data(repeating: 1, count: 32).base64EncodedString(), assertion: nextP9TestAssertion(), environment: .development)
  }
  func receipt(_ request: ChallengeHealthUploadRequest) throws -> Data {
    try JSONSerialization.data(withJSONObject: ["version": "challenge_real_health_receipt_v1", "request_id": request.requestID.uuidString.lowercased(),
      "challenge_id": request.challengeID.uuidString.lowercased(), "revision": request.revision, "accepted_at": "2026-09-20T00:00:00Z"])
  }

  @Test("response loss survives relaunch, retries identical signature while admission is disabled")
  func lostResponse() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let request = try request(), session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    var original: ChallengeHealthSignedUpload?
    let client = ChallengeHealthUploadClient(enabled: true, environment: .development, coordinator: coordinator(store), binding: { session },
      sign: { _, _ in material() }, send: { upload, _ in original = upload; throw ChallengeHealthUploadClientError.unavailable })
    await #expect(throws: ChallengeHealthUploadClientError.unavailable) { try await client.submit(request) }
    #expect(try store.load(actor: actor).pending.count == 1)
    let relaunched = ChallengeHealthUploadClient(environment: .development, coordinator: coordinator(store), binding: { session },
      sign: { _, _ in Issue.record("a durable retry must not sign again"); return material() },
      send: { upload, _ in #expect(upload == original); return try receipt(request) })
    try await relaunched.retry(actor: actor)
    #expect(try store.load(actor: actor).pending.isEmpty)
  }

  @Test("private account activity survives response loss without requesting a device signature")
  func privateAccountRecovery() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let request = try request(), session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    var saved: ChallengeHealthSignedUpload?
    let first = ChallengeHealthUploadClient(enabled: true, environment: .development, privateAccountMode: true,
      coordinator: coordinator(store), binding: { session },
      sign: { _, _ in Issue.record("private activity must not request device verification"); return material() },
      send: { upload, _ in
        #expect(upload.isPrivateAccount && upload.keyID.isEmpty && upload.assertion.isEmpty)
        saved = upload; throw ChallengeHealthUploadClientError.unavailable
      })
    await #expect(throws: ChallengeHealthUploadClientError.unavailable) { try await first.submit(request) }
    let retry = ChallengeHealthUploadClient(environment: .development, privateAccountMode: true,
      coordinator: coordinator(store), binding: { session },
      sign: { _, _ in Issue.record("recovery must not sign"); return material() },
      send: { upload, _ in #expect(upload == saved); return try receipt(request) })
    try await retry.retry(actor: actor)
    #expect(try store.load(actor: actor).pending.isEmpty)
  }

  @Test("a new upload drains an earlier durable assertion before signing")
  func newUploadDrainsEarlierPendingRequestAfterRelaunch() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let firstRequest = try request(), secondRequest = try request()
    let session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    var firstSigned: ChallengeHealthSignedUpload?
    let interrupted = ChallengeHealthUploadClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in material() }, send: { upload, _ in
        firstSigned = upload; throw ChallengeHealthUploadClientError.unavailable
      })
    await #expect(throws: ChallengeHealthUploadClientError.unavailable) { try await interrupted.submit(firstRequest) }
    let saved = try #require(firstSigned)

    var sent: [ChallengeHealthSignedUpload] = []
    var newSignedBodies: [Data] = []
    let relaunched = ChallengeHealthUploadClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, body in newSignedBodies.append(body); return material() }, send: { upload, _ in
        sent.append(upload)
        if upload == saved { return try receipt(firstRequest) }
        return try receipt(secondRequest)
      })
    try await relaunched.submit(secondRequest)
    #expect(newSignedBodies == [secondRequest.exactBytes])
    #expect(sent.count == 2)
    #expect(sent[0] == saved)
    #expect(sent[1].exactBody == secondRequest.exactBytes)
    #expect(try store.load(actor: actor).pending.isEmpty)
  }

  @Test("a failed durable upload blocks signing a later request")
  func failedPendingUploadBlocksLaterSigningAfterRelaunch() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let firstRequest = try request(), secondRequest = try request()
    let session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    var firstSigned: ChallengeHealthSignedUpload?
    let interrupted = ChallengeHealthUploadClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in material() }, send: { upload, _ in
        firstSigned = upload; throw ChallengeHealthUploadClientError.unavailable
      })
    await #expect(throws: ChallengeHealthUploadClientError.unavailable) { try await interrupted.submit(firstRequest) }
    let saved = try #require(firstSigned)

    var signCount = 0
    var retried: ChallengeHealthSignedUpload?
    let relaunched = ChallengeHealthUploadClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in signCount += 1; return material() }, send: { upload, _ in
        retried = upload; throw ChallengeHealthUploadClientError.unavailable
      })
    await #expect(throws: ChallengeHealthUploadClientError.unavailable) { try await relaunched.submit(secondRequest) }
    #expect(signCount == 0)
    #expect(retried == saved)
    #expect(try store.load(actor: actor).pending.map(\.exactBody) == [saved.exactBody])
  }

  @Test("switch away and back during signing cannot persist or send")
  func signingFence() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    var client: ChallengeHealthUploadClient!
    client = ChallengeHealthUploadClient(enabled: true, environment: .development, coordinator: coordinator(store), binding: { session },
      sign: { _, _ in client.invalidate(); return material() },
      send: { _, _ in Issue.record("stale signing must not send"); return Data() })
    await #expect(throws: ChallengeHealthUploadClientError.accountChanged) { try await client.submit(request()) }
    #expect(try store.load(actor: actor).pending.isEmpty)
  }

  @Test("session change during response leaves pending for the original account")
  func responseFence() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let request = try request()
    var session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    let client = ChallengeHealthUploadClient(enabled: true, environment: .development, coordinator: coordinator(store), binding: { session },
      sign: { _, _ in material() }, send: { _, _ in
        session = WeeklyClientSession(actorID: UUID(), identity: "another-session"); return try receipt(request)
      })
    await #expect(throws: ChallengeHealthUploadClientError.accountChanged) { try await client.submit(request) }
    #expect(try store.load(actor: actor).pending.count == 1)
    #expect(try store.load(actor: session.actorID).pending.isEmpty)
  }

  @Test("default-off client creates no new signature or retry file")
  func disabled() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let client = ChallengeHealthUploadClient(environment: .development, coordinator: coordinator(store),
      binding: { WeeklyClientSession(actorID: actor, identity: "fictional-session") },
      sign: { _, _ in Issue.record("disabled client cannot sign"); return material() },
      send: { _, _ in Issue.record("disabled client cannot send"); return Data() })
    await #expect(throws: ChallengeHealthUploadClientError.unavailable) { try await client.submit(request()) }
    #expect(try store.load(actor: actor).pending.isEmpty)
  }
}
