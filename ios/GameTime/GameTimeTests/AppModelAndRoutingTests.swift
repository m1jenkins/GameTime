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
                    "--fixture-pending-duel",
                ]
            )
        )
        await model.start()
        XCTAssertFalse(model.contests.isEmpty)
        XCTAssertNotNil(model.pendingDuel)
        model.presentedError = "Private prior-session error"

        await model.signOut()

        XCTAssertEqual(model.phase, .signedOut)
        XCTAssertNil(model.userID)
        XCTAssertNil(model.profile)
        XCTAssertTrue(model.friendshipCards.isEmpty)
        XCTAssertTrue(model.contests.isEmpty)
        XCTAssertTrue(model.charities.isEmpty)
        XCTAssertNil(model.exactHandleResult)
        XCTAssertNil(model.pendingDuel)
        XCTAssertFalse(model.hasPendingDuelRecoveryIssue)
        XCTAssertNil(model.presentedError)
    }

    func testRouterResetClearsEveryIndependentStackAndSheet() {
        let router = AppRouter()
        router.selectedTab = .you
        router.todayPath = [.contest(UUID())]
        router.duelsPath = [.contest(UUID())]
        router.friendsPath = [.profile(UUID())]
        router.youPath = [.trustAndPrivacy]
        router.duelsSegment = .done
        router.presentedSheet = .createDuel

        router.reset()

        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertTrue(router.todayPath.isEmpty)
        XCTAssertTrue(router.duelsPath.isEmpty)
        XCTAssertTrue(router.friendsPath.isEmpty)
        XCTAssertTrue(router.youPath.isEmpty)
        XCTAssertEqual(router.duelsSegment, .live)
        XCTAssertNil(router.presentedSheet)
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
        var draft = DuelDraft()
        draft.title = "Locked duel"
        draft.inviteeID = try XCTUnwrap(
            model.acceptedFriendships.first?.otherUserID
        )
        draft.charityID = try XCTUnwrap(model.charities.first?.id)
        let terms = try draft.validated()

        let createdID = await model.createDuel(terms)
        XCTAssertNil(createdID)
        XCTAssertEqual(model.contests.count, originalCount)
        XCTAssertNil(model.pendingDuel)

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

    func testLostResponsePersistsAndRelaunchRetriesTheSameDuel() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let pendingStore = FilePendingDuelStore(directoryURL: directory)
        let services = FixtureServicesFactory.make(
            arguments: [
                "GameTimeTests",
                "--fixture-mode",
                "--fixture-lost-duel-response",
            ],
            pendingDuelStore: pendingStore
        )
        let firstModel = AppModel(
            configuration: .fixture,
            services: services
        )
        await firstModel.start()

        var draft = DuelDraft()
        draft.title = "Persisted lost response"
        draft.inviteeID = try XCTUnwrap(
            firstModel.acceptedFriendships.first?.otherUserID
        )
        draft.charityID = try XCTUnwrap(firstModel.charities.first?.id)
        let terms = try draft.validated()

        let firstCreatedID = await firstModel.createDuel(terms)
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
        let restored = try XCTUnwrap(relaunchedModel.pendingDuel)
        XCTAssertEqual(restored.terms.requestID, terms.requestID)
        XCTAssertEqual(restored.terms, terms)

        let createdID = await relaunchedModel.createDuel(restored.terms)
        XCTAssertNotNil(createdID)
        XCTAssertNil(relaunchedModel.pendingDuel)
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
        let pendingStore = TestPendingDuelStore(
            submission: nil,
            loadError: .corruptData
        )
        let contests = RecordingContestsClient()
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"],
                pendingDuelStore: pendingStore,
                contestsClient: contests
            )
        )
        await model.start()

        XCTAssertTrue(model.hasPendingDuelRecoveryIssue)
        let createdID = await model.createDuel(makeTerms())
        XCTAssertNil(createdID)
        XCTAssertEqual(contests.createCallCount, 0)
    }

    func testDifferentRequestIsBlockedWhilePendingDuelExists() async {
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let pendingTerms = makeTerms()
        let pendingStore = TestPendingDuelStore(
            submission: PendingDuelSubmission(
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
                pendingDuelStore: pendingStore,
                contestsClient: contests
            )
        )
        await model.start()

        XCTAssertEqual(model.pendingDuel?.terms, pendingTerms)
        let createdID = await model.createDuel(makeTerms())
        XCTAssertNil(createdID)
        XCTAssertEqual(contests.createCallCount, 0)
    }

    func testCancellationRetainsPendingDuelWithoutAnErrorAlert() async throws {
        let pendingStore = TestPendingDuelStore(submission: nil)
        let contests = RecordingContestsClient(behavior: .cancel)
        let model = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTimeTests", "--fixture-mode"],
                pendingDuelStore: pendingStore,
                contestsClient: contests
            )
        )
        await model.start()
        let terms = makeTerms()

        let createdID = await model.createDuel(terms)

        XCTAssertNil(createdID)
        XCTAssertEqual(contests.createCallCount, 1)
        XCTAssertNil(model.presentedError)
        let restored = try await pendingStore.load(
            for: try XCTUnwrap(model.userID)
        )
        XCTAssertEqual(restored?.terms, terms)
        XCTAssertEqual(restored?.attemptCount, 1)
    }

    func testDiscardClearsSavedRetryAndUnlocksAReplacementDuel() async throws {
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let pendingStore = TestPendingDuelStore(
            submission: PendingDuelSubmission(
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
                pendingDuelStore: pendingStore,
                contestsClient: contests
            )
        )
        await model.start()

        XCTAssertNotNil(model.pendingDuel)
        let discarded = await model.discardPendingDuel()
        XCTAssertTrue(discarded)
        XCTAssertNil(model.pendingDuel)
        XCTAssertFalse(model.hasPendingDuelRecoveryIssue)
        let storedAfterDiscard = try await pendingStore.load(for: ownerID)
        XCTAssertNil(storedAfterDiscard)

        let replacementID = await model.createDuel(makeTerms())
        XCTAssertNotNil(replacementID)
        XCTAssertEqual(contests.createCallCount, 1)
    }

    func testAccountSwitchCannotAttachAStalePendingDuel() async throws {
        let firstOwnerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let secondOwnerID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let auth = SwitchingAuthClient(initialUserID: firstOwnerID)
        let pendingStore = BlockingPendingDuelStore(
            blockedOwnerID: firstOwnerID,
            submission: PendingDuelSubmission(
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
                pendingDuels: pendingStore
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
        XCTAssertNil(model.pendingDuel)
        XCTAssertFalse(model.hasPendingDuelRecoveryIssue)
    }

    func testDiscardRefusesAStaleLoadedActor() async throws {
        let firstOwnerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let secondOwnerID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let auth = SwitchingAuthClient(initialUserID: firstOwnerID)
        let pendingStore = TestPendingDuelStore(
            submission: PendingDuelSubmission(
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
                pendingDuels: pendingStore
            )
        )
        await model.start()
        XCTAssertEqual(model.pendingDuel?.ownerID, firstOwnerID)

        auth.setCurrentUserWithoutPublishing(secondOwnerID)
        let discarded = await model.discardPendingDuel()

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
        let store = FilePendingDuelStore(directoryURL: directory)
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let otherOwnerID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let terms = makeTerms()
        let now = Date()
        try await store.save(
            PendingDuelSubmission(
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
                pendingDuelStore: store
            )
        )
        await model.start()
        XCTAssertEqual(model.pendingDuel?.terms, terms)

        await model.signOut()

        XCTAssertNil(model.pendingDuel)
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
        XCTAssertEqual(model.pendingDuel?.terms, terms)
    }

    private func assertClientBoundary(_ services: AppServices) {
        let clients: [AnyObject] = [
            services.auth,
            services.profiles,
            services.friendships,
            services.contests,
            services.pendingDuels,
        ]
        XCTAssertEqual(clients.count, 5)
    }

    private func makeTerms(requestID: UUID = UUID()) -> DuelTerms {
        let startsAt = Date().addingTimeInterval(86_400)
        return DuelTerms(
            requestID: requestID,
            title: "Blocked duplicate proof",
            inviteeID: UUID(
                uuidString: "44444444-4444-4444-4444-444444444444"
            )!,
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

private actor TestPendingDuelStore: PendingDuelStore {
    private var submission: PendingDuelSubmission?
    private let loadError: PendingDuelStoreError?

    init(
        submission: PendingDuelSubmission?,
        loadError: PendingDuelStoreError? = nil
    ) {
        self.submission = submission
        self.loadError = loadError
    }

    func load(for ownerID: UUID) throws -> PendingDuelSubmission? {
        if let loadError {
            throw loadError
        }
        guard let submission else { return nil }
        try submission.validate(for: ownerID)
        return submission
    }

    func save(_ submission: PendingDuelSubmission) throws {
        try submission.validate(for: submission.ownerID)
        self.submission = submission
    }

    func remove(for ownerID: UUID) {
        guard submission?.ownerID == ownerID else { return }
        submission = nil
    }
}

private actor BlockingPendingDuelStore: PendingDuelStore {
    private let blockedOwnerID: UUID
    private var submission: PendingDuelSubmission?
    private var blockedLoadStarted = false
    private var blockedLoadReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        blockedOwnerID: UUID,
        submission: PendingDuelSubmission?
    ) {
        self.blockedOwnerID = blockedOwnerID
        self.submission = submission
    }

    func load(for ownerID: UUID) async throws -> PendingDuelSubmission? {
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

    func save(_ submission: PendingDuelSubmission) throws {
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

    func listStandings(userID: UUID) async throws -> [UUID: DuelStanding] {
        _ = userID
        return [:]
    }

    func createDuel(
        _ terms: DuelTerms,
        expectedUserID: UUID
    ) async throws -> UUID {
        _ = terms
        _ = expectedUserID
        createCallCount += 1
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
