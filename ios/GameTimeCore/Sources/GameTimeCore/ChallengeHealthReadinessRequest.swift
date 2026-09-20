import Foundation

public enum ChallengeHealthReadinessRequestError: Error, Equatable, Sendable {
    case invalidRequest, wrongAccount, requestConflict, invalidSignature, invalidReceipt, corruptJournal
}

/// The minimal readiness receipt request. It deliberately excludes
/// values, totals, history boundaries, source metadata, and any client-authored
/// readiness/completeness assertion.
public struct ChallengeHealthReadinessRequest: Equatable, Sendable {
    public let exactBytes: Data
    public let actorID: UUID
    public let requestID: UUID

    public init(binding: ChallengeHealthBinding, snapshot: ChallengeHealthSnapshot,
                evaluation: ChallengeHealthEvaluation, requestID: UUID) throws {
        guard snapshot.request.binding == binding,
              snapshot.request.purpose == .readinessHistory,
              let policy = Self.readinessPolicy(for: binding),
              evaluation.readiness == .ready,
              evaluation.activity != nil,
              !evaluation.syntheticOnly,
              evaluation.acceptsRealSourceObservation,
              evaluation.permitsRealConsent,
              evaluation.permitsRealIngestion,
              !evaluation.supportsConfirmedMiss,
              evaluation.issues.isDisjoint(with: [
                .historyLimited, .historyRequired, .lostVisibility,
                .freshnessUnresolved, .incompleteEvidence, .normalizationUnresolved,
                .reconciliationUnresolved, .boundaryUnresolved,
                .realSourceProvenanceUnavailable, .realSourcePolicyMismatch
              ]),
              snapshot.request.queryWindow.interval.end <= snapshot.observedAt,
              Self.hasRequiredCalendarDayHistory(snapshot.request, days: policy.historyDays),
              let observedAt = Self.timestamp(snapshot.observedAt)
        else { throw ChallengeHealthReadinessRequestError.invalidRequest }
        try self.init(wire: Wire(actorID: binding.actorID,
                                 sourcePolicyVersion: policy.sourcePolicyVersion,
                                 observedAt: observedAt, requestID: requestID,
                                 distanceMillimeters: policy.includesDistance
                                   ? binding.selectedDistanceMillimeters : nil))
    }

    public init(restoring exactBytes: Data) throws {
        guard exactBytes.count <= 1024,
              let object = try? JSONSerialization.jsonObject(with: exactBytes) as? [String: Any],
              let sourcePolicyVersion = object["source_policy_version"] as? String,
              Self.hasExactWireKeys(object, sourcePolicyVersion: sourcePolicyVersion) else {
            throw ChallengeHealthReadinessRequestError.invalidRequest
        }
        do {
            try self.init(wire: JSONDecoder().decode(Wire.self, from: exactBytes))
            guard self.exactBytes == exactBytes else { throw ChallengeHealthReadinessRequestError.invalidRequest }
        } catch { throw ChallengeHealthReadinessRequestError.invalidRequest }
    }

