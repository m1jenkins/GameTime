import XCTest
@testable import GameTime

@MainActor
final class DuelTests: XCTestCase {
    let a = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let b = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testLocalPostgresDocumentDecodesAndPreservesConsentAndCursor() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().appendingPathComponent("Fixtures/duel-agreement-v1.json"))
        let row = try DuelCodec.decoder().decode(DuelAgreement.self, from: data)
        try row.validate(for: row.creatorID)
        try row.validate(for: row.inviteeID)
        XCTAssertEqual(row.status, .scheduled)
        XCTAssertEqual(row.terms.policy, .simulated5K)
        XCTAssertTrue(row.participants.allSatisfy { $0.consentTermsDigest == row.termsDigest })
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(row.createdAtWireValue, raw["created_at"] as? String)
        var sent: [String: DuelParameter] = [:]
        let client = SupabaseDuelClient(enabled: true, currentActor: { row.creatorID }, rpc: { name, params in
            XCTAssertEqual(name, "list_my_duels_v1")
            sent = params
            return Data("[]".utf8)
        }, readTable: { _ in Data() })
        _ = try await client.list(actorID: row.creatorID, before: row)
        XCTAssertEqual(sent["p_before"], .string(try XCTUnwrap(row.createdAtWireValue)))
        XCTAssertEqual(sent["p_before_id"], .string(row.id.uuidString.lowercased()))
        XCTAssertThrowsError(try row.validate(for: UUID()))
    }

    func testEnvelopeRoundTripEveryVerbAndExactRPCParameters() throws {
        let backend = FixtureDuelBackend(actors: [a, b])
        let create = try creation(backend)
        let id = try backend.submit(create)
        let row = try backend.detail(id, actor: b)
        let operations: [DuelMutation] = [create.operation,
            .accept(challengeID: id, policyVersion: row.policyVersion, termsDigest: row.termsDigest),
            .decline(challengeID: id), .cancel(challengeID: id)]
        for operation in operations {
            let request = try PendingDuelRequest(actorID: operation == create.operation ? a : b, operation: operation)
            let decoded = try JSONDecoder().decode(PendingDuelRequest.self, from: JSONEncoder().encode(request))
            XCTAssertEqual(request, decoded)
            try decoded.validate(for: request.actorID)
            XCTAssertThrowsError(try decoded.validate(for: UUID()))
            let body = try JSONDecoder().decode([String: DuelParameter].self, from: request.requestBody)
            XCTAssertEqual(body, operation.parameters(requestID: request.requestID))
            XCTAssertEqual(body["p_request_id"], .string(request.requestID.uuidString.lowercased()))
            XCTAssertFalse(body.keys.contains("amount"))
            XCTAssertFalse(body.keys.contains("mode"))
        }
    }

    func testFileEnvelopeSurvivesRelaunchRejectsReplacementAndCorruption() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let request = try creation(FixtureDuelBackend(actors: [a, b]))
        let file = FilePendingDuelRequestStore(directory: directory)
        try await file.save(request)
        let reopened = FilePendingDuelRequestStore(directory: directory)
        let loaded = try await reopened.load(for: a)
        XCTAssertEqual(loaded, request)
        let other = try await reopened.load(for: b)
        XCTAssertNil(other)
        do {
            try await reopened.save(PendingDuelRequest(actorID: a, requestID: request.requestID,
                operation: .cancel(challengeID: UUID())))
            XCTFail("Changed operation must not replace the request")
        } catch { XCTAssertEqual(error as? DuelClientError, .storage) }
        try await reopened.remove(for: a, matching: UUID())
        let stillSaved = try await reopened.load(for: a)
        XCTAssertNotNil(stillSaved)
        let path = directory.appendingPathComponent("\(a.uuidString.lowercased()).json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        json["kind"] = "personal_challenge_v1"
        try JSONSerialization.data(withJSONObject: json).write(to: path)
        do { _ = try await reopened.load(for: a); XCTFail("Wrong product must fail closed") }
        catch { XCTAssertEqual(error as? DuelClientError, .storage) }
        try await reopened.remove(for: a, matching: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))
    }

    func testDeletionCleanupRejectsQueuedEnvelopeWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pending = FilePendingDuelRequestStore(directory: directory)
        let request = try creation(FixtureDuelBackend(actors: [a,b]))
        try await pending.save(request)
        try await pending.remove(for: a, matching: nil)
        do { try await pending.save(request); XCTFail("Deleted actor cannot restore a saved request") }
        catch { XCTAssertEqual(error as? DuelClientError, .storage) }
        let retained = try await pending.load(for: a)
        XCTAssertNil(retained)
    }

    func testDisabledAdapterCannotReadOrMutateEvenWithMatchingActor() async throws {
        let request = try creation(FixtureDuelBackend(actors: [a,b]))
        let client = SupabaseDuelClient(enabled: false, currentActor: { self.a },
            rpc: { _, _ in XCTFail("Disabled client sent an RPC"); return Data() },
            readTable: { _ in XCTFail("Disabled client read a table"); return Data() })
        do { _ = try await client.submit(request); XCTFail("Disabled mutation accepted") }
        catch { XCTAssertEqual(error as? DuelClientError, .accessDenied) }
        do { _ = try await client.catalog(actorID: a); XCTFail("Disabled catalog accepted") }
        catch { XCTAssertEqual(error as? DuelClientError, .accessDenied) }
    }

    func testEnvelopeRejectsVersionPayloadAndActorTampering() throws {
        let request = try creation(FixtureDuelBackend(actors: [a,b]))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any])
        for (key, value): (String, Any) in [("version", 2), ("actorID", b.uuidString),
            ("requestBody", Data("{}".utf8).base64EncodedString())] {
            var json = original
            json[key] = value
            let changed = try JSONDecoder().decode(PendingDuelRequest.self, from: JSONSerialization.data(withJSONObject: json))
            XCTAssertThrowsError(try changed.validate(for: a))
        }
    }

    func testTwoActorsAgreeToIdenticalTermsAndCanCancelWithGateOff() async throws {
        let backend = FixtureDuelBackend(actors: [a,b])
        let auth = DuelTestAuth(a)
        let store = makeStore(backend, auth)
        store.setActor(a)
        await store.refresh()
        await store.submit(try creation(backend).operation)
        let original = try XCTUnwrap(store.agreements.first)
        auth.actor = b
        store.setActor(b)
        XCTAssertTrue(store.agreements.isEmpty)
        await store.refresh()
        XCTAssertEqual(store.agreements.first?.terms, original.terms)
        await store.submit(.accept(challengeID: original.id, policyVersion: original.policyVersion, termsDigest: original.termsDigest))
        let agreed = try XCTUnwrap(store.agreements.first)
        XCTAssertEqual(agreed.status, .scheduled)
        XCTAssertTrue(agreed.participants.allSatisfy { $0.consentTermsDigest == original.termsDigest })
        backend.enabled = false
        await store.submit(.cancel(challengeID: original.id))
        XCTAssertEqual(store.agreements.first?.status, .cancelled)
        XCTAssertEqual(store.agreements.first?.terms, original.terms)
        XCTAssertNil(store.pending)
    }

    func testLostCommittedResponseRecoversAfterRelaunchAndGateOffWithoutDuplicate() async throws {
        let backend = FixtureDuelBackend(actors: [a,b])
        let auth = DuelTestAuth(a)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let pending = FilePendingDuelRequestStore(directory: directory)
        let first = makeStore(backend, auth, pending: pending)
        first.setActor(a)
        await first.refresh()
        backend.loseNextResponse = true
        await first.submit(try creation(backend).operation)
        let saved = try XCTUnwrap(first.pending)
        XCTAssertTrue(saved.mayHaveCommitted)
        XCTAssertEqual(backend.rows.count, 1)
        backend.enabled = false
        let second = makeStore(backend, auth, pending: FilePendingDuelRequestStore(directory: directory))
        second.setActor(a)
        await second.refresh()
        XCTAssertEqual(second.pending, saved, "Refresh must not replay a mutation")
        await second.retry()
        XCTAssertNil(second.pending)
        XCTAssertEqual(second.agreements.count, 1)
        XCTAssertEqual(backend.rows.count, 1)
        XCTAssertEqual(second.agreements.first?.id, backend.rows.values.first?.id)
    }

    func testOfflineAndAccountSwitchNeverReplayOtherActorsPendingRequest() async throws {
        let backend = FixtureDuelBackend(actors: [a,b])
        let auth = DuelTestAuth(a)
        let pending = EphemeralPendingDuelRequestStore()
        let store = makeStore(backend, auth, pending: pending)
        store.setActor(a)
        await store.refresh()
        backend.offline = true
        await store.submit(try creation(backend).operation)
        XCTAssertNotNil(store.pending)
        auth.actor = b
        store.setActor(b)
        XCTAssertNil(store.pending)
        XCTAssertTrue(store.agreements.isEmpty)
        backend.offline = false
        await store.refresh()
        await store.retry()
        XCTAssertTrue(backend.rows.isEmpty)
        auth.actor = a
        store.setActor(a)
        await store.refresh()
        await store.retry()
        XCTAssertEqual(backend.rows.count, 1)
    }

    func testAccountSwitchDuringSubmissionDiscardsLateRowsAndRetainsOriginalRequest() async throws {
        let backend = FixtureDuelBackend(actors: [a,b])
        let auth = DuelTestAuth(a)
        let pending = EphemeralPendingDuelRequestStore()
        let client = DuelSuspendingClient(backend: backend)
        let store = DuelStore(enabled: true, auth: auth, client: client,
            friendships: DuelTestFriends(), pendingStore: pending)
        store.setActor(a)
        await store.refresh()
        let operation = try creation(backend).operation
        let task = Task { await store.submit(operation) }
        while client.continuation == nil { await Task.yield() }
        auth.actor = b
        store.setActor(b)
        client.continuation?.resume()
        await task.value
        XCTAssertTrue(store.agreements.isEmpty)
        XCTAssertNil(store.pending)
        let retained = await pending.load(for: a)
        XCTAssertNotNil(retained)
        XCTAssertNil(store.lastConfirmedID)
    }

    func testDefiniteRejectionClearsNewRequestAndAllowsSafeExit() async throws {
        let backend = FixtureDuelBackend(actors: [a,b])
        backend.enabled = false
        let auth = DuelTestAuth(a)
        let store = makeStore(backend, auth)
        store.setActor(a)
        await store.refresh()
        await store.submit(try creation(backend).operation)
        XCTAssertNil(store.pending)
        XCTAssertTrue(store.canStartRequest)
        XCTAssertEqual(store.errorMessage, DuelClientError.accessDenied.localizedDescription)
    }

    func testLifecycleFailureRefreshesDetailWithoutInventingResult() async throws {
        let backend = FixtureDuelBackend(actors: [a,b])
        let id = try backend.submit(creation(backend))
        let row = try backend.detail(id, actor: b)
        let auth = DuelTestAuth(b)
        let store = makeStore(backend, auth)
        store.setActor(b)
        await store.refresh()
        backend.now = row.acceptBy
        await store.submit(.accept(challengeID: id, policyVersion: row.policyVersion, termsDigest: row.termsDigest))
        XCTAssertNil(store.pending)
        XCTAssertEqual(store.agreements.first?.expiryDue, true)
        XCTAssertEqual(store.agreements.first?.status, .invited)
        XCTAssertEqual(store.errorMessage, DuelClientError.lifecycle.localizedDescription)
    }

    func testDeletedActorCannotRecoverAndOpponentRetainsHistory() throws {
        let backend = FixtureDuelBackend(actors: [a,b])
        let request = try creation(backend)
        let id = try backend.submit(request)
        backend.deleteActor(a)
        XCTAssertThrowsError(try backend.submit(request))
        let history = try backend.detail(id, actor: b)
        XCTAssertEqual(history.status, .cancelled)
        XCTAssertEqual(history.closeReason, "account_deleted")
        XCTAssertEqual(history.participants.first?.consentTermsDigest, history.termsDigest)
    }

    func testSQLStateMappingNeverRendersRawReason() {
        for code in ["42501", "22023", "23505", "55000", "XX000"] {
            let error = DuelClientError.sqlState(code)
            XCTAssertFalse(error.localizedDescription.contains(code))
            XCTAssertFalse(error.localizedDescription.contains("duel_"))
        }
        XCTAssertEqual(DuelClientError.sqlState("55000"), .lifecycle)
    }

    func testAdapterChecksActorBeforeAndAfterTransportAndUsesOnlyDuelRPCs() async throws {
        var actor: UUID? = a
        var calls = 0
        let request = try creation(FixtureDuelBackend(actors: [a,b]))
        let client = SupabaseDuelClient(enabled: true, currentActor: { actor }, rpc: { name, parameters in
            calls += 1
            XCTAssertEqual(name, "create_duel_v1")
            XCTAssertEqual(parameters, request.operation.parameters(requestID: request.requestID))
            actor = self.b
            return try JSONEncoder().encode(UUID())
        }, readTable: { _ in XCTFail("Mutation cannot read other tables"); return Data() })
        do { _ = try await client.submit(request); XCTFail("Account changed in flight") }
        catch { XCTAssertEqual(error as? DuelClientError, .accountChanged) }
        do { _ = try await client.submit(request); XCTFail("Wrong account must not send") }
        catch { XCTAssertEqual(error as? DuelClientError, .accountChanged) }
        XCTAssertEqual(calls, 1)
    }

    func testConfigurationRequiresAnExplicitDisposableLoopbackURL() {
        let supported = [
            "http://127.0.0.1:54321",
            "http://localhost:54321/",
            "http://[::1]:54321",
        ]
        for rawURL in supported {
            let config = AppConfiguration(environment: .debug,
                supabaseURL: URL(string: rawURL)!,
                supabasePublishableKey: "sb_publishable_fixture", contestMutationsEnabled: true,
                duelRequested: true)
            XCTAssertTrue(config.duelRuntimeEnabled, rawURL)
        }

        let rejected = [
            "https://localhost:443",
            "http://127.0.0.1",
            "http://127.0.0.1:54321/other?x=1",
            "http://user@127.0.0.1:54321",
            "http://127.0.0.2:54321",
            "https://project.supabase.co:443",
        ]
        for rawURL in rejected {
            let config = AppConfiguration(environment: .debug,
                supabaseURL: URL(string: rawURL)!,
                supabasePublishableKey: "sb_publishable_fixture", contestMutationsEnabled: true,
                duelRequested: true)
            XCTAssertFalse(config.duelRuntimeEnabled, rawURL)
        }

        let staging = AppConfiguration(environment: .staging,
            supabaseURL: URL(string: "http://127.0.0.1:54321")!,
            supabasePublishableKey: "sb_publishable_fixture", contestMutationsEnabled: true,
            duelRequested: true)
        XCTAssertTrue(staging.duelRuntimeEnabled)

        let release = AppConfiguration(environment: .release,
            supabaseURL: URL(string: "http://127.0.0.1:54321")!,
            supabasePublishableKey: "sb_publishable_fixture", contestMutationsEnabled: true,
            duelRequested: true)
        XCTAssertFalse(release.duelRuntimeEnabled)

        let disabled = AppConfiguration(environment: .debug,
            supabaseURL: URL(string: "http://127.0.0.1:54321")!,
            supabasePublishableKey: "sb_publishable_fixture", contestMutationsEnabled: true,
            duelRequested: false)
        XCTAssertFalse(disabled.duelRuntimeEnabled)
    }

    private func creation(_ backend: FixtureDuelBackend) throws -> PendingDuelRequest {
        try PendingDuelRequest(actorID: a, operation: .create(inviteeID: b,
            eventID: backend.event.id, policyVersion: backend.event.policyVersion, consent: true))
    }

    private func makeStore(_ backend: FixtureDuelBackend, _ auth: DuelTestAuth,
                           pending: any PendingDuelRequestStore = EphemeralPendingDuelRequestStore()) -> DuelStore {
        DuelStore(enabled: true, auth: auth,
            client: FixtureDuelClient(backend: backend, currentActor: { auth.actor }),
            friendships: DuelTestFriends(), pendingStore: pending)
    }
}

@MainActor
private final class DuelTestAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}

@MainActor
private final class DuelTestFriends: FriendshipsClient {
    func listCards() async throws -> [FriendshipCard] { [] }
    func findExactHandle(_ handle: String) async throws -> ProfileCard? { nil }
    func requestFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func acceptFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func removeFriendship(callerID: UUID, otherUserID: UUID) async throws {}
}

@MainActor
private final class DuelSuspendingClient: DuelClient {
    let backend: FixtureDuelBackend
    var continuation: CheckedContinuation<Void, Never>?
    init(backend: FixtureDuelBackend) { self.backend = backend }
    func catalog(actorID: UUID) async throws -> DuelCatalog { DuelCatalog(events: [], policies: []) }
    func list(actorID: UUID, before: DuelAgreement?) async throws -> [DuelAgreement] { [] }
    func detail(id: UUID, actorID: UUID) async throws -> DuelAgreement { try backend.detail(id, actor: actorID) }
    func lifecycle(id: UUID, actorID: UUID) async throws -> DuelLifecycle { try backend.lifecycle(id, actor: actorID) }
    func submit(_ request: PendingDuelRequest) async throws -> UUID {
        let id = try backend.submit(request)
        await withCheckedContinuation { continuation = $0 }
        return id
    }
}
