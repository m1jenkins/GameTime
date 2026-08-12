import Foundation
import XCTest

@testable import GameTime

final class PersonalHealthSnapshotPlannerV2Tests: XCTestCase {
    func testPlannerUsesSevenFrozenLocalDatesAcrossSpringDST() throws {
        let terms = makeV2Terms(
            startsAt: localDate(
                year: 2026,
                month: 3,
                day: 6,
                hour: 0,
                timezone: "America/Chicago"
            ),
            timezone: "America/Chicago"
        )

        let plan = try PersonalHealthSnapshotPlanner.plan(
            terms: terms,
            observedAt: terms.endsAt
        )

        XCTAssertEqual(plan.days.count, 7)
        XCTAssertEqual(plan.days.first?.localDate, "2026-03-06")
        XCTAssertEqual(plan.days.last?.localDate, "2026-03-12")
        XCTAssertEqual(
            plan.days.compactMap(\.interval).map(\.duration),
            [86_400, 86_400, 82_800, 86_400, 86_400, 86_400, 86_400]
        )
    }

    func testPlannerUsesSevenFrozenLocalDatesAcrossFallDST() throws {
        let terms = makeV2Terms(
            startsAt: localDate(
                year: 2026,
                month: 10,
                day: 30,
                hour: 0,
                timezone: "America/Chicago"
            ),
            timezone: "America/Chicago"
        )

        let plan = try PersonalHealthSnapshotPlanner.plan(
            terms: terms,
            observedAt: terms.endsAt
        )

        XCTAssertEqual(plan.days.count, 7)
        XCTAssertEqual(plan.days.first?.localDate, "2026-10-30")
        XCTAssertEqual(plan.days.last?.localDate, "2026-11-05")
        XCTAssertEqual(
            plan.days.compactMap(\.interval).map(\.duration),
            [86_400, 86_400, 90_000, 86_400, 86_400, 86_400, 86_400]
        )
    }

    func testPlannerClipsCustomFirstDayToChallengeStart() throws {
        let start = localDate(
            year: 2026,
            month: 8,
            day: 3,
            hour: 15,
            timezone: "America/Chicago"
        )
        let terms = makeV2Terms(
            startsAt: start,
            timezone: "America/Chicago"
        )

        let plan = try PersonalHealthSnapshotPlanner.plan(
            terms: terms,
            observedAt: terms.endsAt
        )

        XCTAssertEqual(plan.days.first?.interval?.start, start)
        XCTAssertEqual(plan.days.first?.interval?.duration, 9 * 3_600)
        XCTAssertEqual(plan.days.count, 7)
    }

    func testPlannerUsesPartialCurrentDayAndZerosFutureDays() throws {
        let start = localDate(
            year: 2026,
            month: 8,
            day: 3,
            hour: 0,
            timezone: "America/Chicago"
        )
        let observedAt = localDate(
            year: 2026,
            month: 8,
            day: 5,
            hour: 11,
            timezone: "America/Chicago"
        )
        let plan = try PersonalHealthSnapshotPlanner.plan(
            terms: makeV2Terms(
                startsAt: start,
                timezone: "America/Chicago"
            ),
            observedAt: observedAt
        )

        XCTAssertEqual(plan.queryThrough, observedAt)
        XCTAssertEqual(plan.days[2].interval?.end, observedAt)
        XCTAssertEqual(plan.days[2].interval?.duration, 11 * 3_600)
        XCTAssertTrue(plan.days.dropFirst(3).allSatisfy { $0.interval == nil })
    }

    func testPlannerQueriesThroughEndDuringGrace() throws {
        let start = localDate(
            year: 2026,
            month: 8,
            day: 3,
            hour: 0,
            timezone: "America/Chicago"
        )
        let terms = makeV2Terms(
            startsAt: start,
            timezone: "America/Chicago"
        )

        let plan = try PersonalHealthSnapshotPlanner.plan(
            terms: terms,
            observedAt: terms.endsAt.addingTimeInterval(12 * 3_600)
        )

        XCTAssertEqual(plan.queryThrough, terms.endsAt)
        XCTAssertTrue(plan.days.allSatisfy { $0.interval != nil })
        XCTAssertEqual(plan.days.last?.interval?.end, terms.endsAt)
    }
}

