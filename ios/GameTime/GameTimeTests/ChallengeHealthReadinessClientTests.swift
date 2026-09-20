import Foundation
import GameTimeCore
import Testing
@testable import GameTime

@Suite("Real Health readiness receipt recovery") @MainActor
struct ChallengeHealthReadinessClientTests {
  let actor = UUID(uuidString: "bbbbbbbb-1111-1111-1111-111111111111")!

  func request() throws -> ChallengeHealthReadinessRequest {
    let challenge = try ChallengeHealthWindow(
      startMicroseconds: 1_800_000_000_000_000,
      endMicroseconds: 1_800_086_400_000_000,
      timeZoneIdentifier: "UTC", calendar: .gregorian
    )
    let binding = try ChallengeHealthBinding(
      actorID: actor, challengeID: UUID(), agreementVersion: 1,
      termsDigest: String(repeating: "a", count: 64), metric: .steps,
      challengeWindow: challenge, realSourcePolicy: .appleWatchAutomaticStepsV1
    )
    let history = try ChallengeHealthWindow(
      startMicroseconds: 1_797_300_000_000_000,
      endMicroseconds: challenge.startMicroseconds,
      timeZoneIdentifier: "UTC", calendar: .gregorian
    )
    let read = try ChallengeHealthReadRequest(binding: binding, deviceRequestID: UUID(),
                                              queryWindow: history, purpose: .readinessHistory)
    let record = WeeklySourceRecord(
      id: UUID(), metric: .steps,
      start: Date(timeIntervalSince1970: 1_799_000_000),
      end: Date(timeIntervalSince1970: 1_799_000_060), value: 100,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1",
      wasUserEntered: false
    )
    let snapshot = ChallengeHealthSnapshot(request: read, records: [record],
                                           observedAt: Date(timeIntervalSince1970: 1_800_100_000),
                                           sourceFreshness: Date(timeIntervalSince1970: 1_800_100_000),
                                           evidence: .boundedSnapshot)
    let evaluation = ChallengeHealthAppleWatchStepsAdapter().evaluate(snapshot)
    #expect(evaluation.readiness == .ready)
    return try ChallengeHealthReadinessRequest(binding: binding, snapshot: snapshot,
                                               evaluation: evaluation, requestID: UUID())
  }

  func timedRequest() throws -> ChallengeHealthReadinessRequest {
    let challenge = try ChallengeHealthWindow(
      startMicroseconds: 1_800_000_000_000_000,
      endMicroseconds: 1_800_086_400_000_000,
      timeZoneIdentifier: "UTC", calendar: .gregorian
    )
    let binding = try ChallengeHealthBinding(
      actorID: actor, challengeID: UUID(), agreementVersion: 1,
      termsDigest: String(repeating: "a", count: 64), metric: .timedRunElapsedSeconds,
      challengeWindow: challenge, realSourcePolicy: .appleWorkoutOutdoorTimedV1,
      selectedDistanceMillimeters: 100
    )
    let history = try ChallengeHealthWindow(
      startMicroseconds: 1_792_224_000_000_000,
      endMicroseconds: challenge.startMicroseconds,
      timeZoneIdentifier: "UTC", calendar: .gregorian
    )
    let read = try ChallengeHealthReadRequest(binding: binding, deviceRequestID: UUID(),
                                              queryWindow: history, purpose: .readinessHistory)
    let record = WeeklySourceRecord(
      id: UUID(), metric: .runningDistanceMillimeters,
      start: Date(timeIntervalSince1970: 1_799_000_000),
      end: Date(timeIntervalSince1970: 1_799_000_060), value: 100,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1",
      wasUserEntered: false, workoutActivityType: "running", wasIndoorWorkout: false
    )
    let snapshot = ChallengeHealthSnapshot(request: read, records: [record],
                                           observedAt: Date(timeIntervalSince1970: 1_800_100_000),
                                           sourceFreshness: Date(timeIntervalSince1970: 1_800_100_000),
                                           evidence: .boundedSnapshot)
    let evaluation = ChallengeHealthAppleWorkoutTimedAdapter().evaluate(snapshot)
    #expect(evaluation.readiness == .ready)
    return try ChallengeHealthReadinessRequest(binding: binding, snapshot: snapshot,
                                               evaluation: evaluation, requestID: UUID())
  }

