import XCTest

@testable import GameTime

@MainActor
final class AppModelAndRoutingTests: XCTestCase {
    func testDemoStartNowActivatesImmediatelyAndCountsFromLocalMidnight()
        async throws
    {
        let services = FixtureServicesFactory.make(
            arguments: ["GameTimeTests", "--fixture-empty"]
        )
        let currentUserID = await services.auth.currentUserID()
        let ownerID = try XCTUnwrap(currentUserID)
        let requestedStart = PersonalChallengeStart.currentMinute(now: Date())
        let request = PersonalChallengeCreationRequest(
            requestID: UUID(),
            cadence: .daily,
            targetSteps: 10_000,
            commitmentAmountMinor: 1_000,
            timezone: "America/Chicago",
            startsAt: requestedStart
        )

        let challengeID = try await services.personalAccountability.create(
            request,
            expectedUserID: ownerID
        )
        let createdChallenge = try await services.personalAccountability
            .challenge(id: challengeID)
        let challenge = try XCTUnwrap(createdChallenge)
        let calendar = PersonalChallengeStart.calendar(request.timezone)

        XCTAssertEqual(challenge.status, .active)
        XCTAssertEqual(
            challenge.terms.startsAt,
            calendar.startOfDay(for: requestedStart)
        )

        let observedAt = Date()
        let plan = try PersonalHealthSnapshotPlanner.plan(
            terms: challenge.terms,
            observedAt: observedAt
        )
        XCTAssertEqual(
            plan.days.first?.interval?.start,
            challenge.terms.startsAt
        )
        XCTAssertEqual(plan.days.first?.interval?.end, observedAt)
    }

