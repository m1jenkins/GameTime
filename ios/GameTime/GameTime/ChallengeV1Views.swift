#if DEBUG
import Charts
import Supabase
import SwiftUI

enum ChallengeLocalLaunch {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--beta-challenges-local") }
}

@MainActor @Observable final class ChallengeLocalSession {
    let store: ChallengeV1Store?
    let sdk: SupabaseClient?
    var message: String?
    init() {
        let env = ProcessInfo.processInfo.environment
        guard let text = env["GAMETIME_BETA_LOCAL_URL"], let url = URL(string: text),
              SupabaseWeeklyClient.isExplicitLoopback(url),
              let key = env["GAMETIME_BETA_LOCAL_KEY"], key.hasPrefix("sb_publishable_") else {
            sdk = nil; store = nil
            message = "This local preview needs its own connection settings. Follow the launch instructions to continue."
            return
        }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key,
            options: .init(auth: .init(storage: ChallengeMemoryAuthStorage(), autoRefreshToken: false, emitLocalSessionAsInitialSession: true)))
        sdk = client
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = ChallengeV1Store(auth: SupabaseAuthClient(client: client), client: SupabaseChallengeV1Client(sdk: client, url: url, key: key),
            requests: ChallengeV1RequestStore(directory: root.appendingPathComponent("GameTime/ChallengeV1Pending")))
    }
    func login(email: String, password: String) async {
        guard let sdk, let store else { return }
        store.setActor(nil)
        do {
            let session = try await sdk.auth.signIn(email: email, password: password)
            store.setActor(session.user.id); message = nil; await store.refresh()
        } catch { message = "We couldn’t sign in. Check the local account and password, then try again." }
    }
    func logout() async {
        store?.setActor(nil)
        try? await sdk?.auth.signOut(scope: .local)
    }
}
final class ChallengeMemoryAuthStorage: AuthLocalStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    func store(key: String, value: Data) throws { lock.lock(); defer { lock.unlock() }; values[key] = value }
    func retrieve(key: String) throws -> Data? { lock.lock(); defer { lock.unlock() }; return values[key] }
    func remove(key: String) throws { lock.lock(); defer { lock.unlock() }; values.removeValue(forKey: key) }
}

struct ChallengeLocalLaunchView: View {
    @State private var session = ChallengeLocalSession()
    @State private var invitation = ChallengeInvitationIntent()
    @State private var email = ProcessInfo.processInfo.environment["GAMETIME_BETA_LOCAL_EMAIL"] ?? ""
    @State private var password = ProcessInfo.processInfo.environment["GAMETIME_BETA_LOCAL_PASSWORD"] ?? ""
    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--beta-a11y-control-check") {
                ChallengeControlDiagnostic()
            } else if let store = session.store, store.actor != nil {
                ChallengeV1Shell(store: store, invitation: invitation, logout: { await session.logout() })
            } else {
                NavigationStack {
                    ChallengeForm {
                        ChallengeFormSection("Local challenge preview") {
                            Text("Fictional activity and simulated stakes. Nothing can be paid out or redeemed.")
                            TextField("Local account email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("beta.login.email")
                            SecureField("Password", text: $password).accessibilityIdentifier("beta.login.password")
                            Button("Sign in") { Task { await session.login(email: email, password: password); password = ""; if session.store?.actor != nil { email = "" } } }
                                .disabled(session.store == nil || email.isEmpty || password.isEmpty)
                                .accessibilityIdentifier("beta.login.submit")
                        }
                        if let message = session.message { Text(message) }
                        if let message = invitation.message { Text(message) }
                    }.navigationTitle("GameTime")
                }
            }
        }.frame(maxWidth: ProcessInfo.processInfo.arguments.contains("--beta-compact-check") ? 320 : .infinity)
            .tint(CompetitiveTrustTheme.actionCoral).onOpenURL { invitation.receive($0) }
    }
}

