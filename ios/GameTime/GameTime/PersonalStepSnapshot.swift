import Foundation

enum PersonalStepDataPolicy: String, Codable, Equatable, Sendable {
    case attestedHourlyV1 = "attested_hourly_v1"
    case healthKitNonmanualDailyV1 = "healthkit_nonmanual_daily_v1"

    var usesAutomaticHealthProgress: Bool {
        self == .healthKitNonmanualDailyV1
    }
}

/// One coherent Health observation for all seven challenge-local dates.
/// Individual days are never merged with a different observation.
struct PersonalStepSnapshot: Codable, Equatable, Sendable {
    struct Day: Codable, Equatable, Identifiable, Sendable {
        let localDate: String
        let totalSteps: Int

        var id: String { localDate }

        enum CodingKeys: String, CodingKey {
            case localDate = "local_date"
            case totalSteps = "total_steps"
        }
    }

    let challengeID: UUID
    let termsFingerprint: String
    let observedAt: Date
    let queryThrough: Date
    let dailyProgress: [Day]

    var totalSteps: Int {
        dailyProgress.reduce(into: 0) { total, day in
            let (value, overflow) = total.addingReportingOverflow(day.totalSteps)
            total = overflow ? Int.max : value
        }
    }

    var isStructurallyValid: Bool {
        dailyProgress.count == 7
            && Set(dailyProgress.map(\.localDate)).count == 7
            && dailyProgress.allSatisfy { $0.totalSteps >= 0 }
            && queryThrough <= observedAt
    }

    func matches(
        challengeID: UUID,
        termsFingerprint: String
    ) -> Bool {
        isStructurallyValid
            && self.challengeID == challengeID
            && self.termsFingerprint == termsFingerprint
    }

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case termsFingerprint = "terms_fingerprint"
        case observedAt = "observed_at"
        case queryThrough = "query_through"
        case dailyProgress = "daily_progress"
    }
}

enum PersonalDisplayedProgressSource: String, Codable, Equatable, Sendable {
    case liveHealth
    case protectedCache
    case serverSnapshot
    case frozenResult
    case legacy
}

enum PersonalDisplayedDayState: String, Codable, Equatable, Sendable {
    case future
    case current
    case complete
}

struct PersonalDisplayedDay: Codable, Equatable, Identifiable, Sendable {
    let localDate: String
    let totalSteps: Int
    let targetSteps: Int?
    let state: PersonalDisplayedDayState
    let metTarget: Bool?

    var id: String { localDate }
}

/// The only progress shape Personal UI should render. It intentionally has no
/// upload, attestation, or hourly-coverage state.
struct PersonalDisplayedProgress: Codable, Equatable, Sendable {
    let totalSteps: Int
    let remainingSteps: Int
    let qualifyingDays: Int
    let completedDays: Int
    let days: [PersonalDisplayedDay]
    let observedAt: Date?
    let snapshotUpdatedAt: Date?
    let source: PersonalDisplayedProgressSource
    let isStale: Bool
    let isFrozen: Bool

    static func snapshot(
        _ snapshot: PersonalStepSnapshot,
        terms: FrozenPersonalTerms,
        source: PersonalDisplayedProgressSource,
        snapshotUpdatedAt: Date? = nil,
        now: Date = Date(),
        frozen: Bool = false,
        stale: Bool = false
    ) -> Self {
        let calendar = PersonalChallengeStart.calendar(terms.timezone)
        let days = snapshot.dailyProgress.map { day -> PersonalDisplayedDay in
            let interval = Self.dayInterval(
                localDate: day.localDate,
                calendar: calendar
            )
            let effectiveStart = interval.map {
                max($0.start, terms.startsAt)
            }
            let effectiveEnd = interval.map {
                min($0.end, terms.endsAt)
            }
            let state: PersonalDisplayedDayState
            if frozen || now >= terms.evidenceCutoff {
                state = .complete
            } else if let effectiveStart,
                effectiveStart >= snapshot.queryThrough
            {
                state = .future
            } else if let effectiveEnd,
                effectiveEnd <= snapshot.queryThrough
            {
                state = .complete
            } else {
                state = .current
            }
            let target = terms.cadence == .daily ? terms.targetSteps : nil
            return PersonalDisplayedDay(
                localDate: day.localDate,
                totalSteps: day.totalSteps,
                targetSteps: target,
                state: state,
                metTarget: target.map { day.totalSteps >= $0 }
            )
        }
        return make(
            days: days,
            terms: terms,
            observedAt: snapshot.observedAt,
            snapshotUpdatedAt: snapshotUpdatedAt,
            source: source,
            isStale: stale,
            isFrozen: frozen
        )
    }

