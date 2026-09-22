#if DEBUG
import XCTest
@testable import GameTime

/// The presentation fixture must go through the same store, request journal and
/// agreement projection as the app. It must not manufacture production records.
@MainActor
final class LiveDesignPresentationTests: XCTestCase {
    private let actor = LiveDesignFixtures.actorID

    func testFixturePagesFeedRealStoreAndPreserveUnknownActivity() async throws {
        let client = LiveDesignFixtureClient()
        let (store, folder) = makeStore(client)
        defer { try? FileManager.default.removeItem(at: folder) }
        await store.refresh()

        XCTAssertTrue(store.fresh)
        XCTAssertTrue(store.entryFresh)
        XCTAssertEqual(store.homeState, .content)
        XCTAssertEqual(store.sections[.active]?.rows.map(\.id), [LiveDesignFixtures.activeID])
        XCTAssertEqual(store.sections[.action]?.rows.map(\.id), [LiveDesignFixtures.invitationID])
        XCTAssertEqual(store.sections[.upcoming]?.rows.map(\.id), [LiveDesignFixtures.upcomingID])
        XCTAssertEqual(store.profileSnapshot.finished.count, 3)
        XCTAssertEqual(store.profileSnapshot.availability, .complete)

        let active = try await client.detail(LiveDesignFixtures.activeID, actor: actor)
        XCTAssertEqual(active.savedScore(try XCTUnwrap(active.own(actor))), 6_400_000)
        XCTAssertEqual(active.own(actor)?.target, 20_000_000)
        XCTAssertEqual(active.members.map(\.username), ["alexlee", "Sam", "Jordan", "Priya"])
        let closed = try await client.detail(LiveDesignFixtures.closedID, actor: actor)
        XCTAssertNil(closed.own(actor)?.fact)
        XCTAssertTrue(closed.own(actor)?.exited == true)
        let upcoming = try await client.detail(LiveDesignFixtures.upcomingID, actor: actor)
        XCTAssertNil(upcoming.own(actor)?.fact)
        for row in store.challenges { try row.validate(actor: actor) }
        XCTAssertTrue(store.challenges.allSatisfy { $0.config.amountCents == 2_000 })
        XCTAssertNil(LiveDesignFixtures.displayTitle(for: UUID()))
        XCTAssertNil(LiveDesignFixtures.portraitName(for: UUID()))
        XCTAssertEqual(LiveDesignFixtures.displayTitle(for: active.id), "September runs")
        let profile = try await LiveDesignFixtures.makeProfileClient().currentProfile(userID: actor)
        XCTAssertEqual(profile?.displayName, "Alex Lee")
    }

    func testConsentRequiresExactAgreementAndReplaysOnce() async throws {
        let client = LiveDesignFixtureClient()
        let row = try await client.detail(LiveDesignFixtures.invitationID, actor: actor)
        let base: [String: ChallengeJSON] = ["op": .string("consent"), "id": .string(row.id.uuidString.lowercased()),
            "revision": .integer(row.revision), "digest": .string(try XCTUnwrap(row.agreement?.digest))]
        do {
            _ = try await client.submit(.init(actor: actor, payload: .object(base)))
            XCTFail("Opening a review must not imply consent")
        } catch { XCTAssertEqual(error as? ChallengeV1Error, .server("challenge_consent_mismatch")) }
        var fields = base; fields["consent"] = .bool(true)
        let request = ChallengeV1Request(actor: actor, payload: .object(fields))
        let receipt = try await client.submit(request)
        XCTAssertEqual(receipt.status, "scheduled")
        let repeated = try await client.submit(request)
        XCTAssertEqual(repeated, receipt)
        let accepted = try await client.detail(row.id, actor: actor)
        XCTAssertEqual(accepted.revision, row.revision + 1)
        XCTAssertTrue(accepted.own(actor)?.consented == true)
        do {
            _ = try await client.detail(row.id, actor: UUID())
            XCTFail("The fixture must preserve actor isolation")
        } catch { XCTAssertEqual(error as? ChallengeV1Error, .accountChanged) }
    }

    func testExitPreservesRecordAndLeavesOtherParticipantsIntact() async throws {
        let client = LiveDesignFixtureClient()
        let (store, folder) = makeStore(client)
        defer { try? FileManager.default.removeItem(at: folder) }
        await store.refresh()
        let row = try XCTUnwrap(store.challenges.first { $0.id == LiveDesignFixtures.activeID })
        let receipt = await store.submit(op: "leave", challenge: row)
        XCTAssertNotNil(receipt)
        XCTAssertNil(store.pending)
        XCTAssertEqual(store.sections[.history]?.rows.first { $0.id == row.id }?.own(actor)?.exited, true)
        let departed = try await client.detail(row.id, actor: actor)
        XCTAssertEqual(departed.status, "active")
        XCTAssertEqual(departed.members.filter { !$0.exited }.count, 3)
        XCTAssertNil(departed.final)
    }

