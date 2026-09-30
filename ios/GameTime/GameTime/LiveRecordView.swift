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
    @State private var scrolled = false

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
        FloodlightScrollPage(scrolled: $scrolled) { topInset in
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 10) {
                        FloodlightTitle("You", size: 38).foregroundStyle(Floodlight.ink)
                        Spacer(minLength: 8)
                        FloodlightNavButton(symbol: "gearshape", label: "Settings", action: settings)
                            .accessibilityIdentifier("profile.settings")
                    }
                    .padding(.horizontal, 18).padding(.top, topInset + 6)
                    identityHeader.padding(.horizontal, 20).padding(.top, 12)
                    summary.padding(.horizontal, 16).padding(.top, 14)
                }
                .padding(.bottom, 14)
                .background(alignment: .top) { FloodlightSky() }

                VStack(alignment: .leading, spacing: 0) {
                    if friends != nil {
                        FriendsEntryRow(challenges: store, username: identity?.handle)
                    }
                    let finishedLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                    finishedLayout {
                        FloodlightTitle("Finished", size: 21)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        Text("\(snapshot.countText(snapshot.finished.count)) challenges")
                            .floodlightFont(12.5, weight: .medium).foregroundStyle(Floodlight.muted)
                    }
                    .padding(.horizontal, 4).padding(.top, 22).padding(.bottom, 12)

                    LazyVStack(spacing: 12) {
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
                    if snapshot.finished.isEmpty { emptyRecord }
                    if snapshot.availability != .complete {
                        Text(snapshot.scopeText)
                            .floodlightFont(13).foregroundStyle(Floodlight.muted).padding(.top, 16)
                            .accessibilityIdentifier("profile.record-scope")
                    }
                    if snapshot.availability == .stale || snapshot.availability == .unavailable {
                        Button(store.refreshing ? "Refreshing…" : "Refresh records") { Task { await store.refresh() } }
                            .buttonStyle(FloodlightCalmButtonStyle()).disabled(store.refreshing).padding(.top, 12)
                    }
                    if !snapshot.sectionsWithMore.isEmpty, snapshot.availability != .stale {
                        Button(loadingMore ? "Loading…" : "Load more records", action: loadMore)
                            .buttonStyle(FloodlightCalmButtonStyle()).disabled(loadingMore || store.refreshing)
                            .padding(.top, 16).accessibilityIdentifier("profile.load-more")
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 28)
            }
        }
        .foregroundStyle(Floodlight.ink)
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
            FloodlightOrb(slot: 0, initials: FloodlightOrb.initials(identity?.displayName ?? identity?.handle ?? ""), size: 52)
            VStack(alignment: .leading, spacing: 2) {
                Text(identity?.displayName ?? "Your profile").floodlightFont(17, weight: .semibold)
                if let identity {
                    let layout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
                    layout {
                        Text("@\(identity.handle)").accessibilityLabel("Username \(identity.handle)")
                        if !dynamicTypeSize.isAccessibilitySize { Text("·").accessibilityHidden(true) }
                        Label("Private", systemImage: "lock")
                    }
                    .floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted)
                }
            }
            Spacer(minLength: 0)
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
            let headingLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            headingLayout {
                FloodlightLabel("Your record")
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                Text(recordPeriod).floodlightFont(13, weight: .semibold)
            }
            let numbersLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .top, spacing: 10))
            numbersLayout {
                summaryNumber(snapshot.countText(LiveChallengePresentation.goalsMet(in: snapshot)), label: "Goals met", id: "met")
                summaryNumber(snapshot.countText(snapshot.finished.count), label: "Challenges finished", id: "finished")
            }
            if !snapshot.finished.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 20, maximum: 20), spacing: 4)], alignment: .leading, spacing: 4) {
                    ForEach(snapshot.finished.reversed()) { row in
                        recordPip(row)
                    }
                }
                .padding(.top, 12)
                .overlay(alignment: .top) { Rectangle().fill(Floodlight.line).frame(height: 1) }
                .padding(.top, 2)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .floodlightHero()
    }

    private func summaryNumber(_ value: String, label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).floodlightFont(64, weight: .semibold, condensed: true, maxScale: 1.5).tracking(-1.28)
                .foregroundStyle(Floodlight.muted).lineLimit(1).minimumScaleFactor(0.65)
            Text(label).floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("profile.count.\(id)")
    }

    private enum RecordState { case met, missed, unconfirmed, other }
    private func recordState(_ row: ChallengeV1) -> RecordState {
        guard let own = row.own(snapshot.actor), own.selected, own.consented, !own.exited else { return .other }
        let result = row.final?.result
        let status = result?.participants?[own.actorId.uuidString.lowercased()]?.status ?? (row.socialHidden ? result?.own?.status : nil)
        if row.status == "final", status == "met" { return .met }
        if row.status == "final", status == "missed" { return .missed }
        if row.isClosed, row.status != "cancelled", !["winner", "placed"].contains(status ?? ""),
           row.savedScore(own) == nil || status == nil || status == "missing" || status == "unverified" {
            return .unconfirmed
        }
        return .other
    }

    private func recordPip(_ row: ChallengeV1) -> some View {
        let state = recordState(row)
        return ZStack {
            Circle().fill(state == .met ? Floodlight.button : state == .unconfirmed ? Floodlight.unconfirmedWash : Floodlight.well)
            if state == .met {
                Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Floodlight.buttonInk)
            } else if state == .unconfirmed {
                Circle().strokeBorder(Floodlight.unconfirmed, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                Text("?").floodlightFont(12, weight: .bold, maxScale: 1).foregroundStyle(Floodlight.unconfirmed)
            } else {
                Circle().strokeBorder(state == .missed ? Floodlight.faint : Floodlight.wellEdge, lineWidth: 1)
            }
        }
        .frame(width: 20, height: 20)
    }

    private func resultCard(_ row: ChallengeV1) -> some View {
        let state = recordState(row)
        let savedValue = row.own(snapshot.actor).flatMap { row.savedScore($0) }
        let hasFinalResult = row.status == "final" && row.own(snapshot.actor)?.exited != true
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        return layout {
            resultRing(state)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        FloodlightTitle(LiveChallengePresentation.title(row), size: 18)
                        Text(dateRange(row)).floodlightFont(12, weight: .medium).foregroundStyle(Floodlight.muted)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right").font(.system(size: 15, weight: .semibold)).padding(.top, 3)
                        .foregroundStyle(Floodlight.muted).accessibilityHidden(true)
                }
                if state == .unconfirmed {
                    Text("Result unavailable")
                        .floodlightFont(22, weight: .semibold, condensed: true)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !hasFinalResult {
                    Text(LiveChallengePresentation.outcome(row, actor: snapshot.actor))
                        .floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted)
                } else if let savedValue {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(LiveChallengePresentation.value(savedValue, metric: row.format.metric))
                            .floodlightFont(28, weight: .semibold, condensed: true, maxScale: 1.5)
                            .tracking(-0.56).lineLimit(1).minimumScaleFactor(0.7)
                        Text(LiveChallengePresentation.unit(row.format.metric))
                            .floodlightFont(12, weight: .medium).foregroundStyle(Floodlight.muted)
                    }
                } else {
                    Text("Result unavailable").floodlightFont(22, weight: .semibold, condensed: true)
                }
                if hasFinalResult || state == .unconfirmed {
                    let footerLayout = dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                    footerLayout {
                        Text(state == .unconfirmed ? "It doesn’t count against you." : targetText(row))
                            .floodlightFont(12, weight: .medium).foregroundStyle(Floodlight.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        resultTag(state, otherText: LiveChallengePresentation.outcome(row, actor: snapshot.actor))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floodlightCard(fill: state == .unconfirmed ? Floodlight.unconfirmedWash : Floodlight.card,
                       dashedEdge: state == .unconfirmed ? Floodlight.unconfirmed : nil)
    }

    private func resultRing(_ state: RecordState) -> some View {
        ZStack {
            if state == .unconfirmed {
                Circle().stroke(Floodlight.unconfirmed, style: StrokeStyle(lineWidth: 3, dash: [4, 4])).padding(6)
                Text("?").floodlightFont(20, weight: .bold, condensed: true, maxScale: 1).foregroundStyle(Floodlight.unconfirmed)
            } else {
                Circle().stroke(Floodlight.well, lineWidth: 7).padding(6)
                Circle().trim(from: 0, to: state == .met ? 1 : 0).stroke(FloodlightToken.arcYou.color, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(6)
                if state == .met {
                    Image(systemName: "checkmark").font(.system(size: 22, weight: .bold)).foregroundStyle(Floodlight.ink)
                }
            }
        }
        .frame(width: 58, height: 58).accessibilityHidden(true)
    }

    private func resultTag(_ state: RecordState, otherText: String) -> some View {
        HStack(spacing: 5) {
            if state == .met { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).accessibilityHidden(true) }
            Text(state == .met ? "Your goal met" : state == .missed ? "Missed" : state == .unconfirmed ? "Not confirmed" : otherText)
                .floodlightFont(11.5, weight: .semibold)
        }
        .foregroundStyle(state == .met ? Floodlight.buttonInk : Floodlight.ink)
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(Capsule().fill(state == .met ? Floodlight.button : state == .unconfirmed ? .clear : Floodlight.well))
        .overlay {
            if state == .unconfirmed {
                Capsule().strokeBorder(Floodlight.unconfirmed, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
    }

    private var emptyRecord: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.availability == .complete ? "No finished challenges yet" : "Your record is loading")
                .floodlightFont(20, weight: .bold, condensed: true)
            Text(snapshot.availability == .complete
                 ? "Your finished challenges will appear here. Find your current goals in Challenges."
                 : "Refresh to see your saved results.")
                .floodlightFont(14).foregroundStyle(Floodlight.muted)
        }
        .padding(20).frame(maxWidth: .infinity, alignment: .leading)
        .floodlightCard()
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
