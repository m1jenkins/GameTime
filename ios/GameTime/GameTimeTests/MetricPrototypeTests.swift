import XCTest
@testable import GameTime

@MainActor final class MetricPrototypeTests: XCTestCase {
    private let actor = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let created = try! DuelInstant("2026-09-06T05:00:00.000001Z")
    private func draft(_ format: MetricPrototypeFormat = .cumulativeDistance, target: Int = 1_600_000) throws -> MetricPrototypeDraft {
        .init(format: format, target: target,
            startsAt: try DuelInstant("2026-09-07T05:00:00.000000Z"),
            endsAt: try DuelInstant("2026-09-08T05:00:00.000000Z"), timezone: "America/Chicago",
            elapsedTargetMicroseconds: format == .timedDistance ? 600_000_000 : nil,
            comparator: format == .timedDistance ? .strictlyUnder : nil)
    }
    private func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private func observed(_ terms: MetricPrototypeDraft, value: Int) -> MetricPrototypeProofDraft {
        .init(state: .observed, value: value, startsAt: terms.startsAt,
            endsAt: DuelInstant(date: terms.startsAt.date.addingTimeInterval(600)))
    }

    func testDistanceAndTimeConversionNeverRoundsTrackToMile() throws {
        XCTAssertEqual(try MetricPrototypeUnits.millimeters("1600", unit: .meters), 1_600_000)
        XCTAssertEqual(try MetricPrototypeUnits.millimeters("1", unit: .miles), 1_609_344)
        XCTAssertEqual(try MetricPrototypeUnits.millimeters("1.609344", unit: .kilometers), 1_609_344)
        XCTAssertEqual(try MetricPrototypeUnits.microseconds("600.000001"), 600_000_001)
        for text in ["NaN", "-1", "1e3", "0.0001", "1,6", " 10"] {
            XCTAssertThrowsError(try MetricPrototypeUnits.millimeters(text, unit: .meters))
        }
        XCTAssertThrowsError(try MetricPrototypeUnits.millimeters("0", unit: .meters))
        XCTAssertEqual(try MetricPrototypeUnits.millimeters("0.0", unit: .meters, allowZero: true), 0)
    }

