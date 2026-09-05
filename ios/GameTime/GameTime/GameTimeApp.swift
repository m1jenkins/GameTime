import GameTimeCore
import StripePaymentSheet
import SwiftUI
import UserNotifications

enum GameTimePublicIdentity {
    static let name = "GameTime"
}

@main
@MainActor
struct GameTimeApp: App {
    @UIApplicationDelegateAdaptor(GameTimeAppDelegate.self)
    private var appDelegate
    @State private var liveModel: AppModel?
    @State private var demoModel: AppModel?
    @State private var livePersonalStore: PersonalAccountabilityStore?
    @State private var demoPersonalStore: PersonalAccountabilityStore?
    @State private var router = AppRouter()
    @State private var pushCoordinator: PushNotificationCoordinator
    @State private var isUsingDemoModel: Bool
    #if DEBUG || STAGING
    private let watchConnectivity = PhoneWatchConnectivityCoordinator()
    #endif
    private let configurationFailure: String?
    private let isFixtureTestLaunch: Bool

    init() {
        DaybreakAppearance.install()

        let notificationCoordinator = PushNotificationCoordinator()
        _pushCoordinator = State(initialValue: notificationCoordinator)

        let arguments = ProcessInfo.processInfo.arguments
        let fixtureLaunch = arguments.contains("--fixture-mode")
        let interactiveDemoLaunch = arguments.contains("--demo-interactive")
            || arguments.contains("--fixture-demo-interactive")
        #if DEBUG || STAGING
        let usesFixtureModel = fixtureLaunch
        let usesPaymentStatusFixture = arguments.contains(where: {
            $0.hasPrefix("--fixture-payment-status=")
                || $0.hasPrefix("--fixture-payment-status-sequence=")
        }) || arguments.contains("--fixture-payment-unavailable")
            || arguments.contains(
                "--fixture-payment-refresh-fails-after-first"
            )
            || arguments.contains("--fixture-payment-review-expired")
        let usesStripeSandboxFixture = arguments.contains(
            "--fixture-stripe-sandbox"
        ) || arguments.contains("--fixture-sandbox-met")
            || arguments.contains("--fixture-sandbox-missing-result")
            || arguments.contains("--fixture-stripe-review")
            || arguments.contains("--fixture-open-review-challenge")
            || arguments.contains("--fixture-expired-review")
            || usesPaymentStatusFixture
        #else
        let usesFixtureModel = false
        #endif
        isFixtureTestLaunch = usesFixtureModel && !interactiveDemoLaunch

        let initialRouter = AppRouter()
        #if DEBUG || STAGING
        let opensCompletedPersonalResult = arguments.contains(
            "--fixture-open-review-challenge"
        ) || arguments.contains("--fixture-open-result-challenge")
        if usesFixtureModel,
            arguments.contains("--fixture-challenges")
                || arguments.contains("--fixture-open-active-challenge")
                || opensCompletedPersonalResult
        {
            initialRouter.selectedTab = .challenges
        }
        if usesFixtureModel,
            arguments.contains("--fixture-open-active-challenge"),
            let activePersonalID = UUID(
                uuidString: "18181818-1818-1818-1818-181818181818"
            )
        {
            initialRouter.challengesPath = [
                .personalChallenge(activePersonalID)
            ]
        }
        if usesFixtureModel,
            opensCompletedPersonalResult,
            let reviewChallengeID = UUID(
                uuidString: "19191919-1919-1919-1919-191919191919"
            )
        {
            initialRouter.challengesPath = [
                .personalChallenge(reviewChallengeID)
            ]
        }
        #endif
        _router = State(initialValue: initialRouter)

        do {
            let configuration: AppConfiguration
            let services: AppServices

            #if DEBUG || STAGING
            if usesFixtureModel {
                if arguments.contains("--duels") {
                    configuration = .duelFixture
                } else if usesStripeSandboxFixture {
                    configuration = .stripeSandboxFixture
                } else {
                    configuration = arguments.contains("--fixture-activity")
                        ? .activityFixture
                        : .personalFixture
                }
                services = FixtureServicesFactory.make()
            } else {
                configuration = try .load()
                services = try LiveServicesFactory.make(
                    configuration: configuration
                )
            }
            #else
            configuration = try .load()
            services = try LiveServicesFactory.make(
                configuration: configuration
            )
            #endif

            let initialModel = AppModel(
                configuration: configuration,
                services: services
            )
            let initialPersonalStore = PersonalAccountabilityStore(
                configuration: configuration,
                auth: services.auth,
                client: services.personalAccountability,
                paymentClient: services.personalPayments,
                pendingStore: services.pendingPersonalChallenges,
                pendingCancellationStore:
                    services.pendingPersonalCancellations,
                diagnosticClient: services.trustedActivityDiagnostic,
                activitySync: services.personalActivitySync,
                stepProgressStore: PersonalStepProgressStore(
                    reader: services.personalHealthSteps,
                    cache: services.personalStepSnapshotCache,
                    uploader: services.personalHealthSnapshotUploader
                )
            )
            #if DEBUG || STAGING
            if usesFixtureModel {
                _liveModel = State(initialValue: nil)
                _demoModel = State(initialValue: initialModel)
                _livePersonalStore = State(initialValue: nil)
                _demoPersonalStore = State(
                    initialValue: initialPersonalStore
                )
                _isUsingDemoModel = State(initialValue: true)
            } else {
                _liveModel = State(initialValue: initialModel)
                _demoModel = State(initialValue: nil)
                _livePersonalStore = State(
                    initialValue: initialPersonalStore
                )
                _demoPersonalStore = State(initialValue: nil)
                _isUsingDemoModel = State(initialValue: false)
            }
            #else
            _liveModel = State(initialValue: initialModel)
            _demoModel = State(initialValue: nil)
            _livePersonalStore = State(initialValue: initialPersonalStore)
            _demoPersonalStore = State(initialValue: nil)
            _isUsingDemoModel = State(initialValue: false)
            #endif
            configurationFailure = nil
        } catch {
            _liveModel = State(initialValue: nil)
            _demoModel = State(initialValue: nil)
            _livePersonalStore = State(initialValue: nil)
            _demoPersonalStore = State(initialValue: nil)
            _isUsingDemoModel = State(initialValue: false)
            configurationFailure = error.localizedDescription
        }

        // Notification responses can arrive before SwiftUI view tasks run when
        // a terminated app is launched from a push tap.
        UNUserNotificationCenter.current().delegate = notificationCoordinator
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isUsingDemoModel,
                    let demoModel,
                    let demoPersonalStore
                {
                    RootView(
                        model: demoModel,
                        personalStore: demoPersonalStore,
                        router: router,
                        demoMode: demoModeAccess,
                        pushCoordinator: pushCoordinator
                    )
                    .environment(demoModel)
                    .environment(demoPersonalStore)
                    .environment(demoPersonalStore.stepProgress)
                    .environment(router)
                    .tint(CompetitiveTrustTheme.actionCoral)
                } else if let liveModel, let livePersonalStore {
                    RootView(
                        model: liveModel,
                        personalStore: livePersonalStore,
                        router: router,
                        demoMode: demoModeAccess,
                        pushCoordinator: pushCoordinator
                    )
                    .environment(liveModel)
                    .environment(livePersonalStore)
                    .environment(livePersonalStore.stepProgress)
                    .environment(router)
                    .tint(CompetitiveTrustTheme.actionCoral)
                } else {
                    ConfigurationFailureView(
                        message: configurationFailure
                            ?? "GameTime isn’t set up correctly on this device."
                    )
                }
            }
            .task(id: isUsingDemoModel) {
                #if DEBUG || STAGING
                watchConnectivity.activate()
                #endif
                appDelegate.pushCoordinator = pushCoordinator
                if let livePersonalStore {
                    livePersonalStore.setBackgroundDeliveryRegistration(
                        appDelegate.personalHealthBackgroundDelivery
                    )
                    await appDelegate.personalHealthBackgroundDelivery
                        .setUpdateHandler { [weak livePersonalStore] in
                            await livePersonalStore?
                                .handleBackgroundActivityUpdate()
                        }
                } else {
                    await appDelegate.personalHealthBackgroundDelivery
                        .setUpdateHandler({})
                }
                guard !isUsingDemoModel, let liveModel else { return }
                await pushCoordinator.configure(
                    environment: liveModel.configuration.environment,
                    bundleID: Bundle.main.bundleIdentifier
                )
            }
            .onOpenURL { url in
                _ = StripeAPI.handleURLCallback(with: url)
            }
            .preferredColorScheme(.light)
        }
    }

    private var demoModeAccess: DemoModeAccess {
        #if DEBUG || STAGING
        DemoModeAccess(
            isAvailable: !isFixtureTestLaunch,
            isActive: isUsingDemoModel && !isFixtureTestLaunch,
            enter: enterDemoMode,
            exit: exitDemoMode
        )
        #else
        .unavailable
        #endif
    }

    #if DEBUG || STAGING
    private func enterDemoMode() {
        router.reset()
        let services = FixtureServicesFactory.make(
            arguments: ["GameTime", "--demo-interactive"],
            // Interactive demo challenges stay isolated from the live account
            // and network, but their step progress should still reflect the
            // person holding this phone. Deterministic `--fixture-mode`
            // launches keep the fixture reader used by UI tests.
            personalHealthSteps: HealthKitPersonalHealthStepReader()
        )
        demoModel = AppModel(
            configuration: .personalFixture,
            services: services
        )
        demoPersonalStore = PersonalAccountabilityStore(
            configuration: .personalFixture,
            auth: services.auth,
            client: services.personalAccountability,
            paymentClient: services.personalPayments,
            pendingStore: services.pendingPersonalChallenges,
            pendingCancellationStore:
                services.pendingPersonalCancellations,
            diagnosticClient: services.trustedActivityDiagnostic,
            activitySync: services.personalActivitySync,
            stepProgressStore: PersonalStepProgressStore(
                reader: services.personalHealthSteps,
                cache: services.personalStepSnapshotCache,
                uploader: services.personalHealthSnapshotUploader
            )
        )
        isUsingDemoModel = true
    }

    private func exitDemoMode() {
        router.reset()
        demoModel = nil
        demoPersonalStore = nil
        isUsingDemoModel = false
    }
    #endif
}

