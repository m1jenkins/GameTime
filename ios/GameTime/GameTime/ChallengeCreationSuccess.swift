import SwiftUI

/// Quiet acknowledgement after a challenge is saved. It states the goal once
/// and returns home; it does not recap the agreement.
struct ChallengeCreationSuccess: View {
    @Bindable var store: ChallengeV1Store
    let challengeID: UUID
    let onGoHome: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @State private var showingGoal = false
    @ScaledMetric(relativeTo: .largeTitle) private var headingSize: CGFloat = 30
    @AccessibilityFocusState private var headingFocused: Bool

    init(store: ChallengeV1Store, challengeID: UUID, onGoHome: @escaping () -> Void = {}) {
        self.store = store
        self.challengeID = challengeID
        self.onGoHome = onGoHome
    }

    private var row: ChallengeV1? { store.challenges.first { $0.id == challengeID } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(SignalCreationTheme.accent)
                    .accessibilityHidden(true)
                Text(ChallengeCreationSuccessCopy.title)
                    .font(.system(size: headingSize, weight: .bold)).tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($headingFocused)
                    .accessibilityIdentifier("beta.create.saved")
                if let row {
                    Text(ChallengeCreationSuccessCopy.summary(row, locale: locale))
                        .font(.subheadline)
                        .foregroundStyle(SignalCreationTheme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("beta.create.saved.summary")
                    if let stake = ChallengeCreationSuccessCopy.stake(row) {
                        Text(stake)
                            .font(.caption)
                            .foregroundStyle(SignalCreationTheme.textSecondary)
                            .accessibilityIdentifier("beta.create.saved.stake")
                    }
                }
            }
            .padding(.horizontal, SignalCreationTheme.contentInset)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(SignalCreationTheme.canvas)
        .foregroundStyle(SignalCreationTheme.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            SignalCreationChrome(title: "", showsBack: false, back: {}, close: { dismiss() })
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 4) {
                Button {
                    onGoHome()
                    dismiss()
                } label: {
                    HStack(spacing: 10) {
                        Text("Go to Home")
                        Image(systemName: "arrow.right").accessibilityHidden(true)
                    }
                }
                .buttonStyle(SignalCreationPrimaryStyle())
                .accessibilityIdentifier("beta.create.home")
                Button { showingGoal = true } label: {
                    Text("View goal").font(.subheadline.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(SignalCreationTheme.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityIdentifier("beta.create.detail")
            }
            .padding(.horizontal, SignalCreationTheme.contentInset)
            .padding(.top, 12)
            .padding(.bottom, 6)
            .background(SignalCreationTheme.canvas)
        }
        .navigationDestination(isPresented: $showingGoal) {
            LiveGoalDetail(store: store, id: challengeID)
        }
        .onAppear { headingFocused = true }
    }
}

@MainActor enum ChallengeCreationSuccessCopy {
    static let title = "Challenge locked in."

    static func summary(_ row: ChallengeV1, locale: Locale = .current) -> String {
        LiveChallengePresentation.title(row, locale: locale) + " · " + dates(row, locale: locale)
    }

    static func stake(_ row: ChallengeV1) -> String? {
        stakeLine(cents: row.config.amountCents)
    }

    static func stakeLine(cents: Int) -> String? {
        guard cents > 0 else { return nil }
        return "\(LiveChallengePresentation.money(cents)) simulated · fee $0"
    }

    static func dates(_ row: ChallengeV1, locale: Locale = .current) -> String {
        let zone = TimeZone(identifier: row.config.timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        let start = row.config.startsAt.date
        let end = row.config.endsAt.date.addingTimeInterval(-1)
        let sameYear = calendar.component(.year, from: start) == calendar.component(.year, from: end)
        let sameDay = calendar.isDate(start, inSameDayAs: end)
        if sameDay {
            return formatted(start, template: sameYear ? "MMMd" : "yMMMd", zone: zone, locale: locale)
        }
        let sameMonth = sameYear && calendar.component(.month, from: start) == calendar.component(.month, from: end)
        if sameMonth {
            let startText = formatted(start, template: "MMMd", zone: zone, locale: locale)
            let endDay = formatted(end, template: "d", zone: zone, locale: locale)
            return startText + "–" + endDay
        }
        let template = sameYear ? "MMMd" : "yMMMd"
        return formatted(start, template: template, zone: zone, locale: locale)
            + "–" + formatted(end, template: template, zone: zone, locale: locale)
    }

    private static func formatted(_ date: Date, template: String, zone: TimeZone, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}
