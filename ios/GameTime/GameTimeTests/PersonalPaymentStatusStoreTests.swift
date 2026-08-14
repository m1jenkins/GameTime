import Foundation
import XCTest

@testable import GameTime

@MainActor
final class PersonalPaymentStatusStoreTests: XCTestCase {
    func testDetailOpenIsTheOnlyAutomaticStripeStatusRead() async {
        let context = makeContext(state: .methodSaved)

        await context.store.activate(ownerID: context.ownerID)
        XCTAssertTrue(context.payments.statusRequests.isEmpty)

        await context.store.loadDetail(challengeID: context.challengeID)
        XCTAssertTrue(context.payments.statusRequests.isEmpty)

        await context.store.openDetail(challengeID: context.challengeID)
        await Task.yield()

        XCTAssertEqual(context.payments.statusRequests.count, 1)
        XCTAssertEqual(
            confirmedStatus(in: context.store, challengeID: context.challengeID)?.state,
            .methodSaved
        )
    }

    func testTestOnlyDetailNeverReadsPaymentStatus() async {
        let context = makeContext(
            state: .methodSaved,
            settlementMode: .testOnly,
            configuration: configuration(
                mutationsEnabled: true,
                settlementMode: .testOnly
            )
        )

        await context.store.activate(ownerID: context.ownerID)
        await context.store.openDetail(challengeID: context.challengeID)

        XCTAssertTrue(context.payments.statusRequests.isEmpty)
        XCTAssertEqual(
            context.store.paymentStatusState(for: context.challengeID),
            .idle
        )
    }

    func testReopeningDetailImmediatelyInvalidatesCachedReviewFreshness()
        async throws
    {
        let now = Date()
        let context = makeContext(
            state: .reviewOpen,
            reviewDeadline: now.addingTimeInterval(3_600)
        )
        await context.store.activate(ownerID: context.ownerID)
        await context.store.openDetail(challengeID: context.challengeID)
        XCTAssertNotNil(
            context.store.freshReviewDeadline(
                for: context.challengeID,
                at: now
            )
        )

        context.accountability.suspendNextChallengeResponse()
        let reopening = Task {
            await context.store.openDetail(challengeID: context.challengeID)
        }
        await context.accountability.waitUntilChallengeResponseSuspends()

        guard case .loading(let lastConfirmed) =
            context.store.paymentStatusState(for: context.challengeID)
        else {
            context.accountability.resumeChallengeResponse()
            await reopening.value
            return XCTFail("Reopening must invalidate cached freshness immediately.")
        }
        XCTAssertEqual(lastConfirmed?.status.state, .reviewOpen)
        XCTAssertNil(
            context.store.freshReviewDeadline(
                for: context.challengeID,
                at: now
            )
        )

        context.accountability.resumeChallengeResponse()
        await reopening.value

        XCTAssertEqual(context.payments.statusRequests.count, 2)
        XCTAssertEqual(
            confirmedStatus(
                in: context.store,
                challengeID: context.challengeID
            )?.state,
            .reviewOpen
        )
    }

    func testManualRefreshAdvancesStateAndFailureRetainsLastConfirmation()
        async throws
    {
        let context = makeContext(state: .chargePending)
        await context.store.activate(ownerID: context.ownerID)
        await context.store.openDetail(challengeID: context.challengeID)
        let pending = try XCTUnwrap(
            confirmation(in: context.store, challengeID: context.challengeID)
        )

        context.payments.currentStatus = status(
            challengeID: context.challengeID,
            state: .charged
        )
        await context.store.refreshPaymentStatus(
            challengeID: context.challengeID
        )
        let charged = try XCTUnwrap(
            confirmation(in: context.store, challengeID: context.challengeID)
        )

        XCTAssertEqual(pending.status.state, .chargePending)
        XCTAssertEqual(charged.status.state, .charged)
        XCTAssertGreaterThanOrEqual(charged.checkedAt, pending.checkedAt)

        context.payments.statusError = .unavailable
        await context.store.refreshPaymentStatus(
            challengeID: context.challengeID
        )

        guard case .failed(let lastConfirmed) =
            context.store.paymentStatusState(for: context.challengeID)
        else {
            return XCTFail("The failed refresh should remain card-local.")
        }
        XCTAssertEqual(lastConfirmed, charged)
        XCTAssertTrue(
            context.store.paymentStatusState(for: context.challengeID).isStale
        )
        XCTAssertNil(context.store.presentedError)
    }

