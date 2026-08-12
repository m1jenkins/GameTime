import Foundation
import Supabase

@MainActor
enum LiveServicesFactory {
    static func make(configuration: AppConfiguration) throws -> AppServices {
        let client = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.supabasePublishableKey
        )
        let activitySync: any ActivitySyncing
        let personalActivitySync: any PersonalActivitySyncing
        let trustedActivityDiagnostic: any TrustedActivityDiagnosticClient
        let appAttestedBodySigner: any AppAttestedBodySigning
        if configuration.activitySyncEnabled,
            !configuration.attestedUploadEnabled
        {
            // Read Health locally, upload nothing. Lets the product be used
            // and demoed before the attested stack is live.
            let health = HealthKitActivityClient()
            activitySync = DisabledActivitySyncCoordinator()
            personalActivitySync = LocalOnlyPersonalActivitySyncCoordinator(
                activity: health
            )
            appAttestedBodySigner = UnavailableAppAttestedBodySigner()
            trustedActivityDiagnostic =
                try SupabaseTrustedActivityDiagnosticClient(
                    client: client,
                    configuration: configuration,
                    activity: health,
                    signer: appAttestedBodySigner
                )
        } else if configuration.activitySyncEnabled {
            let health = HealthKitActivityClient()
            let uploads = try SupabaseMetricUploadClient(
                client: client,
                configuration: configuration
            )
            let coordinator = ActivitySyncCoordinator(
                activity: health,
                uploads: uploads,
                pendingUploads: try FilePendingMetricUploadStore
                    .applicationSupport()
            )
            appAttestedBodySigner = uploads
            activitySync = coordinator
            personalActivitySync = PersonalActivitySyncCoordinator(
                activity: health,
                metrics: coordinator,
                coverage: try SupabasePersonalCoverageClient(
                    client: client,
                    configuration: configuration,
                    signer: uploads
                ),
                pendingCoverage: try FilePendingPersonalCoverageStore
                    .applicationSupport()
            )
            trustedActivityDiagnostic = try SupabaseTrustedActivityDiagnosticClient(
                client: client,
                configuration: configuration,
                activity: health,
                signer: uploads
            )
        } else {
            activitySync = DisabledActivitySyncCoordinator()
            personalActivitySync = DisabledPersonalActivitySyncCoordinator()
            appAttestedBodySigner = UnavailableAppAttestedBodySigner()
            trustedActivityDiagnostic = DisabledTrustedActivityDiagnosticClient()
        }
        let pendingChallenges = try FilePendingChallengeStore.applicationSupport()
        let pendingPersonalChallenges = try FilePendingPersonalChallengeStore
            .applicationSupport()
        let pendingPersonalCancellations = try FilePendingPersonalCancellationStore
            .applicationSupport()
        let personalStepSnapshotCache = try FilePersonalStepSnapshotCache
            .applicationSupport()
        return AppServices(
            auth: SupabaseAuthClient(client: client),
            profiles: SupabaseProfileClient(client: client),
            friendships: SupabaseFriendshipsClient(client: client),
            contests: SupabaseContestsClient(client: client),
            pendingChallenges: pendingChallenges,
            activitySync: activitySync,
            pushNotifications: SupabasePushNotificationsClient(client: client),
            personalAccountability: SupabasePersonalAccountabilityClient(
                client: client
            ),
            personalPayments:
                configuration.personalSettlementMode == .stripeSandbox
                    ? SupabasePersonalPaymentClient(
                        client: client,
                        configuration: configuration
                    )
                    : DisabledPersonalPaymentClient(),
            pendingPersonalChallenges: pendingPersonalChallenges,
            pendingPersonalCancellations: pendingPersonalCancellations,
            trustedActivityDiagnostic: trustedActivityDiagnostic,
            personalActivitySync: personalActivitySync,
            personalHealthSteps: HealthKitPersonalHealthStepReader(),
            personalStepSnapshotCache: personalStepSnapshotCache,
            personalHealthSnapshotUploader:
                SupabasePersonalHealthSnapshotUploader(client: client),
            accountDeletion: SupabaseAccountDeletionClient(
                client: client,
                configuration: configuration
            ),
            localStateCleanup: AccountLocalStateCleaner(
                pendingChallenges: pendingChallenges,
                activitySync: activitySync,
                pendingPersonalChallenges: pendingPersonalChallenges,
                pendingPersonalCancellations: pendingPersonalCancellations,
                personalActivitySync: personalActivitySync,
                personalStepSnapshotCache: personalStepSnapshotCache,
                appAttestedBodySigner: appAttestedBodySigner
            )
        )
    }
}

