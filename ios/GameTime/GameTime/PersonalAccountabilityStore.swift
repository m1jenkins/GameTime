import Foundation
import Observation

enum PersonalActivitySyncViewState: Equatable, Sendable {
    case idle
    case syncing
    case synced(stepTotal: Double)
    /// Read from HealthKit on this device but never uploaded or attested.
    case observedLocally(stepTotal: Double)
    case replayAccepted(stepTotal: Double)
    case savedRequestAccepted
    case savedRequestUnavailable
    case queuedForRetry(stepTotal: Double)
    case noReadableData
    case failed(String)

    var message: String? {
        switch self {
        case .idle: nil
        case .syncing: "Checking your steps…"
        case .synced(let total):
            "\(total.formatted(.number.precision(.fractionLength(0)))) steps synced."
        case .observedLocally(let total):
            "\(total.formatted(.number.precision(.fractionLength(0)))) steps read on this phone — not confirmed yet."
        case .replayAccepted(let total):
            "\(total.formatted(.number.precision(.fractionLength(0)))) saved steps confirmed."
        case .savedRequestAccepted:
            "Saved step evidence confirmed."
        case .savedRequestUnavailable:
            "Steps saved on this phone couldn’t be confirmed. Sync again while the window is open."
        case .queuedForRetry(let total):
            "\(total.formatted(.number.precision(.fractionLength(0)))) steps are saved and waiting to send."
        case .noReadableData:
            "We couldn’t read any steps for that time."
        case .failed(let message): message
        }
    }
}

@MainActor
@Observable
final class PersonalAccountabilityStore {
    let configuration: AppConfiguration

    private(set) var ownerID: UUID?
    private(set) var challenges: [PersonalChallengeSummary] = []
    private(set) var detailsByID: [UUID: PersonalChallengeDetail] = [:]
    private(set) var loadState: ScreenLoadState = .idle
    private(set) var pendingCreation: PendingPersonalChallengeSubmission?
    private(set) var hasPendingCreationRecoveryIssue = false
    private(set) var pendingCancellation:
        PendingPersonalCancellationSubmission?
    private(set) var hasPendingCancellationRecoveryIssue = false
    private(set) var latestDiagnostic: TrustedActivityDiagnostic?
    private(set) var healthReadiness: PersonalHealthReadiness = .unknown
    private(set) var isVerifyingHealthAccess = false
    private(set) var eligibilityHold: PersonalEligibilityHold?
    private(set) var eligibilityHoldActive = false
    private(set) var activityAuthorizationOutcome: ActivityAuthorizationOutcome?
    private(set) var activitySyncStates: [UUID: PersonalActivitySyncViewState] = [:]
    private(set) var pendingActivityUploadCount = 0
    private(set) var pendingActivityChallengeID: UUID?
    private(set) var hasPendingActivityRecoveryIssue = false
    private(set) var isRestoringSavedState = false
    private(set) var isMutating = false
    private(set) var isPreparingPayment = false
    private(set) var isRequestingReview = false
    private(set) var reviewRequestsByChallengeID:
        [UUID: PersonalReviewRequestResult] = [:]
    private(set) var isRunningDiagnostic = false
    private(set) var isSyncingActivity = false
    var presentedError: String?

    private let auth: any AuthClient
    private let client: any PersonalAccountabilityClient
    private let paymentClient: any PersonalPaymentClient
    private let pendingStore: any PendingPersonalChallengeStore
    private let pendingCancellationStore:
        any PendingPersonalCancellationStore
    private let diagnosticClient: any TrustedActivityDiagnosticClient
    private let activitySync: any PersonalActivitySyncing
    @ObservationIgnored private weak var backgroundDeliveryRegistration:
        (any PersonalHealthBackgroundDeliveryRegistering)?
    @ObservationIgnored private var actorGeneration = UUID()
    @ObservationIgnored private var refreshGeneration = UUID()

