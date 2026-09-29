import SwiftUI

/// One compact group above Home's hero, most urgent first. Each row states one
/// fact and offers one action, and it leaves once handled. At most three show;
/// there are no counts, badges or countdowns.
struct HomeActionRows: View {
    let challenges: ChallengeV1Store
    let viewGoal: (UUID) -> Void
    @Environment(FriendsStore.self) private var friends: FriendsStore?
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showingAll = false

    enum Item: Identifiable {
        case agree(ChallengeV1)
        case incoming(FriendPerson)
        case invitation(ChallengeV1)
        case accepted(FriendPerson)
        var id: String {
            switch self {
            case .agree(let row): "agree." + row.id.uuidString
            case .incoming(let person): "incoming." + person.id.uuidString
            case .invitation(let row): "invitation." + row.id.uuidString
            case .accepted(let person): "accepted." + person.id.uuidString
            }
        }
    }

    /// Challenges come from the fresh server projection only, never a stale copy.
    static func items(challenges: ChallengeV1Store, friends: FriendsStore?) -> [Item] {
        let actor = challenges.actor
        let rows = challenges.challenges.filter { challenges.isFresh($0) && !$0.socialHidden && $0.own(actor)?.exited == false }
        let agree = rows.filter { row in
            guard row.status == "consent_pending", let own = row.own(actor) else { return false }
            return own.selected && !own.consented
        }.sorted { $0.config.startsAt < $1.config.startsAt }
        let invitations = rows.filter { row in
            guard row.status == "lobby_open", row.creatorId != actor, row.format.mode == .friend,
                  row.format.hasTarget, let own = row.own(actor) else { return false }
            return own.target == nil
        }.sorted { $0.config.startsAt < $1.config.startsAt }
        let incoming = friends?.fresh == true ? friends?.incoming ?? [] : []
        let accepted = friends?.fresh == true ? friends?.recentlyAccepted ?? [] : []
        return agree.map(Item.agree) + incoming.map(Item.incoming) + invitations.map(Item.invitation) + accepted.map(Item.accepted)
    }

    var body: some View {
        let all = Self.items(challenges: challenges, friends: friends)
        if !all.isEmpty {
            let shown = showingAll ? all : Array(all.prefix(3))
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(SignalTheme.divider).padding(.leading, 14) }
                    row(item)
                }
                if all.count > shown.count {
                    Divider().overlay(SignalTheme.divider)
                    Button("Show \(all.count - shown.count) more") { showingAll = true }
                        .liveFont(14, weight: .semibold).foregroundStyle(SignalTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .accessibilityIdentifier("home.actions.more")
                }
            }
            .background(SignalTheme.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(SignalTheme.divider.opacity(0.7), lineWidth: 0.75) }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Needs you")
            .accessibilityIdentifier("home.actions")
        }
    }

    @ViewBuilder private func row(_ item: Item) -> some View {
        switch item {
        case .agree(let row):
            let deadline = Self.deadline(row)
            line(glyph: "calendar", title: "Agree to " + LiveChallengePresentation.title(row),
                 detail: deadline.short, spoken: deadline.spoken) {
                // Home's one blue action.
                Button("Review") { viewGoal(row.id) }.buttonStyle(LivePillButtonStyle(kind: .filled))
                    .accessibilityLabel("Review \(LiveChallengePresentation.title(row))")
            }
        case .incoming(let person):
            line(person: person, detail: "Friend request") {
                LiveActionGroup(spacing: 6) {
                    Button("Decline") { Task { await friends?.perform(.decline, person: person) } }
                        .buttonStyle(LivePillButtonStyle(kind: .quiet, ink: Floodlight.ink))
                        .accessibilityLabel("Decline \(person.displayName)’s request")
                    Button("Accept") { Task { await friends?.perform(.accept, person: person) } }
                        .buttonStyle(LivePillButtonStyle(kind: .quiet, ink: Floodlight.ink))
                        .accessibilityLabel("Accept \(person.displayName)’s request")
                }.disabled(friends?.canAct != true)
            }
        case .invitation(let row):
            let from = row.members.first { $0.actorId == row.creatorId }?.username
            line(glyph: "envelope", title: LiveChallengePresentation.title(row),
                 detail: (from.map { "From \($0) · " } ?? "") + ChallengePresentation.dates(row)) {
                Button("Review") { viewGoal(row.id) }.buttonStyle(LivePillButtonStyle(kind: .quiet, ink: Floodlight.ink))
                    .accessibilityLabel("Review \(LiveChallengePresentation.title(row))")
            }
        case .accepted(let person):
            line(person: person, detail: "Accepted your request") {
                Button { Task { await friends?.dismissAccepted(person) } } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SignalTheme.textSecondary).frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("Dismiss")
            }
        }
    }

    private func line<Trailing: View>(glyph: String, title: String, detail: String, spoken: String? = nil,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        stacked {
            HStack(spacing: 12) {
                Image(systemName: glyph).font(.system(size: 16)).foregroundStyle(SignalTheme.accent)
                    .frame(width: 40, height: 40).background(SignalTheme.selection, in: Circle())
                    .accessibilityHidden(true)
                text(title, detail, spoken: spoken)
            }
            trailing()
        }
    }

    private func line<Trailing: View>(person: FriendPerson, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        stacked {
            HStack(spacing: 12) {
                LiveAvatar(username: person.displayName, size: 40).accessibilityHidden(true)
                text(person.displayName, detail)
            }
            trailing()
        }
    }

    /// One row, or the actions under the text when large text needs the width.
    private func stacked<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout { content() }
            .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8).frame(minHeight: 64)
    }

    /// Floodlight 9.3's Next up type: the title in Barlow SemiBold 17 and
    /// the detail in Barlow Regular 15, muted.
    private func text(_ title: String, _ detail: String, spoken: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).floodlightFont(17, weight: .semibold).foregroundStyle(Floodlight.ink)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            Text(detail).floodlightFont(15).foregroundStyle(Floodlight.muted)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
                .accessibilityLabel(spoken ?? detail)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Everyone on the roster agrees before the start, or it's cancelled. The
    /// start is midnight in the challenge's time zone, so the day before is the
    /// last day: "Agree by Sun, Sep 27". The time shows only when it matters:
    /// the start isn't at midnight, or your own day would end after the
    /// deadline, which then also names the challenge's time zone.
    static func deadline(_ row: ChallengeV1, viewer: TimeZone = .current) -> (short: String, spoken: String) {
        let zone = TimeZone(identifier: row.config.timezone) ?? viewer
        let start = row.config.startsAt.date
        let last = start.addingTimeInterval(-60)
        func format(_ template: String) -> String {
            let formatter = DateFormatter(); formatter.timeZone = zone
            formatter.setLocalizedDateFormatFromTemplate(template)
            return formatter.string(from: last)
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var yours = Calendar(identifier: .gregorian); yours.timeZone = viewer
        // When that day ends on your own clock.
        let yourDayEnds = yours.date(from: calendar.dateComponents([.year, .month, .day], from: last))
            .flatMap { yours.date(byAdding: .day, value: 1, to: $0) } ?? start
        guard calendar.startOfDay(for: start) != start || yourDayEnds > start else {
            return ("Agree by " + format("EEEMMMd"), "Agree by " + format("EEEEMMMMd"))
        }
        let clock = format("jmm") + (zone.secondsFromGMT(for: last) == viewer.secondsFromGMT(for: last)
            ? "" : " " + FloodlightInvitationPage.zoneName(zone.identifier))
        return ("Agree by \(format("EEEMMMd")), \(clock)", "Agree by \(format("EEEEMMMMd")) at \(clock)")
    }
}
