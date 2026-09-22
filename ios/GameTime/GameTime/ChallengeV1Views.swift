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
    var body: some View {
        LiveChallengeShell(store: store, invitation: invitation, logout: logout,
                           accountContent: accountContent, serviceAvailable: serviceAvailable,
                           personalStepsOnly: personalStepsOnly)
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
            if row.format.hasTarget, let own = row.own(actor) {
                VStack(alignment: .leading, spacing: 12) {
                    if ["lobby_open", "consent_pending", "scheduled", "published_open"].contains(row.status) {
                        Text("Your goal").font(.subheadline)
                        if let target = own.target {
                            SignalMetricValue(value: target, metric: row.format.metric)
                        } else { Text("Choose your own goal").font(.title.weight(.semibold)) }
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


/// Retained source-level entry point for saved links and creation receipts.
/// All destinations now render the approved agreement UI.
struct ChallengeV1Detail: View {
    @Bindable var store: ChallengeV1Store
    let id: UUID
    var body: some View { LiveGoalDetail(store: store, id: id) }
}
