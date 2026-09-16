import XCTest

@testable import GameTime

@MainActor
final class AccountDeletionTests: XCTestCase {
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
