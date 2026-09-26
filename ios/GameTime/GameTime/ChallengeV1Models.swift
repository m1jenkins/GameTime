import Foundation

/// New D134 wire contract. Only timestamp/JSON primitives share old meanings.
typealias ChallengeInstant = DuelInstant
typealias ChallengeJSON = WeeklyJSON

struct ChallengeV1: Codable, Equatable, Identifiable, Sendable {
    struct Window: Codable, Equatable, Sendable {
        let startDate: String; let days: Int; let timezone: String; let amountCents: Int
        var distanceMm: Int? = nil
        let startsAt: ChallengeInstant; let endsAt: ChallengeInstant
        let syncBy: ChallengeInstant; let correctionsBy: ChallengeInstant; let noticeDue: ChallengeInstant
    }
    struct Agreement: Codable, Equatable, Sendable { let digest: String; let terms: ChallengeJSON? }
    struct Fact: Codable, Equatable, Sendable {
        let value: Int?; let state: String; let recordedAt: ChallengeInstant; let revision: Int
    }
    struct Member: Codable, Equatable, Identifiable, Sendable {
        let actorId: UUID; let username: String; let target: Int?; let selected: Bool
        let exited: Bool; let consented: Bool; let fact: Fact?
        var id: UUID { actorId }
    }
    struct Allocation: Codable, Equatable, Sendable {
        struct Person: Codable, Equatable, Sendable { let status: String; let returnedCents: Int }
        let outcome: String?; let participants: [String: Person]?; let own: Person?
        let entryCents: Int?; let unallocatedCents: Int?; let simulation: String?
    }
    struct Notice: Codable, Equatable, Sendable {
        let revision: Int; let recordedAt: ChallengeInstant; let reviewBy: ChallengeInstant; let result: Allocation?
    }
    struct Review: Codable, Equatable, Identifiable, Sendable {
        var noticeRevision: Int? = nil
        let id: UUID; let reason: String; let filedAt: ChallengeInstant; let resolveBy: ChallengeInstant; let decision: String?
    }
    struct Final: Codable, Equatable, Sendable { let recordedAt: ChallengeInstant; let result: Allocation }
    struct Counts: Codable, Equatable, Sendable {
        let joined: Int?
        var state: String? = nil
        var asOf: ChallengeInstant? = nil

