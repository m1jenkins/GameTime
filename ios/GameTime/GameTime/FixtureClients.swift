#if DEBUG || STAGING
import Foundation

@MainActor
enum FixtureServicesFactory {
    static func make(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        pendingChallengeStore: (any PendingChallengeStore)? = nil,
        contestsClient: (any ContestsClient)? = nil,
        activitySync: (any ActivitySyncing)? = nil
    ) -> AppServices {
        let scenario = FixtureScenario(arguments: arguments)
        let store = FixtureStore(scenario: scenario)
        return AppServices(
            auth: FixtureAuthClient(store: store),
            profiles: FixtureProfileClient(store: store),
            friendships: FixtureFriendshipsClient(store: store),
            contests: contestsClient ?? FixtureContestsClient(store: store),
            pendingChallenges: pendingChallengeStore
                ?? FixturePendingChallengeStore(
                    submission: scenario.pendingChallenge
                        ? FixtureStore.pendingChallengeSubmission()
                        : nil
                ),
            activitySync: activitySync
                ?? (
                    scenario.activity
                        ? FixtureActivitySyncCoordinator()
                        : DisabledActivitySyncCoordinator()
                )
        )
    }
}

private struct FixtureScenario {
    let signedOut: Bool
    let onboarding: Bool
    let empty: Bool
    let offline: Bool
    let loading: Bool
    let pendingChallenge: Bool
    let lostChallengeResponse: Bool
    let finalStandings: Bool
    let activity: Bool
    let instantlyAcceptFriendRequests: Bool

    init(arguments: [String]) {
        signedOut = arguments.contains("--fixture-signed-out")
        onboarding = arguments.contains("--fixture-onboarding")
        empty = arguments.contains("--fixture-empty")
        offline = arguments.contains("--fixture-offline")
        loading = arguments.contains("--fixture-loading")
        pendingChallenge =
            arguments.contains("--fixture-pending-challenge")
            || arguments.contains("--fixture-pending-duel")
        lostChallengeResponse =
            arguments.contains("--fixture-lost-challenge-response")
            || arguments.contains("--fixture-lost-duel-response")
        finalStandings = arguments.contains("--fixture-final-standings")
        activity = arguments.contains("--fixture-activity")
        instantlyAcceptFriendRequests = arguments.contains(
            "--demo-interactive"
        )
    }
}

@MainActor
private final class FixtureStore {
    static let callerID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let incomingID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    static let outgoingID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    static let friendID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let secondFriendID = UUID(
        uuidString: "55555555-5555-5555-5555-555555555555"
    )!
    static let davidID = UUID(
        uuidString: "66666666-6666-6666-6666-666666666666"
    )!
    static let davidTwoID = UUID(
        uuidString: "77777777-7777-7777-7777-777777777777"
    )!
    static let charityID = UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!
    static let invitationID = UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
    static let activeContestID = UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!

    var userID: UUID?
    var profile: UserProfile?
    var cards: [FriendshipCard]
    var contests: [ContestCard]
    var charities: [Charity]
    var standingsByContestID: [UUID: ChallengeStandings]
    var challengeRequests: [UUID: FixtureChallengeRequest] = [:]
    let discoverableProfiles: [ProfileCard]
    let offline: Bool
    let loading: Bool
    let lostChallengeResponse: Bool
    let instantlyAcceptFriendRequests: Bool
    var hasLostChallengeResponse = false

    init(scenario: FixtureScenario) {
        userID = scenario.signedOut ? nil : Self.callerID
        profile =
            scenario.onboarding || scenario.signedOut
            ? nil
            : UserProfile(
                id: Self.callerID,
                handle: "austinmoves",
                displayName: "Austin",
                timezone: "America/Chicago"
            )
        offline = scenario.offline
        loading = scenario.loading
        lostChallengeResponse = scenario.lostChallengeResponse
        instantlyAcceptFriendRequests =
            scenario.instantlyAcceptFriendRequests
        discoverableProfiles = [
            ProfileCard(
                id: Self.friendID,
                handle: "marcusmoves",
                displayName: "Marcus Green"
            ),
            ProfileCard(
                id: Self.davidID,
                handle: "david1",
                displayName: "David Chen"
            ),
            ProfileCard(
                id: Self.davidTwoID,
                handle: "david2",
                displayName: "David Brooks"
            ),
        ]

        let now = Date()
        cards =
            scenario.empty
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
                FriendshipCard(
                    otherUserID: Self.secondFriendID,
                    handle: "priyaruns",
                    displayName: "Priya Shah",
                    status: .accepted,
                    requestedBy: Self.callerID,
                    createdAt: now.addingTimeInterval(-172_800),
                    updatedAt: now.addingTimeInterval(-172_000),
                    acceptedAt: now.addingTimeInterval(-172_000)
                ),
            ]

