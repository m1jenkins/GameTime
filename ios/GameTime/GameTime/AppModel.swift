import Foundation
import Observation

enum AppPhase: Equatable, Sendable {
    case launching
    case signedOut
    case onboarding
    case signedIn
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
    private(set) var onboardingNamePrefill = ""
    private(set) var profileSetupSubmissionState:
        ProfileSetupSubmissionState = .idle
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
    @ObservationIgnored private var profileSetupMutationID: UUID?
    @ObservationIgnored private var pushRegistration: PushDeviceRegistration?
    @ObservationIgnored private var registeredPushActorID: UUID?

    init(configuration: AppConfiguration, services: AppServices) {
        self.configuration = configuration
        self.services = services
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
                await self.resolveAuthentication(userID: snapshot.userID)
            }
        }
        await resolveAuthentication(userID: initialUserID)

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
        let validation = ProfileSetupValidation(
            displayName: displayName,
            username: handle
        )
        guard let userID else {
            presentedError = "You’re signed out. Sign in again to continue."
            return
        }
        guard phase == .onboarding, !isMutating else { return }
        guard validation.isValid else {
            profileSetupSubmissionState = .validationFailed(
                validation.issues
            )
            return
        }
        let generation = authGeneration
        let mutationID = UUID()

        profileSetupMutationID = mutationID
        isMutating = true
        profileSetupSubmissionState = .submitting
        defer {
            if profileSetupMutationID == mutationID {
                profileSetupMutationID = nil
                isMutating = false
            }
        }
        do {
            let createdProfile = try await services.profiles.createProfile(
                userID: userID,
                handle: validation.username,
                displayName: validation.displayName,
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
            profileSetupSubmissionState = .succeeded
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
            guard isCurrentActor(userID, generation: generation) else {
                return
            }
            profileSetupSubmissionState = .idle
            return
        } catch {
            guard isCurrentActor(userID, generation: generation) else {
                return
            }
            switch AppMutationError.map(error) {
            case .handleUnavailable:
                profileSetupSubmissionState = .usernameUnavailable(
                    username: validation.username
                )
            case .offline:
                profileSetupSubmissionState = .offline
            case .cancelled:
                profileSetupSubmissionState = .idle
            case .duplicateRequestChanged, .localPersistence,
                .permissionDenied, .invalidInput, .server:
                profileSetupSubmissionState = .failed
            }
        }
    }

    func profileSetupInputDidChange(_ field: ProfileSetupField) {
        guard !isMutating else { return }
        switch profileSetupSubmissionState {
        case .idle, .submitting, .succeeded:
            break
        case .usernameUnavailable where field != .username:
            break
        case .validationFailed, .usernameUnavailable, .offline, .failed:
            profileSetupSubmissionState = .idle
        }
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

        let reauthenticatedUserID = try await services.auth.signInWithApple(
            identity
        )
        guard reauthenticatedUserID == ownerID else {
            throw AccountDeletionError.accountChanged
        }

        try await services.accountDeletion.deleteAccount(
            ownerID: ownerID,
            appleAuthorizationCode: authorizationCode
        )

        var cleanupWarning = false
        do {
            try await services.localStateCleanup.clear(for: ownerID)
        } catch {
            cleanupWarning = true
        }

        if let pushRegistration,
            registeredPushActorID == ownerID
        {
            do {
                try await services.pushNotifications.unregister(
                    pushRegistration
                )
            } catch {
                cleanupWarning = true
            }
        }

        do {
            try await services.auth.signOut()
        } catch {
            cleanupWarning = true
        }

        let result: AccountDeletionResult = cleanupWarning
            ? .deletedWithLocalCleanupWarning
            : .deleted
        accountDeletionNotice = switch result {
        case .deleted:
            "Your GameTime account was deleted."
        case .deletedWithLocalCleanupWarning:
            "Your GameTime account was deleted. Some saved data on this phone could not be cleared."
        }
        clearUserState()
        return result
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
            return
        }
        if self.userID == userID,
            phase == .signedIn || phase == .onboarding
        {
            return
        }

        invalidateProfileSetupMutationForAuthenticationChange()
        let generation = UUID()
        authGeneration = generation
        refreshGeneration = UUID()
        self.userID = userID
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
        onboardingNamePrefill = namePrefill ?? ""
        profileSetupSubmissionState = .idle
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
        return await services.auth.currentUserID() == userID
    }

    private func clearUserState() {
        invalidateProfileSetupMutationForAuthenticationChange()
        authGeneration = UUID()
        refreshGeneration = UUID()
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
        profileSetupSubmissionState = .idle
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

    private func invalidateProfileSetupMutationForAuthenticationChange() {
        guard profileSetupMutationID != nil else { return }
        profileSetupMutationID = nil
        if !isPerformingExplicitAuthMutation {
            isMutating = false
        }
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
