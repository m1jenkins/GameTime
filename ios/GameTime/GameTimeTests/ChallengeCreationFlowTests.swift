#if DEBUG
import SwiftUI
import UIKit
import XCTest
@testable import GameTime

/// Exercises the native create-to-invite route with an in-memory service. No
/// local or hosted server is contacted, and every person and receipt is fictional.
@MainActor final class ChallengeCreationFlowTests: XCTestCase {
    func testGoalAndAgreementRenderFromTheCreationDraft() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        await fixture.start()
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_distance_goal_v1"), zone: "America/Los_Angeles")
        await draft.initialize(store: fixture.store, health: nil)
        draft.target = "20"
        let goal = try await capture(ChallengeV1Create(store: fixture.store, draft: draft), name: "native-create-goal")
        XCTAssertTrue(goal.contains("20"))
        XCTAssertTrue(goal.contains("kilometres"))
        XCTAssertTrue(fixture.client.requests.isEmpty, "Opening and editing a goal does not save it")

        let reviewed = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_distance_goal_v1"), zone: "America/Los_Angeles")
        await reviewed.initialize(store: fixture.store, health: nil)
        reviewed.target = "20"
        fixture.client.agreement = try fixture.agreement(reviewed)
        await reviewed.review(store: fixture.store)
        XCTAssertEqual(reviewed.step, .review)
        let personal = try await capture(ChallengeV1Create(store: fixture.store, draft: reviewed), name: "native-personal-agreement")
        XCTAssertTrue(personal.contains("complete rules and agree"))
        XCTAssertFalse(reviewed.consent, "The reviewed agreement still needs explicit consent")