@MainActor
struct RootView: View {
    @Bindable var model: AppModel
    @Bindable var personalStore: PersonalAccountabilityStore
    @Bindable var router: AppRouter
    let demoMode: DemoModeAccess
    let pushCoordinator: PushNotificationCoordinator

    private var isShowingDuel: Bool {
        #if DEBUG || STAGING
        return model.configuration.duelRuntimeEnabled && router.selectedTab == .you
            && router.youPath.contains(.duels)
        #else
        return false
        #endif
    }

    var body: some View {
        @Bindable var router = router

        VStack(spacing: 0) {
            if router.presentedSheet == nil && !isShowingDuel {
                EnvironmentDisclosureBanner(
                    settlementMode:
                        model.configuration.personalSettlementMode,
                    isDemo: demoMode.isActive
                )
                .background(
                    (demoMode.isActive
                        ? CompetitiveTrustTheme.actionCoral
                        : CompetitiveTrustTheme.sun)
                        .ignoresSafeArea(edges: .top)
                )
            }

            Group {
                switch model.phase {
                case .launching:
                    LaunchingView(
                        errorMessage: model.presentedError,
                        retry: {
                            Task { await model.retryLaunch() }
                        }
                    )
                case .signedOut:
                    SignedOutView()
                case .onboarding:
                    OnboardingView(
                        namePrefill: model.onboardingNamePrefill
                    )
                case .signedIn:
                    AppShellView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .environment(\.demoMode, demoMode)
        .task {
            #if DEBUG
            // Keep the loading UI fixture stable and idle so UI automation can
            // observe it without racing the normal launch refresh.
            if ProcessInfo.processInfo.arguments.contains("--fixture-loading") {
                return
            }
            #endif
            await model.start()
            await personalStore.activate(
                ownerID: model.phase == .signedIn ? model.userID : nil
            )
            if let registration = pushCoordinator.deviceRegistration {
                await model.receivePushRegistration(registration)
            }
            await handlePushDestination()
            openDuelInvitation()
        }
        .onOpenURL { url in
            #if DEBUG || STAGING
            model.duels.receiveInvitation(url)
            openDuelInvitation()
            #endif
        }
        .onChange(of: model.phase) { _, phase in
            if phase != .signedIn {
                router.reset()
                Task { await personalStore.activate(ownerID: nil) }
            } else {
                Task {
                    await personalStore.activate(ownerID: model.userID)
                    await handlePushDestination()
                    openDuelInvitation()
                }
            }
        }
        .onChange(of: model.userID) { _, userID in
            Task {
                await personalStore.activate(
                    ownerID: model.phase == .signedIn ? userID : nil
                )
            }
        }
        .onChange(of: pushCoordinator.deviceRegistration) {
            _, registration in
            guard let registration else { return }
            Task {
                await model.receivePushRegistration(registration)
            }
        }
        .onChange(of: pushCoordinator.pendingDestination) {
            _, destination in
            guard destination != nil else { return }
            Task { await handlePushDestination() }
        }
        .alert(
            "GameTime",
            isPresented: Binding(
                get: {
                    model.phase != .launching
                        && model.phase != .onboarding
                        && (
                            personalStore.presentedError != nil
                                || model.presentedError != nil
                        )
                },
                set: { isPresented in
                    if !isPresented {
                        model.presentedError = nil
                        personalStore.presentedError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.presentedError = nil
                personalStore.presentedError = nil
            }
        } message: {
            Text(
                personalStore.presentedError
                    ?? model.presentedError
                    ?? ""
            )
        }
    }

    private func openDuelInvitation() {
        #if DEBUG || STAGING
        guard model.configuration.duelRuntimeEnabled, model.phase == .signedIn,
              model.duels.pendingInvitationToken != nil else { return }
        router.presentedSheet = nil
        router.selectedTab = .you
        router.youPath = [.duels, .duelInvitation]
        #endif
    }

    private func handlePushDestination() async {
        guard
            model.phase == .signedIn,
            let destination = pushCoordinator.pendingDestination
        else {
            return
        }
        // Social standings and reaction destinations are dormant in personal
        // V1. Consume old payloads without surfacing a hidden route or action.
        _ = destination
        pushCoordinator.consumeDestination()
    }
}

private struct ConfigurationFailureView: View {
    let message: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(CompetitiveTrustTheme.amber)
                .accessibilityHidden(true)
            Text("GameTime can’t start")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            PublicSupportLinksView(
                privacyURL: AppConfiguration.publishedPolicyURL(
                    Bundle.main.object(
                        forInfoDictionaryKey: "GAMETIME_PRIVACY_POLICY_URL"
                    ) as? String
                ),
                betaTermsURL: AppConfiguration.publishedPolicyURL(
                    Bundle.main.object(
                        forInfoDictionaryKey: "GAMETIME_BETA_TERMS_URL"
                    ) as? String
                ),
                supportMailtoURL: AppConfiguration.supportInbox(
                    Bundle.main.object(
                        forInfoDictionaryKey: "GAMETIME_SUPPORT_EMAIL"
                    ) as? String
                ).flatMap { URL(string: "mailto:\($0)") }
            )
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CompetitiveTrustTheme.ink)
        .preferredColorScheme(.light)
    }
}

private struct SignedOutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.demoMode) private var demoMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 56)

