import Foundation
import GameTimeCore
import HealthKit
import XCTest

@testable import GameTime

final class PersonalAccountabilityModelTests: XCTestCase {
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

    func testReleaseCannotEnablePersonalMutationOrLiveSettlement() throws {
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
        _ year: Int, _ month: Int, _ day: Int, _ hour: Int
    ) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar.date(
            from: DateComponents(
                year: year, month: month, day: day, hour: hour
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
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await firstStore.activate(ownerID: ownerID)

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
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await relaunchedStore.activate(ownerID: ownerID)
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
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await firstStore.activate(ownerID: ownerID)
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
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await relaunchedStore.activate(ownerID: ownerID)
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
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        await firstStore.activate(ownerID: ownerID)
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
        let store = PersonalAccountabilityStore(
            configuration: .activityFixture,
            auth: PersonalAuthFake(ownerID: ownerID),
            client: PersonalClientFake(ownerID: ownerID),
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: PersonalDiagnosticFake(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        store.setBackgroundDeliveryRegistration(registration)
        await store.activate(ownerID: ownerID)

        _ = await store.runDiagnostic(timezone: "America/Chicago")

        XCTAssertEqual(registration.retryCount, 1)
    }

    func testActiveTabsExposeOnlyPersonalV1Shell() {
        XCTAssertEqual(AppTab.allCases, [.today, .challenges, .you])
    }
}

@MainActor
final class PersonalActivitySyncCoordinatorTests: XCTestCase {
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
}

@MainActor
final class PersonalHealthBackgroundDeliveryTests: XCTestCase {
    func testStagingIsOnlyEnvironmentThatStartsHealthObserver() {
        XCTAssertTrue(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Staging"
            )
        )
        XCTAssertFalse(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Debug"
            )
        )
        XCTAssertFalse(
            GameTimeAppDelegate.shouldStartPersonalHealthBackgroundDelivery(
                environmentValue: "Release"
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
    private(set) var cancellationRequests:
        [(challengeID: UUID, requestID: UUID)] = []
    private var challenge: PersonalChallengeDetail?

    init(ownerID: UUID) {
        self.ownerID = ownerID
    }

    func setChallenge(_ challenge: PersonalChallengeDetail) {
        self.challenge = challenge
    }

    func listMyChallenges() async throws -> PersonalAccountabilitySnapshot {
        PersonalAccountabilitySnapshot(
            challenges: challenge.map {
                [
                    PersonalChallengeSummary(
                        id: $0.id,
                        status: $0.status,
                        terms: $0.terms,
                        progress: $0.progress,
                        outcome: $0.outcome
                    )
                ]
            } ?? [],
            latestDiagnostic: trustedDiagnostic,
            eligibilityHold: hold
        )
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
    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        .requestCompleted
    }

    func probeLocalStepAccess(
        timezone: String
    ) async throws -> LocalStepAccessProbe {
        _ = timezone
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
private final class SequencedActivitySyncFake: ActivitySyncing {
    private var pendingCount: Int
    private var outcomes: [ActivitySyncOutcome]
    private let pendingCountsAfterSync: [Int]
    private(set) var syncCallCount = 0
    private(set) var pendingCountReadCount = 0

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
            createdAt: observedAt,
            attemptCount: 0,
            lastAttemptAt: nil
        )
    }

    func send(
        ownerID: UUID,
        submission: PendingPersonalCoverageSubmission
    ) async throws -> PersonalCoverageReceipt {
        XCTAssertEqual(ownerID, submission.ownerID)
        sentSubmissions.append(submission)
        return PersonalCoverageReceipt(
            coverageBatchID: submission.clientCoverageID,
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
