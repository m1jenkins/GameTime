import Foundation
import GameTimeCore

/// Reads challenge steps from HealthKit and reports the total without
/// uploading anything.
///
/// Attested upload needs a provisioned device and the deployed attested
/// endpoints. Debug builds have neither, but the person still needs to see that
/// their steps are being read — otherwise an active challenge looks broken.
///
/// This deliberately produces no evidence. Nothing here is signed, nothing is
/// sent, and the server's scored progress is unaffected. It is a local display
/// value only, and the UI must label it as unverified.
@MainActor
final class LocalOnlyPersonalActivitySyncCoordinator: PersonalActivitySyncing {
    private let activity: any ActivityClient

    init(activity: any ActivityClient) {
        self.activity = activity
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        try await activity.requestStepReadAuthorization()
    }

    func pendingUploadCount(for ownerID: UUID) async throws -> Int {
        _ = ownerID
        // Nothing is ever queued, because nothing is ever uploaded.
        return 0
    }

    func sync(
        ownerID: UUID,
        challenge: PersonalChallengeDetail,
        asOf: Date
    ) async throws -> ActivitySyncOutcome {
        _ = ownerID
        guard challenge.permitsActivitySync(at: asOf) else {
            throw ActivitySyncError.challengeNotEligible
        }
        guard
            let frozenTimeZone = TimeZone(
                identifier: challenge.terms.timezone
            )
        else {
            throw ActivitySyncError.invalidTimeZoneSchedule
        }

        let buckets = try await activity.stepBuckets(
            overlapping: DateInterval(
                start: challenge.terms.startsAt,
                end: challenge.terms.endsAt
            ),
            timeZoneSchedule: ContestTimeZoneSchedule(
                initialTimeZone: frozenTimeZone
            ),
            asOf: asOf
        )
        // Same admissibility rule the attested path uses, so the local number
        // does not drift above what the server would eventually accept.
        let deviceSteps = buckets
            .filter { $0.provenance == .device }
            .reduce(0.0) { $0 + $1.value }

        guard !buckets.isEmpty else { return .noReadableData }
        return .synced(replayed: false, stepTotal: deviceSteps)
    }
}

/// Stands in where App Attest cannot run. Every signing attempt refuses.
///
/// This exists so the local read path can be constructed without pretending a
/// signer is available. It must never produce a value that looks like a valid
/// assertion.
@MainActor
final class UnavailableAppAttestedBodySigner: AppAttestedBodySigning {
    func sign(ownerID: UUID, body: Data) async throws -> MetricSignedMaterial {
        _ = (ownerID, body)
        throw MetricUploadClientError.stagingOnly
    }
}
