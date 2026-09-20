import Foundation
import Testing
@testable import GameTimeCore

@Suite("Versioned Apple Exercise credit")
struct ChallengeHealthExerciseCreditTests {
    typealias F = ChallengeHealthFixtures
    func request(_ purpose: ChallengeHealthReadRequest.Purpose = .readinessHistory,
                 source: ChallengeHealthRealSourcePolicy = .appleWatchExerciseCreditV2) throws -> ChallengeHealthReadRequest {
        let binding = try ChallengeHealthBinding(actorID: F.id(1), challengeID: F.id(2), agreementVersion: 1,
            termsDigest: String(repeating: "a", count: 64), metric: .exerciseSeconds,
            challengeWindow: F.window(start: 1_000, end: 2_000), realSourcePolicy: source)
        return try ChallengeHealthReadRequest(binding: binding, deviceRequestID: F.id(3),
            queryWindow: purpose == .challengeActivity ? binding.challengeWindow : F.window(start: purpose == .suggestionHistory ? -2_418_200 : -2_800_000, end: 1_000), purpose: purpose)
    }
    func record(_ id: Int = 10, start: Double = 0, end: Double = 60, minutes: Double = 30,
                manual: Bool? = nil, writer: String? = "com.apple.health", watch: String? = "Watch7,1",
                sync: String? = nil, revision: Int? = nil) -> WeeklySourceRecord {
        WeeklySourceRecord(id: F.id(id), metric: .appleExerciseMinutes, start: F.date(start), end: F.date(end), value: minutes,
            sourceBundleIdentifier: writer, sourceProductType: watch, wasUserEntered: manual, syncIdentifier: sync, syncVersion: revision)
    }
    @Test func acceptsUnknownCausalOriginAndNormalizesOnceAfterReconciliation() throws {
        let query = try request(), adapter = ChallengeHealthAppleWatchExerciseCreditAdapter()
        let one = record(minutes: 0.509), two = record(11, start: 60, end: 120, minutes: 0.509, watch: "Watch8,3")
        let snapshot = try F.snapshot([one, two], request: query)
        let result = adapter.evaluate(snapshot)
        #expect(result.activity?.integerValue == 61)
        #expect(result.permitsRealConsent && result.acceptsRealSourceObservation && !result.supportsConfirmedMiss)
        #expect(!result.issues.contains(.exerciseCausalLineageUnavailable))
        let wire = try ChallengeHealthReadinessRequest(binding: query.binding, snapshot: snapshot, evaluation: result, requestID: F.id(81))
        #expect(try ChallengeHealthReadinessRequest(restoring: wire.exactBytes) == wire)
        let activity = try request(.challengeActivity)
        let upload = try ChallengeHealthUploadRequest(binding: activity.binding, requestID: F.id(90), revision: 1, previousRevision: nil,
            replacement: .value(ChallengeHealthValue(metric: .exerciseSeconds, integerValue: 61)),
            observedAtMicroseconds: (F.epoch + 1_500) * 1_000_000, queriedThroughMicroseconds: (F.epoch + 1_500) * 1_000_000)
        #expect(try ChallengeHealthUploadRequest(restoring: upload.exactBytes) == upload)
        let json = try #require(JSONSerialization.jsonObject(with: upload.exactBytes) as? [String: Any])
        #expect(json["source_policy_version"] as? String == "apple_watch_exercise_credit_v2")
        #expect(json["records"] == nil && json["history"] == nil)
    }
    @Test func excludesIdentifiableManualAndUnsupportedWhileOtherUncertaintyBlocks() throws {
        let query = try request(), adapter = ChallengeHealthAppleWatchExerciseCreditAdapter()
        for unsupported in [record(11, manual: true), record(11, writer: "com.example.run"), record(11, watch: "iPhone17,1"), record(11, watch: "iPad13,1")] {
            let result = adapter.evaluate(try F.snapshot([record(), unsupported], request: query))
            #expect(result.activity?.integerValue == 1800)
        }
        for unknown in [record(11, writer: nil), record(11, watch: nil), record(11, watch: "WatchFuture"), record(11)] {
            let result = adapter.evaluate(try F.snapshot([record(), unknown], request: query))
            #expect(result.activity == nil && result.readiness == .staleOrIncomplete)
        }
        #expect(adapter.evaluate(try F.snapshot([record(), record(minutes: 31)], request: query)).activity == nil)
    }
    @Test func correctionsDisappearanceAndPartialReadsNeverEstablishAMiss() throws {
        let query = try request(.challengeActivity), adapter = ChallengeHealthAppleWatchExerciseCreditAdapter()
        let before = try F.snapshot([record(start: 1_100, end: 1_160, minutes: 10.01)], request: query, observed: 1_500, freshness: 1_500)
        let after = try F.snapshot([record(start: 1_100, end: 1_160, minutes: 9.99)], request: query, observed: 1_600, freshness: 1_600)
        let correction = adapter.evaluate(after, replacing: before)
        #expect(correction.activity?.integerValue == 599 && !correction.supportsConfirmedMiss)
        let absent = adapter.evaluate(try F.snapshot([], request: query, observed: 1_600, freshness: 1_600), replacing: before)
        #expect(absent.realReplacementDecision.normalizedReplacement == .unresolved(.lostVisibility))
        let deleted = adapter.evaluate(try F.snapshot([], request: query, observed: 1_600, freshness: 1_600, evidence: .boundedSnapshotAfterDeletion, deleted: [F.id(10)]), replacing: before)
        #expect(deleted.realReplacementDecision.normalizedReplacement == .deleted)
        for evidence in [ChallengeHealthEvidence.truncated, .anchoredChanges, .observerInvalidation] {
            let incomplete = adapter.evaluate(try F.snapshot([record(start: 1_100, end: 1_160)], request: query, observed: 1_600, freshness: 1_600, evidence: evidence))
            #expect(incomplete.activity == nil && !incomplete.supportsConfirmedMiss)
        }
    }
    @Test func strictV1AndPlanningPurposeRemainSeparate() throws {
        let strict = try request(source: .appleWatchExerciseV1)
        let snapshot = try F.snapshot([record()], request: strict)
        #expect(ChallengeHealthAppleWatchExerciseAdapter().evaluate(snapshot).readiness == .unsupported)
        #expect(ChallengeHealthAppleWatchExerciseCreditAdapter().evaluate(snapshot).activity == nil)
        let query = try request(.suggestionHistory)
        let planning = try F.snapshot([record()], request: query)
        let result = ChallengeHealthAppleWatchExerciseCreditAdapter().evaluate(planning)
        #expect(result.activity?.integerValue == 1800 && !result.permitsRealConsent)
        #expect(throws: Error.self) { try ChallengeHealthReadinessRequest(binding: query.binding, snapshot: planning, evaluation: result, requestID: F.id(82)) }
    }
}
