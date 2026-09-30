import SwiftUI

/// Floodlight round 12: the wordmark and one line on the sky or beams, then
/// Apple's own button and the policy links on the ground. It follows the
/// phone's appearance. Every failure is one quiet sentence above the button,
/// which is also how you try again.
struct LiveSignInView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.demoMode) private var demoMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingAccountDeletionReceipt = false

    static let valueLine = "Private challenges with friends. Proof from Apple Health."
    static let failedMessage = "Couldn’t sign in. Try again."

    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ScrollView {
                VStack(spacing: 0) {
                    hero
                        .padding(.horizontal, 28).padding(.top, top + 24).padding(.bottom, 76)
                        .frame(maxWidth: .infinity, minHeight: (proxy.size.height + top) * 0.69, alignment: .bottom)
                        .background(alignment: .top) { FloodlightSky() }
                    Spacer(minLength: 0)
                    foot.padding(.horizontal, 18).padding(.bottom, 12)
                }
                .frame(minHeight: proxy.size.height + top + proxy.safeAreaInsets.bottom)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .ignoresSafeArea(.container, edges: .top)
        }
        .background(Floodlight.ground.ignoresSafeArea())
        .foregroundStyle(Floodlight.ink)
        .sheet(isPresented: $showingAccountDeletionReceipt) { LiveAccountDeletionReceiptView() }
        .onChange(of: model.isMutating) { _, signingIn in
            if signingIn { SignalAccessibility.announce("Signing in…") }
        }
        .onChange(of: model.signInFailure) { _, failure in
            if failure != nil { SignalAccessibility.announce(Self.failedMessage) }
        }
        #if DEBUG
        .task { await FixtureSignInAttempt.run(model) }
        #endif
    }

    private var hero: some View {
        VStack(spacing: 0) {
            FloodlightBrandMark().fill(Floodlight.brand).frame(width: 46, height: 46).accessibilityHidden(true)
            FloodlightTitle(GameTimePublicIdentity.name, size: 76, maxScale: 1.3, spacing: -0.015)
                .foregroundStyle(Floodlight.ink).lineLimit(1).minimumScaleFactor(0.6)
                .accessibilityAddTraits(.isHeader).padding(.top, 14)
            Text(Self.valueLine).floodlightFont(17, weight: .medium).lineSpacing(3)
                .foregroundStyle(Floodlight.heroMuted).multilineTextAlignment(.center)
                .frame(maxWidth: 270).fixedSize(horizontal: false, vertical: true).padding(.top, 14)
        }
    }

    private var foot: some View {
        VStack(spacing: 12) {
            if model.signInFailure != nil {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle").font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Floodlight.accent).frame(width: 30, height: 30)
                        .background(Circle().fill(Floodlight.well)).accessibilityHidden(true)
                    Text(Self.failedMessage).floodlightFont(15, weight: .semibold)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14).padding(.vertical, 12).floodlightCard(radius: 16)
                .accessibilityElement(children: .combine).accessibilityIdentifier("auth.sign-in.failed")
            }
            #if DEBUG
            if ChallengeAuthenticatedAppLaunch.enabled {
                Button("Sign in with local test account") {
                    Task { await model.signInWithApple(ChallengeAuthenticatedAppLaunch.identity) }
                }.buttonStyle(FloodlightPrimaryButtonStyle())
                    .disabled(model.isMutating).accessibilityIdentifier("auth.local-substitute")
            } else {
                appleButton
            }
            #else
            appleButton
            #endif
            if model.isMutating {
                HStack(spacing: 8) {
                    ProgressView().tint(Floodlight.accent)
                    Text("Signing in…").floodlightFont(14, weight: .medium).foregroundStyle(Floodlight.muted)
                }.frame(minHeight: 24).accessibilityElement(children: .combine)
                    .accessibilityIdentifier("auth.sign-in.status")
            }
            if demoMode.isAvailable, !demoMode.isActive {
                Button("Try demo mode", action: demoMode.enter).buttonStyle(FloodlightCalmButtonStyle(height: 48))
                    .accessibilityIdentifier("demo.enter")
            }
            if let notice = model.accountDeletionNotice {
                Label(notice, systemImage: "checkmark.circle")
                    .floodlightFont(14, weight: .medium).foregroundStyle(Floodlight.accent)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .floodlightCard(radius: 16)
                    .accessibilityIdentifier("account-deletion.success")
            }
            if model.accountDeletionReceipt != nil {
                Button("Check account deletion") { showingAccountDeletionReceipt = true }
                    .buttonStyle(FloodlightQuietButtonStyle()).accessibilityIdentifier("account-deletion.receipt")
            }
            policyLinks
        }
    }

    private var appleButton: some View {
        // Apple's button, not a Floodlight action: its own colors, height and
        // shape. It dims while we finish signing in.
        NativeAppleSignInButton().disabled(model.isMutating).opacity(model.isMutating ? 0.6 : 1)
    }

    private var policyLinks: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 28))
        return layout {
            if let url = model.configuration.privacyPolicyURL { policyLink("Privacy Policy", url) }
            if let url = model.configuration.betaTermsURL { policyLink("Beta Terms", url) }
        }.frame(maxWidth: .infinity)
    }

    private func policyLink(_ title: String, _ url: URL) -> some View {
        Link(title, destination: url).floodlightFont(13.5, weight: .semibold).foregroundStyle(Floodlight.link)
            .frame(minHeight: 44).contentShape(Rectangle())
    }
}

