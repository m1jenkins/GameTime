import Foundation

struct DuelPolicySpecification: Codable, Equatable, Sendable {
    let source: String
    let sport: String
    let distanceMeters: Int
    let timingBasis: String
    let precisionSeconds: Int
    let attempts: Int
    let handicap: String
    let mode: String
    let currency: String
    let stakeCentsEach: Int
    let feeCentsEach: Int
    let participantCount: Int
    let acceptWithinHours: Int
    let acceptBeforeStartHours: Int
    let resultsAfterEndHours: Int
    let disputeAfterDurableNoticeHours: Int
    let reviewAfterFilingHours: Int
    let finalityAfterEndHours: Int
    let winner: String
    let tie: String
    let confirmedNonfinish: String
    let bothNonfinish: String
    let missingOrAmbiguousProof: String
    let prestartCancellation: String
    let poststartWithdrawal: String
    let injuryOrEventCancellation: String
    let settlement: String
    let reviewTimeout: String
    let corrections: String
    let consentVersion: String

    enum CodingKeys: String, CodingKey {
        case source = "source"
        case sport = "sport"
        case distanceMeters = "distance_meters"
        case timingBasis = "timing_basis"
        case precisionSeconds = "precision_seconds"
        case attempts = "attempts"
        case handicap = "handicap"
        case mode = "mode"
        case currency = "currency"
        case stakeCentsEach = "stake_cents_each"
        case feeCentsEach = "fee_cents_each"
        case participantCount = "participant_count"
        case acceptWithinHours = "accept_within_hours"
        case acceptBeforeStartHours = "accept_before_start_hours"
        case resultsAfterEndHours = "results_after_end_hours"
        case disputeAfterDurableNoticeHours = "dispute_after_durable_notice_hours"
        case reviewAfterFilingHours = "review_after_filing_hours"
        case finalityAfterEndHours = "finality_after_end_hours"
        case winner = "winner"
        case tie = "tie"
        case confirmedNonfinish = "confirmed_nonfinish"
        case bothNonfinish = "both_nonfinish"
        case missingOrAmbiguousProof = "missing_or_ambiguous_proof"
        case prestartCancellation = "prestart_cancellation"
        case poststartWithdrawal = "poststart_withdrawal"
        case injuryOrEventCancellation = "injury_or_event_cancellation"
        case settlement = "settlement"
        case reviewTimeout = "review_timeout"
        case corrections = "corrections"
        case consentVersion = "consent_version"
    }

    static let simulated5K = DuelPolicySpecification(
        source: "fixture_official_5k_v1",
        sport: "outdoor_running",
        distanceMeters: 5000,
        timingBasis: "organizer_chip",
        precisionSeconds: 1,
        attempts: 1,
        handicap: "none",
        mode: "simulated",
        currency: "USD",
        stakeCentsEach: 2000,
        feeCentsEach: 0,
        participantCount: 2,
        acceptWithinHours: 72,
        acceptBeforeStartHours: 1,
        resultsAfterEndHours: 72,
        disputeAfterDurableNoticeHours: 168,
        reviewAfterFilingHours: 168,
        finalityAfterEndHours: 720,
        winner: "lower_valid_chip_seconds",
        tie: "return_both_zero_fee",
        confirmedNonfinish: "qualifying_finisher_wins_after_review",
        bothNonfinish: "void_zero_consequence",
        missingOrAmbiguousProof: "review_then_void_zero_consequence",
        prestartCancellation: "creator_or_either_accepted_runner_zero_consequence",
        poststartWithdrawal: "withdrawn_no_contest_zero_consequence",
        injuryOrEventCancellation: "void_zero_consequence",
        settlement: "simulation_only_after_dispute_deadline_and_review",
        reviewTimeout: "void_zero_consequence",
        corrections: "append_only_no_automatic_new_consequence",
        consentVersion: "duel-simulated-consent-v1"
    )
}

struct DuelPolicy: Codable, Equatable, Sendable {
    let version: String
    let specification: DuelPolicySpecification

    enum CodingKeys: String, CodingKey {
        case version = "version"
        case specification = "specification"
    }

