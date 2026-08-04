import Foundation
import Supabase

@MainActor
final class SupabasePersonalAccountabilityClient: PersonalAccountabilityClient {
    private let client: SupabaseClient

    init(client: SupabaseClient) {
        self.client = client
    }

    func listMyChallenges() async throws -> PersonalAccountabilitySnapshot {
        do {
            let challengesResponse = try await client
                .rpc("list_my_accountability_challenges_v1")
                .execute()
            let eligibilityResponse = try await client
                .rpc("get_my_personal_eligibility_v1")
                .execute()
            let snapshot = try PersonalRPCDecoder.snapshot(
                from: challengesResponse.data
            )
            let eligibility = try PersonalRPCDecoder.eligibility(
                from: eligibilityResponse.data
            )
            return PersonalAccountabilitySnapshot(
                challenges: snapshot.challenges,
                latestDiagnostic: eligibility.latestDiagnostic
                    ?? snapshot.latestDiagnostic,
                eligibilityHold: eligibility.hold,
                eligibilityHoldActive: !eligibility.eligible
            )
        } catch {
            throw map(error)
        }
    }

    func challenge(id: UUID) async throws -> PersonalChallengeDetail? {
        do {
            let response = try await client
                .rpc(
                    "get_my_accountability_challenge_v1",
                    params: PersonalChallengeIDParameters(challengeID: id)
                )
                .execute()
            return try PersonalRPCDecoder.detail(from: response.data)
        } catch {
            throw map(error)
        }
    }

    func create(
        _ request: PersonalChallengeCreationRequest,
        expectedUserID: UUID
    ) async throws -> UUID {
        guard client.auth.currentSession?.user.id == expectedUserID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        do {
            let response = try await client
                .rpc(
                    "create_personal_challenge_v1",
                    params: CreatePersonalChallengeParameters(request: request)
                )
                .execute()
            guard client.auth.currentSession?.user.id == expectedUserID else {
                throw PersonalAccountabilityClientError.accountChanged
            }
            return try PersonalRPCDecoder.challengeID(from: response.data)
        } catch {
            throw map(error)
        }
    }

    func cancel(
        challengeID: UUID,
        requestID: UUID,
        expectedUserID: UUID
    ) async throws {
        guard client.auth.currentSession?.user.id == expectedUserID else {
            throw PersonalAccountabilityClientError.accountChanged
        }
        do {
            _ = try await client
                .rpc(
                    "cancel_personal_challenge_v1",
                    params: CancelPersonalChallengeParameters(
                        challengeID: challengeID,
                        requestID: requestID
                    )
                )
                .execute()
            guard client.auth.currentSession?.user.id == expectedUserID else {
                throw PersonalAccountabilityClientError.accountChanged
            }
        } catch {
            throw map(error)
        }
    }

    private func map(_ error: Error) -> Error {
        if let typed = error as? PersonalAccountabilityClientError {
            return typed
        }
        let value = String(describing: error).lowercased()
        if value.contains("personal_open_slot")
            || value.contains("one_open_personal")
            || value.contains("open personal challenge")
        {
            return PersonalAccountabilityClientError.openChallengeExists
        }
        if value.contains("eligibility_hold")
            || value.contains("eligibility hold")
        {
            return PersonalAccountabilityClientError.eligibilityHold
        }
        if value.contains("cancellation_closed")
            || value.contains("already started")
            || value.contains("can be cancelled only before it begins")
        {
            return PersonalAccountabilityClientError.cancellationClosed
        }
        if value.contains("network") || value.contains("offline") {
            return PersonalAccountabilityClientError.unavailable
        }
        return error
    }
}

private struct CreatePersonalChallengeParameters: Encodable {
    let requestID: UUID
    let cadence: PersonalChallengeCadence
    let targetSteps: Int
    let commitmentAmountMinor: Int
    let timezone: String
    let requestedStartsAt: Date?

    init(request: PersonalChallengeCreationRequest) {
        requestID = request.requestID
        cadence = request.cadence
        targetSteps = request.targetSteps
        commitmentAmountMinor = request.commitmentAmountMinor
        timezone = request.timezone
        requestedStartsAt = request.startsAt
    }

    /// An omitted start must reach the server as an absent key rather than an
    /// explicit null, so the parameter keeps its default and the request
    /// hashes exactly as it did before a start could be chosen.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(cadence, forKey: .cadence)
        try container.encode(targetSteps, forKey: .targetSteps)
        try container.encode(
            commitmentAmountMinor,
            forKey: .commitmentAmountMinor
        )
        try container.encode(timezone, forKey: .timezone)
        if let requestedStartsAt {
            // A whole-second UTC instant. `timestamptz` parses this
            // unambiguously, which matters because the server compares it
            // against a whole local hour in the frozen timezone.
            try container.encode(
                requestedStartsAt.formatted(.iso8601),
                forKey: .requestedStartsAt
            )
        }
    }

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case cadence
        case targetSteps = "target_steps"
        case commitmentAmountMinor = "commitment_amount_minor"
        case timezone
        case requestedStartsAt = "requested_starts_at"
    }
}

