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
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system
    @State private var selection = 0
    @State private var homePath: [UUID] = []
    @State private var libraryPath: [UUID] = []
    @State private var recordPath: [UUID] = []
    @State private var create = false
    @State private var settings = false
    @State private var entry = false
    @State private var filter = "All"
    @State private var initialRouteApplied = false

    /// The system tab bar: on iOS 26 it's Liquid Glass floating over the
    /// content, which scrolls underneath; earlier systems get the solid bar
    /// `SignalAppearance` sets up. Tapping the open tab again goes back to
    /// its first page.
    private var tabs: some View {
        TabView(selection: Binding(get: { selection }, set: { index in
            if index == selection {
                if index == 0 { homePath = [] }
                if index == 1 { libraryPath = [] }
                if index == 2 { recordPath = [] }
            }
            selection = index
        })) {
            Tab("Home", systemImage: "house", value: 0) {
                NavigationStack(path: $homePath) {
                    LiveHomeView(store: store, profile: profile, serviceAvailable: serviceAvailable,
                                 viewGoal: { homePath.append($0) }, showRecord: { selection = 2 },
                                 create: beginCreation, library: { selection = 1 })
                        .navigationDestination(for: UUID.self) { LiveGoalDetail(store: store, id: $0) }
                }
            }
            Tab("Challenges", systemImage: "flag", value: 1) {
                NavigationStack(path: $libraryPath) {
                    LiveLibraryView(store: store, filter: $filter, serviceAvailable: serviceAvailable,
                                    create: beginCreation, entry: { entry = true }, open: { libraryPath.append($0) })
                        .navigationDestination(for: UUID.self) { LiveGoalDetail(store: store, id: $0) }
                }
            }
            Tab("You", systemImage: "person", value: 2) {
                NavigationStack(path: $recordPath) {
                    LiveRecordView(store: store, profile: profile, accountActor: accountActor ?? store.actor,
                                   settings: { settings = true })
                }
            }
        }
        .tint(Floodlight.link)
    }

    private func beginCreation() {
        // Keep the existing confirmation path reachable when the empty library
        // has no utility rows. Admission still requires the person's own choice.
        if serviceAvailable, store.access?.ageConfirmed != true { entry = true }
        else { create = true }
    }

    private var presentedShell: some View {
        tabs
        .background(SignalTheme.canvas.ignoresSafeArea())
        // System follows the iPhone until the person saves Light or Dark.
        .preferredColorScheme(appearance.colorScheme)
        .fullScreenCover(isPresented: $create, onDismiss: { personalRouteCoordinator?.allowPresentation() }) {
            if serviceAvailable {
                AppleHealthIntroductionGate {
                    ChallengeV1Create(store: store, allowed: creatablePolicies, profile: profile, onGoHome: {
                        selection = 0
                        homePath = []
                        libraryPath = []
                        recordPath = []
                    }).preferredColorScheme(appearance.colorScheme)
                }
            } else {
                LiveUnavailableSheet(title: "New challenges aren’t open yet", message: "You can refresh your saved challenges or return later.")
                    .preferredColorScheme(.light)
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
            }.presentationDragIndicator(.hidden).tint(SignalTheme.accent).preferredColorScheme(appearance.colorScheme)
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
            }.tint(SignalTheme.accent).presentationDragIndicator(.visible).preferredColorScheme(.light)
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
        .onChange(of: store.homeState) { applyInitialRoute() }
        .onAppear { applyInitialRoute(); if !invitation.link.isEmpty { entry = true; selection = 1 } }
        .environment(\.challengeInvitationLinks, invitation.links)
    }

    private func applyInitialRoute() {
        #if DEBUG
        guard !initialRouteApplied, LiveDesignFixtures.enabled, store.homeState == .content || store.homeState == .empty else { return }
        initialRouteApplied = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--live-screen=challenges") || args.contains("--live-screen=challenges-empty") { selection = 1 }
        if args.contains("--live-screen=you") || args.contains("--live-screen=friends") { selection = 2 }
        if args.contains("--live-screen=goal") || args.contains("--live-screen=rules") || args.contains("--live-screen=pot") {
            homePath = [LiveDesignFixtures.activeID]
        }
        if args.contains("--live-screen=invitation") || args.contains("--live-screen=invitation-pot") {
            homePath = [LiveDesignFixtures.invitationID]
        }
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
    @State private var scrolled = false
    private var featured: ChallengeV1? {
        let rows = store.profileSnapshot.rows.filter { !$0.isClosed && $0.own(store.actor)?.exited == false }
        return rows.first { $0.status == "active" && $0.format.mode == .friend }
            ?? rows.first { $0.status == "active" || $0.status == "syncing" }
            ?? rows.filter { $0.status == "scheduled" }.min { $0.config.startsAt < $1.config.startsAt } ?? rows.first
    }
    var body: some View {
        // Floodlight 9.3 Home: the wordmark and the active challenge's lit card
        // sit on the sky; everything else is on the ground below it.
        FloodlightScrollPage(scrolled: $scrolled) { topInset in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    header.padding(.horizontal, 20).padding(.top, topInset + 8)
                    if let row = featured { heroCard(row).padding(.horizontal, 16).padding(.top, 12) }
                }
                .padding(.bottom, 18)
                .background(alignment: .top) { FloodlightSky() }
                VStack(alignment: .leading, spacing: 12) {
                    if let row = featured {
                        cheer(row)
                        HomeActionRows(challenges: store, viewGoal: viewGoal)
                    } else {
                        HomeActionRows(challenges: store, viewGoal: viewGoal)
                        if store.homeState == .content {
                            let complete = store.profileSnapshot.availability == .complete
                            VStack(alignment: .leading, spacing: 16) {
                                Text(complete ? "No active challenge" : "Your saved challenges").liveFont(24, weight: .bold).tracking(-0.8)
                                Text(complete ? "Your finished goals are in You." : "Refresh to check your current goals. Your saved records are in You.").font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                                if complete && serviceAvailable { Button("Create a challenge", action: create).buttonStyle(LivePrimaryButtonStyle()) }
                                if !complete { Button("Refresh") { Task { await store.refresh() } }.buttonStyle(LiveSecondaryButtonStyle()) }
                                Button("View your record", action: showRecord).font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SignalTheme.accent).frame(minHeight: 44)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(20).modifier(LiveCardModifier())
                        } else {
                            LiveEmptyState(store: store, serviceAvailable: serviceAvailable, create: create)
                        }
                    }
                    LiveRecoveryView(store: store)
                }.padding(.horizontal, 16).padding(.bottom, 24)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refresh(); await friends?.refresh(); await health?.refresh() }
        .modifier(FriendsNoticeToast(friends: friends))
    }

    /// The GameTime mark and the date; the date moves under the mark at
    /// accessibility text sizes so neither is cut off.
    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 10))
        return layout {
            HStack(spacing: 8) {
                FloodlightBrandMark().fill(Floodlight.brand).frame(width: 24, height: 24).accessibilityHidden(true)
                FloodlightTitle(GameTimePublicIdentity.name, size: 34, maxScale: 1.4, spacing: -0.02).foregroundStyle(Floodlight.ink)
                    .lineLimit(1).fixedSize()
                    .accessibilityAddTraits(.isHeader)
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            FloodlightLabel(today, color: Floodlight.heroMuted).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }
    /// The server's today in the featured challenge's time zone, or the phone's.
    private var today: String {
        let format = DateFormatter()
        format.timeZone = featured.flatMap { TimeZone(identifier: $0.config.timezone) } ?? .current
        format.setLocalizedDateFormatFromTemplate("EEEMMMd")
        return format.string(from: featured?.serverTime.date ?? Date())
    }

    /// The lit card: the challenge, your number and the group dial with the pot.
    private func heroCard(_ row: ChallengeV1) -> some View {
        let actor = store.actor
        let own = row.own(actor)
        let group = row.format.mode == .friend && !row.socialHidden
        let people = group ? FloodlightChallengeFacts.people(row, actor: actor) : own.map { [$0] } ?? []
        let slots = FloodlightChallengeFacts.slots(row, actor: actor)
        let pot = group && row.format.hasTarget ? FloodlightChallengeFacts.potCents(row) : nil
        let sync = own.flatMap { FloodlightChallengeFacts.syncTime(row, $0, actor: actor) }
        let title = LiveChallengePresentation.title(row)
        var parts = ["Open \(title)."]
        if let pot { parts.append("Pot: \(LiveChallengePresentation.money(pot)) in simulated stakes.") }
        parts += people.map { FloodlightChallengeFacts.spoken(row, $0, actor: actor) }
        if let sync { parts.append(sync.spoken + ".") }
        let spoken = parts.joined(separator: " ")
        return Button { viewGoal(row.id) } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        FloodlightTitle(title, size: 28).foregroundStyle(Floodlight.ink).fixedSize(horizontal: false, vertical: true)
                        Text("\(ChallengePresentation.dates(row)) · \(LiveChallengePresentation.ends(row))")
                            .floodlightFont(12.5, weight: .medium).foregroundStyle(Floodlight.heroMuted).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).foregroundStyle(Floodlight.heroMuted).padding(.top, 4)
                }
                if typeSize.isAccessibilitySize {
                    // Larger text: the dial on its own row, then the number.
                    VStack(alignment: .leading, spacing: 8) {
                        if row.format.hasTarget, !people.isEmpty { dial(row, people: people, pot: pot) }
                        measure(row, own: own)
                    }
                } else {
                    // The page's 0.8fr / 1.2fr split: number left, dial right.
                    HStack(alignment: .center, spacing: 4) {
                        measure(row, own: own).frame(maxWidth: .infinity, alignment: .leading)
                        if row.format.hasTarget, !people.isEmpty {
                            dial(row, people: people, pot: pot)
                                .containerRelativeFrame(.horizontal) { width, _ in max(120, (width - 64) * 0.6) }
                        }
                    }
                }
                let foot = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
                foot {
                    FloodlightFaceStack(people: people.map { person in
                        (slot: slots[person.actorId] ?? 0, initials: FloodlightChallengeFacts.initials(person, actor: actor, profile: profile),
                         badge: FloodlightChallengeFacts.met(row, person) ? FloodlightOrb.Badge.met : .none, waiting: row.savedScore(person) == nil)
                    })
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    // Hero-muted, like the card's other secondary text. CI's audit flagged
                    // this line even in ink, which measured 12.4:1 in CI's own screenshot,
                    // so LiveDesignUITests measures its pixels instead.
                    if let sync { FloodlightSyncTime(short: sync.short, spoken: sync.spoken, late: sync.late, color: Floodlight.heroMuted) }
                }
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .top) { Rectangle().fill(Floodlight.line).frame(height: 1) }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .floodlightHero()
            .contentShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("live.home.goal")
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("live.home.metric")
    }

    private func measure(_ row: ChallengeV1, own: ChallengeV1.Member?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(own.map { FloodlightChallengeFacts.value(row, $0) } ?? "—")
                .floodlightFont(70, weight: .semibold, condensed: true, maxScale: 1.3).tracking(-1.75).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.5).foregroundStyle(Floodlight.ink)
            if let target = own?.target {
                Text("/ " + FloodlightChallengeFacts.goal(row, target)).floodlightFont(15, weight: .medium).foregroundStyle(Floodlight.heroMuted)
            } else {
                Text(LiveChallengePresentation.unit(row.format.metric)).floodlightFont(15, weight: .medium).foregroundStyle(Floodlight.heroMuted)
            }
            if let own, row.savedScore(own) == nil {
                Text("No update yet").floodlightFont(13, weight: .semibold).foregroundStyle(Floodlight.heroMuted).padding(.top, 4)
            } else if let own, FloodlightChallengeFacts.met(row, own) {
                Label("Goal reached", systemImage: "checkmark").floodlightFont(13, weight: .semibold).foregroundStyle(Floodlight.ink).padding(.top, 4)
            }
        }
    }

    private func dial(_ row: ChallengeV1, people: [ChallengeV1.Member], pot: Int?) -> some View {
        let lanes = FloodlightChallengeFacts.lanes(row, actor: store.actor, profile: profile).filter { lane in people.contains { $0.actorId == lane.id } }
        return FloodlightDial(kind: .compact, lanes: lanes, potCents: pot)
    }

    /// "Priya reached their goal." under the card, with who reached it.
    @ViewBuilder private func cheer(_ row: ChallengeV1) -> some View {
        if row.format.mode == .friend, !row.socialHidden, let line = FloodlightChallengeFacts.metLine(row, actor: store.actor) {
            let slots = FloodlightChallengeFacts.slots(row, actor: store.actor)
            let met = FloodlightChallengeFacts.people(row, actor: store.actor).filter { FloodlightChallengeFacts.met(row, $0) }.prefix(3)
            HStack(spacing: 12) {
                FloodlightFaceStack(people: met.map { person in
                    (slot: slots[person.actorId] ?? 0, initials: FloodlightChallengeFacts.initials(person, actor: store.actor, profile: profile),
                     badge: FloodlightOrb.Badge.met, waiting: false)
                }, size: 32)
                Text(line).floodlightFont(15, weight: .semibold).foregroundStyle(Floodlight.ink).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .floodlightCard()
            .accessibilityElement(children: .combine)
        }
    }
}

