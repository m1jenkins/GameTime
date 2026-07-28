import XCTest

/// The Glass Arena screens draw their own headers and tab bar, so these tests
/// address elements by accessibility identifier rather than by navigation-bar
/// title, tab-bar membership, or visible copy.
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
            onboarding.textFields["Display name"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(onboarding.textFields["Handle"].exists)
        XCTAssertTrue(onboarding.buttons["onboarding.continue"].exists)
    }

    func testAllFourTabsAndActionFirstToday() {
        let app = launch()
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.today"]
                .waitForExistence(timeout: 5)
        )
        // Today leads with the live duel, then whatever is waiting on you.
        XCTAssertTrue(app.buttons["today.hero-duel"].exists)
        XCTAssertTrue(app.buttons["Add Jordan Lee"].exists)
        XCTAssertTrue(app.buttons["invite.accept"].exists)

        let tabs = [
            (tab: "tab.duels", screen: "screen.duels"),
            (tab: "tab.friends", screen: "screen.friends"),
            (tab: "tab.you", screen: "screen.you"),
            (tab: "tab.today", screen: "screen.today"),
        ]
        for entry in tabs {
            let tabButton = app.buttons[entry.tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 3))
            tabButton.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)[entry.screen]
                    .waitForExistence(timeout: 3),
                "Expected \(entry.screen) after tapping \(entry.tab)"
            )
        }
    }

    func testFriendAcceptanceAndExactHandleSubmission() {
        let app = launch()
        let accept = app.buttons["Add Jordan Lee"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5))
        accept.tap()

        app.buttons["tab.friends"].tap()
        XCTAssertTrue(app.staticTexts["Jordan Lee"].waitForExistence(timeout: 4))

        let handle = app.textFields["friends.exact-handle"]
        handle.tap()
        handle.typeText("marcusmoves")
        app.buttons["friends.find"].tap()
        XCTAssertTrue(
            app.staticTexts["EXACT MATCH"].waitForExistence(timeout: 4)
                || app.staticTexts["Marcus Green"].exists
        )
    }

    func testDuelReviewSubmissionAndInvitationAcceptance() {
        let app = launch()
        app.buttons["tab.duels"].tap()
        let create = app.buttons["challenge.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 4))
        create.tap()

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
            app.navigationBars["Last look"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["IMMUTABLE TERMS"].exists)
        let submitDuel = app.buttons["duel.submit"]
        for _ in 0..<5 where !submitDuel.exists {
            app.swipeUp()
        }
        XCTAssertTrue(submitDuel.waitForExistence(timeout: 3))
        submitDuel.tap()

        // A duel you created lands in Live, awaiting their reply.
        XCTAssertTrue(
            containsText(app, "UI test duel").waitForExistence(timeout: 5)
        )

        app.buttons["tab.today"].tap()
        let takeIt = app.buttons["invite.accept"]
        XCTAssertTrue(takeIt.waitForExistence(timeout: 4))
        takeIt.tap()
        XCTAssertTrue(
            app.navigationBars["Their terms"].waitForExistence(timeout: 4)
        )
        app.buttons["invitation.accept"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["screen.today"]
                .waitForExistence(timeout: 5)
        )
    }

    func testSavedDuelCanBeResumedWithoutAutomaticRetry() {
        let app = launch("--fixture-pending-duel")
        let duelsTab = app.buttons["tab.duels"]
        XCTAssertTrue(duelsTab.waitForExistence(timeout: 5))
        duelsTab.tap()

        XCTAssertTrue(
            app.staticTexts["Explicit retry required"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Saved response retry"].exists)
        let resume = app.buttons["duel.pending.resume"]
        XCTAssertTrue(resume.exists)
        resume.tap()

        XCTAssertTrue(
            app.navigationBars["Last look"].waitForExistence(timeout: 4)
        )
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
            app.staticTexts["Discard the local retry record?"].exists
        )
        app.buttons["Discard local retry"].tap()
        XCTAssertTrue(
            app.navigationBars["New duel"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.textFields["duel.title"].exists)
    }

    func testLoadingEmptyAndOfflineStates() {
        let loading = launch("--fixture-loading")
        XCTAssertTrue(
            loading.staticTexts["Getting the rope ready…"]
                .waitForExistence(timeout: 2)
        )
        loading.terminate()

        let empty = launch("--fixture-empty")
        XCTAssertTrue(
            empty.descendants(matching: .any)["state.empty"]
                .waitForExistence(timeout: 5)
                || empty.staticTexts["Nobody's challenged you."].exists
        )
        empty.terminate()

        let offline = launch("--fixture-offline")
        XCTAssertTrue(
            offline.descendants(matching: .any)["state.offline"]
                .waitForExistence(timeout: 5)
                || offline.staticTexts["Couldn't refresh"].exists
        )
    }

    func testDebugFixturesDynamicTypeLabelsAndReduceMotion() {
        let app = launch(
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-UIAccessibilityReduceMotionEnabled",
            "YES"
        )
        app.buttons["tab.you"].tap()

        let debugRow = app.buttons["debug.future-states"]
        for _ in 0..<4 where !debugRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(debugRow.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["account.sign-out"].exists)
        debugRow.tap()
        XCTAssertTrue(
            app.staticTexts["Post-duel states"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Result frozen"].exists)
        XCTAssertTrue(app.staticTexts["Pledge awaiting settlement"].exists)
        XCTAssertTrue(app.staticTexts["Evidence under review"].exists)
    }

    // MARK: Helpers

    /// Card titles can be folded into their enclosing button's label, so match
    /// on either.
    private func containsText(
        _ app: XCUIApplication,
        _ text: String
    ) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(
                NSPredicate(format: "label CONTAINS %@", text)
            )
            .firstMatch
    }

    private func launch(_ extraArguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode"] + extraArguments
        app.launch()
        return app
    }
}
