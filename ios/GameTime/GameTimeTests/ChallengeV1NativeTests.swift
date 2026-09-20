import XCTest
@testable import GameTime

@MainActor final class ChallengeV1NativeTests:XCTestCase {
    func testHostedAndMalformedURLsCannotSend() async throws {
        for text in ["https://example.com","http://127.0.0.1","http://127.0.0.1:58321/redirect","http://user:pass@127.0.0.1:58321"] {
            var calls=0;let actor=UUID()
            let client=SupabaseChallengeV1Client(url:URL(string:text)!,binding:{.init(actorID:actor,identity:"session")},rpc:{_,_ in calls+=1;return Data("[]".utf8)})
            do { _=try await client.list(actor:actor);XCTFail("Must reject endpoint") } catch {}
            XCTAssertEqual(calls,0)
        }
    }
    func testClientRejectsResponseAfterSessionSwitch() async throws {
        let actor=UUID();var current=WeeklyClientSession(actorID:actor,identity:"first")
        let client=SupabaseChallengeV1Client(url:URL(string:"http://127.0.0.1:58321")!,binding:{current},rpc:{_,_ in
            current = .init(actorID:actor,identity:"replacement");return Data("[]".utf8)
        })
        do { _=try await client.list(actor:actor);XCTFail("A replaced session must reject in-flight data") }
        catch { XCTAssertEqual(error as? ChallengeV1Error,.accountChanged) }
    }
    func testDurableRequestsCannotBeOverwrittenOrReadByAnotherActor() async throws {
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {if FileManager.default.fileExists(atPath:dir.path){try? FileManager.default.removeItem(at:dir)}}
        let queue=ChallengeV1RequestStore(directory:dir);let actor=UUID()
        let first=ChallengeV1Request(actor:actor,payload:.object(["op":.string("leave")]))
        try await queue.save(first)
        let restored=try await ChallengeV1RequestStore(directory:dir).load(actor)
        XCTAssertEqual(restored,first)
        let other=try await queue.load(UUID());XCTAssertNil(other)
        do {try await queue.save(ChallengeV1Request(actor:actor,payload:.object(["op":.string("cancel")])));XCTFail("Do not overwrite pending action")}
        catch {XCTAssertEqual(error as? ChallengeV1Error,.storage)}
        try await queue.remove(first)
        let gone=try await queue.load(actor);XCTAssertNil(gone)
    }
    func testHeldFinalAuthenticationCannotRestoreSupersededSocialContent() async throws {
        let actor=UUID();let auth=ChallengeHeldAuth(actor);let client=ChallengeTestClient()
        let dir=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store=ChallengeV1Store(auth:auth,client:client,requests:ChallengeV1RequestStore(directory:dir))
        store.setActor(actor);client.rows=[sample(actor,"Old friend")];auth.holdCall=2
        let old=Task{await store.refresh()}
        while auth.held==nil {await Task.yield()}
        client.rows=[sample(actor,"Current friend")]
        await store.refresh()
        XCTAssertEqual(store.challenges.first?.members.first?.username,"Current friend")
        auth.held?.resume(returning:actor);auth.held=nil;await old.value
        XCTAssertEqual(store.challenges.first?.members.first?.username,"Current friend")
        store.setActor(nil);XCTAssertTrue(store.challenges.isEmpty)
    }
    func testExpiredAuthClearsPreviouslyVisibleSocialContent() async throws {
        let actor=UUID();let auth=ChallengeHeldAuth(actor);let client=ChallengeTestClient()
        let store=ChallengeV1Store(auth:auth,client:client,requests:ChallengeV1RequestStore(directory:FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)))
        store.setActor(actor);client.rows=[sample(actor,"Private friend")];await store.refresh()
        XCTAssertFalse(store.challenges.isEmpty)
        auth.actor=nil;await store.refresh()
        XCTAssertTrue(store.challenges.isEmpty)
        XCTAssertNil(store.actor)
    }
    func testCommunityCountsRequireMatureServerSnapshot() throws {
        let time = try ChallengeInstant("2026-10-01T12:00:00Z")
        let counts = ChallengeV1.Counts(joined: 5, state: "available", asOf: time)
        XCTAssertNil(counts.disclosedJoined(at: try ChallengeInstant("2026-10-01T12:14:59Z")))
        XCTAssertEqual(counts.disclosedJoined(at: try ChallengeInstant("2026-10-01T12:15:00Z")), 5)
        XCTAssertEqual(counts.disclosedJoined(at: try ChallengeInstant("2026-10-01T12:15:01Z")), 5)
        XCTAssertNil(ChallengeV1.Counts(joined: 4, state: "available", asOf: time).disclosedJoined(at: try ChallengeInstant("2026-10-01T13:00:00Z")))
        XCTAssertNil(ChallengeV1.Counts(joined: 6, state: "threshold", asOf: time).disclosedJoined(at: try ChallengeInstant("2026-10-01T13:00:00Z")))
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let hidden = try decoder.decode(ChallengeV1.Counts.self, from: Data(#"{"joined":null,"state":"threshold","as_of":null}"#.utf8))
        XCTAssertNil(hidden.joined)
        XCTAssertNil(hidden.disclosedJoined(at: time))
    }
    func testQuotaErrorCannotDecodeAsSuccessfulReceipt() async throws {
        let actor = UUID()
        let client = SupabaseChallengeV1Client(url: URL(string: "http://127.0.0.1:58321")!, binding: { .init(actorID: actor, identity: "session") }, rpc: { _, _ in
            Data(#"{"message":"challenge_rate_limited"}"#.utf8)
        })
        do {
            _ = try await client.submit(ChallengeV1Request(actor: actor, payload: .object(["op": .string("redeem_link")])))
            XCTFail("Quota rejection is not a successful receipt")
        } catch { XCTAssertEqual(error as? ChallengeV1Error, .server("challenge_rate_limited")) }
    }

    func testPrivateTrialGuardErrorsTellThePersonWhatToDo() {
        XCTAssertEqual(
            ChallengeV1Error.server("challenge_private_trial_account_required").localizedDescription,
            "This private trial is available only to the selected account. Sign in with the account you were invited to use."
        )
        XCTAssertEqual(
            ChallengeV1Error.server("challenge_private_trial_personal_steps_only").localizedDescription,
            "This private trial currently supports personal step goals only. Choose a personal step goal to continue."
        )
    }
    private func sample(_ actor:UUID,_ name:String)->ChallengeV1 {
        let start=ChallengeInstant(date:Date());let end=ChallengeInstant(date:Date().addingTimeInterval(86400))
        return ChallengeV1(id:UUID(),creatorId:actor,policy:"friend_steps_goal_v1",config:.init(startDate:"2026-10-03",days:1,timezone:"UTC",amountCents:100,startsAt:start,endsAt:end,syncBy:end,correctionsBy:end,noticeDue:end),status:"lobby_open",revision:1,agreementVersion:0,serverTime:start,socialHidden:false,agreement:nil,members:[.init(actorId:actor,username:name,target:100,selected:true,exited:false,consented:false,fact:nil)],notice:nil,reviews:[],final:nil)
    }
}
@MainActor private final class ChallengeTestClient:ChallengeV1Client {
    var rows:[ChallengeV1]=[]
    func list(actor:UUID) async throws->[ChallengeV1]{rows}
    func detail(_ id:UUID,actor:UUID) async throws->ChallengeV1{rows.first!}
    func submit(_ request:ChallengeV1Request) async throws->ChallengeV1Receipt{throw ChallengeV1Error.unavailable}
    func abandon(_ request:ChallengeV1Request) async throws->ChallengeV1Receipt{throw ChallengeV1Error.unavailable}
}
@MainActor private final class ChallengeHeldAuth:AuthClient {
    var actor:UUID?;var calls=0;var holdCall=0;var held:CheckedContinuation<UUID?,Never>?
    init(_ actor:UUID){self.actor=actor}
    func currentUserID() async->UUID? {
        calls+=1
        if calls==holdCall{return await withCheckedContinuation{held=$0}}
        return actor
    }
    func authStateChanges() async->AsyncStream<AuthSnapshot>{AsyncStream{$0.finish()}}
    func signInWithApple(_ identity:AppleIdentity) async throws->UUID{actor!}
    func signOut() async throws{actor=nil}
}
