import Foundation

@MainActor
protocol PersonalAccountabilityClient: AnyObject {
    func listMyChallenges() async throws -> PersonalAccountabilitySnapshot
    func challenge(id: UUID) async throws -> PersonalChallengeDetail?
    func create(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> UUID
    func cancel(
        challengeID: UUID,
        requestID: UUID,
        expectedUserID: UUID
    ) async throws
}

@MainActor
protocol TrustedActivityDiagnosticClient: AnyObject {
    func requestAuthorization() async throws -> ActivityAuthorizationOutcome
    func runTrustedDiagnostic(
        ownerID: UUID,
        timezone: String
    ) async throws -> TrustedActivityDiagnostic
}

@MainActor
protocol PersonalActivitySyncing: AnyObject {
    func requestAuthorization() async throws -> ActivityAuthorizationOutcome
    func pendingUploadCount(for ownerID: UUID) async throws -> Int
    func sync(
        ownerID: UUID,
        challenge: PersonalChallengeDetail,
        asOf: Date
    ) async throws -> ActivitySyncOutcome
}

enum PersonalAccountabilityClientError: LocalizedError, Equatable, Sendable {
    case stagingOnly
    case unavailable
    case invalidResponse
    case accountChanged
    case openChallengeExists
    case eligibilityHold
    case cancellationClosed
    case diagnosticUnavailable

    var errorDescription: String? {
        switch self {
        case .stagingOnly:
            "Personal challenge changes are available only in local and Staging builds."
        case .unavailable:
            "GameTime could not reach personal accountability right now."
        case .invalidResponse:
            "GameTime received an invalid personal challenge response."
        case .accountChanged:
            "The signed-in account changed. Try again."
        case .openChallengeExists:
            "Finish or cancel your current challenge before starting another."
        case .eligibilityHold:
            "Complete a fresh trusted Health diagnostic before starting another challenge."
        case .cancellationClosed:
            "This challenge has already started and can no longer be cancelled."
        case .diagnosticUnavailable:
            "A trusted Health diagnostic is not available on this device."
        }
    }
}

@MainActor
final class DisabledPersonalAccountabilityClient: PersonalAccountabilityClient {
    func listMyChallenges() async throws -> PersonalAccountabilitySnapshot {
        PersonalAccountabilitySnapshot(
            challenges: [],
            latestDiagnostic: nil,
            eligibilityHold: nil
        )
    }

    func challenge(id: UUID) async throws -> PersonalChallengeDetail? {
        _ = id
        return nil
    }

    func create(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> UUID {
        _ = (request, expectedUserID)
        throw PersonalAccountabilityClientError.stagingOnly
    }

    func cancel(
        challengeID: UUID,
        requestID: UUID,
        expectedUserID: UUID
    ) async throws {
        _ = (challengeID, requestID, expectedUserID)
        throw PersonalAccountabilityClientError.stagingOnly
    }
}

@MainActor
final class DisabledTrustedActivityDiagnosticClient:
    TrustedActivityDiagnosticClient
{
    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        throw PersonalAccountabilityClientError.diagnosticUnavailable
    }

    func runTrustedDiagnostic(
        ownerID: UUID,
        timezone: String
    ) async throws -> TrustedActivityDiagnostic {
        _ = (ownerID, timezone)
        throw PersonalAccountabilityClientError.diagnosticUnavailable
    }
}

@MainActor
final class DisabledPersonalActivitySyncCoordinator: PersonalActivitySyncing {
    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        throw ActivitySyncError.stagingOnly
    }

    func pendingUploadCount(for ownerID: UUID) async throws -> Int {
        _ = ownerID
        return 0
    }

    func sync(
        ownerID: UUID,
        challenge: PersonalChallengeDetail,
        asOf: Date
    ) async throws -> ActivitySyncOutcome {
        _ = (ownerID, challenge, asOf)
        throw ActivitySyncError.stagingOnly
    }
}
