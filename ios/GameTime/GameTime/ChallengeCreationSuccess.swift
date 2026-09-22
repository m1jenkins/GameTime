import SwiftUI

/// Quiet acknowledgement after a challenge is saved. It states the goal once
/// and returns home; it does not recap the agreement. An open friend lobby
/// isn't locked in: nobody has agreed yet, so it says what happens next.
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
    private var lobby: ChallengeV1? { row.flatMap { ChallengeCreationSuccessCopy.isOpenLobby($0) ? $0 : nil } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Image(systemName: lobby == nil ? "checkmark.circle.fill" : "envelope.circle.fill")
                    .font(.system(size: 28, weight: .regular))
                    .foregroundStyle(SignalCreationTheme.accent)
                    .accessibilityHidden(true)
                Text(lobby == nil ? ChallengeCreationSuccessCopy.title : ChallengeCreationSuccessCopy.lobbyTitle)
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
                if let lobby { lobbyFacts(lobby).padding(.top, 10) }
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
                    Text(lobby == nil ? "View goal" : "View challenge").font(.subheadline.weight(.medium))
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

    /// Who was invited, then the three factual steps to a locked-in challenge.
    private func lobbyFacts(_ row: ChallengeV1) -> some View {
        let invited = row.members.filter { $0.actorId != store.actor && !$0.exited }
        return VStack(alignment: .leading, spacing: 18) {
            if !invited.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Invited").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Text(invited.contains(where: \.consented) ? "" : "Nobody has agreed yet")
                            .font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                    }
                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(invited) { person in
                                VStack(spacing: 5) {
                                    LiveAvatar(username: person.username, actorID: person.actorId, size: 44)
                                    Text(person.username).font(.caption.weight(.semibold)).lineLimit(2)
                                        .multilineTextAlignment(.center).minimumScaleFactor(0.8)
                                    Text(person.consented ? "Agreed" : "Invited").font(.caption2)
                                        .foregroundStyle(SignalCreationTheme.textSecondary)
                                }
                                .frame(width: 72).accessibilityElement(children: .combine)
                            }
                        }
                    }.scrollIndicators(.hidden)
                }
                .padding(16).background(SignalCreationTheme.soft.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("beta.create.saved.invited")
            }
            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(ChallengeCreationSuccessCopy.steps(row, invited: invited.count).enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Group {
                            if index == 0 && invited.count > 0 { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
                            else { Text("\(index + 1)").font(.system(size: 12, weight: .bold)) }
                        }
                        .foregroundStyle(index == 0 && invited.count > 0 ? .white : SignalCreationTheme.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(index == 0 && invited.count > 0 ? SignalCreationTheme.accent : SignalCreationTheme.soft, in: Circle())
                        .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(step.title).font(.subheadline.weight(.semibold))
                            Text(step.detail).font(.subheadline).foregroundStyle(SignalCreationTheme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .accessibilityIdentifier("beta.create.saved.steps")
        }
    }
}

@MainActor enum ChallengeCreationSuccessCopy {
    static let title = "Challenge locked in."
    static let lobbyTitle = "Challenge saved."

    static func isOpenLobby(_ row: ChallengeV1) -> Bool { row.format.mode == .friend && row.status == "lobby_open" }

    /// Matches the server: the creator picks the roster, and a lobby still
    /// waiting for agreement at the start is cancelled with nothing counted.
    static func steps(_ row: ChallengeV1, invited: Int, locale: Locale = .current) -> [(title: String, detail: String)] {
        let zone = TimeZone(identifier: row.config.timezone) ?? .current
        var day = Date.FormatStyle.dateTime.month(.abbreviated).day(); day.timeZone = zone; day.locale = locale
        let first: (String, String) = invited > 0
            ? ("You invited \(invited) \(invited == 1 ? "friend" : "friends")",
               row.format.hasTarget ? "They’ll see it in GameTime and choose their own goal." : "They’ll see it in GameTime and review the rules.")
            : ("Invite friends", "Open the challenge to invite friends once they’ve accepted your request.")
        return [first,
                ("You pick the roster", "Choose who’s in from the friends who accept."),
                ("Everyone agrees before \(row.config.startsAt.date.formatted(day))",
                 "It locks in when everyone on the roster agrees. If anyone hasn’t by the start, it’s cancelled and nothing counts.")]
    }

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
