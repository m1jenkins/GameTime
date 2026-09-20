#if DEBUG
import GameTimeCore
import Supabase
import SwiftUI
import XCTest
@testable import GameTime

@MainActor final class ChallengeHealthOrdinaryAppTests: XCTestCase {
    struct Config: Decodable {
        struct Actor: Decodable { let id: UUID; let email: String; let username: String }
        let url: URL; let key: String; let controlToken: String; let password: String; let actors: [Actor]
        let synthetic_only: Bool; let owner: String
    }
    var config: Config!
    var personalStore: PersonalAccountabilityStore!
    var sdk: SupabaseClient!
    var dependencies: ChallengeHealthFlowDependencies!
    @discardableResult func control(_ values: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: config.url.appendingPathComponent("p9/control"))
        request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: values)
        request.setValue(config.controlToken, forHTTPHeaderField: "x-p9-control")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession.shared.data(for: request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
    func makeModel(existingDirectory: URL? = nil) throws -> (AppModel, ChallengeHealthSyntheticLocal, URL) {
        let path = ProcessInfo.processInfo.environment["GAMETIME_P9_NATIVE_MANIFEST"] ?? "/private/tmp/gametime-p9/native.json"
        guard path.hasPrefix("/private/tmp/"), FileManager.default.fileExists(atPath: path) else {
            throw XCTSkip("The owned synthetic P9 loopback controller is required")
        }
        config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        XCTAssertTrue(config.synthetic_only); XCTAssertTrue(config.owner.hasPrefix("gametime-p8-real-health-"))
        XCTAssertTrue(SupabaseWeeklyClient.isExplicitLoopback(config.url))
        let sdk = SupabaseClient(supabaseURL: config.url, supabaseKey: config.key,
            options: .init(auth: .init(storage: ChallengeMemoryAuthStorage(), autoRefreshToken: false, emitLocalSessionAsInitialSession: true)))
        self.sdk = sdk
        let directory = existingDirectory ?? FileManager.default.temporaryDirectory.appendingPathComponent("p9-" + UUID().uuidString)
        let configuration = try AppConfiguration.validated(environmentValue: "debug", urlValue: config.url.absoluteString,
            keyValue: config.key, mutationValue: "NO", challengeV1Value: "YES")
        let local = try ChallengeHealthSyntheticLocal(origin: config.url, control: config.controlToken)
        let health = try local.dependencies(sdk: sdk, key: config.key, directory: directory)
        dependencies = health
        let services = FixtureServicesFactory.make(arguments: ["--fixture-mode"],
            authClient: P9Auth(sdk: sdk, password: config.password), personalHealthSteps: DisabledPersonalHealthStepReader(),
            profileClient: SupabaseProfileClient(client: sdk),
            challengesV1: LiveServicesFactory.makeChallenges(configuration: configuration, client: sdk), challengeHealthDependencies: health)
        personalStore = PersonalAccountabilityStore(configuration: configuration, auth: services.auth,
            client: services.personalAccountability, paymentClient: services.personalPayments,
            pendingStore: services.pendingPersonalChallenges, pendingCancellationStore: services.pendingPersonalCancellations,
            diagnosticClient: services.trustedActivityDiagnostic, activitySync: services.personalActivitySync)
        let model = AppModel(configuration: configuration, services: services, challengeDirectory: directory.appendingPathComponent("commands"),
            challengeInvitation: ChallengeInvitationIntent(directory: directory.appendingPathComponent("links")))
        return (model, local, directory)
    }
    func login(_ actor: Int, model: AppModel) async throws {
        if model.userID != nil { await model.signOut() }
        await model.signInWithApple(.init(idToken: config.actors[actor].email, rawNonce: "synthetic", firstSignInDisplayName: nil))
        XCTAssertEqual(model.phase, .signedIn, model.presentedError ?? "Ordinary sign-in")
        XCTAssertEqual(model.challengeHealth?.actor, config.actors[actor].id)
        await model.challengesV1.refresh()
        if model.challengesV1.access?.ageConfirmed != true {
            await model.challengesV1.submit(op: "confirm_age", fields: ["confirmed": .bool(true)])
        }
        XCTAssertNil(model.challengesV1.pending, model.challengesV1.error ?? "Age confirmation")
    }
    func personal(model: AppModel, start: String, metric: ChallengeV1Policy.Metric = .steps, target: Int = 10000) async throws -> UUID {
        let store = model.challengesV1, actor = try XCTUnwrap(model.userID), health = try XCTUnwrap(model.challengeHealth)
        var configFields: [String: ChallengeJSON] = ["start_date": .string(start), "days": .integer(1), "timezone": .string("UTC"), "amount_cents": .integer(100)]
        if metric == .timed { configFields["distance_mm"] = .integer(5_000_000) }
        let fields: ChallengeJSON = .object(configFields)
        let policy = ChallengeV1Policy(rawValue: "personal_" + metric.rawValue + "_goal_v1")!
        let source = try XCTUnwrap(ChallengeHealthBindingMapper.selectedSource(metric)).identifier
        let agreement = try await store.client.read("challenge_personal_preview_v1", fields: [
            "p_policy": .string(policy.id), "p_config": fields, "p_target": .integer(target),
            "p_source_policy_version": .string(source)], actor: actor, as: ChallengeV1.Agreement.self)
        let binding = try ChallengeHealthBindingMapper.binding(actor: actor, id: UUID(), version: 1, digest: agreement.digest,
            policy: policy, window: XCTUnwrap(decodeWindow(agreement.terms?["config"])), source: source)
        XCTAssertFalse(health.canConsent(binding))
        await health.checkReadiness(binding, connect: true)
        XCTAssertEqual(health.state(for: binding).readiness, .ready, health.state(for: binding).message ?? "Readiness")
        XCTAssertTrue(health.canConsent(binding), health.state(for: binding).message ?? "Matching acknowledgement required")
        await store.submit(op: "personal_commit", fields: ["policy": .string(policy.id), "config": fields,
            "target": .integer(target), "source_policy_version": .string(source),
            "digest": .string(agreement.digest), "consent": .bool(true)])
        XCTAssertNil(store.pending, store.error ?? "Personal commitment")
        let id = try XCTUnwrap(store.lastReceipt?.id, store.error ?? "Commit receipt")
        let row = try await store.client.detail(id, actor: actor)
        XCTAssertEqual(row.sourcePolicyVersion, source)
        XCTAssertEqual(try ChallengeHealthBindingMapper.agreement(row, actor: actor).termsDigest, agreement.digest)
        return id
    }
    func testTResponseLossActorSwitchRelaunchGateOffAndDiagnosticReplay() async throws {
        let (model, _, directory) = try makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await control(["action": "clock", "now": "2026-10-24T12:00:00Z"])
        await model.start(); try await login(0, model: model)
        let actor = config.actors[0].id
        let id = try await personal(model: model, start: "2026-10-26")
        try await control(["action": "clock", "now": "2026-10-26T12:00:00Z"])
        try await control(["action": "tick", "id": id.uuidString.lowercased()])
        try await control(["action": "input", "actor": 0, "mode": "value", "value": 10001])
        try await control(["action": "lose"])
        await model.challengeHealth?.refresh(id)
        let saved = try XCTUnwrap(dependencies.coordinator.uploadStore.load(actor: actor).pending.first)
        XCTAssertEqual(model.challengeHealth?.states[id]?.pendingDelivery, true)
        try await login(1, model: model)
        try await dependencies.uploads.retry(actor: config.actors[1].id)
        XCTAssertEqual(try dependencies.coordinator.uploadStore.load(actor: actor).pending.first, saved)
        await model.signOut()
        let (relaunch, local, _) = try makeModel(existingDirectory: directory)
        await relaunch.start(); try await login(0, model: relaunch)
        try await control(["action": "clock", "now": "2026-10-30T12:00:00Z"])
        let before = try await control(["action": "stats"])["counters"] as? [Int]
        try await control(["action": "gate", "enabled": false])
        await relaunch.challengeHealth?.refresh(id)
        try await control(["action": "gate", "enabled": true])
        let after = try await control(["action": "stats"])["counters"] as? [Int]
        XCTAssertEqual(before, after, "Recovery after correction closes must not create a new signature")
        XCTAssertTrue(try dependencies.coordinator.uploadStore.load(actor: actor).pending.isEmpty)
        let row = try await relaunch.challengesV1.client.detail(id, actor: actor)
        XCTAssertEqual(row.own(actor)?.fact?.revision, 1)
        XCTAssertEqual(row.own(actor)?.fact?.value, 10001)
        // A retained writer shares the same key and lease. Its actual endpoint
        // commits before a lost response; a new client restores the exact journal.
        let staging = AppConfiguration(environment: .staging, supabaseURL: config.url,
            supabasePublishableKey: config.key, contestMutationsEnabled: false)
        let journal = TrustedActivityDiagnosticFileStore(directory: directory.appendingPathComponent("diagnostic"))
        let diagnostic = try SupabaseTrustedActivityDiagnosticClient(client: sdk, configuration: staging,
            activity: P9DiagnosticActivity(), signer: local, transport: dependencies.coordinator, journal: journal)
        try await control(["action": "lose"])
        do { _ = try await diagnostic.runTrustedDiagnostic(ownerID: actor, timezone: "UTC"); XCTFail("The response is deliberately lost") }
        catch { XCTAssertEqual(error as? PersonalAccountabilityClientError, .unavailable) }
        let savedDiagnostic = try XCTUnwrap(journal.load(actor: actor))
        let counterBeforeReplay = try await control(["action": "stats"])["counters"] as? [Int]
        let recovery = ChallengeHealthTransportCoordinator(uploadStore: dependencies.coordinator.uploadStore,
            readinessStore: dependencies.coordinator.readinessStore, binding: { [sdk] in
                sdk?.auth.currentSession.map { .init(actorID: $0.user.id, identity: $0.accessToken) }
            })
        let debug = try AppConfiguration.validated(environmentValue: "debug", urlValue: config.url.absoluteString,
            keyValue: config.key, mutationValue: "NO", challengeV1Value: "NO")
        let recovered = try SupabaseTrustedActivityDiagnosticClient(client: sdk, configuration: debug,
            activity: DisabledActivityClient(), signer: UnavailableAppAttestedBodySigner(), transport: recovery, journal: journal)
        let result = try await recovered.runTrustedDiagnostic(ownerID: actor, timezone: "UTC")
        XCTAssertEqual(result.status, .trusted)
        XCTAssertEqual(result.positiveTrustedSampleCount, savedDiagnostic.sampleCount)
        XCTAssertNil(try journal.load(actor: actor))
        let counterAfterReplay = try await control(["action": "stats"])["counters"] as? [Int]
        XCTAssertEqual(counterBeforeReplay, counterAfterReplay)
        await relaunch.signOut()
    }
    func testVersionedExerciseThenRunningAndFriendPolicyMatrix() async throws {
        let (model, _, directory) = try makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        await model.start()
        let store = model.challengesV1, health = try XCTUnwrap(model.challengeHealth)
        var base = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-11-01T12:00:00Z"))
        let formatter = ISO8601DateFormatter()
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.timeZone = TimeZone(secondsFromGMT: 0); day.dateFormat = "yyyy-MM-dd"
        for metric in [ChallengeV1Policy.Metric.exercise, .distance, .timed, .steps] {
            for people in [1, 2, 6] {
                try await control(["action": "clock", "now": formatter.string(from: base)])
                try await login(0, model: model)
                let start = day.string(from: base.addingTimeInterval(2 * 86400))
                let source = try XCTUnwrap(ChallengeHealthBindingMapper.selectedSource(metric)).identifier
                let id: UUID
                if people == 1 { id = try await personal(model: model, start: start, metric: metric, target: 1000) }
                else {
                    var fields: [String: ChallengeJSON] = ["start_date": .string(start), "days": .integer(1), "timezone": .string("UTC"), "amount_cents": .integer(100)]
                    if metric == .timed { fields["distance_mm"] = .integer(5_000_000) }
                    await store.submit(op: "create", fields: ["policy": .string("friend_" + metric.rawValue + "_goal_v1"), "config": .object(fields), "source_policy_version": .string(source)])
                    XCTAssertNil(store.pending, store.error ?? "Friend creation")
                    id = try XCTUnwrap(store.lastReceipt?.id)
                    var row = try await store.client.detail(id, actor: config.actors[0].id)
                    XCTAssertEqual(row.sourcePolicyVersion, source, "Open lobby carries its selected source without an agreement")
                    await store.loadDetail(id)
                    await store.submit(op: "target", challenge: row, fields: ["target": .integer(1000)])
                    for person in 1..<people {
                        row = try await store.client.detail(id, actor: config.actors[0].id); await store.loadDetail(id)
                        await store.submit(op: "invite", challenge: row, fields: ["username": .string(config.actors[person].username.uppercased())])
                        XCTAssertNil(store.pending, store.error ?? "Invitation")
                        try await login(person, model: model)
                        row = try await store.client.detail(id, actor: config.actors[person].id); await store.loadDetail(id)
                        XCTAssertTrue(row.socialHidden)
                        await store.submit(op: "target", challenge: row, fields: ["target": .integer(1000)])
                        try await login(0, model: model)
                        row = try await store.client.detail(id, actor: config.actors[0].id); await store.loadDetail(id)
                        await store.submit(op: "select", challenge: row, fields: ["actor_id": .string(config.actors[person].id.uuidString.lowercased()), "selected": .bool(true)])
                    }
                    row = try await store.client.detail(id, actor: config.actors[0].id); await store.loadDetail(id)
                    await store.submit(op: "freeze", challenge: row)
                    XCTAssertNil(store.pending, store.error ?? "Freeze")
                    for person in 0..<people {
                        try await login(person, model: model)
                        row = try await store.client.detail(id, actor: config.actors[person].id); await store.loadDetail(id)
                        let binding = try ChallengeHealthBindingMapper.agreement(row, actor: config.actors[person].id)
                        await health.checkReadiness(binding, connect: true)
                        XCTAssertTrue(health.canConsent(binding), health.state(for: binding).message ?? metric.rawValue)
                        if metric == .exercise { XCTAssertEqual(row.agreement?.terms?["source_terms"]?["accepted_causal_uncertainty"], .bool(true)) }
                        await store.submit(op: "consent", challenge: row, fields: ["digest": .string(binding.termsDigest), "consent": .bool(true)])
                        XCTAssertNil(store.pending, store.error ?? "Matching consent")
                    }
                }
                try await control(["action": "clock", "now": formatter.string(from: base.addingTimeInterval(2 * 86400))])
                try await control(["action": "tick", "id": id.uuidString.lowercased()])
                for person in 0..<people {
                    try await login(person, model: model)
                    try await control(["action": "input", "actor": person, "mode": "value", "value": metric == .timed ? 899 : 1001])
                    await health.refresh(id)
                    var row = try await store.client.detail(id, actor: config.actors[person].id)
                    XCTAssertEqual(row.own(config.actors[person].id)?.fact?.state, "value", health.states[id]?.message ?? metric.rawValue)
                    // One of two, or two of six, becomes explicitly unresolved.
                    if people > 1 && person >= (people == 6 ? 4 : 1) {
                        try await control(["action": "input", "actor": person, "mode": "unresolved", "value": 0])
                        await health.refresh(id)
                        row = try await store.client.detail(id, actor: config.actors[person].id)
                        XCTAssertEqual(row.own(config.actors[person].id)?.fact?.state, "unresolved")
                        XCTAssertNil(ChallengePresentation.value(row.own(config.actors[person].id)!, actor: config.actors[person].id))
                    } else {
                        try await control(["action": "input", "actor": person, "mode": "value", "value": metric == .timed ? 999 : 1000])
                        await health.refresh(id)
                    }
                }
                try await control(["action": "clock", "now": formatter.string(from: base.addingTimeInterval(6 * 86400))])
                try await control(["action": "tick", "id": id.uuidString.lowercased()])
                try await control(["action": "clock", "now": formatter.string(from: base.addingTimeInterval(8 * 86400 + 1))])
                try await control(["action": "tick", "id": id.uuidString.lowercased()])
                try await login(0, model: model)
                let row = try await store.client.detail(id, actor: config.actors[0].id)
                let result = try XCTUnwrap(row.final?.result, metric.rawValue + " final")
                XCTAssertEqual(result.outcome, people == 2 ? "void" : "scored")
                let own = result.own ?? result.participants?[config.actors[0].id.uuidString.lowercased()]
                XCTAssertEqual(own?.returnedCents, 100)
                if let participants = result.participants {
                    XCTAssertTrue(participants.values.allSatisfy { $0.returnedCents == 100 && $0.status != "missed" })
                    if people == 6 { XCTAssertEqual(participants.values.filter { $0.status == "met" }.count, 4) }
                }
                base = base.addingTimeInterval(12 * 86400)
            }
        }
        await model.signOut()
    }
    func testZCommunityReadinessDisclosureAndOutcomeMinimum() async throws {
        let (model, _, directory) = try makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        await model.start()
        let store = model.challengesV1, health = try XCTUnwrap(model.challengeHealth)
        try await control(["action": "clock", "now": "2027-05-01T12:00:00Z"])
        let published = try await control(["action": "community", "start": "2027-05-03", "minimum": 5])
        let id = try XCTUnwrap((published["id"] as? String).flatMap(UUID.init(uuidString:)))
        for person in 0..<6 {
            try await login(person, model: model)
            let preview = try XCTUnwrap(store.communities.first { $0.id == id })
            let binding = try ChallengeHealthBindingMapper.binding(actor: config.actors[person].id, id: id, version: 1,
                digest: preview.digest, policy: ChallengeV1Policy(rawValue: "community_steps_goal_v1")!,
                window: XCTUnwrap(decodeWindow(preview.terms["config"])), source: "apple_watch_steps_v1")
            await health.checkReadiness(binding, connect: true)
            XCTAssertTrue(health.canConsent(binding), health.state(for: binding).message ?? "Community readiness")
            await store.submit(op: "join_community", fields: ["id": .string(id.uuidString.lowercased()), "digest": .string(preview.digest), "consent": .bool(true)])
            XCTAssertNil(store.pending, store.error ?? "Join")
            let row = try await store.client.detail(id, actor: config.actors[person].id)
            XCTAssertTrue(row.socialHidden); XCTAssertEqual(row.members.count, 1); XCTAssertNil(row.creatorId)
            if person == 3 {
                try await control(["action": "community_snapshot", "id": id.uuidString.lowercased()])
                try await control(["action": "clock", "now": "2027-05-01T12:16:00Z"])
                let four = try await store.client.detail(id, actor: config.actors[person].id)
                XCTAssertNil(four.counts?.disclosedJoined(at: four.serverTime))
            } else if person == 4 {
                try await control(["action": "community_snapshot", "id": id.uuidString.lowercased()])
                try await control(["action": "clock", "now": "2027-05-01T12:30:59Z"])
                let early = try await store.client.detail(id, actor: config.actors[person].id)
                XCTAssertNil(early.counts?.disclosedJoined(at: early.serverTime))
                try await control(["action": "clock", "now": "2027-05-01T12:31:00Z"])
                let five = try await store.client.detail(id, actor: config.actors[person].id)
                XCTAssertEqual(five.counts?.disclosedJoined(at: five.serverTime), 5)
            }
        }
        try await control(["action": "community_snapshot", "id": id.uuidString.lowercased()])
        try await control(["action": "clock", "now": "2027-05-01T12:46:00Z"])
        var row = try await store.client.detail(id, actor: config.actors[5].id)
        XCTAssertEqual(row.counts?.disclosedJoined(at: row.serverTime), 6)
        await store.loadDetail(id)
        let exit = await store.submit(op: "leave", challenge: row)
        XCTAssertNotNil(exit, store.error ?? "Non-punitive community exit")
        // Five remain after the exit. Four positive results and one unresolved
        // result exercise the configured outcome minimum independently of counts.
        try await control(["action": "clock", "now": "2027-05-03T12:00:00Z"])
        try await control(["action": "tick", "id": id.uuidString.lowercased()])
        for person in 0..<4 {
            try await login(person, model: model)
            try await control(["action": "input", "actor": person, "mode": "value", "value": 1001])
            await health.refresh(id)
            row = try await store.client.detail(id, actor: config.actors[person].id)
            XCTAssertEqual(row.own(config.actors[person].id)?.fact?.value, 1001, health.states[id]?.message ?? "Community progress")
            XCTAssertEqual(row.members.count, 1)
        }
        try await control(["action": "clock", "now": "2027-05-08T12:00:00Z"])
        try await control(["action": "tick", "id": id.uuidString.lowercased()])
        try await control(["action": "clock", "now": "2027-05-10T12:00:01Z"])
        try await control(["action": "tick", "id": id.uuidString.lowercased()])
        row = try await store.client.detail(id, actor: config.actors[3].id)
        XCTAssertEqual(row.status, "void")
        XCTAssertEqual(row.final?.result.own?.status, "void")
        XCTAssertEqual(row.final?.result.own?.returnedCents, 100)
        XCTAssertNil(row.final?.result.participants)
        await model.signOut()
    }
    func testStepsCorrectionReviewAndFinalHistoryInOrdinaryRoot() async throws {
        let (model, _, directory) = try makeModel()
        defer { try? FileManager.default.removeItem(at: directory) }
        await model.start(); try await login(0, model: model)
        let store = model.challengesV1, health = try XCTUnwrap(model.challengeHealth), actor = try XCTUnwrap(model.userID)
        try await control(["action": "clock", "now": "2026-10-01T12:00:00Z"])
        let id = try await personal(model: model, start: "2026-10-03")
        try await control(["action": "clock", "now": "2026-10-03T12:00:00Z"])
        try await control(["action": "tick", "id": id.uuidString.lowercased()])
        try await control(["action": "input", "actor": 0, "mode": "value", "value": 10001])
        await health.refresh(id)
        var row = try await store.client.detail(id, actor: actor)
        XCTAssertEqual(row.own(actor)?.fact?.state, "value")
        XCTAssertEqual(row.own(actor)?.fact?.value, 10001, health.states[id]?.message ?? "Initial observation")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let router = AppRouter()
        let host = UIHostingController(rootView: RootView(model: model, personalStore: personalStore,
            router: router, demoMode: .unavailable, pushCoordinator: PushNotificationCoordinator()).environment(model).environment(personalStore).environment(personalStore.stepProgress).environment(router))
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(400))
        _ = try await captureMountedSignal(window, controller: host, name: "p9-ordinary-root-progress", test: self)
        // Corrections use the full product period, including end+48h itself.
        try await control(["action": "clock", "now": "2026-10-06T00:00:00Z"])
        try await control(["action": "input", "actor": 0, "mode": "value", "value": 9999])
        await health.refresh(id)
        row = try await store.client.detail(id, actor: actor)
        XCTAssertEqual(row.own(actor)?.fact?.value, 9999, health.states[id]?.message ?? "Downward correction")
        try await control(["action": "clock", "now": "2026-10-10T12:00:00Z"])
        try await control(["action": "tick", "id": id.uuidString.lowercased()])
        row = try await store.client.detail(id, actor: actor)
        XCTAssertEqual(row.status, "review")
        XCTAssertEqual(row.notice?.reviewBy, try ChallengeInstant("2026-10-12T12:00:00Z"))
        await store.loadDetail(id)
        XCTAssertTrue(store.isFresh(row), "Review uses the freshly displayed notice")
        let reviewReceipt = await store.submit(op: "review", challenge: row, fields: ["notice_revision": .integer(try XCTUnwrap(row.notice?.revision)), "reason": .string("wrong_total")])
        XCTAssertNotNil(reviewReceipt, store.error ?? "Review must be sent")
        XCTAssertNil(store.pending, store.error ?? "Review request")
        row = try await store.client.detail(id, actor: actor)
        XCTAssertEqual(row.reviews.first?.resolveBy, try ChallengeInstant("2026-10-13T12:00:00Z"))
        try await control(["action": "clock", "now": "2026-10-13T12:00:01Z"])
        try await control(["action": "tick", "id": id.uuidString.lowercased()])
        await store.refresh(); row = try await store.client.detail(id, actor: actor)
        XCTAssertNotNil(row.final)
        let own = row.final?.result.own ?? row.final?.result.participants?[actor.uuidString.lowercased()]
        XCTAssertEqual(own?.returnedCents, 100)
        XCTAssertNotEqual(own?.status, "missed")
        XCTAssertEqual(row.final?.result.outcome, "void")
        _ = try await captureMountedSignal(window, controller: host, name: "p9-ordinary-root-final", test: self)
        // A downward correction that still establishes the target can succeed.
        try await control(["action": "clock", "now": "2026-10-14T12:00:00Z"])
        let second = try await personal(model: model, start: "2026-10-16")
        try await control(["action": "clock", "now": "2026-10-16T12:00:00Z"])
        try await control(["action": "tick", "id": second.uuidString.lowercased()])
        try await control(["action": "input", "actor": 0, "mode": "value", "value": 11000])
        await health.refresh(second)
        try await control(["action": "input", "actor": 0, "mode": "value", "value": 10001])
        await health.refresh(second)
        try await control(["action": "clock", "now": "2026-10-20T12:00:00Z"])
        try await control(["action": "tick", "id": second.uuidString.lowercased()])
        try await control(["action": "clock", "now": "2026-10-22T12:00:01Z"])
        try await control(["action": "tick", "id": second.uuidString.lowercased()])
        row = try await store.client.detail(second, actor: actor)
        XCTAssertEqual(row.own(actor)?.fact?.value, 10001)
        let success = row.final?.result.own ?? row.final?.result.participants?[actor.uuidString.lowercased()]
        XCTAssertEqual(success?.status, "met"); XCTAssertEqual(success?.returnedCents, 100)
        await model.signOut()
        XCTAssertTrue(health.states.isEmpty)
    }
}
@MainActor private final class P9DiagnosticActivity: ActivityClient {
    func requestStepReadAuthorization() async throws -> ActivityAuthorizationOutcome { .requestCompleted }
    func stepBuckets(overlapping window: DateInterval, timeZoneSchedule: ContestTimeZoneSchedule, asOf: Date) async throws -> [HourlyBucket] {
        [.init(metric: .steps, bucketStart: window.start, provenance: .device, value: 100, sampleCount: 1)]
    }
}
@MainActor private final class P9Auth: GameTime.AuthClient {
    let sdk: SupabaseClient; let auth: SupabaseAuthClient; let password: String
    init(sdk: SupabaseClient, password: String) { self.sdk = sdk; self.password = password; auth = SupabaseAuthClient(client: sdk) }
    func currentUserID() async -> UUID? { await auth.currentUserID() }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { await auth.authStateChanges() }
    func signOut() async throws { try await auth.signOut() }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { try await sdk.auth.signIn(email: identity.idToken, password: password).user.id }
}
#endif
