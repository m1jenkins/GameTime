#if DEBUG
import Supabase
import XCTest
@testable import GameTime

/// Friends Phase 4: the app's own FriendsStore, friend client and availability
/// decoding against a disposable local stack with the build 1 settings.
/// scripts/friends-native-smoke.sh writes the private manifest this reads and
/// removes it afterwards; without it the test is skipped. Fictional accounts
/// only, on a loopback URL.
@MainActor final class FriendsNativeSmokeTests: XCTestCase {
    struct Config: Decodable {
        struct Actor: Decodable { let id: UUID; let email: String; let username: String }
        let url: URL; let key: String; let password: String; let actors: [Actor]
    }
    struct Account {
        let actor: Config.Actor
        let client: SupabaseChallengeV1Client
        let store: FriendsStore
    }

    private func config() throws -> Config {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("tmp/friends-native-smoke.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw XCTSkip("Run scripts/friends-native-smoke.sh to create the local friends manifest.")
        }
        let config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: file))
        XCTAssertTrue(SupabaseWeeklyClient.isExplicitLoopback(config.url))
        XCTAssertEqual(config.actors.count, 4)
        return config
    }

    private func signIn(_ config: Config, _ index: Int, directory: URL) async throws -> Account {
        let actor = config.actors[index]
        let sdk = SupabaseClient(supabaseURL: config.url, supabaseKey: config.key, options: .init(
            auth: .init(storage: ChallengeMemoryAuthStorage(), autoRefreshToken: false,
                        emitLocalSessionAsInitialSession: true)))
        _ = try await sdk.auth.signIn(email: actor.email, password: config.password)
        let client = SupabaseChallengeV1Client(sdk: sdk, url: config.url, key: config.key)
        let store = FriendsStore(auth: SupabaseAuthClient(client: sdk), client: client,
                                 journal: FriendJournal(directory: directory.appendingPathComponent("\(index)")))
        store.setActor(actor.id)
        await store.refresh()
        XCTAssertEqual(store.state, .loaded, store.loadError ?? "The friends list didn't load")
        return Account(actor: actor, client: client, store: store)
    }

    private func find(_ account: Account, _ username: String) async throws -> FriendPerson {
        guard case .found(let person, _)? = await account.store.lookup(username) else {
            throw XCTSkip("Unreachable: lookup of \(username) failed")
        }
        return person
    }

    func testFriendsStoreAgainstTheLocalServer() async throws {
        let config = try config()
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ana = try await signIn(config, 0, directory: directory)
        let ben = try await signIn(config, 1, directory: directory)
        let cal = try await signIn(config, 2, directory: directory)
        let looker = try await signIn(config, 3, directory: directory)

        // What the server offers, decoded as the app decodes it.
        let availability = try await ana.client.read("challenge_availability_v1", actor: ana.actor.id,
                                                     as: ChallengeV1Availability.self)
        XCTAssertTrue(availability.restricted)
        XCTAssertTrue(availability.accountMode)
        XCTAssertEqual(availability.links, false)
        XCTAssertEqual(availability.community, false)
        XCTAssertEqual(availability.creatablePolicies, [
            "friend_steps_goal_v1", "friend_exercise_goal_v1", "friend_distance_goal_v1", "friend_timed_goal_v1",
            "personal_steps_goal_v1", "personal_distance_goal_v1"])

        // Request, a crossed request, accept.
        guard case .found(let benPerson, .none)? = await ana.store.lookup("@" + ben.actor.username) else {
            return XCTFail("Ana finds Ben by exact username")
        }
        XCTAssertEqual(benPerson.username, ben.actor.username, "A mixed-case username comes back unchanged")
        let sent = await ana.store.perform(.request, person: benPerson)
        XCTAssertTrue(sent, ana.store.actionError ?? "")
        XCTAssertEqual(ana.store.outgoing.map(\.id), [ben.actor.id])
        XCTAssertNil(ana.store.pending, "A confirmed request leaves nothing to retry")
        await ben.store.refresh()
        let anaPerson = try XCTUnwrap(ben.store.incoming.first)
        XCTAssertEqual(anaPerson.id, ana.actor.id)
        let crossed = await ben.store.perform(.request, person: anaPerson)
        XCTAssertFalse(crossed)
        XCTAssertEqual(ben.store.actionErrorCode, "friend_incoming_request_exists")
        XCTAssertEqual(ben.store.actionError, "\(ana.actor.username) already sent you a request. Accept it to become friends.")
        ben.store.clearActionError()
        let accepted = await ben.store.perform(.accept, person: anaPerson)
        XCTAssertTrue(accepted, ben.store.actionError ?? "")
        await ana.store.refresh()
        XCTAssertEqual(ana.store.friends.map(\.id), [ben.actor.id])
        XCTAssertEqual(ana.store.recentlyAccepted.map(\.id), [ben.actor.id], "Ana's Home row: Ben accepted")
        XCTAssertEqual(ben.store.friends.map(\.id), [ana.actor.id])
        XCTAssertTrue(ben.store.recentlyAccepted.isEmpty, "Only the sender sees the accepted row")

        // A silent decline, then block, unblock and report.
        let calPerson = try await find(ana, cal.actor.username)
        let requested = await ana.store.perform(.request, person: calPerson)
        XCTAssertTrue(requested)
        await cal.store.refresh()
        let declined = await cal.store.perform(.decline, person: try XCTUnwrap(cal.store.incoming.first))
        XCTAssertTrue(declined)
        await ana.store.refresh()
        XCTAssertTrue(ana.store.outgoing.isEmpty, "A declined request leaves the sender's list")
        let blocked = await ana.store.perform(.block, person: calPerson)
        XCTAssertTrue(blocked)
        XCTAssertEqual(ana.store.blocked.map(\.id), [cal.actor.id])
        guard case .notFound? = await cal.store.lookup(ana.actor.username) else {
            return XCTFail("A blocked person can't find the account that blocked them")
        }
        let unblocked = await ana.store.perform(.unblock, person: calPerson)
        XCTAssertTrue(unblocked)
        XCTAssertTrue(ana.store.blocked.isEmpty)
        XCTAssertFalse(ana.store.friends.contains { $0.id == cal.actor.id })
        let reported = await ana.store.perform(.report, person: calPerson, reason: .unwantedContact)
        XCTAssertTrue(reported, ana.store.actionError ?? "")

        // A stale action gets the refreshed-list sentence.
        let staleCancel = await ana.store.perform(.cancel, person: benPerson)
        XCTAssertFalse(staleCancel)
        XCTAssertEqual(ana.store.actionErrorCode, "friend_state_changed")
        XCTAssertEqual(ana.store.state, .loaded, "The refusal refreshed the list")

        // The lookup limit reaches the person as a sentence.
        var outcome: FriendsStore.LookupOutcome?
        for index in 0..<31 { outcome = await looker.store.lookup("nobody_\(index)") }
        XCTAssertEqual(outcome, .failed("Too many searches. Wait a minute and try again."))
    }
}
#endif
