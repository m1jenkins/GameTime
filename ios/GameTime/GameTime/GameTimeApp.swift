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
                    .tint(GlassArena.teal800)
                    // The Glass Arena direction is light-mode only.
                    .preferredColorScheme(.light)
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
        VStack(spacing: 16) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(GlassArena.amber700)
                .accessibilityHidden(true)
            Text("Configuration blocked")
                .font(GlassArenaFont.display(26, .heavy))
                .foregroundStyle(GlassArena.ink)
            Text(message)
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.inkTertiary)
                .multilineTextAlignment(.center)
            Text("Only a Supabase URL and publishable key belong in this app.")
                .font(GlassArenaFont.text(12))
                .foregroundStyle(GlassArena.mutedLight)
                .multilineTextAlignment(.center)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassArenaBackground(.today)
        .accessibilityElement(children: .combine)
    }
}

private struct LaunchingView: View {
    let retry: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(GlassArena.teal800)
                .accessibilityLabel("Loading GameTime")
            Text("Getting the rope ready…")
                .font(GlassArenaFont.text(16, .semibold))
                .foregroundStyle(GlassArena.inkSecondary)
            if model.presentedError != nil {
                Button("Try again", action: retry)
                    .buttonStyle(GlassSecondaryButtonStyle())
                    .frame(maxWidth: 260)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassArenaBackground(.today)
    }
}

private struct SignedOutView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Spacer(minLength: 40)

                DuelEyebrow(text: "GameTime", isChip: true)

                Text("Put something\non it.")
                    .font(GlassArenaFont.display(44, .heavy))
                    .foregroundStyle(GlassArena.ink)
                    .lineSpacing(GlassArenaFont.displayLineSpacing(44))
                    .fixedSize(horizontal: false, vertical: true)

                Text(
                    "Pick a friend, pick a number, pick a charity. Whoever loses pays up."
                )
                .font(GlassArenaFont.text(16))
                .foregroundStyle(GlassArena.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 12) {
                    promise(
                        "Terms freeze before the invitation goes out",
                        systemImage: "lock.doc"
                    )
                    promise(
                        "Progress comes from Apple Health — typed numbers never count",
                        systemImage: "heart.fill"
                    )
                    promise(
                        "Friends are found by exact handle, never browsed",
                        systemImage: "at"
                    )
                }
                .padding(18)
                .glassPane(.hero, cornerRadius: 30)

                NativeAppleSignInButton()
                    .disabled(model.isMutating)

                Text(
                    "Signing in creates or restores your private staging account. Apple shares your name only the first time, and you can change it before you finish."
                )
                .font(GlassArenaFont.text(12))
                .foregroundStyle(GlassArena.mutedLight)
                .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: GlassArenaMetrics.contentCap)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .glassArenaBackground(.today)
    }

    private func promise(
        _ text: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(GlassArena.teal800)
                .frame(width: 20)
            Text(text)
                .font(GlassArenaFont.text(14))
                .foregroundStyle(GlassArena.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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

    /// Format is checked as you type. Whether the handle is actually taken is
    /// only known once the profile is created, so this never claims more than
    /// it can.
    private var normalizedHandle: String? {
        ExactHandleSubmission.normalized(handle)
    }

    private var trimmedName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Spacer(minLength: 32)

                Text("Pick a name\nworth beating.")
                    .font(GlassArenaFont.display(38, .heavy))
                    .foregroundStyle(GlassArena.ink)
                    .lineSpacing(GlassArenaFont.displayLineSpacing(38))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 11) {
                    GlassTextField(
                        placeholder: "Your name",
                        text: $displayName,
                        accessibilityID: "Display name",
                        accessibilityName: "Display name"
                    )
                    .focused($focusedField, equals: .name)

                    GlassTextField(
                        placeholder: "handle",
                        text: $handle,
                        prefix: "@",
                        accessibilityID: "Handle",
                        accessibilityName: "Handle",
                        isLowercase: true
                    )
                    .focused($focusedField, equals: .handle)

                    handleFeedback
                }

                Text(
                    "Your handle is how friends find you — exact matches only, so make it something you'll say out loud. It's locked once you're in."
                )
                .font(GlassArenaFont.text(13))
                .foregroundStyle(GlassArena.mutedLight)
                .fixedSize(horizontal: false, vertical: true)

                Button {
                    Task {
                        await model.completeOnboarding(
                            handle: handle,
                            displayName: displayName
                        )
                    }
                } label: {
                    if model.isMutating {
                        ProgressView()
                            .tint(GlassArena.tealInk)
                            .accessibilityLabel("Saving profile")
                    } else {
                        Text("Let's go")
                    }
                }
                .buttonStyle(
                    GlassPrimaryButtonStyle(
                        height: 56,
                        cornerRadius: 20,
                        fontSize: 18
                    )
                )
                .disabled(
                    model.isMutating
                        || normalizedHandle == nil
                        || trimmedName.isEmpty
                )
                .accessibilityIdentifier("onboarding.continue")

                Spacer(minLength: 24)
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: GlassArenaMetrics.contentCap)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .glassArenaBackground(.today)
        .onAppear {
            focusedField = displayName.isEmpty ? .name : .handle
        }
    }

    @ViewBuilder
    private var handleFeedback: some View {
        if handle.isEmpty {
            EmptyView()
        } else if let normalizedHandle {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("@\(normalizedHandle) looks good")
                    .font(GlassArenaFont.text(13, .semibold))
            }
            .foregroundStyle(GlassArena.teal900)
            .padding(.leading, 4)
            .accessibilityElement(children: .combine)
        } else {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 12, weight: .bold))
                Text("3–30 letters, numbers or underscores, starting with a letter")
                    .font(GlassArenaFont.text(13, .semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(GlassArena.amber800)
            .padding(.leading, 4)
            .accessibilityElement(children: .combine)
        }
    }
}
