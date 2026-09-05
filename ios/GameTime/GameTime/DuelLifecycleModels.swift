import Foundation

/// Wire timestamps keep all six PostgreSQL fractional digits. Date is used
/// only to format the whole second; deadline comparisons use integer micros.
struct DuelInstant: Codable, Equatable, Comparable, Sendable {
    let rawValue: String
    let microseconds: Int64

    init(_ value: String) throws {
        let pattern = #"^(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(?:\.(\d{1,6}))?(Z|[+-]\d{2}:\d{2})$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let full = NSRange(value.startIndex..., in: value)
        guard let match = regex.firstMatch(in: value, range: full),
              let baseRange = Range(match.range(at: 1), in: value),
              let zoneRange = Range(match.range(at: 3), in: value),
              let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: false)
                .parse(String(value[baseRange]) + String(value[zoneRange])) else {
            throw DuelClientError.invalidResponse
        }
        let fraction = Range(match.range(at: 2), in: value).map { String(value[$0]) } ?? ""
        microseconds = Int64(date.timeIntervalSince1970.rounded()) * 1_000_000
            + (Int64(fraction.padding(toLength: 6, withPad: "0", startingAt: 0)) ?? 0)
        rawValue = value
    }

    init(date: Date) {
        // Used for device-clock hints and fictional fixtures, never persisted
        // over an incoming server timestamp.
        let micros = Int64((date.timeIntervalSince1970 * 1_000_000).rounded(.down))
        microseconds = micros
        let seconds = Date(timeIntervalSince1970: Double(micros / 1_000_000))
        rawValue = seconds.formatted(.iso8601).replacingOccurrences(of: "Z", with:
            String(format: ".%06lldZ", micros % 1_000_000))
    }

    init(from decoder: any Decoder) throws {
        try self.init(decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.microseconds < rhs.microseconds }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.microseconds == rhs.microseconds }
    var date: Date { Date(timeIntervalSince1970: Double(microseconds) / 1_000_000) }
    func text(zone: String) -> String {
        let formatter = DateFormatter()
        formatter.timeZone = TimeZone(identifier: zone) ?? .gmt
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm:ss"
        let whole = Date(timeIntervalSince1970: Double(microseconds / 1_000_000))
        let prefix = formatter.string(from: whole)
        let fraction = microseconds % 1_000_000
        formatter.dateFormat = "a zzz"
        return prefix + (fraction == 0 ? "" : String(format: ".%06lld", fraction))
            + " " + formatter.string(from: whole)
    }
}

enum DuelReviewReason: String, Codable, CaseIterable, Sendable {
    case wrongResult = "wrong_result", wrongIdentity = "wrong_identity", missingResult = "missing_result"
    var title: String {
        switch self {
        case .wrongResult: "My result is wrong"
        case .wrongIdentity: "This result belongs to someone else"
        case .missingResult: "My result is missing"
        }
    }
}

enum DuelSafeExitKind: String, Codable, CaseIterable, Sendable {
    case withdrawal, injury
    var title: String { self == .injury ? "Report an injury" : "Withdraw from duel" }
}

struct DuelOutcome: Codable, Equatable, Sendable {
    let kind: String
    let reason: String
    let winnerId: UUID?

    func validate(actors: Set<UUID>) throws {
        let reasons: [String: Set<String>] = [
            "winner": ["faster_chip", "only_finisher"],
            "tie": ["equal_chip_seconds"],
            "withdrawn_no_contest": ["participant_withdrew"],
            "void": ["both_nonfinish", "unresolved_proof", "prestart_withdrawal", "injury",
                     "event_cancelled", "account_deleted", "review_void", "review_timeout", "finality_timeout"]
        ]
        guard reasons[kind]?.contains(reason) == true,
              kind == "winner" ? winnerId.map(actors.contains) == true : winnerId == nil else {
            throw DuelClientError.invalidResponse
        }
    }

    func title(actorID: UUID) -> String {
        switch kind {
        case "winner": winnerId == actorID ? "You have the winning result" : "Your friend has the winning result"
        case "tie": "Same time"
        case "withdrawn_no_contest": "Duel ended after withdrawal"
        default: "This duel didn’t count"
        }
    }

    var explanation: String {
        switch reason {
        case "faster_chip": "The faster qualifying chip time wins."
        case "only_finisher": "One runner finished with a qualifying time; the other has a confirmed nonfinish."
        case "equal_chip_seconds": "Your qualifying times match to the whole second."
        case "both_nonfinish": "Neither runner has a qualifying finish. Neither loses a simulated stake."
        case "unresolved_proof": "We couldn’t confirm this result. Neither of you loses your simulated stake."
        case "prestart_withdrawal", "participant_withdrew": "A runner withdrew. Neither loses a simulated stake."
        case "injury": "A runner reported an injury. Neither loses a simulated stake."
        case "event_cancelled": "The race was cancelled. Neither of you loses your simulated stake."
        case "account_deleted": "A participant left GameTime. Neither runner loses a simulated stake."
        case "review_void": "Review found that this duel should not count. Neither of you loses your simulated stake."
        case "review_timeout": "Review ran out of time. Neither of you loses your simulated stake."
        case "finality_timeout": "We couldn’t finish confirming the result in time. Neither of you loses your simulated stake."
        default: "We couldn’t read this result. Refresh your duel to try again."
        }
    }
}

