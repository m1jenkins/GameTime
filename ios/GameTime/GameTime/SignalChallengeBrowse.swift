import SwiftUI

/// These filters select server-owned sections. They do not count a loaded page
/// as a complete history or move attention-required records into a quiet tab.
enum SignalChallengeFilter: String, CaseIterable, Identifiable {
    case active = "Active", upcoming = "Upcoming", finished = "Finished"
    var id: Self { self }
    var section: ChallengeV1Section {
        switch self { case .active: .active; case .upcoming: .upcoming; case .finished: .history }
    }
    var emptyTitle: String {
        switch self {
        case .active: "No challenges in progress"
        case .upcoming: "No upcoming challenges"
        case .finished: "No finished challenges"
        }
    }
}

struct SignalChallengeBrowse: View {
    @Bindable var store: ChallengeV1Store
    @Binding var filter: SignalChallengeFilter
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let attention = store.sections[.action], !attention.rows.isEmpty || attention.error != nil {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Needs your attention").font(.title3.bold()).accessibilityAddTraits(.isHeader)
                    sectionState(attention)
                    rows(attention.rows)
                    more(.action, state: attention)
                }
            }
            filters
            if let state = store.sections[filter.section] {
                sectionState(state)
                if state.rows.isEmpty {
                    if state.fresh {
                        Text(emptyTitle).font(.title3.weight(.semibold))
                            .foregroundStyle(SignalTheme.textSecondary).padding(.vertical, 24)
                            .accessibilityIdentifier("beta.challenges.empty")
                    } else if state.error == nil {
                        ProgressView("Loading your challenges…")
                    }
                } else {
                    groupedRows(state.rows)
                    more(filter.section, state: state)
                }
            } else {
                ProgressView("Loading your challenges…")
            }
        }
    }

    private var emptyTitle: String {
        if filter == .finished, store.sections[.action]?.rows.contains(where: {
            $0.isClosed || $0.own(store.actor)?.exited == true
        }) == true { return "No other finished challenges" }
        return filter.emptyTitle
    }

    private var filters: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 4) {
                    ForEach(SignalChallengeFilter.allCases) { value in
                        Button { filter = value } label: {
                            HStack {
                                Text(value.rawValue)
                                Spacer()
                                if filter == value { Image(systemName: "checkmark").accessibilityHidden(true) }
                            }.padding(12).frame(minHeight: 44)
                                .background(filter == value ? SignalTheme.selection : .clear, in: Capsule())
                        }.buttonStyle(.plain).accessibilityAddTraits(filter == value ? .isSelected : [])
                            .accessibilityIdentifier("beta.filter." + value.section.rawValue)
                    }
                }.padding(4).modifier(SignalControlMaterial(interactive: false))
            } else {
                Picker("Challenge status", selection: $filter) {
                    ForEach(SignalChallengeFilter.allCases) { value in
                        Text(value.rawValue).tag(value).accessibilityIdentifier("beta.filter." + value.section.rawValue)
                    }
                }.pickerStyle(.segmented).frame(minHeight: 44).accessibilityIdentifier("beta.challenges.filter")
            }
        }
    }

    @ViewBuilder private func sectionState(_ state: ChallengeV1SectionState) -> some View {
        if let message = state.error {
            Text(message).font(.subheadline).foregroundStyle(SignalTheme.textSecondary)
            Button("Refresh") { Task { await store.refresh() } }.buttonStyle(SignalPillButtonStyle())
        } else if !state.fresh && !state.rows.isEmpty {
            Text("This might be out of date. Refresh before you make a choice.").font(.subheadline)
                .foregroundStyle(SignalTheme.textSecondary)
        }
    }

    @ViewBuilder private func groupedRows(_ values: [ChallengeV1]) -> some View {
        ForEach([ChallengeV1Policy.Mode.personal, .friend, .community], id: \.self) { mode in
            let group = values.filter { $0.format.mode == mode }
            if !group.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text(mode == .personal ? "Just for you" : mode == .friend ? "With friends" : "Community")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(SignalTheme.textSecondary)
                        .accessibilityAddTraits(.isHeader)
                    rows(group)
                }
            }
        }
    }

    private func rows(_ values: [ChallengeV1]) -> some View {
        ForEach(values) { row in
            NavigationLink { ChallengeV1Detail(store: store, id: row.id) } label: {
                SignalChallengeSummary(row: row, actor: store.actor)
            }.buttonStyle(.plain)
                .accessibilityIdentifier("beta.row.\(row.status).\(row.policy).\(row.id.uuidString)")
        }
    }

    @ViewBuilder private func more(_ section: ChallengeV1Section, state: ChallengeV1SectionState) -> some View {
        if state.cursor != nil {
            Button("Show more") { Task { await store.loadMore(section) } }
                .buttonStyle(SignalSecondaryButtonStyle()).accessibilityIdentifier("beta.more." + section.rawValue)
        }
    }
}

/// Home presents the next saved goal as an object, rather than another list of
/// field labels. All values come from the current authorized challenge row.
struct SignalHomeGoal: View {
    let row: ChallengeV1
    let actor: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.status == "scheduled" ? "Your next goal" : "Your goal")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.up.right").accessibilityHidden(true)
            }
            if let own = row.own(actor), let target = own.target {
                if row.status == "scheduled" {
                    SignalMetricValue(value: target, metric: row.format.metric)
                    if row.format.metric == .timed, let distance = row.config.distanceMm {
                        Text("Whole run: \(ChallengeV1Policy.Metric.distance.display(distance))").font(.subheadline)
                    }
                } else {
                    SignalGoalProgress(onAccent: true, row: row, member: own, actor: actor)
                }
            } else { Text(row.title).font(.title2.bold()) }
            VStack(alignment: .leading, spacing: 6) {
                Text(ChallengePresentation.dates(row)).font(.headline)
                Text("\(SignalDateSpan.duration(row.config.days)) · \(SignalTimeZone.name(row.config.timezone))")
                    .font(.subheadline)
                Text(row.statusText).font(.subheadline)
            }
        }.padding(SignalTheme.contentInset).frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(SignalTheme.onAccent).background(SignalTheme.accent)
            .padding(.horizontal, -SignalTheme.contentInset)
            .accessibilityElement(children: .combine)
    }
}
