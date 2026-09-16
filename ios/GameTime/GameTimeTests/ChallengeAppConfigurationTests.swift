import XCTest
@testable import GameTime

@MainActor final class ChallengeAppConfigurationTests: XCTestCase {
    func testOrdinaryChallengeTransportRequiresExplicitConfiguration() throws {
        for environment in ["debug", "staging", "release"] {
            for value in [nil, "NO", "UNCONFIGURED", "$(GAMETIME_CHALLENGE_V1_ENABLED)"] {
                let config = try configuration(environment, "https://beta.example.invalid", value)
                XCTAssertFalse(config.challengeV1RuntimeEnabled)
            }
            XCTAssertTrue(try configuration(environment, "https://beta.example.invalid", "YES").challengeV1RuntimeEnabled)
        }
    }

    func testOnlyAnHTTPSOriginOrExplicitDevelopmentLoopbackCanSend() throws {
        for text in ["https://user:pass@beta.example.invalid", "https://beta.example.invalid/path",
                     "https://beta.example.invalid?redirect=x", "https://beta.example.invalid#fragment",
                     "https://beta.example.invalid:444", "http://192.168.1.2:61321", "http://127.0.0.1"] {
            XCTAssertFalse(try configuration("debug", text, "YES").challengeV1RuntimeEnabled, text)
        }
        XCTAssertTrue(try configuration("debug", "http://127.0.0.1:61321", "YES").challengeV1RuntimeEnabled)
        let release = AppConfiguration(environment: .release, supabaseURL: URL(string: "http://127.0.0.1:61321")!,
            supabasePublishableKey: "sb_publishable_fictional", contestMutationsEnabled: false, challengeV1Requested: true)
        XCTAssertFalse(release.challengeV1RuntimeEnabled)
    }

    func testConfiguredHTTPSUsesTheExistingActorAndExactRequestBytes() async throws {
        let actor = UUID()
        let request = ChallengeV1Request(actor: actor, payload: .object(["op": .string("confirm_age"), "confirmed": .bool(true)]))
        var calls = 0
        let client = SupabaseChallengeV1Client(url: URL(string: "https://beta.example.invalid")!, permitsHTTPS: true,
            binding: { .init(actorID: actor, identity: "token") }, rpc: { name, body in
                calls += 1
                XCTAssertEqual(name, "challenge_command_v1")
                XCTAssertEqual(body, try request.body)
                return Data(#"{"confirmed":true}"#.utf8)
            })
        let receipt = try await client.submit(request)
        XCTAssertEqual(receipt.confirmed, true)
        let retry = try await client.submit(request)
        XCTAssertEqual(retry, receipt)
        do { _ = try await client.list(actor: UUID()); XCTFail("Wrong actor must not send") }
        catch { XCTAssertEqual(error as? ChallengeV1Error, .accountChanged) }
        XCTAssertEqual(calls, 2)
    }

    func testExpiredSessionPreparationCannotSendOrConsumePendingAction() async throws {
        let actor = UUID()
        var calls = 0
        let client = SupabaseChallengeV1Client(url: URL(string: "https://beta.example.invalid")!, permitsHTTPS: true,
            prepareSession: { _ in throw ChallengeV1Error.accountChanged },
            binding: { .init(actorID: actor, identity: "expired") }, rpc: { _, _ in calls += 1; return Data() })
        let auth = WeeklyTestAuth(actor)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let queue = ChallengeV1RequestStore(directory: directory)
        let request = ChallengeV1Request(actor: actor, payload: .object(["op": .string("confirm_age"), "confirmed": .bool(true)]))
        try await queue.save(request)
        let store = ChallengeV1Store(auth: auth, client: client, requests: queue)
        store.setActor(actor)
        await store.refresh()
        XCTAssertNil(store.actor)
        XCTAssertTrue(store.challenges.isEmpty)
        let saved = try await queue.load(actor)
        XCTAssertEqual(saved, request)
        XCTAssertEqual(calls, 0)
    }

    private func configuration(_ environment: String, _ url: String, _ value: String?) throws -> AppConfiguration {
        try AppConfiguration.validated(environmentValue: environment, urlValue: url,
            keyValue: "sb_publishable_fictional", mutationValue: "NO", challengeV1Value: value)
    }
}
