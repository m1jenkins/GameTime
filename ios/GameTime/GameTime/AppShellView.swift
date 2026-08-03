import SwiftUI

struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PersonalAccountabilityStore.self) private var personalStore
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            NavigationStack(path: $router.todayPath) {
                TodayView()
                    .navigationDestination(for: TodayRoute.self) { route in
                        switch route {
                        case .personalChallenge(let id):
                            PersonalChallengeDetailView(challengeID: id)
                        case .contest, .friendship:
                            PersonalV1UnavailableRouteView()
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
                        case .personalChallenge(let id):
                            PersonalChallengeDetailView(challengeID: id)
                        case .contest:
                            PersonalV1UnavailableRouteView()
                        }
                    }
            }
            .tabItem {
                Label("Challenges", systemImage: "flag.checkered")
                    .accessibilityIdentifier("tab.challenges")
            }
            .tag(AppTab.challenges)

            NavigationStack(path: $router.youPath) {
                YouView()
                    .navigationDestination(for: YouRoute.self) { route in
                        switch route {
                        case .trustAndPrivacy:
                            TrustAndPrivacyView()
                        }
                    }
            }
            .tabItem {
                Label("You", systemImage: "person.crop.circle")
                    .accessibilityIdentifier("tab.you")
            }
            .tag(AppTab.you)
        }
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 15,
                relativeTo: .body
            )
        )
        .tint(CompetitiveTrustTheme.coral)
        .toolbarBackground(
            CompetitiveTrustTheme.paper,
            for: .tabBar
        )
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .environment(\.colorScheme, .light)
        .sheet(item: $router.presentedSheet) { destination in
            switch destination {
            case .createPersonalChallenge:
                CreatePersonalChallengeFlow()
            case .createChallenge, .acceptInvitation:
                PersonalV1UnavailableRouteView()
            }
        }
        .task {
            await personalStore.refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await personalStore.refresh() }
        }
    }
}

private struct PersonalV1UnavailableRouteView: View {
    var body: some View {
        ContentUnavailableView(
            "Unavailable in Personal V1",
            systemImage: "lock.fill",
            description: Text(
                "This preserved legacy surface is not reachable from the personal-accountability app."
            )
        )
        .daybreakScreenChrome()
    }
}
