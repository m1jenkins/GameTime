#if DEBUG
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import GameTime

@MainActor final class ChallengeDepartureResponseTests: XCTestCase {
    func testHeldInitialPageCannotUndoLowerRevisionDeparture() async throws { try await overlap(first: .refresh, second: .detail, oldRevision: 1) }
    func testHeldInitialPageCannotUndoEqualRevisionDeparture() async throws { try await overlap(first: .refresh, second: .detail, oldRevision: 2) }
    func testHeldInitialPageCannotUndoHigherRevisionDeparture() async throws { try await overlap(first: .refresh, second: .detail, oldRevision: 3) }

    func testPageAndDetailReversalsKeepPartialRedaction() async throws {
        let pairs: [(ReadKind, ReadKind)] = [(.page, .detail), (.detail, .page), (.detail, .detail)]
        for revision in [1, 2, 3] {
            for pair in pairs { try await overlap(first: pair.0, second: pair.1, oldRevision: revision) }
        }
    }

    private enum ReadKind { case refresh, page, detail }
    private func begin(_ kind: ReadKind, _ fixture: DepartureFixture) -> Task<Void, Never> {
        Task {
            switch kind {
            case .refresh: await fixture.store.refresh()
            case .page: await fixture.store.loadMore(.active)
            case .detail: await fixture.store.loadDetail(fixture.id)
            }
        }
    }
    private func held(_ kind: ReadKind, _ fixture: DepartureFixture) async throws -> (ChallengeV1) -> Void {
        if kind == .detail {
            let response = try await fixture.client.nextDetail()
            return { response.finish($0) }
        }
        let response = try await fixture.client.nextPage()
        return { response.finish(fixture.client.pageValue(.active, rows: [$0, fixture.unrelated], cursor: nil)) }
    }
    private func overlap(first: ReadKind, second: ReadKind, oldRevision: Int) async throws {
        let fixture = DepartureFixture(); defer { fixture.clean() }
        try await fixture.start()
        let bytes = try Data(contentsOf: fixture.pendingPath)
        fixture.clock.value = 20; fixture.client.holding = true
        let a = begin(first, fixture); let releaseA = try await held(first, fixture)
        fixture.clock.value = 30
        let b = begin(second, fixture); let releaseB = try await held(second, fixture)
        releaseB(fixture.redacted); await b.value
        assertRedacted(fixture)
        let cursor = fixture.store.sections[.active]?.cursor
        fixture.clock.value = 40
        releaseA(fixture.row(departed: false, revision: oldRevision)); await a.value
        assertRedacted(fixture)
        XCTAssertEqual(fixture.store.sections[.active]?.cursor, cursor)
        XCTAssertEqual(fixture.store.sections[.active]?.receivedAt, 0)
        XCTAssertTrue(fixture.store.challenges.contains(fixture.unrelated))
        XCTAssertEqual(try Data(contentsOf: fixture.pendingPath), bytes)
        XCTAssertEqual(fixture.store.pending, fixture.pending)
        fixture.clock.value = 61; fixture.store.purgeExpiredContent()
        XCTAssertFalse(fixture.store.challenges.contains { $0.id == fixture.otherID })
        XCTAssertEqual(fixture.store.challenges, second == .detail ? [fixture.redacted] : [])
        fixture.clock.value = 91; fixture.store.purgeExpiredContent()
        XCTAssertTrue(fixture.store.challenges.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.pendingPath), bytes)
    }

    func testPartialFenceSurvivesExpiredContent() async throws {
        let fixture = DepartureFixture(); defer { fixture.clean() }
        try await fixture.start()
        fixture.clock.value = 20; fixture.client.holding = true
        let old = begin(.detail, fixture); let releaseOld = try await held(.detail, fixture)
        fixture.clock.value = 30
        let page = begin(.page, fixture); let releasePage = try await held(.page, fixture)
        releasePage(fixture.redacted); await page.value
        fixture.clock.value = 61; fixture.store.purgeExpiredContent()
        XCTAssertTrue(fixture.store.challenges.isEmpty)
        releaseOld(fixture.shared); await old.value
        XCTAssertTrue(fixture.store.challenges.isEmpty, "The partial-redaction marker must outlive the original content")
        fixture.clock.value = 91; fixture.store.purgeExpiredContent()
        fixture.client.holding = false; fixture.client.detailRow = fixture.redacted
        await fixture.store.loadDetail(fixture.id)
        assertRedacted(fixture)
    }

    func testUnrelatedAndFutureAuthorizedReadsRemainUsable() async throws {
        let fixture = DepartureFixture(); defer { fixture.clean() }
        try await fixture.start()
        fixture.clock.value = 20; fixture.client.holding = true
        let old = begin(.detail, fixture); let releaseOld = try await held(.detail, fixture)
        let unrelated = Task { await fixture.store.loadDetail(fixture.otherID) }
        let unrelatedResponse = try await fixture.client.nextDetail()
        fixture.clock.value = 30
        let restriction = begin(.detail, fixture); let releaseRestriction = try await held(.detail, fixture)
        releaseRestriction(fixture.redacted); await restriction.value
        unrelatedResponse.finish(fixture.unrelated); await unrelated.value
        XCTAssertTrue(fixture.store.challenges.contains(fixture.unrelated))
        fixture.clock.value = 40; fixture.client.holding = false
        let laterDetail = fixture.row(departed: true, revision: 2, ownValue: 109, continuingValue: 777)
        fixture.client.detailRow = laterDetail; await fixture.store.loadDetail(fixture.id)
        assertRedacted(fixture, expected: laterDetail)
        let laterPage = fixture.row(departed: true, revision: 2, ownValue: 109, continuingValue: 888)
        fixture.client.rows[.active] = [laterPage, fixture.unrelated]; await fixture.store.loadMore(.active)
        assertRedacted(fixture, expected: laterPage)
        releaseOld(fixture.shared); await old.value
        assertRedacted(fixture, expected: laterPage)
        XCTAssertTrue(fixture.store.challenges.contains(fixture.unrelated))
    }

    func testLateActivePageCannotReplaceRedactedFinalHistory() async throws {
        let fixture = DepartureFixture(); defer { fixture.clean() }
        try await fixture.start()
        fixture.clock.value = 20; fixture.client.holding = true
        let old = begin(.refresh, fixture); let releaseOld = try await held(.refresh, fixture)
        fixture.clock.value = 30
        let detail = begin(.detail, fixture); let releaseDetail = try await held(.detail, fixture)
        let final = fixture.row(departed: true, revision: 3, ownValue: 109, finalized: true)
        try final.validate(actor: fixture.actor)
        releaseDetail(final); await detail.value
        fixture.clock.value = 40; releaseOld(fixture.shared); await old.value
        assertRedacted(fixture, expected: final)
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }?.agreement, fixture.agreement)
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }?.final, final.final)
        fixture.clock.value = 61; fixture.store.purgeExpiredContent()
        XCTAssertEqual(fixture.store.challenges, [final], "The independent detail cache retains the same immutable history")
    }

    func testMountedDetailKeepsDepartedFieldsHiddenAfterLateInitialPage() async throws {
        for revision in [1, 2, 3] { try await mounted(detail: true, oldRevision: revision) }
    }
    func testMountedHomeKeepsPartialProjectionAfterLateInitialPage() async throws {
        for revision in [1, 2, 3] { try await mounted(detail: false, oldRevision: revision) }
    }

    private func mounted(detail: Bool, oldRevision: Int) async throws {
        let fixture = DepartureFixture(); defer { fixture.clean() }
        try await fixture.start()
        let view = detail ? AnyView(NavigationStack { ChallengeV1Detail(store: fixture.store, id: fixture.id) }) :
            AnyView(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}))
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 430, height: 3000)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(300))
        let name = "departure-\(detail ? "detail" : "home")-old-revision-\(oldRevision)"
        let before = try capture(window, controller, name: name + "-shared")
        XCTAssertTrue(before.contains("100 of 1,000 steps"))
        if detail { XCTAssertTrue(before.contains("departedfriend")); XCTAssertTrue(before.contains("321 of 2,000 steps")); XCTAssertTrue(before.contains("2,000 steps")) }
        else { XCTAssertTrue(before.contains("507")) }
        fixture.clock.value = 20; fixture.client.holding = true
        let old = begin(.refresh, fixture); let releaseOld = try await held(.refresh, fixture)
        fixture.clock.value = 30
        let restriction = begin(.detail, fixture); let releaseRestriction = try await held(.detail, fixture)
        releaseRestriction(fixture.redacted); await restriction.value
        let detailCalls = fixture.client.detailCalls
        try await Task.sleep(for: .milliseconds(300))
        let redacted = try capture(window, controller, name: name + "-redacted")
        assertRendered(redacted, detail: detail)
        fixture.clock.value = 40
        releaseOld(fixture.row(departed: false, revision: oldRevision)); await old.value
        try await Task.sleep(for: .milliseconds(300))
        let late = try capture(window, controller, name: name + "-after-late-response")
        assertRendered(late, detail: detail)
        XCTAssertEqual(fixture.client.detailCalls, detailCalls, "No extra detail fetch or remount can conceal the late completion")
        assertRedacted(fixture)
        XCTAssertNotNil(controller.view.window)
    }
    private func assertRendered(_ text: String, detail: Bool, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(text.contains("109 of 1,000 steps"), file: file, line: line)
        if detail {
            XCTAssertFalse(text.contains("departedfriend"), file: file, line: line)
            XCTAssertFalse(text.contains("321 of 2,000 steps"), file: file, line: line)
            XCTAssertFalse(text.contains("2,000 steps"), file: file, line: line)
            XCTAssertTrue(text.contains("former participant"), file: file, line: line)
            XCTAssertTrue(text.contains("continuingfriend"), file: file, line: line)
            XCTAssertTrue(text.contains("654 of 3,000 steps"), file: file, line: line)
        } else { XCTAssertTrue(text.contains("507"), file: file, line: line) }
    }
    private func assertRedacted(_ fixture: DepartureFixture, expected: ChallengeV1? = nil, file: StaticString = #filePath, line: UInt = #line) {
        let expected = expected ?? fixture.redacted
        let copies = fixture.store.sections.values.flatMap(\.rows).filter { $0.id == fixture.id }
        for row in copies { XCTAssertEqual(row, expected, file: file, line: line) }
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }, expected, file: file, line: line)
        XCTAssertFalse(expected.socialHidden, "This regression must exercise partial sharing", file: file, line: line)
        XCTAssertEqual(expected.members.first { $0.actorId == fixture.departed }?.username, "", file: file, line: line)
        XCTAssertNil(expected.members.first { $0.actorId == fixture.departed }?.target, file: file, line: line)
        XCTAssertNil(expected.members.first { $0.actorId == fixture.departed }?.fact, file: file, line: line)
        XCTAssertEqual(expected.members.first { $0.actorId == fixture.continuing }?.username, "Continuingfriend", file: file, line: line)
        XCTAssertEqual(expected.agreement, fixture.agreement, file: file, line: line)
    }
    private func capture(_ window: UIWindow, _ controller: UIViewController, name: String) throws -> String {
        controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { controller.view.layer.render(in: $0.cgContext) }
        let cg = try XCTUnwrap(image.cgImage); var lines: [String] = []
        // Overlap crops so a line crossing a tile edge is recognized whole in
        // the next tile. The cobalt Home value crosses the old 650-point edge.
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

@MainActor private final class DepartureFixture {
    let actor = UUID(), departed = UUID(), continuing = UUID(), id = UUID(), otherID = UUID()
    let clock = DepartureClock(), client = DepartureClient()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("challenge-departure-" + UUID().uuidString)
    lazy var auth = DepartureAuth(actor)
    lazy var store = ChallengeV1Store(auth: auth, client: client, requests: ChallengeV1RequestStore(directory: directory), now: { [clock] in clock.value })
    lazy var agreement = ChallengeV1.Agreement(digest: String(repeating: "a", count: 64), terms: .object([
        "version": .integer(1), "simulation": .string("nonredeemable"), "participants": .array([
            .object(["actor_id": .string(actor.uuidString.lowercased()), "target": .integer(1000)]),
            .object(["actor_id": .string(departed.uuidString.lowercased()), "target": .integer(2000)]),
            .object(["actor_id": .string(continuing.uuidString.lowercased()), "target": .integer(3000)])])]))
    lazy var shared = row(departed: false, revision: 1)
    lazy var redacted = row(departed: true, revision: 2, ownValue: 109)
    lazy var unrelated = row(departed: false, revision: 1, ownValue: 507, id: otherID)
    lazy var pending = ChallengeV1Request(actor: actor, payload: .object(["op": .string("leave"), "id": .string(id.uuidString.lowercased()), "revision": .integer(1)]))
    var pendingPath: URL { directory.appendingPathComponent(actor.uuidString.lowercased() + ".json") }
    func start() async throws {
        client.rows[.active] = [shared, unrelated]; client.detailRow = shared
        try await store.requests.save(pending); store.setActor(actor); await store.refresh(); await store.loadDetail(id)
        try shared.validate(actor: actor); try redacted.validate(actor: actor)
        XCTAssertEqual(store.access?.suspended, false)
    }
    func clean() { client.cancelPending(); try? FileManager.default.removeItem(at: directory) }
    func row(departed: Bool, revision: Int, ownValue: Int = 100, continuingValue: Int = 654, id: UUID? = nil, finalized: Bool = false) -> ChallengeV1 {
        let start = ChallengeInstant(date: Date(timeIntervalSince1970: 1790985600)), end = ChallengeInstant(date: Date(timeIntervalSince1970: 1791072000))
        let own = ChallengeV1.Member(actorId: actor, username: "Ownfictional", target: 1000, selected: true, exited: false, consented: true, fact: .init(value: ownValue, state: "complete", recordedAt: start, revision: 1))
        let old = ChallengeV1.Member(actorId: self.departed, username: departed ? "" : "Departedfriend", target: departed ? nil : 2000, selected: true, exited: departed, consented: true, fact: departed ? nil : .init(value: 321, state: "complete", recordedAt: start, revision: 1))
        let other = ChallengeV1.Member(actorId: continuing, username: "Continuingfriend", target: 3000, selected: true, exited: false, consented: true, fact: .init(value: continuingValue, state: "complete", recordedAt: start, revision: 1))
        let result = ChallengeV1.Allocation(outcome: "void", participants: Dictionary(uniqueKeysWithValues: [actor, self.departed, continuing].map { ($0.uuidString.lowercased(), ChallengeV1.Allocation.Person(status: "refunded", returnedCents: 100)) }), own: nil, entryCents: 300, unallocatedCents: 0, simulation: "nonredeemable")
        return ChallengeV1(id: id ?? self.id, creatorId: actor, policy: "friend_steps_goal_v1", config: .init(startDate: "2026-10-03", days: 1, timezone: "UTC", amountCents: 100, startsAt: start, endsAt: end, syncBy: end, correctionsBy: end, noticeDue: end), status: finalized ? "void" : "active", revision: revision, agreementVersion: 1, serverTime: start, socialHidden: false, agreement: agreement, members: [own, old, other], notice: nil, reviews: [], final: finalized ? .init(recordedAt: end, result: result) : nil)
    }
}
@MainActor private final class DepartureResponse<Value: Sendable> {
    var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    func finish(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    func cancel() { continuation?.resume(throwing: ChallengeV1Error.unavailable); continuation = nil }
}
@MainActor private final class DepartureClient: ChallengeV1Client {
    var rows: [ChallengeV1Section: [ChallengeV1]] = [:], holding = false
    var detailRow: ChallengeV1?, detailCalls = 0
    let projection = UUID()
    var pages: [DepartureResponse<ChallengeV1Page>] = [], details: [DepartureResponse<ChallengeV1>] = []
    var cancellations: [() -> Void] = []
    func pageValue(_ section: ChallengeV1Section, rows: [ChallengeV1]? = nil, cursor: ChallengeJSON? = .object(["offset": .integer(1)])) -> ChallengeV1Page {
        ChallengeV1Page(section: section, projectionRevision: projection, serverTime: ChallengeInstant(date: Date()), expiresAt: ChallengeInstant(date: Date().addingTimeInterval(120)), rows: rows ?? self.rows[section] ?? [], nextCursor: cursor)
    }
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        // Hold the initial Active page, preserving the real section/status shape.
        if holding && section == .active { return try await withCheckedThrowingContinuation { let response = DepartureResponse($0); pages.append(response); cancellations.append { response.cancel() } } }
        return pageValue(section)
    }
    func nextPage() async throws -> DepartureResponse<ChallengeV1Page> {
        let deadline = Date().addingTimeInterval(2)
        while pages.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        guard !pages.isEmpty else { throw ChallengeV1Error.unavailable }
        return pages.removeFirst()
    }
    func nextDetail() async throws -> DepartureResponse<ChallengeV1> {
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
        if holding { return try await withCheckedThrowingContinuation { let response = DepartureResponse($0); details.append(response); cancellations.append { response.cancel() } } }
        return try XCTUnwrap(detailRow)
    }
    func list(actor: UUID) async throws -> [ChallengeV1] { [] }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
}
@MainActor private final class DepartureAuth: AuthClient {
    var actor: UUID?; init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}
@MainActor private final class DepartureClock { var value: TimeInterval = 0 }
#endif