final class PersonalStepSnapshotCacheV2Tests: XCTestCase {
    func testCacheRejectsFingerprintMismatchAndCorruption() async throws {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let cache = FilePersonalStepSnapshotCache(directoryURL: directory)
        let ownerID = UUID()
        let snapshot = makeSnapshot(total: 700, fingerprint: "terms-a")

        try await cache.save(snapshot, ownerID: ownerID)
        let match = try await cache.load(
            ownerID: ownerID,
            challengeID: snapshot.challengeID,
            termsFingerprint: "terms-a"
        )
        XCTAssertEqual(match, snapshot)
        await XCTAssertThrowsErrorAsync(
            try await cache.load(
                ownerID: ownerID,
                challengeID: snapshot.challengeID,
                termsFingerprint: "terms-b"
            )
        )

        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent(
                "\(ownerID.uuidString.lowercased())-\(snapshot.challengeID.uuidString.lowercased()).json"
            )
        )
        await XCTAssertThrowsErrorAsync(
            try await cache.load(
                ownerID: ownerID,
                challengeID: snapshot.challengeID,
                termsFingerprint: "terms-a"
            )
        )
    }

    func testCacheReplacesWholeSnapshotWithZeroAndDownwardValues() async throws {
        let directory = temporaryDirectory()
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        let cache = FilePersonalStepSnapshotCache(directoryURL: directory)
        let ownerID = UUID()
        let first = makeSnapshot(total: 700, fingerprint: "same")
        let zero = makeSnapshot(
            challengeID: first.challengeID,
            total: 0,
            fingerprint: "same",
            observedAt: first.observedAt.addingTimeInterval(60)
        )

        try await cache.save(first, ownerID: ownerID)
        try await cache.save(zero, ownerID: ownerID)
        let restored = try await cache.load(
            ownerID: ownerID,
            challengeID: first.challengeID,
            termsFingerprint: "same"
        )

        XCTAssertEqual(restored, zero)
        XCTAssertEqual(restored?.totalSteps, 0)
        XCTAssertFalse(restored?.dailyProgress.contains(where: {
            $0.totalSteps == 100
        }) ?? true)
    }
}

final class PersonalDisplayedProgressResolverV2Tests: XCTestCase {
    func testV1CleanScheduledRowsDeriveFutureStateFromFrozenTerms() throws {
        let timezone = "America/Chicago"
        let startsAt = localDate(
            year: 2026,
            month: 8,
            day: 20,
            hour: 0,
            timezone: timezone
        )
        let now = startsAt.addingTimeInterval(-3_600)
        let terms = makeV2Terms(startsAt: startsAt, timezone: timezone)
        let rows = (20...26).map {
            "{\"local_date\":\"2026-08-\(String(format: "%02d", $0))\",\"total_steps\":0}"
        }.joined(separator: ",")
        let days = try JSONDecoder().decode(
            [PersonalDayProgress].self,
            from: Data("[\(rows)]".utf8)
        )
        XCTAssertTrue(
            days.allSatisfy { $0.evidenceState == .complete },
            "The clean row omits legacy evidence_state."
        )
        let progress = PersonalProgress(
            trustedSteps: 0,
            remainingSteps: terms.targetSteps,
            qualifyingDays: 0,
            completedDays: 7,
            days: days,
            evidenceState: .pending,
            lastTrustedSyncAt: nil,
            pendingUploadCount: 0,
            coveredBucketCount: 0,
            expectedBucketCount: 0
        )
        let summary = PersonalChallengeSummary(
            id: terms.challengeID,
            status: .scheduled,
            terms: terms,
            progress: progress,
            stepDataPolicy: .attestedHourlyV1
        )

        let result = try XCTUnwrap(
            PersonalDisplayedProgressResolver.resolve(
                challenge: summary,
                live: nil,
                cached: nil,
                now: now
            )
        )

        XCTAssertEqual(result.source, .legacy)
        XCTAssertEqual(result.days.count, 7)
        XCTAssertTrue(result.days.allSatisfy { $0.state == .future })
        XCTAssertEqual(result.completedDays, 0)
    }

