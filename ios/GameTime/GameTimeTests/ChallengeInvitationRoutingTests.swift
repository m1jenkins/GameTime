#if DEBUG
import XCTest
@testable import GameTime

@MainActor final class ChallengeInvitationRoutingTests: XCTestCase {
    func testColdDeliverySurvivesInterruptedSignInAndWaitsForAgeAndDeliberateRedemption() async throws {
        let fixture = HTTPSInvitationFixture()
        defer { fixture.cleanup() }
        let model = fixture.model()
        let root = fixture.root(model)
        let url = try fixture.url("a")
        XCTAssertEqual(model.phase, .launching)
        root.receiveURL(url)
        XCTAssertEqual(model.challengeInvitation.link, url.absoluteString)
        XCTAssertEqual(fixture.client.reads, 0)
        XCTAssertTrue(fixture.client.requests.isEmpty)
        await model.start()
        XCTAssertEqual(model.phase, .signedOut)

        for failure in [CancellationError(), ChallengeV1Error.unavailable] as [Error] {
            fixture.auth.failure = failure
            await model.signInWithApple(fixture.identity)
            XCTAssertEqual(model.phase, .signedOut)
            XCTAssertEqual(fixture.model().challengeInvitation.link, url.absoluteString)
            await fixture.use(model)
            XCTAssertTrue(fixture.client.requests.isEmpty)
        }
        fixture.auth.failure = nil
        await fixture.signIn(model, as: fixture.firstActor)
        XCTAssertEqual(model.phase, .signedIn)
        XCTAssertEqual(model.challengesV1.access?.ageConfirmed, false)
        await fixture.use(model)
        XCTAssertTrue(fixture.client.requests.isEmpty, "Age is required inside the action, not just in the button")
        await model.challengesV1.submit(op: "confirm_age", fields: ["confirmed": .bool(true)])
        XCTAssertEqual(model.challengesV1.access?.ageConfirmed, true)
        XCTAssertEqual(fixture.client.requests.map { $0.payload["op"]?.string }, ["confirm_age"])
        XCTAssertEqual(model.challengeInvitation.link, url.absoluteString)
        await fixture.use(model)
        XCTAssertEqual(fixture.client.requests.map { $0.payload["op"]?.string }, ["confirm_age", "redeem_link"])
        XCTAssertTrue(model.challengeInvitation.link.isEmpty)
        XCTAssertTrue(fixture.model().challengeInvitation.link.isEmpty)
    }

    func testWarmDeliveryDoesNotFetchOrRedeemAndInvalidDeliveryCannotReplaceIt() async throws {
        let fixture = HTTPSInvitationFixture()
        defer { fixture.cleanup() }
        let model = fixture.model()
        await model.start()
        fixture.client.confirmed.insert(fixture.firstActor)
        await fixture.signIn(model, as: fixture.firstActor)
        let root = fixture.root(model)
        let reads = fixture.client.reads
        let url = try fixture.url("b")
        root.receiveURL(url)
        root.receiveURL(url) // duplicate OS delivery is still only an intent
        root.receiveURL(try XCTUnwrap(URL(string: url.absoluteString + "#")))
        root.receiveURL(try XCTUnwrap(URL(string: "https://invites.example.invalid.evil.invalid/challenge-invite/" + String(repeating: "c", count: 64))))
        XCTAssertEqual(model.challengeInvitation.link, url.absoluteString)
        XCTAssertEqual(fixture.client.reads, reads)
        XCTAssertTrue(fixture.client.requests.isEmpty)
        await fixture.use(model)
        XCTAssertEqual(fixture.client.requests.count, 1)
        XCTAssertEqual(fixture.client.requests.first?.actorId, fixture.firstActor)
        XCTAssertEqual(fixture.client.requests.first?.payload["token"]?.string, String(repeating: "b", count: 64))
    }

