import Foundation

/// Timestamp arithmetic is the existing microsecond primitive, not an old agreement decoder.
typealias WeeklyInstant = DuelInstant

indirect enum WeeklyJSON: Codable, Equatable, Sendable {
    case object([String: WeeklyJSON]), array([WeeklyJSON]), string(String), integer(Int), bool(Bool), null
    init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int.self) { self = .integer(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: WeeklyJSON].self) { self = .object(v) }
        else { self = .array(try c.decode([WeeklyJSON].self)) }
    }
    func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }
    subscript(_ key: String) -> WeeklyJSON? { if case .object(let v) = self { v[key] } else { nil } }
    var string: String? { if case .string(let v) = self { v } else { nil } }
    var integer: Int? { if case .integer(let v) = self { v } else { nil } }
    static func data(_ value: WeeklyJSON) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

struct WeeklyRuleFields: Codable, Equatable, Sendable {
    struct Person: Codable, Equatable, Identifiable, Sendable {
        let participantId: UUID
        let targetSteps: Int
        var id: UUID { participantId }
    }
    struct Day: Codable, Equatable, Sendable { let date: String; let startsAt: WeeklyInstant; let endsAt: WeeklyInstant }
    struct Lifecycle: Codable, Equatable, Sendable {
        let noticeBy: WeeklyInstant
        let filingWindowHours: Int
        let resolutionWindowHours: Int
        let finalityBy: WeeklyInstant
        let simulationEntryCents: Int
        let feeCents: Int
        let exitPolicy: String
        let retentionPolicy: String
    }
    let agreementVersion: Int
    let policy: WeeklyJSON
    let creatorId: UUID?
    let createdAt: WeeklyInstant
    let timezone: String
    let startsAt: WeeklyInstant
    let endsAt: WeeklyInstant
    let uploadClosesAt: WeeklyInstant
    let correctionsCloseAt: WeeklyInstant
    let days: [Day]
    let participants: [Person]?
    let lifecycle: Lifecycle
    let commonTargetSteps: Int?
    let capacity: Int?
    let targetStatus: String?
    var isCommunity: Bool { policy["version"]?.string == "weekly-community-steps-fixture-v1" }
}

/// Keeps every exact wire term for consent/recovery while exposing typed display fields.
struct WeeklyTerms: Codable, Equatable, Sendable {
    let raw: WeeklyJSON
    let fields: WeeklyRuleFields
    init(raw: WeeklyJSON) throws {
        self.raw = raw
        fields = try JSONDecoder().decode(WeeklyRuleFields.self, from: WeeklyJSON.data(raw))
        try validate()
    }
    init(from decoder: any Decoder) throws { try self.init(raw: WeeklyJSON(from: decoder)) }
    func encode(to encoder: any Encoder) throws { try raw.encode(to: encoder) }
    func validate() throws {
        let f = fields, p = f.policy, l = f.lifecycle
        guard f.agreementVersion == 1,
              ["weekly-friend-steps-fixture-v1", "weekly-community-steps-fixture-v1"].contains(p["version"]?.string ?? ""),
              p["source"]?.string == "fixture_weekly_steps_v1", p["metric"]?.string == "steps",
              p["unit"]?.string == "whole_steps", p["mode"]?.string == "fictional_nonredeemable",
              p["simulatedCentsEach"]?.integer == 2000, p["feeCentsEach"]?.integer == 0,
              f.createdAt < f.startsAt, f.startsAt < f.endsAt, TimeZone(identifier: f.timezone) != nil,
              f.uploadClosesAt.microseconds == f.endsAt.microseconds + 24 * 3_600_000_000,
              f.correctionsCloseAt.microseconds == f.endsAt.microseconds + 48 * 3_600_000_000,
              l.noticeBy.microseconds == f.endsAt.microseconds + 72 * 3_600_000_000,
              l.finalityBy.microseconds == f.endsAt.microseconds + 216 * 3_600_000_000,
              l.filingWindowHours == 48, l.resolutionWindowHours == 72,
              l.simulationEntryCents == 2000, l.feeCents == 0,
              l.exitPolicy == "void_friend_refund_community_v1", l.retentionPolicy == "private_fictional_receipts_v1",
              f.days.count == 7, Set(f.days.map(\.date)).count == 7,
              f.days.first?.startsAt == f.startsAt, f.days.last?.endsAt == f.endsAt else {
            throw WeeklyClientError.invalidResponse
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: f.timezone)!
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone; formatter.dateFormat = "yyyy-MM-dd"
        guard calendar.component(.weekday, from: f.startsAt.date) == 2 else { throw WeeklyClientError.invalidResponse }
        for (i, day) in f.days.enumerated() {
            guard day.startsAt < day.endsAt, day.startsAt.microseconds % 1_000_000 == 0,
                  formatter.string(from: day.startsAt.date) == day.date,
                  calendar.startOfDay(for: day.startsAt.date) == day.startsAt.date,
                  calendar.date(byAdding: .day, value: 1, to: day.startsAt.date) == day.endsAt.date,
                  i == 0 || f.days[i - 1].endsAt == day.startsAt else { throw WeeklyClientError.invalidResponse }
        }
        if f.isCommunity {
            guard f.commonTargetSteps.map({ (1...1_000_000).contains($0) }) == true,
                  f.capacity.map({ (2...30).contains($0) }) == true,
                  f.targetStatus == "fixture_not_launch_target", f.participants == nil else { throw WeeklyClientError.invalidResponse }
        } else {
            guard let people = f.participants, (1...5).contains(people.count),
                  Set(people.map(\.id)).count == people.count,
                  people.allSatisfy({ (1...1_000_000).contains($0.targetSteps) }) else { throw WeeklyClientError.invalidResponse }
        }
    }
}

