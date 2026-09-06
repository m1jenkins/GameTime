import SwiftUI

struct AppShellView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @Environment(PersonalAccountabilityStore.self) private var personalStore
    @Environment(AppRouter.self) private var router
    @State private var foregroundRefreshGate =
        AppShellForegroundRefreshGate()

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
                        #if DEBUG || STAGING
                        case .duels:
                            DuelHomeView()
                        case .duelInvitation:
                            DuelInvitationView()
                        case .performanceCommitments:
                            PerformanceCommitmentHomeView()
                        #endif
                        case .trustAndPrivacy:
                            TrustAndPrivacyView()
                        case .accountSupport:
                            AccountSupportView()
                        }
                    }
            }
            .tabItem {
                Label("You", systemImage: "person.crop.circle")
                    .accessibilityIdentifier("tab.you")
            }
            .tag(AppTab.you)
        }
        .tint(CompetitiveTrustTheme.actionCoral)
        .toolbarBackground(
            CompetitiveTrustTheme.paper,
            for: .tabBar
        )
        .toolbarBackground(.visible, for: .tabBar)
        .toolbarColorScheme(.light, for: .tabBar)
        .preferredColorScheme(.light)
        .sheet(item: $router.presentedSheet) { destination in
            switch destination {
            case .createPersonalChallenge:
                CreatePersonalChallengeFlow()
            case .createChallenge, .acceptInvitation:
                PersonalV1UnavailableRouteView()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            if newPhase == .background { model.performanceCommitments.clearVisibleContent() }
            guard foregroundRefreshGate.shouldRefresh(after: newPhase) else {
                return
            }
            Task { await personalStore.refresh() }
            Task { await model.performanceCommitments.refresh() }
        }
    }
}

struct AppShellForegroundRefreshGate {
    private var hasEnteredBackground = false

    mutating func shouldRefresh(after phase: ScenePhase) -> Bool {
        if phase == .background {
            hasEnteredBackground = true
            return false
        }
        guard phase == .active, hasEnteredBackground else { return false }
        hasEnteredBackground = false
        return true
    }
}

private struct PersonalV1UnavailableRouteView: View {
    var body: some View {
        ContentUnavailableView(
            "Not available yet",
            systemImage: "lock.fill",
            description: Text(
                "This part of the app isn’t open right now."
            )
        )
        .daybreakScreenChrome()
    }
}
