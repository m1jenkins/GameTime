import Foundation

enum PerformanceCommitmentParameter: Codable, Equatable, Sendable {
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
    static func body(_ parameters: [String: Self]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(parameters)
    }
}

struct PerformanceCommitmentDraft: Codable, Equatable, Sendable {
    let targetSeconds: Int
    let startsAt: PerformanceCommitmentInstant
    let deadlineAt: PerformanceCommitmentInstant
    let displayTimezone: String
    var policyVersion = "performance-commitment-fixture-5k-v1"

    func validate() throws {
        let duration = deadlineAt.microseconds - startsAt.microseconds
        guard (1...86400).contains(targetSeconds),
              (28 * 86_400_000_000...90 * 86_400_000_000).contains(duration),
              TimeZone(identifier: displayTimezone) != nil,
              policyVersion == "performance-commitment-fixture-5k-v1"
        else { throw PerformanceCommitmentClientError.invalidTerms }
    }

    func matches(_ terms: PerformanceCommitmentTerms) -> Bool {
        terms.targetMS == targetSeconds * 1000 && terms.startsAt == startsAt
            && terms.deadlineAt == deadlineAt && terms.displayTimezone == displayTimezone
            && terms.policyVersion == policyVersion
    }

    var parameters: [String: PerformanceCommitmentParameter] {
        ["p_target_seconds": .integer(targetSeconds), "p_starts_at": .string(startsAt.rawValue),
         "p_deadline_at": .string(deadlineAt.rawValue), "p_display_timezone": .string(displayTimezone),
         "p_expected_policy_version": .string(policyVersion)]
    }
}

enum PerformanceCommitmentMutation: Codable, Equatable, Sendable {
    case create(draft: PerformanceCommitmentDraft, termsDigest: String, consent: Bool)
    case close(commitmentID: UUID, reason: PerformanceCommitmentCloseReason)
    case fileReview(commitmentID: UUID, revision: Int, reason: PerformanceCommitmentReviewReason)

    var commitmentID: UUID? {
        switch self {
        case .create: nil
        case .close(let id, _), .fileReview(let id, _, _): id
        }
    }
    var rpc: String {
        switch self {
        case .create: "create_performance_commitment_v1"
        case .close: "close_performance_commitment_v1"
        case .fileReview: "file_commitment_review_v1"
        }
    }
    func parameters(requestID: UUID) -> [String: PerformanceCommitmentParameter] {
        var parameters: [String: PerformanceCommitmentParameter] = [
            "p_request_id": .string(requestID.uuidString.lowercased())]
        switch self {
        case let .create(draft, digest, consent):
            parameters.merge(draft.parameters) { _, new in new }
            parameters["p_expected_terms_digest"] = .string(digest)
            parameters["p_consent"] = .bool(consent)
        case let .close(id, reason):
            parameters["p_commitment_id"] = .string(id.uuidString.lowercased())
            parameters["p_reason"] = .string(reason.rawValue)
        case let .fileReview(id, revision, reason):
            parameters["p_commitment_id"] = .string(id.uuidString.lowercased())
            parameters["p_revision"] = .integer(revision)
            parameters["p_reason"] = .string(reason.rawValue)
        }
        return parameters
    }
}

/// This product's exact request bytes contain no session, key or auth token.
/// Only the uncertainty marker may change after the initial durable save.
struct PendingPerformanceCommitmentRequest: Codable, Equatable, Sendable {
    let kind: String
    let version: Int
    let actorID: UUID
    let requestID: UUID
    let operation: PerformanceCommitmentMutation
    let requestBody: Data
    var mayHaveCommitted: Bool

    init(actorID: UUID, requestID: UUID = UUID(), operation: PerformanceCommitmentMutation) throws {
        kind = "performance_commitment_request_v1"
        version = 1
        self.actorID = actorID
        self.requestID = requestID
        self.operation = operation
        requestBody = try PerformanceCommitmentParameter.body(operation.parameters(requestID: requestID))
        mayHaveCommitted = false
        try validate(for: actorID)
    }
    func validate(for actorID: UUID) throws {
        guard kind == "performance_commitment_request_v1", version == 1, self.actorID == actorID,
              requestBody == (try PerformanceCommitmentParameter.body(operation.parameters(requestID: requestID)))
        else { throw PerformanceCommitmentClientError.storage }
        switch operation {
        case let .create(draft, digest, consent):
            do { try draft.validate() } catch { throw PerformanceCommitmentClientError.storage }
            guard consent, digest.count == 64, digest.allSatisfy({ "0123456789abcdef".contains($0) })
            else { throw PerformanceCommitmentClientError.storage }
        case .close(_, let reason):
            guard reason != .accountDeleted else { throw PerformanceCommitmentClientError.storage }
        case .fileReview(_, let revision, _):
            guard (0...Int(Int32.max)).contains(revision) else { throw PerformanceCommitmentClientError.storage }
        }
    }
    func allowsReplacement(by next: Self) -> Bool {
        actorID == next.actorID && requestID == next.requestID && operation == next.operation
            && requestBody == next.requestBody && (!mayHaveCommitted || next.mayHaveCommitted)
    }
}

