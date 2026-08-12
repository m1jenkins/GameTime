import Foundation
import GameTimeCore
import HealthKit
import SwiftUI
import XCTest

@testable import GameTime

final class PersonalAccountabilityModelTests: XCTestCase {
    func testStripeTermsSelectV2PolicyWithoutChangingPaymentConsent() throws {
        let request = try PersonalChallengeDraft().validated(
            requestID: fixedRequestID
        )
        let data = try JSONEncoder().encode(
            PersonalPaymentTermsDocument(request: request)
        )
        let document = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(
            document["stepDataPolicy"] as? String,
            "healthkit_nonmanual_daily_v1"
        )
        XCTAssertEqual(
            document["agreementVersion"] as? String,
            "personal-stripe-sandbox-v1"
        )
        XCTAssertEqual(
            document["consentVersion"] as? String,
            "personal-stripe-sandbox-consent-v1"
        )
    }

    func testMissingHealthDataReasonUsesPlainV2Language() {
        XCTAssertEqual(
            PersonalReasonText.sentence(for: "missing_health_data"),
            "Apple Health didn’t have step data available for this challenge."
        )
    }

    func testDraftDefaultsAndCadenceDefaultsAreLocked() throws {
        var draft = PersonalChallengeDraft()

        XCTAssertEqual(draft.cadence, .daily)
        XCTAssertEqual(draft.targetSteps, 10_000)
        XCTAssertEqual(draft.commitmentAmountMinor, 1_000)
        XCTAssertEqual(
            PersonalChallengeDraft.allowedCommitmentAmountsMinor,
            [1_000, 2_000, 3_000, 4_000, 5_000]
        )
        for amount in PersonalChallengeDraft.allowedCommitmentAmountsMinor {
            var preset = draft
            preset.commitmentAmountMinor = amount
            XCTAssertEqual(
                try preset.validated(requestID: fixedRequestID)
                    .commitmentAmountMinor,
                amount
            )
        }

        draft.selectCadence(.cumulative)
        XCTAssertEqual(draft.targetSteps, 70_000)

        draft.targetSteps = 82_500
        draft.selectCadence(.daily)
        XCTAssertEqual(draft.targetSteps, 82_500)

        let request = try draft.validated(requestID: fixedRequestID)
        XCTAssertEqual(request.targetSteps, 82_500)
        XCTAssertEqual(request.commitmentAmountMinor, 1_000)
    }

    func testDraftRejectsUnsupportedTargetCommitmentAndTimezone() {
        var draft = PersonalChallengeDraft()
        draft.targetSteps = 0
        XCTAssertThrowsError(try draft.validated()) { error in
            XCTAssertEqual(
                error as? PersonalChallengeValidationError,
                .invalidTarget
            )
        }

        draft.targetSteps = 10_000
        draft.commitmentAmountMinor = 1_500
        XCTAssertThrowsError(try draft.validated()) { error in
            XCTAssertEqual(
                error as? PersonalChallengeValidationError,
                .invalidCommitment
            )
        }

        draft.commitmentAmountMinor = 1_000
        draft.timezone = "Not/A-Timezone"
        XCTAssertThrowsError(try draft.validated()) { error in
            XCTAssertEqual(
                error as? PersonalChallengeValidationError,
                .invalidTimezone
            )
        }
    }

    func testNewDraftFreezesValidProfileTimezoneInsteadOfTravelZone() {
        let draft = PersonalChallengeDraft.initial(
            profileTimezone: "America/Chicago",
            deviceTimezone: "Europe/Paris"
        )

        XCTAssertEqual(draft.timezone, "America/Chicago")
    }

    func testFrozenTermsFormatterDoesNotUseTravelTimezone() {
        let instant = Date(timeIntervalSince1970: 1_785_733_200)
        let frozen = PersonalTermsDateFormatter.dateTime(
            instant,
            timezoneIdentifier: "America/Chicago"
        )
        let expected = instant.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                timeZone: TimeZone(identifier: "America/Chicago")!
            )
        )
        let travelDisplay = instant.formatted(
            Date.FormatStyle(
                date: .abbreviated,
                time: .shortened,
                timeZone: TimeZone(identifier: "Europe/Paris")!
            )
        )

        XCTAssertEqual(frozen, expected)
        XCTAssertNotEqual(frozen, travelDisplay)
    }

    func testReleaseDefaultsToLockedPersonalModeUntilSandboxIsSelected() throws {
        let configuration = try AppConfiguration.validated(
            environmentValue: "Release",
            urlValue: "https://example.supabase.co",
            keyValue: "sb_publishable_unit_test",
            mutationValue: "YES"
        )

        XCTAssertFalse(configuration.personalChallengeMutationsEnabled)
        XCTAssertEqual(configuration.personalSettlementMode, .testOnly)
    }

    func testPersonalStatusDecoderNeverReinterpretsUnknownModelState() throws {
        XCTAssertEqual(
            try JSONDecoder().decode(
                PersonalChallengeStatus.self,
                from: Data("\"pending\"".utf8)
            ),
            .scheduled
        )
        XCTAssertThrowsError(
            try JSONDecoder().decode(
                PersonalChallengeStatus.self,
                from: Data("\"winner\"".utf8)
            )
        )
    }

    func testDailyProgressDecodesFractionalServiceStepsWithoutRescoring()
        throws
    {
        let data = Data(
            #"{"local_date":"2026-08-03","trusted_steps":123.45,"target_steps":10000,"evidence_state":"complete","met_target":false}"#.utf8
        )

        let progress = try JSONDecoder().decode(
            PersonalDayProgress.self,
            from: data
        )

        XCTAssertEqual(progress.trustedSteps, 123.45, accuracy: 0.000_001)
        XCTAssertEqual(progress.displayedTrustedSteps, 123)
        XCTAssertFalse(try XCTUnwrap(progress.metTarget))
    }

    func testDailyRemainingUsesInProgressDayInsteadOfFutureTail() throws {
        let data = Data(
            #"[{"local_date":"2026-08-03","trusted_steps":10000,"target_steps":10000,"evidence_state":"complete","met_target":true},{"local_date":"2026-08-04","trusted_steps":1234.56,"target_steps":10000,"evidence_state":"in_progress","met_target":null},{"local_date":"2026-08-05","trusted_steps":0,"target_steps":10000,"evidence_state":"future","met_target":null},{"local_date":"2026-08-06","trusted_steps":0,"target_steps":10000,"evidence_state":"future","met_target":null},{"local_date":"2026-08-07","trusted_steps":0,"target_steps":10000,"evidence_state":"future","met_target":null},{"local_date":"2026-08-08","trusted_steps":0,"target_steps":10000,"evidence_state":"future","met_target":null},{"local_date":"2026-08-09","trusted_steps":0,"target_steps":10000,"evidence_state":"future","met_target":null}]"#.utf8
        )
        let days = try JSONDecoder().decode(
            [PersonalDayProgress].self,
            from: data
        )

        XCTAssertEqual(
            PersonalProgress.dailyRemainingSteps(
                targetSteps: 10_000,
                days: days
            ),
            8_766
        )
    }

    func testDiagnosticResponseRejectsStatusReplayMismatch() throws {
        let newResponse = Data(
            #"{"diagnosticId":"44444444-4444-4444-4444-444444444444","performedAt":"2026-08-03T02:00:00.000Z","replayed":false,"clearedHold":false}"#.utf8
        )
        let replayResponse = Data(
            #"{"diagnosticId":"44444444-4444-4444-4444-444444444444","performedAt":"2026-08-03T02:00:00.000Z","replayed":true,"clearedHold":false}"#.utf8
        )

        XCTAssertNoThrow(
            try DiagnosticResponse.decode(newResponse, statusCode: 201)
        )
        XCTAssertNoThrow(
            try DiagnosticResponse.decode(replayResponse, statusCode: 200)
        )
        XCTAssertThrowsError(
            try DiagnosticResponse.decode(newResponse, statusCode: 200)
        ) { error in
            XCTAssertEqual(
                error as? PersonalAccountabilityClientError,
                .invalidResponse
            )
        }
        XCTAssertThrowsError(
            try DiagnosticResponse.decode(replayResponse, statusCode: 201)
        ) { error in
            XCTAssertEqual(
                error as? PersonalAccountabilityClientError,
                .invalidResponse
            )
        }
    }

    func testAggregateEvidenceDoesNotHideQuarantineBehindCoverageCount() {
        let day = PersonalDayProgress(
            localDate: "2026-08-03",
            trustedSteps: 12_345.67,
            targetSteps: 10_000,
            evidenceState: .quarantined,
            metTarget: nil
        )

        XCTAssertEqual(
            PersonalProgress.aggregateEvidenceState(
                days: [day],
                coveredBucketCount: 24,
                expectedBucketCount: 24
            ),
            .quarantined
        )
    }

    func testOpenChallengeBecomesResultPendingAtEvidenceCutoff() {
        let challengeID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let cutoff = Date(timeIntervalSince1970: 1_785_889_800)
        let summary = PersonalChallengeSummary(
            id: challengeID,
            status: .active,
            terms: FrozenPersonalTerms(
                challengeID: challengeID,
                userID: nil,
                cadence: .daily,
                targetSteps: 10_000,
                commitmentAmountMinor: 1_000,
                currency: "USD",
                settlementMode: .testOnly,
                termsVersion: "personal-v1",
                timezone: "America/Chicago",
                agreementAt: cutoff.addingTimeInterval(-9 * 86_400),
                startsAt: cutoff.addingTimeInterval(-8 * 86_400),
                endsAt: cutoff.addingTimeInterval(-86_400),
                evidenceCutoff: cutoff,
                closedAt: nil
            )
        )

        XCTAssertEqual(
            summary.presentationStatus(at: cutoff),
            .resultPending
        )
        XCTAssertFalse(summary.permitsActivitySync(at: cutoff))
    }

    // MARK: - Chosen start day and hour

    /// 2026-08-03 20:37:12 UTC — 15:37 in Chicago, deliberately mid-hour.
    private var startClock: Date {
        Date(timeIntervalSince1970: 1_785_789_432)
    }

    private func chicagoInstant(
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int,
        minute: Int = 0
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour,
                minute: minute
            )
        )!
    }

    func testDefaultStartIsStillTheNextLocalMidnightAndTravelsAsOmitted() throws {
        let draft = PersonalChallengeDraft.initial(
            profileTimezone: "America/Chicago",
            now: startClock
        )

        XCTAssertEqual(draft.startsAt, chicagoInstant(2026, 8, 4, 0))
        // Omitted, so the server resolves "next local midnight" when the
        // request commits rather than when the draft was filled in.
        XCTAssertNil(draft.requestedStart(now: startClock))
        XCTAssertNil(
            try draft.validated(requestID: fixedRequestID, now: startClock)
                .startsAt
        )
        XCTAssertEqual(
            PersonalChallengeStart.firstDayHours(
                startsAt: draft.startsAt,
                timezone: "America/Chicago"
            ),
            24
        )
    }

    func testChosenLaterHourTravelsExplicitlyAndShortensOnlyTheFirstDay() throws {
        var draft = PersonalChallengeDraft.initial(
            profileTimezone: "America/Chicago",
            now: startClock
        )
        draft.selectStartDay(chicagoInstant(2026, 8, 5, 0), now: startClock)
        draft.selectStartHour(15, now: startClock)

        XCTAssertEqual(draft.startsAt, chicagoInstant(2026, 8, 5, 15))
        XCTAssertEqual(
            try draft.validated(requestID: fixedRequestID, now: startClock)
                .startsAt,
            chicagoInstant(2026, 8, 5, 15)
        )
        XCTAssertEqual(
            PersonalChallengeStart.firstDayHours(
                startsAt: draft.startsAt,
                timezone: "America/Chicago"
            ),
            9
        )
    }

    func testTodayOffersOnlyTheHoursItHasLeft() {
        let today = chicagoInstant(2026, 8, 3, 0)
        let hours = PersonalChallengeStart.selectableHours(
            onLocalDay: today,
            now: startClock,
            timezone: "America/Chicago"
        )

        // 15:37 local: 15:00 has passed, 16:00 has not.
        XCTAssertEqual(hours, Array(16...23))
        XCTAssertEqual(
            PersonalChallengeStart.earliestSelectableInstant(
                now: startClock,
                timezone: "America/Chicago"
            ),
            chicagoInstant(2026, 8, 3, 16)
        )
    }

    func testStartMustBeAWholeFutureLocalHourWithinNinetyDays() {
        let timezone = "America/Chicago"

        XCTAssertFalse(
            PersonalChallengeStart.isSelectable(
                startClock,
                now: startClock.addingTimeInterval(-3_600),
                timezone: timezone
            ),
            "a mid-hour instant is never a bucket boundary"
        )
        XCTAssertFalse(
            PersonalChallengeStart.isSelectable(
                chicagoInstant(2026, 8, 3, 12),
                now: startClock,
                timezone: timezone
            ),
            "an hour already past cannot open a window"
        )
        XCTAssertFalse(
            PersonalChallengeStart.isSelectable(
                chicagoInstant(2026, 11, 3, 9),
                now: startClock,
                timezone: timezone
            ),
            "beyond ninety days is refused, matching the server bound"
        )
        XCTAssertTrue(
            PersonalChallengeStart.isSelectable(
                chicagoInstant(2026, 8, 5, 15),
                now: startClock,
                timezone: timezone
            )
        )
    }

    func testDraftRejectsAStartThatHasAlreadyPassed() {
        var draft = PersonalChallengeDraft.initial(
            profileTimezone: "America/Chicago",
            now: startClock
        )
        draft.startsAt = chicagoInstant(2026, 8, 3, 12)

        XCTAssertThrowsError(
            try draft.validated(requestID: fixedRequestID, now: startClock)
        ) { error in
            XCTAssertEqual(
                error as? PersonalChallengeValidationError,
                .invalidStart
            )
        }
    }

    func testStartNowAcceptsOnlyTheCurrentMinute() throws {
        var draft = PersonalChallengeDraft.initial(
            profileTimezone: "America/Chicago",
            now: startClock
        )
        draft.startsAt = PersonalChallengeStart.currentMinute(now: startClock)

        XCTAssertThrowsError(
            try draft.validated(requestID: fixedRequestID, now: startClock)
        )
        XCTAssertEqual(
            try draft.validated(
                requestID: fixedRequestID,
                now: startClock,
                allowsCurrentMinuteStart: true
            ).startsAt,
            chicagoInstant(2026, 8, 3, 15, minute: 37)
        )

        draft.startsAt = chicagoInstant(2026, 8, 3, 15, minute: 36)
        XCTAssertThrowsError(
            try draft.validated(
                requestID: fixedRequestID,
                now: startClock,
                allowsCurrentMinuteStart: true
            )
        )
    }

    func testSpringForwardSkippedHourIsNotOffered() {
        // America/Chicago loses 02:00 on 2026-03-08.
        let transitionDay = chicagoInstant(2026, 3, 7, 0)
        let dayBefore = chicagoInstant(2026, 3, 6, 12)

        XCTAssertNil(
            PersonalChallengeStart.instant(
                localDay: chicagoInstant(2026, 3, 8, 0),
                hour: 2,
                timezone: "America/Chicago"
            ),
            "an hour the zone skips cannot be a start"
        )
        XCTAssertFalse(
            PersonalChallengeStart.selectableHours(
                onLocalDay: chicagoInstant(2026, 3, 8, 0),
                now: dayBefore,
                timezone: "America/Chicago"
            ).contains(2)
        )
        XCTAssertEqual(
            PersonalChallengeStart.selectableHours(
                onLocalDay: transitionDay,
                now: dayBefore,
                timezone: "America/Chicago"
            ),
            Array(0...23),
            "the day before the transition keeps all of its hours"
        )
    }

    /// A retry record written before a start could be chosen carries no such
    /// key. Its absence already meant the next local midnight, so it must load
    /// unchanged and keep its request identity rather than fail validation.
    func testRetryRecordWithoutAStartStillDecodesAsTheServerDefault() throws {
        let legacy = Data(
            """
            {"cadence":"cumulative","commitmentAmountMinor":2000,\
            "requestID":"AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",\
            "targetSteps":70000,"timezone":"America/Chicago"}
            """.utf8
        )

        let request = try JSONDecoder().decode(
            PersonalChallengeCreationRequest.self,
            from: legacy
        )

        XCTAssertEqual(request.requestID, fixedRequestID)
        XCTAssertNil(request.startsAt)
        XCTAssertEqual(request.timezone, "America/Chicago")
    }

    private var fixedRequestID: UUID {
        UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!
    }
}

