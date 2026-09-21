import XCTest

final class ChallengeV1UITests:XCTestCase {
    @MainActor func testOrdinarySignalAppJourney() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("tmp/beta-native-smoke.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Owned local Beta controller required") }
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let actors = try XCTUnwrap(config["actors"] as? [[String: String]])
        let app = XCUIApplication()
        app.launchArguments = ["--authenticated-app-local"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_URL"] = config["url"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_KEY"] = config["key"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_EMAIL"] = actors[0]["email"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_PASSWORD"] = config["password"] as? String
        app.launch()
        let signIn = app.buttons["auth.local-substitute"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        // A real URL delivery while signed out must survive the ordinary root.
        let opaqueLink = "gametime-beta://challenge-invite/" + String(repeating: "d", count: 64)
        app.open(try XCTUnwrap(URL(string: opaqueLink)))
        signIn.tap()
        XCTAssertTrue(app.buttons["beta.tab.home"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.otherElements["signal.service.closed"].exists)
        XCTAssertTrue(app.buttons["signal.existing-challenges"].exists)
        app.buttons["signal.existing-challenges"].tap()
        XCTAssertTrue(app.buttons["signal.existing.done"].waitForExistence(timeout: 10))
        app.buttons["signal.existing.done"].tap()
        app.buttons["beta.tab.challenges"].tap()
        XCTAssertEqual(app.textFields["Invitation link"].value as? String, opaqueLink)
        let age = app.switches["beta.age.toggle"]
        XCTAssertTrue(age.waitForExistence(timeout: 10))
        age.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        app.buttons["beta.age.submit"].tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: age)], timeout: 10), .completed)
        app.buttons["beta.create.open"].tap()
        func bring(_ element: XCUIElement) {
            for _ in 0..<12 { if element.exists && element.isHittable { return }; app.swipeUp() }
        }
        advanceFriendCreation(app)
        let create = app.buttons["beta.create.submit"]
        bring(create)
        XCTAssertTrue(create.waitForExistence(timeout: 10)); XCTAssertTrue(create.isEnabled)
        create.tap()
        closeSavedCreation(app)
        XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout: 10))
        let latest = try await betaControl(config, ["action": "latest", "actor": actors[0]["id"]!])
        let id = try XCTUnwrap(latest["id"] as? String)
        let lobby = app.buttons["beta.row.lobby_open.friend_steps_goal_v1." + id.uppercased()]
        bring(lobby); XCTAssertTrue(lobby.waitForExistence(timeout: 10)); lobby.tap()
        let cancel = app.buttons["Cancel challenge"]
        bring(cancel); XCTAssertTrue(cancel.waitForExistence(timeout: 10)); cancel.tap()
        let confirmCancel = app.sheets.buttons["Cancel challenge"]
        XCTAssertTrue(confirmCancel.waitForExistence(timeout: 5)); confirmCancel.tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Finished"].tap()
        let history = app.buttons["beta.row.cancelled.friend_steps_goal_v1." + id.uppercased()]
        bring(history); XCTAssertTrue(history.waitForExistence(timeout: 10)); history.tap()
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Ordinary Signal shared-session history"
        attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["beta.tab.you"].tap()
        app.buttons["profile.settings"].tap()
        app.buttons["account-support.open"].tap()
        let signOut = app.buttons["account-support.sign-out"]
        bring(signOut); XCTAssertTrue(signOut.waitForExistence(timeout: 10)); signOut.tap()
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        app.terminate()
        app.launch()
        XCTAssertTrue(signIn.waitForExistence(timeout: 10)); signIn.tap()
        XCTAssertTrue(app.buttons["beta.tab.challenges"].waitForExistence(timeout: 15)); app.buttons["beta.tab.challenges"].tap()
        XCTAssertEqual(app.textFields["Invitation link"].value as? String, opaqueLink, "Cold relaunch retains an unredeemed invitation")
    }

    @MainActor func testOwnedLocalAccountDeletionJourney() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent(
            "tmp/account-deletion-native-local.json"
        )
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw XCTSkip("Owned local deletion fixture required")
        }
        let config = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: file)
            ) as? [String: String]
        )
        let app = XCUIApplication()
        app.launchArguments = ["--beta-challenges-local", "--account-deletion-local"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_URL"] = config["url"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_KEY"] = config["key"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_EMAIL"] = config["email"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_PASSWORD"] = config["password"]
        app.launchEnvironment["GAMETIME_ACCOUNT_DELETION_LOCAL_CODE"] = config["appleCode"]
        app.launch()

        let signIn = app.buttons["beta.login.submit"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10))
        XCTAssertTrue(signIn.isEnabled)
        signIn.tap()
        let you = app.buttons["beta.tab.you"]
        XCTAssertTrue(you.waitForExistence(timeout: 15))
        you.tap()
        let support = app.buttons["local-account-deletion.support"]
        XCTAssertTrue(support.waitForExistence(timeout: 10))
        support.tap()
        let delete = app.buttons["account-support.delete"]
        XCTAssertTrue(delete.waitForExistence(timeout: 10))
        delete.tap()
        let confirmation = app.alerts["Delete your account?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        confirmation.buttons["Continue"].tap()
        let localConfirmation = app.buttons["account-deletion.local-confirm"]
        XCTAssertTrue(localConfirmation.waitForExistence(timeout: 10))
        localConfirmation.tap()
        let complete = app.staticTexts["Account closure is complete"]
        if !complete.waitForExistence(timeout: 5) {
            let receipt = app.buttons["account-support.deletion-receipt"]
            XCTAssertTrue(receipt.waitForExistence(timeout: 15))
            receipt.tap()
        }
        XCTAssertTrue(complete.waitForExistence(timeout: 15))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Owned local account deletion receipt"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor func testAuthenticatedLocalShellHistoryAndAccountExit() throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file=root.appendingPathComponent("tmp/beta-native-smoke.json")
        guard FileManager.default.fileExists(atPath:file.path) else {throw XCTSkip("Local Beta controller required")}
        let config=try XCTUnwrap(JSONSerialization.jsonObject(with:Data(contentsOf:file)) as? [String:Any])
        let actors=try XCTUnwrap(config["actors"] as? [[String:String]])
        let app=XCUIApplication();app.launchArguments=["--beta-challenges-local"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_URL"]=config["url"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_KEY"]=config["key"] as? String
        app.launch()
        let email=app.textFields["beta.login.email"];XCTAssertTrue(email.waitForExistence(timeout:10));email.tap();email.typeText(actors[0]["email"]!)
        let password=app.secureTextFields["beta.login.password"];password.tap();password.typeText(config["password"] as! String)
        app.buttons["beta.login.submit"].tap()
        XCTAssertTrue(app.buttons["beta.tab.home"].waitForExistence(timeout:15))
        XCTAssertTrue(app.buttons["beta.home.create"].exists)
        XCTAssertTrue(app.staticTexts["beta.home.heading"].waitForExistence(timeout:5))
        XCTAssertEqual(app.staticTexts["beta.home.heading"].label, "GameTime")
        app.buttons["beta.tab.challenges"].tap()
        XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout:5))
        app.buttons["beta.tab.you"].tap()
        XCTAssertTrue(app.staticTexts["Fictional activity only"].waitForExistence(timeout:5))
        app.buttons["beta.signout"].tap()
        XCTAssertTrue(email.waitForExistence(timeout:10))
        XCTAssertFalse(app.buttons["beta.home.create"].exists)
    }
    @MainActor func testLocalAccessibilityPreparation() throws {
        continueAfterFailure = true
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("tmp/beta-native-smoke.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Local Beta controller required") }
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let actors = try XCTUnwrap(config["actors"] as? [[String: String]])
        guard let mode = config["accessibilityMode"] as? String, ["light", "dark", "large", "compact"].contains(mode) else { throw XCTSkip("Run the explicit accessibility controller") }
        let app = XCUIApplication(); app.launchArguments = ["--beta-challenges-local"]
        if mode == "compact" { app.launchArguments += ["--beta-compact-check"] }
        app.launchEnvironment["GAMETIME_BETA_LOCAL_URL"] = config["url"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_KEY"] = config["key"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_EMAIL"] = actors[0]["email"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_PASSWORD"] = config["password"] as? String
        app.launch()
        XCTAssertTrue(app.textFields["beta.login.email"].waitForExistence(timeout: 10))
        for _ in 0..<10 where !app.buttons["beta.login.submit"].isHittable { app.swipeUp() }
        XCTAssertTrue(app.buttons["beta.login.submit"].waitForExistence(timeout: 10))
        app.buttons["beta.login.submit"].tap()
        XCTAssertTrue(app.buttons["beta.nav.menu"].waitForExistence(timeout: 2) || app.buttons["beta.tab.home"].waitForExistence(timeout: 15))
        func chooseTab(_ key: String) {
            if app.buttons["beta.nav.menu"].exists { app.buttons["beta.nav.menu"].tap() }
            app.buttons["beta.tab." + key].tap()
        }
        // Ordinary app navigation, with fictional authenticated accounts. System
        // audit is preparation; it cannot establish human VoiceOver comprehension.
        let beforeAudit = XCTAttachment(screenshot: app.screenshot()); beforeAudit.name = "Beta audit screen " + mode; beforeAudit.lifetime = .keepAlways; add(beforeAudit)
        do {
            try app.performAccessibilityAudit()
        } catch { XCTFail("Unfiltered accessibility audit failed: \(error)") }
        chooseTab("challenges")
        let age = app.switches["beta.age.toggle"]
        if age.waitForExistence(timeout: 2) {
            for _ in 0..<12 where !age.isHittable { app.swipeUp() }
            XCTAssertTrue(age.isHittable)
            if age.value as? String != "1" { age.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap() }
            XCTAssertEqual(age.value as? String, "1")
            let submit = app.buttons["beta.age.submit"]
            for _ in 0..<12 {
                let bottom = app.buttons["beta.nav.menu"].exists ? app.buttons["beta.nav.menu"].frame.minY : app.frame.maxY - 100
                if submit.isHittable && submit.frame.midY < bottom { break }
                app.swipeUp()
            }
            XCTAssertTrue(submit.isEnabled); submit.tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: age)], timeout: 10), .completed)
        }
        let create = app.buttons["beta.create.open"]
        for _ in 0..<8 where !create.isHittable { app.swipeDown() }
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        XCTAssertTrue(app.staticTexts["Who’s it for?"].waitForExistence(timeout: 5))
        let formCapture = XCTAttachment(screenshot: app.screenshot()); formCapture.name = "Beta creation " + mode; formCapture.lifetime = .keepAlways; add(formCapture)
        do {
            try app.performAccessibilityAudit()
        } catch { XCTFail("Unfiltered accessibility audit failed: \(error)") }
        tapContinue(app)
        app.buttons["beta.create.dates"].tap()
        let increment = app.buttons["beta.stepper.days-Increment"]
        XCTAssertTrue(increment.isHittable); increment.tap()
        XCTAssertEqual(app.textFields["beta.create.days"].value as? String, "8")
        app.buttons["beta.stepper.days-Decrement"].tap()
        XCTAssertEqual(app.textFields["beta.create.days"].value as? String, "7")
        app.buttons["beta.create.dates.done"].tap()
        tapContinue(app)
        let editAmount = app.buttons["beta.create.edit-amount"]
        for _ in 0..<12 where !editAmount.isHittable { app.swipeUp() }
        editAmount.tap()
        let amount = app.textFields["beta.create.amount"]
        amount.tap(); amount.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "21")
        app.buttons["beta.create.input.done"].tap(); XCTAssertEqual(amount.value as? String, "21")
        amount.tap(); amount.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "20")
        app.buttons["beta.create.input.done"].tap(); XCTAssertEqual(amount.value as? String, "20")
        app.buttons["beta.create.amount.save"].tap()
        let save = app.buttons["beta.create.submit"]
        for _ in 0..<12 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)], timeout: 10), .completed)
        closeSavedCreation(app)
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        chooseTab("home")
        let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "beta.row.lobby_open.friend_steps_goal_v1.")).firstMatch
        // Home cards combine their readable values; Challenges rows have stable IDs.
        let snapshot = XCTAttachment(screenshot: app.screenshot()); snapshot.name = "Beta Home " + mode; snapshot.lifetime = .keepAlways; add(snapshot)
        do {
            try app.performAccessibilityAudit()
        } catch { XCTFail("Unfiltered accessibility audit failed: \(error)") }
        chooseTab("challenges")
        for _ in 0..<10 where !card.isHittable { app.swipeUp() }
        XCTAssertTrue(card.isHittable); card.tap()
        do {
            try app.performAccessibilityAudit()
        } catch { XCTFail("Unfiltered accessibility audit failed: \(error)") }
    }
    private func explicitAccessibilityMode() throws -> String? {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("tmp/beta-native-smoke.json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return (try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])?["accessibilityMode"] as? String
    }
    @MainActor func testSystemScrollDynamicTypeReference() throws {
        guard try explicitAccessibilityMode() == "scroll-reference" else { throw XCTSkip("Explicit diagnostic mode required") }
        let app = XCUIApplication(); app.launchArguments = ["--beta-challenges-local", "--beta-a11y-control-check", "--beta-a11y-scroll-parent"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Body reference 0"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }
    @MainActor func testSystemFormDynamicTypeReference() throws {
        guard try explicitAccessibilityMode() == "form-reference" else { throw XCTSkip("Explicit diagnostic mode required") }
        let app = XCUIApplication(); app.launchArguments = ["--beta-challenges-local", "--beta-a11y-control-check", "--beta-a11y-form-parent"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Body reference 0"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }
    @MainActor func testSystemTabContrastReference() throws {
        guard try explicitAccessibilityMode() == "tab-reference" else { throw XCTSkip("Explicit diagnostic mode required") }
        let app = XCUIApplication(); app.launchArguments = ["--beta-challenges-local", "--beta-a11y-control-check", "--beta-a11y-tab-parent"]
        app.launch()
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
    }
    @MainActor func testIsolatedDynamicTypeControl() throws {
        guard try explicitAccessibilityMode() == "control" else { throw XCTSkip("Explicit diagnostic mode required") }
        let app = XCUIApplication(); app.launchArguments = ["--beta-challenges-local", "--beta-a11y-control-check"]
        app.launch()
        XCTAssertTrue(app.staticTexts["$20.00 simulated each"].waitForExistence(timeout: 10))
        try app.performAccessibilityAudit()
        app.buttons["beta.stepper.amount-Increment"].tap()
        XCTAssertTrue(app.staticTexts["$21.00 simulated each"].exists)
        app.buttons["beta.stepper.amount-Decrement"].tap()
        XCTAssertTrue(app.staticTexts["$20.00 simulated each"].exists)
    }
    @MainActor func testTwoPersonTouchJourney() async throws { try await touchJourney([2]) }
    @MainActor func testSixPersonTouchJourney() async throws { try await touchJourney([6]) }

    @MainActor func testMetricChoicesAndPersonalConsentAfterEditing() throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("tmp/beta-native-smoke.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Local Beta controller required") }
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let actors = try XCTUnwrap(config["actors"] as? [[String: String]])
        let app = XCUIApplication(); app.launchArguments = ["--beta-challenges-local"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_URL"] = config["url"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_KEY"] = config["key"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_EMAIL"] = actors[0]["email"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_PASSWORD"] = config["password"] as? String
        app.launch()
        func bring(_ element: XCUIElement) {
            for _ in 0..<15 where !element.isHittable { app.swipeUp() }
            XCTAssertTrue(element.waitForExistence(timeout: 10))
        }
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "Signal " + name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        func choose(_ identifier: String, _ value: String) {
            let control = app.buttons[identifier]
            for _ in 0..<15 where !control.isHittable { app.swipeDown() }
            control.tap(); app.buttons[value].tap()
        }
        let signIn = app.buttons["beta.login.submit"]; XCTAssertTrue(signIn.waitForExistence(timeout: 10)); signIn.tap()
        let challenges = app.buttons["beta.tab.challenges"]; XCTAssertTrue(challenges.waitForExistence(timeout: 15)); challenges.tap()
        let age = app.switches["beta.age.toggle"]
        if age.waitForExistence(timeout: 1) {
            age.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap(); app.buttons["beta.age.submit"].tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: age)], timeout: 10), .completed)
        }
        app.buttons["beta.create.open"].tap()
        app.buttons["beta.create.type.leaderboard"].tap(); tapContinue(app)
        for metric in ["steps", "exercise", "distance", "timed"] {
            app.buttons["beta.create.metric." + metric].tap()
            XCTAssertFalse(app.textFields["beta.create.target"].exists)
            capture("leaderboard-create-" + metric)
        }
        app.buttons["beta.create.back"].tap(); app.buttons["beta.create.type.personal"].tap(); tapContinue(app)
        app.buttons["beta.create.metric.steps"].tap()
        XCTAssertFalse(app.buttons["beta.create.type.leaderboard"].exists)
        let target = app.textFields["beta.create.target"]
        bring(target); target.tap(); target.typeText("0"); app.buttons["beta.create.input.done"].tap()
        tapContinue(app)
        XCTAssertTrue(app.staticTexts["beta.personal.preview.error"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["beta.personal.preview.error"].label, "Enter a whole number of steps from 1 to 1,000,000,000.")
        target.tap(); target.typeText(XCUIKeyboardKey.delete.rawValue + "15000"); app.buttons["beta.create.input.done"].tap()
        let preview = app.buttons["beta.personal.preview"]; bring(preview); preview.tap()
        let agreement = app.staticTexts["Review your goal."]
        XCTAssertTrue(agreement.waitForExistence(timeout: 10))
        let consent = app.switches["beta.personal.consent"]
        bring(consent); XCTAssertEqual(consent.value as? String, "0")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        capture("personal-complete-agreement")
        let editAmount = app.buttons["beta.create.edit-amount"]
        for _ in 0..<12 where !editAmount.isHittable { app.swipeDown() }
        editAmount.tap()
        let amount = app.textFields["beta.create.amount"]
        amount.tap(); amount.typeText(XCUIKeyboardKey.delete.rawValue + XCUIKeyboardKey.delete.rawValue + "21"); app.buttons["beta.create.input.done"].tap()
        app.buttons["beta.create.amount.save"].tap()
        XCTAssertTrue(consent.waitForExistence(timeout: 15)); bring(consent)
        XCTAssertEqual(consent.value as? String, "0", "The revised agreement requires another explicit choice")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let commit = app.buttons["beta.personal.commit"]; bring(commit); XCTAssertTrue(commit.isEnabled); commit.tap()
        closeSavedCreation(app)
        XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout: 15))
        capture("personal-scheduled")
        app.buttons["beta.tab.you"].tap(); capture("you")
        app.buttons["Privacy and terms"].tap(); capture("privacy-and-terms")
    }
    @MainActor private func touchJourney(_ counts: [Int]) async throws {
        continueAfterFailure = false
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("tmp/beta-native-smoke.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Local Beta controller required") }
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let actors = try XCTUnwrap(config["actors"] as? [[String: String]])
        let app = XCUIApplication(); app.launchArguments = ["--beta-challenges-local"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_URL"] = config["url"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_KEY"] = config["key"] as? String
        app.launch()
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "Signal " + name
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        func bring(_ element: XCUIElement) {
            for _ in 0..<20 { if element.exists && element.isHittable { return }; app.swipeUp() }
        }
        func tap(_ element: XCUIElement) {
            bring(element)
            XCTAssertTrue(element.waitForExistence(timeout: 10))
            let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: element)
            XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
            element.tap()
        }
        func enter(_ field: XCUIElement, _ value: String) {
            bring(field); XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap()
            if let old = field.value as? String, old != field.placeholderValue { field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count)) }
            field.typeText(value + "\n")
        }
        func login(_ i: Int) {
            let email = app.textFields["beta.login.email"]
            XCTAssertTrue(email.waitForExistence(timeout: 15)); enter(email, actors[i]["email"]!)
            enter(app.secureTextFields["beta.login.password"], config["password"] as! String)
            tap(app.buttons["beta.login.submit"])
            XCTAssertTrue(app.buttons["beta.tab.challenges"].waitForExistence(timeout: 15))
            app.buttons["beta.tab.challenges"].tap()
            let age = app.switches["beta.age.toggle"]
            if age.waitForExistence(timeout: 1) {
                age.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
                tap(app.buttons["beta.age.submit"])
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: age)], timeout: 10), .completed)
            }
        }
        func logout() {
            app.buttons["beta.tab.you"].tap(); tap(app.buttons["beta.signout"])
            XCTAssertTrue(app.textFields["beta.login.email"].waitForExistence(timeout: 10))
        }
        func open(_ status: String) { tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "beta.row." + status + ".friend_steps_goal_v1.")).firstMatch) }
        func target(_ value: String) {
            enter(app.textFields["beta.target.input"], value); tap(app.buttons["beta.target.submit"])
        }
        for count in counts {
            _ = try await betaControl(config, ["action": "clock", "now": "2026-10-01T12:00:00Z"])
            login(0); tap(app.buttons["beta.create.open"])
            capture("creation-\(count)-people")
            advanceFriendCreation(app)
            tap(app.buttons["beta.create.submit"])
            closeSavedCreation(app)
            XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout: 10))
            open("lobby_open"); target("10000")
            let latest = try await betaControl(config, ["action": "latest", "actor": actors[0]["id"]!])
            let id = try XCTUnwrap(latest["id"] as? String)
            for i in 1..<count {
                enter(app.textFields["beta.invite.input"], actors[i]["username"]!); tap(app.buttons["beta.invite.submit"])
                logout(); login(i); open("lobby_open"); target(String(10000 + i))
                logout(); login(0); open("lobby_open")
                tap(app.buttons["beta.select." + actors[i]["username"]!])
            }
            capture("lobby-\(count)-people")
            tap(app.buttons["beta.freeze"])
            logout()
            for i in 0..<count {
                login(i); open("consent_pending")
                let agreementButton = app.buttons["beta.consent"]
                bring(agreementButton)
                let agreementSwitch = app.switches["beta.consent.toggle"]
                XCTAssertTrue(agreementSwitch.isHittable)
                agreementSwitch.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
                XCTAssertEqual(agreementSwitch.value as? String, "1", "Explicit consent must visibly be on before submitting")
                if i == 0 { capture("consent-\(count)-people") }
                tap(agreementButton)
                logout()
            }
            _ = try await betaControl(config, ["action": "clock", "now": "2026-10-05T12:00:00Z"])
            _ = try await betaControl(config, ["action": "process", "id": id])
            for i in 0..<count { _ = try await betaControl(config, ["action": "capture", "id": id, "actor": actors[i]["id"]!, "value": 12000]) }
            login(0); open("active")
            XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "12,000 steps of 10,000 steps")).firstMatch.waitForExistence(timeout: 10))
            capture("active-\(count)-people")
            logout()
            _ = try await betaControl(config, ["action": "clock", "now": "2026-10-11T12:00:00Z"])
            _ = try await betaControl(config, ["action": "capture", "id": id, "actor": actors[0]["id"]!, "value": 100])
            _ = try await betaControl(config, ["action": "clock", "now": "2026-10-20T12:00:00Z"])
            _ = try await betaControl(config, ["action": "process", "id": id])
            login(0); open("review")
            capture("review-\(count)-people")
            tap(app.buttons["beta.review"])
            XCTAssertTrue(app.staticTexts["Your review request is saved. We’re checking your result."].waitForExistence(timeout: 10))
            logout()
            // Operator response is fixture control; every participant action above
            // and below is a touch through the real SwiftUI client and Auth.
            _ = try await betaControl(config, ["action": "resolve_challenge", "id": id])
            _ = try await betaControl(config, ["action": "clock", "now": "2026-10-22T12:00:00Z"])
            _ = try await betaControl(config, ["action": "process", "id": id])
            login(0)
            app.buttons["Finished"].tap()
            let history = app.buttons["beta.row.final.friend_steps_goal_v1." + id.uppercased()]
            bring(history); XCTAssertTrue(history.waitForExistence(timeout: 10))
            tap(history)
            let result = app.staticTexts["Recorded simulated return: $0.00"]
            bring(result); XCTAssertTrue(result.waitForExistence(timeout: 10))
            capture("final-\(count)-people")
            logout()
        }
    }
    @MainActor private func tapContinue(_ app: XCUIApplication) {
        let button = app.buttons["beta.create.continue"].exists ? app.buttons["beta.create.continue"] : app.buttons["beta.personal.preview"]
        for _ in 0..<15 where !button.isHittable { app.swipeUp() }
        XCTAssertTrue(button.waitForExistence(timeout: 10)); button.tap()
    }
    @MainActor private func advanceFriendCreation(_ app: XCUIApplication) {
        for _ in 0..<2 { tapContinue(app) }
    }
    @MainActor private func closeSavedCreation(_ app: XCUIApplication) {
        XCTAssertTrue(app.staticTexts["beta.create.saved"].waitForExistence(timeout: 15))
        app.buttons["beta.create.close"].tap()
    }
    @MainActor private func betaControl(_ config: [String: Any], _ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: (config["url"] as! String) + "/__beta/control")!)
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue(config["controlToken"] as? String, forHTTPHeaderField: "X-Beta-Control")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

}
