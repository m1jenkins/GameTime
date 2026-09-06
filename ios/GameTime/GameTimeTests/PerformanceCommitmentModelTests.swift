import XCTest
@testable import GameTime

final class PerformanceCommitmentModelTests: XCTestCase {
    private struct Fixtures: Decodable {
        let provenance: String
        let preview: PerformanceCommitmentPreview
        let documents: [Document]
    }
    private struct Document: Codable {
        let label: String
        let actorID: UUID
        let agreement: PerformanceCommitmentAgreement
        let lifecycle: PerformanceCommitmentLifecycle
        enum CodingKeys: String, CodingKey { case label, actorID = "actor_id", agreement, lifecycle }
    }
    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/performance-commitment-v1.json")
    }
    private func fixtures() throws -> Fixtures {
        try PerformanceCommitmentCodec.decoder().decode(Fixtures.self, from: Data(contentsOf: fixtureURL))
    }
    private func document(_ label: String = "corrected_notices") throws -> Document {
        try XCTUnwrap(fixtures().documents.first { $0.label == label })
    }
    private func validate(_ document: Document) throws {
        try document.lifecycle.validate(agreement: document.agreement, actorID: document.actorID)
    }
    private func changed<T: Codable>(_ input: T, path: [String], value: Any) throws -> T {
        let root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(input))
        func replacing(_ object: Any, keys: ArraySlice<String>) throws -> Any {
            guard let key = keys.first else { return value }
            if var array = object as? [Any], let index = Int(key), array.indices.contains(index) {
                array[index] = try replacing(array[index], keys: keys.dropFirst())
                return array
            }
            var dictionary = try XCTUnwrap(object as? [String: Any])
            if keys.count == 1 { dictionary[key] = value }
            else { dictionary[key] = try replacing(try XCTUnwrap(dictionary[key]), keys: keys.dropFirst()) }
            return dictionary
        }
        let data = try JSONSerialization.data(withJSONObject: replacing(root, keys: path[...]))
        return try PerformanceCommitmentCodec.decoder().decode(T.self, from: data)
    }

    func testFictionalOwnerWireShapesAndRoundTrips() throws {
        let captures = try fixtures()
        XCTAssertTrue(captures.provenance.contains("Hand-authored"), "Do not mislabel fixture shapes as hosted or HTTP acceptance")
        XCTAssertEqual(captures.documents.count, 8)
        try captures.preview.validate(for: XCTUnwrap(captures.documents.first).actorID)
        for capture in captures.documents {
            try validate(capture)
            let restored = try PerformanceCommitmentCodec.decoder().decode(Document.self, from: JSONEncoder().encode(capture))
            try validate(restored)
            XCTAssertEqual(restored.agreement, capture.agreement)
            XCTAssertEqual(restored.lifecycle, capture.lifecycle)
        }
        XCTAssertEqual(captures.preview.terms.targetText, "Run 5K in under 6:00")
        XCTAssertEqual(captures.preview.terms.policy.distanceMeters, 5000, "A six-minute target does not turn 5K into a mile")
    }

    func testActorAgreementTermsAndConsentMustStayBound() throws {
        let capture = try document()
        let stranger = UUID()
        XCTAssertThrowsError(try capture.agreement.validate(for: stranger))
        XCTAssertThrowsError(try fixtures().preview.validate(for: stranger))
        for path in [["actor_id"], ["terms", "actor_id"], ["consent", "actor_id"], ["consent", "commitment_id"]] {
            let changed = try changed(capture.agreement, path: path, value: stranger.uuidString)
            XCTAssertThrowsError(try changed.validate(for: capture.actorID), "Must bind \(path)")
        }
        for path in [["policy_version"], ["terms", "policy_version"], ["consent", "policy_version"]] {
            let changed = try changed(capture.agreement, path: path, value: "performance-commitment-fixture-mile-v1")
            XCTAssertThrowsError(try changed.validate(for: capture.actorID))
        }
        let wrongDigest = try changed(capture.agreement, path: ["consent", "terms_digest"], value: String(repeating: "b", count: 64))
        XCTAssertThrowsError(try wrongDigest.validate(for: capture.actorID))
        let shiftedConsent = try changed(capture.agreement, path: ["consent", "accepted_at"], value: "2026-05-01T12:00:00.123456Z")
        XCTAssertThrowsError(try shiftedConsent.validate(for: capture.actorID), "A one-microsecond mismatch changes consent")
        let wrongTarget = try changed(capture.agreement, path: ["target_seconds"], value: 361)
        XCTAssertThrowsError(try wrongTarget.validate(for: capture.actorID))
    }

    func testExactPolicySourceMoneyAndRuleSupportFailsClosed() throws {
        let capture = try document()
        let replacements: [(String, Any)] = [
            ("source", "garmin"), ("sport", "indoor_running"), ("distance_meters", 1609),
            ("timing_basis", "moving"), ("precision_ms", 1), ("comparator", "lte"),
            ("duration_basis", "calendar_days"), ("attempts", "one"), ("success", "latest_attempt"),
            ("slower_later_attempt", "undo_success"), ("milestones", "qualifying_proof"),
            ("miss", "missing_proof"), ("dispute_after_durable_notice_hours", 24),
            ("review_after_filing_hours", 24), ("mode", "live"), ("currency", "EUR"),
            ("commitment_cents", 3000), ("fee_cents", 100), ("redeemable", true),
            ("forfeiture_recipient", "business"), ("consent_version", "new-consent")
        ]
        for (key, value) in replacements {
            let unsupported = try changed(capture.agreement, path: ["terms", "policy", key], value: value)
            XCTAssertThrowsError(try unsupported.validate(for: capture.actorID), "Unsupported policy: \(key)")
        }
        XCTAssertThrowsError(try changed(capture.agreement, path: ["terms", "policy", "payee"], value: UUID().uuidString))
        XCTAssertThrowsError(try changed(capture.agreement, path: ["terms", "policy", "unknown_rule"], value: true))
    }

    func testPreviewAndWindowValidateExactElapsedUTCInstants() throws {
        let capture = try document()
        let preview = try fixtures().preview
        let atStart = try changed(preview, path: ["server_now"], value: preview.terms.startsAt.rawValue)
        XCTAssertThrowsError(try atStart.validate(for: capture.actorID), "Start is strictly future")
        let malformedDigest = try changed(preview, path: ["terms_digest"], value: String(repeating: "G", count: 64))
        XCTAssertThrowsError(try malformedDigest.validate(for: capture.actorID))
        let unknownZone = try changed(preview, path: ["terms", "display_timezone"], value: "MadeUp/Zone")
        XCTAssertThrowsError(try unknownZone.validate(for: capture.actorID))
        let shortDuration = try changed(preview, path: ["terms", "deadline_at"], value: "2026-05-30T12:00:00.123455Z")
        XCTAssertThrowsError(try shortDuration.validate(for: capture.actorID), "28 days minus one microsecond is too short")
        let cutoffShift = try changed(preview, path: ["terms", "results_due_at"], value: "2026-07-04T12:00:00.123455Z")
        XCTAssertThrowsError(try cutoffShift.validate(for: capture.actorID))
        let notWholeSeconds = try changed(preview, path: ["terms", "target_ms"], value: 360001)
        XCTAssertThrowsError(try notWholeSeconds.validate(for: capture.actorID))
    }

    func testUnknownStateAndOutcomeDoNotBecomeBenignDefaults() throws {
        let capture = try document()
        XCTAssertThrowsError(try changed(capture.agreement, path: ["status"], value: "final"))
        XCTAssertThrowsError(try changed(capture.agreement, path: ["phase"], value: "missed"))
        XCTAssertThrowsError(try changed(capture.lifecycle, path: ["reviews", "0", "reason"], value: "new_reason"))
        XCTAssertThrowsError(try changed(capture.lifecycle, path: ["reviews", "0", "resolution", "decision"], value: "void"))
        XCTAssertThrowsError(try changed(capture.lifecycle, path: ["notices", "0", "outcome", "reason"], value: "missing_proof"))
        XCTAssertThrowsError(try changed(capture.lifecycle, path: ["notices", "1", "outcome", "attemptId"], value: NSNull()))
        XCTAssertThrowsError(try changed(capture.lifecycle, path: ["notices", "0", "outcome", "attemptId"], value: UUID().uuidString))
    }

    func testMissingNullableFieldsCannotHideFinalityOrClosure() throws {
        func without<T: Codable>(_ input: T, key: String) throws -> T {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(input)) as? [String: Any])
            object.removeValue(forKey: key)
            return try PerformanceCommitmentCodec.decoder().decode(T.self,
                from: JSONSerialization.data(withJSONObject: object))
        }
        let capture = try document("final_return_recorded")
        for key in ["activation", "closure", "final_result", "simulation"] {
            XCTAssertThrowsError(try without(capture.lifecycle, key: key), "Absence of \(key) is not a confirmed null")
        }
        for key in ["closed_at", "close_reason"] {
            XCTAssertThrowsError(try without(capture.agreement, key: key))
        }
        XCTAssertThrowsError(try without(XCTUnwrap(capture.lifecycle.simulation), key: "payee"))
        XCTAssertThrowsError(try without(XCTUnwrap(capture.lifecycle.reviews.first), key: "resolution"))
    }

    func testCorrectedNoticesKeepOldReviewAndExactReviewBoundary() throws {
        let capture = try document()
        XCTAssertEqual(capture.lifecycle.notices.map(\.proofRevision), [1, 2])
        XCTAssertEqual(capture.lifecycle.reviews.map(\.proofRevision), [1])
        XCTAssertEqual(capture.lifecycle.latestNotice?.outcome.kind, "success")
        XCTAssertEqual(capture.lifecycle.reviews.first?.resolution?.decision, .uphold)
        var before = try changed(capture.lifecycle, path: ["server_now"], value: "2026-07-12T12:00:00.123455+00:00")
        try before.validate(agreement: capture.agreement, actorID: capture.actorID)
        before = try changed(before, path: ["server_now"], value: "2026-07-12T12:00:00.123456+00:00")
        XCTAssertThrowsError(try before.validate(agreement: capture.agreement, actorID: capture.actorID), "Expired action hint must be rejected")
        let atDeadline = try changed(before, path: ["notices", "1", "can_file_review"], value: false)
        try atDeadline.validate(agreement: capture.agreement, actorID: capture.actorID)
        let shortWindow = try changed(capture.lifecycle, path: ["notices", "1", "dispute_closes_at"], value: "2026-07-12T12:00:00.123455Z")
        XCTAssertThrowsError(try shortWindow.validate(agreement: capture.agreement, actorID: capture.actorID))
    }

    func testReviewsCannotDetachFromNoticesOrSkipFullReviewWindow() throws {
        let capture = try document()
        let values: [([String], Any)] = [
            (["reviews", "0", "proof_revision"], 3),
            (["reviews", "0", "filed_at"], "2026-07-04T12:00:00.123455Z"),
            (["reviews", "0", "review_due_at"], "2026-07-11T12:30:00.123455Z"),
            (["reviews", "0", "resolution", "recorded_at"], "2026-07-11T12:30:00.123456Z"),
            (["notices", "1", "proof_revision"], 1)
        ]
        for (path, value) in values {
            let invalid = try changed(capture.lifecycle, path: path, value: value)
            XCTAssertThrowsError(try invalid.validate(agreement: capture.agreement, actorID: capture.actorID))
        }
    }

    func testFinalityRemainsSeparateFromOpenAgreementAndSimulation() throws {
        let pending = try document("final_pending_simulation")
        try validate(pending)
        XCTAssertEqual(pending.agreement.status, .open)
        XCTAssertEqual(pending.agreement.phase, .awaitingProof)
        XCTAssertEqual(pending.lifecycle.progressText, "Result confirmed")
        XCTAssertNotNil(pending.lifecycle.finalResult)
        XCTAssertNil(pending.lifecycle.simulation)
        let settled = try document("final_return_recorded")
        XCTAssertEqual(settled.lifecycle.simulation?.returnedCents, 2000)
        XCTAssertEqual(settled.lifecycle.simulation?.lostCents, 0)
        XCTAssertEqual(try XCTUnwrap(settled.lifecycle.simulation).recordedAt.microseconds
            - XCTUnwrap(settled.lifecycle.finalResult).finalizedAt.microseconds, 1)
        let unsupported: [([String], Any)] = [
            (["final_result", "commitmentId"], UUID().uuidString),
            (["final_result", "termsDigest"], String(repeating: "b", count: 64)),
            (["final_result", "version"], "different-evaluator"),
            (["final_result", "finalizedAt"], "2026-07-12T12:00:00.123455Z"),
            (["simulation", "commitment_id"], UUID().uuidString),
            (["simulation", "returned_cents"], 0), (["simulation", "lost_cents"], 2000),
            (["simulation", "redeemable"], true), (["simulation", "fee_cents"], 100),
            (["simulation", "mode"], "live"), (["simulation", "payee"], UUID().uuidString),
            (["simulation", "forfeiture_recipient"], "business"),
            (["simulation", "recorded_at"], "2026-07-12T12:00:00.123455Z"),
            (["final_result"], NSNull())
        ]
        for (path, value) in unsupported {
            let invalid = try changed(settled.lifecycle, path: path, value: value)
            XCTAssertThrowsError(try invalid.validate(agreement: settled.agreement, actorID: settled.actorID))
        }
        let unresolved = try changed(settled.lifecycle, path: ["reviews", "0", "resolution"], value: NSNull())
        XCTAssertThrowsError(try unresolved.validate(agreement: settled.agreement, actorID: settled.actorID),
            "A success or miss cannot bypass an unresolved review")
    }

    func testClosureAndWorkerSilenceNeverInventAFinalResult() throws {
        let closed = try document("injury_receipt_pending_final")
        XCTAssertEqual(closed.agreement.closeReason, .injury)
        XCTAssertEqual(closed.agreement.status, .cancelled)
        XCTAssertNil(closed.lifecycle.finalResult)
        XCTAssertNil(closed.lifecycle.simulation)
        XCTAssertEqual(PerformanceCommitmentCloseReason.ownerSelectable, [.cancel, .withdrawal, .injury])
        let final = try document("injury_final_pending_simulation")
        try validate(final)
        let wrongClosure = try changed(closed.lifecycle, path: ["closure", "reason"], value: "cancel")
        XCTAssertThrowsError(try wrongClosure.validate(agreement: closed.agreement, actorID: closed.actorID))
        let missingClosure = try changed(closed.lifecycle, path: ["closure"], value: NSNull())
        XCTAssertThrowsError(try missingClosure.validate(agreement: closed.agreement, actorID: closed.actorID))
        for label in ["scheduled_no_worker", "past_deadline_no_worker"] {
            let silent = try document(label)
            try validate(silent)
            XCTAssertNil(silent.lifecycle.finalResult)
            XCTAssertEqual(silent.lifecycle.progressText, "No result update is saved yet")
            XCTAssertFalse(silent.agreement.statusText.contains("miss"))
        }
    }

    func testPostFinalSupportHasNoEffectOnResultOrSimulation() throws {
        let before = try document("final_return_recorded")
        let after = try document("post_final_support")
        XCTAssertEqual(before.lifecycle.finalResult, after.lifecycle.finalResult)
        XCTAssertEqual(before.lifecycle.simulation, after.lifecycle.simulation)
        XCTAssertEqual(after.lifecycle.supportReceipts.count, 1)
        let withoutFinal = try changed(after.lifecycle, path: ["final_result"], value: NSNull())
        XCTAssertThrowsError(try withoutFinal.validate(agreement: after.agreement, actorID: after.actorID))
    }
}
