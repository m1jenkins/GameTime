import Foundation

struct AuthSnapshot: Equatable, Sendable {
    let userID: UUID?
}

struct AppleIdentity: Equatable, Sendable {
    let idToken: String
    let rawNonce: String
    let firstSignInDisplayName: String?
    let authorizationCode: String?

    init(
        idToken: String,
        rawNonce: String,
        firstSignInDisplayName: String?,
        authorizationCode: String? = nil
    ) {
        self.idToken = idToken
        self.rawNonce = rawNonce
        self.firstSignInDisplayName = firstSignInDisplayName
        self.authorizationCode = authorizationCode
    }
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

enum AccountDeletionResult: Equatable, Sendable {
    case deleted
    case deletedWithLocalCleanupWarning
}

enum AccountDeletionError: LocalizedError, Equatable, Sendable {
    case authenticationRequired
    case authorizationCodeUnavailable
    case accountChanged
    case invalidResponse
    case rejected
    case unavailable

    var errorDescription: String? {
        switch self {
        case .authenticationRequired:
            "Sign in again before deleting your account."
        case .authorizationCodeUnavailable:
            "Apple didn’t return the confirmation needed to delete this account. Try again."
        case .accountChanged:
            "You signed in with a different Apple account. Try again with the account you want to delete."
        case .invalidResponse, .rejected:
            "GameTime couldn’t finish deleting your account. Try again or contact support."
        case .unavailable:
            "Account deletion is temporarily unavailable. Try again in a moment or contact support."
        }
    }
}

@MainActor
protocol AccountDeletionClient: AnyObject {
    func deleteAccount(
        ownerID: UUID,
        appleAuthorizationCode: String
    ) async throws
}

@MainActor
final class DisabledAccountDeletionClient: AccountDeletionClient {
    func deleteAccount(
        ownerID: UUID,
        appleAuthorizationCode: String
    ) async throws {
        _ = (ownerID, appleAuthorizationCode)
        throw AccountDeletionError.unavailable
    }
}

@MainActor
protocol AccountLocalStateCleaning: AnyObject {
    func clear(for ownerID: UUID) async throws
}

@MainActor
final class NoOpAccountLocalStateCleaner: AccountLocalStateCleaning {
    func clear(for ownerID: UUID) async throws {
        _ = ownerID
    }
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
    let personalPayments: any PersonalPaymentClient
    let pendingPersonalChallenges: any PendingPersonalChallengeStore
    let pendingPersonalCancellations: any PendingPersonalCancellationStore
    let trustedActivityDiagnostic: any TrustedActivityDiagnosticClient
    let personalActivitySync: any PersonalActivitySyncing
    let personalHealthSteps: any PersonalHealthStepReading
    let personalStepSnapshotCache: any PersonalStepSnapshotCaching
    let personalHealthSnapshotUploader: any PersonalHealthSnapshotUploading
    let accountDeletion: any AccountDeletionClient
    let localStateCleanup: any AccountLocalStateCleaning
    let duels: any DuelClient
    let pendingDuels: any PendingDuelRequestStore
    let metricPrototypes: MetricPrototypeStore?
    let weekly: any WeeklyClient
    let pendingWeekly: any PendingWeeklyRequestStore
    let performanceCommitments: any PerformanceCommitmentClient
    let pendingPerformanceCommitments: any PendingPerformanceCommitmentRequestStore

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
        personalPayments: any PersonalPaymentClient =
            DisabledPersonalPaymentClient(),
        pendingPersonalChallenges: any PendingPersonalChallengeStore =
            EphemeralPendingPersonalChallengeStore(),
        pendingPersonalCancellations: any PendingPersonalCancellationStore =
            EphemeralPendingPersonalCancellationStore(),
        trustedActivityDiagnostic: any TrustedActivityDiagnosticClient =
            DisabledTrustedActivityDiagnosticClient(),
        personalActivitySync: any PersonalActivitySyncing =
            DisabledPersonalActivitySyncCoordinator(),
        personalHealthSteps: any PersonalHealthStepReading =
            DisabledPersonalHealthStepReader(),
        personalStepSnapshotCache: any PersonalStepSnapshotCaching =
            EphemeralPersonalStepSnapshotCache(),
        personalHealthSnapshotUploader:
            any PersonalHealthSnapshotUploading =
                DisabledPersonalHealthSnapshotUploader(),
        accountDeletion: any AccountDeletionClient =
            DisabledAccountDeletionClient(),
        localStateCleanup: any AccountLocalStateCleaning =
            NoOpAccountLocalStateCleaner(),
        duels: any DuelClient = DisabledDuelClient(),
        pendingDuels: any PendingDuelRequestStore = EphemeralPendingDuelRequestStore(),
        performanceCommitments: any PerformanceCommitmentClient = DisabledPerformanceCommitmentClient(),
        pendingPerformanceCommitments: any PendingPerformanceCommitmentRequestStore = EphemeralPendingPerformanceCommitmentRequestStore(),
        weekly: any WeeklyClient = DisabledWeeklyClient(),
        pendingWeekly: any PendingWeeklyRequestStore = EphemeralPendingWeeklyRequestStore(),
        metricPrototypes: MetricPrototypeStore? = nil
    ) {
        self.auth = auth
        self.profiles = profiles
        self.friendships = friendships
        self.contests = contests
        self.pendingChallenges = pendingChallenges
        self.activitySync = activitySync
        self.pushNotifications = pushNotifications
        self.personalAccountability = personalAccountability
        self.personalPayments = personalPayments
        self.pendingPersonalChallenges = pendingPersonalChallenges
        self.pendingPersonalCancellations = pendingPersonalCancellations
        self.trustedActivityDiagnostic = trustedActivityDiagnostic
        self.personalActivitySync = personalActivitySync
        self.personalHealthSteps = personalHealthSteps
        self.personalStepSnapshotCache = personalStepSnapshotCache
        self.personalHealthSnapshotUploader = personalHealthSnapshotUploader
        self.accountDeletion = accountDeletion
        self.localStateCleanup = localStateCleanup
        self.duels = duels
        self.pendingDuels = pendingDuels
        self.performanceCommitments = performanceCommitments
        self.pendingPerformanceCommitments = pendingPerformanceCommitments
        self.metricPrototypes = metricPrototypes
        self.weekly = weekly
        self.pendingWeekly = pendingWeekly
    }
}
