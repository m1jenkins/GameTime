import XCTest
#if DEBUG
import SwiftUI
import UIKit
#endif
@testable import GameTime

@MainActor final class ChallengeProfileTests: XCTestCase {
    private let actor = UUID()
    private let now: TimeInterval = 100

    func testUpcomingPersonalGoalUsesChallengeRecords() throws {
        let goal = try row(status: "scheduled")
        let snapshot = snapshot([goal])
        XCTAssertEqual(snapshot.availability, .complete)
        XCTAssertEqual(snapshot.upcoming.map(\.id), [goal.id])
        XCTAssertEqual(snapshot.countText(snapshot.upcoming.count), "1")
        XCTAssertEqual(snapshot.featured?.id, goal.id)
        XCTAssertEqual(snapshot.active.count, 0)
        XCTAssertEqual(snapshot.wins, 0)
        XCTAssertEqual(snapshot.losses, 0)
    }

    func testActiveReviewFinishedAndExitHaveDistinctCounts() throws {
        let rows = try [row(status: "active"), row(status: "review"), row(status: "final"), row(status: "active", exited: true)]
        let snapshot = snapshot(rows)
        XCTAssertEqual(snapshot.active.count, 2)
        XCTAssertEqual(snapshot.finished.count, 2)
        XCTAssertEqual(snapshot.upcoming.count, 0)
    }

    func testOnlyCompleteEmptyReadsEstablishZero() {
        let complete = snapshot([])
        XCTAssertEqual(complete.countText(0), "0")
        let missing = ChallengeProfileSnapshot(actor: actor, sections: [:], now: now)
        XCTAssertEqual(missing.availability, .unavailable)
        XCTAssertEqual(missing.countText(0), "—")
        var partial = states([])
        partial[.history] = nil
        let notLoaded = ChallengeProfileSnapshot(actor: actor, sections: partial, now: now)
        XCTAssertEqual(notLoaded.availability, .partial)
        XCTAssertEqual(notLoaded.countText(0), "—")
    }

    func testPaginationCannotPresentLoadedCountsAsLifetimeTotals() throws {
        var pages = states([try row(status: "scheduled")])
        pages[.history]?.cursor = .object(["page": .integer(2)])
        let snapshot = ChallengeProfileSnapshot(actor: actor, sections: pages, now: now)
        XCTAssertEqual(snapshot.availability, .partial)
        XCTAssertEqual(snapshot.countText(snapshot.upcoming.count), "1+")
        XCTAssertEqual(snapshot.countText(0), "—")
        XCTAssertEqual(snapshot.sectionsWithMore, [.history])
        XCTAssertFalse(snapshot.scopeText.localizedCaseInsensitiveContains("all saved"))
    }

    func testFailedReadIsStaleAndExpiredRowsDisappear() throws {
        var pages = states([try row(status: "active")])
        pages[.active]?.fresh = false
        pages[.active]?.error = "Please refresh."
        let stale = ChallengeProfileSnapshot(actor: actor, sections: pages, now: now + 20)
        XCTAssertEqual(stale.availability, .stale)
        XCTAssertEqual(stale.rows.count, 1)
        XCTAssertEqual(stale.countText(1), "—")
        let expired = ChallengeProfileSnapshot(actor: actor, sections: pages, now: now + 60)
        XCTAssertEqual(expired.availability, .unavailable)
        XCTAssertTrue(expired.rows.isEmpty)
    }

    func testInitialPartialReadStaysPartialUntilAggregateCanBeConfirmed() throws {
        let goal = try row(status: "scheduled")
        var pages = states([goal])
        pages[.history] = nil
        let loading = ChallengeProfileSnapshot(actor: actor, sections: pages, now: now, aggregateFresh: false)
        XCTAssertEqual(loading.availability, .partial)
        XCTAssertEqual(loading.countText(0), "—")
        let initial = ChallengeProfileSnapshot(actor: actor, sections: [:], now: now, aggregateFresh: false)
        XCTAssertEqual(initial.availability, .unavailable)
    }