                Text(GameTimePublicIdentity.name)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(CompetitiveTrustTheme.actionCoral)
                    .accessibilityLabel(Text(GameTimePublicIdentity.name))

                VStack(alignment: .leading, spacing: 12) {
                    Text("Commit clearly.\nShow up daily.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(
                        "Set one step goal, put a little on the line, and see it through for seven days."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    NativeAppleSignInButton()
                        .disabled(model.isMutating)

                    if model.isMutating {
                        DaybreakAsyncStatus(message: "Signing in…")
                            .accessibilityIdentifier("auth.sign-in.status")
                    }
                }

                if let accountDeletionNotice = model.accountDeletionNotice {
                    Label(
                        accountDeletionNotice,
                        systemImage: "checkmark.circle.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CompetitiveTrustTheme.mintInk)
                    .trustCard()
                    .accessibilityIdentifier("account-deletion.success")
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        "Hit it every day, or hit a weekly total",
                        systemImage: "checkmark.shield"
                    )
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .trustCard()

                if demoMode.isAvailable, !demoMode.isActive {
                    Button("Try demo mode", action: demoMode.enter)
                        .buttonStyle(TrustSecondaryButtonStyle())
                        .accessibilityIdentifier("demo.enter")
                }

                Text(
                    "Signing in creates your private account. Apple only shares your name the first time, and you can change it on the next screen."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                PublicSupportLinksView(
                    privacyURL: model.configuration.privacyPolicyURL,
                    betaTermsURL: model.configuration.betaTermsURL,
                    supportMailtoURL: model.configuration.supportMailtoURL
                )
            }
            .padding(24)
        }
        .background(CompetitiveTrustTheme.ink)
        .preferredColorScheme(.light)
        .onChange(of: model.isMutating) { _, isSigningIn in
            guard isSigningIn else { return }
            DaybreakAccessibility.announce("Signing in…")
        }
        .onChange(of: model.presentedError) { _, message in
            guard let message else { return }
            DaybreakAccessibility.announce(message)
        }
    }
}

private struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var handle = ""
    @State private var displayName: String
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case handle
    }

    init(namePrefill: String) {
        _displayName = State(initialValue: namePrefill)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Make GameTime yours")
                                .font(
                                    CompetitiveTrustTheme.displayFont(
                                        size: 32,
                                        relativeTo: .largeTitle
                                    )
                                )
                            Text(
                                "Add your name and choose the username you’ll use in GameTime."
                            )
                            .font(.subheadline)
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                        }

                        DaybreakSectionLabel(text: "Your profile")

                        DaybreakCard {
                            VStack(alignment: .leading, spacing: 18) {
                                onboardingField(
                                    title: "Your name",
                                    text: $displayName,
                                    field: .name,
                                    textContentType: .name,
                                    submitLabel: .next
                                )

                                Divider().overlay(CompetitiveTrustTheme.border)

                                onboardingField(
                                    title: "Username",
                                    text: $handle,
                                    field: .handle,
                                    textContentType: .username,
                                    submitLabel: .done
                                )

                                Text(
                                    "Pick carefully — you can’t change your username yet."
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    CompetitiveTrustTheme.secondaryText
                                )
                            }
                        }

                        if let message = error(for: .general) {
                            Text(message)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(
                                    CompetitiveTrustTheme.actionCoral
                                )
                                .accessibilityIdentifier(
                                    "onboarding.general.error"
                                )
                        }

                        Button {
                            submitOnboarding()
                        } label: {
                            Text(
                                model.isMutating
                                    ? "Saving profile…"
                                    : "Enter GameTime"
                            )
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TrustPrimaryButtonStyle())
                        .disabled(
                            model.isMutating
                                || handle.isEmpty
                                || displayName.trimmingCharacters(
                                    in: .whitespacesAndNewlines
                                ).isEmpty
                        )
                        .accessibilityIdentifier("onboarding.submit")

                        Button("Use a different Apple account") {
                            focusedField = nil
                            Task { await model.signOut() }
                        }
                        .buttonStyle(TrustSecondaryButtonStyle())
                        .disabled(model.isMutating)
                        .accessibilityIdentifier(
                            "onboarding.use-different-account"
                        )
                    }
                    .padding(20)
                }
                .scrollDismissesKeyboard(.interactively)
                .daybreakScreenChrome()
                .onChange(of: focusedField) { _, field in
                    guard let field else { return }
                    Task { @MainActor in
                        await Task.yield()
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(field, anchor: .center)
                        }
                    }
                }
            }
            .navigationTitle("Set your profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(focusedField == .name ? "Next" : "Done") {
                        if focusedField == .name {
                            focusedField = .handle
                        } else {
                            submitOnboarding()
                        }
                    }
                }
            }
            .onAppear {
                focusedField = displayName.isEmpty ? .name : .handle
            }
            .onChange(of: displayName) { _, _ in
                model.clearOnboardingError()
            }
            .onChange(of: handle) { _, _ in
                model.clearOnboardingError()
            }
            .onChange(of: model.onboardingError) { _, error in
                guard let error else { return }
                switch error.field {
                case .name:
                    focusedField = .name
                case .username:
                    focusedField = .handle
                case .general:
                    break
                }
            }
        }
        .preferredColorScheme(.light)
    }

    private func onboardingField(
        title: String,
        text: Binding<String>,
        field: Field,
        textContentType: UITextContentType,
        submitLabel: SubmitLabel
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title)
                .font(.subheadline.weight(.semibold))

            TextField(title, text: text)
                .textContentType(textContentType)
                .textInputAutocapitalization(field == .handle ? .never : .words)
                .autocorrectionDisabled(field == .handle)
                .submitLabel(submitLabel)
                .focused($focusedField, equals: field)
                .onSubmit {
                    if field == .name {
                        focusedField = .handle
                    } else {
                        submitOnboarding()
                    }
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 50)
                .background(
                    CompetitiveTrustTheme.paperSunk,
                    in: RoundedRectangle(cornerRadius: 14)
                )
                .disabled(model.isMutating)
                .accessibilityLabel(title)
                .id(field)

            Text(supportingText(for: field))
                .font(.caption)
                .foregroundStyle(
                    error(for: field) == nil
                        ? CompetitiveTrustTheme.secondaryText
                        : CompetitiveTrustTheme.actionCoral
                )
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(
                    field == .name
                        ? "onboarding.name.message"
                        : "onboarding.username.message"
                )
        }
    }

    private func supportingText(for field: Field) -> String {
        if let error = error(for: field) {
            return error
        }
        switch field {
        case .name:
            return "Name: 1–50 characters"
        case .handle:
            return "Username: 3–30 letters, numbers, or underscores; starts with a letter"
        }
    }

    private func error(for field: OnboardingErrorField) -> String? {
        guard model.onboardingError?.field == field else { return nil }
        return model.onboardingError?.message
    }

    private func error(for field: Field) -> String? {
        error(for: field == .name ? .name : .username)
    }

    private func submitOnboarding() {
        focusedField = nil
        Task {
            await model.completeOnboarding(
                handle: handle,
                displayName: displayName
            )
        }
    }
}
