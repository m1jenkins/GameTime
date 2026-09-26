import SwiftUI

/// Ordinary-product profile. Retained Personal history has a separate owner
/// and remains in Existing challenges, including its original Health controls.
struct ChallengeProfileView: View {
    let store: ChallengeV1Store
    let profile: UserProfile?
    let accountActor: UUID?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selection = ProfileSection.challenges
    @State private var loadingMore = false
    @State private var pageRequest = UUID()

    private enum ProfileSection: String, CaseIterable, Identifiable {
        case challenges = "Challenges", activity = "Activity"
        var id: Self { self }
    }
    private var snapshot: ChallengeProfileSnapshot {
        guard accountActor == store.actor else {
            return ChallengeProfileSnapshot(actor: nil, sections: [:], now: 0)
        }
        return store.profileSnapshot
    }
    private var identity: UserProfile? {
        profile?.id == accountActor && accountActor == store.actor ? profile : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                SignalSimulationBanner()
                    .padding(.horizontal, -SignalTheme.contentInset)
                    .padding(.top, -16)
                identityHeader
                if let row = snapshot.featured {
                    VStack(alignment: .leading, spacing: 10) {
                        if snapshot.availability == .stale {
                            Text("Might be out of date").font(.caption).foregroundStyle(SignalTheme.textSecondary)
                        }
                        NavigationLink {
                            ChallengeV1Detail(store: store, id: row.id)
                        } label: {
                            if ["scheduled", "active"].contains(row.status), row.format.hasTarget {
                                SignalHomeGoal(row: row, actor: snapshot.actor)
                            } else {
                                SignalChallengeSummary(row: row, actor: snapshot.actor)
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.featured-goal")
                    }
                }
                savedSummary
                sectionPicker
                if selection == .challenges { challengeRecords } else { personalActivity }
                DisclosureGroup("About these records") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("These are the challenges saved to your current GameTime account. Upcoming means scheduled; active includes activity checks and result reviews. Finished includes closed challenges and saved exits.")
                        Text("Counts cover the records loaded here, across their agreed dates. A plus means more records may remain. A dash means we can’t confirm a count. Refresh starts again with the latest pages.")
                        Text("Your earlier Personal agreements stay in Existing challenges. They aren’t added to these counts. Switching accounts clears this view.")
                    }
                    .font(.subheadline)
                    .foregroundStyle(SignalTheme.textSecondary)
                    .padding(.top, 10)
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(.horizontal, SignalTheme.contentInset)
            .padding(.vertical, 16)
        }
        .signalTabScrollClearance()
        .signalScreenChrome()
        .navigationTitle("You")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(value: YouRoute.settings) {
                    Label("Settings", systemImage: "gearshape")
                }
                .accessibilityIdentifier("profile.settings")
            }
        }
        .refreshable { await store.refresh() }
        .onChange(of: accountActor) { _, _ in
            selection = .challenges
            pageRequest = UUID()
            loadingMore = false
        }
    }

    @ViewBuilder private var sectionPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                ForEach(ProfileSection.allCases) { section in
                    Button { selection = section } label: {
                        HStack {
                            Text(section.rawValue)
                            Spacer(minLength: 8)
                            if selection == section {
                                Image(systemName: "checkmark").accessibilityHidden(true)
                            }
                        }
                    }
                    .buttonStyle(SignalSecondaryButtonStyle())
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                    .accessibilityIdentifier("profile.section.\(section.id.rawValue.lowercased())")
                }
            }
            .modifier(SignalGlassGroup())
        } else {
            Picker("Profile section", selection: $selection) {
                ForEach(ProfileSection.allCases) { section in Text(section.rawValue).tag(section) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("profile.section")
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 16) {
            if let identity, !dynamicTypeSize.isAccessibilitySize {
                Text(identity.initials)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(SignalTheme.accent)
                    .frame(width: 60, height: 60)
                    .background(SignalTheme.selection, in: Circle())
                    .accessibilityHidden(true)
            } else if identity == nil {
                Image(systemName: "person.crop.circle")
                    .font(.largeTitle)
                    .foregroundStyle(SignalTheme.accent)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(identity?.displayName ?? "Your profile")
                    .font(.largeTitle.weight(.semibold))
                    .tracking(-1)
                if let identity {
                    Text("@\(identity.handle)")
                        .font(.subheadline)
                        .foregroundStyle(SignalTheme.textSecondary)
                        .accessibilityLabel("Username \(identity.handle)")
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    private var savedSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 16) { summaryNumbers }
            } else {
                HStack(alignment: .top, spacing: 18) { summaryNumbers }
            }
            Text(snapshot.scopeText)
                .font(.caption)
                .foregroundStyle(SignalTheme.textSecondary)
                .accessibilityIdentifier("profile.record-scope")
            if let checked = snapshot.checkedAt {
                Text("Checked \(checked.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(SignalTheme.textSecondary)
            }
            if snapshot.availability == .stale || snapshot.availability == .unavailable {
                Button(store.refreshing ? "Refreshing…" : "Refresh") { Task { await store.refresh() } }
                    .buttonStyle(SignalPillButtonStyle())
                    .disabled(store.refreshing)
            }
        }
        .padding(.vertical, 20)
        .overlay(alignment: .top) { Divider().overlay(SignalTheme.divider) }
        .overlay(alignment: .bottom) { Divider().overlay(SignalTheme.divider) }
    }

    @ViewBuilder private var summaryNumbers: some View {
        profileMetric(snapshot.countText(snapshot.upcoming.count), title: "Upcoming", id: "upcoming")
        profileMetric(snapshot.countText(snapshot.active.count), title: "Active", id: "active")
        profileMetric(snapshot.countText(snapshot.finished.count), title: "Finished", id: "finished")
    }

    private func profileMetric(_ value: String, title: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.largeTitle.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(SignalTheme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.count.\(id)")
    }

    private var challengeRecords: some View {
        VStack(alignment: .leading, spacing: 24) {
            if snapshot.rows.isEmpty, snapshot.availability == .complete {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Your goals belong here").font(.title2.weight(.semibold))
                    Text("Create a goal from Challenges. Its dates, progress and result will appear here.")
                        .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
                }
            }
            let otherRows = snapshot.rows.filter { $0.id != snapshot.featured?.id }
            if !otherRows.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SignalSectionLabel(text: "Saved challenges").padding(.bottom, 8)
                    ForEach(otherRows) { row in
                        NavigationLink { ChallengeV1Detail(store: store, id: row.id) } label: {
                            SignalChallengeSummary(row: row, actor: snapshot.actor)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if !snapshot.sectionsWithMore.isEmpty, snapshot.availability != .stale {
                Button(loadingMore ? "Loading…" : "Load more records") {
                    let actor = accountActor
                    let request = UUID()
                    let sections = snapshot.sectionsWithMore
                    pageRequest = request
                    Task {
                        loadingMore = true
                        defer { if pageRequest == request { loadingMore = false } }
                        for section in sections {
                            guard actor != nil, actor == accountActor, actor == store.actor,
                                  request == pageRequest else { return }
                            await store.loadMore(section)
                        }
                    }
                }
                .buttonStyle(SignalSecondaryButtonStyle())
                .disabled(loadingMore || store.refreshing)
                .accessibilityIdentifier("profile.load-more")
            }
            if snapshot.rows.contains(where: { $0.format.mode == .friend && $0.format.competition == .leaderboard }) {
                competitionRecord
            }
        }
    }

    private var competitionRecord: some View {
        VStack(alignment: .leading, spacing: 12) {
            SignalSectionLabel(text: "Friend competitions")
            if snapshot.competitiveResults.isEmpty {
                Text(snapshot.availability == .complete ? "No final competitive results yet." : "No final competitive results in the records loaded here.")
                    .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 24) { competitiveNumbers }
                    VStack(alignment: .leading, spacing: 16) { competitiveNumbers }
                }
                if let first = snapshot.competitiveResults.compactMap(\.row.final?.recordedAt).min(),
                   let last = snapshot.competitiveResults.compactMap(\.row.final?.recordedAt).max() {
                    Text(first == last
                         ? "Finalized \(last.date.formatted(date: .abbreviated, time: .omitted))"
                         : "Finalized \(first.date.formatted(date: .abbreviated, time: .omitted))–\(last.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(SignalTheme.textSecondary)
                }
            }
            Text("Only final best-result competitions count. Shared wins count as wins. Individual goals, open reviews and missing scores don’t add a loss.")
                .font(.caption).foregroundStyle(SignalTheme.textSecondary)
        }
    }

    @ViewBuilder private var competitiveNumbers: some View {
        profileMetric(snapshot.countText(snapshot.wins), title: "Wins", id: "wins")
        profileMetric(snapshot.countText(snapshot.losses), title: "Losses", id: "losses")
    }

    private var personalActivity: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Your personal activity", systemImage: "figure.walk")
                .font(.title2.weight(.semibold))
            Text("Lifetime totals and streaks aren’t available yet.")
                .font(.headline)
            Text("This profile doesn’t have a complete personal activity history. Your saved challenge scores stay with each goal; adding them together could count the same activity more than once.")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            Text("Open a goal to see the activity saved for its dates. You can manage GameTime’s access in Apple Health.")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
        }
        .accessibilityIdentifier("profile.activity.unavailable")
    }
}