    func testV1CleanDailyRowsDeriveTargetAndVerdictFromFrozenTerms() throws {
        let timezone = "America/Chicago"
        let startsAt = localDate(
            year: 2026,
            month: 8,
            day: 3,
            hour: 0,
            timezone: timezone
        )
        let cumulativeTerms = makeV2Terms(
            startsAt: startsAt,
            timezone: timezone
        )
        let terms = FrozenPersonalTerms(
            challengeID: cumulativeTerms.challengeID,
            userID: cumulativeTerms.userID,
            cadence: .daily,
            targetSteps: 10_000,
            commitmentAmountMinor: cumulativeTerms.commitmentAmountMinor,
            currency: cumulativeTerms.currency,
            settlementMode: cumulativeTerms.settlementMode,
            termsVersion: cumulativeTerms.termsVersion,
            timezone: cumulativeTerms.timezone,
            agreementAt: cumulativeTerms.agreementAt,
            startsAt: cumulativeTerms.startsAt,
            endsAt: cumulativeTerms.endsAt,
            evidenceCutoff: cumulativeTerms.evidenceCutoff,
            closedAt: cumulativeTerms.closedAt
        )
        let totals = [12_000, 9_000, 10_000, 8_000, 14_000, 7_000, 11_000]
        let rows = totals.enumerated().map { index, total in
            "{\"local_date\":\"2026-08-\(String(format: "%02d", index + 3))\",\"total_steps\":\(total)}"
        }.joined(separator: ",")
        let days = try JSONDecoder().decode(
            [PersonalDayProgress].self,
            from: Data("[\(rows)]".utf8)
        )
        let progress = PersonalProgress(
            trustedSteps: totals.reduce(0, +),
            remainingSteps: 0,
            qualifyingDays: 0,
            completedDays: 7,
            days: days,
            evidenceState: .complete,
            lastTrustedSyncAt: nil,
            pendingUploadCount: 0,
            coveredBucketCount: 0,
            expectedBucketCount: 0
        )
        let summary = PersonalChallengeSummary(
            id: terms.challengeID,
            status: .completed,
            terms: terms,
            progress: progress,
            stepDataPolicy: .attestedHourlyV1
        )

        let result = try XCTUnwrap(
            PersonalDisplayedProgressResolver.resolve(
                challenge: summary,
                live: nil,
                cached: nil,
                now: terms.evidenceCutoff
            )
        )

        XCTAssertTrue(result.days.allSatisfy { $0.targetSteps == 10_000 })
        XCTAssertEqual(
            result.days.map(\.metTarget),
            [true, false, true, false, true, false, true]
        )
        XCTAssertEqual(result.qualifyingDays, 4)
    }

    func testScheduledCustomHourKeepsFirstDayFutureBeforeStart() {
        let timezone = "America/Chicago"
        let startsAt = localDate(
            year: 2026,
            month: 8,
            day: 20,
            hour: 15,
            timezone: timezone
        )
        let terms = makeV2Terms(startsAt: startsAt, timezone: timezone)
        let observedAt = startsAt.addingTimeInterval(-3_600)
        let snapshot = makeSnapshot(
            challengeID: terms.challengeID,
            total: 0,
            fingerprint: "terms",
            observedAt: observedAt,
            queryThrough: observedAt
        )
        let summary = makeV2Summary(
            terms: terms,
            status: .scheduled,
            serverSnapshot: snapshot
        )

        let result = PersonalDisplayedProgressResolver.resolve(
            challenge: summary,
            live: snapshot,
            cached: nil,
            now: observedAt
        )

        XCTAssertEqual(result?.days.first?.state, .future)
        XCTAssertTrue(result?.days.allSatisfy { $0.state == .future } == true)
    }

