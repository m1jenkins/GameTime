import XCTest

/// Uses the ordinary app with the existing loopback Auth and synthetic Health harness.
final class SignalCreationUITests: XCTestCase {
    @MainActor func testStagedPersonalJourney() throws {
        continueAfterFailure = false
        let app = try launch(actor: 1)
        app.buttons["beta.tab.challenges"].tap(); confirmAge(app)
        app.buttons["beta.create.open"].tap()
        capture(app, "after-type")
        app.buttons["beta.create.type.personal"].tap(); next(app)
        let target = app.textFields["beta.create.target"]
        XCTAssertEqual(target.value as? String, "—", "No target is invented")
        for (metric, value) in [("exercise", "150:30"), ("distance", "12.345678"), ("timed", "25:01"), ("steps", "10000")] {
            app.buttons["beta.create.metric." + metric].tap()
            if metric == "timed" { enter(app, app.textFields["beta.create.distance"], "5.01") }
            enter(app, target, value)
            capture(app, "after-activity-" + metric)
        }
        enter(app, target, "0"); next(app)
        XCTAssertTrue(app.staticTexts["beta.personal.preview.error"].exists)
        XCTAssertFalse(app.textFields["beta.create.days"].exists)
        enter(app, target, "10000")
        target.tap(); capture(app, "after-keyboard"); done(app)
        next(app); capture(app, "after-dates")
        app.buttons["beta.stepper.days-Increment"].tap()
        XCTAssertEqual(app.textFields["beta.create.days"].value as? String, "8")
        app.buttons["beta.create.back"].tap()
        XCTAssertEqual(target.value as? String, "10000")
        next(app); XCTAssertEqual(app.textFields["beta.create.days"].value as? String, "8")
        app.buttons["beta.stepper.days-Decrement"].tap()
        app.buttons["beta.create.zone"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("UTC")
        app.buttons["beta.create.zone.UTC"].tap()
        next(app); capture(app, "after-amount")
        let amount = app.textFields["beta.create.amount"]
        enter(app, amount, "501"); app.buttons["beta.personal.preview"].tap()
        XCTAssertTrue(app.staticTexts["beta.personal.preview.error"].exists)
        enter(app, amount, "20"); app.buttons["beta.personal.preview"].tap()
        let consent = app.switches["beta.personal.consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 20)); capture(app, "after-review-top")
        bring(app, consent); XCTAssertEqual(consent.value as? String, "0")
        let connect = app.buttons["beta.health.connect"]
        bring(app, connect); connect.tap()
        XCTAssertTrue(app.staticTexts["Activity found"].waitForExistence(timeout: 20))
        bring(app, consent); XCTAssertEqual(consent.value as? String, "0", "Readiness never grants consent")
        consent.switchOn(); capture(app, "after-review-consent")
        app.buttons["beta.create.back"].tap(); enter(app, amount, "21")
        app.buttons["beta.personal.preview"].tap()
        XCTAssertTrue(consent.waitForExistence(timeout: 20)); bring(app, consent)
        XCTAssertEqual(consent.value as? String, "0", "An edited agreement requires new consent")
        bring(app, connect); connect.tap()
        XCTAssertTrue(app.staticTexts["Activity found"].waitForExistence(timeout: 20))
        bring(app, consent); consent.switchOn()
        let commit = app.buttons["beta.personal.commit"]; bring(app, commit)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: commit)], timeout: 15), .completed)
        commit.tap()
        XCTAssertTrue(app.staticTexts["beta.create.saved"].waitForExistence(timeout: 20)); capture(app, "after-saved")
        let detail = app.buttons["beta.create.detail"]; bring(app, detail); detail.tap()
        XCTAssertTrue(app.staticTexts["Your steps goal"].waitForExistence(timeout: 10)); capture(app, "after-detail")
        app.swipeUp(); capture(app, "after-detail-lower")
    }
    @MainActor func testSharedFriendCreation() throws {
        continueAfterFailure = false
        let app = try launch(actor: 2)
        app.buttons["beta.tab.challenges"].tap(); confirmAge(app)
        app.buttons["beta.create.open"].tap()
        app.buttons["beta.create.type.leaderboard"].tap(); next(app)
        for metric in ["steps", "exercise", "distance", "timed"] {
            app.buttons["beta.create.metric." + metric].tap()
            XCTAssertFalse(app.textFields["beta.create.target"].exists)
            XCTAssertFalse(app.staticTexts["Leaderboard — Not available yet"].exists)
            capture(app, "after-friend-leaderboard-" + metric)
        }
        app.buttons["beta.create.metric.steps"].tap()
        next(app); next(app); next(app)
        let save = app.buttons["beta.create.submit"]; bring(app, save); capture(app, "after-friend-review")
        save.tap(); XCTAssertTrue(app.staticTexts["beta.create.saved"].waitForExistence(timeout: 20))
        let detail = app.buttons["beta.create.detail"]; bring(app, detail); detail.tap()
        capture(app, "after-friend-lobby")
    }
    @MainActor func testFriendGoalAndRetainedAccess() throws {
        continueAfterFailure = false
        let app = try launch(actor: 4)
        app.buttons["beta.tab.home"].tap()
        let existing = app.buttons["Existing challenges"]
        XCTAssertTrue(existing.waitForExistence(timeout: 5)); existing.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); capture(app, "after-retained-access"); done.tap()
        app.buttons["beta.tab.challenges"].tap(); confirmAge(app)
        app.buttons["beta.create.open"].tap()
        app.buttons["beta.create.type.friend"].tap()
        next(app); next(app); next(app); next(app)
        let save = app.buttons["beta.create.submit"]; bring(app, save); save.tap()
        XCTAssertTrue(app.staticTexts["beta.create.saved"].waitForExistence(timeout: 20))
        capture(app, "after-friend-goal-saved")
        let detail = app.buttons["beta.create.detail"]; bring(app, detail); detail.tap()
        capture(app, "after-friend-goal-lobby")
    }
    @MainActor func testReducedTransparencyAndMotionCreation() throws {
        continueAfterFailure = false
        guard FileManager.default.fileExists(atPath: "/private/tmp/gametime-signal-creation/native.json") else { throw XCTSkip("Owned Signal controller required") }
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        for _ in 0..<5 {
            if settings.staticTexts["Accessibility"].waitForExistence(timeout: 1) { break }
            if settings.navigationBars.buttons.firstMatch.exists { settings.navigationBars.buttons.firstMatch.tap() } else { settings.swipeUp() }
        }
        let accessibility = settings.staticTexts["Accessibility"]
        if !accessibility.isHittable { settings.swipeUp() }
        accessibility.tap()
        settings.staticTexts["Display & Text Size"].tap()
        let transparency = settings.switches.containing(NSPredicate(format: "label CONTAINS 'Reduce Transparency'")).firstMatch
        let wasTransparent = transparency.value as? String == "1"
        if !wasTransparent { transparency.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        XCTAssertEqual(transparency.value as? String, "1")
        settings.navigationBars.buttons.firstMatch.tap()
        settings.staticTexts["Motion"].tap()
        let motion = settings.switches.containing(NSPredicate(format: "label CONTAINS 'Reduce Motion'")).firstMatch
        let wasReduced = motion.value as? String == "1"
        if !wasReduced { motion.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        XCTAssertEqual(motion.value as? String, "1")
        defer {
            settings.activate()
            if !wasReduced { motion.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
            settings.navigationBars.buttons.firstMatch.tap()
            settings.staticTexts["Display & Text Size"].tap()
            if !wasTransparent { transparency.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        }
        try testCompactCreationControls()
    }
    @MainActor func testCompactCreationControls() throws {
        continueAfterFailure = false
        let app = try launch(actor: 3)
        app.buttons["beta.tab.challenges"].tap(); confirmAge(app)
        app.buttons["beta.create.open"].tap(); capture(app, "compact-type")
        // System bars expose the visible glass bounds, which can be smaller
        // than their expanded hit regions. Audit the actual targets.
        try app.performAccessibilityAudit(for: .hitRegion)
        app.buttons["beta.create.type.personal"].tap(); next(app)
        enter(app, app.textFields["beta.create.target"], "12345")
        capture(app, "compact-activity")
        app.textFields["beta.create.target"].tap(); capture(app, "compact-keyboard"); done(app)
        next(app); capture(app, "compact-dates")
        XCTAssertGreaterThanOrEqual(app.buttons["beta.stepper.days-Increment"].frame.height, 44)
        next(app); capture(app, "compact-amount")
        app.buttons["beta.personal.preview"].tap()
        XCTAssertTrue(app.switches["beta.personal.consent"].waitForExistence(timeout: 20))
        capture(app, "compact-review")
        bring(app, app.buttons["beta.personal.commit"]); capture(app, "compact-review-bottom")
        XCTAssertFalse(app.buttons["beta.personal.commit"].isEnabled)
        app.buttons["beta.create.close"].tap()
        XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout: 5))
    }
    @MainActor func next(_ app: XCUIApplication) { let button = app.buttons["beta.create.continue"]; bring(app, button); button.tap() }
    @MainActor func done(_ app: XCUIApplication) { if app.keyboards.count > 0 { app.buttons["beta.create.input.done"].tap() } }
    @MainActor func enter(_ app: XCUIApplication, _ field: XCUIElement, _ value: String) {
        bring(app, field); field.tap()
        if let old = field.value as? String, old != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(value); done(app)
    }

    @MainActor func launch(actor: Int) throws -> XCUIApplication {
        let file = URL(fileURLWithPath: "/private/tmp/gametime-signal-creation/native.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Owned Signal controller required") }
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(fixture["synthetic_only"] as? Bool, true)
        let actors = try XCTUnwrap(fixture["actors"] as? [[String: String]])
        let app = XCUIApplication()
        app.launchArguments = ["--authenticated-app-local", "--p9-synthetic-health"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_URL"] = fixture["url"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_KEY"] = fixture["key"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_EMAIL"] = actors[actor]["email"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_PASSWORD"] = fixture["password"] as? String
        app.launchEnvironment["GAMETIME_P9_CONTROL"] = fixture["controlToken"] as? String
        app.launch()
        let signIn = app.buttons["auth.local-substitute"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10)); signIn.tap()
        XCTAssertTrue(app.buttons["beta.tab.challenges"].waitForExistence(timeout: 20))
        return app
    }
    @MainActor func confirmAge(_ app: XCUIApplication) {
        let age = app.switches["beta.age.toggle"]
        if age.waitForExistence(timeout: 1) {
            age.switchOn(); app.buttons["beta.age.submit"].tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: age)], timeout: 15), .completed)
        }
    }
    @MainActor func bring(_ app: XCUIApplication, _ element: XCUIElement) {
        for _ in 0..<12 { if element.exists && element.isHittable { return }; app.swipeUp() }
        XCTAssertTrue(element.exists); XCTAssertTrue(element.isHittable)
    }
    @MainActor func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
private extension XCUIElement {
    @MainActor func switchOn() { if value as? String != "1" { coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() } }
}
