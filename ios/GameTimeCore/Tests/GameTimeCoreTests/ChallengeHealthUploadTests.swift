import Foundation
import Testing
@testable import GameTimeCore

@Suite("Real Health normalized uploads and durable journal")
struct ChallengeHealthUploadTests {
    let actor = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let challenge = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!

    func request(actor: UUID? = nil, id: UUID = UUID(), revision: Int = 1,
                 value: Int64 = 123) throws -> ChallengeHealthUploadRequest {
        let window = try ChallengeHealthWindow(startMicroseconds: 1_800_000_000_123456,
            endMicroseconds: 1_800_086_400_123456, timeZoneIdentifier: "UTC", calendar: .gregorian)
        let binding = try ChallengeHealthBinding(actorID: actor ?? self.actor, challengeID: challenge,
            agreementVersion: 2, termsDigest: String(repeating: "a", count: 64), metric: .steps,
            challengeWindow: window, realSourcePolicy: .appleWatchAutomaticStepsV1)
        return try ChallengeHealthUploadRequest(binding: binding, requestID: id, revision: revision,
            previousRevision: revision == 1 ? nil : revision - 1,
            replacement: .value(ChallengeHealthValue(metric: .steps, integerValue: value)),
            observedAtMicroseconds: 1_800_086_401_123456, queriedThroughMicroseconds: window.endMicroseconds)
    }
    func signed(_ request: ChallengeHealthUploadRequest) throws -> ChallengeHealthSignedUpload {
        try ChallengeHealthSignedUpload(request: request, keyID: Data(repeating: 1, count: 32).base64EncodedString(),
                                        assertion: Data([1, 2, 3]), environment: "development")
    }
    func receipt(_ request: ChallengeHealthUploadRequest) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["version": "challenge_real_health_receipt_v1",
            "request_id": request.requestID.uuidString.lowercased(), "challenge_id": challenge.uuidString.lowercased(),
            "revision": request.revision, "accepted_at": "2027-01-16T00:00:00Z"])
    }

    @Test("canonical wire preserves microseconds and has exactly the minimum fields")
    func privacy() throws {
        let request = try request()
        #expect(try ChallengeHealthUploadRequest(restoring: request.exactBytes) == request)
        let json = try #require(JSONSerialization.jsonObject(with: request.exactBytes) as? [String: Any])
        #expect(json.count == 16)
        #expect((json["window_starts_at"] as? String)?.hasSuffix(".123456Z") == true)
        #expect(json["previous_revision"] is NSNull)
        for forbidden in ["complete", "qualified", "records", "baseline", "source_name", "route"] { #expect(json[forbidden] == nil) }
        var changed = json; changed["records"] = []
        #expect(throws: ChallengeHealthUploadError.self) {
            try ChallengeHealthUploadRequest(restoring: JSONSerialization.data(withJSONObject: changed))
        }
    }

    @Test("relaunch returns identical bytes and assertions; acknowledgement unlocks a lower revision")
    func recovery() throws {
        let first = try request(value: 1000), signedFirst = try signed(first)
        var journal = ChallengeHealthUploadJournal(actorID: actor)
        try journal.enqueue(signedFirst)
        var restored = try ChallengeHealthUploadJournal(restoring: journal.encoded(), actorID: actor)
        #expect(restored.pending == [signedFirst])
        try restored.enqueue(signedFirst)
        #expect(restored.pending.count == 1)
        #expect(throws: ChallengeHealthUploadError.revisionConflict) { try restored.enqueue(signed(request(revision: 2, value: 800))) }
        try restored.acknowledge(first, receipt: receipt(first))
        restored = try ChallengeHealthUploadJournal(restoring: restored.encoded(), actorID: actor)
        try restored.enqueue(signed(request(revision: 2, value: 800)))
        #expect(restored.pending.count == 1)
    }

    @Test("timed wire binds the selected distance and preserves it across relaunch")
    func timedDistance() throws {
        let window = try ChallengeHealthWindow(startMicroseconds: 1_800_000_000_000000,
            endMicroseconds: 1_800_086_400_000000, timeZoneIdentifier: "UTC", calendar: .gregorian)
        let binding = try ChallengeHealthBinding(actorID: actor, challengeID: challenge,
            agreementVersion: 1, termsDigest: String(repeating: "a", count: 64), metric: .timedRunElapsedSeconds,
            challengeWindow: window, realSourcePolicy: .appleWorkoutOutdoorTimedV1, selectedDistanceMillimeters: 5_000_000)
        let upload = try ChallengeHealthUploadRequest(binding: binding, requestID: UUID(), revision: 1,
            previousRevision: nil, replacement: .value(ChallengeHealthValue(metric: .timedRunElapsedSeconds, integerValue: 1501)),
            observedAtMicroseconds: window.endMicroseconds, queriedThroughMicroseconds: window.endMicroseconds)
        let json = try #require(JSONSerialization.jsonObject(with: upload.exactBytes) as? [String: Any])
        #expect(json.count == 17)
        #expect(json["distance_mm"] as? Int == 5_000_000)
        #expect(try ChallengeHealthUploadRequest(restoring: upload.exactBytes) == upload)
        var journal = ChallengeHealthUploadJournal(actorID: actor)
        try journal.enqueue(signed(upload))
        #expect(try ChallengeHealthUploadJournal(restoring: journal.encoded(), actorID: actor).pending == journal.pending)
        for distance in [0, 1_000_000_001] {
            var changed = json; changed["distance_mm"] = distance
            #expect(throws: ChallengeHealthUploadError.self) {
                try ChallengeHealthUploadRequest(restoring: JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys, .withoutEscapingSlashes]))
            }
        }
    }

    @Test("account isolation and changed-body request identity fail before journal mutation")
    func isolation() throws {
        var journal = ChallengeHealthUploadJournal(actorID: actor)
        let first = try request(); try journal.enqueue(signed(first))
        #expect(throws: ChallengeHealthUploadError.corruptJournal) {
            try ChallengeHealthUploadJournal(restoring: journal.encoded(), actorID: UUID())
        }
        #expect(throws: ChallengeHealthUploadError.wrongAccount) { try journal.enqueue(signed(request(actor: UUID()))) }
        #expect(throws: ChallengeHealthUploadError.requestConflict) { try journal.enqueue(signed(request(id: first.requestID, value: 999))) }
        #expect(journal.pending.count == 1)
    }

    @Test("wrong receipt and invalid initial revision preserve the exact pending update")
    func receiptIsolation() throws {
        let first = try request(); var journal = ChallengeHealthUploadJournal(actorID: actor)
        try journal.enqueue(signed(first))
        #expect(throws: ChallengeHealthUploadError.invalidReceipt) { try journal.acknowledge(first, receipt: receipt(request())) }
        #expect(journal.pending.count == 1)
        var empty = ChallengeHealthUploadJournal(actorID: actor)
        #expect(throws: ChallengeHealthUploadError.revisionConflict) { try empty.enqueue(signed(request(revision: 2))) }
        #expect(throws: ChallengeHealthUploadError.invalidRequest) { try request(value: 0) }
    }
}
