import XCTest

/// Touches the ordinary root using only task-owned synthetic Health/Auth input.
/// It never instantiates a physical Health reader or an Apple device signer.
final class ChallengeHealthSignalUITests: XCTestCase {
    @MainActor func testSignalStepsReadinessConsentCorrectionReviewAndHistory() async throws {
        continueAfterFailure = false
        let file = URL(fileURLWithPath: "/private/tmp/gametime-p9/native.json")
        guard FileManager.default.fileExists(atPath: file.path) else { throw XCTSkip("Owned P9 synthetic controller required") }
        let fixture = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        XCTAssertEqual(fixture["synthetic_only"] as? Bool, true)
        let origin = try XCTUnwrap(URL(string: XCTUnwrap(fixture["url"] as? String)))
        XCTAssertEqual(origin.host, "127.0.0.1")
        let actors = try XCTUnwrap(fixture["actors"] as? [[String: String]])
        let actor = Int(ProcessInfo.processInfo.environment["GAMETIME_SIGNAL_HEALTH_ACTOR"] ?? "7") ?? 7
        XCTAssertTrue(actors.indices.contains(actor))
        @MainActor func control(_ body: [String: Any]) async throws -> [String: Any] {
            var request = URLRequest(url: origin.appendingPathComponent("p9/control"))
            request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue(fixture["controlToken"] as? String, forHTTPHeaderField: "x-p9-control")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let (data, response) = try await URLSession.shared.data(for: request)
            XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
            return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }
        _ = try await control(["action": "clock", "now": "2027-06-01T12:00:00Z"])
        let app = XCUIApplication()
        app.launchArguments = ["--authenticated-app-local", "--p9-synthetic-health"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_URL"] = origin.absoluteString
        app.launchEnvironment["GAMETIME_BETA_LOCAL_KEY"] = fixture["key"] as? String
        app.launchEnvironment["GAMETIME_BETA_LOCAL_EMAIL"] = actors[actor]["email"]
        app.launchEnvironment["GAMETIME_BETA_LOCAL_PASSWORD"] = fixture["password"] as? String
        app.launchEnvironment["GAMETIME_P9_CONTROL"] = fixture["controlToken"] as? String
        app.launch(); defer { app.terminate() }
        func bring(_ element: XCUIElement, down: Bool = false) {
            for _ in 0..<24 { if element.exists && element.isHittable { return }; if down { app.swipeDown() } else { app.swipeUp() } }
            XCTAssertTrue(element.exists, "Missing control: \(element.identifier)"); XCTAssertTrue(element.isHittable)
        }
        func choose(_ identifier: String, _ value: String) {
            let picker = app.buttons[identifier]; bring(picker, down: true); picker.tap(); app.buttons[value].tap()
        }
        func capture(_ name: String) {
            let attachment = XCTAttachment(screenshot: app.screenshot()); attachment.name = "P9 Signal " + name
            attachment.lifetime = .keepAlways; add(attachment)
        }
        let signIn = app.buttons["auth.local-substitute"]
        XCTAssertTrue(signIn.waitForExistence(timeout: 10)); signIn.tap()
        let challenges = app.buttons["beta.tab.challenges"]
        XCTAssertTrue(challenges.waitForExistence(timeout: 15)); challenges.tap()
        let age = app.switches["beta.age.toggle"]
        if age.waitForExistence(timeout: 2) {
            age.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            app.buttons["beta.age.submit"].tap()
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: age)], timeout: 10), .completed)
        }
        app.buttons["beta.create.open"].tap()
        let advanced = app.buttons["beta.create.advanced"]
        bring(advanced, down: true)
        advanced.tap()
        app.buttons["beta.create.type.leaderboard"].tap()
        for metric in ["steps", "exercise", "distance", "timed"] {
            app.buttons["beta.create.metric." + metric].tap()
            XCTAssertFalse(app.staticTexts["Leaderboard — Not available yet"].exists)
            XCTAssertFalse(app.textFields["beta.create.target"].exists)
            XCTAssertTrue(app.buttons["beta.create.continue"].exists)
            capture("received-leaderboard-" + metric)
        }
        let personal = app.buttons["beta.create.type.personal"]
        bring(personal)
        personal.tap()
        app.buttons["beta.create.metric.steps"].tap()
        let target = app.textFields["beta.create.target"]; bring(target); target.tap(); target.typeText("10000")
        app.buttons["beta.create.input.done"].tap()
        let preview = app.buttons["beta.personal.preview"]; bring(preview); XCTAssertTrue(preview.isEnabled); preview.tap()
        let consent = app.switches["beta.personal.consent"], commit = app.buttons["beta.personal.commit"]
        bring(consent); XCTAssertEqual(consent.value as? String, "0")
        consent.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        bring(commit); XCTAssertFalse(commit.isEnabled, "Consent alone cannot replace acknowledged readiness")
        let connect = app.buttons["beta.health.connect"]; bring(connect, down: true); connect.tap()
        XCTAssertTrue(app.staticTexts["Activity found"].waitForExistence(timeout: 15))
        capture("matching-readiness")
        bring(commit)
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: commit)], timeout: 10), .completed)
        commit.tap(); XCTAssertTrue(app.staticTexts["beta.create.saved"].waitForExistence(timeout: 15))
        capture("saved-confirmation")
        app.buttons["beta.create.close"].tap()
        XCTAssertTrue(app.buttons["beta.create.open"].waitForExistence(timeout: 15))
        let latest = try await control(["action": "latest", "actor": actor])
        let id = try XCTUnwrap(latest["id"] as? String), config = try XCTUnwrap(latest["config"] as? [String: Any])
        XCTAssertEqual(config["start_date"] as? String, "2027-06-03", "Planning uses the source clock")
        let scheduled = app.buttons["beta.row.scheduled.personal_steps_goal_v1." + id.uppercased()]
        bring(scheduled); scheduled.tap()
        XCTAssertTrue(app.buttons["Refresh"].waitForExistence(timeout: 10), "The whole saved row opens its detail")
        _ = try await control(["action": "clock", "now": "2027-06-03T12:00:00Z"])
        _ = try await control(["action": "tick", "id": id])
        _ = try await control(["action": "input", "actor": actor, "mode": "value", "value": 10001])
        app.buttons["Refresh"].tap()
        let progress = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '10,001'")).firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 15)); capture("10001-progress")
        _ = try await control(["action": "clock", "now": XCTUnwrap(config["corrections_by"] as? String)])
        _ = try await control(["action": "input", "actor": actor, "mode": "value", "value": 9999])
        app.buttons["Refresh"].tap()
        let corrected = app.staticTexts.containing(NSPredicate(format: "label CONTAINS '9,999'")).firstMatch
        XCTAssertTrue(corrected.waitForExistence(timeout: 15)); capture("9999-correction")
        _ = try await control(["action": "clock", "now": "2027-06-15T12:00:00Z"])
        _ = try await control(["action": "tick", "id": id]); app.buttons["Refresh"].tap()
        let review = app.buttons["beta.review"]; bring(review)
        XCTAssertTrue(app.staticTexts["Latest result update"].exists); capture("actual-notice-review")
        review.tap()
        XCTAssertTrue(app.staticTexts["Your review request is saved. We’re checking your result."].waitForExistence(timeout: 15))
        _ = try await control(["action": "clock", "now": "2027-06-18T12:00:01Z"])
        _ = try await control(["action": "tick", "id": id]); app.buttons["Refresh"].tap()
        let final = app.staticTexts["Result confirmed"].firstMatch
        bring(final); XCTAssertTrue(final.waitForExistence(timeout: 15)); capture("final-return")
        let amount = try XCTUnwrap(config["amount_cents"] as? Int)
        let expectedReturn = "$" + String(format: "%.2f", Double(amount) / 100)
        let returned = app.descendants(matching: .any).matching(identifier: "beta.result.return").firstMatch
        bring(returned); XCTAssertTrue(returned.label.contains(expectedReturn))
        let back = app.buttons["Back to Home"]
        for _ in 0..<12 where !back.isHittable { app.swipeDown() }
        XCTAssertTrue(back.waitForExistence(timeout: 5)); back.tap()
        app.buttons["Finished"].tap()
        let history = app.buttons["beta.row.void.personal_steps_goal_v1." + id.uppercased()]
        bring(history); XCTAssertTrue(history.exists); capture("didnt-count-history")
    }
}
