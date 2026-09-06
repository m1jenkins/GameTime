import XCTest
@testable import GameTime

@MainActor
final class PerformanceCommitmentStoreTests: XCTestCase {
    func testLostCreateResponseSurvivesRelaunchAndOnlyExplicitRetrySendsExactBytes() async throws {
        let fixture = try CommitmentStoreFixture()
        let auth = CommitmentStoreAuth(fixture.actor)
        let client = CommitmentStoreClient(fixture)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = make(auth, client, FilePendingPerformanceCommitmentRequestStore(directory: directory))
        first.setActor(fixture.actor)
        await first.refresh()
        await first.preview(fixture.draft)
        client.loseResponse = true
        await first.submit(fixture.create)
        let saved = try XCTUnwrap(first.pending)
        XCTAssertTrue(saved.mayHaveCommitted)
        XCTAssertEqual(client.commits, 1)
        let second = make(auth, client, FilePendingPerformanceCommitmentRequestStore(directory: directory))
        second.setActor(fixture.actor)
        client.admission = false
        await second.refresh()
        XCTAssertEqual(second.pending, saved)
        XCTAssertEqual(client.requests.count, 1, "Reading history must never replay the mutation")
        await second.retry()
        XCTAssertNil(second.pending)
        XCTAssertEqual(client.commits, 1)
        XCTAssertEqual(client.requests.map(\.requestBody), [saved.requestBody, saved.requestBody])
        XCTAssertEqual(second.lastConfirmedID, fixture.agreement.id)
    }

    func testBothDurableSavesMustSucceedBeforeAnySend() async throws {
        for failingSave in [1, 2] {
            let fixture = try CommitmentStoreFixture()
            let auth = CommitmentStoreAuth(fixture.actor)
            let client = CommitmentStoreClient(fixture)
            let persistence = CommitmentFailingPersistence(failAt: failingSave)
            let store = make(auth, client, persistence)
            store.setActor(fixture.actor)
            await store.refresh()
            await store.preview(fixture.draft)
            await store.submit(fixture.create)
            XCTAssertTrue(client.requests.isEmpty)
            XCTAssertTrue(store.storageBlocked)
        }
    }

    func testBackgroundedMutationKeepsExactRequestAfterSuccessOrRejection() async throws {
        for rejection in [false, true] {
            let fixture = try CommitmentStoreFixture()
            let client = CommitmentStoreClient(fixture)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let persistence = FilePendingPerformanceCommitmentRequestStore(directory: directory)
            let store = make(CommitmentStoreAuth(fixture.actor), client, persistence)
            store.setActor(fixture.actor)
            await store.refresh()
            await store.preview(fixture.draft)
            client.suspendSubmit = true
            client.rejectSubmission = rejection
            let submit = Task { await store.submit(fixture.create) }
            while client.submitContinuation == nil { await Task.yield() }
            let saved = try XCTUnwrap(store.pending)
            XCTAssertTrue(saved.mayHaveCommitted)
            store.clearVisibleContent()
            client.submitContinuation?.resume()
            client.submitContinuation = nil
            await submit.value
            let disk = try await FilePendingPerformanceCommitmentRequestStore(directory: directory).load(for: fixture.actor)
            XCTAssertEqual(disk, saved, "A background reply must not delete the durable request")
            XCTAssertEqual(store.pending, saved)
            XCTAssertTrue(store.agreements.isEmpty)
            XCTAssertTrue(store.lifecycles.isEmpty)
            XCTAssertTrue(client.detailIDs.isEmpty, "A stale mutation reply must not start receipt reads")
            XCTAssertNil(store.lastConfirmedID)
            client.rejectSubmission = false
            await store.refresh()
            XCTAssertEqual(client.requests.count, 1)
            await store.retry()
            XCTAssertNil(store.pending)
            XCTAssertEqual(client.commits, 1)
            XCTAssertEqual(client.requests.map(\.requestBody), [saved.requestBody, saved.requestBody])
        }
    }

