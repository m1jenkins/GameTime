import Foundation
import Observation

enum AppPhase: Equatable, Sendable {
    case launching
    case signedOut
    case onboarding
    case signedIn
}

enum OnboardingErrorField: Equatable, Sendable {
    case name
    case username
    case general
}

struct OnboardingPresentationError: Equatable, Sendable {
    let field: OnboardingErrorField
    let message: String
}

enum ActivitySyncViewState: Equatable, Sendable {
    case idle
    case syncing
    case synced(stepTotal: Double)
    case replayAccepted(stepTotal: Double)
    case savedRequestAccepted
    case savedRequestUnavailable
    case queuedForRetry(stepTotal: Double)
    case noReadableData
    case failed

    var message: String? {
        switch self {
        case .idle:
            nil
        case .syncing:
            "Checking your steps…"
        case let .synced(stepTotal):
            "\(formatted(stepTotal)) steps confirmed."
        case let .replayAccepted(stepTotal):
            "\(formatted(stepTotal)) saved steps confirmed."
        case .savedRequestAccepted:
            "Saved activity confirmed."
        case .savedRequestUnavailable:
            "Steps saved on this phone couldn’t be confirmed. Sync again while the window is open."
        case let .queuedForRetry(stepTotal):
            "\(formatted(stepTotal)) steps are saved and waiting to send. Tap Sync to try again."
        case .noReadableData:
            "We couldn’t find any steps from your phone. Health access may be off or limited."
        case .failed:
            "Your steps aren’t syncing. Check your Health connection."
        }
    }

    private func formatted(_ stepTotal: Double) -> String {
        stepTotal.formatted(
            .number.precision(.fractionLength(0...2))
        )
    }
}

@MainActor
@Observable
final class AppModel {
    let configuration: AppConfiguration
    let challengesV1: ChallengeV1Store
    let challengeInvitation: ChallengeInvitationIntent
    let duels: DuelStore
    let metricPrototypes: MetricPrototypeStore?
    let weekly: WeeklyStore
    let performanceCommitments: PerformanceCommitmentStore

    private(set) var phase: AppPhase = .launching
    private(set) var userID: UUID?
    private(set) var profile: UserProfile?
    private(set) var friendshipCards: [FriendshipCard] = []
    private(set) var contests: [ContestCard] = []
    private(set) var challengeSummaries: [UUID: ChallengeRosterSummary] = [:]
    private(set) var charities: [Charity] = []
    private(set) var standingsByContestID: [UUID: ChallengeStandings] = [:]
    private(set) var standingsLoadStates: [UUID: ScreenLoadState] = [:]
    private(set) var reactedStandingsSnapshotIDs: Set<UUID> = []
    private(set) var reactingStandingsSnapshotID: UUID?
    private(set) var loadState: ScreenLoadState = .idle
    private(set) var exactHandleResult: ProfileCard?
    private(set) var lastSubmittedHandle: String?
    private(set) var isMutating = false
    private(set) var accountDeletionNotice: String?
    private(set) var accountDeletionReceipt: AccountDeletionReceipt?
    private(set) var accountDeletionStatus: AccountDeletionStatus?
    private(set) var accountDeletionStatusError: String?
    private(set) var onboardingNamePrefill = ""
    private(set) var onboardingError: OnboardingPresentationError?
    private(set) var pendingChallenge: PendingChallengeSubmission?
    private(set) var hasPendingChallengeRecoveryIssue = false
    private(set) var activityAuthorizationOutcome:
        ActivityAuthorizationOutcome?
    private(set) var activitySyncStates: [UUID: ActivitySyncViewState] = [:]
    private(set) var pendingActivityUploadCount = 0
    private(set) var isActivityMutating = false
    var presentedError: String?

    private let services: AppServices
    @ObservationIgnored private var authObservationTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isPerformingExplicitAuthMutation = false
    @ObservationIgnored private var authGeneration = UUID()
    @ObservationIgnored private var refreshGeneration = UUID()
    @ObservationIgnored private var pushRegistration: PushDeviceRegistration?
    @ObservationIgnored private var registeredPushActorID: UUID?

    init(configuration: AppConfiguration, services: AppServices, challengeDirectory: URL? = nil,
         challengeInvitation: ChallengeInvitationIntent? = nil) {
        self.configuration = configuration
        self.services = services
        self.challengeInvitation = challengeInvitation ?? ChallengeInvitationIntent(links: configuration.challengeInvitationLinks)
        let challengeDirectory = challengeDirectory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameTime/ProductChallengeV1Pending")
        challengesV1 = ChallengeV1Store(auth: services.auth, client: services.challengesV1,
            requests: ChallengeV1RequestStore(directory: challengeDirectory))
        duels = DuelStore(enabled: configuration.duelRuntimeEnabled,
            auth: services.auth, client: services.duels,
            friendships: services.friendships, pendingStore: services.pendingDuels)
        metricPrototypes = services.metricPrototypes
        weekly = WeeklyStore(enabled: configuration.weeklyRuntimeEnabled, auth: services.auth, client: services.weekly,
            friendships: services.friendships, pendingStore: services.pendingWeekly)
        performanceCommitments = PerformanceCommitmentStore(
            enabled: configuration.performanceCommitmentRuntimeEnabled,
            auth: services.auth, client: services.performanceCommitments,
            pendingStore: services.pendingPerformanceCommitments)
        accountDeletionReceipt = try? services.accountDeletionReceipts.loadLatest()
    }

