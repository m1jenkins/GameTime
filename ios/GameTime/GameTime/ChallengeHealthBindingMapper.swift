import Foundation
import CryptoKit
import GameTimeCore

/// Drafts can request local planning/history and readiness. Only freshly read,
/// complete server agreements can yield the activity binding type.
enum ChallengeHealthBindingMapper {
    struct Activity {
        let binding: ChallengeHealthBinding
        let row: ChallengeV1
        fileprivate init(binding: ChallengeHealthBinding, row: ChallengeV1) { self.binding = binding; self.row = row }
    }

    static func source(_ identifier: String?) -> ChallengeHealthRealSourcePolicy? {
        switch identifier {
        case "apple_watch_steps_v1": .appleWatchAutomaticStepsV1
        case "apple_watch_exercise_v1": .appleWatchExerciseV1
        case "apple_watch_exercise_credit_v2": .appleWatchExerciseCreditV2
        case "apple_workout_outdoor_distance_v1": .appleWorkoutOutdoorDistanceV1
        case "apple_workout_outdoor_timed_v1": .appleWorkoutOutdoorTimedV1
        default: nil
        }
    }
    static func adapter(_ binding: ChallengeHealthBinding) -> any ChallengeHealthAdapter {
        switch binding.metric {
        case .steps: return ChallengeHealthAppleWatchStepsAdapter()
        case .exerciseSeconds:
            if binding.realSourcePolicy == .appleWatchExerciseCreditV2 { return ChallengeHealthAppleWatchExerciseCreditAdapter() }
            return ChallengeHealthAppleWatchExerciseAdapter()
        case .runningMillimeters: return ChallengeHealthAppleWorkoutDistanceAdapter()
        case .timedRunElapsedSeconds: return ChallengeHealthAppleWorkoutTimedAdapter()
        }
    }
    static func metric(_ metric: ChallengeV1Policy.Metric) -> ChallengeHealthMetric {
        switch metric {
        case .steps: .steps
        case .exercise: .exerciseSeconds
        case .distance: .runningMillimeters
        case .timed: .timedRunElapsedSeconds
        }
    }
    static func selectedSource(_ metric: ChallengeV1Policy.Metric) -> ChallengeHealthRealSourcePolicy? {
        switch metric {
        case .steps: .appleWatchAutomaticStepsV1
        case .exercise: .appleWatchExerciseCreditV2
        case .distance: .appleWorkoutOutdoorDistanceV1
        case .timed: .appleWorkoutOutdoorTimedV1
        }
    }
    static func binding(actor: UUID, id: UUID, version: Int, digest: String,
                        policy: ChallengeV1Policy, window: ChallengeV1.Window, source: String) throws -> ChallengeHealthBinding {
        guard let source = self.source(source), source.metric == metric(policy.metric) else { throw ChallengeV1Error.invalidResponse }
        return try ChallengeHealthBinding(actorID: actor, challengeID: id, agreementVersion: version,
            termsDigest: digest, metric: source.metric,
            challengeWindow: ChallengeHealthWindow(startMicroseconds: window.startsAt.microseconds,
                endMicroseconds: window.endsAt.microseconds, timeZoneIdentifier: window.timezone, calendar: .gregorian),
            realSourcePolicy: source, selectedDistanceMillimeters: window.distanceMm.map(Int64.init))
    }
    /// Local planning identity. This is never accepted by `activity`, which
    /// requires a fresh server agreement and its exact stored digest.
    static func planning(actor: UUID, id: UUID, policy: ChallengeV1Policy, window: ChallengeV1.Window,
                         source: String, draft: String) throws -> ChallengeHealthBinding {
        guard policy.hasTarget, policy.mode != .community else { throw ChallengeV1Error.unavailable }
        let digest = SHA256.hash(data: try JSONEncoder().encode(window) + Data((policy.id + "|planning|" + draft).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return try binding(actor: actor, id: id, version: 1, digest: digest, policy: policy, window: window, source: source)
    }
    static func planningDraft(actor: UUID, id: UUID, policy: ChallengeV1Policy, config: ChallengeJSON,
                              source: String, draft: String) throws -> ChallengeHealthBinding {
        guard let zone = config["timezone"]?.string, let timeZone = TimeZone(identifier: zone),
              let text = config["start_date"]?.string, let days = config["days"]?.integer, (1...30).contains(days) else { throw ChallengeV1Error.invalidResponse }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar; formatter.timeZone = timeZone; formatter.dateFormat = "yyyy-MM-dd"
        guard let start = formatter.date(from: text), formatter.string(from: start) == text,
              let end = calendar.date(byAdding: .day, value: days, to: start) else { throw ChallengeV1Error.invalidResponse }
        let window = ChallengeV1.Window(startDate: text, days: days, timezone: zone, amountCents: config["amount_cents"]?.integer ?? 100,
            distanceMm: config["distance_mm"]?.integer, startsAt: ChallengeInstant(date: start), endsAt: ChallengeInstant(date: end),
            syncBy: ChallengeInstant(date: end.addingTimeInterval(86400)), correctionsBy: ChallengeInstant(date: end.addingTimeInterval(172800)),
            noticeDue: ChallengeInstant(date: end.addingTimeInterval(172800)))
        return try planning(actor: actor, id: id, policy: policy, window: window, source: source, draft: draft)
    }
    static func agreement(_ row: ChallengeV1, actor: UUID) throws -> ChallengeHealthBinding {
        try row.validate(actor: actor)
        guard let source = row.sourcePolicyVersion, let agreement = row.agreement,
              let terms = agreement.terms, terms["source_policy_version"]?.string == source,
              terms["policy"]?.string == row.policy,
              !row.format.usesReceivedScores || terms["score_rule"]?.string == "received_by_correction_cutoff_v2",
              decodeWindow(terms["config"]) == row.config else { throw ChallengeV1Error.invalidResponse }
        return try binding(actor: actor, id: row.id, version: row.agreementVersion, digest: agreement.digest,
            policy: row.format, window: row.config, source: source)
    }
    static func activity(_ fresh: ChallengeV1, actor: UUID) throws -> Activity {
        guard (fresh.format.hasTarget || fresh.format.usesReceivedScores), !fresh.isClosed, let own = fresh.own(actor),
              own.selected, own.consented, !own.exited,
              ["scheduled", "active", "syncing"].contains(fresh.status) else { throw ChallengeV1Error.unavailable }
        return try Activity(binding: agreement(fresh, actor: actor), row: fresh)
    }
}
