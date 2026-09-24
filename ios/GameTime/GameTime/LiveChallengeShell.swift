import SwiftUI

/// One production presentation for every signed-in account and local client.
/// Source availability governs actions; it never selects a different visual app.
struct LiveChallengeShell: View {
    @Bindable var store: ChallengeV1Store
    @Bindable var invitation: ChallengeInvitationIntent
    let logout: @MainActor () async -> Void
    var profile: UserProfile? = nil
    var accountActor: UUID? = nil
    var accountContent: AnyView? = nil
    var serviceAvailable = true
    /// What the server lets this account create; nil means no restriction.
    var allowedPolicies: Set<String>? = nil
    /// The live-design capture route opens the private trial's personal
    /// choices without changing the ordinary friend create.
    private var creatablePolicies: Set<String>? {
        #if DEBUG
        if LiveDesignFixtures.enabled, ProcessInfo.processInfo.arguments.contains("--live-screen=create-personal") {
            return ChallengeV1Availability.privateTrialPolicies
        }
        #endif
        return allowedPolicies
    }
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.challengeHealthFlow) private var health
    @Environment(\.livePersonalRouteCoordinator) private var personalRouteCoordinator
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @State private var selection = 0
    @State private var homePath: [UUID] = []
    @State private var libraryPath: [UUID] = []
    @State private var recordPath: [UUID] = []
    @State private var create = false
    @State private var settings = false
    @State private var entry = false
    @State private var filter = "All"
    @State private var initialRouteApplied = false

    private var selectedTab: some View {
        Group {
            switch selection {
            case 0:
                NavigationStack(path: $homePath) {
                    LiveHomeView(store: store, profile: profile, serviceAvailable: serviceAvailable,
                                 viewGoal: { homePath.append($0) }, showRecord: { selection = 2 },
                                 create: { create = true }, library: { selection = 1 })
                        .navigationDestination(for: UUID.self) { LiveGoalDetail(store: store, id: $0) }
                }
            case 1:
                NavigationStack(path: $libraryPath) {
                    LiveLibraryView(store: store, filter: $filter, serviceAvailable: serviceAvailable,
                                    create: { create = true }, entry: { entry = true }, open: { libraryPath.append($0) })
                        .navigationDestination(for: UUID.self) { LiveGoalDetail(store: store, id: $0) }
                }
            default:
                NavigationStack(path: $recordPath) {
                    LiveRecordView(store: store, profile: profile, accountActor: accountActor ?? store.actor,
                                   settings: { settings = true })
                }
            }
        }
    }

    private var presentedShell: some View {
        selectedTab
        .tint(SignalTheme.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) { tabBar }
        .background(SignalTheme.canvas.ignoresSafeArea())
        .preferredColorScheme(.light)
        .fullScreenCover(isPresented: $create, onDismiss: { personalRouteCoordinator?.allowPresentation() }) {
            if serviceAvailable {
                ChallengeV1Create(store: store, allowed: creatablePolicies, onGoHome: {
                    selection = 0
                    homePath = []
                    libraryPath = []
                    recordPath = []
                })
            } else {
                LiveUnavailableSheet(title: "New challenges aren’t open yet", message: "You can refresh your saved challenges or return later.")
            }
        }
        .sheet(isPresented: $settings, onDismiss: { personalRouteCoordinator?.allowPresentation() }) {
            NavigationStack {
                if let accountContent { accountContent }
                else {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Settings").liveFont(27, weight: .bold)
                        Text("Simulated stakes · no real money moves").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                        Button("Sign out") { Task { await logout() } }.buttonStyle(LiveSecondaryButtonStyle())
                    }.padding(SignalTheme.contentInset).frame(maxHeight: .infinity, alignment: .top).background(SignalTheme.canvas)
                }
            }.presentationDragIndicator(.visible).tint(SignalTheme.accent)
        }
        .sheet(isPresented: $entry, onDismiss: { personalRouteCoordinator?.allowPresentation() }) {
            NavigationStack {
                ScrollView {
                    ChallengeEntryPanel(store: store, invitation: invitation)
                        .padding(.horizontal, SignalTheme.contentInset).padding(.top, 8).padding(.bottom, 28)
                }.background(SignalTheme.canvas.ignoresSafeArea())
                    .toolbar(.hidden, for: .navigationBar)
                    .safeAreaInset(edge: .top, spacing: 0) {
                        LiveSheetHeader(title: "Your invitation", close: { entry = false })
                    }
            }.tint(SignalTheme.accent).presentationDragIndicator(.visible)
        }
    }

    var body: some View {
        presentedShell
        .onChange(of: store.actor) { _, _ in
            create = false; settings = false; entry = false; selection = 0
            homePath = []; libraryPath = []; recordPath = []; filter = "All"
        }
        .onChange(of: personalRouteCoordinator?.pendingID, initial: true) { _, id in
            guard id != nil else { return }
            if create || settings || entry { create = false; settings = false; entry = false }
            else { personalRouteCoordinator?.allowPresentation() }
        }
        .onChange(of: invitation.link) { _, link in if !link.isEmpty { selection = 1; entry = true } }
        .onChange(of: store.access?.suspended) { _, suspended in health?.restrict(suspended == true) }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { store.hide(); friends?.hide(); health?.cancelAll() }
            else { Task { await store.show(); await friends?.show(); await health?.refresh() } }
        }
        .task(id: store.actor) { await store.watchVisibility() }
        .onChange(of: store.challenges.count) { applyInitialRoute() }
        .onAppear { applyInitialRoute(); if !invitation.link.isEmpty { entry = true; selection = 1 } }
        .environment(\.challengeInvitationLinks, invitation.links)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            tab(0, "Home", "house", "house.fill")
            tab(1, "Challenges", "flag", "flag")
            tab(2, "You", "person", "person")
        }
        .padding(.horizontal, 11).padding(.top, 3).padding(.bottom, 4)
        .background(Color(red: 247/255, green: 248/255, blue: 250/255).ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(SignalTheme.divider).frame(height: 0.75) }
    }
    private func tab(_ index: Int, _ label: String, _ icon: String, _ selectedIcon: String) -> some View {
        Button {
            if selection == index {
                if index == 0 { homePath = [] }
                if index == 1 { libraryPath = [] }
                if index == 2 { recordPath = [] }
            }
            selection = index
        } label: {
            VStack(spacing: 5) {
                Image(systemName: selection == index ? selectedIcon : icon).font(.system(size: 23, weight: .regular))
                Text(label).font(.system(size: 10, weight: selection == index ? .semibold : .regular))
            }.frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(selection == index ? SignalTheme.accent : SignalTheme.textSecondary)
        }.buttonStyle(.plain).accessibilityIdentifier("beta.tab." + label.lowercased())
            .accessibilityAddTraits(selection == index ? .isSelected : [])
    }
    private func applyInitialRoute() {
        #if DEBUG
        guard !initialRouteApplied, LiveDesignFixtures.enabled, !store.challenges.isEmpty else { return }
        initialRouteApplied = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--live-screen=challenges") { selection = 1 }
        if args.contains("--live-screen=you") || args.contains("--live-screen=friends") { selection = 2 }
        if args.contains("--live-screen=goal") || args.contains("--live-screen=rules") { homePath = [LiveDesignFixtures.activeID] }
        if args.contains("--live-screen=settings") { selection = 2; settings = true }
        if args.contains("--live-screen=create") || args.contains("--live-screen=create-personal") { selection = 1; create = true }
        #endif
    }
}

