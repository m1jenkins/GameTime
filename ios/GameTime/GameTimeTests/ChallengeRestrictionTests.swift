#if DEBUG
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import GameTime

/// Fictional client responses exercise production stores and mounted views.
/// These checks do not establish physical-source or human accessibility acceptance.
@MainActor final class ChallengeRestrictionTests: XCTestCase {
    func testEqualRevisionHistoryRestrictsEveryCachedCopy() async throws { try await history(revision: 1) }
    func testHigherRevisionHistoryRestrictsEveryCachedCopy() async throws { try await history(revision: 2) }

    private func history(revision: Int) async throws {
        let fixture = RestrictionFixture()
        defer { fixture.clean() }
        // Seed every section and a separate detail cache. A server restriction
        // must replace all copies even when the other sections fail to refresh.
        for section in ChallengeV1Section.allCases { fixture.client.rows[section] = [fixture.shared, fixture.unrelated] }
        await fixture.start()
        await fixture.store.loadDetail(fixture.shared.id)
        let request = ChallengeV1Request(actor: fixture.actor, payload: .object(["op": .string("leave"), "id": .string(fixture.shared.id.uuidString.lowercased()), "revision": .integer(1)]))
        try await fixture.store.requests.save(request)
        let path = fixture.directory.appendingPathComponent(fixture.actor.uuidString.lowercased() + ".json")
        let bytes = try Data(contentsOf: path)
        fixture.restrict(revision: revision, failing: [.action, .active, .upcoming])
        await fixture.store.refresh()
        let restricted = fixture.client.rows[.history]![0]
        XCTAssertEqual(fixture.store.access?.suspended, false)
        for section in ChallengeV1Section.allCases {
            XCTAssertEqual(fixture.store.sections[section]?.rows.first { $0.id == fixture.shared.id }, restricted)
        }
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.shared.id }, restricted)
        XCTAssertEqual(fixture.store.sections[.active]?.rows.last, fixture.unrelated)
        XCTAssertEqual(fixture.store.sections[.active]?.receivedAt, 0, "Reconciliation cannot renew unrelated rows")
        XCTAssertEqual(fixture.store.pending, request)
        XCTAssertEqual(try Data(contentsOf: path), bytes)
        fixture.clock.value = 61
        fixture.store.purgeExpiredContent()
        XCTAssertFalse(fixture.store.challenges.contains { $0.id == fixture.unrelated.id })
        XCTAssertEqual(fixture.store.challenges, [restricted], "The newer History projection survives earlier cache expiry")
        fixture.clock.value = 91
        fixture.store.purgeExpiredContent()
        XCTAssertTrue(fixture.store.challenges.isEmpty, "Reconciliation cannot orphan a detail cache lifetime")
        XCTAssertEqual(try Data(contentsOf: path), bytes)
        await fixture.store.retry()
        XCTAssertEqual(fixture.client.submitted, [request], "Recovery resends the exact original request")
        let retried = try await fixture.store.requests.load(fixture.actor)
        XCTAssertEqual(retried, request, "An interrupted retry preserves the original request")
        XCTAssertEqual(try retried?.body, try request.body, "Recovery preserves canonical request bytes")
    }

    func testRestrictedLaterPageReplacesDuplicateAndDetailCopies() async throws {
        for revision in [1, 2] {
            let fixture = RestrictionFixture(); defer { fixture.clean() }
            fixture.client.rows[.active] = [fixture.shared, fixture.unrelated]
            fixture.client.rows[.history] = [fixture.shared]
            fixture.client.cursor = .object(["offset": .integer(1)])
            await fixture.start(); await fixture.store.loadDetail(fixture.shared.id)
            fixture.clock.value = 30
            let restricted = fixture.restricted(revision: revision)
            fixture.client.moreRows = [restricted]
            await fixture.store.loadMore(.history)
            XCTAssertEqual(fixture.store.sections[.active]?.rows.first, restricted)
            XCTAssertEqual(fixture.store.sections[.history]?.rows, [restricted])
            // Clearing sections with a successful empty read must not reveal an
            // older, shared detail that was cached before the later-page response.
            fixture.client.rows = [:]; fixture.client.cursor = nil
            await fixture.store.refresh()
            XCTAssertEqual(fixture.store.challenges, [restricted])
            fixture.clock.value = 60; fixture.store.purgeExpiredContent()
            XCTAssertTrue(fixture.store.challenges.isEmpty)
        }
    }

    func testRestrictedDetailReconcilesAllSectionsWithoutRenewingThem() async throws {
        let fixture = RestrictionFixture(); defer { fixture.clean() }
        for section in ChallengeV1Section.allCases { fixture.client.rows[section] = [fixture.shared, fixture.unrelated] }
        await fixture.start(); fixture.clock.value = 30
        fixture.client.detailRow = fixture.restricted(revision: 1)
        await fixture.store.loadDetail(fixture.shared.id)
        for state in fixture.store.sections.values {
            XCTAssertEqual(state.rows, [fixture.client.detailRow!, fixture.unrelated])
            XCTAssertEqual(state.receivedAt, 0)
        }
        fixture.clock.value = 61; fixture.store.purgeExpiredContent()
        XCTAssertEqual(fixture.store.challenges, [fixture.client.detailRow!])
        fixture.clock.value = 91; fixture.store.purgeExpiredContent()
        XCTAssertTrue(fixture.store.challenges.isEmpty)
    }

    func testRestrictedResponseCannotCrossAnAccountGeneration() async throws {
        let fixture = RestrictionFixture(); defer { fixture.clean() }
        await fixture.start(); fixture.restrict(revision: 2, failing: [.active])
        fixture.client.holdHistory = true
        let refresh = Task { await fixture.store.refresh() }
        while fixture.client.held == nil { await Task.yield() }
        let replacement = UUID(); fixture.auth.actor = replacement; fixture.store.setActor(replacement)
        fixture.client.held?.resume(returning: fixture.client.pageValue(.history)); fixture.client.held = nil
        await refresh.value
        XCTAssertEqual(fixture.store.actor, replacement)
        XCTAssertTrue(fixture.store.sections.isEmpty)
        XCTAssertTrue(fixture.store.challenges.isEmpty)
    }

    func testMountedHomeEqualRevisionUpdatesWithoutDetailFetch() async throws { try await mounted(detail: false, revision: 1) }
    func testMountedHomeHigherRevisionUpdatesWithoutDetailFetch() async throws { try await mounted(detail: false, revision: 2) }
    func testMountedDetailEqualRevisionUpdatesWithoutAnotherFetch() async throws { try await mounted(detail: true, revision: 1) }
    func testMountedDetailHigherRevisionUpdatesWithoutAnotherFetch() async throws { try await mounted(detail: true, revision: 2) }

    private func mounted(detail: Bool, revision: Int) async throws {
        let fixture = RestrictionFixture(); defer { fixture.clean() }
        await fixture.start()
        let view = detail ? AnyView(NavigationStack { ChallengeV1Detail(store: fixture.store, id: fixture.shared.id) }.environment(\.dynamicTypeSize, .accessibility1)) :
            AnyView(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}))
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertNotNil(controller.view.window)
        XCTAssertEqual(fixture.client.detailCalls, detail ? 1 : 0)
        let name = "restriction-\(detail ? "detail" : "home")-revision-\(revision)"
        let before = try await capture(window, controller: controller, name: name + "-before")
        if detail {
            XCTAssertTrue(before.contains("sharedfriend"), "Counterpart must actually be visible before restriction")
            XCTAssertTrue(before.contains("321 of 2,000 steps"), "Counterpart activity and agreed goal must actually be rendered")
        } else {
            XCTAssertFalse(before.contains("you left this challenge"))
            XCTAssertTrue(before.contains("507"), "Unrelated activity is the rendered Home control")
        }
        fixture.restrict(revision: revision, failing: [.active])
        await fixture.store.refresh()
        try await Task.sleep(for: .milliseconds(300))
        let after = try await capture(window, controller: controller, name: name + "-after")
        XCTAssertEqual(fixture.client.detailCalls, detail ? 1 : 0, "No forced detail fetch may repair the mounted view")
        if detail {
            XCTAssertFalse(after.contains("sharedfriend"))
            XCTAssertFalse(after.contains("321 of 2,000 steps"))
            // Saved viewport images show "of"; Vision sometimes reads its f as r.
            // Keep the exact own value, goal and unit, plus every privacy check.
            XCTAssertNotNil(after.range(of: #"\b100\s+o[fr]\s+1,000 steps\b"#, options: .regularExpression),
                            "Own activity and agreed goal remain visible")
        } else {
            XCTAssertEqual(after.components(separatedBy: "you left this challenge").count - 1, 2, "Both the retained Active card and current History card must render the restriction")
            XCTAssertTrue(after.contains("507"), "Unrelated card stays mounted with its original activity")
        }
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.shared.id }, fixture.client.rows[.history]?.first)
        XCTAssertEqual(fixture.store.sections[.active]?.rows.first { $0.id == fixture.shared.id }, fixture.client.rows[.history]?.first,
                       "The retained Active copy must match the same restricted History projection")
    }

    private func capture(_ window: UIWindow, controller: UIViewController, name: String) async throws -> String {
        try await captureMountedSignal(window, controller: controller, name: name, test: self)
    }

}

