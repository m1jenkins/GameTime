import Foundation

enum DuelParameter: Codable, Equatable, Sendable {
    case string(String), bool(Bool), integer(Int)

    init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer()
        if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let int = try? value.decode(Int.self) { self = .integer(int) }
        else { self = .string(try value.decode(String.self)) }
    }

    func encode(to encoder: any Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .string(let string): try value.encode(string)
        case .bool(let bool): try value.encode(bool)
        case .integer(let int): try value.encode(int)
        }
    }
}

enum DuelMutation: Codable, Equatable, Sendable {
    case create(inviteeID: UUID, eventID: UUID, policyVersion: String, consent: Bool)
    case rematch(previousID: UUID, eventID: UUID, policyVersion: String, consent: Bool)
    case issueLink(challengeID: UUID)
    case revokeLink(challengeID: UUID, token: UUID)
    case accept(challengeID: UUID, policyVersion: String, termsDigest: String)
    case decline(challengeID: UUID)
    case cancel(challengeID: UUID)
    case fileReview(challengeID: UUID, revision: Int, reason: DuelReviewReason)
    case exit(challengeID: UUID, kind: DuelSafeExitKind)

    var rpc: String {
        switch self {
        case .create: "create_duel_v1"
        case .rematch: "rematch_duel_v1"
        case .issueLink: "issue_duel_link_v1"
        case .revokeLink: "revoke_duel_link_v1"
        case .accept: "accept_duel_v1"
        case .decline: "decline_duel_v1"
        case .cancel: "cancel_duel_v1"
        case .fileReview: "file_duel_review_v1"
        case .exit: "exit_duel_v1"
        }
    }

    var challengeID: UUID? {
        switch self {
        case .create, .rematch: nil
        case .accept(let id, _, _), .decline(let id), .cancel(let id),
             .fileReview(let id, _, _), .exit(let id, _), .issueLink(let id), .revokeLink(let id, _): id
        }
    }

    var isLifecycle: Bool {
        switch self { case .fileReview, .exit: true; default: false }
    }

    func parameters(requestID: UUID) -> [String: DuelParameter] {
        var result: [String: DuelParameter] = [
            "p_request_id": .string(requestID.uuidString.lowercased())
        ]
        switch self {
        case let .create(invitee, event, policy, consent):
            result["p_invitee_id"] = .string(invitee.uuidString.lowercased())
            result["p_event_id"] = .string(event.uuidString.lowercased())
            result["p_expected_policy_version"] = .string(policy)
            result["p_consent"] = .bool(consent)
        case let .rematch(previous, event, policy, consent):
            result["p_previous_challenge_id"] = .string(previous.uuidString.lowercased())
            result["p_event_id"] = .string(event.uuidString.lowercased())
            result["p_expected_policy_version"] = .string(policy)
            result["p_consent"] = .bool(consent)
        case let .revokeLink(challenge, token):
            result["p_challenge_id"] = .string(challenge.uuidString.lowercased())
            result["p_token"] = .string(token.uuidString.lowercased())
        case let .accept(challenge, policy, digest):
            result["p_challenge_id"] = .string(challenge.uuidString.lowercased())
            result["p_expected_policy_version"] = .string(policy)
            result["p_expected_terms_digest"] = .string(digest)
        case let .fileReview(challenge, revision, reason):
            result["p_challenge_id"] = .string(challenge.uuidString.lowercased())
            result["p_revision"] = .integer(revision)
            result["p_reason"] = .string(reason.rawValue)
        case let .exit(challenge, kind):
            result["p_challenge_id"] = .string(challenge.uuidString.lowercased())
            result["p_kind"] = .string(kind.rawValue)
        case .decline(let challenge), .cancel(let challenge), .issueLink(let challenge):
            result["p_challenge_id"] = .string(challenge.uuidString.lowercased())
        }
        return result
    }
}

/// Independent of every historical Personal/contest envelope. Only the
/// uncertainty marker may change; operation and exact parameters never do.
struct PendingDuelRequest: Codable, Equatable, Sendable {
    let kind: String
    let version: Int
    let actorID: UUID
    let requestID: UUID
    let operation: DuelMutation
    let requestBody: Data
    var mayHaveCommitted: Bool

    init(actorID: UUID, requestID: UUID = UUID(), operation: DuelMutation) throws {
        kind = "duel_request_v1"
        version = 1
        self.actorID = actorID
        self.requestID = requestID
        self.operation = operation
        requestBody = try Self.body(operation, requestID: requestID)
        mayHaveCommitted = false
        try validate(for: actorID)
    }

