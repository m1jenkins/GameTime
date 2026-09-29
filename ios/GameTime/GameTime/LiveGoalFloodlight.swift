import GameTimeCore
import SwiftUI

/// What the Floodlight friend-goal screens show, derived only from the saved
/// challenge row. It never infers a miss: a person without a saved update is
/// "no update", and the pot counts people who agreed and are still in.
enum FloodlightChallengeFacts {
    enum Layout: Equatable { case challenge, invitation, legacy }

    /// Friend goals in progress get the dial; an invitation you still need to
    /// agree to gets the invitation. Everything else keeps its current page.
    static func layout(_ row: ChallengeV1, actor: UUID?) -> Layout {
        guard row.format.mode == .friend, row.format.hasTarget, !row.socialHidden,
              let own = row.own(actor), own.selected, !own.exited else { return .legacy }
        if row.status == "consent_pending", !own.consented { return .invitation }
        if ["active", "syncing"].contains(row.status), row.format.metric != .timed { return .challenge }
        return .legacy
    }

    /// Roster slots pick colors: you are slot 0, everyone else follows the
    /// saved roster order, including people who left, so colors never shift.
    static func slots(_ row: ChallengeV1, actor: UUID?) -> [UUID: Int] {
        var slots: [UUID: Int] = [:]
        if let actor { slots[actor] = 0 }
        for member in row.members where member.actorId != actor { slots[member.actorId] = slots.count }
        return slots
    }

    /// People on the dial: you first, then the roster, never ranked.
    static func people(_ row: ChallengeV1, actor: UUID?) -> [ChallengeV1.Member] {
        let inGroup = row.members.filter { $0.selected && !$0.exited }
        return inGroup.filter { $0.actorId == actor } + inGroup.filter { $0.actorId != actor }
    }

    static func name(_ member: ChallengeV1.Member, actor: UUID?) -> String { member.actorId == actor ? "You" : member.username }
    static func initials(_ member: ChallengeV1.Member, actor: UUID?, profile: UserProfile? = nil) -> String {
        FloodlightOrb.initials(member.actorId == actor ? (profile?.displayName ?? member.username) : member.username)
    }

    static func fraction(_ row: ChallengeV1, _ member: ChallengeV1.Member) -> Double? {
        guard let score = row.savedScore(member), let target = member.target, target > 0 else { return nil }
        if row.format.metric == .timed { return score < target ? 1 : 0 }
        return min(1, max(0, Double(score) / Double(target)))
    }
    static func met(_ row: ChallengeV1, _ member: ChallengeV1.Member) -> Bool { (fraction(row, member) ?? 0) >= 1 }

    static func lanes(_ row: ChallengeV1, actor: UUID?, profile: UserProfile? = nil) -> [FloodlightDial.Lane] {
        let slots = slots(row, actor: actor)
        return people(row, actor: actor).map { member in
            FloodlightDial.Lane(id: member.actorId, slot: slots[member.actorId] ?? 0, fraction: fraction(row, member),
                                initials: initials(member, actor: actor, profile: profile), met: met(row, member),
                                late: syncTime(row, member, actor: actor)?.late == true)
        }
    }

    /// Stake × people who agreed and are still in.
    static func potCents(_ row: ChallengeV1) -> Int {
        row.config.amountCents * row.members.filter { $0.selected && $0.consented && !$0.exited }.count
    }
    static func potSpoken(_ row: ChallengeV1) -> String {
        "Pot: \(LiveChallengePresentation.money(potCents(row))) in simulated stakes, \(LiveChallengePresentation.money(row.config.amountCents)) each."
    }

    /// "Priya reached their goal." Never a ranking; nil when nobody has.
    static func metLine(_ row: ChallengeV1, actor: UUID?) -> String? {
        let everyone = people(row, actor: actor)
        let met = everyone.filter { self.met(row, $0) }
        guard !met.isEmpty else { return nil }
        if met.count == everyone.count { return "Everyone reached their goal." }
        let others = met.filter { $0.actorId != actor }.map(\.username)
        if met.contains(where: { $0.actorId == actor }) {
            return others.isEmpty ? "You reached your goal." : "\(list(["You"] + others)) reached your goals."
        }
        return "\(list(others)) reached their goal\(others.count > 1 ? "s" : "")."
    }
    static func list(_ names: [String]) -> String {
        names.count < 3 ? names.joined(separator: " and ") : names.dropLast().joined(separator: ", ") + " and " + names[names.count - 1]
    }

    /// When a person's saved update arrived. Earlier days show the day and time
    /// with a clock ("late"); today shows how long ago.
    static func syncTime(_ row: ChallengeV1, _ member: ChallengeV1.Member, actor: UUID?) -> (short: String, spoken: String, late: Bool)? {
        guard let fact = member.fact, row.savedScore(member) != nil else { return nil }
        let zone = TimeZone(identifier: row.config.timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let now = row.serverTime.date, then = fact.recordedAt.date
        let prefix = row.sourcePolicyVersion != nil && member.actorId == actor ? "Updated from Apple Health " : "Updated "
        let today = calendar.startOfDay(for: now)
        if then >= today || now.timeIntervalSince(then) < 3600 {
            let minutes = max(0, Int(now.timeIntervalSince(then) / 60))
            let short = minutes < 1 ? "Just now" : minutes < 60 ? "\(minutes) min ago" : "\(minutes / 60) h ago"
            return (short, prefix + (minutes < 1 ? "just now" : short), false)
        }
        let time = DateFormatter(); time.timeZone = zone; time.setLocalizedDateFormatFromTemplate("jmm")
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today).map { then >= $0 } ?? false
        let day: String
        if yesterday { day = "Yesterday" } else {
            let date = DateFormatter(); date.timeZone = zone; date.setLocalizedDateFormatFromTemplate("MMM d")
            day = date.string(from: then)
        }
        let clock = time.string(from: then)
        return ("\(day), \(clock)", prefix + (yesterday ? "yesterday" : day) + " at " + clock, true)
    }