struct WeeklyPreview: Codable, Equatable, Sendable {
    let terms: WeeklyTerms
    let termsDigest: String
    enum CodingKeys: String, CodingKey { case terms, termsDigest = "terms_digest" }
    func validate(actorID: UUID, draft: WeeklyDraft) throws {
        guard !terms.fields.isCommunity, terms.fields.creatorId == actorID,
              terms.fields.participants?.count == draft.participants.count,
              Set(terms.fields.participants?.map(\.id) ?? []) == Set(draft.participants.map(\.actorID)),
              draft.participants.allSatisfy({ person in terms.fields.participants?.contains(where: {
                  $0.id == person.actorID && $0.targetSteps == person.targetSteps
              }) == true }), terms.fields.timezone == draft.timezone,
              terms.fields.days.first?.date == draft.weekStart, WeeklyModel.isDigest(termsDigest) else { throw WeeklyClientError.invalidResponse }
    }
}

enum WeeklyQualification: String, Codable, Sendable {
    case pending, met, confirmedMiss = "confirmed_miss", unresolved, refund
    var provisionalTitle: String {
        switch self {
        case .unresolved, .refund: "We couldn’t confirm this update yet"
        case .met: "Goal appears met — review pending"
        case .confirmedMiss: "Goal appears missed — review open"
        case .pending: "Waiting for the week’s result"
        }
    }
    var title: String {
        switch self {
        case .pending: "Waiting for the week’s result"
        case .met: "Goal met"
        case .confirmedMiss: "Goal missed"
        case .unresolved, .refund: "This week didn’t count against you"
        }
    }
}

