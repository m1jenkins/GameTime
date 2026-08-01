import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.demoMode) private var demoMode

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 11) {
                profileCard
                accountSection
                historySection
                demoSection
                debugSection
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
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 13,
                                    relativeTo: .subheadline
                                )
                            )
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                            .accessibilityLabel(
                                "Handle \(profile.handle), read only"
                            )
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if let profile = model.profile {
            DaybreakSectionLabel(text: "Account")
            DaybreakCard {
                VStack(spacing: 0) {
                    settingRow(
                        title: "Contest timezone",
                        value: profile.timezone
                    )
                    Divider()
                        .overlay(CompetitiveTrustTheme.border)
                    settingRow(
                        title: "Handle changes",
                        value: "Locked"
                    )
                    Divider()
                        .overlay(CompetitiveTrustTheme.border)
                    Button {
                        router.youPath.append(.trustAndPrivacy)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.shield")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(
                                    CompetitiveTrustTheme.mintInk
                                )
                                .frame(width: 22)
                                .accessibilityHidden(true)
                            Text("Trust and privacy boundaries")
                                .font(
                                    CompetitiveTrustTheme.uiFont(
                                        size: 15,
                                        relativeTo: .body,
                                        weight: .semibold
                                    )
                                )
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(
                                    CompetitiveTrustTheme.guide
                                )
                                .accessibilityHidden(true)
                        }
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func settingRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 15,
                        relativeTo: .body,
                        weight: .semibold
                    )
                )
            Spacer(minLength: 8)
            Text(value)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 13.5,
                        relativeTo: .subheadline
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }

    private var historySection: some View {
        Group {
            DaybreakSectionLabel(text: "Challenge history")
            DaybreakCard {
                VStack(alignment: .leading, spacing: 14) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 0) {
                            historyMetric(
                                value: model.contests.count.formatted(),
                                label: "Total"
                            )
                            historyMetric(
                                value: liveChallengeCount.formatted(),
                                label: "Live now"
                            )
                            historyMetric(
                                value: finishedChallengeCount.formatted(),
                                label: "Finished"
                            )
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            historyMetric(
                                value: model.contests.count.formatted(),
                                label: "Total"
                            )
                            historyMetric(
                                value: liveChallengeCount.formatted(),
                                label: "Live now"
                            )
                            historyMetric(
                                value: finishedChallengeCount.formatted(),
                                label: "Finished"
                            )
                        }
                    }

                    HStack(spacing: 4) {
                        if model.contests.isEmpty {
                            Capsule()
                                .fill(CompetitiveTrustTheme.rail)
                                .frame(height: 6)
                        } else {
                            ForEach(model.contests.prefix(9)) { contest in
                                Capsule()
                                    .fill(historyColor(for: contest.status))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 6)
                                    .accessibilityHidden(true)
                            }
                        }
                    }

                    Text(
                        model.contests.isEmpty
                            ? "Your accepted challenges will collect here."
                            : "Coral is live, gold is upcoming, and green is finished."
                    )
                    .font(
                        CompetitiveTrustTheme.uiFont(
                            size: 11.5,
                            relativeTo: .caption
                        )
                    )
                    .foregroundStyle(CompetitiveTrustTheme.secondaryText)
                }
            }
        }
    }

    private func historyMetric(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(
                    CompetitiveTrustTheme.displayFont(
                        size: 20,
                        relativeTo: .title3
                    )
                )
            Text(label)
                .font(
                    CompetitiveTrustTheme.uiFont(
                        size: 11.5,
                        relativeTo: .caption
                    )
                )
                .foregroundStyle(CompetitiveTrustTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var liveChallengeCount: Int {
        model.contests.filter { $0.status == .active }.count
    }

    private var finishedChallengeCount: Int {
        model.contests.filter { $0.status == .finalized }.count
    }

    private func historyColor(for status: ContestStatus) -> Color {
        switch status {
        case .active:
            CompetitiveTrustTheme.coral
        case .pending:
            CompetitiveTrustTheme.sun
        case .finalized:
            CompetitiveTrustTheme.mint
        case .cancelled:
            CompetitiveTrustTheme.rail
        }
    }

    @ViewBuilder
    private var demoSection: some View {
        if demoMode.isAvailable {
            DaybreakSectionLabel(text: "Demo")
            if demoMode.isActive {
                demoCard(
                    title: "Exit demo mode",
                    detail: "Return to your unchanged staging account.",
                    buttonTitle: "Exit",
                    identifier: "demo.exit",
                    action: demoMode.exit
                )
            } else {
                demoCard(
                    title: "Open demo mode",
                    detail: "Practice without changing your account.",
                    buttonTitle: "Open",
                    identifier: "demo.enter",
                    action: demoMode.enter
                )
            }
        }
    }

    private func demoCard(
        title: String,
        detail: String,
        buttonTitle: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        DaybreakCard {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 15,
                                relativeTo: .body,
                                weight: .semibold
                            )
                        )
                    Text(detail)
                        .font(
                            CompetitiveTrustTheme.uiFont(
                                size: 11.5,
                                relativeTo: .caption
                            )
                        )
                        .foregroundStyle(
                            CompetitiveTrustTheme.secondaryText
                        )
                }
                Spacer(minLength: 8)
                Button(buttonTitle, action: action)
                    .buttonStyle(TrustCompactButtonStyle())
                    .accessibilityIdentifier(identifier)
            }
        }
    }

    @ViewBuilder
    private var debugSection: some View {
        #if DEBUG
        DaybreakSectionLabel(text: "Debug fixtures")
        DaybreakCard {
            Button {
                router.youPath.append(.futureContestFixtures)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "wrench.and.screwdriver")
                        .foregroundStyle(CompetitiveTrustTheme.sunInk)
                        .frame(width: 22)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Post-contest states")
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 15,
                                    relativeTo: .body,
                                    weight: .semibold
                                )
                            )
                        Text("Fixture-only finalization and review states")
                            .font(
                                CompetitiveTrustTheme.uiFont(
                                    size: 11.5,
                                    relativeTo: .caption
                                )
                            )
                            .foregroundStyle(
                                CompetitiveTrustTheme.secondaryText
                            )
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(CompetitiveTrustTheme.guide)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("debug.future-states")
        }
        #endif
    }

    @ViewBuilder
    private var signOutControl: some View {
        if !demoMode.isActive {
            Button(role: .destructive) {
                Task { await model.signOut() }
            } label: {
                Group {
                    if model.isMutating {
                        ProgressView()
                            .accessibilityLabel("Signing out")
                    } else {
                        Text("Sign out")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(
                TrustCompactButtonStyle(tone: .quiet)
            )
            .disabled(model.isMutating)
            .accessibilityIdentifier("account.sign-out")
            .padding(.top, 3)
        }
    }

    private var availabilityNote: some View {
        Text(
            "Handle changes and avatar uploads aren’t available in this alpha."
        )
        .font(
            CompetitiveTrustTheme.uiFont(
                size: 11,
                relativeTo: .caption2
            )
        )
        .foregroundStyle(CompetitiveTrustTheme.tertiaryText)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
    }
}

struct TrustAndPrivacyView: View {
    var body: some View {
        List {
            Section("Included in staging") {
                Label(
                    "Apple ID-token exchange with a cryptographic nonce",
                    systemImage: "apple.logo"
                )
                Label(
                    "Exact-handle friendship discovery",
                    systemImage: "at"
                )
                Label(
                    "Immutable challenge terms and caller-scoped retries",
                    systemImage: "doc.text.magnifyingglass"
                )
                Label(
                    "Merged Apple-device steps with App Attest",
                    systemImage: "figure.walk"
                )
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)

            Section {
                Text("Background HealthKit delivery")
                Text("Core Location")
                Text("Push notifications")
                Text("Finalization, settlement, and disputes")
                Text("Account deletion")
            } header: {
                Text("Deliberately unavailable")
            } footer: {
                Text(
                    "Only device-recorded step counts are in this prototype. Manual and third-party HealthKit entries are excluded, and raw health data is never sent to analytics."
                )
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)
        }
        .trustScreenBackground()
        .navigationTitle("Trust & privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#if DEBUG
struct FutureContestFixturesView: View {
    var body: some View {
        List {
            Section("Finalized") {
                debugCard(
                    title: "Result frozen",
                    detail:
                        "Scoring is complete. This fixture does not invoke a live finalization API.",
                    icon: "checkmark.seal.fill",
                    color: CompetitiveTrustTheme.teal
                )
            }
            Section("Settlement") {
                debugCard(
                    title: "Pledge awaiting settlement",
                    detail:
                        "No payment or donation action exists in M8.1.",
                    icon: "heart.text.square",
                    color: CompetitiveTrustTheme.amber
                )
            }
            Section("Dispute") {
                debugCard(
                    title: "Evidence under review",
                    detail:
                        "This is visual-only. No live dispute mutation is routed from the product app.",
                    icon: "exclamationmark.bubble",
                    color: CompetitiveTrustTheme.amber
                )
            }
        }
        .trustScreenBackground()
        .navigationTitle("Future states")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func debugCard(
        title: String,
        detail: String,
        icon: String,
        color: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}
#endif