    func testNewerStatusRefreshRejectsOlderResponse() async {
        let context = makeContext(state: .methodSaved)
        await context.store.activate(ownerID: context.ownerID)
        await context.store.openDetail(challengeID: context.challengeID)

        context.payments.currentStatus = status(
            challengeID: context.challengeID,
            state: .chargePending
        )
        context.payments.suspendNextStatusResponse()
        let olderRefresh = Task {
            await context.store.refreshPaymentStatus(
                challengeID: context.challengeID
            )
        }
        await context.payments.waitUntilStatusResponseSuspends()

        context.payments.currentStatus = status(
            challengeID: context.challengeID,
            state: .charged
        )
        await context.store.refreshPaymentStatus(
            challengeID: context.challengeID
        )

        context.payments.resumeStatusResponse()
        await olderRefresh.value

        XCTAssertEqual(
            confirmedStatus(in: context.store, challengeID: context.challengeID)?.state,
            .charged
        )
    }

    func testOwnerResetClearsStatusAndRejectsInFlightResponse() async {
        let context = makeContext(state: .methodSaved)
        await context.store.activate(ownerID: context.ownerID)
        await context.store.openDetail(challengeID: context.challengeID)

        context.payments.currentStatus = status(
            challengeID: context.challengeID,
            state: .charged
        )
        context.payments.suspendNextStatusResponse()
        let oldOwnerRefresh = Task {
            await context.store.refreshPaymentStatus(
                challengeID: context.challengeID
            )
        }
        await context.payments.waitUntilStatusResponseSuspends()

        context.auth.ownerID = nil
        await context.store.activate(ownerID: nil)

        XCTAssertTrue(context.store.paymentStatusStatesByChallengeID.isEmpty)
        XCTAssertEqual(
            context.store.paymentStatusState(for: context.challengeID),
            .idle
        )

        context.payments.resumeStatusResponse()
        await oldOwnerRefresh.value

        XCTAssertTrue(context.store.paymentStatusStatesByChallengeID.isEmpty)
        XCTAssertEqual(
            context.store.paymentStatusState(for: context.challengeID),
            .idle
        )
    }

    func testReviewRequiresFreshUnexpiredAuthoritativeState() async {
        let now = Date(timeIntervalSince1970: 1_786_000_000)
        let futureDeadline = now.addingTimeInterval(3_600)
        let context = makeContext(
            state: .reviewOpen,
            reviewDeadline: futureDeadline
        )
        await context.store.activate(ownerID: context.ownerID)

        XCTAssertNil(
            context.store.freshReviewDeadline(
                for: context.challengeID,
                at: now
            )
        )
        let idleReview = await context.store.requestReview(
            challengeID: context.challengeID,
            reason: .userDisputesResult,
            now: now
        )
        XCTAssertFalse(idleReview)
        XCTAssertTrue(context.payments.reviewRequests.isEmpty)

        await context.store.openDetail(challengeID: context.challengeID)
        XCTAssertEqual(
            context.store.freshReviewDeadline(
                for: context.challengeID,
                at: now
            ),
            futureDeadline
        )

        context.payments.statusError = .unavailable
        await context.store.refreshPaymentStatus(
            challengeID: context.challengeID
        )
        XCTAssertNil(
            context.store.freshReviewDeadline(
                for: context.challengeID,
                at: now
            )
        )
        let staleReview = await context.store.requestReview(
            challengeID: context.challengeID,
            reason: .userDisputesResult,
            now: now
        )
        XCTAssertFalse(staleReview)
        XCTAssertTrue(context.payments.reviewRequests.isEmpty)

        context.payments.statusError = nil
        context.payments.currentStatus = status(
            challengeID: context.challengeID,
            state: .reviewOpen,
            reviewDeadline: now
        )
        await context.store.refreshPaymentStatus(
            challengeID: context.challengeID
        )
        XCTAssertNil(
            context.store.freshReviewDeadline(
                for: context.challengeID,
                at: now
            )
        )
        let expiredReview = await context.store.requestReview(
            challengeID: context.challengeID,
            reason: .userDisputesResult,
            now: now
        )
        XCTAssertFalse(expiredReview)
        XCTAssertEqual(
            context.store.presentedError,
            PersonalPaymentClientError.reviewWindowClosed.localizedDescription
        )
        XCTAssertTrue(context.payments.reviewRequests.isEmpty)
    }

