#if DEBUG
import XCTest

extension LiveDesignUITests {
    func testRound13FriendReviewShowsTheFourCapturedOutcomes() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-live-design", "--live-screen=challenges",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let create = app.buttons["beta.create.open"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let next = app.buttons["beta.create.continue"]
        for _ in 0..<2 {
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == true"), object: next)], timeout: 10), .completed)
            next.tap()
        }
        XCTAssertTrue(app.staticTexts["Everyone reaches it"].waitForExistence(timeout: 5))
        for copy in ["All stakes back", "Some reach it", "They split missed stakes", "Everyone misses",
                     "No one collects", "Couldn’t confirm", "Stake back, not a miss"] {
            XCTAssertTrue(app.staticTexts[copy].exists, "Missing captured result: " + copy)
        }
        XCTAssertEqual(app.buttons["beta.create.submit"].label, "Continue to invite")
    }

    func testRound13ChosenFriendsFillPendingSeatsWithoutIncreasingThePot() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--fixture-live-design", "--live-screen=challenges",
                               "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        defer { app.terminate() }
        let create = app.buttons["beta.create.open"]
        XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
        let next = app.buttons["beta.create.continue"]
        for _ in 0..<2 {
            XCTAssertTrue(next.waitForExistence(timeout: 10))
            XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "enabled == true"), object: next)], timeout: 10), .completed)
            next.tap()
        }
        let invite = app.buttons["beta.create.submit"]
        XCTAssertTrue(invite.waitForExistence(timeout: 10)); invite.tap()
        let sam = app.buttons["beta.invite.friend.samr"]
        let priya = app.buttons["beta.invite.friend.priya_n"]
        XCTAssertTrue(sam.waitForExistence(timeout: 10)); sam.tap()
        for _ in 0..<5 where !priya.isHittable { app.swipeUp() }
        XCTAssertTrue(priya.isHittable); priya.tap()
        let lobby = app.descendants(matching: .any).matching(identifier: "beta.invite.lobby").firstMatch
        XCTAssertTrue(lobby.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["beta.invite.pot"].label, "$20 in the pot")
        XCTAssertTrue(app.staticTexts["Sam and Priya are invited. A seat fills when that friend agrees."].exists)
        XCTAssertEqual(app.buttons["beta.invite.done"].label, "Invite 2 friends")
        XCTAssertTrue(sam.isSelected)
        XCTAssertTrue(priya.isSelected)
    }
}
#endif