struct WeeklyParticipant: Codable, Equatable, Identifiable, Sendable {
    let actorID: UUID; let targetSteps: Int
    let displayName: String?
    let acceptedAt: WeeklyInstant?; let declinedAt: WeeklyInstant?; let exitedAt: WeeklyInstant?
    var id: UUID { actorID }
    enum CodingKeys: String, CodingKey {
        case displayName = "display_name", actorID = "actor_id", targetSteps = "target_steps", acceptedAt = "accepted_at", declinedAt = "declined_at", exitedAt = "exited_at"
    }
}
struct WeeklyNotice: Codable, Equatable, Identifiable, Sendable {
    let revision: Int; let recordedAt: WeeklyInstant; let fileBy: WeeklyInstant; let resolveBy: WeeklyInstant
    let qualification: WeeklyQualification
    var id: Int { revision }
    enum CodingKeys: String, CodingKey { case revision, qualification, recordedAt = "recorded_at", fileBy = "file_by", resolveBy = "resolve_by" }
}
struct WeeklyCase: Codable, Equatable, Identifiable, Sendable {
    let id: UUID; let noticeRevision: Int; let reason: WeeklyReviewReason; let recordedAt: WeeklyInstant; let resolution: String?
    enum CodingKeys: String, CodingKey { case id, reason, resolution, noticeRevision = "notice_revision", recordedAt = "recorded_at" }
}
struct WeeklyExit: Codable, Equatable, Identifiable, Sendable {
    let id: UUID; let kind: String; let recordedAt: WeeklyInstant
    enum CodingKeys: String, CodingKey { case id, kind, recordedAt = "recorded_at" }
}
struct WeeklySupport: Codable, Equatable, Identifiable, Sendable {
    let id: UUID; let reason: WeeklySupportReason; let recordedAt: WeeklyInstant
    enum CodingKeys: String, CodingKey { case id, reason, recordedAt = "recorded_at" }
}
struct WeeklyResult: Codable, Equatable, Sendable {
    let recordedAt: WeeklyInstant; let qualification: WeeklyQualification; let reason: String
    enum CodingKeys: String, CodingKey { case qualification, reason, recordedAt = "recorded_at" }
}
struct WeeklyAllocation: Codable, Equatable, Sendable {
    let recordedAt: WeeklyInstant; let returnedCents: Int; let bonusCents: Int; let mode: String; let redeemable: Bool
    enum CodingKeys: String, CodingKey { case mode, redeemable, recordedAt = "recorded_at", returnedCents = "returned_cents", bonusCents = "bonus_cents" }
}
struct WeeklyProgress: Codable, Equatable, Sendable {
    let observedSteps: Int; let qualifyingSteps: Int?; let completeDayCount: Int?; let updatedAt: WeeklyInstant?; let status: String
    enum CodingKeys: String, CodingKey { case status, observedSteps = "observed_steps", qualifyingSteps = "qualifying_steps", completeDayCount = "complete_day_count", updatedAt = "updated_at" }
}
struct WeeklyChallenge: Codable, Equatable, Identifiable, Sendable {
    let id: UUID; let mode: String; let status: String; let terms: WeeklyTerms; let termsDigest: String
    let serverNow: WeeklyInstant; let participantCount: Int; let acceptedCount: Int
    let own: WeeklyParticipant; let roster: [WeeklyParticipant]; let contactSuppressed: Bool
    let ownProgress: WeeklyProgress?; let notices: [WeeklyNotice]; let cases: [WeeklyCase]; let exits: [WeeklyExit]; let support: [WeeklySupport]
    let result: WeeklyResult?; let allocation: WeeklyAllocation?
    enum CodingKeys: String, CodingKey {
        case id, mode, status, terms, own, roster, notices, cases, exits, support, result, allocation
        case termsDigest = "terms_digest", serverNow = "server_now", participantCount = "participant_count", acceptedCount = "accepted_count"
        case contactSuppressed = "contact_suppressed", ownProgress = "own_progress"
    }
    func validate(for actorID: UUID) throws {
        try terms.validate()
        guard own.actorID == actorID, (1...1_000_000).contains(own.targetSteps), WeeklyModel.isDigest(termsDigest),
              ["friend", "community"].contains(mode), (mode == "community") == terms.fields.isCommunity,
              ["invited", "scheduled", "active", "review", "closed", "final"].contains(status),
              (1...30).contains(participantCount), (0...participantCount).contains(acceptedCount),
              Set(roster.map(\.id)).count == roster.count,
              !(mode == "community" || contactSuppressed) || roster.isEmpty,
              !contactSuppressed || terms.fields.participants?.map(\.id) == [actorID],
              mode != "friend" || contactSuppressed || ((2...5).contains(roster.count) && Set(roster.map(\.id)) == Set(terms.fields.participants?.map(\.id) ?? []) && roster.allSatisfy { person in terms.fields.participants?.contains { $0.id == person.actorID && $0.targetSteps == person.targetSteps } == true }),
              mode != "community" || terms.fields.commonTargetSteps == own.targetSteps,
              Set(notices.map(\.revision)).count == notices.count,
              notices.allSatisfy({ $0.revision >= 0 && $0.fileBy.microseconds == $0.recordedAt.microseconds + 48 * 3_600_000_000 && $0.resolveBy.microseconds == $0.fileBy.microseconds + 72 * 3_600_000_000 }),
              cases.allSatisfy({ $0.resolution == nil || ["upheld", "void"].contains($0.resolution!) }) else { throw WeeklyClientError.invalidResponse }
        if let progress = ownProgress {
            guard (0...7_000_000).contains(progress.observedSteps),
                  (progress.status == "client_progress_only" && progress.qualifyingSteps == nil && progress.completeDayCount == nil) ||
                  (progress.status == "fixture_only" && progress.qualifyingSteps.map { (0...7_000_000).contains($0) } == true && progress.completeDayCount.map { (0...7).contains($0) } == true) else { throw WeeklyClientError.invalidResponse }
        }
        if let allocation {
            guard result != nil, allocation.mode == "fictional_nonredeemable", !allocation.redeemable,
                  (0...2000).contains(allocation.returnedCents), (0...60_000).contains(allocation.bonusCents) else { throw WeeklyClientError.invalidResponse }
        }
    }
}