/// The GameTime mark from the Floodlight page.
struct FloodlightBrandMark: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 24
        var path = Path()
        path.addLines([(4, 21), (4, 10), (11, 3), (11, 10), (20, 3), (20, 14), (11, 21), (11, 14)].map {
            CGPoint(x: rect.minX + $0.0 * s, y: rect.minY + $0.1 * s)
        })
        path.closeSubpath()
        return path
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var scheme
    @State private var declining: UUID?
    @State private var scrolled = false

    private var grouped: [(String, ChallengeV1Section)] {
        [("Needs your attention", .action), ("Active", .active), ("Upcoming", .upcoming), ("Finished", .history)]
    }
    private var featuredID: UUID? {
        store.sections[.active]?.rows.first { ["active", "syncing"].contains($0.status) && $0.own(store.actor)?.exited != true }?.id
    }

    var body: some View {
        FloodlightScrollPage(scrolled: $scrolled) { topInset in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        FloodlightTitle("Challenges", size: 38).foregroundStyle(Floodlight.ink)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer(minLength: 4)
                        FloodlightNavButton(symbol: "plus", label: "Create a challenge", action: create)
                            .accessibilityIdentifier("beta.create.open")
                    }
                    .padding(.horizontal, 18).padding(.top, topInset + 6)

                    if store.homeState == .content {
                        filters.padding(.horizontal, 16).padding(.top, 12)
                    } else if store.homeState == .empty && serviceAvailable {
                        LiveLibraryEmptyState(create: create).padding(.horizontal, 16).padding(.top, 22)
                    } else {
                        LiveEmptyState(store: store, serviceAvailable: serviceAvailable, create: create)
                            .padding(.horizontal, 16).padding(.top, 22)
                    }

                    ForEach(grouped, id: \.0) { title, section in
                        if filter == "All" || filter == title || filter == "Invited" && section == .action {
                            if let state = store.sections[section], !visibleRows(state.rows).isEmpty || state.cursor != nil {
                                let rows = visibleRows(state.rows)
                                VStack(spacing: 12) {
                                    sectionHeading(title, rows: rows, section: section, hasMore: state.cursor != nil)
                                    ForEach(rows) { row in
                                        if isInvitation(row) {
                                            invitationCard(row)
                                        } else {
                                            Button { open(row.id) } label: {
                                                LiveLibraryCard(row: row, actor: store.actor, highlighted: row.id == featuredID)
                                            }
                                            .buttonStyle(.plain)
                                            .accessibilityIdentifier(row.id == featuredID ? "live.library.active" : "live.library.row." + row.id.uuidString.lowercased())
                                        }
                                    }
                                    if state.cursor != nil {
                                        Button("Load more") { Task { await store.loadMore(section) } }
                                            .frame(minHeight: 44).foregroundStyle(Floodlight.link).disabled(store.busy)
                                    }
                                }
                                .padding(.horizontal, 16).padding(.top, 22)
                            }
                        }
                    }
                    if filter == "Invited", invitationCount == 0, store.homeState == .content {
                        Text("No invitations waiting.").floodlightFont(14).foregroundStyle(Floodlight.muted)
                            .padding(.horizontal, 20).padding(.top, 22)
                    }
                    if filter == "Finished", store.sections[.history]?.rows.isEmpty == true, store.homeState == .content {
                        Text("No finished challenges yet.").floodlightFont(14).foregroundStyle(Floodlight.muted)
                            .padding(.horizontal, 20).padding(.top, 22)
                    }
                }
                .padding(.bottom, 18)
                .background(alignment: .top) {
                    FloodlightSky().frame(height: store.homeState == .empty ? 500 : 620)
                }
                VStack(alignment: .leading, spacing: 12) {
                    LiveRecoveryView(store: store)
                    if store.homeState == .content,
                       store.access?.ageConfirmed != true || store.linksAvailable || !store.communities.isEmpty {
                        Button(action: entry) {
                            Label(store.access?.ageConfirmed == true ? "Use an invitation link" : "Set up challenge access",
                                  systemImage: store.access?.ageConfirmed == true ? "link" : "person.crop.circle.badge.checkmark")
                                .frame(minHeight: 44)
                        }
                        .floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.link)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
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

    private var filters: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
        return layout {
            ForEach(["All", "Invited", "Finished"], id: \.self) { value in
                Button { filter = value } label: {
                    HStack(spacing: 6) {
                        Text(value)
                        if value == "Invited", invitationCount > 0 {
                            Text(invitationCount.formatted()).floodlightFont(11, weight: .bold)
                                .frame(minWidth: 19, minHeight: 19)
                                .background(Capsule().fill(scheme == .dark ? Floodlight.well : Floodlight.card))
                                .overlay(Capsule().strokeBorder(scheme == .dark ? Floodlight.wellEdge : Floodlight.cardEdge, lineWidth: 1))
                        }
                    }
                    .floodlightFont(13.5, weight: .semibold).foregroundStyle(Floodlight.ink)
                    .frame(maxWidth: .infinity, minHeight: 38)
                    .background {
                        if filter == value {
                            Capsule().fill(scheme == .dark ? Floodlight.well : Floodlight.card)
                                .overlay(Capsule().strokeBorder(scheme == .dark ? Floodlight.wellEdge : Floodlight.cardEdge, lineWidth: 1))
                        }
                    }
                    .frame(minHeight: 44).contentShape(Capsule())
                }
                .buttonStyle(.plain).accessibilityIdentifier("live.filter." + value.lowercased())
                .accessibilityAddTraits(filter == value ? .isSelected : [])
            }
        }
        .padding(3).background(Capsule().fill(scheme == .dark ? Floodlight.card : Floodlight.well))
        .overlay(Capsule().strokeBorder(scheme == .dark ? Floodlight.cardEdge : Floodlight.wellEdge, lineWidth: 1))
    }

    private func sectionHeading(_ title: String, rows: [ChallengeV1], section: ChallengeV1Section, hasMore: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            FloodlightTitle(title, size: 21).foregroundStyle(Floodlight.ink)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
            Text("\(rows.count) \(section == .action && rows.allSatisfy(isInvitation) ? (rows.count == 1 ? "invitation" : "invitations") : (rows.count == 1 ? "challenge" : "challenges"))\(hasMore ? "+" : "")")
                .floodlightFont(12.5, weight: .medium).foregroundStyle(Floodlight.muted)
        }
        .padding(.horizontal, 4)
    }
    private func isInvitation(_ row: ChallengeV1) -> Bool { row.status == "consent_pending" && row.own(store.actor)?.consented == false }
    private func visibleRows(_ rows: [ChallengeV1]) -> [ChallengeV1] { filter == "Invited" ? rows.filter(isInvitation) : rows }
    private var invitationCount: Int { store.sections[.action]?.rows.filter(isInvitation).count ?? 0 }

    private func invitationCard(_ row: ChallengeV1) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let titleLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            titleLayout {
                VStack(alignment: .leading, spacing: 4) {
                    FloodlightTitle(LiveChallengePresentation.title(row), size: 21).foregroundStyle(Floodlight.ink)
                    Text("\(ChallengePresentation.dates(row)) · \(LiveChallengePresentation.goal(row, actor: store.actor).replacingOccurrences(of: " goal", with: "")) over \(row.config.days) days")
                        .floodlightFont(12.5, weight: .medium).foregroundStyle(Floodlight.muted)
                }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text("Invited").floodlightFont(12, weight: .semibold).foregroundStyle(Floodlight.ink)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Floodlight.well))
                    .overlay(Capsule().strokeBorder(Floodlight.wellEdge, lineWidth: 1))
            }
            if let person = row.members.first(where: { $0.actorId == row.creatorId }) {
                HStack(spacing: 8) {
                    FloodlightOrb(slot: 2, initials: FloodlightOrb.initials(person.username), size: 24)
                    Text("From \(person.username)").floodlightFont(12, weight: .medium).foregroundStyle(Floodlight.muted)
                }
            }
            let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            actions {
                Button { open(row.id) } label: {
                    HStack(spacing: 9) {
                        Text("Review and agree").floodlightFont(14, weight: .bold)
                        Image(systemName: "arrow.right").font(.system(size: 16, weight: .semibold)).accessibilityHidden(true)
                    }
                }
                .buttonStyle(FloodlightPrimaryButtonStyle(height: 40))
                .frame(minHeight: 44)
                .accessibilityLabel("Review and agree").accessibilityIdentifier("live.library.review")
                Button { declining = row.id } label: {
                    Text("Decline").floodlightFont(14, weight: .semibold)
                        .lineLimit(1).fixedSize(horizontal: true, vertical: true)
                        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(Floodlight.ink)
                        .background(Capsule().fill(Floodlight.well))
                        .overlay(Capsule().strokeBorder(Floodlight.wellEdge, lineWidth: 1))
                }
                    .buttonStyle(.plain)
                    .frame(width: typeSize.isAccessibilitySize ? nil : 76)
                    .frame(minHeight: 44)
                    .disabled(!store.isFresh(row) || store.busy || store.pending != nil)
                    .accessibilityIdentifier("live.library.decline")
            }
        }
        .padding(14).floodlightCard()
    }
}

