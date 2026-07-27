#if DEBUG
import Foundation

@MainActor
enum FixtureServicesFactory {
    static func make(arguments: [String] = ProcessInfo.processInfo.arguments)
        -> AppServices
    {
        let scenario = FixtureScenario(arguments: arguments)
        let store = FixtureStore(scenario: scenario)
        return AppServices(
            auth: FixtureAuthClient(store: store),
            profiles: FixtureProfileClient(store: store),
            friendships: FixtureFriendshipsClient(store: store),
            contests: FixtureContestsClient(store: store)
        )
    }
}

private struct FixtureScenario {
    let signedOut: Bool
    let onboarding: Bool
    let empty: Bool
    let offline: Bool
    let loading: Bool

    init(arguments: [String]) {
        signedOut = arguments.contains("--fixture-signed-out")
        onboarding = arguments.contains("--fixture-onboarding")
        empty = arguments.contains("--fixture-empty")
        offline = arguments.contains("--fixture-offline")
        loading = arguments.contains("--fixture-loading")
    }
}

@MainActor
private final class FixtureStore {
    static let callerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let incomingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let outgoingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let friendID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let charityID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    static let invitationID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    static let activeContestID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

    var userID: UUID?
    var profile: UserProfile?
    var cards: [FriendshipCard]
    var contests: [ContestCard]
    var charities: [Charity]
    let offline: Bool
    let loading: Bool

    init(scenario: FixtureScenario) {
        userID = scenario.signedOut ? nil : Self.callerID
        profile = scenario.onboarding || scenario.signedOut
            ? nil
            : UserProfile(
                id: Self.callerID,
                handle: "austinmoves",
                displayName: "Austin",
                timezone: "America/Chicago"
            )
        offline = scenario.offline
        loading = scenario.loading

        let now = Date()
        cards = scenario.empty
            ? []
            : [
                FriendshipCard(
                    otherUserID: Self.incomingID,
                    handle: "jordanjumps",
                    displayName: "Jordan Lee",
                    status: .pending,
                    requestedBy: Self.incomingID,
                    createdAt: now.addingTimeInterval(-1_800),
                    updatedAt: now.addingTimeInterval(-1_800),
                    acceptedAt: nil
                ),
                FriendshipCard(
                    otherUserID: Self.outgoingID,
                    handle: "caseyclimbs",
                    displayName: "Casey Morgan",
                    status: .pending,
                    requestedBy: Self.callerID,
                    createdAt: now.addingTimeInterval(-3_600),
                    updatedAt: now.addingTimeInterval(-3_600),
                    acceptedAt: nil
                ),
                FriendshipCard(
                    otherUserID: Self.friendID,
                    handle: "marcusmoves",
                    displayName: "Marcus Green",
                    status: .accepted,
                    requestedBy: Self.friendID,
                    createdAt: now.addingTimeInterval(-86_400),
                    updatedAt: now.addingTimeInterval(-86_000),
                    acceptedAt: now.addingTimeInterval(-86_000)
                ),
            ]

        contests = scenario.empty
            ? []
            : [
                ContestCard(
                    id: Self.invitationID,
                    title: "Three-day step duel",
                    createdBy: Self.friendID,
                    metric: .steps,
                    cadence: .daily,
                    targetValue: 8_000,
                    stakeAmountCents: 500,
                    tieBreak: .integrityScore,
                    startsAt: now.addingTimeInterval(86_400),
                    endsAt: now.addingTimeInterval(4 * 86_400),
                    status: .pending,
                    myStatus: .invited
                ),
                ContestCard(
                    id: Self.activeContestID,
                    title: "Weekend distance",
                    createdBy: Self.callerID,
                    metric: .distanceMeters,
                    cadence: .cumulative,
                    targetValue: 10_000,
                    stakeAmountCents: 1_000,
                    tieBreak: .earliestToTarget,
                    startsAt: now.addingTimeInterval(-3_600),
                    endsAt: now.addingTimeInterval(2 * 86_400),
                    status: .active,
                    myStatus: .accepted
                ),
            ]
        charities = [
            Charity(
                id: Self.charityID,
                name: "Fixture Community Fund",
                slug: "fixture-community-fund"
            )
        ]
    }

    func prepareRead() async throws {
        if loading {
            try await Task.sleep(for: .seconds(2))
        }
        if offline {
            throw FixtureFailure.offline
        }
    }
}

private enum FixtureFailure: LocalizedError {
    case offline

    var errorDescription: String? {
        "Network unavailable in this fixture."
    }
}

@MainActor
private final class FixtureAuthClient: AuthClient {
    private let store: FixtureStore
    private var continuations: [UUID: AsyncStream<AuthSnapshot>.Continuation] = [:]

    init(store: FixtureStore) {
        self.store = store
    }

    func currentUserID() async -> UUID? {
        store.userID
    }

    func authStateChanges() async -> AsyncStream<AuthSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.yield(AuthSnapshot(userID: store.userID))
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID {
        _ = identity
        store.userID = FixtureStore.callerID
        publish()
        return FixtureStore.callerID
    }

