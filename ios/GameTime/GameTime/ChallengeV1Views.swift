import Supabase
import SwiftUI

#if DEBUG

enum ChallengeLocalLaunch {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--beta-challenges-local") }

    /// Disposable local Supabase stacks can use either a publishable key or the
    /// signed anonymous key supplied by the local bootstrap. This route is
    /// DEBUG-only and still requires an explicit loopback URL.
    static func acceptsLocalKey(_ key: String) -> Bool {
        key.hasPrefix("sb_publishable_")
            || key.split(separator: ".").count == 3
    }
}

/// Controlled sign-in substitute for the ordinary AppModel/Signal path. It uses
/// the same service selection as live Apple auth, but only task-owned loopback
/// accounts and disabled Health/provider services. Never compiled into Release.
@MainActor enum ChallengeAuthenticatedAppLaunch {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--authenticated-app-local") }
    static let identity = AppleIdentity(idToken: "local-substitute", rawNonce: "local-substitute", firstSignInDisplayName: nil)

    static func configuration() throws -> AppConfiguration {
        let env = ProcessInfo.processInfo.environment
        guard enabled, let text = env["GAMETIME_BETA_LOCAL_URL"], let url = URL(string: text),
              SupabaseWeeklyClient.isExplicitLoopback(url) else { throw ChallengeV1Error.unavailable }
        return try AppConfiguration.validated(environmentValue: "debug", urlValue: text,
            keyValue: env["GAMETIME_BETA_LOCAL_KEY"], mutationValue: "NO",
            challengeV1Value: "YES")
    }

    static func services(configuration: AppConfiguration) -> AppServices {
        let sdk = SupabaseClient(supabaseURL: configuration.supabaseURL,
            supabaseKey: configuration.supabasePublishableKey,
            options: .init(auth: .init(storage: ChallengeMemoryAuthStorage(), autoRefreshToken: false,
                emitLocalSessionAsInitialSession: true)))
        var health: ChallengeHealthFlowDependencies?
        if ProcessInfo.processInfo.arguments.contains("--p9-synthetic-health"),
           let token = ProcessInfo.processInfo.environment["GAMETIME_P9_CONTROL"],
           let local = try? ChallengeHealthSyntheticLocal(origin: configuration.supabaseURL, control: token),
           let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            health = try? local.dependencies(sdk: sdk, key: configuration.supabasePublishableKey,
                directory: root.appendingPathComponent("GameTime/P9Synthetic"))
        }
        return FixtureServicesFactory.make(arguments: ["--fixture-mode"],
            authClient: ChallengeAppSignInSubstitute(sdk: sdk),
            personalHealthSteps: DisabledPersonalHealthStepReader(),
            profileClient: SupabaseProfileClient(client: sdk),
            challengesV1: LiveServicesFactory.makeChallenges(configuration: configuration, client: sdk),
            challengeHealthDependencies: health)
    }
}

@MainActor private final class ChallengeAppSignInSubstitute: AuthClient {
    let sdk: SupabaseClient
    let auth: SupabaseAuthClient
    init(sdk: SupabaseClient) { self.sdk = sdk; auth = SupabaseAuthClient(client: sdk) }
    func currentUserID() async -> UUID? { await auth.currentUserID() }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { await auth.authStateChanges() }
    func signOut() async throws { try await auth.signOut() }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID {
        let env = ProcessInfo.processInfo.environment
        guard ChallengeAuthenticatedAppLaunch.enabled, identity == ChallengeAuthenticatedAppLaunch.identity,
              let email = env["GAMETIME_BETA_LOCAL_EMAIL"], let password = env["GAMETIME_BETA_LOCAL_PASSWORD"] else {
            throw ChallengeV1Error.unavailable
        }
        return try await sdk.auth.signIn(email: email, password: password).user.id
    }
}