@MainActor
final class PersonalAccountabilityStoreTests: XCTestCase {
    func testRefreshReplacesCachedActiveDetailWithTerminalFrozenSummary()
        async throws
    {
        let ownerID = UUID()
        let active = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .active,
            totalSteps: 900
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(active)
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await store.activate(ownerID: ownerID)
        await store.loadDetail(challengeID: active.id)
        XCTAssertEqual(store.detail(for: active.id)?.status, .active)

        let outcome = PersonalOutcome(
            id: active.id,
            kind: .metGoal,
            reasonCode: "target_reached_complete_evidence",
            evidenceCutoff: active.terms.evidenceCutoff,
            publishedAt: active.terms.evidenceCutoff
        )
        let terminal = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .completed,
            totalSteps: 100,
            outcome: outcome,
            challengeID: active.id,
            terms: active.terms
        )
        client.setChallenge(terminal)

        await store.refresh()

        let refreshed = try XCTUnwrap(store.detail(for: active.id))
        XCTAssertEqual(refreshed.status, .completed)
        XCTAssertEqual(refreshed.outcome, outcome)
        XCTAssertEqual(refreshed.serverStepSnapshot?.totalSteps, 100)
        let displayed = try XCTUnwrap(store.displayedProgress(for: refreshed))
        XCTAssertEqual(displayed.source, .frozenResult)
        XCTAssertEqual(displayed.totalSteps, 100)
        XCTAssertTrue(displayed.isFrozen)
    }

    func testRefreshReplacesCachedOpenDetailWithCancellationTruth()
        async throws
    {
        let ownerID = UUID()
        let active = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .active,
            totalSteps: 900
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(active)
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await store.activate(ownerID: ownerID)
        await store.loadDetail(challengeID: active.id)
        XCTAssertEqual(store.detail(for: active.id)?.status, .active)

        let cancelled = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .cancelled,
            totalSteps: 0,
            challengeID: active.id,
            terms: active.terms
        )
        client.setChallenge(cancelled)

        await store.refresh()

        XCTAssertEqual(store.detail(for: active.id)?.status, .cancelled)
        XCTAssertNil(store.openChallenge)
        XCTAssertEqual(store.history.map(\.id), [active.id])
    }

    func testTerminalDetailPromotesOpenListAndFreezesEverySurface()
        async throws
    {
        let ownerID = UUID()
        let active = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .active,
            totalSteps: 900
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(active)
        let cache = EphemeralPersonalStepSnapshotCache()
        let stepProgress = PersonalStepProgressStore(
            reader: StorePersonalHealthStepReaderFake(),
            cache: cache,
            uploader: DisabledPersonalHealthSnapshotUploader()
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: stepProgress
        )
        await store.activate(ownerID: ownerID)
        XCTAssertEqual(store.openChallenge?.id, active.id)
        let cachedBeforeTerminal = await cache.load(
            ownerID: ownerID,
            challengeID: active.id,
            termsFingerprint: "lifecycle-v2"
        )
        XCTAssertNotNil(cachedBeforeTerminal)

        let outcome = PersonalOutcome(
            id: active.id,
            kind: .metGoal,
            reasonCode: "target_reached_complete_evidence",
            evidenceCutoff: active.terms.evidenceCutoff,
            publishedAt: active.terms.evidenceCutoff
        )
        let terminal = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .completed,
            totalSteps: 100,
            outcome: outcome,
            challengeID: active.id,
            terms: active.terms
        )
        // The list remains open while the newer detail endpoint observes the
        // monotonic terminal transition.
        client.setChallenge(terminal)

        await store.loadDetail(challengeID: active.id)

        XCTAssertNil(store.openChallenge)
        let history = try XCTUnwrap(store.history.first)
        XCTAssertEqual(history.status, .completed)
        XCTAssertEqual(history.outcome, outcome)
        XCTAssertEqual(store.detail(for: active.id)?.status, .completed)
        let displayed = try XCTUnwrap(store.displayedProgress(for: history))
        XCTAssertEqual(displayed.source, .frozenResult)
        XCTAssertEqual(displayed.totalSteps, 100)
        XCTAssertTrue(displayed.isFrozen)
        XCTAssertNil(stepProgress.challengeID)
        let cachedAfterTerminal = await cache.load(
            ownerID: ownerID,
            challengeID: active.id,
            termsFingerprint: "lifecycle-v2"
        )
        XCTAssertNil(cachedAfterTerminal)
    }

    func testCancelledDetailPromotesOpenListAndRetiresMutableProgress()
        async throws
    {
        let ownerID = UUID()
        let active = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .active,
            totalSteps: 900
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(active)
        let cache = EphemeralPersonalStepSnapshotCache()
        let stepProgress = PersonalStepProgressStore(
            reader: StorePersonalHealthStepReaderFake(),
            cache: cache,
            uploader: DisabledPersonalHealthSnapshotUploader()
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: stepProgress
        )
        await store.activate(ownerID: ownerID)
        XCTAssertEqual(store.openChallenge?.id, active.id)
        let cachedBeforeCancellation = await cache.load(
            ownerID: ownerID,
            challengeID: active.id,
            termsFingerprint: "lifecycle-v2"
        )
        XCTAssertNotNil(cachedBeforeCancellation)

        let cancelledBase = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .cancelled,
            totalSteps: 0,
            challengeID: active.id,
            terms: active.terms
        )
        let cancelled = PersonalChallengeDetail(
            id: cancelledBase.id,
            status: .cancelled,
            terms: cancelledBase.terms,
            progress: .empty,
            outcome: nil,
            stepDataPolicy: cancelledBase.stepDataPolicy,
            termsFingerprint: cancelledBase.termsFingerprint,
            serverStepSnapshot: nil,
            snapshotUpdatedAt: nil
        )
        client.setChallenge(cancelled)

        await store.loadDetail(challengeID: active.id)

        XCTAssertNil(store.openChallenge)
        let history = try XCTUnwrap(store.history.first)
        XCTAssertEqual(history.status, .cancelled)
        XCTAssertEqual(store.detail(for: active.id)?.status, .cancelled)
        XCTAssertNil(store.displayedProgress(for: history))
        XCTAssertNil(stepProgress.challengeID)
        let cachedAfterCancellation = await cache.load(
            ownerID: ownerID,
            challengeID: active.id,
            termsFingerprint: "lifecycle-v2"
        )
        XCTAssertNil(cachedAfterCancellation)
    }

    func testStaleOpenListCannotUndoTerminalDetailPromotion() async throws {
        let ownerID = UUID()
        let active = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .active,
            totalSteps: 900
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(active)
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await store.activate(ownerID: ownerID)

        client.suspendNextListResponse()
        let staleRefresh = Task { await store.refresh() }
        await client.waitUntilListResponseSuspends()

        let outcome = PersonalOutcome(
            id: active.id,
            kind: .metGoal,
            reasonCode: "target_reached_complete_evidence",
            evidenceCutoff: active.terms.evidenceCutoff,
            publishedAt: active.terms.evidenceCutoff
        )
        let terminal = makeV2LifecycleChallenge(
            ownerID: ownerID,
            status: .completed,
            totalSteps: 100,
            outcome: outcome,
            challengeID: active.id,
            terms: active.terms
        )
        client.setChallenge(terminal)
        await store.loadDetail(challengeID: active.id)
        XCTAssertNil(store.openChallenge)

        client.resumeSuspendedListResponse()
        await staleRefresh.value

        XCTAssertNil(store.openChallenge)
        let history = try XCTUnwrap(store.history.first)
        XCTAssertEqual(history.status, .completed)
        XCTAssertEqual(history.outcome, outcome)
        let displayed = try XCTUnwrap(store.displayedProgress(for: history))
        XCTAssertEqual(displayed.source, .frozenResult)
        XCTAssertEqual(displayed.totalSteps, 100)
    }

    func testOpenV2PolicyRetiresLegacyPersonalUploads() async {
        let ownerID = UUID()
        let legacy = makeActivityChallenge(
            ownerID: ownerID,
            evidenceCutoff: Date().addingTimeInterval(86_400)
        )
        let challenge = PersonalChallengeDetail(
            id: legacy.id,
            status: legacy.status,
            terms: legacy.terms,
            progress: legacy.progress,
            outcome: legacy.outcome,
            stepDataPolicy: .healthKitNonmanualDailyV1,
            termsFingerprint: "v2-terms"
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(challenge)
        let activitySync = StorePersonalActivitySyncFake(
            pendingCount: 2,
            pendingChallengeID: challenge.id,
            results: []
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: activitySync
        )

        await store.activate(ownerID: ownerID)

        XCTAssertEqual(
            activitySync.retiredContexts,
            [.init(ownerID: ownerID, challengeID: challenge.id)]
        )
        XCTAssertEqual(store.pendingActivityUploadCount, 0)
        XCTAssertNil(store.pendingActivityChallengeID)
        XCTAssertFalse(store.hasPendingActivityRecoveryIssue)
    }

    func testOfflineServerRefreshStillRunsLocalV2HealthRead() async {
        let ownerID = UUID()
        let legacy = makeActivityChallenge(
            ownerID: ownerID,
            evidenceCutoff: Date().addingTimeInterval(2 * 86_400)
        )
        let challenge = PersonalChallengeDetail(
            id: legacy.id,
            status: legacy.status,
            terms: legacy.terms,
            progress: legacy.progress,
            outcome: legacy.outcome,
            stepDataPolicy: .healthKitNonmanualDailyV1,
            termsFingerprint: "v2-terms"
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(challenge)
        let reader = StorePersonalHealthStepReaderFake()
        let stepProgress = PersonalStepProgressStore(
            reader: reader,
            cache: EphemeralPersonalStepSnapshotCache(),
            uploader: DisabledPersonalHealthSnapshotUploader()
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: stepProgress
        )
        await store.activate(ownerID: ownerID)
        XCTAssertEqual(reader.readCount, 1)
        client.listError = .unavailable

        await store.refresh()

        XCTAssertEqual(reader.readCount, 2)
        XCTAssertNotNil(stepProgress.displayedProgress)
        guard case .failed = store.loadState else {
            return XCTFail("Server failure should remain visible.")
        }
    }


    func testOverlappingSameAccountActivationsRestoreAndListOnce() async {
        let ownerID = UUID()
        let pendingStore = CountingPendingPersonalChallengeStore()
        let pendingCancellationStore =
            CountingPendingPersonalCancellationStore()
        let activitySync = StorePersonalActivitySyncFake(
            pendingCount: 0,
            pendingChallengeID: nil,
            results: [],
            blocksNextPendingCountRead: true
        )
        let client = PersonalClientFake(ownerID: ownerID)
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: pendingStore,
            pendingCancellationStore: pendingCancellationStore,
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: activitySync
        )

        let firstActivation = Task {
            await store.activate(ownerID: ownerID)
        }
        await activitySync.waitUntilPendingCountReadStarts()
        let overlappingActivation = Task {
            await store.activate(ownerID: ownerID)
        }
        await Task.yield()
        activitySync.releasePendingCountRead()
        await firstActivation.value
        await overlappingActivation.value

        let pendingCreationLoadCount = await pendingStore.loadCallCount
        let pendingCancellationLoadCount =
            await pendingCancellationStore.loadCallCount
        XCTAssertEqual(pendingCreationLoadCount, 1)
        XCTAssertEqual(pendingCancellationLoadCount, 1)
        XCTAssertEqual(activitySync.pendingCountReadCount, 1)
        XCTAssertEqual(client.listCallCount, 1)

        await store.activate(ownerID: ownerID)

        XCTAssertEqual(activitySync.pendingCountReadCount, 1)
        XCTAssertEqual(client.listCallCount, 1)
    }

    func testCreationStaysFailClosedWhileSavedStateRestores() async {
        let ownerID = UUID()
        let activitySync = StorePersonalActivitySyncFake(
            pendingCount: 0,
            pendingChallengeID: nil,
            results: [],
            blocksNextPendingCountRead: true
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: PersonalClientFake(ownerID: ownerID),
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: activitySync
        )

        let activation = Task {
            await store.activate(ownerID: ownerID)
        }
        await activitySync.waitUntilPendingCountReadStarts()
        await store.refresh()

        XCTAssertEqual(store.loadState, .empty)
        XCTAssertTrue(store.isRestoringSavedState)
        XCTAssertFalse(store.hasVerifiedCreationState)
        XCTAssertFalse(store.canCreate)

        activitySync.releasePendingCountRead()
        await activation.value

        XCTAssertFalse(store.isRestoringSavedState)
        XCTAssertTrue(store.hasVerifiedCreationState)
        XCTAssertTrue(store.canCreate)
    }

    func testSameAccountActivationRetriesActivityRecoveryIssue() async {
        let ownerID = UUID()
        let activitySync = StorePersonalActivitySyncFake(
            pendingCount: 0,
            pendingChallengeID: nil,
            results: [],
            pendingCountError: ActivitySyncError.queuedRequestUnavailable
        )
        let client = PersonalClientFake(ownerID: ownerID)
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: activitySync
        )

        await store.activate(ownerID: ownerID)

        XCTAssertTrue(store.hasPendingActivityRecoveryIssue)
        XCTAssertEqual(activitySync.pendingCountReadCount, 1)
        XCTAssertEqual(client.listCallCount, 1)

        activitySync.setPendingCountError(nil)
        await store.activate(ownerID: ownerID)

        XCTAssertFalse(store.hasPendingActivityRecoveryIssue)
        XCTAssertEqual(activitySync.pendingCountReadCount, 2)
        XCTAssertEqual(client.listCallCount, 2)
        XCTAssertTrue(store.canCreate)
    }

    func testGenuineForegroundTransitionPerformsOneNewRefresh() async {
        let ownerID = UUID()
        let client = PersonalClientFake(ownerID: ownerID)
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await store.activate(ownerID: ownerID)
        var gate = AppShellForegroundRefreshGate()

        XCTAssertFalse(gate.shouldRefresh(after: .active))
        XCTAssertFalse(gate.shouldRefresh(after: .inactive))
        XCTAssertFalse(gate.shouldRefresh(after: .active))
        XCTAssertFalse(gate.shouldRefresh(after: .background))
        XCTAssertFalse(gate.shouldRefresh(after: .inactive))
        if gate.shouldRefresh(after: .active) {
            await store.refresh()
        }
        XCTAssertFalse(gate.shouldRefresh(after: .active))

        XCTAssertEqual(client.listCallCount, 2)
    }

    func testExplicitPullToRefreshPerformsOneNewRefresh() async {
        let ownerID = UUID()
        let client = PersonalClientFake(ownerID: ownerID)
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await store.activate(ownerID: ownerID)

        await store.refresh()

        XCTAssertEqual(client.listCallCount, 2)
    }

    func testAccountSwitchDiscardsStaleRefreshResult() async {
        let ownerA = UUID()
        let ownerB = UUID()
        let asOf = Date(timeIntervalSince1970: 1_785_888_000)
        let challengeA = makeActivityChallenge(
            ownerID: ownerA,
            evidenceCutoff: asOf
        )
        let challengeB = makeActivityChallenge(
            ownerID: ownerB,
            evidenceCutoff: asOf.addingTimeInterval(86_400)
        )
        let auth = PersonalAuthFake(ownerID: ownerA)
        let client = PersonalClientFake(ownerID: ownerA)
        client.setChallenge(challengeA)
        client.suspendNextListResponse()
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: auth,
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )

        let accountAActivation = Task {
            await store.activate(ownerID: ownerA)
        }
        await client.waitUntilListResponseSuspends()
        auth.ownerID = ownerB
        client.setChallenge(challengeB)

        await store.activate(ownerID: ownerB)

        XCTAssertEqual(store.ownerID, ownerB)
        XCTAssertEqual(store.challenges.map(\.id), [challengeB.id])

        client.resumeSuspendedListResponse()
        await accountAActivation.value

        XCTAssertEqual(store.ownerID, ownerB)
        XCTAssertEqual(store.challenges.map(\.id), [challengeB.id])
        XCTAssertEqual(client.listCallCount, 2)
    }

    func testCreationFailsClosedAfterAvailabilityRefreshFails() async throws {
        let ownerID = UUID()
        let client = PersonalClientFake(ownerID: ownerID)
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await store.activate(ownerID: ownerID)
        XCTAssertEqual(store.loadState, .empty)
        XCTAssertTrue(store.canCreate)

        client.listError = .unavailable
        await store.refresh()

        guard case .failed = store.loadState else {
            return XCTFail("A failed server refresh must remain visible.")
        }
        XCTAssertFalse(store.hasVerifiedCreationState)
        XCTAssertFalse(store.canCreate)

        let challengeID = await store.create(
            try PersonalChallengeDraft().validated()
        )

        XCTAssertNil(challengeID)
        XCTAssertTrue(client.requests.isEmpty)
        XCTAssertEqual(
            store.presentedError,
            PersonalAccountabilityClientError.unavailable.localizedDescription
        )

        client.listError = nil
        await store.refresh()
        XCTAssertEqual(store.loadState, .empty)
        XCTAssertTrue(store.canCreate)
    }

    func testPaymentPreparationFailsClosedAfterAvailabilityRefreshFails()
        async throws
    {
        let ownerID = UUID()
        let client = PersonalClientFake(ownerID: ownerID)
        let payments = PersonalPaymentFake(ownerID: ownerID)
        let store = PersonalAccountabilityStore(
            configuration: .stripeSandboxFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            paymentClient: payments,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await store.activate(ownerID: ownerID)
        client.listError = .unavailable
        await store.refresh()
        let request = try PersonalChallengeDraft().validated(
            requestID: UUID()
        )

        let setup = await store.preparePayment(request)

        XCTAssertNil(setup)
        XCTAssertTrue(payments.preparedRequests.isEmpty)
        XCTAssertNil(store.pendingCreation)
    }

    func testBackgroundUpdateDoesNotReplayRetiredLegacyQueue()
        async throws
    {
        let ownerID = UUID()
        let asOf = Date(timeIntervalSince1970: 1_785_888_000)
        let challenge = makeActivityChallenge(
            ownerID: ownerID,
            evidenceCutoff: asOf
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(challenge)
        let activitySync = StorePersonalActivitySyncFake(
            pendingCount: 1,
            pendingChallengeID: challenge.id,
            results: [
                .outcome(.savedRequestAccepted, pendingAfter: 0)
            ]
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: activitySync
        )
        await store.activate(ownerID: ownerID)
        XCTAssertEqual(store.pendingActivityChallengeID, challenge.id)
        client.listError = .unavailable

        await store.handleBackgroundActivityUpdate(asOf: asOf)

        XCTAssertTrue(activitySync.syncedChallengeIDs.isEmpty)
        XCTAssertEqual(store.pendingActivityUploadCount, 1)
        XCTAssertEqual(store.pendingActivityChallengeID, challenge.id)
        XCTAssertEqual(store.syncState(for: challenge.id), .idle)
        guard case .failed = store.loadState else {
            return XCTFail("The independent server failure stays visible.")
        }
    }

    func testCancellationRecountsSavedActivityRequests() async throws {
        let ownerID = UUID()
        let asOf = Date(timeIntervalSince1970: 1_785_888_000)
        let challenge = makeActivityChallenge(
            ownerID: ownerID,
            evidenceCutoff: asOf.addingTimeInterval(86_400)
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(challenge)
        let activitySync = StorePersonalActivitySyncFake(
            pendingCount: 1,
            pendingChallengeID: challenge.id,
            results: [.cancellation(pendingAfter: 0)]
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: activitySync
        )
        await store.activate(ownerID: ownerID)
        XCTAssertEqual(store.pendingActivityUploadCount, 1)
        XCTAssertEqual(store.pendingActivityChallengeID, challenge.id)

        await store.sync(challengeID: challenge.id, asOf: asOf)

        XCTAssertEqual(store.pendingActivityUploadCount, 0)
        XCTAssertNil(store.pendingActivityChallengeID)
        XCTAssertEqual(store.syncState(for: challenge.id), .idle)
        XCTAssertNil(store.presentedError)
    }

    func testSavedLegacyActivityDoesNotBlockV2CreationAvailability()
        async
    {
        let ownerID = UUID()
        let asOf = Date(timeIntervalSince1970: 1_785_888_000)
        let challenge = makeActivityChallenge(
            ownerID: ownerID,
            evidenceCutoff: asOf,
            status: .completed
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(challenge)
        let activitySync = StorePersonalActivitySyncFake(
            pendingCount: 1,
            pendingChallengeID: challenge.id,
            results: []
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: activitySync
        )

        await store.activate(ownerID: ownerID)

        XCTAssertNil(store.openChallenge)
        XCTAssertTrue(store.canCreate)
        XCTAssertEqual(store.pendingActivityChallengeID, challenge.id)
        XCTAssertTrue(
            store.canSyncActivity(
                challengeID: challenge.id,
                permitsFreshSync: false
            )
        )
        XCTAssertFalse(
            store.canSyncActivity(
                challengeID: UUID(),
                permitsFreshSync: true
            )
        )

    }

    func testUnreadableLegacyActivityQueueDoesNotBlockV2Creation() async {
        let ownerID = UUID()
        let activitySync = StorePersonalActivitySyncFake(
            pendingCount: 0,
            pendingChallengeID: nil,
            results: [],
            pendingCountError: ActivitySyncError.queuedRequestUnavailable
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: PersonalClientFake(ownerID: ownerID),
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: activitySync
        )

        await store.activate(ownerID: ownerID)

        XCTAssertEqual(store.loadState, .empty)
        XCTAssertTrue(store.hasPendingActivityRecoveryIssue)
        XCTAssertTrue(store.canCreate)
        XCTAssertFalse(
            store.canSyncActivity(
                challengeID: UUID(),
                permitsFreshSync: true
            )
        )

        activitySync.setPendingCountError(nil)
        await store.retryPendingActivityRecovery()

        XCTAssertFalse(store.hasPendingActivityRecoveryIssue)
        XCTAssertTrue(store.canCreate)
    }

    func testV2CreateBypassesActivityThatBecamePendingInLegacyQueue()
        async throws
    {
        let ownerID = UUID()
        let asOf = Date(timeIntervalSince1970: 1_785_888_000)
        let challenge = makeActivityChallenge(
            ownerID: ownerID,
            evidenceCutoff: asOf,
            status: .completed
        )
        let client = PersonalClientFake(ownerID: ownerID)
        client.setChallenge(challenge)
        let activitySync = StorePersonalActivitySyncFake(
            pendingCount: 0,
            pendingChallengeID: challenge.id,
            results: [
                .outcome(
                    .queuedForRetry(stepTotal: 123),
                    pendingAfter: 1
                )
            ]
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: activitySync,
            stepProgressStore: automaticStepProgressStore()
        )
        await store.activate(ownerID: ownerID)
        await connectHealth(store)
        XCTAssertTrue(store.canCreate)
        let draftOpenedBeforeQueue = try PersonalChallengeDraft().validated()

        await store.sync(challengeID: challenge.id, asOf: asOf)
        let createdID = await store.create(draftOpenedBeforeQueue)

        XCTAssertEqual(createdID, client.createdChallengeID)
        XCTAssertEqual(client.requests, [draftOpenedBeforeQueue])
        XCTAssertEqual(store.pendingActivityUploadCount, 1)
        XCTAssertEqual(store.pendingActivityChallengeID, challenge.id)
    }

    func testLostReviewResponseRetriesTheExactReasonAndShowsUnderReview()
        async throws
    {
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let challengeID = UUID(
            uuidString: "19191919-1919-1919-1919-191919191919"
        )!
        let auth = PersonalAuthFake(ownerID: ownerID)
        let client = PersonalClientFake(ownerID: ownerID)
        let payments = PersonalPaymentFake(ownerID: ownerID)
        payments.loseFirstReviewResponse = true
        let now = Date()
        client.setChallenge(
            PersonalChallengeDetail(
                id: challengeID,
                status: .completed,
                terms: FrozenPersonalTerms(
                    challengeID: challengeID,
                    userID: ownerID,
                    cadence: .cumulative,
                    targetSteps: 70_000,
                    commitmentAmountMinor: 2_000,
                    currency: "USD",
                    settlementMode: .stripeSandbox,
                    termsVersion: "personal-stripe-sandbox-v1",
                    timezone: "America/Chicago",
                    agreementAt: now.addingTimeInterval(-10 * 86_400),
                    startsAt: now.addingTimeInterval(-9 * 86_400),
                    endsAt: now.addingTimeInterval(-2 * 86_400),
                    evidenceCutoff: now.addingTimeInterval(-86_400),
                    closedAt: now.addingTimeInterval(-86_400)
                ),
                progress: .empty,
                outcome: PersonalOutcome(
                    id: UUID(),
                    kind: .missedGoal,
                    reasonCode: "target_missed_complete_evidence",
                    evidenceCutoff: now.addingTimeInterval(-86_400),
                    publishedAt: now.addingTimeInterval(-3_600)
                )
            )
        )
        let store = PersonalAccountabilityStore(
            configuration: .stripeSandboxFixture,
            auth: auth,
            client: client,
            paymentClient: payments,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await store.activate(ownerID: ownerID)

        let first = await store.requestReview(
            challengeID: challengeID,
            reason: .userDisputesResult,
            now: now
        )
        XCTAssertFalse(first)
        XCTAssertNil(store.reviewRequest(for: challengeID))

        let retry = await store.requestReview(
            challengeID: challengeID,
            reason: .userDisputesResult,
            now: now
        )

        XCTAssertTrue(retry)
        XCTAssertEqual(payments.reviewRequests.count, 2)
        XCTAssertEqual(
            payments.reviewRequests.map(\.challengeID),
            [challengeID, challengeID]
        )
        XCTAssertEqual(
            payments.reviewRequests.map(\.reason),
            [.userDisputesResult, .userDisputesResult]
        )
        XCTAssertEqual(
            store.reviewRequest(for: challengeID)?.state,
            .underReview
        )
    }

    func testStripeSetupCompletionAndLostCommitRetryExactFrozenRequest()
        async throws
    {
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let auth = PersonalAuthFake(ownerID: ownerID)
        let client = PersonalClientFake(ownerID: ownerID)
        let payments = PersonalPaymentFake(ownerID: ownerID)
        payments.loseFirstCommitResponse = true
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let pendingStore = FilePendingPersonalChallengeStore(
            directoryURL: directory
        )
        let request = try PersonalChallengeDraft().validated(
            requestID: UUID(
                uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            )!
        )
        let firstStore = PersonalAccountabilityStore(
            configuration: .stripeSandboxFixture,
            auth: auth,
            client: client,
            paymentClient: payments,
            pendingStore: pendingStore,
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: automaticStepProgressStore()
        )
        await firstStore.activate(ownerID: ownerID)
        await connectHealth(firstStore)

        let preparedSetup = await firstStore.preparePayment(request)
        let setup = try XCTUnwrap(
            preparedSetup,
            firstStore.presentedError ?? "No store error was presented."
        )
        XCTAssertEqual(setup.setupID, payments.setupID)
        XCTAssertEqual(
            firstStore.pendingCreation?.paymentSetupID,
            payments.setupID
        )
        XCTAssertNil(
            firstStore.pendingCreation?.paymentSetupCompletedAt
        )
        let persistedSetupURL = await pendingStore.fileURL(for: ownerID)
        let persistedSetupData = try Data(contentsOf: persistedSetupURL)
        let persistedSetup = try XCTUnwrap(
            String(data: persistedSetupData, encoding: .utf8)
        )
        XCTAssertTrue(persistedSetup.contains(payments.setupID))
        XCTAssertFalse(persistedSetup.contains(payments.publishableKey))
        XCTAssertFalse(
            persistedSetup.contains(payments.setupIntentClientSecret)
        )
        let confirmed = await firstStore.confirmPaymentSetup(
            request: request,
            setupID: setup.setupID
        )
        XCTAssertTrue(confirmed)
        XCTAssertNotNil(
            firstStore.pendingCreation?.paymentSetupCompletedAt
        )

        let firstChallengeID = await firstStore.create(request)
        XCTAssertNil(firstChallengeID)
        let failedPending = try await pendingStore.load(for: ownerID)
        XCTAssertEqual(failedPending?.request, request)
        XCTAssertEqual(failedPending?.attemptCount, 1)

        let relaunchedStore = PersonalAccountabilityStore(
            configuration: .stripeSandboxFixture,
            auth: auth,
            client: client,
            paymentClient: payments,
            pendingStore: pendingStore,
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: automaticStepProgressStore()
        )
        await relaunchedStore.activate(ownerID: ownerID)
        await connectHealth(relaunchedStore)
        XCTAssertTrue(relaunchedStore.pendingPaymentIsConfirmed)

        let challengeID = await relaunchedStore.create(request)

        XCTAssertEqual(challengeID, payments.challengeID)
        XCTAssertEqual(payments.preparedRequests, [request])
        XCTAssertEqual(payments.committedRequests, [request, request])
        XCTAssertTrue(client.requests.isEmpty)
        let clearedPending = try await pendingStore.load(for: ownerID)
        XCTAssertNil(clearedPending)
    }

    func testLostCreateResponseRetriesExactRequestAndClearsPendingRecord()
        async throws
    {
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let auth = PersonalAuthFake(ownerID: ownerID)
        let client = PersonalClientFake(ownerID: ownerID)
        client.loseFirstResponse = true
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: directory)
        }
        let pendingStore = FilePendingPersonalChallengeStore(
            directoryURL: directory
        )
        let firstStore = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: auth,
            client: client,
            pendingStore: pendingStore,
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: automaticStepProgressStore()
        )
        await firstStore.activate(ownerID: ownerID)
        await connectHealth(firstStore)
        let request = try PersonalChallengeDraft().validated(
            requestID: UUID(
                uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
            )!
        )

        let unconfirmedID = await firstStore.create(request)
        XCTAssertNil(unconfirmedID)
        let pending = try await pendingStore.load(for: ownerID)
        XCTAssertEqual(pending?.request, request)
        XCTAssertEqual(pending?.attemptCount, 1)

        let relaunchedStore = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: auth,
            client: client,
            pendingStore: pendingStore,
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: automaticStepProgressStore()
        )
        await relaunchedStore.activate(ownerID: ownerID)
        await connectHealth(relaunchedStore)
        XCTAssertEqual(relaunchedStore.pendingCreation?.request, request)
        XCTAssertEqual(
            relaunchedStore.openChallenge?.id,
            client.createdChallengeID
        )

        let createdID = await relaunchedStore.create(request)

        XCTAssertEqual(createdID, client.createdChallengeID)
        XCTAssertEqual(client.requests, [request, request])
        let clearedPending = try await pendingStore.load(for: ownerID)
        XCTAssertNil(clearedPending)
        XCTAssertEqual(relaunchedStore.openChallenge?.id, createdID)
    }

    func testStoreBlocksCreationWhenEligibilityHoldIsActive() async throws {
        let ownerID = UUID()
        let auth = PersonalAuthFake(ownerID: ownerID)
        let client = PersonalClientFake(ownerID: ownerID)
        client.hold = PersonalEligibilityHold(
            id: UUID(),
            reasonCode: "unresolved_device_sync",
            createdAt: Date(),
            clearedAt: nil,
            clearedByDiagnosticID: nil
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: auth,
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await store.activate(ownerID: ownerID)

        let heldRequest = try PersonalChallengeDraft().validated()
        let heldCreationID = await store.create(heldRequest)
        XCTAssertNil(heldCreationID)
        XCTAssertEqual(client.requests.count, 0)
        XCTAssertTrue(store.eligibilityHoldActive)
    }

    func testLostCancellationResponseRelaunchRetriesExactRequest()
        async throws
    {
        let ownerID = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let auth = PersonalAuthFake(ownerID: ownerID)
        let client = PersonalClientFake(ownerID: ownerID)
        let cancellationStore = EphemeralPendingPersonalCancellationStore()
        let firstStore = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: auth,
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            pendingCancellationStore: cancellationStore,
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: automaticStepProgressStore()
        )
        await firstStore.activate(ownerID: ownerID)
        await connectHealth(firstStore)
        let createdChallengeID = await firstStore.create(
            try PersonalChallengeDraft().validated()
        )
        let challengeID = try XCTUnwrap(createdChallengeID)
        let requestID = UUID(
            uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc"
        )!
        client.loseFirstCancellationResponse = true

        let firstCancellationConfirmed = await firstStore.cancel(
            challengeID: challengeID,
            requestID: requestID
        )
        XCTAssertFalse(firstCancellationConfirmed)
        let restoredCancellation = try await cancellationStore.load(
            for: ownerID
        )
        let saved = try XCTUnwrap(restoredCancellation)
        XCTAssertEqual(saved.challengeID, challengeID)
        XCTAssertEqual(saved.requestID, requestID)
        XCTAssertEqual(saved.attemptCount, 1)
        XCTAssertEqual(
            try saved.recordingAttempt().requestBody,
            saved.requestBody
        )

        let relaunchedStore = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: auth,
            client: client,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            pendingCancellationStore: cancellationStore,
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await relaunchedStore.activate(ownerID: ownerID)

        XCTAssertEqual(client.cancellationRequests.count, 2)
        XCTAssertEqual(client.cancellationRequests[0].challengeID, challengeID)
        XCTAssertEqual(client.cancellationRequests[0].requestID, requestID)
        XCTAssertEqual(client.cancellationRequests[1].challengeID, challengeID)
        XCTAssertEqual(client.cancellationRequests[1].requestID, requestID)
        let cleared = try await cancellationStore.load(for: ownerID)
        XCTAssertNil(cleared)
        XCTAssertNil(relaunchedStore.pendingCancellation)
    }

    func testPendingCancellationIsIsolatedByOwner() async throws {
        let ownerA = UUID(
            uuidString: "11111111-1111-1111-1111-111111111111"
        )!
        let ownerB = UUID(
            uuidString: "99999999-9999-9999-9999-999999999999"
        )!
        let cancellationStore = EphemeralPendingPersonalCancellationStore()
        let submission = try PendingPersonalCancellationSubmission(
            ownerID: ownerA,
            challengeID: UUID(),
            requestID: UUID()
        )
        try await cancellationStore.save(submission)
        let clientB = PersonalClientFake(ownerID: ownerB)
        let storeB = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerB),
            client: clientB,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            pendingCancellationStore: cancellationStore,
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )

        await storeB.activate(ownerID: ownerB)

        XCTAssertNil(storeB.pendingCancellation)
        XCTAssertTrue(clientB.cancellationRequests.isEmpty)
        let ownerASubmission = try await cancellationStore.load(for: ownerA)
        XCTAssertEqual(ownerASubmission?.requestBody, submission.requestBody)
    }

    func testCompletedHealthAuthorizationRetriesBackgroundRegistration()
        async
    {
        let ownerID = UUID()
        let registration = BackgroundDeliveryRegistrationFake()
        let diagnostic = PersonalDiagnosticFake()
        let stepProgress = PersonalStepProgressStore(
            reader: StorePersonalHealthStepReaderFake(),
            cache: EphemeralPersonalStepSnapshotCache(),
            uploader: DisabledPersonalHealthSnapshotUploader()
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: PersonalClientFake(ownerID: ownerID),
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: diagnostic,
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: stepProgress
        )
        store.setBackgroundDeliveryRegistration(registration)
        await store.activate(ownerID: ownerID)

        let connected = await store.verifyHealthAccess(
            timezone: "America/Chicago"
        )

        XCTAssertTrue(connected)
        XCTAssertEqual(store.healthReadiness, .authorizationRequested)
        XCTAssertTrue(store.canCreate)
        XCTAssertEqual(registration.retryCount, 1)
        XCTAssertEqual(diagnostic.authorizationRequestCount, 0)
        XCTAssertEqual(diagnostic.probeCount, 0)
        XCTAssertEqual(diagnostic.diagnosticCount, 0)
    }

    func testUnavailableHealthAuthorizationPresentsAnError() async {
        let ownerID = UUID()
        let stepProgress = PersonalStepProgressStore(
            reader: StorePersonalHealthStepReaderFake(
                authorizationOutcome: .healthDataUnavailable
            ),
            cache: EphemeralPersonalStepSnapshotCache(),
            uploader: DisabledPersonalHealthSnapshotUploader()
        )
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: PersonalClientFake(ownerID: ownerID),
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator(),
            stepProgressStore: stepProgress
        )
        await store.activate(ownerID: ownerID)

        let connected = await store.verifyHealthAccess(
            timezone: "America/Chicago"
        )

        XCTAssertFalse(connected)
        XCTAssertEqual(store.healthReadiness, .unavailable)
        XCTAssertEqual(
            store.presentedError,
            PersonalHealthStepReaderError.unavailable.localizedDescription
        )
    }

    func testActiveTabsExposeOnlyPersonalV1Shell() {
        XCTAssertEqual(AppTab.allCases, [.today, .challenges, .you])
    }

    private func automaticStepProgressStore() -> PersonalStepProgressStore {
        PersonalStepProgressStore(
            reader: StorePersonalHealthStepReaderFake(),
            cache: EphemeralPersonalStepSnapshotCache(),
            uploader: DisabledPersonalHealthSnapshotUploader()
        )
    }

    private func connectHealth(_ store: PersonalAccountabilityStore) async {
        let connected = await store.verifyHealthAccess(
            timezone: "America/Chicago"
        )
        XCTAssertTrue(connected)
    }

    private func makeActivityChallenge(
        ownerID: UUID,
        evidenceCutoff: Date,
        status: PersonalChallengeStatus = .awaitingEvidence
    ) -> PersonalChallengeDetail {
        let challengeID = UUID()
        let start = evidenceCutoff.addingTimeInterval(-8 * 86_400)
        return PersonalChallengeDetail(
            id: challengeID,
            status: status,
            terms: FrozenPersonalTerms(
                challengeID: challengeID,
                userID: ownerID,
                cadence: .daily,
                targetSteps: 10_000,
                commitmentAmountMinor: 1_000,
                currency: "USD",
                settlementMode: .testOnly,
                termsVersion: "personal-v1",
                timezone: "America/Chicago",
                agreementAt: start.addingTimeInterval(-86_400),
                startsAt: start,
                endsAt: evidenceCutoff.addingTimeInterval(-86_400),
                evidenceCutoff: evidenceCutoff,
                closedAt: nil
            ),
            progress: .empty
        )
    }

    private func makeV2LifecycleChallenge(
        ownerID: UUID,
        status: PersonalChallengeStatus,
        totalSteps: Int,
        outcome: PersonalOutcome? = nil,
        challengeID: UUID = UUID(),
        terms suppliedTerms: FrozenPersonalTerms? = nil
    ) -> PersonalChallengeDetail {
        let terms = suppliedTerms ?? makeActivityChallenge(
            ownerID: ownerID,
            evidenceCutoff: Date().addingTimeInterval(3 * 86_400),
            status: status
        ).terms
        let normalizedTerms = FrozenPersonalTerms(
            challengeID: challengeID,
            userID: ownerID,
            cadence: terms.cadence,
            targetSteps: terms.targetSteps,
            commitmentAmountMinor: terms.commitmentAmountMinor,
            currency: terms.currency,
            settlementMode: terms.settlementMode,
            termsVersion: "personal-v2",
            timezone: terms.timezone,
            agreementAt: terms.agreementAt,
            startsAt: terms.startsAt,
            endsAt: terms.endsAt,
            evidenceCutoff: terms.evidenceCutoff,
            closedAt: status.isOpen ? nil : terms.evidenceCutoff
        )
        let base = totalSteps / 7
        let remainder = totalSteps - (base * 7)
        let snapshot = PersonalStepSnapshot(
            challengeID: challengeID,
            termsFingerprint: "lifecycle-v2",
            observedAt: normalizedTerms.evidenceCutoff,
            queryThrough: normalizedTerms.endsAt,
            dailyProgress: (0..<7).map { index in
                PersonalStepSnapshot.Day(
                    localDate: String(format: "2026-08-%02d", index + 3),
                    totalSteps: base + (index == 0 ? remainder : 0)
                )
            }
        )
        return PersonalChallengeDetail(
            id: challengeID,
            status: status,
            terms: normalizedTerms,
            progress: .empty,
            outcome: outcome,
            stepDataPolicy: .healthKitNonmanualDailyV1,
            termsFingerprint: "lifecycle-v2",
            serverStepSnapshot: snapshot,
            snapshotUpdatedAt: snapshot.observedAt
        )
    }
}