@MainActor
final class SupabaseAccountDeletionClient: AccountDeletionClient {
    private struct RequestBody: Encodable {
        let appleAuthorizationCode: String

        enum CodingKeys: String, CodingKey {
            case appleAuthorizationCode = "appleAuthorizationCode"
        }
    }

    private struct ResponseBody: Decodable {
        let deleted: Bool
    }

    private let client: SupabaseClient
    private let configuration: AppConfiguration
    private let session: URLSession

    init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        session: URLSession = .shared
    ) {
        self.client = client
        self.configuration = configuration
        self.session = session
    }

    func deleteAccount(
        ownerID: UUID,
        appleAuthorizationCode: String
    ) async throws {
        guard !appleAuthorizationCode.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).isEmpty else {
            throw AccountDeletionError.authorizationCodeUnavailable
        }
        guard let liveSession = try await client.validSession() else {
            throw AccountDeletionError.authenticationRequired
        }
        guard liveSession.user.id == ownerID else {
            throw AccountDeletionError.accountChanged
        }

        var request = URLRequest(url: try endpointURL())
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(
            RequestBody(appleAuthorizationCode: appleAuthorizationCode)
        )
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            configuration.supabasePublishableKey,
            forHTTPHeaderField: "apikey"
        )
        request.setValue(
            "Bearer \(liveSession.accessToken)",
            forHTTPHeaderField: "Authorization"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw AccountDeletionError.unavailable
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AccountDeletionError.invalidResponse
        }
        if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
            throw AccountDeletionError.authenticationRequired
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode >= 500 {
                throw AccountDeletionError.unavailable
            }
            throw AccountDeletionError.rejected
        }
        guard data.count <= 64 * 1024 else {
            throw AccountDeletionError.invalidResponse
        }
        guard (try? JSONDecoder().decode(ResponseBody.self, from: data))?.deleted
            == true
        else {
            throw AccountDeletionError.invalidResponse
        }
    }

    private func endpointURL() throws -> URL {
        guard var components = URLComponents(
            url: configuration.supabaseURL,
            resolvingAgainstBaseURL: false
        ) else {
            throw AccountDeletionError.unavailable
        }
        var parts = components.path.split(separator: "/").map(String.init)
        if Array(parts.suffix(2)) != ["functions", "v1"] {
            parts.append(contentsOf: ["functions", "v1"])
        }
        parts.append("delete-account")
        components.path = "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw AccountDeletionError.unavailable
        }
        return url
    }
}

@MainActor
final class AccountLocalStateCleaner: AccountLocalStateCleaning {
    private let pendingChallenges: any PendingChallengeStore
    private let activitySync: any ActivitySyncing
    private let pendingPersonalChallenges: any PendingPersonalChallengeStore
    private let pendingPersonalCancellations: any PendingPersonalCancellationStore
    private let personalActivitySync: any PersonalActivitySyncing
    private let personalStepSnapshotCache: any PersonalStepSnapshotCaching
    private let appAttestedBodySigner: any AppAttestedBodySigning

    init(
        pendingChallenges: any PendingChallengeStore,
        activitySync: any ActivitySyncing,
        pendingPersonalChallenges: any PendingPersonalChallengeStore,
        pendingPersonalCancellations: any PendingPersonalCancellationStore,
        personalActivitySync: any PersonalActivitySyncing,
        personalStepSnapshotCache: any PersonalStepSnapshotCaching,
        appAttestedBodySigner: any AppAttestedBodySigning
    ) {
        self.pendingChallenges = pendingChallenges
        self.activitySync = activitySync
        self.pendingPersonalChallenges = pendingPersonalChallenges
        self.pendingPersonalCancellations = pendingPersonalCancellations
        self.personalActivitySync = personalActivitySync
        self.personalStepSnapshotCache = personalStepSnapshotCache
        self.appAttestedBodySigner = appAttestedBodySigner
    }