protocol PendingPerformanceCommitmentRequestStore: AnyObject, Sendable {
    func load(for actorID: UUID) async throws -> PendingPerformanceCommitmentRequest?
    func save(_ request: PendingPerformanceCommitmentRequest) async throws
    func remove(for actorID: UUID, matching requestID: UUID?) async throws
}

actor FilePendingPerformanceCommitmentRequestStore: PendingPerformanceCommitmentRequestStore {
    private let directory: URL
    private var deletedActors: Set<UUID> = []
    init(directory: URL) { self.directory = directory }
    static func applicationSupport() throws -> FilePendingPerformanceCommitmentRequestStore {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else { throw PerformanceCommitmentClientError.storage }
        return FilePendingPerformanceCommitmentRequestStore(directory:
            root.appendingPathComponent("GameTime/PendingPerformanceCommitments", isDirectory: true))
    }
    func load(for actorID: UUID) throws -> PendingPerformanceCommitmentRequest? {
        guard !deletedActors.contains(actorID), FileManager.default.fileExists(atPath: file(actorID).path)
        else { return nil }
        do {
            let data = try Data(contentsOf: file(actorID))
            guard data.count <= 16_384 else { throw PerformanceCommitmentClientError.storage }
            let request = try JSONDecoder().decode(PendingPerformanceCommitmentRequest.self, from: data)
            try request.validate(for: actorID)
            return request
        } catch { throw PerformanceCommitmentClientError.storage }
    }
    func save(_ request: PendingPerformanceCommitmentRequest) throws {
        guard !deletedActors.contains(request.actorID) else { throw PerformanceCommitmentClientError.storage }
        try request.validate(for: request.actorID)
        do {
            if let existing = try load(for: request.actorID), !existing.allowsReplacement(by: request) {
                throw PerformanceCommitmentClientError.storage
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try excludeFromBackup(directory)
            try JSONEncoder().encode(request).write(to: file(request.actorID), options: [.atomic, .completeFileProtection])
            try excludeFromBackup(file(request.actorID))
        } catch { throw PerformanceCommitmentClientError.storage }
    }
    func remove(for actorID: UUID, matching requestID: UUID?) throws {
        if requestID == nil { deletedActors.insert(actorID) }
        if let requestID, try load(for: actorID)?.requestID != requestID { return }
        guard FileManager.default.fileExists(atPath: file(actorID).path) else { return }
        do { try FileManager.default.removeItem(at: file(actorID)) }
        catch { throw PerformanceCommitmentClientError.storage }
    }
    private func file(_ actorID: UUID) -> URL {
        directory.appendingPathComponent("\(actorID.uuidString.lowercased()).json")
    }
    private func excludeFromBackup(_ original: URL) throws {
        var url = original
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

actor EphemeralPendingPerformanceCommitmentRequestStore: PendingPerformanceCommitmentRequestStore {
    private var requests: [UUID: PendingPerformanceCommitmentRequest] = [:]
    private var deletedActors: Set<UUID> = []
    func load(for actorID: UUID) -> PendingPerformanceCommitmentRequest? { requests[actorID] }
    func save(_ request: PendingPerformanceCommitmentRequest) throws {
        guard !deletedActors.contains(request.actorID) else { throw PerformanceCommitmentClientError.storage }
        try request.validate(for: request.actorID)
        if let existing = requests[request.actorID], !existing.allowsReplacement(by: request) {
            throw PerformanceCommitmentClientError.storage
        }
        requests[request.actorID] = request
    }
    func remove(for actorID: UUID, matching requestID: UUID?) {
        if requestID == nil { deletedActors.insert(actorID) }
        if requestID == nil || requests[actorID]?.requestID == requestID { requests[actorID] = nil }
    }
}
