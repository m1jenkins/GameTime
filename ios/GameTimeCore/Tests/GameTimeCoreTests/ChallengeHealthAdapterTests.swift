import Foundation
import Testing
@testable import GameTimeCore

@Suite("Challenge Health closed adapters")
struct ChallengeHealthAdapterTests {
    typealias F = ChallengeHealthFixtures

    @Test("public adapters never convert reads, metadata or a policy identifier into acceptance")
    func realGatesRemainClosed() throws {
        let adapters: [any ChallengeHealthAdapter] = [ChallengeHealthStepsAdapter(), ChallengeHealthExerciseAdapter(),
            ChallengeHealthRunningDistanceAdapter(), ChallengeHealthTimedRunAdapter()]
        for adapter in adapters {
            for records in [[], [F.record(metric: adapter.metric.rawMetric)], [F.record(metric: adapter.metric.rawMetric, value: 0)]] {
                let result = adapter.evaluate(try F.snapshot(records, request: F.request(metric: adapter.metric)), replacing: nil)
                #expect(result.activity == nil)
                #expect(result.readiness != .ready)
                #expect(!result.permitsRealConsent && !result.permitsRealIngestion && !result.supportsConfirmedMiss)
                #expect(!result.syntheticOnly)
            }
        }
        #expect(!ChallengeHealthSourcePolicy.unaccepted.acceptsRealSources)
    }