    func testOpenV2WithoutSnapshotDoesNotTreatZeroRowsAsFinalProgress() {
        let terms = makeCurrentV2Terms()
        let summary = PersonalChallengeSummary(
            id: terms.challengeID,
            status: .active,
            terms: terms,
            progress: .empty,
            stepDataPolicy: .healthKitNonmanualDailyV1,
            termsFingerprint: "terms"
        )

        XCTAssertNil(
            PersonalDisplayedProgressResolver.resolve(
                challenge: summary,
                live: nil,
                cached: nil
            )
        )
    }

    func testLiveThenCacheThenServerPrecedenceBeforeCutoff() throws {
        let terms = makeCurrentV2Terms()
        let challengeID = terms.challengeID
        let server = makeSnapshot(
            challengeID: challengeID,
            total: 100,
            fingerprint: "terms"
        )
        let cache = makeSnapshot(
            challengeID: challengeID,
            total: 200,
            fingerprint: "terms"
        )
        let live = makeSnapshot(
            challengeID: challengeID,
            total: 300,
            fingerprint: "terms"
        )
        let summary = makeV2Summary(terms: terms, serverSnapshot: server)

        let liveResult = PersonalDisplayedProgressResolver.resolve(
            challenge: summary,
            live: live,
            cached: cache
        )
        XCTAssertEqual(liveResult?.totalSteps, 300)
        XCTAssertEqual(liveResult?.source, .liveHealth)

        let cacheResult = PersonalDisplayedProgressResolver.resolve(
            challenge: summary,
            live: nil,
            cached: cache
        )
        XCTAssertEqual(cacheResult?.totalSteps, 200)
        XCTAssertEqual(cacheResult?.source, .protectedCache)

        let serverResult = PersonalDisplayedProgressResolver.resolve(
            challenge: summary,
            live: nil,
            cached: nil
        )
        XCTAssertEqual(serverResult?.totalSteps, 100)
        XCTAssertEqual(serverResult?.source, .serverSnapshot)
    }

    func testServerSnapshotWinsAndFreezesAfterCutoff() throws {
        let terms = makePastV2Terms()
        let server = makeSnapshot(
            challengeID: terms.challengeID,
            total: 100,
            fingerprint: "terms",
            queryThrough: terms.endsAt
        )
        let live = makeSnapshot(
            challengeID: terms.challengeID,
            total: 900,
            fingerprint: "terms",
            queryThrough: terms.endsAt
        )
        let summary = makeV2Summary(
            terms: terms,
            status: .completed,
            serverSnapshot: server
        )

        let result = PersonalDisplayedProgressResolver.resolve(
            challenge: summary,
            live: live,
            cached: live,
            now: Date()
        )

        XCTAssertEqual(result?.totalSteps, 100)
        XCTAssertEqual(result?.source, .frozenResult)
        XCTAssertEqual(result?.isFrozen, true)
    }

    func testTerminalMissingHealthSnapshotDoesNotInventZeroHealthProgress() {
        let terms = makePastV2Terms()
        let days = (0..<7).map { index in
            PersonalDayProgress(
                localDate: String(format: "2026-08-%02d", index + 3),
                trustedSteps: 0,
                targetSteps: nil,
                evidenceState: .complete,
                metTarget: false
            )
        }
        let summary = PersonalChallengeSummary(
            id: terms.challengeID,
            status: .completed,
            terms: terms,
            progress: PersonalProgress(
                trustedSteps: 0,
                remainingSteps: terms.targetSteps,
                qualifyingDays: 0,
                completedDays: 7,
                days: days,
                evidenceState: .complete,
                lastTrustedSyncAt: nil,
                pendingUploadCount: 0,
                coveredBucketCount: 0,
                expectedBucketCount: 0
            ),
            outcome: PersonalOutcome(
                id: terms.challengeID,
                kind: .inconclusive,
                reasonCode: "missing_health_data",
                evidenceCutoff: terms.evidenceCutoff,
                publishedAt: terms.evidenceCutoff
            ),
            stepDataPolicy: .healthKitNonmanualDailyV1,
            termsFingerprint: "terms",
            serverStepSnapshot: nil,
            snapshotUpdatedAt: nil
        )

        XCTAssertNil(
            PersonalDisplayedProgressResolver.resolve(
                challenge: summary,
                live: makeSnapshot(
                    challengeID: terms.challengeID,
                    total: 900,
                    fingerprint: "terms"
                ),
                cached: makeSnapshot(
                    challengeID: terms.challengeID,
                    total: 800,
                    fingerprint: "terms"
                ),
                now: terms.evidenceCutoff.addingTimeInterval(1)
            )
        )
    }