struct ChallengeControlDiagnostic: View {
    @State private var amount = 20
    @State private var selected = 0
    private var control: some View {
        ChallengeIntegerControl(value: $amount, range: 1...500, id: "amount", title: "Simulated dollars", display: "\(challengeMoney(amount * 100)) simulated each")
    }
    var body: some View {
        if ProcessInfo.processInfo.arguments.contains("--beta-a11y-scroll-parent") {
            ScrollView { VStack(alignment: .leading, spacing: 24) {
                Text("System scroll reference").font(.headline)
                ForEach(0..<9) { n in Text("Body reference \(n)").font(.body) }
                control
            }.padding(20) }
        } else if ProcessInfo.processInfo.arguments.contains("--beta-a11y-form-parent") {
            Form {
                Section("System form reference") {
                    ForEach(0..<9) { n in Text("Body reference \(n)").font(.body) }
                    control
                }
            }
        } else if ProcessInfo.processInfo.arguments.contains("--beta-a11y-tab-parent") {
            TabView(selection: $selected) {
                VStack { Text("Body reference").font(.body); control }.padding().tabItem { Label("Home", systemImage: "house") }.tag(0)
                Text("Second page").tabItem { Label("Challenges", systemImage: "flag") }.tag(1)
                Text("Third page").tabItem { Label("You", systemImage: "person") }.tag(2)
            }
        } else { VStack(spacing: 24) { Text("Body reference").font(.body); control }.padding(20) }
    }
}

struct ChallengeLocalDisclosures: View {
    var body: some View {
        ChallengeForm {
            ChallengeFormSection("This local preview") {
                Text("Fictional activity and simulated stakes only. No real money moves, and nothing can be paid out or redeemed.")
                Text("Confirm that you are 21 or older before joining. We store your confirmation, not your birth date.")
            }
            ChallengeFormSection("Your information") {
                Text("The local service saves your account, challenge agreements, consent, normalized fictional progress, corrections, reviews and results. Saved requests on this phone help recover an interrupted action.")
                Text("Selected friends can see your username, agreed goal when there is one, current challenge activity and results. Personal activity and community activity are private to you; community screens show anonymous counts.")
                Text("Assigned operators can inspect the limited challenge facts needed for reviews and safety reports. Raw Health records, routes and activity history outside the challenge are not shared.")
                Text("The separate private activity check keeps its records on this phone and clears them when you leave the check. It does not send them to the challenge service.")
                Text("There are no analytics or advertising in this preview. Local preview records are retained for verification; stopping the preview revokes its account sessions and preserves the records.")
            }
            ChallengeFormSection("Your choices") {
                Text("Read each complete agreement before consenting. You can leave an unfinished challenge and recover your simulated entry. Results include a review deadline; an interrupted action can be retried or stopped from Home.")
                Text("Report or block an account from a shared challenge. Shared details become hidden after a safety exit; your own final history remains available.")
                Text("External support and account deletion for the new beta are not available in this local preview. They must be accepted before distribution. Existing account and historical records are preserved.")
            }
        }.navigationTitle("Privacy and terms")
    }
}