@MainActor
final class PersonalActivitySyncCoordinatorTests: XCTestCase {
    func testV2RetirementDeletesCoverageAndMetricRetries() async throws {
        let metrics = SequencedActivitySyncFake(
            pendingCount: 2,
            outcomes: [],
            pendingCountsAfterSync: []
        )
        let pendingCoverage = EphemeralPendingPersonalCoverageStore()
        try await pendingCoverage.save(savedCoverageSubmission())
        let coordinator = PersonalActivitySyncCoordinator(
            activity: PersonalCoverageQueryFake(),
            metrics: metrics,
            coverage: PersonalCoverageClientFake(),
            pendingCoverage: pendingCoverage
        )

        try await coordinator.retirePendingUploads(
            for: ownerID,
            challengeID: savedCoverageSubmission().challengeID
        )

        let remainingCoverage = await pendingCoverage.load(for: ownerID)
        XCTAssertNil(remainingCoverage)
        XCTAssertEqual(
            metrics.retiredContexts,
            [.init(ownerID: ownerID, contestID: savedCoverageSubmission().challengeID)]
        )
        let remainingMetrics = try await metrics.pendingUploadCount(for: ownerID)
        XCTAssertEqual(remainingMetrics, 0)
    }

    func testQueuedMetricRetryNeverPublishesCoverage() async throws {
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [.queuedForRetry(stepTotal: 321)],
            pendingCountsAfterSync: [1]
        )
        let activity = PersonalCoverageQueryFake()
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: activity,
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: EphemeralPendingPersonalCoverageStore()
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: activeChallenge,
            asOf: asOf
        )

        XCTAssertEqual(outcome, .queuedForRetry(stepTotal: 321))
        XCTAssertEqual(metrics.syncCallCount, 1)
        XCTAssertEqual(activity.queryCount, 0)
        XCTAssertEqual(coverage.prepareCount, 0)
        XCTAssertTrue(coverage.sentSubmissions.isEmpty)
    }

    func testUnreadableMetricPassNeverPublishesCoverage() async throws {
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [.noReadableData],
            pendingCountsAfterSync: [0]
        )
        let activity = PersonalCoverageQueryFake(
            intervalStarts: [asOf.addingTimeInterval(-3_600)]
        )
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: activity,
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: EphemeralPendingPersonalCoverageStore()
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: activeChallenge,
            asOf: asOf
        )

        XCTAssertEqual(outcome, .noReadableData)
        XCTAssertEqual(activity.queryCount, 0)
        XCTAssertEqual(coverage.prepareCount, 0)
        XCTAssertTrue(coverage.sentSubmissions.isEmpty)
    }

    func testStalePendingMetricIsFlushedThenFreshlyQueriedBeforeCoverage()
        async throws
    {
        let metrics = SequencedActivitySyncFake(
            pendingCount: 1,
            outcomes: [
                .synced(replayed: true, stepTotal: 100),
                .synced(replayed: false, stepTotal: 250),
            ],
            pendingCountsAfterSync: [0, 0]
        )
        let activity = PersonalCoverageQueryFake(
            intervalStarts: [asOf.addingTimeInterval(-3_600)]
        )
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: activity,
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: EphemeralPendingPersonalCoverageStore()
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: activeChallenge,
            asOf: asOf
        )

        XCTAssertEqual(
            outcome,
            .synced(replayed: false, stepTotal: 250)
        )
        XCTAssertEqual(metrics.syncCallCount, 2)
        XCTAssertEqual(metrics.pendingCountReadCount, 3)
        XCTAssertEqual(activity.queryCount, 1)
        XCTAssertEqual(coverage.prepareCount, 1)
        XCTAssertEqual(coverage.sentSubmissions.count, 1)
    }

    func testSavedCoverageRetryKeepsSignedBytesExactly() async throws {
        let pendingStore = EphemeralPendingPersonalCoverageStore()
        let exactBody = Data(
            #"{"challengeId":"22222222-2222-2222-2222-222222222222","clientCoverageId":"33333333-3333-3333-3333-333333333333","coveredIntervalStarts":["2026-08-03T01:00:00.000Z"],"observedAt":"2026-08-03T02:00:00.000Z"}"#.utf8
        )
        let exactAssertion = Data([0x01, 0x02, 0x03, 0x04])
        let saved = PendingPersonalCoverageSubmission(
            ownerID: ownerID,
            challengeID: activeChallenge.id,
            clientCoverageID: UUID(
                uuidString: "33333333-3333-3333-3333-333333333333"
            )!,
            body: exactBody,
            keyID: "saved-key",
            assertion: exactAssertion,
            createdAt: asOf.addingTimeInterval(-300),
            attemptCount: 0,
            lastAttemptAt: nil
        )
        try await pendingStore.save(saved)
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [.synced(replayed: false, stepTotal: 250)],
            pendingCountsAfterSync: [0]
        )
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: PersonalCoverageQueryFake(
                intervalStarts: [asOf.addingTimeInterval(-3_600)]
            ),
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingStore
        )

        _ = try await coordinator.sync(
            ownerID: ownerID,
            challenge: activeChallenge,
            asOf: asOf
        )

        let retried = try XCTUnwrap(coverage.sentSubmissions.first)
        XCTAssertEqual(retried.body, exactBody)
        XCTAssertEqual(retried.keyID, "saved-key")
        XCTAssertEqual(retried.assertion, exactAssertion)
        XCTAssertEqual(retried.attemptCount, 1)
    }

    func testLegacyCoverageAddsDevelopmentMarkerWithoutChangingSignedBytes()
        async throws
    {
        let pendingStore = EphemeralPendingPersonalCoverageStore()
        let saved = savedCoverageSubmission()
        try await pendingStore.save(saved)
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [],
            pendingCountsAfterSync: []
        )
        let coverage = PersonalCoverageClientFake(
            retryEnvironment: .development,
            sendError: .unavailable
        )
        let coordinator = PersonalActivitySyncCoordinator(
            activity: PersonalCoverageQueryFake(),
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingStore
        )
        let expiredChallenge = makeChallenge(
            status: .awaitingEvidence,
            evidenceCutoff: asOf
        )

        do {
            _ = try await coordinator.sync(
                ownerID: ownerID,
                challenge: expiredChallenge,
                asOf: asOf
            )
            XCTFail("Expected the first network attempt to remain queued.")
        } catch {
            XCTAssertEqual(error as? PersonalCoverageError, .unavailable)
        }

        let persistedValue = await pendingStore.load(for: ownerID)
        let persisted = try XCTUnwrap(persistedValue)
        XCTAssertEqual(persisted.body, saved.body)
        XCTAssertEqual(persisted.keyID, saved.keyID)
        XCTAssertEqual(persisted.assertion, saved.assertion)
        XCTAssertEqual(persisted.attestEnvironment, .development)
        XCTAssertEqual(persisted.attemptCount, 1)

        coverage.sendError = nil
        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: expiredChallenge,
            asOf: asOf
        )

        XCTAssertEqual(outcome, .savedRequestAccepted)
        XCTAssertEqual(coverage.sentSubmissions.last?.body, saved.body)
        XCTAssertEqual(
            coverage.sentSubmissions.last?.assertion,
            saved.assertion
        )
        let remaining = await pendingStore.load(for: ownerID)
        XCTAssertNil(remaining)
    }

    func testWrongCoverageReceiptKeepsTheExactSavedRequest() async throws {
        let pendingStore = EphemeralPendingPersonalCoverageStore()
        let saved = savedCoverageSubmission(environment: .development)
        try await pendingStore.save(saved)
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [],
            pendingCountsAfterSync: []
        )
        let activity = PersonalCoverageQueryFake()
        let coverage = PersonalCoverageClientFake(
            receiptBatchID: UUID()
        )
        let coordinator = PersonalActivitySyncCoordinator(
            activity: activity,
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingStore
        )

        do {
            _ = try await coordinator.sync(
                ownerID: ownerID,
                challenge: activeChallenge,
                asOf: asOf
            )
            XCTFail("Expected a mismatched receipt to fail closed.")
        } catch {
            XCTAssertEqual(
                error as? PersonalCoverageError,
                .invalidResponse
            )
        }

        let retainedValue = await pendingStore.load(for: ownerID)
        let retained = try XCTUnwrap(retainedValue)
        XCTAssertEqual(retained.body, saved.body)
        XCTAssertEqual(retained.keyID, saved.keyID)
        XCTAssertEqual(retained.assertion, saved.assertion)
        XCTAssertEqual(retained.attestEnvironment, .development)
        XCTAssertEqual(activity.queryCount, 0)
    }

    func testPendingMetricReplaysAfterCutoffWithoutAFreshRead() async throws {
        let metrics = SequencedActivitySyncFake(
            pendingCount: 1,
            outcomes: [.synced(replayed: true, stepTotal: 123)],
            pendingCountsAfterSync: [0]
        )
        let activity = PersonalCoverageQueryFake(
            intervalStarts: [asOf.addingTimeInterval(-3_600)]
        )
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: activity,
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: EphemeralPendingPersonalCoverageStore()
        )
        let expiredChallenge = makeChallenge(
            status: .awaitingEvidence,
            evidenceCutoff: asOf
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: expiredChallenge,
            asOf: asOf
        )

        XCTAssertEqual(
            outcome,
            .synced(replayed: true, stepTotal: 123)
        )
        XCTAssertEqual(metrics.syncCallCount, 1)
        XCTAssertEqual(activity.queryCount, 0)
        XCTAssertEqual(coverage.prepareCount, 0)
        XCTAssertTrue(coverage.sentSubmissions.isEmpty)
    }

    func testProductionReReadsInsteadOfPromotingDevelopmentCoverage()
        async throws
    {
        let pendingStore = EphemeralPendingPersonalCoverageStore()
        try await pendingStore.save(
            savedCoverageSubmission(environment: .development)
        )
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [.synced(replayed: false, stepTotal: 250)],
            pendingCountsAfterSync: [0]
        )
        let activity = PersonalCoverageQueryFake(
            intervalStarts: [asOf.addingTimeInterval(-3_600)]
        )
        let coverage = PersonalCoverageClientFake(
            retryEnvironment: .production
        )
        let coordinator = PersonalActivitySyncCoordinator(
            activity: activity,
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingStore
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: activeChallenge,
            asOf: asOf
        )

        XCTAssertEqual(
            outcome,
            .synced(replayed: false, stepTotal: 250)
        )
        XCTAssertEqual(metrics.syncCallCount, 1)
        XCTAssertEqual(activity.queryCount, 1)
        XCTAssertEqual(coverage.sentSubmissions.count, 1)
        XCTAssertEqual(
            coverage.sentSubmissions.first?.attestEnvironment,
            .production
        )
        let remaining = await pendingStore.load(for: ownerID)
        XCTAssertNil(remaining)
    }

    func testProductionDoesNotPromoteDevelopmentCoverageAfterCutoff()
        async throws
    {
        let pendingStore = EphemeralPendingPersonalCoverageStore()
        try await pendingStore.save(
            savedCoverageSubmission(environment: .development)
        )
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [],
            pendingCountsAfterSync: []
        )
        let activity = PersonalCoverageQueryFake()
        let coverage = PersonalCoverageClientFake(
            retryEnvironment: .production
        )
        let coordinator = PersonalActivitySyncCoordinator(
            activity: activity,
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingStore
        )
        let expiredChallenge = makeChallenge(
            status: .awaitingEvidence,
            evidenceCutoff: asOf
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: expiredChallenge,
            asOf: asOf
        )

        XCTAssertEqual(outcome, .savedRequestUnavailable)
        XCTAssertEqual(metrics.syncCallCount, 0)
        XCTAssertEqual(activity.queryCount, 0)
        XCTAssertTrue(coverage.sentSubmissions.isEmpty)
        let remaining = await pendingStore.load(for: ownerID)
        XCTAssertNil(remaining)
    }

    func testSavedCoverageReplaysAfterCutoffWithoutReportingFailure()
        async throws
    {
        let pendingStore = EphemeralPendingPersonalCoverageStore()
        let saved = savedCoverageSubmission()
        try await pendingStore.save(saved)
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [],
            pendingCountsAfterSync: []
        )
        let activity = PersonalCoverageQueryFake(
            intervalStarts: [asOf.addingTimeInterval(-3_600)]
        )
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: activity,
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingStore
        )
        let expiredChallenge = makeChallenge(
            status: .awaitingEvidence,
            evidenceCutoff: asOf
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: expiredChallenge,
            asOf: asOf
        )

        XCTAssertEqual(outcome, .savedRequestAccepted)
        XCTAssertEqual(metrics.syncCallCount, 0)
        XCTAssertEqual(activity.queryCount, 0)
        XCTAssertEqual(coverage.prepareCount, 0)
        XCTAssertEqual(coverage.sentSubmissions.first?.body, saved.body)
        let pendingAfterReplay = await pendingStore.load(for: ownerID)
        XCTAssertNil(pendingAfterReplay)
    }

    func testSavedCoverageClearsBeforeAFreshUnreadableMetricPass()
        async throws
    {
        let pendingStore = EphemeralPendingPersonalCoverageStore()
        let saved = savedCoverageSubmission()
        try await pendingStore.save(saved)
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [.noReadableData],
            pendingCountsAfterSync: [0]
        )
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: PersonalCoverageQueryFake(),
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingStore
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: activeChallenge,
            asOf: asOf
        )

        XCTAssertEqual(outcome, .noReadableData)
        XCTAssertEqual(metrics.syncCallCount, 1)
        XCTAssertEqual(coverage.sentSubmissions.first?.body, saved.body)
        XCTAssertEqual(coverage.prepareCount, 0)
        let pendingAfterFreshAttempt = await pendingStore.load(for: ownerID)
        XCTAssertNil(pendingAfterFreshAttempt)
    }

    func testMetricStillWaitingBlocksSavedCoverageReplay() async throws {
        let pendingStore = EphemeralPendingPersonalCoverageStore()
        let saved = savedCoverageSubmission()
        try await pendingStore.save(saved)
        let metrics = SequencedActivitySyncFake(
            pendingCount: 1,
            outcomes: [.synced(replayed: true, stepTotal: 321)],
            pendingCountsAfterSync: [1]
        )
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: PersonalCoverageQueryFake(),
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingStore
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: activeChallenge,
            asOf: asOf
        )

        XCTAssertEqual(outcome, .queuedForRetry(stepTotal: 321))
        XCTAssertTrue(coverage.sentSubmissions.isEmpty)
        let pendingAfterBlockedReplay = await pendingStore.load(for: ownerID)
        XCTAssertEqual(pendingAfterBlockedReplay, saved)
    }

    func testGracePeriodAllowsFinalManualSync() async throws {
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [.synced(replayed: false, stepTotal: 777)],
            pendingCountsAfterSync: [0]
        )
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: PersonalCoverageQueryFake(
                intervalStarts: [asOf.addingTimeInterval(-3_600)]
            ),
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: EphemeralPendingPersonalCoverageStore()
        )
        let graceChallenge = makeChallenge(
            status: .awaitingEvidence,
            evidenceCutoff: asOf.addingTimeInterval(60)
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: graceChallenge,
            asOf: asOf
        )

        XCTAssertEqual(
            outcome,
            .synced(replayed: false, stepTotal: 777)
        )
        XCTAssertEqual(coverage.sentSubmissions.count, 1)
    }

    func testFreshCoverageRejectionPreparesANewProofAndRetriesOnce()
        async throws
    {
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [.synced(replayed: false, stepTotal: 12_349)],
            pendingCountsAfterSync: [0]
        )
        let pendingCoverage = EphemeralPendingPersonalCoverageStore()
        let coverage = PersonalCoverageClientFake(
            sendErrors: [.attestationRejected, nil]
        )
        let coordinator = PersonalActivitySyncCoordinator(
            activity: PersonalCoverageQueryFake(
                intervalStarts: [asOf.addingTimeInterval(-3_600)]
            ),
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingCoverage
        )

        let outcome = try await coordinator.sync(
            ownerID: ownerID,
            challenge: activeChallenge,
            asOf: asOf
        )

        XCTAssertEqual(
            outcome,
            .synced(replayed: false, stepTotal: 12_349)
        )
        XCTAssertEqual(metrics.syncCallCount, 1)
        XCTAssertEqual(coverage.prepareCount, 2)
        XCTAssertEqual(coverage.sentSubmissions.count, 2)
        XCTAssertNotEqual(
            coverage.sentSubmissions[0].clientCoverageID,
            coverage.sentSubmissions[1].clientCoverageID
        )
        XCTAssertNotEqual(
            coverage.sentSubmissions[0].body,
            coverage.sentSubmissions[1].body
        )
        let remaining = await pendingCoverage.load(for: ownerID)
        XCTAssertNil(remaining)
    }

    func testRepeatedFreshCoverageRejectionRemainsACurrentFailure()
        async throws
    {
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [.synced(replayed: false, stepTotal: 12_349)],
            pendingCountsAfterSync: [0]
        )
        let pendingCoverage = EphemeralPendingPersonalCoverageStore()
        let coverage = PersonalCoverageClientFake(
            sendErrors: [.attestationRejected, .attestationRejected]
        )
        let coordinator = PersonalActivitySyncCoordinator(
            activity: PersonalCoverageQueryFake(
                intervalStarts: [asOf.addingTimeInterval(-3_600)]
            ),
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: pendingCoverage
        )

        do {
            _ = try await coordinator.sync(
                ownerID: ownerID,
                challenge: activeChallenge,
                asOf: asOf
            )
            XCTFail("Expected the second current proof to be rejected.")
        } catch {
            XCTAssertEqual(
                error as? PersonalCoverageError,
                .attestationRejected
            )
        }

        XCTAssertEqual(coverage.prepareCount, 2)
        XCTAssertEqual(coverage.sentSubmissions.count, 2)
        let remaining = await pendingCoverage.load(for: ownerID)
        XCTAssertNil(remaining)
    }

    func testSyncAfterEvidenceCutoffIsRejectedBeforeMetricRead() async {
        let metrics = SequencedActivitySyncFake(
            pendingCount: 0,
            outcomes: [.synced(replayed: false, stepTotal: 777)],
            pendingCountsAfterSync: [0]
        )
        let coverage = PersonalCoverageClientFake()
        let coordinator = PersonalActivitySyncCoordinator(
            activity: PersonalCoverageQueryFake(
                intervalStarts: [asOf.addingTimeInterval(-3_600)]
            ),
            metrics: metrics,
            coverage: coverage,
            pendingCoverage: EphemeralPendingPersonalCoverageStore()
        )
        let expiredChallenge = makeChallenge(
            status: .awaitingEvidence,
            evidenceCutoff: asOf
        )

        do {
            _ = try await coordinator.sync(
                ownerID: ownerID,
                challenge: expiredChallenge,
                asOf: asOf
            )
            XCTFail("Expected the cutoff guard to reject the sync.")
        } catch {
            XCTAssertEqual(
                error as? ActivitySyncError,
                .challengeNotEligible
            )
        }
        XCTAssertEqual(metrics.syncCallCount, 0)
        XCTAssertTrue(coverage.sentSubmissions.isEmpty)
    }

    private var ownerID: UUID {
        UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    }

    private var asOf: Date {
        Date(timeIntervalSince1970: 1_785_889_800)
    }

    private var activeChallenge: PersonalChallengeDetail {
        makeChallenge(
            status: .active,
            evidenceCutoff: asOf.addingTimeInterval(7 * 86_400)
        )
    }

    private func makeChallenge(
        status: PersonalChallengeStatus,
        evidenceCutoff: Date
    ) -> PersonalChallengeDetail {
        let challengeID = UUID(
            uuidString: "22222222-2222-2222-2222-222222222222"
        )!
        let start = asOf.addingTimeInterval(-7_200)
        let end = start.addingTimeInterval(7 * 86_400)
        return PersonalChallengeDetail(
            id: challengeID,
            status: status,
            terms: FrozenPersonalTerms(
                challengeID: challengeID,
                userID: ownerID,
                cadence: .daily,
                targetSteps: 10_000,
                commitmentAmountMinor: 1_000,
                currency: "USD",
                settlementMode: .testOnly,
                termsVersion: "personal-v1",
                timezone: "America/Chicago",
                agreementAt: start.addingTimeInterval(-86_400),
                startsAt: start,
                endsAt: end,
                evidenceCutoff: evidenceCutoff,
                closedAt: nil
            ),
            progress: .empty
        )
    }

    private func savedCoverageSubmission(
        environment: AppAttestEnvironment? = nil
    )
        -> PendingPersonalCoverageSubmission
    {
        let clientCoverageID = UUID(
            uuidString: "33333333-3333-3333-3333-333333333333"
        )!
        return PendingPersonalCoverageSubmission(
            ownerID: ownerID,
            challengeID: activeChallenge.id,
            clientCoverageID: clientCoverageID,
            body: Data(
                #"{"challengeId":"22222222-2222-2222-2222-222222222222","clientCoverageId":"33333333-3333-3333-3333-333333333333","coveredIntervalStarts":["2026-08-03T01:00:00.000Z"],"observedAt":"2026-08-03T02:00:00.000Z"}"#.utf8
            ),
            keyID: "saved-key",
            assertion: Data([0x01, 0x02, 0x03, 0x04]),
            attestEnvironment: environment,
            createdAt: asOf.addingTimeInterval(-300),
            attemptCount: 0,
            lastAttemptAt: nil
        )
    }
}

