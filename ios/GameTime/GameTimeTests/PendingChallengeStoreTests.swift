import XCTest

@testable import GameTime

// MARK: - Pending challenge persistence

final class PendingChallengeStoreTests: XCTestCase {
    func testProtectedStoreRoundTripPreservesRequestAndAccountIsolation()
        async throws
    {
        let directory = try makeTemporaryDirectory()
        let store = FilePendingChallengeStore(directoryURL: directory)
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
        let store = FilePendingChallengeStore(directoryURL: directory)
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
            XCTAssertEqual(error as? PendingChallengeStoreError, .corruptData)
        }

        let envelope = PendingChallengeStoreEnvelope(
            version: PendingChallengeStoreEnvelope.currentVersion + 1,
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
                error as? PendingChallengeStoreError,
                .unsupportedVersion(
                    PendingChallengeStoreEnvelope.currentVersion + 1
                )
            )
        }
    }

    func testVersionOneSavedDuelMigratesWithoutChangingItsRequest() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FilePendingChallengeStore(directoryURL: directory)
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let inviteeID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let requestID = UUID(
            uuidString: "33333333-3333-3333-3333-333333333333"
        )!
        let charityID = UUID(
            uuidString: "44444444-4444-4444-4444-444444444444"
        )!
        let createdAt = Date(
            timeIntervalSinceReferenceDate: 800_000_000.123_456
        )
        let lastAttemptAt = createdAt.addingTimeInterval(15)
        let legacyTerms = LegacyDuelTerms(
            requestID: requestID,
            title: "Legacy saved duel",
            inviteeID: inviteeID,
            metric: .steps,
            cadence: .cumulative,
            targetValue: 10_000,
            stakeAmountCents: 500,
            startsAt: Date(
                timeIntervalSinceReferenceDate: 800_086_400.987_654
            ),
            endsAt: Date(
                timeIntervalSinceReferenceDate: 800_259_200.654_321
            ),
            timezone: "America/Chicago",
            charityID: charityID,
            tieBreak: .integrityScore
        )
        let legacyEnvelope = LegacyPendingDuelStoreEnvelope(
            version: LegacyPendingDuelStoreEnvelope.legacyVersion,
            submission: LegacyPendingDuelSubmission(
                ownerID: ownerID,
                terms: legacyTerms,
                createdAt: createdAt,
                attemptCount: 2,
                lastAttemptAt: lastAttemptAt
            )
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let fileURL = await store.fileURL(for: ownerID)
        try encoder.encode(legacyEnvelope).write(to: fileURL)

        let loaded = try await store.load(for: ownerID)
        let restored = try XCTUnwrap(loaded)

        XCTAssertEqual(restored.ownerID, ownerID)
        XCTAssertEqual(restored.terms.requestID, requestID)
        XCTAssertEqual(restored.terms.inviteeIDs, [inviteeID])
        XCTAssertEqual(restored.terms.maxParticipants, 2)
        XCTAssertEqual(restored.attemptCount, 2)
        XCTAssertEqual(
            restored.createdAt.timeIntervalSinceReferenceDate.bitPattern,
            createdAt.timeIntervalSinceReferenceDate.bitPattern
        )
        XCTAssertEqual(
            restored.lastAttemptAt?.timeIntervalSinceReferenceDate.bitPattern,
            lastAttemptAt.timeIntervalSinceReferenceDate.bitPattern
        )
        XCTAssertEqual(
            restored.terms.startsAt.timeIntervalSinceReferenceDate.bitPattern,
            legacyTerms.startsAt.timeIntervalSinceReferenceDate.bitPattern
        )
        XCTAssertEqual(
            restored.terms.endsAt.timeIntervalSinceReferenceDate.bitPattern,
            legacyTerms.endsAt.timeIntervalSinceReferenceDate.bitPattern
        )

        let migratedEnvelope = try JSONDecoder().decode(
            PendingChallengeStoreEnvelope.self,
            from: Data(contentsOf: fileURL)
        )
        XCTAssertEqual(
            migratedEnvelope.version,
            PendingChallengeStoreEnvelope.currentVersion
        )
        XCTAssertEqual(migratedEnvelope.submission, restored)
        XCTAssertEqual(
            try fileURL.resourceValues(
                forKeys: [.isExcludedFromBackupKey]
            ).isExcludedFromBackup,
            true
        )
    }

    func testStoreRejectsCopiedCrossAccountRecordAndInvalidAttemptState()
        async throws
    {
        let directory = try makeTemporaryDirectory()
        let store = FilePendingChallengeStore(directoryURL: directory)
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
            XCTAssertEqual(error as? PendingChallengeStoreError, .ownerMismatch)
        }

        let invalid = PendingChallengeSubmission(
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
            guard let storeError = error as? PendingChallengeStoreError else {
                return XCTFail("Unexpected error: \(error)")
            }
            guard case .invalidRecord = storeError else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testStoreRejectsChangedOrRegressedExistingSubmission() async throws {
        let directory = try makeTemporaryDirectory()
        let store = FilePendingChallengeStore(directoryURL: directory)
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let original = makeSubmission(ownerID: ownerID)
        try await store.save(original)

        let changedTerms = ChallengeTerms(
            requestID: UUID(),
            title: original.terms.title,
            inviteeIDs: original.terms.inviteeIDs,
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
            PendingChallengeSubmission(
                ownerID: ownerID,
                terms: changedTerms,
                createdAt: original.createdAt,
                attemptCount: original.attemptCount + 1,
                lastAttemptAt: original.lastAttemptAt?.addingTimeInterval(1)
            ),
            store: store
        )
        await assertConflictingSave(
            PendingChallengeSubmission(
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

    private func makeSubmission(ownerID: UUID) -> PendingChallengeSubmission {
        let createdAt = Date(timeIntervalSince1970: 2_000_000_000)
        let startsAt = Date(
            timeIntervalSinceReferenceDate: 800_000_000.123_456_7
        )
        let endsAt = Date(
            timeIntervalSinceReferenceDate: 800_172_800.765_432_1
        )
        return PendingChallengeSubmission(
            ownerID: ownerID,
            terms: ChallengeTerms(
                requestID: UUID(
                    uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
                )!,
                title: "Restart-safe challenge",
                inviteeIDs: [
                    UUID(
                        uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
                    )!,
                    UUID(
                        uuidString: "dddddddd-dddd-dddd-dddd-dddddddddddd"
                    )!,
                ],
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
        _ submission: PendingChallengeSubmission,
        store: FilePendingChallengeStore
    ) async {
        do {
            try await store.save(submission)
            XCTFail("Expected an existing immutable retry to reject changes")
        } catch {
            XCTAssertEqual(
                error as? PendingChallengeStoreError,
                .conflictingRecord
            )
        }
    }
}
