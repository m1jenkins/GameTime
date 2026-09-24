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
                        .liveFont(size: 14, weight: .semibold).foregroundStyle(SignalTheme.accent)
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
            line(glyph: "calendar", title: "Agree to " + LiveChallengePresentation.title(row),
                 detail: "Before " + Self.deadline(row), urgent: true) {
                Button("Review") { viewGoal(row.id) }.buttonStyle(FriendsPillStyle(kind: .filled))
                    .accessibilityLabel("Review \(LiveChallengePresentation.title(row))")
            }
        case .incoming(let person):
            line(person: person, detail: "Friend request") {
                FriendsActionGroup(spacing: 6) {
                    Button("Decline") { Task { await friends?.perform(.decline, person: person) } }
                        .buttonStyle(FriendsPillStyle(kind: .quiet))
                        .accessibilityLabel("Decline \(person.displayName)’s request")
                    Button("Accept") { Task { await friends?.perform(.accept, person: person) } }
                        .buttonStyle(FriendsPillStyle(kind: .filled))
                        .accessibilityLabel("Accept \(person.displayName)’s request")
                }.disabled(friends?.canAct != true)
            }
        case .invitation(let row):
            let from = row.members.first { $0.actorId == row.creatorId }?.username
            line(glyph: "envelope", title: LiveChallengePresentation.title(row),
                 detail: (from.map { "From \($0) · " } ?? "") + ChallengePresentation.dates(row)) {
                Button("Review") { viewGoal(row.id) }.buttonStyle(FriendsPillStyle(kind: .quiet))
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

    private func line<Trailing: View>(glyph: String, title: String, detail: String, urgent: Bool = false,
                                      @ViewBuilder trailing: () -> Trailing) -> some View {
        rowLayout {
            HStack(spacing: 12) {
                Image(systemName: glyph).font(.system(size: 16)).foregroundStyle(SignalTheme.accent)
                    .frame(width: 40, height: 40).background(SignalTheme.selection, in: Circle())
                    .accessibilityHidden(true)
                text(title, detail, urgent: urgent)
            }
            trailing()
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8).frame(minHeight: 64)
    }

    private func line<Trailing: View>(person: FriendPerson, detail: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        rowLayout {
            HStack(spacing: 12) {
                LiveAvatar(username: person.displayName, size: 40).accessibilityHidden(true)
                text(person.displayName, detail)
            }
            trailing()
        }
        .padding(.leading, 14).padding(.trailing, 10).padding(.vertical, 8).frame(minHeight: 64)
    }

    private var rowLayout: AnyLayout {
        typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private func text(_ title: String, _ detail: String, urgent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).liveFont(size: 15, weight: .semibold).lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            Text(detail).liveFont(size: 13, weight: urgent ? .medium : .regular)
                .foregroundStyle(urgent ? SignalTheme.textPrimary : SignalTheme.textSecondary)
                .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// Everyone on the roster agrees before the start, or it's cancelled.
    static func deadline(_ row: ChallengeV1) -> String {
        let zone = TimeZone(identifier: row.config.timezone) ?? .current
        var day = Date.FormatStyle.dateTime.month(.abbreviated).day(); day.timeZone = zone
        var time = Date.FormatStyle(date: .omitted, time: .shortened); time.timeZone = zone
        return row.config.startsAt.date.formatted(day) + ", " + row.config.startsAt.date.formatted(time)
    }
}
