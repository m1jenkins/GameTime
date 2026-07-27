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
                arguments: ["GameTimeTests", "--fixture-mode"]
            )
        )
        await model.start()
        XCTAssertFalse(model.contests.isEmpty)
        model.presentedError = "Private prior-session error"

        await model.signOut()

        XCTAssertEqual(model.phase, .signedOut)
        XCTAssertNil(model.userID)
        XCTAssertNil(model.profile)
        XCTAssertTrue(model.friendshipCards.isEmpty)
        XCTAssertTrue(model.contests.isEmpty)
        XCTAssertTrue(model.charities.isEmpty)
        XCTAssertNil(model.exactHandleResult)
        XCTAssertNil(model.presentedError)
    }

    func testRouterResetClearsEveryIndependentStackAndSheet() {
        let router = AppRouter()
        router.selectedTab = .you
        router.todayPath = [.contest(UUID())]
        router.challengesPath = [.contest(UUID())]
        router.friendsPath = [.profile(UUID())]
        router.youPath = [.trustAndPrivacy]
        router.presentedSheet = .createDuel

        router.reset()

        XCTAssertEqual(router.selectedTab, .today)
        XCTAssertTrue(router.todayPath.isEmpty)
        XCTAssertTrue(router.challengesPath.isEmpty)
        XCTAssertTrue(router.friendsPath.isEmpty)
        XCTAssertTrue(router.youPath.isEmpty)
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
        let live = LiveServicesFactory.make(
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

    private func assertClientBoundary(_ services: AppServices) {
        let clients: [AnyObject] = [
            services.auth,
            services.profiles,
            services.friendships,
            services.contests,
        ]
        XCTAssertEqual(clients.count, 4)
    }
}
