import XCTest
import GameTimeCore

@testable import GameTime

@MainActor
final class AccountDeletionTests: XCTestCase {
    func testAcceptedDeletionClearsNewHealthStateAndSignerOnlyForItsOwner() async throws {
        let owner = UUID(), other = UUID()
        let cache = try ChallengeHealthComparisonCache.applicationSupport()
        let uploads = try ChallengeHealthUploadFileStore.applicationSupport()
        let readiness = try ChallengeHealthReadinessFileStore.applicationSupport()
        let diagnostic = try TrustedActivityDiagnosticFileStore.applicationSupport()
        defer {
            for actor in [owner, other] {
                try? cache.clear(actor: actor); try? uploads.clear(actor: actor)
                try? readiness.clear(actor: actor); try? diagnostic.clear(actor: actor)
            }
        }
        for actor in [owner, other] {
            try cache.connect(actor: actor, source: "apple_watch_steps_v1")
            try cache.enqueue(actor: actor, ids: [UUID()])
            try uploads.save(.init(actorID: actor)); try readiness.save(.init(actorID: actor))
            let id = UUID()
            let bytes = try JSONSerialization.data(withJSONObject: ["clientDiagnosticId": id.uuidString.lowercased(), "trustedDeviceSampleCount": 1])
            try diagnostic.save(.init(version: 1, actorID: actor, requestID: id, body: bytes,
                keyID: "owned-test-key", assertion: nextP9TestAssertion(), environment: .development, hourCount: 1, sampleCount: 1))
        }
        let fixture = FixtureServicesFactory.make(arguments: ["GameTimeTests"]), signer = DeletionHealthSigner()
        let cleaner = AccountLocalStateCleaner(pendingChallenges: fixture.pendingChallenges,
            activitySync: fixture.activitySync, pendingPersonalChallenges: fixture.pendingPersonalChallenges,
            pendingPersonalCancellations: fixture.pendingPersonalCancellations, personalActivitySync: fixture.personalActivitySync,
            personalStepSnapshotCache: fixture.personalStepSnapshotCache, appAttestedBodySigner: signer)
        try await cleaner.clear(for: owner)
        XCTAssertTrue(try cache.pending(actor: owner).isEmpty)
        XCTAssertTrue(try cache.connected(actor: owner).isEmpty)
        XCTAssertNil(try diagnostic.load(actor: owner)); XCTAssertEqual(signer.cleared, [owner])
        for directory in [uploads.directory, readiness.directory] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent(owner.uuidString.lowercased() + ".json").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(other.uuidString.lowercased() + ".json").path))
        }
        XCTAssertEqual(try cache.pending(actor: other).count, 1)
        XCTAssertNotNil(try diagnostic.load(actor: other))
    }
    func testReceiptJournalKeepsBothAccountsAndExactSavedRight() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("account-deletion-receipt-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileAccountDeletionReceiptStore(directory: directory)
        let firstOwner = UUID()
        let secondOwner = UUID()
        let firstRequest = AccountDeletionRightsRequest(
            id: UUID(), operation: .review, challengeID: UUID(),
            noticeRevision: 1, reason: "wrong_total"
        )
        try store.save(AccountDeletionReceipt(
            ownerID: firstOwner,
            secret: String(repeating: "a", count: 32),
            pendingRightsRequest: firstRequest
        ))
        try store.save(AccountDeletionReceipt(
            ownerID: secondOwner,
            secret: String(repeating: "b", count: 32)
        ))

        XCTAssertEqual(
            try store.load(for: firstOwner)?.pendingRightsRequest,
            firstRequest
        )
        XCTAssertEqual(try store.loadLatest()?.ownerID, secondOwner)
        try store.remove(for: secondOwner)
        XCTAssertEqual(try store.loadLatest()?.ownerID, firstOwner)
    }

    func testLateDeletionCompletionCannotClearAReplacementAccount() async throws {
        let firstOwner = UUID()
        let replacementOwner = UUID()
        let auth = DeletionSwitchingAuth(actor: firstOwner)
        let deletion = HeldDeletionClient()
        let cleaner = RecordingDeletionCleaner()
        let services = FixtureServicesFactory.make(
            arguments: ["GameTimeTests"],
            authClient: auth,
            accountDeletionClient: deletion,
            accountDeletionReceiptStore: EphemeralAccountDeletionReceiptStore(),
            accountLocalStateCleaner: cleaner,
            profileClient: DeletionProfileClient()
        )
        let model = AppModel(configuration: .fixture, services: services)
        await model.start()
        XCTAssertEqual(model.userID, firstOwner)

        let task = Task {
            try await model.deleteAccount(with: AppleIdentity(
                idToken: "fictional", rawNonce: "fictional",
                firstSignInDisplayName: nil, authorizationCode: "fictional-code"
            ))
        }
        await deletion.waitUntilCalled()
        auth.setActor(replacementOwner)
        deletion.complete()
        _ = try await task.value
        try await Task.sleep(for: .milliseconds(25))

        let currentUserID = await auth.currentUserID()
        XCTAssertEqual(currentUserID, replacementOwner)
        XCTAssertEqual(model.userID, replacementOwner)
        XCTAssertTrue(cleaner.cleanedOwners.isEmpty)
    }

    func testAccountSwitchDuringDeletionCleanupCannotPublishOldNotice() async throws {
        let first = UUID(), second = UUID()
        let auth = DeletionSwitchingAuth(actor: first)
        let cleaner = HeldDeletionCleaner()
        let model = AppModel(configuration: .fixture, services: FixtureServicesFactory.make(
            arguments: ["GameTimeTests"], authClient: auth,
            accountDeletionClient: SequencedDeletionClient(state: .completed),
            accountDeletionReceiptStore: EphemeralAccountDeletionReceiptStore(),
            accountLocalStateCleaner: cleaner, profileClient: DeletionProfileClient()))
        await model.start()
        let deletion = Task { try await model.deleteAccount(with: AppleIdentity(
            idToken: "fictional", rawNonce: "fictional", firstSignInDisplayName: nil,
            authorizationCode: "fictional-code")) }
        let deadline = Date().addingTimeInterval(2)
        while cleaner.held == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertNotNil(cleaner.held)
        auth.setActor(second)
        cleaner.held?.resume(); cleaner.held = nil
        _ = try await deletion.value
        let switchDeadline = Date().addingTimeInterval(2)
        while model.userID != second, Date() < switchDeadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(model.userID, second)
        XCTAssertNil(model.accountDeletionNotice)
        XCTAssertNil(model.accountDeletionReceipt)
        XCTAssertNil(model.accountDeletionStatus)
        XCTAssertEqual(cleaner.owners, [first])
    }

    func testDelayedAccountCleanupCannotEraseANewerInvitation() async throws {
        let pending = HeldDeletionPendingStore()
        let fixture = FixtureServicesFactory.make(arguments: ["GameTimeTests"])
        let cleaner = AccountLocalStateCleaner(pendingChallenges: pending,
            activitySync: fixture.activitySync, pendingPersonalChallenges: fixture.pendingPersonalChallenges,
            pendingPersonalCancellations: fixture.pendingPersonalCancellations,
            personalActivitySync: fixture.personalActivitySync,
            personalStepSnapshotCache: fixture.personalStepSnapshotCache,
            appAttestedBodySigner: UnavailableAppAttestedBodySigner())
        // This is the test host's invitation file; the cleaner owns this location.
        let invitation = ChallengeInvitationIntent()
        let old = URL(string: "gametime-beta://challenge-invite/" + String(repeating: "a", count: 64))!
        let newer = URL(string: "gametime-beta://challenge-invite/" + String(repeating: "b", count: 64))!
        invitation.receive(old)
        defer { invitation.clear() }
        let cleanup = Task { try await cleaner.clear(for: UUID()) }
        await pending.waitUntilRemoving()
        invitation.receive(newer)
        await pending.finish()
        try await cleanup.value
        XCTAssertEqual(ChallengeInvitationIntent().link, newer.absoluteString)
    }

    func testNativeDeletionKeepsTheReceiptForPendingHeldAndCompletedStates() async throws {
        let owner = UUID()
        for state in [
            AccountDeletionProgress.pendingProvider,
            .held,
            .completed,
        ] {
            let auth = DeletionSwitchingAuth(actor: owner)
            let deletion = SequencedDeletionClient(state: state)
            let services = FixtureServicesFactory.make(
                arguments: ["GameTimeTests"],
                authClient: auth,
                accountDeletionClient: deletion,
                accountDeletionReceiptStore: EphemeralAccountDeletionReceiptStore(),
                accountLocalStateCleaner: RecordingDeletionCleaner(),
                profileClient: DeletionProfileClient()
            )
            let model = AppModel(configuration: .fixture, services: services)
            await model.start()
            model.challengeInvitation.link = "gametime-beta://challenge-invite/" + String(repeating: "a", count: 64)

            _ = try await model.deleteAccount(with: AppleIdentity(
                idToken: "fictional", rawNonce: "fictional",
                firstSignInDisplayName: nil, authorizationCode: "fictional-code"
            ))

            XCTAssertEqual(model.accountDeletionStatus?.state, state)
            XCTAssertEqual(model.accountDeletionReceipt?.ownerID, owner)
            XCTAssertNil(model.userID, "\(state) must end ordinary access")
            XCTAssertNil(model.challengesV1.actor)
            XCTAssertTrue(model.challengeInvitation.link.isEmpty)
        }
    }

    func testServerReviewNoticeAndPendingProviderReceiptDecodeThroughTheNativeClient() throws {
        let challengeID = UUID()
        let data = try JSONSerialization.data(
            withJSONObject: [
                "deleted": false,
                "deletion": [
                    "state": "pending_provider",
                    "accepted_at": "2026-09-15T18:00:00.125Z",
                    "account_closed_at": NSNull(),
                    "receipt_expires_at": NSNull(),
                    "holds": ["review": true, "appeal": false],
                    "rights": [
                        "review_notices": [[
                            "challenge_id": challengeID.uuidString.lowercased(),
                            "notice_revision": 3,
                            "review_by": "2026-09-16T18:00:00.125Z",
                        ]],
                        "appeal_available": false,
                        "holds_review_due": true,
                    ],
                    "retained": [[
                        "category": "deletion status receipt",
                        "until": "2026-12-15T18:00:00.125Z",
                        "completed_at": NSNull(),
                    ]],
                ],
            ]
        )

        let status = try SupabaseAccountDeletionClient.decodeStatusResponse(data)
        XCTAssertEqual(status.state, .pendingProvider)
        XCTAssertEqual(status.rights?.reviewNotices, [
            .init(challengeID: challengeID, noticeRevision: 3, reviewBy: "2026-09-16T18:00:00.125Z"),
        ])
        XCTAssertEqual(status.retained.first?.until, "2026-12-15T18:00:00.125Z")
    }

    func testRejectedReviewClearsOnlyThatPendingRequestAndAllowsAnAppeal() async throws {
        let owner = UUID()
        let challengeID = UUID()
        let auth = DeletionSwitchingAuth(actor: owner)
        let deletion = RightsRejectionClient(challengeID: challengeID)
        let services = FixtureServicesFactory.make(
            arguments: ["GameTimeTests"],
            authClient: auth,
            accountDeletionClient: deletion,
            accountDeletionReceiptStore: EphemeralAccountDeletionReceiptStore(),
            accountLocalStateCleaner: RecordingDeletionCleaner(),
            profileClient: DeletionProfileClient()
        )
        let model = AppModel(configuration: .fixture, services: services)
        await model.start()
        _ = try await model.deleteAccount(with: AppleIdentity(
            idToken: "fictional", rawNonce: "fictional",
            firstSignInDisplayName: nil, authorizationCode: "fictional-code"
        ))

        let notice = try XCTUnwrap(deletion.status.rights?.reviewNotices.first)
        do {
            try await model.fileAccountDeletionReview(notice: notice, reason: "wrong_total")
            XCTFail("Expected the stale review right to be rejected")
        } catch {
            XCTAssertEqual(error as? AccountDeletionError, .rejected)
        }
        XCTAssertFalse(model.hasPendingAccountDeletionRightsRequest)

        try await model.fileAccountDeletionAppeal()
        XCTAssertFalse(model.hasPendingAccountDeletionRightsRequest)
        XCTAssertEqual(deletion.reviewCalls, 1)
        XCTAssertEqual(deletion.appealCalls, 1)
    }

    func testReceiptDatesUseFractionalPostgresTimestampsWithoutShowingRawValues() {
        let date = AccountDeletionReceiptDate.display("2026-09-16T18:00:00.125Z")
        XCTAssertNotEqual(date, "2026-09-16T18:00:00.125Z")
        XCTAssertFalse(date.contains("T"))
        XCTAssertNotEqual(date, "Date unavailable")
    }
}

