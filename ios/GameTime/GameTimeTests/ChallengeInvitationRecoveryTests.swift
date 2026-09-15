#if DEBUG
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import GameTime

@MainActor final class ChallengeInvitationRecoveryTests: XCTestCase {
    func testOlderRedemptionCannotClearNewlyReceivedInvitation() async throws {
        try await redemptionOverlap(editOnly: false, accountChange: false)
    }

    func testOlderRedemptionCannotClearEditedInvitation() async throws {
        try await redemptionOverlap(editOnly: true, accountChange: false)
    }

    func testAccountChangeCannotAcknowledgeUnconfirmedRedemption() async throws {
        try await redemptionOverlap(editOnly: false, accountChange: true)
    }

    func testUnchangedInvitationClearsOnlyAfterSuccessfulRedemption() async throws {
        let fixture = InvitationRecoveryFixture()
        await fixture.start()
        fixture.client.receipt = .init(id: fixture.id, status: "pending_request")
        let invitation = ChallengeInvitationIntent(directory: fixture.directory.appendingPathComponent("intent"))
        let url = invitationURL("b")
        invitation.receive(url)
        fixture.client.loseFirstResponse = true
        let panel = ChallengeEntryPanel(store: fixture.store, invitation: invitation)
        await panel.useInvitation()
        XCTAssertEqual(invitation.link, url.absoluteString, "An unconfirmed request stays recoverable")
        await fixture.store.retry()
        await panel.useInvitation()
        XCTAssertTrue(invitation.link.isEmpty)
        XCTAssertTrue(ChallengeInvitationIntent(directory: fixture.directory.appendingPathComponent("intent")).link.isEmpty)
    }

    func testUnrelatedOrIncompleteReceiptsDoNotClearInvitation() async throws {
        for receipt in [ChallengeV1Receipt(status: "pending_request"), .init(id: UUID(), status: "cancelled_request"), .init(saved: true)] {
            let fixture = InvitationRecoveryFixture()
            await fixture.start(); fixture.client.receipt = receipt
            let directory = fixture.directory.appendingPathComponent("intent")
            let invitation = ChallengeInvitationIntent(directory: directory)
            let url = invitationURL("b"); invitation.receive(url)
            await ChallengeEntryPanel(store: fixture.store, invitation: invitation).useInvitation()
            XCTAssertEqual(invitation.link, url.absoluteString)
            XCTAssertEqual(ChallengeInvitationIntent(directory: directory).link, url.absoluteString)
            XCTAssertEqual(fixture.client.requests.count, 1)
        }
    }

    private func redemptionOverlap(editOnly: Bool, accountChange: Bool) async throws {
        let fixture = InvitationRecoveryFixture()
        await fixture.start()
        fixture.client.receipt = .init(id: fixture.id, status: "pending_request")
        fixture.client.holdResponse = true
        let intentDirectory = fixture.directory.appendingPathComponent("intent")
        let invitation = ChallengeInvitationIntent(directory: intentDirectory)
        let first = invitationURL("b"), newer = invitationURL("c")
        invitation.receive(first)
        let panel = ChallengeEntryPanel(store: fixture.store, invitation: invitation)
        let task = Task { await panel.useInvitation() }
        defer { fixture.client.finishHeld(throwing: ChallengeV1Error.unavailable) }
        let deadline = Date().addingTimeInterval(2)
        while fixture.client.held == nil && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertNotNil(fixture.client.held)
        XCTAssertEqual(fixture.client.requests.last?.payload["token"]?.string, String(repeating: "b", count: 64))
        if accountChange {
            fixture.auth.actor = UUID(); fixture.store.setActor(fixture.auth.actor)
        } else if editOnly { invitation.link = newer.absoluteString }
        else { invitation.receive(newer) }
        fixture.client.finishHeld()
        await task.value
        let expected = accountChange ? first : newer
        XCTAssertEqual(invitation.link, expected.absoluteString, "Only the successfully submitted, unchanged invitation can be acknowledged")
        if !editOnly {
            XCTAssertEqual(ChallengeInvitationIntent(directory: intentDirectory).link, expected.absoluteString,
                           "The newer received invitation must survive relaunch")
        }
        XCTAssertEqual(fixture.client.requests.count, 1, "Receiving a replacement never submits or consents to it")
    }

