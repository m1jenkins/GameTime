import Foundation

public enum ChallengeHealthUploadError: Error, Equatable, Sendable {
    case invalidRequest, wrongAccount, requestConflict, revisionConflict, queueFull
    case invalidSignature, invalidReceipt, corruptJournal
}

/// The sole real upload representation. It cannot carry records, history,
/// routes, source names, baselines, or client-authored result/completeness flags.
public struct ChallengeHealthUploadRequest: Equatable, Sendable {
    public let exactBytes: Data
    public let actorID: UUID
    public let challengeID: UUID
    public let requestID: UUID
    public let revision: Int
    public let previousRevision: Int?
    public let scope: String

    public init(binding: ChallengeHealthBinding, requestID: UUID, revision: Int,
                previousRevision: Int?, replacement: ChallengeHealthReplacement,
                observedAtMicroseconds: Int64, queriedThroughMicroseconds: Int64) throws {
        guard let policy = binding.realSourcePolicy, policy.metric == binding.metric else {
            throw ChallengeHealthUploadError.invalidRequest
        }
        let state: String
        let value: Int64?
        switch replacement {
        case .value(let activity):
            guard activity.metric == binding.metric else { throw ChallengeHealthUploadError.invalidRequest }
            state = "value"; value = activity.integerValue
        case .deleted: state = "deleted"; value = nil
        case .unresolved: state = "unresolved"; value = nil
        }
        let wire = Wire(actorID: binding.actorID, challengeID: binding.challengeID,
                        agreementVersion: binding.agreementVersion, termsDigest: binding.termsDigest,
                        sourcePolicyVersion: policy.identifier, metric: Self.metricName(binding.metric),
                        windowStartsAt: try Self.timestamp(binding.challengeWindow.startMicroseconds),
                        windowEndsAt: try Self.timestamp(binding.challengeWindow.endMicroseconds),
                        requestID: requestID, revision: revision, previousRevision: previousRevision,
                        state: state, value: value, observedAt: try Self.timestamp(observedAtMicroseconds),
                        queriedThroughAt: try Self.timestamp(queriedThroughMicroseconds),
                        distanceMillimeters: binding.selectedDistanceMillimeters)
        try self.init(wire: wire)
    }

    /// Restoring bytes validates the exact canonical shape, including unknown
    /// keys. It never reserializes a pending request before retransmission.
    public init(restoring exactBytes: Data) throws {
        guard exactBytes.count <= 4096 else { throw ChallengeHealthUploadError.invalidRequest }
        do {
            try self.init(wire: JSONDecoder().decode(Wire.self, from: exactBytes))
            guard self.exactBytes == exactBytes else { throw ChallengeHealthUploadError.invalidRequest }
        } catch { throw ChallengeHealthUploadError.invalidRequest }
    }

    private init(wire: Wire) throws {
        let policies = ["steps": "apple_watch_steps_v1", "exercise": "apple_watch_exercise_v1",
                        "distance": "apple_workout_outdoor_distance_v1", "timed": "apple_workout_outdoor_timed_v1"]
        guard wire.contractVersion == 1, wire.agreementVersion > 0, wire.agreementVersion <= 2_147_483_647,
              wire.termsDigest.utf8.count == 64,
              wire.termsDigest.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              policies[wire.metric] == wire.sourcePolicyVersion,
              wire.revision > 0, wire.revision <= 2_147_483_647,
              wire.previousRevision == (wire.revision == 1 ? nil : wire.revision - 1),
              ["value", "deleted", "unresolved"].contains(wire.state),
              wire.metric != "exercise" || wire.state != "value",
              wire.metric == "timed" ? (wire.distanceMillimeters.map({ $0 > 0 && $0 <= 1_000_000_000 }) ?? false) : wire.distanceMillimeters == nil,
              wire.state == "value" ? (wire.value.map({ $0 > 0 && $0 <= 1_000_000_000 }) ?? false) : wire.value == nil,
              let start = Self.date(wire.windowStartsAt), let end = Self.date(wire.windowEndsAt),
              let observed = Self.date(wire.observedAt), let through = Self.date(wire.queriedThroughAt),
              start < end, start <= through, through <= end, through <= observed
        else { throw ChallengeHealthUploadError.invalidRequest }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.exactBytes = try encoder.encode(wire)
        self.actorID = wire.actorID; self.challengeID = wire.challengeID
        self.requestID = wire.requestID; self.revision = wire.revision; self.previousRevision = wire.previousRevision
        self.scope = [wire.actorID.uuidString, wire.challengeID.uuidString, String(wire.agreementVersion),
                      wire.termsDigest, wire.sourcePolicyVersion, wire.metric,
                      wire.windowStartsAt, wire.windowEndsAt].joined(separator: ":")
                      + (wire.distanceMillimeters.map { ":\($0)" } ?? "")
    }

