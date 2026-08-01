import XCTest

@testable import GameTime

@MainActor
final class AppModelAndRoutingTests: XCTestCase {
    func testFixtureLaunchRestoresSignedInLiveShape() async {
        let services = FixtureServicesFactory.make(
            arguments: ["GameTimeTests", "--fixture-mode"]
        )
        let model = AppModel(
            configuration: .fixture,
            services: services
        )

        await model.start()

        XCTAssertEqual(model.phase, .signedIn)
        XCTAssertEqual(model.profile?.handle, "austinmoves")
        XCTAssertFalse(model.friendshipCards.isEmpty)
        XCTAssertFalse(model.contests.isEmpty)
        XCTAssertEqual(model.loadState, .loaded)
    }

    func testFixtureLaunchFailureRemainsLaunchingAndSupportsExplicitRetry()
        async
    {
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: [
                    "GameTimeTests",
                    "--fixture-mode",
                    "--fixture-launch-error",
                ]
            )
        )

        await model.start()

        XCTAssertEqual(model.phase, .launching)
        XCTAssertTrue(
            model.presentedError?.localizedCaseInsensitiveContains(
                "offline"
            ) == true
        )

        await model.retryLaunch()

        XCTAssertEqual(model.phase, .launching)
        XCTAssertTrue(
            model.presentedError?.localizedCaseInsensitiveContains(
                "offline"
            ) == true
        )
    }

    func testFixtureLoadsProvisionalStandingsWithRivalIntegrityRedacted()
        async throws
    {
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"]
            )
        )
        await model.start()
        let contest = try XCTUnwrap(
            model.contests.first { $0.status == .active }
        )

        await model.loadStandings(contestID: contest.id)

        let standings = try XCTUnwrap(model.standings(for: contest.id))
        let callerID = try XCTUnwrap(model.userID)
        let caller = try XCTUnwrap(
            standings.standings.first { $0.participantID == callerID }
        )
        let rival = try XCTUnwrap(
            standings.standings.first { $0.participantID != callerID }
        )
        XCTAssertEqual(standings.phase, .provisional)
        XCTAssertEqual(model.standingsLoadState(for: contest.id), .loaded)
        XCTAssertNotNil(caller.integrityScore)
        XCTAssertNil(rival.integrityScore)
        XCTAssertNil(rival.integrityFlags)
        XCTAssertNil(rival.rationale)
    }

    func testFixtureLoadsFinalRankingsAndOnlyLoserObligation() async throws {
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: [
                    "GameTimeTests",
                    "--fixture-mode",
                    "--fixture-final-standings",
                ]
            )
        )
        await model.start()
        let contest = try XCTUnwrap(
            model.contests.first { $0.status == .finalized }
        )

        await model.loadStandings(contestID: contest.id)

        let standings = try XCTUnwrap(model.standings(for: contest.id))
        let callerID = try XCTUnwrap(model.userID)
        let caller = try XCTUnwrap(
            standings.standings.first { $0.participantID == callerID }
        )
        let winner = try XCTUnwrap(
            standings.standings.first {
                $0.participantID == standings.result?.winnerParticipantID
            }
        )
        XCTAssertEqual(standings.phase, .final)
        XCTAssertEqual(standings.result?.kind, .winner)
        XCTAssertNotNil(caller.obligation)
        XCTAssertEqual(caller.obligation?.amountCents, 1_000)
        XCTAssertNil(winner.obligation)
        XCTAssertTrue(
            standings.standings.allSatisfy { $0.integrityScore != nil }
        )
    }

    func testAuthenticatedUserWithoutProfileEntersOnboarding() async {
        let services = FixtureServicesFactory.make(
            arguments: [
                "GameTimeTests",
                "--fixture-mode",
                "--fixture-onboarding",
            ]
        )
        let model = AppModel(
            configuration: .fixture,
            services: services
        )

        await model.start()
        XCTAssertEqual(model.phase, .onboarding)

        await model.completeOnboarding(
            handle: "new_runner",
            displayName: "New Runner"
        )
        XCTAssertEqual(model.phase, .signedIn)
        XCTAssertEqual(model.profile?.handle, "new_runner")
    }

    func testSignOutClearsEveryLoadedUserValue() async {
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: [
                    "GameTimeTests",
                    "--fixture-mode",
                    "--fixture-pending-challenge",
                ]
            )
        )
        await model.start()
        XCTAssertFalse(model.contests.isEmpty)
        XCTAssertNotNil(model.pendingChallenge)
        let activeContest = try! XCTUnwrap(
            model.contests.first { $0.status == .active }
        )
        await model.loadStandings(contestID: activeContest.id)
        XCTAssertFalse(model.standingsByContestID.isEmpty)
        model.presentedError = "Private prior-session error"

        await model.signOut()

        XCTAssertEqual(model.phase, .signedOut)
        XCTAssertNil(model.userID)
        XCTAssertNil(model.profile)
        XCTAssertTrue(model.friendshipCards.isEmpty)
        XCTAssertTrue(model.contests.isEmpty)
        XCTAssertTrue(model.charities.isEmpty)
        XCTAssertTrue(model.standingsByContestID.isEmpty)
        XCTAssertTrue(model.standingsLoadStates.isEmpty)
        XCTAssertNil(model.exactHandleResult)
        XCTAssertNil(model.pendingChallenge)
        XCTAssertFalse(model.hasPendingChallengeRecoveryIssue)
        XCTAssertNil(model.presentedError)
    }

    func testRouterResetClearsEveryIndependentStackAndSheet() {
        let router = AppRouter()
        router.selectedTab = .you
        router.todayPath = [.contest(UUID())]
        router.challengesPath = [.contest(UUID())]
        router.friendsPath = [.profile(UUID())]
        router.youPath = [.trustAndPrivacy]
        router.presentedSheet = .createChallenge

        router.reset()

        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertTrue(router.todayPath.isEmpty)
        XCTAssertTrue(router.challengesPath.isEmpty)
        XCTAssertTrue(router.friendsPath.isEmpty)
        XCTAssertTrue(router.youPath.isEmpty)
        XCTAssertNil(router.presentedSheet)
    }

    func testRouterOpensPushDestinationDirectlyOnStandings() {
        let contestID = UUID()
        let router = AppRouter()
        router.presentedSheet = .createChallenge
        router.todayPath = [.contest(UUID())]

        router.openStandings(contestID: contestID)

        XCTAssertEqual(router.selectedTab, .challenges)
        XCTAssertEqual(router.challengesPath, [.standings(contestID)])
        XCTAssertNil(router.presentedSheet)
    }

    func testPushEnvironmentIsStagingDevelopmentOnly() {
        XCTAssertNil(
            PushNotificationCoordinator.pushEnvironment(for: .debug)
        )
        XCTAssertEqual(
            PushNotificationCoordinator.pushEnvironment(for: .staging)?
                .rawValue,
            "development"
        )
        XCTAssertNil(
            PushNotificationCoordinator.pushEnvironment(for: .release)
        )
    }

    func testComebackReactionIsIdempotentInTheModel() async throws {
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"]
            )
        )
        await model.start()
        let contest = try XCTUnwrap(
            model.contests.first { $0.status == .active }
        )
        await model.loadStandings(contestID: contest.id)
        let snapshotID = try XCTUnwrap(
            model.standings(for: contest.id)?.snapshotID
        )

        await model.sendComebackReaction(
            contestID: contest.id,
            snapshotID: snapshotID
        )
        await model.sendComebackReaction(
            contestID: contest.id,
            snapshotID: snapshotID
        )

        XCTAssertTrue(
            model.hasSentComebackReaction(snapshotID: snapshotID)
        )
        XCTAssertNil(model.reactingStandingsSnapshotID)
    }

    func testExactHandleRequestMutatesThenRefreshes() async {
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: [
                    "GameTimeTests",
                    "--fixture-mode",
                    "--fixture-empty",
                ]
            )
        )
        await model.start()

        await model.submitExactHandle("@marcusmoves")
        XCTAssertEqual(model.exactHandleResult?.handle, "marcusmoves")

        let friendID = try! XCTUnwrap(model.exactHandleResult?.id)
        await model.requestFriendship(with: friendID)

        XCTAssertEqual(model.outgoingFriendships.count, 1)
        XCTAssertNil(model.exactHandleResult)
    }

    func testInteractiveDemoAddsDavidAndCreatesChallenge() async throws {
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: [
                    "GameTimeTests",
                    "--fixture-mode",
                    "--fixture-empty",
                    "--demo-interactive",
                ]
            )
        )
        await model.start()

        await model.submitExactHandle("@david1")
        let david = try XCTUnwrap(model.exactHandleResult)
        XCTAssertEqual(david.displayName, "David Chen")

        await model.requestFriendship(with: david.id)

        XCTAssertTrue(model.outgoingFriendships.isEmpty)
        XCTAssertEqual(model.acceptedFriendships.map(\.handle), ["david1"])

        var draft = ChallengeDraft()
        draft.title = "Challenge David"
        draft.inviteeIDs = [david.id]
        draft.charityID = try XCTUnwrap(model.charities.first?.id)
        let terms = try draft.validated()

        let createdID = await model.createChallenge(terms)

        XCTAssertNotNil(createdID)
        XCTAssertEqual(
            model.contests.filter { $0.title == "Challenge David" }.count,
            1
        )
    }

    func testFixtureAndLiveFactoriesExposeTheSameClientBoundaries() throws {
        let fixture = FixtureServicesFactory.make(
            arguments: ["GameTimeTests", "--fixture-mode"]
        )
        let liveConfiguration = try AppConfiguration.validated(
            environmentValue: "Debug",
            urlValue: "http://127.0.0.1:54321",
            keyValue: "sb_publishable_compile_shape",
            mutationValue: "YES"
        )
        let live = try LiveServicesFactory.make(
            configuration: liveConfiguration
        )

        assertClientBoundary(fixture)
        assertClientBoundary(live)
    }

    func testOfflineRefreshSurfacesStateWithoutMutationRetry() async {
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: [
                    "GameTimeTests",
                    "--fixture-mode",
                    "--fixture-offline",
                ]
            )
        )

        await model.start()

        XCTAssertEqual(model.phase, .signedIn)
        guard case .failed(let message) = model.loadState else {
            return XCTFail("Expected offline failure state")
        }
        XCTAssertTrue(message.localizedCaseInsensitiveContains("offline"))
    }

    func testReleaseLocksEveryContestMutation() async throws {
        let configuration = try AppConfiguration.validated(
            environmentValue: "Release",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_release_test",
            mutationValue: "YES"
        )
        let model = AppModel(
            configuration: configuration,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"]
            )
        )
        await model.start()

        let originalCount = model.contests.count
        var draft = ChallengeDraft()
        draft.title = "Locked challenge"
        draft.inviteeIDs = Set(
            model.acceptedFriendships.map(\.otherUserID)
        )
        draft.charityID = try XCTUnwrap(model.charities.first?.id)
        let terms = try draft.validated()

        let createdID = await model.createChallenge(terms)
        XCTAssertNil(createdID)
        XCTAssertEqual(model.contests.count, originalCount)
        XCTAssertNil(model.pendingChallenge)

        let invitation = try XCTUnwrap(model.invitations.first)
        let charityID = try XCTUnwrap(model.charities.first?.id)
        await model.acceptInvitation(
            contestID: invitation.id,
            charityID: charityID
        )
        XCTAssertEqual(
            model.contests.first { $0.id == invitation.id }?.myStatus,
            .invited
        )

        await model.declineInvitation(contestID: invitation.id)
        XCTAssertEqual(
            model.contests.first { $0.id == invitation.id }?.myStatus,
            .invited
        )
        XCTAssertNotNil(model.presentedError)
    }

    func testLostResponsePersistsAndRelaunchRetriesTheSameChallenge() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let pendingStore = FilePendingChallengeStore(directoryURL: directory)
        let services = FixtureServicesFactory.make(
            arguments: [
                "GameTimeTests",
                "--fixture-mode",
                "--fixture-lost-challenge-response",
            ],
            pendingChallengeStore: pendingStore
        )
        let firstModel = AppModel(
            configuration: .fixture,
            services: services
        )
        await firstModel.start()

        var draft = ChallengeDraft()
        draft.title = "Persisted lost response"
        draft.inviteeIDs = Set(
            firstModel.acceptedFriendships.map(\.otherUserID)
        )
        draft.charityID = try XCTUnwrap(firstModel.charities.first?.id)
        let terms = try draft.validated()

        let firstCreatedID = await firstModel.createChallenge(terms)
        XCTAssertNil(firstCreatedID)
        XCTAssertTrue(
            firstModel.presentedError?.localizedCaseInsensitiveContains(
                "couldn’t confirm"
            ) == true
        )
        XCTAssertFalse(
            firstModel.presentedError?.localizedCaseInsensitiveContains(
                "not submitted"
            ) == true
        )
        let saved = try await pendingStore.load(
            for: try XCTUnwrap(firstModel.userID)
        )
        XCTAssertEqual(saved?.terms, terms)
        XCTAssertEqual(saved?.attemptCount, 1)

        let relaunchedModel = AppModel(
            configuration: .fixture,
            services: services
        )
        await relaunchedModel.start()
        let restored = try XCTUnwrap(relaunchedModel.pendingChallenge)
        XCTAssertEqual(restored.terms.requestID, terms.requestID)
        XCTAssertEqual(restored.terms, terms)

        let createdID = await relaunchedModel.createChallenge(restored.terms)
        XCTAssertNotNil(createdID)
        XCTAssertNil(relaunchedModel.pendingChallenge)
        let clearedSubmission = try await pendingStore.load(
            for: try XCTUnwrap(relaunchedModel.userID)
        )
        XCTAssertNil(clearedSubmission)
        XCTAssertEqual(
            relaunchedModel.contests.filter {
                $0.title == "Persisted lost response"
            }.count,
            1
        )
    }

    func testUnreadablePendingRecordBlocksContestRPC() async {
        let pendingStore = TestPendingChallengeStore(
            submission: nil,
            loadError: .corruptData
        )
        let contests = RecordingContestsClient()
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"],
                pendingChallengeStore: pendingStore,
                contestsClient: contests
            )
        )
        await model.start()

        XCTAssertTrue(model.hasPendingChallengeRecoveryIssue)
        let createdID = await model.createChallenge(makeTerms())
        XCTAssertNil(createdID)
        XCTAssertEqual(contests.createCallCount, 0)
    }

    func testDifferentRequestIsBlockedWhilePendingChallengeExists() async {
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let pendingTerms = makeTerms()
        let pendingStore = TestPendingChallengeStore(
            submission: PendingChallengeSubmission(
                ownerID: ownerID,
                terms: pendingTerms,
                createdAt: Date(),
                attemptCount: 1,
                lastAttemptAt: Date()
            )
        )
        let contests = RecordingContestsClient()
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"],
                pendingChallengeStore: pendingStore,
                contestsClient: contests
            )
        )
        await model.start()

        XCTAssertEqual(model.pendingChallenge?.terms, pendingTerms)
        XCTAssertEqual(
            contests.createCallCount,
            0,
            "Relaunch must restore only; it must not resend automatically."
        )
        let createdID = await model.createChallenge(makeTerms())
        XCTAssertNil(createdID)
        XCTAssertEqual(contests.createCallCount, 0)
    }

    func testCancellationRetainsPendingChallengeWithoutAnErrorAlert() async throws {
        let pendingStore = TestPendingChallengeStore(submission: nil)
        let contests = RecordingContestsClient(behavior: .cancel)
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"],
                pendingChallengeStore: pendingStore,
                contestsClient: contests
            )
        )
        await model.start()
        let terms = makeTerms()

        let createdID = await model.createChallenge(terms)

        XCTAssertNil(createdID)
        XCTAssertEqual(contests.createCallCount, 1)
        XCTAssertEqual(contests.submittedTerms, [terms])
        XCTAssertNil(model.presentedError)
        let restored = try await pendingStore.load(
            for: try XCTUnwrap(model.userID)
        )
        XCTAssertEqual(restored?.terms, terms)
        XCTAssertEqual(restored?.attemptCount, 1)
    }

    func testDiscardClearsSavedRetryAndUnlocksAReplacementChallenge() async throws {
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let pendingStore = TestPendingChallengeStore(
            submission: PendingChallengeSubmission(
                ownerID: ownerID,
                terms: makeTerms(),
                createdAt: Date().addingTimeInterval(-30),
                attemptCount: 1,
                lastAttemptAt: Date()
            )
        )
        let contests = RecordingContestsClient()
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"],
                pendingChallengeStore: pendingStore,
                contestsClient: contests
            )
        )
        await model.start()

        XCTAssertNotNil(model.pendingChallenge)
        let discarded = await model.discardPendingChallenge()
        XCTAssertTrue(discarded)
        XCTAssertNil(model.pendingChallenge)
        XCTAssertFalse(model.hasPendingChallengeRecoveryIssue)
        let storedAfterDiscard = try await pendingStore.load(for: ownerID)
        XCTAssertNil(storedAfterDiscard)

        let replacementID = await model.createChallenge(makeTerms())
        XCTAssertNotNil(replacementID)
        XCTAssertEqual(contests.createCallCount, 1)
    }

    func testAccountSwitchCannotAttachAStalePendingChallenge() async throws {
        let firstOwnerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let secondOwnerID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let auth = SwitchingAuthClient(initialUserID: firstOwnerID)
        let pendingStore = BlockingPendingChallengeStore(
            blockedOwnerID: firstOwnerID,
            submission: PendingChallengeSubmission(
                ownerID: firstOwnerID,
                terms: makeTerms(),
                createdAt: Date().addingTimeInterval(-30),
                attemptCount: 1,
                lastAttemptAt: Date()
            )
        )
        let fixture = FixtureServicesFactory.make(
            arguments: ["GameTimeTests", "--fixture-mode"]
        )
        let model = AppModel(
            configuration: .fixture,
            services: AppServices(
                auth: auth,
                profiles: AnyActorProfileClient(),
                friendships: fixture.friendships,
                contests: fixture.contests,
                pendingChallenges: pendingStore,
                activitySync: fixture.activitySync
            )
        )

        let startTask = Task { await model.start() }
        await pendingStore.waitUntilBlockedLoadStarts()
        auth.switchUser(to: secondOwnerID)
        await pendingStore.releaseBlockedLoad()
        await startTask.value
        for _ in 0..<10 {
            guard model.userID != secondOwnerID || model.phase != .signedIn else {
                break
            }
            await Task.yield()
        }

        XCTAssertEqual(model.userID, secondOwnerID)
        XCTAssertEqual(model.phase, .signedIn)
        XCTAssertEqual(model.profile?.id, secondOwnerID)
        XCTAssertNil(model.pendingChallenge)
        XCTAssertFalse(model.hasPendingChallengeRecoveryIssue)
    }

    func testDiscardRefusesAStaleLoadedActor() async throws {
        let firstOwnerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let secondOwnerID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let auth = SwitchingAuthClient(initialUserID: firstOwnerID)
        let pendingStore = TestPendingChallengeStore(
            submission: PendingChallengeSubmission(
                ownerID: firstOwnerID,
                terms: makeTerms(),
                createdAt: Date().addingTimeInterval(-30),
                attemptCount: 1,
                lastAttemptAt: Date()
            )
        )
        let fixture = FixtureServicesFactory.make(
            arguments: ["GameTimeTests", "--fixture-mode"]
        )
        let model = AppModel(
            configuration: .fixture,
            services: AppServices(
                auth: auth,
                profiles: AnyActorProfileClient(),
                friendships: fixture.friendships,
                contests: fixture.contests,
                pendingChallenges: pendingStore,
                activitySync: fixture.activitySync
            )
        )
        await model.start()
        XCTAssertEqual(model.pendingChallenge?.ownerID, firstOwnerID)

        auth.setCurrentUserWithoutPublishing(secondOwnerID)
        let discarded = await model.discardPendingChallenge()

        XCTAssertFalse(discarded)
        XCTAssertTrue(
            model.presentedError?.localizedCaseInsensitiveContains(
                "not discarded"
            ) == true
        )
        let preserved = try await pendingStore.load(for: firstOwnerID)
        XCTAssertNotNil(preserved)
    }

    func testSignOutDetachesProtectedRecordAndSameActorRestoresIt()
        async throws
    {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let store = FilePendingChallengeStore(directoryURL: directory)
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let otherOwnerID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let terms = makeTerms()
        let now = Date()
        try await store.save(
            PendingChallengeSubmission(
                ownerID: ownerID,
                terms: terms,
                createdAt: now.addingTimeInterval(-30),
                attemptCount: 1,
                lastAttemptAt: now
            )
        )
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"],
                pendingChallengeStore: store
            )
        )
        await model.start()
        XCTAssertEqual(model.pendingChallenge?.terms, terms)

        await model.signOut()

        XCTAssertNil(model.pendingChallenge)
        let savedOwnerSubmission = try await store.load(for: ownerID)
        let otherOwnerSubmission = try await store.load(for: otherOwnerID)
        XCTAssertNotNil(savedOwnerSubmission)
        XCTAssertNil(otherOwnerSubmission)

        await model.signInWithApple(
            AppleIdentity(
                idToken: "fixture-token",
                rawNonce: "fixture-nonce",
                firstSignInDisplayName: nil
            )
        )
        XCTAssertEqual(model.phase, .signedIn)
        XCTAssertEqual(model.pendingChallenge?.terms, terms)
    }

    private func assertClientBoundary(_ services: AppServices) {
        let clients: [AnyObject] = [
            services.auth,
            services.profiles,
            services.friendships,
            services.contests,
            services.pendingChallenges,
            services.pushNotifications,
        ]
        XCTAssertEqual(clients.count, 6)
    }

    private func makeTerms(requestID: UUID = UUID()) -> ChallengeTerms {
        let startsAt = Date().addingTimeInterval(86_400)
        return ChallengeTerms(
            requestID: requestID,
            title: "Blocked duplicate proof",
            inviteeIDs: [
                UUID(
                    uuidString: "44444444-4444-4444-4444-444444444444"
                )!,
                UUID(
                    uuidString: "55555555-5555-5555-5555-555555555555"
                )!,
            ],
            metric: .steps,
            cadence: .cumulative,
            targetValue: 10_000,
            stakeAmountCents: 500,
            startsAt: startsAt,
            endsAt: startsAt.addingTimeInterval(2 * 86_400),
            timezone: "America/Chicago",
            charityID: UUID(
                uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
            )!,
            tieBreak: .integrityScore
        )
    }
}