@MainActor
private final class DeletionSwitchingAuth: AuthClient {
    private var actor: UUID?
    private var continuations: [AsyncStream<AuthSnapshot>.Continuation] = []

    init(actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> {
        AsyncStream { continuation in
            continuations.append(continuation)
        }
    }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID {
        _ = identity
        return try XCTUnwrap(actor)
    }
    func signOut() async throws { setActor(nil) }
    func setActor(_ actor: UUID?) {
        self.actor = actor
        continuations.forEach { $0.yield(AuthSnapshot(userID: actor)) }
    }
}

@MainActor
private final class DeletionProfileClient: ProfileClient {
    func currentProfile(userID: UUID) async throws -> UserProfile? {
        UserProfile(id: userID, handle: "fixture", displayName: "Fixture", timezone: "America/Chicago")
    }
    func createProfile(userID: UUID, handle: String, displayName: String, timezone: String) async throws -> UserProfile {
        UserProfile(id: userID, handle: handle, displayName: displayName, timezone: timezone)
    }
}

@MainActor
private final class RecordingDeletionCleaner: AccountLocalStateCleaning {
    private(set) var cleanedOwners: [UUID] = []
    func clear(for ownerID: UUID) async throws { cleanedOwners.append(ownerID) }
}

@MainActor
private final class HeldDeletionClient: AccountDeletionClient {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var wasCalled = false
    private let status = AccountDeletionStatus(
        state: .completed, acceptedAt: nil, accountClosedAt: nil,
        receiptExpiresAt: nil, holds: nil, rights: nil, retained: []
    )