/// A narrow, DEBUG-only route for exercising account deletion against an
/// owned loopback fixture. It is unavailable unless both flags are present.
enum ChallengeLocalAccountDeletionLaunch {
    static var enabled: Bool {
        ChallengeLocalLaunch.enabled
            && ProcessInfo.processInfo.arguments.contains("--account-deletion-local")
    }

    static var confirmationCode: String? {
        guard enabled,
              let code = ProcessInfo.processInfo.environment[
                "GAMETIME_ACCOUNT_DELETION_LOCAL_CODE"
              ]?.trimmingCharacters(in: .whitespacesAndNewlines),
              code.count >= 8 else { return nil }
        return code
    }
}

@MainActor @Observable final class ChallengeLocalSession {
    let store: ChallengeV1Store?
    let sdk: SupabaseClient?
    private let localURL: URL?
    private let localKey: String?
    private(set) var accountDeletionModel: AppModel?
    var message: String?
    private(set) var signingIn = false
    init() {
        let env = ProcessInfo.processInfo.environment
        guard let text = env["GAMETIME_BETA_LOCAL_URL"], let url = URL(string: text),
              SupabaseWeeklyClient.isExplicitLoopback(url),
              let key = env["GAMETIME_BETA_LOCAL_KEY"],
              ChallengeLocalLaunch.acceptsLocalKey(key) else {
            sdk = nil; store = nil; localURL = nil; localKey = nil
            message = "This local preview needs its own connection settings. Follow the launch instructions to continue."
            return
        }
        let client = SupabaseClient(supabaseURL: url, supabaseKey: key,
            options: .init(auth: .init(storage: ChallengeMemoryAuthStorage(), autoRefreshToken: false, emitLocalSessionAsInitialSession: true)))
        sdk = client; localURL = url; localKey = key
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        store = ChallengeV1Store(auth: SupabaseAuthClient(client: client), client: SupabaseChallengeV1Client(sdk: client, url: url, key: key),
            requests: ChallengeV1RequestStore(directory: root.appendingPathComponent("GameTime/ChallengeV1Pending")))
    }
    func login(email: String, password: String) async {
        guard let sdk, let store, !signingIn else { return }
        signingIn = true
        defer { signingIn = false }
        store.setActor(nil)
        do {
            let session = try await sdk.auth.signIn(email: email, password: password)
            store.setActor(session.user.id)
            if ChallengeLocalAccountDeletionLaunch.enabled {
                guard let code = ChallengeLocalAccountDeletionLaunch.confirmationCode,
                      let localURL, let localKey else {
                    try? await sdk.auth.signOut(scope: .local)
                    store.setActor(nil)
                    message = "This local account-deletion check needs its confirmation code. Start the owned local check again."
                    return
                }
                let configuration = AppConfiguration(
                    environment: .debug,
                    supabaseURL: localURL,
                    supabasePublishableKey: localKey,
                    contestMutationsEnabled: false
                )
                let receiptDirectory = FileManager.default.urls(
                    for: .applicationSupportDirectory,
                    in: .userDomainMask
                )[0].appendingPathComponent("GameTime/LocalAccountDeletion")
                let services = FixtureServicesFactory.make(
                    arguments: ["--fixture-mode"],
                    authClient: ChallengeLocalDeletionAuthClient(
                        client: sdk,
                        confirmationCode: code
                    ),
                    accountDeletionClient: SupabaseAccountDeletionClient(
                        client: sdk,
                        configuration: configuration
                    ),
                    accountDeletionReceiptStore: FileAccountDeletionReceiptStore(
                        directory: receiptDirectory
                    ),
                    profileClient: SupabaseProfileClient(client: sdk)
                )
                let model = AppModel(configuration: configuration, services: services)
                await model.start()
                guard model.userID == session.user.id else {
                    try? await sdk.auth.signOut(scope: .local)
                    store.setActor(nil)
                    message = "We couldn’t open the local account check. Start it again with its owned local account."
                    return
                }
                accountDeletionModel = model
            }
            message = nil
            await store.refresh()
        } catch { message = "We couldn’t sign in. Check the local account and password, then try again." }
    }
    func logout() async {
        store?.setActor(nil)
        accountDeletionModel = nil
        try? await sdk?.auth.signOut(scope: .local)
    }
}