    func testTerminalIncompleteHealthSnapshotFreezesItsPartialTotals() {
        let terms = makePastV2Terms()
        let partial = makeSnapshot(
            challengeID: terms.challengeID,
            total: 12_345,
            fingerprint: "terms",
            observedAt: terms.endsAt.addingTimeInterval(3_600),
            queryThrough: terms.endsAt.addingTimeInterval(-3_600)
        )
        let summary = PersonalChallengeSummary(
            id: terms.challengeID,
            status: .completed,
            terms: terms,
            progress: nil,
            outcome: PersonalOutcome(
                id: terms.challengeID,
                kind: .inconclusive,
                reasonCode: "missing_health_data",
                evidenceCutoff: terms.evidenceCutoff,
                publishedAt: terms.evidenceCutoff
            ),
            stepDataPolicy: .healthKitNonmanualDailyV1,
            termsFingerprint: "terms",
            serverStepSnapshot: partial,
            snapshotUpdatedAt: terms.evidenceCutoff
        )

        let result = PersonalDisplayedProgressResolver.resolve(
            challenge: summary,
            live: nil,
            cached: nil,
            now: terms.evidenceCutoff.addingTimeInterval(1)
        )

        XCTAssertEqual(result?.source, .frozenResult)
        XCTAssertEqual(result?.totalSteps, 12_345)
        XCTAssertEqual(result?.isFrozen, true)
    }

    func testOpenPostCutoffDoesNotPresentMutableServerSnapshotAsFrozen() {
        let terms = makePastV2Terms()
        let server = makeSnapshot(
            challengeID: terms.challengeID,
            total: 100,
            fingerprint: "terms",
            queryThrough: terms.endsAt
        )
        let local = makeSnapshot(
            challengeID: terms.challengeID,
            total: 250,
            fingerprint: "terms",
            queryThrough: terms.endsAt
        )
        let summary = makeV2Summary(
            terms: terms,
            status: .awaitingEvidence,
            serverSnapshot: server
        )

        let localResult = PersonalDisplayedProgressResolver.resolve(
            challenge: summary,
            live: local,
            cached: nil,
            now: Date()
        )
        XCTAssertEqual(localResult?.totalSteps, 250)
        XCTAssertEqual(localResult?.source, .liveHealth)
        XCTAssertEqual(localResult?.isFrozen, false)

        XCTAssertNil(
            PersonalDisplayedProgressResolver.resolve(
                challenge: summary,
                live: nil,
                cached: nil,
                now: Date()
            )
        )
    }
}

@MainActor
final class PersonalStepProgressStoreV2Tests: XCTestCase {
    func testSuccessfulZeroAndDownwardReadReplacesDisplayedProgress() async {
        let terms = makeCurrentV2Terms()
        let reader = V2SequenceReader(snapshots: [
            makeSnapshot(
                challengeID: terms.challengeID,
                total: 700,
                fingerprint: "terms"
            ),
            makeSnapshot(
                challengeID: terms.challengeID,
                total: 0,
                fingerprint: "terms"
            ),
        ])
        let store = makeProgressStore(reader: reader)
        await store.activate(
            ownerID: UUID(),
            challenge: makeV2Summary(terms: terms)
        )
        XCTAssertEqual(store.displayedProgress?.totalSteps, 700)

        await store.refresh()

        XCTAssertEqual(store.displayedProgress?.totalSteps, 0)
        XCTAssertEqual(store.displayedProgress?.source, .liveHealth)
    }