    func testUncertainMutationInvalidatesCountsEvenWhenPagesRemainFresh() async throws {
        let client = ProfileClient(first: try row(status: "final"), second: try row(status: "final"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ChallengeV1Store(auth: ProfileAuth(actor: actor), client: client,
            requests: .init(directory: folder), now: { 100 })
        store.setActor(actor)
        await store.refresh()
        XCTAssertTrue(store.fresh, "A remaining cursor does not invalidate fresh pages")
        XCTAssertEqual(store.profileSnapshot.availability, .partial)
        await store.loadMore(.history)
        XCTAssertEqual(store.profileSnapshot.availability, .complete)
        _ = await store.submit(op: "leave")
        XCTAssertNotNil(store.pending)
        XCTAssertFalse(store.fresh)
        XCTAssertTrue(store.sections.values.allSatisfy(\.fresh))
        XCTAssertEqual(store.profileSnapshot.availability, .stale)
        XCTAssertEqual(store.profileSnapshot.countText(0), "—")
        XCTAssertEqual(store.profileSnapshot.countText(2), "—")
    }

    func testSuspensionFilteringCannotBecomeACompleteZero() async throws {
        let client = ProfileClient(first: try row(status: "final"), second: try row(status: "final"))
        client.suspended = true
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ChallengeV1Store(auth: ProfileAuth(actor: actor), client: client,
            requests: .init(directory: folder), now: { 100 })
        store.setActor(actor)
        await store.refresh()
        XCTAssertEqual(store.access?.suspended, true)
        XCTAssertFalse(store.fresh)
        XCTAssertTrue(store.profileSnapshot.rows.isEmpty)
        XCTAssertEqual(store.profileSnapshot.availability, .stale)
        XCTAssertEqual(store.profileSnapshot.countText(0), "—")
    }

    func testDuplicatesCountOnceAndUseLatestRevision() throws {
        let id = UUID()
        let old = try row(id: id, status: "scheduled", revision: 1)
        let current = try row(id: id, status: "active", revision: 2)
        var pages = states([old])
        pages[.active]?.rows = [current]
        let snapshot = ChallengeProfileSnapshot(actor: actor, sections: pages, now: now)
        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertEqual(snapshot.active.count, 1)
        XCTAssertEqual(snapshot.upcoming.count, 0)
    }

    func testCompetitiveRecordUsesOnlyFinalCompetitiveAllocations() throws {
        let validWin = try row(policy: "friend_steps_leaderboard_v2", status: "final", result: "winner")
        let validLoss = try row(policy: "friend_timed_leaderboard_v1", status: "final", result: "placed")
        let excluded = try [
            row(status: "final", result: "missed"),
            row(policy: "friend_steps_goal_v1", status: "final", result: "met"),
            row(policy: "community_steps_goal_v1", status: "final", result: "missed"),
            row(policy: "friend_steps_leaderboard_v2", status: "review", result: "placed"),
            row(policy: "friend_steps_leaderboard_v2", status: "final", result: "unranked"),
            row(policy: "friend_steps_leaderboard_v2", status: "void", result: "void"),
            row(policy: "friend_steps_leaderboard_v2", status: "final", result: "placed", exited: true),
            row(policy: "friend_steps_leaderboard_v2", status: "final", result: nil)
        ]
        let snapshot = snapshot([validWin, validLoss] + excluded)
        XCTAssertEqual(snapshot.wins, 1)
        XCTAssertEqual(snapshot.losses, 1)
        XCTAssertEqual(Set(snapshot.competitiveResults.map(\.row.id)), [validWin.id, validLoss.id])
    }

    func testHiddenFinalOwnResultCanRemainInPrivateRecord() throws {
        let own = try row(policy: "friend_steps_leaderboard_v2", status: "final", result: "winner", hidden: true)
        XCTAssertEqual(snapshot([own]).wins, 1)
    }

    func testNilActorNeverReadsPreviousAccountRows() throws {
        let pages = states([try row(status: "scheduled")])
        let signedOut = ChallengeProfileSnapshot(actor: nil, sections: pages, now: now)
        XCTAssertEqual(signedOut.availability, .unavailable)
        XCTAssertTrue(signedOut.rows.isEmpty)
        XCTAssertNil(signedOut.checkedAt)
    }

    func testStorePaginationDeduplicatesAndAccountSwitchClearsProfile() async throws {
        let first = try row(status: "final")
        let second = try row(status: "final")
        let auth = ProfileAuth(actor: actor)
        let client = ProfileClient(first: first, second: second)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ChallengeV1Store(auth: auth, client: client,
            requests: ChallengeV1RequestStore(directory: folder), now: { 100 })
        store.setActor(actor)
        await store.refresh()
        XCTAssertEqual(store.profileSnapshot.availability, .partial)
        XCTAssertEqual(store.profileSnapshot.finished.count, 1)
        await store.loadMore(.history)
        XCTAssertEqual(store.profileSnapshot.availability, .complete)
        XCTAssertEqual(store.profileSnapshot.finished.count, 2)
        store.setActor(UUID())
        XCTAssertEqual(store.profileSnapshot.availability, .unavailable)
        XCTAssertTrue(store.profileSnapshot.rows.isEmpty)
    }

    func testHeldPaginationCannotRestoreAnotherAccountsProfile() async throws {
        let client = ProfileClient(first: try row(status: "final"), second: try row(status: "final"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ChallengeV1Store(auth: ProfileAuth(actor: actor), client: client,
            requests: .init(directory: folder), now: { 100 })
        store.setActor(actor)
        await store.refresh()
        client.holdNextPage = true
        let loading = Task { await store.loadMore(.history) }
        while client.pageContinuation == nil { await Task.yield() }
        store.setActor(UUID())
        client.pageContinuation?.resume()
        client.pageContinuation = nil
        await loading.value
        XCTAssertEqual(store.profileSnapshot.availability, .unavailable)
        XCTAssertTrue(store.profileSnapshot.rows.isEmpty)
    }

    #if DEBUG
    func testProfileMountedVisualMatrix() async throws {
        let client = ProfileRenderClient()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ChallengeV1Store(auth: ProfileAuth(actor: actor), client: client,
            requests: .init(directory: folder), now: { 100 })
        store.setActor(actor)
        client.rows = try [row(status: "scheduled"), row(status: "active"), row(status: "final", result: "met"),
            row(policy: "friend_steps_leaderboard_v2", status: "final", result: "winner")]
        await store.refresh()
        for (name, scheme, size, solid) in [
            ("profile-loaded-light", ColorScheme.light, DynamicTypeSize.large, false),
            ("profile-loaded-dark", .dark, .large, false),
            ("profile-compact-large-solid", .dark, .accessibility3, true)
        ] {
            let text = try await captureProfile(store, name: name, scheme: scheme, size: size, solid: solid)
            XCTAssertTrue(text.contains("alex lee"), text)
            XCTAssertTrue(text.contains("upcoming"), text)
            XCTAssertTrue(text.contains("finished"), text)
            XCTAssertTrue(text.contains("wins"), text)
            XCTAssertFalse(text.contains("all time"), text)
        }
        client.rows = try [row(status: "scheduled")]
        await store.refresh()
        let upcoming = try await captureProfile(store, name: "profile-upcoming-goal")
        XCTAssertTrue(upcoming.contains("your next goal"), upcoming)
        XCTAssertTrue(upcoming.contains("50,000"), upcoming)
        let activity = try await captureProfile(store, name: "profile-personal-activity-unavailable", showActivity: true)
        XCTAssertTrue(activity.contains("lifetime totals and streaks"), activity)
        XCTAssertTrue(activity.contains("aren’t available") || activity.contains("aren't available"), activity)
        client.paginated = true
        await store.refresh()
        let partial = try await captureProfile(store, name: "profile-partial")
        XCTAssertTrue(partial.contains("load more records"), partial)
        client.fail = true
        await store.refresh()
        let stale = try await captureProfile(store, name: "profile-stale")
        XCTAssertTrue(stale.contains("out of date"), stale)
        store.setActor(actor)
        await store.refresh()
        let unavailable = try await captureProfile(store, name: "profile-unavailable")
        XCTAssertTrue(unavailable.contains("refresh to try again"), unavailable)
        client.fail = false; client.paginated = false; client.rows = []
        await store.refresh()
        let empty = try await captureProfile(store, name: "profile-empty")
        XCTAssertTrue(empty.contains("your goals belong here"), empty)
    }

    private func captureProfile(_ store: ChallengeV1Store, name: String,
                                scheme: ColorScheme = .light, size: DynamicTypeSize = .large,
                                solid: Bool = false, showActivity: Bool = false) async throws -> String {
        let profile = UserProfile(id: actor, handle: "alexlee", displayName: "Alex Lee", timezone: "America/Los_Angeles")
        let view = TabView(selection: .constant(2)) {
                Text("Home").tabItem { Label("Home", systemImage: "house") }.tag(0)
                Text("Challenges").tabItem { Label("Challenges", systemImage: "flag") }.tag(1)
                NavigationStack {
                    ChallengeProfileView(store: store, profile: profile, accountActor: actor)
                }.tabItem { Label("You", systemImage: "person") }.tag(2)
        }
        .environment(\.colorScheme, scheme)
        .environment(\.dynamicTypeSize, size)
        .tint(SignalTheme.accent)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: view.frame(width: 375, height: 812))
        host.traitOverrides.accessibilityContrast = solid ? .high : .normal
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(250))
        if showActivity {
            func segmentedControl(in view: UIView) -> UISegmentedControl? {
                if let control = view as? UISegmentedControl { return control }
                return view.subviews.lazy.compactMap { segmentedControl(in: $0) }.first
            }
            let control = try XCTUnwrap(segmentedControl(in: host.view))
            control.selectedSegmentIndex = 1
            control.sendActions(for: .valueChanged)
            try await Task.sleep(for: .milliseconds(150))
        }
        return try await captureMountedSignal(window, controller: host, name: name, test: self)
    }
    #endif

    private func snapshot(_ rows: [ChallengeV1]) -> ChallengeProfileSnapshot {
        ChallengeProfileSnapshot(actor: actor, sections: states(rows), now: now)
    }
    private func states(_ rows: [ChallengeV1]) -> [ChallengeV1Section: ChallengeV1SectionState] {
        Dictionary(uniqueKeysWithValues: ChallengeV1Section.allCases.map { section in
            (section, ChallengeV1SectionState(rows: rows.filter { section.includes($0, actor: actor) },
                cursor: nil, projectionRevision: UUID(), serverTime: ChallengeInstant(date: Date(timeIntervalSince1970: 100)),
                receivedAt: now, error: nil, fresh: true))
        })
    }
    private func row(id: UUID = UUID(), policy: String = "personal_steps_goal_v1", status: String,
                     revision: Int = 1, result: String? = nil, exited: Bool = false, hidden: Bool = false) throws -> ChallengeV1 {
        let start = try ChallengeInstant("2026-09-23T00:00:00Z")
        let end = try ChallengeInstant("2026-09-30T00:00:00Z")
        let person = result.map { ChallengeV1.Allocation.Person(status: $0, returnedCents: 100) }
        let allocation = person.map { person in
            ChallengeV1.Allocation(outcome: status == "void" ? "void" : "scored",
                participants: hidden ? nil : [actor.uuidString.lowercased(): person], own: hidden ? person : nil,
                entryCents: 100, unallocatedCents: 0, simulation: "nonredeemable")
        }
        return ChallengeV1(id: id, creatorId: actor, policy: policy,
            config: .init(startDate: "2026-09-23", days: 7, timezone: "UTC", amountCents: 100,
                distanceMm: policy.contains("timed") ? 5_000_000 : nil,
                startsAt: start, endsAt: end, syncBy: end, correctionsBy: end, noticeDue: end),
            status: status, revision: revision, agreementVersion: 1, serverTime: start,
            socialHidden: hidden, agreement: nil,
            members: [.init(actorId: actor, username: "alex", target: policy.contains("leaderboard") ? nil : 50_000,
                selected: true, exited: exited, consented: true, fact: nil)], notice: nil, reviews: [],
            final: allocation.map { .init(recordedAt: end, result: $0) })
    }
}

@MainActor private final class ProfileAuth: AuthClient {
    var actor: UUID
    init(actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor }
    func signOut() async throws {}
}

@MainActor private final class ProfileClient: ChallengeV1Client {
    let first: ChallengeV1
    let second: ChallengeV1
    let revision = UUID()
    var holdNextPage = false
    var suspended = false
    var pageContinuation: CheckedContinuation<Void, Never>?
    init(first: ChallengeV1, second: ChallengeV1) { self.first = first; self.second = second }
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        if cursor != nil, holdNextPage {
            await withCheckedContinuation { pageContinuation = $0 }
        }
        let rows = section == .history ? (cursor == nil ? [first] : [first, second]) : []
        return .init(section: section, projectionRevision: revision, serverTime: first.serverTime,
            expiresAt: first.config.endsAt, rows: rows,
            nextCursor: section == .history && cursor == nil ? .object(["page": .integer(2)]) : nil)
    }
    func list(actor: UUID) async throws -> [ChallengeV1] { [first, second] }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 { first }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        if name == "challenge_access_status_v1" {
            return ChallengeV1Access(serverTime: nil, ageConfirmed: true, betaAccess: true, suspended: suspended) as! T
        }
        if name == "challenge_community_catalog_v1" { return [ChallengeV1Community]() as! T }
        throw ChallengeV1Error.unavailable
    }
}

#if DEBUG
@MainActor private final class ProfileRenderClient: ChallengeV1Client {
    var rows: [ChallengeV1] = []
    var fail = false
    var paginated = false
    let revision = UUID()
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        guard !fail else { throw ChallengeV1Error.unavailable }
        let now = ChallengeInstant(date: Date())
        return .init(section: section, projectionRevision: revision, serverTime: now, expiresAt: now,
            rows: rows.filter { section.includes($0, actor: actor) },
            nextCursor: paginated && section == .history ? .object(["page": .integer(2)]) : nil)
    }
    func list(actor: UUID) async throws -> [ChallengeV1] { rows }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 { try XCTUnwrap(rows.first { $0.id == id }) }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
}
#endif