    private init(wire: Wire) throws {
        guard wire.contractVersion == 1,
              Self.wirePolicy(sourcePolicyVersion: wire.sourcePolicyVersion,
                              distanceMillimeters: wire.distanceMillimeters) != nil,
              wire.observedAt.hasSuffix("Z"),
              Self.date(wire.observedAt) != nil else {
            throw ChallengeHealthReadinessRequestError.invalidRequest
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        exactBytes = try encoder.encode(wire)
        actorID = wire.actorID
        requestID = wire.requestID
    }

    private static func hasRequiredCalendarDayHistory(_ request: ChallengeHealthReadRequest,
                                                       days: Int) -> Bool {
        guard let zone = TimeZone(identifier: request.queryWindow.timeZoneIdentifier) else { return false }
        var calendar: Calendar
        switch request.queryWindow.calendar {
        case .gregorian: calendar = Calendar(identifier: .gregorian)
        case .iso8601: calendar = Calendar(identifier: .iso8601)
        }
        calendar.timeZone = zone
        guard let start = calendar.date(byAdding: .day, value: -days,
                                        to: request.queryWindow.interval.end) else { return false }
        return request.queryWindow.interval.start <= start
    }

    private struct ReadinessPolicy {
        let sourcePolicyVersion: String
        let historyDays: Int
        let includesDistance: Bool
    }

    private static func readinessPolicy(for binding: ChallengeHealthBinding) -> ReadinessPolicy? {
        switch (binding.metric, binding.realSourcePolicy) {
        case (.steps, .appleWatchAutomaticStepsV1):
            return ReadinessPolicy(sourcePolicyVersion: "apple_watch_steps_v1", historyDays: 30,
                                   includesDistance: false)
        case (.exerciseSeconds, .appleWatchExerciseCreditV2):
            return ReadinessPolicy(sourcePolicyVersion: "apple_watch_exercise_credit_v2", historyDays: 30,
                                   includesDistance: false)
        case (.runningMillimeters, .appleWorkoutOutdoorDistanceV1):
            return ReadinessPolicy(sourcePolicyVersion: "apple_workout_outdoor_distance_v1", historyDays: 30,
                                   includesDistance: false)
        case (.timedRunElapsedSeconds, .appleWorkoutOutdoorTimedV1)
                where binding.selectedDistanceMillimeters != nil:
            return ReadinessPolicy(sourcePolicyVersion: "apple_workout_outdoor_timed_v1", historyDays: 90,
                                   includesDistance: true)
        default:
            return nil
        }
    }

    private static func wirePolicy(sourcePolicyVersion: String,
                                   distanceMillimeters: Int64?) -> ReadinessPolicy? {
        switch sourcePolicyVersion {
        case "apple_watch_steps_v1", "apple_watch_exercise_credit_v2":
            return distanceMillimeters == nil
                ? ReadinessPolicy(sourcePolicyVersion: sourcePolicyVersion, historyDays: 30, includesDistance: false)
                : nil
        case "apple_workout_outdoor_distance_v1":
            return distanceMillimeters == nil
                ? ReadinessPolicy(sourcePolicyVersion: sourcePolicyVersion, historyDays: 30, includesDistance: false)
                : nil
        case "apple_workout_outdoor_timed_v1":
            guard let distanceMillimeters, (1...1_000_000_000).contains(distanceMillimeters) else { return nil }
            return ReadinessPolicy(sourcePolicyVersion: sourcePolicyVersion, historyDays: 90, includesDistance: true)
        default:
            return nil
        }
    }

    private static func hasExactWireKeys(_ object: [String: Any], sourcePolicyVersion: String) -> Bool {
        let base: Set<String> = ["contract_version", "actor_id", "source_policy_version", "observed_at", "request_id"]
        if sourcePolicyVersion == "apple_workout_outdoor_timed_v1" {
            return Set(object.keys) == base.union(["distance_mm"])
        }
        return Set(object.keys) == base
    }

    private static func timestamp(_ date: Date) -> String? {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite else { return nil }
        let microseconds = (seconds * 1_000_000).rounded(.down)
        guard let integer = Int64(exactly: microseconds) else { return nil }
        let whole = integer / 1_000_000 - (integer % 1_000_000 < 0 ? 1 : 0)
        let fraction = integer - whole * 1_000_000
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let base = formatter.string(from: Date(timeIntervalSince1970: Double(whole)))
        guard base.count == 20 else { return nil }
        return String(base.dropLast()) + String(format: ".%06lldZ", fraction)
    }

    private static func date(_ timestamp: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: timestamp) ?? fractionalFormatter.date(from: timestamp)
    }

    private struct Wire: Codable {
        var contractVersion: Int = 1
        let actorID: UUID
        let sourcePolicyVersion: String
        let observedAt: String
        let requestID: UUID
        let distanceMillimeters: Int64?
        enum CodingKeys: String, CodingKey {
            case contractVersion = "contract_version", actorID = "actor_id"
            case sourcePolicyVersion = "source_policy_version", observedAt = "observed_at"
            case requestID = "request_id"
            case distanceMillimeters = "distance_mm"
        }
        func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(contractVersion, forKey: .contractVersion)
            try container.encode(actorID.uuidString.lowercased(), forKey: .actorID)
            try container.encode(sourcePolicyVersion, forKey: .sourcePolicyVersion)
            try container.encode(observedAt, forKey: .observedAt)
            try container.encode(requestID.uuidString.lowercased(), forKey: .requestID)
            if let distanceMillimeters {
                try container.encode(distanceMillimeters, forKey: .distanceMillimeters)
            }
        }
    }
}

