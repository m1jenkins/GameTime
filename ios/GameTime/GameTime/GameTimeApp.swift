import GameTimeCore
import SwiftUI

@main
@MainActor
struct GameTimeApp: App {
    @State private var liveModel: AppModel?
    @State private var demoModel: AppModel?
    @State private var router = AppRouter()
    @State private var isUsingDemoModel: Bool
    private let configurationFailure: String?
    private let isFixtureTestLaunch: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let fixtureLaunch = arguments.contains("--fixture-mode")
        let interactiveDemoLaunch = arguments.contains("--demo-interactive")
        #if DEBUG || STAGING
        let usesFixtureModel = fixtureLaunch
        #else
        let usesFixtureModel = false
        #endif
        isFixtureTestLaunch = usesFixtureModel && !interactiveDemoLaunch

        do {
            let configuration: AppConfiguration
            let services: AppServices

            #if DEBUG || STAGING
            if usesFixtureModel {
                configuration = .fixture
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
            #if DEBUG || STAGING
            if usesFixtureModel {
                _liveModel = State(initialValue: nil)
                _demoModel = State(initialValue: initialModel)
                _isUsingDemoModel = State(initialValue: true)
            } else {
                _liveModel = State(initialValue: initialModel)
                _demoModel = State(initialValue: nil)
                _isUsingDemoModel = State(initialValue: false)
            }
            #else
            _liveModel = State(initialValue: initialModel)
            _demoModel = State(initialValue: nil)
            _isUsingDemoModel = State(initialValue: false)
            #endif
            configurationFailure = nil
        } catch {
            _liveModel = State(initialValue: nil)
            _demoModel = State(initialValue: nil)
            _isUsingDemoModel = State(initialValue: false)
            configurationFailure = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if isUsingDemoModel, let demoModel {
                RootView(
                    model: demoModel,
                    router: router,
                    demoMode: demoModeAccess
                )
                    .environment(demoModel)
                    .environment(router)
                    .tint(CompetitiveTrustTheme.teal)
            } else if let liveModel {
                RootView(
                    model: liveModel,
                    router: router,
                    demoMode: demoModeAccess
                )
                    .environment(liveModel)
                    .environment(router)
                    .tint(CompetitiveTrustTheme.teal)
            } else {
                ConfigurationFailureView(
                    message: configurationFailure
                        ?? "GameTime configuration is unavailable."
                )
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
        demoModel = AppModel(
            configuration: .fixture,
            services: FixtureServicesFactory.make(
                arguments: ["GameTime", "--demo-interactive"]
            )
        )
        isUsingDemoModel = true
    }

    private func exitDemoMode() {
        router.reset()
        demoModel = nil
        isUsingDemoModel = false
    }
    #endif
}

@MainActor
struct RootView: View {
    @Bindable var model: AppModel
    @Bindable var router: AppRouter
    let demoMode: DemoModeAccess

    var body: some View {
        Group {
            switch model.phase {
            case .launching:
                LaunchingView(
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
        .environment(\.demoMode, demoMode)
        .safeAreaInset(edge: .top, spacing: 0) {
            if demoMode.isActive {
                DemoEnvironmentBanner()
            } else if model.configuration.environment
                .showsTestEnvironmentBanner
            {
                TestEnvironmentBanner()
            }
        }
        .task {
            #if DEBUG
            // Keep the loading UI fixture stable and idle so UI automation can
            // observe it without racing the normal launch refresh.
            if ProcessInfo.processInfo.arguments.contains("--fixture-loading") {
                return
            }
            #endif
            await model.start()
        }
        .onChange(of: model.phase) { _, phase in
            if phase != .signedIn {
                router.reset()
            }
        }
        .alert(
            "GameTime",
            isPresented: Binding(
                get: { model.presentedError != nil },
                set: { isPresented in
                    if !isPresented {
                        model.presentedError = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                model.presentedError = nil
            }
        } message: {
            Text(model.presentedError ?? "")
        }
    }
}

private struct DemoEnvironmentBanner: View {
    var body: some View {
        Label(
            "Demo mode — changes stay on this device",
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
            Text("Configuration blocked")
                .font(.title2.bold())
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Only a Supabase URL and publishable key belong in this app.")
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

private struct LaunchingView: View {
    let retry: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            ProgressView()
                .tint(CompetitiveTrustTheme.teal)
                .accessibilityLabel("Loading GameTime")
            Text("Loading trusted state…")
                .font(.headline)
            if model.presentedError != nil {
                Button("Try again", action: retry)
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .frame(maxWidth: 260)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(CompetitiveTrustTheme.ink)
    }
}

private struct SignedOutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.demoMode) private var demoMode

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Spacer(minLength: 56)

                Text("G//T")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(CompetitiveTrustTheme.teal)
                    .accessibilityLabel("GameTime")

                VStack(alignment: .leading, spacing: 12) {
                    Text("Commit clearly.\nCompete fairly.")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(
                        "A staging alpha for friend-to-friend activity challenges with fixed terms and verified progress."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        "Terms are reviewed before invitations are sent",
                        systemImage: "checkmark.shield"
                    )
                    Label(
                        "No sensor or payment action is enabled in M8.1",
                        systemImage: "hand.raised"
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
                    "Sign in creates or restores your private staging account. Apple shares your name only on the first authorization; you can edit it before onboarding."
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
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .name)
                        .accessibilityLabel("Display name")

                    TextField("Handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .handle)
                        .accessibilityLabel("Handle")
                } header: {
                    Text("Your profile")
                } footer: {
                    Text(
                        "Your handle becomes read-only after onboarding until server-side change limits are available."
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
                                    .accessibilityLabel("Saving profile")
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
