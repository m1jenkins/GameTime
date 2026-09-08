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
}