    func clear(for ownerID: UUID) async throws {
        var failures: [String] = []

        do { try await pendingChallenges.remove(for: ownerID) }
        catch { failures.append("challenge retry") }
        do { try await pendingPersonalChallenges.remove(for: ownerID) }
        catch { failures.append("personal challenge retry") }
        do { try await pendingPersonalCancellations.remove(for: ownerID) }
        catch { failures.append("cancellation retry") }
        do { try await activitySync.clearPendingUploads(for: ownerID) }
        catch { failures.append("activity upload") }
        do { try await personalActivitySync.clearPendingUploads(for: ownerID) }
        catch { failures.append("personal activity upload") }
        do { try await personalStepSnapshotCache.removeAll(ownerID: ownerID) }
        catch { failures.append("Health snapshot") }
        do { try appAttestedBodySigner.clearLocalState(for: ownerID) }
        catch { failures.append("device verification") }

        guard failures.isEmpty else {
            throw AccountDeletionLocalCleanupError(failures: failures)
        }
    }
}

struct AccountDeletionLocalCleanupError: LocalizedError, Equatable, Sendable {
    let failures: [String]

    var errorDescription: String? {
        "Your account was deleted, but some saved data on this phone could not be cleared."
    }
}

enum SupabaseSessionError: LocalizedError, Equatable, Sendable {
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .refreshFailed:
            "GameTime could not refresh this account's sign-in. Check the connection and try again."
        }
    }
}

extension SupabaseClient {
    /// The signed-in session, with an access token that is valid *now*.
    ///
    /// `auth.currentSession` is whatever is in storage, and the SDK documents
    /// it as possibly expired. Requests to the Edge Functions are built by hand
    /// rather than issued through the SDK, so nothing on that path refreshes
    /// the token: reading the stored one sends an expired JWT, the function
    /// answers 401, and the app reports a sign-in problem to somebody who never
    /// had one.
    ///
    /// - Returns: nil when there is no usable session and signing in again is
    ///   the only way forward — either nobody is signed in, or the refresh
    ///   token itself was refused.
    /// - Throws: ``SupabaseSessionError/refreshFailed`` when a refresh was
    ///   needed but could not be completed, which a later attempt may manage.
    func validSession() async throws -> Session? {
        do {
            return try await auth.session
        } catch is CancellationError {
            throw CancellationError()
        } catch AuthError.sessionMissing {
            return nil
        } catch {
            if
                case AuthError.api(_, _, _, let response) = error,
                (400...403).contains(response.statusCode)
            {
                // The refresh token was refused; there is nothing left to renew.
                return nil
            }
            throw SupabaseSessionError.refreshFailed
        }
    }
}

@MainActor
final class SupabaseAuthClient: AuthClient {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentUserID() async -> UUID? {
        client.auth.currentSession?.user.id
    }

