import Foundation

/// One opponent-approved, server-stamped change to a contest's timezone.
///
/// The roster keeps the timezone originally accepted. Changes are separate
/// events so an old HealthKit sample can still be bucketed under the timezone
/// that governed it, rather than being relabelled when somebody relocates.
public struct ContestTimeZoneChange: Sendable, Hashable, Codable {
    public let fromTimeZoneIdentifier: String
    public let toTimeZoneIdentifier: String
    public let effectiveAt: Date

    public init(
        fromTimeZoneIdentifier: String,
        toTimeZoneIdentifier: String,
        effectiveAt: Date
    ) {
        self.fromTimeZoneIdentifier = fromTimeZoneIdentifier
        self.toTimeZoneIdentifier = toTimeZoneIdentifier
        self.effectiveAt = effectiveAt
    }
}

public enum ContestTimeZoneScheduleError: Error, Sendable, Equatable {
    case invalidTimeZone(String)
    case unchangedTimeZone(index: Int)
    case brokenChain(index: Int, expected: String, found: String)
    case nonIncreasingEffectiveAt(index: Int)
}

/// The immutable base timezone plus its approved, prospective changes.
///
/// API rows may arrive in any order, so the schedule sorts them by their
/// server-stamped effective instant before validating the chain. Equal instants
/// are rejected because they do not define an unambiguous epoch order. After
/// ordering, a broken chain is still rejected rather than repaired locally: the
/// schedule controls which local day receives evidence, so guessing a link can
/// change a result.
public struct ContestTimeZoneSchedule: Sendable {
    public let initialTimeZoneIdentifier: String
    public let initialTimeZone: TimeZone
    public let changes: [ContestTimeZoneChange]

    private let resolvedTimeZones: [TimeZone]

    public init(initialTimeZone: TimeZone) {
        self.initialTimeZoneIdentifier = initialTimeZone.identifier
        self.initialTimeZone = initialTimeZone
        self.changes = []
        self.resolvedTimeZones = [initialTimeZone]
    }

    public init(
        initialTimeZone: TimeZone,
        changes: [ContestTimeZoneChange]
    ) throws {
        try self.init(
            initialTimeZoneIdentifier: initialTimeZone.identifier,
            changes: changes
        )
    }

    public init(
        initialTimeZoneIdentifier: String,
        changes: [ContestTimeZoneChange]
    ) throws {
        guard let initialTimeZone = TimeZone(identifier: initialTimeZoneIdentifier) else {
            throw ContestTimeZoneScheduleError.invalidTimeZone(initialTimeZoneIdentifier)
        }

        let orderedChanges = changes.sorted { left, right in
            if left.effectiveAt != right.effectiveAt {
                return left.effectiveAt < right.effectiveAt
            }
            if left.fromTimeZoneIdentifier != right.fromTimeZoneIdentifier {
                return left.fromTimeZoneIdentifier < right.fromTimeZoneIdentifier
            }
            return left.toTimeZoneIdentifier < right.toTimeZoneIdentifier
        }

        for index in orderedChanges.indices.dropFirst() {
            if orderedChanges[index].effectiveAt == orderedChanges[index - 1].effectiveAt {
                throw ContestTimeZoneScheduleError.nonIncreasingEffectiveAt(index: index)
            }
        }

        var expectedIdentifier = initialTimeZoneIdentifier
        var resolved = [initialTimeZone]

        for (index, change) in orderedChanges.enumerated() {
            guard change.fromTimeZoneIdentifier == expectedIdentifier else {
                throw ContestTimeZoneScheduleError.brokenChain(
                    index: index,
                    expected: expectedIdentifier,
                    found: change.fromTimeZoneIdentifier
                )
            }
            guard change.toTimeZoneIdentifier != change.fromTimeZoneIdentifier else {
                throw ContestTimeZoneScheduleError.unchangedTimeZone(index: index)
            }
            guard let toTimeZone = TimeZone(identifier: change.toTimeZoneIdentifier) else {
                throw ContestTimeZoneScheduleError.invalidTimeZone(
                    change.toTimeZoneIdentifier
                )
            }

            resolved.append(toTimeZone)
            expectedIdentifier = change.toTimeZoneIdentifier
        }

        self.initialTimeZoneIdentifier = initialTimeZoneIdentifier
        self.initialTimeZone = initialTimeZone
        self.changes = orderedChanges
        self.resolvedTimeZones = resolved
    }