    func testLostResponseRelaunchAndAccountSwitchKeepExactRecoveryWithItsActor() async throws {
        let fixture = HTTPSInvitationFixture()
        defer { fixture.cleanup() }
        let model = fixture.model()
        await model.start()
        fixture.client.confirmed = [fixture.firstActor, fixture.secondActor]
        await fixture.signIn(model, as: fixture.firstActor)
        let url = try fixture.url("c")
        fixture.root(model).receiveURL(url)
        fixture.client.failNext = true
        await fixture.use(model)
        let pending = try XCTUnwrap(model.challengesV1.pending)
        XCTAssertEqual(model.challengeInvitation.link, url.absoluteString)

        let relaunched = fixture.model()
        await relaunched.start()
        await relaunched.challengesV1.refresh()
        XCTAssertEqual(relaunched.challengesV1.pending, pending)
        XCTAssertEqual(relaunched.challengeInvitation.link, url.absoluteString)
        XCTAssertEqual(fixture.client.requests, [pending], "Relaunch cannot retry automatically")
        await relaunched.signOut()
        await fixture.signIn(relaunched, as: fixture.secondActor)
        XCTAssertNil(relaunched.challengesV1.pending)
        XCTAssertNil(relaunched.challengesV1.lastReceipt)
        XCTAssertTrue(relaunched.challengesV1.issuedLinks.isEmpty)
        await relaunched.challengesV1.retry()
        XCTAssertEqual(fixture.client.requests, [pending], "Another account cannot retry the first account's redemption")
        let saved = try await relaunched.challengesV1.requests.load(fixture.firstActor)
        XCTAssertEqual(saved, pending)
        await relaunched.signOut()
        await fixture.signIn(relaunched, as: fixture.firstActor)
        XCTAssertEqual(relaunched.challengesV1.pending, pending)
        await fixture.use(relaunched)
        XCTAssertEqual(fixture.client.requests, [pending], "Use invitation cannot replace a queued exact request")
        await relaunched.challengesV1.retry()
        XCTAssertEqual(fixture.client.requests, [pending, pending])
        XCTAssertNil(relaunched.challengesV1.pending)
        XCTAssertEqual(relaunched.challengeInvitation.link, url.absoluteString)
        await fixture.use(relaunched)
        XCTAssertTrue(relaunched.challengeInvitation.link.isEmpty)
    }

    func testLateResponseAcrossAccountSwitchCannotClearNewHTTPSIntent() async throws {
        let fixture = HTTPSInvitationFixture()
        defer { fixture.cleanup() }
        let model = fixture.model()
        await model.start()
        fixture.client.confirmed = [fixture.firstActor, fixture.secondActor]
        await fixture.signIn(model, as: fixture.firstActor)
        fixture.root(model).receiveURL(try fixture.url("d"))
        fixture.client.holdNext = true
        let submission = Task { await fixture.use(model) }
        let deadline = Date().addingTimeInterval(2)
        while fixture.client.held == nil, Date() < deadline { await Task.yield() }
        let held = try XCTUnwrap(fixture.client.held)
        let pending = try XCTUnwrap(model.challengesV1.pending)
        await model.signOut()
        await fixture.signIn(model, as: fixture.secondActor)
        let newer = try fixture.url("e")
        fixture.root(model).receiveURL(newer)
        held.resume(returning: .init(id: UUID(), status: "pending_request"))
        fixture.client.held = nil
        await submission.value
        XCTAssertEqual(model.challengeInvitation.link, newer.absoluteString)
        XCTAssertNil(model.challengesV1.lastReceipt)
        XCTAssertNil(model.challengesV1.pending)
        let saved = try await model.challengesV1.requests.load(fixture.firstActor)
        XCTAssertEqual(saved, pending)
        XCTAssertEqual(fixture.client.requests, [pending])
        XCTAssertEqual(fixture.model().challengeInvitation.link, newer.absoluteString)
    }

    func testRootPreservesFixtureAndHistoricalDuelDelivery() async throws {
        let fixture = HTTPSInvitationFixture()
        defer { fixture.cleanup() }
        let model = fixture.model(configuration: .duelFixture)
        let root = fixture.root(model)
        let token = UUID()
        root.receiveURL(DuelInvitationLink.url(token: token))
        XCTAssertEqual(model.duels.pendingInvitationToken, token)
        XCTAssertTrue(model.challengeInvitation.link.isEmpty)
        let local = try XCTUnwrap(ChallengeInvitation.localFixture.url(for: String(repeating: "f", count: 64)))
        root.receiveURL(local)
        XCTAssertEqual(model.challengeInvitation.link, local.absoluteString)
        XCTAssertEqual(model.duels.pendingInvitationToken, token)
        root.receiveURL(try XCTUnwrap(URL(string: "gametime-beta://stripe-redirect")))
        XCTAssertEqual(model.challengeInvitation.link, local.absoluteString)
        XCTAssertEqual(model.duels.pendingInvitationToken, token)
        XCTAssertTrue(fixture.client.requests.isEmpty)
    }
}

