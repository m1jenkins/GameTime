#if DEBUG
import XCTest

extension LiveDesignUITests {
    /// Deterministic local capture account; all transitions use ordinary controls.
    /// Run in each simulator appearance and export these ten named attachments.
    func testRound13ScreenshotStates() {
        continueAfterFailure = false
        let fixture = ["--fixture-round-13"]
        var app = launch("challenges", extra: fixture)
        XCTAssertTrue(app.buttons["live.library.review"].waitForExistence(timeout: 10))
        capture(app, name: "round13-challenges")
        app.terminate()

        app = launch("challenges-empty", extra: fixture)
        XCTAssertTrue(app.staticTexts["Your first challenge"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["live.filter.all"].exists)
        capture(app, name: "round13-challenges-empty")
        app.terminate()

        app = launch("you", extra: fixture)
        XCTAssertTrue(element(app, "profile.count.met").waitForExistence(timeout: 10))
        XCTAssertEqual(element(app, "profile.count.met").label, "7, Goals met")
        XCTAssertEqual(element(app, "profile.count.finished").label, "9, Challenges finished")
        capture(app, name: "round13-you")
        app.buttons["profile.settings"].tap()
        let system = app.buttons["settings.appearance.system"]
        XCTAssertTrue(system.waitForExistence(timeout: 5))
        system.tap()
        XCTAssertTrue(system.isSelected)
        capture(app, name: "round13-settings")
        app.terminate()

        app = launch("friends", extra: fixture)
        let accept = app.buttons["Accept Maya’s request"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        capture(app, name: "round13-friends")
        accept.tap()
        XCTAssertTrue(app.staticTexts["@maya.d · Added today"].waitForExistence(timeout: 10))
        XCTAssertFalse(element(app, "friends.notice").exists)
        XCTAssertTrue(app.tabBars.buttons["You"].isHittable)
        capture(app, name: "round13-friends-accepted")
        app.terminate()

        app = launch("challenges", extra: fixture)
        defer { app.terminate() }
        app.buttons["beta.create.open"].tap()
        XCTAssertTrue(app.staticTexts["Who’s it for?"].waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "beta.create.progress").label, "Step 1 of 4, Who")
        XCTAssertFalse(app.staticTexts["Step 1 of 4"].exists)
        capture(app, name: "round13-create-who")
        let next = app.buttons["beta.create.continue"]
        next.tap()
        XCTAssertTrue(app.staticTexts["What’s your goal?"].waitForExistence(timeout: 5))
        capture(app, name: "round13-create-goal")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"), object: next)], timeout: 10), .completed)
        next.tap()
        XCTAssertTrue(app.staticTexts["Everyone reaches it"].waitForExistence(timeout: 5))
        capture(app, name: "round13-create-challenge")
        let invite = app.buttons["beta.create.submit"]
        bring(app, invite); invite.tap()
        let sam = app.buttons["beta.invite.friend.sam.r"]
        let priya = app.buttons["beta.invite.friend.priya.n"]
        XCTAssertTrue(sam.waitForExistence(timeout: 10))
        sam.tap(); priya.tap()
        XCTAssertEqual(app.buttons["beta.invite.done"].label, "Invite 2 friends")
        // Let the last selection's pressed-state fade finish before the artifact.
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        capture(app, name: "round13-create-friends")
    }
}
#endif
