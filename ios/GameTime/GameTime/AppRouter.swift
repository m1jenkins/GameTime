import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case challenges
    case friends
    case you

    var id: String { rawValue }
}

enum TodayRoute: Hashable {
    case contest(UUID)
    case friendship(UUID)
}

enum ChallengesRoute: Hashable {
    case contest(UUID)
}

enum FriendsRoute: Hashable {
    case profile(UUID)
}

enum YouRoute: Hashable {
    case trustAndPrivacy
    #if DEBUG
    case futureContestFixtures
    #endif
}

enum SheetDestination: Identifiable, Hashable {
    case createChallenge
    case acceptInvitation(UUID)

    var id: String {
        switch self {
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
}
