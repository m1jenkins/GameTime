import XCTest

@MainActor
final class PerformanceCommitmentUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testSummaryKeepsAmountAndFullRulesBeforeConsent() {
        let app = launch()
        openGoals(app)
        app.buttons["commitment.create"].tap()
        scrollTo(app.buttons["commitment.preview"], in: app)
        app.buttons["commitment.preview"].tap()
        let amount = app.staticTexts["commitment.summary-amount"]
        scrollTo(amount, in: app)
        XCTAssertTrue(amount.label.contains("$20 simulated amount"))
        XCTAssertTrue(amount.label.contains("$0 fee"))
        XCTAssertTrue(amount.label.contains("no recipient has been selected"))
        let details = app.buttons["commitment.full-rules"]
        scrollTo(details, in: app)
        details.tap()
        let proofRule = app.staticTexts.matching(NSPredicate(format: "label == %@",
            "Any qualifying attempt that beats your target meets the goal. A later slower run does not undo it. Your notes and milestones do not count as race results.")).firstMatch
        scrollTo(proofRule, in: app)
        XCTAssertTrue(proofRule.isHittable)
        scrollTo(details, in: app, down: true)
        details.tap()
        let consent = app.switches["commitment.consent"]
        scrollTo(consent, in: app)
        XCTAssertEqual(consent.value as? String, "0")
        scrollTo(app.buttons["commitment.save"], in: app)
        XCTAssertFalse(app.buttons["commitment.save"].isEnabled)
        attach(app, "commitment-summary-full-rules-consent")
    }

    func testGoalConsentAndExactRecovery() {
        let app = launch("--fixture-commitment-lost-response")
        openGoals(app)
        app.buttons["commitment.create"].tap()
        scrollTo(app.buttons["commitment.preview"], in: app)
        app.buttons["commitment.preview"].tap()
        let consent = app.switches["commitment.consent"]
        scrollTo(consent, in: app)
        scrollTo(app.buttons["commitment.save"], in: app)
        XCTAssertFalse(app.buttons["commitment.save"].isEnabled)
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        scrollTo(app.buttons["commitment.save"], in: app)
        XCTAssertTrue(app.buttons["commitment.save"].isEnabled)
        app.buttons["commitment.save"].tap()
        let retry = app.buttons["commitment.retry"].firstMatch
        scrollTo(retry, in: app, down: true)
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        let receipt = app.buttons["commitment.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        receipt.tap()
        XCTAssertTrue(app.staticTexts["commitment.status"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["commitment.status"].label, "Starts soon")
        XCTAssertFalse(app.staticTexts["commitment.final-result"].exists)
        attach(app, "commitment-created")
    }

    func testChangingPreviewRequiresFreshConsent() {
        let app = launch()
        openGoals(app)
        app.buttons["commitment.create"].tap()
        scrollTo(app.buttons["commitment.preview"], in: app)
        app.buttons["commitment.preview"].tap()
        let consent = app.switches["commitment.consent"]
        scrollTo(consent, in: app)
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["Change goal"].tap()
        scrollTo(app.buttons["commitment.preview"], in: app)
        app.buttons["commitment.preview"].tap()
        scrollTo(consent, in: app)
        XCTAssertEqual(consent.value as? String, "0")
        scrollTo(app.buttons["commitment.save"], in: app)
        XCTAssertFalse(app.buttons["commitment.save"].isEnabled)
    }

    func testCorrectedResultReviewSurvivesLostResponseWithGateOff() {
        let app = launch("--fixture-commitment-correction", "--fixture-commitment-gate-off", "--fixture-commitment-lost-response")
        openGoals(app)
        openFirstGoal(app)
        let ask = app.buttons["commitment.ask-review.2"]
        scrollTo(ask, in: app)
        ask.tap()
        let send = app.buttons["commitment.send-review"]
        scrollTo(send, in: app)
        XCTAssertFalse(send.isEnabled)
        app.buttons["commitment.review-reason.wrong_identity"].tap()
        send.tap()
        let retry = app.buttons["commitment.retry"].firstMatch
        scrollTo(retry, in: app, down: true)
        retry.tap()
        let receipt = app.staticTexts["commitment.review-receipt"]
        scrollTo(receipt, in: app)
        XCTAssertEqual(receipt.label, "Your review request is saved")
        XCTAssertFalse(app.buttons["commitment.ask-review.2"].exists)
        attach(app, "commitment-review-recovery")
    }

    func testFinalResultDoesNotInventSimulatedReturnOrAllowExit() {
        let app = launch("--fixture-commitment-final")
        openGoals(app)
        openFirstGoal(app)
        XCTAssertTrue(app.staticTexts["commitment.final-result"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["commitment.final-result"].label, "Goal met")
        XCTAssertTrue(app.staticTexts["commitment.simulation-pending"].exists)
        XCTAssertFalse(app.staticTexts["commitment.simulated-return"].exists)
        XCTAssertFalse(app.buttons["commitment.close.withdrawal"].exists)
        XCTAssertFalse(app.buttons["commitment.close.injury"].exists)
        attach(app, "commitment-final-simulation-pending")
    }

    func testAppendedSimulationIsSeparateAndNonredeemable() {
        let app = launch("--fixture-commitment-settlement")
        openGoals(app)
        openFirstGoal(app)
        let recorded = app.staticTexts["commitment.simulated-return"]
        scrollTo(recorded, in: app)
        XCTAssertEqual(recorded.label, "Simulated return recorded: $20.00.")
        XCTAssertEqual(app.staticTexts["commitment.simulated-loss"].label, "Simulated amount lost: $0.00.")
        XCTAssertFalse(app.staticTexts["commitment.simulation-pending"].exists)
        attach(app, "commitment-simulation-recorded")
    }

    func testGateOffSafeExitAtAccessibilitySize() {
        let app = launch("--fixture-commitment-correction", "--fixture-commitment-gate-off",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-UIAccessibilityReduceMotionEnabled", "YES")
        openGoals(app)
        openFirstGoal(app)
        let injury = app.buttons["commitment.close.injury"]
        scrollTo(injury, in: app)
        XCTAssertGreaterThanOrEqual(injury.frame.height, 40)
        injury.tap()
        let confirm = app.buttons["commitment.confirm-close"]
        scrollTo(confirm, in: app)
        confirm.tap()
        let saved = app.staticTexts["commitment.close-receipt"]
        scrollTo(saved, in: app, down: true)
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["commitment.close.injury"].exists)
        attach(app, "commitment-injury-accessibility-xxxl")
    }

    func testNormalPersonalLaunchHasNoRunningGoalEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["You"].waitForExistence(timeout: 8))
        app.tabBars.buttons["You"].tap()
        XCTAssertFalse(app.buttons["commitment.open"].exists)
        XCTAssertFalse(app.staticTexts["commitment.disclosure"].exists)
        XCTAssertFalse(app.buttons["duel.open"].exists)
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode", "--commitments"] + arguments
        if !arguments.contains("-UIPreferredContentSizeCategoryName") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        app.launch()
        return app
    }
    private func openGoals(_ app: XCUIApplication) {
        let tab = app.tabBars.buttons["You"]
        XCTAssertTrue(tab.waitForExistence(timeout: 8))
        tab.tap()
        let open = app.buttons["commitment.open"]
        scrollTo(open, in: app)
        open.tap()
        XCTAssertTrue(app.navigationBars["Running goals"].waitForExistence(timeout: 5))
    }
    private func openFirstGoal(_ app: XCUIApplication) {
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'commitment.row.'")).firstMatch
        scrollTo(row, in: app)
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.navigationBars["Your running goal"].waitForExistence(timeout: 5))
    }
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, down: Bool = false,
                          file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<24 {
            if element.exists && element.isHittable { return }
            down ? app.swipeDown() : app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Expected a reachable control", file: file, line: line)
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