struct LiveHomeView: View {
    @Bindable var store: ChallengeV1Store
    let profile: UserProfile?
    let serviceAvailable: Bool
    let viewGoal: (UUID) -> Void
    let showRecord: () -> Void
    let create: () -> Void
    let library: () -> Void
    @Environment(\.challengeHealthFlow) private var health
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @State private var selectedFriend: LiveFriendSelection?
    private var featured: ChallengeV1? {
        let rows = store.profileSnapshot.rows.filter { !$0.isClosed && $0.own(store.actor)?.exited == false }
        return rows.first { $0.status == "active" && $0.format.mode == .friend }
            ?? rows.first { $0.status == "active" || $0.status == "syncing" }
            ?? rows.filter { $0.status == "scheduled" }.min { $0.config.startsAt < $1.config.startsAt } ?? rows.first
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let row = featured {
                    HomeActionRows(challenges: store, viewGoal: viewGoal).padding(.bottom, homeRowsVisible ? 24 : 0)
                    heading(row)
                    metric(row).padding(.top, 24)
                    let friends = row.members.filter { $0.actorId != store.actor && $0.selected && !$0.exited }
                    if !row.socialHidden, !friends.isEmpty { withYou(row, friends: friends).padding(.top, 28) }
                    else { personalContext(row).padding(.top, 26) }
                    VStack(spacing: 16) {
                        Text("\(LiveChallengePresentation.money(row.config.amountCents)) simulated · fee $0")
                            .liveFont(13).foregroundStyle(SignalTheme.textSecondary)
                        Button { viewGoal(row.id) } label: {
                            HStack(spacing: 10) { Text("View goal"); Image(systemName: "arrow.right").font(.system(size: 18)) }
                        }.buttonStyle(LivePrimaryButtonStyle()).accessibilityIdentifier("live.home.goal")
                        Text(sourceLine(row)).liveFont(11).foregroundStyle(SignalTheme.textSecondary)
                    }.padding(.top, 30).frame(maxWidth: .infinity)
                    LiveRecoveryView(store: store).padding(.top, 12)
                } else {
                    HStack {
                        Text("Home").liveFont(27, weight: .bold).tracking(-1.15)
                        Spacer()
                        Button(action: showRecord) { LiveAvatar(username: profile?.displayName ?? "You", actorID: store.actor, size: 32).frame(width: 44, height: 44) }.accessibilityLabel("Your record")
                    }
                    HomeActionRows(challenges: store, viewGoal: viewGoal).padding(.top, homeRowsVisible ? 22 : 0)
                    if store.homeState == .content {
                        let complete = store.profileSnapshot.availability == .complete
                        VStack(alignment: .leading, spacing: 16) {
                            Text(complete ? "No active challenge" : "Your saved challenges").liveFont(24, weight: .bold).tracking(-0.8)
                            Text(complete ? "Your finished goals are in You." : "Refresh to check your current goals. Your saved records are in You.").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                            if complete && serviceAvailable { Button("Create a challenge", action: create).buttonStyle(LivePrimaryButtonStyle()) }
                            if !complete { Button("Refresh") { Task { await store.refresh() } }.buttonStyle(LiveSecondaryButtonStyle()) }
                            Button("View your record", action: showRecord).font(.subheadline.weight(.semibold))
                                .foregroundStyle(SignalTheme.accent).frame(minHeight: 44)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).modifier(LiveCardModifier()).padding(.top, 30)
                    } else {
                        LiveEmptyState(store: store, serviceAvailable: serviceAvailable, create: create).padding(.top, 30)
                    }
                    LiveRecoveryView(store: store).padding(.top, 18)
                }
            }.padding(.horizontal, SignalTheme.contentInset).padding(.top, 20).padding(.bottom, 16)
        }.background(SignalTheme.canvas).toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh(); await friends?.refresh(); await health?.refresh() }
            .modifier(FriendsNoticeToast(friends: friends))
            .sheet(item: $selectedFriend) { selection in
                LiveFriendSheet(store: store, challengeID: selection.challengeID, personID: selection.personID)
            }
            .onChange(of: store.actor) { selectedFriend = nil }
    }
    private var homeRowsVisible: Bool { !HomeActionRows.items(challenges: store, friends: friends).isEmpty }
    private func heading(_ row: ChallengeV1) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 9) {
                Text(LiveChallengePresentation.title(row)).liveFont(27, weight: .bold).tracking(-1.15)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Text(ChallengePresentation.dates(row)).liveFont(14).foregroundStyle(SignalTheme.textSecondary)
                    let state = LiveChallengePresentation.state(row, actor: store.actor)
                    HStack(spacing: 5) { Circle().frame(width: 5, height: 5); Text(state) }
                        .liveFont(13, weight: .semibold)
                        .foregroundStyle(state == "Behind" ? SignalTheme.danger : state == "No update yet" ? SignalTheme.textSecondary : SignalTheme.accent)
                }.fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button(action: showRecord) { LiveAvatar(username: profile?.displayName ?? "You", actorID: store.actor, size: 32).frame(width: 44, height: 44) }
                .buttonStyle(.plain).accessibilityLabel("Your record").padding(.top, -5)
        }
    }
    private func metric(_ row: ChallengeV1) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(row.format.metric == .distance ? "Your distance" : row.format.metric == .steps ? "Your steps" : "Your activity")
                    .fontWeight(.medium)
                Spacer()
                Text(LiveChallengePresentation.goal(row, actor: store.actor))
            }.liveFont(13).foregroundStyle(SignalTheme.textSecondary)
            LiveMetric(value: LiveChallengePresentation.value(row.own(store.actor).flatMap { row.savedScore($0) }, metric: row.format.metric),
                       unit: LiveChallengePresentation.unit(row.format.metric), size: row.format.metric == .steps ? 83 : 114)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 5).padding(.bottom, 8)
            LiveProgressRail(progress: LiveChallengePresentation.progress(row, actor: store.actor))
            HStack(alignment: .firstTextBaseline) {
                Text(LiveChallengePresentation.remaining(row, actor: store.actor)).fontWeight(.semibold)
                Spacer(minLength: 8)
                Text(LiveChallengePresentation.ends(row)).foregroundStyle(SignalTheme.textSecondary)
            }.liveFont(12).padding(.top, 12)
        }.padding(.horizontal, 20).padding(.top, 21).padding(.bottom, 20).modifier(LiveCardModifier())
            .accessibilityIdentifier("live.home.metric")
    }
    private func withYou(_ row: ChallengeV1, friends: [ChallengeV1.Member]) -> some View {
        VStack(alignment: .leading, spacing: 19) {
            HStack {
                Text("With you").liveFont(19, weight: .semibold).tracking(-0.4)
                Spacer()
                Button { viewGoal(row.id) } label: { Text("\(friends.count) friends ↗").liveFont(12).foregroundStyle(SignalTheme.textSecondary) }
                    .frame(minHeight: 44).padding(.vertical, -12)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: typeSize.isAccessibilitySize ? 2 : min(3, friends.count)), spacing: 18) {
                ForEach(friends.prefix(6)) { friend in
                    Button { selectedFriend = .init(challengeID: row.id, personID: friend.actorId) } label: {
                        VStack(spacing: 0) {
                            ZStack {
                                Circle().stroke(SignalTheme.progressTrack, lineWidth: 4)
                                if let progress = LiveChallengePresentation.progress(row, actor: friend.actorId) {
                                    Circle().trim(from: 0, to: progress).stroke(SignalTheme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round)).rotationEffect(.degrees(-90))
                                }
                                LiveAvatar(username: friend.username, actorID: friend.actorId, size: 55)
                            }.frame(width: 66, height: 66).padding(3)
                            Text(friend.username).liveFont(14, weight: .medium).padding(.top, 10).lineLimit(1)
                            let state = LiveChallengePresentation.state(row, member: friend)
                            HStack(spacing: 3) {
                                if state == "Done" { Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)) }
                                Text(state)
                            }.liveFont(13, weight: .semibold).padding(.top, 4)
                                .foregroundStyle(state == "Behind" ? SignalTheme.danger : state == "No update yet" ? SignalTheme.textSecondary : SignalTheme.accent)
                        }.frame(maxWidth: .infinity)
                    }.buttonStyle(.plain)
                }
            }
        }
    }
    private func personalContext(_ row: ChallengeV1) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lock").font(.system(size: 20)).foregroundStyle(SignalTheme.accent)
            VStack(alignment: .leading, spacing: 4) {
                Text("Your goal").liveFont(15, weight: .semibold)
                Text("Your activity and record stay private.").liveFont(13).foregroundStyle(SignalTheme.textSecondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(16).modifier(LiveCardModifier(radius: 17, material: true))
    }
    private func sourceLine(_ row: ChallengeV1) -> String {
        guard let fact = row.own(store.actor)?.fact else { return "Waiting for activity · Refresh after your Watch syncs" }
        guard row.sourcePolicyVersion != nil else { return "Last saved challenge update" }
        let minutes = max(0, Int(row.serverTime.date.timeIntervalSince(fact.recordedAt.date) / 60))
        return "From Apple Health · " + (minutes < 1 ? "just now" : minutes < 60 ? "\(minutes) min ago" : "last saved update")
    }
}