@MainActor
final class PersonalHealthBackgroundDeliveryTests: XCTestCase {
    func testPhysicalAppEnvironmentsStartHealthObserver() {
        let arguments = ["GameTime"]
        let environment: [String: String] = [:]
        XCTAssertTrue(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Debug",
                arguments: arguments,
                processEnvironment: environment,
                isSimulator: false
            )
        )
        XCTAssertTrue(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Staging",
                arguments: arguments,
                processEnvironment: environment,
                isSimulator: false
            )
        )
        XCTAssertTrue(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Release",
                arguments: arguments,
                processEnvironment: environment,
                isSimulator: false
            )
        )
        XCTAssertFalse(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: nil,
                arguments: arguments,
                processEnvironment: environment,
                isSimulator: false
            )
        )
    }

    func testSimulatorFixtureAndUITestNeverStartHealthObserver() {
        XCTAssertFalse(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Release",
                arguments: ["GameTime"],
                processEnvironment: [:],
                isSimulator: true
            )
        )
        XCTAssertFalse(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Release",
                arguments: ["GameTime", "--fixture-mode"],
                processEnvironment: [:],
                isSimulator: false
            )
        )
        XCTAssertFalse(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Release",
                arguments: ["GameTime"],
                processEnvironment: [
                    "XCTestConfigurationFilePath": "/tmp/GameTime.xctestconfiguration"
                ],
                isSimulator: false
            )
        )
        XCTAssertFalse(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Release",
                arguments: ["GameTime"],
                processEnvironment: ["XCTestBundlePath": "/tmp/GameTimeUITests.xctest"],
                isSimulator: false
            )
        )
    }

    func testObserverCompletionRunsAfterPersonalSyncHandler() async {
        let coordinator = PersonalHealthBackgroundDeliveryCoordinator()
        var events: [String] = []
        await coordinator.setUpdateHandler {
            events.append("sync")
        }

        await coordinator.receiveUpdate(hadError: false) {
            events.append("completion")
        }

        XCTAssertEqual(events, ["sync", "completion"])
    }

    func testObserverErrorCompletesWithoutRunningSyncHandler() async {
        let coordinator = PersonalHealthBackgroundDeliveryCoordinator()
        var events: [String] = []
        await coordinator.setUpdateHandler {
            events.append("sync")
        }

        await coordinator.receiveUpdate(hadError: true) {
            events.append("completion")
        }

        XCTAssertEqual(events, ["completion"])
    }

    func testLaunchOrderWakeIsBufferedUntilHandlerIsReady() async {
        let coordinator = PersonalHealthBackgroundDeliveryCoordinator()
        var events: [String] = []

        await coordinator.receiveUpdate(hadError: false) {
            events.append("completion")
        }
        XCTAssertTrue(events.isEmpty)

        await coordinator.setUpdateHandler {
            events.append("sync")
        }

        XCTAssertEqual(events, ["sync", "completion"])
    }

    func testEnablementRetriesAfterFirstAuthorizationFailure() {
        let coordinator = RetryableBackgroundDeliveryCoordinator(
            enableResults: [false, true]
        )

        coordinator.start()
        XCTAssertEqual(coordinator.observerInstallCount, 1)
        XCTAssertEqual(coordinator.enableRequestCount, 1)
        XCTAssertFalse(coordinator.isBackgroundDeliveryEnabled)

        coordinator.retryRegistration()
        XCTAssertEqual(coordinator.observerInstallCount, 1)
        XCTAssertEqual(coordinator.enableRequestCount, 2)
        XCTAssertTrue(coordinator.isBackgroundDeliveryEnabled)
    }
}