        let friend = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"), zone: "America/Los_Angeles")
        await friend.initialize(store: fixture.store, health: nil)
        await friend.review(store: fixture.store)
        let challenge = try await capture(ChallengeV1Create(store: fixture.store, draft: friend), name: "native-create-challenge")
        XCTAssertTrue(challenge.contains("full challenge rules"))
        XCTAssertTrue(challenge.contains("20"))
        XCTAssertTrue(fixture.client.requests.isEmpty, "Review does not create the lobby or send invitations")
    }

    func testSuccessfulFriendCreationOpensInvitationsWithoutClaimingTheyWereSent() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        await fixture.start()
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"), zone: "America/Los_Angeles")
        await draft.initialize(store: fixture.store, health: nil)
        await draft.review(store: fixture.store)
        fixture.client.row = try fixture.row(draft)
        fixture.client.receipt = .init(id: fixture.id, status: "lobby_open")
        await draft.submit(store: fixture.store)
        XCTAssertEqual(draft.receipt?.id, fixture.id)
        XCTAssertNil(fixture.store.pending)
        XCTAssertEqual(fixture.client.requests.map { $0.payload["op"]?.string }, ["create"])

        let text = try await capture(ChallengeV1Create(store: fixture.store, draft: draft), name: "native-invite-friends")
        XCTAssertTrue(text.contains("invite friends"), text)
        XCTAssertFalse(text.contains("invitations sent"), "A lobby receipt cannot report invitation delivery")
        XCTAssertFalse(text.contains("challenge ready"), "A lobby is not an agreed or scheduled challenge")
        XCTAssertEqual(fixture.client.requests.count, 1, "Opening the next screen never sends an invitation")
    }

    func testUnconfirmedCreationKeepsItsExactRequestAndDoesNotOpenInvitations() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        await fixture.start()
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_steps_goal_v1"), zone: "UTC")
        await draft.initialize(store: fixture.store, health: nil)
        await draft.review(store: fixture.store)
        fixture.client.row = try fixture.row(draft)
        fixture.client.failSubmission = true
        await draft.submit(store: fixture.store)
        let request = try XCTUnwrap(fixture.store.pending)
        XCTAssertNil(draft.receipt)
        let mounted = try mount(ChallengeV1Create(store: fixture.store, draft: draft))
        defer { mounted.close() }
        let pending = try await captureMountedSignal(mounted.window, controller: mounted.host, name: "native-create-pending", test: self)
        XCTAssertTrue(pending.contains("retry saved action"))
        XCTAssertFalse(pending.contains("exact friend username"))

        fixture.client.failSubmission = false
        fixture.client.receipt = .init(id: fixture.id, status: "lobby_open")
        await draft.submit(store: fixture.store)
        XCTAssertEqual(fixture.client.requests, [request, request])
        XCTAssertEqual(draft.receipt?.id, fixture.id)
        XCTAssertNil(fixture.store.pending)
    }

    func testMountedInvitationsRemovePeopleAfterStaleReadsAndAccountChanges() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"),
            now: try ChallengeInstant("2026-09-26T12:00:00Z").date, zone: "UTC")
        fixture.client.row = try fixture.row(draft, friends: ["Sam Rivera", "Jordan Park"])
        await fixture.start()
        let mounted = try mount(NavigationStack {
            ChallengeCreationInviteView(store: fixture.store, challengeID: fixture.id)
        }.environment(\.colorScheme, .light))
        defer { mounted.close() }
        try await Task.sleep(for: .milliseconds(250))
        let populated = try await captureMountedSignal(mounted.window, controller: mounted.host,
            name: "native-invite-populated", test: self)
        XCTAssertTrue(populated.contains("sam rivera"))
        XCTAssertTrue(populated.contains("waiting for roster selection"))

        fixture.client.failReads = true
        await fixture.store.refresh()
        await fixture.store.loadDetail(fixture.id)
        let stale = try await captureMountedSignal(mounted.window, controller: mounted.host,
            name: "native-invite-stale", test: self)
        XCTAssertTrue(stale.contains("refresh your challenge"))
        XCTAssertFalse(stale.contains("sam rivera"))
        XCTAssertFalse(stale.contains("jordan park"))
        XCTAssertFalse(stale.contains("done inviting"), "An old roster cannot be confirmed")

        fixture.client.failReads = false
        await fixture.store.refresh()
        await fixture.store.loadDetail(fixture.id)
        let restored = try await captureMountedSignal(mounted.window, controller: mounted.host,
            name: "native-invite-restored", test: self)
        XCTAssertTrue(restored.contains("sam rivera"))
        fixture.auth.actor = UUID(); fixture.store.setActor(fixture.auth.actor)
        let changed = try await captureMountedSignal(mounted.window, controller: mounted.host,
            name: "native-invite-account-changed", test: self)
        XCTAssertFalse(changed.contains("sam rivera"))
        XCTAssertFalse(changed.contains("jordan park"))
        XCTAssertFalse(changed.contains("done inviting"))
        XCTAssertTrue(fixture.client.requests.isEmpty, "Viewing and refreshing never send invitations")
    }

    func testConfirmationShowsSavedLobbyFactsWithoutInventingAgreementOrDelivery() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"),
            now: try ChallengeInstant("2026-09-26T12:00:00Z").date, zone: "America/Los_Angeles")
        fixture.client.row = try fixture.row(draft, friends: ["Sam Rivera", "Jordan Park", "Priya Shah"], ownTarget: 20_000_000)
        await fixture.start()
        for (name, scheme, size) in [("native-create-confirm", ColorScheme.light, DynamicTypeSize.large),
                                     ("native-create-confirm-dark-accessibility", .dark, .accessibility3)] {
            let text = try await capture(NavigationStack {
                ChallengeCreationInviteView(store: fixture.store, challengeID: fixture.id, showingConfirmation: true)
            }, name: name, scheme: scheme, size: size)
            XCTAssertTrue(text.contains("your challenge is saved"))
            XCTAssertTrue(text.contains("everyone still needs to review and agree"))
            XCTAssertTrue(text.contains("sam rivera"))
            XCTAssertTrue(text.contains("view lobby"))
            XCTAssertFalse(text.contains("invitations sent"))
            XCTAssertFalse(text.contains("challenge ready"))
        }
        XCTAssertTrue(fixture.client.requests.isEmpty, "Confirmation does not select a roster, freeze rules or grant consent")
    }

    func testInvitationAcknowledgmentRequiresItsCompleteLobbyReceipt() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        try await fixture.startLobby()
        let draft = ChallengeCreationInvitationDraft(challengeID: fixture.id)
        for receipt in [ChallengeV1Receipt(saved: true),
                        .init(id: UUID(), revision: 2, status: "lobby_open"),
                        .init(id: fixture.id, status: "lobby_open"),
                        .init(id: fixture.id, revision: 0, status: "lobby_open"),
                        .init(id: fixture.id, revision: 2, status: "scheduled")] {
            fixture.client.receipt = receipt
            draft.username = "  @Sam_Rivera  "
            let accepted = await draft.invite(store: fixture.store)
            XCTAssertFalse(accepted)
            XCTAssertFalse(draft.invitationSaved)
            XCTAssertEqual(draft.username, "  @Sam_Rivera  ", "An unrelated or incomplete receipt cannot clear entered text")
        }
        fixture.client.receipt = .init(id: fixture.id, revision: 2, status: "lobby_open")
        let accepted = await draft.invite(store: fixture.store)
        XCTAssertTrue(accepted)
        XCTAssertTrue(draft.invitationSaved)
        XCTAssertEqual(draft.username, "")
        XCTAssertTrue(fixture.client.requests.allSatisfy {
            $0.payload["op"]?.string == "invite"
                && $0.payload["username"]?.string == "Sam_Rivera"
                && $0.payload["id"]?.string == fixture.id.uuidString.lowercased()
                && $0.payload["revision"]?.integer == 1
        }, "The action sends only an exact username against the displayed lobby revision")
    }

    func testInvitationRetryUsesExactRequestAndPreservesNewerEnteredName() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        try await fixture.startLobby()
        let draft = ChallengeCreationInvitationDraft(challengeID: fixture.id)
        draft.username = "Sam_Rivera"
        fixture.client.failSubmission = true
        let first = await draft.invite(store: fixture.store)
        XCTAssertFalse(first)
        XCTAssertFalse(draft.invitationSaved)
        let request = try XCTUnwrap(fixture.store.pending)
        XCTAssertEqual(draft.username, "Sam_Rivera")

        draft.username = "Priya_Shah"
        let blocked = await draft.invite(store: fixture.store)
        XCTAssertFalse(blocked)
        XCTAssertEqual(fixture.client.requests, [request], "A pending invitation cannot be replaced by a new username")
        fixture.client.failSubmission = false
        fixture.client.receipt = .init(id: fixture.id, revision: 2, status: "lobby_open")
        let retried = await draft.retry(store: fixture.store)
        XCTAssertTrue(retried)
        XCTAssertTrue(draft.invitationSaved)
        XCTAssertEqual(draft.username, "Priya_Shah", "Completing the older action cannot discard a new name")
        XCTAssertEqual(fixture.client.requests, [request, request])
        XCTAssertNil(fixture.store.pending)
    }

    func testRetryCannotAcknowledgeAnotherActionOrAnotherChallenge() async throws {
        for otherChallenge in [false, true] {
            let fixture = CreationFlowFixture()
            defer { fixture.clean() }
            try await fixture.startLobby()
            let draft = ChallengeCreationInvitationDraft(challengeID: fixture.id)
            draft.username = "Sam_Rivera"
            let requestID = otherChallenge ? UUID() : fixture.id
            fixture.client.failSubmission = true
            await fixture.store.submit(op: otherChallenge ? "invite" : "target", fields: [
                "id": .string(requestID.uuidString.lowercased()), "revision": .integer(1),
                "username": .string("Sam_Rivera"), "target": .integer(20_000_000)
            ])
            let pending = try XCTUnwrap(fixture.store.pending)
            fixture.client.failSubmission = false
            fixture.client.receipt = .init(id: requestID, revision: 2, status: "lobby_open")
            let acknowledged = await draft.retry(store: fixture.store)
            XCTAssertFalse(acknowledged)
            XCTAssertFalse(draft.invitationSaved)
            XCTAssertEqual(draft.username, "Sam_Rivera")
            XCTAssertEqual(fixture.client.requests, [pending, pending])
        }
    }

    func testAccountChangeWhileInvitingCannotAcknowledgeOrEraseTheOldRequest() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        try await fixture.startLobby()
        fixture.client.holdSubmission = true
        let draft = ChallengeCreationInvitationDraft(challengeID: fixture.id)
        draft.username = "Sam_Rivera"
        let task = Task { await draft.invite(store: fixture.store) }
        defer { fixture.client.held?.resume(throwing: ChallengeV1Error.unavailable); fixture.client.held = nil }
        let deadline = Date().addingTimeInterval(2)
        while fixture.client.held == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        let response = try XCTUnwrap(fixture.client.held)
        fixture.client.held = nil
        let request = try XCTUnwrap(fixture.store.pending)
        fixture.auth.actor = UUID(); fixture.store.setActor(fixture.auth.actor)
        response.resume(returning: .init(id: fixture.id, revision: 2, status: "lobby_open"))
        let acknowledged = await task.value
        XCTAssertFalse(acknowledged)
        XCTAssertFalse(draft.invitationSaved)
        XCTAssertNil(fixture.store.lastReceipt)
        let saved = try await fixture.store.requests.load(fixture.actor)
        XCTAssertEqual(saved, request, "The old account retains its recoverable request")
        draft.reset()
        XCTAssertEqual(draft.username, "")
        XCTAssertFalse(draft.invitationSaved)
    }

    private func capture<V: View>(_ view: V, name: String,
                                 scheme: ColorScheme = .light, size: DynamicTypeSize = .large) async throws -> String {
        let mounted = try mount(view.environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size))
        defer { mounted.close() }
        try await Task.sleep(for: .milliseconds(250))
        return try await captureMountedSignal(mounted.window, controller: mounted.host, name: name, test: self)
    }

    private func mount<V: View>(_ view: V) throws -> CreationFlowMounted {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: AnyView(view.frame(width: 390, height: 844)))
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        return .init(window: window, host: host, previous: previous)
    }
}

