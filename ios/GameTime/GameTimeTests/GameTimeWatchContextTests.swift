import Foundation
import XCTest

@testable import GameTime

final class GameTimeWatchContextTests: XCTestCase {
    func testReadyContextRoundTripsOnlyTheHandshakeFields() throws {
        let sentAt = Date(timeIntervalSince1970: 1_786_000_000)

        let context = GameTimeWatchContext.ready(sentAt: sentAt)

        XCTAssertEqual(
            Set(context.keys),
            Set(["schema_version", "kind", "sent_at"])
        )
        let handshake = try XCTUnwrap(GameTimeWatchContext.decode(context))
        XCTAssertEqual(handshake.sentAt, sentAt)
    }

    func testContextRejectsUnknownSchemaVersion() {
        let context: [String: Any] = [
            "schema_version": GameTimeWatchContext.schemaVersion + 1,
            "kind": "phone_ready",
            "sent_at": Date.now.timeIntervalSince1970,
        ]

        XCTAssertNil(GameTimeWatchContext.decode(context))
    }

    func testContextRejectsUnknownKind() {
        let context: [String: Any] = [
            "schema_version": GameTimeWatchContext.schemaVersion,
            "kind": "challenge_mutation",
            "sent_at": Date.now.timeIntervalSince1970,
        ]

        XCTAssertNil(GameTimeWatchContext.decode(context))
    }
}
