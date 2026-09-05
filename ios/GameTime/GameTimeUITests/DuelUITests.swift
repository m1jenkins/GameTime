import XCTest

@MainActor
final class DuelUITests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    func testCreateConsentReceiptAndLostResponseRecovery() {
        let app = launch("--fixture-duel-lost-response")
        openDuels(app)
        app.buttons["duel.create"].tap()
        let friend = app.buttons["duel.friend.44444444-4444-4444-4444-444444444444"]
        XCTAssertTrue(friend.waitForExistence(timeout: 4))
        friend.tap()
        app.buttons["duel.event"].firstMatch.tap()
        app.buttons["duel.review"].tap()
        XCTAssertTrue(app.navigationBars["Review rules"].waitForExistence(timeout: 4))
        assertDuelLanguage(app)
        let consent = app.switches["duel.consent"]
        scrollTo(consent, in: app)
        XCTAssertFalse(app.buttons["duel.send"].isEnabled)
        consent.switches.firstMatch.exists
            ? consent.switches.firstMatch.tap()
            : consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(consent.value as? String, "1")
        XCTAssertTrue(app.buttons["duel.send"].isEnabled)
        app.buttons["duel.send"].tap()
        let retry = app.buttons["duel.retry"].firstMatch
        scrollTo(retry, in: app, direction: .down)
        XCTAssertTrue(retry.waitForExistence(timeout: 4))
        retry.tap()
        let receipt = app.buttons["duel.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        receipt.tap()
        XCTAssertTrue(app.staticTexts["Waiting for an answer"].waitForExistence(timeout: 4))
        XCTAssertFalse(app.buttons["duel.accept"].exists)
        attach(app, name: "duel-creator-receipt")
    }

