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
    @State private var email = ""
    @State private var password = ""
    var body: some View {
        Group {
            if let store = session.store, store.actor != nil {
                ChallengeV1Shell(store: store, logout: { await session.logout() })
            } else {
                NavigationStack {
                    Form {
                        Section("Local challenge preview") {
                            Text("Fictional activity and simulated stakes. Nothing can be paid out or redeemed.")
                            TextField("Local account email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("beta.login.email")
                            SecureField("Password", text: $password).accessibilityIdentifier("beta.login.password")
                            Button("Sign in") { Task { await session.login(email: email, password: password); password = "" } }
                                .disabled(session.store == nil || email.isEmpty || password.isEmpty)
                                .accessibilityIdentifier("beta.login.submit")
                        }
                        if let message = session.message { Text(message) }
                    }.navigationTitle("GameTime")
                }
            }
        }.tint(CompetitiveTrustTheme.actionCoral)
    }
}

struct ChallengeV1Shell: View {
    @Bindable var store: ChallengeV1Store
    let logout: @MainActor () async -> Void
    @Environment(\.scenePhase) private var scenePhase
    @State private var create = false
    @State private var selection = 0
    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("GameTime").font(.largeTitle.bold().italic())
                        Text("Simulated stakes — no real money moves.").font(.subheadline)
                        recovery
                        Text("Your challenges").font(.title2.bold())
                        if store.ordered.isEmpty {
                            ContentUnavailableView("Start something together", systemImage: "flag", description: Text("Create a lobby, invite friends and each choose your own goal."))
                        }
                        ForEach(store.ordered) { row in
                            NavigationLink { ChallengeV1Detail(store: store, id: row.id) } label: {
                                MatchdayChallengeCard(row: row, actor: store.actor)
                            }.buttonStyle(.plain)
                        }
                    }.padding(20)
                }.refreshable { await store.refresh() }
                    .toolbar { Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh() } } }
                    .navigationBarTitleDisplayMode(.inline)
            }.tabItem { Label("Home", systemImage: "house") }.tag(0)
            NavigationStack {
                List {
                    Section {
                        Button("Create friend steps goal") { create = true }.accessibilityIdentifier("beta.create.open")
                        Text("Other formats will appear after the first complete journey is accepted.").font(.footnote)
                    }
                    Section("Challenges and history") {
                        ForEach(store.challenges) { row in
                            NavigationLink { ChallengeV1Detail(store: store, id: row.id) } label: {
                                VStack(alignment: .leading) { Text(row.title); Text(row.statusText).font(.caption) }
                            }
                        }
                    }
                }.navigationTitle("Challenges").refreshable { await store.refresh() }
            }.tabItem { Label("Challenges", systemImage: "flag") }.tag(1)
            NavigationStack {
                Form {
                    Section("Activity") {
                        Text("Fictional activity only").font(.headline)
                        Text("All four Apple Health sources still need physical testing. Real activity cannot score these challenges.")
                    }
                    Section("Account") {
                        Text("Switching accounts clears shared content. Saved actions belong only to the account that made them.")
                        Button("Sign out") { Task { await logout() } }.accessibilityIdentifier("beta.signout")
                    }
                    Section("Help and safety") {
                        Text("You can leave any unfinished challenge from its details. No real money moves.")
                        Text("Support and moderation are being prepared for local acceptance. External beta access is closed.")
                    }
                }.navigationTitle("You")
            }.tabItem { Label("You", systemImage: "person") }.tag(2)
        }
        .sheet(isPresented: $create) { ChallengeV1Create(store: store) }
        .onChange(of: store.actor) { create = false }
        .onChange(of: scenePhase) { _, value in
            if value != .active { store.hide() }
            else { Task { await store.refresh() } }
        }
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

