import XCTest
@testable import GameTime

@MainActor final class ChallengeAppConfigurationTests: XCTestCase {
    func testPrivateAccountModeRequiresSelectedStagingBackendAndExplicitFlag() throws {
        for environment in ["debug", "staging", "release", "testflight"] {
            for host in ["lyushhqoednheqwzsmxh.supabase.co", "historical.example.invalid"] {
                for enabled in ["YES", "NO"] {
                    let config = try AppConfiguration.validated(environmentValue: environment,
                        urlValue: "https://\(host)", keyValue: "sb_publishable_fictional", mutationValue: "NO",
                        challengeV1Value: "YES", privateHealthAccountModeValue: enabled)
                    XCTAssertEqual(config.privateHealthAccountMode,
                        ["staging", "testflight"].contains(environment) && host == "lyushhqoednheqwzsmxh.supabase.co" && enabled == "YES")
                }
            }
        }
    }

    /// D142: the TestFlight build is production-signed, creates only the new
    /// challenges, keeps its own backend storage and can't select Stripe.
    func testTestFlightConfigurationHasNoPaymentProviderOrLegacyCreation() throws {
        let config = try AppConfiguration.validated(environmentValue: "testflight",
            urlValue: "https://lyushhqoednheqwzsmxh.supabase.co", keyValue: "sb_publishable_fictional", mutationValue: "YES",
            settlementModeValue: "test_only", challengeV1Value: "YES", privateHealthAccountModeValue: "YES")
        XCTAssertTrue(config.challengeV1RuntimeEnabled)
        XCTAssertTrue(config.privateHealthAccountMode)
        XCTAssertFalse(config.contestMutationsEnabled)
        XCTAssertFalse(config.personalChallengeMutationsEnabled)
        XCTAssertFalse(config.allowsActiveSandboxChallengeCancellation)
        XCTAssertEqual(config.expectedAppAttestEnvironment, .production)
        XCTAssertTrue(config.usesBackendScopedStorage)
        XCTAssertEqual(config.appAttestStorageNamespace, "lyushhqoednheqwzsmxh.supabase.co")
        XCTAssertThrowsError(try AppConfiguration.validated(environmentValue: "testflight",
            urlValue: "https://lyushhqoednheqwzsmxh.supabase.co", keyValue: "sb_publishable_fictional", mutationValue: "NO",
            settlementModeValue: "stripe_sandbox", stripeReturnURLValue: "gametime-beta://stripe-redirect"))
        let historical = try AppConfiguration.validated(environmentValue: "testflight",
            urlValue: "https://historical.example.invalid", keyValue: "sb_publishable_fictional", mutationValue: "NO",
            challengeV1Value: "YES", privateHealthAccountModeValue: "YES")
        XCTAssertFalse(historical.privateHealthAccountMode, "Account mode stays on the P11B backend")
    }

    /// D144 commitments are a build decision: Staging keeps them for sandbox
    /// testing, TestFlight and Release never offer them, even when asked.
    func testCommitmentsAreOnForStagingAndOffForTestFlightAndRelease() throws {
        func config(_ environment: String, _ value: String?) throws -> AppConfiguration {
            try AppConfiguration.validated(environmentValue: environment,
                urlValue: "https://lyushhqoednheqwzsmxh.supabase.co", keyValue: "sb_publishable_fictional", mutationValue: "NO",
                challengeV1Value: "YES", privateHealthAccountModeValue: "YES", challengeCommitmentsValue: value)
        }
        XCTAssertTrue(try config("staging", "YES").challengeCommitmentsEnabled)
        XCTAssertFalse(try config("staging", "NO").challengeCommitmentsEnabled)
        XCTAssertFalse(try config("staging", nil).challengeCommitmentsEnabled)
        XCTAssertFalse(try config("testflight", "NO").challengeCommitmentsEnabled)
        XCTAssertFalse(try config("testflight", "YES").challengeCommitmentsEnabled, "TestFlight refuses commitments even if asked")
        XCTAssertFalse(try config("release", "YES").challengeCommitmentsEnabled)
        let noTransport = try AppConfiguration.validated(environmentValue: "staging",
            urlValue: "https://lyushhqoednheqwzsmxh.supabase.co", keyValue: "sb_publishable_fictional", mutationValue: "NO",
            challengeV1Value: "NO", challengeCommitmentsValue: "YES")
        XCTAssertFalse(noTransport.challengeCommitmentsEnabled, "no commitments without challenge transport")
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

    /// With the build switch off the client never reaches card setup or the
    /// commitment offer, but can still show a goal's existing commitment.
    func testClientWithoutCommitmentsNeverCallsSetupOrOffer() async throws {
        let actor = UUID()
        var rpcs: [String] = [], functions: [String] = []
        let client = SupabaseChallengeV1Client(url: URL(string: "https://beta.example.invalid")!, permitsHTTPS: true,
            binding: { .init(actorID: actor, identity: "token") },
            rpc: { name, _ in rpcs.append(name); return Data(#"{"challenge_id":"\#(UUID().uuidString)","amount_cents":2000,"state":"committed"}"#.utf8) },
            function: { name, _ in functions.append(name); throw ChallengeV1Error.unavailable })
        XCTAssertFalse(client.commitmentsEnabled)
        do { _ = try await client.commitmentSetup(request: UUID(), amountCents: 2_000, actor: actor); XCTFail("setup must not send") }
        catch { XCTAssertEqual(error as? ChallengeV1Error, .unavailable) }
        for name in ["challenge_commitment_availability_v1", "challenge_commitment_preview_v1"] {
            do { _ = try await client.read(name, fields: [:], actor: actor, as: ChallengeCommitment.Availability.self); XCTFail("\(name) must not send") }
            catch { XCTAssertEqual(error as? ChallengeV1Error, .unavailable) }
        }
        let committed = ChallengeV1Request(actor: actor, payload: .object(["op": .string("personal_commit"),
            "commitment_setup_id": .string(UUID().uuidString.lowercased())]))
        do { _ = try await client.submit(committed); XCTFail("a commitment must not be sent") }
        catch { XCTAssertEqual(error as? ChallengeV1Error, .unavailable) }
        XCTAssertEqual(functions, []); XCTAssertEqual(rpcs, [])
        let status = try await client.read("challenge_commitment_status_v1", fields: [:], actor: actor, as: ChallengeCommitment.Status.self)
        XCTAssertEqual(status.state, "committed")
        XCTAssertEqual(rpcs, ["challenge_commitment_status_v1"])

        let staging = SupabaseChallengeV1Client(url: URL(string: "https://beta.example.invalid")!, permitsHTTPS: true, commitments: true,
            binding: { .init(actorID: actor, identity: "token") }, rpc: { _, _ in Data() },
            function: { name, _ in functions.append(name); throw ChallengeV1Error.unavailable })
        _ = try? await staging.commitmentSetup(request: UUID(), amountCents: 2_000, actor: actor)
        XCTAssertEqual(functions, ["challenge-commitment-setup"])
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
