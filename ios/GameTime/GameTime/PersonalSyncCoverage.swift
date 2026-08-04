import Foundation
import GameTimeCore
import Supabase

struct PendingPersonalCoverageSubmission: Codable, Equatable, Sendable {
    let ownerID: UUID
    let challengeID: UUID
    let clientCoverageID: UUID
    let body: Data
    let keyID: String
    let assertion: Data
    let createdAt: Date
    let attemptCount: Int
    let lastAttemptAt: Date?

    func recordingAttempt(at date: Date = Date())
        -> PendingPersonalCoverageSubmission
    {
        PendingPersonalCoverageSubmission(
            ownerID: ownerID,
            challengeID: challengeID,
            clientCoverageID: clientCoverageID,
            body: body,
            keyID: keyID,
            assertion: assertion,
            createdAt: createdAt,
            attemptCount: attemptCount + 1,
            lastAttemptAt: max(date, lastAttemptAt ?? createdAt)
        )
    }
}

protocol PendingPersonalCoverageStore: AnyObject, Sendable {
    func load(for ownerID: UUID) async throws
        -> PendingPersonalCoverageSubmission?
    func save(_ submission: PendingPersonalCoverageSubmission) async throws
    func remove(for ownerID: UUID) async throws
}

enum PersonalCoverageError: LocalizedError, Equatable, Sendable {
    case invalidRequest
    case accountChanged
    case pendingForDifferentChallenge
    case conflictingPendingRequest
    case protectedStorageUnavailable
    case noTrustedCoverage
    case unavailable
    case rejected
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            "Something went wrong with that request."
        case .accountChanged:
            "You signed in with a different account. Sync your steps again."
        case .pendingForDifferentChallenge:
            "There’s a sync still waiting. Finish that one first."
        case .conflictingPendingRequest:
            "This doesn’t match the sync that’s already waiting."
        case .protectedStorageUnavailable:
            "We couldn’t save this to your phone."
        case .noTrustedCoverage:
            "We can’t tell the difference between “no steps” and “no data” right now. Run a Health check and try again."
        case .unavailable:
            "We couldn’t sync your steps. Try again in a moment."
        case .rejected:
            "GameTime wouldn’t accept those steps. Try again."
        case .invalidResponse:
            "Something came back wrong from GameTime. Try again."
        }
    }
}

actor FilePendingPersonalCoverageStore: PendingPersonalCoverageStore {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func applicationSupport() throws -> FilePendingPersonalCoverageStore {
        guard
            let base = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw PersonalCoverageError.protectedStorageUnavailable
        }
        return FilePendingPersonalCoverageStore(
            directoryURL: base
                .appendingPathComponent("GameTime", isDirectory: true)
                .appendingPathComponent(
                    "PendingPersonalCoverage",
                    isDirectory: true
                )
        )
    }

    func load(for ownerID: UUID) throws
        -> PendingPersonalCoverageSubmission?
    {
        let url = fileURL(ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let submission = try decoder().decode(
                PendingPersonalCoverageSubmission.self,
                from: Data(contentsOf: url)
            )
            try Self.validate(submission, ownerID: ownerID)
            return submission
        } catch let error as PersonalCoverageError {
            throw error
        } catch {
            throw PersonalCoverageError.protectedStorageUnavailable
        }
    }

    func save(_ submission: PendingPersonalCoverageSubmission) throws {
        try Self.validate(submission, ownerID: submission.ownerID)
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
            var directory = directoryURL
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try directory.setResourceValues(values)

            if let existing = try load(for: submission.ownerID),
                existing.body != submission.body
                    || existing.keyID != submission.keyID
                    || existing.assertion != submission.assertion
                    || existing.clientCoverageID != submission.clientCoverageID
                    || existing.challengeID != submission.challengeID
            {
                throw PersonalCoverageError.conflictingPendingRequest
            }
            let data = try encoder().encode(submission)
            let url = fileURL(submission.ownerID)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            var protectedURL = url
            try protectedURL.setResourceValues(values)
        } catch let error as PersonalCoverageError {
            throw error
        } catch {
            throw PersonalCoverageError.protectedStorageUnavailable
        }
    }

    func remove(for ownerID: UUID) throws {
        let url = fileURL(ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw PersonalCoverageError.protectedStorageUnavailable
        }
    }

    private func fileURL(_ ownerID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(ownerID.uuidString.lowercased()).json"
        )
    }

    private static func validate(
        _ submission: PendingPersonalCoverageSubmission,
        ownerID: UUID
    ) throws {
        guard
            submission.ownerID == ownerID,
            !submission.body.isEmpty,
            submission.body.count <= 256 * 1024,
            !submission.keyID.isEmpty,
            !submission.assertion.isEmpty,
            submission.attemptCount >= 0,
            (submission.attemptCount == 0)
                == (submission.lastAttemptAt == nil),
            let identity = try? JSONDecoder().decode(
                PersonalCoverageBodyIdentity.self,
                from: submission.body
            ),
            identity.challengeID == submission.challengeID,
            identity.clientCoverageID == submission.clientCoverageID,
            !identity.coveredIntervalStarts.isEmpty
        else {
            throw PersonalCoverageError.invalidRequest
        }
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}