@MainActor private struct CreationFlowMounted {
    let window: UIWindow
    let host: UIHostingController<AnyView>
    let previous: UIWindow?
    func close() { window.isHidden = true; previous?.makeKeyAndVisible() }
}

@MainActor private final class CreationFlowFixture {
    let actor = UUID(), id = UUID()
    let client = CreationFlowClient()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("creation-flow-" + UUID().uuidString)
    lazy var auth = CreationFlowAuth(actor)
    lazy var store = ChallengeV1Store(auth: auth, client: client, requests: .init(directory: directory))

    func start() async { store.setActor(actor); await store.refresh() }
    func startLobby() async throws {
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"),
            now: try ChallengeInstant("2026-09-26T12:00:00Z").date, zone: "UTC")
        client.row = try row(draft)
        await start()
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func agreement(_ draft: ChallengeCreationDraft) throws -> ChallengeV1.Agreement {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let config = try JSONDecoder().decode(ChallengeJSON.self, from: encoder.encode(XCTUnwrap(draft.window)))
        return .init(digest: String(repeating: "a", count: 64), terms: .object(["config": config]))
    }
    func row(_ draft: ChallengeCreationDraft, friends: [String] = [], ownTarget: Int? = nil) throws -> ChallengeV1 {
        let members = [ChallengeV1.Member(actorId: actor, username: "Fictional You", target: ownTarget,
            selected: true, exited: false, consented: false, fact: nil)] + friends.map {
                ChallengeV1.Member(actorId: UUID(), username: $0, target: nil,
                    selected: false, exited: false, consented: false, fact: nil)
            }
        let result = ChallengeV1(id: id, creatorId: actor, policy: draft.policy.id,
            config: try XCTUnwrap(draft.window), status: "lobby_open", revision: 1, agreementVersion: 0,
            serverTime: try ChallengeInstant("2026-09-26T12:00:00Z"), socialHidden: false, agreement: nil,
            members: members,
            notice: nil, reviews: [], final: nil)
        try result.validate(actor: actor)
        return result
    }
}