    private func invitationURL(_ character: String) -> URL {
        URL(string: "gametime-beta://challenge-invite/" + String(repeating: character, count: 64))!
    }

    func testExactIssueRetryPresentsRecoveredLinkInMountedIssuer() async throws {
        let fixture = InvitationRecoveryFixture()
        let mounted = try mount(fixture)
        defer { mounted.close() }
        await fixture.start()
        fixture.client.loseFirstResponse = true
        await fixture.store.submit(op: "issue_link", fields: ["id": .string(fixture.id.uuidString.lowercased())])
        let pending = try XCTUnwrap(fixture.store.pending)
        XCTAssertNil(fixture.store.lastReceipt)
        await fixture.store.retry()
        XCTAssertNil(fixture.store.pending)
        XCTAssertEqual(fixture.client.requests, [pending, pending], "Recovery must repeat the exact actor, request ID and body")
        XCTAssertEqual(fixture.store.lastReceipt, fixture.client.receipt)
        let text = try await capture(mounted, name: "recovered-issuer")
        XCTAssertTrue(text.contains("revoke invitation link"), "The mounted issuer must present the exact recovered link and its revocation control")
        XCTAssertTrue(text.contains("gametime-beta"))
    }

    func testRecreatedIssuerRetainsLinkWithoutAnotherIssuance() async throws {
        let fixture = InvitationRecoveryFixture()
        await fixture.start()
        await fixture.store.submit(op: "issue_link", fields: ["id": .string(fixture.id.uuidString.lowercased())])
        XCTAssertNil(fixture.store.pending)
        let mounted = try mount(fixture)
        defer { mounted.close() }
        let text = try await capture(mounted, name: "recreated-issuer")
        XCTAssertTrue(text.contains("revoke invitation link"), "Recreating the view must not lose the issuer's only revocation path")
        XCTAssertTrue(text.contains("gametime-beta"))
        XCTAssertEqual(fixture.client.requests.count, 1, "Reopening cannot create a replacement link")
    }

    func testExactRevokeRetryKeepsControlUntilConfirmed() async throws {
        let fixture = InvitationRecoveryFixture()
        await fixture.start()
        await fixture.store.submit(op: "issue_link", fields: ["id": .string(fixture.id.uuidString.lowercased())])
        let mounted = try mount(fixture)
        defer { mounted.close() }
        let linkID = try XCTUnwrap(fixture.client.receipt.id)
        fixture.client.failNextResponse = true
        await fixture.store.submit(op: "revoke_link", fields: ["id": .string(linkID.uuidString.lowercased())])
        let pending = try XCTUnwrap(fixture.store.pending)
        XCTAssertEqual(pending.payload["id"]?.string, linkID.uuidString.lowercased())
        let interrupted = try await capture(mounted, name: "revoke-unconfirmed")
        XCTAssertTrue(interrupted.contains("revoke invitation link"), "An interrupted revocation must retain its locator")
        await fixture.store.retry()
        XCTAssertNil(fixture.store.pending)
        XCTAssertEqual(Array(fixture.client.requests.suffix(2)), [pending, pending])
        let confirmed = try await capture(mounted, name: "revoke-confirmed")
        XCTAssertFalse(confirmed.contains("revoke invitation link"))
        let persisted = try await fixture.store.requests.loadIssuedLinks(fixture.actor)
        XCTAssertTrue(persisted.isEmpty)
    }

