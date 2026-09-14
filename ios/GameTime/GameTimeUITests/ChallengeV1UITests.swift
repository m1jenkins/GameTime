import XCTest

final class ChallengeV1UITests:XCTestCase {
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
        XCTAssertTrue(app.staticTexts["Choose your challenge"].waitForExistence(timeout: 5))
        let formCapture = XCTAttachment(screenshot: app.screenshot()); formCapture.name = "Beta creation " + mode; formCapture.lifetime = .keepAlways; add(formCapture)
        do {
            try app.performAccessibilityAudit()
        } catch { XCTFail("Unfiltered accessibility audit failed: \(error)") }
        for (controlID, before, after) in [("days", "7 days", "8 days"), ("amount", "$20.00 simulated each", "$21.00 simulated each")] {
            let increment = app.buttons["beta.stepper." + controlID + "-Increment"]
            for _ in 0..<12 where !increment.isHittable { app.swipeUp() }
            XCTAssertTrue(increment.isHittable); increment.tap()
            XCTAssertTrue(app.staticTexts[after].exists)
            app.buttons["beta.stepper." + controlID + "-Decrement"].tap()
            XCTAssertTrue(app.staticTexts[before].exists)
        }
        let save = app.buttons["beta.create.submit"]
        for _ in 0..<12 where !save.isHittable { app.swipeUp() }
        XCTAssertTrue(save.isHittable); XCTAssertTrue(save.isEnabled); save.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: save)], timeout: 10), .completed)
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
        choose("beta.create.competition", "Leaderboard")
        for metric in ["Steps", "Exercise time", "Running distance", "Timed run"] {
            choose("beta.create.metric", metric)
            XCTAssertFalse(app.textFields["beta.create.target"].exists)
            capture("leaderboard-create-" + metric)
        }
        choose("beta.create.mode", "Personal goal")
        choose("beta.create.metric", "Steps")
        XCTAssertFalse(app.buttons["beta.create.competition"].exists)
        let target = app.textFields["beta.create.target"]
        bring(target); target.tap(); target.typeText("0\n")
        let preview = app.buttons["beta.personal.preview"]; bring(preview); XCTAssertFalse(preview.isEnabled)
        target.tap(); target.typeText(XCUIKeyboardKey.delete.rawValue + "15000\n")
        bring(preview); XCTAssertTrue(preview.isEnabled); preview.tap()
        let consent = app.switches["beta.personal.consent"]
        bring(consent); XCTAssertEqual(consent.value as? String, "0")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        capture("personal-complete-agreement")
        let increment = app.buttons["beta.stepper.amount-Increment"]
        for _ in 0..<15 where !increment.isHittable { app.swipeDown() }
        increment.tap()
        XCTAssertFalse(consent.exists, "Editing the amount discards the previous consent")
        bring(preview); preview.tap(); bring(consent)
        XCTAssertEqual(consent.value as? String, "0", "The revised agreement requires another explicit choice")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        let commit = app.buttons["beta.personal.commit"]; bring(commit); XCTAssertTrue(commit.isEnabled); commit.tap()
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
            tap(app.buttons["beta.create.submit"])
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
            let history = app.buttons["beta.row.final.friend_steps_goal_v1." + id.uppercased()]
            bring(history); XCTAssertTrue(history.waitForExistence(timeout: 10))
            tap(history)
            let result = app.staticTexts["Recorded simulated return: $0.00"]
            bring(result); XCTAssertTrue(result.waitForExistence(timeout: 10))
            capture("final-\(count)-people")
            logout()
        }
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