struct DuelNotice: Codable, Equatable, Identifiable, Sendable {
    var id: Int { proofRevision }
    let proofRevision: Int
    let recordedAt: DuelInstant
    let outcome: DuelOutcome
    let disputeClosesAt: DuelInstant
    let canFileReview: Bool
}

struct DuelReviewCase: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let proofRevision: Int
    let reason: DuelReviewReason
    let filedAt: DuelInstant
    let reviewDueAt: DuelInstant
    let decision: String?
    let decidedAt: DuelInstant?
    var statusText: String {
        switch decision {
        case "uphold": "Review complete — result upheld"
        case "void": "Review complete — duel won’t count"
        default: "Your review request is saved"
        }
    }
}

struct DuelFinalResult: Codable, Equatable, Sendable {
    let version: String
    let challengeId: UUID
    let termsDigest: String
    let proofRevision: Int
    let finalizedAt: DuelInstant
    let outcome: DuelOutcome
}

struct DuelClosure: Codable, Equatable, Sendable {
    let kind: String
    let recordedAt: DuelInstant
    let isOwn: Bool
}

struct DuelLifecycle: Codable, Equatable, Sendable {
    let challengeId: UUID
    let termsDigest: String
    let contactSuppressed: Bool
    let activatedAt: DuelInstant?
    let notices: [DuelNotice]
    let reviews: [DuelReviewCase]
    let finalResult: DuelFinalResult?
    let simulatedReturnCents: Int?
    let serverNow: DuelInstant
    let canExit: Bool
    let closure: DuelClosure?

    func validate(agreement: DuelAgreement, actorID: UUID) throws {
        try agreement.validate(for: actorID)
        guard challengeId == agreement.id, termsDigest == agreement.termsDigest,
              Set(notices.map(\.id)).count == notices.count,
              Set(reviews.map(\.id)).count == reviews.count,
              Set(reviews.map(\.proofRevision)).count == reviews.count,
              !contactSuppressed || (notices.isEmpty && finalResult == nil && (closure == nil || closure?.isOwn == true)),
              simulatedReturnCents.map({ [0, 2000, 4000].contains($0) }) ?? true,
              !canExit || (finalResult == nil && closure == nil && agreement.status == .scheduled),
              closure.map({ ["withdrawal", "injury", "event_cancelled"].contains($0.kind) && $0.recordedAt <= serverNow }) ?? true
        else { throw DuelClientError.invalidResponse }
        let actors = Set([agreement.creatorID, agreement.inviteeID])
        for notice in notices {
            guard notice.proofRevision >= 0, notice.recordedAt <= serverNow,
                  notice.disputeClosesAt.microseconds - notice.recordedAt.microseconds == 168 * 3600 * 1_000_000,
                  !notice.canFileReview || (finalResult == nil && serverNow < notice.disputeClosesAt
                    && !reviews.contains(where: { $0.proofRevision == notice.proofRevision }))
            else { throw DuelClientError.invalidResponse }
            try notice.outcome.validate(actors: actors)
        }
        for review in reviews {
            guard review.proofRevision >= 0, review.filedAt <= serverNow,
                  review.reviewDueAt.microseconds - review.filedAt.microseconds == 168 * 3600 * 1_000_000,
                  (review.decision == nil) == (review.decidedAt == nil),
                  review.decision.map({ ["uphold", "void"].contains($0) }) ?? true
            else { throw DuelClientError.invalidResponse }
        }
        if let final = finalResult {
            guard final.version == "duel-fixture-official-5k-v1", final.challengeId == challengeId,
                  final.termsDigest == termsDigest, final.proofRevision >= 0, final.finalizedAt <= serverNow
            else { throw DuelClientError.invalidResponse }
            try final.outcome.validate(actors: actors)
            if let cents = simulatedReturnCents {
                let expected = final.outcome.kind == "winner" ? (final.outcome.winnerId == actorID ? 4000 : 0) : 2000
                guard cents == expected else { throw DuelClientError.invalidResponse }
            }
        } else if !contactSuppressed && simulatedReturnCents != nil {
            throw DuelClientError.invalidResponse
        }
    }

    var latestNotice: DuelNotice? { notices.max { $0.proofRevision < $1.proofRevision } }
    var progressText: String {
        if contactSuppressed { return "Contact details hidden" }
        if finalResult != nil { return "Result confirmed" }
        if closure != nil { return "Duel exit saved — result update pending" }
        if let latestNotice {
            return reviews.contains { $0.proofRevision == latestNotice.proofRevision && $0.decision == nil }
                ? "Review requested — result not final" : "Result update — review before confirmation"
        }
        if activatedAt != nil { return "We’re waiting for the race results." }
        return ""
    }
}