private struct PersonalChallengeIDParameters: Encodable {
    let challengeID: UUID

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
    }
}

private struct CancelPersonalChallengeParameters: Encodable {
    let challengeID: UUID
    let requestID: UUID

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case requestID = "request_id"
    }
}

private enum PersonalRPCDecoder {
    private struct ChallengeIDDocument: Decodable {
        let challengeID: UUID?
        let id: UUID?

        enum CodingKeys: String, CodingKey {
            case challengeID = "challenge_id"
            case id
        }
    }

    static func snapshot(from data: Data) throws -> PersonalAccountabilitySnapshot {
        let decoder = makeDecoder()
        if let snapshot = try? decoder.decode(
            PersonalAccountabilitySnapshot.self,
            from: data
        ) {
            return snapshot
        }
        if let challenges = try? decoder.decode(
            [PersonalChallengeSummary].self,
            from: data
        ) {
            return PersonalAccountabilitySnapshot(
                challenges: challenges,
                latestDiagnostic: nil,
                eligibilityHold: nil
            )
        }
        if let rows = try? decoder.decode([PersonalChallengeRow].self, from: data) {
            return PersonalAccountabilitySnapshot(
                challenges: rows.map(\.summary),
                latestDiagnostic: nil,
                eligibilityHold: nil,
                eligibilityHoldActive: rows.contains {
                    $0.eligibilityHoldActive
                }
            )
        }
        throw PersonalAccountabilityClientError.invalidResponse
    }

    static func detail(from data: Data) throws -> PersonalChallengeDetail? {
        if data == Data("null".utf8) {
            return nil
        }
        let decoder = makeDecoder()
        if let detail = try? decoder.decode(PersonalChallengeDetail.self, from: data) {
            return detail
        }
        if let rows = try? decoder.decode([PersonalChallengeDetail].self, from: data) {
            return rows.first
        }
        if let row = try? decoder.decode(PersonalChallengeRow.self, from: data) {
            return row.detail
        }
        if let rows = try? decoder.decode([PersonalChallengeRow].self, from: data) {
            return rows.first?.detail
        }
        throw PersonalAccountabilityClientError.invalidResponse
    }

    static func challengeID(from data: Data) throws -> UUID {
        let decoder = makeDecoder()
        if let id = try? decoder.decode(UUID.self, from: data) {
            return id
        }
        if let document = try? decoder.decode(ChallengeIDDocument.self, from: data),
            let id = document.challengeID ?? document.id
        {
            return id
        }
        if let documents = try? decoder.decode([ChallengeIDDocument].self, from: data),
            let id = documents.first?.challengeID ?? documents.first?.id
        {
            return id
        }
        throw PersonalAccountabilityClientError.invalidResponse
    }

    static func eligibility(from data: Data) throws -> PersonalEligibilityRow {
        let decoder = makeDecoder()
        if let row = try? decoder.decode(PersonalEligibilityRow.self, from: data) {
            return row
        }
        if let rows = try? decoder.decode([PersonalEligibilityRow].self, from: data),
            let row = rows.first
        {
            return row
        }
        throw PersonalAccountabilityClientError.invalidResponse
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            if let seconds = try? container.decode(Double.self) {
                return Date(timeIntervalSince1970: seconds)
            }
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
            ]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid personal challenge timestamp."
            )
        }
        return decoder
    }
}

private struct PersonalEligibilityRow: Decodable {
    let eligible: Bool
    let holdID: UUID?
    let holdReason: String?
    let heldAt: Date?
    let challengeID: UUID?
    let latestDiagnosticID: UUID?
    let latestDiagnosticObservedAt: Date?
    let latestDiagnosticRecordedAt: Date?
    let latestDiagnosticTrustedDeviceSampleCount: Int?
    let latestDiagnosticClearedHold: Bool

    enum CodingKeys: String, CodingKey {
        case eligible
        case holdID = "hold_id"
        case holdReason = "hold_reason"
        case heldAt = "held_at"
        case challengeID = "challenge_id"
        case latestDiagnosticID = "latest_diagnostic_id"
        case latestDiagnosticObservedAt = "latest_diagnostic_observed_at"
        case latestDiagnosticRecordedAt = "latest_diagnostic_recorded_at"
        case latestDiagnosticTrustedDeviceSampleCount =
            "latest_diagnostic_trusted_device_sample_count"
        case latestDiagnosticClearedHold =
            "latest_diagnostic_cleared_hold"
    }

    var hold: PersonalEligibilityHold? {
        guard !eligible, let holdID, let holdReason, let heldAt else {
            return nil
        }
        return PersonalEligibilityHold(
            id: holdID,
            reasonCode: holdReason,
            createdAt: heldAt,
            clearedAt: nil,
            clearedByDiagnosticID: nil
        )
    }