    func testReviewSuccessPublishesUnderReviewAndInvalidatesOlderRead()
        async
    {
        let now = Date()
        let context = makeContext(
            state: .reviewOpen,
            reviewDeadline: now.addingTimeInterval(3_600)
        )
        await context.store.activate(ownerID: context.ownerID)
        await context.store.openDetail(challengeID: context.challengeID)

        context.payments.suspendNextReviewResponse()
        let review = Task {
            await context.store.requestReview(
                challengeID: context.challengeID,
                reason: .userDisputesStepData,
                now: now
            )
        }
        await context.payments.waitUntilReviewResponseSuspends()

        context.payments.suspendNextStatusResponse()
        let staleStatusRead = Task {
            await context.store.refreshPaymentStatus(
                challengeID: context.challengeID
            )
        }
        await context.payments.waitUntilStatusResponseSuspends()

        context.payments.resumeReviewResponse()
        let reviewSucceeded = await review.value
        XCTAssertTrue(reviewSucceeded)
        XCTAssertEqual(
            confirmedStatus(in: context.store, challengeID: context.challengeID)?.state,
            .underReview
        )

        context.payments.resumeStatusResponse()
        await staleStatusRead.value

        XCTAssertEqual(context.payments.statusRequests.count, 3)
        XCTAssertEqual(
            confirmedStatus(in: context.store, challengeID: context.challengeID)?.state,
            .underReview
        )
        XCTAssertNil(
            context.store.freshReviewDeadline(
                for: context.challengeID,
                at: now
            )
        )
    }

    func testLostReviewResponseIsRecoveredByManualRefresh() async {
        let now = Date()
        let context = makeContext(
            state: .reviewOpen,
            reviewDeadline: now.addingTimeInterval(3_600)
        )
        await context.store.activate(ownerID: context.ownerID)
        await context.store.openDetail(challengeID: context.challengeID)
        context.payments.loseNextReviewResponse = true

        let reviewSucceeded = await context.store.requestReview(
            challengeID: context.challengeID,
            reason: .userDisputesResult,
            now: now
        )
        XCTAssertFalse(reviewSucceeded)
        XCTAssertEqual(
            confirmedStatus(in: context.store, challengeID: context.challengeID)?.state,
            .reviewOpen
        )

        await context.store.refreshPaymentStatus(
            challengeID: context.challengeID
        )

        XCTAssertEqual(context.payments.reviewRequests.count, 1)
        XCTAssertEqual(
            confirmedStatus(in: context.store, challengeID: context.challengeID)?.state,
            .underReview
        )
    }

