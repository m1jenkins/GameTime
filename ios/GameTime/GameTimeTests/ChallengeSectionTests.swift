import XCTest
@testable import GameTime

@MainActor final class ChallengeSectionTests: XCTestCase {
    func testPartialFailurePreservesOnlyStillPermittedSectionsUntilMonotonicExpiry() async throws {
        let actor = UUID(); let auth = SectionAuth(actor); let client = SectionClient()
        let clock = SectionClock()
        let store = ChallengeV1Store(auth: auth, client: client, requests: ChallengeV1RequestStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), now: { clock.value })
        let active = sample(actor, name: "Prior activity", status: "active")
        let upcoming = sample(actor, name: "Prior plan", status: "scheduled")
        client.values[.active] = page(.active, [active]); client.values[.upcoming] = page(.upcoming, [upcoming])
        store.setActor(actor); await store.refresh(); XCTAssertTrue(store.fresh)
        clock.value = 30; client.fail = [.active]
        let updated = sample(actor, name: "New plan", status: "scheduled")
        client.values[.upcoming] = page(.upcoming, [updated]); await store.refresh()
        XCTAssertEqual(store.sections[.active]?.rows, [active]); XCTAssertFalse(store.isFresh(active))
        XCTAssertEqual(store.sections[.upcoming]?.rows, [updated]); XCTAssertTrue(store.isFresh(updated))
        clock.value = 61; store.purgeExpiredContent()
        XCTAssertTrue(store.sections[.active]?.rows.isEmpty == true)
        XCTAssertEqual(store.sections[.upcoming]?.rows, [updated])
        store.setActor(UUID()); XCTAssertTrue(store.challenges.isEmpty)
    }
    func testHeldRoutineRefreshKeepsFreshLayoutButDoesNotExtendVisibility() async throws {
        let actor = UUID(); let auth = SectionAuth(actor); let client = SectionClient()
        let clock = SectionClock()
        let store = ChallengeV1Store(auth: auth, client: client, requests: ChallengeV1RequestStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), now: { clock.value })
        let row = sample(actor, name: "Still current", status: "active")
        client.values[.active] = page(.active, [row]); store.setActor(actor); await store.refresh()
        clock.value = 30; client.holdSection = .active
        let refreshing = Task { await store.refresh() }
        while client.held == nil { await Task.yield() }
        XCTAssertTrue(store.isFresh(row)); XCTAssertEqual(store.sections[.active]?.rows, [row])
        clock.value = 60; store.purgeExpiredContent()
        XCTAssertFalse(store.isFresh(row)); XCTAssertTrue(store.sections[.active]?.rows.isEmpty == true)
        let activeResponse = client.held; client.held = nil; client.holdSection = .history
        activeResponse?.resume(throwing: ChallengeV1Error.unavailable)
        while client.held == nil { await Task.yield() }
        // Observe while the next section is still held, before end-of-refresh purge.
        XCTAssertTrue(store.sections[.active]?.rows.isEmpty == true)
        client.held?.resume(returning: page(.history, [])); client.held = nil
        await refreshing.value
        XCTAssertTrue(store.sections[.active]?.rows.isEmpty == true)
    }
    func testDelayedSuccessfulPageCannotRestartExpiredVisibility() async throws {
        let actor = UUID(); let auth = SectionAuth(actor); let client = SectionClient()
        let clock = SectionClock()
        let store = ChallengeV1Store(auth: auth, client: client, requests: ChallengeV1RequestStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)), now: { clock.value })
        let row = sample(actor, name: "Delayed private response", status: "active")
        client.values[.active] = page(.active, [row]); store.setActor(actor); await store.refresh()
        client.holdSection = .active
        let refreshing = Task { await store.refresh() }
        while client.held == nil { await Task.yield() }
        clock.value = 60; store.purgeExpiredContent()
        let response = client.held; client.held = nil; client.holdSection = .history
        response?.resume(returning: page(.active, [row]))
        while client.held == nil { await Task.yield() }
        XCTAssertTrue(store.sections[.active]?.rows.isEmpty == true)
        XCTAssertFalse(store.isFresh(row))
        client.held?.resume(returning: page(.history, [])); client.held = nil
        await refreshing.value
        XCTAssertTrue(store.sections[.active]?.rows.isEmpty == true)
    }
    func testSupersededCursorCannotAppendOldSocialRows() async throws {
        let actor = UUID(); let auth = SectionAuth(actor); let client = SectionClient()
        let store = ChallengeV1Store(auth: auth, client: client, requests: ChallengeV1RequestStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        let old = sample(actor, name: "Old page", status: "scheduled")
        let initial = page(.upcoming, [old], cursor: .object(["offset": .integer(1)]))
        client.values[.upcoming] = initial; store.setActor(actor); await store.refresh()
        client.holdMore = true
        let pending = Task { await store.loadMore(.upcoming) }
        while client.held == nil { await Task.yield() }
        let current = sample(actor, name: "Current page", status: "scheduled")
        client.values[.upcoming] = page(.upcoming, [current]); await store.refresh()
        client.held?.resume(returning: initial); client.held = nil; await pending.value
        XCTAssertEqual(store.sections[.upcoming]?.rows, [current])
    }
    func testBackgroundCannotReloadPrivateContentAndServerRevocationClearsIt() async throws {
        let actor = UUID(); let auth = SectionAuth(actor); let client = SectionClient()
        let store = ChallengeV1Store(auth: auth, client: client, requests: ChallengeV1RequestStore(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        client.values[.active] = page(.active, [sample(actor, name: "Private person", status: "active")])
        store.setActor(actor); await store.refresh(); let calls = client.calls
        store.hide(); await store.refresh()
        XCTAssertEqual(client.calls, calls); XCTAssertTrue(store.challenges.isEmpty)
        await store.show(); XCTAssertFalse(store.challenges.isEmpty)
        client.revoked = true; await store.refresh()
        XCTAssertNil(store.actor); XCTAssertTrue(store.challenges.isEmpty)
    }
    private func page(_ section: ChallengeV1Section, _ rows: [ChallengeV1], cursor: ChallengeJSON? = nil) -> ChallengeV1Page {
        ChallengeV1Page(section: section, projectionRevision: UUID(), serverTime: ChallengeInstant(date: Date()), expiresAt: ChallengeInstant(date: Date().addingTimeInterval(120)), rows: rows, nextCursor: cursor)
    }
    private func sample(_ actor: UUID, name: String, status: String) -> ChallengeV1 {
        let start = ChallengeInstant(date: Date()); let end = ChallengeInstant(date: Date().addingTimeInterval(86400))
        return ChallengeV1(id: UUID(), creatorId: actor, policy: "friend_steps_goal_v1", config: .init(startDate: "2026-10-03", days: 1, timezone: "UTC", amountCents: 100, startsAt: start, endsAt: end, syncBy: end, correctionsBy: end, noticeDue: end), status: status, revision: 1, agreementVersion: 0, serverTime: start, socialHidden: false, agreement: nil, members: [.init(actorId: actor, username: name, target: 100, selected: true, exited: false, consented: false, fact: nil)], notice: nil, reviews: [], final: nil)
    }
}
@MainActor private final class SectionClient: ChallengeV1Client {
    var values: [ChallengeV1Section: ChallengeV1Page] = [:]
    var fail = Set<ChallengeV1Section>(); var revoked = false; var calls = 0
    var holdSection: ChallengeV1Section?
    var holdMore = false; var held: CheckedContinuation<ChallengeV1Page, Error>?
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        calls += 1
        if revoked { throw ChallengeV1Error.accountChanged }
        if fail.contains(section) { throw ChallengeV1Error.unavailable }
        if holdMore && cursor != nil || holdSection == section { return try await withCheckedThrowingContinuation { held = $0 } }
        return values[section] ?? ChallengeV1Page(section: section, projectionRevision: UUID(), serverTime: ChallengeInstant(date: Date()), expiresAt: ChallengeInstant(date: Date().addingTimeInterval(120)), rows: [], nextCursor: nil)
    }
    func list(actor: UUID) async throws -> [ChallengeV1] { [] }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 { throw ChallengeV1Error.unavailable }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
}
@MainActor private final class SectionAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}

@MainActor private final class SectionClock { var value: TimeInterval = 0 }
