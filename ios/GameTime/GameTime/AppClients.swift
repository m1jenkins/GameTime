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
    func listChallengeSummaries(userID: UUID) async throws
        -> [ChallengeRosterSummary]
    func listCharities() async throws -> [Charity]
    func standings(contestID: UUID) async throws -> ChallengeStandings?
    func sendComebackReaction(
        contestID: UUID,
        snapshotID: UUID
    ) async throws
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

enum PushTokenEnvironment: String, Codable, Sendable {
    case development
    case production
}

@MainActor
protocol PushNotificationsClient: AnyObject {
    func register(_ registration: PushDeviceRegistration) async throws
    func unregister(_ registration: PushDeviceRegistration) async throws
}

@MainActor
final class DisabledPushNotificationsClient: PushNotificationsClient {
    func register(_ registration: PushDeviceRegistration) async throws {}
    func unregister(_ registration: PushDeviceRegistration) async throws {}
}

@MainActor
struct AppServices {
    let auth: any AuthClient
    let profiles: any ProfileClient
    let friendships: any FriendshipsClient
    let contests: any ContestsClient
    let pendingChallenges: any PendingChallengeStore
    let activitySync: any ActivitySyncing
    let pushNotifications: any PushNotificationsClient
    let personalAccountability: any PersonalAccountabilityClient
    let pendingPersonalChallenges: any PendingPersonalChallengeStore
    let pendingPersonalCancellations: any PendingPersonalCancellationStore
    let trustedActivityDiagnostic: any TrustedActivityDiagnosticClient
    let personalActivitySync: any PersonalActivitySyncing

    init(
        auth: any AuthClient,
        profiles: any ProfileClient,
        friendships: any FriendshipsClient,
        contests: any ContestsClient,
        pendingChallenges: any PendingChallengeStore,
        activitySync: any ActivitySyncing,
        pushNotifications: any PushNotificationsClient =
            DisabledPushNotificationsClient(),
        personalAccountability: any PersonalAccountabilityClient =
            DisabledPersonalAccountabilityClient(),
        pendingPersonalChallenges: any PendingPersonalChallengeStore =
            EphemeralPendingPersonalChallengeStore(),
        pendingPersonalCancellations: any PendingPersonalCancellationStore =
            EphemeralPendingPersonalCancellationStore(),
        trustedActivityDiagnostic: any TrustedActivityDiagnosticClient =
            DisabledTrustedActivityDiagnosticClient(),
        personalActivitySync: any PersonalActivitySyncing =
            DisabledPersonalActivitySyncCoordinator()
    ) {
        self.auth = auth
        self.profiles = profiles
        self.friendships = friendships
        self.contests = contests
        self.pendingChallenges = pendingChallenges
        self.activitySync = activitySync
        self.pushNotifications = pushNotifications
        self.personalAccountability = personalAccountability
        self.pendingPersonalChallenges = pendingPersonalChallenges
        self.pendingPersonalCancellations = pendingPersonalCancellations
        self.trustedActivityDiagnostic = trustedActivityDiagnostic
        self.personalActivitySync = personalActivitySync
    }
}
