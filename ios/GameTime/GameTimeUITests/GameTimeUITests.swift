import XCTest

@MainActor
final class GameTimeUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    func testSignedOutAndPublicHandleOnboardingRoots() {
        let signedOut = launch("--fixture-signed-out")
        XCTAssertTrue(
            signedOut.buttons["Sign in with Apple"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            signedOut.staticTexts[
                "Test commitment — no money will be charged."
            ].exists
        )
        XCTAssertTrue(signedOut.staticTexts["GameTime"].exists)
        XCTAssertFalse(signedOut.staticTexts["Compete fairly."].exists)
        assertNoForbiddenLanguage(in: signedOut)
        signedOut.terminate()

        let onboarding = launch("--fixture-onboarding")
        XCTAssertTrue(
            onboarding.navigationBars["Set your profile"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(onboarding.textFields["Your name"].exists)
        XCTAssertTrue(onboarding.textFields["Username"].exists)
        assertNoForbiddenLanguage(in: onboarding)
    }

    func testOnlyThreePersonalTabsAreReachable() {
        let app = launch()
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.tabBars.buttons.count, 3)
        XCTAssertFalse(app.tabBars.buttons["Friends"].exists)

        for tab in ["Challenges", "You", "Today"] {
            let tabButton = app.tabBars.buttons[tab]
            XCTAssertTrue(tabButton.waitForExistence(timeout: 3))
            tabButton.tap()
            XCTAssertTrue(
                app.navigationBars[tab].waitForExistence(timeout: 3)
            )
            assertExactDisclosure(in: app)
            assertNoForbiddenLanguage(in: app)
        }
    }

    func testStripeSandboxFlowUsesFixturePaymentAndExactConsent() {
        let app = launch(
            "--fixture-empty",
            "--fixture-stripe-sandbox"
        )
        XCTAssertTrue(
            app.staticTexts[
                "Payment test mode — no real money moves."
            ].waitForExistence(timeout: 5)
        )
        XCTAssertFalse(
            app.staticTexts[
                "Test commitment — no money will be charged."
            ].exists
        )

        app.buttons["personal.create"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["How it counts"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["Step 1 of 6"].exists
        )
        assertHiddenBetaCreationSteps(in: app)
        for title in ["Your goal", "Your amount", "Apple Health"] {
            app.buttons["personal.continue"].waitAndTap()
            XCTAssertTrue(
                app.navigationBars[title].waitForExistence(timeout: 4)
            )
        }
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 3))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        app.buttons["personal.continue"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Test payment"]
                .waitForExistence(timeout: 4)
        )

        let consent =
            "By starting, you agree that GameTime may create one $10.00 test charge only if this challenge is confirmed missed after the review window. Missing or unclear step data never counts as a miss."
        XCTAssertTrue(
            exactStaticText(consent, in: app)
                .waitForExistence(timeout: 3)
        )
        let startNow = app.switches["personal.start.now"]
        XCTAssertTrue(startNow.waitForExistence(timeout: 3))
        startNow.tap()
        let setup = app.buttons["personal.payment.setup"]
        XCTAssertTrue(setup.exists)
        XCTAssertFalse(setup.isEnabled)
        app.switches["personal.payment.consent"].waitAndTap()
        XCTAssertTrue(setup.isEnabled)
        setup.tap()

        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.staticTexts["Test method saved — ready for review"].exists
        )
        XCTAssertTrue(
            app.staticTexts["Now — today counts from midnight"].exists
        )
        app.buttons["personal.submit"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Payment test mode — no real money moves."
            ].exists
        )
        XCTAssertTrue(app.staticTexts["In progress"].exists)
        XCTAssertTrue(app.buttons["personal.challenge.sync-now"].exists)
    }

    func testStripeMissReviewUsesFixedReasonAndShowsSettlementPausedState() {
        let app = launch(
            "--fixture-stripe-sandbox",
            "--fixture-stripe-review",
            "--fixture-open-review-challenge"
        )
        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        assertCumulativeProgress(in: app)

        let request = app.buttons["personal.review.request"]
        for _ in 0..<10 where !request.isHittable { app.swipeUp() }
        XCTAssertTrue(request.waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.buttons[
                "personal.review.reason.user_disputes_step_data"
            ].exists
        )
        let resultReason = app.buttons[
            "personal.review.reason.user_disputes_result"
        ]
        XCTAssertTrue(resultReason.exists)
        resultReason.tap()
        XCTAssertEqual(resultReason.value as? String, "Selected")

        request.tap()

        XCTAssertTrue(
            app.staticTexts["Review requested"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.staticTexts[
                "Settlement stays paused while this result is reviewed."
            ].exists
        )
    }

    func testTodayShowsAutomaticPersonalProgressTimeline() {
        let app = launch("--fixture-activity")

        XCTAssertTrue(
            app.staticTexts["Your week"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["10,000 steps a day"].exists)
        assertDailyProgress(in: app)
        XCTAssertFalse(app.staticTexts["17,832 steps"].exists)
        XCTAssertTrue(app.staticTexts["Day by day"].exists)
        XCTAssertTrue(app.staticTexts["10,482"].exists)
        XCTAssertTrue(app.staticTexts["7,350"].exists)
        assertExactDisclosure(in: app)
        XCTAssertFalse(app.staticTexts["Friend requests"].exists)
        XCTAssertFalse(app.staticTexts["Challenge invitations"].exists)
        assertNoForbiddenLanguage(in: app)

        assertNoLegacyPersonalHealthSurfaces(in: app)

        app.tabBars.buttons["Challenges"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Challenges"].waitForExistence(timeout: 4)
        )
        assertDailyProgress(in: app)
        assertNoLegacyPersonalHealthSurfaces(in: app)

        let activeCard = app.buttons[
            "personal.challenge.18181818-1818-1818-1818-181818181818"
        ]
        XCTAssertTrue(activeCard.waitForExistence(timeout: 4))
        activeCard.tap()
        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 4)
        )
        assertDailyProgress(in: app)
        XCTAssertTrue(app.staticTexts["Your pace"].exists)
        let syncNow = app.buttons["personal.challenge.sync-now"]
        XCTAssertTrue(syncNow.waitForExistence(timeout: 4))
        syncNow.tap()
        XCTAssertTrue(
            app.staticTexts["7,350 steps today"]
                .waitForExistence(timeout: 4)
        )
        let paceChart = app.descendants(matching: .any)["personal.pace.chart"]
        for _ in 0..<8 where !paceChart.exists { app.swipeUp() }
        XCTAssertTrue(paceChart.waitForExistence(timeout: 4))
        let weekTotal = app.descendants(matching: .any)[
            "personal.pace.week-total"
        ]
        XCTAssertTrue(weekTotal.waitForExistence(timeout: 4))
        XCTAssertTrue(
            weekTotal.label.localizedCaseInsensitiveContains("Week total")
        )
        XCTAssertTrue(weekTotal.label.contains("17,832"))
        assertNoLegacyPersonalHealthSurfaces(in: app)
    }

    func testPersonalDetailContainsLockedTermsAndNoCompetitiveLanguage() {
        let app = launch("--fixture-open-active-challenge")
        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Your pace"].exists)
        XCTAssertFalse(app.staticTexts["Steps received"].exists)
        assertExactDisclosure(in: app)

        // The terms still exist; they live behind "Challenge details" now.
        let details = app.buttons["personal.details"]
        for _ in 0..<8 where !details.isHittable { app.swipeUp() }
        XCTAssertTrue(details.waitForExistence(timeout: 3))
        XCTAssertEqual(details.value as? String, "Hidden")
        details.tap()
        XCTAssertEqual(details.value as? String, "Showing")
        XCTAssertTrue(
            containing("Updates through", in: app)
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(containing("How it counts", in: app).exists)

        let cancel = app.buttons["personal.cancel"]
        for _ in 0..<8 where !cancel.exists { app.swipeUp() }
        XCTAssertTrue(
            cancel.waitForExistence(timeout: 3),
            "Internal test-only active challenges should expose cleanup cancellation."
        )

        assertNoLegacyPersonalHealthSurfaces(in: app)
        XCTAssertFalse(app.staticTexts["Standings"].exists)
        XCTAssertFalse(app.staticTexts["Winner"].exists)
        XCTAssertFalse(app.staticTexts["Charity"].exists)
        assertNoForbiddenLanguage(in: app)
    }

    func testCumulativeCreationOmitsFixedMetricAndStartSteps() {
        let app = launch(
            "--fixture-empty",
            "--fixture-activity"
        )
        XCTAssertTrue(
            app.buttons["personal.create"].waitForExistence(timeout: 5)
        )
        app.buttons["personal.create"].tap()

        XCTAssertTrue(
            app.navigationBars["How it counts"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["Step 1 of 5"].exists
        )
        XCTAssertFalse(app.buttons["Back"].exists)
        assertHiddenBetaCreationSteps(in: app)
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        attachScreenshot(
            of: app,
            named: "Beta creation - cadence first"
        )
        XCTAssertTrue(app.buttons["personal.cadence.daily"].exists)
        XCTAssertTrue(app.buttons["personal.cadence.cumulative"].exists)
        app.buttons["personal.cadence.cumulative"].tap()
        XCTAssertEqual(
            app.buttons["personal.cadence.cumulative"].value as? String,
            "Selected"
        )
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.continue"].tap()

        XCTAssertTrue(
            app.navigationBars["Your goal"].waitForExistence(timeout: 3)
        )
        XCTAssertEqual(
            app.textFields["personal.target"].value as? String,
            "70,000"
        )
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.continue"].tap()

        XCTAssertTrue(
            app.navigationBars["Your amount"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertEqual(
            app.buttons["personal.commitment.1000"].value as? String,
            "Selected"
        )
        for amount in [1_000, 2_000, 3_000, 4_000, 5_000] {
            let preset = app.buttons["personal.commitment.\(amount)"]
            XCTAssertTrue(preset.exists)
            preset.tap()
            XCTAssertEqual(preset.value as? String, "Selected")
        }
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        assertHiddenBetaCreationSteps(in: app)
        assertNoForbiddenLanguage(in: app)
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 3))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        XCTAssertFalse(app.buttons["personal.continue"].isEnabled)
        assertNoLegacyPersonalHealthSurfaces(in: app)
        attachScreenshot(
            of: app,
            named: "Apple Health - connection required"
        )
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertFalse(connectHealth.exists)
        XCTAssertTrue(app.buttons["personal.continue"].isEnabled)
        assertNoLegacyPersonalHealthSurfaces(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Week total"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "$50")
            ).firstMatch.exists
        )
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.submit"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Scheduled"].exists)
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
    }

    func testMainModeCanStartNowAndExposeSyncNow() {
        let app = launch(
            "--fixture-empty",
            "--fixture-activity"
        )
        app.buttons["personal.create"].waitAndTap()
        // cadence, target, commitment
        for _ in 0..<3 {
            app.buttons["personal.continue"].waitAndTap()
        }

        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 3))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        assertNoLegacyPersonalHealthSurfaces(in: app)
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["personal.continue"].isEnabled)
        assertNoLegacyPersonalHealthSurfaces(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        assertExactDisclosure(in: app)
        XCTAssertTrue(app.staticTexts["Seven full days"].exists)
        XCTAssertTrue(app.staticTexts["24 hours after your last day"].exists)
        XCTAssertTrue(app.staticTexts["Every day"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "$10")
            ).firstMatch.exists
        )
        assertNoForbiddenLanguage(in: app)
        let startNow = app.switches["personal.start.now"]
        XCTAssertTrue(startNow.waitForExistence(timeout: 3))
        startNow.tap()
        XCTAssertTrue(
            app.staticTexts["Now — today counts from midnight"].exists
        )
        app.buttons["personal.submit"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["In progress"].exists)
        let syncNow = app.buttons["personal.challenge.sync-now"]
        for _ in 0..<8 where !syncNow.exists { app.swipeUp() }
        XCTAssertTrue(syncNow.waitForExistence(timeout: 3))
        // The disclosure sits at the top of a LazyVStack, so assert it before
        // scrolling to the bottom for the cancel control — once the top of the
        // stack is recycled it is no longer in the hierarchy to find.
        assertExactDisclosure(in: app)
        let cancel = app.buttons["personal.cancel"]
        for _ in 0..<8 where !cancel.exists { app.swipeUp() }
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        assertNoForbiddenLanguage(in: app)

        app.tabBars.buttons["You"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["You"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.staticTexts["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertFalse(
            app.staticTexts.matching(
                NSPredicate(
                    format: "label BEGINSWITH %@",
                    "Last checked"
                )
            ).firstMatch.exists,
            "The local Apple Health creation check must not run or record a trusted diagnostic."
        )
    }

    func testCompletedAppleHealthPermissionCarriesIntoCreation() {
        let app = launch(
            "--fixture-empty"
        )
        app.tabBars.buttons["You"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["You"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Apple Health"].exists)
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 4))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        assertNoLegacyPersonalHealthSurfaces(in: app)
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertFalse(connectHealth.exists)

        app.tabBars.buttons["Today"].waitAndTap()
        app.buttons["personal.create"].waitAndTap()
        // cadence, target, commitment
        for _ in 0..<3 {
            app.buttons["personal.continue"].waitAndTap()
        }

        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Health connected"].exists)
        XCTAssertFalse(app.buttons["personal.health.verify"].exists)
        assertNoLegacyPersonalHealthSurfaces(in: app)
        attachScreenshot(
            of: app,
            named: "Apple Health - permission completed"
        )

        let continueButton = app.buttons["personal.continue"]
        XCTAssertTrue(continueButton.isEnabled)
        continueButton.tap()
        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
    }

    func testLegacyDiagnosticAndHoldStateStayOutOfPersonalV2UI() {
        let app = launch(
            "--fixture-empty",
            "--fixture-personal-hold"
        )
        app.tabBars.buttons["You"].waitAndTap()

        XCTAssertTrue(
            app.staticTexts["Apple Health"].waitForExistence(timeout: 5)
        )
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 4))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        assertNoLegacyPersonalHealthSurfaces(in: app)
        connectHealth.tap()

        app.tabBars.buttons["Today"].waitAndTap()
        let create = app.buttons["personal.create"]
        for _ in 0..<5 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.waitForExistence(timeout: 4))
        XCTAssertTrue(create.isEnabled)
        create.tap()
        for _ in 0..<3 {
            app.buttons["personal.continue"].waitAndTap()
        }
        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Health connected"].exists)
        app.buttons["personal.continue"].waitAndTap()
        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.buttons["personal.submit"].isEnabled)
        assertNoLegacyPersonalHealthSurfaces(in: app)
    }

    func testSavedPersonalRequestCanResumeAfterRelaunch() {
        let app = launch(
            "--fixture-empty",
            "--fixture-personal-pending"
        )
        app.tabBars.buttons["Challenges"].waitAndTap()

        XCTAssertTrue(
            app.staticTexts["Ready to finish"].waitForExistence(timeout: 5)
        )
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        let resume = app.buttons["personal.pending.resume"]
        XCTAssertTrue(resume.waitForExistence(timeout: 4))
        XCTAssertEqual(resume.label, "Continue setup")
        resume.tap()

        XCTAssertTrue(
            app.navigationBars["Apple Health"]
                .waitForExistence(timeout: 4)
        )
        let connectHealth = app.buttons["personal.health.verify"]
        XCTAssertTrue(connectHealth.waitForExistence(timeout: 4))
        XCTAssertEqual(connectHealth.label, "Connect Apple Health")
        connectHealth.tap()
        XCTAssertTrue(
            app.staticTexts["Health connected"]
                .waitForExistence(timeout: 4)
        )
        assertNoLegacyPersonalHealthSurfaces(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Check and confirm"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Week total"].exists)
        XCTAssertTrue(
            exactStaticText(
                "On a daily challenge you have to hit your goal all seven days. On a weekly one you just have to reach the total by the end. If your steps go missing or don’t add up, the week doesn’t count — and it doesn’t count against you.",
                in: app
            ).exists
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["personal.request-id"].exists
        )
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.submit"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Your challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Scheduled"].exists)
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
    }

    func testLoadingEmptyAndOfflineStates() {
        let loading = launch("--fixture-loading")
        XCTAssertTrue(loading.staticTexts["Loading…"].waitForExistence(timeout: 2))
        XCTAssertTrue(loading.otherElements["launch.loading"].exists)
        XCTAssertTrue(
            loading.descendants(matching: .any).matching(
                NSPredicate(format: "label == %@", "Loading GameTime")
            ).firstMatch.exists
        )
        assertNoForbiddenLanguage(in: loading)
        loading.terminate()

        let empty = launch("--fixture-empty")
        XCTAssertTrue(
            empty.staticTexts["Make this week count"]
                .waitForExistence(timeout: 5)
        )
        assertNoForbiddenLanguage(in: empty)
        empty.terminate()

        let offline = launch("--fixture-offline")
        XCTAssertTrue(
            offline.otherElements["state.offline"].waitForExistence(timeout: 5)
                || offline.staticTexts["Couldn’t refresh"].exists
        )
        XCTAssertFalse(offline.staticTexts["Make this week count"].exists)
        XCTAssertFalse(offline.buttons["personal.create"].exists)

        offline.tabBars.buttons["Challenges"].waitAndTap()
        XCTAssertTrue(
            offline.staticTexts["Couldn’t refresh"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(offline.buttons["Try again"].exists)
        XCTAssertFalse(offline.staticTexts["No challenges yet"].exists)
        XCTAssertFalse(offline.buttons["personal.create"].exists)
        assertNoForbiddenLanguage(in: offline)
    }

    func testPersonalDynamicTypeAccessibilityLabelsAndReduceMotion() {
        let app = launch(
            "--fixture-empty",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            "-UIAccessibilityReduceMotionEnabled",
            "YES"
        )

        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Refresh your progress"].exists)
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Challenges"].exists)
        XCTAssertTrue(app.tabBars.buttons["You"].exists)
        assertExactDisclosure(in: app)

        let create = app.buttons["personal.create"]
        for _ in 0..<6 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(
            app.navigationBars["How it counts"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["Step 1 of 5"].exists
        )
        XCTAssertFalse(app.buttons["Back"].exists)
        assertHiddenBetaCreationSteps(in: app)
        let continueButton = app.buttons["personal.continue"]
        XCTAssertEqual(continueButton.label, "Continue")
        XCTAssertTrue(
            continueButton.isHittable,
            "The first beta creation action is off-screen at accessibility XXXL."
        )
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        attachScreenshot(
            of: app,
            named: "Beta creation - cadence accessibility XXXL"
        )
        app.buttons["Close"].waitAndTap()

        app.tabBars.buttons["You"].waitAndTap()
        let privacy = app.buttons["privacy.open"]
        for _ in 0..<8 where !privacy.isHittable { app.swipeUp() }
        XCTAssertTrue(privacy.isHittable)
        privacy.tap()
        XCTAssertTrue(
            app.navigationBars["Privacy"]
                .waitForExistence(timeout: 4)
        )
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
    }

    private func assertHiddenBetaCreationSteps(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            app.navigationBars["What you’ll track"].exists,
            "The one-option metric page is still reachable.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.descendants(matching: .any)["personal.metric.steps"].exists,
            "The fixed Steps choice is still exposed.",
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.navigationBars["When you start"].exists,
            "The custom-start page is still reachable.",
            file: file,
            line: line
        )
        for identifier in [
            "personal.start.day",
            "personal.start.hour",
            "personal.start.tomorrow",
            "personal.start.next-hour",
        ] {
            XCTAssertFalse(
                app.descendants(matching: .any)[identifier].exists,
                "A custom-start control is still exposed: \(identifier)",
                file: file,
                line: line
            )
        }
    }

    private func assertNoLegacyPersonalHealthSurfaces(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for identifier in [
            "personal.sync",
            "personal.health.probe-result",
            "personal.diagnostic.run",
            "personal.eligibility-hold",
        ] {
            XCTAssertFalse(
                app.descendants(matching: .any)[identifier].exists,
                "Personal v2 exposed a retired Health surface: \(identifier)",
                file: file,
                line: line
            )
        }
        let labels = app.descendants(matching: .any).allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let forbidden =
            #"health diagnostic|trusted diagnostic|\battested\b|app attest|first[- ]party|\bsample(?: count|s?)\b|completed[- ]hour|provisioned device"#
        XCTAssertNil(
            labels.range(
                of: forbidden,
                options: [.regularExpression, .caseInsensitive]
            ),
            "Challenge creation contains technical diagnostic copy:\n\(labels)",
            file: file,
            line: line
        )
    }

    private func attachScreenshot(
        of app: XCUIApplication,
        named name: String
    ) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertExactDisclosure(in app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts[
                "Test commitment — no money will be charged."
            ].exists
        )
    }

    private func assertDailyProgress(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.staticTexts["7,350 steps today"].exists,
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts["2,650 to today’s goal"].exists,
            file: file,
            line: line
        )
        let progress = app.progressIndicators["personal.progress"]
        XCTAssertTrue(progress.exists, file: file, line: line)
        XCTAssertEqual(
            progress.label,
            "Today’s progress",
            file: file,
            line: line
        )
        XCTAssertEqual(
            progress.value as? String,
            "7,350 steps today. 2,650 to today’s goal.",
            file: file,
            line: line
        )
    }

    private func assertCumulativeProgress(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.staticTexts["56,000 steps this week"].exists,
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts["14,000 to this week’s goal"].exists,
            file: file,
            line: line
        )
        let progress = app.progressIndicators["personal.progress"]
        XCTAssertTrue(progress.exists, file: file, line: line)
        XCTAssertEqual(progress.label, "Week progress", file: file, line: line)
        XCTAssertEqual(
            progress.value as? String,
            "56,000 steps this week. 14,000 to this week’s goal.",
            file: file,
            line: line
        )
    }

    private func exactStaticText(
        _ label: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "label == %@", label)
        ).firstMatch
    }

    /// Rows that combine a label and a value into one accessibility element
    /// do not surface the label on its own, so match on a fragment.
    private func containing(
        _ fragment: String,
        in app: XCUIApplication
    ) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", fragment)
        ).firstMatch
    }

    private func assertNoForbiddenLanguage(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let labels = app.descendants(matching: .any).allElementsBoundByIndex
            .map(\.label)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let forbidden =
            #"(?i)\b(?:friend|friends|invitation|invitations|roster|rosters|competitor|competitors|rank|ranks|standing|standings|winner|winners|winning|charity|charities|reaction|reactions|tie[- ]?break)\b"#
        XCTAssertNil(
            labels.range(of: forbidden, options: .regularExpression),
            "Reachable Personal V1 UI contains forbidden copy:\n\(labels)",
            file: file,
            line: line
        )
        XCTAssertNil(
            labels.range(
                of: #"B//B|Better Bet"#,
                options: [.regularExpression, .caseInsensitive]
            ),
            "Reachable UI contains a former public identity:\n\(labels)",
            file: file,
            line: line
        )
    }

    private func launch(_ extraArguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode"] + extraArguments
        app.launch()
        return app
    }
}

private extension XCUIElement {
    func waitAndTap(timeout: TimeInterval = 4) {
        XCTAssertTrue(waitForExistence(timeout: timeout))
        tap()
    }
}
