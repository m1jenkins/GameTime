import Foundation

enum ChallengeV1HomeState: Equatable {
    case loading, empty, content, unavailable
}

enum ChallengeV1Section: String, CaseIterable, Codable, Sendable {
    case action, active, upcoming, history
    var title: String {
        switch self { case .action: "Needs your attention"; case .active: "In progress"; case .upcoming: "Coming up"; case .history: "Your history" }
    }
    func includes(_ row: ChallengeV1, actor: UUID) -> Bool {
        if row.own(actor)?.exited == true { return self == .history }
        switch self {
        case .action: return ["review", "consent_pending"].contains(row.status)
        case .active: return ["active", "syncing"].contains(row.status)
        case .upcoming: return ["lobby_open", "published_open", "scheduled"].contains(row.status)
        case .history: return row.isClosed
        }
    }
}
struct ChallengeV1Page: Decodable, Equatable, Sendable {
    let section: ChallengeV1Section
    /// Identifies the stable ID ordering; each row carries its current revision.
    let projectionRevision: UUID
    let serverTime: ChallengeInstant
    let expiresAt: ChallengeInstant
    let rows: [ChallengeV1]
    let nextCursor: ChallengeJSON?
}
struct ChallengeV1SectionState: Equatable {
    var rows: [ChallengeV1] = []
    var cursor: ChallengeJSON?
    var projectionRevision: UUID?
    var serverTime: ChallengeInstant?
    var receivedAt: TimeInterval?
    var error: String?
    var fresh = false
}