    var latestDiagnostic: TrustedActivityDiagnostic? {
        guard
            let latestDiagnosticID,
            latestDiagnosticObservedAt != nil,
            let latestDiagnosticRecordedAt,
            let latestDiagnosticTrustedDeviceSampleCount,
            latestDiagnosticTrustedDeviceSampleCount > 0
        else {
            return nil
        }
        return TrustedActivityDiagnostic(
            id: latestDiagnosticID,
            status: .trusted,
            performedAt: latestDiagnosticRecordedAt,
            trustedQueriedHourCount: 0,
            positiveTrustedSampleCount:
                latestDiagnosticTrustedDeviceSampleCount,
            clearsEligibilityHold: latestDiagnosticClearedHold
        )
    }
}

private struct PersonalChallengeRow: Decodable {
    let challengeID: UUID
    let status: PersonalChallengeStatus
    let cadence: PersonalChallengeCadence
    let targetSteps: Int
    let commitmentAmountMinor: Int
    let currency: String
    let settlementMode: PersonalSettlementMode
    let termsVersion: String
    let timezone: String
    let agreedAt: Date
    let startsAt: Date
    let endsAt: Date
    let evidenceCutoff: Date
    let closedAt: Date?
    let totalSteps: Double
    let coveredBucketCount: Int
    let expectedBucketCount: Int
    let latestSyncAt: Date?
    let outcome: PersonalOutcomeKind?
    let outcomeReason: String?
    let resultPublishedAt: Date?
    let eligibilityHoldActive: Bool
    let dailyProgress: [PersonalDayProgress]?

    enum CodingKeys: String, CodingKey {
        case challengeID = "challenge_id"
        case status
        case cadence
        case targetSteps = "target_steps"
        case commitmentAmountMinor = "commitment_amount_minor"
        case currency
        case settlementMode = "settlement_mode"
        case termsVersion = "terms_version"
        case timezone
        case agreedAt = "agreed_at"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case evidenceCutoff = "evidence_cutoff"
        case closedAt = "closed_at"
        case totalSteps = "total_steps"
        case coveredBucketCount = "covered_bucket_count"
        case expectedBucketCount = "expected_bucket_count"
        case latestSyncAt = "latest_sync_at"
        case outcome
        case outcomeReason = "outcome_reason"
        case resultPublishedAt = "result_published_at"
        case eligibilityHoldActive = "eligibility_hold_active"
        case dailyProgress = "daily_progress"
    }

    var summary: PersonalChallengeSummary {
        PersonalChallengeSummary(
            id: challengeID,
            status: status,
            terms: terms,
            progress: progress,
            outcome: result
        )
    }

    var detail: PersonalChallengeDetail {
        PersonalChallengeDetail(
            id: challengeID,
            status: status,
            terms: terms,
            progress: progress,
            outcome: result
        )
    }

    private var terms: FrozenPersonalTerms {
        FrozenPersonalTerms(
            challengeID: challengeID,
            userID: nil,
            cadence: cadence,
            targetSteps: targetSteps,
            commitmentAmountMinor: commitmentAmountMinor,
            currency: currency,
            settlementMode: settlementMode,
            termsVersion: termsVersion,
            timezone: timezone,
            agreementAt: agreedAt,
            startsAt: startsAt,
            endsAt: endsAt,
            evidenceCutoff: evidenceCutoff,
            closedAt: closedAt
        )
    }

    private var progress: PersonalProgress {
        let steps = Int(totalSteps.rounded(.towardZero))
        let days = dailyProgress ?? []
        let remaining: Int
        if cadence == .daily {
            remaining = PersonalProgress.dailyRemainingSteps(
                targetSteps: targetSteps,
                days: days
            )
        } else {
            remaining = max(0, targetSteps - steps)
        }
        let evidenceState = PersonalProgress.aggregateEvidenceState(
            days: days,
            coveredBucketCount: coveredBucketCount,
            expectedBucketCount: expectedBucketCount
        )
        return PersonalProgress(
            trustedSteps: steps,
            remainingSteps: remaining,
            qualifyingDays: days.filter { $0.metTarget == true }.count,
            completedDays: days.filter {
                switch $0.evidenceState {
                case .future, .inProgress, .pending:
                    false
                case .complete, .incomplete, .missing, .quarantined,
                    .conflicting, .unresolved, .outageWaived:
                    true
                }
            }.count,
            days: days,
            evidenceState: evidenceState,
            lastTrustedSyncAt: latestSyncAt,
            pendingUploadCount: 0,
            coveredBucketCount: coveredBucketCount,
            expectedBucketCount: expectedBucketCount
        )
    }

    private var result: PersonalOutcome? {
        guard
            let outcome,
            let resultPublishedAt
        else {
            return nil
        }
        return PersonalOutcome(
            id: challengeID,
            kind: outcome,
            reasonCode: outcomeReason ?? "unspecified",
            evidenceCutoff: evidenceCutoff,
            publishedAt: resultPublishedAt
        )
    }
}
