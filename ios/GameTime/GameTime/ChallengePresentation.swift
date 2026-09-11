import Foundation

/// Read-only presentation. No outcome or progress is inferred from absent activity.
enum ChallengePresentation {
    static func value(_ member: ChallengeV1.Member, actor: UUID?) -> Int? {
        guard !member.exited || member.actorId == actor,
              member.fact?.state == "complete" else { return nil }
        return member.fact?.value
    }

    static func rank(_ member: ChallengeV1.Member, in row: ChallengeV1, actor: UUID?) -> Int? {
        guard !row.format.hasTarget, !member.exited,
              let value = value(member, actor: actor) else { return nil }
        return 1 + row.members.filter { other in
            guard !other.exited, let otherValue = self.value(other, actor: actor) else { return false }
            return row.format.metric == .timed ? otherValue < value : otherValue > value
        }.count
    }

    static func progress(_ member: ChallengeV1.Member, in row: ChallengeV1, actor: UUID?) -> Double? {
        guard row.format.hasTarget, row.format.metric != .timed,
              let target = member.target, target > 0, let value = value(member, actor: actor) else { return nil }
        return min(1, max(0, Double(value) / Double(target)))
    }

    static func dates(_ row: ChallengeV1) -> String {
        let formatter = DateIntervalFormatter()
        formatter.timeZone = TimeZone(identifier: row.config.timezone)
        formatter.dateTemplate = "MMM d"
        // endsAt is exclusive: display the final included local calendar date.
        return formatter.string(from: row.config.startsAt.date, to: row.config.endsAt.date.addingTimeInterval(-1))
    }

    static func endDate(_ row: ChallengeV1) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: row.config.timezone)
        formatter.setLocalizedDateFormatFromTemplate("EEE MMM d")
        return formatter.string(from: row.config.endsAt.date.addingTimeInterval(-1))
    }

    static func featuredTitle(_ row: ChallengeV1) -> String {
        guard row.config.days == 7, row.format.competition == .leaderboard else { return row.title }
        return switch row.format.metric {
        case .steps: "Weekly steps"
        case .exercise: "Weekly exercise"
        case .distance: "Weekly running"
        case .timed: "Timed run"
        }
    }
}