    /// The number and the goal in the same unit: "6.4" and "20 km".
    static func value(_ row: ChallengeV1, _ member: ChallengeV1.Member) -> String {
        LiveChallengePresentation.value(row.savedScore(member), metric: row.format.metric)
    }
    static func goal(_ row: ChallengeV1, _ target: Int) -> String {
        "\(LiveChallengePresentation.value(target, metric: row.format.metric)) \(LiveChallengePresentation.unit(row.format.metric))"
    }
    private static func spokenAmount(_ row: ChallengeV1, _ value: Int) -> String {
        let number = LiveChallengePresentation.value(value, metric: row.format.metric)
        return switch row.format.metric {
        case .distance: "\(number) kilometres"
        case .steps: "\(number) steps"
        case .exercise: "\(number) minutes"
        case .timed: number
        }
    }

    /// "Sam, 7.8 of 20 kilometres, 39 percent of their goal."
    static func spoken(_ row: ChallengeV1, _ member: ChallengeV1.Member, actor: UUID?) -> String {
        let name = name(member, actor: actor)
        guard let score = row.savedScore(member), let target = member.target, let fraction = fraction(row, member) else {
            return "\(name), no update yet."
        }
        let own = member.actorId == actor ? "your" : "their"
        let late = syncTime(row, member, actor: actor).flatMap { $0.late ? ", " + $0.spoken.lowercased() : nil } ?? ""
        return "\(name), \(LiveChallengePresentation.value(score, metric: row.format.metric)) of \(spokenAmount(row, target)), "
            + "\(Int((fraction * 100).rounded())) percent of \(own) goal\(fraction >= 1 ? ", goal reached" : "")\(late)."
    }

    static func stakeSpoken(_ row: ChallengeV1, actor: UUID?) -> String {
        let stake = "Your simulated stake, \(LiveChallengePresentation.money(row.config.amountCents))."
        guard let own = row.own(actor), let target = own.target else { return stake + " Show how the pot works." }
        return met(row, own)
            ? "\(stake) Goal reached. It comes back when results are final. Show how the pot works."
            : "\(stake) Reach \(spokenAmount(row, target)) and it comes back after results are final. Show how the pot works."
    }

    /// Where the challenge is in its days, for the pips.
    static func day(_ row: ChallengeV1) -> (index: Int, spoken: String) {
        let zone = TimeZone(identifier: row.config.timezone) ?? .current
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let start = calendar.startOfDay(for: row.config.startsAt.date)
        let elapsed = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: row.serverTime.date)).day ?? 0
        let index = min(max(0, elapsed), row.config.days)
        let weekday = DateFormatter(); weekday.timeZone = zone; weekday.dateFormat = "EEEE"
        let ends = weekday.string(from: row.config.endsAt.date.addingTimeInterval(-1))
        guard index < row.config.days else { return (index, "Ended \(ends).") }
        return (index, "\(weekday.string(from: row.serverTime.date)), day \(index + 1) of \(row.config.days). Ends \(ends).")
    }

    struct Outcome: Identifiable {
        let kind: FloodlightOutcomePicture.Outcome
        let title: String
        let short: String
        let long: String
        var id: String { title }
    }
    /// COPY.md "Friend-goal pot and Floodlight screens": two-person wording for
    /// exactly two people, group wording for three or more.
    static func outcomes(pair: Bool) -> [Outcome] {
        pair ? [
            .init(kind: .all, title: "Both reach it", short: "Both stakes back", long: "You each get your stake back after results are final."),
            .init(kind: .some, title: "One reaches it", short: "They get both stakes", long: "They get their stake back plus the missed one."),
            .init(kind: .none, title: "Both miss", short: "No one collects", long: "Neither stake comes back. No one collects the pot."),
            // A no-break space keeps "won’t count" on one line.
            .init(kind: .unconfirmed, title: "Couldn’t confirm", short: "Stakes back · Challenge won’t\u{00A0}count",
                  long: "If we can’t confirm a result from Apple Health, both stakes come back and the challenge won’t count.")
        ] : [
            .init(kind: .all, title: "Everyone reaches it", short: "All stakes back", long: "Everyone gets their stake back after results are final."),
            .init(kind: .some, title: "Some reach it", short: "They split missed stakes",
                  long: "They get their stakes back and split missed stakes evenly. Cents that don’t split evenly go to no one."),
            .init(kind: .none, title: "Everyone misses", short: "No one collects", long: "No stakes come back. No one collects the pot."),
            .init(kind: .unconfirmed, title: "Couldn’t confirm", short: "Stake back, not a miss",
                  long: "If we can’t confirm someone’s result from Apple Health, their stake comes back. It doesn’t count as a miss.")
        ]
    }

    // MARK: Invitation

    /// People who agreed first, then people still deciding, in roster order.
    static func seats(_ row: ChallengeV1, actor: UUID?) -> [FloodlightLobbyPot.Seat] {
        let slots = slots(row, actor: actor)
        let group = people(row, actor: actor)
        return (group.filter(\.consented) + group.filter { !$0.consented }).map {
            .init(slot: slots[$0.actorId] ?? 0, initials: initials($0, actor: actor), agreed: $0.consented)
        }
    }
    /// "Jordan agreed. Your seat fills when you agree."
    static func seatLine(_ row: ChallengeV1, actor: UUID?) -> String {
        let agreed = people(row, actor: actor).filter { $0.consented && $0.actorId != actor }.map(\.username)
        return agreed.isEmpty ? "Your seat fills when you agree." : "\(list(agreed)) agreed. Your seat fills when you agree."
    }
    /// "20 km" with "each" when everyone has the same goal, otherwise your own.
    static func goalHeader(_ row: ChallengeV1, actor: UUID?) -> (goal: String, label: String, spoken: String)? {
        let group = people(row, actor: actor)
        guard let target = row.own(actor)?.target else { return nil }
        let names = list(group.map { name($0, actor: actor) })
        let goal = row.format.metric.display(target)
        if group.allSatisfy({ $0.target == target }) { return (goal, "each", "\(names): \(goal) each.") }
        return (goal, "your goal", "Your goal: \(goal).")
    }
    static func sourceFact(_ row: ChallengeV1) -> String {
        switch row.sourcePolicyVersion {
        case "apple_workout_outdoor_distance_v1", "apple_workout_outdoor_timed_v1": "Outdoor runs on Apple Watch"
        case "apple_watch_steps_v1": "Steps on Apple Watch"
        case "apple_watch_exercise_credit_v2": "Activity minutes on Apple Watch"
        default: LiveGoalCopy.sourceTitle(row)
        }
    }
}