/// Original supplied sole geometry on its 24-unit grid; decorative beside text.
struct MatchdayStepsIcon: View {
    var body: some View {
        Canvas { context, size in
            context.scaleBy(x: size.width / 24, y: size.height / 24)
            var path = Path()
            for (x,y) in [(4.0,5.5),(14.0,9.5)] {
                path.move(to:CGPoint(x:x,y:y+4.5))
                path.addLine(to:CGPoint(x:x,y:y))
                path.addCurve(to:CGPoint(x:x+5,y:y),control1:CGPoint(x:x,y:y-3.333333),control2:CGPoint(x:x+5,y:y-3.333333))
                path.addLine(to:CGPoint(x:x+5,y:y+4.5));path.closeSubpath()
                path.move(to:CGPoint(x:x,y:y+7.5));path.addLine(to:CGPoint(x:x+5,y:y+7.5))
                path.addLine(to:CGPoint(x:x+5,y:y+9.5))
                path.addCurve(to:CGPoint(x:x,y:y+9.5),control1:CGPoint(x:x+5,y:y+12.833333),control2:CGPoint(x:x,y:y+12.833333))
                path.closeSubpath()
            }
            context.stroke(path,with:.foreground,style:StrokeStyle(lineWidth:1.75,lineCap:.round,lineJoin:.round))
        }.rotationEffect(.degrees(20)).frame(width:28,height:28).accessibilityHidden(true)
    }
}
struct MatchdayChallengeCard: View {
    let row: ChallengeV1; let actor: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { MatchdayStepsIcon(); Text("STEPS · \(row.members.filter(\.selected).count) PEOPLE").font(.caption.bold()); Spacer(minLength:0) }
            Text(row.statusText).font(.subheadline)
            Text(row.title.uppercased()).font(.largeTitle.bold()).fixedSize(horizontal:false,vertical:true)
            if let own = row.own(actor) {
                HStack(alignment:.top) {
                    value(own.fact?.value?.formatted() ?? "—", caption:"Your steps")
                    Spacer(minLength:8)
                    value(own.target?.formatted() ?? "Choose", caption:"Your goal")
                }
            }
            Divider().overlay(.gray)
            Text("\(row.config.startDate) · \(row.config.days) days").font(.subheadline)
            Text("\(money(row.config.amountCents)) simulated each · View challenge ↗").font(.caption)
        }.foregroundStyle(.white).padding(22).frame(maxWidth:.infinity,alignment:.leading)
            .background(Color(red:0.065,green:0.067,blue:0.063),in:RoundedRectangle(cornerRadius:18))
            .accessibilityElement(children:.combine)
    }
    private func value(_ value:String,caption:String)->some View {
        VStack(alignment:.leading,spacing:4) {
            Text(value).font(.title.bold().monospacedDigit()).foregroundStyle(CompetitiveTrustTheme.signalOrange)
            Text(caption).font(.caption)
        }
    }
}
private func money(_ cents: Int) -> String { (Double(cents)/100).formatted(.currency(code:"USD")) }