    func testDefaultOffAndExplicitConsentRequired() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let disabled = MetricPrototypeStore(directory: root, now: { self.created.date }); disabled.setActor(actor)
        XCTAssertThrowsError(try disabled.create(draft: draft(), consent: true, requestID: UUID())) { XCTAssertEqual($0 as? MetricPrototypeError, .unavailable) }
        let enabled = MetricPrototypeStore(enabled: true, directory: root, now: { self.created.date }); enabled.setActor(actor)
        XCTAssertThrowsError(try enabled.create(draft: draft(), consent: false, requestID: UUID())) { XCTAssertEqual($0 as? MetricPrototypeError, .consentRequired) }
        XCTAssertTrue(enabled.agreements.isEmpty)
    }

    func testDurableExactReplaySurvivesGateOffAndCutoff() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let request = UUID(), terms = try draft()
        let store = MetricPrototypeStore(enabled: true, directory: root, now: { self.created.date }); store.setActor(actor)
        let id = try store.create(draft: terms, consent: true, requestID: request)
        let saved = try XCTUnwrap(store.agreements.first)
        let reopened = MetricPrototypeStore(enabled: false, directory: root, now: { terms.endsAt.date.addingTimeInterval(7 * 86_400) }); reopened.setActor(actor)
        XCTAssertEqual(try reopened.create(draft: terms, consent: true, requestID: request), id)
        XCTAssertEqual(reopened.agreements, [saved])
        XCTAssertThrowsError(try reopened.create(draft: draft(target: 1_609_344), consent: true, requestID: request)) { XCTAssertEqual($0 as? MetricPrototypeError, .requestConflict) }
        XCTAssertThrowsError(try reopened.create(draft: terms, consent: true, requestID: UUID()))
        try reopened.exit(agreementID: id, requestID: UUID())
        XCTAssertNotNil(reopened.agreements.first?.exitedAt)
        XCTAssertEqual(reopened.agreements.first?.qualification, "unresolved_not_evaluated")
        XCTAssertEqual(reopened.agreements.first?.final, false)
    }

    func testDownwardRevisionsMissingAndExactCutoffNeverCreateResult() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        var clock = created.date
        let store = MetricPrototypeStore(enabled: true, directory: root, now: { clock }); store.setActor(actor)
        let terms = try draft(), id = try store.create(draft: terms, consent: true, requestID: UUID())
        clock = terms.endsAt.date
        let firstID = UUID(), first = observed(terms, value: 9_000_000)
        try store.appendProof(agreementID: id, draft: first, requestID: firstID)
        clock = clock.addingTimeInterval(1)
        try store.appendProof(agreementID: id, draft: observed(terms, value: 0), requestID: UUID())
        let cutoff = try XCTUnwrap(store.agreements.first?.terms.correctionsCloseAt)
        // Date's precision is sufficient at this epoch to represent this microsecond.
        clock = Date(timeIntervalSince1970: Double(cutoff.microseconds - 1) / 1_000_000)
        try store.appendProof(agreementID: id, draft: .init(state: .missing, value: nil, startsAt: nil, endsAt: nil), requestID: UUID())
        clock = cutoff.date
        XCTAssertThrowsError(try store.appendProof(agreementID: id, draft: first, requestID: UUID())) { XCTAssertEqual($0 as? MetricPrototypeError, .closed) }
        try store.appendProof(agreementID: id, draft: first, requestID: firstID)
        XCTAssertEqual(store.agreements[0].proofs.map(\.revision), [1, 2, 3])
        XCTAssertEqual(store.agreements[0].proofs[1].draft.value, 0)
        XCTAssertEqual(store.agreements[0].qualification, "unresolved_not_evaluated")
        XCTAssertFalse(store.agreements[0].final)
    }

    func testTimedProofUsesEntireElapsedWindowAndCannotFinishAtClose() throws {
        let terms = try MetricPrototypeTerms(actorID: actor, agreementID: UUID(), draft: draft(.timedDistance), createdAt: created)
        let atEnd = MetricPrototypeProofDraft(state: .observed, value: terms.draft.target, startsAt: terms.draft.startsAt, endsAt: terms.draft.endsAt)
        XCTAssertThrowsError(try atEnd.validate(for: terms, recordedAt: terms.draft.endsAt))
        try observed(terms.draft, value: terms.draft.target).validate(for: terms, recordedAt: terms.draft.endsAt)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: terms.evaluatorTermsData()) as? [String: Any])
        XCTAssertEqual(json["timing_basis"] as? String, "full_elapsed_including_pauses")
        XCTAssertEqual(json["segment_policy"] as? String, "whole_run_only")
        XCTAssertEqual(json["comparator"] as? String, "lt")
        XCTAssertEqual(json["short_tolerance_millimeters"] as? Int, 0)
        XCTAssertNil(json["moving_time"])
    }

    func testAccountSwitchDeletionAndCleanupWithGateOff() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = MetricPrototypeStore(enabled: true, directory: root, now: { self.created.date }); store.setActor(actor)
        let id = try store.create(draft: draft(), consent: true, requestID: UUID())
        let other = UUID(); store.setActor(other)
        XCTAssertTrue(store.agreements.isEmpty)
        XCTAssertThrowsError(try store.exit(agreementID: id, requestID: UUID()))
        store.setActor(nil); XCTAssertTrue(store.agreements.isEmpty)
        // Cleanup can run after signout or in Release without loading the file.
        try store.deleteLocalAccount(actor)
        store.setActor(actor); XCTAssertTrue(store.agreements.isEmpty)
        XCTAssertThrowsError(try store.create(draft: draft(), consent: true, requestID: UUID()))
        let reopened = MetricPrototypeStore(directory: root); reopened.setActor(actor)
        XCTAssertTrue(reopened.agreements.isEmpty)
    }

    func testExitFreezesProofsButRecoversSavedRequest() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        var clock = created.date
        let store = MetricPrototypeStore(enabled: true, directory: root, now: { clock }); store.setActor(actor)
        let terms = try draft(), id = try store.create(draft: terms, consent: true, requestID: UUID())
        clock = terms.endsAt.date
        let request = UUID(), proof = observed(terms, value: 1)
        try store.appendProof(agreementID: id, draft: proof, requestID: request)
        try store.exit(agreementID: id, requestID: UUID())
        try store.appendProof(agreementID: id, draft: proof, requestID: request)
        XCTAssertEqual(store.agreements[0].proofs.count, 1)
        XCTAssertThrowsError(try store.appendProof(agreementID: id, draft: proof, requestID: UUID()))
    }

    func testCorruptAndCrossActorDiskDataFailClosed() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = MetricPrototypeStore(enabled: true, directory: root, now: { self.created.date }); store.setActor(actor)
        _ = try store.create(draft: draft(), consent: true, requestID: UUID())
        let actorFile = root.appendingPathComponent("\(actor.uuidString.lowercased()).json")
        let foreign = UUID()
        try FileManager.default.copyItem(at: actorFile, to: root.appendingPathComponent("\(foreign.uuidString.lowercased()).json"))
        store.setActor(foreign); XCTAssertTrue(store.agreements.isEmpty); XCTAssertNotNil(store.errorMessage)
        try Data("{}".utf8).write(to: actorFile)
        store.setActor(actor); XCTAssertTrue(store.agreements.isEmpty); XCTAssertNotNil(store.errorMessage)
        XCTAssertThrowsError(try store.create(draft: draft(), consent: true, requestID: UUID()))
    }

    func testExerciseContractHasSevenActualLocalDatesAcrossDSTAndOwnUnit() throws {
        let value = MetricPrototypeDraft(format: .exerciseMinutes, target: 30_000,
            startsAt: try DuelInstant("2026-03-02T06:00:00Z"), endsAt: try DuelInstant("2026-03-09T05:00:00Z"),
            timezone: "America/Chicago", elapsedTargetMicroseconds: nil, comparator: nil)
        let terms = try MetricPrototypeTerms(actorID: actor, agreementID: UUID(), draft: value,
            createdAt: DuelInstant("2026-03-01T00:00:00Z"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: terms.evaluatorTermsData()) as? [String: Any])
        XCTAssertEqual(json["source"] as? String, "fixture_apple_exercise_minutes_v1")
        XCTAssertEqual(json["unit"] as? String, "milliminutes")
        XCTAssertEqual((json["day_boundaries"] as? [String])?.count, 8)
        XCTAssertEqual(value.endsAt.microseconds - value.startsAt.microseconds, 167 * 3_600_000_000)
    }

    func testConsentAndProofBindingRejectChangedFrozenTerms() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = MetricPrototypeStore(enabled: true, directory: root, now: { self.created.date }); store.setActor(actor)
        _ = try store.create(draft: draft(), consent: true, requestID: UUID())
        let saved = store.agreements[0]
        let changed = try MetricPrototypeTerms(actorID: actor, agreementID: saved.id, draft: draft(target: 1_609_344), createdAt: created)
        let invalid = MetricPrototypeAgreement(terms: changed, consentBinding: saved.consentBinding, consentAt: created, proofs: [], exitedAt: nil)
        XCTAssertThrowsError(try invalid.validate(for: actor))
        XCTAssertNotEqual(try changed.binding, saved.consentBinding)
    }

    func testEqualRevisionTimestampRejectedAndReadablePrecisionPreserved() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        var clock = created.date
        let store = MetricPrototypeStore(enabled: true, directory: root, now: { clock }); store.setActor(actor)
        let terms = try draft(), id = try store.create(draft: terms, consent: true, requestID: UUID())
        clock = terms.endsAt.date
        try store.appendProof(agreementID: id, draft: observed(terms, value: 2), requestID: UUID())
        XCTAssertThrowsError(try store.appendProof(agreementID: id, draft: observed(terms, value: 1), requestID: UUID())) { XCTAssertEqual($0 as? MetricPrototypeError, .invalidProof) }
        XCTAssertEqual(MetricPrototypeDisplay.value(1_609_344, format: .timedDistance), "1609.344 meters")
        XCTAssertEqual(MetricPrototypeDisplay.seconds(600_000_001), "600.000001")
    }

    func testFullRequestCapacityStillAllowsFirstExitWithGateOff() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let store = MetricPrototypeStore(enabled: true, directory: root, now: { self.created.date }); store.setActor(actor)
        let first = try store.create(draft: draft(), consent: true, requestID: UUID())
        let remaining = try store.create(draft: draft(), consent: true, requestID: UUID())
        for _ in 0..<1_022 { try store.exit(agreementID: first, requestID: UUID()) }
        XCTAssertThrowsError(try store.create(draft: draft(), consent: true, requestID: UUID())) { XCTAssertEqual($0 as? MetricPrototypeError, .capacity) }
        let gateOff = MetricPrototypeStore(directory: root, now: { self.created.date }); gateOff.setActor(actor)
        let request = UUID()
        try gateOff.exit(agreementID: remaining, requestID: request)
        try gateOff.exit(agreementID: remaining, requestID: request)
        XCTAssertTrue(gateOff.agreements.allSatisfy { $0.exitedAt != nil })
    }

    func testExportActualNativeTermsForTypeScriptBridge() throws {
        let cumulative = try draft()
        let strict = try draft(.timedDistance, target: 1_609_344)
        let inclusive = MetricPrototypeDraft(format: .timedDistance, target: strict.target,
            startsAt: strict.startsAt, endsAt: strict.endsAt, timezone: strict.timezone,
            elapsedTargetMicroseconds: strict.elapsedTargetMicroseconds, comparator: .atMost)
        let exercise = MetricPrototypeDraft(format: .exerciseMinutes, target: 30_000,
            startsAt: try DuelInstant("2026-03-02T06:00:00Z"), endsAt: try DuelInstant("2026-03-09T05:00:00Z"),
            timezone: "America/Chicago", elapsedTargetMicroseconds: nil, comparator: nil)
        let cases: [[String: String]] = try [cumulative, strict, inclusive, exercise].map { draft in
            let accepted = draft.format == .exerciseMinutes ? try DuelInstant("2026-03-01T00:00:00Z") : created
            let terms = try MetricPrototypeTerms(actorID: actor, agreementID: UUID(), draft: draft, createdAt: accepted)
            return ["terms_json": String(decoding: try terms.evaluatorTermsData(), as: UTF8.self),
                "accepted_at": MetricPrototypeTerms.utc(accepted.microseconds),
                "now": MetricPrototypeTerms.utc(terms.correctionsCloseAt.microseconds + 1)]
        }
        let data = try JSONSerialization.data(withJSONObject: ["kind": "metric-native-bridge-v1", "cases": cases], options: [.sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "metric-native-bridge.json"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(cases.count, 4)
    }

    func testBackwardPhoneClockCannotBlockSafeExit() throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        var clock = created.date
        let store = MetricPrototypeStore(enabled: true, directory: root, now: { clock }); store.setActor(actor)
        let terms = try draft(), id = try store.create(draft: terms, consent: true, requestID: UUID())
        clock = terms.endsAt.date
        try store.appendProof(agreementID: id, draft: observed(terms, value: 1), requestID: UUID())
        clock = created.date.addingTimeInterval(-86_400)
        let gateOff = MetricPrototypeStore(directory: root, now: { clock }); gateOff.setActor(actor)
        try gateOff.exit(agreementID: id, requestID: UUID())
        XCTAssertEqual(gateOff.agreements[0].exitedAt, gateOff.agreements[0].proofs.last?.recordedAt)
        try gateOff.refresh()
        XCTAssertNotNil(gateOff.agreements[0].exitedAt)
        XCTAssertFalse(gateOff.agreements[0].final)
    }

    func testAccountBoundaryErasesEveryPrivateCreationAndProofField() {
        let first = Date(timeIntervalSince1970: 1_800_000_000)
        let fresh = first.addingTimeInterval(86_400)
        var creation = MetricPrototypeCreationFields(now: first)
        creation.format = .timedDistance; creation.distance = "1.234567"; creation.unit = .miles
        creation.elapsedSeconds = "431.765432"; creation.comparator = .atMost
        creation.startsAt = first.addingTimeInterval(123); creation.endsAt = first.addingTimeInterval(456)
        var proof = MetricPrototypeProofFields(now: first)
        proof.state = .observed; proof.distance = "2345.678"
        proof.startsAt = first.addingTimeInterval(789); proof.endsAt = first.addingTimeInterval(999)
        creation.clear(now: fresh); proof.clear(now: fresh)
        XCTAssertEqual(creation, MetricPrototypeCreationFields(now: fresh))
        XCTAssertEqual(proof, MetricPrototypeProofFields(now: fresh))
        XCTAssertTrue(creation.distance.isEmpty && creation.elapsedSeconds.isEmpty && proof.distance.isEmpty)
        XCTAssertEqual(proof.state, .missing)
    }
}