    init(
        configuration: AppConfiguration,
        auth: any AuthClient,
        client: any PersonalAccountabilityClient,
        paymentClient: any PersonalPaymentClient =
            DisabledPersonalPaymentClient(),
        pendingStore: any PendingPersonalChallengeStore,
        pendingCancellationStore: any PendingPersonalCancellationStore =
            EphemeralPendingPersonalCancellationStore(),
        diagnosticClient: any TrustedActivityDiagnosticClient,
        activitySync: any PersonalActivitySyncing
    ) {
        self.configuration = configuration
        self.auth = auth
        self.client = client
        self.paymentClient = paymentClient
        self.pendingStore = pendingStore
        self.pendingCancellationStore = pendingCancellationStore
        self.diagnosticClient = diagnosticClient
        self.activitySync = activitySync
    }

    var openChallenge: PersonalChallengeSummary? {
        challenges.first(where: { $0.status.isOpen })
    }

    var history: [PersonalChallengeSummary] {
        challenges.filter { !$0.status.isOpen }
    }

    var pendingPaymentIsConfirmed: Bool {
        pendingCreation?.paymentSetupCompletedAt != nil
    }

    var hasVerifiedCreationState: Bool {
        guard !isRestoringSavedState else { return false }
        switch loadState {
        case .loaded, .empty:
            return true
        case .idle, .loading, .failed:
            return false
        }
    }

    func reviewRequest(
        for challengeID: UUID
    ) -> PersonalReviewRequestResult? {
        reviewRequestsByChallengeID[challengeID]
    }

    var canCreate: Bool {
        configuration.personalChallengeMutationsEnabled
            && hasVerifiedCreationState
            && openChallenge == nil
            && !eligibilityHoldActive
            && !hasPendingCreationRecoveryIssue
            && pendingCancellation == nil
            && !hasPendingCancellationRecoveryIssue
            && pendingActivityUploadCount == 0
            && !hasPendingActivityRecoveryIssue
    }

    func setBackgroundDeliveryRegistration(
        _ registration: any PersonalHealthBackgroundDeliveryRegistering
    ) {
        backgroundDeliveryRegistration = registration
    }

    func activate(ownerID: UUID?) async {
        guard self.ownerID != ownerID else {
            if
                ownerID != nil,
                !isRestoringSavedState,
                hasPendingActivityRecoveryIssue
            {
                await retryPendingActivityRecovery()
            }
            return
        }
        actorGeneration = UUID()
        refreshGeneration = UUID()
        clearVolatileState()
        self.ownerID = ownerID
        guard let ownerID else { return }
        let generation = actorGeneration
        isRestoringSavedState = true
        defer {
            if isCurrent(ownerID, generation: generation) {
                isRestoringSavedState = false
            }
        }
        await restorePendingCreation(for: ownerID, generation: generation)
        guard isCurrent(ownerID, generation: generation) else { return }
        await restorePendingCancellation(for: ownerID, generation: generation)
        guard isCurrent(ownerID, generation: generation) else { return }
        if pendingCancellation != nil {
            _ = await retryPendingCancellation()
        }
        guard isCurrent(ownerID, generation: generation) else { return }
        await restorePendingActivityCount(for: ownerID, generation: generation)
        guard isCurrent(ownerID, generation: generation) else { return }
        await refresh()
    }

    func retryPendingActivityRecovery() async {
        guard let ownerID, !isRestoringSavedState else { return }
        let generation = actorGeneration
        isRestoringSavedState = true
        defer {
            if isCurrent(ownerID, generation: generation) {
                isRestoringSavedState = false
            }
        }
        await restorePendingActivityCount(
            for: ownerID,
            generation: generation
        )
        guard isCurrent(ownerID, generation: generation) else { return }
        await refresh()
    }

