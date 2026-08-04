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
                TestCommitmentDisclosure()
                healthSection
                if personalStore.eligibilityHoldActive {
                    DaybreakSectionLabel(text: "Account status")
                    PersonalEligibilityHoldCard(
                        hold: personalStore.eligibilityHold
                    )
                }
                privacySection
                historySection
                demoSection
                signOutControl
                availabilityNote
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
                                "Username \(profile.handle), can’t be changed yet"
                            )
                    }
                    Spacer(minLength: 0)
                }
                Divider()
                    .overlay(CompetitiveTrustTheme.border)
                    .padding(.vertical, 12)
                settingRow("Time zone", profile.timezone)
                settingRow("Username", "Can’t be changed yet")
            }
        }
    }

    private var healthSection: some View {
        Group {
            DaybreakSectionLabel(text: "Apple Health")
            DaybreakCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Steps", systemImage: "heart.fill")
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 18,
                                    relativeTo: .headline
                                )
                            )
                        Spacer(minLength: 8)
                        if personalStore.latestDiagnostic != nil {
                            TrustStatusPill(
                                text: diagnosticStatus,
                                kind: personalStore.latestDiagnostic?.isTrusted
                                    == true
                                    ? .verified
                                    : .action
                            )
                        }
                    }
                    Text(
                        "We look at the last day of steps to check that your iPhone or Apple Watch is recording them."
                    )
                    .font(.caption)
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    if let diagnostic = personalStore.latestDiagnostic {
                        Text(
                            "Last checked \(diagnostic.performedAt.formatted(.relative(presentation: .named))) · \(diagnostic.positiveTrustedSampleCount) step readings found"
                        )
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    }
                    if case .localStepsObserved(let probe) =
                        personalStore.healthReadiness
                    {
                        Text(
                            probe.sawTrustedDeviceSteps
                                ? "Found \(probe.positiveTrustedSampleCount) step readings from your Apple devices in the last \(probe.trustedHourCount) hours."
                                : "No steps from your Apple devices in the last \(probe.trustedHourCount) hours."
                        )
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                        .accessibilityIdentifier("personal.health.probe-result")
                    }
                    Button(
                        personalStore.isVerifyingHealthAccess
                            ? "Checking…"
                            : "Check Health connection"
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
                    if personalStore.configuration.attestedUploadEnabled,
                        personalStore.eligibilityHoldActive
                    {
                        Button(
                            personalStore.isRunningDiagnostic
                                ? "Reconnecting…"
                                : "Reconnect Health"
                        ) {
                            Task {
                                _ = await personalStore.runDiagnostic(
                                    timezone: model.profile?.timezone
                                        ?? TimeZone.current.identifier
                                )
                            }
                        }
                        .buttonStyle(TrustSecondaryButtonStyle())
                        .disabled(personalStore.isRunningDiagnostic)
                        .accessibilityIdentifier("personal.diagnostic.run")
                    }
                    if !personalStore.configuration.activitySyncEnabled {
                        Text(
                            "Health connection checks aren’t available yet."
                        )
                        .font(.caption2)
                        .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                    } else if !personalStore.configuration.attestedUploadEnabled {
                        Text(
                            "Your steps stay on your phone and aren’t sent to GameTime."
                        )
                        .font(.caption2)
                        .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
                    }
                }
            }
        }
    }

    private var privacySection: some View {
        Group {
            DaybreakSectionLabel(text: "Privacy")
            DaybreakCard {
                Button {
                    router.youPath.append(.trustAndPrivacy)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(CompetitiveTrustTheme.mintInk)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Your privacy")
                                .font(.body.weight(.semibold))
                            Text("What we read, what we send, and what stays on your phone")
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
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("privacy.open")
            }
        }
    }

    private var historySection: some View {
        Group {
            DaybreakSectionLabel(text: "Your history")
            DaybreakCard {
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

    @ViewBuilder
    private var signOutControl: some View {
        if !demoMode.isActive {
            Button(role: .destructive) {
                Task { await model.signOut() }
            } label: {
                Group {
                    if model.isMutating {
                        ProgressView().accessibilityLabel("Signing out")
                    } else {
                        Text("Sign out")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(TrustCompactButtonStyle(tone: .quiet))
            .disabled(model.isMutating)
            .accessibilityIdentifier("account.sign-out")
        }
    }

    private var availabilityNote: some View {
        Text(
            "You can’t change your username or add a photo yet."
        )
        .font(.caption2)
        .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
    }

    private var diagnosticStatus: String {
        switch personalStore.latestDiagnostic?.status {
        case .trusted: "Connected"
        case .noPositiveTrustedSample: "No steps found"
        case .unavailable: "Unavailable"
        case .failed: "Needs attention"
        case .notRun, nil: "Not checked"
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
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                TestCommitmentDisclosure()
                privacyCard(
                    title: "Only you can see your challenges",
                    detail:
                        "Your goal, your progress, and how each week turned out are yours alone. Nobody else can look them up.",
                    icon: "person.crop.circle.badge.checkmark"
                )
                privacyCard(
                    title: "We read steps, not your health history",
                    detail:
                        "We only read step counts recorded by your iPhone or Apple Watch. Steps you typed in yourself or that came from another app aren’t counted, and nothing else in Apple Health is ever read.",
                    icon: "heart.text.square.fill"
                )
                privacyCard(
                    title: "If we can’t see your data, you don’t lose",
                    detail:
                        "When steps go missing or don’t add up, the week doesn’t count — it’s never treated as a miss. If the problem is on our end, that’s on us.",
                    icon: "checkmark.shield.fill"
                )
                privacyCard(
                    title: "Nothing social, nothing to pay",
                    detail:
                        "This is just between you and your goal. There’s nobody else in here, and there’s nothing to pay.",
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