struct LiveLibraryView: View {
    @Bindable var store: ChallengeV1Store
    @Binding var filter: String
    let serviceAvailable: Bool
    let create: () -> Void
    let entry: () -> Void
    let open: (UUID) -> Void
    @Environment(\.challengeHealthFlow) private var health
    @State private var declining: UUID?
    private var grouped: [(String, ChallengeV1Section)] { [("Active", .active), ("Invited", .action), ("Upcoming", .upcoming), ("Finished", .history)] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                VStack(spacing: 16) {
                    HStack {
                        Text("Challenges").liveFont(27, weight: .bold).tracking(-1.15)
                        Spacer()
                        Button(action: create) {
                            Image(systemName: "plus").font(.system(size: 23)).foregroundStyle(.white)
                                .frame(width: 44, height: 44).background(SignalTheme.accent, in: Circle())
                        }.accessibilityLabel("Create a challenge").accessibilityIdentifier("beta.create.open")
                    }
                    HStack(spacing: 3) {
                        ForEach(["All", "Invited", "Finished"], id: \.self) { value in
                            Button { filter = value } label: {
                                HStack(spacing: 6) {
                                    Text(value)
                                    if value == "Invited", invitationCount > 0 {
                                        Text(invitationCount.formatted()).liveFont(10, weight: .semibold)
                                            .padding(.horizontal, 5).padding(.vertical, 2).background(SignalTheme.divider, in: RoundedRectangle(cornerRadius: 6))
                                    }
                                }.liveFont(12, weight: .semibold).frame(maxWidth: .infinity, minHeight: 44)
                                    .foregroundStyle(filter == value ? SignalTheme.accent : SignalTheme.textSecondary)
                                    .background(filter == value ? Color.white : Color.clear, in: RoundedRectangle(cornerRadius: 13))
                            }.buttonStyle(.plain).accessibilityIdentifier("live.filter." + value.lowercased())
                                .accessibilityAddTraits(filter == value ? .isSelected : [])
                        }
                    }.padding(3).background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                }
                if store.homeState != .content { LiveEmptyState(store: store, serviceAvailable: serviceAvailable, create: create) }
                ForEach(grouped, id: \.0) { title, section in
                    if filter == "All" || filter == title {
                        if let state = store.sections[section], !visibleRows(state.rows, section: section).isEmpty || state.cursor != nil {
                            let rows = visibleRows(state.rows, section: section)
                            VStack(spacing: 10) {
                                HStack {
                                    Text(section == .action && rows.contains(where: { $0.status == "review" }) ? "Needs your attention" : title)
                                        .liveFont(15, weight: .semibold).tracking(-0.25)
                                    Spacer()
                                    Text("\(rows.count) \(section == .action && rows.allSatisfy(isInvitation) ? (rows.count == 1 ? "invitation" : "invitations") : (rows.count == 1 ? "challenge" : "challenges"))\(state.cursor == nil ? "" : "+")")
                                        .liveFont(11).foregroundStyle(SignalTheme.textSecondary)
                                }
                                ForEach(rows) { row in
                                    if row.status == "consent_pending", row.own(store.actor)?.consented == false {
                                        invitationCard(row)
                                    } else {
                                        Button { open(row.id) } label: { LiveLibraryCard(row: row, actor: store.actor) }.buttonStyle(.plain)
                                    }
                                }
                                if state.cursor != nil {
                                    Button("Load more") { Task { await store.loadMore(section) } }
                                        .frame(minHeight: 44).foregroundStyle(SignalTheme.accent).disabled(store.busy)
                                }
                            }
                        }
                    }
                }
                if filter == "Invited", invitationCount == 0, store.homeState == .content {
                    Text("No invitations waiting.").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                }
                if filter == "Finished", store.sections[.history]?.rows.isEmpty == true, store.homeState == .content {
                    Text("No finished challenges yet.").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                }
                LiveRecoveryView(store: store)
                if store.access?.ageConfirmed != true || store.linksAvailable || !store.communities.isEmpty {
                    Button(action: entry) { Label(store.access?.ageConfirmed == true ? "Use an invitation link" : "Set up challenge access", systemImage: store.access?.ageConfirmed == true ? "link" : "person.crop.circle.badge.checkmark").frame(minHeight: 44) }
                        .liveFont(13, weight: .medium).foregroundStyle(SignalTheme.accent)
                }
            }.padding(.horizontal, SignalTheme.contentInset).padding(.top, 13).padding(.bottom, 24)
        }.background(SignalTheme.canvas).toolbar(.hidden, for: .navigationBar)
            .refreshable { await store.refresh(); await health?.refresh() }
            .confirmationDialog("Decline this invitation?", isPresented: Binding(get: { declining != nil }, set: { if !$0 { declining = nil } }), titleVisibility: .visible) {
                Button("Decline invitation", role: .destructive) {
                    if let id = declining, let row = store.challenges.first(where: { $0.id == id }), store.isFresh(row), isInvitation(row) {
                        Task { await store.submit(op: "leave", challenge: row) }
                    }
                    declining = nil
                }
                Button("Keep invitation", role: .cancel) { declining = nil }
            } message: { Text("You won’t join this challenge. Your existing agreements stay unchanged.") }
            .onChange(of: store.actor) { declining = nil }
    }
    private func isInvitation(_ row: ChallengeV1) -> Bool { row.status == "consent_pending" && row.own(store.actor)?.consented == false }
    private func visibleRows(_ rows: [ChallengeV1], section: ChallengeV1Section) -> [ChallengeV1] {
        filter == "Invited" ? rows.filter(isInvitation) : rows
    }
    private var invitationCount: Int { store.sections[.action]?.rows.filter { $0.status == "consent_pending" && $0.own(store.actor)?.consented == false }.count ?? 0 }
    private func invitationCard(_ row: ChallengeV1) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    Text(LiveChallengePresentation.title(row)).liveFont(18, weight: .bold).tracking(-0.55)
                    Spacer(minLength: 0); LiveStateChip(text: "Invited", neutral: true)
                }
                Text("\(ChallengePresentation.dates(row)) · \(LiveChallengePresentation.goal(row, actor: store.actor).replacingOccurrences(of: " goal", with: "")) over \(row.config.days) days")
                    .liveFont(11).foregroundStyle(SignalTheme.textSecondary)
            }
            if let person = row.members.first(where: { $0.actorId == row.creatorId }) {
                HStack(spacing: 8) { LiveAvatar(username: person.username, actorID: person.actorId, size: 27); Text("From \(person.username)").liveFont(11).foregroundStyle(SignalTheme.textSecondary) }
            }
            HStack(spacing: 9) {
                Button { open(row.id) } label: { HStack(spacing: 8) { Text("Accept"); Image(systemName: "arrow.right") }.font(.system(size: 13, weight: .semibold)) }
                    .buttonStyle(LivePrimaryButtonStyle(height: 44, radius: 13)).accessibilityLabel("Accept: review invitation")
                Button("Decline") { declining = row.id }
                    .liveFont(13, weight: .semibold).frame(maxWidth: .infinity, minHeight: 44)
                    .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 13)).foregroundStyle(SignalTheme.textSecondary)
                    .disabled(!store.isFresh(row) || store.busy || store.pending != nil)
            }
        }.padding(.horizontal, 17).padding(.vertical, 16).modifier(LiveCardModifier(radius: 20, material: true))
    }
}

