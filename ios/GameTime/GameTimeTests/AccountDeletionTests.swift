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
