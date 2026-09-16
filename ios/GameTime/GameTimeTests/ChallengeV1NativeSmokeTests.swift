#if DEBUG
import Supabase
import XCTest
@testable import GameTime

@MainActor final class ChallengeV1NativeSmokeTests: XCTestCase {
    struct Config: Decodable {
        struct Actor: Decodable { let id:UUID;let email:String;let username:String }
        let url:URL;let key:String;let controlToken:String;let password:String;let actors:[Actor]
        let nativePhase: String?
    }
    var config:Config!
    func testOwnedLocalAccountDeletionFixtureLogin() async throws {
        struct LocalDeletionConfig: Decodable {
            let url: URL
            let key: String
            let email: String
            let password: String
        }
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let file = root.appendingPathComponent("tmp/account-deletion-native-local.json")
        guard FileManager.default.fileExists(atPath: file.path) else {
            throw XCTSkip("Owned local deletion fixture required")
        }
        let local = try JSONDecoder().decode(
            LocalDeletionConfig.self,
            from: Data(contentsOf: file)
        )
        XCTAssertTrue(SupabaseWeeklyClient.isExplicitLoopback(local.url))
        let sdk = SupabaseClient(
            supabaseURL: local.url,
            supabaseKey: local.key,
            options: .init(
                auth: .init(
                    storage: ChallengeMemoryAuthStorage(),
                    autoRefreshToken: false,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
        let session = try await sdk.auth.signIn(
            email: local.email,
            password: local.password
        )
        XCTAssertFalse(session.accessToken.isEmpty)
    }
    private func makeSession() throws -> (SupabaseClient, ChallengeV1Store, SupabaseChallengeV1Client, URL) {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file=root.appendingPathComponent("tmp/beta-native-smoke.json")
        guard FileManager.default.fileExists(atPath:file.path) else { throw XCTSkip("Run scripts/beta-native-smoke.py with the owned Simulator.") }
        config=try JSONDecoder().decode(Config.self,from:Data(contentsOf:file))
        XCTAssertTrue(SupabaseWeeklyClient.isExplicitLoopback(config.url))
        XCTAssertEqual(config.url.absoluteString, ProcessInfo.processInfo.environment["GAMETIME_BETA_EXPECTED_LOCAL_URL"] ?? "http://127.0.0.1:58339")
        let sdk=SupabaseClient(supabaseURL:config.url,supabaseKey:config.key,options:.init(auth:.init(storage:ChallengeMemoryAuthStorage(),autoRefreshToken:false,emitLocalSessionAsInitialSession:true)))
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let queue=ChallengeV1RequestStore(directory:directory)
        let client=SupabaseChallengeV1Client(sdk:sdk,url:config.url,key:config.key)
        let store=ChallengeV1Store(auth:SupabaseAuthClient(client:sdk),client:client,requests:queue)
        return (sdk, store, client, directory)
    }
    func testOrdinaryAppSharedSessionJourney() async throws {
        let (sdk, _, _, directory) = try makeSession()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = try AppConfiguration.validated(environmentValue: "debug", urlValue: config.url.absoluteString,
            keyValue: config.key, mutationValue: "NO", challengeV1Value: "YES")
        let auth = AppChallengeSmokeAuth(sdk: sdk, password: config.password)
        let client = LiveServicesFactory.makeChallenges(configuration: configuration, client: sdk)
        let services = FixtureServicesFactory.make(arguments: ["--fixture-mode"], authClient: auth,
            personalHealthSteps: DisabledPersonalHealthStepReader(), profileClient: SupabaseProfileClient(client: sdk), challengesV1: client)
        let intentDirectory = directory.appendingPathComponent("intent")
        let model = AppModel(configuration: configuration, services: services,
            challengeDirectory: directory.appendingPathComponent("requests"),
            challengeInvitation: ChallengeInvitationIntent(directory: intentDirectory))
        let store = model.challengesV1
        XCTAssertTrue(store.client === client, "Ordinary AppModel consumes the configured shared service")
        await model.start()
        XCTAssertEqual(model.phase, .signedOut)
        let unopened = "gametime-beta://challenge-invite/" + String(repeating: "a", count: 64)
        model.challengeInvitation.receive(try XCTUnwrap(URL(string: unopened)))
        for interruption in ["cancel", "fail"] {
            await model.signInWithApple(.init(idToken: interruption, rawNonce: "fixture", firstSignInDisplayName: nil))
            XCTAssertEqual(model.phase, .signedOut)
            XCTAssertEqual(model.challengeInvitation.link, unopened)
            XCTAssertEqual(ChallengeInvitationIntent(directory: intentDirectory).link, unopened)
        }
        func signIn(_ index: Int) async throws {
            if model.userID != nil { await model.signOut() }
            XCTAssertTrue(store.challenges.isEmpty, "Ordinary sign-out clears challenge projections")
            await model.signInWithApple(.init(idToken: config.actors[index].email, rawNonce: "fixture", firstSignInDisplayName: nil))
            XCTAssertEqual(model.phase, .signedIn, model.presentedError ?? "App sign-in failed")
            XCTAssertEqual(model.userID, config.actors[index].id)
            XCTAssertEqual(store.actor, model.userID, "AppModel binds challenges before mounting Signal")
            await store.refresh()
            XCTAssertNil(store.error)
            XCTAssertEqual(store.actor, config.actors[index].id, "Queued prior Auth events cannot clear the new actor")
            _ = try XCTUnwrap(store.access)
        }
        try await signIn(0)
        XCTAssertFalse(try XCTUnwrap(store.access).ageConfirmed)
        await store.submit(op: "confirm_age", fields: ["confirmed": .bool(true)])
        XCTAssertTrue(try XCTUnwrap(store.access).ageConfirmed)
        let fields: [String: ChallengeJSON] = ["policy": .string("friend_steps_goal_v1"), "config": .object([
            "start_date": .string("2026-10-03"), "days": .integer(1), "timezone": .string("UTC"), "amount_cents": .integer(100)])]
        try await control(["action": "clock", "now": "2026-10-01T12:00:00Z", "admission": false])
        await store.submit(op: "create", fields: fields)
        XCTAssertEqual(store.error, ChallengeV1Error.server("challenge_admission_paused").localizedDescription)
        let pausedRequest = try XCTUnwrap(store.pending, "Existing recovery keeps the exact paused action")
        try await control(["action": "clock", "now": "2026-10-01T12:00:00Z"])
        await store.retry()
        XCTAssertNil(store.pending)
        XCTAssertEqual(pausedRequest.actorId, config.actors[0].id)
        let id = try XCTUnwrap(store.lastReceipt?.id, store.error ?? "Create failed")
        await store.submit(op: "issue_link", fields: ["id": .string(id.uuidString.lowercased())])
        let link = "gametime-beta://challenge-invite/" + (try XCTUnwrap(store.lastReceipt?.token))
        await model.signOut()
        model.challengeInvitation.receive(try XCTUnwrap(URL(string: link)))
        try await signIn(6)
        XCTAssertEqual(model.challengeInvitation.link, link)
        await store.submit(op: "confirm_age", fields: ["confirmed": .bool(true)])
        let panel = ChallengeEntryPanel(store: store, invitation: model.challengeInvitation)
        try await control(["action": "lose", "rpc": "challenge_command_v1"])
        await panel.useInvitation()
        let pending = try XCTUnwrap(store.pending)
        XCTAssertEqual(model.challengeInvitation.link, link)
        try await signIn(0)
        XCTAssertNil(store.pending, "A different account never inherits redemption")
        try await signIn(6)
        XCTAssertEqual(store.pending, pending)
        await store.retry()
        XCTAssertNil(store.pending, store.error ?? "Exact retry failed")
        await panel.useInvitation()
        XCTAssertTrue(model.challengeInvitation.link.isEmpty)
        for index in [0, 6] {
            try await signIn(index)
            let row = try await client.detail(id, actor: config.actors[index].id)
            await store.submit(op: "target", challenge: row, fields: ["target": .integer(100)])
            XCTAssertNil(store.pending, store.error ?? "Target failed")
        }
        try await signIn(0)
        var row = try await client.detail(id, actor: config.actors[0].id)
        await store.submit(op: "select", challenge: row, fields: ["actor_id": .string(config.actors[6].id.uuidString.lowercased()), "selected": .bool(true)])
        row = try await client.detail(id, actor: config.actors[0].id)
        await store.submit(op: "freeze", challenge: row)
        for index in [0, 6] {
            try await signIn(index)
            row = try await client.detail(id, actor: config.actors[index].id)
            await store.submit(op: "consent", challenge: row, fields: ["digest": .string(try XCTUnwrap(row.agreement?.digest)), "consent": .bool(true)])
            XCTAssertNil(store.pending, store.error ?? "Consent failed")
        }
        row = try await client.detail(id, actor: config.actors[6].id)
        XCTAssertEqual(row.status, "scheduled")
        await store.loadDetail(id)
        XCTAssertTrue(store.challenges.contains { $0.id == id && $0.status == "scheduled" })
        try await control(["action": "clock", "now": "2026-10-01T12:00:00Z", "admission": false])
        await store.submit(op: "leave", challenge: row)
        XCTAssertNil(store.pending, store.error ?? "Paused admission must preserve safe exit")
        await store.refresh()
        XCTAssertTrue(store.sections[.history]?.rows.contains { $0.id == id } == true)

        // Force expiry only in the stored client metadata. The renewal itself
        // goes to real local Auth; no JWT signing or authorization is substituted.
        var expired = try XCTUnwrap(sdk.auth.currentSession)
        expired.expiresAt = 0
        let storage = ChallengeMemoryAuthStorage()
        let storageKey = "p9-expired-session"
        try storage.store(key: storageKey, value: JSONEncoder().encode(expired))
        let renewedSDK = SupabaseClient(supabaseURL: config.url, supabaseKey: config.key,
            options: .init(auth: .init(storage: storage, storageKey: storageKey, autoRefreshToken: false,
                emitLocalSessionAsInitialSession: true)))
        let renewed = LiveServicesFactory.makeChallenges(configuration: configuration, client: renewedSDK)
        _ = try await renewed.list(actor: config.actors[6].id)
        XCTAssertGreaterThan(try XCTUnwrap(renewedSDK.auth.currentSession).expiresAt, Date().timeIntervalSince1970)
        try await control(["action": "revoke_actor_sessions", "actor": config.actors[6].id.uuidString])
        await store.refresh()
        XCTAssertNil(store.actor, "Revoked session clears ordinary app content")
        XCTAssertTrue(store.challenges.isEmpty)
        await model.signOut()
        XCTAssertEqual(model.phase, .signedOut)
    }

    func testProductionNativeJourneys() async throws {
        let (sdk, store, client, directory) = try makeSession()
        defer { try? FileManager.default.removeItem(at: directory) }
        if config.nativePhase == "recovery" {
            try await communityPrivacy(sdk, store, client)
            try await entry(sdk, store, client)
            return
        }
        let queue = store.requests
        for people in [2,6] {
            try await control(["action":"clock","now":"2026-10-01T12:00:00Z"])
            try await login(0,sdk,store)
            if people==2 { try await control(["action":"lose","rpc":"challenge_command_v1"]) }
            await store.submit(op:"create",fields:["config":.object(["start_date":.string("2026-10-03"),"days":.integer(7),"timezone":.string("America/Chicago"),"amount_cents":.integer(100)])])
            if people==2 {
                let saved=try XCTUnwrap(store.pending)
                XCTAssertNotNil(store.error,"Actually lose a committed HTTP response")
                try await login(1,sdk,store)
                XCTAssertNil(store.pending,"Other account cannot inherit saved action")
                let reloaded=try await queue.load(config.actors[0].id)
                XCTAssertEqual(saved,reloaded,"Protected exact request survives account change")
                try await login(0,sdk,store)
                XCTAssertEqual(store.pending,saved)
                try await control(["action":"clock","now":"2026-10-01T12:00:00Z","admission":false])
                await store.retry()
                XCTAssertNil(store.pending,store.error ?? "Saved request failed")
                try await control(["action":"clock","now":"2026-10-01T12:00:00Z"])
            }
            let id=try XCTUnwrap(store.lastReceipt?.id)
            var row=try await client.detail(id,actor:config.actors[0].id)
            await store.refresh();await store.submit(op:"target",challenge:row,fields:["target":.integer(10000)])
            for i in 1..<people {
                row=try await client.detail(id,actor:config.actors[0].id)
                await store.submit(op:"invite",challenge:row,fields:["username":.string(config.actors[i].username.uppercased())])
                XCTAssertNil(store.pending,store.error ?? "Invitation failed")
                try await login(i,sdk,store)
                row=try await client.detail(id,actor:config.actors[i].id)
                XCTAssertTrue(row.socialHidden,"Pending entrant sees only own facts")
                await store.submit(op:"target",challenge:row,fields:["target":.integer(10000+i)])
                XCTAssertNil(store.pending,store.error ?? "Target failed")
                try await login(0,sdk,store)
                row=try await client.detail(id,actor:config.actors[0].id)
                await store.submit(op:"select",challenge:row,fields:["actor_id":.string(config.actors[i].id.uuidString.lowercased()),"selected":.bool(true)])
                XCTAssertNil(store.pending,store.error ?? "Selection failed")
            }
            row=try await client.detail(id,actor:config.actors[0].id)
            await store.submit(op:"freeze",challenge:row)
            XCTAssertNil(store.pending,store.error ?? "Freeze failed")
            for i in 0..<people {
                try await login(i,sdk,store)
                row=try await client.detail(id,actor:config.actors[i].id)
                XCTAssertEqual(row.members.filter(\.selected).count,people)
                let digest=try XCTUnwrap(row.agreement?.digest)
                await store.submit(op:"consent",challenge:row,fields:["digest":.string(digest),"consent":.bool(true)])
                XCTAssertNil(store.pending,store.error ?? "Consent failed")
            }
            row=try await client.detail(id,actor:config.actors[people-1].id)
            XCTAssertEqual(row.status,"scheduled")
            XCTAssertTrue(row.members.allSatisfy(\.consented))
            try await control(["action":"clock","now":"2026-10-05T12:00:00Z"])
            try await control(["action":"process","id":id.uuidString])
            await store.refresh();XCTAssertEqual(store.challenges.first(where:{$0.id==id})?.status,"active")
            for i in 0..<people {
                try await control(["action":"capture","id":id.uuidString,"actor":config.actors[i].id.uuidString,"value":12000])
            }
            await store.refresh()
            row=try XCTUnwrap(store.challenges.first(where:{$0.id==id}))
            XCTAssertEqual(row.own(config.actors[people-1].id)?.fact?.value,12000,"Exact server total")
            try await control(["action":"clock","now":"2026-10-11T12:00:00Z"])
            try await control(["action":"capture","id":id.uuidString,"actor":config.actors[people-1].id.uuidString,"value":100])
            await store.refresh()
            row=try XCTUnwrap(store.challenges.first(where:{$0.id==id}))
            XCTAssertEqual(row.own(config.actors[people-1].id)?.fact?.value,100,"Downward correction visible")
            XCTAssertEqual(row.own(config.actors[people-1].id)?.fact?.revision,2)
            try await control(["action":"clock","now":"2026-10-20T12:00:00Z"])
            try await control(["action":"process","id":id.uuidString])
            await store.refresh();row=try XCTUnwrap(store.challenges.first(where:{$0.id==id}))
            XCTAssertEqual(row.status,"review")
            XCTAssertEqual(row.notice?.reviewBy,try ChallengeInstant("2026-10-22T12:00:00Z"))
            try await control(["action":"clock","now":"2026-10-22T11:59:59Z"])
            await store.refresh();row=try XCTUnwrap(store.challenges.first(where:{$0.id==id}))
            await store.submit(op:"review",challenge:row,fields:["notice_revision":.integer(1),"reason":.string("wrong_total")])
            XCTAssertNil(store.pending,store.error ?? "Review failed")
            row=try XCTUnwrap(store.challenges.first(where:{$0.id==id}))
            let review=try XCTUnwrap(row.reviews.first)
            XCTAssertEqual(review.resolveBy,try ChallengeInstant("2026-10-25T11:59:59Z"))
            try await control(["action":"clock","now":"2026-10-22T12:00:00Z"])
            try await control(["action":"process","id":id.uuidString])
            await store.refresh();XCTAssertNil(store.challenges.first(where:{$0.id==id})?.final)
            try await control(["action":"resolve","review":review.id.uuidString])
            try await control(["action":"process","id":id.uuidString])
            await store.refresh();row=try XCTUnwrap(store.challenges.first(where:{$0.id==id}))
            XCTAssertEqual(row.status,"final")
            XCTAssertEqual(row.final?.result.entryCents,100*people)
            XCTAssertEqual(row.final?.result.participants?[config.actors[people-1].id.uuidString.lowercased()]?.status,"missed")
            try await login(0,sdk,store)
            row=try XCTUnwrap(store.challenges.first(where:{$0.id==id}))
            XCTAssertEqual(row.final?.result.participants?[config.actors[0].id.uuidString.lowercased()]?.returnedCents,100+100/(people-1))
        }
        // Authenticated cancellation and the two-person non-punitive exit.
        try await control(["action":"clock","now":"2026-10-01T12:00:00Z"])
        try await login(0,sdk,store)
        await store.submit(op:"create",fields:["config":.object(["start_date":.string("2026-10-03"),"days":.integer(1),"timezone":.string("UTC"),"amount_cents":.integer(100)])])
        let cancelId=try XCTUnwrap(store.lastReceipt?.id)
        var cancelled=try await client.detail(cancelId,actor:config.actors[0].id)
        await store.submit(op:"cancel",challenge:cancelled)
        cancelled=try await client.detail(cancelId,actor:config.actors[0].id)
        XCTAssertEqual(cancelled.status,"cancelled")
        XCTAssertNil(store.pending)
        await store.submit(op:"create",fields:["config":.object(["start_date":.string("2026-10-03"),"days":.integer(1),"timezone":.string("UTC"),"amount_cents":.integer(100)])])
        let exitId=try XCTUnwrap(store.lastReceipt?.id)
        var exitRow=try await client.detail(exitId,actor:config.actors[0].id)
        await store.submit(op:"target",challenge:exitRow,fields:["target":.integer(10000)])
        exitRow=try await client.detail(exitId,actor:config.actors[0].id)
        await store.submit(op:"invite",challenge:exitRow,fields:["username":.string(config.actors[1].username)])
        try await login(1,sdk,store);exitRow=try await client.detail(exitId,actor:config.actors[1].id)
        await store.submit(op:"target",challenge:exitRow,fields:["target":.integer(11000)])
        try await login(0,sdk,store);exitRow=try await client.detail(exitId,actor:config.actors[0].id)
        await store.submit(op:"select",challenge:exitRow,fields:["actor_id":.string(config.actors[1].id.uuidString.lowercased()),"selected":.bool(true)])
        exitRow=try await client.detail(exitId,actor:config.actors[0].id)
        await store.submit(op:"freeze",challenge:exitRow)
        try await login(1,sdk,store);exitRow=try await client.detail(exitId,actor:config.actors[1].id)
        try await control(["action":"clock","now":"2026-10-01T12:00:00Z","admission":false,"processing":false])
        await store.submit(op:"leave",challenge:exitRow)
        XCTAssertNil(store.pending,store.error ?? "Safe exit failed")
        exitRow=try await client.detail(exitId,actor:config.actors[1].id)
        XCTAssertTrue(exitRow.isClosed)
        XCTAssertEqual(exitRow.final?.result.own?.returnedCents,100,"Leaving retains own refund and hides shared data")
        try await login(0,sdk,store)
        // Lost/stale action can be explicitly stopped with a durable server fence.
        try await control(["action":"clock","now":"2026-10-01T12:00:00Z"])
        let request=ChallengeV1Request(actor:config.actors[0].id,payload:.object(["op":.string("create"),"config":.object(["start_date":.string("2026-10-03"),"days":.integer(1),"timezone":.string("UTC"),"amount_cents":.integer(100)])]))
        let abandoned = try await client.abandon(request)
        XCTAssertEqual(abandoned.status,"cancelled_request")
        let late = try await client.submit(request)
        XCTAssertEqual(late.status,"cancelled_request","Late original request cannot commit after abandonment")
        XCTAssertEqual(store.challenges.filter({$0.status=="final"}).count,2)
        try await matrix(sdk, store, client)
        if config.nativePhase != "matrix" {
            try await communityPrivacy(sdk, store, client)
            try await entry(sdk, store, client)
        }
    }
    func matrix(_ sdk: SupabaseClient, _ store: ChallengeV1Store, _ client: SupabaseChallengeV1Client) async throws {
        var completed = Set<String>()
        for policy in ChallengeV1Policy.all {
            let id = try await createPolicy(policy, sdk, store, client)
            try await control(["action": "clock", "now": "2026-10-03T12:00:00Z"])
            try await control(["action": "process", "id": id.uuidString])
            for i in 0..<(policy.mode == .personal ? 1 : 2) {
                try await control(["action": "capture", "id": id.uuidString, "actor": config.actors[i].id.uuidString, "value": 101])
            }
            try await control(["action": "clock", "now": "2026-10-05T12:00:00Z"])
            for i in 0..<(policy.mode == .personal ? 1 : 2) {
                try await control(["action": "capture", "id": id.uuidString, "actor": config.actors[i].id.uuidString, "value": 99])
            }
            try await control(["action": "clock", "now": "2026-10-10T12:00:00Z"])
            try await control(["action": "process", "id": id.uuidString])
            try await login(0, sdk, store)
            var row = try await client.detail(id, actor: config.actors[0].id)
            XCTAssertEqual(row.own(config.actors[0].id)?.fact?.value, 99, "Exact downward correction: " + policy.id)
            XCTAssertEqual(row.notice?.reviewBy, try ChallengeInstant("2026-10-12T12:00:00Z"))
            if policy.mode == .community {
                XCTAssertEqual(row.members.count, 1); XCTAssertNil(row.creatorId)
                XCTAssertNil(row.notice?.result?.participants); XCTAssertNotNil(row.notice?.result?.own)
            }
            await store.submit(op: "review", challenge: row, fields: ["notice_revision": .integer(try XCTUnwrap(row.notice?.revision)), "reason": .string("wrong_result")])
            XCTAssertNil(store.pending, store.error ?? policy.id)
            row = try await client.detail(id, actor: config.actors[0].id)
            let review = try XCTUnwrap(row.reviews.first)
            XCTAssertEqual(review.resolveBy, try ChallengeInstant("2026-10-13T12:00:00Z"), policy.id)
            try await control(["action": "resolve", "review": review.id.uuidString])
            try await control(["action": "clock", "now": "2026-10-12T12:00:00Z"])
            try await control(["action": "process", "id": id.uuidString])
            row = try await client.detail(id, actor: config.actors[0].id)
            XCTAssertNotNil(row.final, policy.id)
            let own = row.final?.result.own ?? row.final?.result.participants?[config.actors[0].id.uuidString.lowercased()]
            XCTAssertEqual(own?.status, !policy.hasTarget ? "winner" : policy.metric == .timed ? "met" : "missed", policy.id)
            // Empty/unknown fictional activity must not become a zero or a loss.
            let missingID = try await createPolicy(policy, sdk, store, client)
            try await control(["action": "clock", "now": "2026-10-03T12:00:00Z"])
            try await control(["action": "process", "id": missingID.uuidString])
            try await control(["action": "capture", "id": missingID.uuidString, "actor": config.actors[0].id.uuidString, "value": NSNull()])
            if policy.mode != .personal {
                try await control(["action": "capture", "id": missingID.uuidString, "actor": config.actors[1].id.uuidString, "value": 200])
            }
            try await login(0, sdk, store)
            let unknown = try await client.detail(missingID, actor: config.actors[0].id)
            XCTAssertNil(unknown.own(config.actors[0].id)?.fact?.value, policy.id)
            try await control(["action": "clock", "now": "2026-10-10T12:00:00Z"])
            try await control(["action": "process", "id": missingID.uuidString])
            try await control(["action": "clock", "now": "2026-10-12T12:00:00Z"])
            try await control(["action": "process", "id": missingID.uuidString])
            let missingFinal = try await client.detail(missingID, actor: config.actors[0].id)
            let missingOwn = missingFinal.final?.result.own ?? missingFinal.final?.result.participants?[config.actors[0].id.uuidString.lowercased()]
            XCTAssertTrue(missingFinal.isClosed, policy.id)
            XCTAssertNotEqual(missingOwn?.status, "missed", policy.id)
            XCTAssertEqual(missingOwn?.returnedCents, 100, policy.id)
            let exitID = try await createPolicy(policy, sdk, store, client)
            try await control(["action": "clock", "now": "2026-10-03T12:00:00Z"])
            try await control(["action": "process", "id": exitID.uuidString])
            try await login(0, sdk, store)
            let beforeExit = try await client.detail(exitID, actor: config.actors[0].id)
            try await control(["action": "clock", "now": "2026-10-03T12:00:00Z", "admission": false, "processing": false])
            await store.submit(op: "leave", challenge: beforeExit)
            XCTAssertNil(store.pending, store.error ?? policy.id)
            let afterExit = try await client.detail(exitID, actor: config.actors[0].id)
            XCTAssertTrue(afterExit.isClosed, policy.id)
            XCTAssertEqual(afterExit.final?.result.own?.returnedCents, 100, "Safe paused exit: " + policy.id)
            completed.insert(policy.id)
        }
        XCTAssertEqual(completed.count, 13, "Every exact policy traversed the production native HTTP client")
    }
    func communityPrivacy(_ sdk: SupabaseClient, _ store: ChallengeV1Store, _ client: SupabaseChallengeV1Client) async throws {
        let policy = try XCTUnwrap(ChallengeV1Policy(rawValue: "community_steps_goal_v1"))
        let id = try await createPolicy(policy, sdk, store, client)
        for i in 2...5 {
            try await login(i, sdk, store)
            let cohort = try XCTUnwrap(store.communities.first { $0.id == id })
            await store.submit(op: "join_community", fields: ["id": .string(id.uuidString.lowercased()), "digest": .string(cohort.digest), "consent": .bool(true)])
            XCTAssertNil(store.pending, store.error ?? "Community join failed")
            let row = try await client.detail(id, actor: config.actors[i].id)
            XCTAssertEqual(row.members.count, 1)
            XCTAssertNil(row.creatorId)
            XCTAssertNil(row.counts?.joined, "Fresh joins cannot reveal a live count")
            if i == 3 { XCTAssertEqual(row.counts?.state, "threshold") }
            if i == 4 {
                try await control(["action": "community_snapshot", "id": id.uuidString])
                try await control(["action": "clock", "now": "2026-10-01T12:14:59Z"])
                let early = try await client.detail(id, actor: config.actors[i].id)
                XCTAssertNil(early.counts?.joined, "899 seconds must remain hidden")
            }
        }
        try await control(["action": "clock", "now": "2026-10-01T12:15:00Z"])
        try await login(0, sdk, store)
        var row = try await client.detail(id, actor: config.actors[0].id)
        XCTAssertEqual(row.counts?.disclosedJoined(at: row.serverTime), 5, "Six current members still see the mature snapshot of five")
        await store.submit(op: "report_scoped", fields: ["id": .string(id.uuidString.lowercased()), "subject": .null, "reason": .string("unsafe_behavior")])
        XCTAssertNil(store.pending)
        try await login(6, sdk, store)
        // The participant client's endpoint allowlist intentionally excludes
        // operator reports/actions. Use the authenticated operator SDK path;
        // assert actual server denials, not a participant-side unavailable error.
        func operatorRead(_ name: String, _ fields: [String: ChallengeJSON] = [:]) async throws -> ChallengeJSON {
            XCTAssertEqual(sdk.auth.currentSession?.user.id, config.actors[6].id)
            let response = try await sdk.rpc(name, params: ChallengeJSON.object(fields)).execute()
            return try JSONDecoder().decode(ChallengeJSON.self, from: response.data)
        }
        func reports() async throws -> ChallengeJSON {
            try await operatorRead("challenge_operator_reports_v1", ["p_id": .string(id.uuidString.lowercased())])
        }
        do { _ = try await reports(); XCTFail("An unassigned operator cannot read reports") }
        catch { XCTAssertEqual((error as? PostgrestError)?.code, "42501") }
        try await control(["action": "community_moderator", "id": id.uuidString])
        let scoped = try await reports()
        if case .array(let reports) = scoped { XCTAssertEqual(reports.count, 1) }
        else { XCTFail("Expected the scoped report") }
        do {
            _ = try await operatorRead("challenge_support_reports_v1")
            XCTFail("A community grant cannot read global support reports")
        } catch { XCTAssertEqual((error as? PostgrestError)?.code, "42501") }
        _ = try await operatorRead("challenge_operator_action_v1", [
            "p_request_id": .string(UUID().uuidString.lowercased()),
            "p_payload": .object(["op": .string("remove"), "id": .string(id.uuidString.lowercased()),
                                  "actor_id": .string(config.actors[5].id.uuidString.lowercased()), "reason": .string("unsafe_behavior")])
        ])
        try await control(["action": "community_moderator", "id": id.uuidString, "revoke": true])
        do { _ = try await reports(); XCTFail("Revoked moderation cannot read reports") }
        catch { XCTAssertEqual((error as? PostgrestError)?.code, "42501") }
        try await login(5, sdk, store)
        let removed = try await client.detail(id, actor: config.actors[5].id)
        XCTAssertEqual(removed.own(config.actors[5].id)?.exited, true)
        XCTAssertEqual(store.access?.suspended, false, "Scoped removal must not suspend the account")
        try await login(4, sdk, store)
        row = try await client.detail(id, actor: config.actors[4].id)
        await store.submit(op: "leave", challenge: row)
        XCTAssertNil(store.pending)
        try await login(0, sdk, store)
        row = try await client.detail(id, actor: config.actors[0].id)
        XCTAssertEqual(row.counts?.state, "threshold")
        XCTAssertNil(row.counts?.joined); XCTAssertNil(row.counts?.asOf)
        // Finish only this fixture, retaining each own safe-exit record.
        for i in 0...3 {
            try await login(i, sdk, store)
            row = try await client.detail(id, actor: config.actors[i].id)
            if !row.isClosed { await store.submit(op: "leave", challenge: row); XCTAssertNil(store.pending) }
        }
    }
    func createPolicy(_ policy: ChallengeV1Policy, _ sdk: SupabaseClient, _ store: ChallengeV1Store, _ client: SupabaseChallengeV1Client) async throws -> UUID {
        try await control(["action": "clock", "now": "2026-10-01T12:00:00Z"])
        try await login(0, sdk, store)
        var conf: [String: ChallengeJSON] = ["start_date": .string("2026-10-03"), "days": .integer(1), "timezone": .string("UTC"), "amount_cents": .integer(100)]
        if policy.metric == .timed { conf["distance_mm"] = .integer(1_609_344) }
        let configJSON = ChallengeJSON.object(conf)
        let id: UUID
        if policy.mode == .personal {
            let preview = try await client.read("challenge_personal_preview_v1", fields: ["p_policy": .string(policy.id), "p_config": configJSON, "p_target": .integer(100)], actor: config.actors[0].id, as: ChallengeV1.Agreement.self)
            await store.submit(op: "personal_commit", fields: ["policy": .string(policy.id), "config": configJSON, "target": .integer(100), "digest": .string(preview.digest), "consent": .bool(true)])
            XCTAssertNil(store.pending, store.error ?? policy.id)
            id = try XCTUnwrap(store.lastReceipt?.id)
        } else if policy.mode == .community {
            let publication = try await control(["action": "community"])
            let publishedID = try XCTUnwrap(publication["id"] as? String)
            for i in 0...1 {
                try await login(i, sdk, store)
                let catalog = try await client.read("challenge_community_catalog_v1", actor: config.actors[i].id, as: [ChallengeV1Community].self)
                let cohort = try XCTUnwrap(catalog.first { $0.id.uuidString.lowercased() == publishedID })
                await store.submit(op: "join_community", fields: ["id": .string(cohort.id.uuidString.lowercased()), "digest": .string(cohort.digest), "consent": .bool(true)])
                XCTAssertNil(store.pending, store.error ?? policy.id)
            }
            id = try XCTUnwrap(store.lastReceipt?.id)
        } else {
            await store.submit(op: "create", fields: ["policy": .string(policy.id), "config": configJSON])
            XCTAssertNil(store.pending, store.error ?? policy.id)
            id = try XCTUnwrap(store.lastReceipt?.id)
            var row = try await client.detail(id, actor: config.actors[0].id)
            if policy.hasTarget {
                await store.submit(op: "target", challenge: row, fields: ["target": .integer(100)])
                row = try await client.detail(id, actor: config.actors[0].id)
            }
            await store.submit(op: "invite", challenge: row, fields: ["username": .string(config.actors[1].username)])
            try await login(1, sdk, store)
            if policy.hasTarget {
                row = try await client.detail(id, actor: config.actors[1].id)
                await store.submit(op: "target", challenge: row, fields: ["target": .integer(100)])
            }
            try await login(0, sdk, store)
            row = try await client.detail(id, actor: config.actors[0].id)
            await store.submit(op: "select", challenge: row, fields: ["actor_id": .string(config.actors[1].id.uuidString.lowercased()), "selected": .bool(true)])
            row = try await client.detail(id, actor: config.actors[0].id)
            await store.submit(op: "freeze", challenge: row)
            for i in 0...1 {
                try await login(i, sdk, store)
                row = try await client.detail(id, actor: config.actors[i].id)
                if !policy.hasTarget {
                    XCTAssertTrue(row.members.allSatisfy { $0.target == nil })
                    if case .array(let people) = row.agreement?.terms?["participants"] {
                        XCTAssertTrue(people.allSatisfy { $0["target"] == nil }, "Leaderboards have no target fields in the agreement")
                    } else { XCTFail("Missing complete agreement") }
                }
                await store.submit(op: "consent", challenge: row, fields: ["digest": .string(try XCTUnwrap(row.agreement?.digest)), "consent": .bool(true)])
                XCTAssertNil(store.pending, store.error ?? policy.id)
            }
        }
        return id
    }
    func entry(_ sdk: SupabaseClient, _ store: ChallengeV1Store, _ client: SupabaseChallengeV1Client) async throws {
        try await control(["action": "clock", "now": "2026-10-01T12:00:00Z"])
        try await login(0, sdk, store)
        await store.submit(op: "create", fields: ["config": .object(["start_date": .string("2026-10-03"), "days": .integer(1), "timezone": .string("UTC"), "amount_cents": .integer(100)])])
        let id = try XCTUnwrap(store.lastReceipt?.id)
        try await control(["action": "lose", "rpc": "challenge_command_v1"])
        await store.submit(op: "issue_link", fields: ["id": .string(id.uuidString.lowercased())])
        let pendingIssue = try XCTUnwrap(store.pending)
        let recreated = ChallengeV1Store(auth: SupabaseAuthClient(client: sdk), client: client, requests: store.requests)
        recreated.setActor(config.actors[0].id); await recreated.refresh()
        XCTAssertEqual(recreated.pending, pendingIssue)
        await recreated.retry()
        XCTAssertNil(recreated.pending, recreated.error ?? "Exact issuance recovery failed")
        let link = try XCTUnwrap(recreated.lastReceipt)
        await store.refresh()
        XCTAssertEqual(store.issuedLinks.first { $0.id == link.id }?.requestId, pendingIssue.requestId)
        XCTAssertEqual(store.issuedLinks.first { $0.id == link.id }?.challengeId, id)
        let token = try XCTUnwrap(link.token)
        try await control(["action": "unallow_actor", "actor": config.actors[6].id.uuidString])
        try await login(6, sdk, store)
        let before = try await client.read("challenge_access_status_v1", actor: config.actors[6].id, as: ChallengeV1Access.self)
        XCTAssertFalse(before.betaAccess, "Entrant must actually lack access before redeeming")
        let request = ChallengeV1Request(actor: config.actors[6].id, payload: .object(["op": .string("redeem_link"), "token": .string(token)]))
        let receipt = try await client.submit(request)
        XCTAssertEqual(receipt.status, "pending_request")
        let access = try await client.read("challenge_access_status_v1", actor: config.actors[6].id, as: ChallengeV1Access.self)
        XCTAssertTrue(access.ageConfirmed && access.betaAccess)
        var own = try await client.detail(id, actor: config.actors[6].id)
        XCTAssertTrue(own.socialHidden); XCTAssertEqual(own.members.count, 1)
        XCTAssertFalse(try XCTUnwrap(own.own(config.actors[6].id)).selected)
        try await login(0, sdk, store)
        let row = try await client.detail(id, actor: config.actors[0].id)
        await store.submit(op: "reject", challenge: row, fields: ["actor_id": .string(config.actors[6].id.uuidString.lowercased())])
        XCTAssertNil(store.pending, store.error ?? "Rejection failed")
        try await control(["action": "lose", "rpc": "challenge_command_v1"])
        await store.submit(op: "revoke_link", fields: ["id": .string(try XCTUnwrap(link.id).uuidString.lowercased())])
        XCTAssertNotNil(store.pending)
        XCTAssertTrue(store.issuedLinks.contains { $0.id == link.id })
        await store.retry()
        XCTAssertNil(store.pending, store.error ?? "Revocation failed")
        XCTAssertFalse(store.issuedLinks.contains { $0.id == link.id })
        try await login(6, sdk, store)
        own = try await client.detail(id, actor: config.actors[6].id)
        XCTAssertTrue(try XCTUnwrap(own.own(config.actors[6].id)).exited)
        let retained = try await client.read("challenge_access_status_v1", actor: config.actors[6].id, as: ChallengeV1Access.self)
        XCTAssertTrue(retained.betaAccess, "Declining and revoking do not revoke granted access")
        let retry = try await client.submit(request)
        XCTAssertEqual(retry, receipt, "Exact redemption receipt recovers after rejection and revocation")
        try await login(0, sdk, store)
        let remaining = try await client.detail(id, actor: config.actors[0].id)
        await store.submit(op: "cancel", challenge: remaining)
        XCTAssertNil(store.pending)
        try await invitedReconsent(sdk, store, client)
        try await login(6, sdk, store)
        XCTAssertFalse(store.challenges.isEmpty)
        try await control(["action": "revoke_actor_sessions", "actor": config.actors[6].id.uuidString])
        await store.refresh()
        XCTAssertNil(store.actor, "Server-side session revocation clears the native actor even while the local token has time left")
        XCTAssertTrue(store.challenges.isEmpty)
        // Real Swift transport and local Auth for participant safety, including
        // an acknowledged server action whose response is actually lost.
        let policy = try XCTUnwrap(ChallengeV1Policy.all.first { $0.id == "friend_steps_goal_v1" })
        let safeID = try await createPolicy(policy, sdk, store, client)
        try await control(["action": "clock", "now": "2026-10-03T12:00:00Z"])
        try await control(["action": "process", "id": safeID.uuidString])
        try await login(0, sdk, store)
        try await control(["action": "clock", "now": "2026-10-03T12:00:00Z", "admission": false, "processing": false])
        await store.submit(op: "report", fields: ["subject": .string(config.actors[1].id.uuidString.lowercased()), "reason": .string("unwanted_contact")])
        XCTAssertNil(store.pending, store.error ?? "Native report failed during pause")
        try await control(["action": "lose", "rpc": "challenge_command_v1"])
        await store.submit(op: "block", fields: ["subject": .string(config.actors[1].id.uuidString.lowercased())])
        XCTAssertNotNil(store.pending, "Lost block response keeps the exact durable action")
        await store.retry()
        XCTAssertNil(store.pending, store.error ?? "Block recovery failed")
        let blocked = try await client.detail(safeID, actor: config.actors[0].id)
        XCTAssertTrue(blocked.socialHidden); XCTAssertEqual(blocked.members.count, 1)
        XCTAssertEqual(blocked.final?.result.own?.returnedCents, 100)
        try await login(1, sdk, store)
        let other = try await client.detail(safeID, actor: config.actors[1].id)
        XCTAssertTrue(other.socialHidden); XCTAssertEqual(other.members.count, 1)
        XCTAssertEqual(other.final?.result.own?.returnedCents, 100)
    }
    func invitedReconsent(_ sdk: SupabaseClient, _ store: ChallengeV1Store, _ client: SupabaseChallengeV1Client) async throws {
        // Keep actor 7 off the fixture allowlist: its previously granted link
        // access must suffice for the complete nonfriend journey.
        try await login(0, sdk, store)
        await store.submit(op: "create", fields: ["config": .object(["start_date": .string("2026-10-03"), "days": .integer(1), "timezone": .string("UTC"), "amount_cents": .integer(100)])])
        let id = try XCTUnwrap(store.lastReceipt?.id)
        await store.submit(op: "issue_link", fields: ["id": .string(id.uuidString.lowercased())])
        let token = try XCTUnwrap(store.lastReceipt?.token)
        try await login(6, sdk, store)
        let intentDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: intentDirectory) }
        let intent = ChallengeInvitationIntent(directory: intentDirectory)
        intent.receive(try XCTUnwrap(URL(string: "gametime-beta://challenge-invite/" + token)))
        let panel = ChallengeEntryPanel(store: store, invitation: intent)
        try await control(["action": "lose", "rpc": "challenge_command_v1"])
        await panel.useInvitation()
        XCTAssertNotNil(store.pending); XCTAssertFalse(intent.link.isEmpty)
        XCTAssertEqual(ChallengeInvitationIntent(directory: intentDirectory).link, intent.link)
        await store.retry()
        await panel.useInvitation()
        XCTAssertTrue(intent.link.isEmpty, "Only the confirmed unchanged invitation is acknowledged")
        XCTAssertNil(store.pending, store.error ?? "Second invitation failed")
        for i in [0, 6] {
            try await login(i, sdk, store)
            let row = try await client.detail(id, actor: config.actors[i].id)
            await store.submit(op: "target", challenge: row, fields: ["target": .integer(i == 0 ? 100 : 200)])
            XCTAssertNil(store.pending, store.error ?? "Proposal failed")
        }
        try await login(0, sdk, store)
        var row = try await client.detail(id, actor: config.actors[0].id)
        await store.submit(op: "select", challenge: row, fields: ["actor_id": .string(config.actors[6].id.uuidString.lowercased()), "selected": .bool(true)])
        row = try await client.detail(id, actor: config.actors[0].id)
        await store.submit(op: "freeze", challenge: row)
        row = try await client.detail(id, actor: config.actors[0].id)
        let oldDigest = try XCTUnwrap(row.agreement?.digest)
        for i in [0, 6] {
            try await login(i, sdk, store)
            row = try await client.detail(id, actor: config.actors[i].id)
            await store.submit(op: "consent", challenge: row, fields: ["digest": .string(oldDigest), "consent": .bool(true)])
            XCTAssertNil(store.pending, store.error ?? "Consent failed")
        }
        try await login(0, sdk, store)
        row = try await client.detail(id, actor: config.actors[0].id)
        XCTAssertEqual(row.status, "scheduled")
        await store.submit(op: "reopen", challenge: row)
        row = try await client.detail(id, actor: config.actors[0].id)
        XCTAssertEqual(row.status, "lobby_open"); XCTAssertNil(row.agreement)
        XCTAssertTrue(row.members.allSatisfy { !$0.consented })
        await store.submit(op: "target", challenge: row, fields: ["target": .integer(150)])
        row = try await client.detail(id, actor: config.actors[0].id)
        await store.submit(op: "freeze", challenge: row)
        row = try await client.detail(id, actor: config.actors[0].id)
        let newDigest = try XCTUnwrap(row.agreement?.digest)
        XCTAssertNotEqual(newDigest, oldDigest)
        let obsolete = ChallengeV1Request(actor: config.actors[0].id, payload: .object(["op": .string("consent"), "id": .string(id.uuidString.lowercased()), "revision": .integer(row.revision), "digest": .string(oldDigest), "consent": .bool(true)]))
        do { _ = try await client.submit(obsolete); XCTFail("Obsolete consent must fail") } catch { XCTAssertNotNil(error as? ChallengeV1Error) }
        for i in [0, 6] {
            try await login(i, sdk, store)
            row = try await client.detail(id, actor: config.actors[i].id)
            XCTAssertFalse(try XCTUnwrap(row.own(config.actors[i].id)).consented)
            await store.submit(op: "consent", challenge: row, fields: ["digest": .string(newDigest), "consent": .bool(true)])
            XCTAssertNil(store.pending, store.error ?? "Fresh consent failed")
        }
        row = try await client.detail(id, actor: config.actors[6].id)
        XCTAssertEqual(row.status, "scheduled"); XCTAssertTrue(row.members.allSatisfy { $0.consented })
        await store.submit(op: "leave", challenge: row)
        XCTAssertNil(store.pending, store.error ?? "Nonfriend safe exit failed")
        row = try await client.detail(id, actor: config.actors[6].id)
        XCTAssertTrue(row.socialHidden); XCTAssertEqual(row.final?.result.own?.returnedCents, 100)
    }
    func login(_ index:Int,_ sdk:SupabaseClient,_ store:ChallengeV1Store) async throws {
        store.setActor(nil)
        let session=try await sdk.auth.signIn(email:config.actors[index].email,password:config.password)
        XCTAssertEqual(session.user.id,config.actors[index].id)
        store.setActor(session.user.id)
        let age = try await store.client.submit(ChallengeV1Request(actor: session.user.id, payload: .object(["op": .string("confirm_age"), "confirmed": .bool(true)])))
        XCTAssertEqual(age.confirmed, true, "Explicit fictional account age confirmation through native client")
        await store.refresh()
        XCTAssertNil(store.error)
    }
    @discardableResult
    func control(_ value:[String:Any]) async throws -> [String: Any] {
        var request=URLRequest(url:config.url.appendingPathComponent("__beta/control"))
        request.httpMethod="POST";request.httpBody=try JSONSerialization.data(withJSONObject:value)
        request.setValue(config.controlToken,forHTTPHeaderField:"X-Beta-Control")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (data,response)=try await URLSession.shared.data(for:request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
@MainActor private final class AppChallengeSmokeAuth: GameTime.AuthClient {
    let sdk: SupabaseClient
    let auth: SupabaseAuthClient
    let password: String
    init(sdk: SupabaseClient, password: String) { self.sdk = sdk; self.password = password; auth = SupabaseAuthClient(client: sdk) }
    func currentUserID() async -> UUID? { await auth.currentUserID() }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { await auth.authStateChanges() }
    func signOut() async throws { try await auth.signOut() }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID {
        if identity.idToken == "cancel" { throw CancellationError() }
        if identity.idToken == "fail" { throw ChallengeV1Error.unavailable }
        return try await sdk.auth.signIn(email: identity.idToken, password: password).user.id
    }
}
#endif