    fileprivate struct Epoch {
        let timeZone: TimeZone
        let startsAt: Date?
        let endsAt: Date?
    }

    fileprivate func epoch(containing instant: Date) -> Epoch {
        var selectedIndex = 0
        for (index, change) in changes.enumerated() {
            if change.effectiveAt > instant { break }
            selectedIndex = index + 1
        }

        return Epoch(
            timeZone: resolvedTimeZones[selectedIndex],
            startsAt: selectedIndex == 0 ? nil : changes[selectedIndex - 1].effectiveAt,
            endsAt: selectedIndex < changes.count ? changes[selectedIndex].effectiveAt : nil
        )
    }
}

/// One hour of one metric from one source, ready to be sent.
///
/// This is the client's half of a `metric_snapshots` row. The four fields the
/// ledger keys on — metric, bucket start, provenance, and the contest it belongs
/// to — are all here except the contest, which the queue attaches.
public struct HourlyBucket: Sendable, Hashable {
    public let metric: ContestMetric
    /// Aligned to a whole hour in the applicable approved timezone epoch.
    public let bucketStart: Date
    public let provenance: MetricProvenance
    public let value: Double
    /// How many HealthKit samples went into this figure.
    public let sampleCount: Int
    /// Nil where the samples in this bucket disagreed about their source.
    public let sourceBundleIdentifier: String?
    public let deviceModel: String?

    public init(
        metric: ContestMetric,
        bucketStart: Date,
        provenance: MetricProvenance,
        value: Double,
        sampleCount: Int,
        sourceBundleIdentifier: String? = nil,
        deviceModel: String? = nil
    ) {
        self.metric = metric
        self.bucketStart = bucketStart
        self.provenance = provenance
        self.value = value
        self.sampleCount = sampleCount
        self.sourceBundleIdentifier = sourceBundleIdentifier
        self.deviceModel = deviceModel
    }
}

/// Turns HealthKit samples into the hourly buckets the ledger accepts.
///
/// ---------------------------------------------------------------------------
/// Why the hour is local rather than UTC
/// ---------------------------------------------------------------------------
/// A daily-cadence goal asks whether you hit 10,000 steps on *your* Tuesday, so
/// every bucket has to sit inside one local day. Not every zone is a whole
/// number of hours from UTC — India is +05:30, Nepal +05:45, Chatham +13:45 — so
/// a UTC-aligned hour straddles the local day boundary for roughly a fifth of
/// the world, and those participants would have part of Tuesday counted against
/// Monday. Aligning to the local hour makes that impossible by construction.
///
/// The base zone is frozen on the participant's roster row when they accepted,
/// not read from the device's current zone. An opponent-approved relocation is
/// an immutable, prospective schedule event. That preserves the zone governing
/// every old sample while allowing future hours to follow a genuine move
/// (DECISIONS.md D5).
///
/// ---------------------------------------------------------------------------
/// Straddling samples, and the approximation
/// ---------------------------------------------------------------------------
/// A HealthKit cumulative sample covers an interval, and an interval can cross
/// an hour boundary — a 90-minute walk is one sample spanning two or three
/// buckets. This prorates by overlap, which is exact when a sample lies inside
/// one bucket (the ordinary case: the pedometer records in short spans) and a
/// linear estimate when it does not.
///
/// The alternative is to let HealthKit bucket it, with an
/// `HKStatisticsCollectionQuery` anchored to local midnight on an hourly
/// interval. That is exact rather than estimated, and it was rejected because a
/// statistics collection reports sums without saying which source produced them
/// — and provenance is the point of this milestone. Running one statistics query
/// per source would recover it, at the cost of a query count that grows with
/// however many health apps the user happens to have installed.
public struct HourlyBucketer: Sendable {
    public let timeZoneSchedule: ContestTimeZoneSchedule

