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
                    DaybreakSectionLabel(text: "Eligibility")
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
                                "Handle \(profile.handle), read only"
                            )
                    }
                    Spacer(minLength: 0)
                }
                Divider()
                    .overlay(CompetitiveTrustTheme.border)
                    .padding(.vertical, 12)
                settingRow("Frozen challenge timezone", profile.timezone)
                settingRow("Handle changes", "Locked")
            }
        }
    }

    private var healthSection: some View {
        Group {
            DaybreakSectionLabel(text: "Health access")
            DaybreakCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Apple Health steps", systemImage: "heart.fill")
                            .font(
                                CompetitiveTrustTheme.displayFont(
                                    size: 18,
                                    relativeTo: .headline
                                )
                            )
                        Spacer(minLength: 8)
                        TrustStatusPill(
                            text: diagnosticStatus,
                            kind: personalStore.latestDiagnostic?.isTrusted == true
                                ? .verified
                                : .action
                        )
                    }
                    if let diagnostic = personalStore.latestDiagnostic {
                        Text(
                            "Last diagnostic \(diagnostic.performedAt.formatted(.relative(presentation: .named))) · \(diagnostic.positiveTrustedSampleCount) trusted samples"
                        )
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    } else {
                        Text(
                            "A trusted diagnostic is required before confirming a personal challenge."
                        )
                        .font(.caption)
                        .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                    }
                    Button("Run trusted diagnostic") {
                        Task {
                            _ = await personalStore.runDiagnostic(
                                timezone: model.profile?.timezone
                                    ?? TimeZone.current.identifier
                            )
                        }
                    }
                    .buttonStyle(TrustSecondaryButtonStyle())
                    .disabled(
                        personalStore.isRunningDiagnostic
                            || !personalStore.configuration.activitySyncEnabled
                    )
                    .accessibilityIdentifier("personal.diagnostic.run")
                    if !personalStore.configuration.activitySyncEnabled {
                        Text(
                            "This check is locked outside Staging and requires a supported physical iPhone for acceptance."
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
                            Text("Health and account boundaries")
                                .font(.body.weight(.semibold))
                            Text("What GameTime reads, sends, and keeps private")
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
            DaybreakSectionLabel(text: "Personal history")
            DaybreakCard {
                HStack(spacing: 0) {
                    historyMetric(
                        personalStore.challenges.count.formatted(),
                        "Total"
                    )
                    historyMetric(
                        (personalStore.openChallenge == nil ? 0 : 1).formatted(),
                        "Open"
                    )
                    historyMetric(
                        personalStore.history.count.formatted(),
                        "Completed"
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
                                ? "Return to your unchanged staging account."
                                : "Practice with personal-accountability fixtures."
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
            "Handle changes and avatar uploads aren’t available in this alpha."
        )
        .font(.caption2)
        .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 12)
    }

    private var diagnosticStatus: String {
        switch personalStore.latestDiagnostic?.status {
        case .trusted: "Trusted"
        case .noPositiveTrustedSample: "Needs positive sample"
        case .unavailable: "Unavailable"
        case .failed: "Needs attention"
        case .notRun, nil: "Not run"
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
                    title: "Owner-only personal records",
                    detail:
                        "Your frozen terms, progress, diagnostic state, result, and eligibility hold are readable only by you. Publishing results and clearing holds remain trusted-service operations.",
                    icon: "person.crop.circle.badge.checkmark"
                )
                privacyCard(
                    title: "Trusted steps, not raw health history",
                    detail:
                        "GameTime uses only first-party Apple-device step evidence from completed hourly intervals. Manual, third-party, and unknown-provenance entries are excluded; only the minimum signed metrics and coverage needed for assessment are sent.",
                    icon: "heart.text.square.fill"
                )
                privacyCard(
                    title: "Inconclusive means waived",
                    detail:
                        "Missing, quarantined, conflicting, or unresolved evidence is never treated as a miss. Confirmed GameTime outages waive without placing an eligibility hold.",
                    icon: "checkmark.shield.fill"
                )
                privacyCard(
                    title: "No social or payment surface",
                    detail:
                        "Your accountability experience is private and individual, with no live payment request.",
                    icon: "lock.fill"
                )
            }
            .padding(18)
        }
        .daybreakScreenChrome()
        .navigationTitle("Trust & privacy")
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