private actor TestPendingChallengeStore: PendingChallengeStore {
    private var submission: PendingChallengeSubmission?
    private let loadError: PendingChallengeStoreError?

    init(
        submission: PendingChallengeSubmission?,
        loadError: PendingChallengeStoreError? = nil
    ) {
        self.submission = submission
        self.loadError = loadError
    }

    func load(for ownerID: UUID) throws -> PendingChallengeSubmission? {
        if let loadError {
            throw loadError
        }
        guard let submission else { return nil }
        try submission.validate(for: ownerID)
        return submission
    }

    func save(_ submission: PendingChallengeSubmission) throws {
        try submission.validate(for: submission.ownerID)
        self.submission = submission
    }

    func remove(for ownerID: UUID) {
        guard submission?.ownerID == ownerID else { return }
        submission = nil
    }
}

private actor BlockingPendingChallengeStore: PendingChallengeStore {
    private let blockedOwnerID: UUID
    private var submission: PendingChallengeSubmission?
    private var blockedLoadStarted = false
    private var blockedLoadReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        blockedOwnerID: UUID,
        submission: PendingChallengeSubmission?
    ) {
        self.blockedOwnerID = blockedOwnerID
        self.submission = submission
    }

    func load(for ownerID: UUID) async throws -> PendingChallengeSubmission? {
        if ownerID == blockedOwnerID {
            if !blockedLoadStarted {
                blockedLoadStarted = true
                let waiters = startWaiters
                startWaiters.removeAll()
                for waiter in waiters {
                    waiter.resume()
                }
            }
            if !blockedLoadReleased {
                await withCheckedContinuation { continuation in
                    releaseWaiters.append(continuation)
                }
            }
        }

        guard submission?.ownerID == ownerID else { return nil }
        try submission?.validate(for: ownerID)
        return submission
    }

    func save(_ submission: PendingChallengeSubmission) throws {
        try submission.validate(for: submission.ownerID)
        self.submission = submission
    }

    func remove(for ownerID: UUID) {
        guard submission?.ownerID == ownerID else { return }
        submission = nil
    }

    func waitUntilBlockedLoadStarts() async {
        guard !blockedLoadStarted else { return }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func releaseBlockedLoad() {
        blockedLoadReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}

@MainActor
private final class SwitchingAuthClient: AuthClient {
    private var userID: UUID?
    private var continuations: [UUID: AsyncStream<AuthSnapshot>.Continuation] = [:]

    init(initialUserID: UUID?) {
        userID = initialUserID
    }

    func currentUserID() async -> UUID? {
        userID
    }

    func authStateChanges() async -> AsyncStream<AuthSnapshot> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.continuations[id] = nil
                }
            }
        }
    }

    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID {
        _ = identity
        guard let userID else {
            throw AppMutationError.permissionDenied
        }
        return userID
    }

    func signOut() async throws {
        switchUser(to: nil)
    }

    func switchUser(to userID: UUID?) {
        self.userID = userID
        let snapshot = AuthSnapshot(userID: userID)
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    func setCurrentUserWithoutPublishing(_ userID: UUID?) {
        self.userID = userID
    }
}

