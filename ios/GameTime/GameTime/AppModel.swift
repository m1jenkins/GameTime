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
    private(set) var loadState: ScreenLoadState = .idle
    private(set) var exactHandleResult: ProfileCard?
    private(set) var lastSubmittedHandle: String?
    private(set) var isMutating = false
    private(set) var onboardingNamePrefill = ""
    var presentedError: String?

    private let services: AppServices
    @ObservationIgnored private var authObservationTask: Task<Void, Never>?
    @ObservationIgnored private var hasStarted = false
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
        authObservationTask = Task { @MainActor [weak self] in
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { return }
                await self.resolveAuthentication(userID: snapshot.userID)
            }
        }

        await resolveAuthentication(
            userID: await services.auth.currentUserID()
        )
    }

    func retryLaunch() async {
        phase = .launching
        presentedError = nil
        await resolveAuthentication(
            userID: await services.auth.currentUserID()
        )
    }

    func signInWithApple(_ identity: AppleIdentity) async {
        isMutating = true
        defer { isMutating = false }
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

        isMutating = true
        defer { isMutating = false }
        do {
            profile = try await services.profiles.createProfile(
                userID: userID,
                handle: exactHandle,
                displayName: cleanName,
                timezone: TimeZone.current.identifier
            )
            onboardingNamePrefill = ""
            phase = .signedIn
            await refresh()
        } catch is CancellationError {
            return
        } catch {
            present(error)
        }
    }

    func refresh() async {
        guard phase == .signedIn, let userID else { return }
        let generation = UUID()
        refreshGeneration = generation
        loadState = .loading

        do {
            let cards = try await services.friendships.listCards()
            let contests = try await services.contests.listContests(
                userID: userID
            )
            let charities = try await services.contests.listCharities()
            guard generation == refreshGeneration, !Task.isCancelled else {
                return
            }
            friendshipCards = cards
            self.contests = contests
            self.charities = charities
            loadState = cards.isEmpty && contests.isEmpty
                ? .empty
                : .loaded
        } catch is CancellationError {
            return
        } catch {
            guard generation == refreshGeneration else { return }
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
        var createdID: UUID?
        await mutate {
            createdID = try await services.contests.createDuel(terms)
        }
        return createdID
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
        isMutating = true
        defer { isMutating = false }
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

        self.userID = userID
        phase = .launching
        do {
            if let profile = try await services.profiles.currentProfile(
                userID: userID
            ) {
                self.profile = profile
                onboardingNamePrefill = ""
                phase = .signedIn
                await refresh()
            } else {
                profile = nil
                phase = .onboarding
                loadState = .idle
            }
        } catch is CancellationError {
            return
        } catch {
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

    private func clearUserState() {
        refreshGeneration = UUID()
        userID = nil
        profile = nil
        friendshipCards = []
        contests = []
        charities = []
        exactHandleResult = nil
        lastSubmittedHandle = nil
        onboardingNamePrefill = ""
        loadState = .idle
        presentedError = nil
        phase = .signedOut
    }
}