@MainActor private final class CreationFlowClient: ChallengeV1Client {
    var row: ChallengeV1?
    var agreement: ChallengeV1.Agreement?
    var receipt = ChallengeV1Receipt(saved: true)
    var requests: [ChallengeV1Request] = []
    var failSubmission = false
    var failReads = false
    var holdSubmission = false
    var held: CheckedContinuation<ChallengeV1Receipt, Error>?
    func list(actor: UUID) async throws -> [ChallengeV1] {
        if failReads { throw ChallengeV1Error.unavailable }
        return row.map { [$0] } ?? []
    }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 {
        guard !failReads, let row, row.id == id else { throw ChallengeV1Error.unavailable }
        return row
    }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        requests.append(request)
        if failSubmission { throw ChallengeV1Error.unavailable }
        if holdSubmission { return try await withCheckedThrowingContinuation { held = $0 } }
        return receipt
    }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        .init(status: "cancelled_request")
    }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        let data: Data
        switch name {
        case "challenge_access_status_v1":
            data = Data(#"{"serverTime":"2026-09-26T12:00:00Z","ageConfirmed":true,"betaAccess":true,"suspended":false}"#.utf8)
        case "challenge_community_catalog_v1": data = Data("[]".utf8)
        case "challenge_personal_preview_v1": data = try JSONEncoder().encode(XCTUnwrap(agreement))
        default: throw ChallengeV1Error.unavailable
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

@MainActor private final class CreationFlowAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { try XCTUnwrap(actor) }
    func signOut() async throws { actor = nil }
}
#endif
