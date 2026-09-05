import XCTest
@testable import GameTime

@MainActor
final class DuelLifecycleTests: XCTestCase {
    private let a = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    private let b = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

    func testPostgresMicrosecondsRoundTripAndExclusiveDeadline() throws {
        let before = try DuelInstant("2026-09-05T12:00:00.000001+00:00")
        let deadline = try DuelInstant("2026-09-05T12:00:00.000002Z")
        XCTAssertLessThan(before, deadline)
        XCTAssertEqual(deadline.microseconds - before.microseconds, 1)
        XCTAssertEqual(before.text(zone: "America/Chicago"), "Sep 5, 2026 at 7:00:00.000001 AM CDT")
        let recovered = try JSONDecoder().decode(DuelInstant.self, from: JSONEncoder().encode(before))
        XCTAssertEqual(recovered.rawValue, before.rawValue)
        XCTAssertThrowsError(try DuelInstant("2026-09-05T12:00:00.0000001Z"))
        XCTAssertThrowsError(try DuelInstant("infinity"))
    }

    func testActualPostgresParticipantDocumentsDecode() throws {
        struct Capture: Decodable {
            struct Document: Decodable { let actorId: UUID; let agreement: DuelAgreement; let lifecycle: DuelLifecycle }
            let label: String
            let document: Document
        }
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/duel-lifecycle-v1.json")
        let captures = try DuelCodec.decoder().decode([Capture].self, from: Data(contentsOf: path))
        XCTAssertEqual(captures.count, 4)
        for capture in captures {
            try capture.document.lifecycle.validate(agreement: capture.document.agreement, actorID: capture.document.actorId)
        }
        XCTAssertEqual(captures.first { $0.label == "blocked_own" }?.document.lifecycle.contactSuppressed, true)
        XCTAssertNil(captures.first { $0.label == "final_pending" }?.document.lifecycle.simulatedReturnCents)
        XCTAssertEqual(captures.first { $0.label == "final_return" }?.document.lifecycle.simulatedReturnCents, 2000)
    }

    func testNewEnvelopesRetainExactRevisionReasonAndExitKind() throws {
        for operation: DuelMutation in [.fileReview(challengeID: a, revision: 0, reason: .missingResult),
                                      .fileReview(challengeID: a, revision: 2, reason: .wrongIdentity),
                                      .exit(challengeID: a, kind: .injury), .exit(challengeID: a, kind: .withdrawal)] {
            let saved = try PendingDuelRequest(actorID: b, operation: operation)
            let restored = try JSONDecoder().decode(PendingDuelRequest.self, from: JSONEncoder().encode(saved))
            try restored.validate(for: b)
            XCTAssertEqual(restored, saved)
            XCTAssertEqual(try JSONDecoder().decode([String: DuelParameter].self, from: saved.requestBody),
                           operation.parameters(requestID: saved.requestID))
            XCTAssertThrowsError(try restored.validate(for: a))
        }
        XCTAssertThrowsError(try PendingDuelRequest(actorID: a,
            operation: .fileReview(challengeID: b, revision: -1, reason: .wrongResult)))
    }

    func testCorrectionHistoryAndIndependentOwnCases() async throws {
        let (backend, id) = try scenario("correction")
        let auth = LifecycleTestAuth(a)
        let store = makeStore(backend, auth)
        store.setActor(a)
        await store.refresh()
        XCTAssertEqual(store.lifecycles[id]?.notices.count, 2)
        XCTAssertEqual(store.lifecycles[id]?.latestNotice?.outcome.winnerId, b)
        await store.submit(.fileReview(challengeID: id, revision: 1, reason: .wrongResult))
        XCTAssertEqual(store.lastConfirmedID, id, "Case receipt must not become the navigation destination")
        XCTAssertNil(store.pending)
        XCTAssertEqual(store.lifecycles[id]?.reviews.map(\.proofRevision), [1])
        XCTAssertFalse(store.canFileReview(id, revision: 1))
        XCTAssertTrue(store.canFileReview(id, revision: 2))
        await store.submit(.fileReview(challengeID: id, revision: 2, reason: .wrongIdentity))
        XCTAssertEqual(store.lifecycles[id]?.reviews.count, 2)
        XCTAssertEqual(store.lifecycles[id]?.notices.count, 2)
        auth.actor = b
        store.setActor(b)
        XCTAssertTrue(store.lifecycles.isEmpty)
        XCTAssertTrue(store.lifecycleReceivedAt.isEmpty)
        await store.refresh()
        XCTAssertEqual(store.lifecycles[id]?.reviews.count, 0)
        XCTAssertTrue(store.canFileReview(id, revision: 2))
    }