        contests =
            scenario.empty
            ? []
            : [
                ContestCard(
                    id: Self.invitationID,
                    title: "Three-day step challenge",
                    createdBy: Self.friendID,
                    metric: .steps,
                    cadence: .daily,
                    targetValue: 8_000,
                    stakeAmountCents: 500,
                    tieBreak: .integrityScore,
                    startsAt: now.addingTimeInterval(86_400),
                    endsAt: now.addingTimeInterval(4 * 86_400),
                    status: .pending,
                    myStatus: .invited,
                    maxParticipants: 2,
                    participantTimeZone: nil,
                    timeZoneChanges: [],
                    participants: [
                        ContestParticipantCard(
                            userID: Self.friendID,
                            status: .accepted,
                            charityID: Self.charityID
                        ),
                        ContestParticipantCard(
                            userID: Self.callerID,
                            status: .invited,
                            charityID: nil
                        ),
                    ]
                ),
                ContestCard(
                    id: Self.activeContestID,
                    title: scenario.activity
                        ? "Weekend steps"
                        : "Weekend distance",
                    createdBy: Self.callerID,
                    metric: scenario.activity ? .steps : .distanceMeters,
                    cadence: .cumulative,
                    targetValue: 10_000,
                    stakeAmountCents: 1_000,
                    tieBreak: .earliestToTarget,
                    startsAt: now.addingTimeInterval(
                        scenario.finalStandings ? -3 * 86_400 : -3_600
                    ),
                    endsAt: now.addingTimeInterval(
                        scenario.finalStandings ? -8 * 3_600 : 2 * 86_400
                    ),
                    status: scenario.finalStandings ? .finalized : .active,
                    myStatus: .accepted,
                    maxParticipants: 2,
                    participantTimeZone: "America/Chicago",
                    timeZoneChanges: [],
                    participants: [
                        ContestParticipantCard(
                            userID: Self.callerID,
                            status: .accepted,
                            charityID: Self.charityID
                        ),
                        ContestParticipantCard(
                            userID: Self.friendID,
                            status: .accepted,
                            charityID: Self.charityID
                        ),
                    ]
                ),
            ]
        charities = [
            Charity(
                id: Self.charityID,
                name: "Fixture Community Fund",
                slug: "fixture-community-fund"
            )
        ]
        standingsByContestID =
            scenario.empty
            ? [:]
            : [
                Self.activeContestID: Self.makeStandings(
                    now: now,
                    final: scenario.finalStandings
                )
            ]
    }

    static func pendingChallengeSubmission(now: Date = Date())
        -> PendingChallengeSubmission
    {
        PendingChallengeSubmission(
            ownerID: callerID,
            terms: ChallengeTerms(
                requestID: UUID(
                    uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd"
                )!,
                title: "Saved response retry",
                inviteeIDs: [friendID, secondFriendID],
                metric: .steps,
                cadence: .cumulative,
                targetValue: 10_000,
                stakeAmountCents: 500,
                startsAt: now.addingTimeInterval(86_400),
                endsAt: now.addingTimeInterval(3 * 86_400),
                timezone: "America/Chicago",
                charityID: charityID,
                tieBreak: .integrityScore
            ),
            createdAt: now.addingTimeInterval(-120),
            attemptCount: 1,
            lastAttemptAt: now.addingTimeInterval(-60)
        )
    }

    private static func makeStandings(
        now: Date,
        final: Bool
    ) -> ChallengeStandings {
        let resultID = UUID(
            uuidString: "12121212-1212-1212-1212-121212121212"
        )!
        let obligationID = UUID(
            uuidString: "14141414-1414-1414-1414-141414141414"
        )!
        let result =
            final
            ? ChallengeResult(
                id: resultID,
                kind: .winner,
                reason: .earliestToTarget,
                winnerParticipantID: friendID,
                evidenceCutoff: now.addingTimeInterval(-2 * 3_600),
                finalizedAt: now.addingTimeInterval(-3_600)
            )
            : nil
        let winnerRationale = [
            ChallengeIntegrityRationale(
                code: "trusted_source",
                summary: "Health data passed integrity review.",
                points: 0
            )
        ]
        let callerRationale = [
            ChallengeIntegrityRationale(
                code: "trusted_source",
                summary: "Health data passed integrity review.",
                points: 0
            )
        ]

        return ChallengeStandings(
            contestID: activeContestID,
            snapshotID: UUID(
                uuidString: final
                    ? "13131313-1313-1313-1313-131313131313"
                    : "15151515-1515-1515-1515-151515151515"
            )!,
            phase: final ? .final : .provisional,
            reason: final ? .final : .live,
            asOf: now.addingTimeInterval(-300),
            scoringVersion: "m7-scoring-v1",
            integrityConfigurationVersion: "m7-integrity-v1",
            result: result,
            standings: [
                ChallengeStanding(
                    participantID: friendID,
                    displayName: "Marcus Green",
                    handle: "marcusmoves",
                    displayOrder: 1,
                    rank: 1,
                    qualified: final,
                    total: final ? 10_520 : 7_600,
                    qualifyingDays: final ? 3 : 2,
                    scoreableDays: 3,
                    dayRate: final ? 1 : 2.0 / 3.0,
                    reachedTargetAt: final
                        ? now.addingTimeInterval(-12 * 3_600)
                        : nil,
                    integrityScore: final ? 97 : nil,
                    integrityFlags: final ? [] : nil,
                    rationale: final ? winnerRationale : nil,
                    obligation: nil
                ),
                ChallengeStanding(
                    participantID: callerID,
                    displayName: "Austin",
                    handle: "austinmoves",
                    displayOrder: 2,
                    rank: 2,
                    qualified: final,
                    total: final ? 10_100 : 6_400,
                    qualifyingDays: final ? 3 : 2,
                    scoreableDays: 3,
                    dayRate: final ? 1 : 2.0 / 3.0,
                    reachedTargetAt: final
                        ? now.addingTimeInterval(-10 * 3_600)
                        : nil,
                    integrityScore: final ? 95 : 94.5,
                    integrityFlags: [],
                    rationale: callerRationale,
                    obligation: final
                        ? ChallengeObligation(
                            id: obligationID,
                            kind: .loserToWinnerCharity,
                            amountCents: 1_000,
                            charityID: charityID,
                            charityName: "Fixture Community Fund",
                            charitySlug: "fixture-community-fund",
                            destinationOwnerID: friendID,
                            resultDisputeClosesAt: now.addingTimeInterval(
                                7 * 86_400
                            )
                        )
                        : nil
                ),
            ]
        )
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
    case lostResponse
    case requestChanged

    var errorDescription: String? {
        switch self {
        case .offline:
            "Network unavailable in this fixture."
        case .lostResponse:
            "Network connection was lost after the contest committed."
        case .requestChanged:
            "Request UUID already used with different contest terms."
        }
    }
}