    func testBackgroundedReceiptReadKeepsDurableRequestAndRejectsLateContent() async throws {
        let fixture = try CommitmentStoreFixture()
        let client = CommitmentStoreClient(fixture)
        let persistence = EphemeralPendingPerformanceCommitmentRequestStore()
        let store = make(CommitmentStoreAuth(fixture.actor), client, persistence)
        store.setActor(fixture.actor)
        await store.refresh()
        await store.preview(fixture.draft)
        client.suspendDetail = true
        let submit = Task { await store.submit(fixture.create) }
        while client.detailContinuation == nil { await Task.yield() }
        let saved = try XCTUnwrap(store.pending)
        store.clearVisibleContent()
        client.detailContinuation?.resume()
        client.detailContinuation = nil
        await submit.value
        let disk = await persistence.load(for: fixture.actor)
        XCTAssertEqual(disk, saved)
        XCTAssertTrue(store.agreements.isEmpty)
        XCTAssertTrue(store.lifecycles.isEmpty)
        XCTAssertNil(store.lastConfirmedID)
    }

    func testReviewAndCancellationClockPreservesLastMicrosecondAndClosesAtBoundary() async throws {
        for label in ["corrected_notices", "scheduled_no_worker"] {
            let fixture = try CommitmentStoreFixture(label: label)
            let client = CommitmentStoreClient(fixture)
            client.exists = true
            let isReview = label == "corrected_notices"
            let before = try PerformanceCommitmentInstant(isReview
                ? "2026-07-12T12:00:00.123455+00:00" : "2026-05-02T12:00:00.123455+00:00")
            client.lifecycleOverride = PerformanceCommitmentLifecycle(commitmentID: fixture.lifecycle.commitmentID,
                serverNow: before, activation: fixture.lifecycle.activation, closure: fixture.lifecycle.closure,
                notices: fixture.lifecycle.notices, reviews: fixture.lifecycle.reviews,
                finalResult: fixture.lifecycle.finalResult, simulation: fixture.lifecycle.simulation,
                supportReceipts: fixture.lifecycle.supportReceipts)
            let store = make(CommitmentStoreAuth(fixture.actor), client)
            store.setActor(fixture.actor)
            await store.refresh()
            let received = try XCTUnwrap(store.lifecycleReceivedAt[fixture.agreement.id])
            XCTAssertEqual(store.estimatedNow(for: fixture.agreement.id, at: received)?.microseconds, before.microseconds)
            let cutoff = received.addingTimeInterval(0.000001)
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(store.estimatedNow(for: fixture.agreement.id, at: cutoff)).microseconds,
                                        before.microseconds + 1)
            if isReview {
                XCTAssertTrue(store.canFileReview(fixture.agreement.id, revision: 2, at: received))
                XCTAssertFalse(store.canFileReview(fixture.agreement.id, revision: 2, at: cutoff))
            } else {
                XCTAssertTrue(store.canClose(fixture.agreement.id, reason: .cancel, at: received))
                XCTAssertFalse(store.canClose(fixture.agreement.id, reason: .cancel, at: cutoff))
            }
        }
    }

    func testFailedListDetailAndLifecycleClearAllOwnerContent() async throws {
        for read in ["list", "detail", "lifecycle"] {
            let fixture = try CommitmentStoreFixture()
            let client = CommitmentStoreClient(fixture)
            client.exists = true
            let store = make(CommitmentStoreAuth(fixture.actor), client)
            store.setActor(fixture.actor)
            await store.refresh()
            XCTAssertFalse(store.agreements.isEmpty)
            client.failRead = read
            if read == "list" { await store.refresh() }
            else { await store.refreshDetail(fixture.agreement.id) }
            XCTAssertTrue(store.agreements.isEmpty, read)
            XCTAssertTrue(store.lifecycles.isEmpty, read)
            XCTAssertTrue(store.freshIDs.isEmpty, read)
        }
    }

    func testFinalResultDespiteOpenAgreementPreventsReviewAndSafeExit() async throws {
        let fixture = try CommitmentStoreFixture(label: "final_pending_simulation")
        let client = CommitmentStoreClient(fixture)
        client.exists = true
        let store = make(CommitmentStoreAuth(fixture.actor), client)
        store.setActor(fixture.actor)
        await store.refresh()
        XCTAssertEqual(store.agreements.first?.status, .open)
        XCTAssertNotNil(store.lifecycles[fixture.agreement.id]?.finalResult)
        XCTAssertNil(store.lifecycles[fixture.agreement.id]?.simulation)
        XCTAssertFalse(store.canClose(fixture.agreement.id, reason: .injury))
        XCTAssertFalse(store.canFileReview(fixture.agreement.id, revision: 2))
        await store.submit(.close(commitmentID: fixture.agreement.id, reason: .injury))
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testActorAToBToARejectsSuspendedOldRead() async throws {
        let fixture = try CommitmentStoreFixture()
        let auth = CommitmentStoreAuth(fixture.actor)
        let client = CommitmentStoreClient(fixture)
        client.exists = true
        client.suspendList = true
        let store = make(auth, client)
        store.setActor(fixture.actor)
        let old = Task { await store.refresh() }
        await client.waitUntilListSuspended()
        let other = UUID()
        auth.actor = other
        store.setActor(other)
        auth.actor = fixture.actor
        store.setActor(fixture.actor)
        client.resumeList()
        await old.value
        XCTAssertTrue(store.agreements.isEmpty)
        XCTAssertTrue(store.lifecycles.isEmpty)
    }

    func testLatestRefreshWinsOverEarlierSuspendedResponse() async throws {
        let fixture = try CommitmentStoreFixture()
        let client = CommitmentStoreClient(fixture)
        client.exists = true
        client.suspendList = true
        let store = make(CommitmentStoreAuth(fixture.actor), client)
        store.setActor(fixture.actor)
        let first = Task { await store.refresh() }
        await client.waitUntilListSuspended()
        client.exists = false
        await store.refresh()
        client.resumeList()
        await first.value
        XCTAssertTrue(store.agreements.isEmpty)
        XCTAssertTrue(store.lifecycles.isEmpty)
        XCTAssertFalse(store.isLoading)
    }

    func testAuthRevocationDetectedWithoutAppEventClearsState() async throws {
        let fixture = try CommitmentStoreFixture()
        let auth = CommitmentStoreAuth(fixture.actor)
        let client = CommitmentStoreClient(fixture)
        client.exists = true
        let store = make(auth, client)
        store.setActor(fixture.actor)
        await store.refresh()
        client.suspendList = true
        let read = Task { await store.refresh() }
        await client.waitUntilListSuspended()
        auth.actor = nil
        client.resumeList()
        await read.value
        XCTAssertNil(store.actorID)
        XCTAssertTrue(store.agreements.isEmpty)
        XCTAssertTrue(store.lifecycles.isEmpty)
        XCTAssertFalse(store.canStartRequest)
    }

    func testEditingOrBackgroundingInvalidatesSuspendedPreview() async throws {
        for background in [false, true] {
            let fixture = try CommitmentStoreFixture()
            let client = CommitmentStoreClient(fixture)
            let store = make(CommitmentStoreAuth(fixture.actor), client)
            store.setActor(fixture.actor)
            await store.refresh()
            client.suspendPreview = true
            let preview = Task { await store.preview(fixture.draft) }
            while client.previewContinuation == nil { await Task.yield() }
            if background { store.clearVisibleContent() } else { store.invalidatePreview() }
            client.previewContinuation?.resume()
            client.previewContinuation = nil
            await preview.value
            XCTAssertNil(store.previewedTerms)
            XCTAssertFalse(store.isPreviewing)
        }
    }

    func testChangedDraftCannotReuseConsentPreview() async throws {
        let fixture = try CommitmentStoreFixture()
        let client = CommitmentStoreClient(fixture)
        let store = make(CommitmentStoreAuth(fixture.actor), client)
        store.setActor(fixture.actor)
        await store.refresh()
        await store.preview(fixture.draft)
        let changed = PerformanceCommitmentDraft(targetSeconds: fixture.draft.targetSeconds + 1,
            startsAt: fixture.draft.startsAt, deadlineAt: fixture.draft.deadlineAt,
            displayTimezone: fixture.draft.displayTimezone)
        await store.submit(.create(draft: changed, termsDigest: fixture.preview.termsDigest, consent: true))
        XCTAssertTrue(client.requests.isEmpty)
    }

    func testMismatchedReviewReceiptIsRetainedForExactRecovery() async throws {
        let fixture = try CommitmentStoreFixture()
        let client = CommitmentStoreClient(fixture)
        client.exists = true
        let store = make(CommitmentStoreAuth(fixture.actor), client)
        store.setActor(fixture.actor)
        await store.refresh()
        XCTAssertTrue(store.canFileReview(fixture.agreement.id, revision: 2))
        await store.submit(.fileReview(commitmentID: fixture.agreement.id, revision: 2, reason: .wrongResult))
        XCTAssertNotNil(store.pending)
        XCTAssertTrue(store.agreements.isEmpty)
        XCTAssertNil(store.lastConfirmedID)
        XCTAssertEqual(client.detailIDs.last, fixture.agreement.id, "A case UUID is never a commitment destination")
    }

    func testFileStorageRejectsReplacementTamperingAndDeletionResurrection() async throws {
        let fixture = try CommitmentStoreFixture()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FilePendingPerformanceCommitmentRequestStore(directory: directory)
        var request = try PendingPerformanceCommitmentRequest(actorID: fixture.actor, operation: fixture.create)
        try await persistence.save(request)
        request.mayHaveCommitted = true
        try await persistence.save(request)
        let loaded = try await FilePendingPerformanceCommitmentRequestStore(directory: directory).load(for: fixture.actor)
        XCTAssertEqual(loaded, request)
        var replacement = request
        replacement.mayHaveCommitted = false
        do { try await persistence.save(replacement); XCTFail("Uncertainty cannot be erased") } catch {}
        let path = directory.appendingPathComponent("\(fixture.actor.uuidString.lowercased()).json")
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
        raw["kind"] = "duel_request_v1"
        try JSONSerialization.data(withJSONObject: raw).write(to: path)
        do { _ = try await persistence.load(for: fixture.actor); XCTFail("Wrong namespace") } catch {}
        try await persistence.remove(for: fixture.actor, matching: nil)
        do { try await persistence.save(request); XCTFail("Deletion must fence queued saves") } catch {}
    }

    private func make(_ auth: CommitmentStoreAuth, _ client: CommitmentStoreClient,
                      _ pending: any PendingPerformanceCommitmentRequestStore = EphemeralPendingPerformanceCommitmentRequestStore()) -> PerformanceCommitmentStore {
        PerformanceCommitmentStore(enabled: true, auth: auth, client: client, pendingStore: pending)
    }
}

