import SwiftUI

/// Account entry uses the approved light system while retaining the native
/// Apple authorization control and AppModel's account lifecycle.
struct LiveSignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.demoMode) private var demoMode
    @State private var showingAccountDeletionReceipt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Text(GameTimePublicIdentity.name)
                        .font(.system(size: 28, weight: .bold)).tracking(-1.1)
                    Spacer()
                    Label("Private account", systemImage: "lock")
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(SignalTheme.textSecondary)
                }.padding(.top, 22)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sign in").font(.system(size: 32, weight: .bold)).tracking(-1.1)
                    Text("Your challenges and your record, in one place.")
                        .font(.system(size: 15)).foregroundStyle(SignalTheme.textSecondary)
                }.padding(.top, 14)

                VStack(spacing: 0) {
                    introduction("Your goal", value: "Choose the activity, goal and dates.", symbol: "flag")
                    Divider().overlay(SignalTheme.divider.opacity(0.6)).padding(.leading, 62)
                    introduction("Your agreement", value: "Review the full rules before you start.", symbol: "checkmark.shield")
                    Divider().overlay(SignalTheme.divider.opacity(0.6)).padding(.leading, 62)
                    introduction("Your record", value: "Your wider activity history stays private.", symbol: "lock")
                }.modifier(LiveCardModifier(radius: 20, material: true))

                VStack(spacing: 14) {
                    #if DEBUG
                    if ChallengeAuthenticatedAppLaunch.enabled {
                        Button("Sign in with local test account") {
                            Task { await model.signInWithApple(ChallengeAuthenticatedAppLaunch.identity) }
                        }.buttonStyle(LivePrimaryButtonStyle())
                            .disabled(model.isMutating).accessibilityIdentifier("auth.local-substitute")
                    } else {
                        NativeAppleSignInButton().disabled(model.isMutating)
                    }
                    #else
                    NativeAppleSignInButton().disabled(model.isMutating)
                    #endif

                    if model.isMutating {
                        HStack(spacing: 8) {
                            ProgressView().tint(SignalTheme.accent)
                            Text("Signing in…").font(.system(size: 13)).foregroundStyle(SignalTheme.textSecondary)
                        }.accessibilityIdentifier("auth.sign-in.status")
                    }
                    if demoMode.isAvailable, !demoMode.isActive {
                        Button("Try demo mode", action: demoMode.enter)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(SignalTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                            .accessibilityIdentifier("demo.enter")
                    }
                }

                if let notice = model.accountDeletionNotice {
                    Label(notice, systemImage: "checkmark.circle")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(SignalTheme.accent)
                        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        .modifier(LiveCardModifier(radius: 18, material: true))
                        .accessibilityIdentifier("account-deletion.success")
                }
                if model.accountDeletionReceipt != nil {
                    Button("Check account deletion") { showingAccountDeletionReceipt = true }
                        .font(.system(size: 14, weight: .semibold)).frame(minHeight: 44)
                        .foregroundStyle(SignalTheme.accent).accessibilityIdentifier("account-deletion.receipt")
                }

                VStack(alignment: .leading, spacing: 16) {
                    Text("Signing in creates your private account. Apple only shares your name the first time, and you can change it on the next screen.")
                        .font(.system(size: 12)).lineSpacing(3).foregroundStyle(SignalTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    PublicSupportLinksView(privacyURL: model.configuration.privacyPolicyURL,
                        betaTermsURL: model.configuration.betaTermsURL,
                        supportMailtoURL: model.configuration.supportMailtoURL)
                }
            }.padding(24)
        }.background(SignalTheme.canvas).foregroundStyle(SignalTheme.textPrimary)
            .sheet(isPresented: $showingAccountDeletionReceipt) { LiveAccountDeletionReceiptView() }
            .onChange(of: model.isMutating) { _, signingIn in
                if signingIn { SignalAccessibility.announce("Signing in…") }
            }
            .onChange(of: model.presentedError) { _, message in
                if let message { SignalAccessibility.announce(message) }
            }
    }

    private func introduction(_ title: String, value: String, symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                .foregroundStyle(SignalTheme.accent).frame(width: 34, height: 34)
                .background(SignalTheme.accent.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(value).font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16)
    }
}