    var isSupported: Bool {
        version == "duel-fixture-5k-v1" && specification == .simulated5K
    }
}

struct DuelEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let policyVersion: String
    let eventName: String
    let course: String
    let wave: String
    let startsAt: Date
    let endsAt: Date
    let displayTimezone: String

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case policyVersion = "policy_version"
        case eventName = "event_name"
        case course = "course"
        case wave = "wave"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case displayTimezone = "display_timezone"
    }

    var isSupported: Bool {
        policyVersion == "duel-fixture-5k-v1"
            && eventName == "Fictional local 5K"
            && course == "fixture_course_5k_v1"
            && wave == "fixture_common_wave_v1"
            && TimeZone(identifier: displayTimezone) != nil && endsAt > startsAt
    }

    func isAvailable(at now: Date) -> Bool {
        isSupported && startsAt.addingTimeInterval(-3600) > now
            && endsAt <= now.addingTimeInterval(720 * 3600)
    }
}

struct DuelTerms: Codable, Equatable, Sendable {
    let agreementVersion: Int
    let policyVersion: String
    let policy: DuelPolicySpecification
    let creatorID: UUID
    let inviteeID: UUID
    let event: DuelEvent
    let createdAt: Date
    let acceptBy: Date
    let resultsDueAt: Date
    let finalityDueAt: Date

    enum CodingKeys: String, CodingKey {
        case agreementVersion = "agreement_version"
        case policyVersion = "policy_version"
        case policy = "policy"
        case creatorID = "creator_id"
        case inviteeID = "invitee_id"
        case event = "event"
        case createdAt = "created_at"
        case acceptBy = "accept_by"
        case resultsDueAt = "results_due_at"
        case finalityDueAt = "finality_due_at"
    }
}

enum DuelStatus: String, Codable, Sendable {
    case invited, scheduled, declined, expired, cancelled
}

struct DuelParticipant: Codable, Equatable, Sendable {
    let challengeID: UUID
    let actorID: UUID
    let role: String
    let acceptedAt: Date?
    let consentPolicyVersion: String?
    let consentTermsDigest: String?
    let declinedAt: Date?

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case actorID = "actor_id"
        case role = "role"
        case acceptedAt = "accepted_at"
        case consentPolicyVersion = "consent_policy_version"
        case consentTermsDigest = "consent_terms_digest"
        case declinedAt = "declined_at"
    }
}

struct DuelAgreement: Codable, Equatable, Identifiable, Sendable {
    var createdAtWireValue: String? = nil
    let id: UUID
    let creatorID: UUID
    let inviteeID: UUID
    let eventID: UUID
    let policyVersion: String
    let createdAt: Date
    let startsAt: Date
    let acceptBy: Date
    let terms: DuelTerms
    let termsDigest: String
    let status: DuelStatus
    let closedAt: Date?
    let closeReason: String?
    let expiryDue: Bool
    let participants: [DuelParticipant]

    enum CodingKeys: String, CodingKey {
        case id = "id"
        case creatorID = "creator_id"
        case inviteeID = "invitee_id"
        case eventID = "event_id"
        case policyVersion = "policy_version"
        case createdAt = "created_at"
        case startsAt = "starts_at"
        case acceptBy = "accept_by"
        case terms = "terms"
        case termsDigest = "terms_digest"
        case status = "status"
        case closedAt = "closed_at"
        case closeReason = "close_reason"
        case expiryDue = "expiry_due"
        case participants = "participants"
    }

