import XCTest
@testable import GameTime

@MainActor final class ChallengeAppConfigurationTests: XCTestCase {
    func testPrivateAccountModeRequiresSelectedStagingBackendAndExplicitFlag() throws {
        for environment in ["debug", "staging", "release"] {
            for host in ["lyushhqoednheqwzsmxh.supabase.co", "historical.example.invalid"] {
                for enabled in ["YES", "NO"] {
                    let config = try AppConfiguration.validated(environmentValue: environment,
                        urlValue: "https://\(host)", keyValue: "sb_publishable_fictional", mutationValue: "NO",
                        challengeV1Value: "YES", privateHealthAccountModeValue: enabled)
                    XCTAssertEqual(config.privateHealthAccountMode,
                        environment == "staging" && host == "lyushhqoednheqwzsmxh.supabase.co" && enabled == "YES")
                }
            }
        }
    }

    func testInvitationOriginIsIndependentOfBackendAndTransport() throws {
        for environment in ["debug", "staging", "release"] {
            let config = try AppConfiguration.validated(environmentValue: environment,
                urlValue: "https://backend.example.invalid", keyValue: "sb_publishable_fictional",
                mutationValue: "NO", invitationHTTPSOriginValue: "https://INVITES.EXAMPLE.INVALID/")
            XCTAssertFalse(config.challengeV1RuntimeEnabled)
            XCTAssertEqual(config.challengeInvitationLinks.httpsOrigin?.absoluteString, "https://invites.example.invalid")
            let token = String(repeating: "b", count: 64)
            XCTAssertEqual(config.challengeInvitationLinks.url(for: token)?.absoluteString,
                           "https://invites.example.invalid/challenge-invite/" + token)
            XCTAssertNil(config.challengeInvitationLinks.token(from: "https://backend.example.invalid/challenge-invite/" + token))
        }
    }

    func testMissingOrMalformedInvitationConfigurationStaysClosedInEveryEnvironment() throws {
        let origins: [String?] = [nil, "", "UNCONFIGURED", "$(GAMETIME_INVITATION_HTTPS_ORIGIN)",
            "http://invites.example.invalid", "https://user:pass@invites.example.invalid",
            "https://invites.example.invalid:443", "https://invites.example.invalid:",
            "https://invites.example.invalid/path", "https://invites.example.invalid?",
            "https://invites.example.invalid#", "https://invites.example.invalid.",
            "https://*.example.invalid", "https://-invites.example.invalid", "https://invites..invalid",
            "https://invites%2eexample.invalid", "https://invіtes.example.invalid", "https://localhost",
            "https://127.0.0.1", "https://[::1]", " https://invites.example.invalid", "https://invites.example.invalid\n"]
        for environment in ["debug", "staging", "release"] {
            for origin in origins {
                let config = try AppConfiguration.validated(environmentValue: environment,
                    urlValue: "https://backend.example.invalid", keyValue: "sb_publishable_fictional",
                    mutationValue: "NO", invitationHTTPSOriginValue: origin)
                XCTAssertNil(config.challengeInvitationLinks.httpsOrigin, origin ?? "missing")
                XCTAssertFalse(config.challengeInvitationLinks.canFormat)
                XCTAssertNil(config.challengeInvitationLinks.url(for: String(repeating: "a", count: 64)))
                XCTAssertFalse(config.challengeV1RuntimeEnabled)
            }
        }
    }

    #if DEBUG || STAGING
    func testAppModelUsesConfiguredInvitationOriginByDefault() throws {
        let configuration = AppConfiguration(environment: .debug, supabaseURL: URL(string: "https://backend.example.invalid")!,
            supabasePublishableKey: "sb_publishable_fictional", contestMutationsEnabled: false,
            invitationHTTPSOrigin: "https://invites.example.invalid")
        let model = AppModel(configuration: configuration, services: FixtureServicesFactory.make(arguments: ["--fixture-mode"]))
        XCTAssertEqual(model.challengeInvitation.links, configuration.challengeInvitationLinks)
    }
    #endif

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
