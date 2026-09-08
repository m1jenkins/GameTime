#if DEBUG
import Supabase
import XCTest
@testable import GameTime

@MainActor final class ChallengeV1NativeSmokeTests: XCTestCase {
    struct Config: Decodable {
        struct Actor: Decodable { let id:UUID;let email:String;let username:String }
        let url:URL;let key:String;let controlToken:String;let password:String;let actors:[Actor]
    }
    var config:Config!
    func testTwoAndSixPersonProductionNativeJourney() async throws {
        let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let file=root.appendingPathComponent("tmp/beta-native-smoke.json")
        guard FileManager.default.fileExists(atPath:file.path) else { throw XCTSkip("Run scripts/beta-native-smoke.py with the owned Simulator.") }
        config=try JSONDecoder().decode(Config.self,from:Data(contentsOf:file))
        XCTAssertEqual(config.url.absoluteString,"http://127.0.0.1:58339")
        let sdk=SupabaseClient(supabaseURL:config.url,supabaseKey:config.key,options:.init(auth:.init(storage:ChallengeMemoryAuthStorage(),autoRefreshToken:false,emitLocalSessionAsInitialSession:true)))
        let directory=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        defer { if FileManager.default.fileExists(atPath:directory.path) { try? FileManager.default.removeItem(at:directory) } }
        let queue=ChallengeV1RequestStore(directory:directory)
        let client=SupabaseChallengeV1Client(sdk:sdk,url:config.url,key:config.key)
        let store=ChallengeV1Store(auth:SupabaseAuthClient(client:sdk),client:client,requests:queue)
        for people in [2,6] {
            try await control(["action":"clock","now":"2026-10-01T12:00:00Z"])
            try await login(0,sdk,store)
            if people==2 { try await control(["action":"lose","rpc":"challenge_mutate_v1"]) }
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
    }
    func login(_ index:Int,_ sdk:SupabaseClient,_ store:ChallengeV1Store) async throws {
        store.setActor(nil)
        let session=try await sdk.auth.signIn(email:config.actors[index].email,password:config.password)
        XCTAssertEqual(session.user.id,config.actors[index].id)
        store.setActor(session.user.id);await store.refresh()
        XCTAssertNil(store.error)
    }
    func control(_ value:[String:Any]) async throws {
        var request=URLRequest(url:config.url.appendingPathComponent("__beta/control"))
        request.httpMethod="POST";request.httpBody=try JSONSerialization.data(withJSONObject:value)
        request.setValue(config.controlToken,forHTTPHeaderField:"X-Beta-Control")
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        let (_,response)=try await URLSession.shared.data(for:request)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode,200)
    }
}
#endif
