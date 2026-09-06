import XCTest
import Supabase
@testable import GameTime

@MainActor
final class PerformanceCommitmentClientTests: XCTestCase {
    private let localURL = URL(string: "http://127.0.0.1:57321")!

    func testProductionBoundaryRejectsHostedImplicitPortAndURLCredentials() async throws {
        let fixture = try CommitmentStoreFixture()
        for value in ["https://example.supabase.co", "http://127.0.0.1", "http://127.0.0.1:57321/path",
                      "http://user@localhost:57321", "http://localhost:57321?redirect=hosted", "http://127.0.0.1.example.com:57321"] {
            let client = make(fixture.actor, url: URL(string: value)!) { _, _ in
                XCTFail("Rejected endpoint must never receive a request")
                return Data()
            }
            do { _ = try await client.list(actorID: fixture.actor, before: nil); XCTFail(value) }
            catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .accessDenied) }
        }
        XCTAssertTrue(SupabasePerformanceCommitmentClient.isExplicitLoopback(localURL))
    }

    func testDisabledClientCannotSendWithValidLocalActor() async throws {
        let fixture = try CommitmentStoreFixture()
        let client = SupabasePerformanceCommitmentClient(enabled: false, localURL: localURL,
            currentSession: { .init(actorID: fixture.actor, identity: "session-a") }, rpc: { _, _ in
                XCTFail("Disabled transport sent a request"); return Data()
            })
        do { _ = try await client.preview(fixture.draft, actorID: fixture.actor); XCTFail("Disabled preview") }
        catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .accessDenied) }
    }

    func testProductionInitializerRejectsServiceSecretAndLegacyKeysBeforeSessionLookup() async throws {
        let fixture = try CommitmentStoreFixture()
        for key in ["sb_secret_fictional", "fictional-service-role-jwt", "", "sb_publishable"] {
            let supabase = SupabaseClient(supabaseURL: localURL, supabaseKey: key,
                options: .init(auth: .init(storage: CommitmentClientEmptyAuthStorage(), autoRefreshToken: false)))
            let client = SupabasePerformanceCommitmentClient(client: supabase, enabled: true,
                localURL: localURL, publishableKey: key)
            do { _ = try await client.list(actorID: fixture.actor, before: nil); XCTFail("Unsafe key accepted") }
            catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .accessDenied) }
        }
    }

    func testMutationSendsCompleteSavedBytesAndPaginationPreservesMicroseconds() async throws {
        let fixture = try CommitmentStoreFixture()
        let request = try PendingPerformanceCommitmentRequest(actorID: fixture.actor, operation: fixture.create)
        var sent: [(String, Data)] = []
        let client = make(fixture.actor) { name, body in
            sent.append((name, body))
            return name == "create_performance_commitment_v1"
                ? try JSONEncoder().encode(fixture.agreement.id) : Data("[]".utf8)
        }
        let receipt = try await client.submit(request)
        XCTAssertEqual(receipt, .commitment(fixture.agreement.id))
        XCTAssertEqual(sent.first?.1, request.requestBody)
        _ = try await client.list(actorID: fixture.actor, before: fixture.agreement)
        let parameters = try JSONDecoder().decode([String: PerformanceCommitmentParameter].self, from: sent[1].1)
        XCTAssertEqual(parameters["p_before"], .string(fixture.agreement.createdAt.rawValue))
        XCTAssertEqual(parameters["p_before_id"], .string(fixture.agreement.id.uuidString.lowercased()))
        let envelope = String(decoding: try JSONEncoder().encode(request), as: UTF8.self)
        XCTAssertFalse(envelope.contains("session-a"))
        XCTAssertFalse(envelope.contains("accessToken"))
    }

    func testChangedOrRevokedSessionRejectsResponseEvenWhenActorMatches() async throws {
        let fixture = try CommitmentStoreFixture()
        for replacement in [PerformanceCommitmentClientSession(actorID: fixture.actor, identity: "session-b"), nil] {
            var session: PerformanceCommitmentClientSession? = .init(actorID: fixture.actor, identity: "session-a")
            let client = SupabasePerformanceCommitmentClient(enabled: true, localURL: localURL,
                currentSession: { session }, rpc: { _, _ in
                    session = replacement
                    return try JSONEncoder().encode([fixture.agreement])
                })
            do { _ = try await client.list(actorID: fixture.actor, before: nil); XCTFail("Stale session response") }
            catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .accountChanged) }
        }
    }

    func testPreviewRejectsServerTermsForDifferentDraft() async throws {
        let fixture = try CommitmentStoreFixture()
        let client = make(fixture.actor) { _, _ in try JSONEncoder().encode(fixture.preview) }
        let different = PerformanceCommitmentDraft(targetSeconds: fixture.draft.targetSeconds + 1,
            startsAt: fixture.draft.startsAt, deadlineAt: fixture.draft.deadlineAt, displayTimezone: fixture.draft.displayTimezone)
        do { _ = try await client.preview(different, actorID: fixture.actor); XCTFail("Unbound terms") }
        catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .invalidResponse) }
    }

    func testReviewReceiptIsTypedSeparatelyAndCloseReceiptMustMatchCommitment() async throws {
        let fixture = try CommitmentStoreFixture()
        let review = PerformanceCommitmentReviewReceipt(caseID: UUID(), recordedAt: fixture.lifecycle.serverNow)
        let client = make(fixture.actor) { name, _ in
            if name == "file_commitment_review_v1" { return try JSONEncoder().encode(review) }
            return try JSONEncoder().encode(UUID())
        }
        let request = try PendingPerformanceCommitmentRequest(actorID: fixture.actor,
            operation: .fileReview(commitmentID: fixture.agreement.id, revision: 2, reason: .wrongResult))
        let receipt = try await client.submit(request)
        XCTAssertEqual(receipt, .review(review))
        let close = try PendingPerformanceCommitmentRequest(actorID: fixture.actor,
            operation: .close(commitmentID: fixture.agreement.id, reason: .injury))
        do { _ = try await client.submit(close); XCTFail("Unbound close receipt") }
        catch { XCTAssertEqual(error as? PerformanceCommitmentClientError, .invalidResponse) }
    }

    func testInvalidPayloadAndActorTamperingFailBeforeTransport() async throws {
        let fixture = try CommitmentStoreFixture()
        let original = try PendingPerformanceCommitmentRequest(actorID: fixture.actor, operation: fixture.create)
        for (field, value): (String, Any) in [("kind", "duel_request_v1"), ("version", 2),
                ("requestBody", Data("{}".utf8).base64EncodedString()), ("actorID", UUID().uuidString)] {
            var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            raw[field] = value
            let changed = try JSONDecoder().decode(PendingPerformanceCommitmentRequest.self,
                from: JSONSerialization.data(withJSONObject: raw))
            XCTAssertThrowsError(try changed.validate(for: fixture.actor))
        }
    }

    private func make(_ actor: UUID, url: URL? = nil,
                      rpc: @escaping @MainActor (String, Data) async throws -> Data) -> SupabasePerformanceCommitmentClient {
        SupabasePerformanceCommitmentClient(enabled: true, localURL: url ?? localURL,
            currentSession: { .init(actorID: actor, identity: "session-a") }, rpc: rpc)
    }
}

private struct CommitmentClientEmptyAuthStorage: AuthLocalStorage {
    func store(key: String, value: Data) throws {}
    func retrieve(key: String) throws -> Data? { nil }
    func remove(key: String) throws {}
}