struct WeeklyCohort: Codable, Equatable, Identifiable, Sendable {
    let id: UUID; let mode: String; let terms: WeeklyTerms; let termsDigest: String
    let joinBy: WeeklyInstant; let capacity: Int; let participantCount: Int
    enum CodingKeys: String, CodingKey { case id, mode, terms, capacity, termsDigest = "terms_digest", joinBy = "join_by", participantCount = "participant_count" }
    func validate() throws {
        guard mode == "community", terms.fields.isCommunity, WeeklyModel.isDigest(termsDigest),
              capacity == terms.fields.capacity, (0...capacity).contains(participantCount), joinBy < terms.fields.startsAt else { throw WeeklyClientError.invalidResponse }
    }
}
struct WeeklyPreferences: Codable, Equatable, Sendable {
    let paused: Bool
    let pilotConsent: Bool
    enum CodingKeys: String, CodingKey { case paused = "entry_paused", pilotConsent = "pilot_consent" }
}
struct WeeklySharing: Codable, Equatable, Identifiable, Sendable {
    let friendID: UUID; let displayName: String; let enabled: Bool; let offerID: UUID; let state: String
    var id: UUID { friendID }
    enum CodingKeys: String, CodingKey { case enabled, state, offerID = "offer_id", friendID = "friend_id", displayName = "display_name" }
}
struct WeeklyFollowRequest: Codable, Equatable, Identifiable, Sendable {
    let challengeID: UUID; let ownerID: UUID; let displayName: String; let offerID: UUID
    let policyVersion: String; let state: String
    var id: UUID { offerID }
    enum CodingKeys: String, CodingKey { case state, challengeID = "challenge_id", ownerID = "owner_id", displayName = "display_name", offerID = "offer_id", policyVersion = "policy_version" }
}
struct WeeklySharedProgress: Codable, Equatable, Identifiable, Sendable {
    let challengeID: UUID; let ownerID: UUID; let displayName: String; let offerID: UUID
    let startsAt: WeeklyInstant; let endsAt: WeeklyInstant; let timezone: String
    let targetSteps: Int; let observedSteps: Int?; let updatedAt: WeeklyInstant?
    let source: String; let policyVersion: String
    var id: String { challengeID.uuidString + ownerID.uuidString }
    enum CodingKeys: String, CodingKey {
        case timezone, source, offerID = "offer_id", challengeID = "challenge_id", ownerID = "owner_id", displayName = "display_name", startsAt = "starts_at", endsAt = "ends_at", targetSteps = "target_steps", observedSteps = "observed_steps", updatedAt = "updated_at", policyVersion = "policy_version"
    }
    func validate() throws {
        guard startsAt < endsAt, TimeZone(identifier: timezone) != nil,
              (1...1_000_000).contains(targetSteps), observedSteps.map { (0...7_000_000).contains($0) } != false,
              source == "client_progress_only", policyVersion == "weekly-display-sharing-v1" else { throw WeeklyClientError.invalidResponse }
    }
}

struct WeeklyDraft: Equatable, Sendable {
    struct Person: Equatable, Sendable { let actorID: UUID; let targetSteps: Int }
    let participants: [Person]; let weekStart: String; let timezone: String
    func validate(actorID: UUID) throws {
        guard (2...5).contains(participants.count), participants.contains(where: { $0.actorID == actorID }),
              Set(participants.map(\.actorID)).count == participants.count,
              participants.allSatisfy({ (1...1_000_000).contains($0.targetSteps) }),
              weekStart.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil,
              TimeZone(identifier: timezone) != nil else { throw WeeklyClientError.invalidTerms }
    }
    var parameters: WeeklyJSON {
        .object(["p_participants": .array(participants.map { .object(["actor_id": .string($0.actorID.uuidString.lowercased()), "target_steps": .integer($0.targetSteps)]) }),
                 "p_week_start": .string(weekStart), "p_timezone": .string(timezone)])
    }
}
enum WeeklyModel {
    static func isDigest(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { "0123456789abcdef".contains($0) } }
}