struct LiveLibraryCard: View {
    let row: ChallengeV1
    let actor: UUID?
    var highlighted = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    private var isActive: Bool { ["active", "syncing"].contains(row.status) && row.own(actor)?.exited != true }
    private var people: [ChallengeV1.Member] { FloodlightChallengeFacts.people(row, actor: actor) }
    private var slots: [UUID: Int] { FloodlightChallengeFacts.slots(row, actor: actor) }

    var body: some View {
        Group {
            if highlighted { card.floodlightHero() }
            else { card.floodlightCard() }
        }
        .foregroundStyle(Floodlight.ink)
    }
    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    FloodlightTitle(LiveChallengePresentation.title(row), size: 21)
                    Text(ChallengePresentation.dates(row) + (isActive ? " · " + LiveChallengePresentation.ends(row) : ""))
                        .floodlightFont(12.5, weight: .medium).foregroundStyle(Floodlight.muted)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Floodlight.muted).padding(.top, 3).accessibilityHidden(true)
            }
            if isActive {
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    if row.format.hasTarget, row.format.metric != .timed {
                        FloodlightDial(kind: .mini, lanes: FloodlightChallengeFacts.lanes(row, actor: actor),
                                       potCents: row.format.mode == .friend && !row.socialHidden ? FloodlightChallengeFacts.potCents(row) : nil)
                            .frame(width: 112)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text(LiveChallengePresentation.value(row.own(actor).flatMap { row.savedScore($0) }, metric: row.format.metric))
                                .floodlightFont(40, weight: .semibold, condensed: true, maxScale: 1.5)
                                .tracking(-0.8).lineLimit(1).minimumScaleFactor(0.7)
                            Text("/ " + LiveChallengePresentation.goal(row, actor: actor).replacingOccurrences(of: " goal", with: ""))
                                .floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted)
                        }
                        Text(LiveChallengePresentation.remaining(row, actor: actor))
                            .floodlightFont(12, weight: .medium).foregroundStyle(Floodlight.muted)
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) { faces; amount }
                            VStack(alignment: .leading, spacing: 6) { faces; amount }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack {
                    faces
                    Spacer(minLength: 8)
                    LiveStateChip(text: LiveChallengePresentation.state(row, actor: actor), neutral: true)
                }
            }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
    }
    private var faces: some View {
        FloodlightFaceStack(people: people.map { person in
            let name = friends?.friends.first { $0.id == person.actorId }?.displayName ?? person.username
            return (slot: slots[person.actorId] ?? 0, initials: FloodlightOrb.initials(name), badge: .none, waiting: false)
        }, size: 24)
        .accessibilityHidden(false)
        .accessibilityLabel("\(people.count) participants")
    }
    private var amount: some View {
        Text("\(LiveChallengePresentation.money(row.config.amountCents)) sim · fee $0")
            .floodlightFont(12, weight: .medium).foregroundStyle(Floodlight.muted).fixedSize()
    }
}

