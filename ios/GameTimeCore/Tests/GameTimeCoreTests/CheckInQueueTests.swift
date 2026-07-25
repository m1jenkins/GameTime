import Foundation
import Testing

@testable import GameTimeCore

@Suite("Check-in queue")
struct CheckInQueueTests {
    static func checkInId(_ n: Int) -> UUID {
        UUID(uuidString: String(
            format: "c%07d-0000-0000-0000-000000000000",
            n
        ))!
    }

    static func request(
        id: UUID,
        latitude: Double = 41
    ) throws -> EncodedCheckInRequest {
        try EncodedCheckInRequest(
            payload: AttestedCheckInPayload(
                contestId: GeofenceCheckInTests.contestId,
                geofenceId: GeofenceCheckInTests.geofenceId,
                clientCheckInId: id,
                locations: [
                    GeofenceCheckInTests.location(
                        second: 0,
                        latitude: latitude
                    ),
                    GeofenceCheckInTests.location(
                        second: 60,
                        latitude: latitude
                    ),
                ],
                workout: GeofenceCheckInTests.workout()
            )
        )
    }

    @Test("a retry reuses both id and exact signed body bytes")
    func retryByteIdentity() throws {
        let request = try Self.request(id: Self.checkInId(1))
        var queue = CheckInQueue()

        #expect(queue.enqueue(request) == .enqueued)
        let firstBody = queue.next?.body
        queue.recordAttempt(request.clientCheckInId)
        queue.recordAttempt(request.clientCheckInId)

        #expect(queue.next?.clientCheckInId == request.clientCheckInId)
        #expect(queue.next?.body == request.body)
        #expect(queue.next?.body == firstBody)
        #expect(queue.next?.attempts == 2)
    }

    @Test("the same id and bytes are an idempotent local retry")
    func identicalDuplicateIsSafe() throws {
        let request = try Self.request(id: Self.checkInId(1))
        var queue = CheckInQueue()

        #expect(queue.enqueue(request) == .enqueued)
        #expect(queue.enqueue(request) == .alreadyQueued)
        #expect(queue.count == 1)
        #expect(queue.next?.body == request.body)
    }

    @Test("the same id with different bytes returns a loud conflict")
    func conflictingDuplicateIsRefused() throws {
        let id = Self.checkInId(1)
        let first = try Self.request(id: id, latitude: 41)
        let altered = try Self.request(id: id, latitude: 41.000_1)
        #expect(first.body != altered.body)

        var queue = CheckInQueue()
        #expect(queue.enqueue(first) == .enqueued)
        #expect(queue.enqueue(altered) == .conflictingPayload)

        #expect(queue.count == 1)
        #expect(queue.next?.body == first.body)
    }

    @Test("sending is FIFO")
    func fifoOrder() throws {
        var queue = CheckInQueue()
        for n in 1...3 {
            queue.enqueue(try Self.request(id: Self.checkInId(n)))
        }

        #expect(queue.pending.map(\.clientCheckInId) == (1...3).map(Self.checkInId))
        #expect(queue.next?.clientCheckInId == Self.checkInId(1))
    }

    @Test("a replay acknowledgement removes exactly its request")
    func replayAcknowledgesById() throws {
        var queue = CheckInQueue()
        for n in 1...3 {
            queue.enqueue(try Self.request(id: Self.checkInId(n)))
        }

        // HTTP 200 with `replayed: true` means the evidence is already stored,
        // which is the same queue outcome as a first-write 201.
        queue.acknowledge(Self.checkInId(2))

        #expect(queue.pending.map(\.clientCheckInId) == [
            Self.checkInId(1), Self.checkInId(3),
        ])
    }

    @Test("unknown duplicate responses change nothing")
    func unknownAcknowledgementIsSafe() throws {
        var queue = CheckInQueue()
        queue.enqueue(try Self.request(id: Self.checkInId(1)))

        queue.acknowledge(Self.checkInId(99))
        #expect(queue.count == 1)
        queue.acknowledge(Self.checkInId(1))
        queue.acknowledge(Self.checkInId(1))
        #expect(queue.isEmpty)
    }

    @Test("permanent refusal can be abandoned explicitly")
    func abandonRemovesRequest() throws {
        var queue = CheckInQueue()
        queue.enqueue(try Self.request(id: Self.checkInId(1)))

        queue.abandon(Self.checkInId(1))
        #expect(queue.isEmpty)
    }

    @Test("capacity drops oldest and surfaces the count")
    func capacityIsBounded() throws {
        var queue = CheckInQueue(capacity: 3)
        for n in 1...5 {
            queue.enqueue(try Self.request(id: Self.checkInId(n)))
        }

        #expect(queue.count == 3)
        #expect(queue.pending.map(\.clientCheckInId) == (3...5).map(Self.checkInId))
        #expect(queue.droppedForCapacity == 2)
    }

    @Test("conflicts do not consume capacity or evict evidence")
    func conflictDoesNotMutateQueue() throws {
        let id = Self.checkInId(1)
        var queue = CheckInQueue(capacity: 1)
        queue.enqueue(try Self.request(id: id))

        #expect(
            queue.enqueue(try Self.request(id: id, latitude: 41.000_1))
                == .conflictingPayload
        )
        #expect(queue.count == 1)
        #expect(queue.droppedForCapacity == 0)
    }

    @Test("the queue is a Sendable value type")
    func queueCrossesIsolationAndCopiesIndependently() async throws {
        var queue = CheckInQueue()
        queue.enqueue(try Self.request(id: Self.checkInId(1)))

        var copy = queue
        copy.acknowledge(Self.checkInId(1))
        let count = await Task.detached { [queue] in
            queue.count
        }.value

        #expect(count == 1)
        #expect(queue.count == 1)
        #expect(copy.isEmpty)
    }
}
