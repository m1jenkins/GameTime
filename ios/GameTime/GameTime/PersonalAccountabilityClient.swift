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

/// What a purely local HealthKit read observed, with no server round-trip.
///
/// This is the evidence that GameTime can actually see first-party device steps
/// on this phone. It is not a trust claim: nothing here has been attested, and
/// the server must never treat it as proof.
struct LocalStepAccessProbe: Equatable, Sendable {
    let trustedHourCount: Int
    let positiveTrustedSampleCount: Int
    let observedAt: Date

    var sawTrustedDeviceSteps: Bool { positiveTrustedSampleCount > 0 }
}

/// What the device has locally proven about Health access, kept separate from
/// the server's `PersonalDiagnosticStatus`.
///
/// Creating a challenge needs proof that GameTime can read first-party device
/// steps. It does not need the App Attest round-trip: the server independently
/// refuses untrusted evidence when it scores, so gating *creation* on
/// attestation only made the product unreachable until the whole stack was
/// live. Attestation still gates whether evidence counts — see
/// `AppConfiguration.attestedUploadEnabled`.
enum PersonalHealthReadiness: Equatable, Sendable {
    case unknown
    case unavailable
    case authorizationRequested
    case localStepsObserved(LocalStepAccessProbe)
    case attested(TrustedActivityDiagnostic)

    /// Whether the person may freeze terms and create a challenge.
    var permitsCreation: Bool {
        switch self {
        case .unknown, .unavailable, .authorizationRequested:
            false
        case .localStepsObserved(let probe):
            probe.sawTrustedDeviceSteps
        case .attested(let diagnostic):
            diagnostic.isTrusted
        }
    }

    /// Whether the attested path has succeeded. Only this proves the evidence
    /// pipeline end to end.
    var isAttested: Bool {
        if case .attested(let diagnostic) = self { return diagnostic.isTrusted }
        return false
    }
}

@MainActor
protocol TrustedActivityDiagnosticClient: AnyObject {
    func requestAuthorization() async throws -> ActivityAuthorizationOutcome

    /// Reads HealthKit locally and reports whether first-party device steps are
    /// visible. Never contacts the server and never signs anything.
    func probeLocalStepAccess(
        timezone: String
    ) async throws -> LocalStepAccessProbe

    func runTrustedDiagnostic(
        ownerID: UUID,
        timezone: String
    ) async throws -> TrustedActivityDiagnostic
}

@MainActor
protocol PersonalActivitySyncing: AnyObject {
    func requestAuthorization() async throws -> ActivityAuthorizationOutcome
    func pendingUploadCount(for ownerID: UUID) async throws -> Int
    func pendingChallengeID(for ownerID: UUID) async throws -> UUID?
    func sync(
        ownerID: UUID,
        challenge: PersonalChallengeDetail,
        asOf: Date
    ) async throws -> ActivitySyncOutcome
}

extension PersonalActivitySyncing {
    func pendingChallengeID(for ownerID: UUID) async throws -> UUID? {
        _ = ownerID
        return nil
    }
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
            "Challenges can’t be changed yet."
        case .unavailable:
            "We couldn’t reach GameTime right now. Try again in a moment."
        case .invalidResponse:
            "Something came back wrong from GameTime. Try again."
        case .accountChanged:
            "You signed in with a different account. Try again."
        case .openChallengeExists:
            "Finish or cancel your current challenge before you start another."
        case .eligibilityHold:
            "Run a Health check before you start another challenge."
        case .cancellationClosed:
            "Your challenge has already started, so it can’t be cancelled."
        case .diagnosticUnavailable:
            "Health checks aren’t available on this device."
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

    func probeLocalStepAccess(
        timezone: String
    ) async throws -> LocalStepAccessProbe {
        _ = timezone
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
