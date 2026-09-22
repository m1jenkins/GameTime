import Foundation

/// D142 friends. Every change goes through a versioned friend command with an
/// actor-bound request ID, so an exact retry returns the saved receipt instead
/// of acting twice. The server owns the pair state; this file only carries it.
@MainActor protocol FriendCommandsClient: AnyObject {
    func friendList(actor: UUID) async throws -> FriendList
    func friendLookup(_ username: String, actor: UUID) async throws -> FriendLookup
    func friendCommand(_ command: FriendCommand) async throws -> FriendReceipt
}

/// Missing or closed configuration selects no transport and no fabricated data.
@MainActor final class UnavailableFriendCommandsClient: FriendCommandsClient {
    func friendList(actor: UUID) async throws -> FriendList { throw ChallengeV1Error.unavailable }
    func friendLookup(_ username: String, actor: UUID) async throws -> FriendLookup { throw ChallengeV1Error.unavailable }
    func friendCommand(_ command: FriendCommand) async throws -> FriendReceipt { throw ChallengeV1Error.unavailable }
}

struct FriendPerson: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let username: String
    let displayName: String
    var since: ChallengeInstant? = nil
    var youAsked: Bool? = nil
    var sentAt: ChallengeInstant? = nil

    var firstName: String { displayName.split(separator: " ").first.map(String.init) ?? username }
}

struct FriendList: Codable, Equatable, Sendable {
    let serverTime: ChallengeInstant
    var friends: [FriendPerson]
    var incoming: [FriendPerson]
    var outgoing: [FriendPerson]
    var blocked: [FriendPerson]

    /// A person appears once across friends and requests, never as you, and
    /// with a username the profile rules allow. Blocked people are listed
    /// separately because a block severs any friendship or request.
    func validate(actor: UUID) throws {
        let pairs = friends + incoming + outgoing
        let all = pairs + blocked
        guard all.count <= 2_000, Set(pairs.map(\.id)).count == pairs.count,
              Set(blocked.map(\.id)).count == blocked.count,
              Set(pairs.map(\.id)).isDisjoint(with: blocked.map(\.id)),
              !all.contains(where: { $0.id == actor }),
              all.allSatisfy({ ExactHandleSubmission.normalized($0.username) == $0.username && !$0.displayName.isEmpty }),
              friends.allSatisfy({ $0.youAsked != nil })
        else { throw ChallengeV1Error.invalidResponse }
    }

    static let empty = FriendList(serverTime: ChallengeInstant(date: Date(timeIntervalSince1970: 0)),
                                  friends: [], incoming: [], outgoing: [], blocked: [])
}

struct FriendLookup: Codable, Equatable, Sendable {
    enum Relation: String, Codable, Sendable { case none, incoming, outgoing, friends, you = "self" }
    let found: Bool
    var id: UUID? = nil
    var username: String? = nil
    var displayName: String? = nil
    var relation: Relation? = nil

    var person: FriendPerson? {
        guard found, let id, let username, let displayName else { return nil }
        return FriendPerson(id: id, username: username, displayName: displayName)
    }

    func validate() throws {
        guard !found || (person != nil && relation != nil
                         && ExactHandleSubmission.normalized(username ?? "") == username)
        else { throw ChallengeV1Error.invalidResponse }
    }
}

struct FriendCommand: Codable, Equatable, Sendable {
    enum Op: String, Codable, CaseIterable, Sendable { case request, accept, decline, cancel, remove, block, unblock, report }
    /// The three reasons the support queue stores. No free text is sent.
    enum Reason: String, Codable, CaseIterable, Sendable {
        case username, unwantedContact = "unwanted_contact", unsafeBehavior = "unsafe_behavior"
    }
    let kind: String
    let actorId: UUID
    let requestId: UUID
    let op: Op
    let subject: UUID
    let reason: Reason?
    /// Kept only so a saved retry can name the person. It is not sent.
    let username: String
    let displayName: String

    init(actor: UUID, id: UUID = UUID(), op: Op, person: FriendPerson, reason: Reason? = nil) {
        kind = "friend_command_v1"; actorId = actor; requestId = id; self.op = op
        subject = person.id; self.reason = reason; username = person.username; displayName = person.displayName
    }

    var person: FriendPerson { FriendPerson(id: subject, username: username, displayName: displayName) }
    var rpc: String { "friend_\(op.rawValue)_v1" }
    var body: Data { get throws {
        guard kind == "friend_command_v1", subject != actorId, (op == .report) == (reason != nil) else { throw ChallengeV1Error.storage }
        var fields: [String: ChallengeJSON] = ["p_request_id": .string(requestId.uuidString.lowercased()),
                                               "p_subject": .string(subject.uuidString.lowercased())]
        if let reason { fields["p_reason"] = .string(reason.rawValue) }
        return try ChallengeJSON.data(.object(fields))
    } }
}

struct FriendReceipt: Codable, Equatable, Sendable {
    var state: String? = nil
    var saved: Bool? = nil