    func validate(for actorID: UUID) throws {
        guard [creatorID, inviteeID].contains(actorID), creatorID != inviteeID,
            terms.agreementVersion == 1,
            terms.policyVersion == policyVersion,
            terms.policy == .simulated5K, terms.event.isSupported,
            terms.event.id == eventID, terms.event.policyVersion == policyVersion,
            terms.creatorID == creatorID, terms.inviteeID == inviteeID,
            terms.createdAt == createdAt, terms.acceptBy == acceptBy,
            terms.event.startsAt == startsAt,
            policyVersion == "duel-fixture-5k-v1",
            abs(acceptBy.timeIntervalSince(min(createdAt.addingTimeInterval(72 * 3600), startsAt.addingTimeInterval(-3600)))) < 0.00001,
            abs(terms.resultsDueAt.timeIntervalSince(terms.event.endsAt.addingTimeInterval(72 * 3600))) < 0.00001,
            abs(terms.finalityDueAt.timeIntervalSince(terms.event.endsAt.addingTimeInterval(720 * 3600))) < 0.00001,
            (closedAt == nil) == (status == .invited || status == .scheduled),
            (closedAt == nil) == (closeReason == nil),
            termsDigest.count == 64,
            termsDigest.allSatisfy({ "0123456789abcdef".contains($0) }),
            participants.count == 2,
            Set(participants.map(\.actorID)) == Set([creatorID, inviteeID]),
            participants.allSatisfy({
                $0.challengeID == id
                    && $0.role == ($0.actorID == creatorID ? "creator" : "invitee")
                    && ($0.acceptedAt == nil
                        ? $0.consentPolicyVersion == nil && $0.consentTermsDigest == nil
                        : $0.consentPolicyVersion == policyVersion
                            && $0.consentTermsDigest == termsDigest)
            }),
            participants.first(where: { $0.actorID == creatorID })?.acceptedAt == createdAt,
            status != .scheduled || participants.allSatisfy({ $0.acceptedAt != nil })
        else { throw DuelClientError.invalidResponse }
    }

    func canAccept(actorID: UUID, now: Date) -> Bool {
        actorID == inviteeID && status == .invited && !expiryDue && now < acceptBy
    }

    func canCancel(actorID: UUID, now: Date) -> Bool {
        now < startsAt && ((status == .invited && actorID == creatorID)
            || (status == .scheduled && [creatorID, inviteeID].contains(actorID)))
    }

    var statusText: String {
        switch status {
        case .invited: expiryDue ? "Invitation time ended" : "Waiting for an answer"
        case .scheduled: "You both agreed"
        case .declined: "Invitation declined"
        case .expired: "Invitation time ended"
        case .cancelled: "Duel cancelled"
        }
    }
}

extension DuelAgreement {
    init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        creatorID = try values.decode(UUID.self, forKey: .creatorID)
        inviteeID = try values.decode(UUID.self, forKey: .inviteeID)
        eventID = try values.decode(UUID.self, forKey: .eventID)
        policyVersion = try values.decode(String.self, forKey: .policyVersion)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        startsAt = try values.decode(Date.self, forKey: .startsAt)
        acceptBy = try values.decode(Date.self, forKey: .acceptBy)
        terms = try values.decode(DuelTerms.self, forKey: .terms)
        termsDigest = try values.decode(String.self, forKey: .termsDigest)
        status = try values.decode(DuelStatus.self, forKey: .status)
        closedAt = try values.decodeIfPresent(Date.self, forKey: .closedAt)
        closeReason = try values.decodeIfPresent(String.self, forKey: .closeReason)
        expiryDue = try values.decode(Bool.self, forKey: .expiryDue)
        participants = try values.decode([DuelParticipant].self, forKey: .participants)
        createdAtWireValue = try values.decode(String.self, forKey: .createdAt)
    }

}

struct DuelCatalog: Equatable, Sendable {
    let events: [DuelEvent]
    let policies: [DuelPolicy]
}

enum DuelCodec {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(value) { return date }
            if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false).parse(value) { return date }
            throw DuelClientError.invalidResponse
        }
        return decoder
    }

    static func dateText(_ date: Date, zone: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm:ss"
        let prefix = formatter.string(from: date)
        let fraction = date.timeIntervalSince1970 - floor(date.timeIntervalSince1970)
        let micros = min(999_999, Int((fraction * 1_000_000).rounded()))
        let preciseSeconds = micros == 0 ? "" : String(format: ".%06d", micros)
        formatter.dateFormat = "a zzz"
        return "\(prefix)\(preciseSeconds) \(formatter.string(from: date))"
    }
}
