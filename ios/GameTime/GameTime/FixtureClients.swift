#if DEBUG || STAGING
import Foundation

@MainActor
enum FixtureServicesFactory {
    static func make(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        pendingChallengeStore: (any PendingChallengeStore)? = nil,
        friendshipsClient: (any FriendshipsClient)? = nil,
        contestsClient: (any ContestsClient)? = nil,
        activitySync: (any ActivitySyncing)? = nil,
        pendingPersonalChallengeStore:
            (any PendingPersonalChallengeStore)? = nil,
        personalAccountabilityClient:
            (any PersonalAccountabilityClient)? = nil,
        personalPaymentClient: (any PersonalPaymentClient)? = nil,
        trustedActivityDiagnosticClient:
            (any TrustedActivityDiagnosticClient)? = nil,
        personalActivitySync: (any PersonalActivitySyncing)? = nil,
        personalHealthSteps: (any PersonalHealthStepReading)? = nil,
        personalStepSnapshotCache:
            (any PersonalStepSnapshotCaching)? = nil,
        personalHealthSnapshotUploader:
            (any PersonalHealthSnapshotUploading)? = nil
    ) -> AppServices {
        let scenario = FixtureScenario(arguments: arguments)
        let store = FixtureStore(scenario: scenario)
        let personalStore = FixturePersonalStore(scenario: scenario)
        let accountability = personalAccountabilityClient
            ?? FixturePersonalAccountabilityClient(
                store: personalStore,
                authStore: store,
                settlementMode: scenario.stripeSandbox
                    ? .stripeSandbox
                    : .testOnly
            )
        return AppServices(
            auth: FixtureAuthClient(store: store),
            profiles: FixtureProfileClient(store: store),
            friendships: friendshipsClient
                ?? FixtureFriendshipsClient(store: store),
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
                ),
            personalAccountability: accountability,
            personalPayments: personalPaymentClient
                ?? FixturePersonalPaymentClient(
                    accountability: accountability
                ),
            pendingPersonalChallenges: pendingPersonalChallengeStore
                ?? FixturePendingPersonalChallengeStore(
                    submission: scenario.pendingPersonalCreation
                        ? FixturePersonalStore.pendingCreationSubmission()
                        : nil
                ),
            trustedActivityDiagnostic: trustedActivityDiagnosticClient
                ?? FixtureTrustedActivityDiagnosticClient(
                    store: personalStore
                ),
            personalActivitySync: personalActivitySync
                ?? FixturePersonalActivitySyncCoordinator(
                    store: personalStore
                ),
            personalHealthSteps: personalHealthSteps
                ?? FixturePersonalHealthStepReader(store: personalStore),
            personalStepSnapshotCache: personalStepSnapshotCache
                ?? EphemeralPersonalStepSnapshotCache(),
            personalHealthSnapshotUploader: personalHealthSnapshotUploader
                ?? DisabledPersonalHealthSnapshotUploader()
        )
    }
}

private struct FixtureScenario {
    let signedOut: Bool
    let onboarding: Bool
    let empty: Bool
    let offline: Bool
    let loading: Bool
    let launchError: Bool
    let pendingChallenge: Bool
    let lostChallengeResponse: Bool
    let finalStandings: Bool
    let activity: Bool
    let instantlyAcceptFriendRequests: Bool
    let personalHold: Bool
    let personalNoDiagnostic: Bool
    let pendingPersonalCreation: Bool
    let stripeSandbox: Bool
    let stripeReview: Bool

    init(arguments: [String]) {
        signedOut = arguments.contains("--fixture-signed-out")
        onboarding = arguments.contains("--fixture-onboarding")
        empty = arguments.contains("--fixture-empty")
        offline = arguments.contains("--fixture-offline")
        loading = arguments.contains("--fixture-loading")
        launchError = arguments.contains("--fixture-launch-error")
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
        personalHold = arguments.contains("--fixture-personal-hold")
        personalNoDiagnostic = arguments.contains(
            "--fixture-personal-no-diagnostic"
        )
        pendingPersonalCreation = arguments.contains(
            "--fixture-personal-pending"
        )
        stripeSandbox = arguments.contains("--fixture-stripe-sandbox")
        stripeReview = arguments.contains("--fixture-stripe-review")
    }
}