    static func legacy(
        _ progress: PersonalProgress,
        terms: FrozenPersonalTerms,
        status: PersonalChallengeStatus,
        now: Date,
        frozen: Bool
    ) -> Self {
        let calendar = PersonalChallengeStart.calendar(terms.timezone)
        let days = progress.days.map { day in
            let target = terms.cadence == .daily ? terms.targetSteps : nil
            let state = legacyDayState(
                localDate: day.localDate,
                terms: terms,
                status: status,
                now: now,
                frozen: frozen,
                calendar: calendar,
                fallback: day.evidenceState
            )
            return PersonalDisplayedDay(
                localDate: day.localDate,
                totalSteps: day.displayedTrustedSteps,
                targetSteps: target,
                state: state,
                metTarget: target.map { day.displayedTrustedSteps >= $0 }
            )
        }
        return PersonalDisplayedProgress(
            totalSteps: progress.trustedSteps,
            remainingSteps: progress.remainingSteps,
            qualifyingDays: days.filter { $0.metTarget == true }.count,
            completedDays: days.filter { $0.state == .complete }.count,
            days: days,
            observedAt: progress.lastTrustedSyncAt,
            snapshotUpdatedAt: progress.lastTrustedSyncAt,
            source: .legacy,
            isStale: false,
            isFrozen: frozen
        )
    }

    /// The clean read boundary intentionally omits legacy evidence fields. Day
    /// lifecycle is therefore reconstructed from immutable challenge dates and
    /// status instead of treating an absent `evidence_state` as seven completed
    /// days. Exceptional historical evidence remains display-complete once its
    /// local day is over; no hourly coverage language crosses this boundary.
    private static func legacyDayState(
        localDate: String,
        terms: FrozenPersonalTerms,
        status: PersonalChallengeStatus,
        now: Date,
        frozen: Bool,
        calendar: Calendar,
        fallback: PersonalEvidenceState
    ) -> PersonalDisplayedDayState {
        if frozen || status == .completed || status == .cancelled {
            return .complete
        }
        if status == .scheduled { return .future }
        if status == .awaitingEvidence { return .complete }
        if let interval = dayInterval(localDate: localDate, calendar: calendar) {
            let effectiveStart = max(interval.start, terms.startsAt)
            let effectiveEnd = min(interval.end, terms.endsAt)
            if now < effectiveStart { return .future }
            if now >= effectiveEnd { return .complete }
            return .current
        }
        switch fallback {
        case .future: return .future
        case .inProgress, .pending: return .current
        case .complete, .incomplete, .missing, .quarantined,
            .conflicting, .unresolved, .outageWaived:
            return .complete
        }
    }

    /// Terminal v2 rows can intentionally publish a seven-day zero result
    /// without a Health observation/query timestamp. Preserve that as a
    /// server-owned frozen result; absence of timestamps is meaningful and is
    /// not replaced with a fabricated challenge-end query boundary.
    static func frozenServerResult(
        _ progress: PersonalProgress,
        terms: FrozenPersonalTerms,
        snapshotUpdatedAt: Date?
    ) -> Self {
        let days = progress.days.map { day in
            let target = terms.cadence == .daily ? terms.targetSteps : nil
            return PersonalDisplayedDay(
                localDate: day.localDate,
                totalSteps: day.displayedTrustedSteps,
                targetSteps: target,
                state: .complete,
                metTarget: target.map { day.displayedTrustedSteps >= $0 }
            )
        }
        return make(
            days: days,
            terms: terms,
            observedAt: nil,
            snapshotUpdatedAt: snapshotUpdatedAt,
            source: .frozenResult,
            isStale: false,
            isFrozen: true
        )
    }

    private static func make(
        days: [PersonalDisplayedDay],
        terms: FrozenPersonalTerms,
        observedAt: Date?,
        snapshotUpdatedAt: Date?,
        source: PersonalDisplayedProgressSource,
        isStale: Bool,
        isFrozen: Bool
    ) -> Self {
        let total = days.reduce(into: 0) { result, day in
            let (value, overflow) = result.addingReportingOverflow(day.totalSteps)
            result = overflow ? Int.max : value
        }
        let qualifying = days.filter { $0.metTarget == true }.count
        let completed = days.filter { $0.state == .complete }.count
        let remaining: Int
        if terms.cadence == .daily {
            let current = days.first(where: { $0.state == .current })
                ?? days.last(where: { $0.state != .future })
            remaining = max(0, terms.targetSteps - (current?.totalSteps ?? 0))
        } else {
            remaining = max(0, terms.targetSteps - total)
        }
        return PersonalDisplayedProgress(
            totalSteps: total,
            remainingSteps: remaining,
            qualifyingDays: qualifying,
            completedDays: completed,
            days: days,
            observedAt: observedAt,
            snapshotUpdatedAt: snapshotUpdatedAt,
            source: source,
            isStale: isStale,
            isFrozen: isFrozen
        )
    }

