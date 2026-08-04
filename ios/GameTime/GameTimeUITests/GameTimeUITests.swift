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
        XCTAssertFalse(signedOut.staticTexts["Compete fairly."].exists)
        assertNoForbiddenLanguage(in: signedOut)
        signedOut.terminate()

        let onboarding = launch("--fixture-onboarding")
        XCTAssertTrue(
            onboarding.navigationBars["Set your profile"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(onboarding.textFields["Display name"].exists)
        XCTAssertTrue(onboarding.textFields["Handle"].exists)
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

    func testTodayShowsPersonalProgressTimelineAndManualSync() {
        let app = launch("--fixture-activity")

        XCTAssertTrue(
            app.staticTexts["Your seven days"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["10,000 steps per day"].exists)
        XCTAssertTrue(app.staticTexts["Seven-day timeline"].exists)
        assertExactDisclosure(in: app)
        XCTAssertFalse(app.staticTexts["Friend requests"].exists)
        XCTAssertFalse(app.staticTexts["Challenge invitations"].exists)
        assertNoForbiddenLanguage(in: app)

        let sync = app.buttons["personal.sync"]
        for _ in 0..<5 where !sync.exists { app.swipeUp() }
        XCTAssertTrue(sync.waitForExistence(timeout: 3))
        sync.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS %@", "trusted steps synced")
            ).firstMatch.waitForExistence(timeout: 4)
        )
    }

    func testPersonalDetailContainsFrozenTermsAndNoCompetitiveLanguage() {
        let app = launch("--fixture-open-active-challenge")
        XCTAssertTrue(
            app.navigationBars["Personal challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Frozen terms"].exists)
        XCTAssertTrue(app.staticTexts["Evidence completeness"].exists)
        XCTAssertTrue(app.staticTexts["Steps only"].exists)
        XCTAssertTrue(app.staticTexts["Test only"].exists)
        assertExactDisclosure(in: app)
        XCTAssertFalse(app.staticTexts["Standings"].exists)
        XCTAssertFalse(app.staticTexts["Winner"].exists)
        XCTAssertFalse(app.staticTexts["Charity"].exists)
        assertNoForbiddenLanguage(in: app)
    }

    func testCumulativeCreationOffersOnlyStepsAllCommitmentsAndExactDisclosure() {
        let app = launch(
            "--fixture-empty",
            "--fixture-activity",
            "--fixture-personal-no-diagnostic"
        )
        XCTAssertTrue(
            app.buttons["personal.create"].waitForExistence(timeout: 5)
        )
        app.buttons["personal.create"].tap()

        XCTAssertTrue(
            app.navigationBars["Steps goal"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Steps"].exists)
        XCTAssertFalse(app.staticTexts["Distance"].exists)
        XCTAssertFalse(app.staticTexts["Calories"].exists)
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.continue"].tap()

        XCTAssertTrue(
            app.navigationBars["Choose cadence"].waitForExistence(timeout: 3)
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
            app.navigationBars["Set your target"].waitForExistence(timeout: 3)
        )
        XCTAssertEqual(
            app.textFields["personal.target"].value as? String,
            "70,000"
        )
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.continue"].tap()

        XCTAssertTrue(
            app.navigationBars["Test commitment"]
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
            app.navigationBars["Choose your start"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.descendants(matching: .any)["personal.start.day"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["personal.start.hour"].exists)
        // The default selection is the unchanged next local midnight, so the
        // consequence line must say the seven days are full.
        XCTAssertTrue(
            app.descendants(matching: .any)["personal.start.consequence"]
                .waitForExistence(timeout: 3)
        )
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Health diagnostic"]
                .waitForExistence(timeout: 4)
        )
        app.buttons["personal.diagnostic.run"].waitAndTap()
        XCTAssertTrue(
            app.staticTexts["Trusted diagnostic ready"]
                .waitForExistence(timeout: 4)
        )
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Review frozen terms"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Cumulative"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "$50")
            ).firstMatch.exists
        )
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.submit"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Personal challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Scheduled"].exists)
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
    }

    func testDiagnosticThenReviewCanCreateScheduledChallenge() {
        let app = launch(
            "--fixture-empty",
            "--fixture-activity",
            "--fixture-personal-no-diagnostic"
        )
        app.buttons["personal.create"].waitAndTap()
        // metric, cadence, target, commitment, start
        for _ in 0..<5 {
            app.buttons["personal.continue"].waitAndTap()
        }

        XCTAssertTrue(
            app.navigationBars["Health diagnostic"]
                .waitForExistence(timeout: 4)
        )
        app.buttons["personal.diagnostic.run"].waitAndTap()
        XCTAssertTrue(
            app.staticTexts["Trusted diagnostic ready"]
                .waitForExistence(timeout: 4)
        )
        app.buttons["personal.continue"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Review frozen terms"]
                .waitForExistence(timeout: 4)
        )
        assertExactDisclosure(in: app)
        XCTAssertTrue(app.staticTexts["Seven complete local days"].exists)
        XCTAssertTrue(app.staticTexts["24 hours after day seven"].exists)
        XCTAssertTrue(app.staticTexts["Daily"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "$10")
            ).firstMatch.exists
        )
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.submit"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Personal challenge"]
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.staticTexts["Scheduled"].exists)
        let cancel = app.buttons["personal.cancel"]
        for _ in 0..<8 where !cancel.exists { app.swipeUp() }
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
    }

    func testDebugYouVerifiesHealthWithoutTrustedRecoveryAction() {
        let app = launch(
            "--fixture-empty",
            "--fixture-personal-no-diagnostic"
        )
        app.tabBars.buttons["You"].waitAndTap()

        let verify = app.buttons["personal.health.verify"]
        XCTAssertTrue(verify.waitForExistence(timeout: 5))
        XCTAssertEqual(verify.label, "Verify Health access")
        XCTAssertFalse(app.buttons["personal.diagnostic.run"].exists)
        XCTAssertFalse(app.buttons["Run trusted diagnostic"].exists)
        XCTAssertFalse(app.buttons["Restore trusted access"].exists)
        XCTAssertFalse(
            app.staticTexts[
                "A trusted diagnostic is required before confirming a personal challenge."
            ].exists
        )

        verify.tap()

        let result = app.descendants(matching: .any)[
            "personal.health.probe-result"
        ]
        XCTAssertTrue(result.waitForExistence(timeout: 4))
        XCTAssertEqual(
            result.label,
            "Observed 12 positive Apple-device step samples across 24 completed hours."
        )
        XCTAssertFalse(app.buttons["personal.diagnostic.run"].exists)
    }

    func testEligibilityHoldAppearsAndFreshDiagnosticClearsIt() {
        let app = launch(
            "--fixture-empty",
            "--fixture-activity",
            "--fixture-personal-hold"
        )
        app.tabBars.buttons["You"].waitAndTap()

        let hold = app.descendants(matching: .any)[
            "personal.eligibility-hold"
        ]
        for _ in 0..<5 where !hold.exists { app.swipeUp() }
        XCTAssertTrue(
            hold.waitForExistence(timeout: 5)
        )
        let diagnostic = app.buttons["personal.diagnostic.run"]
        for _ in 0..<5 where !diagnostic.isHittable { app.swipeDown() }
        XCTAssertTrue(diagnostic.waitForExistence(timeout: 4))
        XCTAssertEqual(diagnostic.label, "Restore trusted access")
        XCTAssertFalse(app.buttons["Run trusted diagnostic"].exists)
        diagnostic.waitAndTap()
        XCTAssertTrue(
            app.staticTexts["Trusted"].waitForExistence(timeout: 4)
        )
        XCTAssertFalse(hold.exists)
        XCTAssertFalse(app.buttons["personal.diagnostic.run"].exists)
        app.tabBars.buttons["Today"].waitAndTap()
        let create = app.buttons["personal.create"]
        for _ in 0..<5 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.waitForExistence(timeout: 4))
        XCTAssertTrue(create.isEnabled)
        assertNoForbiddenLanguage(in: app)
    }

    func testSavedPersonalRequestCanResumeAfterRelaunch() {
        let app = launch(
            "--fixture-empty",
            "--fixture-personal-pending"
        )
        app.tabBars.buttons["Challenges"].waitAndTap()

        XCTAssertTrue(
            app.staticTexts["Exact retry ready"].waitForExistence(timeout: 5)
        )
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.pending.resume"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Review frozen terms"]
                .waitForExistence(timeout: 4)
        )
        XCTAssertTrue(app.staticTexts["Cumulative"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["personal.request-id"].exists
        )
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        app.buttons["personal.submit"].waitAndTap()

        XCTAssertTrue(
            app.navigationBars["Personal challenge"]
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
        XCTAssertTrue(app.buttons["Refresh accountability progress"].exists)
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Challenges"].exists)
        XCTAssertTrue(app.tabBars.buttons["You"].exists)
        assertExactDisclosure(in: app)

        let create = app.buttons["personal.create"]
        for _ in 0..<6 where !create.isHittable { app.swipeUp() }
        XCTAssertTrue(create.isHittable)
        create.tap()
        XCTAssertTrue(
            app.navigationBars["Steps goal"].waitForExistence(timeout: 4)
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["Step 1 of 7"].exists
        )
        XCTAssertEqual(app.buttons["personal.continue"].label, "Continue")
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
        app.buttons["Close"].waitAndTap()

        app.tabBars.buttons["You"].waitAndTap()
        let privacy = app.buttons["privacy.open"]
        for _ in 0..<8 where !privacy.isHittable { app.swipeUp() }
        XCTAssertTrue(privacy.isHittable)
        privacy.tap()
        XCTAssertTrue(
            app.navigationBars["Trust & privacy"]
                .waitForExistence(timeout: 4)
        )
        assertExactDisclosure(in: app)
        assertNoForbiddenLanguage(in: app)
    }

    private func assertExactDisclosure(in app: XCUIApplication) {
        XCTAssertTrue(
            app.staticTexts[
                "Test commitment — no money will be charged."
            ].exists
        )
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