@MainActor
private final class FixturePersonalStore {
    static let activeChallengeID = UUID(
        uuidString: "18181818-1818-1818-1818-181818181818"
    )!
    static let completedChallengeID = UUID(
        uuidString: "19191919-1919-1919-1919-191919191919"
    )!
    static let diagnosticID = UUID(
        uuidString: "20202020-2020-2020-2020-202020202020"
    )!
    static let holdID = UUID(
        uuidString: "21212121-2121-2121-2121-212121212121"
    )!

    var challenges: [PersonalChallengeDetail]
    var requests: [UUID: (
        request: PersonalChallengeCreationRequest,
        challengeID: UUID
    )] = [:]
    var latestDiagnostic: TrustedActivityDiagnostic?
    var eligibilityHold: PersonalEligibilityHold?
    let offline: Bool

    init(scenario: FixtureScenario, now: Date = Date()) {
        offline = scenario.offline
        latestDiagnostic = scenario.personalNoDiagnostic
            ? nil
            : Self.trustedDiagnostic(at: now.addingTimeInterval(-1_800))
        eligibilityHold = scenario.personalHold
            ? PersonalEligibilityHold(
                id: Self.holdID,
                reasonCode: "unresolved_device_sync",
                createdAt: now.addingTimeInterval(-3_600),
                clearedAt: nil,
                clearedByDiagnosticID: nil
            )
            : nil
        challenges = scenario.empty
            ? []
            : [
                Self.activeChallenge(now: now),
                Self.completedChallenge(
                    now: now,
                    stripeReview: scenario.stripeReview
                ),
            ]
    }

    static func trustedDiagnostic(at date: Date) -> TrustedActivityDiagnostic {
        TrustedActivityDiagnostic(
            id: diagnosticID,
            status: .trusted,
            performedAt: date,
            trustedQueriedHourCount: 24,
            positiveTrustedSampleCount: 8,
            clearsEligibilityHold: true
        )
    }

    static func pendingCreationSubmission(
        now: Date = Date()
    ) -> PendingPersonalChallengeSubmission {
        PendingPersonalChallengeSubmission(
            ownerID: FixtureStore.callerID,
            request: PersonalChallengeCreationRequest(
                requestID: UUID(
                    uuidString: "23232323-2323-2323-2323-232323232323"
                )!,
                cadence: .cumulative,
                targetSteps: 70_000,
                commitmentAmountMinor: 3_000,
                timezone: "America/Chicago"
            ),
            createdAt: now.addingTimeInterval(-300),
            attemptCount: 1,
            lastAttemptAt: now.addingTimeInterval(-240)
        )
    }

