import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case challenges
    case you

    var id: String { rawValue }
}

enum TodayRoute: Hashable {
    case personalChallenge(UUID)
    // Dormant V2/regression routes. The V1 shell never emits them.
    case contest(UUID)
    case friendship(UUID)
}

enum ChallengesRoute: Hashable {
    case personalChallenge(UUID)
    // Dormant V2/regression routes. The V1 shell never emits them.
    case contest(UUID)
}

enum FriendsRoute: Hashable {
    case profile(UUID)
}

enum YouRoute: Hashable {
    case trustAndPrivacy
    case accountSupport
}

enum SheetDestination: Identifiable, Hashable {
    case createPersonalChallenge
    // Dormant V2/regression sheets. The V1 shell never emits them.
    case createChallenge
    case acceptInvitation(UUID)

    var id: String {
        switch self {
        case .createPersonalChallenge: "create-personal-challenge"
        case .createChallenge: "create-challenge"
        case .acceptInvitation(let id): "accept-\(id.uuidString)"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var todayPath: [TodayRoute] = []
    var challengesPath: [ChallengesRoute] = []
    var friendsPath: [FriendsRoute] = []
    var youPath: [YouRoute] = []
    var presentedSheet: SheetDestination?

    func reset() {
        selectedTab = .today
        todayPath = []
        challengesPath = []
        friendsPath = []
        youPath = []
        presentedSheet = nil
    }

    func openPersonalChallenge(_ challengeID: UUID) {
        selectedTab = .challenges
        presentedSheet = nil
        challengesPath = [.personalChallenge(challengeID)]
    }

    func openAccountSupport() {
        selectedTab = .you
        presentedSheet = nil
        youPath = [.accountSupport]
    }
}
