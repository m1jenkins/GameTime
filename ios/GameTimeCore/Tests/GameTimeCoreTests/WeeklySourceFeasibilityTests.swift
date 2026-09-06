import Foundation
import Testing

@testable import GameTimeCore

@Suite("Weekly source feasibility stays diagnostic")
struct WeeklySourceFeasibilityTests {
    let actor = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    func record(
        id: UUID = UUID(), metric: WeeklySourceMetric = .steps,
        value: Double = 100, manual: Bool? = false,
        sync: String? = nil, offset: Double = 0
    ) -> WeeklySourceRecord {
        WeeklySourceRecord(
            id: id, metric: metric, start: start.addingTimeInterval(offset),
            end: start.addingTimeInterval(offset + 60), value: value,
            sourceBundleIdentifier: "com.apple.health.fixture", sourceVersion: "fictional",
            deviceManufacturer: "Apple Inc.", deviceModel: "Watch fixture",
            wasUserEntered: manual, syncIdentifier: sync
        )
    }

    func capture(
        _ records: [WeeklySourceRecord] = [], state: WeeklySourceReadState = .successfulQuery,
        metric: WeeklySourceMetric = .steps, actorID: UUID? = nil, observedOffset: Double = 400
    ) -> WeeklySourceCapture {
        WeeklySourceCapture(
            accountID: actorID ?? actor, metric: metric,
            window: DateInterval(start: start, duration: 1_000),
            observedAt: start.addingTimeInterval(observedOffset), state: state, records: records
        )
    }

    @Test("empty, zero, positive and metadata-rich reads never authorize a miss or a total")
    func noTrustEscalation() throws {
        for records in [[], [record(value: 0)], [record(value: 20_000)]] {
            let result = try WeeklySourceFeasibility.assess(capture(records))
            #expect(!result.availableForQualification)
            #expect(!result.supportsConfirmedMiss)
            #expect(result.qualifyingTotal == nil)
            #expect(result.concerns.contains(.readAccessAndCompletenessUnknown))
        }
    }

    @Test("manual entries and missing marker remain distinct, even with Apple metadata")
    func manualAndUnknown() throws {
        let result = try WeeklySourceFeasibility.assess(capture([record(manual: true), record(manual: nil)]))
        #expect(result.explicitlyManualCount == 1)
        #expect(result.concerns.contains(.manualEntry))
        #expect(result.concerns.contains(.manualMarkerAbsent))
    }

    @Test("exact UUID duplicates collapse; a conflicting UUID is refused")
    func duplicateIdentity() throws {
        let first = record()
        let result = try WeeklySourceFeasibility.assess(capture([first, first]))
        #expect(result.distinctRecordCount == 1)
        #expect(result.repeatedUUIDCount == 1)
        #expect(throws: WeeklySourceFeasibilityError.conflictingRecordIdentity) {
            try WeeklySourceFeasibility.assess(capture([first, record(id: first.id, value: 2)]))
        }
    }

    @Test("overlaps and reimports cannot double-count")
    func overlappingImports() throws {
        let result = try WeeklySourceFeasibility.assess(capture([record(sync: "same"), record(sync: "same", offset: 30)]))
        #expect(result.concerns.contains(.possibleReimport))
        #expect(result.concerns.contains(.overlappingRecords))
        #expect(result.qualifyingTotal == nil)
    }

    @Test("lost visibility and late sync are uncertainty; lower refresh is not discarded")
    func lateAndDeleted() throws {
        let old = capture([record(value: 500)])
        let refreshed = capture([record(value: 100)], observedOffset: 500)
        let result = try WeeklySourceFeasibility.assess(refreshed, replacing: old)
        #expect(result.concerns.contains(.recordsNoLongerVisible))
        #expect(result.concerns.contains(.lateArrivals))
        #expect(!result.supportsConfirmedMiss)
    }

    @Test("permission/locked/offline/query failures do not become zero observations")
    func unavailableReads() throws {
        for state in [WeeklySourceReadState.failed, .unavailable, .truncated, .disabled] {
            let result = try WeeklySourceFeasibility.assess(capture(state: state))
            #expect(!result.supportsConfirmedMiss)
            #expect(result.qualifyingTotal == nil)
        }
        #expect(throws: WeeklySourceFeasibilityError.invalidCapture) {
            try WeeklySourceFeasibility.assess(capture([record()], state: .failed))
        }
    }

    @Test("accounts, frozen windows and out-of-order captures cannot mix")
    func accountIsolation() throws {
        let old = capture([record()])
        #expect(throws: WeeklySourceFeasibilityError.mismatchedAccountOrWindow) {
            try WeeklySourceFeasibility.assess(capture(actorID: UUID()), replacing: old)
        }
        #expect(throws: WeeklySourceFeasibilityError.mismatchedAccountOrWindow) {
            try WeeklySourceFeasibility.assess(capture(observedOffset: 300), replacing: old)
        }
    }

    @Test("Exercise lineage and running accuracy are unresolved independent gates")
    func distinctMetricSemantics() throws {
        let exercise = try WeeklySourceFeasibility.assess(capture([record(metric: .appleExerciseMinutes)], metric: .appleExerciseMinutes))
        #expect(exercise.concerns.contains(.exerciseLineageUnverified))
        let running = try WeeklySourceFeasibility.assess(capture([record(metric: .runningDistanceMillimeters)], metric: .runningDistanceMillimeters))
        #expect(running.concerns.contains(.runningAccuracyUnverified))
        #expect(throws: WeeklySourceFeasibilityError.invalidCapture) {
            try WeeklySourceFeasibility.assess(capture([record(metric: .appleExerciseMinutes)]))
        }
    }

    @Test("invalid numeric/time input and boundary-straddling records do not get normalized")
    func numericAndWindowBounds() throws {
        for value in [-1, .nan, .infinity] {
            #expect(throws: WeeklySourceFeasibilityError.invalidCapture) {
                try WeeklySourceFeasibility.assess(capture([record(value: value)]))
            }
        }
        let result = try WeeklySourceFeasibility.assess(capture([record(offset: -30)]))
        #expect(result.concerns.contains(.intervalCrossesWindow))
        #expect(throws: WeeklySourceFeasibilityError.invalidCapture) {
            try WeeklySourceFeasibility.assess(capture([record(offset: 500)]))
        }
    }

    @Test("instantaneous Health quantities at the opening boundary remain diagnostic")
    func instantaneousRecords() throws {
        let instant = WeeklySourceRecord(
            id: UUID(), metric: .steps, start: start, end: start, value: 1
        )
        let result = try WeeklySourceFeasibility.assess(capture([instant]))
        #expect(result.distinctRecordCount == 1)
        #expect(result.qualifyingTotal == nil)
        let closing = WeeklySourceRecord(
            id: UUID(), metric: .steps,
            start: start.addingTimeInterval(1_000), end: start.addingTimeInterval(1_000), value: 1
        )
        #expect(throws: WeeklySourceFeasibilityError.invalidCapture) {
            try WeeklySourceFeasibility.assess(capture([closing], observedOffset: 2_000))
        }
    }
}
