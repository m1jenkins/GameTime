#if DEBUG
import XCTest

extension LiveDesignUITests {
    func testRound13SettingsShowsAppearancePoliciesAndQuietAccountActions() {
        continueAfterFailure = false
        let app = launch("you")
        defer { app.terminate() }
        app.buttons["profile.settings"].tap()
        XCTAssertTrue(app.staticTexts["Appearance"].waitForExistence(timeout: 5))
        for option in ["System", "Light", "Dark"] {
            XCTAssertTrue(app.buttons["settings.appearance." + option.lowercased()].exists)
        }
        XCTAssertTrue(app.buttons["settings.appearance.system"].isSelected)
        XCTAssertTrue(app.staticTexts["System matches your iPhone."].exists)
        for title in ["Apple Health", "Privacy Policy", "Beta Terms", "Contact support"] {
            XCTAssertTrue(settingsLink(app, title).exists, title)
        }
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Version '")).firstMatch.exists)
        XCTAssertFalse(settingsLink(app, "Account").exists)
        XCTAssertFalse(settingsLink(app, "Help & support").exists)
        let signOut = app.buttons["account-support.sign-out"]
        let delete = app.buttons["account-support.delete"]
        XCTAssertTrue(signOut.exists)
        XCTAssertTrue(delete.exists)
        XCTAssertGreaterThan(delete.frame.minY, signOut.frame.minY)
        delete.tap()
        let alert = app.alerts["Delete your account?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(signOut.exists)
    }

    func testRound13AppearanceChoicePersistsAndSystemCanBeRestored() {
        continueAfterFailure = false
        var app = launch("you")
        app.buttons["profile.settings"].tap()
        let dark = app.buttons["settings.appearance.dark"]
        XCTAssertTrue(dark.waitForExistence(timeout: 5)); dark.tap()
        XCTAssertTrue(dark.isSelected)
        app.terminate()
        app = launch("you")
        defer { app.terminate() }
        app.buttons["profile.settings"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.dark"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings.appearance.dark"].isSelected)
        app.buttons["settings.appearance.light"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.light"].isSelected)
        app.buttons["settings.appearance.system"].tap()
        XCTAssertTrue(app.buttons["settings.appearance.system"].isSelected)
    }
}
#endif
