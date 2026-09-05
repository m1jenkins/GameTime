import Supabase
import SwiftUI
import XCTest
@testable import GameTime

/// Opt-in simulator acceptance using real GoTrue sessions and PostgREST HTTP.
/// No fixture clients, injected RPC closures, privileged mobile key, or Apple login.
/// Start scripts/duel-native-local-smoke.py first; otherwise this test is skipped.
@MainActor
final class DuelNativeLocalSmokeTests: XCTestCase {
    private struct Actor: Decodable { let id: UUID; let email: String }
    private struct Configuration: Decodable {
        let url: URL
        let key: String
        let controlToken: String
        let actors: [Actor]
        let eventID: UUID
    }
    private struct State: Decodable {
        let agreements: Int
        let requests: Int
        let consents: Int
        let openSlots: Int
        let admission: Bool
        let allowlist: Int
        let held: Bool
        let lifecycleID: UUID?
        let reviewCases: Int
        let lifecycleGate: Bool
    }
    private var config: Configuration!

    func testAuthenticatedTwoAccountAgreementRecoveryAndGateOff() async throws {
        let manifest = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("tmp/duel-native-smoke.json")
        guard FileManager.default.fileExists(atPath: manifest.path) else {
            throw XCTSkip("Start the disposable local native smoke controller first.")
        }
        config = try JSONDecoder().decode(Configuration.self, from: Data(contentsOf: manifest))
        XCTAssertEqual(config.url.absoluteString, "http://127.0.0.1:54329")
        XCTAssertEqual(config.actors.count, 2)
        XCTAssertTrue(config.key.hasPrefix("sb_publishable_"))
        XCTAssertFalse(ProcessInfo.processInfo.arguments.contains("--fixture-mode"))
        // Also keep the test host's ordinary app services on loopback.
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String,
                       config.url.absoluteString)
        let initial = try await control("state")
        XCTAssertEqual(initial.agreements, 0)
        XCTAssertTrue(initial.admission)
        XCTAssertEqual(initial.allowlist, 2)

        let a = config.actors[0], b = config.actors[1]
        let sdk = makeSDK()
        let otherSDK = makeSDK()
        let aSession = try await signIn(a, sdk: sdk)
        let bSession = try await signIn(b, sdk: otherSDK)
        XCTAssertEqual(aSession.user.id, a.id)
        XCTAssertEqual(bSession.user.id, b.id)
        XCTAssertNotEqual(aSession.accessToken, bSession.accessToken)

        // Establish the accepted friendship through the actual native client.
        let friends = SupabaseFriendshipsClient(client: sdk)
        try await friends.requestFriendship(callerID: a.id, otherUserID: b.id)
        try await SupabaseFriendshipsClient(client: otherSDK)
            .acceptFriendship(callerID: b.id, otherUserID: a.id)
        try await otherSDK.auth.signOut()

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = SupabaseAuthClient(client: sdk)
        let client = SupabaseDuelClient(client: sdk, enabled: true)
        let settings = AppConfiguration(environment: .debug, supabaseURL: config.url,
            supabasePublishableKey: config.key, contestMutationsEnabled: true, duelRequested: true)
        let services = AppServices(auth: auth, profiles: SupabaseProfileClient(client: sdk),
            friendships: friends, contests: SupabaseContestsClient(client: sdk),
            pendingChallenges: FilePendingChallengeStore(directoryURL: directory.appendingPathComponent("legacy")),
            activitySync: DisabledActivitySyncCoordinator(), duels: client,
            pendingDuels: FilePendingDuelRequestStore(directory: directory.appendingPathComponent("duels")))
        let model = AppModel(configuration: settings, services: services)
        await model.start()
        XCTAssertEqual(model.phase, .signedIn)
        let store = model.duels
        await store.refresh()
        XCTAssertNil(store.errorMessage)
        XCTAssertEqual(store.friends.map(\.otherUserID), [b.id])
        let event = try XCTUnwrap(store.catalog.events.first { $0.id == config.eventID })
        XCTAssertTrue(event.isAvailable(at: Date()))
        XCTAssertGreaterThan(event.startsAt, Date().addingTimeInterval(24 * 3600))
        let create = DuelMutation.create(inviteeID: b.id, eventID: event.id,
                                         policyVersion: event.policyVersion, consent: true)