    func testLegacySummaryDecodesBoundedRosterAndCallerTimezone() throws {
        let json = Data(
            #"{"contest_id":"11111111-1111-1111-1111-111111111111","title":"Legacy steps","created_by":"22222222-2222-2222-2222-222222222222","metric":"steps","cadence":"daily","target_value":10000,"stake_amount_cents":1000,"tie_break":"integrity_score","starts_at":"2026-08-03T05:00:00Z","ends_at":"2026-08-10T05:00:00Z","contest_status":"finalized","max_participants":3,"caller_status":"accepted","caller_timezone":"America/Chicago","accepted_count":2,"invited_count":1,"declined_count":0,"withdrawn_count":0,"lapsed_count":0,"author_profile":{"id":"22222222-2222-2222-2222-222222222222","handle":"author","display_name":"Author","is_deleted":false},"accepted_profiles":[{"id":"22222222-2222-2222-2222-222222222222","handle":"author","display_name":"Author","is_deleted":false},{"id":"33333333-3333-3333-3333-333333333333","handle":"member","display_name":"Member","is_deleted":false}]}"#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let row = try decoder.decode(ChallengeSummaryRow.self, from: json)
        let summary = row.summary(timeZoneChanges: [])

        XCTAssertEqual(summary.acceptedCount, 2)
        XCTAssertEqual(summary.invitedCount, 1)
        XCTAssertEqual(summary.acceptedParticipants.count, 2)
        XCTAssertEqual(summary.contest.participantTimeZone, "America/Chicago")
        XCTAssertEqual(summary.contest.resolvedParticipants.count, 2)
        XCTAssertTrue(
            summary.contest.resolvedParticipants.allSatisfy {
                $0.status == .accepted
            }
        )
    }

    func testPersonalV1LaunchDoesNotLoadDormantSocialInventories() async {
        let friendships = RecordingFriendshipsClient()
        let contests = RecordingContestsClient()
        let services = FixtureServicesFactory.make(
            arguments: ["GameTimeTests", "--fixture-mode"],
            friendshipsClient: friendships,
            contestsClient: contests
        )
        let model = AppModel(
            configuration: .personalFixture,
            services: services
        )

        await model.start()

        XCTAssertEqual(model.phase, .signedIn)
        XCTAssertNotNil(model.profile)
        XCTAssertEqual(friendships.listCallCount, 0)
        XCTAssertEqual(contests.listChallengeSummariesCallCount, 0)
        XCTAssertEqual(contests.listCharitiesCallCount, 0)
        XCTAssertTrue(model.friendshipCards.isEmpty)
        XCTAssertTrue(model.contests.isEmpty)
        XCTAssertTrue(model.charities.isEmpty)
    }

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

    func testRouterOpensPersonalChallengeInChallengesTab() {
        let challengeID = UUID()
        let router = AppRouter()
        router.presentedSheet = .createChallenge
        router.todayPath = [.contest(UUID())]

        router.openPersonalChallenge(challengeID)

        XCTAssertEqual(router.selectedTab, .challenges)
        XCTAssertEqual(
            router.challengesPath,
            [.personalChallenge(challengeID)]
        )
        XCTAssertNil(router.presentedSheet)
    }

    func testSocialPushRegistrationIsDormantInPersonalV1() {
        XCTAssertNil(
            PushNotificationCoordinator.pushEnvironment(for: .debug)
        )
        XCTAssertNil(
            PushNotificationCoordinator.pushEnvironment(for: .staging)
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

    func testPaymentFactoryUsesSandboxClientForExplicitReleaseAndStaging()
        throws
    {
        let debug = try AppConfiguration.validated(
            environmentValue: "Debug",
            urlValue: "http://127.0.0.1:54321",
            keyValue: "sb_publishable_debug_payment_boundary",
            mutationValue: "YES"
        )
        let release = try AppConfiguration.validated(
            environmentValue: "Release",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_release_payment_boundary",
            mutationValue: "YES",
            settlementModeValue: "stripe_sandbox",
            stripeReturnURLValue: "gametime-beta://stripe-redirect"
        )
        let staging = try AppConfiguration.validated(
            environmentValue: "Staging",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_staging_payment_boundary",
            mutationValue: "YES",
            settlementModeValue: "stripe_sandbox",
            stripeReturnURLValue: "gametime-staging://stripe-redirect"
        )

        let debugServices = try LiveServicesFactory.make(
            configuration: debug
        )
        let releaseServices = try LiveServicesFactory.make(
            configuration: release
        )
        let stagingServices = try LiveServicesFactory.make(
            configuration: staging
        )

        XCTAssertEqual(debug.personalSettlementMode, .testOnly)
        XCTAssertTrue(
            debugServices.personalPayments
                is DisabledPersonalPaymentClient
        )
        XCTAssertEqual(release.personalSettlementMode, .stripeSandbox)
        XCTAssertTrue(
            releaseServices.personalPayments
                is SupabasePersonalPaymentClient
        )
        XCTAssertEqual(staging.personalSettlementMode, .stripeSandbox)
        XCTAssertTrue(
            stagingServices.personalPayments
                is SupabasePersonalPaymentClient
        )
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

    func testReleaseKeepsEveryDormantContestMutationInert() async throws {
        let configuration = try AppConfiguration.validated(
            environmentValue: "Release",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_release_test",
            mutationValue: "YES"
        )
        let contests = RecordingContestsClient()
        let model = AppModel(
            configuration: configuration,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"],
                contestsClient: contests
            )
        )
        await model.start()

        XCTAssertFalse(configuration.legacySocialRuntimeEnabled)
        XCTAssertFalse(configuration.contestMutationsEnabled)
        let now = Date()
        let terms = ChallengeTerms(
            requestID: UUID(),
            title: "Locked challenge",
            inviteeIDs: [UUID()],
            metric: .steps,
            cadence: .cumulative,
            targetValue: 10_000,
            stakeAmountCents: 1_000,
            startsAt: now.addingTimeInterval(86_400),
            endsAt: now.addingTimeInterval(8 * 86_400),
            timezone: "America/Chicago",
            charityID: UUID(),
            tieBreak: .integrityScore
        )

        let createdID = await model.createChallenge(terms)
        XCTAssertNil(createdID)
        await model.acceptInvitation(
            contestID: UUID(),
            charityID: UUID()
        )
        await model.declineInvitation(contestID: UUID())

        XCTAssertEqual(contests.createCallCount, 0)
        XCTAssertEqual(contests.acceptInvitationCallCount, 0)
        XCTAssertEqual(contests.declineInvitationCallCount, 0)
        XCTAssertTrue(model.contests.isEmpty)
        XCTAssertNil(model.pendingChallenge)
        XCTAssertNil(model.presentedError)
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
                "wasn’t deleted"
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
private final class RecordingFriendshipsClient: FriendshipsClient {
    private(set) var listCallCount = 0

    func listCards() async throws -> [FriendshipCard] {
        listCallCount += 1
        return []
    }

    func findExactHandle(_ handle: String) async throws -> ProfileCard? {
        _ = handle
        return nil
    }

    func requestFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        _ = (callerID, otherUserID)
    }

    func acceptFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        _ = (callerID, otherUserID)
    }

    func removeFriendship(
        callerID: UUID,
        otherUserID: UUID
    ) async throws {
        _ = (callerID, otherUserID)
    }
}

@MainActor
private final class RecordingContestsClient: ContestsClient {
    enum Behavior: Equatable {
        case succeed
        case cancel
    }

    private(set) var createCallCount = 0
    private(set) var acceptInvitationCallCount = 0
    private(set) var declineInvitationCallCount = 0
    private(set) var listChallengeSummariesCallCount = 0
    private(set) var listCharitiesCallCount = 0
    private(set) var submittedTerms: [ChallengeTerms] = []
    private let behavior: Behavior

    init(behavior: Behavior = .succeed) {
        self.behavior = behavior
    }

    func listChallengeSummaries(userID: UUID) async throws
        -> [ChallengeRosterSummary]
    {
        _ = userID
        listChallengeSummariesCallCount += 1
        return []
    }

    func listCharities() async throws -> [Charity] {
        listCharitiesCallCount += 1
        return []
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
        acceptInvitationCallCount += 1
    }

    func declineInvitation(contestID: UUID, userID: UUID) async throws {
        _ = (contestID, userID)
        declineInvitationCallCount += 1
    }
}
