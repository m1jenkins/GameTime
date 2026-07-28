import SwiftUI

struct YouView: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router

    private func dollars(_ cents: Int) -> String {
        (Double(cents) / 100).formatted(
            .currency(code: "USD").precision(.fractionLength(0))
        )
    }

    var body: some View {
        GlassArenaScreenScaffold(
            screen: .today,
            identifier: "screen.you",
            spacing: 13
        ) {
            Text("You")
                .font(GlassArenaFont.display(33, .heavy))
                .foregroundStyle(GlassArena.ink)
                .padding(.horizontal, 4)

            if let profile = model.profile {
                profileCard(profile)
            }

            charityCard

            settingsCard

            healthPanel

            signOutButton
        }
    }

    // MARK: Profile

    private func profileCard(_ profile: UserProfile) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 8) {
                GlassAvatar(
                    initials: profile.initials,
                    size: 72,
                    side: .you
                )
                Text(profile.displayName)
                    .font(GlassArenaFont.display(24, .heavy))
                    .foregroundStyle(GlassArena.ink)
                Text("@\(profile.handle)")
                    .font(GlassArenaFont.text(14))
                    .foregroundStyle(GlassArena.mutedLight)
                    .accessibilityLabel(
                        "Handle \(profile.handle), read only"
                    )
            }

            HStack(spacing: 0) {
                stat(
                    value: "\(model.record.won)",
                    label: "Won",
                    tint: GlassArena.teal900
                )
                divider
                stat(
                    value: "\(model.record.lost)",
                    label: "Lost",
                    tint: GlassArena.mutedLighter
                )
                divider
                stat(
                    value: dollars(model.givenCents),
                    label: "Given",
                    tint: GlassArena.amber700
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 20)
        .glassPane(.hero, cornerRadius: 32)
    }

    private var divider: some View {
        Rectangle()
            .fill(GlassArena.hairline.opacity(0.5))
            .frame(width: 1, height: 30)
    }

    private func stat(
        value: String,
        label: String,
        tint: Color
    ) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(GlassArenaFont.display(23, .heavy))
                .foregroundStyle(tint)
            Text(label.uppercased())
                .font(GlassArenaFont.text(11, .bold))
                .tracking(0.7)
                .foregroundStyle(GlassArena.mutedLight)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }

    // MARK: Charity

    private var charityCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "heart.text.square")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(GlassArena.amber700)
                .frame(width: 50, height: 50)
                .background(
                    RoundedRectangle(cornerRadius: 17, style: .continuous)
                        .fill(GlassArena.amber400.opacity(0.20))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Because of you and your friends")
                    .font(GlassArenaFont.text(15, .bold))
                    .foregroundStyle(GlassArena.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    model.charityTotalCents == 0
                        ? "Settle a duel and the total starts here."
                        : "\(dollars(model.charityTotalCents)) has gone to the charities you picked."
                )
                .font(GlassArenaFont.text(13))
                .foregroundStyle(GlassArena.mutedLight)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .glassPane(.standard, cornerRadius: 28)
        .accessibilityElement(children: .combine)
    }

    // MARK: Settings

    private var settingsCard: some View {
        VStack(spacing: 12) {
            TermRow(
                label: "Handle changes",
                value: "Locked",
                emphasis: GlassArena.inkSecondary
            )
            Rectangle()
                .fill(GlassArena.hairline.opacity(0.4))
                .frame(height: 1)
            TermRow(
                label: "Duel timezone",
                value: model.profile?.timezone ?? "UTC",
                emphasis: GlassArena.inkSecondary
            )
            Rectangle()
                .fill(GlassArena.hairline.opacity(0.4))
                .frame(height: 1)
            Button {
                router.youPath.append(.trustAndPrivacy)
            } label: {
                HStack {
                    Text("What GameTime can and can't do")
                        .font(GlassArenaFont.text(14, .semibold))
                        .foregroundStyle(GlassArena.ink)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GlassArena.hairline)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("you.trust-and-privacy")

            #if DEBUG
            Rectangle()
                .fill(GlassArena.hairline.opacity(0.4))
                .frame(height: 1)
            Button {
                router.youPath.append(.futureContestFixtures)
            } label: {
                HStack {
                    Text("Post-duel states (debug)")
                        .font(GlassArenaFont.text(14, .semibold))
                        .foregroundStyle(GlassArena.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(GlassArena.hairline)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("debug.future-states")
            #endif
        }
        .padding(18)
        .glassPane(.standard, cornerRadius: 28)
    }

    // MARK: Health disclosure

    private var healthPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Where the numbers come from")
                    .font(GlassArenaFont.text(14, .bold))
            }
            .foregroundStyle(GlassArena.teal950)

            Text(
                "Every duel reads from Apple Health. A number you type in never counts, for you or against you."
            )
            .font(GlassArenaFont.text(13))
            .foregroundStyle(GlassArena.teal950.opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(GlassArena.teal700.opacity(0.14))
                .overlay {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(
                            GlassArena.teal700.opacity(0.28),
                            lineWidth: 1
                        )
                }
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: Sign out

    private var signOutButton: some View {
        Button {
            Task { await model.signOut() }
        } label: {
            if model.isMutating {
                ProgressView()
                    .tint(GlassArena.destructive)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Signing out")
            } else {
                Text("Sign out")
                    .font(GlassArenaFont.text(15, .semibold))
                    .foregroundStyle(GlassArena.destructive)
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 16)
        .disabled(model.isMutating)
        .accessibilityIdentifier("account.sign-out")
    }
}

// MARK: - Trust and privacy

struct TrustAndPrivacyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            GlassNavRow(backTitle: "You", back: { dismiss() }) {
                EmptyView()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("What's switched on")
                        .font(GlassArenaFont.display(28, .heavy))
                        .foregroundStyle(GlassArena.ink)
                        .padding(.horizontal, 4)

                    GlassCardSection(title: "Working now") {
                        bullet(
                            "Sign in with Apple, exchanged with a one-time nonce",
                            systemImage: "apple.logo"
                        )
                        bullet(
                            "Friends found by exact handle only",
                            systemImage: "at"
                        )
                        bullet(
                            "Duel terms freeze on send, and retries stay yours",
                            systemImage: "lock.doc"
                        )
                    }

                    GlassCardSection(
                        title: "Deliberately off",
                        footnote:
                            "Each of these comes back only once its evidence, disclosure and lifecycle boundaries are finished.",
                        tier: .recessed
                    ) {
                        bullet("Health and location permissions", systemImage: "heart")
                        bullet("Evidence submission and App Attest", systemImage: "checkmark.shield")
                        bullet("Push notifications", systemImage: "bell")
                        bullet("Settlement and disputes", systemImage: "scalemass")
                        bullet("Account deletion", systemImage: "trash")
                    }
                }
                .padding(.horizontal, GlassArenaLayout.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, GlassArenaLayout.scrollBottomInset)
                .frame(maxWidth: GlassArenaMetrics.contentCap)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassArenaBackground(.today)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func bullet(
        _ text: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 10) {
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

#if DEBUG
struct FutureContestFixturesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            GlassNavRow(backTitle: "You", back: { dismiss() }) {
                EmptyView()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    Text("Post-duel states")
                        .font(GlassArenaFont.display(28, .heavy))
                        .foregroundStyle(GlassArena.ink)
                        .padding(.horizontal, 4)

                    card(
                        title: "Result frozen",
                        detail:
                            "Scoring is complete. This fixture does not call a live finalization API.",
                        icon: "checkmark.seal.fill",
                        tint: GlassArena.teal800
                    )
                    card(
                        title: "Pledge awaiting settlement",
                        detail: "No payment or donation action exists yet.",
                        icon: "heart.text.square",
                        tint: GlassArena.amber700
                    )
                    card(
                        title: "Evidence under review",
                        detail:
                            "Visual only. No dispute mutation is routed from the product app.",
                        icon: "exclamationmark.bubble",
                        tint: GlassArena.violet600
                    )
                }
                .padding(.horizontal, GlassArenaLayout.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, GlassArenaLayout.scrollBottomInset)
                .frame(maxWidth: GlassArenaMetrics.contentCap)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .glassArenaBackground(.today)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func card(
        title: String,
        detail: String,
        icon: String,
        tint: Color
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(0.16)))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(GlassArenaFont.text(15, .bold))
                    .foregroundStyle(GlassArena.ink)
                Text(detail)
                    .font(GlassArenaFont.text(13))
                    .foregroundStyle(GlassArena.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .glassPane(.standard, cornerRadius: 28)
        .accessibilityElement(children: .combine)
    }
}
#endif
