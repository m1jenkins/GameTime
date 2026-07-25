import Foundation
import Testing

@testable import GameTimeCore

@Suite("Ingest queue")
struct IngestQueueTests {
    static let contest = UUID(uuidString: "a0000001-0000-0000-0000-000000000001")!
    static let otherContest = UUID(uuidString: "a0000002-0000-0000-0000-000000000002")!
    static let epoch = Date(timeIntervalSince1970: 1_785_888_000)

    static func batchId(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "b%07d-0000-0000-0000-000000000000", n))!
    }

    static func bucket(
        hour: Int,
        metric: ContestMetric = .steps,
        value: Double = 500,
        provenance: MetricProvenance = .device
    ) -> HourlyBucket {
        HourlyBucket(
            metric: metric,
            bucketStart: epoch.addingTimeInterval(Double(hour) * 3600),
            provenance: provenance,
            value: value,
            sampleCount: 4
        )
    }

    @Test("a batch keeps its id, which is what makes a retry safe")
    func idIsStableAcrossRetries() {
        // `record_metric_batch()` checks the client batch id *before* it consumes
        // an assertion counter, so a request that timed out after the server
        // committed can be sent again and comes back as a replay. That only works
        // if the id does not change between attempts.
        var queue = IngestQueue()
        let batch = queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )

        #expect(batch?.clientBatchId == Self.batchId(1))

        queue.recordAttempt(Self.batchId(1))
        queue.recordAttempt(Self.batchId(1))

        #expect(queue.next?.clientBatchId == Self.batchId(1))
        #expect(queue.next?.attempts == 2)
        #expect(queue.count == 1)
    }

    @Test("re-enqueuing an id already queued is a no-op")
    func reEnqueueIsIdempotent() {
        // The app persists ids across launches, so "did I already queue this?" is
        // the ordinary shape of the question rather than a defensive check.
        var queue = IngestQueue()
        queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )
        queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0, value: 9999)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )

        #expect(queue.count == 1)
        #expect(queue.next?.buckets.first?.value == 500, "the first content wins")
    }

    @Test("an empty batch is never queued")
    func emptyBatchIsRefused() {
        // record_metric_batch() refuses one, and a round trip to be told so is a
        // round trip wasted.
        var queue = IngestQueue()
        let batch = queue.enqueue(
            contestId: Self.contest,
            buckets: [],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )

        #expect(batch == nil)
        #expect(queue.isEmpty)
    }

    @Test("sending is oldest first")
    func fifoOrder() {
        var queue = IngestQueue()
        for hour in 0..<3 {
            queue.enqueue(
                contestId: Self.contest,
                buckets: [Self.bucket(hour: hour)],
                observedAt: Self.epoch,
                clientBatchId: Self.batchId(hour + 1)
            )
        }

        #expect(queue.pending.map(\.clientBatchId) == (1...3).map(Self.batchId))
        #expect(queue.next?.clientBatchId == Self.batchId(1))
    }

    @Test("acknowledging removes exactly one batch")
    func acknowledgeRemovesOne() {
        var queue = IngestQueue()
        for n in 1...3 {
            queue.enqueue(
                contestId: Self.contest,
                buckets: [Self.bucket(hour: n)],
                observedAt: Self.epoch,
                clientBatchId: Self.batchId(n)
            )
        }

        queue.acknowledge(Self.batchId(2))

        #expect(queue.pending.map(\.clientBatchId) == [Self.batchId(1), Self.batchId(3)])
    }

    @Test("acknowledging an unknown id changes nothing")
    func acknowledgeUnknownIsSafe() {
        // Which is what a response arriving twice looks like, and it must not
        // throw away the batch that happens to be at the head.
        var queue = IngestQueue()
        queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )

        queue.acknowledge(Self.batchId(99))
        queue.acknowledge(Self.batchId(1))
        queue.acknowledge(Self.batchId(1))

        #expect(queue.isEmpty)
    }

    @Test("abandoning removes a batch the server will never accept")
    func abandonRemoves() {
        var queue = IngestQueue()
        queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )

        queue.abandon(Self.batchId(1))
        #expect(queue.isEmpty)
    }

    @Test("capacity is bounded, and drops the oldest while counting the loss")
    func capacityDropsOldest() {
        // The queue is a transmission buffer, not the record — HealthKit still
        // holds the samples and metric_snapshots is the ledger — so dropping and
        // re-reading is recoverable, whereas an unbounded queue on a phone that
        // has been offline for a month ends in a crash.
        var queue = IngestQueue(capacity: 3)
        for n in 1...5 {
            queue.enqueue(
                contestId: Self.contest,
                buckets: [Self.bucket(hour: n)],
                observedAt: Self.epoch,
                clientBatchId: Self.batchId(n)
            )
        }

        #expect(queue.count == 3)
        #expect(queue.pending.map(\.clientBatchId) == (3...5).map(Self.batchId))
        // Surfaced rather than silent: a bound nobody can observe is a bound
        // nobody knows was hit.
        #expect(queue.droppedForCapacity == 2)
    }

    @Test("batches for different contests coexist")
    func contestsCoexist() {
        // A batch is scoped to one contest, because the window and status checks
        // are properties of the contest — so a participant in two contests has
        // two batches in flight, not one.
        var queue = IngestQueue()
        queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )
        queue.enqueue(
            contestId: Self.otherContest,
            buckets: [Self.bucket(hour: 0)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(2)
        )

        #expect(queue.count == 2)
        #expect(Set(queue.pending.map(\.contestId)) == [Self.contest, Self.otherContest])
    }

    @Test("the same hour may be queued twice, because the server decides")
    func supersedingObservationsBothQueue() {
        // Deliberately no client-side merging. The ledger refuses a downward
        // revision and takes the largest figure per source, so 800 then 950 lands
        // on 950 either way. A client that merged would be reimplementing that
        // rule, and the failure mode of the two disagreeing is a participant's
        // evidence quietly going missing.
        var queue = IngestQueue()
        queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0, value: 800)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )
        queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0, value: 950)],
            observedAt: Self.epoch.addingTimeInterval(3600),
            clientBatchId: Self.batchId(2)
        )

        #expect(queue.count == 2)
        #expect(queue.pending.flatMap(\.buckets).map(\.value) == [800, 950])
    }

    @Test("the read cursor comes from the queue, per metric")
    func latestQueuedBucketPerMetric() {
        // Taken from the queue rather than from a separate cursor so the two
        // cannot fall out of step: a cursor advanced before a batch was
        // acknowledged would skip the hours inside it.
        var queue = IngestQueue()
        queue.enqueue(
            contestId: Self.contest,
            buckets: [
                Self.bucket(hour: 1, metric: .steps),
                Self.bucket(hour: 5, metric: .steps),
                Self.bucket(hour: 2, metric: .distanceMeters),
            ],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )

        #expect(
            queue.latestQueuedBucketStart(for: .steps)
                == Self.epoch.addingTimeInterval(5 * 3600)
        )
        #expect(
            queue.latestQueuedBucketStart(for: .distanceMeters)
                == Self.epoch.addingTimeInterval(2 * 3600)
        )
        #expect(queue.latestQueuedBucketStart(for: .activeEnergyKcal) == nil)
    }

    @Test("a queue value type carries its own state")
    func queueIsAValueType() {
        // A struct rather than an actor, which is what lets the app hold it
        // inside whatever isolation it already has instead of introducing a
        // second one. Copies are independent, so a snapshot taken for a retry
        // cannot be mutated out from under the caller.
        var queue = IngestQueue()
        queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )

        var copy = queue
        copy.acknowledge(Self.batchId(1))

        #expect(queue.count == 1)
        #expect(copy.isEmpty)
    }

    @Test("a queue crosses an isolation boundary")
    func queueIsSendable() async {
        var queue = IngestQueue()
        queue.enqueue(
            contestId: Self.contest,
            buckets: [Self.bucket(hour: 0)],
            observedAt: Self.epoch,
            clientBatchId: Self.batchId(1)
        )

        let count = await Task.detached { [queue] in queue.count }.value
        #expect(count == 1)
    }
}