    func validate(for actorID: UUID) throws {
        guard kind == "duel_request_v1", version == 1, self.actorID == actorID,
            requestBody == (try Self.body(operation, requestID: requestID))
        else { throw DuelClientError.storage }
        switch operation {
        case let .create(invitee, _, policy, consent):
            guard invitee != actorID, policy == "duel-fixture-5k-v1", consent else {
                throw DuelClientError.storage
            }
        case let .rematch(_, _, policy, consent):
            guard policy == "duel-fixture-5k-v1", consent else { throw DuelClientError.storage }
        case let .accept(_, policy, digest):
            guard policy == "duel-fixture-5k-v1", digest.count == 64,
                digest.allSatisfy({ "0123456789abcdef".contains($0) })
            else { throw DuelClientError.storage }
        case .fileReview(_, let revision, _):
            guard (0...Int(Int32.max)).contains(revision) else { throw DuelClientError.storage }
        case .decline, .cancel, .exit, .issueLink, .revokeLink: break
        }
    }

    func allowsReplacement(by next: Self) -> Bool {
        actorID == next.actorID && requestID == next.requestID
            && operation == next.operation && requestBody == next.requestBody
            && (!mayHaveCommitted || next.mayHaveCommitted)
    }

    private static func body(_ operation: DuelMutation, requestID: UUID) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(operation.parameters(requestID: requestID))
    }
}

protocol PendingDuelRequestStore: AnyObject, Sendable {
    func load(for actorID: UUID) async throws -> PendingDuelRequest?
    func save(_ request: PendingDuelRequest) async throws
    func remove(for actorID: UUID, matching requestID: UUID?) async throws
}

actor FilePendingDuelRequestStore: PendingDuelRequestStore {
    private let directory: URL
    private var deletedActors: Set<UUID> = []

    init(directory: URL) { self.directory = directory }

    static func applicationSupport() throws -> FilePendingDuelRequestStore {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { throw DuelClientError.storage }
        return FilePendingDuelRequestStore(directory: root
            .appendingPathComponent("GameTime/PendingDuels", isDirectory: true))
    }

    func load(for actorID: UUID) throws -> PendingDuelRequest? {
        guard !deletedActors.contains(actorID) else { return nil }
        let url = file(actorID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 16_384 else { throw DuelClientError.storage }
            let request = try JSONDecoder().decode(PendingDuelRequest.self, from: data)
            try request.validate(for: actorID)
            return request
        } catch { throw DuelClientError.storage }
    }

    func save(_ request: PendingDuelRequest) throws {
        guard !deletedActors.contains(request.actorID) else { throw DuelClientError.storage }
        try request.validate(for: request.actorID)
        do {
            if let existing = try load(for: request.actorID),
                !existing.allowsReplacement(by: request) { throw DuelClientError.storage }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try excludeFromBackup(directory)
            let data = try JSONEncoder().encode(request)
            try data.write(to: file(request.actorID), options: [.atomic, .completeFileProtection])
            try excludeFromBackup(file(request.actorID))
        } catch { throw DuelClientError.storage }
    }

    func remove(for actorID: UUID, matching requestID: UUID?) throws {
        // Deletion cleanup fences any queued writes for this store instance.
        if requestID == nil { deletedActors.insert(actorID) }
        if let requestID, try load(for: actorID)?.requestID != requestID { return }
        guard FileManager.default.fileExists(atPath: file(actorID).path) else { return }
        do { try FileManager.default.removeItem(at: file(actorID)) }
        catch { throw DuelClientError.storage }
    }

    private func file(_ actorID: UUID) -> URL {
        directory.appendingPathComponent("\(actorID.uuidString.lowercased()).json")
    }

    private func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

actor EphemeralPendingDuelRequestStore: PendingDuelRequestStore {
    private var requests: [UUID: PendingDuelRequest] = [:]
    func load(for actorID: UUID) -> PendingDuelRequest? { requests[actorID] }
    func save(_ request: PendingDuelRequest) throws {
        try request.validate(for: request.actorID)
        if let existing = requests[request.actorID], !existing.allowsReplacement(by: request) {
            throw DuelClientError.storage
        }
        requests[request.actorID] = request
    }
    func remove(for actorID: UUID, matching requestID: UUID?) {
        if requestID == nil || requests[actorID]?.requestID == requestID { requests[actorID] = nil }
    }
}