    func testUploadFailureDoesNotHideLocalProgress() async {
        let terms = makeCurrentV2Terms()
        let uploader = V2Uploader(error: TestV2Error.offline)
        let store = makeProgressStore(
            reader: V2SequenceReader(snapshots: [
                makeSnapshot(
                    challengeID: terms.challengeID,
                    total: 350,
                    fingerprint: "terms"
                )
            ]),
            uploader: uploader
        )

        await store.activate(
            ownerID: UUID(),
            challenge: makeV2Summary(terms: terms)
        )

        XCTAssertEqual(store.displayedProgress?.totalSteps, 350)
        XCTAssertEqual(store.displayedProgress?.source, .liveHealth)
        XCTAssertNotNil(store.lastUploadError)
    }

    func testReconnectRetriesRetainedSnapshotWhenHealthReadFails() async {
        let terms = makeCurrentV2Terms()
        let retained = makeSnapshot(
            challengeID: terms.challengeID,
            total: 350,
            fingerprint: "terms"
        )
        let reader = V2SequenceReader(
            results: [.success(retained), .failure(TestV2Error.offline)]
        )
        let uploader = V2SequencedUploader(results: [
            .failure(TestV2Error.offline),
            .success(()),
        ])
        let store = makeProgressStore(reader: reader, uploader: uploader)
        await store.activate(
            ownerID: UUID(),
            challenge: makeV2Summary(terms: terms)
        )
        XCTAssertNotNil(store.lastUploadError)

        await store.refresh()

        XCTAssertEqual(uploader.snapshots, [retained, retained])
        XCTAssertNil(store.lastUploadError)
        XCTAssertEqual(store.displayedProgress?.totalSteps, 350)
        XCTAssertEqual(store.displayedProgress?.isStale, true)
    }

    func testOverlappingRefreshesCoalesceToOneTrailingRead() async {
        let terms = makeCurrentV2Terms()
        let reader = V2BlockingReader(
            challengeID: terms.challengeID,
            fingerprint: "terms"
        )
        reader.isBlocking = false
        let store = makeProgressStore(reader: reader)
        await store.activate(
            ownerID: UUID(),
            challenge: makeV2Summary(terms: terms)
        )
        reader.isBlocking = true

        async let first: Void = store.refresh()
        await reader.waitUntilReadCount(2)
        async let second: Void = store.refresh()
        async let third: Void = store.refresh()
        await Task.yield()
        reader.releaseNext()
        await reader.waitUntilReadCount(3)
        reader.releaseNext()
        _ = await (first, second, third)

        XCTAssertEqual(reader.readCount, 3)
    }

    func testResultFromPreviousAccountIsDiscarded() async {
        let terms = makeCurrentV2Terms()
        let reader = V2BlockingReader(
            challengeID: terms.challengeID,
            fingerprint: "terms"
        )
        reader.isBlocking = false
        let store = makeProgressStore(reader: reader)
        let ownerA = UUID()
        let ownerB = UUID()
        await store.activate(
            ownerID: ownerA,
            challenge: makeV2Summary(terms: terms)
        )
        reader.isBlocking = true

        async let oldRefresh: Void = store.refresh()
        await reader.waitUntilReadCount(2)
        await store.activate(ownerID: ownerB, challenge: nil)
        reader.releaseNext()
        _ = await oldRefresh

        XCTAssertEqual(store.ownerID, ownerB)
        XCTAssertNil(store.challengeID)
        XCTAssertNil(store.displayedProgress)
    }

