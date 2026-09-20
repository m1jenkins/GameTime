import Foundation
import Testing
@testable import GameTimeCore

@Suite("Real Health readiness receipt request")
struct ChallengeHealthReadinessRequestTests {
    typealias F = ChallengeHealthFixtures

    private func binding() throws -> ChallengeHealthBinding {
        try ChallengeHealthBinding(
            actorID: F.id(1), challengeID: F.id(2), agreementVersion: 1,
            termsDigest: String(repeating: "a", count: 64), metric: .steps,
            challengeWindow: F.window(start: 1_000, end: 2_000),
            realSourcePolicy: .appleWatchAutomaticStepsV1
        )
    }

    private func read() throws -> ChallengeHealthReadRequest {
        let binding = try binding()
        return try ChallengeHealthReadRequest(
            binding: binding, deviceRequestID: F.id(3),
            queryWindow: F.window(start: -2_800_000, end: 1_000), purpose: .readinessHistory
        )
    }

    private func accepted() throws -> (ChallengeHealthSnapshot, ChallengeHealthEvaluation) {
        let request = try read()
        let snapshot = try F.snapshot([
            F.record(source: "com.apple.health", productType: "Watch7,1")
        ], request: request, observed: 2_000, freshness: 2_000)
        let evaluation = ChallengeHealthAppleWatchStepsAdapter().evaluate(snapshot)
        #expect(evaluation.readiness == .ready && evaluation.permitsRealConsent)
        return (snapshot, evaluation)
    }

    private func workoutBinding(metric: ChallengeHealthMetric,
                                policy: ChallengeHealthRealSourcePolicy,
                                distance: Int64? = nil) throws -> ChallengeHealthBinding {
        try ChallengeHealthBinding(actorID: F.id(1), challengeID: F.id(2), agreementVersion: 1,
          termsDigest: String(repeating: "a", count: 64), metric: metric,
          challengeWindow: F.window(start: 1_000, end: 2_000), realSourcePolicy: policy,
          selectedDistanceMillimeters: distance)
    }

    private func outdoorRun(_ id: Int = 10, start: Double = -200, end: Double = -100,
                            distance: Double = 100) -> WeeklySourceRecord {
        WeeklySourceRecord(id: F.id(id), metric: .runningDistanceMillimeters,
          start: F.date(start), end: F.date(end), value: distance,
          sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1",
          wasUserEntered: false, workoutActivityType: "running", wasIndoorWorkout: false)
    }

