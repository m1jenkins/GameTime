#if DEBUG
import CryptoKit
import Foundation

/// Explicit, in-memory screenshot data. Nothing in this file selects a hosted
/// client, changes admission, or substitutes a fictional record in ordinary use.
@MainActor
enum LiveDesignFixtures {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--fixture-live-design") }
    // Matches FixtureServicesFactory's authenticated caller.
    static let actorID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    static let samID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    static let jordanID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    static let priyaID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    static let activeID = UUID(uuidString: "a1000000-0000-4000-8000-000000000001")!
    static let invitationID = UUID(uuidString: "a1000000-0000-4000-8000-000000000002")!
    static let upcomingID = UUID(uuidString: "a1000000-0000-4000-8000-000000000003")!
    static let stepsID = UUID(uuidString: "a1000000-0000-4000-8000-000000000004")!
    static let runsID = UUID(uuidString: "a1000000-0000-4000-8000-000000000005")!
    static let closedID = UUID(uuidString: "a1000000-0000-4000-8000-000000000006")!
    static let now = try! ChallengeInstant("2026-09-22T09:41:00-07:00")
    static let profile = UserProfile(id: actorID, handle: "alexlee", displayName: "Alex Lee", timezone: "America/Los_Angeles")

    static func makeClient() -> any ChallengeV1Client { LiveDesignFixtureClient() }
    static func makeProfileClient() -> any ProfileClient { LiveDesignFixtureProfileClient() }
    static func displayTitle(for id: UUID) -> String? {
        [activeID: "September runs", invitationID: "October runs", upcomingID: "Park runs",
         stepsID: "September steps", runsID: "A week outside", closedID: "Midday steps"][id]
    }
    static func portraitName(for actor: UUID) -> String? {
        [actorID: "alex", samID: "sam", jordanID: "jordan", priyaID: "priya"][actor]
    }
    static func lockedDate(for id: UUID) -> Date? {
        if id == activeID { return try! ChallengeInstant("2026-09-19T12:00:00-07:00").date }
        return nil
    }
}

@MainActor
private final class LiveDesignFixtureProfileClient: ProfileClient {
    func currentProfile(userID: UUID) async throws -> UserProfile? {
        userID == LiveDesignFixtures.actorID ? LiveDesignFixtures.profile : nil
    }
    func createProfile(userID: UUID, handle: String, displayName: String, timezone: String) async throws -> UserProfile {
        guard userID == LiveDesignFixtures.actorID else { throw ChallengeV1Error.accountChanged }
        return UserProfile(id: userID, handle: handle, displayName: displayName, timezone: timezone)
    }
}

/// Supports the existing UI's explicit local actions and exact request replay.
/// This is not a replacement for server policy/conformance tests. Unsupported
/// actions fail; the fixture never silently reports them as saved.
@MainActor
final class LiveDesignFixtureClient: ChallengeV1Client {
    private var rows: [UUID: ChallengeV1]
    private var completed: [UUID: (request: ChallengeV1Request, receipt: ChallengeV1Receipt)] = [:]
    private var links: [UUID: (challenge: UUID, token: String)] = [:]
    private var projection = UUID()
    private let clock: ChallengeInstant
    private var friendState = LiveDesignFixtures.friendList()
    private var friendReceipts: [UUID: (command: FriendCommand, receipt: FriendReceipt)] = [:]