// MARK: - Challenge

/// The friend challenge page (Floodlight 9.3): the group dial with the pot,
/// the people under it, the selected person's numbers, your stake and the rules.
struct FloodlightChallengePage: View {
    let row: ChallengeV1
    let actor: UUID?
    var profile: UserProfile? = nil
    let refreshing: Bool
    let canAct: Bool
    /// Apple Health needs attention; nil when there's nothing to say.
    let health: AnyView?
    let recovery: AnyView
    let back: () -> Void
    let pot: () -> Void
    let rules: () -> Void
    let activity: () -> Void
    let refresh: () -> Void
    let leave: () -> Void
    @State private var selected: UUID?
    @State private var chosen = false
    @State private var scrolled = false
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Keeps names level whether or not a person has a "No update" line.
    @ScaledMetric(relativeTo: .caption2) private var statusLine = 12.0

    private var people: [ChallengeV1.Member] { FloodlightChallengeFacts.people(row, actor: actor) }
    private var slots: [UUID: Int] { FloodlightChallengeFacts.slots(row, actor: actor) }
    /// You start selected, as in the design; closing the card clears it.
    private var focus: UUID? { chosen ? selected : actor }

    var body: some View {
        FloodlightScrollPage(scrolled: $scrolled) { topInset in
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    header.padding(.horizontal, 20).padding(.top, topInset + 4)
                    dial.padding(.horizontal, 8).padding(.top, 6)
                    crew.padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 14)
                }
                .background(alignment: .top) { FloodlightSky() }
                .accessibilityElement(children: .contain).accessibilityIdentifier("live.goal.hero")
                panel.padding(.horizontal, 16).padding(.bottom, 28)
            }
        }
        .onChange(of: actor) { chosen = false; selected = nil }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack { FloodlightNavButton(symbol: "chevron.left", label: "Back to Home", action: back).padding(.leading, -2); Spacer() }
                .frame(minHeight: 44)
            FloodlightTitle(LiveChallengePresentation.title(row)).foregroundStyle(Floodlight.ink)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
                .accessibilityAddTraits(.isHeader)
            let day = FloodlightChallengeFacts.day(row)
            let whenLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
            whenLayout {
                // The pips are a picture of the dates line, so it reads both.
                FloodlightLabel(ChallengePresentation.dates(row), color: Floodlight.heroMuted,
                                spoken: "\(ChallengePresentation.dates(row)). \(day.spoken)")
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if row.config.days <= 14 {
                    FloodlightWeekPips(days: row.config.days, today: day.index).accessibilityHidden(true)
                }
            }.padding(.top, 10)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private var dial: some View {
        let lanes = FloodlightChallengeFacts.lanes(row, actor: actor, profile: profile)
        let frame = FloodlightDial.potFrame(.full, count: lanes.count)
        return FloodlightDial(kind: .full, lanes: lanes, potCents: FloodlightChallengeFacts.potCents(row), selected: focus)
            .overlay {
                GeometryReader { proxy in
                    Button(action: pot) { Circle().fill(Color.clear).contentShape(Circle()) }
                        .buttonStyle(.plain)
                        .frame(width: proxy.size.width * frame.diameter, height: proxy.size.width * frame.diameter)
                        .position(x: proxy.size.width * frame.center.x, y: proxy.size.height * frame.center.y)
                        .accessibilityLabel(FloodlightChallengeFacts.potSpoken(row) + " Show how the pot works.")
                        .accessibilityIdentifier("live.goal.pot")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Progress toward each person’s goal")
    }

    private var crew: some View {
        let columns = typeSize.isAccessibilitySize ? 2 : max(1, people.count)
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2, alignment: .top), count: columns), spacing: 10) {
            ForEach(people) { person in
                let on = focus == person.actorId
                let noUpdate = row.savedScore(person) == nil
                Button {
                    selected = person.actorId; chosen = true
                } label: {
                    VStack(spacing: 6) {
                        FloodlightOrb(slot: slots[person.actorId] ?? 0, initials: FloodlightChallengeFacts.initials(person, actor: actor, profile: profile),
                                      size: people.count >= 6 ? 34 : 40, waiting: noUpdate,
                                      badge: FloodlightChallengeFacts.met(row, person) ? .met
                                        : FloodlightChallengeFacts.syncTime(row, person, actor: actor)?.late == true ? .late : .none,
                                      selected: on)
                        Text(FloodlightChallengeFacts.name(person, actor: actor)).floodlightFont(12.5, weight: .semibold)
                            .foregroundStyle(on ? Floodlight.ink : Floodlight.muted)
                            .lineLimit(typeSize.isAccessibilitySize ? nil : 1).minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        if noUpdate {
                            Text("No update").floodlightFont(10, weight: .medium).foregroundStyle(Floodlight.muted)
                        } else {
                            Color.clear.frame(height: statusLine)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44).padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FloodlightChallengeFacts.spoken(row, person, actor: actor))
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }

    private var panel: some View {
        VStack(spacing: 12) {
            detail
            stake
            if let health { health }
            Button(action: activity) {
                HStack(spacing: 12) {
                    Image(systemName: "applewatch").font(.system(size: 17)).foregroundStyle(Floodlight.accent)
                        .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 11).fill(Floodlight.well))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Floodlight.wellEdge, lineWidth: 1))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("What counts").floodlightFont(12.5, weight: .medium).foregroundStyle(Floodlight.muted)
                        Text(LiveGoalCopy.sourceTitle(row)).floodlightFont(15, weight: .semibold).foregroundStyle(Floodlight.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).foregroundStyle(Floodlight.muted)
                }
                .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 60)
                .floodlightCard()
                .accessibilityElement(children: .combine)
            }.buttonStyle(.plain)
            Button("Full rules", action: rules).buttonStyle(FloodlightRowButtonStyle()).accessibilityIdentifier("live.goal.rules")
            // A quiet way out at the end of the list, never red or a pill. The
            // update time on the person card refreshes, so there's no Refresh pill.
            Button("Leave challenge", action: leave).buttonStyle(FloodlightQuietButtonStyle()).disabled(!canAct)
                .accessibilityIdentifier("beta.leave")
            recovery
        }
    }

    @ViewBuilder private var detail: some View {
        if let id = focus, let person = people.first(where: { $0.actorId == id }) {
            let slot = slots[id] ?? 0
            let noUpdate = row.savedScore(person) == nil
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    FloodlightOrb(slot: slot, initials: FloodlightChallengeFacts.initials(person, actor: actor, profile: profile), size: 26, waiting: noUpdate)
                    FloodlightLabel(FloodlightChallengeFacts.name(person, actor: actor), color: Floodlight.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { selected = nil; chosen = true } label: {
                        Image(systemName: "xmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Floodlight.muted)
                            .frame(width: 32, height: 32).background(Circle().fill(Floodlight.well))
                            .overlay(Circle().strokeBorder(Floodlight.wellEdge, lineWidth: 1))
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .buttonStyle(.plain).padding(.vertical, -6).padding(.trailing, -8)
                    .accessibilityLabel(person.actorId == actor ? "Close your numbers" : "Close \(person.username)’s numbers")
                }.frame(minHeight: 32)
                if noUpdate {
                    Text("No update yet").floodlightFont(30, weight: .semibold, condensed: true).foregroundStyle(Floodlight.ink).padding(.top, 8)
                    Text("Missing or partial activity never counts as a miss.").floodlightFont(13.5, weight: .medium)
                        .foregroundStyle(Floodlight.ink).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                } else if let target = person.target {
                    let measure = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                    measure {
                        Text(FloodlightChallengeFacts.value(row, person)).floodlightFont(58, weight: .semibold, condensed: true, maxScale: 1.4)
                            .tracking(-1.2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.5)
                        Text("/ " + FloodlightChallengeFacts.goal(row, target)).floodlightFont(16, weight: .medium).foregroundStyle(Floodlight.muted)
                    }.foregroundStyle(Floodlight.ink).padding(.top, 8)
                    FloodlightProgressBar(fraction: FloodlightChallengeFacts.fraction(row, person) ?? 0, slot: slot).padding(.top, 12).padding(.bottom, 11)
                    let footer = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 10))
                    footer {
                        if FloodlightChallengeFacts.met(row, person) {
                            Label("Goal reached", systemImage: "checkmark").floodlightFont(13, weight: .semibold).foregroundStyle(Floodlight.ink)
                        } else {
                            Text(LiveChallengePresentation.remaining(row, actor: person.actorId)).floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted)
                        }
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                        // The update time is the refresh control.
                        if let sync = FloodlightChallengeFacts.syncTime(row, person, actor: actor) {
                            FloodlightSyncTime(short: sync.short, spoken: sync.spoken, late: sync.late, refreshing: refreshing, refresh: refresh)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .floodlightCard()
            .accessibilityElement(children: .contain)
        } else {
            HStack(spacing: 12) {
                if let line = FloodlightChallengeFacts.metLine(row, actor: actor) {
                    let met = people.filter { FloodlightChallengeFacts.met(row, $0) }.prefix(3)
                    FloodlightFaceStack(people: met.map { person in
                        (slot: slots[person.actorId] ?? 0, initials: FloodlightChallengeFacts.initials(person, actor: actor, profile: profile),
                         badge: FloodlightOrb.Badge.met, waiting: false)
                    }, size: 34)
                    Text(line).floodlightFont(16, weight: .semibold).foregroundStyle(Floodlight.ink).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Tap a name to see their numbers.").floodlightFont(14, weight: .medium).foregroundStyle(Floodlight.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, minHeight: 100)
            .floodlightCard()
            .accessibilityElement(children: .combine)
        }
    }

    private var stake: some View {
        let own = row.own(actor)
        let met = own.map { FloodlightChallengeFacts.met(row, $0) } ?? false
        return Button(action: pot) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    FloodlightLabel("Your stake")
                    Spacer()
                    Image(systemName: "info.circle").font(.system(size: 16)).foregroundStyle(Floodlight.muted)
                }
                FloodlightStakeRail(amount: LiveChallengePresentation.money(row.config.amountCents),
                                    fraction: own.flatMap { FloodlightChallengeFacts.fraction(row, $0) } ?? 0,
                                    goal: own?.target.map { FloodlightChallengeFacts.goal(row, $0) } ?? "", met: met)
                if met {
                    Text("Comes back when results are final.").floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted)
                }
            }
            .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 16)
            .floodlightCard()
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FloodlightChallengeFacts.stakeSpoken(row, actor: actor))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("live.goal.stake")
    }
}

