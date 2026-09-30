#if DEBUG
import XCTest

extension LiveDesignUITests {
    func testRound13EmptyChallengesPreservesAgeConfirmationBeforeCreation() {
        continueAfterFailure = false
        let app = launch("challenges-empty", extra: ["--fixture-round-13", "--fixture-age-unconfirmed"])
        defer { app.terminate() }
        let create = app.buttons["live.library.empty.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 10))
        create.tap()
        let age = app.switches["beta.age.toggle"]
        XCTAssertTrue(age.waitForExistence(timeout: 5))
        let save = app.buttons["beta.age.submit"]
        XCTAssertFalse(save.isEnabled)
        age.tap()
        save.tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: age)], timeout: 10), .completed)
        app.buttons["Close"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        create.tap()
        XCTAssertTrue(app.staticTexts["Who’s it for?"].waitForExistence(timeout: 5))
    }

    func testRound13LibraryReviewAndAgreePrecedesActiveChallenge() {
        continueAfterFailure = false
        let app = launch("challenges", extra: ["--fixture-round-13"])
        defer { app.terminate() }
        let review = app.buttons["live.library.review"]
        XCTAssertTrue(review.waitForExistence(timeout: 10))
        XCTAssertEqual(review.label, "Review and agree")
        XCTAssertTrue(app.staticTexts["Needs your attention"].exists)
        let active = element(app, "live.library.active")
        XCTAssertTrue(active.exists)
        XCTAssertLessThan(review.frame.maxY, active.frame.minY)
        app.buttons["live.library.decline"].tap()
        XCTAssertTrue(app.staticTexts["Decline this invitation?"].waitForExistence(timeout: 5))
        app.buttons["beta.create.open"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hittable == true"), object: review)], timeout: 5), .completed)
        review.tap()
        XCTAssertTrue(app.buttons["live.goal.agree"].waitForExistence(timeout: 10))
    }

    func testRound13YouShowsRecordBeforeFriendsAndUnconfirmedResultWithoutAMiss() {
        continueAfterFailure = false
        let app = launch("you", extra: ["--fixture-round-13"])
        defer { app.terminate() }
        let goalsMet = element(app, "profile.count.met")
        XCTAssertTrue(goalsMet.waitForExistence(timeout: 10))
        let friends = app.buttons["profile.friends"]
        XCTAssertTrue(friends.exists)
        XCTAssertLessThan(goalsMet.frame.maxY, friends.frame.minY)
        XCTAssertTrue(app.staticTexts["Not confirmed"].exists)
        XCTAssertTrue(app.staticTexts["It doesn’t count against you."].exists)
        XCTAssertFalse(app.staticTexts["Didn’t count"].exists)
    }

    func testRound13EmptyChallengesOffersOnlyTheFirstChallengePath() {
        continueAfterFailure = false
        let app = launch("challenges-empty", extra: ["--fixture-round-13"])
        defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["Your first challenge"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Choose a goal and the dates that work for you."].exists)
        for filter in ["all", "invited", "finished"] {
            XCTAssertFalse(app.buttons["live.filter." + filter].exists)
        }
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Use an invitation link")).firstMatch.exists)
        let create = app.buttons["live.library.empty.create"]
        XCTAssertEqual(create.label, "Create a challenge")
        create.tap()
        XCTAssertTrue(app.staticTexts["beta.create.heading"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["beta.create.heading"].label, "Who’s it for?")
    }
}
#endif
