import XCTest
@testable import GameTime

@MainActor
final class DuelRematchLinkTests: XCTestCase {
    let a = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let b = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testStrictLocatorParserHasNoPublicProofOrActorFields() {
        let token = UUID()
        let url = DuelInvitationLink.url(token: token)
        XCTAssertEqual(DuelInvitationLink.token(from: url), token)
        for bad in [url.absoluteString + "?accept=true", url.absoluteString + "#proof",
                    url.absoluteString + "/", url.absoluteString.replacingOccurrences(of: "invitation", with: "other"),
                    "https://invitation/\(token)", "gametime-duel://user@invitation/\(token)",
                    "gametime-duel://invitation:123/\(token)", "gametime-duel://invitation/not-a-token"] {
            XCTAssertNil(DuelInvitationLink.token(from: URL(string: bad)!))
        }
        XCTAssertFalse(url.absoluteString.contains(a.uuidString))
    }

    func testNewEnvelopesRoundTripAndBindExactEventAndToken() throws {
        for operation: DuelMutation in [
            .rematch(previousID: UUID(), eventID: UUID(), policyVersion: "duel-fixture-5k-v1", consent: true),
            .issueLink(challengeID: UUID()), .revokeLink(challengeID: UUID(), token: UUID())
        ] {
            let request = try PendingDuelRequest(actorID: a, operation: operation)
            let saved = try JSONDecoder().decode(PendingDuelRequest.self, from: JSONEncoder().encode(request))
            XCTAssertEqual(saved, request)
            XCTAssertEqual(try JSONDecoder().decode([String: DuelParameter].self, from: saved.requestBody),
                           operation.parameters(requestID: saved.requestID))
            XCTAssertThrowsError(try saved.validate(for: b))
            XCTAssertFalse(saved.allowsReplacement(by: try PendingDuelRequest(actorID: a,
                requestID: saved.requestID, operation: .issueLink(challengeID: UUID()))))
        }
        XCTAssertThrowsError(try PendingDuelRequest(actorID: a, operation: .rematch(previousID: UUID(),
            eventID: UUID(), policyVersion: "duel-fixture-5k-v1", consent: false)))
    }

    func testRematchLostResponseRecoversFreshAgreementAndNeedsInviteeConsent() async throws {
        let backend = FixtureDuelBackend(actors: [a,b], now: Date().addingTimeInterval(-10 * 86400))
        let oldID = try create(backend)
        let old = try backend.detail(oldID, actor: a)
        _ = try backend.submit(PendingDuelRequest(actorID: b, operation: .accept(challengeID: oldID,
            policyVersion: old.policyVersion, termsDigest: old.termsDigest)))
        try backend.seedLifecycle(oldID, scenario: "final")
        let auth = LinkTestAuth(a)
        let pending = EphemeralPendingDuelRequestStore()
        let store = makeStore(backend, auth, pending: pending)
        store.setActor(a)
        await store.refresh()
        backend.loseNextResponse = true
        await store.submit(.rematch(previousID: oldID, eventID: backend.rematchEvent.id,
            policyVersion: old.policyVersion, consent: true))
        let saved = try XCTUnwrap(store.pending)
        XCTAssertEqual(backend.rows.count, 2)
        backend.enabled = false
        store.setActor(b); auth.actor = b
        await store.refresh()
        XCTAssertNil(store.pending)
        store.setActor(a); auth.actor = a
        await store.refresh()
        XCTAssertEqual(store.pending?.requestID, saved.requestID)
        await store.retry()
        let newID = try XCTUnwrap(store.lastConfirmedID)
        XCTAssertNotEqual(newID, oldID)
        let new = try backend.detail(newID, actor: a)
        XCTAssertEqual(new.status, .invited)
        XCTAssertEqual(new.participants.filter { $0.acceptedAt != nil }.count, 1)
        XCTAssertNotEqual(new.termsDigest, old.termsDigest)
        XCTAssertEqual(try backend.detail(oldID, actor: a).terms, old.terms)
        XCTAssertNil(store.pending)
        backend.enabled = true
        _ = try backend.submit(PendingDuelRequest(actorID: b, operation: .accept(challengeID: newID,
            policyVersion: new.policyVersion, termsDigest: new.termsDigest)))
        XCTAssertEqual(try backend.detail(newID, actor: b).participants.filter { $0.acceptedAt != nil }.count, 2)
    }

    func testLinkIssueLostResponseAndRevokeDoNotReactivateOrAccept() async throws {
        let backend = FixtureDuelBackend(actors: [a,b])
        let id = try create(backend)
        let auth = LinkTestAuth(a)
        let store = makeStore(backend, auth)
        store.setActor(a); await store.refresh()
        backend.loseNextResponse = true
        await store.submit(.issueLink(challengeID: id))
        let request = try XCTUnwrap(store.pending)
        let original = try XCTUnwrap(backend.links[id])
        await store.refresh()
        XCTAssertEqual(store.pending?.requestID, request.requestID)
        backend.enabled = false
        await store.retry()
        XCTAssertEqual(store.invitationLinks[id], original)
        XCTAssertEqual(try backend.resolveInvitation(original.token, actor: b), id)
        XCTAssertEqual(try backend.detail(id, actor: b).status, .invited)
        await store.submit(.revokeLink(challengeID: id, token: original.token))
        XCTAssertNil(store.invitationLinks[id])
        _ = try backend.submit(request)
        XCTAssertNil(backend.links[id])
        XCTAssertThrowsError(try backend.resolveInvitation(original.token, actor: b))
    }

