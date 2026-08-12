import Foundation
import Supabase

@MainActor
protocol PersonalHealthSnapshotUploading: AnyObject {
    func upload(
        _ snapshot: PersonalStepSnapshot,
        expectedUserID: UUID
    ) async throws
}

@MainActor
final class SupabasePersonalHealthSnapshotUploader:
    PersonalHealthSnapshotUploading
{
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func upload(
        _ snapshot: PersonalStepSnapshot,
        expectedUserID: UUID
    ) async throws {
        guard snapshot.isStructurallyValid else {
            throw PersonalAccountabilityClientError.invalidResponse
        }
        guard client.auth.currentSession?.user.id == expectedUserID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        _ = try await client.rpc(
            "upsert_my_personal_health_snapshot_v2",
            params: PersonalHealthSnapshotParameters(snapshot: snapshot)
        ).execute()
        guard client.auth.currentSession?.user.id == expectedUserID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
    }
}

private struct PersonalHealthSnapshotParameters: Encodable {
    let challengeID: UUID
    let termsFingerprint: String
    let observedAt: Date
    let queryThrough: Date
    let dailyProgress: [PersonalStepSnapshot.Day]

    init(snapshot: PersonalStepSnapshot) {
        challengeID = snapshot.challengeID
        termsFingerprint = snapshot.termsFingerprint
        observedAt = snapshot.observedAt
        queryThrough = snapshot.queryThrough
        dailyProgress = snapshot.dailyProgress
    }

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case termsFingerprint = "terms_fingerprint"
        case observedAt = "observed_at"
        case queryThrough = "query_through"
        case dailyProgress = "daily_progress"
    }
}

@MainActor
final class DisabledPersonalHealthSnapshotUploader:
    PersonalHealthSnapshotUploading
{
    func upload(
        _ snapshot: PersonalStepSnapshot,
        expectedUserID: UUID
    ) async throws {
        _ = (snapshot, expectedUserID)
    }
}