    func testIssuedLinkSurvivesStoreRelaunchWithoutCrossingActorOrChallenge() async throws {
        let fixture = InvitationRecoveryFixture()
        await fixture.start()
        await fixture.store.submit(op: "issue_link", fields: ["id": .string(fixture.id.uuidString.lowercased())])
        let relaunched = ChallengeV1Store(auth: fixture.auth, client: fixture.client,
            requests: ChallengeV1RequestStore(directory: fixture.directory))
        relaunched.setActor(fixture.actor); await relaunched.refresh()
        let mounted = try mount(fixture, store: relaunched)
        let text = try await capture(mounted, name: "relaunched-issuer"); mounted.close()
        XCTAssertTrue(text.contains("revoke invitation link"))
        let unrelated = InvitationRecoveryFixture()
        let other = try mount(unrelated, store: relaunched)
        let otherText = try await capture(other, name: "unrelated-issuer"); other.close()
        XCTAssertFalse(otherText.contains("revoke invitation link"), "An unrelated challenge must never reuse the actor's last receipt")
        fixture.auth.actor = unrelated.actor
        relaunched.setActor(unrelated.actor)
        let changed = try mount(fixture, store: relaunched)
        defer { changed.close() }
        let changedText = try await capture(changed, name: "other-account-issuer")
        XCTAssertFalse(changedText.contains("revoke invitation link"), "Account changes clear mounted invitation locators")
        let otherLinks = try await relaunched.requests.loadIssuedLinks(unrelated.actor)
        XCTAssertTrue(otherLinks.isEmpty)
        XCTAssertEqual(fixture.client.requests.count, 1)
    }

