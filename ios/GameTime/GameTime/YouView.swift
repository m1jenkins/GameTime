import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @Environment(PersonalAccountabilityStore.self) private var personalStore
    @Environment(AppRouter.self) private var router
    @Environment(\.demoMode) private var demoMode

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                profileCard
                healthSection
                settingsSection
                demoSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .daybreakScreenChrome()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var profileCard: some View {
        if let profile = model.profile {
            DaybreakCard {
                HStack(spacing: 15) {
                    InitialsAvatar(
                        initials: profile.initials,
                        size: 60,
                        color: CompetitiveTrustTheme.coral
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text(profile.displayName)
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 23,
                                    relativeTo: .title2
                                )
                            )
                            .tracking(-0.65)
                        Text("@\(profile.handle)")
                            .font(.subheadline)
                            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                            .accessibilityLabel(
                                "Username \(profile.handle)"
                            )
                    }
                    Spacer(minLength: 0)
                }
                Divider()
                    .overlay(CompetitiveTrustTheme.border)
                    .padding(.vertical, 12)
                settingRow("Time zone", profile.timezone)
                Divider()
                    .overlay(CompetitiveTrustTheme.border)
                    .padding(.vertical, 12)
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
    }

    private var healthSection: some View {
        Group {
            DaybreakSectionLabel(text: "Apple Health")
            DaybreakCard {
                VStack(alignment: .leading, spacing: 12) {
                    Label(
                        personalStore.healthReadiness.permitsCreation
                            ? "Health connected"
                            : "Steps",
                        systemImage: personalStore.healthReadiness.permitsCreation
                            ? "checkmark.circle.fill"
                            : "heart.fill"
                    )
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 18,
                                relativeTo: .headline
                            )
                        )
                    Text(
                        personalStore.healthReadiness.permitsCreation
                            ? "GameTime can update your challenge automatically from your Apple Health step history."
                            : "Connect Apple Health so GameTime can update your challenge automatically from your step history."
                    )
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)

                    if !personalStore.healthReadiness.permitsCreation {
                        Button(
                            personalStore.isVerifyingHealthAccess
                                ? "Connecting…"
                                : "Connect Apple Health"
                        ) {
                            Task {
                                _ = await personalStore.verifyHealthAccess(
                                    timezone: model.profile?.timezone
                                        ?? TimeZone.current.identifier
                                )
                            }
                        }
                        .buttonStyle(TrustSecondaryButtonStyle())
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
                        .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                    }
                }
            }
        }
    }

    private var settingsSection: some View {
        Group {
            DaybreakSectionLabel(text: "Settings")
            DaybreakCard {
                VStack(spacing: 0) {
                    Button {
                        router.youPath.append(.trustAndPrivacy)
                    } label: {
                        settingsNavigationRow(
                            title: "Your privacy",
                            detail: "What we read, what we send, and what stays on your phone",
                            icon: "checkmark.shield.fill",
                            iconColor: CompetitiveTrustTheme.mintInk
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("privacy.open")

                    Divider().overlay(CompetitiveTrustTheme.border)

                    Button {
                        router.youPath.append(.accountSupport)
                    } label: {
                        settingsNavigationRow(
                            title: "Account & support",
                            detail: "Support, documents, sign out, and account deletion",
                            icon: "person.crop.circle.badge.questionmark",
                            iconColor: CompetitiveTrustTheme.coral
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
                        CompetitiveTrustTheme.secondaryText
                    )
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .foregroundStyle(CompetitiveTrustTheme.guide)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var demoSection: some View {
        if demoMode.isAvailable {
            DaybreakSectionLabel(text: "Demo")
            DaybreakCard {
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
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    }
                    Spacer(minLength: 8)
                    Button(demoMode.isActive ? "Exit" : "Open") {
                        demoMode.isActive ? demoMode.exit() : demoMode.enter()
                    }
                    .buttonStyle(TrustCompactButtonStyle())
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
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private func historyMetric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 21,
                        relativeTo: .title3
                    )
                )
            Text(label)
                .font(.caption)
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
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
            .padding(18)
        }
        .daybreakScreenChrome()
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyCard(
        title: String,
        detail: String,
        icon: String
    ) -> some View {
        DaybreakCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(CompetitiveTrustTheme.coral)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(
                            CompetitiveTrustTheme.displayFont(
                                size: 18,
                                relativeTo: .headline
                            )
                        )
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
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
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .daybreakScreenChrome()
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
                "Your profile, challenges, social links, pending requests, Health snapshots, and sign-in will be removed. Integrity records may remain without your name. Your beta Stripe customer and saved payment method will also be deleted. This can’t be undone."
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
            DaybreakSectionLabel(text: "Help & documents")
            DaybreakCard {
                VStack(spacing: 0) {
                    externalRow(
                        title: "Apple Health help",
                        detail: "Manage step access and Health permissions",
                        icon: "heart.text.square.fill",
                        destination: URL(string: "https://support.apple.com/en-us/HT204351")
                    )
                    Divider().overlay(CompetitiveTrustTheme.border)
                    supportRow
                    Divider().overlay(CompetitiveTrustTheme.border)
                    documentRow(
                        title: "Privacy Policy",
                        detail: "How GameTime handles your data",
                        icon: "hand.raised.fill",
                        destination: model.configuration.privacyPolicyURL,
                        accessibilityIdentifier:
                            "account-support.privacy-policy"
                    )
                    Divider().overlay(CompetitiveTrustTheme.border)
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
            DaybreakSectionLabel(text: "Account")
            DaybreakCard {
                VStack(spacing: 12) {
                    if !demoMode.isActive {
                        Button(role: .destructive) {
                            Task { await model.signOut() }
                        } label: {
                            Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(TrustSecondaryButtonStyle())
                        .disabled(model.isMutating)
                        .accessibilityIdentifier("account-support.sign-out")
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete account", systemImage: "person.crop.circle.badge.minus")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
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
                .accessibilityIdentifier("account-support.contact")
            } else {
                rowLabel(
                    title: "Beta support",
                    detail: "Support contact isn’t configured for this build",
                    icon: "envelope.badge.shield.half.filled"
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
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
            } else {
                rowLabel(
                    title: title,
                    detail: "Help link isn’t configured for this build",
                    icon: icon
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
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
                .foregroundStyle(CompetitiveTrustTheme.coral)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .foregroundStyle(CompetitiveTrustTheme.guide)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 10)
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
            .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
    }
}

struct DeleteAccountView: View {
    private enum State: Equatable {
        case reauthenticate
        case deleting
        case failed(String)
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var state: State = .reauthenticate

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
            .daybreakScreenChrome()
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(state == .deleting)
                }
            }
        }
    }

    private var reauthenticateContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Confirm with Apple")
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 25,
                        relativeTo: .title2
                    )
                )
            Text(
                "For your protection, Apple requires a fresh sign-in before GameTime can delete this account."
            )
            .foregroundStyle(CompetitiveTrustTheme.secondaryText)
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
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
    }

    private func failedContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Deletion didn’t finish", systemImage: "exclamationmark.triangle.fill")
                .font(.title3.weight(.semibold))
                .foregroundStyle(CompetitiveTrustTheme.coral)
            Text(message)
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
            Button("Try again") {
                state = .reauthenticate
            }
            .buttonStyle(TrustSecondaryButtonStyle())
            if let supportURL = model.configuration.supportMailtoURL {
                Link("Contact beta support", destination: supportURL)
                    .font(.subheadline.weight(.semibold))
            }
        }
    }

    private func handleReauthentication(
        _ result: Result<AppleIdentity, Error>
    ) {
        switch result {
        case .failure(let error):
            state = .failed(error.localizedDescription)
        case .success(let identity):
            state = .deleting
            Task {
                do {
                    _ = try await model.deleteAccount(with: identity)
                    dismiss()
                } catch is CancellationError {
                    state = .reauthenticate
                } catch {
                    state = .failed(error.localizedDescription)
                }
            }
        }
    }
}

struct PublicSupportLinksView: View {
    let privacyURL: URL?
    let betaTermsURL: URL?
    let supportMailtoURL: URL?

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 16) {
                if let privacyURL {
                    Link("Privacy Policy", destination: privacyURL)
                }
                if let betaTermsURL {
                    Link("Beta Terms", destination: betaTermsURL)
                }
            }
            if let supportMailtoURL {
                Link("Contact support", destination: supportMailtoURL)
            }
        }
        .font(.footnote.weight(.semibold))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
    }
}
