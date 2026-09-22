#if DEBUG
import XCTest

/// Exercises the ordinary native store and navigation with a local, mutable
/// fixture client. These tests never contact a hosted service or move money.
@MainActor
final class LiveDesignUITests: XCTestCase {
    func testFourLockedScreensUseTheNewNativeShell() {
        continueAfterFailure = false
        for route in ["home", "goal", "challenges", "you"] {
            let app = launch(route)
            for tab in ["home", "challenges", "you"] {
                XCTAssertTrue(app.buttons["beta.tab." + tab].exists)
            }
            switch route {
            case "home":
                XCTAssertTrue(element(app, "live.home.metric").waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["live.home.goal"].exists)
            case "goal":
                XCTAssertTrue(element(app, "live.goal.hero").waitForExistence(timeout: 10))
                XCTAssertTrue(app.staticTexts["What counts"].exists)
            case "challenges":
                XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["live.filter.invited"].exists)
            default:
                XCTAssertTrue(element(app, "profile.count.met").waitForExistence(timeout: 10))
                XCTAssertTrue(element(app, "profile.count.finished").exists)
                XCTAssertTrue(app.buttons["profile.settings"].exists)
            }
            XCTAssertFalse(app.tabBars.buttons["Today"].exists)
            capture(app, name: "live-" + route)
            app.terminate()
        }
    }

    func testFullRulesAreDisclosedAsIndependentModules() {
        continueAfterFailure = false
        let app = launch("goal")
        defer { app.terminate() }
        XCTAssertTrue(element(app, "live.goal.hero").waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Ends, not included"].exists)
        let rules = app.buttons["live.goal.rules"]
        bring(app, rules); rules.tap()
        let dates = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Dates and times")).firstMatch
        XCTAssertTrue(dates.waitForExistence(timeout: 5))
        bring(app, dates)
        XCTAssertEqual(dates.value as? String, "Collapsed")
        XCTAssertFalse(app.staticTexts["Ends, not included"].exists)
        dates.tap()
        XCTAssertEqual(dates.value as? String, "Expanded")
        XCTAssertTrue(app.staticTexts["Ends, not included"].waitForExistence(timeout: 5))
        capture(app, name: "live-full-rules-dates")
        let close = app.buttons["Close"]
        bring(app, close, upward: false); close.tap()
        XCTAssertTrue(element(app, "live.goal.hero").waitForExistence(timeout: 5))
    }

    func testChallengeCreationEntryKeepsTheApprovedNativeFlow() {
        continueAfterFailure = false
        let app = launch("challenges")
        defer { app.terminate() }
        let create = app.buttons["beta.create.open"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let heading = app.staticTexts["beta.create.heading"]
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "What’s your goal?")
        XCTAssertFalse(app.staticTexts["Who’s it for?"].exists)
        let progress = element(app, "beta.create.progress")
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        XCTAssertEqual(progress.label, "Step 1 of 3, Goal")
        XCTAssertLessThan(progress.frame.height, 40, "Goal, Challenge and Friends stay on one line")
        XCTAssertFalse(app.buttons["beta.create.type.leaderboard"].isHittable)
        XCTAssertFalse(app.textFields["beta.create.target"].exists)
        capture(app, name: "create-goal")
        let advanced = app.buttons["beta.create.advanced"]
        XCTAssertTrue(advanced.waitForExistence(timeout: 5))
        bring(app, advanced)
        advanced.tap()
        XCTAssertTrue(app.buttons["beta.create.type.leaderboard"].waitForExistence(timeout: 5))
        XCTAssertEqual(heading.label, "What’s your goal?")
        let next = app.buttons["beta.create.continue"]
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: next)], timeout: 10), .completed)
        next.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Make it a"), object: heading)], timeout: 5), .completed)
        XCTAssertEqual(element(app, "beta.create.progress").label, "Step 2 of 3, Challenge")
        capture(app, name: "create-challenge")
        let invite = app.buttons["beta.create.submit"]
        bring(app, invite)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: invite)], timeout: 10), .completed)
        invite.tap()
        let inviteHeading = app.staticTexts["beta.invite.heading"]
        XCTAssertTrue(inviteHeading.waitForExistence(timeout: 10))
        XCTAssertEqual(inviteHeading.label, "Invite friends.")
        XCTAssertEqual(element(app, "beta.create.progress").label, "Step 3 of 3, Friends")
        capture(app, name: "create-friends")
        app.buttons["beta.create.close"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
    }

    func testInviteReviewNeedsSeparateConsentAndDeclineUpdatesTheStore() {
        continueAfterFailure = false
        let app = launch("challenges")
        defer { app.terminate() }
        let invited = app.buttons["live.filter.invited"]
        XCTAssertTrue(invited.waitForExistence(timeout: 10)); invited.tap()
        let accept = app.buttons["Accept: review invitation"]
        XCTAssertTrue(accept.waitForExistence(timeout: 5)); accept.tap()
        let review = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Review and agree")).firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        bring(app, review); review.tap()
        let consent = app.switches["beta.consent.toggle"]
        XCTAssertTrue(consent.waitForExistence(timeout: 5))
        bring(app, consent)
        XCTAssertEqual(consent.value as? String, "0", "Reviewing an invitation does not accept it")
        XCTAssertFalse(app.buttons["beta.consent"].isEnabled)
        let close = app.buttons["Close"]
        bring(app, close, upward: false); close.tap()
        let back = app.buttons["Back to Home"]
        bring(app, back, upward: false); back.tap()
        XCTAssertTrue(accept.waitForExistence(timeout: 5), "An unaccepted invitation remains available")
        app.buttons["Decline"].tap()
        let confirm = app.buttons["Decline invitation"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); confirm.tap()
        XCTAssertTrue(app.staticTexts["No invitations waiting."].waitForExistence(timeout: 10),
                      "The real store must complete leave and refresh its invitation page")
        XCTAssertFalse(accept.exists)
        app.buttons["live.filter.finished"].tap()
        XCTAssertTrue(app.staticTexts["October runs"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Closed early"].exists)
    }

    func testOnboardingSavesProfileAndAccountSignOutClearsTheNewShell() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-mode", "--fixture-onboarding", "--fixture-empty",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let name = app.textFields["onboarding.name.input"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Your profile"].exists)
        let submit = app.buttons["onboarding.submit"]
        XCTAssertFalse(submit.isEnabled, "An empty profile cannot be submitted")
        name.tap(); name.typeText("Alex Native")
        let username = app.textFields["onboarding.username.input"]
        username.tap(); username.typeText("alexnative")
        XCTAssertTrue(submit.isEnabled, "A complete profile can be submitted")
        // The keyboard can cover the page button while XCTest still reports it
        // as hittable. Exercise the field's real .onSubmit path instead.
        let keyboardDone = app.keyboards.buttons["Done"]
        XCTAssertTrue(keyboardDone.waitForExistence(timeout: 5)); keyboardDone.tap()
        let record = app.buttons["beta.tab.you"]
        XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Alex Native")).firstMatch.waitForExistence(timeout: 5),
                      "The record must use the newly saved profile")
        app.buttons["profile.settings"].tap()
        let account = settingsLink(app, "Account")
        XCTAssertTrue(account.waitForExistence(timeout: 5)); bring(app, account); account.tap()
        XCTAssertTrue(app.staticTexts["@alexnative"].waitForExistence(timeout: 5))
        let signOut = app.buttons["account-support.sign-out"]
        XCTAssertTrue(signOut.waitForExistence(timeout: 5)); signOut.tap()
        XCTAssertTrue(app.buttons["Sign in with Apple"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sign in"].exists)
        XCTAssertFalse(app.buttons["beta.tab.you"].exists)
        XCTAssertFalse(element(app, "profile.count.met").exists)
        XCTAssertFalse(app.staticTexts["@alexnative"].exists, "Signing out must remove the prior account’s presentation")
    }

    func testNewSettingsPreserveHealthPrivacyAndAccountDeletionConfirmation() {
        continueAfterFailure = false
        let app = launch("you")
        defer { app.terminate() }
        let settings = app.buttons["profile.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10)); settings.tap()
        let health = settingsLink(app, "Apple Health")
        XCTAssertTrue(health.waitForExistence(timeout: 5)); health.tap()
        let refresh = app.buttons["settings.health.refresh"]
        XCTAssertTrue(refresh.waitForExistence(timeout: 5)); bring(app, refresh); refresh.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: refresh)], timeout: 10), .completed)
        let back = app.buttons["Back"]
        bring(app, back, upward: false); back.tap()
        let privacy = settingsLink(app, "Sharing & privacy")
        XCTAssertTrue(privacy.waitForExistence(timeout: 5)); privacy.tap()
        XCTAssertTrue(app.staticTexts["Missing activity isn’t a loss"].waitForExistence(timeout: 5))
        bring(app, back, upward: false); back.tap()
        let account = settingsLink(app, "Account")
        XCTAssertTrue(account.waitForExistence(timeout: 5)); bring(app, account); account.tap()
        let delete = app.buttons["account-support.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5)); delete.tap()
        let confirmation = app.alerts["Delete your account?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmation.buttons["Continue"].exists)
        confirmation.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["account-support.sign-out"].waitForExistence(timeout: 5))
        XCTAssertTrue(delete.isEnabled)
        XCTAssertFalse(confirmation.exists, "Cancel must leave the account intact without starting Apple confirmation")
        XCTAssertTrue(app.staticTexts["@alexlee"].exists)
    }

    private func launch(_ route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-live-design", "--live-screen=" + route,
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        XCTAssertTrue(app.buttons["beta.tab.home"].waitForExistence(timeout: 10))
        return app
    }

    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func settingsLink(_ app: XCUIApplication, _ title: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
    }

    private func bring(_ app: XCUIApplication, _ target: XCUIElement, upward: Bool = true) {
        for _ in 0..<10 where !target.isHittable {
            if upward { app.swipeUp() } else { app.swipeDown() }
        }
        XCTAssertTrue(target.isHittable, "Expected an actionable control: \(target)")
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
