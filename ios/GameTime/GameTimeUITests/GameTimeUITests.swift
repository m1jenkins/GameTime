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

    func testInteractiveDemoAddsDavidForChallengeSelection() {
        let app = launch("--fixture-empty", "--demo-interactive")
        XCTAssertTrue(
            app.descendants(matching: .any)["demo.banner"]
                .waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["Friends"].tap()
        let handle = app.textFields["friends.exact-handle"]
        XCTAssertTrue(handle.waitForExistence(timeout: 4))
        handle.tap()
        handle.typeText("@david1")
        app.buttons["friends.find"].tap()

        let addDavid = app.buttons["Add David Chen"]
        XCTAssertTrue(addDavid.waitForExistence(timeout: 4))
        addDavid.tap()
        XCTAssertTrue(
            app.staticTexts["David Chen"].waitForExistence(timeout: 4)
        )

        app.tabBars.buttons["Challenges"].tap()
        app.buttons["challenge.create"].tap()
        XCTAssertTrue(
            app.switches[
                "challenge.invitee.66666666-6666-6666-6666-666666666666"
            ].waitForExistence(timeout: 4)
        )
    }

    func testChallengeReviewSubmissionAndInvitationAcceptance() {
        let app = launch()
        app.tabBars.buttons["Challenges"].tap()
        app.buttons["challenge.create"].tap()

        let title = app.textFields["challenge.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        title.tap()
        title.typeText("UI test challenge")
        if app.keyboards.buttons["Return"].exists {
            app.keyboards.buttons["Return"].tap()
        }
        for friendID in [
            "44444444-4444-4444-4444-444444444444",
            "55555555-5555-5555-5555-555555555555",
        ] {
            let invitee = app.switches["challenge.invitee.\(friendID)"]
            XCTAssertTrue(invitee.waitForExistence(timeout: 3))
            invitee.coordinate(
                withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)
            ).tap()
            XCTAssertEqual(invitee.value as? String, "1")
        }
        let reviewTerms = app.buttons["challenge.review"]
        for _ in 0..<4 where !reviewTerms.exists {
            app.swipeUp()
        }
        XCTAssertTrue(reviewTerms.waitForExistence(timeout: 3))
        reviewTerms.tap()

        XCTAssertTrue(
            app.navigationBars["Review challenge"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Immutable terms"].exists)
        XCTAssertTrue(app.staticTexts["Marcus Green"].exists)
        XCTAssertTrue(app.staticTexts["Priya Shah"].exists)
        let rosterSize = app.staticTexts["3 people"]
        for _ in 0..<5 where !rosterSize.exists {
            app.swipeUp()
        }
        XCTAssertTrue(rosterSize.waitForExistence(timeout: 3))
        let submitChallenge = app.buttons["challenge.submit"]
        for _ in 0..<5 where !submitChallenge.exists {
            app.swipeUp()
        }
        XCTAssertTrue(submitChallenge.waitForExistence(timeout: 3))
        submitChallenge.tap()

        XCTAssertTrue(
            app.staticTexts["UI test challenge"].waitForExistence(timeout: 5)
        )

        app.tabBars.buttons["Today"].tap()
        let review = app.buttons[
            "Review and accept Three-day step challenge"
        ]
        XCTAssertTrue(review.waitForExistence(timeout: 4))
        review.tap()
        XCTAssertTrue(
            app.navigationBars["Review invitation"]
                .waitForExistence(timeout: 4)
        )
        let acceptInvitation = app.buttons["invitation.accept"]
        for _ in 0..<5 where !acceptInvitation.exists {
            app.swipeUp()
        }
        XCTAssertTrue(acceptInvitation.waitForExistence(timeout: 3))
        acceptInvitation.tap()
        XCTAssertTrue(
            app.navigationBars["Today"].waitForExistence(timeout: 5)
        )
    }

    func testSavedChallengeCanBeResumedWithoutAutomaticRetry() {
        let app = launch("--fixture-pending-challenge")
        let challengesTab = app.tabBars.buttons["Challenges"]
        XCTAssertTrue(challengesTab.waitForExistence(timeout: 5))
        challengesTab.tap()

        XCTAssertTrue(
            app.staticTexts["Explicit retry required"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Saved response retry"].exists)
        XCTAssertTrue(app.staticTexts["2 friends invited"].exists)
        let resume = app.buttons["challenge.pending.resume"]
        XCTAssertTrue(resume.exists)
        resume.tap()

        XCTAssertTrue(
            app.navigationBars["Review challenge"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Saved response retry"].exists)
        let submit = app.buttons["challenge.submit"]
        for _ in 0..<5 where !submit.exists {
            app.swipeUp()
        }
        XCTAssertTrue(submit.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["challenge.request-id"].exists
        )
        let discard = app.buttons["challenge.pending.discard-review"]
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
            app.navigationBars["Create challenge"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.textFields["challenge.title"].exists)
    }

    func testStagingActivityRequiresExplicitEnableAndSyncActions() {
        let app = launch("--fixture-activity")
        let challenges = app.tabBars.buttons["Challenges"]
        XCTAssertTrue(challenges.waitForExistence(timeout: 5))
        challenges.tap()

        let contest = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Weekend steps")
        ).firstMatch
        XCTAssertTrue(contest.waitForExistence(timeout: 4))
        contest.tap()
        XCTAssertTrue(
            app.navigationBars["Challenge"].waitForExistence(timeout: 4)
        )

        let enable = app.buttons["activity.enable"]
        for _ in 0..<5 where !enable.exists {
            app.swipeUp()
        }
        XCTAssertTrue(enable.waitForExistence(timeout: 3))
        enable.tap()
        let permissionMessage = app.staticTexts[
            "Permission request completed. Read access may still be limited."
        ]
        for _ in 0..<3 where !permissionMessage.exists {
            app.swipeUp()
        }
        XCTAssertTrue(permissionMessage.waitForExistence(timeout: 3))
        let sync = app.buttons["activity.sync"]
        for _ in 0..<3 where !sync.exists {
            app.swipeUp()
        }
        XCTAssertTrue(sync.waitForExistence(timeout: 3))
        sync.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["activity.status"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(
            app.staticTexts[
                "No completed device-recorded step hours were found. Access may be limited or off."
            ].exists
        )
    }

    func testProvisionalAndFinalStandingsDisclosure() {
        let provisional = launch()
        openWeekendDistance(in: provisional)

        let provisionalPhase = provisional.descendants(matching: .any)[
            "standings.phase"
        ]
        for _ in 0..<5 where !provisionalPhase.exists {
            provisional.swipeUp()
        }
        XCTAssertTrue(provisionalPhase.waitForExistence(timeout: 4))
        XCTAssertTrue(provisional.staticTexts["Provisional"].exists)
        XCTAssertTrue(
            provisional.staticTexts[
                "Live ordering only — not a predicted winner."
            ].exists
        )
        let reaction = provisional.buttons["standings.reaction.comeback"]
        for _ in 0..<3 where !reaction.exists {
            provisional.swipeUp()
        }
        XCTAssertTrue(reaction.waitForExistence(timeout: 3))
        reaction.tap()
        XCTAssertTrue(
            provisional.staticTexts["Reaction sent 😤"]
                .waitForExistence(timeout: 3)
        )
        let privacy = provisional.staticTexts[
            "Integrity detail stays private until final."
        ]
        for _ in 0..<3 where !privacy.exists {
            provisional.swipeUp()
        }
        XCTAssertTrue(privacy.waitForExistence(timeout: 3))
        provisional.terminate()

        let final = launch("--fixture-final-standings")
        openWeekendDistance(in: final)

        let finalPhase = final.descendants(matching: .any)["standings.phase"]
        for _ in 0..<5 where !finalPhase.exists {
            final.swipeUp()
        }
        XCTAssertTrue(finalPhase.waitForExistence(timeout: 4))
        XCTAssertTrue(final.staticTexts["Final"].exists)
        let winner = final.staticTexts["Winner: Marcus Green"]
        for _ in 0..<3 where !winner.exists {
            final.swipeUp()
        }
        XCTAssertTrue(winner.waitForExistence(timeout: 3))

        let obligation = final.staticTexts[
            "Pledge $10.00 to Fixture Community Fund"
        ]
        for _ in 0..<5 where !obligation.exists {
            final.swipeUp()
        }
        XCTAssertTrue(obligation.waitForExistence(timeout: 4))
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

    private func openWeekendDistance(in app: XCUIApplication) {
        let challenges = app.tabBars.buttons["Challenges"]
        XCTAssertTrue(challenges.waitForExistence(timeout: 5))
        challenges.tap()

        let contest = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Weekend distance")
        ).firstMatch
        XCTAssertTrue(contest.waitForExistence(timeout: 4))
        contest.tap()
        XCTAssertTrue(
            app.navigationBars["Challenge"].waitForExistence(timeout: 4)
        )
    }
}
