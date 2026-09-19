import XCTest
@testable import GameTime

final class ChallengeInvitationTests: XCTestCase {
    private let origin = "https://invites.example.invalid"
    private let token = String(repeating: "a0", count: 32)

    func testHTTPSFormatterRoundTripsOnlyTheConfiguredOrigin() throws {
        let links = ChallengeInvitation(httpsOrigin: origin + "/")
        let url = try XCTUnwrap(links.url(for: token))
        XCTAssertEqual(url.absoluteString, origin + "/challenge-invite/" + token)
        XCTAssertEqual(links.token(from: url.absoluteString), token)
        XCTAssertEqual(links.token(from: "HTTPS://INVITES.EXAMPLE.INVALID/challenge-invite/" + token), token)
        XCTAssertNil(ChallengeInvitation().token(from: url.absoluteString))
        XCTAssertNil(ChallengeInvitation(httpsOrigin: "https://other.example.invalid").token(from: url.absoluteString))
    }

    func testHTTPSRejectsLookalikesCredentialsAndPorts() {
        let links = ChallengeInvitation(httpsOrigin: origin)
        for authority in [
            "http://invites.example.invalid", "https://invites.example.invalid.evil.invalid",
            "https://sub.invites.example.invalid", "https://invites-example.invalid",
            "https://invites.example.invalid.", "https://invites.examp1e.invalid",
            "https://invіtes.example.invalid", "https://invites%2eexample.invalid",
            "https://user@invites.example.invalid", "https://user:pass@invites.example.invalid",
            "https://@invites.example.invalid", "https://invites.example.invalid@evil.invalid",
            "https://invites.example.invalid:443", "https://invites.example.invalid:444",
            "https://invites.example.invalid:", "//invites.example.invalid",
            "https:///invites.example.invalid", "https://invites.example.invalid\\evil.invalid"
        ] {
            XCTAssertNil(links.token(from: authority + "/challenge-invite/" + token), authority)
        }
    }

    func testRejectsUnexpectedPathsEncodingQueriesAndFragments() {
        let links = ChallengeInvitation(httpsOrigin: origin)
        for path in [
            "/", "/" + token, "/challenge-invite", "/challenge-invite/",
            "/Challenge-invite/" + token, "//challenge-invite/" + token,
            "/other/challenge-invite/" + token, "/challenge-invite//" + token,
            "/challenge-invite/../" + token, "/challenge-invite/" + token + "/",
            "/challenge-invite/" + token + "/more", "/%63hallenge-invite/" + token,
            "/challenge-invite/%61" + String(token.dropFirst()),
            "/challenge-invite/" + token + "%2f", "/challenge-invite/" + token + "?",
            "/challenge-invite/" + token + "?redirect=https://other.invalid",
            "/challenge-invite/" + token + "#", "/challenge-invite/" + token + "#result"
        ] {
            XCTAssertNil(links.token(from: origin + path), path)
        }
        for whitespace in [" ", "\n", "\t", "\r\n"] {
            let url = origin + "/challenge-invite/" + token
            XCTAssertNil(links.token(from: whitespace + url))
            XCTAssertNil(links.token(from: url + whitespace))
        }
    }

    func testEveryTokenConsumerUsesTheSameExactAlphabetAndLength() {
        let links = ChallengeInvitation(httpsOrigin: origin)
        let invalid = ["", String(repeating: "a", count: 63), String(repeating: "a", count: 65),
                       String(repeating: "A", count: 64), String(repeating: "g", count: 64),
                       String(repeating: "０", count: 64), String(repeating: "a", count: 63) + "\n",
                       token + "\n", String(repeating: "a", count: 63) + "-", token + "\0"]
        for value in invalid {
            XCTAssertFalse(ChallengeInvitation.isValidToken(value))
            XCTAssertNil(links.url(for: value))
            XCTAssertNil(ChallengeInvitation.localFixture.url(for: value))
            XCTAssertNil(links.token(from: origin + "/challenge-invite/" + value))
            XCTAssertNil(links.token(from: "gametime-beta://challenge-invite/" + value))
        }
    }

    func testFixtureIntakeRemainsAvailableButGenerationIsExplicit() throws {
        let url = try XCTUnwrap(ChallengeInvitation.localFixture.url(for: token))
        XCTAssertEqual(url.absoluteString, "gametime-beta://challenge-invite/" + token)
        for links in [ChallengeInvitation(), ChallengeInvitation(httpsOrigin: origin), .localFixture] {
            XCTAssertEqual(links.token(from: url.absoluteString), token)
            XCTAssertNil(links.token(from: url.absoluteString + "?"))
            XCTAssertNil(links.token(from: url.absoluteString + "#"))
        }
        XCTAssertNil(ChallengeInvitation().url(for: token))
        let duel = DuelInvitationLink.url(token: UUID())
        XCTAssertNotNil(DuelInvitationLink.token(from: duel))
        XCTAssertNil(ChallengeInvitation(httpsOrigin: origin).token(from: duel.absoluteString))
    }

    @MainActor func testSavedHTTPSIntentRequiresTheSameConfiguredOriginOnRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let links = ChallengeInvitation(httpsOrigin: origin)
        let url = try XCTUnwrap(links.url(for: token))
        let intent = ChallengeInvitationIntent(links: links, directory: directory)
        intent.receive(url)
        XCTAssertEqual(ChallengeInvitationIntent(links: links, directory: directory).link, url.absoluteString)
        for closed in [ChallengeInvitation(), ChallengeInvitation(httpsOrigin: "https://other.example.invalid")] {
            let relaunched = ChallengeInvitationIntent(links: closed, directory: directory)
            XCTAssertTrue(relaunched.link.isEmpty)
            relaunched.receive(url)
            XCTAssertTrue(relaunched.link.isEmpty)
        }
        // Closed configuration never deletes the previous valid intent.
        XCTAssertEqual(ChallengeInvitationIntent(links: links, directory: directory).link, url.absoluteString)
        intent.receive(try XCTUnwrap(URL(string: url.absoluteString + "?redirect=x")))
        XCTAssertEqual(intent.link, url.absoluteString)
    }
}