    func testLostReviewAndExitResponsesRecoverAfterRelaunchAndGateOff() async throws {
        for kind: DuelMutation in [.fileReview(challengeID: a, revision: 2, reason: .wrongResult), .exit(challengeID: a, kind: .injury)] {
            let (backend, id) = try scenario("correction")
            let auth = LifecycleTestAuth(a)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let first = makeStore(backend, auth, pending: FilePendingDuelRequestStore(directory: directory))
            first.setActor(a)
            await first.refresh()
            backend.loseNextResponse = true
            let operation: DuelMutation = kind.rpc == "file_duel_review_v1"
                ? .fileReview(challengeID: id, revision: 2, reason: .wrongResult) : .exit(challengeID: id, kind: .injury)
            await first.submit(operation)
            let request = try XCTUnwrap(first.pending)
            XCTAssertTrue(request.mayHaveCommitted)
            backend.enabled = false
            let second = makeStore(backend, auth, pending: FilePendingDuelRequestStore(directory: directory))
            second.setActor(b)
            auth.actor = b
            await second.refresh()
            XCTAssertNil(second.pending)
            auth.actor = a
            second.setActor(a)
            await second.refresh()
            XCTAssertEqual(second.pending, request, "Refresh must not replay")
            await second.retry()
            XCTAssertNil(second.pending)
            XCTAssertEqual(second.lastConfirmedID, id)
            if operation.rpc == "file_duel_review_v1" { XCTAssertEqual(backend.cases[id]?[a]?.count, 1) }
            else { XCTAssertEqual(second.lifecycles[id]?.closure?.kind, "injury") }
        }
    }

    func testBlockedContactHidesNoticesAndFinalButKeepsOwnCaseAndExit() async throws {
        let (backend, id) = try scenario("correction")
        let auth = LifecycleTestAuth(a)
        let store = makeStore(backend, auth)
        store.setActor(a)
        await store.refresh()
        await store.submit(.fileReview(challengeID: id, revision: 2, reason: .missingResult))
        backend.suppressed.insert(id)
        await store.refreshDetail(id)
        XCTAssertEqual(store.lifecycles[id]?.notices, [])
        XCTAssertEqual(store.lifecycles[id]?.reviews.count, 1)
        XCTAssertTrue(store.canExit(id))
        await store.submit(.exit(challengeID: id, kind: .withdrawal))
        XCTAssertEqual(store.lifecycles[id]?.closure?.isOwn, true)
        XCTAssertFalse(store.canExit(id))
        backend.offline = true
        await store.refreshDetail(id)
        XCTAssertNil(store.lifecycles[id], "No cached opponent content on failure")
        XCTAssertNotNil(store.lifecycleErrors[id])
    }

    func testFinalResultAndReturnAreIndependentOfHistoricalScheduledStatus() async throws {
        for settled in [false, true] {
            let (backend, id) = try scenario(settled ? "settlement" : "final")
            let auth = LifecycleTestAuth(b)
            let store = makeStore(backend, auth)
            store.setActor(b)
            await store.refresh()
            XCTAssertEqual(store.agreements.first?.status, .scheduled)
            XCTAssertEqual(store.lifecycles[id]?.progressText, "Result confirmed")
            XCTAssertEqual(store.lifecycles[id]?.simulatedReturnCents, settled ? 4000 : nil)
            XCTAssertFalse(store.canExit(id))
            XCTAssertFalse(store.canFileReview(id, revision: 2))
        }
    }

    func testEveryScorerOutcomeHasPlainLanguageAndRejectsInvalidWinner() throws {
        for (kind, reasons) in ["winner": ["faster_chip", "only_finisher"], "tie": ["equal_chip_seconds"],
            "withdrawn_no_contest": ["participant_withdrew"], "void": ["both_nonfinish", "unresolved_proof",
            "prestart_withdrawal", "injury", "event_cancelled", "account_deleted", "review_void", "review_timeout", "finality_timeout"]] {
            for reason in reasons {
                let outcome = DuelOutcome(kind: kind, reason: reason, winnerId: kind == "winner" ? a : nil)
                try outcome.validate(actors: [a,b])
                XCTAssertFalse(outcome.explanation.contains("_"))
                XCTAssertFalse(outcome.title(actorID: a).contains("_"))
            }
        }
        XCTAssertThrowsError(try DuelOutcome(kind: "winner", reason: "faster_chip", winnerId: UUID()).validate(actors: [a,b]))
        XCTAssertThrowsError(try DuelOutcome(kind: "void", reason: "new_reason", winnerId: nil).validate(actors: [a,b]))
    }

    func testAdapterUsesParticipantRPCsAndRejectsLateAccountResponse() async throws {
        let (backend, id) = try scenario("correction")
        var actor: UUID? = a
        let expected = try backend.lifecycle(id, actor: a)
        let client = SupabaseDuelClient(enabled: true, currentActor: { actor }, rpc: { name, params in
            XCTAssertEqual(name, "get_duel_lifecycle_v1")
            XCTAssertEqual(params, ["p_challenge_id": .string(id.uuidString.lowercased())])
            actor = self.b
            return try JSONEncoder().encode(expected)
        }, readTable: { _ in XCTFail("No tables needed"); return Data() })
        do { _ = try await client.lifecycle(id: id, actorID: a); XCTFail("Late actor result returned") }
        catch { XCTAssertEqual(error as? DuelClientError, .accountChanged) }
    }

