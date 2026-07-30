import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.demoMode) private var demoMode

    var body: some View {
        List {
            if let profile = model.profile {
                Section {
                    HStack(spacing: 16) {
                        InitialsAvatar(
                            initials: profile.initials,
                            size: 64
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(profile.displayName)
                                .font(.title3.bold())
                            Text("@\(profile.handle)")
                                .foregroundStyle(.secondary)
                                .accessibilityLabel(
                                    "Handle \(profile.handle), read only"
                                )
                        }
                    }
                    .padding(.vertical, 8)

                    LabeledContent("Handle changes") {
                        Text("Locked")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Contest timezone") {
                        Text(profile.timezone)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(
                        "Initials are used in M8.1. Avatar uploads and handle changes are not available."
                    )
                }
                .listRowBackground(CompetitiveTrustTheme.raisedInk)
            }

            Section("Trust") {
                Button {
                    router.youPath.append(.trustAndPrivacy)
                } label: {
                    Label(
                        "Trust and privacy boundaries",
                        systemImage: "checkmark.shield"
                    )
                }
                .foregroundStyle(.primary)
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)

            if demoMode.isAvailable {
                Section {
                    if demoMode.isActive {
                        Button(action: demoMode.exit) {
                            Label(
                                "Exit demo mode",
                                systemImage: "arrow.backward.circle"
                            )
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("demo.exit")
                    } else {
                        Button(action: demoMode.enter) {
                            Label(
                                "Open demo mode",
                                systemImage: "play.circle"
                            )
                        }
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("demo.enter")
                    }
                } header: {
                    Text("Demo")
                } footer: {
                    Text(
                        demoMode.isActive
                            ? "Demo friends and challenges reset when you exit. Your staging account is unchanged."
                            : "Practice adding friends and creating challenges without changing Supabase."
                    )
                }
                .listRowBackground(CompetitiveTrustTheme.raisedInk)
            }

            #if DEBUG
            Section {
                Button {
                    router.youPath.append(.futureContestFixtures)
                } label: {
                    Label(
                        "Post-contest states",
                        systemImage: "wrench.and.screwdriver"
                    )
                }
                .foregroundStyle(.primary)
                .accessibilityIdentifier("debug.future-states")
            } header: {
                Text("Debug fixtures")
            } footer: {
                Text(
                    "Finalization, settlement, and disputes are fixture-only and are compiled out of Release routing."
                )
            }
            .listRowBackground(CompetitiveTrustTheme.raisedInk)
            #endif

            if !demoMode.isActive {
                Section {
                    Button(role: .destructive) {
                        Task { await model.signOut() }
                    } label: {
                        HStack {
                            Spacer()
                            if model.isMutating {
                                ProgressView()
                                    .accessibilityLabel("Signing out")
                            } else {
                                Text("Sign out")
                            }
                            Spacer()
                        }
                    }
                    .disabled(model.isMutating)
                    .accessibilityIdentifier("account.sign-out")
                }
                .listRowBackground(CompetitiveTrustTheme.raisedInk)
            }
        }
        .listStyle(.insetGrouped)
        .trustScreenBackground()
        .navigationTitle("You")
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
