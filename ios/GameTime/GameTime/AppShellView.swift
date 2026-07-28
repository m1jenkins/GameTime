import SwiftUI

/// Four tabs, no cross-tab modality. The native tab bar is hidden so the Glass
/// Arena chrome bar can float over the content — the last card in every list
/// deliberately passes beneath it.
struct AppShellView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    /// True when the selected tab is showing its list root rather than a pushed
    /// screen.
    private var isAtTabRoot: Bool {
        switch router.selectedTab {
        case .today: router.todayPath.isEmpty
        case .duels: router.duelsPath.isEmpty
        case .friends: router.friendsPath.isEmpty
        case .you: router.youPath.isEmpty
        }
    }

    var body: some View {
        @Bindable var router = router

        ZStack(alignment: .bottom) {
            TabView(selection: $router.selectedTab) {
                NavigationStack(path: $router.todayPath) {
                    TodayView()
                        .navigationDestination(for: TodayRoute.self) { route in
                            switch route {
                            case .contest(let id):
                                ContestDetailView(contestID: id)
                            case .result(let id):
                                DuelResultView(contestID: id)
                            case .friendship(let id):
                                FriendshipDetailView(userID: id)
                            }
                        }
                }
                .glassArenaTab()
                .tag(AppTab.today)

                NavigationStack(path: $router.duelsPath) {
                    DuelsView()
                        .navigationDestination(for: DuelsRoute.self) { route in
                            switch route {
                            case .contest(let id):
                                ContestDetailView(contestID: id)
                            case .result(let id):
                                DuelResultView(contestID: id)
                            }
                        }
                }
                .glassArenaTab()
                .tag(AppTab.duels)

                NavigationStack(path: $router.friendsPath) {
                    FriendsView()
                        .navigationDestination(for: FriendsRoute.self) { route in
                            switch route {
                            case .profile(let id):
                                FriendshipDetailView(userID: id)
                            }
                        }
                }
                .glassArenaTab()
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
                .glassArenaTab()
                .tag(AppTab.you)
            }

            // Pushed screens own their bottom edge — Duel detail puts its
            // action bar there, and Result has no chrome at all.
            if isAtTabRoot {
                GlassTabBar(selection: $router.selectedTab)
                    .padding(.horizontal, GlassArenaLayout.tabBarSideInset)
                    .padding(.bottom, GlassArenaLayout.tabBarBottomPadding)
            }
        }
        .sheet(item: $router.presentedSheet) { destination in
            switch destination {
            case .createDuel:
                CreateDuelFlow()
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

private extension View {
    /// Hides the system tab bar so the glass bar can own the bottom of the
    /// screen, and drops the navigation bar in favour of each screen's own
    /// header row.
    func glassArenaTab() -> some View {
        toolbar(.hidden, for: .tabBar)
            .toolbar(.hidden, for: .navigationBar)
    }
}

/// Every Glass Arena screen: the two-layer background, content capped and
/// centred on wide screens, and room at the bottom for the floating bar.
struct GlassArenaScreenScaffold<Content: View>: View {
    let screen: GlassArenaScreen
    /// The two athletes' shares, lifting the substrate curves.
    var lift: (yours: CGFloat, theirs: CGFloat)?
    /// Identifies the screen for UI automation, since these screens draw their
    /// own headers instead of a navigation bar.
    var identifier: String?
    var horizontalPadding: CGFloat = GlassArenaLayout.screenPadding
    var spacing: CGFloat = GlassArenaLayout.cardGap
    var bottomInset: CGFloat = GlassArenaLayout.scrollBottomInset
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) {
                content()
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 10)
            .padding(.bottom, bottomInset)
            // On iPad, cap the content rather than stretching the rope.
            .frame(maxWidth: GlassArenaMetrics.contentCap)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .glassArenaBackground(screen, lift: lift)
        .accessibilityIdentifier(identifier ?? "")
    }
}