/// The stake as a picture: your coin, the groove you fill toward your goal
/// with a return arrow over it, and the flag at your goal.
struct FloodlightStakeRail: View {
    let amount: String
    let fraction: Double
    let goal: String
    let met: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(spacing: 10) {
            coin
            ZStack(alignment: .bottom) {
                FloodlightReturnArc(met: met).frame(height: 28).padding(.leading, 2).padding(.trailing, 6).padding(.bottom, 12)
                FloodlightProgressBar(fraction: fraction, slot: 0, height: 8).padding(.bottom, 6)
            }.frame(height: 40).frame(minWidth: 40)
            HStack(spacing: 6) {
                Image(systemName: met ? "checkmark" : "flag").font(.system(size: 13, weight: .semibold))
                Text(goal).floodlightFont(15, weight: .semibold, condensed: true).tracking(0.3).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(Floodlight.ink)
            .padding(.horizontal, 11).frame(minHeight: 34)
            .background(Capsule().fill(Floodlight.well))
            .overlay(Capsule().strokeBorder(Floodlight.wellEdge, lineWidth: 1))
            .layoutPriority(1)
        }
        .accessibilityHidden(true)
    }

    private var coin: some View {
        let v = { FloodlightMaterial.value($0, scheme) }
        return Text(amount).floodlightFont(20, weight: .semibold, condensed: true, maxScale: 1.2).lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(v(FloodlightMaterial.coinInk).color)
            .frame(width: 52, height: 52)
            .background {
                Circle().fill(RadialGradient(stops: [.init(color: v(FloodlightMaterial.coinHighlight).color, location: 0),
                                                     .init(color: v(FloodlightMaterial.coin).color, location: 0.62),
                                                     .init(color: v(FloodlightMaterial.coinLow).color, location: 1)],
                                             center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 40))
                    .shadow(color: v(FloodlightMaterial.drop).opacity(0.5).color, radius: 5, x: 0, y: 6)
            }
            .overlay(Circle().strokeBorder(v(FloodlightMaterial.coinRing).color, lineWidth: 3))
    }
}