actor EphemeralPendingPersonalCoverageStore: PendingPersonalCoverageStore {
    private var submissions: [UUID: PendingPersonalCoverageSubmission] = [:]

    func load(for ownerID: UUID) -> PendingPersonalCoverageSubmission? {
        submissions[ownerID]
    }

    func save(_ submission: PendingPersonalCoverageSubmission) throws {
        if let existing = submissions[submission.ownerID],
            existing.body != submission.body
                || existing.keyID != submission.keyID
                || existing.assertion != submission.assertion
        {
            throw PersonalCoverageError.conflictingPendingRequest
        }
        submissions[submission.ownerID] = submission
    }

    func remove(for ownerID: UUID) {
        submissions[ownerID] = nil
    }
}

@MainActor
protocol PersonalCoverageClient: AnyObject {
    func prepare(
        ownerID: UUID,
        challengeID: UUID,
        intervalStarts: [Date],
        observedAt: Date
    ) async throws -> PendingPersonalCoverageSubmission
    func send(
        ownerID: UUID,
        submission: PendingPersonalCoverageSubmission
    ) async throws -> PersonalCoverageReceipt
}

struct PersonalCoverageReceipt: Equatable, Sendable {
    let coverageBatchID: UUID
    let replayed: Bool
}

@MainActor
final class SupabasePersonalCoverageClient: PersonalCoverageClient {
    private let client: SupabaseClient
    private let configuration: AppConfiguration
    private let signer: any AppAttestedBodySigning
    private let session: URLSession

    init(
        client: SupabaseClient,
        configuration: AppConfiguration,
        signer: any AppAttestedBodySigning,
        session: URLSession = .shared
    ) throws {
        guard configuration.environment == .staging else {
            throw PersonalCoverageError.unavailable
        }
        self.client = client
        self.configuration = configuration
        self.signer = signer
        self.session = session
    }

    func prepare(
        ownerID: UUID,
        challengeID: UUID,
        intervalStarts: [Date],
        observedAt: Date
    ) async throws -> PendingPersonalCoverageSubmission {
        guard client.auth.currentSession?.user.id == ownerID else {
            throw PersonalCoverageError.accountChanged
        }
        let clientCoverageID = UUID()
        let body = try PersonalCoverageRequestBody.encode(
            challengeID: challengeID,
            clientCoverageID: clientCoverageID,
            observedAt: observedAt,
            coveredIntervalStarts: intervalStarts
        )
        let signed = try await signer.sign(ownerID: ownerID, body: body)
        return PendingPersonalCoverageSubmission(
            ownerID: ownerID,
            challengeID: challengeID,
            clientCoverageID: clientCoverageID,
            body: body,
            keyID: signed.keyID,
            assertion: signed.assertion,
            createdAt: Date(),
            attemptCount: 0,
            lastAttemptAt: nil
        )
    }