    func deleteAccount(ownerID: UUID, requestID: UUID, receiptSecret: String, appleAuthorizationCode: String) async throws -> AccountDeletionStatus {
        _ = (ownerID, requestID, receiptSecret, appleAuthorizationCode)
        wasCalled = true
        await withCheckedContinuation { continuation = $0 }
        return status
    }
    func resumeAccountDeletion(requestID: UUID, receiptSecret: String, appleAuthorizationCode: String?) async throws -> AccountDeletionStatus {
        _ = (requestID, receiptSecret, appleAuthorizationCode)
        return status
    }
    func accountDeletionStatus(receiptSecret: String) async throws -> AccountDeletionStatus {
        _ = receiptSecret
        return status
    }
    func fileAccountDeletionReview(requestID: UUID, receiptSecret: String, challengeID: UUID, noticeRevision: Int, reason: String) async throws {
        _ = (requestID, receiptSecret, challengeID, noticeRevision, reason)
    }
    func fileAccountDeletionAppeal(requestID: UUID, receiptSecret: String) async throws {
        _ = (requestID, receiptSecret)
    }
    func waitUntilCalled() async {
        while !wasCalled { await Task.yield() }
    }
    func complete() { continuation?.resume(); continuation = nil }
}

@MainActor
private final class SequencedDeletionClient: AccountDeletionClient {
    private let status: AccountDeletionStatus

