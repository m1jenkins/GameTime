import SwiftUI

enum GameTimePreviewTab: Hashable {
    case today
    case challenges
    case friends
    case profile
}

struct GameTimePreviewAppView: View {
    @State private var selectedTab: GameTimePreviewTab = .today

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                GameTimeTodayView()
            }
            .tabItem {
                Label("Today", systemImage: "house.fill")
            }
            .tag(GameTimePreviewTab.today)

            NavigationStack {
                GameTimeChallengesView()
            }
            .tabItem {
                Label("Challenges", systemImage: "trophy.fill")
            }
            .tag(GameTimePreviewTab.challenges)

            NavigationStack {
                GameTimeFriendsView()
            }
            .tabItem {
                Label("Friends", systemImage: "person.2.fill")
            }
            .tag(GameTimePreviewTab.friends)

            NavigationStack {
                GameTimeProfileView()
            }
            .tabItem {
                Label("You", systemImage: "person.crop.circle.fill")
            }
            .tag(GameTimePreviewTab.profile)
        }
        .tint(GameTimeStyle.accent)
    }
}

private enum GameTimePreviewSheet: String, Identifiable {
    case createChallenge

    var id: String { rawValue }
}

struct GameTimeTodayView: View {
    @State private var presentedSheet: GameTimePreviewSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PreviewModeBanner()
                todayHero

                VStack(alignment: .leading, spacing: 12) {
                    PreviewSectionHeader(title: "Active challenge", detail: "Provisional")
                    NavigationLink {
                        GameTimeChallengeDetailView(
                            contest: PreviewFixtures.activeContest
                        )
                    } label: {
                        PreviewContestCard(contest: PreviewFixtures.activeContest)
                    }
                    .buttonStyle(.plain)
                }

                momentumSection
                invitationSection
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(GameTimeStyle.canvas)
        .navigationTitle("GameTime")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentedSheet = .createChallenge
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create challenge")
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .createChallenge:
                GameTimeCreateChallengeView()
            }
        }
    }

    private var todayHero: some View {
        HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Good morning, Maya")
                    .font(.title2.bold())
                Text("One more active day puts you over the line.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                PreviewStatusPill(
                    text: "4 day streak",
                    systemImage: "flame.fill",
                    tint: GameTimeStyle.highlight
                )
            }
            .foregroundStyle(.white)

            Spacer(minLength: 0)

            PreviewProgressRing(
                progress: PreviewFixtures.activeContest.currentProgress,
                value: "4 / 5",
                label: "days"
            )
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [GameTimeStyle.accentDark, GameTimeStyle.accent],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 28, style: .continuous)
        )
        .shadow(color: GameTimeStyle.accentDark.opacity(0.2), radius: 18, y: 10)
    }

    private var momentumSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewSectionHeader(title: "Your momentum")
            HStack(spacing: 10) {
                PreviewValueTile(
                    value: "4",
                    label: "verified days",
                    systemImage: "checkmark.shield.fill"
                )
                PreviewValueTile(
                    value: "2",
                    label: "check-ins",
                    systemImage: "location.fill"
                )
                PreviewValueTile(
                    value: "$25",
                    label: "pledge",
                    systemImage: "heart.fill"
                )
            }
        }
    }

    private var invitationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewSectionHeader(title: "Waiting for you")
            NavigationLink {
                GameTimeInvitationView(contest: PreviewFixtures.invitation)
            } label: {
                HStack(spacing: 14) {
                    PreviewAvatar(
                        initials: "JL",
                        name: "Jordan Lee",
                        accentIndex: 1,
                        size: 46
                    )
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Jordan challenged you")
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("10,000 steps a day · \(PreviewFixtures.invitation.stakeLabel)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(
                    .background,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private enum ChallengeFilter: String, CaseIterable, Identifiable {
    case active = "Active"
    case invites = "Invites"
    case history = "History"

    var id: String { rawValue }
}

struct GameTimeChallengesView: View {
    @State private var filter: ChallengeFilter = .active
    @State private var presentedSheet: GameTimePreviewSheet?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PreviewModeBanner()

                Picker("Challenge filter", selection: $filter) {
                    ForEach(ChallengeFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                switch filter {
                case .active:
                    activeContent
                case .invites:
                    invitesContent
                case .history:
                    historyContent
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 28)
        }
        .background(GameTimeStyle.canvas)
        .navigationTitle("Challenges")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    presentedSheet = .createChallenge
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Create challenge")
            }
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .createChallenge:
                GameTimeCreateChallengeView()
            }
        }
    }

    private var activeContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewSectionHeader(title: "In progress", detail: "1 challenge")
            NavigationLink {
                GameTimeChallengeDetailView(contest: PreviewFixtures.activeContest)
            } label: {
                PreviewContestCard(contest: PreviewFixtures.activeContest)
            }
            .buttonStyle(.plain)
        }
    }

    private var invitesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewSectionHeader(title: "Invitations", detail: "1 new")
            NavigationLink {
                GameTimeInvitationView(contest: PreviewFixtures.invitation)
            } label: {
                PreviewContestCard(contest: PreviewFixtures.invitation)
            }
            .buttonStyle(.plain)
        }
    }

    private var historyContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewSectionHeader(title: "Recently finished")
            NavigationLink {
                GameTimeChallengeDetailView(contest: PreviewFixtures.completedContest)
            } label: {
                PreviewContestCard(contest: PreviewFixtures.completedContest)
            }
            .buttonStyle(.plain)
        }
    }
}

