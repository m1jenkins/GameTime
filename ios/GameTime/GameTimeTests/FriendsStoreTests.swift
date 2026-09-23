import XCTest
@testable import GameTime

@MainActor final class FriendsStoreTests: XCTestCase {
    private let serverTime = "2026-09-22T16:41:00.123456+00:00"

    // MARK: Transport

    func testListDecodesServerShapeAndRejectsSelfOrDuplicates() async throws {
        let actor = UUID(), sam = UUID(), taylor = UUID()
        var body = """
        {"server_time":"\(serverTime)",
         "friends":[{"id":"\(sam.uuidString.lowercased())","username":"samr","display_name":"Sam Rivera","since":"2026-09-20T10:00:00+00:00","you_asked":true}],
         "incoming":[{"id":"\(taylor.uuidString.lowercased())","username":"taylork","display_name":"Taylor Kim","sent_at":"2026-09-22T09:00:00+00:00"}],
         "outgoing":[],"blocked":[]}
        """
        var calls: [String] = []
        let client = SupabaseChallengeV1Client(url: URL(string: "http://127.0.0.1:58321")!,
            binding: { .init(actorID: actor, identity: "session") },
            rpc: { name, _ in calls.append(name); return Data(body.utf8) })
        let list = try await client.friendList(actor: actor)
        XCTAssertEqual(calls, ["friend_list_v1"])
        XCTAssertEqual(list.friends.first?.displayName, "Sam Rivera")
        XCTAssertEqual(list.friends.first?.youAsked, true)
        XCTAssertNotNil(list.friends.first?.since)
        XCTAssertEqual(list.incoming.first?.username, "taylork")
        XCTAssertNotNil(list.incoming.first?.sentAt)

        body = body.replacingOccurrences(of: taylor.uuidString.lowercased(), with: actor.uuidString.lowercased())
        do { _ = try await client.friendList(actor: actor); XCTFail("You never appear in your own list") }
        catch { XCTAssertEqual(error as? ChallengeV1Error, .invalidResponse) }

        body = body.replacingOccurrences(of: actor.uuidString.lowercased(), with: sam.uuidString.lowercased())
        do { _ = try await client.friendList(actor: actor); XCTFail("A person appears once") }
        catch { XCTAssertEqual(error as? ChallengeV1Error, .invalidResponse) }
    }

    func testCommandsSendOnlyRequestIDSubjectAndReportReason() async throws {
        let actor = UUID(), person = FriendPerson(id: UUID(), username: "drew_p", displayName: "Drew Park")
        var sent: [(String, [String: Any])] = []
        var reply = #"{"state":"outgoing"}"#
        let client = SupabaseChallengeV1Client(url: URL(string: "http://127.0.0.1:58321")!,
            binding: { .init(actorID: actor, identity: "session") },
            rpc: { name, data in
                sent.append((name, try JSONSerialization.jsonObject(with: data) as! [String: Any]))
                return Data(reply.utf8)
            })
        let request = FriendCommand(actor: actor, op: .request, person: person)
        _ = try await client.friendCommand(request)
        XCTAssertEqual(sent.last?.0, "friend_request_v1")
        XCTAssertEqual(Set(sent.last!.1.keys), ["p_request_id", "p_subject"])
        XCTAssertEqual(sent.last?.1["p_request_id"] as? String, request.requestId.uuidString.lowercased())
        XCTAssertEqual(sent.last?.1["p_subject"] as? String, person.id.uuidString.lowercased())

        reply = #"{"saved":true}"#
        _ = try await client.friendCommand(FriendCommand(actor: actor, op: .report, person: person, reason: .unwantedContact))
        XCTAssertEqual(sent.last?.0, "friend_report_v1")
        XCTAssertEqual(sent.last?.1["p_reason"] as? String, "unwanted_contact")

        reply = #"{"state":"none"}"#
        do { _ = try await client.friendCommand(FriendCommand(actor: actor, op: .accept, person: person)); XCTFail("Wrong answer") }
        catch { XCTAssertEqual(error as? ChallengeV1Error, .invalidResponse) }

        XCTAssertThrowsError(try FriendCommand(actor: actor, op: .block, person: person, reason: .username).body)
        XCTAssertThrowsError(try FriendCommand(actor: actor, op: .report, person: person).body)
    }