        func disclosedJoined(at serverTime: ChallengeInstant) -> Int? {
            guard state == "available", let joined, (5...250).contains(joined), let asOf,
                  serverTime.microseconds - asOf.microseconds >= 900_000_000 else { return nil }
            return joined
        }
        func text(at serverTime: ChallengeInstant) -> String {
            if let joined = disclosedJoined(at: serverTime) {
                return "\(joined.formatted()) people joined · updated at least 15 minutes ago."
            }
            return "Participant totals stay hidden until at least five people have joined and a delayed update is available."
        }
    }
    var sourcePolicyVersion: String? = nil
    var counts: Counts? = nil
    let id: UUID; let creatorId: UUID?; let policy: String; let config: Window
    let status: String; let revision: Int; let agreementVersion: Int
    let serverTime: ChallengeInstant; let socialHidden: Bool; let agreement: Agreement?
    let members: [Member]; let notice: Notice?; let reviews: [Review]; let final: Final?
    var showsRanking: Bool { !format.hasTarget && (sourcePolicyVersion == nil || format.usesReceivedScores) }
    func savedScore(_ member: Member) -> Int? {
        guard let fact = member.fact,
              fact.state == (sourcePolicyVersion == nil ? "complete" : "value"),
              !format.usesReceivedScores || fact.recordedAt <= config.correctionsBy else { return nil }
        return fact.value
    }
    func rankableScore(_ member: Member) -> Int? {
        guard !member.exited, member.selected, member.consented else { return nil }
        if format.usesReceivedScores {
            let result = final?.result ?? notice?.result
            let status = result?.participants?[member.actorId.uuidString.lowercased()]?.status ?? (socialHidden ? result?.own?.status : nil)
            if let status, ["excluded", "unranked", "void"].contains(status) { return nil }
        }
        return savedScore(member)
    }
    var rankedMembers: [Member] {
        guard showsRanking else { return members }
        return members.sorted { a, b in
            let av = rankableScore(a)
            let bv = rankableScore(b)
            if av != bv {
                if let av, let bv { return format.metric == .timed ? av < bv : av > bv }
                return av != nil
            }
            return a.actorId.uuidString < b.actorId.uuidString
        }
    }
    var isClosed: Bool { ["final", "void", "cancelled"].contains(status) }
    func own(_ actor: UUID?) -> Member? { members.first { $0.actorId == actor } }
    var format: ChallengeV1Policy { ChallengeV1Policy(rawValue: policy)! }
    var title: String { ChallengeV1Policy(rawValue: policy)?.title ?? "Challenge" }
    var statusText: String {
        switch status {
        case "published_open": "Joining is open"
        case "lobby_open": format.usesReceivedScores ? "Choose your roster" : "Choose your goals"
        case "consent_pending": "Review and agree"
        case "scheduled": "Starts soon"
        case "active": "In progress"
        case "syncing": "Waiting for activity"
        case "review": "Review your result"
        case "final": "Result confirmed"
        case "void": "This challenge didn’t count"
        case "cancelled": "Challenge cancelled"
        default: "Refresh for an update"
        }
    }
    func validate(actor: UUID) throws {
        guard let format = ChallengeV1Policy(rawValue: policy),
              (format.metric == .timed) == (config.distanceMm != nil),
              format.hasTarget || members.allSatisfy({ $0.target == nil }),
              format.mode != .community || socialHidden, revision > 0, (1...30).contains(config.days),
              (100...50000).contains(config.amountCents), config.amountCents % 100 == 0,
              config.startsAt < config.endsAt, members.count <= 30,
              Set(members.map(\.actorId)).count == members.count, own(actor) != nil,
              !socialHidden || members.allSatisfy({ $0.actorId == actor }),
              members.allSatisfy({ ($0.target.map { (1...1_000_000_000).contains($0) } ?? true) &&
                  ($0.fact?.value.map { (0...1_000_000_000).contains($0) } ?? true) })
        else { throw ChallengeV1Error.invalidResponse }
        if let result = final?.result, let people = result.participants {
            guard result.simulation == "nonredeemable", let total = result.entryCents,
                  let remainder = result.unallocatedCents, remainder >= 0,
                  people.values.allSatisfy({ $0.returnedCents >= 0 }),
                  people.values.reduce(remainder, { $0 + $1.returnedCents }) == total
            else { throw ChallengeV1Error.invalidResponse }
        }
    }
}

struct ChallengeV1Receipt: Codable, Equatable, Sendable {
    let id: UUID?; let revision: Int?; let status: String?
    let token: String?; let expiresAt: ChallengeInstant?; let confirmed: Bool?; let saved: Bool?
    var revoked: Bool? = nil
    init(id: UUID? = nil, revision: Int? = nil, status: String? = nil, token: String? = nil,
         expiresAt: ChallengeInstant? = nil, confirmed: Bool? = nil, saved: Bool? = nil, revoked: Bool? = nil) {
        self.id=id; self.revision=revision; self.status=status; self.token=token
        self.expiresAt=expiresAt; self.confirmed=confirmed; self.saved=saved
        self.revoked=revoked
    }
}
/// What the server allows this account to create, and how its activity is
/// verified (challenge_availability_v1). The app no longer infers either from
/// its build. Older servers without the projection leave this nil.
struct ChallengeV1Availability: Decodable, Equatable, Sendable {
    struct Pair: Decodable, Equatable, Sendable { let policy: String; let sourcePolicyVersion: String }
    let restricted: Bool
    let admission: Bool
    let accountAllowed: Bool
    let verificationMode: String
    let policies: [Pair]
    var links: Bool? = nil
    var community: Bool? = nil

    /// The two pairs the owner-only private trial accepted before this
    /// projection existed. Used only when the server doesn't report one.
    static let privateTrialPolicies: Set<String> = ["personal_steps_goal_v1", "personal_distance_goal_v1"]

    /// nil means no per-policy restriction applies.
    var creatablePolicies: Set<String>? { restricted ? Set(policies.map(\.policy)) : nil }
    var accountMode: Bool { verificationMode == "private_account" }
}