    func testSavedLinkJournalBindsRequestAndRevokesOnlyConfirmedExactTarget() async throws {
        let actor = UUID(), challenge = UUID()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("issued-link-journal-" + UUID().uuidString)
        let requests = ChallengeV1RequestStore(directory: directory)
        let issue = ChallengeV1Request(actor: actor, payload: .object(["op": .string("issue_link"), "id": .string(challenge.uuidString)]))
        let first = ChallengeV1Receipt(id: UUID(), token: String(repeating: "a", count: 64), expiresAt: ChallengeInstant(date: Date().addingTimeInterval(86400)))
        try await requests.save(issue)
        let recorded = try await requests.recordIssuedLinkReceipt(first, for: issue)
        let links = try XCTUnwrap(recorded)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.actorId, actor)
        XCTAssertEqual(links.first?.challengeId, challenge)
        XCTAssertEqual(links.first?.requestId, issue.requestId)
        let again = try await requests.recordIssuedLinkReceipt(first, for: issue)
        XCTAssertEqual(again, links, "Exact recovery cannot duplicate a link")
        let pending = try await requests.load(actor)
        XCTAssertEqual(pending, issue, "Recording the receipt must not rewrite or prematurely clear the pending request")
        let revoke = ChallengeV1Request(actor: actor, payload: .object(["op": .string("revoke_link"), "id": .string(try XCTUnwrap(first.id).uuidString)]))
        do {
            _ = try await requests.recordIssuedLinkReceipt(.init(saved: true), for: revoke)
            XCTFail("An unrelated successful receipt cannot confirm revocation")
        } catch { XCTAssertEqual(error as? ChallengeV1Error, .invalidResponse) }
        let cancelled = try await requests.recordIssuedLinkReceipt(.init(status: "cancelled_request"), for: revoke)
        XCTAssertEqual(cancelled, links, "Stopping an uncommitted revoke cannot discard the issued locator")
        let secondIssue = ChallengeV1Request(actor: actor, payload: issue.payload)
        let second = ChallengeV1Receipt(id: UUID(), token: String(repeating: "d", count: 64), expiresAt: first.expiresAt)
        let together = try await requests.recordIssuedLinkReceipt(second, for: secondIssue)
        XCTAssertEqual(together?.count, 2, "Another issuance must not orphan the first link")
        let revoked = try await requests.recordIssuedLinkReceipt(.init(revoked: true), for: revoke)
        XCTAssertEqual(revoked?.map(\.id), [try XCTUnwrap(second.id)], "Revocation removes only its exact link")
        let restored = try await ChallengeV1RequestStore(directory: directory).loadIssuedLinks(actor)
        XCTAssertEqual(restored, revoked)
    }

    func testRemovingAnAccountAlsoRemovesIssuedLinksWithoutAQueuedRequest() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("issued-link-account-cleanup-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ChallengeV1RequestStore(directory: directory)
        let owner = UUID()
        let other = UUID()
        let ownerRequest = ChallengeV1Request(
            actor: owner,
            payload: .object(["op": .string("issue_link"), "id": .string(UUID().uuidString)])
        )
        let otherRequest = ChallengeV1Request(
            actor: other,
            payload: .object(["op": .string("issue_link"), "id": .string(UUID().uuidString)])
        )
        let ownerReceipt = ChallengeV1Receipt(
            id: UUID(), token: String(repeating: "a", count: 64),
            expiresAt: ChallengeInstant(date: Date().addingTimeInterval(86_400))
        )
        let otherReceipt = ChallengeV1Receipt(
            id: UUID(), token: String(repeating: "b", count: 64),
            expiresAt: ChallengeInstant(date: Date().addingTimeInterval(86_400))
        )
        _ = try await store.recordIssuedLinkReceipt(ownerReceipt, for: ownerRequest)
        _ = try await store.recordIssuedLinkReceipt(otherReceipt, for: otherRequest)
        let ownerPending = try await store.load(owner)
        XCTAssertNil(ownerPending, "This covers the no-pending-request cleanup path")

        try await store.removeAll(for: owner)

        let ownerLinks = try await store.loadIssuedLinks(owner)
        let otherLinks = try await store.loadIssuedLinks(other)
        XCTAssertEqual(ownerLinks, [])
        XCTAssertEqual(otherLinks.count, 1)
    }

    func testUnreadableLinkJournalPreservesExactPendingIssuance() async throws {
        let fixture = InvitationRecoveryFixture()
        await fixture.start()
        try FileManager.default.createDirectory(at: fixture.directory, withIntermediateDirectories: true)
        let file = fixture.directory.appendingPathComponent(fixture.actor.uuidString.lowercased() + "-issued-links.json")
        try Data("unreadable fixture journal".utf8).write(to: file)
        await fixture.store.submit(op: "issue_link", fields: ["id": .string(fixture.id.uuidString.lowercased())])
        let pending = try XCTUnwrap(fixture.store.pending)
        XCTAssertNil(fixture.store.lastReceipt, "A server receipt is not locally complete until its locator is recoverable")
        let persisted = try await fixture.store.requests.load(fixture.actor)
        XCTAssertEqual(persisted, pending)
        // Restore this deliberately malformed test fixture, not any user record.
        let empty: [String: Any] = ["version": 1, "actorId": fixture.actor.uuidString, "links": []]
        try JSONSerialization.data(withJSONObject: empty).write(to: file)
        await fixture.store.retry()
        XCTAssertNil(fixture.store.pending)
        XCTAssertEqual(fixture.client.requests, [pending, pending])
        let links = try await fixture.store.requests.loadIssuedLinks(fixture.actor)
        XCTAssertEqual(links.count, 1)
        XCTAssertEqual(links.first?.requestId, pending.requestId)
        let bytes = try Data(contentsOf: file)
        let other = UUID()
        try bytes.write(to: fixture.directory.appendingPathComponent(other.uuidString.lowercased() + "-issued-links.json"))
        do {
            _ = try await fixture.store.requests.loadIssuedLinks(other)
            XCTFail("A locator journal cannot be moved into another actor's namespace")
        } catch { XCTAssertEqual(error as? ChallengeV1Error, .storage) }
    }

    private func mount(_ fixture: InvitationRecoveryFixture, store: ChallengeV1Store? = nil) throws -> InvitationRecoveryMount {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let controller = UIHostingController(rootView: VStack(spacing: 20) {
            ChallengeLinkIssuer(store: store ?? fixture.store, row: fixture.row)
        }.padding(20))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 900)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        return InvitationRecoveryMount(window: window, controller: controller, previous: previous)
    }

    private func capture(_ mounted: InvitationRecoveryMount, name: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        mounted.controller.view.setNeedsLayout(); mounted.controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: mounted.window.bounds.size, format: format).image {
            mounted.controller.view.layer.render(in: $0.cgContext)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ").lowercased()
        let transcription = XCTAttachment(string: text); transcription.name = name + "-text"; transcription.lifetime = .keepAlways; add(transcription)
        XCTAssertTrue(text.contains("create invitation link"), "The actual issuer view must be visible, not a blank host")
        return text
    }
}

