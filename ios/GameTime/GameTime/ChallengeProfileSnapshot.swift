import Foundation

/// A view of the actor's currently loaded challenge pages, never a lifetime
/// activity aggregate. A bounded page or failed read cannot establish a zero.
struct ChallengeProfileSnapshot {
    enum Availability: Equatable { case complete, partial, stale, unavailable }

    let availability: Availability
    let rows: [ChallengeV1]
    let sectionsWithMore: [ChallengeV1Section]
    let checkedAt: ChallengeInstant?
    let actor: UUID?

    init(actor: UUID?, sections: [ChallengeV1Section: ChallengeV1SectionState], now: TimeInterval,
         aggregateFresh: Bool = true) {
        self.actor = actor
        guard let actor else {
            availability = .unavailable; rows = []; sectionsWithMore = []; checkedAt = nil
            return
        }
        let readable = sections.filter { _, state in
            state.receivedAt.map { now >= $0 && now - $0 < 60 } == true
        }
        var unique: [UUID: ChallengeV1] = [:]
        for section in ChallengeV1Section.allCases {
            for row in readable[section]?.rows ?? [] where row.own(actor) != nil {
                if let previous = unique[row.id], previous.revision > row.revision { continue }
                unique[row.id] = row
            }
        }
        rows = unique.values.sorted {
            if $0.config.startsAt != $1.config.startsAt { return $0.config.startsAt > $1.config.startsAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        sectionsWithMore = ChallengeV1Section.allCases.filter { readable[$0]?.cursor != nil }
        checkedAt = readable.values.compactMap(\.serverTime).min()
        if readable.isEmpty {
            availability = .unavailable
        } else if sections.values.contains(where: { !$0.fresh || $0.error != nil }) || readable.count != sections.count {
            availability = .stale
        } else if readable.count != ChallengeV1Section.allCases.count {
            availability = .partial
        } else if !aggregateFresh {
            // An uncertain mutation or restricted account can invalidate the
            // aggregate without changing the cached pages' freshness flags.
            availability = .stale
        } else if !sectionsWithMore.isEmpty {
            availability = .partial
        } else {
            availability = .complete
        }
    }

    var upcoming: [ChallengeV1] { rows.filter { $0.status == "scheduled" && $0.own(actor)?.exited == false } }
    var active: [ChallengeV1] { rows.filter { ["active", "syncing", "review"].contains($0.status) && $0.own(actor)?.exited == false } }
    var finished: [ChallengeV1] { rows.filter { $0.isClosed || $0.own(actor)?.exited == true } }
    var featured: ChallengeV1? {
        active.first ?? upcoming.min { $0.config.startsAt < $1.config.startsAt }
            ?? rows.first { !$0.isClosed && $0.own(actor)?.exited == false }
    }

    /// Only finalized competitive allocations establish wins or losses.
    /// Missing scores, goals, exits, unresolved results and voids never do.
    var competitiveResults: [(row: ChallengeV1, won: Bool)] {
        rows.compactMap { row in
            guard row.format.mode == .friend, row.format.competition == .leaderboard,
                  row.status == "final", let result = row.final?.result,
                  result.outcome == "scored", let member = row.own(actor),
                  member.selected, member.consented, !member.exited,
                  let actor else { return nil }
            let status = result.participants?[actor.uuidString.lowercased()]?.status
                ?? (row.socialHidden ? result.own?.status : nil)
            guard status == "winner" || status == "placed" else { return nil }
            return (row, status == "winner")
        }
    }

    var wins: Int { competitiveResults.filter(\.won).count }
    var losses: Int { competitiveResults.filter { !$0.won }.count }

    func countText(_ count: Int) -> String {
        switch availability {
        case .complete: count.formatted()
        case .partial: count == 0 ? "—" : "\(count.formatted())+"
        case .stale, .unavailable: "—"
        }
    }

    var scopeText: String {
        switch availability {
        case .complete: "All saved challenges loaded."
        case .partial: "Showing loaded challenges. Load more to see the rest."
        case .stale: "This view may be out of date. Refresh to update it."
        case .unavailable: "Your challenges aren’t available right now. Refresh to try again."
        }
    }
}
