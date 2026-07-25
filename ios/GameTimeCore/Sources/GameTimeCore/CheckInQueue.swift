import Foundation

/// One byte-exact check-in request waiting to be sent or acknowledged.
public struct PendingCheckIn: Sendable, Hashable, Identifiable {
    public var id: UUID { clientCheckInId }

    public let clientCheckInId: UUID
    /// The exact bytes App Attest signs and the HTTP request must transmit.
    public let body: Data
    public var attempts: Int

    init(clientCheckInId: UUID, body: Data) {
        self.clientCheckInId = clientCheckInId
        self.body = body
        self.attempts = 0
    }
}

/// The result of attempting to put one encoded request in the queue.
public enum CheckInEnqueueResult: Sendable, Hashable {
    case enqueued
    case alreadyQueued
    /// The id is already pending with different signed bytes.
    case conflictingPayload
}

/// A bounded FIFO transmission queue for attested venue check-ins.
///
/// The caller generates `clientCheckInId` before encoding. The queue never
/// generates or changes it, and it stores the encoded body rather than a model
/// it would have to re-encode for a retry. This is what makes both database
/// idempotency and App Attest byte identity survive a timeout.
public struct CheckInQueue: Sendable {
    public static let defaultCapacity = 64

    public let capacity: Int
    private var checkIns: [PendingCheckIn] = []

    /// Old requests evicted after the queue reached its explicit bound.
    public private(set) var droppedForCapacity = 0

    public init(capacity: Int = CheckInQueue.defaultCapacity) {
        precondition(capacity > 0, "a queue that cannot hold anything is not a queue")
        self.capacity = capacity
    }

    public var pending: [PendingCheckIn] { checkIns }
    public var next: PendingCheckIn? { checkIns.first }
    public var count: Int { checkIns.count }
    public var isEmpty: Bool { checkIns.isEmpty }

    /// Queues an already encoded body.
    ///
    /// Repeating an id is idempotent only when the bytes agree. Returning an
    /// explicit conflict prevents a reused id from silently dropping a distinct
    /// physical-world claim.
    @discardableResult
    public mutating func enqueue(
        _ request: EncodedCheckInRequest
    ) -> CheckInEnqueueResult {
        if let existing = checkIns.first(where: {
            $0.clientCheckInId == request.clientCheckInId
        }) {
            return existing.body == request.body ? .alreadyQueued : .conflictingPayload
        }

        checkIns.append(
            PendingCheckIn(
                clientCheckInId: request.clientCheckInId,
                body: request.body
            )
        )
        while checkIns.count > capacity {
            checkIns.removeFirst()
            droppedForCapacity += 1
        }
        return .enqueued
    }

    public mutating func recordAttempt(_ clientCheckInId: UUID) {
        guard let index = checkIns.firstIndex(where: {
            $0.clientCheckInId == clientCheckInId
        }) else {
            return
        }
        checkIns[index].attempts += 1
    }

    /// Removes a request accepted with either `201` or replay response `200`.
    public mutating func acknowledge(_ clientCheckInId: UUID) {
        checkIns.removeAll { $0.clientCheckInId == clientCheckInId }
    }

    /// Removes a request the server has permanently refused.
    public mutating func abandon(_ clientCheckInId: UUID) {
        checkIns.removeAll { $0.clientCheckInId == clientCheckInId }
    }
}