struct LiveLibraryCard: View {
    let row: ChallengeV1
    let actor: UUID?
    private var isActive: Bool { ["active", "syncing"].contains(row.status) && row.own(actor)?.exited != true }
    private var people: [ChallengeV1.Member] { row.members.filter { $0.actorId != actor && $0.selected && !$0.exited } }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text(LiveChallengePresentation.title(row)).liveFont(18, weight: .bold).tracking(-0.55)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(SignalTheme.textSecondary)
            }
            Text(ChallengePresentation.dates(row) + (isActive ? " · " + LiveChallengePresentation.ends(row) : ""))
                .liveFont(11).foregroundStyle(SignalTheme.textSecondary).padding(.top, 5)
            if isActive {
                HStack {
                    LiveMetric(value: LiveChallengePresentation.value(row.own(actor).flatMap { row.savedScore($0) }, metric: row.format.metric),
                               unit: "/ " + LiveChallengePresentation.goal(row, actor: actor).replacingOccurrences(of: " goal", with: ""), size: 47)
                    Spacer(minLength: 2)
                    chip
                }.padding(.top, 10)
                LiveProgressRail(progress: LiveChallengePresentation.progress(row, actor: actor), height: 12).padding(.top, 10)
                Text(LiveChallengePresentation.remaining(row, actor: actor)).liveFont(11, weight: .semibold).padding(.top, 7)
            }
            HStack {
                if !people.isEmpty { LiveFaceStack(people: people) }
                else if let own = row.own(actor) { LiveAvatar(username: own.username, actorID: own.actorId, size: 27) }
                Spacer(minLength: 10)
                if isActive { Text("\(LiveChallengePresentation.money(row.config.amountCents)) sim · fee $0").liveFont(10).foregroundStyle(SignalTheme.textSecondary) }
                else { chip }
            }.padding(.top, 13)
        }.foregroundStyle(SignalTheme.textPrimary).padding(.horizontal, 17).padding(.vertical, 16)
            .modifier(LiveCardModifier(radius: isActive ? 24 : 20, material: !isActive))
    }
    private var chip: some View {
        let state = LiveChallengePresentation.state(row, actor: actor)
        return LiveStateChip(text: state, warning: state == "Behind" || state == "Missed", neutral: ["No update yet", "Starts soon", "Closed early", "Didn’t count", "Choosing goals"].contains(state))
    }
}