private actor CountingPendingPersonalChallengeStore:
    PendingPersonalChallengeStore
{
    private var submission: PendingPersonalChallengeSubmission?
    private(set) var loadCallCount = 0

    func load(for ownerID: UUID) throws
        -> PendingPersonalChallengeSubmission?
    {
        loadCallCount += 1
        try submission?.validate(for: ownerID)
        return submission
    }

    func save(_ submission: PendingPersonalChallengeSubmission) throws {
        try submission.validate(for: submission.ownerID)
        self.submission = submission
    }

    func remove(for ownerID: UUID) {
        guard submission?.ownerID == ownerID else { return }
        submission = nil
    }
}

private actor CountingPendingPersonalCancellationStore:
    PendingPersonalCancellationStore
{
    private var submission: PendingPersonalCancellationSubmission?
    private(set) var loadCallCount = 0

    func load(for ownerID: UUID) throws
        -> PendingPersonalCancellationSubmission?
    {
        loadCallCount += 1
        try submission?.validate(for: ownerID)
        return submission
    }

    func save(_ submission: PendingPersonalCancellationSubmission) throws {
        try submission.validate(for: submission.ownerID)
        self.submission = submission
    }

    func remove(for ownerID: UUID) {
        guard submission?.ownerID == ownerID else { return }
        submission = nil
    }
}