@MainActor private final class HTTPSInvitationFixture {
    let firstActor = UUID(), secondActor = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("https-invitation-" + UUID().uuidString)
    let auth = HTTPSInvitationAuth()
    let client = HTTPSInvitationClient()
    let identity = AppleIdentity(idToken: "fictional", rawNonce: "fictional", firstSignInDisplayName: nil)
    let configuration = AppConfiguration(environment: .debug, supabaseURL: URL(string: "https://backend.example.invalid")!,
        supabasePublishableKey: "sb_publishable_fictional", contestMutationsEnabled: false,
        invitationHTTPSOrigin: "https://invites.example.invalid")
    lazy var services = FixtureServicesFactory.make(arguments: ["--fixture-mode"], authClient: auth,
        personalHealthSteps: DisabledPersonalHealthStepReader(), profileClient: HTTPSInvitationProfiles(), challengesV1: client)

    func model(configuration override: AppConfiguration? = nil) -> AppModel {
        let config = override ?? configuration
        return AppModel(configuration: config, services: services, challengeDirectory: directory.appendingPathComponent("requests"),
            challengeInvitation: ChallengeInvitationIntent(links: config.challengeInvitationLinks, directory: directory.appendingPathComponent("intent")))
    }
    func root(_ model: AppModel) -> RootView {
        RootView(model: model, personalStore: PersonalAccountabilityStore(configuration: model.configuration,
            auth: auth, client: services.personalAccountability, pendingStore: services.pendingPersonalChallenges,
            diagnosticClient: services.trustedActivityDiagnostic, activitySync: services.personalActivitySync),
            router: AppRouter(), demoMode: .unavailable, pushCoordinator: PushNotificationCoordinator())
    }
    func url(_ character: String) throws -> URL {
        try XCTUnwrap(configuration.challengeInvitationLinks.url(for: String(repeating: character, count: 64)))
    }
    func signIn(_ model: AppModel, as actor: UUID) async {
        auth.nextActor = actor
        await model.signInWithApple(identity)
        await model.challengesV1.refresh()
    }
    func use(_ model: AppModel) async {
        await ChallengeEntryPanel(store: model.challengesV1, invitation: model.challengeInvitation).useInvitation()
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}

@MainActor private final class HTTPSInvitationAuth: AuthClient {
    var actor: UUID?
    var nextActor = UUID()
    var failure: Error?
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID {
        if let failure { throw failure }
        actor = nextActor
        return nextActor
    }
    func signOut() async throws { actor = nil }
}

@MainActor private final class HTTPSInvitationProfiles: ProfileClient {
    func currentProfile(userID: UUID) async throws -> UserProfile? {
        UserProfile(id: userID, handle: "fictional_runner", displayName: "Fictional Runner", timezone: "UTC")
    }
    func createProfile(userID: UUID, handle: String, displayName: String, timezone: String) async throws -> UserProfile {
        UserProfile(id: userID, handle: handle, displayName: displayName, timezone: timezone)
    }
}

@MainActor private final class HTTPSInvitationClient: ChallengeV1Client {
    var requests: [ChallengeV1Request] = []
    private var receipts: [UUID: ChallengeV1Receipt] = [:]
    var reads = 0
    var confirmed: Set<UUID> = []
    var failNext = false
    var holdNext = false
    var held: CheckedContinuation<ChallengeV1Receipt, Error>?
    func list(actor: UUID) async throws -> [ChallengeV1] { reads += 1; return [] }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 { reads += 1; throw ChallengeV1Error.unavailable }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        requests.append(request)
        if holdNext { holdNext = false; return try await withCheckedThrowingContinuation { held = $0 } }
        if request.payload["op"]?.string == "confirm_age" {
            confirmed.insert(request.actorId)
            return .init(confirmed: true)
        }
        let receipt = receipts[request.requestId] ?? ChallengeV1Receipt(id: UUID(), status: "pending_request")
        receipts[request.requestId] = receipt
        if failNext { failNext = false; throw ChallengeV1Error.unavailable }
        return receipt
    }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        reads += 1
        if name == "challenge_access_status_v1" {
            return ChallengeV1Access(serverTime: nil, ageConfirmed: confirmed.contains(actor), betaAccess: true, suspended: false) as! T
        }
        if name == "challenge_community_catalog_v1" { return [ChallengeV1Community]() as! T }
        throw ChallengeV1Error.unavailable
    }
}
#endif