/// The dashed arc from the flag back to the coin: the stake comes back.
struct FloodlightReturnArc: View {
    let met: Bool
    private func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.9))
        return path
    }
    var body: some View {
        GeometryReader { proxy in
            let rect = CGRect(origin: .zero, size: proxy.size)
            ZStack(alignment: .bottomLeading) {
                path(in: rect).stroke(met ? Floodlight.accent : Floodlight.muted.opacity(0.8),
                                      style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: met ? [] : [3, 3]))
                Path { arrow in
                    arrow.move(to: CGPoint(x: -4.5, y: rect.maxY - 5)); arrow.addLine(to: CGPoint(x: 0, y: rect.maxY + 2))
                    arrow.addLine(to: CGPoint(x: 4.5, y: rect.maxY - 5)); arrow.closeSubpath()
                }.fill(met ? Floodlight.accent : Floodlight.muted.opacity(0.8))
            }
        }
    }
}

// MARK: - Invitation

/// An invitation you still need to agree to (Floodlight 9.3 with round 11.1's
/// decisions): the lobby pot counts only people who agreed, the terms read
/// "$20 each", and the outcomes follow the head count.
struct FloodlightInvitationPage: View {
    let row: ChallengeV1
    let actor: UUID?
    let canAct: Bool
    let recovery: AnyView
    let back: () -> Void
    let pot: () -> Void
    let rules: () -> Void
    let agree: () -> Void
    let decline: () -> Void
    @State private var scrolled = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private var pair: Bool { FloodlightChallengeFacts.people(row, actor: actor).count == 2 }
    private var slots: [UUID: Int] { FloodlightChallengeFacts.slots(row, actor: actor) }

