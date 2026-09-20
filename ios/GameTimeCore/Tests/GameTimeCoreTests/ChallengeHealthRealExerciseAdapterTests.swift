import Foundation
import Testing
@testable import GameTimeCore

@Suite("Challenge Health unavailable Apple Watch Exercise adapter")
struct ChallengeHealthRealExerciseAdapterTests {
    typealias F = ChallengeHealthFixtures

    private func binding() throws -> ChallengeHealthBinding {
        try ChallengeHealthBinding(actorID: F.id(1), challengeID: F.id(2), agreementVersion: 1,
            termsDigest: String(repeating: "a", count: 64), metric: .exerciseSeconds,
            challengeWindow: F.window(start: 1_000, end: 2_000), realSourcePolicy: .appleWatchExerciseV1)
    }
    private func request() throws -> ChallengeHealthReadRequest {
        try ChallengeHealthReadRequest(binding: binding(), deviceRequestID: F.id(3),
            queryWindow: F.window(start: -2_800_000, end: 1_000), purpose: .readinessHistory)
    }

    @Test("source, seconds normalization, and reconciliation never enable Exercise")
    func remainsUnavailable() throws {
        let adapter = ChallengeHealthAppleWatchExerciseAdapter()
        let result = adapter.evaluate(try F.snapshot([
            F.record(metric: .appleExerciseMinutes, value: 61.9, source: "com.apple.health", productType: "Watch7,1"),
            F.record(11, metric: .appleExerciseMinutes, start: 100, end: 160, value: 2.1,
                     source: "com.apple.health.two", productType: "Watch8,1")
        ], request: request()))
        #expect(result.readiness == .unsupported)
        #expect(result.activity == nil)
        #expect(result.issues.contains(.exerciseCausalLineageUnavailable))
        #expect(!result.acceptsRealSourceObservation && !result.permitsRealConsent && !result.permitsRealIngestion)
        #expect(result.realReplacementDecision == .unresolved(.requeryRequired))
    }

    @Test("unknown source and point samples stay fail closed")
    func rejectsUnresolvedInputs() throws {
        let result = ChallengeHealthAppleWatchExerciseAdapter().evaluate(try F.snapshot([
            F.record(metric: .appleExerciseMinutes, start: 100, end: 100, value: 1,
                     source: nil, productType: nil)
        ], request: request()))
        #expect(result.readiness == .unsupported)
        #expect(result.issues.contains(.realSourceProvenanceUnavailable))
        #expect(result.issues.contains(.reconciliationUnresolved))
    }
}