struct ChallengeV1Shell: View {
    @Bindable var store: ChallengeV1Store
    @Bindable var invitation: ChallengeInvitationIntent
    let logout: @MainActor () async -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var create = false
    @State private var selection = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(spacing: 0) {
        TabView(selection: $selection) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !dynamicTypeSize.isAccessibilitySize { Text("GameTime").font(.largeTitle.bold().italic()) }
                        Text("Simulated stakes — no real money moves.").font(.subheadline)
                        recovery
                        if !dynamicTypeSize.isAccessibilitySize || !store.ordered.isEmpty { Text("Your challenges").font(.title2.bold()) }
                        if store.ordered.isEmpty {
                            Text("No challenges yet.").font(.body).foregroundStyle(.primary).fixedSize(horizontal: false, vertical: true)
                            Button("Explore challenges") { selection = 1 }.buttonStyle(ChallengeActionStyle())
                        }
                        ForEach(ChallengeV1Section.allCases, id: \.self) { section in
                            if let state = store.sections[section], !state.rows.isEmpty || state.error != nil {
                                Text(section.title).font(.headline)
                                if let message = state.error { Text(message).font(.caption) }
                                if !state.fresh && !state.rows.isEmpty { Text("Last saved view · refresh before making a choice.").font(.caption) }
                                ForEach(state.rows) { row in
                                    NavigationLink { ChallengeV1Detail(store: store, id: row.id) } label: {
                                        MatchdayChallengeCard(row: row, actor: store.actor)
                                    }.buttonStyle(.plain)
                                }
                                if state.cursor != nil { Button("More in \(section.title.lowercased())") { Task { await store.loadMore(section) } } }
                            }
                        }
                    }.padding(20)
                }.modifier(ChallengeScrollLegibility()).refreshable { await store.refresh() }
                    .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } } }
                    .navigationBarTitleDisplayMode(.inline)
            }.toolbar(.hidden, for: .tabBar).tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack {
                List {
                    Section {
                        Button("Create a challenge") { create = true }.accessibilityIdentifier("beta.create.open")
                        Text("Choose a friend goal, a best-result challenge or a personal goal.").font(.footnote)
                        ChallengeEntryPanel(store: store, invitation: invitation)
                    }
                    ForEach(ChallengeV1Section.allCases, id: \.self) { section in
                        Section(section.title) {
                            if let state = store.sections[section] {
                                if let message = state.error { Text(message).font(.caption) }
                                ForEach(state.rows) { row in
                                    NavigationLink { ChallengeV1Detail(store: store, id: row.id) } label: {
                                        VStack(alignment: .leading) { Text(row.title); Text(row.own(store.actor)?.exited == true ? "You left this challenge" : row.statusText).font(.caption) }
                                    }.accessibilityIdentifier("beta.row.\(row.status).\(row.policy).\(row.id.uuidString)")
                                }
                                if state.cursor != nil { Button("Show more") { Task { await store.loadMore(section) } }.accessibilityIdentifier("beta.more.\(section.rawValue)") }
                            }
                        }
                    }
                }.navigationTitle("Challenges").refreshable { await store.refresh() }
            }.toolbar(.hidden, for: .tabBar).tabItem { Label("Challenges", systemImage: "flag") }.tag(1)
            NavigationStack {
                ChallengeForm {
                    ChallengeFormSection("Activity") {
                        Text("Fictional activity only").font(.headline)
                        Text("All four Apple Health sources still need physical testing. Real activity cannot score these challenges.")
                    }
                    ChallengeFormSection("Account") {
                        Text("Switching accounts clears shared content. Saved actions belong only to the account that made them.")
                        Button("Sign out") { Task { await logout() } }.accessibilityIdentifier("beta.signout")
                    }
                    ChallengeFormSection("Help and safety") {
                        NavigationLink("Privacy and terms") { ChallengeLocalDisclosures() }
                        Text("You can leave any unfinished challenge from its details. No real money moves.")
                        Text("Report or block someone from a shared challenge. External beta access is closed.")
                    }
                }.navigationTitle("You")
            }.toolbar(.hidden, for: .tabBar).tabItem { Label("You", systemImage: "person") }.tag(2)
        }
        .toolbar(.hidden, for: .tabBar).clipped()
        ChallengeBottomNavigation(selection: $selection)
        }
        .sheet(isPresented: $create) { ChallengeV1Create(store: store) }
        .onChange(of: store.actor) { create = false }
        .onChange(of: scenePhase) { _, value in
            if value != .active { store.hide() }
            else { Task { await store.show() } }
        }
        .task(id: store.actor) { await store.watchVisibility() }
    }
    @ViewBuilder var recovery: some View {
        if let error = store.error { Text(error).foregroundStyle(.secondary).accessibilityIdentifier("beta.error") }
        if store.pending != nil {
            VStack(alignment: .leading, spacing: 12) {
                Text("Your action is saved on this phone.").font(.headline)
                Text("Retry checks the same action. Stop waiting checks whether it completed and prevents a late request from changing anything.")
                Button("Retry saved action") { Task { await store.retry() } }.accessibilityIdentifier("beta.retry")
                Button("Stop waiting for this action") { Task { await store.abandon() } }.accessibilityIdentifier("beta.abandon")
            }.disabled(store.busy)
        }
        if !store.fresh && !store.challenges.isEmpty { Text("Last saved view · refresh before making a choice.").font(.caption) }
    }
}