    func authStateChanges() async -> AsyncStream<AuthSnapshot> {
        let upstream = client.auth.authStateChanges
        return AsyncStream { continuation in
            let task = Task { @MainActor in
                for await (_, session) in upstream {
                    guard !Task.isCancelled else { break }
                    continuation.yield(
                        AuthSnapshot(userID: session?.user.id)
                    )
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID {
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(
                provider: .apple,
                idToken: identity.idToken,
                nonce: identity.rawNonce
            )
        )
        return session.user.id
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}

@MainActor
final class SupabaseProfileClient: ProfileClient {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func currentProfile(userID: UUID) async throws -> UserProfile? {
        let rows: [UserProfile] =
            try await client
            .from("profiles")
            .select("id,handle,display_name,timezone")
            .eq("id", value: userID.uuidString.lowercased())
            .limit(1)
            .execute()
            .value
        return rows.first
    }

    func createProfile(
        userID: UUID,
        handle: String,
        displayName: String,
        timezone: String
    ) async throws -> UserProfile {
        let payload = ProfileInsert(
            id: userID,
            handle: handle,
            displayName: displayName,
            timezone: timezone
        )
        // The account-deletion RLS boundary makes the actor active in an
        // AFTER INSERT trigger. Keep RETURNING out of this statement so its
        // SELECT policy is evaluated only after that binding has committed.
        try await client
            .from("profiles")
            .insert(payload)
            .execute()

        guard let profile = try await currentProfile(userID: userID) else {
            throw AppMutationError.server(
                "Profile creation completed without a readable profile."
            )
        }
        return profile
    }
}

@MainActor
final class SupabaseFriendshipsClient: FriendshipsClient {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func listCards() async throws -> [FriendshipCard] {
        try await client
            .rpc("list_my_friendship_cards")
            .execute()
            .value
    }

    func findExactHandle(_ handle: String) async throws -> ProfileCard? {
        guard let exact = ExactHandleSubmission.normalized(handle) else {
            return nil
        }
        let rows: [ProfileCard] =
            try await client
            .rpc("find_profile_by_handle", params: ["p_handle": exact])
            .execute()
            .value
        return rows.first
    }

    func requestFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        let pair = canonicalPair(callerID, otherUserID)
        try await client
            .from("friendships")
            .insert(
                FriendshipInsert(
                    userA: pair.0,
                    userB: pair.1,
                    requestedBy: callerID
                )
            )
            .execute()
    }

    func acceptFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        let pair = canonicalPair(callerID, otherUserID)
        try await client
            .from("friendships")
            .update(FriendshipStatusUpdate(status: .accepted))
            .eq("user_a", value: pair.0.uuidString.lowercased())
            .eq("user_b", value: pair.1.uuidString.lowercased())
            .execute()
    }

    func removeFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        let pair = canonicalPair(callerID, otherUserID)
        try await client
            .from("friendships")
            .delete()
            .eq("user_a", value: pair.0.uuidString.lowercased())
            .eq("user_b", value: pair.1.uuidString.lowercased())
            .execute()
    }

    private func canonicalPair(_ left: UUID, _ right: UUID) -> (UUID, UUID) {
        left.uuidString.lowercased() < right.uuidString.lowercased()
            ? (left, right)
            : (right, left)
    }
}

@MainActor
final class SupabaseContestsClient: ContestsClient {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func listChallengeSummaries(userID: UUID) async throws
        -> [ChallengeRosterSummary]
    {
        let rows: [ChallengeSummaryRow] = try await client
            .rpc("list_my_challenge_summaries_v1")
            .execute()
            .value
        let timeZoneRows: [TimeZoneChangeRow] =
            try await client
            .from("timezone_change_applied_events")
            .select(
                """
                contest_id,user_id,from_timezone,to_timezone,effective_at
                """
            )
            .eq("user_id", value: userID.uuidString.lowercased())
            .execute()
            .value
        let timeZoneChanges = Dictionary(
            grouping: timeZoneRows,
            by: \.contestID
        )
        return rows.map { row in
            row.summary(
                timeZoneChanges: timeZoneChanges[row.contestID, default: []]
            )
        }
    }