    var body: some View {
        FloodlightScrollPage(scrolled: $scrolled) { topInset in
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    top.padding(.horizontal, 20).padding(.top, topInset + 4)
                    head.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 18)
                }
                .background(alignment: .top) { FloodlightSky() }
                .accessibilityElement(children: .contain).accessibilityIdentifier("live.goal.hero")
                panel.padding(.horizontal, 16).padding(.bottom, 28)
            }
        }
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                FloodlightNavButton(symbol: "chevron.left", label: "Back to Home", action: back).padding(.leading, -2)
                Spacer()
                FloodlightPill(text: "Not started")
            }.frame(minHeight: 44)
            if let creator = row.members.first(where: { $0.actorId == row.creatorId }), creator.actorId != actor {
                HStack(spacing: 10) {
                    FloodlightOrb(slot: slots[creator.actorId] ?? 1, initials: FloodlightOrb.initials(creator.username), size: 30)
                    Text("\(creator.username) invited you").floodlightFont(14, weight: .semibold).foregroundStyle(Floodlight.heroMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 4)
            }
            FloodlightTitle(LiveChallengePresentation.title(row)).foregroundStyle(Floodlight.ink)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private var head: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12)) : AnyLayout(HStackLayout(spacing: 14))
        return layout {
            Button(action: pot) {
                FloodlightLobbyPot(seats: FloodlightChallengeFacts.seats(row, actor: actor), potCents: FloodlightChallengeFacts.potCents(row))
                    .frame(width: typeSize.isAccessibilitySize ? 120 : 92)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Pot: \(LiveChallengePresentation.money(FloodlightChallengeFacts.potCents(row))) in simulated stakes so far. Show how the pot works.")
            .accessibilityIdentifier("live.goal.pot")
            VStack(alignment: .leading, spacing: 6) {
                if let header = FloodlightChallengeFacts.goalHeader(row, actor: actor) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(header.goal).floodlightFont(30, weight: .semibold, condensed: true, maxScale: 1.6).foregroundStyle(Floodlight.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        FloodlightLabel(header.label)
                    }
                    .accessibilityElement(children: .ignore).accessibilityLabel(header.spoken)
                }
                FloodlightLabel("\(ChallengePresentation.dates(row)) · \(Self.zoneName(row.config.timezone))")
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(LiveChallengePresentation.money(FloodlightChallengeFacts.potCents(row))) in the pot")
                    .floodlightFont(14, weight: .semibold).foregroundStyle(Floodlight.ink).padding(.top, 2)
                Text(FloodlightChallengeFacts.seatLine(row, actor: actor)).floodlightFont(12.5, weight: .medium)
                    .foregroundStyle(Floodlight.muted).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.leading, 12).padding(.trailing, 16).padding(.vertical, 12)
        .floodlightHero()
    }

    private var panel: some View {
        VStack(alignment: .leading, spacing: 12) {
            let terms = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            terms {
                term("Stake", LiveChallengePresentation.money(row.config.amountCents), unit: "each")
                term("Fee", "$0")
            }
            Text("Simulated stakes — no real money moves.").floodlightFont(12.5, weight: .medium).foregroundStyle(Floodlight.muted)
                .fixedSize(horizontal: false, vertical: true).padding(.leading, 4).padding(.top, -2)
            FloodlightTitle(pair ? "You both agree to these rules." : "You all agree to these rules.", size: 24).foregroundStyle(Floodlight.ink)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.leading, 2)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
                ForEach(FloodlightChallengeFacts.outcomes(pair: pair)) { outcome in
                    VStack(spacing: 6) {
                        FloodlightOutcomePicture(outcome: outcome.kind, pair: pair).frame(maxWidth: 84)
                        Text(outcome.title).floodlightFont(12.5, weight: .semibold).foregroundStyle(Floodlight.ink)
                        Text(outcome.short).floodlightFont(11.5, weight: .medium).foregroundStyle(Floodlight.muted)
                    }
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 12).frame(maxWidth: .infinity)
                    .floodlightCard(radius: 18, fill: outcome.kind == .unconfirmed ? Floodlight.unconfirmedWash : FloodlightToken.card.color,
                                    dashedEdge: outcome.kind == .unconfirmed ? Floodlight.unconfirmed : nil)
                    .accessibilityElement(children: .combine)
                }
            }
            facts
            Button("Full rules", action: rules).buttonStyle(FloodlightRowButtonStyle()).accessibilityIdentifier("live.goal.rules")
            Button("Review and agree", action: agree).buttonStyle(FloodlightPrimaryButtonStyle()).padding(.top, 4)
                .accessibilityIdentifier("live.goal.agree")
            Button("Decline", action: decline).buttonStyle(FloodlightQuietButtonStyle()).disabled(!canAct)
                .accessibilityIdentifier("live.goal.decline")
            recovery
        }
    }

    private func term(_ label: String, _ value: String, unit: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FloodlightLabel(label)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).floodlightFont(30, weight: .semibold, condensed: true, maxScale: 1.6).monospacedDigit()
                if let unit { Text(unit).floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted) }
            }.foregroundStyle(Floodlight.ink)
        }
        .padding(.horizontal, 12).padding(.top, 12).padding(.bottom, 11).frame(maxWidth: .infinity, alignment: .leading)
        .floodlightCard(radius: 18)
        .accessibilityElement(children: .combine)
    }

    private var facts: some View {
        let lines: [(String, String)] = [("applewatch", FloodlightChallengeFacts.sourceFact(row)),
                                         ("circle.dashed", "Missing or partial activity never counts as a miss."),
                                         ("magnifyingglass", "48 h to ask for a review"),
                                         ("arrow.turn.up.left", "Leave before your result is final")]
        return VStack(spacing: 0) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                if index > 0 { Rectangle().fill(Floodlight.line).frame(height: 1) }
                HStack(spacing: 12) {
                    Image(systemName: line.0).font(.system(size: 16, weight: .medium)).foregroundStyle(Floodlight.accent)
                        .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 11).fill(Floodlight.well))
                        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Floodlight.wellEdge, lineWidth: 1))
                        .accessibilityHidden(true)
                    Text(line.1).floodlightFont(14, weight: .medium).foregroundStyle(Floodlight.ink)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                }.padding(.vertical, 6).frame(minHeight: 50)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 4)
        .floodlightCard()
    }

    /// "Pacific Time": the zone's everyday name.
    static func zoneName(_ identifier: String) -> String {
        guard let zone = TimeZone(identifier: identifier) else { return identifier }
        return zone.localizedName(for: .generic, locale: .current) ?? identifier
    }
}

