#if DEBUG
import XCTest

@MainActor
extension LiveDesignUITests {
    func testRound13AcceptAddsFriendToTopWithoutToast() {
        continueAfterFailure = false
        let app = launch("friends")
        defer { app.terminate() }
        let accept = app.buttons["Accept Taylor’s request"]
        XCTAssertTrue(accept.waitForExistence(timeout: 10))
        accept.tap()
        let added = app.staticTexts["@taylork · Added today"]
        XCTAssertTrue(added.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Requests for you"].exists)
        XCTAssertFalse(element(app, "friends.notice").exists)
        let sam = app.staticTexts["@samr"]
        XCTAssertTrue(sam.exists)
        XCTAssertLessThan(added.frame.minY, sam.frame.minY)
    }
}
#endif