    deinit {
        authObservationTask?.cancel()
    }

    func start() async {
        guard !hasStarted else { return }
        hasStarted = true

        let stream = await services.auth.authStateChanges()
        let initialUserID = await services.auth.currentUserID()
        authObservationTask = Task { @MainActor [weak self] in
            var isFirstSnapshot = true
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { return }
                if isFirstSnapshot {
                    isFirstSnapshot = false
                    if snapshot.userID == initialUserID {
                        continue
                    }
                }
                while self.isPerformingExplicitAuthMutation {
                    try? await Task.sleep(for: .milliseconds(10))
                    guard !Task.isCancelled else { return }
                }
                // Auth events can queue behind an explicit sign-out/sign-in.
                // Never replay an older actor into the new shared app session.
                let generation = self.authGeneration
                let currentUserID = await self.services.auth.currentUserID()
                guard !self.isPerformingExplicitAuthMutation,
                      self.authGeneration == generation,
                      currentUserID == snapshot.userID else { continue }
                await self.resolveAuthentication(userID: currentUserID)
            }
        }
        await resolveAuthentication(userID: initialUserID)
        await refreshAccountDeletionStatus()

        let liveUserID = await services.auth.currentUserID()
        if liveUserID != userID || (phase == .launching && presentedError == nil) {
            await resolveAuthentication(userID: liveUserID)
        }
    }

    func retryLaunch() async {
        phase = .launching
        presentedError = nil
        await resolveAuthentication(
            userID: await services.auth.currentUserID()
        )
    }

    func signInWithApple(_ identity: AppleIdentity) async {
        isPerformingExplicitAuthMutation = true
        isMutating = true
        onboardingError = nil
        defer {
            isMutating = false
            isPerformingExplicitAuthMutation = false
        }
        do {
            let signedInUserID = try await services.auth.signInWithApple(identity)
            accountDeletionNotice = nil
            await resolveAuthentication(
                userID: signedInUserID,
                namePrefill: identity.firstSignInDisplayName
            )
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func completeOnboarding(handle: String, displayName: String) async {
        guard let userID else {
            onboardingError = OnboardingPresentationError(
                field: .general,
                message: "You’re signed out. Sign in again to continue."
            )
            return
        }
        let cleanName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard (1...50).contains(cleanName.count) else {
            onboardingError = OnboardingPresentationError(
                field: .name,
                message: "Your name needs to be between 1 and 50 characters."
            )
            return
        }
        guard let exactHandle = ExactHandleSubmission.normalized(handle) else {
            onboardingError = OnboardingPresentationError(
                field: .username,
                message:
                    "Usernames are 3–30 letters, numbers, or underscores, and start with a letter."
            )
            return
        }
        let generation = authGeneration

        onboardingError = nil
        isMutating = true
        defer {
            if isCurrentActor(userID, generation: generation) {
                isMutating = false
            }
        }
        do {
            let createdProfile = try await services.profiles.createProfile(
                userID: userID,
                handle: exactHandle,
                displayName: cleanName,
                timezone: TimeZone.current.identifier
            )
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            profile = createdProfile
            onboardingNamePrefill = ""
            onboardingError = nil
            if configuration.legacySocialRuntimeEnabled {
                await restorePendingActivityUploads(
                    for: userID,
                    generation: generation
                )
            }
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            phase = .signedIn
            await refresh()
            await registerPushIfPossible()
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentActor(userID, generation: generation) else {
                return
            }
            let mapped = AppMutationError.map(error)
            onboardingError = OnboardingPresentationError(
                field: mapped == .handleUnavailable ? .username : .general,
                message: mapped.errorDescription
                    ?? "That didn’t go through. Try again."
            )
        }
    }

    func clearOnboardingError() {
        onboardingError = nil
    }

    func refresh() async {
        guard phase == .signedIn, let userID else { return }
        guard configuration.legacySocialRuntimeEnabled else {
            friendshipCards = []
            contests = []
            challengeSummaries = [:]
            charities = []
            loadState = .empty
            return
        }
        let actorGeneration = authGeneration
        let generation = UUID()
        refreshGeneration = generation
        loadState = .loading

        do {
            let cards = try await services.friendships.listCards()
            let summaries = try await services.contests.listChallengeSummaries(
                userID: userID
            )
            let contests = summaries.map(\.contest)
            let charities = try await services.contests.listCharities()
            guard
                generation == refreshGeneration,
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: actorGeneration
                ),
                !Task.isCancelled
            else {
                return
            }
            friendshipCards = cards
            self.contests = contests
            challengeSummaries = Dictionary(
                summaries.map { ($0.id, $0) },
                uniquingKeysWith: { current, _ in current }
            )
            self.charities = charities
            loadState =
                cards.isEmpty && contests.isEmpty
                ? .empty
                : .loaded
        } catch is CancellationError {
            return
        } catch {
            guard
                generation == refreshGeneration,
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: actorGeneration
                )
            else {
                return
            }
            loadState = .failed(
                AppMutationError.map(error).localizedDescription
            )
        }
    }

    func standings(for contestID: UUID) -> ChallengeStandings? {
        standingsByContestID[contestID]
    }

    func standingsLoadState(for contestID: UUID) -> ScreenLoadState {
        standingsLoadStates[contestID] ?? .idle
    }

    func loadStandings(contestID: UUID) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard phase == .signedIn, let userID else { return }
        guard
            let contest = contests.first(where: { $0.id == contestID }),
            contest.myStatus == .accepted,
            contest.status == .active || contest.status == .finalized
        else {
            standingsByContestID[contestID] = nil
            standingsLoadStates[contestID] = .empty
            return
        }

        let generation = authGeneration
        standingsLoadStates[contestID] = .loading
        do {
            let standings = try await services.contests.standings(
                contestID: contestID
            )
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                ),
                !Task.isCancelled
            else {
                return
            }
            if let standings {
                standingsByContestID[contestID] = standings
                standingsLoadStates[contestID] = .loaded
            } else {
                standingsByContestID[contestID] = nil
                standingsLoadStates[contestID] = .empty
            }
        } catch is CancellationError {
            return
        } catch {
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            standingsLoadStates[contestID] = .failed(
                AppMutationError.map(error).localizedDescription
            )
        }
    }

    func hasSentComebackReaction(snapshotID: UUID) -> Bool {
        reactedStandingsSnapshotIDs.contains(snapshotID)
    }

    func sendComebackReaction(
        contestID: UUID,
        snapshotID: UUID
    ) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard phase == .signedIn, let userID else { return }
        guard !reactedStandingsSnapshotIDs.contains(snapshotID) else {
            return
        }
        guard reactingStandingsSnapshotID == nil else { return }
        let generation = authGeneration
        reactingStandingsSnapshotID = snapshotID
        defer {
            if reactingStandingsSnapshotID == snapshotID {
                reactingStandingsSnapshotID = nil
            }
        }

        do {
            try await services.contests.sendComebackReaction(
                contestID: contestID,
                snapshotID: snapshotID
            )
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            reactedStandingsSnapshotIDs.insert(snapshotID)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentActor(userID, generation: generation) else {
                return
            }
            present(error)
        }
    }

    func reactToLatestStandings(contestID: UUID) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        if standingsByContestID[contestID] == nil {
            await loadStandings(contestID: contestID)
        }
        guard
            let standings = standingsByContestID[contestID],
            standings.phase == .provisional
        else {
            return
        }
        await sendComebackReaction(
            contestID: contestID,
            snapshotID: standings.snapshotID
        )
    }

    func receivePushRegistration(
        _ registration: PushDeviceRegistration
    ) async {
        pushRegistration = registration
        await registerPushIfPossible()
    }

    func submitExactHandle(_ input: String) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        exactHandleResult = nil
        guard let exact = ExactHandleSubmission.normalized(input) else {
            lastSubmittedHandle = input
            presentedError =
                "Enter one username: 3–30 letters, numbers, or underscores."
            return
        }
        lastSubmittedHandle = exact
        isMutating = true
        defer { isMutating = false }
        do {
            exactHandleResult = try await services.friendships.findExactHandle(
                exact
            )
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func requestFriendship(with otherUserID: UUID) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard let userID else { return }
        await mutate {
            try await services.friendships.requestFriendship(
                callerID: userID,
                otherUserID: otherUserID
            )
            exactHandleResult = nil
        }
    }

    func acceptFriendship(with otherUserID: UUID) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard let userID else { return }
        await mutate {
            try await services.friendships.acceptFriendship(
                callerID: userID,
                otherUserID: otherUserID
            )
        }
    }

    func removeFriendship(with otherUserID: UUID) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard let userID else { return }
        await mutate {
            try await services.friendships.removeFriendship(
                callerID: userID,
                otherUserID: otherUserID
            )
        }
    }

    func createChallenge(_ terms: ChallengeTerms) async -> UUID? {
        guard configuration.legacySocialRuntimeEnabled else { return nil }
        guard configuration.contestMutationsEnabled else {
            presentedError =
                "Challenges aren’t open yet."
            return nil
        }
        guard let userID else {
            presentedError = "You’re signed out. Sign in again to continue."
            return nil
        }
        let actorGeneration = authGeneration
        guard !hasPendingChallengeRecoveryIssue else {
            presentedError =
                "Sort out or delete your saved draft before starting another one."
            return nil
        }
        guard !isMutating else { return nil }
        isMutating = true
        defer { isMutating = false }

        let submission: PendingChallengeSubmission
        if let pendingChallenge {
            guard pendingChallenge.ownerID == userID else {
                hasPendingChallengeRecoveryIssue = true
                presentedError =
                    "That saved draft belongs to a different account."
                return nil
            }
            guard pendingChallenge.terms.requestID == terms.requestID else {
                presentedError =
                    "Finish or delete your saved draft before starting another one."
                return nil
            }
            guard pendingChallenge.terms == terms else {
                presentedError =
                    AppMutationError.duplicateRequestChanged.localizedDescription
                return nil
            }
            submission = pendingChallenge
        } else {
            submission = PendingChallengeSubmission(
                ownerID: userID,
                terms: terms
            )
        }

        let attemptedSubmission: PendingChallengeSubmission
        do {
            attemptedSubmission = try submission.recordingAttempt()
            try await services.pendingChallenges.save(attemptedSubmission)
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return nil
            }
            pendingChallenge = attemptedSubmission
        } catch {
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return nil
            }
            hasPendingChallengeRecoveryIssue = true
            present(error)
            return nil
        }

        do {
            guard
                isCurrentActor(userID, generation: actorGeneration),
                await services.auth.currentUserID() == userID
            else {
                return nil
            }
            let createdID = try await services.contests.createChallenge(
                terms,
                expectedUserID: userID
            )
            guard
                isCurrentActor(userID, generation: actorGeneration),
                await services.auth.currentUserID() == userID
            else {
                return nil
            }
            do {
                try await services.pendingChallenges.remove(for: userID)
            } catch {
                guard
                    isCurrentActor(userID, generation: actorGeneration)
                else {
                    return nil
                }
                hasPendingChallengeRecoveryIssue = true
                presentedError =
                    "Your challenge started, but we couldn’t clear the draft from your phone. We’ve locked it so you don’t end up with two."
                await refresh()
                return nil
            }
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return nil
            }
            pendingChallenge = nil
            hasPendingChallengeRecoveryIssue = false
            await refresh()
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return nil
            }
            return createdID
        } catch is CancellationError {
            return nil
        } catch {
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return nil
            }
            let mapped = AppMutationError.map(error)
            if mapped == .offline || mapped.isUnknownServerFailure {
                presentedError =
                    "We couldn’t confirm your challenge started. We saved exactly what you picked so you can try again."
            } else {
                present(error)
            }
            return nil
        }
    }

    func discardPendingChallenge() async -> Bool {
        guard configuration.legacySocialRuntimeEnabled else { return false }
        guard let userID else { return false }
        let actorGeneration = authGeneration
        guard !isMutating else { return false }
        isMutating = true
        defer { isMutating = false }
        guard
            await isCurrentAuthenticatedActor(
                userID,
                generation: actorGeneration
            )
        else {
            presentedError =
                "You signed in with a different account, so the draft wasn’t deleted."
            return false
        }
        do {
            try await services.pendingChallenges.remove(for: userID)
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: actorGeneration
                )
            else {
                return false
            }
            pendingChallenge = nil
            hasPendingChallengeRecoveryIssue = false
            return true
        } catch {
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return false
            }
            hasPendingChallengeRecoveryIssue = true
            present(error)
            return false
        }
    }

    func retryPendingChallengeRecovery() async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard let userID, !isMutating else { return }
        let actorGeneration = authGeneration
        isMutating = true
        defer { isMutating = false }
        await restorePendingChallenge(
            for: userID,
            generation: actorGeneration
        )
    }

    func acceptInvitation(contestID: UUID, charityID: UUID) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard let userID, let profile else { return }
        guard configuration.contestMutationsEnabled else {
            presentedError =
                "Challenges aren’t open yet."
            return
        }
        await mutate {
            try await services.contests.acceptInvitation(
                contestID: contestID,
                userID: userID,
                timezone: profile.timezone,
                charityID: charityID
            )
        }
    }

    func declineInvitation(contestID: UUID) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard let userID else { return }
        guard configuration.contestMutationsEnabled else {
            presentedError =
                "Challenges aren’t open yet."
            return
        }
        await mutate {
            try await services.contests.declineInvitation(
                contestID: contestID,
                userID: userID
            )
        }
    }

    func enableActivity() async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard configuration.activitySyncEnabled else {
            presentedError =
                "Activity updates aren’t available yet."
            return
        }
        guard let userID else {
            presentedError = "Sign in again to turn on activity updates."
            return
        }
        guard !isActivityMutating else { return }
        let generation = authGeneration
        isActivityMutating = true
        defer { isActivityMutating = false }

        do {
            let outcome = try await services.activitySync
                .requestAuthorization()
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            activityAuthorizationOutcome = outcome
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentActor(userID, generation: generation) else {
                return
            }
            presentedError = error.localizedDescription
        }
    }

    func activitySyncState(
        for contestID: UUID
    ) -> ActivitySyncViewState {
        activitySyncStates[contestID] ?? .idle
    }

    func syncActivity(contestID: UUID) async {
        guard configuration.legacySocialRuntimeEnabled else { return }
        guard configuration.activitySyncEnabled else {
            presentedError =
                "Activity updates aren’t available yet."
            return
        }
        guard let userID else {
            presentedError = "Sign in again to sync your steps."
            return
        }
        guard
            let contest = contests.first(where: { $0.id == contestID })
        else {
            presentedError = "Pull to refresh, then sync again."
            return
        }
        guard !isActivityMutating else { return }
        let generation = authGeneration
        isActivityMutating = true
        activitySyncStates[contestID] = .syncing
        defer { isActivityMutating = false }

        do {
            let outcome = try await services.activitySync.sync(
                ownerID: userID,
                contest: contest,
                asOf: Date()
            )
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            switch outcome {
            case let .synced(replayed, stepTotal):
                activitySyncStates[contestID] = replayed
                    ? .replayAccepted(stepTotal: stepTotal)
                    : .synced(stepTotal: stepTotal)
            case .savedRequestAccepted:
                activitySyncStates[contestID] = .savedRequestAccepted
            case .savedRequestUnavailable:
                activitySyncStates[contestID] = .savedRequestUnavailable
            case let .queuedForRetry(stepTotal):
                activitySyncStates[contestID] = .queuedForRetry(
                    stepTotal: stepTotal
                )
            case .noReadableData:
                activitySyncStates[contestID] = .noReadableData
            }
            let pendingCount = try await services.activitySync
                .pendingUploadCount(for: userID)
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            pendingActivityUploadCount = pendingCount
        } catch is CancellationError {
            guard isCurrentActor(userID, generation: generation) else {
                return
            }
            activitySyncStates[contestID] = .idle
        } catch {
            guard isCurrentActor(userID, generation: generation) else {
                return
            }
            activitySyncStates[contestID] = .failed
            presentedError = error.localizedDescription
            let pendingCount = try? await services.activitySync
                .pendingUploadCount(for: userID)
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            if let pendingCount {
                pendingActivityUploadCount = pendingCount
            }
        }
    }

    func signOut() async {
        isPerformingExplicitAuthMutation = true
        isMutating = true
        defer {
            isMutating = false
            isPerformingExplicitAuthMutation = false
        }
        do {
            if let pushRegistration,
                registeredPushActorID == userID
            {
                try? await services.pushNotifications.unregister(
                    pushRegistration
                )
                registeredPushActorID = nil
            }
            try await services.auth.signOut()
            clearUserState()
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func deleteAccount(
        with identity: AppleIdentity
    ) async throws -> AccountDeletionResult {
        guard let ownerID = userID else {
            throw AccountDeletionError.authenticationRequired
        }
        let generation = authGeneration
        guard let authorizationCode = identity.authorizationCode,
            !authorizationCode.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).isEmpty
        else {
            throw AccountDeletionError.authorizationCodeUnavailable
        }

        isPerformingExplicitAuthMutation = true
        isMutating = true
        defer {
            isMutating = false
            isPerformingExplicitAuthMutation = false
        }

        let receipt = try deletionReceipt(for: ownerID)
        let reauthenticatedUserID = try await services.auth.signInWithApple(
            identity
        )
        guard reauthenticatedUserID == ownerID,
            await isCurrentAuthenticatedActor(ownerID, generation: generation)
        else {
            throw AccountDeletionError.accountChanged
        }

        let status: AccountDeletionStatus
        do {
            status = try await services.accountDeletion.deleteAccount(
                ownerID: ownerID,
                requestID: receipt.requestID,
                receiptSecret: receipt.secret,
                appleAuthorizationCode: authorizationCode
            )
        } catch {
            // A lost response can happen after the server has accepted the
            // immutable request. Recover that exact state before telling the
            // person to begin again.
            guard let recovered = try? await services.accountDeletion
                .accountDeletionStatus(receiptSecret: receipt.secret)
            else { throw error }
            status = recovered
        }
        return await finishAcceptedAccountDeletion(
            ownerID: ownerID,
            receipt: receipt,
            status: status,
            generation: generation
        )
    }

    func refreshAccountDeletionStatus() async {
        guard let receipt = accountDeletionReceipt else { return }
        let visibleOwnerID = userID
        accountDeletionStatusError = nil
        do {
            let status = try await services.accountDeletion
                .accountDeletionStatus(receiptSecret: receipt.secret)
            guard receipt == accountDeletionReceipt,
                visibleOwnerID == userID,
                userID == nil || userID == receipt.ownerID
            else { return }
            accountDeletionStatus = status
        } catch {
            guard receipt == accountDeletionReceipt,
                visibleOwnerID == userID
            else { return }
            if case AccountDeletionError.receiptExpired = error {
                try? services.accountDeletionReceipts.remove(for: receipt.ownerID)
                accountDeletionReceipt = nil
                accountDeletionStatus = nil
                accountDeletionStatusError = AccountDeletionError.receiptExpired
                    .localizedDescription
            } else {
                // Keep the opaque receipt and the last known status. A network
                // interruption is recoverable; authorization-shaped failures
                // must never erase the only post-sign-out recovery path.
                accountDeletionStatusError = error.localizedDescription
            }
        }
    }

    func resumeAccountDeletion(with identity: AppleIdentity?) async throws
        -> AccountDeletionResult
    {
        guard let receipt = accountDeletionReceipt else {
            throw AccountDeletionError.authenticationRequired
        }
        if let userID, userID != receipt.ownerID {
            throw AccountDeletionError.accountChanged
        }
        let generation = authGeneration
        let status = try await services.accountDeletion.resumeAccountDeletion(
            requestID: receipt.requestID,
            receiptSecret: receipt.secret,
            appleAuthorizationCode: identity?.authorizationCode
        )
        return await finishAcceptedAccountDeletion(
            ownerID: receipt.ownerID,
            receipt: receipt,
            status: status,
            generation: generation
        )
    }

    func fileAccountDeletionReview(
        notice: AccountDeletionStatus.ReviewNotice,
        reason: String
    ) async throws {
        guard let receipt = accountDeletionReceipt else {
            throw AccountDeletionError.authenticationRequired
        }
        let request = try pendingRightsRequest(
            for: receipt,
            operation: .review,
            challengeID: notice.challengeID,
            noticeRevision: notice.noticeRevision,
            reason: reason
        )
        do {
            try await services.accountDeletion.fileAccountDeletionReview(
                requestID: request.id,
                receiptSecret: receipt.secret,
                challengeID: notice.challengeID,
                noticeRevision: notice.noticeRevision,
                reason: reason
            )
            try clearPendingRightsRequest(for: receipt)
            await refreshAccountDeletionStatus()
        } catch {
            try await reconcileDefinitiveRightsRejection(error, for: receipt)
            throw error
        }
    }

    func fileAccountDeletionAppeal() async throws {
        guard let receipt = accountDeletionReceipt else {
            throw AccountDeletionError.authenticationRequired
        }
        let request = try pendingRightsRequest(
            for: receipt,
            operation: .appeal,
            challengeID: nil,
            noticeRevision: nil,
            reason: nil
        )
        do {
            try await services.accountDeletion.fileAccountDeletionAppeal(
                requestID: request.id,
                receiptSecret: receipt.secret
            )
            try clearPendingRightsRequest(for: receipt)
            await refreshAccountDeletionStatus()
        } catch {
            try await reconcileDefinitiveRightsRejection(error, for: receipt)
            throw error
        }
    }

    var hasPendingAccountDeletionRightsRequest: Bool {
        accountDeletionReceipt?.pendingRightsRequest != nil
    }

    func retryPendingAccountDeletionRightsRequest() async throws {
        guard let receipt = accountDeletionReceipt,
            let request = receipt.pendingRightsRequest
        else { return }
        do {
            switch request.operation {
            case .review:
                guard let challengeID = request.challengeID,
                    let noticeRevision = request.noticeRevision,
                    let reason = request.reason
                else { throw AccountDeletionError.invalidResponse }
                try await services.accountDeletion.fileAccountDeletionReview(
                    requestID: request.id,
                    receiptSecret: receipt.secret,
                    challengeID: challengeID,
                    noticeRevision: noticeRevision,
                    reason: reason
                )
            case .appeal:
                try await services.accountDeletion.fileAccountDeletionAppeal(
                    requestID: request.id,
                    receiptSecret: receipt.secret
                )
            }
            try clearPendingRightsRequest(for: receipt)
            await refreshAccountDeletionStatus()
        } catch {
            try await reconcileDefinitiveRightsRejection(error, for: receipt)
            throw error
        }
    }

    private func pendingRightsRequest(
        for receipt: AccountDeletionReceipt,
        operation: AccountDeletionRightsOperation,
        challengeID: UUID?,
        noticeRevision: Int?,
        reason: String?
    ) throws -> AccountDeletionRightsRequest {
        let requested = AccountDeletionRightsRequest(
            id: UUID(),
            operation: operation,
            challengeID: challengeID,
            noticeRevision: noticeRevision,
            reason: reason
        )
        if let pending = receipt.pendingRightsRequest {
            guard pending.operation == operation,
                pending.challengeID == challengeID,
                pending.noticeRevision == noticeRevision,
                pending.reason == reason
            else { throw AccountDeletionError.unavailable }
            return pending
        }
        var savedReceipt = receipt
        savedReceipt.pendingRightsRequest = requested
        try services.accountDeletionReceipts.save(savedReceipt)
        accountDeletionReceipt = savedReceipt
        return requested
    }

    private func clearPendingRightsRequest(
        for receipt: AccountDeletionReceipt
    ) throws {
        var savedReceipt = receipt
        savedReceipt.pendingRightsRequest = nil
        try services.accountDeletionReceipts.save(savedReceipt)
        if accountDeletionReceipt?.ownerID == receipt.ownerID {
            accountDeletionReceipt = savedReceipt
        }
    }

    private func reconcileDefinitiveRightsRejection(
        _ error: Error,
        for receipt: AccountDeletionReceipt
    ) async throws {
        // A non-2xx rejection is a durable answer: retaining its fresh UUID
        // would block another still-open review or appeal. Transport, decode,
        // and server failures remain exact retries because their outcome is
        // genuinely ambiguous.
        guard error as? AccountDeletionError == .rejected else { return }
        try clearPendingRightsRequest(for: receipt)
        await refreshAccountDeletionStatus()
    }

    private func deletionReceipt(for ownerID: UUID) throws -> AccountDeletionReceipt {
        if let receipt = try services.accountDeletionReceipts.load(for: ownerID) {
            accountDeletionReceipt = receipt
            return receipt
        }
        if let accountDeletionReceipt, accountDeletionReceipt.ownerID == ownerID {
            return accountDeletionReceipt
        }
        let receipt = AccountDeletionReceipt(
            ownerID: ownerID,
            secret: UUID().uuidString.replacingOccurrences(of: "-", with: "")
        )
        try services.accountDeletionReceipts.save(receipt)
        accountDeletionReceipt = receipt
        return receipt
    }

    private func finishAcceptedAccountDeletion(
        ownerID: UUID,
        receipt: AccountDeletionReceipt,
        status: AccountDeletionStatus,
        generation: UUID
    ) async -> AccountDeletionResult {
        let result = deletionResult(for: status)
        // The accepted request is already durable. If its response arrives
        // after another account becomes current, preserve its receipt but do
        // not clear, sign out, or overwrite that other account's local state.
        let signedOutRecovery = userID == nil && accountDeletionReceipt == receipt
        let isCurrentOwner = await isCurrentAuthenticatedActor(
            ownerID,
            generation: generation
        )
        guard isCurrentOwner || signedOutRecovery else { return result }
        accountDeletionReceipt = receipt
        accountDeletionStatus = status
        accountDeletionStatusError = nil

        // Acceptance already cleared the ordinary account. A signed-out
        // receipt resume may finish provider/account work but must not try to
        // clear a different person's current device state.
        guard isCurrentOwner else { return result }

        challengesV1.setActor(nil)
        // The existing cleaner removes the persisted invitation. End its
        // in-memory visibility immediately, even if disk cleanup needs recovery.
        challengeInvitation.link = ""
        challengeInvitation.message = nil
        duels.setActor(nil)
        performanceCommitments.setActor(nil)
        weekly.setActor(nil)
        metricPrototypes?.setActor(nil)
        var cleanupWarning = false
        do {
            try await services.localStateCleanup.clear(for: ownerID)
        } catch {
            cleanupWarning = true
        }

        let canUnregisterPush = await isCurrentAuthenticatedActor(
            ownerID,
            generation: generation
        )
        if let pushRegistration,
            registeredPushActorID == ownerID,
            canUnregisterPush
        {
            do {
                try await services.pushNotifications.unregister(
                    pushRegistration
                )
            } catch {
                cleanupWarning = true
            }
        }

        if await isCurrentAuthenticatedActor(ownerID, generation: generation) {
            do {
                try await services.auth.signOut()
            } catch {
                cleanupWarning = true
            }
        }

        let completedResult: AccountDeletionResult = result == .deleted && cleanupWarning
            ? .deletedWithLocalCleanupWarning : result
        let currentUserID = await services.auth.currentUserID()
        guard isCurrentActor(ownerID, generation: generation),
            currentUserID == nil || currentUserID == ownerID
        else { return completedResult }
        accountDeletionNotice = switch result {
        case .deleted:
            "We closed your account. You can check the saved account-deletion receipt here."
        case .deletedWithLocalCleanupWarning:
            "We closed your account, but some saved data on this phone could not be cleared. You can check the saved account-deletion receipt here."
        case .pendingProvider:
            "We stopped access and saved your account-deletion receipt. We still need to finish account closure."
        case .held:
            "We closed ordinary access and saved your account-deletion receipt. A review or appeal is still open."
        }
        if isCurrentActor(ownerID, generation: generation) {
            clearUserState()
        }
        return completedResult
    }

    private func deletionResult(for status: AccountDeletionStatus) -> AccountDeletionResult {
        switch status.state {
        case .completed: .deleted
        case .held: .held
        case .pendingProvider, .pendingAccountClose: .pendingProvider
        }
    }

    var incomingFriendships: [FriendshipCard] {
        guard let userID else { return [] }
        return friendshipCards.filter {
            $0.direction(for: userID) == .incoming
        }
    }

    var outgoingFriendships: [FriendshipCard] {
        guard let userID else { return [] }
        return friendshipCards.filter {
            $0.direction(for: userID) == .outgoing
        }
    }

    var acceptedFriendships: [FriendshipCard] {
        guard let userID else { return [] }
        return friendshipCards.filter {
            $0.direction(for: userID) == .accepted
        }
    }

    var invitations: [ContestCard] {
        contests.filter { $0.myStatus == .invited }
    }

    var activeAndUpcomingContests: [ContestCard] {
        contests.filter {
            $0.myStatus == .accepted
                && ($0.status == .active || $0.status == .pending)
        }
    }

    private func resolveAuthentication(
        userID: UUID?,
        namePrefill: String? = nil
    ) async {
        guard let userID else {
            clearUserState()
            accountDeletionReceipt = try? services.accountDeletionReceipts
                .loadLatest()
            accountDeletionStatus = nil
            accountDeletionStatusError = nil
            return
        }
        if self.userID == userID, phase == .signedIn {
            return
        }

        let resolvedNamePrefill = namePrefill
            ?? (self.userID == userID ? onboardingNamePrefill : "")
        let generation = UUID()
        authGeneration = generation
        refreshGeneration = UUID()
        if !isPerformingExplicitAuthMutation { isMutating = false }
        self.userID = userID
        accountDeletionNotice = nil
        accountDeletionReceipt = try? services.accountDeletionReceipts
            .load(for: userID)
        accountDeletionStatus = nil
        accountDeletionStatusError = nil
        challengesV1.setActor(userID)
        duels.setActor(userID)
        performanceCommitments.setActor(userID)
        weekly.setActor(userID)
        metricPrototypes?.setActor(configuration.weeklyRuntimeEnabled ? userID : nil)
        profile = nil
        friendshipCards = []
        contests = []
        challengeSummaries = [:]
        charities = []
        standingsByContestID = [:]
        standingsLoadStates = [:]
        reactedStandingsSnapshotIDs = []
        reactingStandingsSnapshotID = nil
        exactHandleResult = nil
        lastSubmittedHandle = nil
        onboardingNamePrefill = resolvedNamePrefill
        onboardingError = nil
        pendingChallenge = nil
        hasPendingChallengeRecoveryIssue = false
        activityAuthorizationOutcome = nil
        activitySyncStates = [:]
        pendingActivityUploadCount = 0
        isActivityMutating = false
        registeredPushActorID = nil
        loadState = .idle
        presentedError = nil
        phase = .launching
        do {
            if let profile = try await services.profiles.currentProfile(
                userID: userID
            ) {
                guard
                    await isCurrentAuthenticatedActor(
                        userID,
                        generation: generation
                    )
                else {
                    return
                }
                self.profile = profile
                onboardingNamePrefill = ""
                onboardingError = nil
                if configuration.legacySocialRuntimeEnabled {
                    await restorePendingChallenge(
                        for: userID,
                        generation: generation
                    )
                }
                guard
                    await isCurrentAuthenticatedActor(
                        userID,
                        generation: generation
                    )
                else {
                    return
                }
                if configuration.legacySocialRuntimeEnabled {
                    await restorePendingActivityUploads(
                        for: userID,
                        generation: generation
                    )
                }
                guard
                    await isCurrentAuthenticatedActor(
                        userID,
                        generation: generation
                    )
                else {
                    return
                }
                phase = .signedIn
                await refresh()
                await registerPushIfPossible()
            } else {
                guard
                    await isCurrentAuthenticatedActor(
                        userID,
                        generation: generation
                    )
                else {
                    return
                }
                profile = nil
                onboardingError = nil
                phase = .onboarding
                loadState = .idle
            }
        } catch is CancellationError {
            return
        } catch {
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            presentedError = AppMutationError.map(error).localizedDescription
            phase = .launching
        }
    }

    private func mutate(
        _ operation: () async throws -> Void
    ) async {
        isMutating = true
        defer { isMutating = false }
        do {
            try await operation()
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    private func present(_ error: Error) {
        let mapped = AppMutationError.map(error)
        guard mapped != .cancelled else { return }
        presentedError = mapped.localizedDescription
    }

    private func restorePendingChallenge(
        for userID: UUID,
        generation: UUID
    ) async {
        do {
            let restored = try await services.pendingChallenges.load(for: userID)
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            pendingChallenge = restored
            hasPendingChallengeRecoveryIssue = false
        } catch {
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            pendingChallenge = nil
            hasPendingChallengeRecoveryIssue = true
            if let storeError = error as? PendingChallengeStoreError {
                presentedError = storeError.localizedDescription
            } else {
                present(error)
            }
        }
    }

    private func restorePendingActivityUploads(
        for userID: UUID,
        generation: UUID
    ) async {
        guard configuration.activitySyncEnabled else {
            pendingActivityUploadCount = 0
            return
        }
        do {
            let count = try await services.activitySync.pendingUploadCount(
                for: userID
            )
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            // Restoration is read-only. Uploads move only after an explicit
            // Sync Activity action.
            pendingActivityUploadCount = count
        } catch {
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            pendingActivityUploadCount = 0
            presentedError = error.localizedDescription
        }
    }

    private func isCurrentActor(
        _ userID: UUID,
        generation: UUID
    ) -> Bool {
        self.userID == userID && authGeneration == generation
    }

    private func isCurrentAuthenticatedActor(
        _ userID: UUID,
        generation: UUID
    ) async -> Bool {
        guard isCurrentActor(userID, generation: generation) else {
            return false
        }
        let currentUserID = await services.auth.currentUserID()
        return isCurrentActor(userID, generation: generation)
            && currentUserID == userID
    }

    private func clearUserState() {
        challengesV1.setActor(nil)
        duels.setActor(nil)
        performanceCommitments.setActor(nil)
        weekly.setActor(nil)
        metricPrototypes?.setActor(nil)
        authGeneration = UUID()
        refreshGeneration = UUID()
        if !isPerformingExplicitAuthMutation { isMutating = false }
        userID = nil
        profile = nil
        friendshipCards = []
        contests = []
        challengeSummaries = [:]
        charities = []
        standingsByContestID = [:]
        standingsLoadStates = [:]
        reactedStandingsSnapshotIDs = []
        reactingStandingsSnapshotID = nil
        exactHandleResult = nil
        lastSubmittedHandle = nil
        onboardingNamePrefill = ""
        onboardingError = nil
        pendingChallenge = nil
        hasPendingChallengeRecoveryIssue = false
        activityAuthorizationOutcome = nil
        activitySyncStates = [:]
        pendingActivityUploadCount = 0
        isActivityMutating = false
        registeredPushActorID = nil
        loadState = .idle
        presentedError = nil
        phase = .signedOut
    }

    private func registerPushIfPossible() async {
        guard
            phase == .signedIn,
            let userID,
            let pushRegistration,
            registeredPushActorID != userID
        else {
            return
        }
        let generation = authGeneration
        do {
            try await services.pushNotifications.register(pushRegistration)
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            registeredPushActorID = userID
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentActor(userID, generation: generation) else {
                return
            }
            presentedError =
                "We couldn’t turn on notifications. Everything else still works."
        }
    }
}