    @Test("permission-ambiguous empty and explicit zero cannot become ready or a zero fact")
    func emptyAndZero() throws {
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(0)]))
        for records in [[], [F.record(value: 0)]] {
            let result = adapter.evaluate(try F.snapshot(records))
            #expect(result.readiness == .noEligibleDataYet)
            #expect(result.activity == nil)
        }
        #expect(ChallengeHealthStepsAdapter().evaluate(try F.snapshot()).readiness == .noEligibleDataYet)
    }

    @Test("units are explicit; Exercise fixture seconds never silently reuse diagnostic minutes")
    func fourUnits() throws {
        let steps = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(123)]))
        #expect(steps.evaluate(try F.snapshot([F.record(value: 123)])).activity?.integerValue == 123)
        let exercise = ChallengeHealthExerciseAdapter(fixture: F.policy([10: .contribution(150)]))
        let result = exercise.evaluate(try F.snapshot([F.record(metric: .appleExerciseMinutes, value: 2.5)],
            request: F.request(metric: .exerciseSeconds)))
        #expect(result.activity == (try ChallengeHealthValue(metric: .exerciseSeconds, integerValue: 150)))
        #expect(result.activity?.unit == .seconds)
        let distance = ChallengeHealthRunningDistanceAdapter(fixture: F.policy([10: .contribution(1_234_567)]))
        let distanceResult = distance.evaluate(try F.snapshot([F.record(metric: .runningDistanceMillimeters, value: 1_234_567)],
            request: F.request(metric: .runningMillimeters)))
        #expect(distanceResult.activity?.integerValue == 1_234_567)
        #expect(distanceResult.activity?.unit == .millimeters)
        #expect(steps.metric.unit == .count && ChallengeHealthMetric.timedRunElapsedSeconds.unit == .seconds)
    }

    @Test("manual, imported and missing metadata stay distinct and require explicit fixture decisions")
    func metadataDoesNotAuthorize() throws {
        let records = [F.record(10, manual: true), F.record(11, manual: nil, source: nil),
                       F.record(12, source: "synthetic.import", sync: "import-identity", syncVersion: 2)]
        let undecided = ChallengeHealthStepsAdapter(fixture: F.policy([:], reconciled: true))
            .evaluate(try F.snapshot(records))
        #expect(undecided.activity == nil && undecided.issues.contains(.normalizationUnresolved))
        #expect(undecided.diagnosticConcerns.contains(.manualEntry))
        #expect(undecided.diagnosticConcerns.contains(.manualMarkerAbsent))
        #expect(undecided.diagnosticConcerns.contains(.sourceMetadataAbsent))
        let excluded = ChallengeHealthStepsAdapter(fixture: F.policy([10: .exclude, 11: .exclude, 12: .exclude], reconciled: true))
            .evaluate(try F.snapshot(records))
        #expect(excluded.readiness == .noEligibleDataYet && excluded.activity == nil)
        #expect(records[1].wasUserEntered == nil && records[0].wasUserEntered == true)
        #expect(records[2].syncVersion == 2 && records[2].sourceBundleIdentifier == "synthetic.import")
    }

    @Test("exact UUID duplicates and out-of-order additions produce one contribution each")
    func duplicatesAndOrdering() throws {
        let a = F.record(), b = F.record(11, start: 100, end: 160, value: 50)
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(100), 11: .contribution(50)]))
        let first = adapter.evaluate(try F.snapshot([a, b]))
        #expect(first == adapter.evaluate(try F.snapshot([b, a, b, a])))
        #expect(first.activity?.integerValue == 150)
        let conflict = adapter.evaluate(try F.snapshot([a, F.record(value: 99)]))
        #expect(conflict.activity == nil && conflict.issues.contains(.invalidSnapshot))
    }

    @Test("overlap and sync reimport need an explicit synthetic resolution, never a max/version winner")
    func overlapAndSync() throws {
        let records = [F.record(sync: "same", syncVersion: 1), F.record(11, start: 30, end: 100, sync: "same", syncVersion: 2)]
        let decisions: [Int: ChallengeHealthSyntheticPolicy.Decision] = [10: .contribution(80), 11: .exclude]
        let blocked = ChallengeHealthStepsAdapter(fixture: F.policy(decisions)).evaluate(try F.snapshot(records))
        #expect(blocked.activity == nil && blocked.issues.contains(.reconciliationUnresolved))
        #expect(blocked.diagnosticConcerns.contains(.possibleReimport))
        let resolved = ChallengeHealthStepsAdapter(fixture: F.policy(decisions, reconciled: true)).evaluate(try F.snapshot(records))
        #expect(resolved.activity?.integerValue == 80 && resolved.syntheticOnly)
        #expect(!resolved.permitsRealIngestion)
    }

    @Test("limited history may show positive eligible activity without establishing full access or a miss")
    func limitedHistory() throws {
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(100)]))
        let positive = adapter.evaluate(try F.snapshot([F.record()], earliest: 5, evidence: .limitedHistory))
        #expect(positive.readiness == .ready && positive.activity?.integerValue == 100)
        #expect(positive.issues.contains(.historyLimited) && !positive.supportsConfirmedMiss)
        let empty = adapter.evaluate(try F.snapshot([], earliest: 5, evidence: .limitedHistory))
        #expect(empty.readiness == .noEligibleDataYet && empty.activity == nil)
        let unknown = adapter.evaluate(try F.snapshot([F.record()], earliest: nil))
        #expect(!unknown.supportsConfirmedMiss)
    }

    @Test("late arrivals and same-ID lower edits replace observations without a high-water mark")
    func lateAndDownward() throws {
        let old = try F.snapshot([F.record(value: 500)], observed: 900, freshness: 800)
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(100), 11: .contribution(20)]))
        let lower = adapter.evaluate(try F.snapshot([F.record(value: 100)]), replacing: old)
        #expect(lower.activity?.integerValue == 100)
        let late = adapter.evaluate(try F.snapshot([F.record(value: 100), F.record(11, start: 100, end: 160, value: 20)]), replacing: old)
        #expect(late.activity?.integerValue == 120)
        #expect(late.diagnosticConcerns.contains(.lateArrivals))
    }

    @Test("disappearing records are lost visibility; explicit tombstones and change signals require requery")
    func deletionAndVisibility() throws {
        let old = try F.snapshot([F.record()], observed: 900, freshness: 800)
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(100)]))
        let empty = adapter.evaluate(try F.snapshot(), replacing: old)
        #expect(empty.readiness == .staleOrIncomplete && empty.issues.contains(.lostVisibility))
        #expect(!empty.issues.contains(.deletionObserved) && empty.activity == nil)
        let deleted = adapter.evaluate(try F.snapshot(evidence: .explicitDeletion, deleted: [F.id(10)]), replacing: old)
        #expect(deleted.issues.contains(.deletionObserved) && !deleted.issues.contains(.lostVisibility))
        #expect(deleted.activity == nil && !deleted.supportsConfirmedMiss)
        for evidence in [ChallengeHealthEvidence.anchoredChanges, .observerInvalidation, .truncated, .unknown] {
            let result = adapter.evaluate(try F.snapshot([F.record()], evidence: evidence), replacing: old)
            #expect(result.activity == nil && result.readiness == .staleOrIncomplete)
        }
    }

    @Test("a bounded requery can carry explicit tombstones and lower a cumulative run observation")
    func requeryAfterDeletion() throws {
        let request = try F.request(metric: .runningMillimeters)
        let first = F.record(metric: .runningDistanceMillimeters, value: 1_000_000)
        let second = F.record(11, metric: .runningDistanceMillimeters, start: 100, end: 160, value: 2_000_000)
        let adapter = ChallengeHealthRunningDistanceAdapter(fixture: F.policy([10: .contribution(1_000_000), 11: .contribution(2_000_000)]))
        let old = try F.snapshot([first, second], request: request, observed: 900, freshness: 800)
        #expect(adapter.evaluate(old).activity?.integerValue == 3_000_000)
        let requery = adapter.evaluate(try F.snapshot([second], request: request,
            evidence: .boundedSnapshotAfterDeletion, deleted: [first.id]), replacing: old)
        #expect(requery.activity?.integerValue == 2_000_000 && requery.readiness == .ready)
        #expect(requery.issues.contains(.deletionObserved) && !requery.issues.contains(.lostVisibility))
        #expect(!requery.supportsConfirmedMiss && !requery.permitsRealIngestion)
        #expect(adapter.evaluate(try F.snapshot([second], request: request,
            evidence: .boundedSnapshotAfterDeletion)).issues.contains(.invalidSnapshot))
    }

    @Test("best qualifying whole run uses elapsed seconds including pauses; no pace or segment slicing")
    func timedWholeRun() throws {
        let adapter = ChallengeHealthTimedRunAdapter(fixture: F.policy([10: .qualifyingWholeTimedRun, 11: .qualifyingWholeTimedRun]))
        let records = [F.record(metric: .runningDistanceMillimeters, start: 10, end: 310, value: 5_000_000, activeDuration: 100),
                       F.record(11, metric: .runningDistanceMillimeters, start: 400, end: 650, value: 5_000_000, activeDuration: 200)]
        let result = adapter.evaluate(try F.snapshot(records, request: F.request(metric: .timedRunElapsedSeconds)))
        #expect(result.activity?.integerValue == 250)
        #expect(result.activity?.integerValue != 100)
        #expect(result.readiness == .ready && !result.permitsRealConsent)
        let noTolerance = ChallengeHealthTimedRunAdapter(fixture: F.policy([:]))
            .evaluate(try F.snapshot([records[0]], request: F.request(metric: .timedRunElapsedSeconds)))
        #expect(noTolerance.activity == nil && noTolerance.issues.contains(.normalizationUnresolved))
    }

    @Test("boundary crossing, fractional elapsed and missing/invalid distance do not get fallback rules")
    func timedAmbiguities() throws {
        let adapter = ChallengeHealthTimedRunAdapter(fixture: F.policy([10: .qualifyingWholeTimedRun]))
        let request = try F.request(metric: .timedRunElapsedSeconds)
        let crossing = adapter.evaluate(try F.snapshot([F.record(metric: .runningDistanceMillimeters, start: -1, end: 10)], request: request))
        #expect(crossing.issues.contains(.boundaryUnresolved) && crossing.activity == nil)
        for record in [F.record(metric: .runningDistanceMillimeters, end: 70.5),
                       F.record(metric: .runningDistanceMillimeters, value: 0),
                       F.record(metric: .runningDistanceMillimeters, value: .nan)] {
            #expect(adapter.evaluate(try F.snapshot([record], request: request)).activity == nil)
        }
    }

    @Test("cumulative quantity crossing stays unresolved, including an opening/closing calendar boundary")
    func quantityBoundary() throws {
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(100)]))
        #expect(adapter.evaluate(try F.snapshot([F.record(start: -10, end: 10)])).issues.contains(.boundaryUnresolved))
        #expect(adapter.evaluate(try F.snapshot([F.record(start: 999, end: 1_010)], observed: 1_100)).activity == nil)
        #expect(adapter.evaluate(try F.snapshot([F.record(start: 1_000, end: 1_000)])).issues.contains(.invalidSnapshot))
    }

    @Test("freshness and history readiness are independent of a positive challenge-window observation")
    func activityNotCompleteness() throws {
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(100)], freshThrough: 999))
        let stale = adapter.evaluate(try F.snapshot([F.record()]))
        #expect(stale.activity?.integerValue == 100 && stale.readiness == .staleOrIncomplete)
        #expect(stale.issues.contains(.freshnessUnresolved))
        let current = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(100)], freshThrough: 2_000))
        let result = current.evaluate(try F.snapshot([F.record(start: 1_010, end: 1_070)],
            request: F.request(purpose: .challengeActivity), observed: 2_000, freshness: 1_900))
        #expect(result.activity?.integerValue == 100 && result.issues.contains(.historyRequired))
        #expect(result.readiness != .ready && !result.supportsConfirmedMiss)
        #expect(current.evaluate(try F.snapshot([F.record()], freshness: nil)).readiness != .ready)
    }

    @Test("wrong metric, future/stale observations and overflowing canonical totals fail closed")
    func invalidInputs() throws {
        let adapter = ChallengeHealthStepsAdapter(fixture: F.policy([10: .contribution(Int64.max), 11: .contribution(1)]))
        let overflow = adapter.evaluate(try F.snapshot([F.record(), F.record(11, start: 100, end: 160)]))
        #expect(overflow.activity == nil && overflow.issues.contains(.normalizationUnresolved))
        #expect(adapter.evaluate(try F.snapshot([F.record(metric: .appleExerciseMinutes)])).issues.contains(.invalidSnapshot))
        #expect(adapter.evaluate(try F.snapshot(request: F.request(metric: .exerciseSeconds))).issues.contains(.metricMismatch))
        #expect(adapter.evaluate(try F.snapshot([F.record()], observed: 50)).issues.contains(.invalidSnapshot))
        #expect(adapter.evaluate(try F.snapshot([F.record()], observed: 900), replacing: try F.snapshot([F.record()])).issues.contains(.invalidSnapshot))
        #expect(adapter.evaluate(try F.snapshot([F.record()], deleted: [F.id(10)])).issues.contains(.invalidSnapshot))
    }
}
