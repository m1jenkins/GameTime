import Foundation

/// New local-only agreements, never a reinterpretation of an old running goal.
enum MetricPrototypeFormat: String, Codable, Sendable {
    case exerciseMinutes = "exercise_minutes"
    case cumulativeDistance = "cumulative_running_distance"
    case timedDistance = "timed_running_distance"

    var source: String {
        switch self {
        case .exerciseMinutes: "fixture_apple_exercise_minutes_v1"
        case .cumulativeDistance: "fixture_cumulative_running_distance_v1"
        case .timedDistance: "fixture_timed_running_distance_v1"
        }
    }
    var unit: String { self == .exerciseMinutes ? "milliminutes" : "millimeters" }
    var title: String {
        switch self {
        case .exerciseMinutes: "Exercise-minute practice record"
        case .cumulativeDistance: "Total running distance"
        case .timedDistance: "One run over your chosen distance"
        }
    }
}
enum MetricPrototypeComparator: String, Codable, Sendable { case strictlyUnder = "lt", atMost = "lte" }
enum MetricPrototypeDistanceUnit: String, CaseIterable, Sendable { case meters, kilometers, miles }

enum MetricPrototypeError: LocalizedError, Equatable {
    case unavailable, accountChanged, invalidTerms, invalidProof, consentRequired
    case requestConflict, closed, storage, capacity
    var errorDescription: String? {
        switch self {
        case .unavailable: "This private practice tool is unavailable. Return to your existing challenges."
        case .accountChanged: "Your account changed. Reopen the practice tool after signing in."
        case .invalidTerms: "Check your distance, time and dates, then review your choices again."
        case .invalidProof: "Check the practice run’s distance and start and finish times, then try again."
        case .consentRequired: "Review the complete practice rules and agree before saving."
        case .requestConflict: "That saved request has different details. Reload your practice records before trying again."
        case .closed: "This practice record is closed to new updates. You can still read it or leave it."
        case .storage: "We couldn’t read or save your private practice records. Unlock your phone and try again."
        case .capacity: "This private notebook has reached a record limit. You can still read your history or leave an open practice record."
        }
    }
}

enum MetricPrototypeUnits {
    static func millimeters(_ text: String, unit: MetricPrototypeDistanceUnit, allowZero: Bool = false) throws -> Int {
        let factor: Int
        switch unit { case .meters: factor = 1_000; case .kilometers: factor = 1_000_000; case .miles: factor = 1_609_344 }
        return try scaledInteger(text, factor: factor, maximum: 1_000_000_000, minimum: allowZero ? 0 : 1)
    }
    static func microseconds(_ seconds: String) throws -> Int {
        try scaledInteger(seconds, factor: 1_000_000, maximum: 86_400_000_000)
    }
    private static func scaledInteger(_ text: String, factor: Int, maximum: Int, minimum: Int = 1) throws -> Int {
        guard text.range(of: #"^[0-9]{1,10}(?:\.[0-9]{1,6})?$"#, options: .regularExpression) != nil,
            let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
        else { throw MetricPrototypeError.invalidTerms }
        var scaled = number * Decimal(factor)
        var whole = Decimal()
        NSDecimalRound(&whole, &scaled, 0, .plain)
        guard scaled == whole, whole >= Decimal(minimum), whole <= Decimal(maximum) else { throw MetricPrototypeError.invalidTerms }
        return NSDecimalNumber(decimal: whole).intValue
    }
}

struct MetricPrototypeDraft: Codable, Equatable, Sendable {
    let format: MetricPrototypeFormat
    /// Integer millimeters, or thousandths of an Exercise minute.
    let target: Int
    let startsAt: DuelInstant
    let endsAt: DuelInstant
    let timezone: String
    let elapsedTargetMicroseconds: Int?
    let comparator: MetricPrototypeComparator?

    func validate() throws {
        guard (1...(format == .exerciseMinutes ? 100_000_000 : 1_000_000_000)).contains(target),
            startsAt.microseconds > 0, startsAt < endsAt,
            endsAt.microseconds - startsAt.microseconds <= 3_660 * 86_400_000_000,
            endsAt.date < Date(timeIntervalSince1970: 253_402_000_000),
            TimeZone(identifier: timezone) != nil else { throw MetricPrototypeError.invalidTerms }
        if format == .timedDistance {
            guard elapsedTargetMicroseconds.map({ (1...86_400_000_000).contains($0) }) == true,
                comparator != nil else { throw MetricPrototypeError.invalidTerms }
        } else {
            guard elapsedTargetMicroseconds == nil, comparator == nil else { throw MetricPrototypeError.invalidTerms }
        }
        if format == .exerciseMinutes {
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = TimeZone(identifier: timezone)!
            guard calendar.component(.weekday, from: startsAt.date) == 2,
                calendar.startOfDay(for: startsAt.date) == startsAt.date,
                calendar.date(byAdding: .day, value: 7, to: startsAt.date) == endsAt.date
            else { throw MetricPrototypeError.invalidTerms }
        }
    }
}

struct MetricPrototypeTerms: Codable, Equatable, Sendable {
    let version: String
    let actorID: UUID
    let agreementID: UUID
    let draft: MetricPrototypeDraft
    let createdAt: DuelInstant
    let correctionsCloseAt: DuelInstant
    let fixtureOnly: Bool

