import Foundation

/// One hour of one metric from one source, ready to be sent.
///
/// This is the client's half of a `metric_snapshots` row. The four fields the
/// ledger keys on — metric, bucket start, provenance, and the contest it belongs
/// to — are all here except the contest, which the queue attaches.
public struct HourlyBucket: Sendable, Hashable {
    public let metric: ContestMetric
    /// Aligned to a whole hour in the participant's frozen timezone.
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
/// The zone is the one frozen on the participant's roster row when they
/// accepted, not the device's current zone. A live zone would let somebody fly
/// their day boundary backwards to reopen a day they had already lost, which is
/// exactly what freezing it prevents (DECISIONS.md D5).
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
    /// The participant's frozen zone.
    public let timeZone: TimeZone

    private let calendar: Calendar

    public init(timeZone: TimeZone) {
        self.timeZone = timeZone
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.calendar = calendar
    }

    /// The local-hour bucket containing `date`, or nil if the calendar cannot
    /// place it.
    ///
    /// `Calendar.dateInterval(of: .hour,)` is what makes this correct across
    /// half-hour offsets and daylight-saving transitions: it truncates to the
    /// local hour rather than to a multiple of 3600 seconds since the epoch.
    public func bucket(containing date: Date) -> DateInterval? {
        calendar.dateInterval(of: .hour, for: date)
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
                guard let interval = bucket(containing: slice.start) else { continue }

                // Wholly inside the window, and finished. Both mirror a server
                // rule; see `app.prepare_metric_snapshot()`.
                guard interval.start >= window.start,
                      interval.end <= window.end,
                      interval.end <= asOf
                else { continue }

                let key = Key(
                    metric: sample.metric,
                    bucketStart: interval.start,
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
        let start: Date
        let value: Double
    }

    /// Splits a sample across the local hours it covers, prorating by overlap.
    private func slices(of sample: some HealthSampleDescriptor) -> [Slice] {
        let duration = sample.end.timeIntervalSince(sample.start)

        // An instantaneous sample belongs entirely to the hour it happened in.
        // HealthKit reports plenty of these, and dividing by a zero duration to
        // prorate would produce a NaN that then poisons a whole bucket.
        guard duration > 0 else {
            return [Slice(start: sample.start, value: sample.value)]
        }

        guard let first = bucket(containing: sample.start) else {
            return [Slice(start: sample.start, value: sample.value)]
        }

        // The common case, and worth short-circuiting: no arithmetic, so no
        // rounding drift on the overwhelming majority of samples.
        if sample.end <= first.end {
            return [Slice(start: sample.start, value: sample.value)]
        }

        var slices: [Slice] = []
        var cursor = first

        // Bounded rather than `while true`. A sample longer than a fortnight is
        // not a walk, and an unbounded loop over a calendar is one clock bug
        // away from never ending.
        let maximumBuckets = 24 * 15

        while slices.count < maximumBuckets {
            let overlapStart = max(cursor.start, sample.start)
            let overlapEnd = min(cursor.end, sample.end)
            let overlap = overlapEnd.timeIntervalSince(overlapStart)

            if overlap > 0 {
                slices.append(
                    Slice(start: overlapStart, value: sample.value * (overlap / duration))
                )
            }

            guard cursor.end < sample.end,
                  let next = bucket(containing: cursor.end)
            else { break }

            // Belt and braces against a calendar that fails to advance, which
            // would otherwise be an infinite loop rather than a wrong answer.
            guard next.start > cursor.start else { break }
            cursor = next
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