@MainActor
private final class PersonalAuthFake: AuthClient {
    var ownerID: UUID?

    init(ownerID: UUID?) {
        self.ownerID = ownerID
    }

    func currentUserID() async -> UUID? { ownerID }

    func authStateChanges() async -> AsyncStream<AuthSnapshot> {
        AsyncStream { continuation in continuation.finish() }
    }

    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID {
        _ = identity
        guard let ownerID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        return ownerID
    }

    func signOut() async throws { ownerID = nil }
}

@MainActor
private final class PersonalClientFake: PersonalAccountabilityClient {
    let ownerID: UUID
    let createdChallengeID = UUID(
        uuidString: "18181818-1818-1818-1818-181818181818"
    )!
    var requests: [PersonalChallengeCreationRequest] = []
    var loseFirstResponse = false
    var loseFirstCancellationResponse = false
    var hold: PersonalEligibilityHold?
    var listError: PersonalAccountabilityClientError?
    private(set) var listCallCount = 0
    private(set) var cancellationRequests:
        [(challengeID: UUID, requestID: UUID)] = []
    private var challenge: PersonalChallengeDetail?
    private var shouldSuspendNextListResponse = false
    private var suspendedListResponseStarted = false
    private var suspendedListResponseReleased = false
    private var suspendedListStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var suspendedListReleaseWaiters:
        [CheckedContinuation<Void, Never>] = []

    init(ownerID: UUID) {
        self.ownerID = ownerID
    }

    func setChallenge(_ challenge: PersonalChallengeDetail) {
        self.challenge = challenge
    }