    @Test("the exact body has only the five readiness receipt fields")
    func canonicalMinimalBody() throws {
        let (snapshot, evaluation) = try accepted()
        let request = try ChallengeHealthReadinessRequest(
            binding: try binding(), snapshot: snapshot, evaluation: evaluation, requestID: F.id(4)
        )
        let body = try JSONSerialization.jsonObject(with: request.exactBytes) as! [String: Any]
        #expect(Set(body.keys) == Set([
            "contract_version", "actor_id", "source_policy_version", "observed_at", "request_id"
        ]))
        #expect(body["source_policy_version"] as? String == "apple_watch_steps_v1")
        #expect(try ChallengeHealthReadinessRequest(restoring: request.exactBytes) == request)
    }

    @Test("short history and synthetic readiness cannot construct a receipt request")
    func rejectsUnacceptedReadiness() throws {
        let binding = try binding()
        let short = try ChallengeHealthReadRequest(
            binding: binding, deviceRequestID: F.id(3), queryWindow: F.window(), purpose: .readinessHistory
        )
        let snapshot = try F.snapshot([
            F.record(source: "com.apple.health", productType: "Watch7,1")
        ], request: short)
        let evaluation = ChallengeHealthAppleWatchStepsAdapter().evaluate(snapshot)
        #expect(evaluation.readiness != .ready)
        #expect(throws: ChallengeHealthReadinessRequestError.invalidRequest) {
            try ChallengeHealthReadinessRequest(binding: binding, snapshot: snapshot,
                                                evaluation: evaluation, requestID: F.id(4))
        }
    }

    @Test("a readiness window ending at the observation can precede the challenge")
    func acceptsObservationBoundHistory() throws {
        let binding = try ChallengeHealthBinding(
            actorID: F.id(1), challengeID: F.id(2), agreementVersion: 1,
            termsDigest: String(repeating: "a", count: 64), metric: .steps,
            challengeWindow: F.window(start: 10_000, end: 11_000),
            realSourcePolicy: .appleWatchAutomaticStepsV1
        )
        let request = try ChallengeHealthReadRequest(
            binding: binding, deviceRequestID: F.id(3),
            queryWindow: F.window(start: -2_600_000, end: 5_000), purpose: .readinessHistory
        )
        let snapshot = try F.snapshot([
            F.record(source: "com.apple.health", productType: "Watch7,1")
        ], request: request, observed: 5_000, freshness: 5_000)
        let evaluation = ChallengeHealthAppleWatchStepsAdapter().evaluate(snapshot)
        #expect(evaluation.readiness == .ready)
        #expect(try ChallengeHealthReadinessRequest(
            binding: binding, snapshot: snapshot, evaluation: evaluation, requestID: F.id(4)
        ).actorID == binding.actorID)
    }

    @Test("signed exact bytes survive restoration and receipt acknowledgement")
    func journalRecovery() throws {
        let (snapshot, evaluation) = try accepted()
        let request = try ChallengeHealthReadinessRequest(
            binding: try binding(), snapshot: snapshot, evaluation: evaluation, requestID: F.id(4)
        )
        let signed = try ChallengeHealthSignedReadinessRequest(
            request: request, keyID: Data(repeating: 1, count: 32).base64EncodedString(),
            assertion: Data([1]), environment: "development"
        )
        var journal = ChallengeHealthReadinessJournal(actorID: request.actorID)
        try journal.enqueue(signed)
        let restored = try ChallengeHealthReadinessJournal(restoring: journal.encoded(), actorID: request.actorID)
        #expect(restored.pending == [signed])
        let receipt = try JSONSerialization.data(withJSONObject: [
            "version": "challenge_real_health_readiness_receipt_v1",
            "request_id": request.requestID.uuidString.lowercased(),
            "accepted_at": "2026-09-20T00:00:00Z"
        ])
        journal = restored
        try journal.acknowledge(request, receipt: receipt)
        #expect(journal.pending.isEmpty)
    }

    @Test("private-account readiness keeps the exact request and receipt recovery")
    func privateAccountJournalRecovery() throws {
        let (snapshot, evaluation) = try accepted()
        let request = try ChallengeHealthReadinessRequest(
            binding: try binding(), snapshot: snapshot, evaluation: evaluation, requestID: F.id(4)
        )
        let privateRequest = try ChallengeHealthSignedReadinessRequest(privateAccountRequest: request)
        #expect(privateRequest.isPrivateAccount)
        #expect(privateRequest.keyID.isEmpty && privateRequest.assertion.isEmpty)
        var journal = ChallengeHealthReadinessJournal(actorID: request.actorID)
        try journal.enqueue(privateRequest)
        let restored = try ChallengeHealthReadinessJournal(restoring: journal.encoded(), actorID: request.actorID)
        #expect(restored.pending == [privateRequest])
        #expect(restored.pending[0].exactBody == request.exactBytes)
        let receipt = try JSONSerialization.data(withJSONObject: [
            "version": "challenge_real_health_readiness_receipt_v1",
            "request_id": request.requestID.uuidString.lowercased(),
            "accepted_at": "2026-09-20T00:00:00Z"
        ])
        journal = restored
        try journal.acknowledge(request, receipt: receipt)
        #expect(journal.pending.isEmpty)
    }

    @Test("cumulative outdoor-running readiness keeps the five-field receipt shape")
    func cumulativeRunningCanonicalBody() throws {
        let binding = try workoutBinding(metric: .runningMillimeters,
          policy: .appleWorkoutOutdoorDistanceV1)
        let read = try ChallengeHealthReadRequest(binding: binding, deviceRequestID: F.id(3),
          queryWindow: F.window(start: -30 * 86_400 - 10_000, end: 1_000), purpose: .readinessHistory)
        let snapshot = try F.snapshot([outdoorRun()], request: read, observed: 1_000, freshness: 1_000)
        let evaluation = ChallengeHealthAppleWorkoutDistanceAdapter().evaluate(snapshot)
        #expect(evaluation.readiness == .ready && evaluation.permitsRealConsent)
        let request = try ChallengeHealthReadinessRequest(binding: binding, snapshot: snapshot,
          evaluation: evaluation, requestID: F.id(4))
        let body = try JSONSerialization.jsonObject(with: request.exactBytes) as! [String: Any]
        #expect(Set(body.keys) == Set([
          "contract_version", "actor_id", "source_policy_version", "observed_at", "request_id"
        ]))
        #expect(body["source_policy_version"] as? String == "apple_workout_outdoor_distance_v1")
    }

    @Test("timed outdoor-running readiness binds the selected distance in canonical six bytes")
    func timedRunningCanonicalBodyAndNinetyDays() throws {
        let binding = try workoutBinding(metric: .timedRunElapsedSeconds,
          policy: .appleWorkoutOutdoorTimedV1, distance: 100)
        let read = try ChallengeHealthReadRequest(binding: binding, deviceRequestID: F.id(3),
          queryWindow: F.window(start: -90 * 86_400 - 10_000, end: 1_000), purpose: .readinessHistory)
        let snapshot = try F.snapshot([outdoorRun()], request: read, observed: 1_000, freshness: 1_000)
        let evaluation = ChallengeHealthAppleWorkoutTimedAdapter().evaluate(snapshot)
        #expect(evaluation.readiness == .ready && evaluation.permitsRealConsent)
        let request = try ChallengeHealthReadinessRequest(binding: binding, snapshot: snapshot,
          evaluation: evaluation, requestID: F.id(4))
        let body = try JSONSerialization.jsonObject(with: request.exactBytes) as! [String: Any]
        #expect(Set(body.keys) == Set([
          "contract_version", "actor_id", "source_policy_version", "observed_at", "request_id", "distance_mm"
        ]))
        #expect(body["source_policy_version"] as? String == "apple_workout_outdoor_timed_v1")
        #expect(body["distance_mm"] as? Int == 100)
        #expect(try ChallengeHealthReadinessRequest(restoring: request.exactBytes) == request)
    }
}