@MainActor private struct InvitationRecoveryMount {
    let window: UIWindow
    let controller: UIViewController
    let previous: UIWindow?
    func close() { window.isHidden = true; previous?.makeKeyAndVisible() }
}

@MainActor private final class InvitationRecoveryFixture {
    let actor = UUID(), id = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("invitation-recovery-" + UUID().uuidString)
    let client = InvitationRecoveryClient()
    lazy var auth = InvitationRecoveryAuth(actor)
    lazy var store = ChallengeV1Store(auth: auth, client: client, requests: ChallengeV1RequestStore(directory: directory))
    lazy var row: ChallengeV1 = {
        let start = ChallengeInstant(date: Date(timeIntervalSince1970: 1790985600))
        let end = ChallengeInstant(date: Date(timeIntervalSince1970: 1791072000))
        return ChallengeV1(id: id, creatorId: actor, policy: "friend_steps_goal_v1",
            config: .init(startDate: "2026-10-03", days: 1, timezone: "UTC", amountCents: 100,
                startsAt: start, endsAt: end, syncBy: end, correctionsBy: end, noticeDue: end),
            status: "lobby_open", revision: 1, agreementVersion: 0, serverTime: start, socialHidden: false,
            agreement: nil, members: [.init(actorId: actor, username: "Fictionalissuer", target: 100,
                selected: true, exited: false, consented: false, fact: nil)], notice: nil, reviews: [], final: nil)
    }()
    func start() async { client.row = row; store.setActor(actor); await store.refresh() }
}

@MainActor private final class InvitationRecoveryClient: ChallengeV1Client {
    var row: ChallengeV1?
    var loseFirstResponse = false
    var failNextResponse = false
    var holdResponse = false
    var held: CheckedContinuation<ChallengeV1Receipt, Error>?
    var requests: [ChallengeV1Request] = []
    var receipt = ChallengeV1Receipt(id: UUID(), token: String(repeating: "a", count: 64),
        expiresAt: ChallengeInstant(date: Date(timeIntervalSince1970: 1790985600)))
    func list(actor: UUID) async throws -> [ChallengeV1] { [try XCTUnwrap(row)] }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 { try XCTUnwrap(row) }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        requests.append(request)
        if holdResponse { return try await withCheckedThrowingContinuation { held = $0 } }
        if failNextResponse { failNextResponse = false; throw ChallengeV1Error.unavailable }
        if loseFirstResponse, requests.count == 1 { throw ChallengeV1Error.unavailable }
        if request.payload["op"]?.string == "revoke_link" { return .init(revoked: true) }
        return receipt
    }
    func finishHeld(throwing error: Error? = nil) {
        if let error { held?.resume(throwing: error) }
        else { held?.resume(returning: receipt) }
        held = nil
    }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        if name == "challenge_access_status_v1" { return ChallengeV1Access(serverTime: nil, ageConfirmed: true, betaAccess: true, suspended: false) as! T }
        if name == "challenge_community_catalog_v1" { return [ChallengeV1Community]() as! T }
        throw ChallengeV1Error.unavailable
    }
}

@MainActor private final class InvitationRecoveryAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { try XCTUnwrap(actor) }
    func signOut() async throws { actor = nil }
}
#endif
