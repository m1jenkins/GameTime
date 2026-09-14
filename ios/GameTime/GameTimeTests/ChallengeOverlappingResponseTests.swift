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

    func testUnrestrictedLateDetailCannotRestoreOlderGoalTotal() async throws {
        try await unrestrictedDetailOverlap(leaderboard: false)
    }

    func testUnrestrictedLateDetailCannotRestoreOlderLeaderboardRank() async throws {
        try await unrestrictedDetailOverlap(leaderboard: true)
    }

    func testUnrestrictedLatePreFinalDetailCannotReplaceFinalResult() async throws {
        try await unrestrictedDetailOverlap(leaderboard: true, finalized: true)
    }

    func testSupersededDetailSessionRejectionClearsCurrentSession() async throws {
        try await supersededRPCSessionFailure(expireBinding: false, replaceGeneration: false)
    }

    func testSupersededDetailBindingExpiryClearsCurrentSession() async throws {
        try await supersededRPCSessionFailure(expireBinding: true, replaceGeneration: false)
    }

    func testOldDetailSessionFailureCannotClearReplacementGeneration() async throws {
        try await supersededRPCSessionFailure(expireBinding: false, replaceGeneration: true)
    }

    private func supersededRPCSessionFailure(expireBinding: Bool, replaceGeneration: Bool) async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        let latest = fixture.unrestrictedRow(revision: 3, ownValue: 99, leaderboard: false)
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let initialData = try encoder.encode(fixture.shared), latestData = try encoder.encode(latest)
        let rowJSON = try JSONDecoder().decode(ChallengeJSON.self, from: initialData)
        var binding: WeeklyClientSession? = .init(actorID: fixture.actor, identity: "fictional-session")
        let readControl = OverlapReadControl()
        var replies: [OverlapResponse<Data>] = [], allReplies: [OverlapResponse<Data>] = []
        defer { allReplies.forEach { $0.cancel() } }
        let client = SupabaseChallengeV1Client(url: URL(string: "http://127.0.0.1:61321")!, binding: { binding }, rpc: { name, body in
            // Exercise the production decoder/session mapping without a socket,
            // credentials, or a live database. Auth retains its cached actor.
            if name == "challenge_detail_v1" {
                let fields = try JSONDecoder().decode(ChallengeJSON.self, from: body)
                XCTAssertEqual(fields["p_id"]?.string, fixture.id.uuidString.lowercased())
                if readControl.holding {
                    return try await withCheckedThrowingContinuation {
                        let response = OverlapResponse<Data>($0); replies.append(response); allReplies.append(response)
                    }
                }
                return initialData
            }
            if name == "challenge_section_v1" {
                let fields = try JSONDecoder().decode(ChallengeJSON.self, from: body)
                return try ChallengeJSON.data(.object([
                    "section": try XCTUnwrap(fields["p_section"]), "projection_revision": .string(UUID().uuidString),
                    "server_time": try XCTUnwrap(rowJSON["server_time"]), "expires_at": try XCTUnwrap(rowJSON["server_time"]),
                    "rows": .array([rowJSON]), "next_cursor": .null
                ]))
            }
            if name == "challenge_access_status_v1" { return Data(#"{"age_confirmed":true,"beta_access":true,"suspended":false}"#.utf8) }
            if name == "challenge_community_catalog_v1" { return Data("[]".utf8) }
            throw ChallengeV1Error.unavailable
        })
        func nextReply() async throws -> OverlapResponse<Data> {
            let deadline = Date().addingTimeInterval(2)
            while replies.isEmpty && Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
            guard !replies.isEmpty else { throw ChallengeV1Error.unavailable }
            return replies.removeFirst()
        }
        let requests = ChallengeV1RequestStore(directory: fixture.directory)
        try await requests.save(fixture.pending)
        let bytes = try Data(contentsOf: fixture.pendingPath)
        let store = ChallengeV1Store(auth: fixture.auth, client: client, requests: requests, now: { fixture.clock.value })
        store.setActor(fixture.actor); await store.refresh(); await store.loadDetail(fixture.id)
        XCTAssertTrue(store.fresh); XCTAssertEqual(store.challenges, [fixture.shared])
        XCTAssertEqual(store.pending, fixture.pending)
        readControl.holding = true
        let old = Task { await store.loadDetail(fixture.id) }; let oldReply = try await nextReply()
        let current = Task { await store.loadDetail(fixture.id) }; let currentReply = try await nextReply()
        currentReply.finish(latestData); await current.value
        XCTAssertEqual(store.challenges, [latest], "A valid newer response must first become visible")
        if replaceGeneration {
            binding = .init(actorID: fixture.actor, identity: "fictional-replacement")
            store.setActor(fixture.actor); readControl.holding = false; await store.refresh()
            XCTAssertEqual(store.challenges, [fixture.shared])
        } else if expireBinding { binding = nil }
        oldReply.finish(expireBinding ? initialData : Data(#"{"message":"challenge_session_required"}"#.utf8))
        await old.value
        XCTAssertEqual(fixture.auth.actor, fixture.actor, "Server invalidation need not change the cached local actor")
        if replaceGeneration {
            XCTAssertEqual(store.actor, fixture.actor)
            XCTAssertEqual(store.challenges, [fixture.shared], "An old binding cannot invalidate a replaced Store generation")
            XCTAssertTrue(store.fresh)
        } else {
            XCTAssertNil(store.actor)
            XCTAssertTrue(store.sections.isEmpty)
            XCTAssertTrue(store.challenges.isEmpty)
            XCTAssertNil(store.access)
            XCTAssertFalse(store.fresh)
        }
        XCTAssertEqual(try Data(contentsOf: fixture.pendingPath), bytes)
        let pending = try await requests.load(fixture.actor)
        XCTAssertEqual(pending, fixture.pending)
        XCTAssertEqual(try pending?.body, try fixture.pending.body)
    }

    func testSupersededOrdinaryDetailErrorsCannotEraseAcceptedDetail() async throws {
        // Session invalidation is deliberately covered separately through the
        // production client's held RPC boundary, not treated as an ordinary error.
        for failure in [ChallengeV1Error.unavailable] {
            let fixture = OverlapFixture(); defer { fixture.clean() }
            try await fixture.start(allCaches: true)
            let latest = fixture.unrestrictedRow(revision: 3, ownValue: 99, leaderboard: false)
            try latest.validate(actor: fixture.actor)
            let bytes = try Data(contentsOf: fixture.pendingPath)
            fixture.clock.value = 20; fixture.client.holding = true
            let old = Task { await fixture.store.loadDetail(fixture.id) }
            let oldResponse = try await fixture.client.nextDetail()
            fixture.clock.value = 30
            let current = Task { await fixture.store.loadDetail(fixture.id) }
            let currentResponse = try await fixture.client.nextDetail()
            currentResponse.finish(latest); await current.value
            fixture.clock.value = 40
            oldResponse.fail(failure); await old.value
            assertUnrestrictedCopies(fixture, expected: latest)
            XCTAssertEqual(fixture.store.actor, fixture.actor)
            XCTAssertNil(fixture.store.error)
            XCTAssertEqual(fixture.store.pending, fixture.pending)
            XCTAssertEqual(try Data(contentsOf: fixture.pendingPath), bytes)
            fixture.clock.value = 61; fixture.store.purgeExpiredContent()
            XCTAssertEqual(fixture.store.challenges, [latest], "The late error must not erase the independent detail cache")
            XCTAssertTrue(fixture.store.isFresh(latest))
            fixture.clock.value = 90; fixture.store.purgeExpiredContent()
            XCTAssertTrue(fixture.store.challenges.isEmpty)
        }
    }

    func testCurrentDetailFailureStillInvalidatesItsCache() async throws {
        for failure in [ChallengeV1Error.unavailable, .accountChanged] {
            let fixture = OverlapFixture(); defer { fixture.clean() }
            try await fixture.start(allCaches: false)
            fixture.clock.value = 30
            await fixture.store.loadDetail(fixture.id)
            fixture.clock.value = 61; fixture.store.purgeExpiredContent()
            XCTAssertEqual(fixture.store.challenges, [fixture.shared])
            fixture.client.holding = true
            let old = Task { await fixture.store.loadDetail(fixture.id) }
            let oldResponse = try await fixture.client.nextDetail()
            fixture.clock.value = 62
            let current = Task { await fixture.store.loadDetail(fixture.id) }
            let response = try await fixture.client.nextDetail()
            response.fail(failure); await current.value
            XCTAssertTrue(fixture.store.challenges.isEmpty)
            fixture.clock.value = 63
            oldResponse.finish(fixture.shared); await old.value
            XCTAssertTrue(fixture.store.challenges.isEmpty, "An older success cannot undo the latest read's failure")
            if failure == .accountChanged { XCTAssertNil(fixture.store.actor) }
            else {
                XCTAssertEqual(fixture.store.actor, fixture.actor)
                XCTAssertNotNil(fixture.store.error)
            }
        }
    }

    func testDetailSupersessionDoesNotSuppressSafetyRestrictions() async throws {
        for partial in [false, true] {
            for restrictionReturnsFirst in [false, true] {
                let fixture = OverlapFixture(); defer { fixture.clean() }
                try await fixture.start(allCaches: true)
                let restriction = partial ? fixture.departure : fixture.restricted
                try restriction.validate(actor: fixture.actor)
                fixture.clock.value = 20; fixture.client.holding = true
                let old = Task { await fixture.store.loadDetail(fixture.id) }
                let oldResponse = try await fixture.client.nextDetail()
                fixture.clock.value = 30
                let current = Task { await fixture.store.loadDetail(fixture.id) }
                let currentResponse = try await fixture.client.nextDetail()
                if restrictionReturnsFirst {
                    oldResponse.finish(restriction); await old.value
                    currentResponse.finish(fixture.shared); await current.value
                } else {
                    currentResponse.finish(fixture.shared); await current.value
                    oldResponse.finish(restriction); await old.value
                }
                for section in [ChallengeV1Section.action, .upcoming, .history] {
                    XCTAssertEqual(fixture.store.sections[section]?.rows, [restriction])
                    XCTAssertEqual(fixture.store.sections[section]?.receivedAt, 0)
                }
                fixture.clock.value = 61; fixture.store.purgeExpiredContent()
                XCTAssertEqual(fixture.store.challenges, [restriction], "Ordinary request ordering cannot suppress a safety projection or bypass its fence")
                // Restriction remains a fence, not a permanent sharing ban.
                fixture.client.holding = false; fixture.client.detailRow = fixture.shared
                await fixture.store.loadDetail(fixture.id)
                XCTAssertEqual(fixture.store.challenges, [fixture.shared])
            }
        }
    }

    private func unrestrictedDetailOverlap(leaderboard: Bool, finalized: Bool = false) async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        let older = fixture.unrestrictedRow(revision: 1, ownValue: finalized ? 100 : 12_000,
                                            leaderboard: leaderboard, status: finalized ? "review" : "active")
        let latest = fixture.unrestrictedRow(revision: 2, ownValue: 100,
                                             leaderboard: leaderboard, status: finalized ? "final" : "active")
        let unrelated = fixture.row(hidden: false, revision: 3, ownValue: 777, id: fixture.otherID)
        for row in [older, latest, unrelated] {
            try row.validate(actor: fixture.actor)
            XCTAssertFalse(row.socialHidden)
            XCTAssertTrue(row.members.allSatisfy { !$0.exited }, "No privacy restriction may mask ordinary response ordering")
        }
        try await fixture.start(allCaches: true, initial: older)
        let bytes = try Data(contentsOf: fixture.pendingPath)
        assertUnrestrictedCopies(fixture, expected: older)
        if leaderboard {
            XCTAssertEqual(ChallengePresentation.rank(try XCTUnwrap(older.own(fixture.actor)), in: older, actor: fixture.actor), finalized ? 2 : 1)
        }

        fixture.clock.value = 20; fixture.client.holding = true
        let old = Task { await fixture.store.loadDetail(fixture.id) }
        let oldResponse = try await fixture.client.nextDetail()
        fixture.clock.value = 25
        let other = Task { await fixture.store.loadDetail(fixture.otherID) }
        let otherResponse = try await fixture.client.nextDetail()
        fixture.clock.value = 30
        let current = Task { await fixture.store.loadDetail(fixture.id) }
        let currentResponse = try await fixture.client.nextDetail()
        currentResponse.finish(latest); await current.value
        assertUnrestrictedCopies(fixture, expected: latest)
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }?.own(fixture.actor)?.fact?.value, 100,
                       "A newer revision must accept a downward correction")

        fixture.clock.value = 35
        otherResponse.finish(unrelated); await other.value
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.otherID }, unrelated,
                       "Superseding one challenge's read must not discard an unrelated in-flight response")
        assertUnrestrictedCopies(fixture, expected: latest)

        // Both detail calls share one account/refresh generation, and the old
        // request is only 20 seconds old. No refresh, restriction or expiry can
        // accidentally provide the missing supersession guard.
        fixture.clock.value = 40
        oldResponse.finish(older); await old.value
        assertUnrestrictedCopies(fixture, expected: latest)
        let shown = try XCTUnwrap(fixture.store.challenges.first { $0.id == fixture.id })
        XCTAssertEqual(shown.own(fixture.actor)?.fact?.value, 100)
        XCTAssertEqual(shown.own(fixture.actor)?.fact?.revision, finalized ? 1 : 2)
        XCTAssertEqual(shown.status, finalized ? "final" : "active")
        XCTAssertEqual(shown.final, latest.final)
        if leaderboard {
            XCTAssertEqual(ChallengePresentation.rank(try XCTUnwrap(shown.own(fixture.actor)), in: shown, actor: fixture.actor), 2,
                           "The current 100 total must stay behind 321 after the late response")
        }
        XCTAssertTrue(fixture.store.isFresh(latest))
        XCTAssertNil(fixture.store.error)
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.otherID }, unrelated)
        XCTAssertEqual(fixture.store.pending, fixture.pending)
        XCTAssertEqual(try Data(contentsOf: fixture.pendingPath), bytes)
        for section in ChallengeV1Section.allCases {
            XCTAssertEqual(fixture.store.sections[section]?.receivedAt, 0, "Detail reads must not extend section lifetimes")
        }

        // Section copies expire first, exposing the independent detail cache.
        fixture.clock.value = 61; fixture.store.purgeExpiredContent()
        XCTAssertTrue(fixture.store.sections.values.allSatisfy { $0.rows.isEmpty })
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }, latest)
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.otherID }, unrelated)
        fixture.clock.value = 89; fixture.store.purgeExpiredContent()
        XCTAssertTrue(fixture.store.isFresh(latest), "The accepted detail retains its own 60-second lifetime")
        fixture.clock.value = 90; fixture.store.purgeExpiredContent()
        XCTAssertFalse(fixture.store.challenges.contains { $0.id == fixture.id },
                       "The rejected response at 40 must not renew the detail accepted at 30")
        XCTAssertEqual(fixture.store.challenges, [unrelated], "The unrelated detail keeps its own later expiry")
        fixture.clock.value = 95; fixture.store.purgeExpiredContent()
        XCTAssertTrue(fixture.store.challenges.isEmpty)
        XCTAssertEqual(try Data(contentsOf: fixture.pendingPath), bytes)
    }

    private func assertUnrestrictedCopies(_ fixture: OverlapFixture, expected: ChallengeV1,
                                          file: StaticString = #filePath, line: UInt = #line) {
        // start(allCaches:) seeds this ID in these three sections and detail,
        // with an independent challenge in Active. Never use a vacuous allSatisfy.
        for section in [ChallengeV1Section.action, .upcoming, .history] {
            XCTAssertEqual(fixture.store.sections[section]?.rows.filter { $0.id == fixture.id }, [expected],
                           "Every existing section copy must preserve the latest row", file: file, line: line)
        }
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }, expected, file: file, line: line)
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

    func testMountedDetailKeepsCorrectedTotalAndRankAfterLateDetail() async throws {
        try await mountedUnrestrictedDetail(finalized: false)
    }

    func testMountedDetailKeepsFinalResultAfterLatePreFinalDetail() async throws {
        try await mountedUnrestrictedDetail(finalized: true)
    }

    private func mountedUnrestrictedDetail(finalized: Bool) async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        let older = fixture.unrestrictedRow(revision: 1, ownValue: finalized ? 100 : 12_000,
                                            leaderboard: true, status: finalized ? "review" : "active")
        let latest = fixture.unrestrictedRow(revision: 2, ownValue: 100,
                                             leaderboard: true, status: finalized ? "final" : "active")
        try older.validate(actor: fixture.actor); try latest.validate(actor: fixture.actor)
        try await fixture.start(allCaches: false, initial: older)
        // Larger text uses the real participant identity without its decorative
        // avatar, keeping the displayed rank/name legible in the OCR evidence.
        let view = NavigationStack { ChallengeV1Detail(store: fixture.store, id: fixture.id) }
            .environment(\.dynamicTypeSize, .accessibility1)
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(300))
        let name = "ordinary-detail-\(finalized ? "final" : "correction")"
        let before = try await capture(window, controller, name: name + "-before")
        XCTAssertEqual(fixture.client.detailCalls, 2, "The mounted initial read must finish before responses are held")
        XCTAssertTrue(before.contains("sharedfriend"))
        XCTAssertFalse(before.contains("result confirmed"))
        if finalized { XCTAssertTrue(before.contains("latest result update")) }
        else {
            XCTAssertTrue(before.contains("12,000"))
            XCTAssertNotNil(before.range(of: #"\b1\s+you\b"#, options: .regularExpression))
        }
        fixture.clock.value = 20; fixture.client.holding = true
        let old = Task { await fixture.store.loadDetail(fixture.id) }
        let oldResponse = try await fixture.client.nextDetail()
        fixture.clock.value = 30
        let current = Task { await fixture.store.loadDetail(fixture.id) }
        let currentResponse = try await fixture.client.nextDetail()
        currentResponse.finish(latest); await current.value
        let calls = fixture.client.detailCalls
        XCTAssertEqual(calls, 4, "Only the two deliberately overlapping reads may start")
        try await Task.sleep(for: .milliseconds(300))
        let corrected = try await capture(window, controller, name: name + "-accepted")
        assertMountedCorrection(corrected, finalized: finalized)
        fixture.clock.value = 40
        oldResponse.finish(older); await old.value
        try await Task.sleep(for: .milliseconds(300))
        let late = try await capture(window, controller, name: name + "-after-late-response")
        assertMountedCorrection(late, finalized: finalized)
        XCTAssertEqual(fixture.client.detailCalls, calls, "No extra fetch or remount can conceal the late response")
        XCTAssertEqual(fixture.store.challenges.first { $0.id == fixture.id }, latest)
        XCTAssertNotNil(controller.view.window)
    }

    private func assertMountedCorrection(_ text: String, finalized: Bool,
                                         file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(text.contains("12,000"), file: file, line: line)
        XCTAssertNotNil(text.range(of: #"\b100\s+steps\b"#, options: .regularExpression), file: file, line: line)
        XCTAssertNotNil(text.range(of: #"\b2\s+you\b"#, options: .regularExpression), file: file, line: line)
        XCTAssertTrue(text.contains("sharedfriend"), file: file, line: line)
        XCTAssertEqual(text.contains("result confirmed"), finalized, file: file, line: line)
    }

    private func mounted(detail: Bool, revision: Int) async throws {
        let fixture = OverlapFixture(); defer { fixture.clean() }
        try await fixture.start(allCaches: false)
        let view = detail ? AnyView(NavigationStack { ChallengeV1Detail(store: fixture.store, id: fixture.id) }.environment(\.dynamicTypeSize, .accessibility1)) :
            AnyView(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}))
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        window.rootViewController = controller; window.makeKeyAndVisible(); controller.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(300))
        let name = "overlap-\(detail ? "detail" : "home")-old-revision-\(revision)"
        let before = try await capture(window, controller, name: name + "-shared")
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
        let restricted = try await capture(window, controller, name: name + "-restricted")
        if detail { XCTAssertFalse(restricted.contains("sharedfriend")); XCTAssertFalse(restricted.contains("321 of 2,000 steps")) }
        else { XCTAssertTrue(restricted.contains("you left this challenge")); XCTAssertTrue(restricted.contains("507")) }
        fixture.clock.value = 40
        responseA.finish(fixture.client.pageValue(.active, rows: [fixture.row(hidden: false, revision: revision)], cursor: nil)); await a.value
        try await Task.sleep(for: .milliseconds(300))
        let late = try await capture(window, controller, name: name + "-after-late-response")
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

    private func capture(_ window: UIWindow, _ controller: UIViewController, name: String) async throws -> String {
        try await captureMountedSignal(window, controller: controller, name: name, test: self)
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
    lazy var departure: ChallengeV1 = {
        let base = shared
        let members = base.members.map { member in
            member.actorId == actor ? member : ChallengeV1.Member(actorId: member.actorId,
                username: "", target: nil, selected: member.selected, exited: true,
                consented: member.consented, fact: nil)
        }
        return ChallengeV1(id: base.id, creatorId: base.creatorId, policy: base.policy,
            config: base.config, status: base.status, revision: base.revision,
            agreementVersion: base.agreementVersion, serverTime: base.serverTime,
            socialHidden: false, agreement: base.agreement, members: members,
            notice: base.notice, reviews: base.reviews, final: base.final)
    }()
    lazy var unrelated = row(hidden: false, revision: 2, ownValue: 507, id: otherID)
    lazy var pending = ChallengeV1Request(actor: actor, payload: .object(["op": .string("leave"), "id": .string(id.uuidString.lowercased()), "revision": .integer(2)]))
    var pendingPath: URL { directory.appendingPathComponent(actor.uuidString.lowercased() + ".json") }
    func start(allCaches: Bool, initial: ChallengeV1? = nil) async throws {
        let startingRow = initial ?? shared
        client.rows[.active] = allCaches ? [unrelated] : [startingRow, unrelated]
        if allCaches { for section in [ChallengeV1Section.action, .upcoming, .history] { client.rows[section] = [startingRow] } }
        client.detailRow = startingRow; try await store.requests.save(pending)
        store.setActor(actor); await store.refresh(); await store.loadDetail(id)
        try startingRow.validate(actor: actor); try restricted.validate(actor: actor)
        XCTAssertEqual(store.access?.suspended, false)
    }
    func clean() { client.cancelPending(); try? FileManager.default.removeItem(at: directory) }
    func unrestrictedRow(revision: Int, ownValue: Int, leaderboard: Bool, status: String = "active") -> ChallengeV1 {
        let base = row(hidden: false, revision: revision, ownValue: ownValue)
        let members = base.members.map { member in
            ChallengeV1.Member(actorId: member.actorId, username: member.username,
                target: leaderboard ? nil : member.target, selected: member.selected,
                exited: member.exited, consented: member.consented,
                fact: member.fact.map { fact in
                    ChallengeV1.Fact(value: fact.value, state: fact.state, recordedAt: fact.recordedAt,
                                     revision: member.actorId == actor && status == "active" ? revision : fact.revision)
                })
        }
        // Review/final share unchanged facts and a full 48-hour review window.
        // In both, the leaderboard's 100 trails 321; only finality changes.
        let result = ChallengeV1.Allocation(outcome: "scored", participants: [
                actor.uuidString.lowercased(): .init(status: "placed", returnedCents: 0),
                friend.uuidString.lowercased(): .init(status: "winner", returnedCents: 200)
            ], own: nil, entryCents: 200, unallocatedCents: 0, simulation: "nonredeemable")
        let reviewStart = ChallengeInstant(date: base.config.endsAt.date.addingTimeInterval(72 * 60 * 60))
        let reviewEnd = ChallengeInstant(date: reviewStart.date.addingTimeInterval(48 * 60 * 60))
        let notice: ChallengeV1.Notice? = status == "active" ? nil :
            .init(revision: 1, recordedAt: reviewStart, reviewBy: reviewEnd, result: result)
        let final: ChallengeV1.Final? = status == "final" ? .init(recordedAt: reviewEnd, result: result) : nil
        let serverTime = status == "active" ? base.serverTime :
            ChallengeInstant(date: reviewEnd.date.addingTimeInterval(status == "review" ? -1 : 0))
        return ChallengeV1(id: base.id, creatorId: base.creatorId,
            policy: leaderboard ? "friend_steps_leaderboard_v1" : base.policy, config: base.config,
            status: status, revision: revision,
            agreementVersion: base.agreementVersion, serverTime: serverTime, socialHidden: false,
            agreement: base.agreement, members: members, notice: notice, reviews: [], final: final)
    }
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
    func fail(_ error: ChallengeV1Error) { continuation?.resume(throwing: error); continuation = nil }
    func cancel() { fail(.unavailable) }
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
@MainActor private final class OverlapReadControl { var holding = false }
#endif