    private static func metricName(_ metric: ChallengeHealthMetric) -> String {
        switch metric {
        case .steps: "steps"
        case .exerciseSeconds: "exercise"
        case .runningMillimeters: "distance"
        case .timedRunElapsedSeconds: "timed"
        }
    }

    private static func timestamp(_ microseconds: Int64) throws -> String {
        // UTC formatting preserves exact frozen microseconds, including pre-epoch dates.
        let seconds = microseconds / 1_000_000 - (microseconds % 1_000_000 < 0 ? 1 : 0)
        let remainder = microseconds % 1_000_000
        let fraction = remainder < 0 ? remainder + 1_000_000 : remainder
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let base = formatter.string(from: Date(timeIntervalSince1970: Double(seconds)))
        guard base.count == 20 else { throw ChallengeHealthUploadError.invalidRequest }
        return String(base.dropLast()) + String(format: ".%06lldZ", fraction)
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private struct Wire: Codable {
        var contractVersion: Int = 1
        let actorID: UUID, challengeID: UUID
        let agreementVersion: Int
        let termsDigest: String, sourcePolicyVersion: String, metric: String
        let windowStartsAt: String, windowEndsAt: String
        let requestID: UUID
        let revision: Int, previousRevision: Int?
        let state: String, value: Int64?
        let observedAt: String, queriedThroughAt: String
        let distanceMillimeters: Int64?
        enum CodingKeys: String, CodingKey {
            case contractVersion = "contract_version", actorID = "actor_id", challengeID = "challenge_id"
            case agreementVersion = "agreement_version", termsDigest = "terms_digest"
            case sourcePolicyVersion = "source_policy_version", metric
            case windowStartsAt = "window_starts_at", windowEndsAt = "window_ends_at", requestID = "request_id"
            case revision, previousRevision = "previous_revision", state, value
            case observedAt = "observed_at", queriedThroughAt = "queried_through_at"
            case distanceMillimeters = "distance_mm"
        }
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(contractVersion, forKey: .contractVersion)
            try c.encode(actorID.uuidString.lowercased(), forKey: .actorID)
            try c.encode(challengeID.uuidString.lowercased(), forKey: .challengeID)
            try c.encode(agreementVersion, forKey: .agreementVersion)
            try c.encode(termsDigest, forKey: .termsDigest)
            try c.encode(sourcePolicyVersion, forKey: .sourcePolicyVersion)
            try c.encode(metric, forKey: .metric)
            try c.encode(windowStartsAt, forKey: .windowStartsAt); try c.encode(windowEndsAt, forKey: .windowEndsAt)
            try c.encode(requestID.uuidString.lowercased(), forKey: .requestID)
            try c.encode(revision, forKey: .revision); try c.encode(previousRevision, forKey: .previousRevision)
            try c.encode(state, forKey: .state); try c.encode(value, forKey: .value)
            try c.encode(observedAt, forKey: .observedAt); try c.encode(queriedThroughAt, forKey: .queriedThroughAt)
            try c.encodeIfPresent(distanceMillimeters, forKey: .distanceMillimeters)
        }
    }
}

public struct ChallengeHealthSignedUpload: Equatable, Codable, Sendable {
    public let exactBody: Data
    public let keyID: String
    public let assertion: Data
    public let environment: String

