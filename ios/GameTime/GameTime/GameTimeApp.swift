import GameTimeCore
import StripePaymentSheet
import SwiftUI
import UserNotifications

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
        #if DEBUG || STAGING
        let usesFixtureModel = fixtureLaunch
        #else
        let usesFixtureModel = false
        #endif
        isFixtureTestLaunch = usesFixtureModel && !interactiveDemoLaunch

        let initialRouter = AppRouter()
        #if DEBUG || STAGING
        if usesFixtureModel,
            arguments.contains("--fixture-challenges")
                || arguments.contains("--fixture-open-active-challenge")
                || arguments.contains("--fixture-open-review-challenge")
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
            arguments.contains("--fixture-open-review-challenge"),
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
                if arguments.contains("--fixture-stripe-sandbox") {
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
                    .tint(CompetitiveTrustTheme.coral)
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
                    .tint(CompetitiveTrustTheme.coral)
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

    var body: some View {
        VStack(spacing: 0) {
            if demoMode.isActive {
                DemoEnvironmentBanner()
            } else if model.configuration.environment
                .showsTestEnvironmentBanner
            {
                TestEnvironmentBanner(
                    settlementMode:
                        model.configuration.personalSettlementMode
                )
                    .background(
                        CompetitiveTrustTheme.sun
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
        }
        .onChange(of: model.phase) { _, phase in
            if phase != .signedIn {
                router.reset()
                Task { await personalStore.activate(ownerID: nil) }
            } else {
                Task {
                    await personalStore.activate(ownerID: model.userID)
                    await handlePushDestination()
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

private struct DemoEnvironmentBanner: View {
    var body: some View {
        Label(
            "Demo mode — nothing here leaves your phone",
            systemImage: "play.circle.fill"
        )
        .font(.caption.weight(.bold))
        .foregroundStyle(CompetitiveTrustTheme.ink)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(CompetitiveTrustTheme.teal)
        .accessibilityIdentifier("demo.banner")
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
            Text("Contact support for help.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CompetitiveTrustTheme.ink)
        .accessibilityElement(children: .combine)
    }
}

private struct SignedOutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.demoMode) private var demoMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 56)

                Text("B//B")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(CompetitiveTrustTheme.teal)
                    .accessibilityLabel("Better Bet")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Commit clearly.\nShow up daily.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(
                        "Set one step goal, put a little on the line, and see it through for seven days."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        "Hit it every day, or hit a weekly total",
                        systemImage: "checkmark.shield"
                    )
                    Label(
                        model.configuration.personalSettlementMode
                            .disclosureText,
                        systemImage: "figure.walk"
                    )
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .trustCard()

                NativeAppleSignInButton()
                    .disabled(model.isMutating)

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
            }
            .padding(24)
        }
        .background(CompetitiveTrustTheme.ink)
    }
}

private struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var handle = ""
    @State private var displayName: String
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case handle
    }

    init(namePrefill: String) {
        _displayName = State(initialValue: namePrefill)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                        .accessibilityLabel("Your name")

                    TextField("Username", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .handle)
                        .accessibilityLabel("Username")
                } header: {
                    Text("Your profile")
                } footer: {
                    Text(
                        "Pick carefully — you can’t change your username yet."
                    )
                }

                Section {
                    Button {
                        Task {
                            await model.completeOnboarding(
                                handle: handle,
                                displayName: displayName
                            )
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isMutating {
                                ProgressView()
                                    .accessibilityLabel("Saving")
                            } else {
                                Text("Enter GameTime")
                            }
                            Spacer()
                        }
                    }
                    .disabled(
                        model.isMutating
                            || handle.isEmpty
                            || displayName.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            ).isEmpty
                    )
                }
            }
            .trustScreenBackground()
            .navigationTitle("Set your profile")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                focusedField = displayName.isEmpty ? .name : .handle
            }
        }
    }
}
