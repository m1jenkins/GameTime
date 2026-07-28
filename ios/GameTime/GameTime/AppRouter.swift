import Foundation
import Observation

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case today
    case duels
    case friends
    case you

    var id: String { rawValue }
}

enum TodayRoute: Hashable {
    case contest(UUID)
    case result(UUID)
    case friendship(UUID)
}

enum DuelsRoute: Hashable {
    case contest(UUID)
    case result(UUID)
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

/// The Duels list is sorted by who needs attention, and the segmented control
/// picks which partition is showing.
enum DuelsSegment: String, CaseIterable, Identifiable, Sendable {
    case live
    case invites
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .live: "Live"
        case .invites: "Invites"
        case .done: "Done"
        }
    }
}

enum SheetDestination: Identifiable, Hashable {
    case createDuel
    case acceptInvitation(UUID)

    var id: String {
        switch self {
        case .createDuel: "create-duel"
        case .acceptInvitation(let id): "accept-\(id.uuidString)"
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    var selectedTab: AppTab = .today
    var todayPath: [TodayRoute] = []
    var duelsPath: [DuelsRoute] = []
    var friendsPath: [FriendsRoute] = []
    var youPath: [YouRoute] = []
    var duelsSegment: DuelsSegment = .live
    var presentedSheet: SheetDestination?

    func reset() {
        selectedTab = .today
        todayPath = []
        duelsPath = []
        friendsPath = []
        youPath = []
        duelsSegment = .live
        presentedSheet = nil
    }
}