    init(now: ChallengeInstant = LiveDesignFixtures.now) {
        clock = now
        rows = Dictionary(uniqueKeysWithValues: Self.seedRows(now: now).map { ($0.id, $0) })
    }

    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        guard cursor == nil else { throw ChallengeV1Error.invalidResponse }
        let values = try await list(actor: actor).filter { section.includes($0, actor: actor) }
        return .init(section: section, projectionRevision: projection, serverTime: clock,
                     expiresAt: .init(date: clock.date.addingTimeInterval(120)), rows: values, nextCursor: nil)
    }
    func list(actor: UUID) async throws -> [ChallengeV1] {
        try checkActor(actor)
        let values = rows.values.sorted {
            if $0.config.startsAt != $1.config.startsAt { return $0.config.startsAt > $1.config.startsAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        for row in values { try row.validate(actor: actor) }
        return values
    }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 {
        try checkActor(actor)
        guard let row = rows[id] else { throw ChallengeV1Error.unavailable }
        try row.validate(actor: actor)
        return row
    }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        try checkActor(request.actorId)
        if let saved = completed[request.requestId] {
            guard saved.request == request else { throw ChallengeV1Error.invalidResponse }
            return saved.receipt
        }
        let receipt = try perform(request)
        completed[request.requestId] = (request, receipt)
        projection = UUID()
        return receipt
    }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        try checkActor(request.actorId)
        if let saved = completed[request.requestId] {
            guard saved.request == request else { throw ChallengeV1Error.invalidResponse }
            return saved.receipt
        }
        let receipt = ChallengeV1Receipt(status: "cancelled_request", confirmed: true)
        completed[request.requestId] = (request, receipt)
        return receipt
    }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        try checkActor(actor)
        let payload: ChallengeJSON
        switch name {
        case "challenge_access_status_v1":
            payload = .object(["server_time": .string(clock.rawValue), "age_confirmed": .bool(true),
                               "beta_access": .bool(true), "suspended": .bool(false), "appeal_filed": .bool(false)])
        case "challenge_community_catalog_v1": payload = .array([])
        case "challenge_personal_preview_v1":
            guard let raw = fields["p_policy"]?.string, let policy = ChallengeV1Policy(rawValue: raw), policy.mode == .personal,
                  let config = fields["p_config"], let target = fields["p_target"]?.integer,
                  (1...1_000_000_000).contains(target) else { throw ChallengeV1Error.invalidResponse }
            let window = try makeWindow(config, policy: policy)
            let member = Self.member(actor, target: target, value: nil, consented: false, now: clock)
            payload = try Self.json(Self.agreement(policy: policy, window: window, members: [member],
                                                   source: fields["p_source_policy_version"]?.string))
        default: throw ChallengeV1Error.unavailable
        }
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: ChallengeJSON.data(payload))
    }

    private func checkActor(_ actor: UUID) throws {
        guard actor == LiveDesignFixtures.actorID else { throw ChallengeV1Error.accountChanged }
    }
    private func perform(_ request: ChallengeV1Request) throws -> ChallengeV1Receipt {
        let p = request.payload
        guard let op = p["op"]?.string else { throw ChallengeV1Error.invalidResponse }
        if op == "confirm_age" {
            guard p["confirmed"] == .bool(true) else { throw ChallengeV1Error.invalidResponse }
            return .init(confirmed: true, saved: true)
        }
        if op == "create" || op == "personal_commit" { return try create(p, actor: request.actorId, personal: op == "personal_commit") }
        if op == "revoke_link" {
            guard let id = p["id"]?.string.flatMap(UUID.init(uuidString:)), links.removeValue(forKey: id) != nil
            else { throw ChallengeV1Error.server("challenge_link_unavailable") }
            return .init(id: id, saved: true, revoked: true)
        }
        guard let id = p["id"]?.string.flatMap(UUID.init(uuidString:)), let row = rows[id]
        else { throw ChallengeV1Error.unavailable }
        if let revision = p["revision"]?.integer, revision != row.revision { throw ChallengeV1Error.server("challenge_stale") }
        let ownID = request.actorId
        var members = row.members
        var state = row.status
        var agreement = row.agreement
        var version = row.agreementVersion
        var reviews = row.reviews
        switch op {
        case "consent":
            guard state == "consent_pending", p["consent"] == .bool(true),
                  let digest = agreement?.digest, p["digest"]?.string == digest,
                  let own = row.own(ownID), own.selected, !own.exited, !own.consented
            else { throw ChallengeV1Error.server("challenge_consent_mismatch") }
            members = members.map { Self.replacing($0, consented: $0.actorId == ownID ? true : $0.consented) }
            if members.filter({ $0.selected && !$0.exited }).allSatisfy(\.consented) { state = "scheduled" }
        case "leave", "cancel":
            guard !row.isClosed, row.own(ownID)?.exited == false else { throw ChallengeV1Error.server("challenge_stale") }
            if op == "cancel" {
                guard row.creatorId == ownID, clock < row.config.startsAt else { throw ChallengeV1Error.server("challenge_stale") }
                state = "cancelled"
                members = members.map { Self.replacing($0, exited: true) }
            } else {
                members = members.map { Self.replacing($0, exited: $0.actorId == ownID ? true : $0.exited) }
                let minimum = row.format.mode == .personal ? 1 : 2
                if members.filter({ $0.selected && !$0.exited }).count < minimum { state = "cancelled" }
            }
        case "review":
            guard state == "review", let notice = row.notice, clock < notice.reviewBy,
                  p["notice_revision"]?.integer == notice.revision,
                  !reviews.contains(where: { $0.noticeRevision == notice.revision }),
                  let reason = p["reason"]?.string, ["wrong_total", "missing_activity", "wrong_result"].contains(reason)
            else { throw ChallengeV1Error.server("challenge_review_closed") }
            reviews.append(.init(noticeRevision: notice.revision, id: UUID(), reason: reason, filedAt: clock,
                                 resolveBy: .init(date: clock.date.addingTimeInterval(72 * 3600)), decision: nil))
        case "target":
            guard state == "lobby_open", row.format.hasTarget, let value = p["target"]?.integer,
                  (1...1_000_000_000).contains(value) else { throw ChallengeV1Error.invalidResponse }
            members = members.map { Self.replacing($0, target: $0.actorId == ownID ? value : $0.target) }
        case "invite":
            guard state == "lobby_open", row.creatorId == ownID, let name = p["username"]?.string,
                  let friend = Self.people.first(where: { $0.value.lowercased() == name.lowercased() })?.key
                    ?? friendState.friends.first(where: { $0.username.lowercased() == name.lowercased() })?.id, friend != ownID
            else { throw ChallengeV1Error.server("challenge_friend_unavailable") }
            if !members.contains(where: { $0.actorId == friend }) {
                members.append(Self.member(friend, target: nil, value: nil, selected: false, consented: false, now: clock))
            }
        case "select", "reject":
            guard state == "lobby_open", row.creatorId == ownID,
                  let subject = p["actor_id"]?.string.flatMap(UUID.init(uuidString:)), subject != ownID,
                  members.contains(where: { $0.actorId == subject }) else { throw ChallengeV1Error.invalidResponse }
            members = members.map { Self.replacing($0,
                selected: $0.actorId == subject ? p["selected"] == .bool(true) : $0.selected,
                exited: $0.actorId == subject && op == "reject" ? true : $0.exited) }
        case "freeze":
            let selected = members.filter { $0.selected && !$0.exited }
            guard state == "lobby_open", row.creatorId == ownID, (2...6).contains(selected.count),
                  !row.format.hasTarget || selected.allSatisfy({ $0.target != nil })
            else { throw ChallengeV1Error.server("challenge_incomplete_roster") }
            members = members.map { Self.replacing($0, consented: false) }
            agreement = try Self.agreement(policy: row.format, window: row.config, members: members, source: row.sourcePolicyVersion)
            state = "consent_pending"; version += 1
        case "reopen":
            guard row.creatorId == ownID, ["consent_pending", "scheduled"].contains(state), clock < row.config.startsAt
            else { throw ChallengeV1Error.server("challenge_stale") }
            state = "lobby_open"; agreement = nil
            members = members.map { Self.replacing($0, consented: false) }
        case "issue_link":
            guard row.creatorId == ownID, state == "lobby_open" else { throw ChallengeV1Error.server("challenge_link_unavailable") }
            let linkID = UUID()
            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
                + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            links[linkID] = (id, token)
            return .init(id: linkID, token: token, expiresAt: row.config.startsAt, saved: true)
        default: throw ChallengeV1Error.unavailable
        }
        let updated = Self.replacing(row, status: state, members: members, agreement: agreement, version: version, reviews: reviews, now: clock)
        try updated.validate(actor: ownID)
        rows[id] = updated
        return .init(id: id, revision: updated.revision, status: state, saved: true)
    }

    private func create(_ p: ChallengeJSON, actor: UUID, personal: Bool) throws -> ChallengeV1Receipt {
        guard let raw = p["policy"]?.string, let policy = ChallengeV1Policy(rawValue: raw),
              policy.mode == (personal ? .personal : .friend), let config = p["config"]
        else { throw ChallengeV1Error.invalidResponse }
        let window = try makeWindow(config, policy: policy)
        guard window.startsAt > clock else { throw ChallengeV1Error.invalidResponse }
        let target = p["target"]?.integer
        if personal { guard let target, (1...1_000_000_000).contains(target) else { throw ChallengeV1Error.invalidResponse } }
        let member = Self.member(actor, target: target, value: nil, consented: personal, now: clock)
        let source = p["source_policy_version"]?.string
        let agreement = personal ? try Self.agreement(policy: policy, window: window, members: [member], source: source) : nil
        if personal {
            guard p["consent"] == .bool(true), p["digest"]?.string == agreement?.digest else { throw ChallengeV1Error.server("challenge_consent_mismatch") }
        }
        let row = ChallengeV1(sourcePolicyVersion: source, id: UUID(), creatorId: actor, policy: raw, config: window,
            status: personal ? "scheduled" : "lobby_open", revision: 1, agreementVersion: 1, serverTime: clock,
            socialHidden: personal, agreement: agreement, members: [member], notice: nil, reviews: [], final: nil)
        try row.validate(actor: actor); rows[row.id] = row
        return .init(id: row.id, revision: row.revision, status: row.status, saved: true)
    }
    private func makeWindow(_ config: ChallengeJSON, policy: ChallengeV1Policy) throws -> ChallengeV1.Window {
        guard let start = config["start_date"]?.string, let days = config["days"]?.integer, (1...30).contains(days),
              let zone = config["timezone"]?.string, let timeZone = TimeZone(identifier: zone),
              let amount = config["amount_cents"]?.integer, (100...50_000).contains(amount), amount % 100 == 0
        else { throw ChallengeV1Error.invalidResponse }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let first = formatter.date(from: start), formatter.string(from: first) == start else { throw ChallengeV1Error.invalidResponse }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let end = calendar.date(byAdding: .day, value: days, to: first) else { throw ChallengeV1Error.invalidResponse }
        let distance = config["distance_mm"]?.integer
        guard (policy.metric == .timed) == (distance != nil), distance.map({ (1...1_000_000_000).contains($0) }) ?? true
        else { throw ChallengeV1Error.invalidResponse }
        return .init(startDate: start, days: days, timezone: zone, amountCents: amount, distanceMm: distance,
            startsAt: .init(date: first), endsAt: .init(date: end), syncBy: .init(date: end.addingTimeInterval(86_400)),
            correctionsBy: .init(date: end.addingTimeInterval(172_800)), noticeDue: .init(date: end.addingTimeInterval(259_200)))
    }

    /// A test can seed a provisional notice without changing the screenshot's
    /// six record fixtures or pretending elapsed time confirms a result.
    func seedReview(for id: UUID) throws {
        guard let row = rows[id], !row.isClosed else { throw ChallengeV1Error.invalidResponse }
        let notice = ChallengeV1.Notice(revision: 1, recordedAt: clock,
            reviewBy: .init(date: clock.date.addingTimeInterval(48 * 3600)), result: nil)
        rows[id] = .init(sourcePolicyVersion: row.sourcePolicyVersion, counts: row.counts, id: row.id,
            creatorId: row.creatorId, policy: row.policy, config: row.config, status: "review", revision: row.revision + 1,
            agreementVersion: row.agreementVersion, serverTime: clock, socialHidden: row.socialHidden,
            agreement: row.agreement, members: row.members, notice: notice, reviews: [], final: nil)
        projection = UUID()
    }

    private static let people = [LiveDesignFixtures.actorID: "alexlee", LiveDesignFixtures.samID: "Sam",
                                 LiveDesignFixtures.jordanID: "Jordan", LiveDesignFixtures.priyaID: "Priya"]
    private static func member(_ id: UUID, target: Int?, value: Int?, selected: Bool = true,
                               consented: Bool = true, exited: Bool = false, now: ChallengeInstant) -> ChallengeV1.Member {
        .init(actorId: id, username: people[id] ?? "runner", target: target, selected: selected, exited: exited, consented: consented,
              fact: value.map { .init(value: $0, state: "value", recordedAt: .init(date: now.date.addingTimeInterval(-60)), revision: 1) })
    }
    private static func replacing(_ member: ChallengeV1.Member, target: Int? = nil, selected: Bool? = nil,
                                  consented: Bool? = nil, exited: Bool? = nil) -> ChallengeV1.Member {
        .init(actorId: member.actorId, username: member.username, target: target ?? member.target,
              selected: selected ?? member.selected, exited: exited ?? member.exited, consented: consented ?? member.consented, fact: member.fact)
    }
    private static func replacing(_ row: ChallengeV1, status: String, members: [ChallengeV1.Member],
                                  agreement: ChallengeV1.Agreement?, version: Int, reviews: [ChallengeV1.Review], now: ChallengeInstant) -> ChallengeV1 {
        .init(sourcePolicyVersion: row.sourcePolicyVersion, counts: row.counts, id: row.id, creatorId: row.creatorId,
              policy: row.policy, config: row.config, status: status, revision: row.revision + 1, agreementVersion: version,
              serverTime: now, socialHidden: row.socialHidden, agreement: agreement, members: members,
              notice: row.notice, reviews: reviews, final: row.final)
    }
    private static func json<T: Encodable>(_ value: T) throws -> ChallengeJSON {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        return try JSONDecoder().decode(ChallengeJSON.self, from: encoder.encode(value))
    }
    private static func agreement(policy: ChallengeV1Policy, window: ChallengeV1.Window,
                                  members: [ChallengeV1.Member], source: String?) throws -> ChallengeV1.Agreement {
        var terms: [String: ChallengeJSON] = ["policy": .string(policy.id), "config": try json(window),
            "minimum": .integer(policy.mode == .personal ? 1 : 2), "source_policy_version": source.map(ChallengeJSON.string) ?? .null,
            "participants": .array(members.filter { $0.selected && !$0.exited }.sorted { $0.actorId.uuidString < $1.actorId.uuidString }.map {
                .object(["actor_id": .string($0.actorId.uuidString.lowercased()), "target": $0.target.map(ChallengeJSON.integer) ?? .null])
            })]
        terms["simulation"] = .string("nonredeemable")
        let raw = ChallengeJSON.object(terms)
        let digest = SHA256.hash(data: try ChallengeJSON.data(raw)).map { String(format: "%02x", $0) }.joined()
        return .init(digest: digest, terms: raw)
    }
    private static func seedRows(now: ChallengeInstant) -> [ChallengeV1] {
        let f = LiveDesignFixtures.self
        func row(_ id: UUID, start: String, policy raw: String, status: String,
                 members: [ChallengeV1.Member], creator: UUID? = nil, finalAt: String? = nil) -> ChallengeV1 {
            let policy = ChallengeV1Policy(rawValue: raw)!
            let first = try! ChallengeInstant(start + "T00:00:00-07:00")
            let end = first.date.addingTimeInterval(7 * 86_400)
            let window = ChallengeV1.Window(startDate: start, days: 7, timezone: "America/Los_Angeles", amountCents: 2_000,
                startsAt: first, endsAt: .init(date: end), syncBy: .init(date: end.addingTimeInterval(86_400)),
                correctionsBy: .init(date: end.addingTimeInterval(172_800)), noticeDue: .init(date: end.addingTimeInterval(259_200)))
            let source = policy.metric == .steps ? "apple_watch_steps_v1" : "apple_workout_outdoor_distance_v1"
            let allocation = ChallengeV1.Allocation(outcome: "scored", participants: Dictionary(uniqueKeysWithValues: members.map {
                ($0.actorId.uuidString.lowercased(), .init(status: "met", returnedCents: 2_000))
            }), own: nil, entryCents: members.count * 2_000, unallocatedCents: 0, simulation: "nonredeemable")
            // A later exit does not erase the roster from the original agreement.
            let agreedMembers = members.map { replacing($0, exited: false) }
            return .init(sourcePolicyVersion: source, id: id, creatorId: creator ?? f.actorID, policy: raw, config: window,
                status: status, revision: 1, agreementVersion: 1, serverTime: now, socialHidden: policy.mode == .personal,
                agreement: try! agreement(policy: policy, window: window, members: agreedMembers, source: source), members: members,
                notice: nil, reviews: [], final: finalAt.map { .init(recordedAt: try! ChallengeInstant($0), result: allocation) })
        }
        return [
            row(f.activeID, start: "2026-09-21", policy: "friend_distance_goal_v1", status: "active", members: [
                member(f.actorID, target: 20_000_000, value: 6_400_000, now: now),
                member(f.samID, target: 20_000_000, value: 7_800_000, now: now),
                member(f.jordanID, target: 15_000_000, value: 1_200_000, now: now),
                member(f.priyaID, target: 10_000_000, value: 10_000_000, now: now)]),
            row(f.invitationID, start: "2026-09-28", policy: "friend_distance_goal_v1", status: "consent_pending", members: [
                member(f.actorID, target: 20_000_000, value: nil, consented: false, now: now),
                member(f.jordanID, target: 20_000_000, value: nil, now: now)], creator: f.jordanID),
            row(f.upcomingID, start: "2026-10-05", policy: "friend_distance_goal_v1", status: "scheduled", members: [
                member(f.actorID, target: 20_000_000, value: nil, now: now), member(f.samID, target: 20_000_000, value: nil, now: now)]),
            row(f.stepsID, start: "2026-09-07", policy: "friend_steps_goal_v1", status: "final", members: [
                member(f.actorID, target: 50_000, value: 52_480, now: try! .init("2026-09-14T00:00:00-07:00")),
                member(f.samID, target: 60_000, value: 61_200, now: try! .init("2026-09-14T00:00:00-07:00"))], finalAt: "2026-09-19T09:00:00-07:00"),
            row(f.runsID, start: "2026-08-24", policy: "personal_distance_goal_v1", status: "final", members: [
                member(f.actorID, target: 12_000_000, value: 12_800_000, now: try! .init("2026-08-31T00:00:00-07:00"))], finalAt: "2026-09-05T09:00:00-07:00"),
            row(f.closedID, start: "2026-08-10", policy: "personal_steps_goal_v1", status: "cancelled", members: [
                member(f.actorID, target: 50_000, value: nil, exited: true, now: now)])
        ]
    }
}