    func testReviewUsesNoticeRevisionAndFullWindow() async throws {
        let now = try ChallengeInstant("2026-10-01T09:00:00-07:00")
        let client = LiveDesignFixtureClient(now: now)
        try client.seedReview(for: LiveDesignFixtures.activeID)
        let row = try await client.detail(LiveDesignFixtures.activeID, actor: actor)
        let notice = try XCTUnwrap(row.notice)
        XCTAssertEqual(notice.reviewBy.microseconds - now.microseconds, 48 * 3_600_000_000)
        let request = ChallengeV1Request(actor: actor, payload: .object([
            "op": .string("review"), "id": .string(row.id.uuidString.lowercased()), "revision": .integer(row.revision),
            "notice_revision": .integer(notice.revision), "reason": .string("missing_activity")]))
        let receipt = try await client.submit(request)
        let repeated = try await client.submit(request)
        XCTAssertEqual(repeated, receipt)
        let reviewed = try await client.detail(row.id, actor: actor)
        XCTAssertEqual(reviewed.reviews.count, 1)
        XCTAssertEqual(reviewed.reviews.first?.resolveBy.microseconds, now.microseconds + 72 * 3_600_000_000)
        XCTAssertNil(reviewed.final)
    }

    func testPersonalCreationRequiresPreviewDigestAndValidAmount() async throws {
        let client = LiveDesignFixtureClient()
        let config: ChallengeJSON = .object(["start_date": .string("2026-10-12"), "days": .integer(7),
            "timezone": .string("America/Los_Angeles"), "amount_cents": .integer(2_000)])
        let agreement = try await client.read("challenge_personal_preview_v1", fields: [
            "p_policy": .string("personal_steps_goal_v1"), "p_config": config, "p_target": .integer(50_000)],
            actor: actor, as: ChallengeV1.Agreement.self)
        var fields: [String: ChallengeJSON] = ["op": .string("personal_commit"), "policy": .string("personal_steps_goal_v1"),
            "config": config, "target": .integer(50_000), "consent": .bool(true), "digest": .string("changed")]
        do {
            _ = try await client.submit(.init(actor: actor, payload: .object(fields)))
            XCTFail("A changed preview cannot be accepted")
        } catch { XCTAssertEqual(error as? ChallengeV1Error, .server("challenge_consent_mismatch")) }
        fields["digest"] = .string(agreement.digest)
        let request = ChallengeV1Request(actor: actor, payload: .object(fields))
        let receipt = try await client.submit(request)
        let created = try await client.detail(try XCTUnwrap(receipt.id), actor: actor)
        XCTAssertEqual(created.status, "scheduled")
        XCTAssertEqual(created.agreement?.digest, agreement.digest)
        XCTAssertEqual(created.own(actor)?.target, 50_000)
        let repeated = try await client.submit(request)
        XCTAssertEqual(repeated.id, created.id)
        try created.validate(actor: actor)
    }

    func testLinkReceiptUsesExistingJournalAndStoppedRequestCannotCreate() async throws {
        let client = LiveDesignFixtureClient()
        let (store, folder) = makeStore(client)
        defer { try? FileManager.default.removeItem(at: folder) }
        await store.refresh()
        let config: ChallengeJSON = .object(["start_date": .string("2026-10-12"), "days": .integer(7),
            "timezone": .string("America/Los_Angeles"), "amount_cents": .integer(2_000)])
        let created = await store.submit(op: "create", fields: ["policy": .string("friend_steps_goal_v1"), "config": config])
        let id = try XCTUnwrap(created?.id)
        let issued = await store.submit(op: "issue_link", fields: ["id": .string(id.uuidString.lowercased())])
        XCTAssertTrue(ChallengeInvitation.isValidToken(try XCTUnwrap(issued?.token)))
        XCTAssertEqual(store.issuedLinks.first?.challengeId, id)
        XCTAssertNil(store.pending)
        let revoked = await store.submit(op: "revoke_link", fields: ["id": .string(try XCTUnwrap(issued?.id).uuidString.lowercased())])
        XCTAssertEqual(revoked?.revoked, true)
        XCTAssertTrue(store.issuedLinks.isEmpty)
        let stopped = ChallengeV1Request(actor: actor, payload: .object([
            "op": .string("create"), "policy": .string("friend_steps_goal_v1"), "config": config]))
        let cancellation = try await client.abandon(stopped)
        let late = try await client.submit(stopped)
        XCTAssertEqual(late, cancellation)
        XCTAssertNil(late.id)
        XCTAssertEqual(late.status, "cancelled_request")
    }

    private func makeStore(_ client: LiveDesignFixtureClient) -> (ChallengeV1Store, URL) {
        let services = FixtureServicesFactory.make(arguments: [], profileClient: LiveDesignFixtures.makeProfileClient(), challengesV1: client)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("live-design-" + UUID().uuidString)
        let store = ChallengeV1Store(auth: services.auth, client: client, requests: .init(directory: folder), now: { 100 })
        store.setActor(actor)
        return (store, folder)
    }
}
#endif