// MARK: - The pot

/// The pot sheet: who put in what, then what happens to the pot in each
/// outcome, in COPY.md's two-person or group wording.
struct FloodlightPotSheet: View {
    let row: ChallengeV1
    let actor: UUID?
    let rules: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    private var people: [ChallengeV1.Member] { FloodlightChallengeFacts.people(row, actor: actor) }
    /// Before the start the pot holds only people who agreed, so the sheet
    /// skips the everyone-in picture.
    private var everyoneIn: Bool { people.allSatisfy(\.consented) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    FloodlightTitle("The pot", size: 26).foregroundStyle(Floodlight.ink).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(Floodlight.muted)
                            .frame(width: 32, height: 32).background(Circle().fill(Floodlight.well))
                            .overlay(Circle().strokeBorder(Floodlight.wellEdge, lineWidth: 1))
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }.buttonStyle(.plain).accessibilityLabel("Close").accessibilityIdentifier("sheet.close")
                }
                if everyoneIn { potPicture }
                ForEach(FloodlightChallengeFacts.outcomes(pair: people.count == 2)) { outcome in
                    HStack(spacing: 14) {
                        FloodlightOutcomePicture(outcome: outcome.kind, pair: people.count == 2).frame(width: 72)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.title).floodlightFont(15, weight: .semibold).foregroundStyle(Floodlight.ink)
                            Text(outcome.long).floodlightFont(13, weight: .medium).foregroundStyle(Floodlight.muted)
                        }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(12).frame(minHeight: 62)
                    .floodlightCard(radius: 18, fill: outcome.kind == .unconfirmed ? Floodlight.unconfirmedWash : FloodlightToken.card.color,
                                    dashedEdge: outcome.kind == .unconfirmed ? Floodlight.unconfirmed : nil)
                    .accessibilityElement(children: .combine)
                }
                Text("Simulated stakes — no real money moves.").floodlightFont(12.5, weight: .semibold).foregroundStyle(Floodlight.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 6)
                Button("Full rules", action: rules).buttonStyle(FloodlightRowButtonStyle()).accessibilityIdentifier("live.pot.rules")
            }
            .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 30)
        }
        .background(FloodlightToken.sheet.color.ignoresSafeArea())
        .presentationDetents([.large]).presentationDragIndicator(.visible).presentationCornerRadius(30)
        .presentationBackground(FloodlightToken.sheet.color)
    }

    private var potPicture: some View {
        let slots = FloodlightChallengeFacts.slots(row, actor: actor)
        let stake = LiveChallengePresentation.money(row.config.amountCents)
        return VStack(spacing: 10) {
            HStack(alignment: .top, spacing: 4) {
                ForEach(people) { person in
                    VStack(spacing: 0) {
                        FloodlightOrb(slot: slots[person.actorId] ?? 0, initials: FloodlightChallengeFacts.initials(person, actor: actor), size: 34)
                        Rectangle().fill(Floodlight.muted.opacity(0.7)).frame(width: 2, height: 22).mask(
                            VStack(spacing: 4) { ForEach(0..<4, id: \.self) { _ in Rectangle().frame(height: 3) } }
                        ).padding(.top, 6)
                        FloodlightMiniCoin(amount: stake)
                    }.frame(maxWidth: .infinity)
                }
            }
            HStack {
                Text(LiveChallengePresentation.money(FloodlightChallengeFacts.potCents(row)))
                    .floodlightFont(40, weight: .semibold, condensed: true, maxScale: 1.4).monospacedDigit()
                Spacer()
                Text("\(people.count) × \(stake)").floodlightFont(14, weight: .semibold)
            }
            .foregroundStyle(FloodlightToken.potInk.color)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 18).fill(LinearGradient(colors: [FloodlightToken.potBarTop.color, FloodlightToken.potBarBottom.color],
                                                                            startPoint: .top, endPoint: .bottom)))
        }
        .padding(14)
        .floodlightCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FloodlightChallengeFacts.potSpoken(row))
    }
}

