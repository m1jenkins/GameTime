import SwiftUI

/// The private record uses server-confirmed outcomes, never arithmetic over a
/// partially loaded page to infer a loss or a lifetime total.
struct LiveRecordView: View {
    let store: ChallengeV1Store
    let profile: UserProfile?
    let accountActor: UUID?
    let settings: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @State private var loadingMore = false
    @State private var pageRequest = UUID()
    @State private var openFriends = false

    private var snapshot: ChallengeProfileSnapshot {
        guard accountActor != nil, accountActor == store.actor else {
            return ChallengeProfileSnapshot(actor: nil, sections: [:], now: 0)
        }
        return store.profileSnapshot
    }

    private var identity: UserProfile? {
        profile?.id == accountActor && accountActor == store.actor ? profile : nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("You")
                        .font(.system(size: 27, weight: .bold)).tracking(-1)
                    Spacer()
                    LiveRoundButton(symbol: "gearshape", label: "Settings", action: settings)
                        .accessibilityIdentifier("profile.settings")
                }
                .padding(.bottom, 13)

                identityHeader
                if friends != nil {
                    FriendsEntryRow(challenges: store, username: identity?.handle).padding(.top, 20)
                }
                summary.padding(.top, friends != nil ? 24 : 16)

                HStack {
                    Text("Finished").font(.system(size: 16, weight: .bold)).tracking(-0.5)
                    Spacer(minLength: 8)
                    Text("\(snapshot.countText(snapshot.finished.count)) challenges")
                        .font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
                }
                .padding(.top, 18).padding(.bottom, 12)