struct LiveRecoveryView: View {
    @Bindable var store: ChallengeV1Store
    var body: some View {
        if let error = store.error { Text(error).font(.subheadline).foregroundStyle(SignalTheme.danger).accessibilityIdentifier("beta.error") }
        if store.pending != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("Your action is saved on this phone").font(.subheadline.weight(.semibold))
                Text("Retry to check whether it completed. Stop waiting checks it before preventing a late change.")
                    .font(.caption).foregroundStyle(SignalTheme.textSecondary)
                HStack {
                    Button("Retry saved action") { Task { await store.retry() } }.accessibilityIdentifier("beta.retry")
                    Spacer()
                    Button("Stop waiting") { Task { await store.abandon() } }.accessibilityIdentifier("beta.abandon")
                }.font(.caption.weight(.semibold)).frame(minHeight: 44).foregroundStyle(SignalTheme.accent).disabled(store.busy)
            }.padding(16).modifier(LiveCardModifier(radius: 17, material: true))
        } else if !store.fresh && !store.challenges.isEmpty {
            Text("Last saved view · refresh before making a choice.").font(.caption).foregroundStyle(SignalTheme.textSecondary)
        }
    }
}

struct LiveEmptyState: View {
    @Bindable var store: ChallengeV1Store
    let serviceAvailable: Bool
    let create: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.homeState == .loading && serviceAvailable {
                ProgressView("Loading your challenges…")
            } else {
                Text(serviceAvailable && store.homeState == .empty ? "Your first challenge" : "Your challenges")
                    .liveFont(24, weight: .bold).tracking(-0.8)
                Text(!serviceAvailable ? "New challenges aren’t open yet. Refresh to check for updates." : store.homeState == .empty ? "Choose a goal and the dates that work for you." : "We couldn’t load your challenges. Refresh to try again.")
                    .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                if serviceAvailable && store.homeState == .empty {
                    Button("Create a challenge", action: create).buttonStyle(LivePrimaryButtonStyle())
                } else {
                    Button("Refresh") { Task { await store.refresh() } }.buttonStyle(LiveSecondaryButtonStyle())
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(20).modifier(LiveCardModifier())
    }
}

struct LiveUnavailableSheet: View {
    let title: String
    let message: String
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(message).foregroundStyle(SignalTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
            Button("Done") { dismiss() }.buttonStyle(LiveSecondaryButtonStyle())
            Spacer()
        }.padding(.horizontal, SignalTheme.contentInset).padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .safeAreaInset(edge: .top, spacing: 0) { LiveSheetHeader(title: title, close: { dismiss() }) }
            .background(SignalTheme.canvas).preferredColorScheme(.light)
    }
}