    func send(
        ownerID: UUID,
        submission: PendingPersonalCoverageSubmission
    ) async throws -> PersonalCoverageReceipt {
        // Checked before the session is read, so an obviously wrong submission
        // still fails without reaching the network.
        guard submission.ownerID == ownerID else {
            throw PersonalCoverageError.accountChanged
        }
        guard let liveSession = try await client.validSession() else {
            throw MetricUploadClientError.authenticationRequired
        }
        guard
            liveSession.user.id == ownerID,
            let identity = try? JSONDecoder().decode(
                PersonalCoverageBodyIdentity.self,
                from: submission.body
            ),
            identity.challengeID == submission.challengeID,
            identity.clientCoverageID == submission.clientCoverageID,
            !identity.coveredIntervalStarts.isEmpty,
            !submission.keyID.isEmpty,
            !submission.assertion.isEmpty
        else {
            if liveSession.user.id != ownerID {
                throw PersonalCoverageError.accountChanged
            }
            throw PersonalCoverageError.invalidRequest
        }
        var request = URLRequest(url: try endpointURL())
        request.httpMethod = "POST"
        request.httpBody = submission.body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(
            configuration.supabasePublishableKey,
            forHTTPHeaderField: "apikey"
        )
        request.setValue(
            "Bearer \(liveSession.accessToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            submission.keyID,
            forHTTPHeaderField: "x-gametime-key-id"
        )
        request.setValue(
            submission.assertion.base64EncodedString(),
            forHTTPHeaderField: "x-gametime-assertion"
        )

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PersonalCoverageError.unavailable
        }
        guard client.auth.currentSession?.user.id == ownerID else {
            throw PersonalCoverageError.accountChanged
        }
        guard let http = response as? HTTPURLResponse else {
            throw PersonalCoverageError.invalidResponse
        }
        guard http.statusCode == 200 || http.statusCode == 201 else {
            if http.statusCode >= 500 {
                throw PersonalCoverageError.unavailable
            }
            // A refused token reads as a refused upload unless the body is read.
            if
                http.statusCode == 401 || http.statusCode == 403,
                AttestedEndpointRefusal.decode(data) == .authentication
            {
                throw MetricUploadClientError.tokenRefusedByService
            }
            throw PersonalCoverageError.rejected
        }
        let decoder = JSONDecoder()
        guard
            data.count <= 64 * 1024,
            let document = try? decoder.decode(
                PersonalCoverageResponse.self,
                from: data
            ),
            (http.statusCode == 200 && document.replayed)
                || (http.statusCode == 201 && !document.replayed)
        else {
            throw PersonalCoverageError.invalidResponse
        }
        return PersonalCoverageReceipt(
            coverageBatchID: document.coverageBatchID,
            replayed: document.replayed
        )
    }

    private func endpointURL() throws -> URL {
        guard
            var components = URLComponents(
                url: configuration.supabaseURL,
                resolvingAgainstBaseURL: false
            )
        else { throw PersonalCoverageError.unavailable }
        var parts = components.path.split(separator: "/").map(String.init)
        if Array(parts.suffix(2)) != ["functions", "v1"] {
            parts.append(contentsOf: ["functions", "v1"])
        }
        parts.append("personal-sync-coverage")
        components.path = "/" + parts.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        guard let url = components.url else {
            throw PersonalCoverageError.unavailable
        }
        return url
    }
}

@MainActor
final class PersonalActivitySyncCoordinator: PersonalActivitySyncing {
    private let activity: any PersonalStepCoverageQuerying
    private let metrics: any ActivitySyncing
    private let coverage: any PersonalCoverageClient
    private let pendingCoverage: any PendingPersonalCoverageStore

    init(
        activity: any PersonalStepCoverageQuerying,
        metrics: any ActivitySyncing,
        coverage: any PersonalCoverageClient,
        pendingCoverage: any PendingPersonalCoverageStore
    ) {
        self.activity = activity
        self.metrics = metrics
        self.coverage = coverage
        self.pendingCoverage = pendingCoverage
    }

    func requestAuthorization() async throws -> ActivityAuthorizationOutcome {
        try await metrics.requestAuthorization()
    }

    func pendingUploadCount(for ownerID: UUID) async throws -> Int {
        let metricCount = try await metrics.pendingUploadCount(for: ownerID)
        let coverageCount = try await pendingCoverage.load(for: ownerID) == nil
            ? 0
            : 1
        return metricCount + coverageCount
    }

