import Foundation

public enum ChallengeHealthReadCompletion: Equatable, Sendable {
    case applied(ChallengeHealthEvaluation)
    case unavailable(ChallengeHealthStoreFailure)
    case discarded
    case notStarted(ChallengeHealthReadiness)
}

/// An in-memory async fence. There is no store singleton, authorization call,
/// persistence, timer, observer or background task here.
public actor ChallengeHealthReadSession {
    public private(set) var readiness: ChallengeHealthReadiness = .notConnected
    private var generation: UInt64 = 0
    private var attempt: UInt64 = 0
    private var request: ChallengeHealthReadRequest?
    private var previous: ChallengeHealthSnapshot?
    private var supported = true
    private var sourceRequestCompleted = false

    public init() {}

    /// Every replacement invalidates in-flight work, including switching away
    /// and back to an equal account/terms binding. Old raw history is forgotten.
    public func configure(request: ChallengeHealthReadRequest?, supported: Bool,
                          sourceRequestCompleted: Bool) throws {
        let next = generation.addingReportingOverflow(1)
        guard !next.overflow else { throw ChallengeHealthContractError.generationExhausted }
        generation = next.partialValue
        attempt = 0
        self.request = request
        self.supported = supported
        self.sourceRequestCompleted = sourceRequestCompleted
        previous = nil
        readiness = !supported ? .unsupported : sourceRequestCompleted && request != nil ? .noEligibleDataYet : .notConnected
    }

    public func refresh(store: any ChallengeHealthStore,
                        adapter: any ChallengeHealthAdapter) async throws -> ChallengeHealthReadCompletion {
        guard supported, sourceRequestCompleted, let request else { return .notStarted(readiness) }
        guard request.binding.metric == adapter.metric else { throw ChallengeHealthContractError.bindingMismatch }
        guard !Task.isCancelled else { return .discarded }
        let next = attempt.addingReportingOverflow(1)
        guard !next.overflow else { throw ChallengeHealthContractError.generationExhausted }
        attempt = next.partialValue
        let ticket = (generation, attempt)
        readiness = .checking
        let outcome = await store.read(request)
        guard ticket.0 == generation, ticket.1 == attempt, self.request == request else { return .discarded }
        guard !Task.isCancelled else {
            readiness = .temporarilyUnavailable
            return .discarded
        }
        switch outcome {
        case .unavailable(let failure):
            readiness = .temporarilyUnavailable
            return .unavailable(failure)
        case .snapshot(let snapshot):
            guard snapshot.request == request else {
                readiness = .staleOrIncomplete
                return .discarded
            }
            let evaluation = adapter.evaluate(snapshot, replacing: previous)
            readiness = evaluation.readiness
            // Invalid/out-of-order responses cannot replace our comparison baseline.
            if !evaluation.issues.contains(.invalidSnapshot) && !evaluation.issues.contains(.metricMismatch)
                && !evaluation.issues.contains(.lostVisibility) && !evaluation.issues.contains(.incompleteEvidence) {
                previous = snapshot
            }
            return .applied(evaluation)
        }
    }
}
