#if DEBUG
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import GameTime

@MainActor final class ChallengeOverlappingResponseTests: XCTestCase {
    func testLateSameCursorLowerRevisionCannotRestoreSharing() async throws { try await overlap(olderRevision: 1, first: .page, second: .page) }
    func testLateSameCursorEqualRevisionCannotRestoreSharing() async throws { try await overlap(olderRevision: 2, first: .page, second: .page) }
    func testLateSameCursorHigherRevisionCannotRestoreSharing() async throws { try await overlap(olderRevision: 3, first: .page, second: .page) }

    func testOverlappingPageAndDetailResponsesCannotUndoRestriction() async throws {
        let pairs: [(ReadKind, ReadKind)] = [(.page, .detail), (.detail, .page), (.detail, .detail)]
        for revision in [1, 2, 3] {
            for pair in pairs {
                try await overlap(olderRevision: revision, first: pair.0, second: pair.1)
            }
        }
    }

    private enum ReadKind { case page, detail }
    private func begin(_ kind: ReadKind, _ fixture: OverlapFixture) -> Task<Void, Never> {
        Task { if kind == .page { await fixture.store.loadMore(.active) } else { await fixture.store.loadDetail(fixture.id) } }
    }
    private func held(_ kind: ReadKind, _ fixture: OverlapFixture) async throws -> (ChallengeV1) -> Void {
        if kind == .page {
            let response = try await fixture.client.nextPage()
            return { response.finish(fixture.client.pageValue(.active, rows: [$0], cursor: nil)) }
        }
        let response = try await fixture.client.nextDetail()
        return { response.finish($0) }
    }

