import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @Environment(PersonalAccountabilityStore.self) private var personalStore
    @Environment(AppRouter.self) private var router
    @Environment(\.demoMode) private var demoMode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                profileCard
                healthSection
                #if DEBUG || STAGING
                if model.configuration.weeklyRuntimeEnabled {
                    NavigationLink(value: YouRoute.weekly) {
                        Label("Weekly challenges", systemImage: "figure.walk")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.accessibilityIdentifier("weekly.open")
                }
                if model.configuration.performanceCommitmentRuntimeEnabled {
                    NavigationLink(value: YouRoute.performanceCommitments) {
                        Label("Running goals", systemImage: "flag.checkered")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("commitment.open")
                }
                if model.configuration.duelRuntimeEnabled {
                    NavigationLink(value: YouRoute.duels) {
                        Label("Friend duels", systemImage: "figure.run")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }
                    .accessibilityIdentifier("duel.open")
                }
                #endif
                settingsSection
                demoSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .signalTabScrollClearance()
        .signalScreenChrome()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var profileCard: some View {
        if let profile = model.profile {
            SignalOpenSection {
                HStack(spacing: 15) {
                    InitialsAvatar(
                        initials: profile.initials,
                        size: 60,
                        color: SignalTheme.accent
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(.title2.bold())
                            .tracking(-0.65)
                        Text("@\(profile.handle)")
                            .font(.subheadline)
                            .foregroundStyle(SignalTheme.textSecondary)
                            .accessibilityLabel(
                                "Username \(profile.handle)"
                            )
                    }
                    Spacer(minLength: 0)
                }
                Divider()
                    .overlay(SignalTheme.divider)
                    .padding(.vertical, 12)
                settingRow("Time zone", profile.timezone)
                Divider()
                    .overlay(SignalTheme.divider)
                    .padding(.vertical, 12)
                historyMetrics
            }
        }
    }

    @ViewBuilder
    private var historyMetrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                historyMetric(
                    personalStore.challenges.count.formatted(),
                    "All"
                )
                historyMetric(
                    (personalStore.openChallenge == nil ? 0 : 1).formatted(),
                    "Active"
                )
                historyMetric(
                    personalStore.history.count.formatted(),
                    "Finished"
                )
            }
        } else {
            HStack(spacing: 0) {
                historyMetric(
                    personalStore.challenges.count.formatted(),
                    "All"
                )
                historyMetric(
                    (personalStore.openChallenge == nil ? 0 : 1).formatted(),
                    "Active"
                )
                historyMetric(
                    personalStore.history.count.formatted(),
                    "Finished"
                )
            }
        }
    }

    private var healthSection: some View {
        Group {
            SignalSectionLabel(text: "Apple Health")
            SignalOpenSection {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        personalStore.healthReadiness.permitsCreation
                            ? "Health connected"
                            : "Steps",
                        systemImage: personalStore.healthReadiness.permitsCreation
                            ? "checkmark.circle.fill"
                            : "heart.fill"
                    )
                        .font(.headline)
                    Text(
                        personalStore.healthReadiness.permitsCreation
                            ? "GameTime can update your challenge automatically from your Apple Health step history."
                            : "Connect Apple Health so GameTime can update your challenge automatically from your step history."
                    )
                    .font(.caption)
                    .foregroundStyle(SignalTheme.textSecondary)

                    if !personalStore.healthReadiness.permitsCreation {
                        Button(
                            personalStore.isVerifyingHealthAccess
                                ? "Connecting…"
                                : "Connect Apple Health"
                        ) {
                            Task {
                                SignalAccessibility.announce("Connecting…")
                                let connected = await personalStore
                                    .verifyHealthAccess(
                                    timezone: model.profile?.timezone
                                        ?? TimeZone.current.identifier
                                )
                                SignalAccessibility.announce(
                                    connected
                                        ? "Health connected."
                                        : "Apple Health connection failed."
                                )
                            }
                        }
                        .buttonStyle(SignalSecondaryButtonStyle())
                        .disabled(
                            personalStore.isVerifyingHealthAccess
                                || !personalStore.configuration.activitySyncEnabled
                        )
                        .accessibilityIdentifier("personal.health.verify")
                    }

                    if !personalStore.configuration.activitySyncEnabled {
                        Text(
                            "Health connection checks aren’t available yet."
                        )
                        .font(.caption2)
                        .foregroundStyle(SignalTheme.textSecondary)
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        Group {
            SignalSectionLabel(text: "Settings")
            SignalOpenSection {
                VStack(spacing: 0) {
                    Button {
                        router.youPath.append(.trustAndPrivacy)
                    } label: {
                        settingsNavigationRow(
                            title: "Your privacy",
                            detail: "What we read, what we send, and what stays on your phone",
                            icon: "checkmark.shield.fill",
                            iconColor: SignalTheme.accent
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacy.open")

                    Divider().overlay(SignalTheme.divider)

                    Button {
                        router.openAccountSupport()
                    } label: {
                        settingsNavigationRow(
                            title: "Account & support",
                            detail: "Support, documents, sign out, and account deletion",
                            icon: "person.crop.circle.badge.questionmark",
                            iconColor: SignalTheme.accent
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("account-support.open")
                }
            }
        }
    }

    private func settingsNavigationRow(
        title: String,
        detail: String,
        icon: String,
        iconColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(
                        SignalTheme.textSecondary
                    )
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .foregroundStyle(SignalTheme.divider)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .signalTappableRow()
    }

    @ViewBuilder
    private var demoSection: some View {
        if demoMode.isAvailable {
            SignalSectionLabel(text: "Demo")
            SignalOpenSection {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(demoMode.isActive ? "Exit demo mode" : "Open demo mode")
                            .font(.body.weight(.semibold))
                        Text(
                            demoMode.isActive
                                ? "Go back to your real account."
                                : "Try the app out with sample data."
                        )
                        .font(.caption)
                        .foregroundStyle(SignalTheme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Button(demoMode.isActive ? "Exit" : "Open") {
                        demoMode.isActive ? demoMode.exit() : demoMode.enter()
                    }
                    .buttonStyle(SignalCompactButtonStyle())
                    .accessibilityIdentifier(
                        demoMode.isActive ? "demo.exit" : "demo.enter"
                    )
                }
            }
        }
    }

    private func settingRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label).font(.subheadline.weight(.semibold))
            Spacer(minLength: 8)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(SignalTheme.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func historyMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(
                    SignalTheme.displayFont(
                        size: 21,
                        relativeTo: .title3
                    )
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(SignalTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct TrustAndPrivacyView: View {
    @Environment(PersonalAccountabilityStore.self)
    private var personalStore

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                privacyCard(
                    title: "Only you can see your challenges",
                    detail:
                        "Your goal, your progress, and how each week turned out are yours alone. Nobody else can look them up.",
                    icon: "person.crop.circle.badge.checkmark"
                )
                privacyCard(
                    title: "We read steps, not your health history",
                    detail:
                        "We only read step counts from Apple Health. Steps Apple marks as manually entered aren’t counted, and nothing else in Apple Health is ever read.",
                    icon: "heart.text.square.fill"
                )
                privacyCard(
                    title: "If we can’t see your data, you don’t lose",
                    detail:
                        "When steps go missing or don’t add up, the week doesn’t count — it’s never treated as a miss. If the problem is on our end, that’s on us.",
                    icon: "checkmark.shield.fill"
                )
                privacyCard(
                    title: "Private challenge and test payment details",
                    detail:
                        "Your goal and progress stay private. Stripe handles test payment details; GameTime keeps only the test payment references and status needed for the sandbox.",
                    icon: "lock.fill"
                )
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
        }
        .signalTabScrollClearance()
        .signalScreenChrome()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyCard(
        title: String,
        detail: String,
        icon: String
    ) -> some View {
        SignalOpenSection {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(SignalTheme.accent)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(SignalTheme.textSecondary)
                }
            }
        }
    }
}

private enum AccountSupportSheet: Identifiable {
    case deleteAccount

    var id: String { "delete-account" }
}

struct AccountSupportView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.demoMode) private var demoMode
    @State private var presentedSheet: AccountSupportSheet?
    @State private var showDeleteConfirmation = false

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                helpDocumentsSection
                accountSection
                versionNote
            }
            .padding(.horizontal, 20)
            .padding(.top, 4)
        }
        .signalTabScrollClearance()
        .signalScreenChrome()
        .navigationTitle("Account & support")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Delete your account?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Continue", role: .destructive) {
                presentedSheet = .deleteAccount
            }
        } message: {
            Text(
                "Your name, username, and profile will be replaced with an anonymous placeholder. Your sign-in and setup saved on this phone will be removed, and your Stripe test customer and saved payment method will be deleted. Your step data will no longer be readable and will be removed on the schedule in the Privacy Policy. A small anonymous record that a challenge existed and how it was scored will remain. This can’t be undone."
            )
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .deleteAccount:
                DeleteAccountView()
            }
        }
    }

    private var helpDocumentsSection: some View {
        Group {
            SignalSectionLabel(text: "Help & documents")
            SignalOpenSection {
                VStack(spacing: 0) {
                    externalRow(
                        title: "Apple Health help",
                        detail: "Manage step access and Health permissions",
                        icon: "heart.text.square.fill",
                        destination: URL(string: "https://support.apple.com/en-us/HT204351")
                    )
                    Divider().overlay(SignalTheme.divider)
                    supportRow
                    Divider().overlay(SignalTheme.divider)
                    documentRow(
                        title: "Privacy Policy",
                        detail: "How GameTime handles your data",
                        icon: "hand.raised.fill",
                        destination: model.configuration.privacyPolicyURL,
                        accessibilityIdentifier:
                            "account-support.privacy-policy"
                    )
                    Divider().overlay(SignalTheme.divider)
                    documentRow(
                        title: "Beta Terms",
                        detail: "The terms for this beta release",
                        icon: "doc.text.fill",
                        destination: model.configuration.betaTermsURL,
                        accessibilityIdentifier: "account-support.beta-terms"
                    )
                }
            }
        }
    }

    private var accountSection: some View {
        Group {
            SignalSectionLabel(text: "Account")
            SignalOpenSection {
                VStack(spacing: 12) {
                    if !demoMode.isActive {
                        Button(role: .destructive) {
                            SignalAccessibility.announce("Signing out…")
                            Task { await model.signOut() }
                        } label: {
                            if model.isMutating {
                                SignalAsyncStatus(message: "Signing out…")
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )
                            } else {
                                Label(
                                    "Sign out",
                                    systemImage:
                                        "rectangle.portrait.and.arrow.right"
                                )
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                            }
                        }
                        .buttonStyle(SignalSecondaryButtonStyle())
                        .disabled(model.isMutating)
                        .accessibilityIdentifier("account-support.sign-out")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete account", systemImage: "person.crop.circle.badge.minus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(SignalSecondaryButtonStyle())
                    .disabled(model.isMutating || demoMode.isActive)
                    .accessibilityIdentifier("account-support.delete")
                }
            }
        }
    }

    private var supportRow: some View {
        Group {
            if let supportURL = model.configuration.supportMailtoURL {
                Link(destination: supportURL) {
                    rowLabel(
                        title: "Contact beta support",
                        detail: "Tell us what happened",
                        icon: "envelope.fill"
                    )
                }
                .foregroundStyle(SignalTheme.accent)
                .accessibilityIdentifier("account-support.contact")
            } else {
                rowLabel(
                    title: "Beta support",
                    detail: "Support contact isn’t configured for this build",
                    icon: "envelope.badge.shield.half.filled"
                )
                .foregroundStyle(SignalTheme.textSecondary)
            }
        }
    }

    private func externalRow(
        title: String,
        detail: String,
        icon: String,
        destination: URL?
    ) -> some View {
        Group {
            if let destination {
                Link(destination: destination) {
                    rowLabel(title: title, detail: detail, icon: icon)
                }
                .foregroundStyle(SignalTheme.accent)
            } else {
                rowLabel(
                    title: title,
                    detail: "Help link isn’t configured for this build",
                    icon: icon
                )
                .foregroundStyle(SignalTheme.textSecondary)
            }
        }
    }

    private func documentRow(
        title: String,
        detail: String,
        icon: String,
        destination: URL?,
        accessibilityIdentifier: String
    ) -> some View {
        externalRow(
            title: title,
            detail: destination == nil
                ? "Link isn’t configured for this build"
                : detail,
            icon: icon,
            destination: destination
        )
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func rowLabel(
        title: String,
        detail: String,
        icon: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(SignalTheme.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SignalTheme.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .layoutPriority(1)
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .foregroundStyle(SignalTheme.divider)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 10)
        .signalTappableRow()
    }

    private var versionNote: some View {
        let version = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "—"
        let build = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleVersion"
        ) as? String ?? "—"
        return Text("Version \(version) (\(build))")
            .font(.caption2)
            .foregroundStyle(SignalTheme.textSecondary)
    }
}