/// D142: nobody under 21 gives us a name or username. The first step states
/// the Apple Watch requirement and simulated stakes and asks for 21+; only
/// then does the profile step appear.
struct LiveOnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var handle = ""
    @State private var displayName: String
    @State private var ageConfirmed = false
    @State private var showingProfile = false
    @State private var under21 = false
    @FocusState private var focusedField: Field?
    private enum Field: Hashable { case name, handle }

    init(namePrefill: String) { _displayName = State(initialValue: namePrefill) }

    var body: some View {
        if showingProfile { profile } else { beforeYouStart }
    }

    private var beforeYouStart: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                LiveOnboardingSteps(current: 1).padding(.top, 16)
                Text("Before you start").font(.system(size: 30, weight: .bold)).tracking(-1)
                    .accessibilityAddTraits(.isHeader).padding(.top, 22)
                Text("A couple of things to know about GameTime.").font(.system(size: 15))
                    .foregroundStyle(SignalTheme.textSecondary).padding(.top, 10)
                VStack(alignment: .leading, spacing: 20) {
                    LiveOnboardingFact(symbol: "applewatch", title: "You need an Apple Watch",
                        text: "Your activity has to come from an Apple Watch that records to Apple Health on this iPhone. Activity recorded only by iPhone doesn’t count.")
                    LiveOnboardingFact(symbol: "info.circle", title: "Stakes are simulated",
                        text: "No real money moves. Nothing can be paid out or redeemed.")
                }.padding(.top, 26)
                Toggle("I confirm I am 21 or older", isOn: $ageConfirmed)
                    .font(.system(size: 16, weight: .medium)).tint(SignalTheme.accent)
                    .padding(.horizontal, 16).frame(minHeight: 56)
                    .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 30).accessibilityIdentifier("onboarding.age.toggle")
                Text("GameTime is only for people 21 and older.").font(.system(size: 12))
                    .foregroundStyle(SignalTheme.textSecondary).padding(.top, 10).padding(.horizontal, 4)
            }.padding(.horizontal, 24).padding(.bottom, 24)
        }
        .background(SignalTheme.canvas.ignoresSafeArea()).foregroundStyle(SignalTheme.textPrimary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button { showingProfile = true } label: {
                    HStack(spacing: 10) { Text("Continue"); Image(systemName: "arrow.right").accessibilityHidden(true) }
                }
                .buttonStyle(LivePrimaryButtonStyle()).disabled(!ageConfirmed)
                .accessibilityIdentifier("onboarding.age.continue")
                Button("I’m under 21") { under21 = true }
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(SignalTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("onboarding.age.under21")
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 6).background(SignalTheme.canvas)
        }
        .alert("GameTime is for people 21 and older", isPresented: $under21) {
            Button("Sign out") { Task { await model.signOut() } }
            Button("Go back", role: .cancel) {}
        } message: {
            Text("You can’t use GameTime yet. We haven’t saved a profile for you. You can sign out, or use a different Apple account.")
        }
        .tint(SignalTheme.accent)
    }

    private var profile: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    LiveOnboardingSteps(current: 2).padding(.top, 16).padding(.bottom, -8)
                    HStack {
                        Text("Your profile").font(.system(size: 28, weight: .bold)).tracking(-1)
                        Spacer()
                        Image(systemName: "person.crop.circle").font(.system(size: 25, weight: .regular))
                            .foregroundStyle(SignalTheme.textSecondary).accessibilityHidden(true)
                    }.padding(.top, 16)
                    Text("Add your name and the username friends will use to find you.")
                        .font(.system(size: 15)).foregroundStyle(SignalTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 22) {
                        profileField("Your name", text: $displayName, field: .name)
                        profileField("Username", text: $handle, field: .handle)
                    }
                    Text("Pick carefully — you can’t change your username yet. Friends need it to send you a request.")
                        .font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let message = error(.general) {
                        Text(message).font(.system(size: 13, weight: .medium)).foregroundStyle(SignalTheme.danger)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("onboarding.general.error")
                    }
                    VStack(spacing: 12) {
                        Button(model.isMutating ? "Saving profile…" : "Enter GameTime") { submit() }
                            .buttonStyle(LivePrimaryButtonStyle())
                            .disabled(model.isMutating || handle.isEmpty || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .accessibilityIdentifier("onboarding.submit")
                        Button("Use a different Apple account") {
                            focusedField = nil
                            Task { await model.signOut() }
                        }.font(.system(size: 14, weight: .medium)).foregroundStyle(SignalTheme.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 44).disabled(model.isMutating)
                            .accessibilityIdentifier("onboarding.use-different-account")
                    }
                }.padding(24)
            }.background(SignalTheme.canvas).foregroundStyle(SignalTheme.textPrimary)
                .scrollDismissesKeyboard(.interactively).toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(focusedField == .name ? "Next" : "Done") {
                            if focusedField == .name { focusedField = .handle } else { submit() }
                        }.disabled(model.isMutating)
                    }
                }
                .onAppear { focusedField = displayName.isEmpty ? .name : .handle }
                .onChange(of: displayName) { _, _ in model.clearOnboardingError() }
                .onChange(of: handle) { _, _ in model.clearOnboardingError() }
                .onChange(of: model.onboardingError) { _, error in
                    guard let error else { return }
                    SignalAccessibility.announce(error.message)
                    switch error.field {
                    case .name: focusedField = .name
                    case .username: focusedField = .handle
                    case .general: break
                    }
                }
        }.tint(SignalTheme.accent)
    }

    private func profileField(_ title: String, text: Binding<String>, field: Field) -> some View {
        let message = error(field == .name ? .name : .username)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                if field == .handle { Text("@").foregroundStyle(SignalTheme.textSecondary) }
                TextField(title, text: text)
                    .textContentType(field == .name ? .name : .username)
                    .textInputAutocapitalization(field == .handle ? .never : .words)
                    .autocorrectionDisabled(field == .handle)
                    .submitLabel(field == .name ? .next : .done)
                    .focused($focusedField, equals: field)
                    .onSubmit { if field == .name { focusedField = .handle } else { submit() } }
                    .disabled(model.isMutating).accessibilityLabel(title)
                    .accessibilityIdentifier(field == .name ? "onboarding.name.input" : "onboarding.username.input")
            }.font(.system(size: 17, weight: .medium)).padding(.horizontal, 16).frame(minHeight: 56)
                .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(message == nil ? SignalTheme.divider.opacity(0.45) : SignalTheme.danger, lineWidth: 1) }
            Text(message ?? (field == .name ? "Name: 1–50 characters" : "Username: 3–30 letters, numbers, or underscores; starts with a letter"))
                .font(.system(size: 12)).foregroundStyle(message == nil ? SignalTheme.textSecondary : SignalTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(field == .name ? "onboarding.name.message" : "onboarding.username.message")
        }
    }

    private func error(_ field: OnboardingErrorField) -> String? {
        model.onboardingError?.field == field ? model.onboardingError?.message : nil
    }
    private func submit() {
        guard !model.isMutating else { return }
        focusedField = nil
        Task { await model.completeOnboarding(handle: handle, displayName: displayName, ageConfirmed: ageConfirmed) }
    }
}

