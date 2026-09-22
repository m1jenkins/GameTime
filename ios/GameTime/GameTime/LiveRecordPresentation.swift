import Foundation

extension LiveChallengePresentation {
    /// Count only explicit final goal outcomes for the account that owns this
    /// snapshot. Wins, partial progress, exits and missing data never qualify.
    /// The caller still uses snapshot.countText to disclose page completeness.
    static func goalsMet(in snapshot: ChallengeProfileSnapshot) -> Int {
        snapshot.finished.filter { row in
            guard row.status == "final", row.format.hasTarget,
                  let actor = snapshot.actor, let member = row.own(actor),
                  member.selected, member.consented, !member.exited,
                  let result = row.final?.result else { return false }
            let outcome = result.participants?[actor.uuidString.lowercased()]?.status
                ?? (row.socialHidden ? result.own?.status : nil)
            return outcome == "met"
        }.count
    }
}
