import XCTest

/// Uses the ordinary app with the existing loopback Auth and synthetic Health harness.
final class SignalCreationUITests: XCTestCase {
    @MainActor func testSavedAccountPresentation() throws {
        continueAfterFailure = false
        let app = try launch(actor: 1)
        capture(app, "saved-account-home")
        app.buttons["beta.tab.challenges"].tap()
        capture(app, "saved-account-challenges")
        app.buttons["beta.tab.you"].tap()
        XCTAssertTrue(app.staticTexts["profile.record-scope"].waitForExistence(timeout: 10))
        capture(app, "saved-account-profile")
        let activity = app.buttons["Activity"]
        bring(app, activity); activity.tap()
        XCTAssertTrue(app.otherElements["profile.activity.unavailable"].exists || app.staticTexts["Lifetime totals and streaks aren’t available yet."].exists)
        capture(app, "saved-account-activity")
        tap(app, "profile.settings")
        capture(app, "saved-account-settings")
        tap(app, "privacy.open")
        capture(app, "saved-account-privacy")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        tap(app, "account-support.open")
        capture(app, "saved-account-support")
    }

    @MainActor func testStagedPersonalJourney() throws {
        continueAfterFailure = false
        let app = try launch(actor: 1)
        app.buttons["beta.tab.you"].tap()
        let upcomingBefore = try upcomingCount(app)
        app.buttons["beta.tab.challenges"].tap(); confirmAge(app)
        app.buttons["beta.create.open"].tap()
        capture(app, "after-goal")
        showAdvanced(app)
        app.buttons["beta.create.type.personal"].tap()
        let target = app.textFields["beta.create.target"]
        XCTAssertEqual(target.value as? String, "—", "No target is invented")
        for (metric, value) in [("exercise", "150:30"), ("distance", "12.345678"), ("timed", "25:01"), ("steps", "10000")] {
            tap(app, "beta.create.metric." + metric)
            if metric == "timed" { enter(app, app.textFields["beta.create.distance"], "5.01") }
            enter(app, target, value)
            capture(app, "after-activity-" + metric)
        }
        enter(app, target, "0"); preview(app)
        XCTAssertTrue(app.staticTexts["beta.personal.preview.error"].exists)
        XCTAssertTrue(app.buttons["beta.create.dates"].exists, "The goal's time period is available alongside entry")
        enter(app, target, "10000")
        target.tap(); capture(app, "after-keyboard"); done(app)
        tap(app, "beta.create.dates"); capture(app, "after-dates-editor")
        app.buttons["beta.stepper.days-Increment"].tap()
        XCTAssertEqual(app.textFields["beta.create.days"].value as? String, "8")
        app.buttons["beta.create.dates.done"].tap()
        XCTAssertEqual(target.value as? String, "10000")
        tap(app, "beta.create.dates")
        XCTAssertEqual(app.textFields["beta.create.days"].value as? String, "8")
        app.buttons["beta.stepper.days-Decrement"].tap()
        tap(app, "beta.create.zone")
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("UTC")
        app.buttons["beta.create.zone.UTC"].tap()
        app.buttons["beta.create.dates.done"].tap()
        preview(app)
        tap(app, "beta.create.edit-amount"); capture(app, "after-amount-editor")
        let amount = app.textFields["beta.create.amount"]
        enter(app, amount, "501"); tap(app, "beta.create.amount.save")
        XCTAssertTrue(app.staticTexts["beta.create.amount.error"].exists)
        enter(app, amount, "20"); tap(app, "beta.create.amount.save")
        let consent = app.switches["beta.personal.consent"]
        XCTAssertTrue(consent.waitForExistence(timeout: 20)); capture(app, "after-review-top")
        bring(app, consent); XCTAssertEqual(consent.value as? String, "0")
        let connect = app.buttons["beta.health.connect"]
        bring(app, connect); connect.tap()
        XCTAssertTrue(app.staticTexts["Activity found"].waitForExistence(timeout: 20))
        bring(app, consent); XCTAssertEqual(consent.value as? String, "0", "Readiness never grants consent")
        consent.switchOn(); capture(app, "after-review-consent")
        tap(app, "beta.create.edit-amount"); enter(app, amount, "21")
        tap(app, "beta.create.amount.save")
        XCTAssertTrue(consent.waitForExistence(timeout: 20)); bring(app, consent)
        XCTAssertEqual(consent.value as? String, "0", "An edited agreement requires new consent")
        bring(app, connect); connect.tap()
        XCTAssertTrue(app.staticTexts["Activity found"].waitForExistence(timeout: 20))
        bring(app, consent); consent.switchOn()
        let commit = app.buttons["beta.personal.commit"]; bring(app, commit)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: commit)], timeout: 15), .completed)
        commit.tap()
        XCTAssertTrue(app.staticTexts["beta.create.saved"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["beta.create.saved"].label, "Challenge locked in.")
        XCTAssertTrue(app.buttons["beta.create.home"].exists)
        XCTAssertEqual(app.buttons["beta.create.detail"].label, "View goal")
        XCTAssertFalse(app.buttons["What counts"].exists)
        capture(app, "after-saved")
        let detail = app.buttons["beta.create.detail"]; bring(app, detail); detail.tap()
        XCTAssertTrue(app.staticTexts["What counts"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Back' OR label == 'Back to Home'")).allElementsBoundByIndex.filter(\.isHittable).count, 1)
        capture(app, "after-detail")
        app.swipeUp(); capture(app, "after-detail-lower")

        // Reload the saved account through the ordinary shell, so profile
        // assertions cannot pass by reading the creation draft or receipt.
        app.terminate()
        let restored = try launch(actor: 1)
        restored.buttons["beta.tab.home"].tap()
        let homeGoal = restored.buttons["beta.home.goal"]
        XCTAssertTrue(homeGoal.waitForExistence(timeout: 20))
        XCTAssertTrue(homeGoal.label.contains("10,000"), homeGoal.label)
        capture(restored, "after-restored-home")
        restored.buttons["beta.tab.challenges"].tap()
        tap(restored, "Upcoming")
        let savedGoal = restored.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "beta.row.scheduled.personal_steps_goal_v1.")).firstMatch
        XCTAssertTrue(savedGoal.waitForExistence(timeout: 10)); bring(restored, savedGoal)
        XCTAssertTrue(savedGoal.label.contains("10,000"), savedGoal.label)
        capture(restored, "after-restored-challenges")
        restored.buttons["beta.tab.you"].tap()
        XCTAssertEqual(try upcomingCount(restored), upcomingBefore + 1,
                       "Profile counts the saved ChallengeV1 goal after relaunch, independently of retained Personal history")
        let featured = restored.buttons["profile.featured-goal"]
        XCTAssertTrue(featured.waitForExistence(timeout: 10)); bring(restored, featured)
        XCTAssertTrue(featured.label.contains("10,000"), featured.label)
        capture(restored, "after-restored-profile")
        featured.tap()
        XCTAssertTrue(restored.staticTexts["What counts"].waitForExistence(timeout: 10))
        XCTAssertEqual(restored.buttons.matching(NSPredicate(format: "label == 'Back' OR label == 'Back to Home'")).allElementsBoundByIndex.filter(\.isHittable).count, 1)
        capture(restored, "after-profile-goal-detail")
        restored.buttons["Back to Home"].tap()
        tap(restored, "profile.settings")
        XCTAssertTrue(restored.navigationBars["Settings"].waitForExistence(timeout: 10))
        capture(restored, "after-profile-settings")
        tap(restored, "privacy.open")
        XCTAssertTrue(restored.staticTexts["You choose what you share"].waitForExistence(timeout: 10))
        capture(restored, "after-profile-privacy")
        restored.navigationBars.buttons.element(boundBy: 0).tap()
        tap(restored, "account-support.open")
        XCTAssertTrue(restored.navigationBars["Account & support"].waitForExistence(timeout: 10))
        capture(restored, "after-profile-support")
    }
    @MainActor func testSharedFriendCreation() throws {
        continueAfterFailure = false
        let app = try launch(actor: 2)
        app.buttons["beta.tab.challenges"].tap(); confirmAge(app)
        app.buttons["beta.create.open"].tap()
        showAdvanced(app)
        app.buttons["beta.create.type.leaderboard"].tap()
        for metric in ["steps", "exercise", "distance", "timed"] {
            tap(app, "beta.create.metric." + metric)
            XCTAssertFalse(app.textFields["beta.create.target"].exists)
            XCTAssertFalse(app.staticTexts["Leaderboard — Not available yet"].exists)
            capture(app, "after-friend-leaderboard-" + metric)
        }
        app.buttons["beta.create.metric.steps"].tap()
        next(app)
        let save = app.buttons["beta.create.submit"]; bring(app, save); capture(app, "after-friend-review")
        save.tap()
        XCTAssertTrue(app.staticTexts["beta.invite.heading"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["beta.create.saved"].exists,
                       "Saving the lobby opens invitations before the confirmation screen")
        capture(app, "after-friend-invite")
        tap(app, "beta.invite.done")
        XCTAssertTrue(app.staticTexts["beta.create.saved"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["beta.create.saved"].label, "Challenge saved.", "An open friend lobby isn't locked in until everyone agrees")
        XCTAssertTrue(app.buttons["beta.create.home"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["beta.create.detail"].label, "View goal")
        capture(app, "after-friend-confirmation")
        let detail = app.buttons["beta.create.detail"]; bring(app, detail); detail.tap()
        XCTAssertTrue(app.staticTexts["What counts"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Back' OR label == 'Back to Home'")).allElementsBoundByIndex.filter(\.isHittable).count, 1,
                       "Opening the goal keeps a single back control")
        capture(app, "after-friend-lobby")
    }
    @MainActor func testSavedLobbyInvitationJourney() async throws {
        continueAfterFailure = false
        let fixture = try ownedFixture()
        let origin = try XCTUnwrap(URL(string: try XCTUnwrap(fixture["url"] as? String)))
        @MainActor func fixtureRequest(_ path: String, body: [String: Any]? = nil) async throws -> [String: Any] {
            var request = URLRequest(url: origin.appendingPathComponent(path))
            request.setValue(fixture["controlToken"] as? String, forHTTPHeaderField: "x-p9-control")
            if let body {
                request.httpMethod = "POST"
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        let previousClock = try await fixtureRequest("p9/clock")
        let previousNow = try XCTUnwrap(previousClock["now"] as? String)
        let savedLobby = try await fixtureRequest("p9/control", body: ["action": "latest", "actor": 2])
        XCTAssertEqual(savedLobby["status"] as? String, "lobby_open")
        let lobbyID = try XCTUnwrap(savedLobby["id"] as? String)
        let config = try XCTUnwrap(savedLobby["config"] as? [String: Any])
        let start = try XCTUnwrap(ISO8601DateFormatter().date(from: try XCTUnwrap(config["starts_at"] as? String)))
        // Other owned tests advance this controller through result review.
        // Revisit this saved lobby's planning window, then restore that clock.
        var restoreClock = URLRequest(url: origin.appendingPathComponent("p9/control"), timeoutInterval: 10)
        restoreClock.httpMethod = "POST"
        restoreClock.httpBody = try JSONSerialization.data(withJSONObject: ["action": "clock", "now": previousNow])
        restoreClock.setValue(fixture["controlToken"] as? String, forHTTPHeaderField: "x-p9-control")
        restoreClock.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let restoreRequest = restoreClock
        addTeardownBlock {
            let (_, response) = try await URLSession.shared.data(for: restoreRequest)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200, "The owned fixture clock must be restored")
        }
        _ = try await fixtureRequest("p9/control", body: [
            "action": "clock", "now": ISO8601DateFormatter().string(from: start.addingTimeInterval(-48 * 60 * 60))
        ])
        let app = try launch(actor: 2)
        app.buttons["beta.tab.challenges"].tap(); confirmAge(app)
        let invitation = app.textFields["Invitation link"]
        if !invitation.exists { tap(app, "Invitations and community") }
        bring(app, invitation); invitation.tap()
        if let old = invitation.value as? String, old != invitation.placeholderValue {
            invitation.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        let invalidLink = "this-is-not-an-invitation"
        invitation.typeText(invalidLink)
        XCTAssertFalse(app.buttons["Use invitation"].isEnabled,
                       "Malformed invitation text cannot request access or a lobby place")
        capture(app, "invitation-invalid-entry")
        invitation.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: invalidLink.count))
        app.buttons["beta.tab.home"].tap()
        app.buttons["beta.tab.challenges"].tap()

        // Actor 2's existing fictional leaderboard lobby was saved by the
        // owned journey fixture. This test never creates another challenge.
        let lobby = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier ENDSWITH %@",
            "beta.row.lobby_open.friend_steps_leaderboard_", lobbyID.uppercased()
        )).firstMatch
        XCTAssertTrue(lobby.waitForExistence(timeout: 20)); bring(app, lobby); lobby.tap()
        tap(app, "beta.invite.open")
        XCTAssertTrue(app.staticTexts["beta.invite.heading"].waitForExistence(timeout: 10))
        // D142: accepted friends are picked from a list; there is no username field.
        XCTAssertFalse(app.textFields["beta.invite.input"].exists)
        XCTAssertTrue(app.buttons["beta.invite.add-friend"].waitForExistence(timeout: 10))
        capture(app, "invitation-saved-lobby")
        tap(app, "beta.invite.links")
        let issue = app.buttons["Create invitation link"]
        bring(app, issue)
        // The ordinary app intentionally has no HTTPS invitation origin.
        // Preserve that availability gate; this test does not enable links.
        XCTAssertFalse(issue.isEnabled)
        XCTAssertTrue(app.staticTexts["Invitation links aren’t available yet. Try again later."].exists)
        capture(app, "invitation-unavailable-link-controls")
        tap(app, "beta.invite.done")
        XCTAssertTrue(app.staticTexts["beta.create.saved"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.staticTexts["beta.create.saved"].label, "Challenge saved.", "An open friend lobby isn't locked in until everyone agrees")
        XCTAssertFalse(app.staticTexts["beta.invite.heading"].exists)
        XCTAssertTrue(app.buttons["beta.create.home"].exists)
        capture(app, "invitation-saved-confirmation")
        app.terminate()
    }
    @MainActor func testFriendGoalAndRetainedAccess() throws {
        continueAfterFailure = false
        let app = try launch(actor: 4)
        app.buttons["beta.tab.home"].tap()
        let existing = app.buttons["Existing challenges"]
        XCTAssertTrue(existing.waitForExistence(timeout: 5)); bring(app, existing); existing.tap()
        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); capture(app, "after-retained-access"); done.tap()
        app.buttons["beta.tab.challenges"].tap(); confirmAge(app)
        app.buttons["beta.create.open"].tap()
        next(app)
        let save = app.buttons["beta.create.submit"]; bring(app, save); save.tap()
        XCTAssertTrue(app.staticTexts["beta.invite.heading"].waitForExistence(timeout: 20))
        capture(app, "after-friend-goal-invite")
        tap(app, "beta.invite.done")
        XCTAssertTrue(app.staticTexts["beta.create.saved"].waitForExistence(timeout: 20))
        XCTAssertEqual(app.staticTexts["beta.create.saved"].label, "Challenge saved.", "An open friend lobby isn't locked in until everyone agrees")
        XCTAssertTrue(app.buttons["beta.create.home"].exists)
        capture(app, "after-friend-goal-saved")
        let detail = app.buttons["beta.create.detail"]; bring(app, detail); detail.tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Back' OR label == 'Back to Home'")).allElementsBoundByIndex.filter(\.isHittable).count, 1)
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
        XCTAssertTrue(transparency.waitForExistence(timeout: 5))
        let wasTransparent = transparency.value as? String == "1"
        // An interrupted earlier fixture run may need an explicit restoration
        // target. Ordinary test runs preserve the setting they found.
        let restoreTransparency = ProcessInfo.processInfo.environment["GAMETIME_RESTORE_TRANSPARENCY"] == "off" ? false : wasTransparent
        if !wasTransparent { transparency.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        XCTAssertEqual(transparency.value as? String, "1")
        settings.navigationBars.buttons.firstMatch.tap()
        settings.staticTexts["Motion"].tap()
        let motion = settings.switches.containing(NSPredicate(format: "label CONTAINS 'Reduce Motion'")).firstMatch
        XCTAssertTrue(motion.waitForExistence(timeout: 5))
        let wasReduced = motion.value as? String == "1"
        if !wasReduced { motion.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
        XCTAssertEqual(motion.value as? String, "1")
        defer {
            settings.activate()
            if !wasReduced { motion.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
            // Changing motion can rebuild Settings' navigation. Reopen it
            // before restoring transparency instead of tapping a stale bar.
            settings.terminate()
            settings.launch()
            for _ in 0..<5 {
                if settings.staticTexts["Accessibility"].waitForExistence(timeout: 1) { break }
                if settings.navigationBars.buttons.firstMatch.exists { settings.navigationBars.buttons.firstMatch.tap() } else { settings.swipeUp() }
            }
            let accessibility = settings.staticTexts["Accessibility"]
            if !accessibility.isHittable { settings.swipeUp() }
            accessibility.tap()
            let display = settings.staticTexts["Display & Text Size"]
            XCTAssertTrue(display.waitForExistence(timeout: 5))
            display.tap()
            XCTAssertTrue(transparency.waitForExistence(timeout: 5))
            if (transparency.value as? String == "1") != restoreTransparency {
                transparency.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            }
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", restoreTransparency ? "1" : "0"), object: transparency)], timeout: 5), .completed)
        }
        try testCompactCreationControls()
    }
    @MainActor func testCompactCreationControls() throws {
        continueAfterFailure = false
        let app = try launch(actor: 3)
        app.buttons["beta.tab.challenges"].tap(); confirmAge(app)
        app.buttons["beta.create.open"].tap(); capture(app, "compact-goal")
        let close = app.buttons["beta.create.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["beta.create.back"].exists,
                       "The first step has a close action, not a duplicate back action")
        XCTAssertGreaterThanOrEqual(close.frame.width, 44)
        XCTAssertGreaterThanOrEqual(close.frame.height, 44)
        try app.performAccessibilityAudit(for: .hitRegion)
        showAdvanced(app)
        app.buttons["beta.create.type.personal"].tap()
        enter(app, app.textFields["beta.create.target"], "12345")
        capture(app, "compact-activity")
        let target = app.textFields["beta.create.target"]
        target.tap()
        assertFocusedEntryVisible(app, field: target)
        capture(app, "compact-keyboard"); done(app)
        tap(app, "beta.create.dates"); capture(app, "compact-dates-editor")
        XCTAssertGreaterThanOrEqual(app.buttons["beta.stepper.days-Increment"].frame.height, 44)
        app.buttons["beta.create.dates.done"].tap()
        preview(app)
        XCTAssertTrue(app.buttons["beta.create.back"].waitForExistence(timeout: 5),
                      "Later creation steps can return to the preceding choice")
        tap(app, "beta.create.edit-amount"); capture(app, "compact-amount-editor")
        tap(app, "beta.create.amount.save")
        XCTAssertTrue(app.switches["beta.personal.consent"].waitForExistence(timeout: 20))
        capture(app, "compact-review")
        bring(app, app.buttons["beta.personal.commit"]); capture(app, "compact-review-bottom")
        XCTAssertFalse(app.buttons["beta.personal.commit"].isEnabled)
        app.buttons["beta.create.close"].tap()
        XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout: 5))
    }
    @MainActor func showAdvanced(_ app: XCUIApplication) {
        let personal = app.buttons["beta.create.type.personal"]
        if personal.exists && personal.isHittable { return }
        let advanced = app.buttons["beta.create.advanced"]
        bring(app, advanced)
        advanced.tap()
        XCTAssertTrue(personal.waitForExistence(timeout: 5))
    }
    @MainActor func next(_ app: XCUIApplication) { tap(app, "beta.create.continue") }
    @MainActor func preview(_ app: XCUIApplication) { tap(app, "beta.personal.preview") }
    @MainActor func tap(_ app: XCUIApplication, _ identifier: String) { let button = app.buttons[identifier]; bring(app, button); button.tap() }
    @MainActor func assertFocusedEntryVisible(_ app: XCUIApplication, field: XCUIElement) {
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        let visible = NSPredicate { _, _ in
            let entry = field.frame
            return entry.height > 0 && entry.minY >= app.frame.minY
                && entry.maxY <= keyboard.frame.minY + 2
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: visible, object: field)], timeout: 5), .completed,
                       "The focused goal must stay visible above the keyboard, not just retain its value offscreen")
    }
    @MainActor func upcomingCount(_ app: XCUIApplication) throws -> Int {
        let scope = app.staticTexts["profile.record-scope"]
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "All saved challenges loaded."), object: scope)], timeout: 20), .completed)
        let count = app.descendants(matching: .any).matching(identifier: "profile.count.upcoming").firstMatch
        XCTAssertTrue(count.waitForExistence(timeout: 10))
        let digits = count.label.filter(\.isNumber)
        return try XCTUnwrap(Int(digits), "Expected a complete upcoming count, got: \(count.label)")
    }
    @MainActor func done(_ app: XCUIApplication) { if app.keyboards.count > 0 { app.buttons["beta.create.input.done"].tap() } }
    @MainActor func enter(_ app: XCUIApplication, _ field: XCUIElement, _ value: String) {
        bring(app, field); field.tap()
        if let old = field.value as? String, old != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
        field.typeText(value); done(app)
    }

    @MainActor func ownedFixture() throws -> [String: Any] {
        let file = URL(fileURLWithPath: "/private/tmp/gametime-signal-creation/native.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Owned Signal controller required") }
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        guard fixture["synthetic_only"] as? Bool == true,
              let rawURL = fixture["url"] as? String, let url = URL(string: rawURL),
              url.scheme == "http", let host = url.host,
              ["127.0.0.1", "localhost", "::1", "[::1]"].contains(host) else {
            throw XCTSkip("An owned synthetic loopback fixture is required")
        }
        return fixture
    }
    @MainActor func launch(actor: Int) throws -> XCUIApplication {
        let fixture = try ownedFixture()
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
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            if element.exists && element.frame != .zero && element.frame.maxY < app.frame.midY { app.swipeDown() } else { app.swipeUp() }
        }
        XCTAssertTrue(element.exists); XCTAssertTrue(element.isHittable)
    }
    @MainActor func capture(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
}
private extension XCUIElement {
    @MainActor func switchOn() { if value as? String != "1" { coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() } }
}
