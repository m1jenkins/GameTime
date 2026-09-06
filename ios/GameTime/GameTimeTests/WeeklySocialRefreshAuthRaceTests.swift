import Foundation
import XCTest
@testable import GameTime

@MainActor final class WeeklySocialRefreshAuthRaceTests: XCTestCase {
    func testSupersededFinalAuthCheckCannotRestoreRevokedSocialData() async throws {
        let row = try weeklyFixture()
        let owner = UUID(), offer = UUID()
        let auth = WeeklyHeldFinalAuth(row.own.actorID)
        let client = WeeklyTestClient(row)
        client.sharedRows = [.init(challengeID: row.id, ownerID: owner,
            displayName: "Old fictional friend", offerID: offer,
            startsAt: row.terms.fields.startsAt, endsAt: row.terms.fields.endsAt,
            timezone: "America/Chicago", targetSteps: 7000, observedSteps: 123,
            updatedAt: row.serverNow, source: "client_progress_only",
            policyVersion: "weekly-display-sharing-v1")]
        client.offers = [.init(challengeID: row.id, ownerID: owner,
            displayName: "Old fictional friend", offerID: offer,
            policyVersion: "weekly-display-sharing-v1", state: "pending")]
        let friends = WeeklyArmFinalAuthFriends(auth: auth, cards: [
            .init(otherUserID: owner, handle: "fictional_friend",
                displayName: "Old fictional friend", status: .accepted,
                requestedBy: row.own.actorID, createdAt: Date(), updatedAt: Date(),
                acceptedAt: Date())
        ])
        let store = WeeklyStore(enabled: true, auth: auth, client: client,
            friendships: friends, pendingStore: EphemeralPendingWeeklyRequestStore(),
            monotonicNow: { 1000 })
        store.setActor(row.own.actorID)
        defer { auth.releaseHeldCheck(); store.setActor(nil) }

        let oldRefresh = Task { await store.refresh() }
        // listCards arms exactly the following auth check: all old social reads
        // have finished, but the final publication guard has not returned.
        await auth.waitForHeldCheck()
        XCTAssertEqual(friends.readCount, 1)
        XCTAssertFalse(store.isLoading)
        XCTAssertTrue(store.canExit(row.id), "Optional social work must not block a safe exit")
        XCTAssertTrue(store.sharedProgress.isEmpty, "No partial social snapshot may publish")

        // The account is unchanged. Only a fresh read revokes the old social
        // data, replacing the refresh token and cancelling the suspended task.
        client.sharedRows = []
        client.offers = []
        friends.cards = []
        await store.refresh()
        XCTAssertEqual(friends.readCount, 2)
        XCTAssertEqual(store.challenges.map(\.id), [row.id])
        XCTAssertTrue(store.sharedProgress.isEmpty)
        XCTAssertTrue(store.followRequests.isEmpty)
        XCTAssertTrue(store.friends.isEmpty)

        auth.releaseHeldCheck()
        await oldRefresh.value
        XCTAssertTrue(auth.resumedWhileCancelled, "The old social task must actually be cancelled")
        XCTAssertEqual(store.challenges.map(\.id), [row.id])
        XCTAssertTrue(store.sharedProgress.isEmpty, "A superseded final auth result restored a revoked private total")
        XCTAssertTrue(store.followRequests.isEmpty, "A superseded final auth result restored a revoked follow offer")
        XCTAssertTrue(store.friends.isEmpty, "A superseded final auth result restored a private friend name")
    }
}

@MainActor private final class WeeklyHeldFinalAuth: AuthClient {
    let actor: UUID
    var holdNextCheck = false
    private var heldCheck: CheckedContinuation<UUID?, Never>?
    private var readiness: CheckedContinuation<Void, Never>?
    private(set) var resumedWhileCancelled = false
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? {
        guard holdNextCheck else { return actor }
        holdNextCheck = false
        let result: UUID? = await withCheckedContinuation { continuation in
            heldCheck = continuation
            readiness?.resume(); readiness = nil
        }
        resumedWhileCancelled = Task.isCancelled
        return result
    }
    func waitForHeldCheck() async {
        guard heldCheck == nil else { return }
        await withCheckedContinuation { readiness = $0 }
    }
    func releaseHeldCheck() {
        heldCheck?.resume(returning: actor); heldCheck = nil
    }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor }
    func signOut() async throws {}
}

@MainActor private final class WeeklyArmFinalAuthFriends: FriendshipsClient {
    let auth: WeeklyHeldFinalAuth
    var cards: [FriendshipCard]
    private(set) var readCount = 0
    init(auth: WeeklyHeldFinalAuth, cards: [FriendshipCard]) { self.auth = auth; self.cards = cards }
    func listCards() async throws -> [FriendshipCard] {
        readCount += 1
        if readCount == 1 { auth.holdNextCheck = true }
        return cards
    }
    func findExactHandle(_ handle: String) async throws -> ProfileCard? { nil }
    func requestFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func acceptFriendship(callerID: UUID, otherUserID: UUID) async throws {}
    func removeFriendship(callerID: UUID, otherUserID: UUID) async throws {}
}