/// D142: nobody under 21 gives us a name or username. The first step states
/// the Apple Watch requirement and simulated stakes and asks for 21+; only
/// then does the profile step appear.
struct LiveOnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var handle = ""
    @State private var displayName: String
    @State private var ageConfirmed = false
    @State private var showingProfile = false
    @State private var under21 = false
    @State private var keyboardVisible = false
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
                Text("Before you start").liveFont(30, weight: .bold).tracking(-1)
                    .accessibilityAddTraits(.isHeader).padding(.top, 22)
                Text("A couple of things to know about GameTime.").liveFont(15)
                    .foregroundStyle(SignalTheme.textSecondary).padding(.top, 10)
                VStack(alignment: .leading, spacing: 20) {
                    LiveOnboardingFact(symbol: "applewatch", title: "You need an Apple Watch",
                        text: "Your activity has to come from an Apple Watch that records to Apple Health on this iPhone. Activity recorded only by iPhone doesn’t count.")
                    LiveOnboardingFact(symbol: "info.circle", title: "Stakes are simulated",
                        text: "No real money moves. Nothing can be paid out or redeemed.")
                }.padding(.top, 26)
                Toggle("I confirm I am 21 or older", isOn: $ageConfirmed)
                    .liveFont(16, weight: .medium).tint(SignalTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
                    .padding(.horizontal, 16).frame(minHeight: 56)
                    .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.top, 30).accessibilityIdentifier("onboarding.age.toggle")
                Text("GameTime is only for people 21 and older.").liveFont(12)
                    .foregroundStyle(SignalTheme.textSecondary).padding(.top, 10).padding(.horizontal, 4)
            }.padding(.horizontal, SignalTheme.contentInset).padding(.bottom, 24)
        }
        .background(SignalTheme.canvas.ignoresSafeArea()).foregroundStyle(SignalTheme.textPrimary)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            consentActions
                .padding(.horizontal, SignalTheme.contentInset).padding(.top, 12).padding(.bottom, 6)
                .background(SignalTheme.canvas)
        }
        .alert("GameTime is for people 21 and older", isPresented: $under21) {
            Button("Sign out") { Task { await model.signOut() } }
            Button("Go back", role: .cancel) {}
        } message: {
            Text("You can’t use GameTime yet. We haven’t saved a profile for you. You can sign out, or use a different Apple account.")
        }
        .tint(SignalTheme.accent)
    }

    private var consentActions: some View {
        VStack(spacing: 4) {
            Button { showingProfile = true } label: {
                HStack(spacing: 10) { Text("Continue"); Image(systemName: "arrow.right").accessibilityHidden(true) }
            }
            .buttonStyle(LivePrimaryButtonStyle()).disabled(!ageConfirmed)
            .accessibilityIdentifier("onboarding.age.continue")
            Button { under21 = true } label: {
                Text("I’m under 21").liveFont(14, weight: .medium).foregroundStyle(SignalTheme.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityIdentifier("onboarding.age.under21")
        }
    }

    private var profile: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        LiveOnboardingSteps(current: 2).padding(.top, 16).padding(.bottom, -8)
                        HStack {
                            Text("Your profile").liveFont(28, weight: .bold).tracking(-1)
                            Spacer()
                            Image(systemName: "person.crop.circle").font(.system(size: 25, weight: .regular))
                                .foregroundStyle(SignalTheme.textSecondary).accessibilityHidden(true)
                        }.padding(.top, 16)
                        Text("Add your name and the username friends will use to find you.")
                            .liveFont(15).foregroundStyle(SignalTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        VStack(alignment: .leading, spacing: 22) {
                            profileField("Your name", text: $displayName, field: .name)
                            profileField("Username", text: $handle, field: .handle)
                        }
                        Text("Pick carefully — you can’t change your username yet. Friends need it to send you a request.")
                            .liveFont(12).foregroundStyle(SignalTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let message = error(.general) {
                            Text(message).liveFont(13, weight: .medium).foregroundStyle(SignalTheme.danger)
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
                            }.liveFont(14, weight: .medium).foregroundStyle(SignalTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 44).disabled(model.isMutating)
                                .accessibilityIdentifier("onboarding.use-different-account")
                        }
                    }.padding(.horizontal, SignalTheme.contentInset).padding(.vertical, 24)
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
                    .onChange(of: focusedField) { _, _ in
                        if keyboardVisible { revealFocusedField(using: proxy) }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidShowNotification)) { _ in
                        keyboardVisible = true
                        revealFocusedField(using: proxy)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                        keyboardVisible = false
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
            }
        }.tint(SignalTheme.accent)
    }

    private func revealFocusedField(using proxy: ScrollViewProxy) {
        guard dynamicTypeSize.isAccessibilitySize, let focusedField else { return }
        // Center the whole field and helper, leaving clearance for the keyboard accessory.
        proxy.scrollTo(focusedField, anchor: .center)
    }

    private func profileField(_ title: String, text: Binding<String>, field: Field) -> some View {
        let message = error(field == .name ? .name : .username)
        return VStack(alignment: .leading, spacing: 8) {
            Text(title).liveFont(13, weight: .semibold)
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
            }.liveFont(17, weight: .medium)
                .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 12 : 0)
                .padding(.horizontal, 16).frame(minHeight: 56)
                .background(SignalTheme.soft, in: RoundedRectangle(cornerRadius: 16))
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(message == nil ? SignalTheme.divider.opacity(0.45) : SignalTheme.danger, lineWidth: 1) }
            Text(message ?? (field == .name ? "Name: 1–50 characters" : "Username: 3–30 letters, numbers, or underscores; starts with a letter"))
                .liveFont(12).foregroundStyle(message == nil ? SignalTheme.textSecondary : SignalTheme.danger)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(field == .name ? "onboarding.name.message" : "onboarding.username.message")
        }
        .id(field)
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
                Text(title).liveFont(16, weight: .semibold)
                Text(text).liveFont(14).foregroundStyle(SignalTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct LiveLaunchingView: View {
    let errorMessage: String?
    let retry: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var offline: Bool { errorMessage?.localizedCaseInsensitiveContains("offline") == true }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                launchContent
                    .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 310)
                    .padding(.horizontal, SignalTheme.contentInset).padding(.vertical, 24)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background(SignalTheme.canvas).foregroundStyle(SignalTheme.textPrimary)
    }

    private var launchContent: some View {
        VStack(spacing: 20) {
            Text(GameTimePublicIdentity.name).liveFont(28, weight: .bold).tracking(-1.1)
            if let errorMessage {
                VStack(spacing: 10) {
                    Text("Couldn’t load your challenges").liveFont(17, weight: .semibold)
                        .accessibilityIdentifier("launch.retry")
                    Text(offline ? "Check your connection and try again." : errorMessage)
                        .liveFont(14).foregroundStyle(SignalTheme.textSecondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    if offline {
                        Label("Offline", systemImage: "wifi.slash").liveFont(12)
                            .foregroundStyle(SignalTheme.textSecondary).accessibilityIdentifier("launch.offline")
                    }
                }
                Button("Try again", action: retry).buttonStyle(LiveSecondaryButtonStyle())
                    .accessibilityIdentifier("launch.retry.button")
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(SignalTheme.accent).accessibilityLabel("Loading \(GameTimePublicIdentity.name)")
                    Text("Loading…").liveFont(14).foregroundStyle(SignalTheme.textSecondary)
                }.accessibilityElement(children: .contain).accessibilityIdentifier("launch.loading")
            }
        }
        .multilineTextAlignment(.center)
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
                    .liveFont(28, weight: .bold).tracking(-1.1)
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
                            .liveFont(17, weight: .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(message)
                        .liveFont(14).lineSpacing(3)
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
            }.padding(.horizontal, SignalTheme.contentInset).padding(.vertical, 24)
        }.background(SignalTheme.canvas).foregroundStyle(SignalTheme.textPrimary)
    }
}