private struct LiveFriendSelection: Identifiable {
    let challengeID: UUID
    let personID: UUID
    var id: UUID { personID }
}

private struct LiveFriendSheet: View {
    @Bindable var store: ChallengeV1Store
    let challengeID: UUID
    let personID: UUID
    @Environment(\.dismiss) private var dismiss
    private var current: ChallengeV1? {
        guard let row = store.challenges.first(where: { $0.id == challengeID }),
              store.isFresh(row), !row.socialHidden else { return nil }
        return row
    }
    var body: some View {
        Group {
        if let row = current, let person = row.members.first(where: { $0.actorId == personID && !$0.exited }) {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                LiveAvatar(username: person.username, actorID: person.actorId, size: 48)
                Text(person.username).liveFont(27, weight: .bold).tracking(-1)
                Spacer(); LiveRoundButton(symbol: "xmark", label: "Close", action: { dismiss() })
            }
            Text(LiveChallengePresentation.title(row)).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            VStack(alignment: .leading, spacing: 14) {
                LiveMetric(value: LiveChallengePresentation.value(row.savedScore(person), metric: row.format.metric), unit: LiveChallengePresentation.unit(row.format.metric), size: 88)
                LiveProgressRail(progress: LiveChallengePresentation.progress(row, actor: person.actorId))
                Text(LiveChallengePresentation.goal(row, actor: person.actorId)).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            }.padding(20).modifier(LiveCardModifier())
            Text("This is their last saved activity. Missing activity isn’t a missed goal.")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            ChallengePersonSafety(store: store, person: person)
            Spacer(minLength: 0)
        }.padding(.horizontal, SignalTheme.contentInset).padding(.vertical, 24)
        } else {
            LiveUnavailableSheet(title: "This update is unavailable", message: "Close this view and refresh your challenges.")
        }
        }.background(SignalTheme.canvas).presentationDetents([.medium, .large]).presentationDragIndicator(.visible)
    }
}