    /// Each command has exactly one successful answer.
    func matches(_ op: FriendCommand.Op) -> Bool {
        switch op {
        case .request: state == "outgoing"
        case .accept: state == "friends"
        case .decline, .cancel, .remove, .unblock: state == "none"
        case .block: state == "blocked"
        case .report: saved == true
        }
    }
}

/// One file per account: a friend command waiting to be confirmed, and the
/// "accepted your request" rows this person dismissed on this phone.
actor FriendJournal {
    struct Entry: Codable, Equatable, Sendable {
        var pending: FriendCommand? = nil
        var dismissed: [String] = []
    }
    let directory: URL
    init(directory: URL) { self.directory = directory }

    func load(_ actor: UUID) throws -> Entry {
        let file = path(actor)
        guard FileManager.default.fileExists(atPath: file.path) else { return Entry() }
        do {
            let data = try Data(contentsOf: file)
            guard data.count <= 65_536 else { throw ChallengeV1Error.storage }
            let entry = try JSONDecoder().decode(Entry.self, from: data)
            if let pending = entry.pending {
                guard pending.actorId == actor else { throw ChallengeV1Error.storage }
                _ = try pending.body
            }
            return entry
        } catch { throw ChallengeV1Error.storage }
    }
    func savePending(_ command: FriendCommand) throws {
        var entry = try load(command.actorId)
        if let prior = entry.pending, prior != command { throw ChallengeV1Error.storage }
        entry.pending = command
        try write(entry, actor: command.actorId)
    }
    func removePending(_ command: FriendCommand) throws {
        var entry = try load(command.actorId)
        guard entry.pending == command else { return }
        entry.pending = nil
        try write(entry, actor: command.actorId)
    }
    func dismiss(_ key: String, actor: UUID) throws {
        var entry = try load(actor)
        guard !entry.dismissed.contains(key) else { return }
        entry.dismissed = Array((entry.dismissed + [key]).suffix(200))
        try write(entry, actor: actor)
    }
    func removeAll(for actor: UUID) throws {
        let file = path(actor)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        do { try FileManager.default.removeItem(at: file) } catch { throw ChallengeV1Error.storage }
    }
    private func write(_ entry: Entry, actor: UUID) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(entry).write(to: path(actor), options: [.atomic, .completeFileProtection])
            var dir = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
        } catch { throw ChallengeV1Error.storage }
    }
    private func path(_ actor: UUID) -> URL { directory.appendingPathComponent(actor.uuidString.lowercased() + ".json") }

    static func applicationSupport() -> FriendJournal {
        FriendJournal(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GameTime/FriendCommandsV1"))
    }
}

/// Every friend error says what happened and what to do next. Known server
/// codes map to sentences; an unknown one is shown only as a reference.
enum FriendsCopy {
    static func message(for error: Error, username: String? = nil) -> String {
        guard let error = error as? ChallengeV1Error else { return ChallengeV1Error.unavailable.localizedDescription }
        guard case .server(let code) = error else {
            if error == .unavailable { return "We couldn’t reach GameTime. Check your connection and try again." }
            return error.localizedDescription
        }
        switch code {
        case "friend_incoming_request_exists":
            return "\(username ?? "They") already sent you a request. Accept it to become friends."
        case "friend_request_limit": return "You’ve reached today’s limit for friend requests. Try again tomorrow."
        case "friend_lookup_rate_limited": return "Too many searches. Wait a minute and try again."
        case "friend_age_required", "challenge_age_required": return "Confirm that you are 21 or older, then try again."
        case "friend_account_restricted":
            return "Your account can’t send or accept friend requests right now. If you think this is a mistake, contact us from Settings."
        case "friend_request_already_sent": return "You already sent \(username.map { "@" + $0 } ?? "them") a request. You can cancel it from Friends."
        case "friend_already_friends": return "You’re already friends."
        case "friend_unavailable": return "We couldn’t find that person. They may have left GameTime. Refresh and try again."
        case "friend_state_changed": return "Something changed since you last looked. We refreshed your friends. Check the list and try again."
        case "friend_rate_limited": return "You’ve sent several reports. Wait an hour, then try again. You can still block them."
        default:
            let safe = code.range(of: #"^[a-z0-9_]{1,64}$"#, options: .regularExpression) != nil
            return "We couldn’t finish that. Refresh and try again." + (safe ? " Reference: \(code)" : "")
        }
    }

    static func done(_ command: FriendCommand) -> String? {
        let name = command.person.firstName
        switch command.op {
        case .request: return "Request sent. \(name) will see it in GameTime and can accept or decline."
        case .accept: return "You and \(name) are now friends."
        case .decline: return "Request declined."
        case .cancel: return "Request cancelled."
        case .remove: return "\(name) is no longer your friend."
        case .block: return "\(name) is blocked. Find them in Blocked people."
        case .unblock: return "\(name) is unblocked."
        case .report: return nil
        }
    }
}