    func testStoreDiscardsSuspendedLifecycleResponseAfterAccountChange() async throws {
        let (backend, id) = try scenario("correction")
        let auth = LifecycleTestAuth(a)
        let client = LifecycleSuspendingClient(backend: backend)
        let store = DuelStore(enabled: true, auth: auth, client: client,
            friendships: LifecycleTestFriends(), pendingStore: EphemeralPendingDuelRequestStore())
        store.setActor(a)
        let task = Task { await store.refresh() }
        while client.continuation == nil { await Task.yield() }
        auth.actor = b
        store.setActor(b)
        client.continuation?.resume()
        await task.value
        XCTAssertTrue(store.lifecycles.isEmpty)
        XCTAssertTrue(store.agreements.isEmpty)
        XCTAssertFalse(store.isLoading)
        XCTAssertNil(store.lifecycleErrors[id])
    }

    func testDeadlineUsesServerClockAndDisablesAtBoundaryWithoutMutation() async throws {
        let (backend, id) = try scenario("correction")
        let auth = LifecycleTestAuth(a)
        let store = makeStore(backend, auth)
        store.setActor(a)
        await store.refresh()
        let life = try XCTUnwrap(store.lifecycles[id])
        let received = try XCTUnwrap(store.lifecycleReceivedAt[id])
        let deadline = try XCTUnwrap(life.latestNotice?.disputeClosesAt)
        let elapsed = Double(deadline.microseconds - life.serverNow.microseconds) / 1_000_000
        XCTAssertTrue(store.canFileReview(id, revision: 2, at: received.addingTimeInterval(elapsed - 0.001)))
        XCTAssertFalse(store.canFileReview(id, revision: 2, at: received.addingTimeInterval(elapsed + 0.001)))
        backend.now = deadline.date
        await store.refreshDetail(id)
        XCTAssertFalse(store.canFileReview(id, revision: 2))
        await store.submit(.fileReview(challengeID: id, revision: 2, reason: .wrongResult))
        XCTAssertNil(store.pending)
        XCTAssertNil(backend.cases[id])
    }

    private func scenario(_ name: String) throws -> (FixtureDuelBackend, UUID) {
        let backend = FixtureDuelBackend(actors: [a,b], now: Date().addingTimeInterval(-10 * 86400))
        let id = try backend.submit(PendingDuelRequest(actorID: a, operation: .create(inviteeID: b,
            eventID: backend.event.id, policyVersion: backend.event.policyVersion, consent: true)))
        let row = try backend.detail(id, actor: b)
        _ = try backend.submit(PendingDuelRequest(actorID: b, operation: .accept(challengeID: id,
            policyVersion: row.policyVersion, termsDigest: row.termsDigest)))
        try backend.seedLifecycle(id, scenario: name)
        return (backend, id)
    }

    private func makeStore(_ backend: FixtureDuelBackend, _ auth: LifecycleTestAuth,
                           pending: any PendingDuelRequestStore = EphemeralPendingDuelRequestStore()) -> DuelStore {
        DuelStore(enabled: true, auth: auth, client: FixtureDuelClient(backend: backend, currentActor: { auth.actor }),
            friendships: LifecycleTestFriends(), pendingStore: pending)
    }
}

@MainActor
private final class LifecycleTestAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}
@MainActor
private final class LifecycleTestFriends: FriendshipsClient {
    func listCards() async throws -> [FriendshipCard] { [] }
    func findExactHandle(_ handle: String) async throws -> ProfileCard? { nil }
    func requestFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func acceptFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func removeFriendship(callerID: UUID, otherUserID: UUID) async throws {}
}
@MainActor
private final class LifecycleSuspendingClient: DuelClient {
    let backend: FixtureDuelBackend
    var continuation: CheckedContinuation<Void, Never>?
    init(backend: FixtureDuelBackend) { self.backend = backend }
    func catalog(actorID: UUID) async throws -> DuelCatalog { DuelCatalog(events: [], policies: []) }
    func list(actorID: UUID, before: DuelAgreement?) async throws -> [DuelAgreement] { Array(backend.rows.values) }
    func detail(id: UUID, actorID: UUID) async throws -> DuelAgreement { try backend.detail(id, actor: actorID) }
    func lifecycle(id: UUID, actorID: UUID) async throws -> DuelLifecycle {
        let row = try backend.lifecycle(id, actor: actorID)
        await withCheckedContinuation { continuation = $0 }
        return row
    }
    func submit(_ request: PendingDuelRequest) async throws -> UUID { try backend.submit(request) }
}