@MainActor
private final class ChallengeLocalDeletionAuthClient: AuthClient {
    private let client: SupabaseClient
    private let confirmationCode: String
    private let liveAuth: SupabaseAuthClient

    init(client: SupabaseClient, confirmationCode: String) {
        self.client = client
        self.confirmationCode = confirmationCode
        liveAuth = SupabaseAuthClient(client: client)
    }

    func currentUserID() async -> UUID? { await liveAuth.currentUserID() }

    func authStateChanges() async -> AsyncStream<AuthSnapshot> {
        await liveAuth.authStateChanges()
    }

    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID {
        guard ChallengeLocalAccountDeletionLaunch.enabled,
              identity.authorizationCode == confirmationCode,
              let actor = client.auth.currentSession?.user.id else {
            throw AccountDeletionError.accountChanged
        }
        return actor
    }

    func signOut() async throws { try await liveAuth.signOut() }
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
    @State private var invitation = ChallengeInvitationIntent(links: .localFixture)
    @State private var email = ProcessInfo.processInfo.environment["GAMETIME_BETA_LOCAL_EMAIL"] ?? ""
    @State private var password = ProcessInfo.processInfo.environment["GAMETIME_BETA_LOCAL_PASSWORD"] ?? ""
    var body: some View {
        Group {
            if ProcessInfo.processInfo.arguments.contains("--beta-a11y-control-check") {
                ChallengeControlDiagnostic()
            } else if let store = session.store, store.actor != nil {
                ChallengeV1Shell(
                    store: store,
                    invitation: invitation,
                    logout: { await session.logout() },
                    accountContent: session.accountDeletionModel.map {
                        AnyView(
                            ChallengeLocalAccountDeletionView(
                                model: $0,
                                logout: { await session.logout() }
                            )
                        )
                    }
                )
            } else if let model = session.accountDeletionModel,
                      model.accountDeletionReceipt != nil {
                // D81 ends this local actor's normal Auth session as soon as
                // the deletion is accepted. Keep only the saved receipt route
                // available instead of sending the just-deleted actor back to
                // the ordinary local sign-in form.
                AccountDeletionReceiptView()
                    .environment(model)
            } else {
                NavigationStack {
                    ChallengeForm {
                        ChallengeFormSection("Local challenge preview") {
                            Text("Fictional activity and simulated stakes. Nothing can be paid out or redeemed.")
                            TextField("Local account email", text: $email).textInputAutocapitalization(.never).autocorrectionDisabled()
                                .accessibilityIdentifier("beta.login.email")
                            SecureField("Password", text: $password).accessibilityIdentifier("beta.login.password")
                            Button("Sign in") { Task { await session.login(email: email, password: password); password = ""; if session.store?.actor != nil { email = "" } } }
                                .disabled(session.signingIn || session.store == nil || email.isEmpty || password.isEmpty)
                                .accessibilityIdentifier("beta.login.submit")
                            if session.signingIn { ProgressView("Signing in…") }
                        }
                        if let message = session.message { Text(message) }
                        if let message = invitation.message { Text(message) }
                    }.navigationTitle("GameTime")
                }
            }
        }.frame(maxWidth: ProcessInfo.processInfo.arguments.contains("--beta-compact-check") ? 320 : .infinity)
            .tint(SignalTheme.accent).background(SignalTheme.canvas).onOpenURL { invitation.receive($0) }
    }
}

private struct ChallengeLocalAccountDeletionView: View {
    let model: AppModel
    let logout: @MainActor () async -> Void