    func testTerminalTransitionRemovesPriorOpenChallengeCache() async throws {
        let terms = makeCurrentV2Terms()
        let ownerID = UUID()
        let snapshot = makeSnapshot(
            challengeID: terms.challengeID,
            total: 450,
            fingerprint: "terms"
        )
        let cache = EphemeralPersonalStepSnapshotCache()
        let store = PersonalStepProgressStore(
            reader: V2SequenceReader(snapshots: [snapshot]),
            cache: cache,
            uploader: V2Uploader()
        )
        await store.activate(
            ownerID: ownerID,
            challenge: makeV2Summary(terms: terms)
        )
        let saved = await cache.load(
            ownerID: ownerID,
            challengeID: terms.challengeID,
            termsFingerprint: "terms"
        )
        XCTAssertEqual(saved, snapshot)

        await store.activate(
            ownerID: ownerID,
            challenge: makeV2Summary(
                terms: terms,
                status: .completed,
                serverSnapshot: snapshot
            )
        )

        let removed = await cache.load(
            ownerID: ownerID,
            challengeID: terms.challengeID,
            termsFingerprint: "terms"
        )
        XCTAssertNil(removed)
        XCTAssertEqual(store.displayedProgress?.source, .frozenResult)
    }
}

private enum TestV2Error: Error {
    case offline
}

@MainActor
private final class V2SequenceReader: PersonalHealthStepReading {
    private var results: [Result<PersonalStepSnapshot, Error>]

    init(snapshots: [PersonalStepSnapshot]) {
        results = snapshots.map(Result.success)
    }

    init(results: [Result<PersonalStepSnapshot, Error>]) {
        self.results = results
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        .requestCompleted
    }

    func readSnapshot(
        challengeID: UUID,
        terms: FrozenPersonalTerms,
        termsFingerprint: String,
        observedAt: Date
    ) async throws -> PersonalStepSnapshot {
        _ = (challengeID, terms, termsFingerprint, observedAt)
        guard !results.isEmpty else { throw TestV2Error.offline }
        return try results.removeFirst().get()
    }
}

@MainActor
private final class V2BlockingReader: PersonalHealthStepReading {
    let challengeID: UUID
    let fingerprint: String
    var isBlocking = true
    private(set) var readCount = 0
    private var releases: [CheckedContinuation<Void, Never>] = []

    init(challengeID: UUID, fingerprint: String) {
        self.challengeID = challengeID
        self.fingerprint = fingerprint
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        .requestCompleted
    }

    func readSnapshot(
        challengeID: UUID,
        terms: FrozenPersonalTerms,
        termsFingerprint: String,
        observedAt: Date
    ) async throws -> PersonalStepSnapshot {
        _ = (challengeID, terms, termsFingerprint)
        readCount += 1
        if isBlocking {
            await withCheckedContinuation { continuation in
                releases.append(continuation)
            }
        }
        return makeSnapshot(
            challengeID: self.challengeID,
            total: readCount * 70,
            fingerprint: fingerprint,
            observedAt: observedAt
        )
    }

    func waitUntilReadCount(_ expected: Int) async {
        while readCount < expected {
            await Task.yield()
        }
    }

    func releaseNext() {
        guard !releases.isEmpty else { return }
        releases.removeFirst().resume()
    }
}

@MainActor
private final class V2Uploader: PersonalHealthSnapshotUploading {
    private(set) var snapshots: [PersonalStepSnapshot] = []
    let error: Error?

    init(error: Error? = nil) {
        self.error = error
    }

    func upload(
        _ snapshot: PersonalStepSnapshot,
        expectedUserID: UUID
    ) async throws {
        _ = expectedUserID
        snapshots.append(snapshot)
        if let error { throw error }
    }
}

@MainActor
private final class V2SequencedUploader: PersonalHealthSnapshotUploading {
    private var results: [Result<Void, Error>]
    private(set) var snapshots: [PersonalStepSnapshot] = []

    init(results: [Result<Void, Error>]) {
        self.results = results
    }