        // A explicitly agrees and receives the same confirmation ID the receipt uses.
        await store.submit(create)
        let firstID = try XCTUnwrap(store.lastConfirmedID, store.errorMessage ?? "Creator receipt missing")
        let invitation = try XCTUnwrap(store.agreements.first { $0.id == firstID })
        XCTAssertEqual(invitation.status, .invited)
        XCTAssertNil(store.pending)
        XCTAssertEqual(invitation.participants.filter { $0.acceptedAt != nil }.count, 1)
        try await capture(model, id: firstID, name: "native-http-actor-a-confirmed-invitation")

        try await switchActor(to: b, sdk: sdk, model: model)
        await store.refresh()
        let incoming = try XCTUnwrap(store.agreements.first { $0.id == firstID })
        XCTAssertEqual(incoming.terms, invitation.terms)
        XCTAssertEqual(incoming.termsDigest, invitation.termsDigest)
        XCTAssertEqual(incoming.participants, invitation.participants)
        XCTAssertTrue(incoming.canAccept(actorID: b.id, now: Date()))
        // Reading and refreshing must not consent on the invitee's behalf.
        XCTAssertNil(incoming.participants.first { $0.actorID == b.id }?.acceptedAt)
        try await capture(model, id: firstID, name: "native-http-actor-b-before-explicit-consent")
        let accept = DuelMutation.accept(challengeID: firstID,
            policyVersion: incoming.policyVersion, termsDigest: incoming.termsDigest)
        await store.submit(accept)
        let scheduled = try XCTUnwrap(store.agreements.first { $0.id == firstID })
        XCTAssertEqual(store.lastConfirmedID, firstID)
        XCTAssertEqual(scheduled.status, .scheduled)
        assertConsents(scheduled)
        try await capture(model, id: firstID, name: "native-http-actor-b-scheduled")
        try await switchActor(to: a, sdk: sdk, model: model)
        await store.refresh()
        let creatorScheduled = try XCTUnwrap(store.agreements.first { $0.id == firstID })
        XCTAssertEqual(creatorScheduled.terms, scheduled.terms)
        XCTAssertEqual(creatorScheduled.participants, scheduled.participants)
        XCTAssertEqual(creatorScheduled.status, .scheduled)
        try await capture(model, id: firstID, name: "native-http-actor-a-scheduled")

        // Hold a real HTTP response after PostgreSQL read it, then change account.
        _ = try await control("arm", ["rpc": "get_duel_v1", "mode": "hold"])
        let staleAdapterRead = Task { try await client.detail(id: firstID, actorID: a.id) }
        try await waitForHeldResponse()
        try await switchActor(to: b, sdk: sdk, model: model)
        _ = try await control("release")
        do {
            _ = try await staleAdapterRead.value
            XCTFail("Production RPC client accepted a response for the previous actor")
        } catch { XCTAssertEqual(error as? DuelClientError, .accountChanged) }
        XCTAssertTrue(store.agreements.isEmpty)
        await store.refresh()
        _ = try await control("arm", ["rpc": "get_duel_v1", "mode": "hold"])
        let staleStoreRead = Task { await store.refreshDetail(firstID) }
        try await waitForHeldResponse()
        try await switchActor(to: a, sdk: sdk, model: model)
        _ = try await control("release")
        await staleStoreRead.value
        assertPrivateStateCleared(store)

        // Gate-off must preserve history and allow either accepted runner to cancel.
        _ = try await control("gate-off")
        await store.refresh()
        XCTAssertEqual(store.agreements.first?.status, .scheduled)
        await store.submit(create)
        XCTAssertEqual(store.errorMessage, DuelClientError.accessDenied.localizedDescription)
        XCTAssertNil(store.pending)
        await store.refreshDetail(firstID)
        await store.submit(.cancel(challengeID: firstID))
        XCTAssertEqual(store.agreements.first { $0.id == firstID }?.status, .cancelled)
        var state = try await control("state")
        XCTAssertEqual(state.requests, 3)
        XCTAssertEqual(state.openSlots, 0)