    private func overlap(olderRevision: Int, first: ReadKind, second: ReadKind) async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        try await fixture.start(allCaches: true)
        let bytes = try Data(contentsOf: fixture.pendingPath)
        fixture.clock.value = 20; fixture.client.holding = true
        let a = begin(first, fixture); let releaseA = try await held(first, fixture)
        fixture.clock.value = 30
        let b = begin(second, fixture); let releaseB = try await held(second, fixture)
        releaseB(fixture.restricted); await b.value
        assertRestricted(fixture)
        let cursorAfterB = fixture.store.sections[.active]?.cursor
        fixture.clock.value = 40
        releaseA(fixture.row(hidden: false, revision: olderRevision)); await a.value
        assertRestricted(fixture)
        XCTAssertEqual(fixture.store.sections[.active]?.cursor, cursorAfterB, "A consumed cursor cannot be restored by the late page")
        XCTAssertTrue(fixture.store.sections[.active]?.rows.contains(fixture.unrelated) == true)
        XCTAssertEqual(fixture.store.sections[.active]?.receivedAt, 0)
        XCTAssertEqual(try Data(contentsOf: fixture.pendingPath), bytes)
        XCTAssertEqual(fixture.store.pending, fixture.pending)
        fixture.clock.value = 61; fixture.store.purgeExpiredContent()
        XCTAssertFalse(fixture.store.challenges.contains { $0.id == fixture.unrelated.id })
        if second == .page {
            XCTAssertTrue(fixture.store.challenges.isEmpty, "The late completion cannot renew any original section/detail lifetime")
        } else {
            XCTAssertEqual(fixture.store.challenges, [fixture.restricted], "Only the fresh restricted detail keeps its own read lifetime")
        }
        fixture.clock.value = 91; fixture.store.purgeExpiredContent()
        XCTAssertTrue(fixture.store.challenges.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.pendingPath), bytes)
    }

    func testInFlightRefreshPageCannotReplaceNewRestrictedDetail() async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        try await fixture.start(allCaches: false)
        fixture.clock.value = 20; fixture.client.holding = true
        let refresh = Task { await fixture.store.refresh() }
        let firstPage = try await fixture.client.nextPage()
        fixture.clock.value = 30
        let detail = Task { await fixture.store.loadDetail(fixture.id) }
        let response = try await fixture.client.nextDetail()
        response.finish(fixture.restricted); await detail.value
        fixture.client.holding = false; fixture.client.rows = [:]
        firstPage.finish(fixture.client.pageValue(.action, rows: [fixture.shared]))
        await refresh.value
        assertRestricted(fixture)
        XCTAssertEqual(fixture.store.challenges, [fixture.restricted])
    }

    func testUnrelatedInFlightResponseAndFreshAuthorizedReadRemainUsable() async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        try await fixture.start(allCaches: false)
        fixture.client.holding = true; fixture.clock.value = 20
        let old = Task { await fixture.store.loadDetail(fixture.id) }
        let oldResponse = try await fixture.client.nextDetail()
        let other = Task { await fixture.store.loadDetail(fixture.unrelated.id) }
        let otherResponse = try await fixture.client.nextDetail()
        fixture.clock.value = 30
        let restriction = Task { await fixture.store.loadDetail(fixture.id) }
        let restrictionResponse = try await fixture.client.nextDetail()
        restrictionResponse.finish(fixture.restricted); await restriction.value
        otherResponse.finish(fixture.unrelated); await other.value
        XCTAssertTrue(fixture.store.challenges.contains(fixture.unrelated), "A fence is scoped to its challenge, not every pending read")
        fixture.clock.value = 40; fixture.client.holding = false
        let future = fixture.row(hidden: false, revision: 2, ownValue: 777)
        fixture.client.detailRow = future
        await fixture.store.loadDetail(fixture.id)
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }, future, "A read started after restriction can accept newly authorized content")
        let futurePage = fixture.row(hidden: false, revision: 2, ownValue: 888)
        fixture.client.rows[.active] = [futurePage]
        await fixture.store.loadMore(.active)
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }, futurePage, "A later page requested after restriction can also accept newly authorized content")
        oldResponse.finish(fixture.shared); await old.value
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }, futurePage, "The old in-flight response remains fenced after valid new reads")
        XCTAssertTrue(fixture.store.challenges.contains(fixture.unrelated))
    }

    func testConsumedCursorCannotBeRewoundByLateResponse() async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        try await fixture.start(allCaches: false)
        fixture.client.holding = true
        let a = Task { await fixture.store.loadMore(.active) }
        let responseA = try await fixture.client.nextPage()
        let b = Task { await fixture.store.loadMore(.active) }
        let responseB = try await fixture.client.nextPage()
        let next = ChallengeJSON.object(["offset": .integer(2)])
        responseB.finish(fixture.client.pageValue(.active, rows: [fixture.shared], cursor: next)); await b.value
        let c = Task { await fixture.store.loadMore(.active) }
        let responseC = try await fixture.client.nextPage()
        let latest = fixture.row(hidden: false, revision: 2, ownValue: 777)
        responseC.finish(fixture.client.pageValue(.active, rows: [latest], cursor: nil)); await c.value
        responseA.finish(fixture.client.pageValue(.active, rows: [fixture.shared], cursor: next)); await a.value
        XCTAssertNil(fixture.store.sections[.active]?.cursor)
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }, latest)
        XCTAssertTrue(fixture.store.challenges.contains(fixture.unrelated))
    }

    func testRestrictionFenceSurvivesContentExpiryWithoutRetainingContent() async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        try await fixture.start(allCaches: true)
        fixture.clock.value = 20; fixture.client.holding = true
        let a = Task { await fixture.store.loadDetail(fixture.id) }
        let responseA = try await fixture.client.nextDetail()
        fixture.clock.value = 30
        let b = Task { await fixture.store.loadMore(.active) }
        let responseB = try await fixture.client.nextPage()
        responseB.finish(fixture.client.pageValue(.active, rows: [fixture.restricted], cursor: nil)); await b.value
        fixture.clock.value = 61; fixture.store.purgeExpiredContent()
        XCTAssertTrue(fixture.store.challenges.isEmpty)
        responseA.finish(fixture.shared); await a.value
        XCTAssertTrue(fixture.store.challenges.isEmpty, "A 41-second-old request cannot restore data after the original caches expired")
        fixture.clock.value = 91; fixture.store.purgeExpiredContent()
        fixture.client.holding = false; fixture.client.detailRow = fixture.shared
        await fixture.store.loadDetail(fixture.id)
        XCTAssertEqual(fixture.store.challenges, [fixture.shared], "Expiring a fence never permanently disables a future authorized read")
    }

    func testMountedHomeKeepsRestrictionAfterLateSameCursorResponse() async throws {
        for revision in [1, 2, 3] { try await mounted(detail: false, revision: revision) }
    }
    func testMountedDetailKeepsRestrictionAfterLatePageResponse() async throws {
        for revision in [1, 2, 3] { try await mounted(detail: true, revision: revision) }
    }

    private func mounted(detail: Bool, revision: Int) async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        try await fixture.start(allCaches: false)
        let view = detail ? AnyView(NavigationStack { ChallengeV1Detail(store: fixture.store, id: fixture.id) }) :
            AnyView(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}))
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 430, height: 3000)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(300))
        let name = "overlap-\(detail ? "detail" : "home")-old-revision-\(revision)"
        let before = try capture(window, controller, name: name + "-shared")
        if detail { XCTAssertTrue(before.contains("sharedfriend")); XCTAssertTrue(before.contains("321 of 2,000 steps")) }
        else { XCTAssertFalse(before.contains("you left this challenge")); XCTAssertTrue(before.contains("507")) }
        fixture.client.holding = true; fixture.clock.value = 20
        let a = Task { await fixture.store.loadMore(.active) }
        let responseA = try await fixture.client.nextPage()
        fixture.clock.value = 30
        let b = Task { await fixture.store.loadMore(.active) }
        let responseB = try await fixture.client.nextPage()
        responseB.finish(fixture.client.pageValue(.active, rows: [fixture.restricted], cursor: nil)); await b.value
        let calls = fixture.client.detailCalls
        try await Task.sleep(for: .milliseconds(300))
        let restricted = try capture(window, controller, name: name + "-restricted")
        if detail { XCTAssertFalse(restricted.contains("sharedfriend")); XCTAssertFalse(restricted.contains("321 of 2,000 steps")) }
        else { XCTAssertTrue(restricted.contains("you left this challenge")); XCTAssertTrue(restricted.contains("507")) }
        fixture.clock.value = 40
        responseA.finish(fixture.client.pageValue(.active, rows: [fixture.row(hidden: false, revision: revision)], cursor: nil)); await a.value
        try await Task.sleep(for: .milliseconds(300))
        let late = try capture(window, controller, name: name + "-after-late-response")
        XCTAssertEqual(fixture.client.detailCalls, calls, "No extra detail fetch or remount can conceal the late response")
        if detail { XCTAssertFalse(late.contains("sharedfriend")); XCTAssertFalse(late.contains("321 of 2,000 steps")); XCTAssertTrue(late.contains("100 of 1,000 steps")) }
        else { XCTAssertTrue(late.contains("you left this challenge")); XCTAssertTrue(late.contains("507")) }
        assertRestricted(fixture)
        XCTAssertNotNil(controller.view.window)
    }

    private func assertRestricted(_ fixture: OverlapFixture, file: StaticString = #filePath, line: UInt = #line) {
        let copies = fixture.store.sections.values.flatMap(\.rows).filter { $0.id == fixture.id }
        XCTAssertTrue(copies.allSatisfy(\.socialHidden), file: file, line: line)
        let shown = fixture.store.challenges.first { $0.id == fixture.id }
        XCTAssertEqual(shown?.socialHidden, true, file: file, line: line)
        XCTAssertFalse(shown?.members.contains { $0.actorId == fixture.friend } == true, file: file, line: line)
    }

    private func capture(_ window: UIWindow, _ controller: UIViewController, name: String) throws -> String {
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { controller.view.layer.render(in: $0.cgContext) }
        let cg = try XCTUnwrap(image.cgImage); var lines: [String] = []
        // Keep text crossing a crop edge whole in at least one OCR tile.
        for y in stride(from: 0, to: cg.height, by: 550) {
            let tile = try XCTUnwrap(cg.cropping(to: CGRect(x: 0, y: y, width: cg.width, height: min(650, cg.height - y))))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
            try VNImageRequestHandler(cgImage: tile).perform([request])
            lines += (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        let text = lines.joined(separator: " ").lowercased()
        let transcription = XCTAttachment(string: text); transcription.name = name + "-recognized-text"; transcription.lifetime = .keepAlways; add(transcription)
        return text
    }
}

@MainActor private final class OverlapFixture {
    let actor = UUID(), friend = UUID(), id = UUID(), otherID = UUID()
    let clock = OverlapClock(), client = OverlapClient()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("challenge-overlap-" + UUID().uuidString)
    lazy var auth = OverlapAuth(actor)
    lazy var store = ChallengeV1Store(auth: auth, client: client, requests: ChallengeV1RequestStore(directory: directory), now: { [clock] in clock.value })
    lazy var shared = row(hidden: false, revision: 2)
    lazy var restricted = row(hidden: true, revision: 2)
    lazy var unrelated = row(hidden: false, revision: 2, ownValue: 507, id: otherID)
    lazy var pending = ChallengeV1Request(actor: actor, payload: .object(["op": .string("leave"), "id": .string(id.uuidString.lowercased()), "revision": .integer(2)]))
    var pendingPath: URL { directory.appendingPathComponent(actor.uuidString.lowercased() + ".json") }
    func start(allCaches: Bool) async throws {
        client.rows[.active] = allCaches ? [unrelated] : [shared, unrelated]
        if allCaches { for section in [ChallengeV1Section.action, .upcoming, .history] { client.rows[section] = [shared] } }
        client.detailRow = shared; try await store.requests.save(pending)
        store.setActor(actor); await store.refresh(); await store.loadDetail(id)
        try shared.validate(actor: actor); try restricted.validate(actor: actor)
        XCTAssertEqual(store.access?.suspended, false)
    }
    func clean() { client.cancelPending(); try? FileManager.default.removeItem(at: directory) }
    func row(hidden: Bool, revision: Int, ownValue: Int = 100, id: UUID? = nil) -> ChallengeV1 {
        let start = ChallengeInstant(date: Date(timeIntervalSince1970: 1790985600)), end = ChallengeInstant(date: Date(timeIntervalSince1970: 1791072000))
        let own = ChallengeV1.Member(actorId: actor, username: "Ownfictional", target: 1000, selected: true, exited: hidden, consented: true, fact: .init(value: ownValue, state: "complete", recordedAt: start, revision: 1))
        let other = ChallengeV1.Member(actorId: friend, username: "Sharedfriend", target: 2000, selected: true, exited: false, consented: true, fact: .init(value: 321, state: "complete", recordedAt: start, revision: 1))
        return ChallengeV1(id: id ?? self.id, creatorId: hidden ? nil : friend, policy: "friend_steps_goal_v1", config: .init(startDate: "2026-10-03", days: 1, timezone: "UTC", amountCents: 100, startsAt: start, endsAt: end, syncBy: end, correctionsBy: end, noticeDue: end), status: "active", revision: revision, agreementVersion: 1, serverTime: start, socialHidden: hidden, agreement: nil, members: hidden ? [own] : [own, other], notice: nil, reviews: [], final: nil)
    }
}
@MainActor private final class OverlapResponse<Value: Sendable> {
    var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    func cancel() { continuation?.resume(throwing: ChallengeV1Error.unavailable); continuation = nil }
}
@MainActor private final class OverlapClient: ChallengeV1Client {
    var rows: [ChallengeV1Section: [ChallengeV1]] = [:], holding = false
    var detailRow: ChallengeV1?, detailCalls = 0
    let projection = UUID()
    var pages: [OverlapResponse<ChallengeV1Page>] = [], details: [OverlapResponse<ChallengeV1>] = []
    var cancellations: [() -> Void] = []
    func pageValue(_ section: ChallengeV1Section, rows: [ChallengeV1]? = nil, cursor: ChallengeJSON? = .object(["offset": .integer(1)])) -> ChallengeV1Page {
        ChallengeV1Page(section: section, projectionRevision: projection, serverTime: ChallengeInstant(date: Date()), expiresAt: ChallengeInstant(date: Date().addingTimeInterval(120)), rows: rows ?? self.rows[section] ?? [], nextCursor: cursor)
    }
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        if holding { return try await withCheckedThrowingContinuation { let response = OverlapResponse($0); pages.append(response); cancellations.append { response.cancel() } } }
        return pageValue(section)
    }
    func nextPage() async throws -> OverlapResponse<ChallengeV1Page> {
        let deadline = Date().addingTimeInterval(2)
        while pages.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        guard !pages.isEmpty else { throw ChallengeV1Error.unavailable }
        return pages.removeFirst()
    }
    func nextDetail() async throws -> OverlapResponse<ChallengeV1> {
        let deadline = Date().addingTimeInterval(2)
        while details.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        guard !details.isEmpty else { throw ChallengeV1Error.unavailable }
        return details.removeFirst()
    }
    func cancelPending() { cancellations.forEach { $0() }; cancellations = [] }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        if name == "challenge_access_status_v1" { return ChallengeV1Access(serverTime: nil, ageConfirmed: true, betaAccess: true, suspended: false) as! T }
        if name == "challenge_community_catalog_v1" { return [ChallengeV1Community]() as! T }
        throw ChallengeV1Error.unavailable
    }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 {
        detailCalls += 1
        if holding { return try await withCheckedThrowingContinuation { let response = OverlapResponse($0); details.append(response); cancellations.append { response.cancel() } } }
        return try XCTUnwrap(detailRow)
    }
    func list(actor: UUID) async throws -> [ChallengeV1] { [] }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
}
@MainActor private final class OverlapAuth: AuthClient {
    var actor: UUID?; init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}
@MainActor private final class OverlapClock { var value: TimeInterval = 0 }
#endif
