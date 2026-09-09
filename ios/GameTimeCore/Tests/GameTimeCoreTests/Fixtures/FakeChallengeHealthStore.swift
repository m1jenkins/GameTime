import Foundation
@testable import GameTimeCore

/// Manually released reads make races reproducible without clocks, sleep or devices.
actor FakeChallengeHealthStore: ChallengeHealthStore {
    private var requests: [ChallengeHealthReadRequest] = []
    private var pending: [Int: CheckedContinuation<ChallengeHealthStoreOutcome, Never>] = [:]
    private var waiters: [(Int, CheckedContinuation<ChallengeHealthReadRequest, Never>)] = []

    func read(_ request: ChallengeHealthReadRequest) async -> ChallengeHealthStoreOutcome {
        let index = requests.count
        requests.append(request)
        return await withCheckedContinuation { continuation in
            pending[index] = continuation
            let ready = waiters.filter { $0.0 < requests.count }
            waiters.removeAll { $0.0 < requests.count }
            for (index, waiter) in ready { waiter.resume(returning: requests[index]) }
        }
    }

    func request(at index: Int) async -> ChallengeHealthReadRequest {
        if index < requests.count { return requests[index] }
        return await withCheckedContinuation { waiters.append((index, $0)) }
    }

    @discardableResult
    func resolve(_ index: Int, with outcome: ChallengeHealthStoreOutcome) -> Bool {
        guard let continuation = pending.removeValue(forKey: index) else { return false }
        continuation.resume(returning: outcome)
        return true
    }
}

enum ChallengeHealthFixtures {
    static let epoch: Int64 = 1_800_000_000
    static func id(_ number: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
    }
    static func date(_ offset: Double = 0) -> Date {
        Date(timeIntervalSince1970: Double(epoch) + offset)
    }
    static func window(start: Int64 = 0, end: Int64 = 1_000,
                       zone: String = "America/Chicago",
                       calendar: ChallengeHealthWindow.CalendarName = .gregorian) throws -> ChallengeHealthWindow {
        try ChallengeHealthWindow(startMicroseconds: (epoch + start) * 1_000_000,
            endMicroseconds: (epoch + end) * 1_000_000, timeZoneIdentifier: zone, calendar: calendar)
    }
    static func binding(metric: ChallengeHealthMetric = .steps, actor: Int = 1,
                        version: Int = 1, digest: String = String(repeating: "a", count: 64)) throws -> ChallengeHealthBinding {
        try ChallengeHealthBinding(actorID: id(actor), challengeID: id(2), agreementVersion: version,
            termsDigest: digest, metric: metric, challengeWindow: window(start: 1_000, end: 2_000))
    }
    static func request(metric: ChallengeHealthMetric = .steps, actor: Int = 1,
                        version: Int = 1, requestID: Int = 3,
                        purpose: ChallengeHealthReadRequest.Purpose = .readinessHistory) throws -> ChallengeHealthReadRequest {
        let binding = try binding(metric: metric, actor: actor, version: version)
        return try ChallengeHealthReadRequest(binding: binding, deviceRequestID: id(requestID),
            queryWindow: purpose == .readinessHistory ? window() : binding.challengeWindow, purpose: purpose)
    }
    static func record(_ id: Int = 10, metric: WeeklySourceMetric = .steps,
                       start: Double = 10, end: Double = 70, value: Double = 100,
                       manual: Bool? = false, source: String? = "synthetic.source",
                       sync: String? = nil, syncVersion: Int? = nil,
                       activeDuration: Double? = nil) -> WeeklySourceRecord {
        WeeklySourceRecord(id: Self.id(id), metric: metric, start: date(start), end: date(end), value: value,
            sourceBundleIdentifier: source, sourceVersion: "fixture-version",
            deviceManufacturer: "synthetic-manufacturer", deviceModel: "synthetic-device-private",
            wasUserEntered: manual, syncIdentifier: sync, syncVersion: syncVersion,
            reportedWorkoutDurationSeconds: activeDuration)
    }
    static func snapshot(_ records: [WeeklySourceRecord] = [],
                         request: ChallengeHealthReadRequest? = nil, observed: Double = 1_000,
                         freshness: Double? = 900, earliest: Double? = nil,
                         evidence: ChallengeHealthEvidence = .boundedSnapshot,
                         deleted: Set<UUID> = []) throws -> ChallengeHealthSnapshot {
        try ChallengeHealthSnapshot(request: request ?? Self.request(), records: records,
            deletedRecordIDs: deleted, observedAt: date(observed), sourceFreshness: freshness.map(date),
            earliestAuthorizedSampleDate: earliest.map(date), evidence: evidence)
    }
    static func policy(_ decisions: [Int: ChallengeHealthSyntheticPolicy.Decision],
                       reconciled: Bool = false, freshThrough: Double = 1_000) -> ChallengeHealthSyntheticPolicy {
        ChallengeHealthSyntheticPolicy(decisions: Dictionary(uniqueKeysWithValues: decisions.map { (id($0.key), $0.value) }),
            resolvesReconciliation: reconciled, freshThrough: date(freshThrough))
    }
}