    func signOut() async throws {
        store.userID = nil
        publish()
    }

    private func publish() {
        let snapshot = AuthSnapshot(userID: store.userID)
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }
}

@MainActor
private final class FixtureProfileClient: ProfileClient {
    private let store: FixtureStore

    init(store: FixtureStore) {
        self.store = store
    }

    func currentProfile(userID: UUID) async throws -> UserProfile? {
        if store.loading {
            try await Task.sleep(for: .seconds(2))
        }
        return store.profile?.id == userID ? store.profile : nil
    }

    func createProfile(
        userID: UUID,
        handle: String,
        displayName: String,
        timezone: String
    ) async throws -> UserProfile {
        let profile = UserProfile(
            id: userID,
            handle: handle,
            displayName: displayName,
            timezone: timezone
        )
        store.profile = profile
        return profile
    }
}

@MainActor
private final class FixtureFriendshipsClient: FriendshipsClient {
    private let store: FixtureStore

    init(store: FixtureStore) {
        self.store = store
    }

    func listCards() async throws -> [FriendshipCard] {
        try await store.prepareRead()
        return store.cards
    }

    func findExactHandle(_ handle: String) async throws -> ProfileCard? {
        try await store.prepareRead()
        guard
            let exact = ExactHandleSubmission.normalized(handle),
            exact.caseInsensitiveCompare("marcusmoves") == .orderedSame
        else {
            return nil
        }
        return ProfileCard(
            id: FixtureStore.friendID,
            handle: "marcusmoves",
            displayName: "Marcus Green"
        )
    }

    func requestFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        guard !store.offline else { throw FixtureFailure.offline }
        let now = Date()
        store.cards.removeAll { $0.otherUserID == otherUserID }
        store.cards.append(
            FriendshipCard(
                otherUserID: otherUserID,
                handle: "marcusmoves",
                displayName: "Marcus Green",
                status: .pending,
                requestedBy: callerID,
                createdAt: now,
                updatedAt: now,
                acceptedAt: nil
            )
        )
    }

    func acceptFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        guard !store.offline else { throw FixtureFailure.offline }
        guard
            let index = store.cards.firstIndex(
                where: { $0.otherUserID == otherUserID }
            )
        else {
            return
        }
        let original = store.cards[index]
        store.cards[index] = FriendshipCard(
            otherUserID: original.otherUserID,
            handle: original.handle,
            displayName: original.displayName,
            status: .accepted,
            requestedBy: original.requestedBy,
            createdAt: original.createdAt,
            updatedAt: Date(),
            acceptedAt: Date()
        )
        _ = callerID
    }

    func removeFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        guard !store.offline else { throw FixtureFailure.offline }
        store.cards.removeAll { $0.otherUserID == otherUserID }
        _ = callerID
    }
}

@MainActor
private final class FixtureContestsClient: ContestsClient {
    private let store: FixtureStore

    init(store: FixtureStore) {
        self.store = store
    }

    func listContests(userID: UUID) async throws -> [ContestCard] {
        try await store.prepareRead()
        _ = userID
        return store.contests
    }

    func listCharities() async throws -> [Charity] {
        try await store.prepareRead()
        return store.charities
    }

    func createDuel(_ terms: DuelTerms) async throws -> UUID {
        guard !store.offline else { throw FixtureFailure.offline }
        let id = UUID()
        store.contests.append(
            ContestCard(
                id: id,
                title: terms.title,
                createdBy: store.userID,
                metric: terms.metric,
                cadence: terms.cadence,
                targetValue: terms.targetValue,
                stakeAmountCents: terms.stakeAmountCents,
                tieBreak: terms.tieBreak,
                startsAt: terms.startsAt,
                endsAt: terms.endsAt,
                status: .pending,
                myStatus: .accepted
            )
        )
        return id
    }

    func acceptInvitation(
        contestID: UUID,
        userID: UUID,
        timezone: String,
        charityID: UUID
    ) async throws {
        guard !store.offline else { throw FixtureFailure.offline }
        update(contestID: contestID, status: .accepted)
        _ = (userID, timezone, charityID)
    }

    func declineInvitation(contestID: UUID, userID: UUID) async throws {
        guard !store.offline else { throw FixtureFailure.offline }
        update(contestID: contestID, status: .declined)
        _ = userID
    }

    private func update(
        contestID: UUID,
        status: ContestParticipantStatus
    ) {
        guard let index = store.contests.firstIndex(where: { $0.id == contestID })
        else {
            return
        }
        let original = store.contests[index]
        store.contests[index] = ContestCard(
            id: original.id,
            title: original.title,
            createdBy: original.createdBy,
            metric: original.metric,
            cadence: original.cadence,
            targetValue: original.targetValue,
            stakeAmountCents: original.stakeAmountCents,
            tieBreak: original.tieBreak,
            startsAt: original.startsAt,
            endsAt: original.endsAt,
            status: original.status,
            myStatus: status
        )
    }
}
#endif