struct ChallengeV1Create: View {
    @Bindable var store: ChallengeV1Store
    @Environment(\.dismiss) private var dismiss
    @State private var start = Calendar.current.date(byAdding:.day,value:2,to:Date())!
    @State private var days = 7
    @State private var dollars = 20
    @State private var zone = TimeZone.current.identifier
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Simulated stakes — no real money moves.")
                    Text("You’ll invite friends next. Everyone chooses their own goal before you lock in the roster and ask everyone to agree.")
                }
                Section("Dates and amount") {
                    DatePicker("Starts",selection:$start,displayedComponents:.date)
                    Stepper("\(days) days",value:$days,in:1...30)
                    TextField("Time zone",text:$zone).autocorrectionDisabled()
                    Stepper("\(money(dollars*100)) simulated each",value:$dollars,in:1...500)
                    Text("Starts in 2–30 calendar days. Every day runs from midnight to midnight in the selected time zone.").font(.footnote)
                }
                if let error = store.error { Text(error) }
                Button("Create lobby") { Task {
                    let fmt = DateFormatter(); fmt.timeZone = TimeZone(identifier:zone); fmt.dateFormat="yyyy-MM-dd"
                    await store.submit(op:"create",fields:["config":.object(["start_date":.string(fmt.string(from:start)),"days":.integer(days),"timezone":.string(zone),"amount_cents":.integer(dollars*100)])])
                    if store.pending == nil && store.lastReceipt?.id != nil { dismiss() }
                }}.disabled(store.busy || store.pending != nil).accessibilityIdentifier("beta.create.submit")
            }.navigationTitle("Friend steps goal")
                .toolbar { Button("Close") { dismiss() } }
        }
    }
}

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
                    people(row)
                    rules(row)
                    if row.status == "lobby_open" { lobby(row) }
                    if row.status == "consent_pending", let own = row.own(store.actor),own.selected && !own.exited && !own.consented {
                        Toggle("I have read the complete rules and agree",isOn:$consent)
                        Button("Agree to this challenge") { Task {
                            await store.submit(op:"consent",challenge:row,fields:["digest":.string(row.agreement?.digest ?? ""),"consent":.bool(true)])
                            consent=false
                        }}.disabled(!consent || !canAct).accessibilityIdentifier("beta.consent")
                    }
                    if row.creatorId == store.actor && ["consent_pending","scheduled"].contains(row.status) {
                        Button("Reopen lobby and ask everyone again") { Task { await store.submit(op:"reopen",challenge:row) } }.disabled(!canAct)
                    }
                    if let notice = row.notice {
                        Text("Latest result update").font(.title2.bold())
                        Text("Ask us to review by \(notice.reviewBy.text(zone:row.config.timezone)).")
                        if let result=notice.result { allocation(result, row:row, confirmed:false) }
                        if row.status=="review" && row.serverTime < notice.reviewBy && row.reviews.isEmpty {
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
                        Text(review.decision == nil ? "Your review request is saved. We’re checking your result." : "Review complete. Refresh for the latest result.")
                    }
                    if let final=row.final {
                        Text("Result confirmed").font(.title2.bold())
                        allocation(final.result,row:row,confirmed:true)
                    }
                    if !row.isClosed {
                        Button("Leave challenge",role:.destructive) { exitAction="leave" }.disabled(!canAct).accessibilityIdentifier("beta.leave")
                        if row.creatorId==store.actor && row.serverTime < row.config.startsAt {
                            Button("Cancel challenge",role:.destructive) { exitAction="cancel" }.disabled(!canAct)
                        }
                    }
                } else { ContentUnavailableView("Refresh this challenge",systemImage:"arrow.clockwise",description:Text("Sign in to the same account and refresh to see its latest details.")) }
            }.padding(20)
        }.navigationTitle("Challenge").navigationBarTitleDisplayMode(.inline)
            .refreshable { await store.refresh() }
            .toolbar { Button("Refresh",systemImage:"arrow.clockwise") { Task { await store.refresh() } } }
            .onChange(of:row?.revision) { consent=false }
            .onChange(of:store.actor) { consent=false;target="";username="";exitAction=nil }
            .confirmationDialog("Leave safely?",isPresented:Binding(get:{exitAction != nil},set:{if !$0 {exitAction=nil}}),titleVisibility:.visible) {
                Button(exitAction=="cancel" ? "Cancel challenge" : "Leave challenge",role:.destructive) {
                    if let row,let action=exitAction { Task { await store.submit(op:action,challenge:row) } };exitAction=nil
                }
            } message: { Text("Your simulated entry is returned. The friend challenge can continue only if at least two people remain. No real money moves.") }
    }
    private var canAct: Bool { store.fresh && !store.busy && store.pending == nil }
    @ViewBuilder private func people(_ row:ChallengeV1)->some View {
        Text("People and goals").font(.title2.bold())
        ForEach(row.members) { person in
            VStack(alignment:.leading,spacing:6) {
                HStack {
                    Text(String(person.username.prefix(2)).uppercased()).font(.caption.bold()).padding(10).background(.quaternary,in:RoundedRectangle(cornerRadius:8))
                    Text(person.actorId==store.actor ? "You" : person.username).font(.headline)
                    Spacer(minLength:0)
                    Text(person.exited ? "Left" : person.consented ? "Agreed" : person.selected ? "Selected" : "Requested").font(.caption)
                }
                Text(person.target.map { "Goal: \($0.formatted()) steps" } ?? "Goal not chosen")
                if let fact=person.fact {
                    Text(fact.value.map { "\($0.formatted()) steps · fictional activity" } ?? "Activity unavailable")
                    Text("Updated \(fact.recordedAt.text(zone:row.config.timezone))").font(.caption)
                    if let value=fact.value, person.actorId==store.actor,let target=person.target {
                        Chart {
                            BarMark(x:.value("Steps",value),y:.value("Activity","You"))
                                .foregroundStyle(CompetitiveTrustTheme.signalOrange)
                            RuleMark(x:.value("Goal",target)).lineStyle(StrokeStyle(dash:[4]))
                        }.chartXScale(domain:0...max(value,target)).frame(height:80)
                            .accessibilityLabel("Your steps: \(value). Your goal: \(target).")
                    }
                }
                if row.status=="lobby_open",row.creatorId==store.actor,person.actorId != store.actor,!person.exited {
                    Button(person.selected ? "Remove from roster" : "Select for roster") { Task {
                        await store.submit(op:"select",challenge:row,fields:["actor_id":.string(person.actorId.uuidString.lowercased()),"selected":.bool(!person.selected)])
                    }}.disabled(!canAct)
                }
            }.padding(.vertical,8)
            Divider()
        }
    }
    private func rules(_ row:ChallengeV1)->some View {
        DisclosureGroup("Complete challenge rules") {
            VStack(alignment:.leading,spacing:10) {
                Text("Each person has their own cumulative steps goal. Count at least your agreed goal to meet it.")
                Text("Source: fictional steps for this local preview. No Apple Health activity is scored.")
                Text("Starts: \(row.config.startsAt.text(zone:row.config.timezone))")
                Text("Ends, not included: \(row.config.endsAt.text(zone:row.config.timezone))")
                Text("Initial updates through \(row.config.syncBy.text(zone:row.config.timezone)). Corrections through \(row.config.correctionsBy.text(zone:row.config.timezone)).")
                Text("Every selected person agrees to this same roster, each goal, these dates and \(money(row.config.amountCents)) simulated each. Nothing can be redeemed.")
                Text("A missing result never proves a missed goal. We exclude and return simulated entries for missing results or anyone who leaves. Fewer than two confirmed results means everyone’s entry returns.")
                Text("People who meet their goals recover their own entry and share confirmed misses evenly. Any remainder and an all-miss pool stay unallocated.")
                Text("You have 48 hours after the actual result notice to ask for a review. Reviewers have 72 hours after your request. A processing delay never shortens those windows.")
                Text("Reopening the lobby requires a new agreement from everyone. Incomplete agreement at the start cancels the challenge.")
            }.font(.subheadline)
        }
    }
    @ViewBuilder private func lobby(_ row:ChallengeV1)->some View {
        if row.own(store.actor)?.exited == false {
            TextField("Your total steps goal",text:$target).keyboardType(.numberPad).textFieldStyle(.roundedBorder)
            Button("Propose my goal") { Task { if let value=Int(target) { await store.submit(op:"target",challenge:row,fields:["target":.integer(value)]) } } }.disabled(!canAct || Int(target)==nil)
        }
        if row.creatorId==store.actor {
            TextField("Exact friend username",text:$username).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
            Button("Invite friend") { Task { await store.submit(op:"invite",challenge:row,fields:["username":.string(username)]) } }.disabled(!canAct || username.isEmpty)
            Button("Lock in roster and goals") { Task { await store.submit(op:"freeze",challenge:row) } }.disabled(!canAct)
                .accessibilityIdentifier("beta.freeze")
        }
    }
    private func allocation(_ result:ChallengeV1.Allocation,row:ChallengeV1,confirmed:Bool)->some View {
        let own=store.actor.flatMap { result.participants?[$0.uuidString.lowercased()] } ?? result.own
        return VStack(alignment:.leading,spacing:8) {
            if let own {
                Text(own.status=="met" ? "Goal met" : own.status=="missed" ? "Goal missed" : "Your entry returns")
                Text("\(confirmed ? "Recorded simulated return" : "Proposed simulated return"): \(money(own.returnedCents))")
            }
            if let cents=result.unallocatedCents { Text("Unallocated simulation: \(money(cents))").font(.caption) }
            Text("Nothing can be paid out or redeemed. No real money moved.").font(.caption)
        }
    }
}
#endif