        // Lose a committed creation at the HTTP boundary, then reconstruct the
        // native store from the protected file, across accounts and gate-off.
        _ = try await control("gate-on")
        await store.refresh()
        _ = try await control("arm", ["rpc": "create_duel_v1", "mode": "lose"])
        await store.submit(create)
        let savedCreate = try XCTUnwrap(store.pending)
        XCTAssertTrue(savedCreate.mayHaveCommitted)
        XCTAssertNil(store.lastConfirmedID)
        state = try await control("gate-off")
        XCTAssertEqual(state.agreements, 2)
        XCTAssertEqual(state.requests, 4)
        try await switchActor(to: b, sdk: sdk, model: model)
        await store.refresh()
        XCTAssertNil(store.pending, "B must never load A's durable request")
        await store.retry()
        let pendingInvitation = try XCTUnwrap(store.agreements.first { $0.status == .invited })
        let secondAccept = DuelMutation.accept(challengeID: pendingInvitation.id,
            policyVersion: pendingInvitation.policyVersion, termsDigest: pendingInvitation.termsDigest)
        await store.submit(secondAccept)
        XCTAssertEqual(store.errorMessage, DuelClientError.accessDenied.localizedDescription)
        XCTAssertNil(store.pending)
        state = try await control("state")
        XCTAssertEqual(state.requests, 4, "Gate-off acceptance must not mutate")
        XCTAssertEqual(state.consents, 3)

        try await switchActor(to: a, sdk: sdk, model: model)
        let recovered = DuelStore(enabled: true, auth: auth, client: client, friendships: friends,
            pendingStore: FilePendingDuelRequestStore(directory: directory.appendingPathComponent("duels")))
        recovered.setActor(a.id)
        await recovered.refresh()
        XCTAssertEqual(recovered.pending, savedCreate)
        state = try await control("state")
        XCTAssertEqual(state.requests, 4, "Refresh cannot replay the saved request")
        await recovered.retry()
        XCTAssertEqual(recovered.lastConfirmedID, pendingInvitation.id)
        XCTAssertNil(recovered.pending)
        let replayedID = try await client.submit(savedCreate)
        XCTAssertEqual(replayedID, pendingInvitation.id)
        state = try await control("state")
        XCTAssertEqual(state.agreements, 2)
        XCTAssertEqual(state.requests, 4)

        // Lose B's explicit acceptance too; committed recovery still works gate-off.
        _ = try await control("gate-on")
        try await switchActor(to: b, sdk: sdk, model: model)
        await store.refresh()
        _ = try await control("arm", ["rpc": "accept_duel_v1", "mode": "lose"])
        await store.submit(secondAccept)
        let savedAccept = try XCTUnwrap(store.pending)
        state = try await control("gate-off")
        XCTAssertEqual(state.requests, 5)
        XCTAssertEqual(state.consents, 4)
        await store.refresh()
        XCTAssertEqual(store.pending, savedAccept)
        XCTAssertEqual(store.agreements.first { $0.id == pendingInvitation.id }?.status, .scheduled)
        await store.retry()
        XCTAssertNil(store.pending)
        XCTAssertEqual(store.lastConfirmedID, pendingInvitation.id)
        let acceptedAgain = try await client.submit(savedAccept)
        XCTAssertEqual(acceptedAgain, pendingInvitation.id)
        // Same key with different exact parameters fails even after commitment.
        let changed = try PendingDuelRequest(actorID: b.id, requestID: savedAccept.requestID,
            operation: .accept(challengeID: pendingInvitation.id, policyVersion: pendingInvitation.policyVersion,
                               termsDigest: String(repeating: "0", count: 64)))
        do { _ = try await client.submit(changed); XCTFail("Changed payload reused an exact request") }
        catch { XCTAssertEqual(error as? DuelClientError, .invalidTerms) }
        state = try await control("state")
        XCTAssertEqual(state.agreements, 2)
        XCTAssertEqual(state.requests, 5)
        XCTAssertEqual(state.consents, 4)