    func listMyChallenges() async throws -> PersonalAccountabilitySnapshot {
        listCallCount += 1
        if let listError { throw listError }
        let snapshot = PersonalAccountabilitySnapshot(
            challenges: challenge.map {
                [
                    PersonalChallengeSummary(
                        id: $0.id,
                        status: $0.status,
                        terms: $0.terms,
                        progress: $0.progress,
                        outcome: $0.outcome,
                        stepDataPolicy: $0.stepDataPolicy,
                        termsFingerprint: $0.termsFingerprint,
                        serverStepSnapshot: $0.serverStepSnapshot,
                        snapshotUpdatedAt: $0.snapshotUpdatedAt,
                        commitmentWaived: $0.commitmentWaived
                    )
                ]
            } ?? [],
            latestDiagnostic: trustedDiagnostic,
            eligibilityHold: hold
        )
        if shouldSuspendNextListResponse {
            shouldSuspendNextListResponse = false
            suspendedListResponseStarted = true
            let startWaiters = suspendedListStartWaiters
            suspendedListStartWaiters.removeAll()
            for waiter in startWaiters {
                waiter.resume()
            }
            if !suspendedListResponseReleased {
                await withCheckedContinuation { continuation in
                    suspendedListReleaseWaiters.append(continuation)
                }
            }
        }
        return snapshot
    }

    func suspendNextListResponse() {
        shouldSuspendNextListResponse = true
        suspendedListResponseStarted = false
        suspendedListResponseReleased = false
    }

    func waitUntilListResponseSuspends() async {
        guard !suspendedListResponseStarted else { return }
        await withCheckedContinuation { continuation in
            suspendedListStartWaiters.append(continuation)
        }
    }

    func resumeSuspendedListResponse() {
        suspendedListResponseReleased = true
        let releaseWaiters = suspendedListReleaseWaiters
        suspendedListReleaseWaiters.removeAll()
        for waiter in releaseWaiters {
            waiter.resume()
        }
    }

    func challenge(id: UUID) async throws -> PersonalChallengeDetail? {
        challenge?.id == id ? challenge : nil
    }

    func create(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> UUID {
        guard expectedUserID == ownerID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        requests.append(request)
        if challenge == nil {
            challenge = makeChallenge(request)
        }
        if loseFirstResponse, requests.count == 1 {
            throw PersonalAccountabilityClientError.unavailable
        }
        return createdChallengeID
    }

    func cancel(
        challengeID: UUID,
        requestID: UUID,
        expectedUserID: UUID
    ) async throws {
        guard expectedUserID == ownerID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        cancellationRequests.append((challengeID, requestID))
        if let challenge, challenge.id == challengeID,
            challenge.status == .scheduled
        {
            self.challenge = PersonalChallengeDetail(
                id: challenge.id,
                status: .cancelled,
                terms: challenge.terms,
                progress: challenge.progress,
                outcome: challenge.outcome
            )
        }
        if loseFirstCancellationResponse,
            cancellationRequests.count == 1
        {
            throw PersonalAccountabilityClientError.unavailable
        }
    }

    private var trustedDiagnostic: TrustedActivityDiagnostic {
        TrustedActivityDiagnostic(
            id: UUID(),
            status: .trusted,
            performedAt: Date(),
            trustedQueriedHourCount: 24,
            positiveTrustedSampleCount: 1,
            clearsEligibilityHold: false
        )
    }

    private func makeChallenge(
        _ request: PersonalChallengeCreationRequest
    ) -> PersonalChallengeDetail {
        let start = Date().addingTimeInterval(3_600)
        let end = start.addingTimeInterval(7 * 86_400)
        return PersonalChallengeDetail(
            id: createdChallengeID,
            status: .scheduled,
            terms: FrozenPersonalTerms(
                challengeID: createdChallengeID,
                userID: ownerID,
                cadence: request.cadence,
                targetSteps: request.targetSteps,
                commitmentAmountMinor: request.commitmentAmountMinor,
                currency: "USD",
                settlementMode: .testOnly,
                termsVersion: "personal-v1",
                timezone: request.timezone,
                agreementAt: Date(),
                startsAt: start,
                endsAt: end,
                evidenceCutoff: end.addingTimeInterval(86_400),
                closedAt: nil
            ),
            progress: .empty
        )
    }
}

@MainActor
private final class PersonalPaymentFake: PersonalPaymentClient {
    let ownerID: UUID
    let setupID = "33333333-3333-3333-3333-333333333333"
    let publishableKey = "pk_test_fixture"
    let setupIntentClientSecret = "seti_fixture_secret_fixture"
    let challengeID = UUID(
        uuidString: "44444444-4444-4444-4444-444444444444"
    )!
    var preparedRequests: [PersonalChallengeCreationRequest] = []
    var committedRequests: [PersonalChallengeCreationRequest] = []
    var reviewRequests: [
        (challengeID: UUID, reason: PersonalReviewReason)
    ] = []
    var loseFirstCommitResponse = false
    var loseFirstReviewResponse = false

    init(ownerID: UUID) {
        self.ownerID = ownerID
    }

    func prepare(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> PersonalPaymentSetup {
        guard expectedUserID == ownerID else {
            throw PersonalPaymentClientError.accountChanged
        }
        preparedRequests.append(request)
        return PersonalPaymentSetup(
            setupID: setupID,
            presentation: .paymentSheet(
                publishableKey: publishableKey,
                setupIntentClientSecret: setupIntentClientSecret
            )
        )
    }

    func commit(
        _ request: PersonalChallengeCreationRequest,
        setupID: String,
        expectedUserID: UUID
    ) async throws -> UUID {
        guard expectedUserID == ownerID else {
            throw PersonalPaymentClientError.accountChanged
        }
        guard setupID == self.setupID else {
            throw PersonalPaymentClientError.termsChanged
        }
        committedRequests.append(request)
        if loseFirstCommitResponse, committedRequests.count == 1 {
            throw PersonalPaymentClientError.unavailable
        }
        return challengeID
    }

    func requestReview(
        challengeID: UUID,
        reason: PersonalReviewReason,
        expectedUserID: UUID
    ) async throws -> PersonalReviewRequestResult {
        guard expectedUserID == ownerID else {
            throw PersonalPaymentClientError.accountChanged
        }
        reviewRequests.append((challengeID, reason))
        if loseFirstReviewResponse, reviewRequests.count == 1 {
            throw PersonalPaymentClientError.unavailable
        }
        return PersonalReviewRequestResult(
            state: .underReview,
            reviewDeadline: Date().addingTimeInterval(7 * 86_400),
            replayed: reviewRequests.count > 1
        )
    }
}

@MainActor
private final class PersonalDiagnosticFake: TrustedActivityDiagnosticClient {
    private(set) var authorizationRequestCount = 0
    private(set) var probeCount = 0
    private(set) var diagnosticCount = 0

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        authorizationRequestCount += 1
        return .requestCompleted
    }

    func probeLocalStepAccess(
        timezone: String
    ) async throws -> LocalStepAccessProbe {
        _ = timezone
        probeCount += 1
        return LocalStepAccessProbe(
            trustedHourCount: 24,
            positiveTrustedSampleCount: 1,
            observedAt: Date()
        )
    }

    func runTrustedDiagnostic(
        ownerID: UUID,
        timezone: String
    ) async throws -> TrustedActivityDiagnostic {
        _ = (ownerID, timezone)
        diagnosticCount += 1
        return TrustedActivityDiagnostic(
            id: UUID(),
            status: .trusted,
            performedAt: Date(),
            trustedQueriedHourCount: 24,
            positiveTrustedSampleCount: 1,
            clearsEligibilityHold: false
        )
    }
}

@MainActor
private final class BackgroundDeliveryRegistrationFake:
    PersonalHealthBackgroundDeliveryRegistering
{
    private(set) var retryCount = 0

    func retryRegistration() {
        retryCount += 1
    }
}

@MainActor
private final class StorePersonalHealthStepReaderFake:
    PersonalHealthStepReading
{
    private(set) var readCount = 0
    private let authorizationOutcome: ActivityAuthorizationOutcome

    init(
        authorizationOutcome: ActivityAuthorizationOutcome = .requestCompleted
    ) {
        self.authorizationOutcome = authorizationOutcome
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        authorizationOutcome
    }

    func readSnapshot(
        challengeID: UUID,
        terms: FrozenPersonalTerms,
        termsFingerprint: String,
        observedAt: Date
    ) async throws -> PersonalStepSnapshot {
        readCount += 1
        let plan = try PersonalHealthSnapshotPlanner.plan(
            terms: terms,
            observedAt: observedAt
        )
        return PersonalStepSnapshot(
            challengeID: challengeID,
            termsFingerprint: termsFingerprint,
            observedAt: observedAt,
            queryThrough: plan.queryThrough,
            dailyProgress: plan.days.map {
                PersonalStepSnapshot.Day(
                    localDate: $0.localDate,
                    totalSteps: readCount
                )
            }
        )
    }
}

@MainActor
private final class StorePersonalActivitySyncFake: PersonalActivitySyncing {
    struct RetiredContext: Equatable {
        let ownerID: UUID
        let challengeID: UUID
    }

    enum Result {
        case outcome(ActivitySyncOutcome, pendingAfter: Int)
        case cancellation(pendingAfter: Int)
    }

    private var pendingCount: Int
    private let queuedChallengeID: UUID?
    private var results: [Result]
    private var pendingCountError: (any Error)?
    private(set) var syncedChallengeIDs: [UUID] = []
    private(set) var pendingCountReadCount = 0
    private(set) var retiredContexts: [RetiredContext] = []
    private var shouldBlockNextPendingCountRead: Bool
    private var pendingCountReadStarted = false
    private var pendingCountReadReleased = false
    private var pendingCountStartWaiters:
        [CheckedContinuation<Void, Never>] = []
    private var pendingCountReleaseWaiters:
        [CheckedContinuation<Void, Never>] = []

    init(
        pendingCount: Int,
        pendingChallengeID: UUID?,
        results: [Result],
        pendingCountError: (any Error)? = nil,
        blocksNextPendingCountRead: Bool = false
    ) {
        self.pendingCount = pendingCount
        queuedChallengeID = pendingChallengeID
        self.results = results
        self.pendingCountError = pendingCountError
        shouldBlockNextPendingCountRead = blocksNextPendingCountRead
    }

    func setPendingCountError(_ error: (any Error)?) {
        pendingCountError = error
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        .requestCompleted
    }

    func pendingUploadCount(for ownerID: UUID) async throws -> Int {
        _ = ownerID
        pendingCountReadCount += 1
        if shouldBlockNextPendingCountRead {
            shouldBlockNextPendingCountRead = false
            pendingCountReadStarted = true
            let startWaiters = pendingCountStartWaiters
            pendingCountStartWaiters.removeAll()
            for waiter in startWaiters {
                waiter.resume()
            }
            if !pendingCountReadReleased {
                await withCheckedContinuation { continuation in
                    pendingCountReleaseWaiters.append(continuation)
                }
            }
        }
        if let pendingCountError {
            throw pendingCountError
        }
        return pendingCount
    }

    func retirePendingUploads(
        for ownerID: UUID,
        challengeID: UUID
    ) async throws {
        retiredContexts.append(
            .init(ownerID: ownerID, challengeID: challengeID)
        )
        pendingCount = 0
    }

    func waitUntilPendingCountReadStarts() async {
        guard !pendingCountReadStarted else { return }
        await withCheckedContinuation { continuation in
            pendingCountStartWaiters.append(continuation)
        }
    }

    func releasePendingCountRead() {
        pendingCountReadReleased = true
        let releaseWaiters = pendingCountReleaseWaiters
        pendingCountReleaseWaiters.removeAll()
        for waiter in releaseWaiters {
            waiter.resume()
        }
    }

    func pendingChallengeID(for ownerID: UUID) async throws -> UUID? {
        _ = ownerID
        return pendingCount > 0 ? queuedChallengeID : nil
    }

    func sync(
        ownerID: UUID,
        challenge: PersonalChallengeDetail,
        asOf: Date
    ) async throws -> ActivitySyncOutcome {
        _ = (ownerID, asOf)
        syncedChallengeIDs.append(challenge.id)
        guard !results.isEmpty else {
            throw ActivitySyncError.queuedRequestUnavailable
        }
        switch results.removeFirst() {
        case .outcome(let outcome, let pendingAfter):
            pendingCount = pendingAfter
            return outcome
        case .cancellation(let pendingAfter):
            pendingCount = pendingAfter
            throw CancellationError()
        }
    }
}

@MainActor
private final class SequencedActivitySyncFake: ActivitySyncing {
    struct RetiredContext: Equatable {
        let ownerID: UUID
        let contestID: UUID
    }

    private var pendingCount: Int
    private var outcomes: [ActivitySyncOutcome]
    private let pendingCountsAfterSync: [Int]
    private(set) var syncCallCount = 0
    private(set) var pendingCountReadCount = 0
    private(set) var retiredContexts: [RetiredContext] = []

    init(
        pendingCount: Int,
        outcomes: [ActivitySyncOutcome],
        pendingCountsAfterSync: [Int]
    ) {
        self.pendingCount = pendingCount
        self.outcomes = outcomes
        self.pendingCountsAfterSync = pendingCountsAfterSync
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        .requestCompleted
    }

    func pendingUploadCount(for ownerID: UUID) async throws -> Int {
        _ = ownerID
        pendingCountReadCount += 1
        return pendingCount
    }

    func retirePendingUploads(
        for ownerID: UUID,
        contestID: UUID
    ) async throws {
        retiredContexts.append(
            .init(ownerID: ownerID, contestID: contestID)
        )
        pendingCount = 0
    }

    func sync(
        ownerID: UUID,
        contest: ContestCard,
        asOf: Date
    ) async throws -> ActivitySyncOutcome {
        _ = (ownerID, contest, asOf)
        guard !outcomes.isEmpty else {
            throw ActivitySyncError.queuedRequestUnavailable
        }
        let index = syncCallCount
        syncCallCount += 1
        if pendingCountsAfterSync.indices.contains(index) {
            pendingCount = pendingCountsAfterSync[index]
        }
        return outcomes.removeFirst()
    }
}

@MainActor
private final class PersonalCoverageQueryFake: PersonalStepCoverageQuerying {
    private let intervalStarts: [Date]
    private(set) var queryCount = 0