struct LiveLibraryEmptyState: View {
    let create: () -> Void
    private static let dialID = UUID()
    var body: some View {
        VStack(spacing: 8) {
            FloodlightDial(kind: .mini, lanes: [.init(id: Self.dialID, slot: 0, fraction: nil, initials: "")])
                .frame(width: 176)
            FloodlightTitle("Your first challenge", size: 26).foregroundStyle(Floodlight.ink)
                .multilineTextAlignment(.center).padding(.top, 4)
            Text("Choose a goal and the dates that work for you.")
                .floodlightFont(14, weight: .medium).foregroundStyle(Floodlight.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 248)
            Button(action: create) { Label("Create a challenge", systemImage: "plus") }
                .buttonStyle(FloodlightPrimaryButtonStyle()).padding(.top, 8)
                .accessibilityIdentifier("live.library.empty.create")
        }
        .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 20)
        .frame(maxWidth: .infinity).floodlightHero()
    }
}

struct LiveRecoveryView: View {
    @Bindable var store: ChallengeV1Store
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if let error = store.error { Text(error).font(.subheadline).foregroundStyle(SignalTheme.danger).accessibilityIdentifier("beta.error") }
        if store.pending != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text(ChallengePendingCopy.title).font(.subheadline.weight(.semibold))
                Text(ChallengePendingCopy.message)
                    .font(.caption).foregroundStyle(SignalTheme.textSecondary)
                let actionLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout())
                actionLayout {
                    Button(ChallengePendingCopy.retry) { Task { await store.retry() } }.accessibilityIdentifier("beta.retry")
                    if !typeSize.isAccessibilitySize { Spacer() }
                    Button(ChallengePendingCopy.cancel) { Task { await store.abandon() } }.accessibilityIdentifier("beta.abandon")
                }.font(.caption.weight(.semibold)).frame(minHeight: 44).foregroundStyle(SignalTheme.accent).disabled(store.busy)
            }.padding(16).modifier(LiveCardModifier(radius: 17, material: true))
        } else if !store.fresh && !store.challenges.isEmpty {
            Text("This might be out of date. Refresh before you make a choice.").font(.caption).foregroundStyle(SignalTheme.textSecondary)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(message).foregroundStyle(SignalTheme.textSecondary).fixedSize(horizontal: false, vertical: true)
                Button("Done") { dismiss() }.buttonStyle(LiveSecondaryButtonStyle())
                Spacer()
            }.padding(.horizontal, SignalTheme.contentInset).padding(.top, 8)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .safeAreaInset(edge: .top, spacing: 0) { LiveSheetHeader(title: title, close: { dismiss() }) }
            .background(SignalTheme.canvas)
    }
}
