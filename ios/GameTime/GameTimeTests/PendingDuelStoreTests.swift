import XCTest
@testable import GameTime

final class PendingDuelStoreTests: XCTestCase {
    func testProtectedStoreRoundTripPreservesRequestAndAccountIsolation()
        async throws
    {
        let directory = try makeTemporaryDirectory()
        let store = FilePendingDuelStore(directoryURL: directory)
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let otherOwnerID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let submission = makeSubmission(ownerID: ownerID)

        try await store.save(submission)

        let restored = try await store.load(for: ownerID)
        XCTAssertEqual(restored, submission)
        XCTAssertEqual(restored?.terms.requestID, submission.terms.requestID)
        XCTAssertEqual(
            restored?.terms.startsAt.timeIntervalSinceReferenceDate.bitPattern,
            submission.terms.startsAt.timeIntervalSinceReferenceDate.bitPattern
        )
        XCTAssertEqual(
            restored?.terms.endsAt.timeIntervalSinceReferenceDate.bitPattern,
            submission.terms.endsAt.timeIntervalSinceReferenceDate.bitPattern
        )
        let rollbackRetry = try XCTUnwrap(restored).recordingAttempt(
            at: submission.createdAt.addingTimeInterval(-3_600)
        )
        XCTAssertEqual(rollbackRetry.attemptCount, submission.attemptCount + 1)
        XCTAssertEqual(rollbackRetry.lastAttemptAt, submission.lastAttemptAt)
        try await store.save(rollbackRetry)
        let restoredRollbackRetry = try await store.load(for: ownerID)
        XCTAssertEqual(restoredRollbackRetry, rollbackRetry)

        let otherSubmission = try await store.load(for: otherOwnerID)
        XCTAssertNil(otherSubmission)

        let fileURL = await store.fileURL(for: ownerID)
        let resourceValues = try fileURL.resourceValues(
            forKeys: [.isExcludedFromBackupKey]
        )
        XCTAssertEqual(resourceValues.isExcludedFromBackup, true)

        try await store.remove(for: ownerID)
        let removedSubmission = try await store.load(for: ownerID)
        XCTAssertNil(removedSubmission)
    }

    func testStoreRejectsCorruptionAndUnsupportedEnvelopeVersion()
        async throws
    {
        let directory = try makeTemporaryDirectory()
        let store = FilePendingDuelStore(directoryURL: directory)
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let fileURL = await store.fileURL(for: ownerID)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fileURL)

        do {
            _ = try await store.load(for: ownerID)
            XCTFail("Expected corrupt protected data to fail closed")
        } catch {
            XCTAssertEqual(error as? PendingDuelStoreError, .corruptData)
        }

        let envelope = PendingDuelStoreEnvelope(
            version: PendingDuelStoreEnvelope.currentVersion + 1,
            submission: makeSubmission(ownerID: ownerID)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        try encoder.encode(envelope).write(to: fileURL)

        do {
            _ = try await store.load(for: ownerID)
            XCTFail("Expected a future envelope version to fail closed")
        } catch {
            XCTAssertEqual(
                error as? PendingDuelStoreError,
                .unsupportedVersion(
                    PendingDuelStoreEnvelope.currentVersion + 1
                )
            )
        }
    }

    func testStoreRejectsCopiedCrossAccountRecordAndInvalidAttemptState()
        async throws
    {
        let directory = try makeTemporaryDirectory()
        let store = FilePendingDuelStore(directoryURL: directory)
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let otherOwnerID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let submission = makeSubmission(ownerID: ownerID)
        try await store.save(submission)

        let ownerURL = await store.fileURL(for: ownerID)
        let otherURL = await store.fileURL(for: otherOwnerID)
        try FileManager.default.copyItem(at: ownerURL, to: otherURL)

        do {
            _ = try await store.load(for: otherOwnerID)
            XCTFail("Expected copied account data to be rejected")
        } catch {
            XCTAssertEqual(error as? PendingDuelStoreError, .ownerMismatch)
        }

        let invalid = PendingDuelSubmission(
            ownerID: ownerID,
            terms: submission.terms,
            createdAt: submission.createdAt,
            attemptCount: 0,
            lastAttemptAt: submission.lastAttemptAt
        )
        do {
            try await store.save(invalid)
            XCTFail("Expected inconsistent attempt state to be rejected")
        } catch {
            guard let storeError = error as? PendingDuelStoreError else {
                return XCTFail("Unexpected error: \(error)")
            }
            guard case .invalidRecord = storeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStoreRejectsChangedOrRegressedExistingSubmission() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FilePendingDuelStore(directoryURL: directory)
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let original = makeSubmission(ownerID: ownerID)
        try await store.save(original)

        let changedTerms = DuelTerms(
            requestID: UUID(),
            title: original.terms.title,
            inviteeID: original.terms.inviteeID,
            metric: original.terms.metric,
            cadence: original.terms.cadence,
            targetValue: original.terms.targetValue,
            stakeAmountCents: original.terms.stakeAmountCents,
            startsAt: original.terms.startsAt,
            endsAt: original.terms.endsAt,
            timezone: original.terms.timezone,
            charityID: original.terms.charityID,
            tieBreak: original.terms.tieBreak
        )
        await assertConflictingSave(
            PendingDuelSubmission(
                ownerID: ownerID,
                terms: changedTerms,
                createdAt: original.createdAt,
                attemptCount: original.attemptCount + 1,
                lastAttemptAt: original.lastAttemptAt?.addingTimeInterval(1)
            ),
            store: store
        )
        await assertConflictingSave(
            PendingDuelSubmission(
                ownerID: ownerID,
                terms: original.terms,
                createdAt: original.createdAt,
                attemptCount: original.attemptCount - 1,
                lastAttemptAt: original.lastAttemptAt
            ),
            store: store
        )

        let restored = try await store.load(for: ownerID)
        XCTAssertEqual(restored, original)
    }

    private func makeSubmission(ownerID: UUID) -> PendingDuelSubmission {
        let createdAt = Date(timeIntervalSince1970: 2_000_000_000)
        let startsAt = Date(
            timeIntervalSinceReferenceDate: 800_000_000.123_456_7
        )
        let endsAt = Date(
            timeIntervalSinceReferenceDate: 800_172_800.765_432_1
        )
        return PendingDuelSubmission(
            ownerID: ownerID,
            terms: DuelTerms(
                requestID: UUID(
                    uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
                )!,
                title: "Restart-safe duel",
                inviteeID: UUID(
                    uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
                )!,
                metric: .distanceMeters,
                cadence: .cumulative,
                targetValue: 5_000,
                stakeAmountCents: 700,
                startsAt: startsAt,
                endsAt: endsAt,
                timezone: "America/Chicago",
                charityID: UUID(
                    uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc"
                )!,
                tieBreak: .earliestToTarget
            ),
            createdAt: createdAt,
            attemptCount: 2,
            lastAttemptAt: createdAt.addingTimeInterval(30)
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func assertConflictingSave(
        _ submission: PendingDuelSubmission,
        store: FilePendingDuelStore
    ) async {
        do {
            try await store.save(submission)
            XCTFail("Expected an existing immutable retry to reject changes")
        } catch {
            XCTAssertEqual(
                error as? PendingDuelStoreError,
                .conflictingRecord
            )
        }
    }
}