struct ChallengeV1Access: Decodable, Equatable, Sendable {
    let serverTime: ChallengeInstant?; let ageConfirmed: Bool; let betaAccess: Bool; let suspended: Bool
    var appealFiled: Bool? = nil
}
struct ChallengeV1Community: Decodable, Equatable, Identifiable, Sendable {
    let id: UUID; let terms: ChallengeJSON; let digest: String; let serverTime: ChallengeInstant; let joinedCount: Int?
    var counts: ChallengeV1.Counts? = nil
}
struct ChallengeV1Request: Codable, Equatable, Sendable {
    let kind: String; let actorId: UUID; let requestId: UUID; let payload: ChallengeJSON
    init(actor: UUID, id: UUID = UUID(), payload: ChallengeJSON) {
        kind = "challenge_request_v1"; actorId = actor; requestId = id; self.payload = payload
    }
    var body: Data { get throws {
        guard kind == "challenge_request_v1", payload["op"]?.string != nil else { throw ChallengeV1Error.storage }
        return try ChallengeJSON.data(.object(["p_request_id": .string(requestId.uuidString.lowercased()), "p_payload": payload]))
    } }
}

/// What a challenge screen says while a change the person made hasn't
/// finished: we didn't hear back, or the server turned it down. Retry sends
/// the same change again; cancel asks the server to drop it.
enum ChallengePendingCopy {
    static let title = "Your last change didn’t finish"
    static let message = "Try again, or cancel it to start fresh."
    static let retry = "Try again"
    static let cancel = "Cancel it"
}

enum ChallengeV1Error: Error, LocalizedError, Equatable {
    case unavailable, accountChanged, invalidResponse, storage, server(String)
    var errorDescription: String? {
        switch self {
        case .unavailable: "We couldn’t connect. Check your connection and try again."
        case .accountChanged: "Your account changed or signed out. Sign in again to continue."
        case .invalidResponse: "We couldn’t read this update. Refresh before making another choice."
        case .storage: "We couldn’t save that on your phone. Free up some space and try again."
        case .server(let reason):
            switch reason {
            case "challenge_rate_limited": "You’ve tried several times. Wait a minute before trying again; invitation links and reports may need an hour. You can still read, leave or request a review."
            case "challenge_join_closed": "This community challenge isn’t accepting your entry. Refresh to see the current options."
            case "challenge_discovery_disabled": "Community joining is paused. You can still open a challenge you joined or leave it."
            case "challenge_age_required": "Confirm that you are 21 or older before continuing."
            case "challenge_link_unavailable": "This invitation is unavailable. Ask the creator for a new link."
            case "challenge_stale": "The challenge changed. Refresh, then review the latest rules."
            case "challenge_real_leaderboard_unavailable": "Leaderboards aren’t available yet. Choose a personal or friend goal instead."
            case "challenge_readiness_required": "Your activity isn’t ready yet. Check Apple Health before agreeing."
            case "challenge_admission_paused": "New challenges are paused. You can still read, leave or request a review."
            case "challenge_private_trial_account_required": "This private trial is available only to the selected account. Sign in with the account you were invited to use."
            case "challenge_private_trial_personal_steps_only": "This private trial currently supports Steps and Outdoor runs. Choose one of those to continue."
            case "challenge_metric_overlap": "You already have a friend challenge for this activity during these dates. Choose different dates."
            case "challenge_unsettled_limit": "Three challenges still need a final result. Wait for one to finish before joining another."
            case "challenge_member_unavailable": "Someone you picked can’t join this challenge. Change who’s in, then try again."
            case "challenge_friend_unavailable": "We couldn’t find an available friend with that username. Check the exact spelling."
            case "challenge_incomplete_roster": "Select two to six people. For a goal challenge, everyone must choose their own goal before continuing."
            case "challenge_consent_mismatch": "The rules changed or agreement is closed. Refresh to see what happens next."
            case "challenge_review_closed": "This review window has ended. Refresh to see your result or contact support."
            default: "We couldn’t finish that. Refresh and try again."
            }
        }
    }
}