  func uploadRequest() throws -> ChallengeHealthUploadRequest {
    let window = try ChallengeHealthWindow(
      startMicroseconds: 1_800_000_000_000_000,
      endMicroseconds: 1_800_086_400_000_000,
      timeZoneIdentifier: "UTC", calendar: .gregorian
    )
    let binding = try ChallengeHealthBinding(
      actorID: actor, challengeID: UUID(), agreementVersion: 1,
      termsDigest: String(repeating: "a", count: 64), metric: .steps,
      challengeWindow: window, realSourcePolicy: .appleWatchAutomaticStepsV1
    )
    return try ChallengeHealthUploadRequest(
      binding: binding, requestID: UUID(), revision: 1, previousRevision: nil,
      replacement: .value(ChallengeHealthValue(metric: .steps, integerValue: 100)),
      observedAtMicroseconds: window.endMicroseconds, queriedThroughMicroseconds: window.endMicroseconds
    )
  }

  func store() -> ChallengeHealthReadinessFileStore {
    ChallengeHealthReadinessFileStore(
      directory: FileManager.default.temporaryDirectory.appendingPathComponent("p8-readiness-" + UUID().uuidString)
    )
  }
  func coordinator(_ readinessStore: ChallengeHealthReadinessFileStore) -> ChallengeHealthTransportCoordinator {
    ChallengeHealthTransportCoordinator(
      uploadStore: ChallengeHealthUploadFileStore(directory: readinessStore.directory.appendingPathComponent("upload")),
      readinessStore: readinessStore
    )
  }

  func material() -> MetricSignedMaterial {
    MetricSignedMaterial(keyID: Data(repeating: 1, count: 32).base64EncodedString(),
                         assertion: Data([1]), environment: .development)
  }

