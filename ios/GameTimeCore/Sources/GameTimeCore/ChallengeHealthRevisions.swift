import Foundation

public enum ChallengeHealthUnresolvedReason: String, Sendable, Encodable {
    case lostVisibility, sourcePolicyUnaccepted, limitedHistory, requeryRequired
    case temporarilyUnavailable, normalizationUnresolved
}

/// A replacement, never an additive delta or a max-with-previous merge.
public enum ChallengeHealthReplacement: Equatable, Sendable, Encodable {
    case value(ChallengeHealthValue)
    case deleted
    case unresolved(ChallengeHealthUnresolvedReason)

    private enum CodingKeys: String, CodingKey { case kind, value, reason }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .value(let value):
            try container.encode("value", forKey: .kind)
            try container.encode(value, forKey: .value)
        case .deleted: try container.encode("deleted", forKey: .kind)
        case .unresolved(let reason):
            try container.encode("unresolved", forKey: .kind)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// Versioned rehearsal format, deliberately distinguished from real ingestion.
/// No raw record, history window, device name, source identity, route or baseline
/// can be supplied to this encoder. It is not an HTTP request or production wire API.
public struct ChallengeHealthRevision: Equatable, Sendable, Encodable {
    public let contractVersion = 1
    public let mode = "synthetic_only"
    public let binding: ChallengeHealthBinding
    public let deviceRequestID: UUID
    public let revisionID: UUID
    public let previousRevisionID: UUID?
    public let replacement: ChallengeHealthReplacement
    public let observedAtMicroseconds: Int64
    public let sourceFreshnessMicroseconds: Int64?
    public let evidence: ChallengeHealthEvidence

    public init(binding: ChallengeHealthBinding, deviceRequestID: UUID, revisionID: UUID,
                previousRevisionID: UUID?, replacement: ChallengeHealthReplacement,
                observedAtMicroseconds: Int64, sourceFreshnessMicroseconds: Int64?,
                evidence: ChallengeHealthEvidence) throws {
        guard revisionID != previousRevisionID,
              sourceFreshnessMicroseconds.map({ $0 <= observedAtMicroseconds }) ?? true
        else { throw ChallengeHealthContractError.invalidRevision }
        if case .value(let value) = replacement, value.metric != binding.metric {
            throw ChallengeHealthContractError.invalidValue
        }
        if case .deleted = replacement, evidence != .explicitDeletion {
            throw ChallengeHealthContractError.invalidDeletionEvidence
        }
        self.binding = binding
        self.deviceRequestID = deviceRequestID
        self.revisionID = revisionID
        self.previousRevisionID = previousRevisionID
        self.replacement = replacement
        self.observedAtMicroseconds = observedAtMicroseconds
        self.sourceFreshnessMicroseconds = sourceFreshnessMicroseconds
        self.evidence = evidence
    }
}

public struct ChallengeHealthPendingRevision: Equatable, Sendable {
    public let revision: ChallengeHealthRevision
    /// Encoded exactly once; retries return these bytes without rebuilding dates,
    /// IDs or JSON. Signing, durable storage and networking belong to later work.
    public let exactBytes: Data
    public var permitsRealIngestion: Bool { false }
}

/// Local rehearsal journal. A context switch drops this instance's retry access;
/// a future durable outbox must independently enforce its actor/session fence.
public struct ChallengeHealthRevisionJournal: Sendable {
    public private(set) var binding: ChallengeHealthBinding
    public private(set) var latest: ChallengeHealthPendingRevision?
    private var pending: [UUID: ChallengeHealthPendingRevision] = [:]

    public init(binding: ChallengeHealthBinding) { self.binding = binding }

    public mutating func switchBinding(to binding: ChallengeHealthBinding) {
        self.binding = binding
        latest = nil
        pending.removeAll()
    }

    public mutating func prepare(_ revision: ChallengeHealthRevision) throws -> ChallengeHealthPendingRevision {
        guard revision.binding == binding else { throw ChallengeHealthContractError.bindingMismatch }
        if let stored = pending[revision.deviceRequestID] {
            guard stored.revision == revision else { throw ChallengeHealthContractError.requestIDConflict }
            return stored
        }
        guard revision.previousRevisionID == latest?.revision.revisionID,
              !pending.values.contains(where: { $0.revision.revisionID == revision.revisionID }),
              latest.map({ revision.observedAtMicroseconds >= $0.revision.observedAtMicroseconds }) ?? true
        else { throw ChallengeHealthContractError.invalidRevision }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let entry = ChallengeHealthPendingRevision(revision: revision, exactBytes: try encoder.encode(revision))
        pending[revision.deviceRequestID] = entry
        latest = entry
        return entry
    }

    public func retry(deviceRequestID: UUID, binding: ChallengeHealthBinding) throws -> ChallengeHealthPendingRevision? {
        guard self.binding == binding else { throw ChallengeHealthContractError.bindingMismatch }
        return pending[deviceRequestID]
    }
}