struct ChallengeBottomNavigation: View {
    @Binding var selection: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let tabs = [("Home", "house", "home"), ("Challenges", "flag", "challenges"), ("You", "person", "you")]
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Menu {
                    ForEach(tabs.indices, id: \.self) { index in
                        Button { selection = index } label: { Label(tabs[index].0, systemImage: tabs[index].1) }
                            .accessibilityIdentifier("beta.tab." + tabs[index].2)
                    }
                } label: {
                    HStack {
                        Text(tabs[selection].0).font(.body.bold()).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Image(systemName: "chevron.up.chevron.down").font(.body).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(CompetitiveTrustTheme.primaryText)
                }.accessibilityLabel("Navigation, " + tabs[selection].0).accessibilityIdentifier("beta.nav.menu")
            } else {
                HStack(alignment: .top, spacing: 8) {
                    ForEach(tabs.indices, id: \.self) { index in
                        Button { selection = index } label: {
                            VStack(spacing: 5) {
                                Image(systemName: tabs[index].1).font(.title3).accessibilityHidden(true)
                                Text(tabs[index].0).font(.caption.bold()).fixedSize(horizontal: false, vertical: true)
                            }.frame(maxWidth: .infinity, minHeight: 48)
                                .foregroundStyle(selection == index ? CompetitiveTrustTheme.actionCoral : CompetitiveTrustTheme.primaryText)
                                .contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel(tabs[index].0)
                            .accessibilityAddTraits(selection == index ? .isSelected : [])
                            .accessibilityIdentifier("beta.tab." + tabs[index].2)
                    }
                }
            }
        }.padding(.horizontal, 20).padding(.vertical, 10)
            .background(CompetitiveTrustTheme.paper)
            .overlay(alignment: .top) { Rectangle().fill(CompetitiveTrustTheme.hairlineDivider).frame(height: 1) }
    }
}

struct ChallengeScrollLegibility: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectHidden(true, for: .all).clipped() }
        else { content.clipped() }
    }
}
struct ChallengeActionStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.semibold))
            .padding(.horizontal, 16).padding(.vertical, 12).frame(minHeight: 44)
            .foregroundStyle(enabled ? CompetitiveTrustTheme.actionCoral : CompetitiveTrustTheme.primaryText)
            .background(enabled ? CompetitiveTrustTheme.coralTint : CompetitiveTrustTheme.paperSunk, in: RoundedRectangle(cornerRadius: 12))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct MatchdayChallengeCard: View {
    let row: ChallengeV1; let actor: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !dynamicTypeSize.isAccessibilitySize { HStack {
                MatchdayMetricIcon(metric: row.format.metric)
                Text(row.format.metric.title.uppercased()).font(.caption.bold()); Spacer(minLength:0)
                Text(row.format.mode.title).font(.caption)
            } }
            Text(row.own(actor)?.exited == true ? "You left this challenge" : row.statusText).font(.subheadline)
            Text(row.title.uppercased()).font(.title2.bold()).fixedSize(horizontal:false,vertical:true)
            if let own = row.own(actor) {
                if dynamicTypeSize.isAccessibilitySize {
                    Text("Your activity: " + (own.fact?.value.map { row.format.metric.display($0) } ?? "No update yet")).font(.body)
                    if row.format.hasTarget { Text("Your goal: " + (own.target.map { row.format.metric.display($0) } ?? "Choose a goal")).font(.body) }
                } else {
                    HStack(alignment:.top) {
                        value(own.fact?.value.map { row.format.metric.display($0) } ?? "No update", caption:"Your activity")
                        Spacer(minLength:8)
                        if row.format.hasTarget { value(own.target.map { row.format.metric.display($0) } ?? "Choose", caption:"Your goal") }
                    }
                }
            }
            Rectangle().fill(.white.opacity(0.65)).frame(height: 1).accessibilityHidden(true)
            Text("\(row.config.startDate) · \(row.config.days) days").font(.subheadline)
            Text("\(challengeMoney(row.config.amountCents)) simulated each · View challenge ↗").font(.caption)
        }.foregroundStyle(.white).padding(22).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(red:0.065,green:0.067,blue:0.063),in:RoundedRectangle(cornerRadius:18))
            .accessibilityElement(children: .combine)
    }
    private func value(_ value:String,caption:String)->some View {
        VStack(alignment:.leading,spacing:4) {
            Text(value).font(.title.bold().monospacedDigit()).foregroundStyle(CompetitiveTrustTheme.signalOrange)
            Text(caption).font(.caption)
        }
    }
}
func challengeMoney(_ cents: Int) -> String { (Double(cents)/100).formatted(.currency(code:"USD")) }


