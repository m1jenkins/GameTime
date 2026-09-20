import Foundation
import Testing
@testable import GameTimeCore

@Suite("Challenge Health real Apple Watch steps adapter")
struct ChallengeHealthRealStepsAdapterTests {
    typealias F = ChallengeHealthFixtures

    private func binding() throws -> ChallengeHealthBinding {
        try ChallengeHealthBinding(
            actorID: F.id(1),
            challengeID: F.id(2),
            agreementVersion: 1,
            termsDigest: String(repeating: "a", count: 64),
            metric: .steps,
            challengeWindow: F.window(start: 1_000, end: 2_000),
            realSourcePolicy: .appleWatchAutomaticStepsV1
        )
    }

    private func request(purpose: ChallengeHealthReadRequest.Purpose = .readinessHistory) throws -> ChallengeHealthReadRequest {
        let binding = try binding()
        return try ChallengeHealthReadRequest(
            binding: binding,
            deviceRequestID: F.id(3),
            queryWindow: purpose == .readinessHistory
                ? F.window(start: -2_800_000, end: 1_000)
                : binding.challengeWindow,
            purpose: purpose
        )
    }

    @Test("the V1 identity is separately frozen and only applies to steps")
    func policyBinding() throws {
        #expect(ChallengeHealthRealSourcePolicy.appleWatchAutomaticStepsV1.identifier == "apple_watch_steps_v1")
        #expect(try binding().realSourcePolicy == .appleWatchAutomaticStepsV1)
        #expect(throws: ChallengeHealthContractError.invalidAgreement) {
            try ChallengeHealthBinding(
                actorID: F.id(1), challengeID: F.id(2), agreementVersion: 1,
                termsDigest: String(repeating: "a", count: 64), metric: .exerciseSeconds,
                challengeWindow: F.window(), realSourcePolicy: .appleWatchAutomaticStepsV1
            )
        }
    }

    @Test("unbound historical reads remain closed and empty reads do not claim a zero")
    func historicalAndEmptyReadsStayClosed() throws {
        let adapter = ChallengeHealthAppleWatchStepsAdapter()
        let historical = adapter.evaluate(try F.snapshot([F.record()]))
        #expect(historical.issues.contains(.realSourcePolicyMismatch))
        #expect(historical.activity == nil && historical.readiness == .staleOrIncomplete)

        let empty = adapter.evaluate(try F.snapshot([], request: request()))
        #expect(empty.activity == nil && empty.readiness == .noEligibleDataYet)
        #expect(!empty.permitsRealConsent && !empty.permitsRealIngestion && !empty.supportsConfirmedMiss)
    }

    @Test("the source revision tuple admits Watch steps and floors the aggregate")
    func sourceProvenanceFailsClosed() throws {
        let adapter = ChallengeHealthAppleWatchStepsAdapter()
        let tuple = adapter.evaluate(try F.snapshot([
            F.record(value: 3.9, manual: nil, source: "com.apple.health.device-a", productType: "Watch7,1"),
            F.record(11, start: 100, end: 160, value: 2.9, manual: false,
                source: "com.apple.health.device-b", productType: "Watch7,1")
        ], request: request()))
        #expect(tuple.activity?.integerValue == 6)
        #expect(tuple.readiness == .ready)

        let manual = adapter.evaluate(try F.snapshot([F.record(manual: true)], request: request()))
        #expect(manual.issues.contains(.sourceExplicitlyRejected))
        #expect(manual.activity == nil && manual.readiness == .noEligibleDataYet)

        for marker in [Bool?.none, Bool?.some(false)] {
            let result = adapter.evaluate(try F.snapshot([
                F.record(manual: marker, source: "com.apple.example", productType: "Watch7,1")
            ], request: request()))
            #expect(result.issues.contains(.sourceExplicitlyRejected))
            #expect(result.activity == nil && result.readiness == .noEligibleDataYet)
        }
        let phone = adapter.evaluate(try F.snapshot([
            F.record(manual: false, source: "com.apple.health", productType: "iPhone17,1")
        ], request: request()))
        #expect(phone.issues.contains(.sourceExplicitlyRejected))

        let unknown = adapter.evaluate(try F.snapshot([
            F.record(manual: false, source: nil, productType: nil)
        ], request: request()))
        #expect(unknown.issues.contains(.realSourceProvenanceUnavailable))
        #expect(unknown.readiness == .staleOrIncomplete)

        let mixed = adapter.evaluate(try F.snapshot([
            F.record(manual: true),
            F.record(11, start: 100, end: 160, value: 20, manual: false,
                source: "com.apple.health", productType: "Watch7,1")
        ], request: request()))
        #expect(mixed.activity?.integerValue == 20)
        #expect(mixed.readiness == .ready)
    }

    @Test("duplicate identities validate before collapsing and visibility loss remains unresolved")
    func replacementsFailClosed() throws {
        let adapter = ChallengeHealthAppleWatchStepsAdapter()
        let query = try request()
        let record = F.record(source: "com.apple.health", productType: "Watch7,1")
        let duplicate = adapter.evaluate(try F.snapshot([record, record], request: query))
        #expect(duplicate.activity?.integerValue == 100)

        let conflict = adapter.evaluate(try F.snapshot([record, F.record(value: 99)], request: query))
        #expect(conflict.issues.contains(.invalidSnapshot))

        let prior = try F.snapshot([record], request: query, observed: 900, freshness: 800)
        let disappeared = adapter.evaluate(try F.snapshot([], request: query), replacing: prior)
        #expect(disappeared.issues.contains(.lostVisibility))
        #expect(disappeared.activity == nil && disappeared.readiness == .staleOrIncomplete)

        let deleted = adapter.evaluate(try F.snapshot(
            [], request: query, evidence: .boundedSnapshotAfterDeletion, deleted: [record.id]
        ), replacing: prior)
        #expect(deleted.issues.contains(.deletionObserved))
        #expect(!deleted.issues.contains(.lostVisibility))
    }

    @Test("lost visibility creates an explicit unresolved replacement instead of retaining the old score")
    func lostActivityReplacesPositiveUpload() throws {
        let query = try request(purpose: .challengeActivity)
        let record = F.record(start: 1_100, end: 1_200, source: "com.apple.health", productType: "Watch7,1")
        let prior = try F.snapshot([record], request: query, observed: 1_500, freshness: 1_500)
        let missing = try F.snapshot([], request: query, observed: 1_600, freshness: 1_600)
        let replacement = ChallengeHealthAppleWatchStepsAdapter().evaluate(missing, replacing: prior)
            .realReplacementDecision.normalizedReplacement
        #expect(replacement == .unresolved(.lostVisibility))
        let upload = try ChallengeHealthUploadRequest(binding: query.binding, requestID: F.id(90), revision: 2,
            previousRevision: 1, replacement: replacement, observedAtMicroseconds: (F.epoch + 1_600) * 1_000_000,
            queriedThroughMicroseconds: (F.epoch + 1_600) * 1_000_000)
        let json = try #require(JSONSerialization.jsonObject(with: upload.exactBytes) as? [String: Any])
        #expect(json["state"] as? String == "unresolved")
        #expect(json["value"] is NSNull)
    }

    @Test("a source-controlled higher sync revision supersedes without double count")
    func syncRevision() throws {
        let adapter = ChallengeHealthAppleWatchStepsAdapter()
        let query = try request()
        let first = F.record(value: 20, source: "com.apple.health", productType: "Watch7,1", sync: "revision", syncVersion: 1)
        let corrected = F.record(11, value: 12, source: "com.apple.health", productType: "Watch7,1", sync: "revision", syncVersion: 2)
        let result = adapter.evaluate(try F.snapshot([first, corrected], request: query))
        #expect(result.activity?.integerValue == 12)

        let conflict = adapter.evaluate(try F.snapshot([
            first,
            F.record(11, value: 12, source: "com.apple.health", productType: "Watch7,1", sync: "revision", syncVersion: 1)
        ], request: query))
        #expect(conflict.activity == nil && conflict.issues.contains(.reconciliationUnresolved))
    }

    @Test("exact challenge activity emits an accepted source observation without a history requirement")
    func challengeActivityDoesNotNeedHistory() throws {
        let adapter = ChallengeHealthAppleWatchStepsAdapter()
        let query = try request(purpose: .challengeActivity)
        let result = adapter.evaluate(try F.snapshot([
            F.record(start: 1_100, end: 1_160, value: 42,
                source: "com.apple.health", productType: "Watch7,1")
        ], request: query, observed: 2_000, freshness: 2_000))
        #expect(result.activity?.integerValue == 42)
        #expect(!result.issues.contains(.historyRequired))
        #expect(result.acceptsRealSourceObservation && result.permitsRealIngestion)
        #expect(!result.permitsRealConsent && !result.supportsConfirmedMiss)
        #expect(result.realReplacementDecision == .uploadable(
            .value(try ChallengeHealthValue(metric: .steps, integerValue: 42))
        ))
    }

    @Test("overlap and a crossing Watch record remain unresolved without slicing")
    func watchOverlapAndBoundary() throws {
        let adapter = ChallengeHealthAppleWatchStepsAdapter()
        let query = try request()
        let first = F.record(source: "com.apple.health.one", productType: "Watch7,1")
        let overlap = F.record(11, start: 50, end: 100, source: "com.apple.health.two", productType: "Watch8,1")
        let overlapping = adapter.evaluate(try F.snapshot([first, overlap], request: query))
        #expect(overlapping.activity == nil && overlapping.issues.contains(.reconciliationUnresolved))

        let crossing = adapter.evaluate(try F.snapshot([
            F.record(start: -2_800_001, end: -2_799_990,
                source: "com.apple.health", productType: "Watch7,1")
        ], request: query))
        #expect(crossing.activity == nil && crossing.issues.contains(.boundaryUnresolved))
    }

    @Test("positive point quantities from multiple Watches stay unresolved")
    func zeroDurationPointsAreNotAggregated() throws {
        let adapter = ChallengeHealthAppleWatchStepsAdapter()
        let query = try request()
        let result = adapter.evaluate(try F.snapshot([
            F.record(10, start: 100, end: 100, value: 10,
                source: "com.apple.health.one", productType: "Watch7,1"),
            F.record(11, start: 100, end: 100, value: 12,
                source: "com.apple.health.two", productType: "Watch8,1")
        ], request: query))
        #expect(result.activity == nil)
        #expect(result.issues.contains(.reconciliationUnresolved))
    }

    @Test("a future-ended readiness window is limited at its actual observation")
    func futureReadinessEndCannotClaimHistory() throws {
        let adapter = ChallengeHealthAppleWatchStepsAdapter()
        let query = try ChallengeHealthReadRequest(
            binding: try binding(), deviceRequestID: F.id(3),
            queryWindow: F.window(start: -2_800_000, end: 1_000), purpose: .readinessHistory
        )
        let result = adapter.evaluate(try F.snapshot([
            F.record(source: "com.apple.health", productType: "Watch7,1")
        ], request: query, observed: 500, freshness: 500))
        #expect(result.activity == nil)
        #expect(result.issues.contains(.historyLimited))
        #expect(result.readiness != .ready)
    }
}
