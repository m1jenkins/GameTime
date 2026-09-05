import Foundation

@MainActor
protocol DuelClient: AnyObject {
    func catalog(actorID: UUID) async throws -> DuelCatalog
    func list(actorID: UUID, before: DuelAgreement?) async throws -> [DuelAgreement]
    func detail(id: UUID, actorID: UUID) async throws -> DuelAgreement
    func lifecycle(id: UUID, actorID: UUID) async throws -> DuelLifecycle
    func invitationLink(id: UUID, actorID: UUID) async throws -> DuelInvitationLink?
    func resolveInvitation(token: UUID, actorID: UUID) async throws -> UUID
    func submit(_ request: PendingDuelRequest) async throws -> UUID
}

enum DuelClientError: LocalizedError, Equatable, Sendable {
    case accessDenied, invalidTerms, slotOccupied, lifecycle
    case accountChanged, invalidResponse, unavailable, storage, reviewAlreadyFiled, exitAlreadySaved

    static func sqlState(_ code: String?) -> Self {
        switch code {
        case "42501": .accessDenied
        case "22023": .invalidTerms
        case "23505": .slotOccupied
        case "55000": .lifecycle
        default: .unavailable
        }
    }

    var isDefinitiveRejection: Bool {
        switch self {
        case .accessDenied, .invalidTerms, .slotOccupied, .lifecycle, .reviewAlreadyFiled, .exitAlreadySaved: true
        default: false
        }
    }

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "We couldn’t open this duel or allow that action. Refresh your duels; new invitations need two approved friends."
        case .invalidTerms:
            "We couldn’t use those rules. Refresh and review the challenge again."
        case .slotOccupied:
            "One of you already has an open duel. Refresh your duels and finish or cancel it before trying again."
        case .lifecycle:
            "This duel changed or its time ended. Refresh to see what you can do next."
        case .reviewAlreadyFiled:
            "You already asked us to review this result update. Refresh to see your request."
        case .exitAlreadySaved:
            "An exit is already saved for this duel. Refresh to see its latest status."
        case .accountChanged:
            "Your account changed. Return to your duels after signing in."
        case .storage:
            "We couldn’t read or save your duel request on this phone. Unlock your phone and try again."
        case .invalidResponse, .unavailable:
            "We couldn’t confirm your duel update. Check your connection, then retry any saved request."
        }
    }
}

@MainActor
final class DisabledDuelClient: DuelClient {
    func catalog(actorID: UUID) async throws -> DuelCatalog { throw DuelClientError.accessDenied }
    func list(actorID: UUID, before: DuelAgreement?) async throws -> [DuelAgreement] { throw DuelClientError.accessDenied }
    func detail(id: UUID, actorID: UUID) async throws -> DuelAgreement { throw DuelClientError.accessDenied }
    func lifecycle(id: UUID, actorID: UUID) async throws -> DuelLifecycle { throw DuelClientError.accessDenied }
    func submit(_ request: PendingDuelRequest) async throws -> UUID { throw DuelClientError.accessDenied }
}

extension DuelClient {
    func invitationLink(id: UUID, actorID: UUID) async throws -> DuelInvitationLink? { nil }
    func resolveInvitation(token: UUID, actorID: UUID) async throws -> UUID { throw DuelClientError.accessDenied }
}