private struct LiveOnboardingSteps: View {
    let current: Int
    var body: some View {
        HStack(spacing: 6) {
            ForEach(1...2, id: \.self) { step in
                Capsule().fill(step <= current ? SignalTheme.accent : SignalTheme.divider).frame(width: 22, height: 5)
            }
        }
        .accessibilityElement().accessibilityLabel("Step \(current) of 2")
    }
}

private struct LiveOnboardingFact: View {
    let symbol: String
    let title: String
    let text: String
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(SignalTheme.textPrimary)
                .frame(width: 40, height: 40).background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 11))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(text).font(.system(size: 14)).foregroundStyle(SignalTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct LiveLaunchingView: View {
    let errorMessage: String?
    let retry: () -> Void
    private var offline: Bool { errorMessage?.localizedCaseInsensitiveContains("offline") == true }

    var body: some View {
        VStack(spacing: 20) {
            Text(GameTimePublicIdentity.name).font(.system(size: 28, weight: .bold)).tracking(-1.1)
            if let errorMessage {
                VStack(spacing: 10) {
                    Text("Couldn’t load your challenges").font(.system(size: 17, weight: .semibold))
                        .accessibilityIdentifier("launch.retry")
                    Text(offline ? "Check your connection and try again." : errorMessage)
                        .font(.system(size: 14)).foregroundStyle(SignalTheme.textSecondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    if offline {
                        Label("Offline", systemImage: "wifi.slash").font(.system(size: 12))
                            .foregroundStyle(SignalTheme.textSecondary).accessibilityIdentifier("launch.offline")
                    }
                }
                Button("Try again", action: retry).buttonStyle(LivePrimaryButtonStyle(height: 48))
                    .accessibilityIdentifier("launch.retry.button")
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(SignalTheme.accent).accessibilityLabel("Loading \(GameTimePublicIdentity.name)")
                    Text("Loading…").font(.system(size: 14)).foregroundStyle(SignalTheme.textSecondary)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("launch.loading")
            }
        }.frame(maxWidth: 310).padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(SignalTheme.canvas).foregroundStyle(SignalTheme.textPrimary)
    }
}

/// Startup cannot offer account actions until configuration loads. Keep the
/// supplied failure and the same validated, published support destinations.
struct LiveConfigurationFailureView: View {
    let message: String

    private var privacyURL: URL? {
        AppConfiguration.publishedPolicyURL(
            Bundle.main.object(forInfoDictionaryKey: "GAMETIME_PRIVACY_POLICY_URL") as? String)
    }
    private var betaTermsURL: URL? {
        AppConfiguration.publishedPolicyURL(
            Bundle.main.object(forInfoDictionaryKey: "GAMETIME_BETA_TERMS_URL") as? String)
    }
    private var supportMailtoURL: URL? {
        AppConfiguration.supportInbox(
            Bundle.main.object(forInfoDictionaryKey: "GAMETIME_SUPPORT_EMAIL") as? String
        ).flatMap { URL(string: "mailto:\($0)") }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text(GameTimePublicIdentity.name)
                    .font(.system(size: 28, weight: .bold)).tracking(-1.1)
                    .padding(.top, 22)

                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.trianglebadge.exclamationmark")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(SignalTheme.danger)
                            .frame(width: 34, height: 34)
                            .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 12))
                            .accessibilityHidden(true)
                        Text("GameTime can’t start")
                            .font(.system(size: 17, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(message)
                        .font(.system(size: 14)).lineSpacing(3)
                        .foregroundStyle(SignalTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .modifier(LiveCardModifier(radius: 20, material: true))
                    .accessibilityIdentifier("configuration.failure")

                if let supportMailtoURL {
                    Link("Contact support", destination: supportMailtoURL)
                        .buttonStyle(LivePrimaryButtonStyle(height: 48))
                }
                PublicSupportLinksView(privacyURL: privacyURL,
                    betaTermsURL: betaTermsURL, supportMailtoURL: nil)
            }.padding(24)
        }.background(SignalTheme.canvas).foregroundStyle(SignalTheme.textPrimary)
    }
}