@MainActor
private final class AnyActorProfileClient: ProfileClient {
    func currentProfile(userID: UUID) async throws -> UserProfile? {
        UserProfile(
            id: userID,
            handle: "actor_\(userID.uuidString.prefix(8).lowercased())",
            displayName: "Test Actor",
            timezone: "America/Chicago"
        )
    }

    func createProfile(
        userID: UUID,
        handle: String,
        displayName: String,
        timezone: String
    ) async throws -> UserProfile {
        UserProfile(
            id: userID,
            handle: handle,
            displayName: displayName,
            timezone: timezone
        )
    }
}

@MainActor
private final class RecordingContestsClient: ContestsClient {
    enum Behavior: Equatable {
        case succeed
        case cancel
    }

    private(set) var createCallCount = 0
    private(set) var submittedTerms: [ChallengeTerms] = []
    private let behavior: Behavior

    init(behavior: Behavior = .succeed) {
        self.behavior = behavior
    }

    func listContests(userID: UUID) async throws -> [ContestCard] {
        _ = userID
        return []
    }

    func listCharities() async throws -> [Charity] {
        []
    }

    func standings(contestID: UUID) async throws -> ChallengeStandings? {
        _ = contestID
        return nil
    }

    func sendComebackReaction(
        contestID: UUID,
        snapshotID: UUID
    ) async throws {
        _ = (contestID, snapshotID)
    }

    func createChallenge(
        _ terms: ChallengeTerms,
        expectedUserID: UUID
    ) async throws -> UUID {
        _ = expectedUserID
        createCallCount += 1
        submittedTerms.append(terms)
        if behavior == .cancel {
            throw CancellationError()
        }
        return UUID()
    }

    func acceptInvitation(
        contestID: UUID,
        userID: UUID,
        timezone: String,
        charityID: UUID
    ) async throws {
        _ = (contestID, userID, timezone, charityID)
    }

    func declineInvitation(contestID: UUID, userID: UUID) async throws {
        _ = (contestID, userID)
    }
}