    public init(request: ChallengeHealthUploadRequest, keyID: String, assertion: Data, environment: String) throws {
        guard Data(base64Encoded: keyID)?.count == 32, !assertion.isEmpty, assertion.count <= 6144,
              ["development", "production"].contains(environment) else { throw ChallengeHealthUploadError.invalidSignature }
        self.exactBody = request.exactBytes; self.keyID = keyID
        self.assertion = assertion; self.environment = environment
    }
}

/// Pure journal; the iPhone store persists this atomically with file protection.
/// A signed body survives response loss and relaunch without fresh timestamps,
/// request IDs, assertions or revision numbers. Tokens never enter the journal.
public struct ChallengeHealthUploadJournal: Codable, Sendable {
    public let actorID: UUID
    public private(set) var pending: [ChallengeHealthSignedUpload] = []
    private var heads: [String: Int] = [:]
    public init(actorID: UUID) { self.actorID = actorID }

    public init(restoring bytes: Data, actorID: UUID) throws {
        do {
            let saved = try JSONDecoder().decode(Self.self, from: bytes)
            guard saved.actorID == actorID, saved.pending.count <= 64, saved.heads.count <= 4096,
                  saved.heads.values.allSatisfy({ $0 > 0 }) else { throw ChallengeHealthUploadError.corruptJournal }
            var ids: Set<UUID> = [], scopes: Set<String> = []
            for entry in saved.pending {
                let request = try ChallengeHealthUploadRequest(restoring: entry.exactBody)
                let valid = try ChallengeHealthSignedUpload(request: request, keyID: entry.keyID,
                                                           assertion: entry.assertion, environment: entry.environment)
                guard valid == entry, request.actorID == actorID, ids.insert(request.requestID).inserted,
                      scopes.insert(request.scope).inserted,
                      request.previousRevision == saved.heads[request.scope] else { throw ChallengeHealthUploadError.corruptJournal }
            }
            self = saved
        } catch { throw ChallengeHealthUploadError.corruptJournal }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public mutating func enqueue(_ upload: ChallengeHealthSignedUpload) throws {
        let request = try ChallengeHealthUploadRequest(restoring: upload.exactBody)
        guard request.actorID == actorID else { throw ChallengeHealthUploadError.wrongAccount }
        for entry in pending {
            let existing = try ChallengeHealthUploadRequest(restoring: entry.exactBody)
            if existing.requestID == request.requestID {
                guard entry == upload else { throw ChallengeHealthUploadError.requestConflict }
                return
            }
            guard existing.scope != request.scope else { throw ChallengeHealthUploadError.revisionConflict }
        }
        guard pending.count < 64, heads.count < 4096 || heads[request.scope] != nil else { throw ChallengeHealthUploadError.queueFull }
        guard request.previousRevision == heads[request.scope] else { throw ChallengeHealthUploadError.revisionConflict }
        pending.append(upload)
    }

    public mutating func acknowledge(_ request: ChallengeHealthUploadRequest, receipt: Data) throws {
        guard request.actorID == actorID else { throw ChallengeHealthUploadError.wrongAccount }
        guard let index = pending.firstIndex(where: { $0.exactBody == request.exactBytes }) else { throw ChallengeHealthUploadError.requestConflict }
        guard receipt.count <= 4096, let json = try JSONSerialization.jsonObject(with: receipt) as? [String: Any],
              Set(json.keys) == Set(["version", "request_id", "challenge_id", "revision", "accepted_at"]),
              json["version"] as? String == "challenge_real_health_receipt_v1",
              (json["request_id"] as? String).flatMap(UUID.init(uuidString:)) == request.requestID,
              (json["challenge_id"] as? String).flatMap(UUID.init(uuidString:)) == request.challengeID,
              json["revision"] as? Int == request.revision, json["accepted_at"] is String
        else { throw ChallengeHealthUploadError.invalidReceipt }
        pending.remove(at: index); heads[request.scope] = request.revision
    }
}