    func sync(
        ownerID: UUID,
        challenge: PersonalChallengeDetail,
        asOf: Date
    ) async throws -> ActivitySyncOutcome {
        guard challenge.permitsActivitySync(at: asOf) else {
            throw ActivitySyncError.challengeNotEligible
        }
        let savedCoverage = try await pendingCoverage.load(for: ownerID)
        if let savedCoverage, savedCoverage.challengeID != challenge.id {
            throw PersonalCoverageError.pendingForDifferentChallenge
        }

        let contest = contestCard(ownerID: ownerID, challenge: challenge)
        let pendingMetricCountBefore = try await metrics.pendingUploadCount(
            for: ownerID
        )
        var metricOutcome = try await metrics.sync(
            ownerID: ownerID,
            contest: contest,
            asOf: asOf
        )
        guard case .synced(_, let firstStepTotal) = metricOutcome else {
            // Coverage must never certify metric bytes that remain queued, or
            // turn an unreadable HealthKit query into evidence completeness.
            return metricOutcome
        }

        if pendingMetricCountBefore > 0 {
            guard try await metrics.pendingUploadCount(for: ownerID) == 0 else {
                return .queuedForRetry(stepTotal: firstStepTotal)
            }
            // ActivitySyncCoordinator returns immediately after replaying an
            // old metric body. A second pass is required to query fresh data
            // for the `asOf` instant that coverage will describe.
            metricOutcome = try await metrics.sync(
                ownerID: ownerID,
                contest: contest,
                asOf: asOf
            )
            guard case .synced(_, let freshStepTotal) = metricOutcome else {
                return metricOutcome
            }
            guard try await metrics.pendingUploadCount(for: ownerID) == 0 else {
                return .queuedForRetry(stepTotal: freshStepTotal)
            }
        } else {
            guard try await metrics.pendingUploadCount(for: ownerID) == 0 else {
                return .queuedForRetry(stepTotal: firstStepTotal)
            }
        }

        if let savedCoverage {
            // Retrying changes attempt metadata only. The signed body and
            // assertion remain byte-for-byte identical to the saved request.
            let attempted = savedCoverage.recordingAttempt()
            try await pendingCoverage.save(attempted)
            _ = try await coverage.send(
                ownerID: ownerID,
                submission: attempted
            )
            try await pendingCoverage.remove(for: ownerID)
        }

        guard let frozenTimeZone = TimeZone(
            identifier: challenge.terms.timezone
        ) else {
            throw ActivitySyncError.invalidTimeZoneSchedule
        }
        let schedule = ContestTimeZoneSchedule(
            initialTimeZone: frozenTimeZone
        )
        let intervalStarts = try await activity
            .completedTrustedStepIntervalStarts(
                overlapping: DateInterval(
                    start: challenge.terms.startsAt,
                    end: challenge.terms.endsAt
                ),
                timeZoneSchedule: schedule,
                asOf: asOf
            )
        guard !intervalStarts.isEmpty else {
            throw PersonalCoverageError.noTrustedCoverage
        }
        var submission = try await coverage.prepare(
            ownerID: ownerID,
            challengeID: challenge.id,
            intervalStarts: intervalStarts,
            observedAt: max(asOf, Date())
        )
        try await pendingCoverage.save(submission)
        submission = submission.recordingAttempt()
        try await pendingCoverage.save(submission)
        _ = try await coverage.send(ownerID: ownerID, submission: submission)
        try await pendingCoverage.remove(for: ownerID)
        return metricOutcome
    }

    private func contestCard(
        ownerID: UUID,
        challenge: PersonalChallengeDetail
    ) -> ContestCard {
        ContestCard(
            id: challenge.id,
            title: "Personal accountability",
            createdBy: ownerID,
            metric: .steps,
            cadence: challenge.terms.cadence == .daily ? .daily : .cumulative,
            targetValue: Double(challenge.terms.targetSteps),
            stakeAmountCents: challenge.terms.commitmentAmountMinor,
            tieBreak: .void,
            startsAt: challenge.terms.startsAt,
            endsAt: challenge.terms.endsAt,
            status: .active,
            myStatus: .accepted,
            maxParticipants: 1,
            participantTimeZone: challenge.terms.timezone,
            timeZoneChanges: [],
            participants: [
                ContestParticipantCard(
                    userID: ownerID,
                    status: .accepted,
                    charityID: nil
                )
            ]
        )
    }
}

private struct PersonalCoverageBodyIdentity: Decodable {
    let challengeID: UUID
    let clientCoverageID: UUID
    let coveredIntervalStarts: [String]

    enum CodingKeys: String, CodingKey {
        case challengeID = "challengeId"
        case clientCoverageID = "clientCoverageId"
        case coveredIntervalStarts
    }
}

private struct PersonalCoverageRequestBody: Encodable {
    let challengeID: UUID
    let clientCoverageID: UUID
    let observedAt: String
    let coveredIntervalStarts: [String]

    enum CodingKeys: String, CodingKey {
        case challengeID = "challengeId"
        case clientCoverageID = "clientCoverageId"
        case observedAt
        case coveredIntervalStarts
    }

    static func encode(
        challengeID: UUID,
        clientCoverageID: UUID,
        observedAt: Date,
        coveredIntervalStarts: [Date]
    ) throws -> Data {
        let unique = Array(Set(coveredIntervalStarts)).sorted()
        guard !unique.isEmpty, unique.count <= 2_000 else {
            throw PersonalCoverageError.invalidRequest
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(
            PersonalCoverageRequestBody(
                challengeID: challengeID,
                clientCoverageID: clientCoverageID,
                observedAt: formatter.string(from: observedAt),
                coveredIntervalStarts: unique.map(formatter.string(from:))
            )
        )
    }
}

private struct PersonalCoverageResponse: Decodable {
    let coverageBatchID: UUID
    let replayed: Bool

    enum CodingKeys: String, CodingKey {
        case coverageBatchID = "coverageBatchId"
        case replayed
    }
}