struct CommitmentStoreFixture: Decodable {
    let preview: PerformanceCommitmentPreview
    let agreement: PerformanceCommitmentAgreement
    let lifecycle: PerformanceCommitmentLifecycle
    var actor: UUID { agreement.actorID }
    var draft: PerformanceCommitmentDraft {
        PerformanceCommitmentDraft(targetSeconds: agreement.targetSeconds, startsAt: agreement.startsAt,
            deadlineAt: agreement.deadlineAt, displayTimezone: agreement.displayTimezone)
    }
    var create: PerformanceCommitmentMutation { .create(draft: draft, termsDigest: preview.termsDigest, consent: true) }
    init(label: String = "corrected_notices") throws {
        struct Document: Decodable {
            let label: String
            let agreement: PerformanceCommitmentAgreement
            let lifecycle: PerformanceCommitmentLifecycle
        }
        struct File: Decodable { let preview: PerformanceCommitmentPreview; let documents: [Document] }
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/performance-commitment-v1.json")
        let file = try JSONDecoder().decode(File.self, from: Data(contentsOf: path))
        let document = try XCTUnwrap(file.documents.first { $0.label == label })
        preview = file.preview
        agreement = document.agreement
        lifecycle = document.lifecycle
    }
}

@MainActor
private final class CommitmentStoreAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}