struct ChallengeV1Detail: View {
    @Bindable var store: ChallengeV1Store
    let id: UUID
    @State private var target = ""
    @State private var username = ""
    @State private var consent = false
    @State private var exitAction: String?
    @State private var reviewReason = "wrong_total"
    private var row: ChallengeV1? { store.challenges.first { $0.id == id } }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                if let row {
                    Text("Simulated stakes — no real money moves.").font(.caption)
                    MatchdayChallengeCard(row:row,actor:store.actor)
                    if let error = store.error { Text(error).foregroundStyle(.secondary) }
                    if store.pending != nil {
                        Button("Retry saved action") { Task { await store.retry() } }
                        Button("Stop waiting for this action") { Task { await store.abandon() } }
                    }
                    if row.socialHidden { Text("Shared details are hidden. Your own records and safe actions remain available.") }
                    if let counts = row.counts { Text("\(counts.joined) people joined").font(.subheadline) }
                    people(row)
                    rules(row)
                    if row.status == "lobby_open" { lobby(row) }
                    if row.status == "consent_pending", let own = row.own(store.actor),own.selected && !own.exited && !own.consented {
                        Toggle("I have read the complete rules and agree",isOn:$consent).accessibilityIdentifier("beta.consent.toggle")
                        Button("Agree to this challenge") { Task {
                            await store.submit(op:"consent",challenge:row,fields:["digest":.string(row.agreement?.digest ?? ""),"consent":.bool(true)])
                            consent=false
                        }}.disabled(!consent || !canAct).accessibilityIdentifier("beta.consent")
                    }
                    if row.format.mode == .friend && row.creatorId == store.actor && ["consent_pending","scheduled"].contains(row.status) {
                        Button("Reopen lobby and ask everyone again") { Task { await store.submit(op:"reopen",challenge:row) } }.disabled(!canAct)
                    }
                    if let notice = row.notice {
                        Text("Latest result update").font(.title2.bold())
                        Text("Ask us to review by \(notice.reviewBy.text(zone:row.config.timezone)).")
                        if let result=notice.result { allocation(result, row:row, confirmed:false) }
                        if row.status=="review" && row.serverTime < notice.reviewBy && !row.reviews.contains(where: { $0.noticeRevision == notice.revision }) {
                            Picker("Reason",selection:$reviewReason) {
                                Text("My total looks wrong").tag("wrong_total")
                                Text("Activity is missing").tag("missing_activity")
                                Text("My result looks wrong").tag("wrong_result")
                            }
                            Button("Ask us to review") { Task { await store.submit(op:"review",challenge:row,fields:["notice_revision":.integer(notice.revision),"reason":.string(reviewReason)]) } }
                                .disabled(!canAct).accessibilityIdentifier("beta.review")
                        }
                    }
                    ForEach(row.reviews) { review in
                        Text(review.decision != nil ? "Review complete. Refresh for the latest result." :
                             row.serverTime >= review.resolveBy ? "Review time has ended. Refresh to see your updated result and simulated return." :
                             "Your review request is saved. We’re checking your result.")
                    }
                    if let final=row.final {
                        Text("Result confirmed").font(.title2.bold())
                        allocation(final.result,row:row,confirmed:true)
                    }
                    if !row.isClosed && row.own(store.actor)?.exited == false {
                        Button("Leave challenge",role:.destructive) { exitAction="leave" }.disabled(!canAct).accessibilityIdentifier("beta.leave")
                        if row.creatorId==store.actor && row.serverTime < row.config.startsAt {
                            Button("Cancel challenge",role:.destructive) { exitAction="cancel" }.disabled(!canAct)
                        }
                    }
                } else { ContentUnavailableView("Refresh this challenge",systemImage:"arrow.clockwise",description:Text("Sign in to the same account and refresh to see its latest details.")) }
            }.padding(20)
        }.navigationTitle("Challenge").navigationBarTitleDisplayMode(.inline)
            .task(id: id) { await store.loadDetail(id) }
            .modifier(ChallengeScrollLegibility())
            .buttonStyle(ChallengeActionStyle())
            .refreshable { await store.loadDetail(id) }
            .toolbar { Button("Refresh",systemImage:"arrow.clockwise") { Task { await store.loadDetail(id) } } }
            .onChange(of:row?.revision) { consent=false }
            .onChange(of:store.actor) { consent=false;target="";username="";exitAction=nil }
            .confirmationDialog("Leave safely?",isPresented:Binding(get:{exitAction != nil},set:{if !$0 {exitAction=nil}}),titleVisibility:.visible) {
                Button(exitAction=="cancel" ? "Cancel challenge" : "Leave challenge",role:.destructive) {
                    if let row,let action=exitAction { Task { await store.submit(op:action,challenge:row) } };exitAction=nil
                }
            } message: { Text("Your simulated entry is returned. A shared challenge continues only if its agreed minimum remains. No real money moves.") }
    }
    private var canAct: Bool { row.map { store.isFresh($0) } == true && !store.busy && store.pending == nil }
    @ViewBuilder private func people(_ row:ChallengeV1)->some View {
        Text(row.format.mode == .friend ? "People and activity" : "Your activity").font(.title2.bold())
        ForEach(row.rankedMembers) { person in
            VStack(alignment:.leading,spacing:6) {
                HStack(alignment: .top) {
                    Text(String(person.username.prefix(2)).uppercased()).font(.caption.bold()).padding(10).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
                        .accessibilityLabel(person.actorId == store.actor ? "Your profile" : "Profile for \(person.username)")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(person.actorId==store.actor ? "You" : person.username).font(.headline).fixedSize(horizontal: false, vertical: true)
                        Text(person.exited ? "Left" : person.consented ? "Agreed" : person.selected ? "Selected" : "Requested").font(.caption).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                if row.format.hasTarget { Text(person.target.map { "Goal: \(row.format.metric.display($0))" } ?? "Goal not chosen") }
                if let finalStatus = row.final?.result.participants?[person.actorId.uuidString.lowercased()]?.status {
                    Text(resultText(finalStatus)).font(.subheadline.bold())
                }
                if let fact=person.fact {
                    Text(fact.value.map { "\(row.format.metric.display($0)) · fictional activity" } ?? "Activity unavailable")
                    Text("Updated \(fact.recordedAt.text(zone:row.config.timezone))").font(.caption)
                    if let value=fact.value, person.actorId==store.actor {
                        Chart {
                            BarMark(x:.value(row.format.metric.title,value),y:.value("Activity","You"))
                                .foregroundStyle(CompetitiveTrustTheme.signalOrange)
                            if let target=person.target { RuleMark(x:.value("Goal",target)).lineStyle(StrokeStyle(dash:[4])) }
                        }.chartXScale(domain:0...max(1,value,person.target ?? 0))
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 3)) { axis in
                                AxisGridLine(); AxisValueLabel { if let exact = axis.as(Int.self) { Text(row.format.metric.display(exact)) } }
                            } }.frame(height:100)
                            .accessibilityLabel("Your activity: \(row.format.metric.display(value)).")
                            .accessibilityValue(person.target.map { "Goal: \(row.format.metric.display($0))" } ?? "Best result wins")
                    }
                }
                if person.actorId != store.actor { ChallengePersonSafety(store: store, person: person) }
                if row.status=="lobby_open",row.creatorId==store.actor,person.actorId != store.actor,!person.exited {
                    Button(person.selected ? "Remove from roster" : "Select for roster") { Task {
                        await store.submit(op:"select",challenge:row,fields:["actor_id":.string(person.actorId.uuidString.lowercased()),"selected":.bool(!person.selected)])
                    }}.disabled(!canAct).accessibilityIdentifier("beta.select.\(person.username)")
                    if !person.selected {
                        Button("Decline request") { Task { await store.submit(op: "reject", challenge: row, fields: ["actor_id": .string(person.actorId.uuidString.lowercased())]) } }.disabled(!canAct)
                    }
                }
            }.padding(.vertical,8)
            Divider()
        }
    }
    private func rules(_ row:ChallengeV1)->some View {
        DisclosureGroup("Complete challenge rules") {
            ChallengeAgreementText(policy:row.format,window:row.config,minimum:row.agreement?.terms?["minimum"]?.integer ?? (row.format.mode == .personal ? 1 : 2))
        }
    }
    @ViewBuilder private func lobby(_ row:ChallengeV1)->some View {
        if row.format.hasTarget && row.own(store.actor)?.exited == false {
            TextField(row.format.metric.targetPrompt,text:$target).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).accessibilityIdentifier("beta.target.input")
            Button("Propose my goal") { Task { if let value=row.format.metric.parse(target) { await store.submit(op:"target",challenge:row,fields:["target":.integer(value)]) } } }.disabled(!canAct || row.format.metric.parse(target)==nil).accessibilityIdentifier("beta.target.submit")
        }
        if row.creatorId==store.actor {
            ChallengeLinkIssuer(store:store,row:row)
            TextField("Exact friend username",text:$username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder).accessibilityIdentifier("beta.invite.input")
            Button("Invite friend") { Task { await store.submit(op:"invite",challenge:row,fields:["username":.string(username)]); if store.pending == nil { username = "" } } }.disabled(!canAct || username.isEmpty).accessibilityIdentifier("beta.invite.submit")
            Button(row.format.hasTarget ? "Lock in roster and goals" : "Lock in roster") { Task { await store.submit(op:"freeze",challenge:row) } }.disabled(!canAct)
                .accessibilityIdentifier("beta.freeze")
        }
    }
    private func resultText(_ status: String) -> String {
        switch status { case "met": "Goal met"; case "missed": "Goal missed"; case "winner": "Winning result"; case "placed": "Result recorded"; default: "Your entry returns" }
    }
    private func allocation(_ result:ChallengeV1.Allocation,row:ChallengeV1,confirmed:Bool)->some View {
        let own=store.actor.flatMap { result.participants?[$0.uuidString.lowercased()] } ?? result.own
        return VStack(alignment:.leading,spacing:8) {
            if let own {
                Text(resultText(own.status))
                Text("\(confirmed ? "Recorded simulated return" : "Proposed simulated return"): \(challengeMoney(own.returnedCents))")
            }
            if let cents=result.unallocatedCents { Text("Unallocated simulation: \(challengeMoney(cents))").font(.caption) }
            Text("Nothing can be paid out or redeemed. No real money moved.").font(.caption)
        }
    }
}
#endif
