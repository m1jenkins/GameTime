import Supabase
import SwiftUI
import XCTest
@testable import GameTime

/// Explicit local acceptance through real Auth sessions and the production RPC client.
/// Start scripts/performance-commitment-native-smoke.py first; no hosted fallback.
@MainActor
final class PerformanceCommitmentNativeSmokeTests: XCTestCase {
    private struct Actor: Decodable { let id: UUID; let email: String }
    private struct Configuration: Decodable {
        let url: URL; let key: String; let controlToken: String; let actors: [Actor]
    }
    private struct State: Decodable {
        struct Trace: Decodable { let rpc: String; let requestID: UUID?; let payloadHash: String }
        let agreements: Int; let requests: Int; let openSlots: Int
        let admission: Bool; let allowlist: Int; let held: Bool
        let lifecycleID: UUID?; let reviewCases: Int; let lifecycleGate: Bool; let attemptGate: Bool
        let trace: [Trace]
    }
    private var config: Configuration!

    func testAuthenticatedOwnerRecoveryAndLifecycle() async throws {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/performance-commitment-native-smoke.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw XCTSkip("Start the disposable local commitment smoke controller first.")
        }
        config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: manifest))
        XCTAssertEqual(config.url.absoluteString, "http://127.0.0.1:57329")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String, config.url.absoluteString)
        XCTAssertTrue(config.key.hasPrefix("sb_publishable_"))
        XCTAssertEqual(config.actors.count, 2)
        let a = config.actors[0], b = config.actors[1]
        let sdk = makeSDK(), reviewerSDK = makeSDK()
        _ = try await signIn(a, sdk: sdk)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = SupabaseAuthClient(client: sdk)
        let client = SupabasePerformanceCommitmentClient(client: sdk, enabled: true,
            localURL: config.url, publishableKey: config.key)
        let pendingStore = FilePendingPerformanceCommitmentRequestStore(directory: directory.appendingPathComponent("commitments"))
        let services = AppServices(auth: auth, profiles: SupabaseProfileClient(client: sdk),
            friendships: SupabaseFriendshipsClient(client: sdk), contests: SupabaseContestsClient(client: sdk),
            pendingChallenges: FilePendingChallengeStore(directoryURL: directory.appendingPathComponent("legacy")),
            activitySync: DisabledActivitySyncCoordinator(), performanceCommitments: client,
            pendingPerformanceCommitments: pendingStore)
        let model = AppModel(configuration: AppConfiguration(environment: .debug, supabaseURL: config.url,
            supabasePublishableKey: config.key, contestMutationsEnabled: false,
            performanceCommitmentRequested: true), services: services)
        await model.start()
        XCTAssertEqual(model.userID, a.id)
        let store = model.performanceCommitments
        await store.refresh()
        XCTAssertNil(store.errorMessage)
        XCTAssertTrue(store.agreements.isEmpty)
        let start = Date().addingTimeInterval(2 * 86400)
        let draft = PerformanceCommitmentDraft(targetSeconds: 1500,
            startsAt: PerformanceCommitmentInstant(date: start),
            deadlineAt: PerformanceCommitmentInstant(date: start.addingTimeInterval(28 * 86400)),
            displayTimezone: "America/Chicago")
        await store.preview(draft)
        let preview = try XCTUnwrap(store.previewedTerms, store.errorMessage ?? "No preview")
        let create = PerformanceCommitmentMutation.create(draft: draft, termsDigest: preview.termsDigest, consent: true)
        await store.submit(create)
        let firstID = try XCTUnwrap(store.lastConfirmedID, store.errorMessage ?? "No creation receipt")
        let first = try XCTUnwrap(store.agreements.first { $0.id == firstID })
        XCTAssertEqual(first.terms, preview.terms)
        XCTAssertEqual(first.consent.termsDigest, preview.termsDigest)
        XCTAssertNil(store.lifecycles[firstID]?.finalResult)
        try await capture(model, id: firstID, name: "commitment-http-created")

        // The other account cannot read private agreement or lifecycle data.
        try await switchActor(to: b, sdk: sdk, model: model)
        await store.refresh()
        XCTAssertTrue(store.agreements.isEmpty)
        do { _ = try await client.detail(id: firstID, actorID: b.id); XCTFail("Foreign owner read succeeded") }
        catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .accessDenied) }
        do { _ = try await client.lifecycle(id: firstID, actorID: b.id); XCTFail("Foreign lifecycle read succeeded") }
        catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .accessDenied) }
        try await switchActor(to: a, sdk: sdk, model: model)
        await store.refresh()

        // A real database response held across account change must never publish.
        _ = try await control("arm", ["rpc": "get_performance_commitment_v1", "mode": "hold"])
        let adapterRead = Task { try await client.detail(id: firstID, actorID: a.id) }
        try await waitForHeldResponse()
        try await switchActor(to: b, sdk: sdk, model: model)
        _ = try await control("release")
        do { _ = try await adapterRead.value; XCTFail("Late adapter response accepted") }
        catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .accountChanged) }
        assertCleared(store)
        try await switchActor(to: a, sdk: sdk, model: model)
        await store.refresh()
        _ = try await control("arm", ["rpc": "get_commitment_lifecycle_v1", "mode": "hold"])
        let storeRead = Task { await store.refreshDetail(firstID) }
        try await waitForHeldResponse()
        try await switchActor(to: b, sdk: sdk, model: model)
        _ = try await control("release")
        await storeRead.value
        assertCleared(store)
        try await switchActor(to: a, sdk: sdk, model: model)
        _ = try await control("gate-off")
        await store.refresh()
        await store.submit(.close(commitmentID: firstID, reason: .cancel))
        XCTAssertEqual(store.agreements.first { $0.id == firstID }?.closeReason, .cancel)
        let zeroSlots = try await control("state").openSlots
        XCTAssertEqual(zeroSlots, 0)

        // Lose a committed create response, relaunch durable recovery under the
        // original owner with admission off, and prove there is one agreement.
        _ = try await control("gate-on")
        await store.preview(draft)
        _ = try await control("arm", ["rpc": "create_performance_commitment_v1", "mode": "lose"])
        await store.submit(create)
        let saved = try XCTUnwrap(store.pending, store.errorMessage ?? "No saved create")
        XCTAssertTrue(saved.mayHaveCommitted)
        let afterLoss = try await control("gate-off")
        XCTAssertEqual(afterLoss.agreements, 2)
        try await switchActor(to: b, sdk: sdk, model: model)
        await store.refresh()
        XCTAssertNil(store.pending)
        XCTAssertTrue(store.agreements.isEmpty)
        try await switchActor(to: a, sdk: sdk, model: model)
        let recovered = PerformanceCommitmentStore(enabled: true, auth: auth, client: client, pendingStore: pendingStore)
        recovered.setActor(a.id)
        await recovered.refresh()
        XCTAssertEqual(recovered.pending, saved)
        await recovered.retry()
        let secondID = try XCTUnwrap(recovered.lastConfirmedID, recovered.errorMessage ?? "Recovery failed")
        XCTAssertNil(recovered.pending)
        let recoveredCount = try await control("state").agreements
        XCTAssertEqual(recoveredCount, 2)
        await recovered.submit(.close(commitmentID: secondID, reason: .cancel))
        let recoveredSlots = try await control("state").openSlots
        XCTAssertEqual(recoveredSlots, 0)

        // SQL clock seams seed fictional organizer proof; native actions still
        // use current authenticated public RPCs and no injected client clock.
        _ = try await signIn(b, sdk: reviewerSDK)
        let seeded = try await control("lifecycle-seed")
        let lifecycleID = try XCTUnwrap(seeded.lifecycleID)
        XCTAssertFalse(seeded.lifecycleGate)
        XCTAssertFalse(seeded.attemptGate)
        await store.refresh()
        let notice = try XCTUnwrap(store.lifecycles[lifecycleID]?.latestNotice, store.errorMessage ?? "No notice")
        XCTAssertEqual(notice.proofRevision, 1)
        XCTAssertEqual(notice.outcome.kind, "success")
        XCTAssertTrue(notice.canFileReview)
        _ = try await control("arm", ["rpc": "file_commitment_review_v1", "mode": "lose"])
        await store.submit(.fileReview(commitmentID: lifecycleID, revision: notice.proofRevision, reason: .wrongResult))
        let savedReview = try XCTUnwrap(store.pending)
        XCTAssertTrue(savedReview.mayHaveCommitted)
        let lostCaseCount = try await control("state").reviewCases
        XCTAssertEqual(lostCaseCount, 1)
        await store.retry()
        XCTAssertNil(store.pending, store.errorMessage ?? "Review recovery failed")
        XCTAssertEqual(store.lifecycles[lifecycleID]?.reviews.count, 1)
        let recoveredCaseCount = try await control("state").reviewCases
        XCTAssertEqual(recoveredCaseCount, 1)
        _ = try await control("lifecycle-correct")
        await store.refreshDetail(lifecycleID)
        XCTAssertEqual(store.lifecycles[lifecycleID]?.notices.count, 2)
        XCTAssertEqual(store.lifecycles[lifecycleID]?.notices.first?.recordedAt, notice.recordedAt)
        XCTAssertEqual(store.lifecycles[lifecycleID]?.latestNotice?.proofRevision, 2)
        XCTAssertEqual(store.lifecycles[lifecycleID]?.reviews.count, 1)
        try await capture(model, id: lifecycleID, name: "commitment-http-correction-and-review")

        // An injury exit is still available with admission off. Final result
        // and simulated returned amount arrive in distinct transactions.
        await store.submit(.close(commitmentID: lifecycleID, reason: .injury))
        XCTAssertEqual(store.lifecycles[lifecycleID]?.closure?.reason, .injury)
        _ = try await control("lifecycle-final")
        await store.refreshDetail(lifecycleID)
        let final = try XCTUnwrap(store.lifecycles[lifecycleID]?.finalResult, store.errorMessage ?? "No final")
        XCTAssertEqual(final.outcome.reason, "injury")
        XCTAssertNil(store.lifecycles[lifecycleID]?.simulation)
        try await capture(model, id: lifecycleID, name: "commitment-http-final-before-simulation")
        _ = try await control("lifecycle-settle")
        await store.refreshDetail(lifecycleID)
        XCTAssertEqual(store.lifecycles[lifecycleID]?.finalResult, final)
        XCTAssertEqual(store.lifecycles[lifecycleID]?.simulation?.returnedCents, 2000)
        XCTAssertEqual(store.lifecycles[lifecycleID]?.simulation?.lostCents, 0)
        let finalReviewReceipt = try await client.submit(savedReview)
        XCTAssertEqual(finalReviewReceipt, .review(PerformanceCommitmentReviewReceipt(
            caseID: try XCTUnwrap(store.lifecycles[lifecycleID]?.reviews.first?.caseID),
            recordedAt: try XCTUnwrap(store.lifecycles[lifecycleID]?.reviews.first?.filedAt))))
        try await capture(model, id: lifecycleID, name: "commitment-http-simulated-return")

        // Revocation rejects exact recovery and clears previously read history.
        _ = try await control("revoke-sessions", ["actorID": a.id.uuidString])
        do { _ = try await client.submit(savedReview); XCTFail("Revoked session recovered a request") }
        catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .accessDenied) }
        await store.refreshDetail(lifecycleID)
        assertCleared(store, includingError: false)
        let end = try await control("state")
        XCTAssertEqual(end.openSlots, 0)
        XCTAssertFalse(end.admission)
        XCTAssertFalse(end.lifecycleGate)
        XCTAssertFalse(end.attemptGate)
        for request in [saved, savedReview] {
            let transmissions = end.trace.filter { $0.requestID == request.requestID }
            XCTAssertGreaterThanOrEqual(transmissions.count, 2)
            XCTAssertEqual(Set(transmissions.map(\.payloadHash)).count, 1,
                           "Exact recovery must resend identical request bytes")
        }
        try await reviewerSDK.auth.signOut()
        await model.signOut()
    }

    private func makeSDK() -> SupabaseClient {
        SupabaseClient(supabaseURL: config.url, supabaseKey: config.key,
            options: .init(auth: .init(storage: CommitmentSmokeSessionStorage(), autoRefreshToken: false,
                                      emitLocalSessionAsInitialSession: true)))
    }
    private func switchActor(to actor: Actor, sdk: SupabaseClient, model: AppModel) async throws {
        await model.signOut()
        assertCleared(model.performanceCommitments)
        _ = try await signIn(actor, sdk: sdk)
        for _ in 0..<200 {
            if model.userID == actor.id && model.phase == .signedIn { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(model.userID, actor.id)
        XCTAssertEqual(model.performanceCommitments.actorID, actor.id)
        assertCleared(model.performanceCommitments)
    }
    private func assertCleared(_ store: PerformanceCommitmentStore, includingError: Bool = true,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(store.agreements.isEmpty, file: file, line: line)
        XCTAssertTrue(store.lifecycles.isEmpty, file: file, line: line)
        XCTAssertTrue(store.freshIDs.isEmpty, file: file, line: line)
        XCTAssertNil(store.previewedTerms, file: file, line: line)
        XCTAssertNil(store.lastConfirmedID, file: file, line: line)
        if includingError { XCTAssertNil(store.errorMessage, file: file, line: line) }
    }
    private func control(_ action: String, _ body: [String: String] = [:]) async throws -> State {
        var request = URLRequest(url: config.url.appendingPathComponent("__smoke/" + action))
        request.httpMethod = "POST"
        request.setValue(config.controlToken, forHTTPHeaderField: "X-Smoke-Token")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, action)
        return try JSONDecoder().decode(State.self, from: data)
    }
    private func signIn(_ actor: Actor, sdk: SupabaseClient) async throws -> Session {
        struct LoginToken: Decodable { let tokenHash: String }
        var request = URLRequest(url: config.url.appendingPathComponent("__smoke/login-token"))
        request.httpMethod = "POST"
        request.setValue(config.controlToken, forHTTPHeaderField: "X-Smoke-Token")
        request.httpBody = try JSONEncoder().encode(["actorID": actor.id.uuidString])
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        let token = try JSONDecoder().decode(LoginToken.self, from: data)
        _ = try await sdk.auth.verifyOTP(tokenHash: token.tokenHash, type: .magiclink)
        return try await sdk.auth.session
    }
    private func waitForHeldResponse() async throws {
        for _ in 0..<200 {
            if try await control("state").held { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw PerformanceCommitmentClientError.unavailable
    }
    private func capture(_ model: AppModel, id: UUID, name: String) async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let previous = scene.windows.first { $0.isKeyWindow }
        window.rootViewController = UIHostingController(rootView:
            NavigationStack { PerformanceCommitmentDetailView(commitmentID: id) }.environment(model))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(350))
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: screenshot)
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}

private final class CommitmentSmokeSessionStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}