        await store.submit(.cancel(challengeID: pendingInvitation.id))
        XCTAssertEqual(store.agreements.first { $0.id == pendingInvitation.id }?.status, .cancelled)
        assertConsents(try XCTUnwrap(store.agreements.first { $0.id == pendingInvitation.id }))
        try await switchActor(to: a, sdk: sdk, model: model)
        await store.refresh()
        XCTAssertEqual(store.agreements.count, 2)
        XCTAssertTrue(store.agreements.allSatisfy { $0.status == .cancelled })
        XCTAssertEqual(store.agreements.first { $0.id == pendingInvitation.id }?.terms, pendingInvitation.terms)
        try await capture(model, id: pendingInvitation.id, name: "native-http-gate-off-cancelled-history")
        state = try await control("state")
        XCTAssertFalse(state.admission)
        XCTAssertEqual(state.allowlist, 0)
        XCTAssertEqual(state.openSlots, 0)
        XCTAssertEqual(state.requests, 6)

        // Phase 2(d): a fictional historical agreement has a real, recent
        // durable missing-result notice. All participant actions below use
        // the production client, store, file envelope and real Auth session.
        state = try await control("lifecycle-seed")
        let lifecycleID = try XCTUnwrap(state.lifecycleID)
        XCTAssertFalse(state.admission)
        XCTAssertFalse(state.lifecycleGate)
        await store.refresh()
        let initialLife = try XCTUnwrap(store.lifecycles[lifecycleID])
        XCTAssertEqual(initialLife.notices.count, 1)
        XCTAssertTrue(store.canFileReview(lifecycleID, revision: 0))
        XCTAssertTrue(initialLife.reviews.isEmpty)
        XCTAssertNil(initialLife.finalResult)
        try await capture(model, id: lifecycleID, name: "native-http-saved-notice")
        _ = try await control("arm", ["rpc": "file_duel_review_v1", "mode": "lose"])
        await store.submit(.fileReview(challengeID: lifecycleID, revision: 0, reason: .missingResult))
        let savedReview = try XCTUnwrap(store.pending)
        XCTAssertTrue(savedReview.mayHaveCommitted)
        state = try await control("state")
        XCTAssertEqual(state.reviewCases, 1)
        try await switchActor(to: b, sdk: sdk, model: model)
        await store.refresh()
        XCTAssertTrue(try XCTUnwrap(store.lifecycles[lifecycleID]).reviews.isEmpty)
        XCTAssertNil(store.pending)
        try await switchActor(to: a, sdk: sdk, model: model)
        let restored = DuelStore(enabled: true, auth: auth, client: client, friendships: friends,
            pendingStore: FilePendingDuelRequestStore(directory: directory.appendingPathComponent("duels")))
        restored.setActor(a.id)
        await restored.refresh()
        XCTAssertEqual(restored.pending, savedReview)
        XCTAssertEqual(restored.lifecycles[lifecycleID]?.reviews.count, 1)
        await restored.retry()
        XCTAssertNil(restored.pending)
        XCTAssertEqual(restored.lastConfirmedID, lifecycleID)
        let reviewReceipt = try await client.submit(savedReview)
        XCTAssertEqual(reviewReceipt, restored.lifecycles[lifecycleID]?.reviews.first?.id)
        let conflict = try PendingDuelRequest(actorID: a.id, requestID: savedReview.requestID,
            operation: .fileReview(challengeID: lifecycleID, revision: 0, reason: .wrongIdentity))
        do { _ = try await client.submit(conflict); XCTFail("Changed review payload accepted") }
        catch { XCTAssertEqual(error as? DuelClientError, .invalidTerms) }
        _ = try await control("lifecycle-block")
        await store.refresh()
        XCTAssertTrue(try XCTUnwrap(store.lifecycles[lifecycleID]).contactSuppressed)
        XCTAssertEqual(store.lifecycles[lifecycleID]?.notices, [])
        XCTAssertEqual(store.lifecycles[lifecycleID]?.reviews.count, 1)
        _ = try await control("arm", ["rpc": "exit_duel_v1", "mode": "lose"])
        await store.submit(.exit(challengeID: lifecycleID, kind: .injury))
        let savedExit = try XCTUnwrap(store.pending)
        await store.refresh()
        XCTAssertEqual(store.pending, savedExit)
        XCTAssertEqual(store.lifecycles[lifecycleID]?.closure?.kind, "injury")
        await store.retry()
        XCTAssertNil(store.pending)
        XCTAssertFalse(store.canExit(lifecycleID))
        let exitReceipt = try await client.submit(savedExit)
        XCTAssertEqual(exitReceipt, lifecycleID)
        try await capture(model, id: lifecycleID, name: "native-http-blocked-own-review-and-exit")
        _ = try await control("lifecycle-worker")
        await store.refreshDetail(lifecycleID)
        XCTAssertNil(store.lifecycles[lifecycleID]?.finalResult, "Blocked shared outcome stays hidden")
        XCTAssertEqual(store.lifecycles[lifecycleID]?.simulatedReturnCents, 2000)
        state = try await control("state")
        XCTAssertEqual(state.reviewCases, 1)
        XCTAssertEqual(state.openSlots, 0)
        XCTAssertFalse(state.admission)
        XCTAssertFalse(state.lifecycleGate)
        try await capture(model, id: lifecycleID, name: "native-http-blocked-own-simulated-return")
        // Phase 2(e): new consent/event, durable rematch recovery, and real
        // target-bound link reads. Restoring this fictional friendship is a
        // controller-owned setup action, never an automatic product unblock.
        _ = try await control("lifecycle-unblock")
        _ = try await control("gate-on")
        await store.refresh()
        let previous = try XCTUnwrap(store.agreements.first { $0.id == lifecycleID })
        XCTAssertTrue(store.canRematch(lifecycleID))
        _ = try await control("arm", ["rpc": "rematch_duel_v1", "mode": "lose"])
        await store.submit(.rematch(previousID: lifecycleID, eventID: config.eventID,
            policyVersion: event.policyVersion, consent: true))
        let savedRematch = try XCTUnwrap(store.pending, store.errorMessage ?? "Missing rematch request")
        _ = try await control("gate-off")
        await store.retry()
        let rematchID = try XCTUnwrap(store.lastConfirmedID, store.errorMessage ?? "Missing rematch receipt")
        XCTAssertNotEqual(rematchID, lifecycleID)
        XCTAssertNil(store.pending)
        let rematch = try XCTUnwrap(store.agreements.first { $0.id == rematchID })
        XCTAssertNotEqual(rematch.eventID, previous.eventID)
        XCTAssertNotEqual(rematch.termsDigest, previous.termsDigest)
        XCTAssertEqual(rematch.participants.filter { $0.acceptedAt != nil }.count, 1)
        let recoveredRematch = try await client.submit(savedRematch)
        XCTAssertEqual(recoveredRematch, rematchID)
        _ = try await control("gate-on")
        _ = try await control("arm", ["rpc": "issue_duel_link_v1", "mode": "lose"])
        await store.submit(.issueLink(challengeID: rematchID))
        let savedLink = try XCTUnwrap(store.pending)
        _ = try await control("gate-off")
        await store.retry()
        let link = try XCTUnwrap(store.invitationLinks[rematchID], store.errorMessage ?? "Missing link")
        XCTAssertNil(store.pending)
        await model.signOut()
        store.receiveInvitation(link.url)
        XCTAssertEqual(store.pendingInvitationToken, link.token)
        try await switchActor(to: b, sdk: sdk, model: model)
        await store.openPendingInvitation()
        XCTAssertEqual(store.resolvedInvitationID, rematchID, store.invitationError ?? "Missing destination")
        XCTAssertEqual(store.agreements.first { $0.id == rematchID }?.status, .invited)
        XCTAssertNil(store.agreements.first { $0.id == rematchID }?.participants.first { $0.actorID == b.id }?.acceptedAt)
        try await capture(model, id: rematchID, name: "native-http-rematch-link-before-consent")
        try await switchActor(to: a, sdk: sdk, model: model)
        await store.refresh()
        await store.submit(.revokeLink(challengeID: rematchID, token: link.token))
        let replayedLink = try await client.submit(savedLink)
        XCTAssertEqual(replayedLink, rematchID)
        let revoked = try await client.invitationLink(id: rematchID, actorID: a.id)
        XCTAssertNil(revoked, "Issue retry must not revive revoked token")
        try await switchActor(to: b, sdk: sdk, model: model)
        do { _ = try await client.resolveInvitation(token: link.token, actorID: b.id); XCTFail("Revoked link opened") }
        catch { XCTAssertEqual(error as? DuelClientError, .accessDenied) }
        _ = try await control("gate-on")
        await store.refresh()
        await store.submit(.accept(challengeID: rematchID, policyVersion: rematch.policyVersion, termsDigest: rematch.termsDigest))
        assertConsents(try XCTUnwrap(store.agreements.first { $0.id == rematchID }))
        _ = try await control("gate-off")
        await store.submit(.cancel(challengeID: rematchID))
        XCTAssertEqual(store.agreements.first { $0.id == rematchID }?.status, .cancelled)
        state = try await control("state")
        XCTAssertEqual(state.openSlots, 0)
        XCTAssertFalse(state.admission)
        XCTAssertEqual(state.allowlist, 0)
        await model.signOut()
        assertPrivateStateCleared(store)
    }

    private func makeSDK() -> SupabaseClient {
        SupabaseClient(supabaseURL: config.url, supabaseKey: config.key,
            options: .init(auth: .init(storage: SmokeSessionStorage(), autoRefreshToken: false,
                                      emitLocalSessionAsInitialSession: true)))
    }

    private func switchActor(to actor: Actor, sdk: SupabaseClient, model: AppModel) async throws {
        await model.signOut()
        XCTAssertNil(sdk.auth.currentSession)
        XCTAssertNil(model.userID)
        assertPrivateStateCleared(model.duels)
        _ = try await signIn(actor, sdk: sdk)
        for _ in 0..<200 {
            if model.userID == actor.id && model.phase == .signedIn { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTAssertEqual(model.userID, actor.id)
        XCTAssertEqual(model.phase, .signedIn, model.presentedError ?? "Auth event not applied")
        XCTAssertEqual(model.duels.actorID, actor.id)
        assertPrivateStateCleared(model.duels)
    }

    private func assertPrivateStateCleared(_ store: DuelStore, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(store.agreements.isEmpty, file: file, line: line)
        XCTAssertTrue(store.lifecycles.isEmpty, file: file, line: line)
        XCTAssertTrue(store.lifecycleReceivedAt.isEmpty, file: file, line: line)
        XCTAssertTrue(store.lifecycleErrors.isEmpty, file: file, line: line)
        XCTAssertNil(store.lastConfirmedOperation, file: file, line: line)
        XCTAssertTrue(store.friends.isEmpty, file: file, line: line)
        XCTAssertTrue(store.catalog.events.isEmpty, file: file, line: line)
        XCTAssertTrue(store.catalog.policies.isEmpty, file: file, line: line)
        XCTAssertTrue(store.freshIDs.isEmpty, file: file, line: line)
        XCTAssertNil(store.pending, file: file, line: line)
        XCTAssertNil(store.lastConfirmedID, file: file, line: line)
        XCTAssertNil(store.errorMessage, file: file, line: line)
    }

    private func assertConsents(_ row: DuelAgreement) {
        XCTAssertEqual(row.participants.count, 2)
        for participant in row.participants {
            XCTAssertNotNil(participant.acceptedAt)
            XCTAssertEqual(participant.consentTermsDigest, row.termsDigest)
            XCTAssertEqual(participant.consentPolicyVersion, row.policyVersion)
        }
    }

    private func control(_ action: String, _ body: [String: String] = [:]) async throws -> State {
        var request = URLRequest(url: config.url.appendingPathComponent("__smoke/" + action))
        request.httpMethod = "POST"
        request.setValue(config.controlToken, forHTTPHeaderField: "X-Smoke-Token")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
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
        XCTFail("HTTP response never reached the hold point")
        throw DuelClientError.unavailable
    }

    private func capture(_ model: AppModel, id: UUID, name: String) async throws {
        // Render the shipping duel detail from real HTTP data in the simulator.
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        let previous = scene.windows.first { $0.isKeyWindow }
        window.rootViewController = UIHostingController(rootView:
            NavigationStack { DuelDetailView(challengeID: id) }.environment(model))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKey() }
        try await Task.sleep(for: .milliseconds(350))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

/// Real SDK sessions, isolated from the app's persisted sign-in credentials.
private final class SmokeSessionStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.withLock { values[key] = value } }
    func retrieve(key: String) throws -> Data? { lock.withLock { values[key] } }
    func remove(key: String) throws { _ = lock.withLock { values.removeValue(forKey: key) } }
}