    func upload(
        _ snapshot: PersonalStepSnapshot,
        expectedUserID: UUID
    ) async throws {
        _ = expectedUserID
        snapshots.append(snapshot)
        guard !results.isEmpty else { return }
        return try results.removeFirst().get()
    }
}

@MainActor
private func makeProgressStore(
    reader: any PersonalHealthStepReading,
    uploader: any PersonalHealthSnapshotUploading = V2Uploader()
) -> PersonalStepProgressStore {
    PersonalStepProgressStore(
        reader: reader,
        cache: EphemeralPersonalStepSnapshotCache(),
        uploader: uploader
    )
}

private func makeV2Summary(
    terms: FrozenPersonalTerms,
    status: PersonalChallengeStatus = .active,
    serverSnapshot: PersonalStepSnapshot? = nil
) -> PersonalChallengeSummary {
    PersonalChallengeSummary(
        id: terms.challengeID,
        status: status,
        terms: terms,
        progress: nil,
        outcome: nil,
        stepDataPolicy: .healthKitNonmanualDailyV1,
        termsFingerprint: "terms",
        serverStepSnapshot: serverSnapshot,
        snapshotUpdatedAt: serverSnapshot?.observedAt
    )
}

private func makeCurrentV2Terms(now: Date = Date()) -> FrozenPersonalTerms {
    let calendar = PersonalChallengeStart.calendar("America/Chicago")
    let start = calendar.date(
        byAdding: .day,
        value: -1,
        to: calendar.startOfDay(for: now)
    )!
    return makeV2Terms(startsAt: start, timezone: "America/Chicago")
}

private func makePastV2Terms(now: Date = Date()) -> FrozenPersonalTerms {
    let calendar = PersonalChallengeStart.calendar("America/Chicago")
    let start = calendar.date(
        byAdding: .day,
        value: -10,
        to: calendar.startOfDay(for: now)
    )!
    return makeV2Terms(startsAt: start, timezone: "America/Chicago")
}

private func makeV2Terms(
    startsAt: Date,
    timezone: String
) -> FrozenPersonalTerms {
    let calendar = PersonalChallengeStart.calendar(timezone)
    let firstDay = calendar.startOfDay(for: startsAt)
    let endsAt = calendar.date(byAdding: .day, value: 7, to: firstDay)!
    return FrozenPersonalTerms(
        challengeID: UUID(
            uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"
        )!,
        userID: nil,
        cadence: .cumulative,
        targetSteps: 70_000,
        commitmentAmountMinor: 1_000,
        currency: "USD",
        settlementMode: .testOnly,
        termsVersion: "personal-v2",
        timezone: timezone,
        agreementAt: startsAt.addingTimeInterval(-60),
        startsAt: startsAt,
        endsAt: endsAt,
        evidenceCutoff: calendar.date(
            byAdding: .day,
            value: 1,
            to: endsAt
        )!,
        closedAt: nil
    )
}

private func makeSnapshot(
    challengeID: UUID = UUID(
        uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb"
    )!,
    total: Int,
    fingerprint: String,
    observedAt: Date = Date(),
    queryThrough: Date? = nil
) -> PersonalStepSnapshot {
    let base = total / 7
    let remainder = total - (base * 7)
    return PersonalStepSnapshot(
        challengeID: challengeID,
        termsFingerprint: fingerprint,
        observedAt: observedAt,
        queryThrough: min(queryThrough ?? observedAt, observedAt),
        dailyProgress: (0..<7).map { day in
            PersonalStepSnapshot.Day(
                localDate: String(format: "2026-08-%02d", day + 3),
                totalSteps: base + (day == 0 ? remainder : 0)
            )
        }
    )
}

private func localDate(
    year: Int,
    month: Int,
    day: Int,
    hour: Int,
    timezone: String
) -> Date {
    let calendar = PersonalChallengeStart.calendar(timezone)
    return calendar.date(
        from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        )
    )!
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(
        "gametime-personal-v2-\(UUID().uuidString)",
        isDirectory: true
    )
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected an error.", file: file, line: line)
    } catch {
        // Expected.
    }
}