    func testLookupRateLimitBodyIsAnErrorNotAResult() async throws {
        let actor = UUID()
        let client = SupabaseChallengeV1Client(url: URL(string: "http://127.0.0.1:58321")!,
            binding: { .init(actorID: actor, identity: "session") },
            rpc: { _, _ in Data(#"{"message":"friend_lookup_rate_limited"}"#.utf8) })
        do { _ = try await client.friendLookup("samr", actor: actor); XCTFail("Rate limit is not a lookup result") }
        catch { XCTAssertEqual(error as? ChallengeV1Error, .server("friend_lookup_rate_limited")) }
    }

    func testClosedConfigurationSendsNothing() async throws {
        let actor = UUID(); var calls = 0
        let client = SupabaseChallengeV1Client(url: URL(string: "https://example.com")!,
            binding: { .init(actorID: actor, identity: "session") }, rpc: { _, _ in calls += 1; return Data() })
        do { _ = try await client.friendList(actor: actor); XCTFail("Must not send") } catch {}
        XCTAssertEqual(calls, 0)
    }

    // MARK: Store

    func testAcceptMovesRequestToFriendsAndSaysSo() async throws {
        let (store, client, actor, _) = makeStore()
        client.list.incoming = [taylor]
        store.setActor(actor); await store.refresh()
        XCTAssertEqual(store.state, .loaded)
        XCTAssertTrue(store.canAct)

        client.afterCommand = { list in list.incoming = []; list.friends = [self.friend(self.taylor, youAsked: false)] }
        let ok = await store.perform(.accept, person: taylor)
        XCTAssertTrue(ok)
        XCTAssertEqual(store.friends.map(\.id), [taylor.id])
        XCTAssertTrue(store.incoming.isEmpty)
        XCTAssertEqual(store.notice, "You and Taylor are now friends.")
        XCTAssertNil(store.pending)
        XCTAssertEqual(client.commands.map(\.op), [.accept])
    }

    func testLostResponseKeepsTheSameRequestForRetry() async throws {
        let (store, client, actor, auth) = makeStore()
        client.list.incoming = [taylor]
        store.setActor(actor); await store.refresh()

        client.failNext = .unavailable
        let first = await store.perform(.accept, person: taylor)
        XCTAssertFalse(first)
        let saved = try XCTUnwrap(store.pending)
        XCTAssertNotNil(store.actionError)
        XCTAssertFalse(store.canAct)
        XCTAssertFalse(store.actionError!.contains("_"))

        // A new store on the same phone finds the saved change.
        let reopened = FriendsStore(auth: auth, client: client, journal: store.journal)
        reopened.setActor(actor); await reopened.refresh()
        XCTAssertEqual(reopened.pending, saved)

        let retried = await reopened.retry()
        XCTAssertTrue(retried)
        XCTAssertEqual(client.commands.map(\.requestId), [saved.requestId, saved.requestId])
        XCTAssertNil(reopened.pending)
        let entry = try await store.journal.load(actor)
        XCTAssertNil(entry.pending)
    }

    func testServerRefusalClearsTheSavedChangeAndKeepsItsCode() async throws {
        let (store, client, actor, _) = makeStore()
        store.setActor(actor); await store.refresh()
        client.failNext = .server("friend_incoming_request_exists")
        let ok = await store.perform(.request, person: taylor)
        XCTAssertFalse(ok)
        XCTAssertNil(store.pending)
        XCTAssertEqual(store.actionErrorCode, "friend_incoming_request_exists")
        XCTAssertEqual(store.actionError, "taylork already sent you a request. Accept it to become friends.")
        let entry = try await store.journal.load(actor)
        XCTAssertNil(entry.pending)
        XCTAssertTrue(store.canAct)
    }

    func testAccountSwitchDropsAnInFlightList() async throws {
        let (store, client, actor, auth) = makeStore()
        client.list.friends = [friend(taylor, youAsked: false)]
        store.setActor(actor)
        client.holdList = true
        let old = Task { await store.refresh() }
        while client.held == nil { await Task.yield() }
        let other = UUID()
        auth.actor = other
        store.setActor(other)
        client.held?.resume(); client.held = nil
        await old.value
        XCTAssertEqual(store.actor, other)
        XCTAssertNil(store.list)
    }

    func testSignedOutSessionClearsTheList() async throws {
        let (store, client, actor, auth) = makeStore()
        client.list.friends = [friend(taylor, youAsked: false)]
        store.setActor(actor); await store.refresh()
        XCTAssertFalse(store.friends.isEmpty)
        auth.actor = nil
        await store.refresh()
        XCTAssertNil(store.actor)
        XCTAssertNil(store.list)
    }

    func testFailedRefreshKeepsTheLastListButBlocksChanges() async throws {
        let (store, client, actor, _) = makeStore()
        client.list.incoming = [taylor]
        store.setActor(actor); await store.refresh()
        client.failList = true
        await store.refresh()
        XCTAssertEqual(store.state, .offline)
        XCTAssertEqual(store.incoming.map(\.id), [taylor.id])
        XCTAssertFalse(store.canAct)
        XCTAssertNotNil(store.savedAt)
    }

    func testRecentlyAcceptedRowsAreYourRequestsAndStayDismissed() async throws {
        let (store, client, actor, auth) = makeStore()
        let morgan = FriendPerson(id: UUID(), username: "morgand", displayName: "Morgan Diaz")
        let old = FriendPerson(id: UUID(), username: "jordanb", displayName: "Jordan Blake")
        client.list.friends = [
            friend(morgan, youAsked: true, since: "2026-09-22T08:00:00+00:00"),
            friend(taylor, youAsked: false, since: "2026-09-22T08:00:00+00:00"),
            friend(old, youAsked: true, since: "2026-09-01T08:00:00+00:00"),
        ]
        store.setActor(actor); await store.refresh()
        XCTAssertEqual(store.recentlyAccepted.map(\.id), [morgan.id])
        await store.dismissAccepted(store.recentlyAccepted[0])
        XCTAssertTrue(store.recentlyAccepted.isEmpty)

        let reopened = FriendsStore(auth: auth, client: client, journal: store.journal)
        reopened.setActor(actor); await reopened.refresh()
        XCTAssertTrue(reopened.recentlyAccepted.isEmpty)
        // Journals are per account.
        let other = try await store.journal.load(UUID())
        XCTAssertEqual(other, FriendJournal.Entry())
    }

    func testLookupNeedsAnExactUsernameAndHidesUnavailablePeople() async throws {
        let (store, client, actor, _) = makeStore()
        store.setActor(actor)
        let invalid = await store.lookup("@a b")
        XCTAssertEqual(invalid, .notFound("a b"))
        XCTAssertTrue(client.lookups.isEmpty)

        client.lookupResult = FriendLookup(found: false)
        let missing = await store.lookup(" @Drew_P ")
        XCTAssertEqual(missing, .notFound("Drew_P"))
        XCTAssertEqual(client.lookups, ["Drew_P"])

        client.lookupResult = FriendLookup(found: true, id: taylor.id, username: "taylork", displayName: "Taylor Kim", relation: .incoming)
        let found = await store.lookup("taylork")
        XCTAssertEqual(found, .found(taylor, .incoming))

        client.failNext = .server("friend_lookup_rate_limited")
        let limited = await store.lookup("taylork")
        XCTAssertEqual(limited, .failed("Too many searches. Wait a minute and try again."))
    }

    func testEveryFriendErrorIsASentenceWithANextStep() {
        for code in ["friend_request_limit", "friend_lookup_rate_limited", "friend_age_required", "friend_account_restricted",
                     "friend_request_already_sent", "friend_already_friends", "friend_unavailable", "friend_state_changed",
                     "friend_rate_limited", "friend_incoming_request_exists"] {
            let text = FriendsCopy.message(for: ChallengeV1Error.server(code), username: "taylork")
            XCTAssertFalse(text.contains(code), code)
            XCTAssertFalse(text.contains("friend_"), code)
        }
        XCTAssertEqual(FriendsCopy.message(for: ChallengeV1Error.server("friend_new_thing")),
                       "We couldn’t finish that. Refresh and try again. Reference: friend_new_thing")
        XCTAssertFalse(FriendsCopy.message(for: ChallengeV1Error.server("<b>odd</b>")).contains("Reference"))
    }

    // MARK: Helpers

    private let taylor = FriendPerson(id: UUID(uuidString: "77777777-7777-4777-8777-777777777777")!, username: "taylork", displayName: "Taylor Kim")

    private func friend(_ person: FriendPerson, youAsked: Bool, since: String = "2026-09-22T09:00:00+00:00") -> FriendPerson {
        var copy = person; copy.youAsked = youAsked; copy.since = try! ChallengeInstant(since); return copy
    }

    private func makeStore() -> (FriendsStore, FakeFriendsClient, UUID, FriendsTestAuth) {
        let actor = UUID()
        let client = FakeFriendsClient(serverTime: try! ChallengeInstant(serverTime))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let auth = FriendsTestAuth(actor)
        let store = FriendsStore(auth: auth, client: client, journal: FriendJournal(directory: dir))
        return (store, client, actor, auth)
    }
}

@MainActor private final class FriendsTestAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor ?? UUID() }
    func signOut() async throws {}
}

@MainActor private final class FakeFriendsClient: FriendCommandsClient {
    var list: FriendList
    var commands: [FriendCommand] = []
    var lookups: [String] = []
    var lookupResult = FriendLookup(found: false)
    var failNext: ChallengeV1Error?
    var failList = false
    var holdList = false
    var held: CheckedContinuation<Void, Never>?
    var afterCommand: ((inout FriendList) -> Void)?

    init(serverTime: ChallengeInstant) {
        list = FriendList(serverTime: serverTime, friends: [], incoming: [], outgoing: [], blocked: [])
    }
    func friendList(actor: UUID) async throws -> FriendList {
        if holdList { holdList = false; await withCheckedContinuation { held = $0 } }
        if failList { throw ChallengeV1Error.unavailable }
        return list
    }
    func friendLookup(_ username: String, actor: UUID) async throws -> FriendLookup {
        lookups.append(username)
        if let failure = failNext { failNext = nil; throw failure }
        return lookupResult
    }
    func friendCommand(_ command: FriendCommand) async throws -> FriendReceipt {
        commands.append(command)
        if let failure = failNext { failNext = nil; throw failure }
        afterCommand?(&list); afterCommand = nil
        switch command.op {
        case .request: return .init(state: "outgoing")
        case .accept: return .init(state: "friends")
        case .block: return .init(state: "blocked")
        case .report: return .init(saved: true)
        default: return .init(state: "none")
        }
    }
}
