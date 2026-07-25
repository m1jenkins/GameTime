import Foundation

/// One batch waiting to be sent, or waiting to be acknowledged.
///
/// `clientBatchId` is the idempotency key. It is generated once, when the batch
/// is first built, and it survives every retry — which is the whole point:
/// `record_metric_batch()` checks it before it consumes an assertion counter, so
/// a request that timed out after the server committed it can be sent again and
/// comes back as a replay rather than an error.
public struct PendingBatch: Sendable, Hashable, Identifiable {
    public var id: UUID { clientBatchId }

    public let clientBatchId: UUID
    public let contestId: UUID
    /// The client's clock when it read HealthKit. The server records its own
    /// clock alongside, so the gap between them is visible.
    public let observedAt: Date
    public let buckets: [HourlyBucket]
    /// How many times sending this has been attempted.
    public var attempts: Int

    init(clientBatchId: UUID, contestId: UUID, observedAt: Date, buckets: [HourlyBucket]) {
        self.clientBatchId = clientBatchId
        self.contestId = contestId
        self.observedAt = observedAt
        self.buckets = buckets
        self.attempts = 0
    }
}

/// The offline queue between HealthKit and the ingest endpoint.
///
/// A phone is offline in tunnels, on planes, and whenever iOS decides the app
/// has had enough background time, so evidence has to survive not being sent.
/// This is that buffer, and it is deliberately small.
///
/// ---------------------------------------------------------------------------
/// What it does not do, and why
/// ---------------------------------------------------------------------------
/// It does not deduplicate across batches, and it does not merge a later reading
/// of an hour into an earlier queued one. Both are tempting — two batches
/// carrying the same hour is redundant traffic — and both are the server's job
/// already: the ledger refuses a downward revision and takes the largest figure
/// per source, so sending 800 and then 950 for the same hour lands on 950 in
/// either order, and sending 800 twice lands on 800. A client that merged would
/// be reimplementing that rule, and the failure mode of the two disagreeing is a
/// participant's evidence quietly going missing.
///
/// It is also not the record. `metric_snapshots` is the record and HealthKit is
/// the source; this holds transmissions. That is what makes the capacity bound
/// below safe rather than lossy — a dropped batch can be rebuilt by reading
/// HealthKit again, whereas an unbounded queue on a phone that has been offline
/// for a month is a memory leak that ends in a crash.
public struct IngestQueue: Sendable {
    /// How many batches may wait at once.
    ///
    /// A batch is up to 2,000 observations, and a day of four metrics from two
    /// sources is about 200, so this is several weeks of backlog. Past that, the
    /// oldest is dropped and re-read rather than held forever.
    public static let defaultCapacity = 64

    public let capacity: Int

    private var batches: [PendingBatch] = []

    /// Batches dropped for want of capacity, since the queue was created.
    ///
    /// Surfaced rather than silent because "we stopped keeping your evidence" is
    /// something the client should be able to notice and report, and a counter
    /// nobody can read is a bound nobody knows was hit.
    public private(set) var droppedForCapacity = 0

    public init(capacity: Int = IngestQueue.defaultCapacity) {
        precondition(capacity > 0, "a queue that cannot hold anything is not a queue")
        self.capacity = capacity
    }

    /// Everything waiting, oldest first.
    public var pending: [PendingBatch] { batches }

    public var isEmpty: Bool { batches.isEmpty }

    public var count: Int { batches.count }

    /// The next batch to send. Sending is FIFO so that the ledger sees a
    /// participant's hours in roughly the order they happened, which keeps the
    /// reporting lag on each row meaningful.
    public var next: PendingBatch? { batches.first }

    /// Queues buckets for one contest.
    ///
    /// Returns nil for an empty set rather than queueing a batch with nothing in
    /// it: `record_metric_batch()` refuses one, and a round trip to be told so is
    /// a round trip wasted.
    ///
    /// `clientBatchId` is a parameter rather than generated here so the suites
    /// can be deterministic, and so the app can persist the id alongside the
    /// batch and keep it stable across a relaunch — which is exactly the case
    /// idempotency exists for.
    @discardableResult
    public mutating func enqueue(
        contestId: UUID,
        buckets: [HourlyBucket],
        observedAt: Date,
        clientBatchId: UUID
    ) -> PendingBatch? {
        guard !buckets.isEmpty else { return nil }

        // Re-enqueueing an id already queued is a no-op rather than a duplicate.
        // The app persists ids across launches, so this is the ordinary shape of
        // "did I already queue this?" rather than a defensive check.
        if let existing = batches.first(where: { $0.clientBatchId == clientBatchId }) {
            return existing
        }

        let batch = PendingBatch(
            clientBatchId: clientBatchId,
            contestId: contestId,
            observedAt: observedAt,
            buckets: buckets
        )
        batches.append(batch)

        while batches.count > capacity {
            batches.removeFirst()
            droppedForCapacity += 1
        }

        return batch
    }

    /// Records that sending was attempted, whatever the outcome.
    ///
    /// Kept separate from acknowledgement so a caller can tell "sent and refused"
    /// from "never sent". A batch the server rejects on a rule — an hour outside
    /// the window, say — will be rejected every time, and a client with no
    /// attempt count has no way to stop trying.
    public mutating func recordAttempt(_ clientBatchId: UUID) {
        guard let index = batches.firstIndex(where: { $0.clientBatchId == clientBatchId })
        else { return }
        batches[index].attempts += 1
    }

    /// Removes a batch the server has accepted.
    ///
    /// A replay counts as accepted: `replayed: true` means the evidence is
    /// already in the ledger, which is the outcome the client wanted.
    /// Acknowledging an id that is not queued is a no-op, because that is what a
    /// response arriving twice looks like.
    public mutating func acknowledge(_ clientBatchId: UUID) {
        batches.removeAll { $0.clientBatchId == clientBatchId }
    }

    /// Drops a batch the server will never accept.
    ///
    /// Distinct from `acknowledge` only in intent, and the distinction is worth a
    /// method name: one means "this is in the ledger" and the other means "this
    /// never will be". Conflating them makes an abandoned batch indistinguishable
    /// from a stored one in any log written from this queue.
    public mutating func abandon(_ clientBatchId: UUID) {
        batches.removeAll { $0.clientBatchId == clientBatchId }
    }

    /// The latest bucket in the queue, per metric.
    ///
    /// The client reads HealthKit forward from the last hour it has already
    /// handled. Taking that from the queue rather than from a separate cursor
    /// means the two cannot fall out of step — a cursor advanced before a batch
    /// was acknowledged would skip the hours in it.
    public func latestQueuedBucketStart(for metric: ContestMetric) -> Date? {
        batches
            .flatMap(\.buckets)
            .filter { $0.metric == metric }
            .map(\.bucketStart)
            .max()
    }
}
