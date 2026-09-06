import XCTest
@testable import GameTime

@MainActor final class WeeklyNativeTests: XCTestCase {
    private let local = URL(string: "http://127.0.0.1:56321")!
    func testVersionedFixturePreservesMicrosecondsAndAllNamedTargets() throws {
        let row = try weeklyFixture()
        try row.validate(for: row.own.actorID)
        XCTAssertEqual(row.terms.fields.createdAt.rawValue, "2026-09-06T05:00:00.360255Z")
        XCTAssertEqual(row.roster.map(\.displayName), ["Alice", "Bob"])
        XCTAssertEqual(row.roster.map(\.targetSteps), [7000, 7700])
        XCTAssertThrowsError(try row.validate(for: UUID()))
        XCTAssertEqual(row.terms.fields.policy["source"]?.string, "fixture_weekly_steps_v1")
    }
    func testReviewFinalAndRefundWireStatesDecodeWithoutReinterpretingOldPolicies() throws {
        for status in ["review", "final"] {
            for qualification in ["met", "confirmed_miss", "unresolved", "refund"] {
                let row = try weeklyFixture { json in
                    json["status"] = status
                    json["server_now"] = "2026-09-18T05:00:00.360255Z"
                    json["notices"] = [["revision": 1, "recorded_at": "2026-09-17T05:00:00.000000Z", "file_by": "2026-09-19T05:00:00.000000Z", "resolve_by": "2026-09-22T05:00:00.000000Z", "qualification": qualification]]
                    if status == "final" { json["result"] = ["recorded_at": "2026-09-23T05:00:00.000000Z", "qualification": qualification, "reason": "fixture_only"] }
                }
                try row.validate(for: row.own.actorID)
                XCTAssertEqual(row.notices[0].qualification.rawValue, qualification)
                if ["unresolved", "refund"].contains(qualification) { XCTAssertEqual(row.notices[0].qualification.provisionalTitle, "We couldn’t confirm this update yet") }
            }
        }
    }
    func testDefaultOffReleaseAndHostedURLsCannotSend() async throws {
        let row = try weeklyFixture()
        for address in ["https://example.supabase.co", "http://127.0.0.1", "http://127.0.0.1:56321/path", "http://user@localhost:56321", "http://127.0.0.1.example.com:56321"] {
            let client = SupabaseWeeklyClient(enabled: true, localURL: URL(string: address)!, currentSession: { .init(actorID: row.own.actorID, identity: "session-a") }, rpc: { _, _ in XCTFail("Rejected endpoint received a call"); return Data() })
            do { _ = try await client.list(actorID: row.own.actorID); XCTFail("Hosted endpoint admitted") }
            catch { XCTAssertEqual(error as? WeeklyClientError, .accessDenied) }
        }
        XCTAssertFalse(AppConfiguration(environment: .debug, supabaseURL: local, supabasePublishableKey: "fixture", contestMutationsEnabled: false).weeklyRuntimeEnabled)
        XCTAssertFalse(AppConfiguration(environment: .release, supabaseURL: local, supabasePublishableKey: "fixture", contestMutationsEnabled: false, weeklyRequested: true).weeklyRuntimeEnabled)
        XCTAssertTrue(AppConfiguration(environment: .debug, supabaseURL: local, supabasePublishableKey: "fixture", contestMutationsEnabled: false, weeklyRequested: true).weeklyRuntimeEnabled)
    }
    func testLateSameActorDifferentSessionResponseRejected() async throws {
        let row = try weeklyFixture()
        var session = WeeklyClientSession(actorID: row.own.actorID, identity: "original")
        let client = SupabaseWeeklyClient(enabled: true, localURL: local, currentSession: { session }, rpc: { _, _ in
            session = .init(actorID: row.own.actorID, identity: "replacement")
            return try JSONEncoder().encode([row])
        })
        do { _ = try await client.list(actorID: row.own.actorID); XCTFail("Old-session response published") }
        catch { XCTAssertEqual(error as? WeeklyClientError, .accountChanged) }
    }
    func testEveryMutationRoundTripsExactBodyAndRejectsForeignActor() throws {
        let row = try weeklyFixture()
        let actor = try XCTUnwrap(row.terms.fields.creatorId)
        let preview = WeeklyPreview(terms: row.terms, termsDigest: row.termsDigest)
        let operations: [WeeklyMutation] = [.create(preview), .accept(row.id, digest: row.termsDigest), .join(row.id, digest: row.termsDigest), .exit(row.id, kind: .withdrawal), .review(row.id, revision: 1, reason: .wrongTotal), .support(row.id, reason: .privacy), .pause(true), .pilotConsent(false), .progress(row.id, day: "2026-09-07", steps: 0), .share(row.id, friendID: row.own.actorID, enabled: true), .follow(row.id, ownerID: row.own.actorID, offerID: UUID(), decision: .unfollow)]
        for operation in operations {
            let saved = try PendingWeeklyRequest(actorID: actor, operation: operation)
            let restored = try JSONDecoder().decode(PendingWeeklyRequest.self, from: JSONEncoder().encode(saved))
            XCTAssertEqual(restored, saved)
            XCTAssertEqual(restored.requestBody, try operation.body(requestID: saved.requestID))
            XCTAssertThrowsError(try restored.validate(for: UUID()))
            XCTAssertFalse(String(decoding: restored.requestBody, as: UTF8.self).contains("accessToken"))
        }
    }
    func testFileRecoveryPreservesExactBytesAndDeletionFencesLateWrites() async throws {
        let row = try weeklyFixture(), directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let saved = try PendingWeeklyRequest(actorID: row.own.actorID, operation: .accept(row.id, digest: row.termsDigest))
        let original = FilePendingWeeklyRequestStore(directory: directory)
        try await original.save(saved)
        let reopened = FilePendingWeeklyRequestStore(directory: directory)
        let restored = try await reopened.load(for: saved.actorID)
        XCTAssertEqual(restored, saved)
        let foreign = try await reopened.load(for: UUID())
        XCTAssertNil(foreign)
        do { try await reopened.save(PendingWeeklyRequest(actorID: saved.actorID, requestID: saved.requestID, operation: .pause(true))); XCTFail("Changed request overwrote saved payload") } catch {}
        try await reopened.remove(for: saved.actorID, matching: nil)
        do { try await reopened.save(saved); XCTFail("Deleted actor restored request") } catch { XCTAssertEqual(error as? WeeklyClientError, .storage) }
    }
    func testWorkerScheduledInvitationStillAcceptsAndBlockOnlySuppressesAcceptance() async throws {
        let row = try weeklyFixture { $0["status"] = "scheduled" }
        let client = WeeklyTestClient(row), auth = WeeklyTestAuth(row.own.actorID)
        let store = makeStore(auth, client)
        store.setActor(auth.actor); await store.refresh()
        XCTAssertTrue(store.canAccept(row.id))
        client.row = try weeklyFixture { json in
            json["contact_suppressed"] = true; json["roster"] = []
            var terms = json["terms"] as! [String: Any]
            terms.removeValue(forKey: "creatorId"); terms["participants"] = [["participantId": row.own.actorID.uuidString, "targetSteps": row.own.targetSteps]]
            json["terms"] = terms
        }
        await store.refresh()
        XCTAssertFalse(store.canAccept(row.id))
        XCTAssertTrue(store.canDecline(row.id))
        XCTAssertTrue(store.canExit(row.id))
    }
    func testFailedReadClearsSensitiveRowsAndActorChangeRejectsLateResponse() async throws {
        let row = try weeklyFixture(), client = WeeklyTestClient(try weeklyFixture()), auth = WeeklyTestAuth(try weeklyFixture().own.actorID)
        let store = makeStore(auth, client)
        store.setActor(auth.actor); await store.refresh()
        XCTAssertEqual(store.challenges.count, 1)
        client.failure = .unavailable; await store.refresh()
        XCTAssertTrue(store.challenges.isEmpty); XCTAssertTrue(store.freshIDs.isEmpty)
        client.failure = nil
        client.hold = true
        let pending = Task { await store.refresh() }
        for _ in 0..<100 where client.continuation == nil { await Task.yield() }
        let reply = try XCTUnwrap(client.continuation)
        auth.actor = UUID(); store.setActor(auth.actor)
        reply.resume(returning: [row]); await pending.value
        XCTAssertTrue(store.challenges.isEmpty); XCTAssertNil(store.previewed); XCTAssertNil(store.preferences)
    }
    func testUncertainNoCommitRequestCanBeRetiredWithoutBlockingSafeExit() async throws {
        let row = try weeklyFixture(), client = WeeklyTestClient(try weeklyFixture()), auth = WeeklyTestAuth(try weeklyFixture().own.actorID)
        let queue = EphemeralPendingWeeklyRequestStore()
        var request = try PendingWeeklyRequest(actorID: row.own.actorID, operation: .accept(row.id, digest: row.termsDigest))
        request.mayHaveCommitted = true
        try await queue.save(request)
        let store = WeeklyStore(enabled: true, auth: auth, client: client, friendships: WeeklyTestFriends(), pendingStore: queue)
        store.setActor(auth.actor); await store.refresh()
        XCTAssertFalse(store.canStartRequest)
        client.resolution = .init(state: "cancelled", receiptID: nil)
        await store.resolveSavedRequest()
        XCTAssertNil(store.pending); XCTAssertTrue(store.canDecline(row.id)); XCTAssertEqual(client.resolved, request.requestID)
    }
    func testPausePreservesExistingReviewAndSupport() async throws {
        let row = try weeklyFixture { json in
            json["status"] = "review"; json["server_now"] = "2026-09-18T05:00:00.000001Z"
            json["notices"] = [["revision": 1, "recorded_at": "2026-09-17T05:00:00.000000Z", "file_by": "2026-09-19T05:00:00.000000Z", "resolve_by": "2026-09-22T05:00:00.000000Z", "qualification": "unresolved"]]
        }
        let client = WeeklyTestClient(row), auth = WeeklyTestAuth(row.own.actorID)
        client.paused = true
        let store = makeStore(auth, client)
        store.setActor(auth.actor); await store.refresh()
        XCTAssertFalse(store.canEnter); XCTAssertTrue(store.canReview(row.id, revision: 1)); XCTAssertTrue(store.canExit(row.id))
    }
    func testMonotonicFreshnessExpiresWithoutTrustingDeviceWallClock() async throws {
        let row = try weeklyFixture(), client = WeeklyTestClient(try weeklyFixture()), auth = WeeklyTestAuth(try weeklyFixture().own.actorID)
        var uptime: Double = 1000
        let store = WeeklyStore(enabled: true, auth: auth, client: client, friendships: WeeklyTestFriends(), pendingStore: EphemeralPendingWeeklyRequestStore(), monotonicNow: { uptime })
        store.setActor(auth.actor); await store.refresh()
        uptime = 1060
        XCTAssertNotNil(store.estimatedNow(row))
        uptime = 1060.001
        XCTAssertNil(store.estimatedNow(row)); XCTAssertFalse(store.canAccept(row.id))
        uptime = 999
        XCTAssertNil(store.estimatedNow(row))
        uptime = .nan
        XCTAssertNil(store.estimatedNow(row))
    }
    func testOptionalStudyFailureDoesNotOwnOrBlockSafetyRequestQueue() async throws {
        let row = try weeklyFixture(), client = WeeklyTestClient(try weeklyFixture()), auth = WeeklyTestAuth(try weeklyFixture().own.actorID)
        client.pilotConsent = true
        let store = makeStore(auth, client)
        store.setActor(auth.actor); await store.refresh()
        await store.recordStudy(event: "result_view", challengeID: row.id, phase: "exposure")
        XCTAssertTrue(store.studyUnavailable); XCTAssertNil(store.pending); XCTAssertTrue(store.canExit(row.id))
        store.setActor(nil)
        XCTAssertFalse(store.studyUnavailable); XCTAssertTrue(store.sharedProgress.isEmpty); XCTAssertTrue(store.followRequests.isEmpty)
    }
    func testForegroundSocialExpiryRemovesRevokedPrivateCardsAndOffers() async throws {
        let row = try weeklyFixture(), client = WeeklyTestClient(try weeklyFixture()), auth = WeeklyTestAuth(try weeklyFixture().own.actorID)
        var uptime: Double = 1000
        let owner = UUID(), offer = UUID()
        client.sharedRows = [.init(challengeID: row.id, ownerID: owner, displayName: "Private friend", offerID: offer, startsAt: row.terms.fields.startsAt, endsAt: row.terms.fields.endsAt, timezone: "America/Chicago", targetSteps: 7000, observedSteps: 123, updatedAt: row.serverNow, source: "client_progress_only", policyVersion: "weekly-display-sharing-v1")]
        client.offers = [.init(challengeID: UUID(), ownerID: owner, displayName: "Private friend", offerID: UUID(), policyVersion: "weekly-display-sharing-v1", state: "pending")]
        let store = WeeklyStore(enabled: true, auth: auth, client: client, friendships: WeeklyTestFriends(), pendingStore: EphemeralPendingWeeklyRequestStore(), monotonicNow: { uptime })
        store.setActor(auth.actor); await store.refresh()
        XCTAssertEqual(store.sharedProgress.count, 1); XCTAssertEqual(store.followRequests.count, 1)
        // Remote revocation cannot reach an idle/offline phone; expire its display.
        client.sharedRows = []; client.offers = []
        uptime = 1060; store.expireSocialIfNeeded()
        XCTAssertTrue(store.sharedProgress.isEmpty); XCTAssertTrue(store.followRequests.isEmpty); XCTAssertTrue(store.sharing.isEmpty)
        await store.refresh()
        XCTAssertTrue(store.sharedProgress.isEmpty)
    }
    func testHungFollowResponseCannotPublishExpiredPartialSnapshot() async throws {
        let row = try weeklyFixture(), client = WeeklyTestClient(try weeklyFixture()), auth = WeeklyTestAuth(try weeklyFixture().own.actorID)
        var uptime: Double = 1000
        client.sharedRows = [.init(challengeID: row.id, ownerID: UUID(), displayName: "Private friend", offerID: UUID(), startsAt: row.terms.fields.startsAt, endsAt: row.terms.fields.endsAt, timezone: "America/Chicago", targetSteps: 7000, observedSteps: 123, updatedAt: row.serverNow, source: "client_progress_only", policyVersion: "weekly-display-sharing-v1")]
        client.holdOffers = true
        let store = WeeklyStore(enabled: true, auth: auth, client: client, friendships: WeeklyTestFriends(), pendingStore: EphemeralPendingWeeklyRequestStore(), monotonicNow: { uptime })
        store.setActor(auth.actor)
        let refresh = Task { await store.refresh() }
        for _ in 0..<100 where client.offersContinuation == nil { await Task.yield() }
        let response = try XCTUnwrap(client.offersContinuation)
        XCTAssertTrue(store.sharedProgress.isEmpty)
        uptime = 1061; response.resume(returning: [])
        await refresh.value
        XCTAssertTrue(store.sharedProgress.isEmpty); XCTAssertTrue(store.followRequests.isEmpty)
    }
    func testHeldOptionalStudyDeliveryLeavesSafetyActionsAvailable() async throws {
        let row = try weeklyFixture(), client = WeeklyTestClient(try weeklyFixture()), auth = WeeklyTestAuth(try weeklyFixture().own.actorID)
        client.pilotConsent = true; client.holdStudy = true; client.submitSucceeds = true
        let store = makeStore(auth, client)
        store.setActor(auth.actor); await store.refresh()
        let recording = Task { await store.submit(.progress(row.id, day: "2026-09-07", steps: 0)) }
        for _ in 0..<100 where client.studyContinuation == nil { await Task.yield() }
        let response = try XCTUnwrap(client.studyContinuation)
        XCTAssertTrue(store.canStartRequest); XCTAssertTrue(store.canExit(row.id)); XCTAssertNil(store.pending)
        auth.actor = UUID(); store.setActor(auth.actor)
        response.resume(throwing: WeeklyClientError.unavailable)
        await recording.value
        XCTAssertFalse(store.studyUnavailable, "Old-actor study failure cannot change new-account state")
    }
    func testMissingFixtureSourceCannotExposeACompletenessCount() throws {
        let noSource = try weeklyFixture { $0["own_progress"] = ["status": "client_progress_only", "observed_steps": 0, "qualifying_steps": NSNull(), "complete_day_count": NSNull(), "updated_at": NSNull()] }
        XCTAssertNoThrow(try noSource.validate(for: noSource.own.actorID))
        let inventedCompleteness = try weeklyFixture { $0["own_progress"] = ["status": "client_progress_only", "observed_steps": 0, "qualifying_steps": NSNull(), "complete_day_count": 0, "updated_at": NSNull()] }
        XCTAssertThrowsError(try inventedCompleteness.validate(for: inventedCompleteness.own.actorID))
    }
    func testChangedDraftRejectsDelayedPreviewBeforeConsent() async throws {
        let row = try weeklyFixture { json in json["own"] = (json["roster"] as! [[String: Any]])[0] }
        let actor = row.own.actorID, client = WeeklyTestClient(row), auth = WeeklyTestAuth(row.own.actorID)
        let friend = try XCTUnwrap(row.roster.first { $0.actorID != actor })
        let friends = WeeklyTestFriends([.init(otherUserID: friend.actorID, handle: "fictional_friend", displayName: "Fictional friend", status: .accepted, requestedBy: actor, createdAt: Date(), updatedAt: Date(), acceptedAt: Date())])
        let store = WeeklyStore(enabled: true, auth: auth, client: client, friendships: friends, pendingStore: EphemeralPendingWeeklyRequestStore())
        store.setActor(actor); await store.refresh()
        client.holdPreview = true
        let draft = WeeklyDraft(participants: row.terms.fields.participants!.map { .init(actorID: $0.id, targetSteps: $0.targetSteps) }, weekStart: "2026-09-07", timezone: "America/Chicago")
        let operation = Task { await store.preview(draft) }
        for _ in 0..<100 where client.previewContinuation == nil { await Task.yield() }
        let reply = try XCTUnwrap(client.previewContinuation)
        XCTAssertTrue(store.isLoading); XCTAssertFalse(store.canEnter); XCTAssertFalse(store.canStartRequest)
        let oldPreview = WeeklyPreview(terms: row.terms, termsDigest: row.termsDigest)
        reply.resume(returning: oldPreview); await operation.value
        XCTAssertTrue(store.previewed == oldPreview, "An unchanged exact draft may become reviewable")
        store.invalidatePreview(); client.previewContinuation = nil
        let changedDraft = Task { await store.preview(draft) }
        for _ in 0..<100 where client.previewContinuation == nil { await Task.yield() }
        let changedReply = try XCTUnwrap(client.previewContinuation)
        store.invalidatePreview() // Editing the draft invalidates the original read.
        changedReply.resume(returning: oldPreview); await changedDraft.value
        XCTAssertNil(store.previewed); XCTAssertFalse(store.isLoading)
        await store.submit(.create(oldPreview))
        XCTAssertTrue(store.pending == nil); XCTAssertEqual(client.submitted, 0)
        client.previewContinuation = nil
        let lateActor = Task { await store.preview(draft) }
        for _ in 0..<100 where client.previewContinuation == nil { await Task.yield() }
        let lateReply = try XCTUnwrap(client.previewContinuation)
        auth.actor = UUID(); store.setActor(auth.actor)
        lateReply.resume(returning: oldPreview); await lateActor.value
        XCTAssertNil(store.previewed); XCTAssertTrue(store.friends.isEmpty)
    }
    func testScheduledExpiryCallbackClearsPrivateSnapshotWithoutUserAction() async throws {
        let row = try weeklyFixture { json in json["own"] = (json["roster"] as! [[String: Any]])[0] }
        let client = WeeklyTestClient(row), auth = WeeklyTestAuth(row.own.actorID), friend = UUID(), offer = UUID()
        var uptime: Double = 1000
        var requestedWait: Double?
        var resumeExpiry: CheckedContinuation<Void, any Error>?
        client.sharedRows = [.init(challengeID: row.id, ownerID: friend, displayName: "Private friend", offerID: offer, startsAt: row.terms.fields.startsAt, endsAt: row.terms.fields.endsAt, timezone: "America/Chicago", targetSteps: 7000, observedSteps: 123, updatedAt: row.serverNow, source: "client_progress_only", policyVersion: "weekly-display-sharing-v1")]
        client.offers = [.init(challengeID: UUID(), ownerID: friend, displayName: "Private friend", offerID: UUID(), policyVersion: "weekly-display-sharing-v1", state: "pending")]
        client.grantRows = [.init(friendID: friend, displayName: "Private friend", enabled: true, offerID: offer, state: "accepted")]
        let store = WeeklyStore(enabled: true, auth: auth, client: client, friendships: WeeklyTestFriends(), pendingStore: EphemeralPendingWeeklyRequestStore(), monotonicNow: { uptime }, waitForSocialExpiry: { seconds in
            requestedWait = seconds
            try await withCheckedThrowingContinuation { resumeExpiry = $0 }
        })
        store.setActor(auth.actor); await store.refresh()
        for _ in 0..<100 where resumeExpiry == nil { await Task.yield() }
        let resume = try XCTUnwrap(resumeExpiry)
        XCTAssertEqual(try XCTUnwrap(requestedWait), 60, accuracy: 0.001)
        XCTAssertEqual(store.sharedProgress.count, 1); XCTAssertEqual(store.followRequests.count, 1)
        XCTAssertEqual(store.sharing[row.id]?.count, 1)
        uptime = 1060; resume.resume()
        for _ in 0..<100 where !store.sharedProgress.isEmpty { await Task.yield() }
        XCTAssertTrue(store.sharedProgress.isEmpty); XCTAssertTrue(store.followRequests.isEmpty); XCTAssertTrue(store.sharing.isEmpty)
    }
    private func makeStore(_ auth: WeeklyTestAuth, _ client: WeeklyTestClient) -> WeeklyStore {
        WeeklyStore(enabled: true, auth: auth, client: client, friendships: WeeklyTestFriends(), pendingStore: EphemeralPendingWeeklyRequestStore())
    }
}

