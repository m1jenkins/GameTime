import Supabase
import XCTest
@testable import GameTime

/// Real local Auth, native stores and exact production HTTP transport. No hosted fallback.
@MainActor final class WeeklyNativeSmokeTests: XCTestCase {
    private struct Actor: Decodable { let id: UUID; let email: String }
    private struct Configuration: Decodable {
        struct History: Decodable { let noticeID: UUID; let reviewID: UUID; let finalID: UUID; let reviewRequestID: UUID; let reviewNoticeRevision: Int }
        let history: History
        let url: URL; let key: String; let controlToken: String; let actors: [Actor]; let cohortID: UUID
    }
    private struct State: Decodable {
        struct Trace: Decodable { let rpc: String; let requestID: UUID?; let payloadHash: String }
        let agreements: Int; let requests: Int; let admission: Bool; let allowlist: Int; let held: Bool; let trace: [Trace]
    }
    private var config: Configuration!

    func testAuthenticatedTwoAndFiveParticipantsCommunityAndExactRecovery() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = root.appendingPathComponent("tmp/weekly-native-smoke.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else { throw XCTSkip("Run scripts/weekly-native-smoke.py on disposable 5632x infrastructure first.") }
        config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: manifest))
        XCTAssertEqual(config.url.absoluteString, "http://127.0.0.1:56329")
        XCTAssertEqual(config.actors.count, 6)
        let sdk = SupabaseClient(supabaseURL: config.url, supabaseKey: config.key,
            options: .init(auth: .init(storage: WeeklySmokeSessionStorage(), autoRefreshToken: false, emitLocalSessionAsInitialSession: true)))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { if FileManager.default.fileExists(atPath: directory.path) { try? FileManager.default.removeItem(at: directory) } }
        let queue = FilePendingWeeklyRequestStore(directory: directory)
        let client = SupabaseWeeklyClient(client: sdk, enabled: true, localURL: config.url, publishableKey: config.key)
        let store = WeeklyStore(enabled: true, auth: SupabaseAuthClient(client: sdk), client: client,
            friendships: SupabaseFriendshipsClient(client: sdk), pendingStore: queue)
        try await switchActor(0, sdk, store)
        XCTAssertEqual(store.friends.count, 4)
        XCTAssertNil(store.errorMessage)
        for id in [config.history.noticeID, config.history.finalID] {
            let historical = try await client.detail(id: id, actorID: config.actors[0].id)
            XCTAssertFalse(historical.notices.isEmpty)
            XCTAssertEqual(historical.status, "final")
            XCTAssertNotNil(historical.result)
            XCTAssertNotNil(historical.allocation)
        }
        let inReview = try await client.detail(id: config.history.reviewID, actorID: config.actors[0].id)
        XCTAssertEqual(inReview.status, "review")
        XCTAssertFalse(inReview.notices.isEmpty)
        XCTAssertEqual(inReview.cases.count, 1)
        XCTAssertNil(inReview.result); XCTAssertNil(inReview.allocation)
        _ = try await control("finalize-history")
        let reviewed = try await client.detail(id: config.history.reviewID, actorID: config.actors[0].id)
        XCTAssertEqual(reviewed.status, "final")
        XCTAssertEqual(reviewed.cases.count, 1)
        XCTAssertEqual(reviewed.result?.qualification, .refund)
        _ = try await control("gate-off")
        let recoveredReview = try await client.submit(PendingWeeklyRequest(actorID: config.actors[0].id, requestID: config.history.reviewRequestID, operation: .review(config.history.reviewID, revision: config.history.reviewNoticeRevision, reason: .wrongTotal)))
        XCTAssertEqual(recoveredReview, reviewed.cases.first?.id)
        _ = try await control("gate-on")
        let draft = makeDraft(2)
        await store.preview(draft)
        let preview = try XCTUnwrap(store.previewed, store.errorMessage ?? "No server preview")
        _ = try await control("arm", ["rpc": "create_weekly_friend_v1", "mode": "lose"])
        await store.submit(.create(preview))
        let uncertain = try XCTUnwrap(store.pending, "Committed response loss must retain the exact request")
        XCTAssertTrue(uncertain.mayHaveCommitted)
        let afterLoss = try await control("gate-off")
        XCTAssertEqual(afterLoss.agreements, 4)
        try await switchActor(1, sdk, store)
        XCTAssertTrue(store.pending == nil)
        try await switchActor(0, sdk, store)
        XCTAssertTrue(store.pending == uncertain, "Recovered envelope must exactly match the actor-bound saved request")
        await store.retry()
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "No recovery")
        let pairID = try XCTUnwrap(store.lastConfirmedID)
        let pair = try XCTUnwrap(store.challenges.first(where: { $0.id == pairID }))
        XCTAssertEqual(pair.terms, preview.terms)
        XCTAssertEqual(pair.roster.count, 2)
        let recovered = try await control("state")
        XCTAssertEqual(recovered.agreements, 4)
        let copies = recovered.trace.filter { $0.rpc == "create_weekly_friend_v1" && $0.requestID == uncertain.requestID }
        XCTAssertEqual(copies.count, 2)
        XCTAssertEqual(Set(copies.map(\.payloadHash)).count, 1)

        _ = try await control("gate-on")
        _ = try await control("worker", ["challengeID": pairID.uuidString])
        try await switchActor(1, sdk, store)
        let invitation = try XCTUnwrap(store.challenges.first(where: { $0.id == pairID }))
        XCTAssertTrue(store.canAccept(pairID))
        XCTAssertTrue(invitation.roster.allSatisfy { $0.displayName != nil })
        await store.submit(.accept(pairID, digest: invitation.termsDigest))
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Pair acceptance")
        XCTAssertEqual(store.challenges.first(where: { $0.id == pairID })?.acceptedCount, 2)
        _ = try await control("gate-off")
        await store.refresh()
        await store.submit(.exit(pairID, kind: .withdrawal))
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Gate-off safe exit")
        XCTAssertEqual(store.challenges.first(where: { $0.id == pairID })?.exits.count, 1)

        _ = try await control("gate-on")
        try await switchActor(0, sdk, store)
        await store.preview(makeDraft(5))
        let groupPreview = try XCTUnwrap(store.previewed, store.errorMessage ?? "Five-person preview")
        await store.submit(.create(groupPreview))
        let groupID = try XCTUnwrap(store.lastConfirmedID, store.errorMessage ?? "Five-person creation")
        _ = try await control("worker", ["challengeID": groupID.uuidString])
        for index in 1..<5 {
            try await switchActor(index, sdk, store)
            let invitation = try XCTUnwrap(store.challenges.first(where: { $0.id == groupID }))
            XCTAssertEqual(invitation.roster.count, 5)
            XCTAssertEqual(invitation.terms.fields.participants?.count, 5)
            await store.submit(.accept(groupID, digest: invitation.termsDigest))
            XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Group acceptance")
        }
        let acceptedGroup = try XCTUnwrap(store.challenges.first(where: { $0.id == groupID }))
        XCTAssertEqual(acceptedGroup.acceptedCount, 5)

        // Owner offers display-only context; recipient must choose to follow.
        try await switchActor(0, sdk, store)
        await store.submit(.share(groupID, friendID: config.actors[1].id, enabled: true))
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Sharing offer")
        try await switchActor(1, sdk, store)
        XCTAssertTrue(store.sharedProgress.isEmpty)
        let offer = try XCTUnwrap(store.followRequests.first { $0.challengeID == groupID })
        await store.submit(.follow(groupID, ownerID: config.actors[0].id, offerID: offer.offerID, decision: .accept))
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Following consent")
        let shared = try XCTUnwrap(store.sharedProgress.first)
        XCTAssertNil(shared.observedSteps, "No observation must not become a zero")
        XCTAssertEqual(shared.source, "client_progress_only")
        _ = try await control("gate-off")
        await store.submit(.follow(groupID, ownerID: shared.ownerID, offerID: shared.offerID, decision: .unfollow))
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Gate-off unfollow")
        XCTAssertTrue(store.sharedProgress.isEmpty)
        _ = try await control("gate-on")

        // One later nonoverlapping community week can be chosen while this group is pending.
        try await switchActor(0, sdk, store)
        let cohort = try XCTUnwrap(store.cohorts.first(where: { $0.id == config.cohortID }))
        XCTAssertEqual(cohort.terms.fields.commonTargetSteps, 12000)
        await store.submit(.join(cohort.id, digest: cohort.termsDigest))
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Following-week community join")
        XCTAssertTrue(store.challenges.contains(where: { $0.id == groupID }))
        XCTAssertTrue(store.challenges.contains(where: { $0.id == cohort.id }))

        // The sixth actor has no friends and cannot inspect the private group.
        try await switchActor(5, sdk, store)
        XCTAssertTrue(store.friends.isEmpty)
        do { _ = try await client.detail(id: groupID, actorID: config.actors[5].id); XCTFail("Unrelated actor read a friend group") }
        catch { XCTAssertEqual(error as? WeeklyClientError, .accessDenied) }
        await store.submit(.join(cohort.id, digest: cohort.termsDigest))
        let solo = try XCTUnwrap(store.challenges.first(where: { $0.id == cohort.id }), store.errorMessage ?? "Solo community join")
        XCTAssertTrue(solo.roster.isEmpty)
        XCTAssertEqual(solo.own.targetSteps, 12000)
        XCTAssertNil(solo.terms.fields.participants)

        // A response held across a real account change cannot be published.
        _ = try await control("arm", ["rpc": "get_weekly_v1", "mode": "hold"])
        let late = Task { try await client.detail(id: cohort.id, actorID: config.actors[5].id) }
        try await waitHeld()
        try await switchActor(0, sdk, store)
        _ = try await control("release")
        do { _ = try await late.value; XCTFail("Late actor response was accepted") }
        catch { XCTAssertEqual(error as? WeeklyClientError, .accountChanged) }

        // Pause and gate closure preserve support and safe exits on the existing group.
        // This ambiguous request never reached the server; gate-off rejection
        // cannot authorize blindly deleting it. Atomic retirement fences it.
        await store.preview(makeDraft(2))
        let droppedPreview = try XCTUnwrap(store.previewed, store.errorMessage ?? "No-commit preview")
        _ = try await control("arm", ["rpc": "create_weekly_friend_v1", "mode": "drop"])
        await store.submit(.create(droppedPreview))
        let dropped = try XCTUnwrap(store.pending)
        _ = try await control("gate-off")
        await store.retry()
        XCTAssertEqual(store.pending?.requestID, dropped.requestID)
        await store.resolveSavedRequest()
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Atomic no-commit resolution")
        XCTAssertTrue(store.canExit(groupID))
        await store.submit(.pause(true))
        XCTAssertEqual(store.preferences?.paused, true)
        XCTAssertFalse(store.canEnter)
        _ = try await control("gate-off")
        await store.refresh()
        await store.submit(.support(groupID, reason: .exitHelp))
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Gate-off support")
        await store.submit(.exit(groupID, kind: .injury))
        XCTAssertTrue(store.pending == nil, store.errorMessage ?? "Gate-off injury exit")
        XCTAssertEqual(store.challenges.first(where: { $0.id == groupID })?.exits.first?.kind, "injury")
        let final = try await control("state")
        XCTAssertFalse(final.admission); XCTAssertEqual(final.allowlist, 0)
    }

    private func makeDraft(_ count: Int) -> WeeklyDraft {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let today = calendar.startOfDay(for: Date()), weekday = calendar.component(.weekday, from: Date())
        let delta = (9 - weekday) % 7
        let monday = calendar.date(byAdding: .day, value: delta == 0 ? 7 : delta, to: today)!
        let formatter = DateFormatter(); formatter.timeZone = calendar.timeZone; formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return WeeklyDraft(participants: config.actors.prefix(count).enumerated().map { .init(actorID: $0.element.id, targetSteps: 7000 + $0.offset * 700) }, weekStart: formatter.string(from: monday), timezone: "America/Chicago")
    }
    private func switchActor(_ index: Int, _ sdk: SupabaseClient, _ store: WeeklyStore) async throws {
        if sdk.auth.currentSession != nil { try await sdk.auth.signOut() }
        store.setActor(nil)
        XCTAssertTrue(store.challenges.isEmpty); XCTAssertNil(store.previewed); XCTAssertTrue(store.pending == nil)
        struct Token: Decodable { let tokenHash: String }
        var request = URLRequest(url: config.url.appendingPathComponent("__smoke/login-token"))
        request.httpMethod = "POST"; request.setValue(config.controlToken, forHTTPHeaderField: "X-Smoke-Token")
        request.httpBody = try JSONEncoder().encode(["actorID": config.actors[index].id.uuidString])
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        _ = try await sdk.auth.verifyOTP(tokenHash: JSONDecoder().decode(Token.self, from: data).tokenHash, type: .magiclink)
        XCTAssertEqual(sdk.auth.currentSession?.user.id, config.actors[index].id, "Local Auth must retain the verified session")
        store.setActor(config.actors[index].id)
        await store.refresh()
        XCTAssertNil(store.errorMessage)
    }
    private func control(_ action: String, _ body: [String: String] = [:]) async throws -> State {
        var request = URLRequest(url: config.url.appendingPathComponent("__smoke/" + action))
        request.httpMethod = "POST"; request.setValue(config.controlToken, forHTTPHeaderField: "X-Smoke-Token")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, action)
        return try JSONDecoder().decode(State.self, from: data)
    }
    private func waitHeld() async throws {
        for _ in 0..<200 {
            if try await control("state").held { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw WeeklyClientError.unavailable
    }
}
private final class WeeklySmokeSessionStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}