    func testMutationKillSwitchDoesNotBlockStatusReadButBlocksReview() async {
        let now = Date()
        let context = makeContext(
            state: .reviewOpen,
            reviewDeadline: now.addingTimeInterval(3_600),
            configuration: configuration(
                mutationsEnabled: false,
                settlementMode: .stripeSandbox
            )
        )
        await context.store.activate(ownerID: context.ownerID)
        await context.store.openDetail(challengeID: context.challengeID)

        XCTAssertEqual(context.payments.statusRequests.count, 1)
        XCTAssertEqual(
            confirmedStatus(in: context.store, challengeID: context.challengeID)?.state,
            .reviewOpen
        )
        XCTAssertNil(
            context.store.freshReviewDeadline(
                for: context.challengeID,
                at: now
            )
        )
        let reviewSucceeded = await context.store.requestReview(
            challengeID: context.challengeID,
            reason: .userDisputesResult,
            now: now
        )
        XCTAssertFalse(reviewSucceeded)
        XCTAssertTrue(context.payments.reviewRequests.isEmpty)
        XCTAssertTrue(context.payments.preparedRequests.isEmpty)
        XCTAssertTrue(context.payments.committedRequests.isEmpty)
    }

    private func makeContext(
        state: PersonalPaymentState,
        reviewDeadline: Date? = nil,
        settlementMode: PersonalSettlementMode = .stripeSandbox,
        configuration: AppConfiguration? = nil
    ) -> PaymentStatusTestContext {
        let ownerID = UUID()
        let challengeID = UUID()
        let auth = PaymentStatusAuthFake(ownerID: ownerID)
        let accountability = PaymentStatusAccountabilityFake(
            challenge: challenge(
                ownerID: ownerID,
                challengeID: challengeID,
                settlementMode: settlementMode
            )
        )
        let payments = PaymentStatusPaymentFake(
            ownerID: ownerID,
            status: status(
                challengeID: challengeID,
                state: state,
                reviewDeadline: reviewDeadline
            )
        )
        let store = PersonalAccountabilityStore(
            configuration: configuration
                ?? Self.configuration(
                    mutationsEnabled: true,
                    settlementMode: settlementMode
                ),
            auth: auth,
            client: accountability,
            paymentClient: payments,
            pendingStore: EphemeralPendingPersonalChallengeStore(),
            diagnosticClient: DisabledTrustedActivityDiagnosticClient(),
            activitySync: DisabledPersonalActivitySyncCoordinator()
        )
        return PaymentStatusTestContext(
            ownerID: ownerID,
            challengeID: challengeID,
            auth: auth,
            accountability: accountability,
            payments: payments,
            store: store
        )
    }

    private static func configuration(
        mutationsEnabled: Bool,
        settlementMode: PersonalSettlementMode
    ) -> AppConfiguration {
        AppConfiguration(
            environment: .staging,
            supabaseURL: URL(string: "https://fixture.invalid")!,
            supabasePublishableKey: "sb_publishable_fixture_only",
            contestMutationsEnabled: mutationsEnabled,
            personalSettlementMode: settlementMode
        )
    }

    private func configuration(
        mutationsEnabled: Bool,
        settlementMode: PersonalSettlementMode
    ) -> AppConfiguration {
        Self.configuration(
            mutationsEnabled: mutationsEnabled,
            settlementMode: settlementMode
        )
    }

    private func challenge(
        ownerID: UUID,
        challengeID: UUID,
        settlementMode: PersonalSettlementMode
    ) -> PersonalChallengeDetail {
        let now = Date()
        return PersonalChallengeDetail(
            id: challengeID,
            status: .completed,
            terms: FrozenPersonalTerms(
                challengeID: challengeID,
                userID: ownerID,
                cadence: .cumulative,
                targetSteps: 70_000,
                commitmentAmountMinor: 2_000,
                currency: "USD",
                settlementMode: settlementMode,
                termsVersion: settlementMode == .stripeSandbox
                    ? "personal-stripe-sandbox-v1"
                    : "personal-v2",
                timezone: "America/Chicago",
                agreementAt: now.addingTimeInterval(-10 * 86_400),
                startsAt: now.addingTimeInterval(-9 * 86_400),
                endsAt: now.addingTimeInterval(-2 * 86_400),
                evidenceCutoff: now.addingTimeInterval(-86_400),
                closedAt: now.addingTimeInterval(-86_400)
            ),
            progress: .empty
        )
    }