    var body: some View {
        NavigationStack {
            ChallengeForm {
                ChallengeFormSection("Account") {
                    NavigationLink("Account & support") {
                        AccountSupportView().environment(model)
                    }
                    .accessibilityIdentifier("local-account-deletion.support")
                    Button("Sign out") { Task { await logout() } }
                        .accessibilityIdentifier("beta.signout")
                }
                ChallengeFormSection("This local check") {
                    Text("This uses a fictional local account and a local confirmation substitute. It does not contact Apple or a payment provider.")
                }
            }
            .navigationTitle("You")
        }
        .environment(model)
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
                Text("The local service saves your account, challenge agreements, consent, normalized fictional progress, corrections, reviews and results. Saved requests and issued invitation links on this phone help recover interrupted actions and manage your links.")
                Text("Selected friends can see your username, agreed goal when there is one, current challenge activity and results. Personal activity and community activity are private to you. Community totals require at least five current participants and are delayed by at least 15 minutes.")
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

#endif

struct ChallengeV1Shell: View {
    @Bindable var store: ChallengeV1Store
    @Bindable var invitation: ChallengeInvitationIntent
    let logout: @MainActor () async -> Void
    var accountContent: AnyView? = nil
    var existingChallenges: AnyView? = nil
    var serviceAvailable = true
    var personalStepsOnly = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.challengeHealthFlow) private var health
    @State private var create = false
    @State private var selection = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(spacing: 0) {
        SignalSimulationBanner()
        TabView(selection: $selection) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        SignalHomeHeader(create: { create = true }, refresh: { Task { await store.refresh(); await health?.refresh() } })
                        if let existingChallenges { existingChallenges }
                        if serviceAvailable { recovery }
                        if !serviceAvailable {
                            SignalNotice {
                                Text("Your next challenge starts here").font(.headline)
                                Text("Friend challenges and new personal goals aren’t open yet. You can still view and manage your existing challenges.")
                            }.accessibilityIdentifier("signal.service.closed")
                        } else if store.actor == nil {
                            Text(ChallengeV1Error.accountChanged.localizedDescription)
                            Button("Sign out") { Task { await logout() } }
                                .accessibilityIdentifier("beta.session.signout")
                        } else if store.homeState == .loading {
                            ProgressView("Loading your challenges…").accessibilityIdentifier("beta.home.loading")
                        } else if store.homeState == .unavailable {
                            Text("We couldn’t load your challenges. Refresh to try again.")
                                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("beta.home.unavailable")
                        } else if store.homeState == .empty {
                            Text("No challenges yet.").font(.body).foregroundStyle(SignalTheme.textPrimary).fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("beta.home.empty")
                            Button("Explore challenges") { selection = 1 }.buttonStyle(ChallengeActionStyle())
                        }
                        ForEach(ChallengeV1Section.allCases, id: \.self) { section in
                            if let state = store.sections[section], !state.rows.isEmpty || (state.error != nil && state.error != store.error) {
                                if section == .action || section == .history { Text(section.title).font(.headline).accessibilityAddTraits(.isHeader) }
                                if let message = state.error, message != store.error { Text(message).font(.caption) }
                                if !state.fresh && !state.rows.isEmpty { Text("Last saved view · refresh before making a choice.").font(.caption) }
                                ForEach(homeRows(state.rows, section: section)) { row in
                                    NavigationLink { ChallengeV1Detail(store: store, id: row.id) } label: {
                                        if row.id == featuredID {
                                            SignalFeaturedChallenge(row: row, actor: store.actor)
                                        } else {
                                            SignalChallengeSummary(row: row, actor: store.actor)
                                        }
                                    }.buttonStyle(.plain)
                                }
                                if state.cursor != nil { Button("More in \(section.title.lowercased())") { Task { await store.loadMore(section) } } }
                            }
                        }
                    }.padding(.horizontal, SignalTheme.contentInset).padding(.vertical, 12).modifier(SignalGlassGroup())
                }.background(SignalTheme.canvas).modifier(ChallengeScrollLegibility()).refreshable { await store.refresh(); await health?.refresh() }
                    .toolbar(.hidden, for: .navigationBar)
                    .navigationBarTitleDisplayMode(.inline)
            }.tabItem { Label("Home", systemImage: "house").accessibilityIdentifier("beta.tab.home") }.tag(0)
            NavigationStack {
                List {
                    Section {
                        Button("Create a challenge") { create = true }.accessibilityIdentifier("beta.create.open")
                        Text(personalStepsOnly ? "Set your own personal step goal." : "Choose a friend goal, a best-result challenge or a personal goal.").font(.footnote)
                        if serviceAvailable {
                            ChallengeEntryPanel(store: store, invitation: invitation)
                        } else {
                            Text("New challenges aren’t open yet. You can still view and manage your existing challenges.")
                            if let existingChallenges { existingChallenges }
                        }
                    }
                    if serviceAvailable {
                    ForEach(ChallengeV1Section.allCases, id: \.self) { section in
                        Section(section.title) {
                            if let state = store.sections[section] {
                                if let message = state.error { Text(message).font(.caption) }
                                ForEach(state.rows) { row in
                                    NavigationLink { ChallengeV1Detail(store: store, id: row.id) } label: {
                                        SignalChallengeSummary(row: row, actor: store.actor)
                                    }.accessibilityIdentifier("beta.row.\(row.status).\(row.policy).\(row.id.uuidString)")
                                }
                                if state.cursor != nil { Button("Show more") { Task { await store.loadMore(section) } }.accessibilityIdentifier("beta.more.\(section.rawValue)") }
                            }
                        }
                    }
                    }
                }.listStyle(.plain).scrollContentBackground(.hidden).background(SignalTheme.canvas).navigationTitle("Challenges").refreshable { await store.refresh(); await health?.refresh() }
            }.tabItem { Label("Challenges", systemImage: "flag").accessibilityIdentifier("beta.tab.challenges") }.tag(1)
            Group {
                if let accountContent { accountContent }
                else {
                    #if DEBUG
                    NavigationStack {
                        ChallengeForm {
                            ChallengeFormSection("Activity") {
                                Text("Fictional activity only").font(.headline)
                                Text("All four Apple Health sources still need physical testing. Real activity cannot score these challenges.")
                            }
                            ChallengeFormSection("Account") {
                                Text("Switching accounts clears shared content. Saved actions belong only to the account that made them.")
                                if store.access?.suspended == true {
                                    Text("New challenges are paused for your account.")
                                    if store.access?.appealFiled == true { Text("Your account review request is saved.") }
                                    else {
                                        Button("Ask us to review your account") { Task { await store.submit(op: "appeal") } }
                                            .disabled(!store.entryFresh || store.busy || store.pending != nil)
                                    }
                                }

                                Button("Sign out") { Task { await logout() } }.accessibilityIdentifier("beta.signout")
                            }
                            ChallengeFormSection("Help and safety") {
                                NavigationLink("Privacy and terms") { ChallengeLocalDisclosures() }
                                Text("You can leave any unfinished challenge from its details. No real money moves.")
                                Text("Report or block someone from a shared challenge. External beta access is closed.")
                            }
                        }.navigationTitle("You")
                    }
                    #else
                    NavigationStack { Button("Sign out") { Task { await logout() } }.navigationTitle("You") }
                    #endif
                }
            }.tabItem { Label("You", systemImage: "person").accessibilityIdentifier("beta.tab.you") }.tag(2)
        }
        .signalTabChrome()
        }
        .background(SignalTheme.canvas.ignoresSafeArea())
        .sheet(isPresented: $create) {
            if serviceAvailable { ChallengeV1Create(store: store, personalStepsOnly: personalStepsOnly) }
            else { SignalChallengeUnavailableView() }
        }
        .onChange(of: store.actor) { create = false }
        .onChange(of: store.access?.suspended) { health?.restrict(store.access?.suspended == true) }
        .onChange(of: scenePhase) { _, value in
            if value != .active { store.hide(); health?.cancelAll() }
            else { Task { await store.show(); await health?.refresh() } }
        }
        .task(id: store.actor) { await store.watchVisibility() }
        .environment(\.challengeInvitationLinks, invitation.links)
    }
    private var featuredID: UUID? {
        store.sections[.active]?.rows.first {
            $0.format.mode == .friend && $0.status == "active" && !$0.socialHidden && $0.own(store.actor)?.exited == false
        }?.id
    }
    private func homeRows(_ rows: [ChallengeV1], section: ChallengeV1Section) -> [ChallengeV1] {
        guard section == .active else { return rows }
        let featured = rows.filter { $0.id == featuredID }
        let others = rows.filter { $0.id != featuredID }
        return featured + others.filter { $0.format.mode == .personal } + others.filter { $0.format.mode != .personal }
    }
    @ViewBuilder var recovery: some View {
        if let error = store.error { Text(error).foregroundStyle(SignalTheme.textSecondary).accessibilityIdentifier("beta.error") }
        if store.pending != nil {
            SignalNotice {
                Text("Your action is saved on this phone.").font(.headline)
                Text("Retry checks the same action. Stop waiting checks whether it completed and prevents a late request from changing anything.")
                Button("Retry saved action") { Task { await store.retry() } }.accessibilityIdentifier("beta.retry")
                Button("Stop waiting for this action") { Task { await store.abandon() } }.accessibilityIdentifier("beta.abandon")
            }.buttonStyle(ChallengeActionStyle()).disabled(store.busy)
        }
        if !store.fresh && !store.challenges.isEmpty { Text("Last saved view · refresh before making a choice.").font(.caption) }
    }
}