/// Fictional friends for screenshots and UI tests. Commands replay exactly and
/// follow the server's expected-state rules; nothing leaves the phone.
extension LiveDesignFixtureClient: FriendCommandsClient {
    func friendList(actor: UUID) async throws -> FriendList {
        guard actor == LiveDesignFixtures.actorID else { throw ChallengeV1Error.accountChanged }
        if ProcessInfo.processInfo.arguments.contains("--friends-empty") {
            return FriendList(serverTime: friendState.serverTime, friends: [], incoming: [], outgoing: [], blocked: [])
        }
        return friendState
    }
    func friendLookup(_ username: String, actor: UUID) async throws -> FriendLookup {
        guard actor == LiveDesignFixtures.actorID else { throw ChallengeV1Error.accountChanged }
        if username.lowercased() == "alexlee" {
            return .init(found: true, id: actor, username: "alexlee", displayName: "Alex Lee", relation: .you)
        }
        let everyone = friendState.friends + friendState.incoming + friendState.outgoing + LiveDesignFixtures.strangers
        guard !friendState.blocked.contains(where: { $0.username.lowercased() == username.lowercased() }),
              let person = everyone.first(where: { $0.username.lowercased() == username.lowercased() })
        else { return .init(found: false) }
        let relation: FriendLookup.Relation = friendState.friends.contains { $0.id == person.id } ? .friends
            : friendState.incoming.contains { $0.id == person.id } ? .incoming
            : friendState.outgoing.contains { $0.id == person.id } ? .outgoing : .none
        return .init(found: true, id: person.id, username: person.username, displayName: person.displayName, relation: relation)
    }
    func friendCommand(_ command: FriendCommand) async throws -> FriendReceipt {
        guard command.actorId == LiveDesignFixtures.actorID else { throw ChallengeV1Error.accountChanged }
        if let saved = friendReceipts[command.requestId] {
            guard saved.command == command else { throw ChallengeV1Error.server("friend_request_conflict") }
            return saved.receipt
        }
        var list = friendState
        func take(_ people: inout [FriendPerson]) -> FriendPerson? {
            guard let index = people.firstIndex(where: { $0.id == command.subject }) else { return nil }
            return people.remove(at: index)
        }
        let receipt: FriendReceipt
        switch command.op {
        case .request:
            if list.incoming.contains(where: { $0.id == command.subject }) { throw ChallengeV1Error.server("friend_incoming_request_exists") }
            guard !list.friends.contains(where: { $0.id == command.subject }),
                  !list.outgoing.contains(where: { $0.id == command.subject }) else { throw ChallengeV1Error.server("friend_state_changed") }
            var person = command.person; person.sentAt = clock
            list.outgoing.insert(person, at: 0); receipt = .init(state: "outgoing")
        case .accept:
            guard var person = take(&list.incoming) else { throw ChallengeV1Error.server("friend_state_changed") }
            person.since = clock; person.youAsked = false; person.sentAt = nil
            list.friends.append(person); receipt = .init(state: "friends")
        case .decline, .cancel, .remove:
            let removed: FriendPerson? = switch command.op {
            case .decline: take(&list.incoming)
            case .cancel: take(&list.outgoing)
            default: take(&list.friends)
            }
            guard removed != nil else { throw ChallengeV1Error.server("friend_state_changed") }
            receipt = .init(state: "none")
        case .block:
            guard !list.blocked.contains(where: { $0.id == command.subject }) else { throw ChallengeV1Error.server("friend_state_changed") }
            _ = take(&list.friends); _ = take(&list.incoming); _ = take(&list.outgoing)
            list.blocked.insert(command.person, at: 0); receipt = .init(state: "blocked")
        case .unblock:
            guard take(&list.blocked) != nil else { throw ChallengeV1Error.server("friend_state_changed") }
            receipt = .init(state: "none")
        case .report:
            receipt = .init(saved: true)
        }
        friendState = list
        friendReceipts[command.requestId] = (command, receipt)
        return receipt
    }
}