    private static func dayInterval(
        localDate: String,
        calendar: Calendar
    ) -> DateInterval? {
        let components = localDate.split(separator: "-").compactMap {
            Int($0)
        }
        guard components.count == 3 else { return nil }
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = calendar.timeZone
        dateComponents.year = components[0]
        dateComponents.month = components[1]
        dateComponents.day = components[2]
        guard let start = calendar.date(from: dateComponents),
            let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return nil }
        return DateInterval(start: start, end: end)
    }
}

enum PersonalDisplayedProgressResolver {
    static func resolve(
        challenge: PersonalChallengeSummary,
        live: PersonalStepSnapshot?,
        cached: PersonalStepSnapshot?,
        now: Date = Date(),
        stale: Bool = false
    ) -> PersonalDisplayedProgress? {
        resolve(
            status: challenge.status,
            terms: challenge.terms,
            policy: challenge.stepDataPolicy,
            serverSnapshot: challenge.serverStepSnapshot,
            snapshotUpdatedAt: challenge.snapshotUpdatedAt,
            legacy: challenge.progress,
            outcome: challenge.outcome,
            live: live,
            cached: cached,
            now: now,
            stale: stale
        )
    }

    static func resolve(
        challenge: PersonalChallengeDetail,
        live: PersonalStepSnapshot?,
        cached: PersonalStepSnapshot?,
        now: Date = Date(),
        stale: Bool = false
    ) -> PersonalDisplayedProgress? {
        resolve(
            status: challenge.status,
            terms: challenge.terms,
            policy: challenge.stepDataPolicy,
            serverSnapshot: challenge.serverStepSnapshot,
            snapshotUpdatedAt: challenge.snapshotUpdatedAt,
            legacy: challenge.progress,
            outcome: challenge.outcome,
            live: live,
            cached: cached,
            now: now,
            stale: stale
        )
    }

    private static func resolve(
        status: PersonalChallengeStatus,
        terms: FrozenPersonalTerms,
        policy: PersonalStepDataPolicy,
        serverSnapshot: PersonalStepSnapshot?,
        snapshotUpdatedAt: Date?,
        legacy: PersonalProgress?,
        outcome: PersonalOutcome?,
        live: PersonalStepSnapshot?,
        cached: PersonalStepSnapshot?,
        now: Date,
        stale: Bool
    ) -> PersonalDisplayedProgress? {
        guard policy.usesAutomaticHealthProgress else {
            return legacy.map {
                .legacy(
                    $0,
                    terms: terms,
                    status: status,
                    now: now,
                    frozen: status == .completed
                )
            }
        }
        let terminal = status == .completed
        let afterCutoff = now >= terms.evidenceCutoff
        if terminal, let serverSnapshot {
            return .snapshot(
                serverSnapshot,
                terms: terms,
                source: .frozenResult,
                snapshotUpdatedAt: snapshotUpdatedAt,
                now: now,
                frozen: true
            )
        }
        if terminal,
            serverSnapshot == nil,
            outcome?.kind == .inconclusive,
            outcome?.reasonCode == "missing_health_data"
        {
            // The clean read contract supplies canonical zero rows when no
            // Health snapshot ever arrived. Those rows are a result envelope,
            // not an observation that Apple Health reported zero steps.
            return nil
        }
        if terminal, let legacy {
            return .frozenServerResult(
                legacy,
                terms: terms,
                snapshotUpdatedAt: snapshotUpdatedAt
            )
        }
        if let live {
            return .snapshot(
                live,
                terms: terms,
                source: .liveHealth,
                now: now,
                stale: stale
            )
        }
        if let cached {
            return .snapshot(
                cached,
                terms: terms,
                source: .protectedCache,
                now: now,
                stale: stale
            )
        }
        if !afterCutoff, let serverSnapshot {
            return .snapshot(
                serverSnapshot,
                terms: terms,
                source: .serverSnapshot,
                snapshotUpdatedAt: snapshotUpdatedAt,
                now: now,
                frozen: false,
                stale: stale
            )
        }
        return nil
    }
}