    func listCharities() async throws -> [Charity] {
        try await client
            .from("charities")
            .select("id,name,slug")
            .eq("is_active", value: true)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func standings(contestID: UUID) async throws -> ChallengeStandings? {
        let standings: ChallengeStandings? =
            try await client
            .rpc(
                "get_contest_standings_v1",
                params: [
                    "p_contest_id": contestID.uuidString.lowercased()
                ]
            )
            .execute()
            .value
        return standings
    }

    func sendComebackReaction(
        contestID: UUID,
        snapshotID: UUID
    ) async throws {
        let _: UUID =
            try await client
            .rpc(
                "send_comeback_reaction_v1",
                params: StandingsReactionParameters(
                    contestID: contestID,
                    snapshotID: snapshotID
                )
            )
            .execute()
            .value
    }

    func createChallenge(
        _ terms: ChallengeTerms,
        expectedUserID: UUID
    ) async throws -> UUID {
        guard client.auth.currentSession?.user.id == expectedUserID else {
            throw AppMutationError.permissionDenied
        }
        let params = CreateContestWithInvitesParameters(terms: terms)
        let contestID: UUID =
            try await client
            .rpc("create_contest_with_invites_v1", params: params)
            .execute()
            .value
        #if STAGING
        StagingAcceptanceDiagnostics.challengeCreationResponseReceived(
            contestID
        )
        #endif
        return contestID
    }

    func acceptInvitation(
        contestID: UUID,
        userID: UUID,
        timezone: String,
        charityID: UUID
    ) async throws {
        try await client
            .from("contest_participants")
            .update(
                AcceptInvitationUpdate(
                    status: .accepted,
                    timezone: timezone,
                    charityID: charityID
                )
            )
            .eq("contest_id", value: contestID.uuidString.lowercased())
            .eq("user_id", value: userID.uuidString.lowercased())
            .execute()
    }

    func declineInvitation(contestID: UUID, userID: UUID) async throws {
        try await client
            .from("contest_participants")
            .update(ParticipantStatusUpdate(status: .declined))
            .eq("contest_id", value: contestID.uuidString.lowercased())
            .eq("user_id", value: userID.uuidString.lowercased())
            .execute()
    }
}

@MainActor
final class SupabasePushNotificationsClient: PushNotificationsClient {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func register(_ registration: PushDeviceRegistration) async throws {
        let _: UUID =
            try await client
            .rpc(
                "register_push_device_v1",
                params: PushDeviceParameters(registration: registration)
            )
            .execute()
            .value
    }

    func unregister(_ registration: PushDeviceRegistration) async throws {
        let _: Bool =
            try await client
            .rpc(
                "unregister_push_device_v1",
                params: PushDeviceParameters(registration: registration)
            )
            .execute()
            .value
    }
}

private struct ProfileInsert: Encodable {
    let id: UUID
    let handle: String
    let displayName: String
    let timezone: String

    enum CodingKeys: String, CodingKey {
        case id
        case handle
        case displayName = "display_name"
        case timezone
    }
}

private struct StandingsReactionParameters: Encodable {
    let contestID: UUID
    let snapshotID: UUID

    enum CodingKeys: String, CodingKey {
        case contestID = "p_contest_id"
        case snapshotID = "p_snapshot_id"
    }
}

private struct PushDeviceParameters: Encodable {
    let deviceToken: String
    let environment: PushTokenEnvironment
    let bundleID: String

    init(registration: PushDeviceRegistration) {
        deviceToken = registration.deviceToken
        environment = registration.environment
        bundleID = registration.bundleID
    }

    enum CodingKeys: String, CodingKey {
        case deviceToken = "p_device_token"
        case environment = "p_environment"
        case bundleID = "p_bundle_id"
    }
}

private struct FriendshipInsert: Encodable {
    let userA: UUID
    let userB: UUID
    let requestedBy: UUID

    enum CodingKeys: String, CodingKey {
        case userA = "user_a"
        case userB = "user_b"
        case requestedBy = "requested_by"
    }
}

private struct FriendshipStatusUpdate: Encodable {
    let status: FriendshipStatus
}

struct ChallengeSummaryRow: Decodable {
    let contestID: UUID
    let title: String
    let createdBy: UUID?
    let metric: ContestMetric
    let cadence: ContestCadence
    let targetValue: Double
    let stakeAmountCents: Int
    let tieBreak: ContestTieBreak
    let startsAt: Date
    let endsAt: Date
    let contestStatus: ContestStatus
    let maxParticipants: Int
    let callerStatus: ContestParticipantStatus
    let callerTimeZone: String?
    let acceptedCount: Int
    let invitedCount: Int
    let declinedCount: Int
    let withdrawnCount: Int
    let lapsedCount: Int
    let authorProfile: ChallengeRosterProfile?
    let acceptedProfiles: [ChallengeRosterProfile]

    enum CodingKeys: String, CodingKey {
        case contestID = "contest_id"
        case title
        case createdBy = "created_by"
        case metric
        case cadence
        case targetValue = "target_value"
        case stakeAmountCents = "stake_amount_cents"
        case tieBreak = "tie_break"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case contestStatus = "contest_status"
        case maxParticipants = "max_participants"
        case callerStatus = "caller_status"
        case callerTimeZone = "caller_timezone"
        case acceptedCount = "accepted_count"
        case invitedCount = "invited_count"
        case declinedCount = "declined_count"
        case withdrawnCount = "withdrawn_count"
        case lapsedCount = "lapsed_count"
        case authorProfile = "author_profile"
        case acceptedProfiles = "accepted_profiles"
    }

