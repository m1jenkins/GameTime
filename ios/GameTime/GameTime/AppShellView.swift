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

            AppAccountNavigationView()
            .tabItem {
                Label("You", systemImage: "person.crop.circle")
                    .accessibilityIdentifier("tab.you")
            }
            .tag(AppTab.you)
        }
        .tint(SignalTheme.accent)
        .signalTabChrome()


        .sheet(item: $router.presentedSheet) { destination in
            switch destination {
            case .createPersonalChallenge:
                CreatePersonalChallengeFlow()
            case .createChallenge, .acceptInvitation:
                PersonalV1UnavailableRouteView()
            }
        }
        .onChange(of: scenePhase, initial: true) { _, newPhase in
            if newPhase == .background {
                model.performanceCommitments.clearVisibleContent()
                model.weekly.setActor(model.userID)
                model.metricPrototypes?.setActor(nil)
            }
            guard foregroundRefreshGate.shouldRefresh(after: newPhase) else {
                return
            }
            Task { await personalStore.refresh() }
            Task { await model.performanceCommitments.refresh() }
            Task { await model.weekly.refresh() }
            if model.configuration.weeklyRuntimeEnabled {
                model.metricPrototypes?.setActor(model.userID)
            }
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
        .signalScreenChrome()
    }
}

/// Shared account routes keep support, privacy and sign-out available in both shells.
struct AppAccountNavigationView: View {
    @Environment(AppRouter.self) private var router
    var body: some View {
        @Bindable var router = router
        NavigationStack(path: $router.youPath) {
            YouView()
                .navigationDestination(for: YouRoute.self) { route in
                    switch route {
                    #if DEBUG || STAGING
                    case .duels:
                        DuelHomeView()
                    case .duelInvitation:
                        DuelInvitationView()
                    case .weekly:
                        WeeklyHomeView()
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
    }
}

struct SignalChallengeUnavailableView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            ContentUnavailableView("New challenges aren’t open yet", systemImage: "flag",
                description: Text("You can still view and manage your existing challenges from Home."))
                .signalScreenChrome()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(SignalTheme.accent)
    }
}

/// Uses the real signed-in actor, with a closed client until hosted challenges are accepted.
struct SignalProductShell: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @State private var showingExistingChallenges = false

    var body: some View {
        ChallengeV1Shell(store: model.challengesV1, invitation: model.challengeInvitation,
            logout: { await model.signOut() },
            accountContent: AnyView(AppAccountNavigationView()),
            existingChallenges: AnyView(Button {
                router.selectedTab = .challenges
                showingExistingChallenges = true
            } label: {
                Label("Existing challenges", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }.accessibilityIdentifier("signal.existing-challenges")),
            serviceAvailable: model.configuration.challengeV1RuntimeEnabled,
            personalStepsOnly: model.configuration.privateHealthAccountMode)
            .tint(SignalTheme.accent)
            .environment(\.challengeHealthFlow, model.challengeHealth)
            .task(id: model.userID) {
                model.challengesV1.setActor(model.userID)
                await model.challengesV1.refresh()
                await model.challengeHealth?.refresh()
            }
            .onDisappear { model.challengesV1.hide() }
            .fullScreenCover(isPresented: $showingExistingChallenges) {
                VStack(spacing: 0) {
                    EnvironmentDisclosureBanner(settlementMode: model.configuration.personalSettlementMode, isDemo: false)
                    HStack {
                        Text("Existing challenges").font(.headline)
                        Spacer()
                        Button("Done") { showingExistingChallenges = false }
                            .accessibilityIdentifier("signal.existing.done")
                    }.padding()
                    AppShellView()
                }.background(SignalTheme.canvas)
            }
    }
}
