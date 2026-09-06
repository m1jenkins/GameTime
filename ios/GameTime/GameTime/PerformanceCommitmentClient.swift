import Foundation

@MainActor
protocol PerformanceCommitmentClient: AnyObject {
    func preview(_ draft: PerformanceCommitmentDraft, actorID: UUID) async throws -> PerformanceCommitmentPreview
    func list(actorID: UUID, before: PerformanceCommitmentAgreement?) async throws -> [PerformanceCommitmentAgreement]
    func detail(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentAgreement
    func lifecycle(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentLifecycle
    func submit(_ request: PendingPerformanceCommitmentRequest) async throws -> PerformanceCommitmentMutationReceipt
}

enum PerformanceCommitmentMutationReceipt: Equatable, Sendable {
    case commitment(UUID)
    case review(PerformanceCommitmentReviewReceipt)
}

enum PerformanceCommitmentClientError: LocalizedError, Equatable, Sendable {
    case accessDenied, invalidTerms, slotOccupied, lifecycle, reviewAlreadyFiled
    case accountChanged, invalidResponse, unavailable, storage

    static func sqlState(_ code: String?) -> Self {
        switch code {
        case "42501", "PGRST301", "PGRST302": .accessDenied
        case "22023": .invalidTerms
        case "23505": .slotOccupied
        case "55000": .lifecycle
        default: .unavailable
        }
    }

    var isDefinitiveRejection: Bool {
        switch self {
        case .accessDenied, .invalidTerms, .slotOccupied, .lifecycle, .reviewAlreadyFiled: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "We couldn’t open this goal or allow that action. Sign in again, then refresh your goals."
        case .invalidTerms:
            "We couldn’t use those rules. Refresh and review your goal again."
        case .slotOccupied:
            "You already have an open goal. Refresh your goals and finish or close it before trying again."
        case .lifecycle:
            "This goal changed or its time ended. Refresh to see what you can do next."
        case .reviewAlreadyFiled:
            "You already asked us to review this result update. Refresh to see your request."
        case .accountChanged:
            "Your sign-in changed. Sign in again, then return to your goals."
        case .storage:
            "We couldn’t read or save your goal request on this phone. Unlock your phone and try again."
        case .invalidResponse, .unavailable:
            "We couldn’t confirm your goal update. Check your connection, then retry any saved request."
        }
    }
}

@MainActor
final class DisabledPerformanceCommitmentClient: PerformanceCommitmentClient {
    func preview(_ draft: PerformanceCommitmentDraft, actorID: UUID) async throws -> PerformanceCommitmentPreview {
        throw PerformanceCommitmentClientError.accessDenied
    }
    func list(actorID: UUID, before: PerformanceCommitmentAgreement?) async throws -> [PerformanceCommitmentAgreement] {
        throw PerformanceCommitmentClientError.accessDenied
    }
    func detail(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentAgreement {
        throw PerformanceCommitmentClientError.accessDenied
    }
    func lifecycle(id: UUID, actorID: UUID) async throws -> PerformanceCommitmentLifecycle {
        throw PerformanceCommitmentClientError.accessDenied
    }
    func submit(_ request: PendingPerformanceCommitmentRequest) async throws -> PerformanceCommitmentMutationReceipt {
        throw PerformanceCommitmentClientError.accessDenied
    }
}
