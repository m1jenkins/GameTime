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
                                 create: { create = true }, library: { selection = 1 })
                        .navigationDestination(for: UUID.self) { LiveGoalDetail(store: store, id: $0) }
                }
            }
            Tab("Challenges", systemImage: "flag", value: 1) {
                NavigationStack(path: $libraryPath) {
                    LiveLibraryView(store: store, filter: $filter, serviceAvailable: serviceAvailable,
                                    create: { create = true }, entry: { entry = true }, open: { libraryPath.append($0) })
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
        .tint(SignalTheme.accent)
    }

    private var presentedShell: some View {
        tabs
        .background(SignalTheme.canvas.ignoresSafeArea())
        // The shell follows the phone's appearance. Creation, Settings (with
        // Personal history) and the invitation-link sheet have no dark design
        // yet, so each presentation keeps asking for light. Connect Apple
        // Health, shown first the first time someone creates, has both.
        .fullScreenCover(isPresented: $create, onDismiss: { personalRouteCoordinator?.allowPresentation() }) {
            if serviceAvailable {
                AppleHealthIntroductionGate {
                    ChallengeV1Create(store: store, allowed: creatablePolicies, onGoHome: {
                        selection = 0
                        homePath = []
                        libraryPath = []
                        recordPath = []
                    }).preferredColorScheme(.light)
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
            }.presentationDragIndicator(.visible).tint(SignalTheme.accent).preferredColorScheme(.light)
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
        .onAppear { applyInitialRoute(); if !invitation.link.isEmpty { entry = true; selection = 1 } }
        .environment(\.challengeInvitationLinks, invitation.links)
    }

    private func applyInitialRoute() {
        #if DEBUG
        guard !initialRouteApplied, LiveDesignFixtures.enabled, !store.challenges.isEmpty else { return }
        initialRouteApplied = true
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--live-screen=challenges") { selection = 1 }
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
    @State private var declining: UUID?
    private var grouped: [(String, ChallengeV1Section)] { [("Active", .active), ("Invited", .action), ("Upcoming", .upcoming), ("Finished", .history)] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 19) {
                VStack(spacing: 16) {
                    HStack {
                        Text("Challenges").liveFont(27, weight: .bold).tracking(-1.15)
                            .lineLimit(1).minimumScaleFactor(0.7)
                        Spacer()
                        Button(action: create) {
                            Image(systemName: "plus").font(.system(size: 23)).foregroundStyle(SignalTheme.onAccent)
                                .frame(width: 44, height: 44).background(SignalTheme.accentFill, in: Circle())
                        }.accessibilityLabel("Create a challenge").accessibilityIdentifier("beta.create.open")
                    }
                    // The three filters share one row until large text needs the full width.
                    let filters = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 3)) : AnyLayout(HStackLayout(spacing: 3))
                    filters {
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
                                    .background(filter == value ? SignalTheme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 13))
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
                                let sectionLayout = typeSize.isAccessibilitySize
                                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                                    : AnyLayout(HStackLayout())
                                sectionLayout {
                                    Text(section == .action && rows.contains(where: { $0.status == "review" }) ? "Needs your attention" : title)
                                        .liveFont(15, weight: .semibold).tracking(-0.25)
                                    if !typeSize.isAccessibilitySize { Spacer() }
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
                let titleLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout(spacing: 10))
                titleLayout {
                    Text(LiveChallengePresentation.title(row)).liveFont(18, weight: .bold).tracking(-0.55)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    LiveStateChip(text: "Invited", neutral: true)
                }
                Text("\(ChallengePresentation.dates(row)) · \(LiveChallengePresentation.goal(row, actor: store.actor).replacingOccurrences(of: " goal", with: "")) over \(row.config.days) days")
                    .liveFont(11).foregroundStyle(SignalTheme.textSecondary)
            }
            if let person = row.members.first(where: { $0.actorId == row.creatorId }) {
                HStack(spacing: 8) { LiveAvatar(username: person.username, actorID: person.actorId, size: 27); Text("From \(person.username)").liveFont(11).foregroundStyle(SignalTheme.textSecondary) }
            }
            let actions = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 9)) : AnyLayout(HStackLayout(spacing: 9))
            actions {
                Button { open(row.id) } label: { HStack(spacing: 8) { Text("Accept"); Image(systemName: "arrow.right") }.liveFont(13, weight: .semibold) }
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
    @Environment(\.dynamicTypeSize) private var typeSize
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
                let progressLayout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                    : AnyLayout(HStackLayout())
                progressLayout {
                    LiveMetric(value: LiveChallengePresentation.value(row.own(actor).flatMap { row.savedScore($0) }, metric: row.format.metric),
                               unit: "/ " + LiveChallengePresentation.goal(row, actor: actor).replacingOccurrences(of: " goal", with: ""), size: 47)
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 2) }
                    chip
                }.padding(.top, 10)
                LiveProgressRail(progress: LiveChallengePresentation.progress(row, actor: actor), height: 12).padding(.top, 10)
                Text(LiveChallengePresentation.remaining(row, actor: actor)).liveFont(11, weight: .semibold).padding(.top, 7)
            }
            let footerLayout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout())
            footerLayout {
                if !people.isEmpty { LiveFaceStack(people: people) }
                else if let own = row.own(actor) { LiveAvatar(username: own.username, actorID: own.actorId, size: 27) }
                if !typeSize.isAccessibilitySize { Spacer(minLength: 10) }
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