struct GameTimeChallengeDetailView: View {
    let contest: PreviewContest
    @State private var simulatedCheckIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                detailHero
                standingsSection
                evidenceSection
                pledgeSection

                if contest.status == .live {
                    Button {
                        withAnimation(.snappy) {
                            simulatedCheckIn.toggle()
                        }
                    } label: {
                        Label(
                            simulatedCheckIn
                                ? "Preview check-in added"
                                : "Simulate a check-in",
                            systemImage: simulatedCheckIn
                                ? "checkmark.circle.fill"
                                : "location.fill"
                        )
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(GameTimeStyle.accent)
                }
            }
            .padding(18)
            .padding(.bottom, 18)
        }
        .background(GameTimeStyle.canvas)
        .navigationTitle(contest.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var detailHero: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                PreviewStatusPill(
                    text: statusText,
                    systemImage: statusIcon,
                    tint: statusTint
                )
                Spacer()
                Text(contest.periodLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                Image(systemName: contest.metricIcon)
                    .font(.title2)
                    .foregroundStyle(GameTimeStyle.accent)
                    .frame(width: 52, height: 52)
                    .background(GameTimeStyle.accent.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text(contest.metric)
                        .font(.title3.bold())
                    Text("Goal: \(contest.targetValue.formatted()) \(contest.progressUnit)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var standingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewSectionHeader(
                title: contest.status == .completed ? "Final result" : "Live standings",
                detail: contest.status == .live ? "Provisional" : nil
            )

            VStack(spacing: 18) {
                standingRow(
                    name: contest.currentParticipant,
                    value: contest.currentValue,
                    progress: contest.currentProgress,
                    tint: GameTimeStyle.accent
                )
                Divider()
                standingRow(
                    name: contest.opponent,
                    value: contest.opponentValue,
                    progress: contest.opponentProgress,
                    tint: GameTimeStyle.highlight
                )
            }
            .padding(18)
            .background(
                .background,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
    }

    private var evidenceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewSectionHeader(title: "Evidence")
            VStack(spacing: 16) {
                PreviewEvidenceRow(
                    title: "Health data",
                    detail: "Source and hourly totals verified",
                    systemImage: "heart.text.clipboard.fill"
                )
                Divider()
                PreviewEvidenceRow(
                    title: "Location check-ins",
                    detail: simulatedCheckIn
                        ? "3 trusted visits in this preview"
                        : "2 trusted visits",
                    systemImage: "location.fill"
                )
                Divider()
                PreviewEvidenceRow(
                    title: "Integrity review",
                    detail: "No issues affecting this standing",
                    systemImage: "checkmark.shield.fill"
                )
            }
            .padding(18)
            .background(
                .background,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
    }

    private var pledgeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewSectionHeader(title: "Charitable pledge")
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    "\(contest.stakeLabel) if you miss the goal",
                    systemImage: "heart.fill"
                )
                .font(.headline)
                .foregroundStyle(GameTimeStyle.accentDark)

                Text(contest.currentCharity)
                    .font(.title3.bold())

                Text(
                    contest.status == .completed
                        ? "This sample ended in an all-donate tie, so each participant gives to their own nomination."
                        : "No cash prize or pot. GameTime tracks whether the agreed donation is honored."
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .background(
                GameTimeStyle.highlight.opacity(0.13),
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
    }

    private func standingRow(
        name: String,
        value: Int,
        progress: Double,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                Text("\(value) / \(contest.targetValue)")
                    .font(.headline.monospacedDigit())
            }
            ProgressView(value: progress)
                .tint(tint)
        }
    }

    private var statusText: String {
        switch contest.status {
        case .live:
            "Live"
        case .invitation:
            "Invitation"
        case .completed:
            "All-donate tie"
        }
    }

    private var statusIcon: String {
        switch contest.status {
        case .live:
            "bolt.fill"
        case .invitation:
            "envelope.fill"
        case .completed:
            "checkmark.seal.fill"
        }
    }

    private var statusTint: Color {
        switch contest.status {
        case .live:
            GameTimeStyle.accent
        case .invitation:
            GameTimeStyle.highlight
        case .completed:
            .blue
        }
    }
}

