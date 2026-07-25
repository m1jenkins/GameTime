import Foundation

/// One byte-exact check-in request waiting to be sent or acknowledged.
///
/// This value is `Codable` because a geofence visit cannot be reconstructed
/// after the app relaunches. The app target persists these values and restores
/// them through `CheckInQueue.init(capacity:restoring:)`.
public struct PendingCheckIn: Sendable, Hashable, Identifiable, Codable {
    public var id: UUID { clientCheckInId }

    public let clientCheckInId: UUID
    /// The exact bytes App Attest signs and the HTTP request must transmit.
    public let body: Data
    public var attempts: Int

    public init(
        clientCheckInId: UUID,
        body: Data,
        attempts: Int = 0
    ) {
        precondition(attempts >= 0, "an attempt count cannot be negative")
        self.clientCheckInId = clientCheckInId
        self.body = body
        self.attempts = attempts
    }
}

/// The result of attempting to put one encoded request in the queue.
public enum CheckInEnqueueResult: Sendable, Hashable {
    case enqueued
    case alreadyQueued
    /// The id is already pending with different signed bytes.
    case conflictingPayload
    /// No existing evidence was discarded; the caller must persist or retry
    /// this new request after making room.
    case capacityReached
}

/// A persisted queue snapshot is rejected rather than silently repaired.
public enum CheckInQueueRestorationError: Error, Sendable, Hashable {
    case capacityExceeded
    case duplicateId(UUID)
    case negativeAttempts(UUID)
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

    /// New requests refused after the queue reached its explicit bound.
    ///
    /// Check-in evidence comes from transient Core Location observations and
    /// cannot be rebuilt like a HealthKit query, so the queue never evicts an
    /// older request to make room.
    public private(set) var refusedForCapacity = 0

    public init(capacity: Int = CheckInQueue.defaultCapacity) {
        precondition(capacity > 0, "a queue that cannot hold anything is not a queue")
        self.capacity = capacity
    }

    /// Restores byte-exact requests previously persisted by the app target.
    ///
    /// Order, ids, bodies, and attempt counts are all preserved. Corrupt or
    /// over-capacity state fails loudly instead of dropping physical-world
    /// evidence or choosing one of two conflicting payloads.
    public init(
        capacity: Int = CheckInQueue.defaultCapacity,
        restoring persisted: [PendingCheckIn]
    ) throws {
        precondition(capacity > 0, "a queue that cannot hold anything is not a queue")
        guard persisted.count <= capacity else {
            throw CheckInQueueRestorationError.capacityExceeded
        }

        var ids: Set<UUID> = []
        for request in persisted {
            guard request.attempts >= 0 else {
                throw CheckInQueueRestorationError.negativeAttempts(
                    request.clientCheckInId
                )
            }
            guard ids.insert(request.clientCheckInId).inserted else {
                throw CheckInQueueRestorationError.duplicateId(
                    request.clientCheckInId
                )
            }
        }

        self.capacity = capacity
        self.checkIns = persisted
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

        guard checkIns.count < capacity else {
            refusedForCapacity += 1
            return .capacityReached
        }

        checkIns.append(
            PendingCheckIn(
                clientCheckInId: request.clientCheckInId,
                body: request.body
            )
        )
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
