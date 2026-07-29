import Foundation
import Supabase

@MainActor
enum LiveServicesFactory {
    static func make(configuration: AppConfiguration) throws -> AppServices {
        let client = SupabaseClient(
            supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.supabasePublishableKey
        )
        return AppServices(
            auth: SupabaseAuthClient(client: client),
            profiles: SupabaseProfileClient(client: client),
            friendships: SupabaseFriendshipsClient(client: client),
            contests: SupabaseContestsClient(client: client),
            pendingChallenges: try FilePendingChallengeStore.applicationSupport()
        )
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

    func listContests(userID: UUID) async throws -> [ContestCard] {
        let participantRows: [ParticipantRow] =
            try await client
            .from("contest_participants")
            .select("contest_id,status")
            .eq("user_id", value: userID.uuidString.lowercased())
            .execute()
            .value

        guard !participantRows.isEmpty else { return [] }

        let ownStatus = Dictionary(
            uniqueKeysWithValues: participantRows.map {
                ($0.contestID, $0.status)
            }
        )
        let contestRows: [ContestRow] =
            try await client
            .from("contests")
            .select(
                """
                id,title,created_by,metric,cadence,target_value,
                stake_amount_cents,tie_break,starts_at,ends_at,status
                """
            )
            .order("starts_at", ascending: true)
            .execute()
            .value

        return contestRows.compactMap { row in
            guard let status = ownStatus[row.id] else { return nil }
            return row.card(myStatus: status)
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

private struct ParticipantRow: Decodable {
    let contestID: UUID
    let status: ContestParticipantStatus

    enum CodingKeys: String, CodingKey {
        case contestID = "contest_id"
        case status
    }
}

private struct ContestRow: Decodable {
    let id: UUID
    let title: String
    let createdBy: UUID?
    let metric: ContestMetric
    let cadence: ContestCadence
    let targetValue: Double
    let stakeAmountCents: Int
    let tieBreak: ContestTieBreak
    let startsAt: Date
    let endsAt: Date
    let status: ContestStatus

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdBy = "created_by"
        case metric
        case cadence
        case targetValue = "target_value"
        case stakeAmountCents = "stake_amount_cents"
        case tieBreak = "tie_break"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case status
    }

    func card(myStatus: ContestParticipantStatus) -> ContestCard {
        ContestCard(
            id: id,
            title: title,
            createdBy: createdBy,
            metric: metric,
            cadence: cadence,
            targetValue: targetValue,
            stakeAmountCents: stakeAmountCents,
            tieBreak: tieBreak,
            startsAt: startsAt,
            endsAt: endsAt,
            status: status,
            myStatus: myStatus
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