    func summary(timeZoneChanges: [TimeZoneChangeRow])
        -> ChallengeRosterSummary
    {
        let contest = ContestCard(
            id: contestID,
            title: title,
            createdBy: createdBy,
            metric: metric,
            cadence: cadence,
            targetValue: targetValue,
            stakeAmountCents: stakeAmountCents,
            tieBreak: tieBreak,
            startsAt: startsAt,
            endsAt: endsAt,
            status: contestStatus,
            myStatus: callerStatus,
            maxParticipants: maxParticipants,
            participantTimeZone: callerTimeZone,
            timeZoneChanges: timeZoneChanges
                .sorted { $0.effectiveAt < $1.effectiveAt }
                .map(\.cardEvent),
            participants: acceptedProfiles.map {
                ContestParticipantCard(
                    userID: $0.id,
                    status: .accepted,
                    charityID: nil
                )
            }
        )
        return ChallengeRosterSummary(
            contest: contest,
            maxParticipants: maxParticipants,
            acceptedCount: acceptedCount,
            invitedCount: invitedCount,
            declinedCount: declinedCount,
            withdrawnCount: withdrawnCount,
            lapsedCount: lapsedCount,
            author: authorProfile,
            acceptedParticipants: acceptedProfiles
        )
    }
}

struct TimeZoneChangeRow: Decodable {
    let contestID: UUID
    let userID: UUID
    let fromTimeZone: String
    let toTimeZone: String
    let effectiveAt: Date

    enum CodingKeys: String, CodingKey {
        case contestID = "contest_id"
        case userID = "user_id"
        case fromTimeZone = "from_timezone"
        case toTimeZone = "to_timezone"
        case effectiveAt = "effective_at"
    }

    var cardEvent: ContestTimeZoneEvent {
        ContestTimeZoneEvent(
            fromTimeZone: fromTimeZone,
            toTimeZone: toTimeZone,
            effectiveAt: effectiveAt
        )
    }
}

struct CreateContestWithInvitesParameters: Encodable {
    let requestID: UUID
    let title: String
    let metric: ContestMetric
    let cadence: ContestCadence
    let targetValue: Double
    let stakeCents: Int
    let startsAt: Date
    let endsAt: Date
    let timezone: String
    let charityID: UUID
    let inviteeIDs: [UUID]
    let maxParticipants: Int
    let tieBreak: ContestTieBreak
    let groupID: UUID?

    init(terms: ChallengeTerms) {
        requestID = terms.requestID
        title = terms.title
        metric = terms.metric
        cadence = terms.cadence
        targetValue = terms.targetValue
        stakeCents = terms.stakeAmountCents
        startsAt = terms.startsAt
        endsAt = terms.endsAt
        timezone = terms.timezone
        charityID = terms.charityID
        inviteeIDs = terms.inviteeIDs
        maxParticipants = terms.maxParticipants
        tieBreak = terms.tieBreak
        groupID = nil
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "p_request_id"
        case title = "p_title"
        case metric = "p_metric"
        case cadence = "p_cadence"
        case targetValue = "p_target_value"
        case stakeCents = "p_stake_cents"
        case startsAt = "p_starts_at"
        case endsAt = "p_ends_at"
        case timezone = "p_timezone"
        case charityID = "p_charity_id"
        case inviteeIDs = "p_invitee_ids"
        case maxParticipants = "p_max_participants"
        case tieBreak = "p_tie_break"
        case groupID = "p_group_id"
    }
}

private struct AcceptInvitationUpdate: Encodable {
    let status: ContestParticipantStatus
    let timezone: String
    let charityID: UUID

    enum CodingKeys: String, CodingKey {
        case status
        case timezone
        case charityID = "charity_id"
    }
}

private struct ParticipantStatusUpdate: Encodable {
    let status: ContestParticipantStatus
}