private enum InvitationDecision {
    case accepted
    case declined
}

struct GameTimeInvitationView: View {
    let contest: PreviewContest
    @State private var decision: InvitationDecision?

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                PreviewModeBanner()

                PreviewAvatar(
                    initials: "JL",
                    name: "Jordan Lee",
                    accentIndex: 1,
                    size: 72
                )

                VStack(spacing: 6) {
                    Text("Jordan challenged you")
                        .font(.title2.bold())
                    Text(contest.title)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    invitationRow(
                        title: "Goal",
                        value: "\(contest.targetValue.formatted()) \(contest.progressUnit)"
                    )
                    Divider()
                    invitationRow(title: "When", value: contest.periodLabel)
                    Divider()
                    invitationRow(title: "Your pledge", value: contest.stakeLabel)
                    Divider()
                    invitationRow(title: "Evidence", value: contest.evidenceSummary)
                }
                .padding(.horizontal, 18)
                .background(
                    .background,
                    in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )

                if let decision {
                    Label(
                        decision == .accepted
                            ? "Accepted in this preview"
                            : "Declined in this preview",
                        systemImage: decision == .accepted
                            ? "checkmark.circle.fill"
                            : "xmark.circle.fill"
                    )
                    .font(.headline)
                    .foregroundStyle(
                        decision == .accepted ? GameTimeStyle.accent : .secondary
                    )
                    .padding()
                } else {
                    VStack(spacing: 10) {
                        Button {
                            withAnimation(.snappy) {
                                decision = .accepted
                            }
                        } label: {
                            Text("Accept challenge")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(GameTimeStyle.accent)

                        Button("Decline") {
                            withAnimation(.snappy) {
                                decision = .declined
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                }

                Text("Preview actions do not write to Supabase or reserve a charitable pledge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(18)
        }
        .background(GameTimeStyle.canvas)
        .navigationTitle("Invitation")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func invitationRow(title: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }
}

private enum PreviewMetric: String, CaseIterable, Identifiable {
    case steps = "Steps"
    case workouts = "Workouts"
    case activeMinutes = "Active minutes"

    var id: String { rawValue }
}

struct GameTimeCreateChallengeView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title = "Morning Move"
    @State private var metric: PreviewMetric = .workouts
    @State private var stake = 25
    @State private var duration = 7
    @State private var startDate =
        Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Challenge name", text: $title)
                    Picker("Metric", selection: $metric) {
                        ForEach(PreviewMetric.allCases) { metric in
                            Text(metric.rawValue).tag(metric)
                        }
                    }
                    Stepper("\(duration) days", value: $duration, in: 2 ... 30)
                    DatePicker(
                        "Starts",
                        selection: $startDate,
                        displayedComponents: [.date]
                    )
                } header: {
                    Text("Goal")
                }

                Section {
                    LabeledContent("Opponent", value: "Alex Chen")
                    Stepper("$\(stake) pledge", value: $stake, in: 5 ... 100, step: 5)
                    LabeledContent("Your charity", value: "Central Texas Food Bank")
                } header: {
                    Text("People and pledge")
                } footer: {
                    Text(
                        "This proof of concept saves nothing. Product creation, "
                            + "Health access, and Supabase wiring begin in M8."
                    )
                }

                Section {
                    Label("Health data provenance", systemImage: "heart.text.clipboard")
                    Label("Trusted check-ins", systemImage: "location")
                    Label("Integrity-aware scoring", systemImage: "checkmark.shield")
                } header: {
                    Text("Verification")
                }
            }
            .navigationTitle("New challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save preview") {
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct GameTimeFriendsView: View {
    @State private var showsFriendPreviewAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreviewModeBanner()
                groupCard

                VStack(alignment: .leading, spacing: 12) {
                    PreviewSectionHeader(
                        title: "Friends",
                        detail: "\(PreviewFixtures.friends.count)"
                    )
                    VStack(spacing: 0) {
                        ForEach(Array(PreviewFixtures.friends.enumerated()), id: \.element.id) {
                            index,
                            friend in
                            friendRow(friend)
                            if index < PreviewFixtures.friends.count - 1 {
                                Divider()
                                    .padding(.leading, 66)
                            }
                        }
                    }
                    .background(
                        .background,
                        in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                    )
                }
            }
            .padding(18)
            .padding(.bottom, 18)
        }
        .background(GameTimeStyle.canvas)
        .navigationTitle("Friends")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showsFriendPreviewAlert = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
                .accessibilityLabel("Add friend")
            }
        }
        .alert("Friend search is not connected yet", isPresented: $showsFriendPreviewAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The production friend search and request flow is planned for M8.")
        }
    }

    private var groupCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sunday Striders")
                        .font(.title3.bold())
                    Text("Your accountability crew")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "figure.run.circle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(GameTimeStyle.accent)
            }

            HStack(spacing: -8) {
                ForEach(PreviewFixtures.friends.prefix(4)) { friend in
                    PreviewAvatar(
                        initials: friend.initials,
                        name: friend.name,
                        accentIndex: friend.accentIndex,
                        size: 38
                    )
                    .overlay {
                        Circle().stroke(.background, lineWidth: 2)
                    }
                }
                Spacer()
                Text("4 members")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [
                    GameTimeStyle.accent.opacity(0.18),
                    GameTimeStyle.highlight.opacity(0.15),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }

    private func friendRow(_ friend: PreviewFriend) -> some View {
        HStack(spacing: 12) {
            PreviewAvatar(
                initials: friend.initials,
                name: friend.name,
                accentIndex: friend.accentIndex
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.headline)
                Text(friend.handle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(friend.sharedActivity)
                    .font(.caption)
                    .foregroundStyle(GameTimeStyle.accent)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(14)
    }
}

struct GameTimeProfileView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PreviewModeBanner()
                profileHeader
                reliabilityCard
                privacySection
                engineeringSection
            }
            .padding(18)
            .padding(.bottom, 18)
        }
        .background(GameTimeStyle.canvas)
        .navigationTitle("You")
    }

    private var profileHeader: some View {
        HStack(spacing: 16) {
            PreviewAvatar(
                initials: "MR",
                name: "Maya Runner",
                accentIndex: 3,
                size: 72
            )
            VStack(alignment: .leading, spacing: 4) {
                Text("Maya Runner")
                    .font(.title2.bold())
                Text("@mayamoves")
                    .foregroundStyle(.secondary)
                PreviewStatusPill(
                    text: "Evidence ready",
                    systemImage: "checkmark.shield.fill"
                )
            }
        }
    }

    private var reliabilityCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Pledge reliability")
                        .font(.headline)
                    Text("Illustrative contract preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("92%")
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .foregroundStyle(GameTimeStyle.accent)
            }
            ProgressView(value: 0.92)
                .tint(GameTimeStyle.accent)
            Text(
                "Only independently confirmed charitable pledges count. "
                    + "Losing a challenge never lowers reliability by itself."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            PreviewSectionHeader(title: "Data and privacy")
            VStack(spacing: 0) {
                profileRow(
                    title: "Health data",
                    detail: "Private evidence",
                    systemImage: "heart.text.clipboard"
                )
                Divider().padding(.leading, 54)
                profileRow(
                    title: "Location",
                    detail: "Trusted check-ins only",
                    systemImage: "location"
                )
                Divider().padding(.leading, 54)
                profileRow(
                    title: "Account controls",
                    detail: "Retention and deletion",
                    systemImage: "hand.raised"
                )
            }
            .background(
                .background,
                in: RoundedRectangle(cornerRadius: 22, style: .continuous)
            )
        }
    }

    private var engineeringSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Engineering status")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text("M0–M6 complete · M6.5 device proof open")
                .font(.subheadline.weight(.semibold))
            Text(
                "This simulator path is a non-networked product proof of concept. "
                    + "Physical-device builds still open the App Attest conformance harness."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            GameTimeStyle.accent.opacity(0.09),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }

    private func profileRow(
        title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(GameTimeStyle.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
    }
}

#Preview("GameTime Today") {
    NavigationStack {
        GameTimeTodayView()
    }
}

#Preview("Challenge Detail") {
    NavigationStack {
        GameTimeChallengeDetailView(contest: PreviewFixtures.activeContest)
    }
}