    init(intervalStarts: [Date] = []) {
        self.intervalStarts = intervalStarts
    }

    func completedTrustedStepIntervalStarts(
        overlapping challengeWindow: DateInterval,
        timeZoneSchedule: ContestTimeZoneSchedule,
        asOf: Date
    ) async throws -> [Date] {
        _ = (challengeWindow, timeZoneSchedule, asOf)
        queryCount += 1
        return intervalStarts
    }
}

@MainActor
private final class PersonalCoverageClientFake: PersonalCoverageClient {
    private(set) var prepareCount = 0
    private(set) var sentSubmissions: [PendingPersonalCoverageSubmission] = []
    private let retryEnvironment: AppAttestEnvironment?
    private let receiptBatchID: UUID?
    private var sendErrors: [PersonalCoverageError?]
    var sendError: PersonalCoverageError?

    init(
        retryEnvironment: AppAttestEnvironment? = nil,
        receiptBatchID: UUID? = nil,
        sendError: PersonalCoverageError? = nil,
        sendErrors: [PersonalCoverageError?]? = nil
    ) {
        self.retryEnvironment = retryEnvironment
        self.receiptBatchID = receiptBatchID
        self.sendError = sendError
        self.sendErrors = sendErrors ?? []
    }

    func prepare(
        ownerID: UUID,
        challengeID: UUID,
        intervalStarts: [Date],
        observedAt: Date
    ) async throws -> PendingPersonalCoverageSubmission {
        prepareCount += 1
        let clientCoverageID = UUID()
        let body = try JSONSerialization.data(
            withJSONObject: [
                "challengeId": challengeID.uuidString.lowercased(),
                "clientCoverageId": clientCoverageID.uuidString.lowercased(),
                "coveredIntervalStarts": intervalStarts.map {
                    ISO8601DateFormatter().string(from: $0)
                },
                "observedAt": ISO8601DateFormatter().string(from: observedAt),
            ],
            options: [.sortedKeys]
        )
        return PendingPersonalCoverageSubmission(
            ownerID: ownerID,
            challengeID: challengeID,
            clientCoverageID: clientCoverageID,
            body: body,
            keyID: "fresh-key",
            assertion: Data([0xaa, 0xbb]),
            attestEnvironment: retryEnvironment ?? .development,
            createdAt: observedAt,
            attemptCount: 0,
            lastAttemptAt: nil
        )
    }

    func prepareForRetry(
        ownerID: UUID,
        submission: PendingPersonalCoverageSubmission
    ) async throws -> PendingPersonalCoverageSubmission {
        XCTAssertEqual(ownerID, submission.ownerID)
        if
            retryEnvironment == .production,
            submission.attestEnvironment != .production
        {
            throw PersonalCoverageError
                .savedEvidenceFromDifferentEnvironment
        }
        if
            retryEnvironment == .development,
            submission.attestEnvironment == nil
        {
            return submission.classifyingLegacyDevelopmentEnvironment()
        }
        return submission
    }

    func send(
        ownerID: UUID,
        submission: PendingPersonalCoverageSubmission
    ) async throws -> PersonalCoverageReceipt {
        XCTAssertEqual(ownerID, submission.ownerID)
        sentSubmissions.append(submission)
        if !sendErrors.isEmpty {
            if let error = sendErrors.removeFirst() {
                throw error
            }
            return PersonalCoverageReceipt(
                coverageBatchID: receiptBatchID
                    ?? submission.clientCoverageID,
                replayed: submission.attemptCount > 1
            )
        }
        if let sendError {
            throw sendError
        }
        return PersonalCoverageReceipt(
            coverageBatchID: receiptBatchID ?? submission.clientCoverageID,
            replayed: submission.attemptCount > 1
        )
    }
}

@MainActor
private final class RetryableBackgroundDeliveryCoordinator:
    PersonalHealthBackgroundDeliveryCoordinator
{
    private var enableResults: [Bool]
    private(set) var observerInstallCount = 0
    private(set) var enableRequestCount = 0

    init(enableResults: [Bool]) {
        self.enableResults = enableResults
        super.init()
    }

    override func healthDataIsAvailable() -> Bool { true }

    override func installObserver(
        for steps: HKQuantityType
    ) -> HKObserverQuery {
        observerInstallCount += 1
        return HKObserverQuery(
            sampleType: steps,
            predicate: nil
        ) { _, completion, _ in
            completion()
        }
    }

    override func requestBackgroundDelivery(for steps: HKQuantityType) {
        _ = steps
        enableRequestCount += 1
        let enabled = enableResults.isEmpty
            ? true
            : enableResults.removeFirst()
        recordBackgroundDeliveryResult(
            enabled: enabled,
            hadError: !enabled
        )
    }
}

final class PersonalPaceSummaryTests: XCTestCase {
    func testWeekPaceComparesStepsWithTheDaysThatCount() {
        let summary = PersonalPaceSummary(
            detail: makeDetail(
                cadence: .cumulative,
                targetSteps: 70_000,
                steps: [11_240, 10_510, 9_870, 12_040, 7_200, 0, 0],
                states: [
                    .complete, .complete, .complete, .complete, .inProgress,
                    .future, .future,
                ],
                metTargets: Array(repeating: nil, count: 7)
            )
        )

        XCTAssertEqual(summary.dayGoal, 10_000)
        XCTAssertEqual(summary.goalLineText, "10,000 a day")
        XCTAssertEqual(summary.dayCountText, "Day 5 of 7")
        XCTAssertEqual(summary.headline, "+860")
        XCTAssertEqual(summary.headlineTone, .positive)
        XCTAssertEqual(
            summary.headlineCaption,
            "steps ahead of where you need to be"
        )
        XCTAssertEqual(
            summary.tiles.map(\.label),
            ["To finish", "Average", "Left"]
        )
        XCTAssertEqual(summary.tiles[0].value, "9,570")
        XCTAssertEqual(summary.tiles[0].caption, "a day, Sat and Sun")
        XCTAssertEqual(summary.tiles[1].value, "10,172")
        XCTAssertEqual(summary.tiles[2].value, "2 days")
    }

    /// Fail-closed scoring never counts a missing day against the person, so
    /// the pace number must not either.
    func testDaysWeCannotCountStayOutOfThePaceComparison() {
        let summary = PersonalPaceSummary(
            detail: makeDetail(
                cadence: .cumulative,
                targetSteps: 70_000,
                steps: [11_240, 0, 4_000, 12_040, 7_200, 0, 0],
                states: [
                    .complete, .missing, .quarantined, .outageWaived,
                    .inProgress, .pending, .future,
                ],
                metTargets: Array(repeating: nil, count: 7)
            )
        )

        // Only Monday and Friday can be scored: 18,440 against 20,000.
        XCTAssertEqual(summary.headline, "−1,560")
        XCTAssertEqual(summary.headlineTone, .action)
        XCTAssertEqual(summary.tiles[1].value, "9,220")

        XCTAssertEqual(
            summary.days.map(\.verdict),
            [.metGoal, .problem, .problem, .waived, .today, .waiting, .future]
        )
    }

    func testEachDayExplainsItselfInPlainWords() {
        let summary = PersonalPaceSummary(
            detail: makeDetail(
                cadence: .cumulative,
                targetSteps: 70_000,
                steps: [11_240, 0, 4_000, 12_040, 7_200, 0, 0],
                states: [
                    .complete, .missing, .quarantined, .outageWaived,
                    .inProgress, .pending, .future,
                ],
                metTargets: Array(repeating: nil, count: 7)
            )
        )
        let captions = summary.days.map { summary.detailText(for: $0).caption }

        XCTAssertEqual(captions[0], "1,240 over a 10,000-step day")
        XCTAssertEqual(
            captions[1],
            "We never received steps for this day, so it won’t count either way."
        )
        XCTAssertEqual(
            captions[2],
            "We couldn’t use this day’s steps, so it won’t count either way."
        )
        XCTAssertEqual(
            captions[3],
            "This was a problem on our end, so it doesn’t count against you."
        )
        XCTAssertEqual(
            captions[4],
            "Still counting. 2,800 to go for a 10,000-step day."
        )
        XCTAssertEqual(summary.detailText(for: summary.days[6]).value, "Not here yet")

        // The card opens on the day that is still running.
        XCTAssertEqual(summary.defaultDayID, summary.days[4].id)
    }

    func testFinishedWeekSpeaksInThePastTense() {
        let summary = PersonalPaceSummary(
            detail: makeDetail(
                cadence: .cumulative,
                targetSteps: 70_000,
                steps: Array(repeating: 8_000, count: 7),
                states: Array(repeating: .complete, count: 7),
                metTargets: Array(repeating: nil, count: 7)
            )
        )

        XCTAssertEqual(summary.headline, "−14,000")
        XCTAssertEqual(
            summary.headlineCaption,
            "steps short of what you needed"
        )
        XCTAssertEqual(summary.tiles[0].caption, "steps short at the end")
        XCTAssertEqual(summary.tiles[2].value, "0 days")
        XCTAssertEqual(summary.tiles[2].caption, "your last day is done")
    }

    func testDailyChallengeLeadsWithTodayNotTheWeekTotal() {
        let summary = PersonalPaceSummary(
            detail: makeDetail(
                cadence: .daily,
                targetSteps: 10_000,
                steps: [10_482, 7_350, 0, 0, 0, 0, 0],
                states: [
                    .complete, .complete, .future, .future, .future, .future,
                    .future,
                ],
                metTargets: [true, false, nil, nil, nil, nil, nil]
            )
        )

        XCTAssertEqual(summary.headline, "2,650")
        XCTAssertEqual(summary.headlineCaption, "steps to go today")
        XCTAssertEqual(summary.tiles[0].label, "Goal days")
        XCTAssertEqual(summary.tiles[0].value, "1 of 2")
        // Five day names would not fit a tile caption.
        XCTAssertEqual(summary.tiles[2].caption, "through Sun")
    }

    func testFinishedDailyChallengeCountsTheDaysYouHit() {
        let summary = PersonalPaceSummary(
            detail: makeDetail(
                cadence: .daily,
                targetSteps: 10_000,
                steps: [10_100, 9_000, 10_400, 10_600, 10_800, 11_000, 11_200],
                states: Array(repeating: .complete, count: 7),
                metTargets: [true, false, true, true, true, true, true]
            )
        )

        XCTAssertEqual(summary.headline, "6 of 7")
        XCTAssertEqual(summary.headlineTone, .action)
        XCTAssertEqual(summary.headlineCaption, "days you hit your goal")
        XCTAssertEqual(summary.tiles[0].label, "Total")
        XCTAssertEqual(summary.tiles[0].value, "73,100")
    }

    func testScheduledChallengeStatesTheRateWithoutInventingProgress() {
        let summary = PersonalPaceSummary(
            detail: makeDetail(
                cadence: .cumulative,
                targetSteps: 70_000,
                steps: Array(repeating: 0, count: 7),
                states: Array(repeating: .future, count: 7),
                metTargets: Array(repeating: nil, count: 7)
            )
        )

        XCTAssertEqual(summary.headline, "10,000")
        XCTAssertEqual(
            summary.headlineCaption,
            "steps a day keeps you on track"
        )
        XCTAssertEqual(summary.dayCountText, "7 days")
        XCTAssertEqual(summary.tiles[1].value, "0")
    }

    /// The chart is drawn against this ceiling, so a day above the goal has to
    /// leave the guide line room to sit below it.
    func testBarCeilingKeepsTheGoalLineInsideTheChart() {
        let summary = PersonalPaceSummary(
            detail: makeDetail(
                cadence: .daily,
                targetSteps: 10_000,
                steps: [30_000, 0, 0, 0, 0, 0, 0],
                states: [.complete, .future, .future, .future, .future, .future, .future],
                metTargets: [true, nil, nil, nil, nil, nil, nil]
            )
        )

        XCTAssertEqual(summary.barCeiling, 31_800, accuracy: 0.5)
        XCTAssertLessThan(Double(summary.dayGoal), summary.barCeiling)
    }

    private func makeDetail(
        cadence: PersonalChallengeCadence,
        targetSteps: Int,
        steps: [Int],
        states: [PersonalEvidenceState],
        metTargets: [Bool?]
    ) -> PersonalChallengeDetail {
        let challengeID = UUID(
            uuidString: "44444444-4444-4444-4444-444444444444"
        )!
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        // A Monday, so the short labels in these expectations are stable.
        let start = calendar.date(
            from: DateComponents(year: 2026, month: 8, day: 3)
        )!
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let days = steps.indices.map { index in
            PersonalDayProgress(
                localDate: formatter.string(
                    from: calendar.date(
                        byAdding: .day,
                        value: index,
                        to: start
                    )!
                ),
                trustedSteps: Double(steps[index]),
                targetSteps: cadence == .daily ? targetSteps : nil,
                evidenceState: states[index],
                metTarget: metTargets[index]
            )
        }
        let total = steps.reduce(0, +)
        return PersonalChallengeDetail(
            id: challengeID,
            status: .active,
            terms: FrozenPersonalTerms(
                challengeID: challengeID,
                userID: UUID(
                    uuidString: "55555555-5555-5555-5555-555555555555"
                )!,
                cadence: cadence,
                targetSteps: targetSteps,
                commitmentAmountMinor: 2_000,
                currency: "USD",
                settlementMode: .testOnly,
                termsVersion: "personal-v1",
                timezone: "America/Chicago",
                agreementAt: start.addingTimeInterval(-86_400),
                startsAt: start,
                endsAt: calendar.date(byAdding: .day, value: 7, to: start)!,
                evidenceCutoff: calendar.date(
                    byAdding: .day,
                    value: 8,
                    to: start
                )!,
                closedAt: nil
            ),
            progress: PersonalProgress(
                trustedSteps: total,
                remainingSteps: cadence == .daily
                    ? PersonalProgress.dailyRemainingSteps(
                        targetSteps: targetSteps,
                        days: days
                    )
                    : max(0, targetSteps - total),
                qualifyingDays: metTargets.filter { $0 == true }.count,
                completedDays: states.filter { $0 != .future }.count,
                days: days,
                evidenceState: .inProgress,
                lastTrustedSyncAt: start,
                pendingUploadCount: 0,
                coveredBucketCount: 47,
                expectedBucketCount: 48
            )
        )
    }
}
