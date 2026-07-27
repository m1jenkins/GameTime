import XCTest

@MainActor
final class GameTimeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSignedOutAndOnboardingRoots() {
        let signedOut = launch("--fixture-signed-out")
        XCTAssertTrue(
            signedOut.buttons["Sign in with Apple"]
                .waitForExistence(timeout: 4)
        )
        signedOut.terminate()

        let onboarding = launch("--fixture-onboarding")
        XCTAssertTrue(
            onboarding.navigationBars["Set your profile"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(onboarding.textFields["Display name"].exists)
        XCTAssertTrue(onboarding.textFields["Handle"].exists)
    }

    func testAllFourTabsAndActionFirstToday() {
        let app = launch()
        XCTAssertTrue(
            app.navigationBars["Today"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Friend requests"].exists)
        XCTAssertTrue(app.staticTexts["Challenge invitations"].exists)

        for tab in ["Challenges", "Friends", "You", "Today"] {
            let tabButton = app.tabBars.buttons[tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 3))
            tabButton.tap()
            let navigationBar = app.navigationBars[tab]
            if !navigationBar.waitForExistence(timeout: 3) {
                tabButton.tap()
            }
            XCTAssertTrue(navigationBar.waitForExistence(timeout: 3))
        }
    }

    func testFriendAcceptanceAndExactHandleSubmission() {
        let app = launch()
        let accept = app.buttons["Accept Jordan Lee"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.tap()

        app.tabBars.buttons["Friends"].tap()
        XCTAssertTrue(app.staticTexts["Jordan Lee"].waitForExistence(timeout: 4))

        let handle = app.textFields["friends.exact-handle"]
        handle.tap()
        handle.typeText("@marcusmoves")
        app.buttons["friends.find"].tap()
        XCTAssertTrue(
            app.staticTexts["Exact match"].waitForExistence(timeout: 4)
        )
    }

    func testDuelReviewSubmissionAndInvitationAcceptance() {
        let app = launch()
        app.tabBars.buttons["Challenges"].tap()
        app.buttons["challenge.create"].tap()

        let title = app.textFields["duel.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        title.tap()
        title.typeText("UI test duel")
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
        let reviewTerms = app.buttons["duel.review"]
        for _ in 0..<4 where !reviewTerms.exists {
            app.swipeUp()
        }
        XCTAssertTrue(reviewTerms.waitForExistence(timeout: 3))
        reviewTerms.tap()

        XCTAssertTrue(
            app.navigationBars["Review duel"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Immutable terms"].exists)
        let submitDuel = app.buttons["duel.submit"]
        for _ in 0..<5 where !submitDuel.exists {
            app.swipeUp()
        }
        XCTAssertTrue(submitDuel.waitForExistence(timeout: 3))
        submitDuel.tap()

        XCTAssertTrue(
            app.staticTexts["UI test duel"].waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["Today"].tap()
        let review = app.buttons[
            "Review and accept Three-day step duel"
        ]
        XCTAssertTrue(review.waitForExistence(timeout: 4))
        review.tap()
        XCTAssertTrue(
            app.navigationBars["Review invitation"]
                .waitForExistence(timeout: 4)
        )
        app.buttons["invitation.accept"].tap()
        XCTAssertTrue(
            app.navigationBars["Today"].waitForExistence(timeout: 5)
        )
    }

    func testSavedDuelCanBeResumedWithoutAutomaticRetry() {
        let app = launch("--fixture-pending-duel")
        let challengesTab = app.tabBars.buttons["Challenges"]
        XCTAssertTrue(challengesTab.waitForExistence(timeout: 5))
        challengesTab.tap()

        XCTAssertTrue(
            app.staticTexts["Explicit retry required"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Saved response retry"].exists)
        let resume = app.buttons["duel.pending.resume"]
        XCTAssertTrue(resume.exists)
        resume.tap()

        XCTAssertTrue(
            app.navigationBars["Review duel"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Saved response retry"].exists)
        let submit = app.buttons["duel.submit"]
        for _ in 0..<5 where !submit.exists {
            app.swipeUp()
        }
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["duel.request-id"].exists
        )
        let discard = app.buttons["duel.pending.discard-review"]
        XCTAssertTrue(discard.waitForExistence(timeout: 3))
        discard.tap()
        XCTAssertTrue(
            app.buttons["Discard local retry"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Discard the local retry record?"
            ].exists
        )
        app.buttons["Discard local retry"].tap()
        XCTAssertTrue(
            app.navigationBars["Create duel"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.textFields["duel.title"].exists)
    }

    func testLoadingEmptyAndOfflineStates() {
        let loading = launch("--fixture-loading")
        XCTAssertTrue(
            loading.staticTexts["Loading trusted state…"]
                .waitForExistence(timeout: 2)
        )
        loading.terminate()

        let empty = launch("--fixture-empty")
        XCTAssertTrue(
            empty.otherElements["state.empty"].waitForExistence(timeout: 5)
                || empty.staticTexts["You’re clear for today"].exists
        )
        empty.terminate()

        let offline = launch("--fixture-offline")
        XCTAssertTrue(
            offline.otherElements["state.offline"]
                .waitForExistence(timeout: 5)
                || offline.staticTexts["Couldn’t refresh"].exists
        )
    }

    func testDebugFixturesDynamicTypeLabelsAndReduceMotion() {
        let app = launch(
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-UIAccessibilityReduceMotionEnabled",
            "YES"
        )
        app.tabBars.buttons["You"].tap()

        XCTAssertTrue(
            app.buttons["debug.future-states"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["account.sign-out"].exists)
        app.buttons["debug.future-states"].tap()
        XCTAssertTrue(
            app.navigationBars["Future states"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Result frozen"].exists)
        XCTAssertTrue(app.staticTexts["Pledge awaiting settlement"].exists)
        XCTAssertTrue(app.staticTexts["Evidence under review"].exists)
    }

    private func launch(_ extraArguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode"] + extraArguments
        app.launch()
        return app
    }
}