private struct FloodlightMiniCoin: View {
    let amount: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let v = { FloodlightMaterial.value($0, scheme) }
        Text(amount).font(.custom(FloodlightFonts.face(.semibold, condensed: true), fixedSize: 11)).lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(v(FloodlightMaterial.coinInk).color)
            .frame(width: 24, height: 24)
            .background(Circle().fill(RadialGradient(stops: [.init(color: v(FloodlightMaterial.coinHighlight).color, location: 0),
                                                            .init(color: v(FloodlightMaterial.coin).color, location: 0.62),
                                                            .init(color: v(FloodlightMaterial.coinLow).color, location: 1)],
                                                    center: UnitPoint(x: 0.4, y: 0.3), startRadius: 0, endRadius: 18)))
            .overlay(Circle().strokeBorder(v(FloodlightMaterial.coinRing).color, lineWidth: 2))
    }
}

// MARK: - Page scaffold

/// A Floodlight page: the sky runs up behind the status bar, and once the
/// page scrolls, the status bar gets the ground color so text stays readable.
struct FloodlightScrollPage<Content: View>: View {
    @Binding var scrolled: Bool
    @ViewBuilder let content: (CGFloat) -> Content
    var body: some View {
        GeometryReader { proxy in
            let top = proxy.safeAreaInsets.top
            ScrollView {
                content(top)
            }
            .scrollIndicators(.hidden)
            .ignoresSafeArea(.container, edges: .top)
            .onScrollGeometryChange(for: Bool.self, of: { $0.contentOffset.y + $0.contentInsets.top > 4 }) { _, value in scrolled = value }
            .overlay(alignment: .top) {
                Rectangle().fill(Floodlight.statusScrolled)
                    .overlay(alignment: .bottom) { Rectangle().fill(Floodlight.line).frame(height: 1) }
                    .frame(height: top).ignoresSafeArea(.container, edges: .top)
                    .opacity(scrolled ? 1 : 0).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
        .background(Floodlight.ground.ignoresSafeArea())
    }
}

// MARK: - Apple Health

/// Apple Health on the challenge page (Floodlight 11.1): what's wrong in one
/// line, a neutral gray action, and the same "Manage access" link as Settings.
struct FloodlightHealthCard: View {
    @Bindable var flow: ChallengeHealthFlowStore
    let binding: ChallengeHealthBinding
    let refreshing: Bool
    let refresh: () -> Void
    var body: some View {
        let state = flow.state(for: binding)
        let notConnected = state.readiness == .notConnected && !state.notSaved
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "heart.text.clipboard").font(.system(size: 16)).foregroundStyle(Floodlight.accent)
                    .frame(width: 34, height: 34).background(RoundedRectangle(cornerRadius: 11).fill(Floodlight.well))
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Floodlight.wellEdge, lineWidth: 1))
                    .accessibilityHidden(true)
                Text(notConnected ? ChallengeHealthCopy.notConnectedCardTitle : ChallengeHealthCopy.title(state))
                    .floodlightFont(15.5, weight: .semibold).foregroundStyle(Floodlight.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("beta.health.state")
            }
            Text(state.notSaved ? ChallengeHealthCopy.notSaved
                 : notConnected ? ChallengeHealthCopy.notConnectedCardBody(binding.metric)
                 : ChallengeHealthCopy.explanation(state.readiness, timed: binding.metric == .timedRunElapsedSeconds, readiness: false))
                .floodlightFont(13.5, weight: .medium).foregroundStyle(Floodlight.muted).fixedSize(horizontal: false, vertical: true)
            if state.pendingDelivery {
                Text("Waiting to send this update").floodlightFont(13.5, weight: .medium).foregroundStyle(Floodlight.ink)
                    .accessibilityIdentifier("beta.health.pending")
            }
            if let message = state.message {
                Text(message).floodlightFont(13.5, weight: .medium).foregroundStyle(Floodlight.ink).fixedSize(horizontal: false, vertical: true)
            }
            if notConnected {
                Button("Connect") {
                    Task {
                        await flow.checkReadiness(binding, connect: true)
                        await flow.refresh(binding.challengeID)
                    }
                }.buttonStyle(FloodlightCalmButtonStyle(height: 48))
                    .accessibilityLabel("Connect Apple Health").accessibilityIdentifier("beta.health.connect")
            } else if !state.notSaved {
                Button(refreshing ? "Refreshing…" : "Refresh activity", action: refresh)
                    .buttonStyle(FloodlightCalmButtonStyle(height: 48)).disabled(refreshing)
                    .accessibilityIdentifier("live.goal.refresh")
            }
            Link("Manage access in Apple Health", destination: URL(string: "https://support.apple.com/en-us/HT204351")!)
                .floodlightFont(13.5, weight: .semibold).foregroundStyle(Floodlight.link).frame(minHeight: 40)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .floodlightCard()
    }
}
