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
    private(set) var standings: [UUID: DuelStanding] = [:]
    private(set) var charities: [Charity] = []
    private(set) var loadState: ScreenLoadState = .idle
    private(set) var exactHandleResult: ProfileCard?
    private(set) var lastSubmittedHandle: String?
    private(set) var isMutating = false
    private(set) var onboardingNamePrefill = ""
    private(set) var pendingDuel: PendingDuelSubmission?
    private(set) var hasPendingDuelRecoveryIssue = false
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
            let standings = try await services.contests.listStandings(
                userID: userID
            )
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
            self.standings = standings
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

    func createDuel(_ terms: DuelTerms) async -> UUID? {
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
        guard !hasPendingDuelRecoveryIssue else {
            presentedError =
                "Resolve or discard the unreadable saved duel before sending another request."
            return nil
        }
        guard !isMutating else { return nil }
        isMutating = true
        defer { isMutating = false }

        let submission: PendingDuelSubmission
        if let pendingDuel {
            guard pendingDuel.ownerID == userID else {
                hasPendingDuelRecoveryIssue = true
                presentedError =
                    "The saved duel does not belong to the active account."
                return nil
            }
            guard pendingDuel.terms.requestID == terms.requestID else {
                presentedError =
                    "Review or discard the saved duel before starting another request."
                return nil
            }
            guard pendingDuel.terms == terms else {
                presentedError =
                    AppMutationError.duplicateRequestChanged.localizedDescription
                return nil
            }
            submission = pendingDuel
        } else {
            submission = PendingDuelSubmission(
                ownerID: userID,
                terms: terms
            )
        }

        let attemptedSubmission: PendingDuelSubmission
        do {
            attemptedSubmission = try submission.recordingAttempt()
            try await services.pendingDuels.save(attemptedSubmission)
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return nil
            }
            pendingDuel = attemptedSubmission
        } catch {
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return nil
            }
            hasPendingDuelRecoveryIssue = true
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
            let createdID = try await services.contests.createDuel(
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
                try await services.pendingDuels.remove(for: userID)
            } catch {
                guard
                    isCurrentActor(userID, generation: actorGeneration)
                else {
                    return nil
                }
                hasPendingDuelRecoveryIssue = true
                presentedError =
                    "The duel was confirmed, but its saved retry could not be removed. Retry recovery remains locked to prevent a duplicate request."
                await refresh()
                return nil
            }
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return nil
            }
            pendingDuel = nil
            hasPendingDuelRecoveryIssue = false
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
                    "GameTime couldn’t confirm the duel result. The exact request was saved for a deliberate retry."
            } else {
                present(error)
            }
            return nil
        }
    }

    func discardPendingDuel() async -> Bool {
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
            try await services.pendingDuels.remove(for: userID)
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: actorGeneration
                )
            else {
                return false
            }
            pendingDuel = nil
            hasPendingDuelRecoveryIssue = false
            return true
        } catch {
            guard isCurrentActor(userID, generation: actorGeneration) else {
                return false
            }
            hasPendingDuelRecoveryIssue = true
            present(error)
            return false
        }
    }

    func retryPendingDuelRecovery() async {
        guard let userID, !isMutating else { return }
        let actorGeneration = authGeneration
        isMutating = true
        defer { isMutating = false }
        await restorePendingDuel(
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

    /// Settled duels, most recently ended first — the Duels list's "Done"
    /// segment and Today's trailing row.
    var completedContests: [ContestCard] {
        contests
            .filter { $0.status == .finalized || $0.status == .cancelled }
            .sorted { $0.endsAt > $1.endsAt }
    }

    /// The duel Today leads with: the live one ending soonest.
    var headlineContest: ContestCard? {
        activeAndUpcomingContests
            .filter { $0.status == .active }
            .min { $0.endsAt < $1.endsAt }
            ?? activeAndUpcomingContests.first
    }

    /// Rope data for a duel. Absent progress is represented, not invented — an
    /// empty standing renders the rope at parity with nothing synced.
    func standing(for contestID: UUID) -> DuelStanding {
        standings[contestID] ?? DuelStanding()
    }

    /// The opponent, preferring the standing's roster and falling back to the
    /// friend who created the duel.
    func opponent(for contest: ContestCard) -> ProfileCard? {
        if let opponent = standings[contest.id]?.opponent {
            return opponent
        }
        guard let createdBy = contest.createdBy, createdBy != userID else {
            return nil
        }
        return friendshipCards
            .first { $0.otherUserID == createdBy }?
            .profileCard
    }

    /// Nil while the result is unknown — a settled duel with no progress read
    /// should not claim a winner.
    func didWin(_ contest: ContestCard) -> Bool? {
        guard let standing = standings[contest.id], standing.hasProgress else {
            return nil
        }
        guard !standing.isLevel else { return nil }
        return standing.isAhead
    }

    /// Whether the Create duel flow can be opened. A saved request blocks a
    /// second duel until it is confirmed or discarded.
    var canStartDuel: Bool {
        configuration.contestMutationsEnabled
            && !hasPendingDuelRecoveryIssue
            && (pendingDuel != nil || !acceptedFriendships.isEmpty)
    }

    /// "You won · Marcus paid $15" — the settlement stated plainly.
    func settlementSummary(for contest: ContestCard) -> String {
        let opponentName = opponent(for: contest)?.firstName ?? "They"
        switch didWin(contest) {
        case true:
            return "You won · \(opponentName) paid \(contest.stakeCompactText)"
        case false:
            return "\(opponentName) won · you paid \(contest.stakeCompactText)"
        case nil:
            return contest.status == .cancelled
                ? "Called off · nothing owed"
                : "Settled · result not synced"
        }
    }

    /// What you have handed over across every duel you lost.
    var givenCents: Int {
        completedContests
            .filter { didWin($0) == false }
            .reduce(0) { $0 + $1.stakeAmountCents }
    }

    /// "Because of you and your friends" — every settled stake, either way.
    var charityTotalCents: Int {
        completedContests
            .filter { didWin($0) != nil }
            .reduce(0) { $0 + $1.stakeAmountCents }
    }

    /// The "2W · 1L" record on the Duels title row.
    var record: (won: Int, lost: Int) {
        completedContests.reduce(into: (won: 0, lost: 0)) { result, contest in
            switch didWin(contest) {
            case true: result.won += 1
            case false: result.lost += 1
            case nil: break
            }
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
        standings = [:]
        charities = []
        exactHandleResult = nil
        lastSubmittedHandle = nil
        onboardingNamePrefill = ""
        pendingDuel = nil
        hasPendingDuelRecoveryIssue = false
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
                await restorePendingDuel(
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

    private func restorePendingDuel(
        for userID: UUID,
        generation: UUID
    ) async {
        do {
            let restored = try await services.pendingDuels.load(for: userID)
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            pendingDuel = restored
            hasPendingDuelRecoveryIssue = false
        } catch {
            guard
                await isCurrentAuthenticatedActor(
                    userID,
                    generation: generation
                )
            else {
                return
            }
            pendingDuel = nil
            hasPendingDuelRecoveryIssue = true
            if let storeError = error as? PendingDuelStoreError {
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
        standings = [:]
        charities = []
        exactHandleResult = nil
        lastSubmittedHandle = nil
        onboardingNamePrefill = ""
        pendingDuel = nil
        hasPendingDuelRecoveryIssue = false
        loadState = .idle
        presentedError = nil
        phase = .signedOut
    }
}