    /// The participant's originally accepted zone.
    public var timeZone: TimeZone { timeZoneSchedule.initialTimeZone }

    public init(timeZone: TimeZone) {
        self.timeZoneSchedule = ContestTimeZoneSchedule(initialTimeZone: timeZone)
    }

    public init(timeZoneSchedule: ContestTimeZoneSchedule) {
        self.timeZoneSchedule = timeZoneSchedule
    }

    private func calendar(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private func rawBucket(containing date: Date, in timeZone: TimeZone) -> DateInterval? {
        calendar(in: timeZone).dateInterval(of: .hour, for: date)
    }

    /// The local-hour bucket containing `date`, or nil if the calendar cannot
    /// place it or an approved timezone change cuts through that local hour.
    ///
    /// `Calendar.dateInterval(of: .hour,)` is what makes this correct across
    /// half-hour offsets and daylight-saving transitions: it truncates to the
    /// local hour rather than to a multiple of 3600 seconds since the epoch.
    public func bucket(containing date: Date) -> DateInterval? {
        let epoch = timeZoneSchedule.epoch(containing: date)
        guard let interval = rawBucket(containing: date, in: epoch.timeZone) else {
            return nil
        }
        if let startsAt = epoch.startsAt, interval.start < startsAt {
            return nil
        }
        if let endsAt = epoch.endsAt, interval.end > endsAt {
            return nil
        }
        return interval
    }

    /// Groups samples into buckets, dropping anything the ledger would refuse.
    ///
    /// - Parameters:
    ///   - samples: whatever HealthKit returned, in any order.
    ///   - window: the contest's window. A bucket must lie wholly inside it, the
    ///     same rule the server applies, so that a client does not spend a round
    ///     trip learning what it could have known.
    ///   - asOf: the current instant. Buckets that have not finished are dropped:
    ///     an hour still in progress has no final figure, and the server refuses
    ///     one outright because accepting it would let a client bank a winning
    ///     scoreline for the rest of an open contest in advance.
    public func buckets(
        from samples: [some HealthSampleDescriptor],
        window: DateInterval,
        asOf: Date
    ) -> [HourlyBucket] {
        var accumulator: [Key: Accumulated] = [:]

        for sample in samples {
            guard sample.value.isFinite, sample.value >= 0, sample.end >= sample.start else {
                // A negative or non-finite quantity is not a measurement, and an
                // interval that ends before it starts is not an interval. Both
                // are dropped rather than clamped: a client that quietly repairs
                // nonsense sends nonsense that looks fine.
                continue
            }

            let provenance = ProvenanceClassifier.classify(sample)

            for slice in slices(of: sample) {
                // Wholly inside the window, and finished. Both mirror a server
                // rule; see `app.prepare_metric_snapshot()`.
                guard slice.interval.start >= window.start,
                      slice.interval.end <= window.end,
                      slice.interval.end <= asOf
                else { continue }

                let key = Key(
                    metric: sample.metric,
                    bucketStart: slice.interval.start,
                    provenance: provenance
                )

                accumulator[key, default: Accumulated()].add(
                    value: slice.value,
                    bundleIdentifier: sample.sourceBundleIdentifier,
                    deviceModel: sample.deviceModel
                )
            }
        }

        return accumulator
            .map { key, accumulated in
                HourlyBucket(
                    metric: key.metric,
                    bucketStart: key.bucketStart,
                    provenance: key.provenance,
                    // The ledger stores numeric(12,2). Rounding here keeps what
                    // the client signed and what lands in the row in agreement.
                    value: (accumulated.value * 100).rounded() / 100,
                    sampleCount: accumulated.sampleCount,
                    sourceBundleIdentifier: accumulated.agreedBundleIdentifier,
                    deviceModel: accumulated.agreedDeviceModel
                )
            }
            // Deterministic order, so a batch's bytes depend only on its
            // contents. The assertion signs those bytes, and a dictionary's
            // iteration order is not something to sign.
            .sorted { left, right in
                if left.bucketStart != right.bucketStart {
                    return left.bucketStart < right.bucketStart
                }
                if left.metric != right.metric {
                    return left.metric.rawValue < right.metric.rawValue
                }
                return left.provenance.rawValue < right.provenance.rawValue
            }
    }

    // MARK: - Splitting

    private struct Slice {
        let interval: DateInterval
        let value: Double
    }

    /// Splits a sample across the valid local hours it covers, prorating by
    /// overlap. A timezone transition can cut two differently aligned hours;
    /// those partial pieces are dropped rather than moved into either day.
    private func slices(of sample: some HealthSampleDescriptor) -> [Slice] {
        let duration = sample.end.timeIntervalSince(sample.start)

        // An instantaneous sample belongs entirely to the hour it happened in.
        // HealthKit reports plenty of these, and dividing by a zero duration to
        // prorate would produce a NaN that then poisons a whole bucket.
        guard duration > 0 else {
            guard let interval = bucket(containing: sample.start) else { return [] }
            return [Slice(interval: interval, value: sample.value)]
        }

        var slices: [Slice] = []
        var cursor = sample.start

        // Bounded rather than `while true`. A sample longer than a fortnight is
        // not a walk, and an unbounded loop over a calendar is one clock bug
        // away from never ending.
        let maximumIterations = 24 * 15 + timeZoneSchedule.changes.count * 2
        var iterations = 0

        while cursor < sample.end, iterations < maximumIterations {
            iterations += 1
            let epoch = timeZoneSchedule.epoch(containing: cursor)
            guard let rawInterval = rawBucket(containing: cursor, in: epoch.timeZone) else {
                break
            }

            let stepEnd = min(rawInterval.end, epoch.endsAt ?? sample.end, sample.end)
            guard stepEnd > cursor else { break }

            let startsInsideEpoch = epoch.startsAt.map { rawInterval.start >= $0 } ?? true
            let endsInsideEpoch = epoch.endsAt.map { rawInterval.end <= $0 } ?? true
            let isWholeEpochBucket = startsInsideEpoch && endsInsideEpoch

            let overlapStart = max(rawInterval.start, sample.start)
            let overlapEnd = min(rawInterval.end, sample.end)
            let overlap = overlapEnd.timeIntervalSince(overlapStart)

            if isWholeEpochBucket, overlap > 0 {
                slices.append(
                    Slice(
                        interval: rawInterval,
                        value: sample.value * (overlap / duration)
                    )
                )
            }

            cursor = stepEnd
        }

        return slices
    }

    // MARK: - Accumulation

    private struct Key: Hashable {
        let metric: ContestMetric
        let bucketStart: Date
        let provenance: MetricProvenance
    }

    /// One bucket under construction.
    ///
    /// The two source fields collapse to nil when the samples disagree, which
    /// happens when two health apps both wrote to the same hour. The ledger
    /// keys on provenance rather than on bundle identifier, so those samples
    /// share a row and there is no honest single answer for whose it was —
    /// naming one of them would be a guess presented as a fact.
    private struct Accumulated {
        var value: Double = 0
        var sampleCount: Int = 0
        private var bundleIdentifiers: Set<String> = []
        private var deviceModels: Set<String> = []

        mutating func add(value: Double, bundleIdentifier: String?, deviceModel: String?) {
            self.value += value
            sampleCount += 1
            if let bundleIdentifier { bundleIdentifiers.insert(bundleIdentifier) }
            if let deviceModel { deviceModels.insert(deviceModel) }
        }

        var agreedBundleIdentifier: String? {
            bundleIdentifiers.count == 1 ? bundleIdentifiers.first : nil
        }

        var agreedDeviceModel: String? {
            deviceModels.count == 1 ? deviceModels.first : nil
        }
    }
}
