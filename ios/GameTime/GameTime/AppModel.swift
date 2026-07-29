import Foundation
import Observation

enum AppPhase: Equatable, Sendable {
    case launching
    case signedOut
    case onboarding
    case signedIn
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
    private(set) var charities: [Charity] = []
    private(set) var standingsByContestID: [UUID: ChallengeStandings] = [:]
    private(set) var standingsLoadStates: [UUID: ScreenLoadState] = [:]
    private(set) var loadState: ScreenLoadState = .idle
    private(set) var exactHandleResult: ProfileCard?
    private(set) var lastSubmittedHandle: String?
    private(set) var isMutating = false
    private(set) var onboardingNamePrefill = ""
    private(set) var pendingChallenge: PendingChallengeSubmission?
    private(set) var hasPendingChallengeRecoveryIssue = false
    var presentedError: String?

    private let services: AppServices
    @ObservationIgnored private var authObservationTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
    @ObservationIgnored private var isPerformingExplicitAuthMutation = false
    @ObservationIgnored private var authGeneration = UUID()
    @ObservationIgnored private var refreshGeneration = UUID()

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
            onboardingNamePrefill = identity.firstSignInDisplayName ?? ""
            await resolveAuthentication(userID: signedInUserID)
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func completeOnboarding(handle: String, displayName: String) async {
        guard let userID else {
            presentedError = "Your sign-in session is no longer available."
            return
        }
        guard let exactHandle = ExactHandleSubmission.normalized(handle) else {
            presentedError =
                "Use 3–30 letters, numbers, or underscores, beginning with a letter."
            return
        }
        let cleanName = displayName.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard (1...50).contains(cleanName.count) else {
            presentedError = "Use a display name between 1 and 50 characters."
            return
        }
        let generation = authGeneration

        isMutating = true
        defer { isMutating = false }
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
            phase = .signedIn
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            guard isCurrentActor(userID, generation: generation) else {
                return
            }
            present(error)
        }
    }

    func refresh() async {
        guard phase == .signedIn, let userID else { return }
        let actorGeneration = authGeneration
        let generation = UUID()
        refreshGeneration = generation
        loadState = .loading

        do {
            let cards = try await services.friendships.listCards()
            let contests = try await services.contests.listContests(
                userID: userID
            )
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

    func submitExactHandle(_ input: String) async {
        exactHandleResult = nil
        guard let exact = ExactHandleSubmission.normalized(input) else {
            lastSubmittedHandle = input
            presentedError =
                "Enter one exact handle: 3–30 letters, numbers, or underscores."
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
        guard let userID else { return }
        await mutate {
            try await services.friendships.acceptFriendship(
                callerID: userID,
                otherUserID: otherUserID
            )
        }
    }

    func removeFriendship(with otherUserID: UUID) async {
        guard let userID else { return }
        await mutate {
            try await services.friendships.removeFriendship(
                callerID: userID,
                otherUserID: otherUserID
            )
        }
    }

    func createChallenge(_ terms: ChallengeTerms) async -> UUID? {
        guard configuration.contestMutationsEnabled else {
            presentedError =
                "Release contest creation stays locked until evidence and App Attest are complete."
            return nil
        }
        guard let userID else {
            presentedError = "Your sign-in session is no longer available."
            return nil
        }
        let actorGeneration = authGeneration
        guard !hasPendingChallengeRecoveryIssue else {
            presentedError =
                "Resolve or discard the unreadable saved challenge before sending another request."
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
                    "The saved challenge does not belong to the active account."
                return nil
            }
            guard pendingChallenge.terms.requestID == terms.requestID else {
                presentedError =
                    "Review or discard the saved challenge before starting another request."
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
                    "The challenge was confirmed, but its saved retry could not be removed. Retry recovery remains locked to prevent a duplicate request."
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
                    "GameTime couldn’t confirm the challenge result. The exact request was saved for a deliberate retry."
            } else {
                present(error)
            }
            return nil
        }
    }

    func discardPendingChallenge() async -> Bool {
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
                "Your sign-in session changed. The saved retry was not discarded."
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
        guard let userID, let profile else { return }
        guard configuration.contestMutationsEnabled else {
            presentedError =
                "Release contest acceptance stays locked until evidence and App Attest are complete."
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
        guard let userID else { return }
        guard configuration.contestMutationsEnabled else {
            presentedError =
                "Release contest responses stay locked until evidence and App Attest are complete."
            return
        }
        await mutate {
            try await services.contests.declineInvitation(
                contestID: contestID,
                userID: userID
            )
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
            try await services.auth.signOut()
            clearUserState()
        } catch is CancellationError {
            return
        } catch {
            present(error)
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

    private func resolveAuthentication(userID: UUID?) async {
        guard let userID else {
            clearUserState()
            return
        }
        if self.userID == userID, phase == .signedIn {
            return
        }

        let generation = UUID()
        authGeneration = generation
        refreshGeneration = UUID()
        self.userID = userID
        profile = nil
        friendshipCards = []
        contests = []
        charities = []
        standingsByContestID = [:]
        standingsLoadStates = [:]
        exactHandleResult = nil
        lastSubmittedHandle = nil
        onboardingNamePrefill = ""
        pendingChallenge = nil
        hasPendingChallengeRecoveryIssue = false
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
                await restorePendingChallenge(
                    for: userID,
                    generation: generation
                )
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
        authGeneration = UUID()
        refreshGeneration = UUID()
        userID = nil
        profile = nil
        friendshipCards = []
        contests = []
        charities = []
        standingsByContestID = [:]
        standingsLoadStates = [:]
        exactHandleResult = nil
        lastSubmittedHandle = nil
        onboardingNamePrefill = ""
        pendingChallenge = nil
        hasPendingChallengeRecoveryIssue = false
        loadState = .idle
        presentedError = nil
        phase = .signedOut
    }
}