    private func status(
        challengeID: UUID,
        state: PersonalPaymentState,
        reviewDeadline: Date? = nil
    ) -> PersonalPaymentStatus {
        PersonalPaymentStatus(
            challengeID: challengeID,
            state: state,
            reviewDeadline: reviewDeadline
        )
    }

    private func confirmation(
        in store: PersonalAccountabilityStore,
        challengeID: UUID
    ) -> PersonalPaymentStatusConfirmation? {
        guard case .confirmed(let confirmation) =
            store.paymentStatusState(for: challengeID)
        else { return nil }
        return confirmation
    }

    private func confirmedStatus(
        in store: PersonalAccountabilityStore,
        challengeID: UUID
    ) -> PersonalPaymentStatus? {
        confirmation(in: store, challengeID: challengeID)?.status
    }
}

@MainActor
private struct PaymentStatusTestContext {
    let ownerID: UUID
    let challengeID: UUID
    let auth: PaymentStatusAuthFake
    let accountability: PaymentStatusAccountabilityFake
    let payments: PaymentStatusPaymentFake
    let store: PersonalAccountabilityStore
}

@MainActor
private final class PaymentStatusAuthFake: AuthClient {
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
            throw PersonalPaymentClientError.authenticationRequired
        }
        return ownerID
    }

    func signOut() async throws {
        ownerID = nil
    }
}