  func receipt(_ request: ChallengeHealthReadinessRequest) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "version": "challenge_real_health_readiness_receipt_v1",
      "request_id": request.requestID.uuidString.lowercased(),
      "accepted_at": "2026-09-20T00:00:00Z"
    ])
  }

  func uploadReceipt(_ request: ChallengeHealthUploadRequest) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
      "version": "challenge_real_health_receipt_v1",
      "request_id": request.requestID.uuidString.lowercased(),
      "challenge_id": request.challengeID.uuidString.lowercased(),
      "revision": request.revision,
      "accepted_at": "2026-09-20T00:00:00Z"
    ])
  }

  @Test("response loss keeps exact signed bytes for a disabled-gate retry")
  func lostResponseRecovery() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let request = try request(), session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    var original: ChallengeHealthSignedReadinessRequest?
    let first = ChallengeHealthReadinessClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in material() }, send: { signed, _ in
        original = signed; throw ChallengeHealthReadinessClientError.unavailable
      })
    await #expect(throws: ChallengeHealthReadinessClientError.unavailable) { try await first.submit(request) }
    #expect(try store.load(actor: actor).pending.count == 1)
    let relaunched = ChallengeHealthReadinessClient(environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in Issue.record("retry must not sign again"); return material() },
      send: { signed, _ in #expect(signed == original); return try receipt(request) })
    try await relaunched.retry(actor: actor)
    #expect(try store.load(actor: actor).pending.isEmpty)
  }

  @Test("a new readiness request drains an earlier durable assertion before signing")
  func newReadinessDrainsEarlierPendingRequestAfterRelaunch() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let firstRequest = try request(), secondRequest = try request()
    let session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    var firstSigned: ChallengeHealthSignedReadinessRequest?
    let interrupted = ChallengeHealthReadinessClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in material() }, send: { signed, _ in
        firstSigned = signed; throw ChallengeHealthReadinessClientError.unavailable
      })
    await #expect(throws: ChallengeHealthReadinessClientError.unavailable) { try await interrupted.submit(firstRequest) }
    let saved = try #require(firstSigned)

    var sent: [ChallengeHealthSignedReadinessRequest] = []
    var newSignedBodies: [Data] = []
    let relaunched = ChallengeHealthReadinessClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, body in newSignedBodies.append(body); return material() }, send: { signed, _ in
        sent.append(signed)
        if signed == saved { return try receipt(firstRequest) }
        return try receipt(secondRequest)
      })
    try await relaunched.submit(secondRequest)
    #expect(newSignedBodies == [secondRequest.exactBytes])
    #expect(sent.count == 2)
    #expect(sent[0] == saved)
    #expect(sent[1].exactBody == secondRequest.exactBytes)
    #expect(try store.load(actor: actor).pending.isEmpty)
  }

  @Test("a failed durable readiness request blocks signing a later request")
  func failedPendingReadinessBlocksLaterSigningAfterRelaunch() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let firstRequest = try request(), secondRequest = try request()
    let session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    var firstSigned: ChallengeHealthSignedReadinessRequest?
    let interrupted = ChallengeHealthReadinessClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in material() }, send: { signed, _ in
        firstSigned = signed; throw ChallengeHealthReadinessClientError.unavailable
      })
    await #expect(throws: ChallengeHealthReadinessClientError.unavailable) { try await interrupted.submit(firstRequest) }
    let saved = try #require(firstSigned)

    var signCount = 0
    var retried: ChallengeHealthSignedReadinessRequest?
    let relaunched = ChallengeHealthReadinessClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in signCount += 1; return material() }, send: { signed, _ in
        retried = signed; throw ChallengeHealthReadinessClientError.unavailable
      })
    await #expect(throws: ChallengeHealthReadinessClientError.unavailable) { try await relaunched.submit(secondRequest) }
    #expect(signCount == 0)
    #expect(retried == saved)
    #expect(try store.load(actor: actor).pending.map(\.exactBody) == [saved.exactBody])
  }

  @Test("a relaunch blocks new readiness signing while upload recovery is pending")
  func crossKindPendingBlocksNewSigningAfterRelaunch() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("p8-cross-kind-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let readinessStore = ChallengeHealthReadinessFileStore(directory: directory.appendingPathComponent("readiness"))
    let uploadStore = ChallengeHealthUploadFileStore(directory: directory.appendingPathComponent("upload"))
    let firstCoordinator = ChallengeHealthTransportCoordinator(uploadStore: uploadStore, readinessStore: readinessStore)
    let session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    let uploadRequest = try uploadRequest()
    let interrupted = ChallengeHealthUploadClient(enabled: true, environment: .development,
      coordinator: firstCoordinator, binding: { session }, sign: { _, _ in material() }, send: { _, _ in
        throw ChallengeHealthUploadClientError.unavailable
      })
    await #expect(throws: ChallengeHealthUploadClientError.unavailable) { try await interrupted.submit(uploadRequest) }
    #expect(try uploadStore.load(actor: actor).pending.count == 1)

    let relaunchedCoordinator = ChallengeHealthTransportCoordinator(uploadStore: uploadStore, readinessStore: readinessStore)
    var signCount = 0
    let readiness = ChallengeHealthReadinessClient(enabled: true, environment: .development,
      coordinator: relaunchedCoordinator, binding: { session }, sign: { _, _ in signCount += 1; return material() },
      send: { _, _ in Issue.record("peer pending must block before send"); return Data() })
    await #expect(throws: ChallengeHealthReadinessClientError.busy) { try await readiness.submit(request()) }
    #expect(signCount == 0)
  }

  @Test("a shared lease prevents concurrent empty-journal signers")
  func sharedLeaseFencesConcurrentSigning() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("p8-shared-lease-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let readinessStore = ChallengeHealthReadinessFileStore(directory: directory.appendingPathComponent("readiness"))
    let uploadStore = ChallengeHealthUploadFileStore(directory: directory.appendingPathComponent("upload"))
    let coordinator = ChallengeHealthTransportCoordinator(uploadStore: uploadStore, readinessStore: readinessStore)
    let session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    let uploadRequest = try uploadRequest(), readinessRequest = try request()
    let gate = ChallengeHealthSigningGate()
    let upload = ChallengeHealthUploadClient(enabled: true, environment: .development,
      coordinator: coordinator, binding: { session }, sign: { _, _ in
        await gate.suspend(); return material()
      }, send: { _, _ in try uploadReceipt(uploadRequest) })
    let readiness = ChallengeHealthReadinessClient(enabled: true, environment: .development,
      coordinator: coordinator, binding: { session }, sign: { _, _ in
        Issue.record("the held lease must block this signer"); return material()
      }, send: { _, _ in Issue.record("the held lease must block this sender"); return Data() })
    let first = Task { try await upload.submit(uploadRequest) }
    await gate.waitForSuspend()
    await #expect(throws: ChallengeHealthReadinessClientError.busy) { try await readiness.submit(readinessRequest) }
    gate.resume()
    try await first.value
  }

  @Test("a disabled client creates neither a signature nor a durable request")
  func disabled() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let client = ChallengeHealthReadinessClient(environment: .development, coordinator: coordinator(store),
      binding: { WeeklyClientSession(actorID: actor, identity: "fictional-session") },
      sign: { _, _ in Issue.record("disabled client cannot sign"); return material() },
      send: { _, _ in Issue.record("disabled client cannot send"); return Data() })
    await #expect(throws: ChallengeHealthReadinessClientError.unavailable) { try await client.submit(request()) }
    #expect(try store.load(actor: actor).pending.isEmpty)
  }

  @Test("a timed readiness relaunch preserves the canonical six-field body")
  func timedRelaunchPreservesCanonicalBody() async throws {
    let store = store(); defer { try? FileManager.default.removeItem(at: store.directory) }
    let request = try timedRequest(), session = WeeklyClientSession(actorID: actor, identity: "fictional-session")
    let first = ChallengeHealthReadinessClient(enabled: true, environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in material() }, send: { _, _ in
        throw ChallengeHealthReadinessClientError.unavailable
      })
    await #expect(throws: ChallengeHealthReadinessClientError.unavailable) { try await first.submit(request) }
    let saved = try #require(store.load(actor: actor).pending.first)
    let body = try JSONSerialization.jsonObject(with: saved.exactBody) as! [String: Any]
    #expect(Set(body.keys) == Set([
      "contract_version", "actor_id", "source_policy_version", "observed_at", "request_id", "distance_mm"
    ]))
    let relaunched = ChallengeHealthReadinessClient(environment: .development, coordinator: coordinator(store),
      binding: { session }, sign: { _, _ in Issue.record("relaunch must reuse the saved signature"); return material() },
      send: { signed, _ in
        #expect(signed.exactBody == saved.exactBody)
        return try receipt(request)
      })
    try await relaunched.retry(actor: actor)
    #expect(try store.load(actor: actor).pending.isEmpty)
  }
}

@MainActor
private final class ChallengeHealthSigningGate {
  private var waiter: CheckedContinuation<Void, Never>?
  private var started: CheckedContinuation<Void, Never>?

  func suspend() async {
    started?.resume(); started = nil
    await withCheckedContinuation { waiter = $0 }
  }

  func waitForSuspend() async {
    if waiter != nil { return }
    await withCheckedContinuation { started = $0 }
  }

  func resume() {
    waiter?.resume(); waiter = nil
  }
}