struct DeleteAccountView: View {
    private enum DeleteAccountState: Equatable {
        case reauthenticate
        case deleting
        case failed(String)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var state: DeleteAccountState = .reauthenticate

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch state {
                    case .reauthenticate:
                        reauthenticateContent
                    case .deleting:
                        deletingContent
                    case .failed(let message):
                        failedContent(message: message)
                    }
                }
                .padding(20)
            }
            .signalScreenChrome()
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(state == .deleting)
                }
            }
        }
        .interactiveDismissDisabled(state == .deleting)
    }

    private var reauthenticateContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Confirm with Apple")
                .font(
                    SignalTheme.displayFont(
                        size: 25,
                        relativeTo: .title2
                    )
                )
            Text(
                "For your protection, Apple requires a fresh sign-in before GameTime can delete this account."
            )
            .foregroundStyle(SignalTheme.textSecondary)
            NativeAppleReauthenticationButton { result in
                handleReauthentication(result)
            }
        }
    }

    private var deletingContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            ProgressView()
            Text("Deleting your account…")
                .font(.title3.weight(.semibold))
            Text("Revoking Apple access, removing server data, and clearing this phone.")
                .foregroundStyle(SignalTheme.textSecondary)
        }
    }

    private func failedContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Deletion didn’t finish", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SignalTheme.accent)
            Text(message)
                .foregroundStyle(SignalTheme.textSecondary)
            Button("Try again") {
                state = .reauthenticate
            }
            .buttonStyle(SignalSecondaryButtonStyle())
            if let supportURL = model.configuration.supportMailtoURL {
                Link("Contact beta support", destination: supportURL)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SignalTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
    }

    private func handleReauthentication(
        _ result: Result<AppleIdentity, Error>
    ) {
        switch result {
        case .failure(let error):
            state = .failed(error.localizedDescription)
            SignalAccessibility.announce("Account deletion failed.")
        case .success(let identity):
            state = .deleting
            SignalAccessibility.announce("Deleting your account…")
            Task {
                do {
                    _ = try await model.deleteAccount(with: identity)
                    SignalAccessibility.announce("Account deleted.")
                    dismiss()
                } catch is CancellationError {
                    state = .reauthenticate
                } catch {
                    state = .failed(error.localizedDescription)
                    SignalAccessibility.announce(
                        "Account deletion failed."
                    )
                }
            }
        }
    }
}

struct PublicSupportLinksView: View {
    let privacyURL: URL?
    let betaTermsURL: URL?
    let supportMailtoURL: URL?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 8) {
            policyLinks
            if let supportMailtoURL {
                publicLink("Contact support", destination: supportMailtoURL)
            }
        }
        .font(.footnote.weight(.semibold))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var policyLinks: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 8) {
                policyLinkContents
            }
        } else {
            HStack(spacing: 16) {
                policyLinkContents
            }
        }
    }

    @ViewBuilder
    private var policyLinkContents: some View {
        if let privacyURL {
            publicLink("Privacy Policy", destination: privacyURL)
        }
        if let betaTermsURL {
            publicLink("Beta Terms", destination: betaTermsURL)
        }
    }

    private func publicLink(
        _ title: String,
        destination: URL
    ) -> some View {
        Link(title, destination: destination)
            .foregroundStyle(SignalTheme.accent)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
    }
}
