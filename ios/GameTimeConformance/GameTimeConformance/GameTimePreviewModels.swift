import Foundation

struct PreviewContest: Identifiable, Hashable, Sendable {
    enum Status: String, Hashable, Sendable {
        case live
        case invitation
        case completed
    }

    let id: String
    let title: String
    let metric: String
    let metricIcon: String
    let currentParticipant: String
    let opponent: String
    let currentValue: Int
    let opponentValue: Int
    let targetValue: Int
    let progressUnit: String
    let periodLabel: String
    let stakeCents: Int
    let currentCharity: String
    let opponentCharity: String
    let evidenceSummary: String
    let status: Status

    var currentProgress: Double {
        guard targetValue > 0 else { return 0 }
        return min(Double(currentValue) / Double(targetValue), 1)
    }

    var opponentProgress: Double {
        guard targetValue > 0 else { return 0 }
        return min(Double(opponentValue) / Double(targetValue), 1)
    }

    var stakeLabel: String {
        "$\(stakeCents / 100)"
    }
}

struct PreviewFriend: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let handle: String
    let initials: String
    let sharedActivity: String
    let accentIndex: Int
}

enum PreviewFixtures {
    static let activeContest = PreviewContest(
        id: "active-move-streak",
        title: "5-Day Move Streak",
        metric: "Completed days",
        metricIcon: "figure.run",
        currentParticipant: "You",
        opponent: "Alex",
        currentValue: 4,
        opponentValue: 3,
        targetValue: 5,
        progressUnit: "days",
        periodLabel: "Ends Friday · 2 days left",
        stakeCents: 2500,
        currentCharity: "Central Texas Food Bank",
        opponentCharity: "Austin Pets Alive!",
        evidenceSummary: "Health data + 2 verified check-ins",
        status: .live
    )

    static let invitation = PreviewContest(
        id: "invitation-sunrise-steps",
        title: "Sunrise Steps",
        metric: "Daily steps",
        metricIcon: "sunrise.fill",
        currentParticipant: "You",
        opponent: "Jordan",
        currentValue: 0,
        opponentValue: 0,
        targetValue: 10_000,
        progressUnit: "steps/day",
        periodLabel: "Starts Monday · 7 days",
        stakeCents: 1500,
        currentCharity: "Meals on Wheels Central Texas",
        opponentCharity: "The Trail Conservancy",
        evidenceSummary: "Health data required",
        status: .invitation
    )

    static let completedContest = PreviewContest(
        id: "completed-weekend-warrior",
        title: "Weekend Warrior",
        metric: "Completed workouts",
        metricIcon: "dumbbell.fill",
        currentParticipant: "You",
        opponent: "Sam",
        currentValue: 3,
        opponentValue: 3,
        targetValue: 3,
        progressUnit: "workouts",
        periodLabel: "Finished Sunday · All-donate tie",
        stakeCents: 2000,
        currentCharity: "Central Texas Food Bank",
        opponentCharity: "TreeFolks",
        evidenceSummary: "Final evidence verified",
        status: .completed
    )

    static let friends = [
        PreviewFriend(
            id: "alex",
            name: "Alex Chen",
            handle: "@alexmoves",
            initials: "AC",
            sharedActivity: "Competing in 5-Day Move Streak",
            accentIndex: 0
        ),
        PreviewFriend(
            id: "jordan",
            name: "Jordan Lee",
            handle: "@jordangoes",
            initials: "JL",
            sharedActivity: "Invited you to Sunrise Steps",
            accentIndex: 1
        ),
        PreviewFriend(
            id: "sam",
            name: "Sam Rivera",
            handle: "@samstrong",
            initials: "SR",
            sharedActivity: "Completed 2 challenges with you",
            accentIndex: 2
        ),
        PreviewFriend(
            id: "priya",
            name: "Priya Shah",
            handle: "@priyapaces",
            initials: "PS",
            sharedActivity: "Member of Sunday Striders",
            accentIndex: 3
        ),
    ]
}