    init(actorID: UUID, agreementID: UUID, draft: MetricPrototypeDraft, createdAt: DuelInstant) throws {
        try draft.validate()
        self.version = "metric-prototype-agreement-v1"
        self.actorID = actorID; self.agreementID = agreementID; self.draft = draft
        self.createdAt = createdAt
        self.correctionsCloseAt = try DuelInstant(Self.utc(draft.endsAt.microseconds + 48 * 3_600_000_000))
        self.fixtureOnly = true
        try validate()
    }
    func validate() throws {
        try draft.validate()
        guard version == "metric-prototype-agreement-v1", fixtureOnly,
            createdAt.microseconds > 0, createdAt < draft.startsAt,
            correctionsCloseAt.microseconds == draft.endsAt.microseconds + 48 * 3_600_000_000
        else { throw MetricPrototypeError.invalidTerms }
    }
    /// Exact W3/W4 TypeScript terms contract, useful for explicit local review
    /// artifacts. Native code never evaluates or publishes its result.
    func evaluatorTermsData() throws -> Data {
        try validate()
        var value: [String: Any] = [
            "version": "weekly-metric-fixtures-v1", "fixture_only": true,
            "actor_id": actorID.uuidString.lowercased(), "agreement_id": agreementID.uuidString.lowercased(),
            "starts_at": Self.utc(draft.startsAt.microseconds), "ends_at": Self.utc(draft.endsAt.microseconds),
            "corrections_close_at": Self.utc(correctionsCloseAt.microseconds), "display_timezone": draft.timezone,
            "format": draft.format.rawValue, "source": draft.format.source, "unit": draft.format.unit,
            "target": draft.target, "comparator": draft.comparator?.rawValue ?? "gte",
        ]
        if draft.format == .exerciseMinutes {
            var calendar = Calendar(identifier: .iso8601); calendar.timeZone = TimeZone(identifier: draft.timezone)!
            value["day_boundaries"] = (0...7).map {
                Self.utc(DuelInstant(date: calendar.date(byAdding: .day, value: $0, to: draft.startsAt.date)!).microseconds)
            }
        } else { value["activity"] = "running" }
        if draft.format == .timedDistance {
            value["elapsed_target_microseconds"] = draft.elapsedTargetMicroseconds!
            value["timing_basis"] = "full_elapsed_including_pauses"
            value["segment_policy"] = "whole_run_only"
            value["attempt_window"] = "start_inclusive_finish_exclusive"
            value["short_tolerance_millimeters"] = 0
            value["long_tolerance_millimeters"] = 0
        }
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
    }
    var binding: Data { get throws { try evaluatorTermsData() } }
    static func utc(_ microseconds: Int64) -> String {
        let base = Date(timeIntervalSince1970: Double(microseconds / 1_000_000)).formatted(.iso8601)
        return base.replacingOccurrences(of: "Z", with: String(format: ".%06lldZ", microseconds % 1_000_000))
    }
}

struct MetricPrototypeProofDraft: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable { case observed, missing, unavailable }
    let state: State
    let value: Int?
    let startsAt: DuelInstant?
    let endsAt: DuelInstant?
    func validate(for terms: MetricPrototypeTerms, recordedAt: DuelInstant) throws {
        if state != .observed {
            guard value == nil, startsAt == nil, endsAt == nil else { throw MetricPrototypeError.invalidProof }
            return
        }
        guard let value, (0...(terms.draft.format == .exerciseMinutes ? 100_000_000 : 1_000_000_000)).contains(value),
            let startsAt, let endsAt, startsAt >= terms.draft.startsAt, startsAt < endsAt,
            endsAt <= terms.draft.endsAt, endsAt <= recordedAt,
            terms.draft.format != .timedDistance || endsAt < terms.draft.endsAt
        else { throw MetricPrototypeError.invalidProof }
    }
}

struct MetricPrototypeProofRevision: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let revision: Int
    let previousRevision: Int?
    let termsBinding: Data
    let recordedAt: DuelInstant
    let draft: MetricPrototypeProofDraft
}
struct MetricPrototypeAgreement: Codable, Equatable, Identifiable, Sendable {
    let terms: MetricPrototypeTerms
    let consentBinding: Data
    let consentAt: DuelInstant
    var proofs: [MetricPrototypeProofRevision]
    var exitedAt: DuelInstant?
    var id: UUID { terms.agreementID }
    /// These reports have no authority to settle, even when numbers exceed a goal.
    var qualification: String { "unresolved_not_evaluated" }
    var final: Bool { false }
    func validate(for actorID: UUID) throws {
        try terms.validate()
        guard terms.actorID == actorID, consentBinding == (try terms.binding), consentAt == terms.createdAt,
            proofs.count <= 100, Set(proofs.map(\.id)).count == proofs.count,
            exitedAt.map({ $0 >= consentAt }) ?? true else { throw MetricPrototypeError.storage }
        var prior: MetricPrototypeProofRevision?
        for proof in proofs {
            guard proof.termsBinding == consentBinding, proof.revision == (prior?.revision ?? 0) + 1,
                proof.previousRevision == prior?.revision, proof.recordedAt >= terms.draft.startsAt,
                proof.recordedAt < terms.correctionsCloseAt,
                prior.map({ proof.recordedAt > $0.recordedAt }) ?? true,
                exitedAt.map({ proof.recordedAt <= $0 }) ?? true else { throw MetricPrototypeError.storage }
            try proof.draft.validate(for: terms, recordedAt: proof.recordedAt)
            prior = proof
        }
    }
}