    func refresh() async {
        guard let ownerID else { return }
        let actorGeneration = actorGeneration
        let generation = UUID()
        refreshGeneration = generation
        loadState = .loading
        do {
            let snapshot = try await client.listMyChallenges()
            guard
                generation == refreshGeneration,
                await isCurrentAuthenticated(
                    ownerID,
                    generation: actorGeneration
                ),
                !Task.isCancelled
            else { return }
            challenges = snapshot.challenges.sorted {
                $0.terms.startsAt > $1.terms.startsAt
            }
            latestDiagnostic = snapshot.latestDiagnostic ?? latestDiagnostic
            // A trusted server record is the strongest readiness evidence and
            // survives relaunch, so it supersedes a local-only probe.
            if let diagnostic = latestDiagnostic, diagnostic.isTrusted {
                healthReadiness = .attested(diagnostic)
            }
            eligibilityHold = snapshot.eligibilityHold
            eligibilityHoldActive = snapshot.eligibilityHoldActive
            loadState = challenges.isEmpty ? .empty : .loaded
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(ownerID, generation: actorGeneration) else { return }
            loadState = .failed(error.localizedDescription)
        }
    }

    func detail(for challengeID: UUID) -> PersonalChallengeDetail? {
        if let detail = detailsByID[challengeID] { return detail }
        guard let summary = challenges.first(where: { $0.id == challengeID }) else {
            return nil
        }
        return PersonalChallengeDetail(
            id: summary.id,
            status: summary.status,
            terms: summary.terms,
            progress: summary.progress ?? .empty,
            outcome: summary.outcome
        )
    }

