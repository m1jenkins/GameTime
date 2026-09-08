import XCTest

final class ChallengeV1UITests:XCTestCase {
    func testAuthenticatedLocalShellHistoryAndAccountExit() throws {
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
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout:15))
        XCTAssertTrue(app.staticTexts["Your challenges"].exists)
        app.tabBars.buttons["Challenges"].tap()
        XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout:5))
        app.tabBars.buttons["You"].tap()
        XCTAssertTrue(app.staticTexts["Fictional activity only"].waitForExistence(timeout:5))
        app.buttons["beta.signout"].tap()
        XCTAssertTrue(email.waitForExistence(timeout:10))
        XCTAssertFalse(app.staticTexts["Your challenges"].exists)
    }
    @MainActor func testTwoPersonTouchJourney() async throws { try await touchJourney([2]) }
    @MainActor func testSixPersonTouchJourney() async throws { try await touchJourney([6]) }
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
            XCTAssertTrue(app.tabBars.buttons["Challenges"].waitForExistence(timeout: 15))
            app.tabBars.buttons["Challenges"].tap()
            let age = app.switches["beta.age.toggle"]
            if age.waitForExistence(timeout: 1) {
                age.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
                tap(app.buttons["beta.age.submit"])
                XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: age)], timeout: 10), .completed)
            }
        }
        func logout() {
            app.tabBars.buttons["You"].tap(); tap(app.buttons["beta.signout"])
            XCTAssertTrue(app.textFields["beta.login.email"].waitForExistence(timeout: 10))
        }
        func open(_ status: String) { tap(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "beta.row." + status + ".friend_steps_goal_v1.")).firstMatch) }
        func target(_ value: String) {
            enter(app.textFields["beta.target.input"], value); tap(app.buttons["beta.target.submit"])
        }
        for count in counts {
            _ = try await betaControl(config, ["action": "clock", "now": "2026-10-01T12:00:00Z"])
            login(0); tap(app.buttons["beta.create.open"])
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
                tap(agreementButton)
                logout()
            }
            _ = try await betaControl(config, ["action": "clock", "now": "2026-10-05T12:00:00Z"])
            _ = try await betaControl(config, ["action": "process", "id": id])
            for i in 0..<count { _ = try await betaControl(config, ["action": "capture", "id": id, "actor": actors[i]["id"]!, "value": 12000]) }
            login(0); open("active")
            XCTAssertTrue(app.staticTexts["12,000 steps · fictional activity"].firstMatch.waitForExistence(timeout: 10))
            logout()
            _ = try await betaControl(config, ["action": "clock", "now": "2026-10-11T12:00:00Z"])
            _ = try await betaControl(config, ["action": "capture", "id": id, "actor": actors[0]["id"]!, "value": 100])
            _ = try await betaControl(config, ["action": "clock", "now": "2026-10-20T12:00:00Z"])
            _ = try await betaControl(config, ["action": "process", "id": id])
            login(0); open("review")
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
