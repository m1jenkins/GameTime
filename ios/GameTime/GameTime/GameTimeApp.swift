import GameTimeCore
import SwiftUI

@main
@MainActor
struct GameTimeApp: App {
    @State private var model: AppModel?
    @State private var router = AppRouter()
    private let configurationFailure: String?

    init() {
        do {
            let configuration: AppConfiguration
            let services: AppServices

            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--fixture-mode") {
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

            _model = State(
                initialValue: AppModel(
                    configuration: configuration,
                    services: services
                )
            )
            configurationFailure = nil
        } catch {
            _model = State(initialValue: nil)
            configurationFailure = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let model {
                RootView(model: model, router: router)
                    .environment(model)
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
}

@MainActor
struct RootView: View {
    @Bindable var model: AppModel
    @Bindable var router: AppRouter

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
        .safeAreaInset(edge: .top, spacing: 0) {
            if model.configuration.environment
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
                        "A staging alpha for friend-to-friend activity duels with fixed terms and verified progress."
                    )
                    .font(.body)
                    .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        "Terms are reviewed before an invitation is sent",
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
