import SwiftUI

struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.todayPath) {
                TodayView()
                    .navigationDestination(for: TodayRoute.self) { route in
                        switch route {
                        case .contest(let id):
                            ContestDetailView(contestID: id)
                        case .friendship(let id):
                            FriendshipDetailView(userID: id)
                        }
                    }
            }
            .tabItem {
                Label("Today", systemImage: "sun.max.fill")
                    .accessibilityIdentifier("tab.today")
            }
            .tag(AppTab.today)

            NavigationStack(path: $router.challengesPath) {
                ChallengesView()
                    .navigationDestination(for: ChallengesRoute.self) { route in
                        switch route {
                        case .contest(let id):
                            ContestDetailView(contestID: id)
                        }
                    }
            }
            .tabItem {
                Label("Challenges", systemImage: "flag.checkered")
                    .accessibilityIdentifier("tab.challenges")
            }
            .tag(AppTab.challenges)

            NavigationStack(path: $router.friendsPath) {
                FriendsView()
                    .navigationDestination(for: FriendsRoute.self) { route in
                        switch route {
                        case .profile(let id):
                            FriendshipDetailView(userID: id)
                        }
                    }
            }
            .tabItem {
                Label("Friends", systemImage: "person.2.fill")
                    .accessibilityIdentifier("tab.friends")
            }
            .tag(AppTab.friends)

            NavigationStack(path: $router.youPath) {
                YouView()
                    .navigationDestination(for: YouRoute.self) { route in
                        switch route {
                        case .trustAndPrivacy:
                            TrustAndPrivacyView()
                        #if DEBUG
                        case .futureContestFixtures:
                            FutureContestFixturesView()
                        #endif
                        }
                    }
            }
            .tabItem {
                Label("You", systemImage: "person.crop.circle")
                    .accessibilityIdentifier("tab.you")
            }
            .tag(AppTab.you)
        }
        .sheet(item: $router.presentedSheet) { destination in
            switch destination {
            case .createChallenge:
                CreateChallengeFlow()
            case .acceptInvitation(let contestID):
                AcceptInvitationView(contestID: contestID)
            }
        }
        .task {
            await model.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await model.refresh() }
        }
    }
}