private struct FixtureChallengeRequest {
    let terms: ChallengeTerms
    let contestID: UUID
}

private actor FixturePendingChallengeStore: PendingChallengeStore {
    private var submission: PendingChallengeSubmission?

    init(submission: PendingChallengeSubmission?) {
        self.submission = submission
    }

    func load(for ownerID: UUID) throws -> PendingChallengeSubmission? {
        guard let submission else { return nil }
        try submission.validate(for: ownerID)
        return submission
    }

    func save(_ submission: PendingChallengeSubmission) throws {
        try submission.validate(for: submission.ownerID)
        self.submission = submission
    }

    func remove(for ownerID: UUID) throws {
        guard submission?.ownerID == ownerID else { return }
        submission = nil
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
        guard let exact = ExactHandleSubmission.normalized(handle) else {
            return nil
        }
        return store.discoverableProfiles.first {
            $0.handle.caseInsensitiveCompare(exact) == .orderedSame
        }
    }

    func requestFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        guard !store.offline else { throw FixtureFailure.offline }
        guard
            let profile = store.discoverableProfiles.first(
                where: { $0.id == otherUserID }
            )
        else {
            throw AppMutationError.permissionDenied
        }
        let now = Date()
        store.cards.removeAll { $0.otherUserID == otherUserID }
        store.cards.append(
            FriendshipCard(
                otherUserID: otherUserID,
                handle: profile.handle,
                displayName: profile.displayName,
                status: store.instantlyAcceptFriendRequests
                    ? .accepted
                    : .pending,
                requestedBy: callerID,
                createdAt: now,
                updatedAt: now,
                acceptedAt: store.instantlyAcceptFriendRequests ? now : nil
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

    func standings(contestID: UUID) async throws -> ChallengeStandings? {
        try await store.prepareRead()
        return store.standingsByContestID[contestID]
    }

    func createChallenge(
        _ terms: ChallengeTerms,
        expectedUserID: UUID
    ) async throws -> UUID {
        guard !store.offline else { throw FixtureFailure.offline }
        guard store.userID == expectedUserID else {
            throw AppMutationError.permissionDenied
        }
        if let existing = store.challengeRequests[terms.requestID] {
            guard existing.terms == terms else {
                throw FixtureFailure.requestChanged
            }
            return existing.contestID
        }

        let id = UUID()
        store.challengeRequests[terms.requestID] = FixtureChallengeRequest(
            terms: terms,
            contestID: id
        )
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
                myStatus: .accepted,
                maxParticipants: terms.maxParticipants,
                participantTimeZone: terms.timezone,
                timeZoneChanges: [],
                participants: [
                    ContestParticipantCard(
                        userID: expectedUserID,
                        status: .accepted,
                        charityID: terms.charityID
                    ),
                ] + terms.inviteeIDs.map {
                    ContestParticipantCard(
                        userID: $0,
                        status: .invited,
                        charityID: nil
                    )
                }
            )
        )
        if store.lostChallengeResponse, !store.hasLostChallengeResponse {
            store.hasLostChallengeResponse = true
            throw FixtureFailure.lostResponse
        }
        return id
    }

    func acceptInvitation(
        contestID: UUID,
        userID: UUID,
        timezone: String,
        charityID: UUID
    ) async throws {
        guard !store.offline else { throw FixtureFailure.offline }
        update(
            contestID: contestID,
            userID: userID,
            status: .accepted,
            timezone: timezone,
            charityID: charityID
        )
    }

    func declineInvitation(contestID: UUID, userID: UUID) async throws {
        guard !store.offline else { throw FixtureFailure.offline }
        update(
            contestID: contestID,
            userID: userID,
            status: .declined
        )
    }

    private func update(
        contestID: UUID,
        userID: UUID,
        status: ContestParticipantStatus,
        timezone: String? = nil,
        charityID: UUID? = nil
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
            myStatus: status,
            maxParticipants: original.maxParticipants,
            participantTimeZone: status == .accepted
                ? (timezone ?? original.participantTimeZone)
                : nil,
            timeZoneChanges: original.timeZoneChanges,
            participants: original.resolvedParticipants.map {
                guard $0.userID == userID else { return $0 }
                return ContestParticipantCard(
                    userID: $0.userID,
                    status: status,
                    charityID: charityID ?? $0.charityID
                )
            }
        )
    }
}

@MainActor
private final class FixtureActivitySyncCoordinator: ActivitySyncing {
    func requestAuthorization() async throws
        -> ActivityAuthorizationOutcome
    {
        .requestCompleted
    }

    func pendingUploadCount(for ownerID: UUID) async throws -> Int {
        _ = ownerID
        return 0
    }

    func sync(
        ownerID: UUID,
        contest: ContestCard,
        asOf: Date
    ) async throws -> ActivitySyncOutcome {
        _ = ownerID
        _ = contest
        _ = asOf
        return .noReadableData
    }
}
#endif