    func testPendingLocatorSurvivesLoginWrongAccountAndRelaunchWithoutAccepting() async throws {
        let backend = FixtureDuelBackend(actors: [a,b])
        let id = try create(backend)
        _ = try backend.submit(PendingDuelRequest(actorID: a, operation: .issueLink(challengeID: id)))
        let link = try XCTUnwrap(backend.links[id])
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let auth = LinkTestAuth(nil)
        let store = makeStore(backend, auth, defaults: defaults)
        store.receiveInvitation(link.url)
        await store.openPendingInvitation()
        XCTAssertNil(store.resolvedInvitationID)
        let relaunched = makeStore(backend, auth, defaults: defaults)
        XCTAssertEqual(relaunched.pendingInvitationToken, link.token)
        auth.actor = a; relaunched.setActor(a)
        await relaunched.openPendingInvitation()
        XCTAssertNotNil(relaunched.invitationError)
        XCTAssertEqual(relaunched.pendingInvitationToken, link.token)
        auth.actor = b; relaunched.setActor(b)
        await relaunched.openPendingInvitation()
        XCTAssertEqual(relaunched.resolvedInvitationID, id)
        XCTAssertNil(relaunched.pendingInvitationToken)
        XCTAssertTrue(relaunched.canStartRequest)
        XCTAssertEqual(try backend.detail(id, actor: b).participants.filter { $0.acceptedAt != nil }.count, 1)
        auth.actor = a; relaunched.setActor(a)
        XCTAssertNil(relaunched.resolvedInvitationID)
        XCTAssertTrue(relaunched.invitationLinks.isEmpty)
        XCTAssertNil(makeStore(backend, auth, defaults: defaults).pendingInvitationToken)
    }

    func testLateResolverReplyCannotNavigateAnotherAccount() async throws {
        let auth = LinkTestAuth(a)
        let token = UUID()
        var started = false
        var continuation: CheckedContinuation<Void, Never>?
        let client = SupabaseDuelClient(enabled: true, currentActor: { auth.actor }, rpc: { name, params in
            if name == "resolve_duel_link_v1" {
                XCTAssertEqual(params, ["p_token": .string(token.uuidString.lowercased())])
                started = true
                await withCheckedContinuation { continuation = $0 }
                return Data("{\"challengeId\":\"\(UUID())\"}".utf8)
            }
            return Data("[]".utf8)
        }, readTable: { _ in Data("[]".utf8) })
        let store = DuelStore(enabled: true, auth: auth, client: client, friendships: LinkTestFriends(),
            pendingStore: EphemeralPendingDuelRequestStore(), invitationDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.setActor(a); store.receiveInvitation(DuelInvitationLink.url(token: token))
        let task = Task { await store.openPendingInvitation() }
        while !started { await Task.yield() }
        auth.actor = b; store.setActor(b)
        continuation?.resume()
        await task.value
        XCTAssertNil(store.resolvedInvitationID)
        XCTAssertNil(store.invitationError)
        XCTAssertEqual(store.pendingInvitationToken, token)
    }

    func testDisabledRuntimeDoesNotSaveOrResolveLinks() async {
        let auth = LinkTestAuth(a)
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = DuelStore(enabled: false, auth: auth, client: DisabledDuelClient(), friendships: LinkTestFriends(),
            pendingStore: EphemeralPendingDuelRequestStore(), invitationDefaults: defaults)
        store.setActor(a)
        store.receiveInvitation(DuelInvitationLink.url(token: UUID()))
        await store.openPendingInvitation()
        XCTAssertNil(store.actorID)
        XCTAssertNil(store.pendingInvitationToken)
    }

    private func create(_ backend: FixtureDuelBackend) throws -> UUID {
        try backend.submit(PendingDuelRequest(actorID: a, operation: .create(inviteeID: b,
            eventID: backend.event.id, policyVersion: backend.event.policyVersion, consent: true)))
    }
    private func makeStore(_ backend: FixtureDuelBackend, _ auth: LinkTestAuth,
                           pending: any PendingDuelRequestStore = EphemeralPendingDuelRequestStore(),
                           defaults: UserDefaults? = nil) -> DuelStore {
        DuelStore(enabled: true, auth: auth, client: FixtureDuelClient(backend: backend, currentActor: { auth.actor }),
            friendships: LinkTestFriends(), pendingStore: pending,
            invitationDefaults: defaults ?? UserDefaults(suiteName: UUID().uuidString)!)
    }
}

@MainActor private final class LinkTestAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID?) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}
@MainActor private final class LinkTestFriends: FriendshipsClient {
    func listCards() async throws -> [FriendshipCard] { [] }
    func findExactHandle(_ handle: String) async throws -> ProfileCard? { nil }
    func requestFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func acceptFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func removeFriendship(callerID: UUID, otherUserID: UUID) async throws {}
}