    init(state: AccountDeletionProgress) {
        status = AccountDeletionStatus(
            state: state, acceptedAt: "2026-09-14T12:00:00Z",
            accountClosedAt: state == .pendingProvider ? nil : "2026-09-14T12:01:00Z",
            receiptExpiresAt: nil, holds: state == .held
                ? .init(review: true, appeal: false) : nil,
            rights: nil, retained: []
        )
    }

    func deleteAccount(ownerID: UUID, requestID: UUID, receiptSecret: String, appleAuthorizationCode: String) async throws -> AccountDeletionStatus {
        _ = (ownerID, requestID, receiptSecret, appleAuthorizationCode)
        return status
    }
    func resumeAccountDeletion(requestID: UUID, receiptSecret: String, appleAuthorizationCode: String?) async throws -> AccountDeletionStatus {
        _ = (requestID, receiptSecret, appleAuthorizationCode)
        return status
    }
    func accountDeletionStatus(receiptSecret: String) async throws -> AccountDeletionStatus {
        _ = receiptSecret
        return status
    }
    func fileAccountDeletionReview(requestID: UUID, receiptSecret: String, challengeID: UUID, noticeRevision: Int, reason: String) async throws {
        _ = (requestID, receiptSecret, challengeID, noticeRevision, reason)
    }
    func fileAccountDeletionAppeal(requestID: UUID, receiptSecret: String) async throws {
        _ = (requestID, receiptSecret)
    }
}

@MainActor
private final class RightsRejectionClient: AccountDeletionClient {
    private(set) var reviewCalls = 0
    private(set) var appealCalls = 0
    let status: AccountDeletionStatus