/// Historical name retained because journal records use this Codable shape.
/// A private-account request has no device assertion and is explicitly marked.
public struct ChallengeHealthSignedReadinessRequest: Equatable, Codable, Sendable {
    public let exactBody: Data
    public let keyID: String
    public let assertion: Data
    public let environment: String

    public init(request: ChallengeHealthReadinessRequest, keyID: String, assertion: Data,
                environment: String) throws {
        if environment == "private_account" {
            guard keyID.isEmpty, assertion.isEmpty else {
                throw ChallengeHealthReadinessRequestError.invalidSignature
            }
            exactBody = request.exactBytes; self.keyID = keyID; self.assertion = assertion
            self.environment = environment
            return
        }
        guard Data(base64Encoded: keyID)?.count == 32,
              !assertion.isEmpty, assertion.count <= 6144,
              ["development", "production"].contains(environment) else {
            throw ChallengeHealthReadinessRequestError.invalidSignature
        }
        exactBody = request.exactBytes; self.keyID = keyID; self.assertion = assertion
        self.environment = environment
    }

    public init(privateAccountRequest request: ChallengeHealthReadinessRequest) throws {
        try self.init(request: request, keyID: "", assertion: Data(), environment: "private_account")
    }

    public var isPrivateAccount: Bool {
        environment == "private_account" && keyID.isEmpty && assertion.isEmpty
    }
}

/// One actor's exact readiness attempts. The iPhone owns protected file
/// persistence; this pure journal never carries a session token or Health data.
public struct ChallengeHealthReadinessJournal: Codable, Sendable {
    public let actorID: UUID
    public private(set) var pending: [ChallengeHealthSignedReadinessRequest] = []
    public init(actorID: UUID) { self.actorID = actorID }

    public init(restoring bytes: Data, actorID: UUID) throws {
        do {
            let saved = try JSONDecoder().decode(Self.self, from: bytes)
            guard saved.actorID == actorID, saved.pending.count <= 16 else {
                throw ChallengeHealthReadinessRequestError.corruptJournal
            }
            var ids = Set<UUID>()
            for signed in saved.pending {
                let request = try ChallengeHealthReadinessRequest(restoring: signed.exactBody)
                let validated = try ChallengeHealthSignedReadinessRequest(
                    request: request, keyID: signed.keyID, assertion: signed.assertion,
                    environment: signed.environment
                )
                guard validated == signed, request.actorID == actorID,
                      ids.insert(request.requestID).inserted else {
                    throw ChallengeHealthReadinessRequestError.corruptJournal
                }
            }
            self = saved
        } catch { throw ChallengeHealthReadinessRequestError.corruptJournal }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public mutating func enqueue(_ signed: ChallengeHealthSignedReadinessRequest) throws {
        let request = try ChallengeHealthReadinessRequest(restoring: signed.exactBody)
        guard request.actorID == actorID else { throw ChallengeHealthReadinessRequestError.wrongAccount }
        if let existing = pending.first(where: {
            (try? ChallengeHealthReadinessRequest(restoring: $0.exactBody).requestID) == request.requestID
        }) {
            guard existing == signed else { throw ChallengeHealthReadinessRequestError.requestConflict }
            return
        }
        pending.append(signed)
    }

    public mutating func acknowledge(_ request: ChallengeHealthReadinessRequest, receipt: Data) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard request.actorID == actorID,
              let index = pending.firstIndex(where: { $0.exactBody == request.exactBytes }),
              receipt.count <= 1024,
              let response = try JSONSerialization.jsonObject(with: receipt) as? [String: Any],
              Set(response.keys) == Set(["version", "request_id", "accepted_at"]),
              response["version"] as? String == "challenge_real_health_readiness_receipt_v1",
              (response["request_id"] as? String).flatMap(UUID.init(uuidString:)) == request.requestID,
              let acceptedAt = response["accepted_at"] as? String,
              (acceptedAt.hasSuffix("Z") || acceptedAt.hasSuffix("+00:00")),
              formatter.date(from: acceptedAt) != nil || fractionalFormatter.date(from: acceptedAt) != nil else {
            throw ChallengeHealthReadinessRequestError.invalidReceipt
        }
        pending.remove(at: index)
    }
}
