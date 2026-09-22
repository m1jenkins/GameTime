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
    private let configurationFailure: String?
    private let isFixtureTestLaunch: Bool

    init() {
        SignalAppearance.install()

        let notificationCoordinator = PushNotificationCoordinator()
        _pushCoordinator = State(initialValue: notificationCoordinator)

        #if DEBUG || STAGING
        let arguments = ProcessInfo.processInfo.arguments
        #endif
        #if DEBUG
        if SourceInvestigationLaunch.enabled || ChallengeLocalLaunch.enabled {
            _liveModel = State(initialValue: nil)
            _demoModel = State(initialValue: nil)
            _livePersonalStore = State(initialValue: nil)
            _demoPersonalStore = State(initialValue: nil)
            _isUsingDemoModel = State(initialValue: false)
            configurationFailure = nil
            isFixtureTestLaunch = true
            return
        }
        #endif
        #if DEBUG || STAGING
        #if DEBUG
        let fixtureLaunch = arguments.contains("--fixture-mode") || LiveDesignFixtures.enabled
        #else
        let fixtureLaunch = arguments.contains("--fixture-mode")
        #endif
        let interactiveDemoLaunch = arguments.contains("--demo-interactive")
            || arguments.contains("--fixture-demo-interactive")
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
        isFixtureTestLaunch = usesFixtureModel && !interactiveDemoLaunch
        #else
        isFixtureTestLaunch = false
        #endif

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
                if arguments.contains("--commitments") {
                    configuration = .performanceCommitmentFixture
                } else if arguments.contains("--duels") {
                    configuration = .duelFixture
                } else if usesStripeSandboxFixture {
                    configuration = .stripeSandboxFixture
                } else {
                    configuration = arguments.contains("--fixture-activity")
                        ? .activityFixture
                        : .personalFixture
                }
                #if DEBUG
                if LiveDesignFixtures.enabled {
                    services = FixtureServicesFactory.make(
                        arguments: ["--fixture-mode"],
                        profileClient: LiveDesignFixtures.makeProfileClient(),
                        challengesV1: LiveDesignFixtures.makeClient())
                } else { services = FixtureServicesFactory.make() }
                #else
                services = FixtureServicesFactory.make()
                #endif
            } else {
                #if DEBUG
                if ChallengeAuthenticatedAppLaunch.enabled {
                    configuration = try ChallengeAuthenticatedAppLaunch.configuration()
                    services = ChallengeAuthenticatedAppLaunch.services(configuration: configuration)
                } else {
                    configuration = try .load()
                    services = try LiveServicesFactory.make(configuration: configuration)
                }
                #else
                configuration = try .load()
                services = try LiveServicesFactory.make(
                    configuration: configuration
                )
                #endif
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
                #if DEBUG
                if SourceInvestigationLaunch.enabled {
                    SourceInvestigationView()
                } else if ChallengeLocalLaunch.enabled {
                    ChallengeLocalLaunchView()
                } else {
                    productRoot
                }
                #else
                productRoot
                #endif
            }
            .task(id: isUsingDemoModel) {
                #if DEBUG
                guard !SourceInvestigationLaunch.enabled, !ChallengeLocalLaunch.enabled else { return }
                #endif
                await configureProductServices()
            }
            .onOpenURL { url in
                #if DEBUG
                guard !SourceInvestigationLaunch.enabled, !ChallengeLocalLaunch.enabled else { return }
                #endif
                _ = StripeAPI.handleURLCallback(with: url)
            }
            .tint(SignalTheme.accent)
            .foregroundStyle(SignalTheme.textPrimary)
            .preferredColorScheme(.light)
        }
    }

    @ViewBuilder private var productRoot: some View {
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
                    .tint(SignalTheme.accent)
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
                    .tint(SignalTheme.accent)
                } else {
                    LiveConfigurationFailureView(
                        message: configurationFailure
                            ?? "GameTime isn’t set up correctly on this device."
                    )
                }
    }

    private func configureProductServices() async {
                #if DEBUG
                guard !ChallengeAuthenticatedAppLaunch.enabled else { return }
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
        @Bindable var router = router

        VStack(spacing: 0) {
            Group {
                switch model.phase {
                case .launching:
                    LiveLaunchingView(
                        errorMessage: model.presentedError,
                        retry: {
                            Task { await model.retryLaunch() }
                        }
                    )
                case .signedOut:
                    LiveSignInView()
                case .onboarding:
                    LiveOnboardingView(
                        namePrefill: model.onboardingNamePrefill
                    )
                case .signedIn:
                    SignalProductShell()
                }
            }
            // SwiftUI can coalesce a fast account switch into signedIn ->
            // signedIn. View-local drafts and presentations still belong to
            // the previous actor and must get a new identity.
            .id(model.userID)
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
            receiveURL(url)
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
        .onChange(of: model.userID) { previousUserID, userID in
            // The first fixture sign-in may have an explicit test route already
            // selected. Later actor changes must discard the previous route.
            if previousUserID != nil && previousUserID != userID {
                router.reset()
            }
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

    /// SwiftUI delivers custom URLs and universal links here, including when
    /// launch/sign-in is unfinished. Save the opaque intent; never redeem it.
    func receiveURL(_ url: URL) {
        model.challengeInvitation.receive(url)
        #if DEBUG || STAGING
        model.duels.receiveInvitation(url)
        openDuelInvitation()
        #endif
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