func weeklyFixture(_ change: ((inout [String: Any]) -> Void)? = nil) throws -> WeeklyChallenge {
    let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/weekly-native-v1.json")
    var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
    change?(&json)
    return try JSONDecoder().decode(WeeklyChallenge.self, from: JSONSerialization.data(withJSONObject: json))
}
@MainActor final class WeeklyTestAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}
@MainActor final class WeeklyTestFriends: FriendshipsClient {
    let cards: [FriendshipCard]
    init(_ cards: [FriendshipCard] = []) { self.cards = cards }
    func listCards() async throws -> [FriendshipCard] { cards }
    func findExactHandle(_ handle: String) async throws -> ProfileCard? { nil }
    func requestFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func acceptFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func removeFriendship(callerID: UUID, otherUserID: UUID) async throws {}
}
@MainActor final class WeeklyTestClient: WeeklyClient {
    var row: WeeklyChallenge; var failure: WeeklyClientError?; var hold = false; var paused = false; var pilotConsent = false
    var continuation: CheckedContinuation<[WeeklyChallenge], any Error>?
    var resolution = WeeklyRequestResolution(state: "cancelled", receiptID: nil)
    var resolved: UUID?
    var cohortRows: [WeeklyCohort] = []
    var sharedRows: [WeeklySharedProgress] = []
    var grantRows: [WeeklySharing] = []
    func sharing(id: UUID, actorID: UUID) async throws -> [WeeklySharing] { grantRows }
    var offers: [WeeklyFollowRequest] = []
    var holdPreview = false
    var previewContinuation: CheckedContinuation<WeeklyPreview, any Error>?
    var submitted = 0
    var submitSucceeds = false
    var holdStudy = false
    var studyContinuation: CheckedContinuation<Void, any Error>?
    func recordPilotEvent(actorID: UUID, challengeID: UUID?, event: String, phase: String, requestID: UUID) async throws {
        if holdStudy { return try await withCheckedThrowingContinuation { studyContinuation = $0 } }
        throw WeeklyClientError.unavailable
    }
    var holdOffers = false
    var offersContinuation: CheckedContinuation<[WeeklyFollowRequest], any Error>?
    func sharedProgress(actorID: UUID) async throws -> [WeeklySharedProgress] { sharedRows }
    func followRequests(actorID: UUID) async throws -> [WeeklyFollowRequest] {
        if holdOffers { return try await withCheckedThrowingContinuation { offersContinuation = $0 } }
        return offers
    }
    init(_ row: WeeklyChallenge) { self.row = row }
    func preview(_ draft: WeeklyDraft, actorID: UUID) async throws -> WeeklyPreview {
        if holdPreview { return try await withCheckedThrowingContinuation { previewContinuation = $0 } }
        throw WeeklyClientError.unavailable
    }
    func list(actorID: UUID) async throws -> [WeeklyChallenge] {
        if let failure { throw failure }
        if hold { return try await withCheckedThrowingContinuation { continuation = $0 } }
        return [row]
    }
    func detail(id: UUID, actorID: UUID) async throws -> WeeklyChallenge { row }
    func cohorts(actorID: UUID) async throws -> [WeeklyCohort] { cohortRows }
    func preferences(actorID: UUID) async throws -> WeeklyPreferences { .init(paused: paused, pilotConsent: pilotConsent) }
    func submit(_ request: PendingWeeklyRequest) async throws -> UUID {
        submitted += 1
        if submitSucceeds { return request.requestID }
        throw WeeklyClientError.lifecycle
    }
    func resolveRequest(_ request: PendingWeeklyRequest) async throws -> WeeklyRequestResolution { resolved = request.requestID; return resolution }
}