    init(challengeID: UUID) {
        status = AccountDeletionStatus(
            state: .completed,
            acceptedAt: "2026-09-15T18:00:00.125Z",
            accountClosedAt: "2026-09-15T18:01:00.125Z",
            receiptExpiresAt: "2026-12-15T18:01:00.125Z",
            holds: .init(review: false, appeal: false),
            rights: .init(
                reviewNotices: [
                    .init(
                        challengeID: challengeID,
                        noticeRevision: 1,
                        reviewBy: "2026-09-16T18:00:00.125Z"
                    ),
                ],
                appealAvailable: true,
                holdsReviewDue: false
            ),
            retained: []
        )
    }

    func deleteAccount(ownerID: UUID, requestID: UUID, receiptSecret: String, appleAuthorizationCode: String) async throws -> AccountDeletionStatus {
        _ = (ownerID, requestID, receiptSecret, appleAuthorizationCode)
        return status
    }
    func resumeAccountDeletion(requestID: UUID, receiptSecret: String, appleAuthorizationCode: String?) async throws -> AccountDeletionStatus {
        _ = (requestID, receiptSecret, appleAuthorizationCode)
        return status
    }
    func accountDeletionStatus(receiptSecret: String) async throws -> AccountDeletionStatus {
        _ = receiptSecret
        return status
    }
    func fileAccountDeletionReview(requestID: UUID, receiptSecret: String, challengeID: UUID, noticeRevision: Int, reason: String) async throws {
        _ = (requestID, receiptSecret, challengeID, noticeRevision, reason)
        reviewCalls += 1
        throw AccountDeletionError.rejected
    }
    func fileAccountDeletionAppeal(requestID: UUID, receiptSecret: String) async throws {
        _ = (requestID, receiptSecret)
        appealCalls += 1
    }
}

@MainActor
private final class HeldDeletionCleaner: AccountLocalStateCleaning {
    var held: CheckedContinuation<Void, Never>?
    var owners: [UUID] = []
    func clear(for ownerID: UUID) async throws {
        owners.append(ownerID)
        await withCheckedContinuation { held = $0 }
    }
}

private actor HeldDeletionPendingStore: PendingChallengeStore {
    private var held: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func load(for ownerID: UUID) -> PendingChallengeSubmission? { nil }
    func save(_ submission: PendingChallengeSubmission) {}
    func remove(for ownerID: UUID) async {
        await withCheckedContinuation {
            held = $0
            started?.resume(); started = nil
        }
    }
    func waitUntilRemoving() async {
        if held == nil { await withCheckedContinuation { started = $0 } }
    }
    func finish() { held?.resume(); held = nil }
}

@MainActor private final class DeletionHealthSigner: AppAttestedBodySigning {
    var cleared: [UUID] = []
    func sign(ownerID: UUID, body: Data) async throws -> MetricSignedMaterial { throw URLError(.unsupportedURL) }
    func invalidateRejectedKey(ownerID: UUID, keyID: String) throws {}
    func clearLocalState(for ownerID: UUID) throws { cleared.append(ownerID) }
}
