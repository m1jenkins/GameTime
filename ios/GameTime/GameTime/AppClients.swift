import Foundation

struct AuthSnapshot: Equatable, Sendable {
    let userID: UUID?
}

struct AppleIdentity: Equatable, Sendable {
    let idToken: String
    let rawNonce: String
    let firstSignInDisplayName: String?
}

@MainActor
protocol AuthClient: AnyObject {
    func currentUserID() async -> UUID?
    func authStateChanges() async -> AsyncStream<AuthSnapshot>
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID
    func signOut() async throws
}

@MainActor
protocol ProfileClient: AnyObject {
    func currentProfile(userID: UUID) async throws -> UserProfile?
    func createProfile(
        userID: UUID,
        handle: String,
        displayName: String,
        timezone: String
    ) async throws -> UserProfile
}

@MainActor
protocol FriendshipsClient: AnyObject {
    func listCards() async throws -> [FriendshipCard]
    func findExactHandle(_ handle: String) async throws -> ProfileCard?
    func requestFriendship(callerID: UUID, otherUserID: UUID) async throws
    func acceptFriendship(callerID: UUID, otherUserID: UUID) async throws
    func removeFriendship(callerID: UUID, otherUserID: UUID) async throws
}

@MainActor
protocol ContestsClient: AnyObject {
    func listContests(userID: UUID) async throws -> [ContestCard]
    func listCharities() async throws -> [Charity]
    func standings(contestID: UUID) async throws -> ChallengeStandings?
    func createChallenge(
        _ terms: ChallengeTerms,
        expectedUserID: UUID
    ) async throws -> UUID
    func acceptInvitation(
        contestID: UUID,
        userID: UUID,
        timezone: String,
        charityID: UUID
    ) async throws
    func declineInvitation(contestID: UUID, userID: UUID) async throws
}

@MainActor
struct AppServices {
    let auth: any AuthClient
    let profiles: any ProfileClient
    let friendships: any FriendshipsClient
    let contests: any ContestsClient
    let pendingChallenges: any PendingChallengeStore
}