struct ChallengeScrollLegibility: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) { content.scrollEdgeEffectHidden(true, for: .all).clipped() }
        else { content.clipped() }
    }
}
struct ChallengeActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SignalSecondaryButtonStyle().makeBody(configuration: configuration)
    }
}

struct SignalChallengeHeader: View {
    let row: ChallengeV1
    let actor: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(row.title).modifier(SignalDisplay(size: 32))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
            SignalStatusTag(text: row.own(actor)?.exited == true ? "You left this challenge" : row.statusText, kind: .neutral)
            if row.format.hasTarget, let own = row.own(actor), !own.exited, !row.isClosed {
                VStack(alignment: .leading, spacing: 12) {
                    if ["lobby_open", "consent_pending", "scheduled", "published_open"].contains(row.status) {
                        Text("Your goal").font(.subheadline)
                        if let target = own.target {
                            SignalMetricValue(value: target, metric: row.format.metric)
                        } else { Text("Goal not chosen").font(.title2) }
                        if row.format.metric == .timed, let distance = row.config.distanceMm {
                            Text("Whole run: \(ChallengeV1Policy.Metric.distance.display(distance))").font(.subheadline)
                        }
                    } else {
                        Text("Your activity").font(.subheadline)
                        SignalGoalProgress(onAccent: true, row: row, member: own, actor: actor)
                    }
                }
                .padding(SignalTheme.contentInset).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(SignalTheme.onAccent).background(SignalTheme.accent)
                .padding(.horizontal, -SignalTheme.contentInset)
            } else if row.format.metric == .timed, let distance = row.config.distanceMm {
                Text("Whole run: \(ChallengeV1Policy.Metric.distance.display(distance))").font(.subheadline)
            }
            SignalDateSpan(window: row.config)
            SignalFactRow(label: "Simulated entry", value: "\(challengeMoney(row.config.amountCents)) simulated each")
        }.foregroundStyle(SignalTheme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
    }
}