    func loadDetail(challengeID: UUID) async {
        guard let ownerID else { return }
        let generation = actorGeneration
        do {
            guard let detail = try await client.challenge(id: challengeID) else {
                return
            }
            guard
                await isCurrentAuthenticated(ownerID, generation: generation),
                !Task.isCancelled
            else { return }
            detailsByID[challengeID] = detail
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return }
            presentedError = error.localizedDescription
        }
    }

    func create(_ request: PersonalChallengeCreationRequest) async -> UUID? {
        guard configuration.personalChallengeMutationsEnabled else {
            presentedError = PersonalAccountabilityClientError.stagingOnly
                .localizedDescription
            return nil
        }
        guard let ownerID else { return nil }
        guard hasVerifiedCreationState else {
            presentedError = PersonalAccountabilityClientError.unavailable
                .localizedDescription
            return nil
        }
        guard !eligibilityHoldActive else {
            presentedError = PersonalAccountabilityClientError.eligibilityHold
                .localizedDescription
            return nil
        }
        guard
            pendingActivityUploadCount == 0,
            !hasPendingActivityRecoveryIssue
        else {
            presentedError =
                "Finish sending or recovering your saved steps first."
            return nil
        }
        // A lost create response can leave both the exact local retry and the
        // server-created open challenge visible after relaunch. Let only that
        // saved request reach the idempotent server boundary; a genuinely new
        // request remains blocked while any challenge is open.
        guard openChallenge == nil || pendingCreation != nil else {
            presentedError = PersonalAccountabilityClientError.openChallengeExists
                .localizedDescription
            return nil
        }
        guard healthReadiness.permitsCreation else {
            presentedError = "Check your Health connection before you start."
            return nil
        }
        guard !hasPendingCreationRecoveryIssue, !isMutating else { return nil }
        let generation = actorGeneration
        isMutating = true
        defer { isMutating = false }

        let submission: PendingPersonalChallengeSubmission
        if let pendingCreation {
            guard
                pendingCreation.ownerID == ownerID,
                pendingCreation.request.requestID == request.requestID,
                pendingCreation.request == request
            else {
                presentedError = "Finish or delete your saved draft first."
                return nil
            }
            submission = pendingCreation
        } else if configuration.personalSettlementMode == .stripeSandbox {
            presentedError =
                "Set up your test payment method before starting the challenge."
            return nil
        } else {
            submission = PendingPersonalChallengeSubmission(
                ownerID: ownerID,
                request: request
            )
        }

        do {
            let attempted = try submission.recordingAttempt()
            try await pendingStore.save(attempted)
            guard isCurrent(ownerID, generation: generation) else { return nil }
            pendingCreation = attempted

            guard await auth.currentUserID() == ownerID else {
                throw PersonalAccountabilityClientError.accountChanged
            }
            let challengeID: UUID
            switch configuration.personalSettlementMode {
            case .testOnly:
                challengeID = try await client.create(
                    request,
                    expectedUserID: ownerID
                )
            case .stripeSandbox:
                guard
                    let setupID = attempted.paymentSetupID,
                    attempted.paymentSetupCompletedAt != nil
                else {
                    throw PersonalPaymentClientError.setupNotConfirmed
                }
                challengeID = try await paymentClient.commit(
                    request,
                    setupID: setupID,
                    expectedUserID: ownerID
                )
            }
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return nil }
            try await pendingStore.remove(for: ownerID)
            pendingCreation = nil
            hasPendingCreationRecoveryIssue = false
            await refresh()
            await loadDetail(challengeID: challengeID)
            return challengeID
        } catch is CancellationError {
            return nil
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return nil }
            presentedError = error.localizedDescription
            return nil
        }
    }

    /// Freezes the exact challenge request before asking the server for a
    /// Stripe SetupIntent. Only GameTime's opaque setup ID is persisted; the
    /// short-lived client secret stays in memory for PaymentSheet.
    func preparePayment(
        _ request: PersonalChallengeCreationRequest
    ) async -> PersonalPaymentSetup? {
        guard
            configuration.personalChallengeMutationsEnabled,
            configuration.personalSettlementMode == .stripeSandbox
        else {
            presentedError = PersonalPaymentClientError.disabled
                .localizedDescription
            return nil
        }
        guard hasVerifiedCreationState else {
            presentedError = PersonalAccountabilityClientError.unavailable
                .localizedDescription
            return nil
        }
        guard let ownerID, !isPreparingPayment, !isMutating else {
            return nil
        }
        guard healthReadiness.permitsCreation else {
            presentedError = "Check your Health connection before you start."
            return nil
        }
        guard !eligibilityHoldActive, !hasPendingCreationRecoveryIssue else {
            presentedError = PersonalAccountabilityClientError.eligibilityHold
                .localizedDescription
            return nil
        }

        let generation = actorGeneration
        isPreparingPayment = true
        defer { isPreparingPayment = false }
        do {
            let submission: PendingPersonalChallengeSubmission
            if let pendingCreation {
                guard
                    pendingCreation.ownerID == ownerID,
                    pendingCreation.request == request
                else {
                    throw PendingPersonalChallengeStoreError.conflictingRecord
                }
                submission = pendingCreation
            } else {
                submission = PendingPersonalChallengeSubmission(
                    ownerID: ownerID,
                    request: request
                )
                try await pendingStore.save(submission)
                guard isCurrent(ownerID, generation: generation) else {
                    return nil
                }
                pendingCreation = submission
            }

            guard await auth.currentUserID() == ownerID else {
                throw PersonalPaymentClientError.accountChanged
            }
            let setup = try await paymentClient.prepare(
                request,
                expectedUserID: ownerID
            )
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return nil }
            let completedAt: Date? =
                setup.presentation == .alreadyConfirmed ? Date() : nil
            let updated = try submission.recordingPaymentSetup(
                id: setup.setupID,
                completedAt: completedAt
            )
            try await pendingStore.save(updated)
            guard isCurrent(ownerID, generation: generation) else {
                return nil
            }
            pendingCreation = updated
            return setup
        } catch is CancellationError {
            return nil
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return nil }
            presentedError = error.localizedDescription
            return nil
        }
    }

    /// Records local PaymentSheet completion so a relaunch can resume at
    /// review. The commit endpoint still verifies Stripe independently before
    /// it creates or replays the challenge.
    func confirmPaymentSetup(
        request: PersonalChallengeCreationRequest,
        setupID: String
    ) async -> Bool {
        guard
            configuration.personalSettlementMode == .stripeSandbox,
            let ownerID,
            let pendingCreation,
            pendingCreation.ownerID == ownerID,
            pendingCreation.request == request,
            !isPreparingPayment,
            !isMutating
        else { return false }
        let generation = actorGeneration
        do {
            guard await auth.currentUserID() == ownerID else {
                throw PersonalPaymentClientError.accountChanged
            }
            let completed = try pendingCreation.recordingPaymentSetup(
                id: setupID,
                completedAt: Date()
            )
            try await pendingStore.save(completed)
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return false }
            self.pendingCreation = completed
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrent(ownerID, generation: generation) else {
                return false
            }
            presentedError = error.localizedDescription
            return false
        }
    }

    func requestReview(
        challengeID: UUID,
        reason: PersonalReviewReason,
        now: Date = Date()
    ) async -> Bool {
        guard
            configuration.personalChallengeMutationsEnabled,
            configuration.personalSettlementMode == .stripeSandbox
        else {
            presentedError = PersonalPaymentClientError.disabled
                .localizedDescription
            return false
        }
        guard
            let ownerID,
            let challenge = detail(for: challengeID),
            challenge.terms.settlementMode == .stripeSandbox,
            let outcome = challenge.outcome,
            outcome.kind == .missedGoal
        else {
            presentedError = PersonalPaymentClientError.invalidResponse
                .localizedDescription
            return false
        }
        guard
            now < outcome.publishedAt.addingTimeInterval(7 * 86_400)
        else {
            presentedError = PersonalPaymentClientError.reviewWindowClosed
                .localizedDescription
            return false
        }
        if reviewRequestsByChallengeID[challengeID]?.state == .underReview {
            return true
        }
        guard !isRequestingReview, !isMutating else { return false }

        let generation = actorGeneration
        isRequestingReview = true
        defer { isRequestingReview = false }
        do {
            guard await auth.currentUserID() == ownerID else {
                throw PersonalPaymentClientError.accountChanged
            }
            let result = try await paymentClient.requestReview(
                challengeID: challengeID,
                reason: reason,
                expectedUserID: ownerID
            )
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return false }
            reviewRequestsByChallengeID[challengeID] = result
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrent(ownerID, generation: generation) else {
                return false
            }
            presentedError = error.localizedDescription
            return false
        }
    }

    func discardPendingCreation() async -> Bool {
        guard let ownerID, !isMutating else { return false }
        let generation = actorGeneration
        isMutating = true
        defer { isMutating = false }
        do {
            try await pendingStore.remove(for: ownerID)
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return false }
            pendingCreation = nil
            hasPendingCreationRecoveryIssue = false
            return true
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return false }
            hasPendingCreationRecoveryIssue = true
            presentedError = error.localizedDescription
            return false
        }
    }

    func retryPendingCreationRecovery() async {
        guard let ownerID, !isMutating else { return }
        await restorePendingCreation(
            for: ownerID,
            generation: actorGeneration
        )
    }

    func cancel(challengeID: UUID, requestID: UUID = UUID()) async -> Bool {
        guard configuration.personalChallengeMutationsEnabled,
            let ownerID,
            !isMutating
        else { return false }
        let generation = actorGeneration
        isMutating = true
        defer { isMutating = false }

        let submission: PendingPersonalCancellationSubmission
        do {
            if let pendingCancellation {
                guard
                    pendingCancellation.ownerID == ownerID,
                    pendingCancellation.challengeID == challengeID
                else {
                    throw PendingPersonalCancellationStoreError
                        .conflictingRecord
                }
                submission = pendingCancellation
            } else {
                submission = try PendingPersonalCancellationSubmission(
                    ownerID: ownerID,
                    challengeID: challengeID,
                    requestID: requestID
                )
            }
            return await submitCancellation(
                submission,
                ownerID: ownerID,
                generation: generation
            )
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return false }
            presentedError = error.localizedDescription
            return false
        }
    }

    func retryPendingCancellation() async -> Bool {
        guard
            let ownerID,
            let pendingCancellation,
            !isMutating
        else { return false }
        let generation = actorGeneration
        isMutating = true
        defer { isMutating = false }
        return await submitCancellation(
            pendingCancellation,
            ownerID: ownerID,
            generation: generation
        )
    }

    private func submitCancellation(
        _ submission: PendingPersonalCancellationSubmission,
        ownerID: UUID,
        generation: UUID
    ) async -> Bool {
        do {
            let attempted = try submission.recordingAttempt()
            try await pendingCancellationStore.save(attempted)
            guard isCurrent(ownerID, generation: generation) else {
                return false
            }
            pendingCancellation = attempted
            hasPendingCancellationRecoveryIssue = false
            guard await auth.currentUserID() == ownerID else {
                throw PersonalAccountabilityClientError.accountChanged
            }
            try await client.cancel(
                challengeID: attempted.challengeID,
                requestID: attempted.requestID,
                expectedUserID: ownerID
            )
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return false }
            try await pendingCancellationStore.remove(for: ownerID)
            pendingCancellation = nil
            hasPendingCancellationRecoveryIssue = false
            await refresh()
            await loadDetail(challengeID: attempted.challengeID)
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return false }
            presentedError = error.localizedDescription
            return false
        }
    }

    /// Requests Health authorization and reads steps locally. This is what
    /// unlocks creation: it proves GameTime can see first-party device steps on
    /// this phone, without needing App Attest or a deployed endpoint.
    ///
    /// It deliberately does not set `latestDiagnostic` — that stays the
    /// server's attested record.
    func verifyHealthAccess(timezone: String) async -> Bool {
        guard configuration.activitySyncEnabled else {
            healthReadiness = .unavailable
            presentedError = PersonalAccountabilityClientError
                .diagnosticUnavailable.localizedDescription
            return false
        }
        guard !isVerifyingHealthAccess else { return false }
        let generation = actorGeneration
        isVerifyingHealthAccess = true
        defer { isVerifyingHealthAccess = false }
        do {
            let outcome = try await diagnosticClient.requestAuthorization()
            guard actorGeneration == generation else { return false }
            activityAuthorizationOutcome = outcome
            guard outcome == .requestCompleted else {
                healthReadiness = .unavailable
                return false
            }
            backgroundDeliveryRegistration?.retryRegistration()
            healthReadiness = .authorizationRequested

            let probe = try await diagnosticClient.probeLocalStepAccess(
                timezone: timezone
            )
            guard actorGeneration == generation else { return false }
            healthReadiness = .localStepsObserved(probe)
            return probe.sawTrustedDeviceSteps
        } catch is CancellationError {
            return false
        } catch {
            guard actorGeneration == generation else { return false }
            presentedError = error.localizedDescription
            return false
        }
    }

    func runDiagnostic(timezone: String) async -> Bool {
        guard configuration.activitySyncEnabled, let ownerID else {
            presentedError = PersonalAccountabilityClientError
                .diagnosticUnavailable.localizedDescription
            return false
        }
        guard !isRunningDiagnostic else { return false }
        let generation = actorGeneration
        isRunningDiagnostic = true
        defer { isRunningDiagnostic = false }
        do {
            activityAuthorizationOutcome = try await diagnosticClient
                .requestAuthorization()
            if activityAuthorizationOutcome == .requestCompleted {
                backgroundDeliveryRegistration?.retryRegistration()
            }
            let diagnostic = try await diagnosticClient.runTrustedDiagnostic(
                ownerID: ownerID,
                timezone: timezone
            )
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return false }
            latestDiagnostic = diagnostic
            if diagnostic.isTrusted {
                healthReadiness = .attested(diagnostic)
            }
            await refresh()
            return diagnostic.isTrusted
        } catch is CancellationError {
            return false
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return false }
            presentedError = error.localizedDescription
            return false
        }
    }

    func sync(challengeID: UUID, asOf: Date = Date()) async {
        guard configuration.activitySyncEnabled,
            let ownerID,
            let challenge = detail(for: challengeID),
            !isSyncingActivity,
            !hasPendingActivityRecoveryIssue,
            pendingActivityUploadCount == 0
                || pendingActivityChallengeID == challengeID
        else { return }
        let generation = actorGeneration
        isSyncingActivity = true
        activitySyncStates[challengeID] = .syncing
        defer { isSyncingActivity = false }
        do {
            let outcome = try await activitySync.sync(
                ownerID: ownerID,
                challenge: challenge,
                asOf: asOf
            )
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return }
            switch outcome {
            case .synced(let replayed, let total):
                activitySyncStates[challengeID] =
                    if !configuration.attestedUploadEnabled {
                        .observedLocally(stepTotal: total)
                    } else if replayed {
                        .replayAccepted(stepTotal: total)
                    } else {
                        .synced(stepTotal: total)
                    }
            case .savedRequestAccepted:
                activitySyncStates[challengeID] = .savedRequestAccepted
            case .savedRequestUnavailable:
                activitySyncStates[challengeID] = .savedRequestUnavailable
            case .queuedForRetry(let total):
                activitySyncStates[challengeID] = .queuedForRetry(stepTotal: total)
            case .noReadableData:
                activitySyncStates[challengeID] = .noReadableData
            }
            await restorePendingActivityCount(
                for: ownerID,
                generation: generation
            )
            await refresh()
            await loadDetail(challengeID: challengeID)
        } catch is CancellationError {
            guard isCurrent(ownerID, generation: generation) else { return }
            await restorePendingActivityCount(
                for: ownerID,
                generation: generation
            )
            activitySyncStates[challengeID] = .idle
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return }
            await restorePendingActivityCount(
                for: ownerID,
                generation: generation
            )
            activitySyncStates[challengeID] = .failed(error.localizedDescription)
            presentedError = error.localizedDescription
        }
    }

    func syncState(for challengeID: UUID) -> PersonalActivitySyncViewState {
        activitySyncStates[challengeID] ?? .idle
    }

    func canSyncActivity(
        challengeID: UUID,
        permitsFreshSync: Bool
    ) -> Bool {
        guard
            configuration.activitySyncEnabled,
            !isSyncingActivity,
            !hasPendingActivityRecoveryIssue
        else { return false }
        if pendingActivityUploadCount > 0 {
            return pendingActivityChallengeID == challengeID
        }
        return permitsFreshSync
    }

    func handleBackgroundActivityUpdate(asOf: Date = Date()) async {
        guard configuration.activitySyncEnabled else { return }
        guard let authenticatedOwner = await auth.currentUserID() else {
            return
        }
        if ownerID != authenticatedOwner {
            await activate(ownerID: authenticatedOwner)
        } else {
            await restorePendingActivityCount(
                for: authenticatedOwner,
                generation: actorGeneration
            )
            guard !hasPendingActivityRecoveryIssue else { return }
            if
                let challenge = pendingActivityChallenge(
                    for: authenticatedOwner
                )
            {
                await sync(challengeID: challenge.id, asOf: asOf)
                return
            }
            await refresh()
        }
        if
            let challenge = pendingActivityChallenge(
                for: authenticatedOwner
            )
        {
            await sync(challengeID: challenge.id, asOf: asOf)
            return
        }
        guard
            ownerID == authenticatedOwner,
            !hasPendingActivityRecoveryIssue,
            loadState == .loaded,
            let challenge = openChallenge,
            challenge.permitsActivitySync(at: asOf)
        else { return }
        await sync(challengeID: challenge.id, asOf: asOf)
    }

    private func restorePendingCreation(
        for ownerID: UUID,
        generation: UUID
    ) async {
        do {
            let submission = try await pendingStore.load(for: ownerID)
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return }
            pendingCreation = submission
            hasPendingCreationRecoveryIssue = false
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return }
            pendingCreation = nil
            hasPendingCreationRecoveryIssue = true
            presentedError = error.localizedDescription
        }
    }

    private func restorePendingCancellation(
        for ownerID: UUID,
        generation: UUID
    ) async {
        do {
            let submission = try await pendingCancellationStore.load(
                for: ownerID
            )
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return }
            pendingCancellation = submission
            hasPendingCancellationRecoveryIssue = false
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return }
            pendingCancellation = nil
            hasPendingCancellationRecoveryIssue = true
            presentedError = error.localizedDescription
        }
    }

    private func restorePendingActivityCount(
        for ownerID: UUID,
        generation: UUID
    ) async {
        do {
            let count = try await activitySync.pendingUploadCount(for: ownerID)
            guard
                await isCurrentAuthenticated(ownerID, generation: generation)
            else { return }
            pendingActivityUploadCount = count
            guard count > 0 else {
                pendingActivityChallengeID = nil
                hasPendingActivityRecoveryIssue = false
                return
            }
            do {
                let challengeID = try await activitySync.pendingChallengeID(
                    for: ownerID
                )
                guard
                    await isCurrentAuthenticated(
                        ownerID,
                        generation: generation
                    )
                else { return }
                pendingActivityChallengeID = challengeID
                hasPendingActivityRecoveryIssue = challengeID == nil
            } catch {
                guard isCurrent(ownerID, generation: generation) else {
                    return
                }
                // Keep the known count so creation stays fail-closed even if
                // the queued challenge identity cannot be restored.
                pendingActivityChallengeID = nil
                hasPendingActivityRecoveryIssue = true
            }
        } catch {
            guard isCurrent(ownerID, generation: generation) else { return }
            // Unknown protected-storage state is not the same as an empty
            // queue. Retain any last known owner/count and block creation until
            // a later read proves the queue is clear.
            hasPendingActivityRecoveryIssue = true
        }
    }

    private func pendingActivityChallenge(
        for ownerID: UUID
    ) -> PersonalChallengeDetail? {
        guard
            self.ownerID == ownerID,
            pendingActivityUploadCount > 0,
            let pendingActivityChallengeID
        else {
            return nil
        }
        return detail(for: pendingActivityChallengeID)
    }

    private func isCurrent(_ ownerID: UUID, generation: UUID) -> Bool {
        self.ownerID == ownerID && actorGeneration == generation
    }

    private func isCurrentAuthenticated(
        _ ownerID: UUID,
        generation: UUID
    ) async -> Bool {
        guard isCurrent(ownerID, generation: generation) else {
            return false
        }
        return await auth.currentUserID() == ownerID
    }

    private func clearVolatileState() {
        challenges = []
        detailsByID = [:]
        loadState = .idle
        pendingCreation = nil
        hasPendingCreationRecoveryIssue = false
        pendingCancellation = nil
        hasPendingCancellationRecoveryIssue = false
        latestDiagnostic = nil
        healthReadiness = .unknown
        isVerifyingHealthAccess = false
        eligibilityHold = nil
        eligibilityHoldActive = false
        activityAuthorizationOutcome = nil
        activitySyncStates = [:]
        pendingActivityUploadCount = 0
        pendingActivityChallengeID = nil
        hasPendingActivityRecoveryIssue = false
        isRestoringSavedState = false
        isMutating = false
        isPreparingPayment = false
        isRequestingReview = false
        reviewRequestsByChallengeID = [:]
        isRunningDiagnostic = false
        isSyncingActivity = false
        presentedError = nil
    }
}