@MainActor
private final class CommitmentStoreClient: PerformanceCommitmentClient {
    let fixture: CommitmentStoreFixture
    var exists = false
    var admission = true
    var commits = 0
    var loseResponse = false
    var requests: [PendingPerformanceCommitmentRequest] = []
    var detailIDs: [UUID] = []
    var receipts: [UUID: PerformanceCommitmentMutationReceipt] = [:]
    var failRead: String?
    var suspendList = false
    var listContinuation: CheckedContinuation<Void, Never>?
    var suspendPreview = false
    var previewContinuation: CheckedContinuation<Void, Never>?
    var suspendSubmit = false
    var submitContinuation: CheckedContinuation<Void, Never>?
    var rejectSubmission = false
    var suspendDetail = false
    var detailContinuation: CheckedContinuation<Void, Never>?
    var lifecycleOverride: PerformanceCommitmentLifecycle?
    init(_ fixture: CommitmentStoreFixture) { self.fixture = fixture }
    func preview(_ draft: PerformanceCommitmentDraft, actorID: UUID) async throws -> PerformanceCommitmentPreview {
        if suspendPreview { await withCheckedContinuation { previewContinuation = $0 } }
        return fixture.preview
    }
    func list(actorID: UUID, before: PerformanceCommitmentAgreement?) async throws -> [PerformanceCommitmentAgreement] {
        let rows = exists ? [fixture.agreement] : []
        if suspendList {
            suspendList = false
            await withCheckedContinuation { listContinuation = $0 }
        }
        if failRead == "list" { throw PerformanceCommitmentClientError.accessDenied }
        return rows
    }
    func detail(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentAgreement {
        detailIDs.append(id)
        if suspendDetail {
            suspendDetail = false
            await withCheckedContinuation { detailContinuation = $0 }
        }
        if failRead == "detail" { throw PerformanceCommitmentClientError.unavailable }
        return fixture.agreement
    }
    func lifecycle(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentLifecycle {
        if failRead == "lifecycle" { throw PerformanceCommitmentClientError.accountChanged }
        return lifecycleOverride ?? fixture.lifecycle
    }
    func submit(_ request: PendingPerformanceCommitmentRequest) async throws -> PerformanceCommitmentMutationReceipt {
        requests.append(request)
        if let receipt = receipts[request.requestID] { return receipt }
        if suspendSubmit {
            suspendSubmit = false
            await withCheckedContinuation { submitContinuation = $0 }
        }
        if rejectSubmission { throw PerformanceCommitmentClientError.accessDenied }
        guard admission else { throw PerformanceCommitmentClientError.accessDenied }
        exists = true
        commits += 1
        let receipt: PerformanceCommitmentMutationReceipt
        if case .fileReview = request.operation {
            receipt = .review(PerformanceCommitmentReviewReceipt(caseID: UUID(), recordedAt: fixture.lifecycle.serverNow))
        } else { receipt = .commitment(fixture.agreement.id) }
        receipts[request.requestID] = receipt
        if loseResponse { loseResponse = false; throw PerformanceCommitmentClientError.unavailable }
        return receipt
    }
    func waitUntilListSuspended() async { while listContinuation == nil { await Task.yield() } }
    func resumeList() { listContinuation?.resume(); listContinuation = nil }
}

private actor CommitmentFailingPersistence: PendingPerformanceCommitmentRequestStore {
    let failAt: Int
    var saves = 0
    var request: PendingPerformanceCommitmentRequest?
    init(failAt: Int) { self.failAt = failAt }
    func load(for actorID: UUID) -> PendingPerformanceCommitmentRequest? { request }
    func save(_ request: PendingPerformanceCommitmentRequest) throws {
        saves += 1
        if saves == failAt { throw PerformanceCommitmentClientError.storage }
        self.request = request
    }
    func remove(for actorID: UUID, matching requestID: UUID?) { request = nil }
}