func challengeMoney(_ cents: Int) -> String { (Double(cents)/100).formatted(.currency(code:"USD")) }


struct ChallengeV1Detail: View {
    @Bindable var store: ChallengeV1Store
    @Environment(\.challengeHealthFlow) private var health
    let id: UUID
    @State private var target = ""
    @State private var username = ""
    @State private var consent = false
    @State private var exitAction: String?
    @State private var reviewReason = "wrong_total"
    @State private var communityReportSaved = false
    private var row: ChallengeV1? { store.challenges.first { $0.id == id } }
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:20) {
                if let row {
                    SignalChallengeHeader(row:row,actor:store.actor)
                    if let error = store.error { Text(error).foregroundStyle(SignalTheme.textSecondary) }
                    if store.pending != nil {
                        Button("Retry saved action") { Task { await store.retry() } }
                        Button("Stop waiting for this action") { Task { await store.abandon() } }
                    }
                    if row.socialHidden { Text("Shared details are hidden. Your own records and safe actions remain available.") }
                    if row.format.mode == .community {
                        Text((row.counts ?? .init(joined: nil)).text(at: row.serverTime)).font(.subheadline)
                        Text("Reports about this community go to its assigned moderator.").font(.caption)
                        Button("Report unsafe behavior in this community") { Task {
                            let actor = store.actor
                            guard !store.busy, store.pending == nil else { return }
                            await store.submit(op: "report_scoped", fields: ["id": .string(row.id.uuidString.lowercased()), "subject": .null, "reason": .string("unsafe_behavior")])
                            if store.actor == actor, store.pending == nil, store.error == nil, store.lastReceipt?.saved == true { communityReportSaved = true }
                        }}.disabled(store.busy || store.pending != nil)
                        if communityReportSaved { Text("Your community report is saved.") }

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
                    if row.format.mode == .personal {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Just for you", systemImage: "lock").font(.title2.weight(.semibold))
                            Text("Other participants cannot see your activity or results.").font(.subheadline)
                        }.padding(.vertical, 12)
                    }
                    if row.sourcePolicyVersion != nil, !row.format.hasTarget {
                        Text("Leaderboard — Not available yet").font(.headline)
                        Text("We can’t confirm a complete activity history for a fair ranking. You can still review your records or leave this challenge safely.")
                    }
                    if let health, let actor = store.actor, let binding = try? ChallengeHealthBindingMapper.agreement(row, actor: actor), !row.isClosed, row.own(actor)?.exited == false {
                        ChallengeHealthStatusView(flow: health, binding: binding, readiness: row.status == "consent_pending")
                    }
                    people(row)
                    rules(row)
                    if row.status == "lobby_open" { lobby(row) }
                    if row.status == "consent_pending", let own = row.own(store.actor),own.selected && !own.exited && !own.consented {
                        Toggle("I have read the complete rules and agree",isOn:$consent).accessibilityIdentifier("beta.consent.toggle")
                        Button("Agree to this challenge") { Task {
                            await store.submit(op:"consent",challenge:row,fields:["digest":.string(row.agreement?.digest ?? ""),"consent":.bool(true)])
                            consent=false
                        }}.disabled(!consent || !canAct || !healthReady).accessibilityIdentifier("beta.consent")
                    }
                    if row.format.mode == .friend && row.creatorId == store.actor && ["consent_pending","scheduled"].contains(row.status) {
                        Button("Reopen lobby and ask everyone again") { Task { await store.submit(op:"reopen",challenge:row) } }.disabled(!canAct)
                    }
                    if !row.isClosed && row.own(store.actor)?.exited == false {
                        Button("Leave challenge",role:.destructive) { exitAction="leave" }.disabled(!canAct).accessibilityIdentifier("beta.leave")
                        if row.creatorId==store.actor && row.serverTime < row.config.startsAt {
                            Button("Cancel challenge",role:.destructive) { exitAction="cancel" }.disabled(!canAct)
                        }
                    }
                } else { ContentUnavailableView("Refresh this challenge",systemImage:"arrow.clockwise",description:Text("Sign in to the same account and refresh to see its latest details.")) }
            }.padding(SignalTheme.contentInset).modifier(SignalGlassGroup())
        }.background(SignalTheme.canvas).navigationTitle("Challenge").navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .task(id: id) { await refreshActivity() }
            .onDisappear { health?.cancel(id) }
            .modifier(ChallengeScrollLegibility())
            .buttonStyle(ChallengeActionStyle())
            .refreshable { await refreshActivity() }
            .toolbar { Button("Refresh",systemImage:"arrow.clockwise") { Task { await refreshActivity() } } }
            .onChange(of:row?.revision) { consent=false }
            .onChange(of:store.actor) { communityReportSaved=false }
            .onChange(of:store.actor) { consent=false;target="";username="";exitAction=nil }
            .confirmationDialog("Leave safely?",isPresented:Binding(get:{exitAction != nil},set:{if !$0 {exitAction=nil}}),titleVisibility:.visible) {
                Button(exitAction=="cancel" ? "Cancel challenge" : "Leave challenge",role:.destructive) {
                    if let row,let action=exitAction { Task { await store.submit(op:action,challenge:row) } };exitAction=nil
                }
            } message: { Text("Your simulated entry is returned. A shared challenge continues only if its agreed minimum remains. No real money moves.") }
    }
    private func refreshActivity() async { await store.loadDetail(id); if row?.sourcePolicyVersion != nil { await health?.refresh(id) } }
    private var healthReady: Bool {
        guard let row, row.sourcePolicyVersion != nil else { return true }
        guard let actor = store.actor, let binding = try? ChallengeHealthBindingMapper.agreement(row, actor: actor) else { return false }
        return health?.canConsent(binding) == true
    }
    private var canAct: Bool { row.map { store.isFresh($0) } == true && !store.busy && store.pending == nil }
    @ViewBuilder private func people(_ row:ChallengeV1)->some View {
        Text(row.format.mode == .friend ? "People and activity" : "Your activity").font(.title2.bold())
        ForEach(row.rankedMembers) { person in
            let departedCounterpart = person.exited && person.actorId != store.actor
            VStack(alignment:.leading,spacing:6) {
                SignalParticipantRow(row: row, person: person, actor: store.actor, showsState: ["lobby_open", "consent_pending", "scheduled"].contains(row.status),
                                     showsMetric: !row.format.hasTarget || departedCounterpart)
                if row.format.hasTarget && !departedCounterpart {
                    SignalGoalProgress(row: row, member: person, actor: store.actor)
                }
                if let finalStatus = row.final?.result.participants?[person.actorId.uuidString.lowercased()]?.status {
                    Text(resultText(finalStatus)).font(.subheadline.bold())
                }
                if let fact=person.fact, !departedCounterpart {
                    Text("\(row.sourcePolicyVersion == nil ? "Fictional activity" : fact.state == "value" ? "Observed activity" : "Activity not confirmed") · Updated \(fact.recordedAt.text(zone:row.config.timezone))").font(.caption)
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
            ChallengeAgreementText(policy:row.format,window:row.config,minimum:row.agreement?.terms?["minimum"]?.integer ?? (row.format.mode == .personal ? 1 : 2), sourcePolicy: row.sourcePolicyVersion)
        }
    }
    @ViewBuilder private func lobby(_ row:ChallengeV1)->some View {
        if row.format.hasTarget && row.own(store.actor)?.exited == false {
            TextField(row.format.metric.targetPrompt,text:$target).keyboardType(.numbersAndPunctuation).textFieldStyle(.roundedBorder).accessibilityLabel(row.format.metric.targetPrompt).accessibilityIdentifier("beta.target.input")
            if !target.isEmpty && row.format.metric.parse(target) == nil { Text(row.format.metric.inputHelp).font(.subheadline) }
            if let health, let actor = store.actor, let source = row.sourcePolicyVersion,
               let planning = try? ChallengeHealthBindingMapper.planning(actor: actor, id: row.id, policy: row.format,
                    window: row.config, source: source, draft: target + "|" + String(row.revision)) {
                ChallengeHealthSuggestionView(flow: health, binding: planning, policy: row.format, days: row.config.days) {
                    target = row.format.metric.inputValue($0)
                }
            }
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