                LazyVStack(spacing: 11) {
                    ForEach(snapshot.finished) { row in
                        NavigationLink {
                            LiveGoalDetail(store: store, id: row.id)
                        } label: {
                            resultCard(row)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.record.\(row.id.uuidString.lowercased())")
                    }
                }

                if snapshot.finished.isEmpty {
                    emptyRecord
                }
                if snapshot.availability != .complete {
                    Text(snapshot.scopeText)
                        .font(.footnote).foregroundStyle(SignalTheme.textSecondary)
                        .padding(.top, 16)
                        .accessibilityIdentifier("profile.record-scope")
                }
                if snapshot.availability == .stale || snapshot.availability == .unavailable {
                    Button(store.refreshing ? "Refreshing…" : "Refresh records") {
                        Task { await store.refresh() }
                    }
                    .buttonStyle(LiveSecondaryButtonStyle())
                    .disabled(store.refreshing)
                    .padding(.top, 12)
                }
                if !snapshot.sectionsWithMore.isEmpty, snapshot.availability != .stale {
                    Button(loadingMore ? "Loading…" : "Load more records", action: loadMore)
                        .buttonStyle(LiveSecondaryButtonStyle())
                        .disabled(loadingMore || store.refreshing)
                        .padding(.top, 16)
                        .accessibilityIdentifier("profile.load-more")
                }
            }
            .padding(.horizontal, 24).padding(.top, 10).padding(.bottom, 24)
        }
        .background(SignalTheme.canvas.ignoresSafeArea())
        .foregroundStyle(SignalTheme.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refresh() }
        .navigationDestination(isPresented: $openFriends) { FriendsView(challenges: store, username: identity?.handle) }
        .onAppear {
            #if DEBUG
            if LiveDesignFixtures.enabled, ProcessInfo.processInfo.arguments.contains("--live-screen=friends") { openFriends = true }
            #endif
        }
        .onChange(of: accountActor) { _, _ in
            pageRequest = UUID()
            loadingMore = false
        }
    }

    private var identityHeader: some View {
        HStack(spacing: 12) {
            LiveAvatar(username: identity?.handle ?? "", actorID: identity?.id, size: 48)
            VStack(alignment: .leading, spacing: 4) {
                Text(identity?.displayName ?? "Your profile")
                    .font(.system(size: 18, weight: .semibold)).tracking(-0.5)
                if let identity {
                    Text("@\(identity.handle)").font(.system(size: 12))
                        .foregroundStyle(SignalTheme.textSecondary)
                        .accessibilityLabel("Username \(identity.handle)")
                }
            }
            Spacer(minLength: 4)
            if !dynamicTypeSize.isAccessibilitySize {
                Label("Private", systemImage: "lock")
                    .font(.system(size: 10)).foregroundStyle(SignalTheme.textSecondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var recordPeriod: String {
        guard snapshot.availability == .complete else { return "Loaded" }
        let years = Set(snapshot.finished.map { Calendar.current.component(.year, from: $0.config.endsAt.date.addingTimeInterval(-1)) })
        return years.count == 1 ? String(years.first!) : "All dates"
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your record")
                Spacer()
                Text(recordPeriod)
            }
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(SignalTheme.textSecondary)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { summaryNumbers }
            } else {
                HStack(alignment: .top, spacing: 20) { summaryNumbers }
            }
        }
        .padding(.top, 12).padding(.bottom, 15)
        .overlay(alignment: .top) { Rectangle().fill(SignalTheme.divider).frame(height: 1) }
        .overlay(alignment: .bottom) { Rectangle().fill(SignalTheme.divider).frame(height: 1) }
    }

    @ViewBuilder private var summaryNumbers: some View {
        summaryNumber(snapshot.countText(LiveChallengePresentation.goalsMet(in: snapshot)), label: "Goals met", id: "met")
        if !dynamicTypeSize.isAccessibilitySize {
            Rectangle().fill(SignalTheme.divider).frame(width: 1, height: 58)
                .accessibilityHidden(true)
        }
        summaryNumber(snapshot.countText(snapshot.finished.count), label: "Challenges\nfinished", id: "finished")
    }

    private func summaryNumber(_ value: String, label: String, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(value).font(.system(size: 46, weight: .black)).italic().tracking(-2.5)
                .minimumScaleFactor(0.65).lineLimit(1)
            Text(label).font(.system(size: 12)).foregroundStyle(SignalTheme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.count.\(id)")
    }

    private func resultCard(_ row: ChallengeV1) -> some View {
        let outcome = LiveChallengePresentation.outcome(row, actor: snapshot.actor)
        let member = row.own(snapshot.actor)
        let savedValue = member.flatMap { row.savedScore($0) }
        let noResult = row.status != "final" || member?.exited == true
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(LiveChallengePresentation.title(row))
                    .font(.system(size: 19, weight: .bold)).tracking(-0.65)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(SignalTheme.textSecondary).accessibilityHidden(true)
            }
            Text(dateRange(row)).font(.system(size: 12))
                .foregroundStyle(SignalTheme.textSecondary).padding(.top, 6)
            if noResult {
                Text(outcome).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SignalTheme.textSecondary).padding(.top, 12)
            } else {
                HStack(spacing: 8) {
                    LiveStateChip(text: outcome, warning: outcome == "Missed", neutral: outcome == "Didn’t count")
                    Spacer(minLength: 0)
                    HStack(spacing: -8) {
                        ForEach(Array(row.members.filter { $0.selected && $0.consented }.prefix(3))) { person in
                            LiveAvatar(username: person.username, actorID: person.actorId, size: 28)
                                .overlay(Circle().stroke(SignalTheme.canvas, lineWidth: 2))
                        }
                    }
                    .accessibilityLabel("\(row.members.filter { $0.selected && $0.consented }.count) participants")
                }
                .padding(.top, 10)
                if let savedValue {
                    LiveMetric(value: LiveChallengePresentation.value(savedValue, metric: row.format.metric),
                               unit: LiveChallengePresentation.unit(row.format.metric), size: 64)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : 66)
                        .padding(.top, 7)
                } else {
                    Text("Result unavailable")
                        .font(.system(size: 24, weight: .bold)).tracking(-0.8).padding(.top, 16)
                }
                Text(targetText(row)).font(.system(size: 11))
                    .foregroundStyle(SignalTheme.textSecondary).padding(.top, 5)
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LiveCardModifier())
    }

    private var emptyRecord: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.availability == .complete ? "No finished challenges yet" : "Your record is loading")
                .font(.system(size: 20, weight: .bold)).tracking(-0.5)
            Text(snapshot.availability == .complete
                 ? "Your finished challenges will appear here. Find your current goals in Challenges."
                 : "Refresh to see your saved results.")
                .font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .modifier(LiveCardModifier())
    }

    private func dateRange(_ row: ChallengeV1) -> String {
        let zone = TimeZone(identifier: row.config.timezone) ?? .gmt
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.timeZone = zone
        let startDate = row.config.startsAt.date
        let endDate = row.config.endsAt.date.addingTimeInterval(-1)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let startYear = calendar.component(.year, from: startDate)
        let endYear = calendar.component(.year, from: endDate)
        let currentYear = calendar.component(.year, from: Date())
        if startYear != endYear {
            style = style.year()
            return "\(startDate.formatted(style))–\(endDate.formatted(style))"
        }
        let start = startDate.formatted(style)
        let sameMonth = calendar.isDate(startDate, equalTo: endDate, toGranularity: .month)
        let end = sameMonth ? String(calendar.component(.day, from: endDate)) : endDate.formatted(style)
        let year = endYear != currentYear || recordPeriod == "All dates" ? ", \(endYear)" : ""
        return "\(start)–\(end)\(year)"
    }

    private func targetText(_ row: ChallengeV1) -> String {
        guard let target = row.own(snapshot.actor)?.target else { return "Saved result" }
        return "Your goal: \(row.format.metric.display(target))"
    }

    private func loadMore() {
        let actor = accountActor
        let request = UUID()
        let sections = snapshot.sectionsWithMore
        pageRequest = request
        loadingMore = true
        Task {
            defer { if pageRequest == request { loadingMore = false } }
            for section in sections {
                guard actor != nil, actor == accountActor, actor == store.actor,
                      request == pageRequest else { return }
                await store.loadMore(section)
            }
        }
    }
}