    func testIncomingAcceptanceAndCancellationRetainHistory() {
        let app = launch("--fixture-duel-incoming")
        openDuels(app)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'duel.row.'")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Duel rules"].waitForExistence(timeout: 4))
        assertDuelLanguage(app)
        let consent = app.switches["duel.consent"]
        scrollTo(consent, in: app)
        XCTAssertFalse(app.buttons["duel.accept"].isEnabled)
        consent.switches.firstMatch.exists
            ? consent.switches.firstMatch.tap()
            : consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(consent.value as? String, "1")
        XCTAssertTrue(app.buttons["duel.accept"].isEnabled)
        app.buttons["duel.accept"].tap()
        scrollTo(app.staticTexts["duel.status"], in: app, direction: .down)
        XCTAssertEqual(app.staticTexts["duel.status"].label, "You both agreed")
        let cancel = app.buttons["duel.cancel"]
        scrollTo(cancel, in: app)
        cancel.tap()
        app.buttons["duel.confirm-exit"].firstMatch.tap()
        scrollTo(app.staticTexts["duel.status"], in: app, direction: .down)
        XCTAssertEqual(app.staticTexts["duel.status"].label, "Duel cancelled")
        attach(app, name: "duel-cancelled-history")
    }

    func testGateOffDeclineWorksAtAccessibilityTextSize() {
        let app = launch("--fixture-duel-incoming", "--fixture-duel-gate-off",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-UIAccessibilityReduceMotionEnabled", "YES")
        openDuels(app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'duel.row.'")).firstMatch
        scrollTo(row, in: app)
        row.tap()
        XCTAssertTrue(app.navigationBars["Duel rules"].waitForExistence(timeout: 4))
        attach(app, name: "duel-accessibility-xxxl")
        let decline = app.buttons["duel.decline"]
        scrollTo(decline, in: app)
        XCTAssertTrue(decline.isHittable)
        XCTAssertGreaterThanOrEqual(decline.frame.height, 40)
        decline.tap()
        app.buttons["duel.confirm-exit"].firstMatch.tap()
        scrollTo(app.staticTexts["duel.status"], in: app, direction: .down)
        XCTAssertEqual(app.staticTexts["duel.status"].label, "Invitation declined")
    }

    func testCorrectedNoticeReviewAndLostResponseRecovery() {
        let app = launch("--fixture-duel-correction", "--fixture-duel-lost-response", "--fixture-duel-gate-off")
        openDuels(app)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'duel.row.'")).firstMatch.tap()
        let ask = app.buttons["duel.ask-review.2"]
        scrollTo(ask, in: app)
        ask.tap()
        XCTAssertTrue(app.navigationBars["Ask for review"].waitForExistence(timeout: 4))
        let send = app.buttons["duel.send-review"]
        scrollTo(send, in: app)
        XCTAssertFalse(send.isEnabled)
        app.buttons["duel.review-reason.wrong_identity"].tap()
        XCTAssertTrue(send.isEnabled)
        send.tap()
        let retry = app.buttons["duel.retry"].firstMatch
        scrollTo(retry, in: app, direction: .down)
        retry.tap()
        let receipt = app.staticTexts["duel.review-receipt"]
        scrollTo(receipt, in: app)
        XCTAssertEqual(receipt.label, "Your review request is saved")
        XCTAssertFalse(app.buttons["duel.ask-review.2"].exists)
        attach(app, name: "duel-corrected-result-review-receipt")
    }

    func testBlockedContactStillAllowsSafeExitAtAccessibilitySize() {
        let app = launch("--fixture-duel-blocked", "--fixture-duel-gate-off",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-UIAccessibilityReduceMotionEnabled", "YES")
        openDuels(app)
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'duel.row.'")).firstMatch
        scrollTo(row, in: app)
        row.tap()
        let hidden = app.staticTexts["duel.contact-hidden"]
        scrollTo(hidden, in: app)
        XCTAssertFalse(app.staticTexts["Your friend has the winning result"].exists)
        XCTAssertFalse(app.buttons["duel.ask-review.2"].exists)
        let injury = app.buttons["duel.exit.injury"]
        scrollTo(injury, in: app)
        XCTAssertGreaterThanOrEqual(injury.frame.height, 40)
        injury.tap()
        app.buttons["duel.confirm-safe-exit"].firstMatch.tap()
        let receipt = app.staticTexts["duel.exit-receipt"]
        scrollTo(receipt, in: app, direction: .down)
        XCTAssertTrue(receipt.exists)
        attach(app, name: "duel-blocked-injury-accessibility-xxxl")
    }

    func testFinalResultKeepsSimulatedReturnSeparate() {
        let app = launch("--fixture-duel-final")
        openDuels(app)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'duel.row.'")).firstMatch.tap()
        let result = app.staticTexts["duel.final-result"]
        scrollTo(result, in: app)
        XCTAssertEqual(result.label, "You have the winning result")
        let pending = app.staticTexts["duel.return-pending"]
        scrollTo(pending, in: app)
        XCTAssertEqual(pending.label, "Result confirmed — simulated return update pending.")
        XCTAssertFalse(app.staticTexts["duel.simulated-return"].exists)
        XCTAssertFalse(app.buttons["duel.exit.injury"].exists)
        attach(app, name: "duel-final-return-pending")
    }

    func testRecordedReturnIsExplicitlySimulated() {
        let app = launch("--fixture-duel-settlement")
        openDuels(app)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'duel.row.'")).firstMatch.tap()
        let returned = app.staticTexts["duel.simulated-return"]
        scrollTo(returned, in: app)
        XCTAssertTrue(returned.label.contains("$40.00"))
        XCTAssertTrue(app.staticTexts["Nothing can be paid out or redeemed. No real money moved."].exists)
        attach(app, name: "duel-simulated-return-recorded")
        scrollTo(app.staticTexts["duel.simulation"].firstMatch, in: app, direction: .down)
        assertDuelLanguage(app)
    }

    func testNormalPersonalLaunchHasNoDuelEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["You"].waitForExistence(timeout: 5))
        app.tabBars.buttons["You"].tap()
        XCTAssertFalse(app.buttons["duel.open"].exists)
        XCTAssertFalse(app.staticTexts["Friend duels"].exists)
        XCTAssertTrue(app.tabBars.buttons["Today"].exists)
        XCTAssertTrue(app.tabBars.buttons["Challenges"].exists)
    }

    func testLinkOpensReviewWithoutConsentAndRejectsReplacement() {
        let app = launch("--fixture-duel-link", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL",
            "-UIAccessibilityReduceMotionEnabled", "YES")
        XCTAssertTrue(app.tabBars.buttons["You"].waitForExistence(timeout: 5))
        app.open(URL(string: "gametime-duel://invitation/77777777-7777-4777-8777-777777777777")!)
        XCTAssertTrue(app.navigationBars["Duel rules"].waitForExistence(timeout: 8))
        let consent = app.switches["duel.consent"]
        scrollTo(consent, in: app)
        XCTAssertEqual(consent.value as? String, "0")
        scrollTo(app.buttons["duel.accept"], in: app)
        XCTAssertFalse(app.buttons["duel.accept"].isEnabled)
        attach(app, name: "duel-link-needs-consent")
        app.open(URL(string: "gametime-duel://invitation/99999999-9999-4999-8999-999999999999")!)
        scrollTo(app.buttons["duel.open-link"], in: app)
        XCTAssertTrue(app.buttons["duel.open-link"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["duel.accept"].exists)
        scrollTo(app.buttons["Dismiss invitation"], in: app)
        app.buttons["Dismiss invitation"].tap()
    }

    func testRematchFreshConsentAndLinkRevocation() {
        let app = launch("--fixture-duel-final")
        openDuels(app)
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'duel.row.'")).firstMatch.tap()
        let rematch = app.buttons["duel.rematch"]
        scrollTo(rematch, in: app)
        rematch.tap()
        XCTAssertTrue(app.navigationBars["Challenge again"].waitForExistence(timeout: 5))
        app.buttons["duel.event"].firstMatch.tap()
        app.buttons["duel.review"].tap()
        let consent = app.switches["duel.consent"]
        scrollTo(consent, in: app)
        scrollTo(app.buttons["duel.send"], in: app)
        XCTAssertFalse(app.buttons["duel.send"].isEnabled)
        consent.switches.firstMatch.exists ? consent.switches.firstMatch.tap()
            : consent.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["duel.send"].tap()
        let receipt = app.buttons["duel.receipt"]
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        receipt.tap()
        let issue = app.buttons["duel.issue-link"]
        scrollTo(issue, in: app)
        issue.tap()
        let share = app.buttons["duel.share"]
        scrollTo(share, in: app)
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        XCTAssertTrue(share.isEnabled)
        XCTAssertFalse(app.buttons["duel.accept"].exists)
        attach(app, name: "duel-rematch-link-ready")
        let revoke = app.buttons["duel.revoke-link"]
        scrollTo(revoke, in: app)
        revoke.tap()
        XCTAssertTrue(issue.waitForExistence(timeout: 5))
        XCTAssertFalse(share.exists)
        attach(app, name: "duel-rematch-link-revoked")
    }

    private func launch(_ arguments: String...) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode", "--duels"] + arguments
        if !arguments.contains("-UIPreferredContentSizeCategoryName") {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        app.launch()
        return app
    }

    private func openDuels(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["You"].waitForExistence(timeout: 5))
        app.tabBars.buttons["You"].tap()
        let open = app.buttons["duel.open"]
        scrollTo(open, in: app)
        open.tap()
        XCTAssertTrue(app.navigationBars["Friend duels"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["duel.create"].waitForExistence(timeout: 5))
    }

    private enum ScrollDirection { case up, down }
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, direction: ScrollDirection = .up,
                          file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<45 {
            if element.exists && element.isHittable { return }
            if direction == .up { app.swipeUp() } else { app.swipeDown() }
        }
        attach(app, name: "unreachable-control")
        print(app.debugDescription)
        XCTFail("Could not reach \(element)", file: file, line: line)
    }

    private func assertDuelLanguage(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["duel.simulation"].firstMatch.exists)
        let labels = app.debugDescription
        for phrase in ["money locked", "funded balance", "Supabase", "terms_digest", "consent_policy_version", "duel_fixture"] {
            XCTAssertFalse(labels.localizedCaseInsensitiveContains(phrase))
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