extension LiveDesignFixtures {
    static let morganID = UUID(uuidString: "88888888-8888-4888-8888-888888888888")!
    static let taylorID = UUID(uuidString: "99999999-9999-4999-8999-999999999999")!
    static let rileyID = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
    static let caseyID = UUID(uuidString: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")!
    static let drewID = UUID(uuidString: "cccccccc-cccc-4ccc-8ccc-cccccccccccc")!
    static let strangers = [FriendPerson(id: drewID, username: "drew_p", displayName: "Drew Park")]

    static func friendList() -> FriendList {
        func at(_ value: String) -> ChallengeInstant { try! ChallengeInstant(value) }
        return FriendList(serverTime: now, friends: [
            FriendPerson(id: samID, username: "samr", displayName: "Sam Rivera", since: at("2026-09-12T10:00:00-07:00"), youAsked: false),
            FriendPerson(id: jordanID, username: "jordanb", displayName: "Jordan Blake", since: at("2026-09-12T11:00:00-07:00"), youAsked: true),
            FriendPerson(id: priyaID, username: "priya_n", displayName: "Priya Nair", since: at("2026-09-14T09:00:00-07:00"), youAsked: false),
            FriendPerson(id: morganID, username: "morgand", displayName: "Morgan Diaz", since: at("2026-09-22T08:30:00-07:00"), youAsked: true),
        ], incoming: [
            FriendPerson(id: taylorID, username: "taylork", displayName: "Taylor Kim", sentAt: at("2026-09-22T07:50:00-07:00")),
        ], outgoing: [
            FriendPerson(id: rileyID, username: "rileyc", displayName: "Riley Chen", sentAt: at("2026-09-22T08:10:00-07:00")),
        ], blocked: [
            FriendPerson(id: caseyID, username: "casey_w", displayName: "Casey Wu"),
        ])
    }
}
#endif