@MainActor
private final class PaymentStatusAccountabilityFake:
    PersonalAccountabilityClient
{
    let challengeValue: PersonalChallengeDetail
    private var shouldSuspendNextChallengeResponse = false
    private var challengeResponseDidSuspend = false
    private var challengeStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var challengeReleaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(challenge: PersonalChallengeDetail) {
        challengeValue = challenge
    }

    func listMyChallenges() async throws -> PersonalAccountabilitySnapshot {
        PersonalAccountabilitySnapshot(
            challenges: [],
            latestDiagnostic: nil,
            eligibilityHold: nil
        )
    }

    func challenge(id: UUID) async throws -> PersonalChallengeDetail? {
        if shouldSuspendNextChallengeResponse {
            shouldSuspendNextChallengeResponse = false
            challengeResponseDidSuspend = true
            resume(&challengeStartWaiters)
            await withCheckedContinuation { continuation in
                challengeReleaseWaiters.append(continuation)
            }
        }
        return id == challengeValue.id ? challengeValue : nil
    }

    func suspendNextChallengeResponse() {
        shouldSuspendNextChallengeResponse = true
        challengeResponseDidSuspend = false
    }

    func waitUntilChallengeResponseSuspends() async {
        guard !challengeResponseDidSuspend else { return }
        await withCheckedContinuation { continuation in
            challengeStartWaiters.append(continuation)
        }
    }

    func resumeChallengeResponse() {
        resume(&challengeReleaseWaiters)
    }

    private func resume(
        _ continuations: inout [CheckedContinuation<Void, Never>]
    ) {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    func create(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> UUID {
        _ = (request, expectedUserID)
        throw PersonalAccountabilityClientError.stagingOnly
    }

    func cancel(
        challengeID: UUID,
        requestID: UUID,
        expectedUserID: UUID
    ) async throws {
        _ = (challengeID, requestID, expectedUserID)
        throw PersonalAccountabilityClientError.stagingOnly
    }
}

@MainActor
private final class PaymentStatusPaymentFake: PersonalPaymentClient {
    let ownerID: UUID
    var currentStatus: PersonalPaymentStatus
    var statusError: PersonalPaymentClientError?
    var loseNextReviewResponse = false
    private(set) var preparedRequests: [PersonalChallengeCreationRequest] = []
    private(set) var committedRequests: [PersonalChallengeCreationRequest] = []
    private(set) var reviewRequests:
        [(challengeID: UUID, reason: PersonalReviewReason)] = []
    private(set) var statusRequests:
        [(challengeID: UUID, expectedUserID: UUID)] = []

    private var shouldSuspendNextStatusResponse = false
    private var statusResponseDidSuspend = false
    private var statusStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var statusReleaseWaiters: [CheckedContinuation<Void, Never>] = []

    private var shouldSuspendNextReviewResponse = false
    private var reviewResponseDidSuspend = false
    private var reviewStartWaiters: [CheckedContinuation<Void, Never>] = []
    private var reviewReleaseWaiters: [CheckedContinuation<Void, Never>] = []

    init(ownerID: UUID, status: PersonalPaymentStatus) {
        self.ownerID = ownerID
        currentStatus = status
    }

    func prepare(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> PersonalPaymentSetup {
        guard expectedUserID == ownerID else {
            throw PersonalPaymentClientError.accountChanged
        }
        preparedRequests.append(request)
        throw PersonalPaymentClientError.disabled
    }

    func commit(
        _ request: PersonalChallengeCreationRequest,
        setupID: String,
        expectedUserID: UUID
    ) async throws -> UUID {
        _ = setupID
        guard expectedUserID == ownerID else {
            throw PersonalPaymentClientError.accountChanged
        }
        committedRequests.append(request)
        throw PersonalPaymentClientError.disabled
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
        if shouldSuspendNextReviewResponse {
            shouldSuspendNextReviewResponse = false
            reviewResponseDidSuspend = true
            resume(&reviewStartWaiters)
            await withCheckedContinuation { continuation in
                reviewReleaseWaiters.append(continuation)
            }
        }
        let deadline = currentStatus.reviewDeadline
            ?? Date().addingTimeInterval(3_600)
        currentStatus = PersonalPaymentStatus(
            challengeID: challengeID,
            state: .underReview,
            reviewDeadline: deadline
        )
        if loseNextReviewResponse {
            loseNextReviewResponse = false
            throw PersonalPaymentClientError.unavailable
        }
        return PersonalReviewRequestResult(
            state: .underReview,
            reviewDeadline: deadline,
            replayed: false
        )
    }

    func paymentStatus(
        challengeID: UUID,
        expectedUserID: UUID
    ) async throws -> PersonalPaymentStatus {
        guard expectedUserID == ownerID else {
            throw PersonalPaymentClientError.accountChanged
        }
        statusRequests.append((challengeID, expectedUserID))
        let response = currentStatus
        let error = statusError
        if shouldSuspendNextStatusResponse {
            shouldSuspendNextStatusResponse = false
            statusResponseDidSuspend = true
            resume(&statusStartWaiters)
            await withCheckedContinuation { continuation in
                statusReleaseWaiters.append(continuation)
            }
        }
        if let error { throw error }
        return response
    }

    func suspendNextStatusResponse() {
        shouldSuspendNextStatusResponse = true
        statusResponseDidSuspend = false
    }

    func waitUntilStatusResponseSuspends() async {
        guard !statusResponseDidSuspend else { return }
        await withCheckedContinuation { continuation in
            statusStartWaiters.append(continuation)
        }
    }

    func resumeStatusResponse() {
        resume(&statusReleaseWaiters)
    }

    func suspendNextReviewResponse() {
        shouldSuspendNextReviewResponse = true
        reviewResponseDidSuspend = false
    }

    func waitUntilReviewResponseSuspends() async {
        guard !reviewResponseDidSuspend else { return }
        await withCheckedContinuation { continuation in
            reviewStartWaiters.append(continuation)
        }
    }

    func resumeReviewResponse() {
        resume(&reviewReleaseWaiters)
    }

    private func resume(
        _ continuations: inout [CheckedContinuation<Void, Never>]
    ) {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