    private static func activeChallenge(now: Date) -> PersonalChallengeDetail {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -2, to: today)!
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        let cutoff = calendar.date(byAdding: .day, value: 1, to: end)!
        let days = (0..<7).map { offset -> PersonalDayProgress in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            let isFuture = date >= today
            let steps = offset == 0 ? 10_482 : offset == 1 ? 7_350 : 0
            return PersonalDayProgress(
                localDate: Self.localDate(date, calendar: calendar),
                trustedSteps: Double(steps),
                targetSteps: 10_000,
                evidenceState: isFuture ? .future : .complete,
                metTarget: isFuture ? nil : steps >= 10_000
            )
        }
        return PersonalChallengeDetail(
            id: activeChallengeID,
            status: .active,
            terms: FrozenPersonalTerms(
                challengeID: activeChallengeID,
                userID: FixtureStore.callerID,
                cadence: .daily,
                targetSteps: 10_000,
                commitmentAmountMinor: 1_000,
                currency: "USD",
                settlementMode: .testOnly,
                termsVersion: "personal-v2",
                timezone: "America/Chicago",
                agreementAt: start.addingTimeInterval(-86_400),
                startsAt: start,
                endsAt: end,
                evidenceCutoff: cutoff,
                closedAt: nil
            ),
            progress: PersonalProgress(
                trustedSteps: days.reduce(0) {
                    $0 + $1.displayedTrustedSteps
                },
                remainingSteps: 2_650,
                qualifyingDays: 1,
                completedDays: 2,
                days: days,
                evidenceState: .inProgress,
                lastTrustedSyncAt: now.addingTimeInterval(-600),
                pendingUploadCount: 0,
                coveredBucketCount: 47,
                expectedBucketCount: 48
            ),
            stepDataPolicy: .healthKitNonmanualDailyV1,
            termsFingerprint: "fixture-active-terms-v2",
            serverStepSnapshot: PersonalStepSnapshot(
                challengeID: activeChallengeID,
                termsFingerprint: "fixture-active-terms-v2",
                observedAt: now,
                queryThrough: now,
                dailyProgress: days.map {
                    PersonalStepSnapshot.Day(
                        localDate: $0.localDate,
                        totalSteps: $0.displayedTrustedSteps
                    )
                }
            ),
            snapshotUpdatedAt: now
        )
    }

    private static func completedChallenge(
        now: Date,
        stripeReview: Bool
    )
        -> PersonalChallengeDetail
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        let end = calendar.date(
            byAdding: .day,
            value: stripeReview ? -2 : -9,
            to: calendar.startOfDay(for: now)
        )!
        let start = calendar.date(byAdding: .day, value: -7, to: end)!
        let cutoff = calendar.date(byAdding: .day, value: 1, to: end)!
        let days = (0..<7).map { offset -> PersonalDayProgress in
            let date = calendar.date(byAdding: .day, value: offset, to: start)!
            return PersonalDayProgress(
                localDate: Self.localDate(date, calendar: calendar),
                trustedSteps: stripeReview
                    ? 8_000
                    : Double(10_000 + offset * 190),
                targetSteps: nil,
                evidenceState: .complete,
                metTarget: nil
            )
        }
        return PersonalChallengeDetail(
            id: completedChallengeID,
            status: .completed,
            terms: FrozenPersonalTerms(
                challengeID: completedChallengeID,
                userID: FixtureStore.callerID,
                cadence: .cumulative,
                targetSteps: 70_000,
                commitmentAmountMinor: 2_000,
                currency: "USD",
                settlementMode: stripeReview
                    ? .stripeSandbox
                    : .testOnly,
                termsVersion: stripeReview
                    ? "personal-stripe-sandbox-v1"
                    : "personal-v2",
                timezone: "America/Chicago",
                agreementAt: start.addingTimeInterval(-86_400),
                startsAt: start,
                endsAt: end,
                evidenceCutoff: cutoff,
                closedAt: cutoff
            ),
            progress: PersonalProgress(
                trustedSteps: days.reduce(0) {
                    $0 + $1.displayedTrustedSteps
                },
                remainingSteps: stripeReview ? 14_000 : 0,
                qualifyingDays: 0,
                completedDays: 7,
                days: days,
                evidenceState: .complete,
                lastTrustedSyncAt: end.addingTimeInterval(-300),
                pendingUploadCount: 0,
                coveredBucketCount: 168,
                expectedBucketCount: 168
            ),
            outcome: PersonalOutcome(
                id: UUID(
                    uuidString: "22222222-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
                )!,
                kind: stripeReview ? .missedGoal : .metGoal,
                reasonCode: stripeReview
                    ? "target_missed_complete_evidence"
                    : "target_reached_complete_evidence",
                evidenceCutoff: cutoff,
                publishedAt: cutoff.addingTimeInterval(60)
            ),
            stepDataPolicy: .healthKitNonmanualDailyV1,
            termsFingerprint: "fixture-completed-terms-v2",
            serverStepSnapshot: PersonalStepSnapshot(
                challengeID: completedChallengeID,
                termsFingerprint: "fixture-completed-terms-v2",
                observedAt: cutoff,
                queryThrough: end,
                dailyProgress: days.map {
                    PersonalStepSnapshot.Day(
                        localDate: $0.localDate,
                        totalSteps: $0.displayedTrustedSteps
                    )
                }
            ),
            snapshotUpdatedAt: cutoff,
            commitmentWaived: false
        )
    }

    fileprivate static func localDate(
        _ date: Date,
        calendar: Calendar
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day],
            from: date
        )
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
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
    let launchError: Bool
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
        launchError = scenario.launchError
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
        if store.launchError {
            throw FixtureFailure.offline
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

    func listChallengeSummaries(userID: UUID) async throws
        -> [ChallengeRosterSummary]
    {
        try await store.prepareRead()
        _ = userID
        return store.contests.map { contest in
            let participants = contest.resolvedParticipants
            return ChallengeRosterSummary(
                contest: contest,
                maxParticipants: contest.maxParticipants
                    ?? max(participants.count, 2),
                acceptedCount: participants.filter { $0.status == .accepted }.count,
                invitedCount: participants.filter { $0.status == .invited }.count,
                declinedCount: participants.filter { $0.status == .declined }.count,
                withdrawnCount: participants.filter { $0.status == .withdrawn }.count,
                lapsedCount: participants.filter { $0.status == .lapsed }.count,
                author: nil,
                acceptedParticipants: []
            )
        }
    }

    func listCharities() async throws -> [Charity] {
        try await store.prepareRead()
        return store.charities
    }

    func standings(contestID: UUID) async throws -> ChallengeStandings? {
        try await store.prepareRead()
        return store.standingsByContestID[contestID]
    }

    func sendComebackReaction(
        contestID: UUID,
        snapshotID: UUID
    ) async throws {
        guard !store.offline else { throw FixtureFailure.offline }
        guard store.standingsByContestID[contestID]?.snapshotID == snapshotID
        else {
            throw AppMutationError.permissionDenied
        }
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

    func retirePendingUploads(
        for ownerID: UUID,
        contestID: UUID
    ) async throws {
        _ = (ownerID, contestID)
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

private actor FixturePendingPersonalChallengeStore:
    PendingPersonalChallengeStore
{
    private var submission: PendingPersonalChallengeSubmission?

    init(submission: PendingPersonalChallengeSubmission?) {
        self.submission = submission
    }

    func load(for ownerID: UUID) throws
        -> PendingPersonalChallengeSubmission?
    {
        try submission?.validate(for: ownerID)
        return submission
    }

    func save(_ submission: PendingPersonalChallengeSubmission) throws {
        try submission.validate(for: submission.ownerID)
        self.submission = submission
    }

    func remove(for ownerID: UUID) {
        guard submission?.ownerID == ownerID else { return }
        submission = nil
    }
}

@MainActor
private final class FixturePersonalAccountabilityClient:
    PersonalAccountabilityClient
{
    private let store: FixturePersonalStore
    private let authStore: FixtureStore
    private let settlementMode: PersonalSettlementMode

    init(
        store: FixturePersonalStore,
        authStore: FixtureStore,
        settlementMode: PersonalSettlementMode
    ) {
        self.store = store
        self.authStore = authStore
        self.settlementMode = settlementMode
    }

    func listMyChallenges() async throws -> PersonalAccountabilitySnapshot {
        guard !store.offline else { throw FixtureFailure.offline }
        return PersonalAccountabilitySnapshot(
            challenges: store.challenges.map(Self.summary),
            latestDiagnostic: store.latestDiagnostic,
            eligibilityHold: store.eligibilityHold
        )
    }

    func challenge(id: UUID) async throws -> PersonalChallengeDetail? {
        guard !store.offline else { throw FixtureFailure.offline }
        return store.challenges.first { $0.id == id }
    }

    func create(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> UUID {
        guard !store.offline else { throw FixtureFailure.offline }
        guard authStore.userID == expectedUserID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        if let existing = store.requests[request.requestID] {
            guard existing.request == request else {
                throw PendingPersonalChallengeStoreError.conflictingRecord
            }
            return existing.challengeID
        }
        guard !store.challenges.contains(where: { $0.status.isOpen }) else {
            throw PersonalAccountabilityClientError.openChallengeExists
        }
        guard store.eligibilityHold?.isActive != true else {
            throw PersonalAccountabilityClientError.eligibilityHold
        }

        let challenge = Self.scheduledChallenge(
            request: request,
            ownerID: expectedUserID,
            settlementMode: settlementMode
        )
        store.requests[request.requestID] = (request, challenge.id)
        store.challenges.insert(challenge, at: 0)
        return challenge.id
    }

    func cancel(
        challengeID: UUID,
        requestID: UUID,
        expectedUserID: UUID
    ) async throws {
        _ = requestID
        guard !store.offline else { throw FixtureFailure.offline }
        guard authStore.userID == expectedUserID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        guard let index = store.challenges.firstIndex(where: {
            $0.id == challengeID
        }) else { return }
        let original = store.challenges[index]
        let canCancelBeforeStart =
            original.status == .scheduled && Date() < original.terms.startsAt
        let canCleanUpTestChallenge =
            settlementMode == .testOnly
            && original.terms.settlementMode == .testOnly
            && (original.status == .scheduled || original.status == .active)
        guard canCancelBeforeStart || canCleanUpTestChallenge else {
            throw PersonalAccountabilityClientError.cancellationClosed
        }
        store.challenges[index] = PersonalChallengeDetail(
            id: original.id,
            status: .cancelled,
            terms: FrozenPersonalTerms(
                challengeID: original.terms.challengeID,
                userID: original.terms.userID,
                cadence: original.terms.cadence,
                targetSteps: original.terms.targetSteps,
                commitmentAmountMinor: original.terms.commitmentAmountMinor,
                currency: original.terms.currency,
                settlementMode: original.terms.settlementMode,
                termsVersion: original.terms.termsVersion,
                timezone: original.terms.timezone,
                agreementAt: original.terms.agreementAt,
                startsAt: original.terms.startsAt,
                endsAt: original.terms.endsAt,
                evidenceCutoff: original.terms.evidenceCutoff,
                closedAt: Date()
            ),
            progress: original.progress,
            outcome: nil,
            stepDataPolicy: original.stepDataPolicy,
            termsFingerprint: original.termsFingerprint,
            serverStepSnapshot: original.serverStepSnapshot,
            snapshotUpdatedAt: original.snapshotUpdatedAt,
            commitmentWaived: original.commitmentWaived
        )
    }

    private static func summary(
        _ detail: PersonalChallengeDetail
    ) -> PersonalChallengeSummary {
        PersonalChallengeSummary(
            id: detail.id,
            status: detail.status,
            terms: detail.terms,
            progress: detail.progress,
            outcome: detail.outcome,
            stepDataPolicy: detail.stepDataPolicy,
            termsFingerprint: detail.termsFingerprint,
            serverStepSnapshot: detail.serverStepSnapshot,
            snapshotUpdatedAt: detail.snapshotUpdatedAt,
            commitmentWaived: detail.commitmentWaived
        )
    }

    private static func scheduledChallenge(
        request: PersonalChallengeCreationRequest,
        ownerID: UUID,
        settlementMode: PersonalSettlementMode,
        now: Date = Date()
    ) -> PersonalChallengeDetail {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.timezone)
            ?? TimeZone(secondsFromGMT: 0)!
        // Mirrors `create_personal_challenge_v1`: an omitted start means the
        // next local midnight, and the window always closes at the local
        // midnight after the seventh local date. A start later in the day
        // therefore shortens day one rather than moving the end.
        let start = request.startsAt
            ?? PersonalChallengeStart.nextLocalMidnight(
                now: now,
                timezone: request.timezone
            )
        let firstLocalDay = calendar.startOfDay(for: start)
        let end = calendar.date(byAdding: .day, value: 7, to: firstLocalDay)!
        let cutoff = calendar.date(byAdding: .day, value: 1, to: end)!
        let id = UUID()
        let days = (0..<7).map { offset in
            PersonalDayProgress(
                localDate: FixturePersonalStore.localDate(
                    calendar.date(
                        byAdding: .day,
                        value: offset,
                        to: firstLocalDay
                    )!,
                    calendar: calendar
                ),
                trustedSteps: 0,
                targetSteps: request.cadence == .daily
                    ? request.targetSteps
                    : nil,
                evidenceState: .future,
                metTarget: nil
            )
        }
        return PersonalChallengeDetail(
            id: id,
            status: .scheduled,
            terms: FrozenPersonalTerms(
                challengeID: id,
                userID: ownerID,
                cadence: request.cadence,
                targetSteps: request.targetSteps,
                commitmentAmountMinor: request.commitmentAmountMinor,
                currency: "USD",
                settlementMode: settlementMode,
                termsVersion: "personal-v2",
                timezone: request.timezone,
                agreementAt: now,
                startsAt: start,
                endsAt: end,
                evidenceCutoff: cutoff,
                closedAt: nil
            ),
            progress: PersonalProgress(
                trustedSteps: 0,
                remainingSteps: request.targetSteps,
                qualifyingDays: 0,
                completedDays: 0,
                days: days,
                evidenceState: .future,
                lastTrustedSyncAt: nil,
                pendingUploadCount: 0,
                coveredBucketCount: 0,
                expectedBucketCount: 0
            ),
            stepDataPolicy: .healthKitNonmanualDailyV1,
            termsFingerprint: "fixture-\(id.uuidString.lowercased())"
        )
    }
}

@MainActor
private final class FixturePersonalPaymentClient: PersonalPaymentClient {
    private let accountability: any PersonalAccountabilityClient

    init(accountability: any PersonalAccountabilityClient) {
        self.accountability = accountability
    }

    func prepare(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> PersonalPaymentSetup {
        _ = (request, expectedUserID)
        return PersonalPaymentSetup(
            setupID: "33333333-3333-3333-3333-333333333333",
            presentation: .alreadyConfirmed
        )
    }

    func commit(
        _ request: PersonalChallengeCreationRequest,
        setupID: String,
        expectedUserID: UUID
    ) async throws -> UUID {
        guard setupID == "33333333-3333-3333-3333-333333333333" else {
            throw PersonalPaymentClientError.invalidResponse
        }
        return try await accountability.create(
            request,
            expectedUserID: expectedUserID
        )
    }

    func requestReview(
        challengeID: UUID,
        reason: PersonalReviewReason,
        expectedUserID: UUID
    ) async throws -> PersonalReviewRequestResult {
        _ = (challengeID, reason, expectedUserID)
        return PersonalReviewRequestResult(
            state: .underReview,
            reviewDeadline: Date().addingTimeInterval(6 * 86_400),
            replayed: false
        )
    }
}

@MainActor
private final class FixtureTrustedActivityDiagnosticClient:
    TrustedActivityDiagnosticClient
{
    private let store: FixturePersonalStore

    init(store: FixturePersonalStore) {
        self.store = store
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        guard !store.offline else { throw FixtureFailure.offline }
        return .requestCompleted
    }

    func probeLocalStepAccess(
        timezone: String
    ) async throws -> LocalStepAccessProbe {
        _ = timezone
        guard !store.offline else { throw FixtureFailure.offline }
        return LocalStepAccessProbe(
            trustedHourCount: 24,
            positiveTrustedSampleCount: 12,
            observedAt: Date()
        )
    }

    func runTrustedDiagnostic(
        ownerID: UUID,
        timezone: String
    ) async throws -> TrustedActivityDiagnostic {
        _ = (ownerID, timezone)
        guard !store.offline else { throw FixtureFailure.offline }
        let diagnostic = FixturePersonalStore.trustedDiagnostic(at: Date())
        store.latestDiagnostic = diagnostic
        store.eligibilityHold = nil
        return diagnostic
    }
}

@MainActor
private final class FixturePersonalActivitySyncCoordinator:
    PersonalActivitySyncing
{
    private let store: FixturePersonalStore

    init(store: FixturePersonalStore) {
        self.store = store
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        guard !store.offline else { throw FixtureFailure.offline }
        return .requestCompleted
    }

    func pendingUploadCount(for ownerID: UUID) async throws -> Int {
        _ = ownerID
        guard !store.offline else { throw FixtureFailure.offline }
        return 0
    }

    func retirePendingUploads(
        for ownerID: UUID,
        challengeID: UUID
    ) async throws {
        _ = (ownerID, challengeID)
    }

    func sync(
        ownerID: UUID,
        challenge: PersonalChallengeDetail,
        asOf: Date
    ) async throws -> ActivitySyncOutcome {
        _ = (ownerID, asOf)
        guard !store.offline else { throw FixtureFailure.offline }
        return .synced(
            replayed: false,
            stepTotal: Double(challenge.progress.trustedSteps)
        )
    }
}

@MainActor
private final class FixturePersonalHealthStepReader:
    PersonalHealthStepReading
{
    private let store: FixturePersonalStore

    init(store: FixturePersonalStore) {
        self.store = store
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        guard !store.offline else { throw FixtureFailure.offline }
        return .requestCompleted
    }

    func readSnapshot(
        challengeID: UUID,
        terms: FrozenPersonalTerms,
        termsFingerprint: String,
        observedAt: Date
    ) async throws -> PersonalStepSnapshot {
        guard !store.offline else { throw FixtureFailure.offline }
        let plan = try PersonalHealthSnapshotPlanner.plan(
            terms: terms,
            observedAt: observedAt
        )
        let existing = store.challenges.first(where: {
            $0.id == challengeID
        })?.serverStepSnapshot
        let totals = Dictionary(
            uniqueKeysWithValues: (existing?.dailyProgress ?? []).map {
                ($0.localDate, $0.totalSteps)
            }
        )
        return PersonalStepSnapshot(
            challengeID: challengeID,
            termsFingerprint: termsFingerprint,
            observedAt: observedAt,
            queryThrough: plan.queryThrough,
            dailyProgress: plan.days.map {
                PersonalStepSnapshot.Day(
                    localDate: $0.localDate,
                    totalSteps: totals[$0.localDate, default: 0]
                )
            }
        )
    }
}
#endif