@MainActor private final class RestrictionFixture {
    let actor = UUID(), counterpart = UUID(), id = UUID(), unrelatedID = UUID()
    let clock = RestrictionClock(), client = RestrictionClient()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("challenge-restriction-" + UUID().uuidString)
    lazy var auth = RestrictionAuth(actor)
    lazy var store = ChallengeV1Store(auth: auth, client: client, requests: ChallengeV1RequestStore(directory: directory), now: { [clock] in clock.value })
    lazy var shared = row(id, hidden: false, revision: 1)
    lazy var unrelated = row(unrelatedID, hidden: false, revision: 1)
    func restricted(revision: Int) -> ChallengeV1 { row(id, hidden: true, revision: revision) }
    func start() async {
        if client.rows.isEmpty { client.rows[.active] = [shared, unrelated] }
        client.detailRow = shared
        store.setActor(actor); await store.refresh()
    }
    func restrict(revision: Int, failing: Set<ChallengeV1Section>) {
        clock.value = 30; client.fail = failing; client.rows[.history] = [restricted(revision: revision)]
        client.detailRow = restricted(revision: revision)
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    private func row(_ id: UUID, hidden: Bool, revision: Int) -> ChallengeV1 {
        let start = ChallengeInstant(date: Date()), end = ChallengeInstant(date: Date().addingTimeInterval(86400))
        let own = ChallengeV1.Member(actorId: actor, username: "Ownfictional", target: 1000, selected: true, exited: hidden, consented: true, fact: .init(value: id == unrelatedID ? 507 : 100, state: "complete", recordedAt: start, revision: 1))
        let friend = ChallengeV1.Member(actorId: counterpart, username: "Sharedfriend", target: 2000, selected: true, exited: false, consented: true, fact: .init(value: 321, state: "complete", recordedAt: start, revision: 1))
        return ChallengeV1(id: id, creatorId: hidden ? nil : counterpart, policy: "friend_steps_goal_v1", config: .init(startDate: "2026-10-03", days: 1, timezone: "UTC", amountCents: 100, startsAt: start, endsAt: end, syncBy: end, correctionsBy: end, noticeDue: end), status: "active", revision: revision, agreementVersion: 1, serverTime: start, socialHidden: hidden, agreement: nil, members: hidden ? [own] : [own, friend], notice: nil, reviews: [], final: nil)
    }
}
@MainActor private final class RestrictionClient: ChallengeV1Client {
    var rows: [ChallengeV1Section: [ChallengeV1]] = [:], fail: Set<ChallengeV1Section> = []
    var detailRow: ChallengeV1?, detailCalls = 0, submitted: [ChallengeV1Request] = []
    var cursor: ChallengeJSON?, moreRows: [ChallengeV1] = []
    let projection = UUID()
    var holdHistory = false; var held: CheckedContinuation<ChallengeV1Page, Error>?
    func pageValue(_ section: ChallengeV1Section, more: Bool = false) -> ChallengeV1Page {
        ChallengeV1Page(section: section, projectionRevision: projection, serverTime: ChallengeInstant(date: Date()), expiresAt: ChallengeInstant(date: Date().addingTimeInterval(120)), rows: more ? moreRows : rows[section] ?? [], nextCursor: more ? nil : cursor)
    }
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        if fail.contains(section) { throw ChallengeV1Error.unavailable }
        if section == .history && holdHistory { return try await withCheckedThrowingContinuation { held = $0 } }
        return pageValue(section, more: cursor != nil)
    }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        if name == "challenge_access_status_v1" { return ChallengeV1Access(serverTime: nil, ageConfirmed: true, betaAccess: true, suspended: false) as! T }
        if name == "challenge_community_catalog_v1" { return [ChallengeV1Community]() as! T }
        throw ChallengeV1Error.unavailable
    }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 { detailCalls += 1; return try XCTUnwrap(detailRow) }
    func list(actor: UUID) async throws -> [ChallengeV1] { [] }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { submitted.append(request); throw ChallengeV1Error.unavailable }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
}
@MainActor private final class RestrictionAuth: AuthClient {
    var actor: UUID?; init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}
@MainActor private final class RestrictionClock { var value: TimeInterval = 0 }
#endif
