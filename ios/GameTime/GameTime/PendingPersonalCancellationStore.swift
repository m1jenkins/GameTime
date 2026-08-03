import Foundation

struct PendingPersonalCancellationSubmission: Codable, Equatable, Sendable {
    let ownerID: UUID
    let challengeID: UUID
    let requestID: UUID
    /// Canonical RPC parameters retained so an ambiguous response can only be
    /// retried with the same logical request bytes.
    let requestBody: Data
    let createdAt: Date
    let attemptCount: Int
    let lastAttemptAt: Date?

    init(
        ownerID: UUID,
        challengeID: UUID,
        requestID: UUID,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil
    ) throws {
        self.ownerID = ownerID
        self.challengeID = challengeID
        self.requestID = requestID
        requestBody = try Self.encodeBody(
            challengeID: challengeID,
            requestID: requestID
        )
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
        try validate(for: ownerID)
    }

    private init(
        ownerID: UUID,
        challengeID: UUID,
        requestID: UUID,
        requestBody: Data,
        createdAt: Date,
        attemptCount: Int,
        lastAttemptAt: Date?
    ) {
        self.ownerID = ownerID
        self.challengeID = challengeID
        self.requestID = requestID
        self.requestBody = requestBody
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
    }

    func recordingAttempt(at date: Date = Date()) throws
        -> PendingPersonalCancellationSubmission
    {
        guard attemptCount < Int.max else {
            throw PendingPersonalCancellationStoreError.invalidRecord
        }
        return PendingPersonalCancellationSubmission(
            ownerID: ownerID,
            challengeID: challengeID,
            requestID: requestID,
            requestBody: requestBody,
            createdAt: createdAt,
            attemptCount: attemptCount + 1,
            lastAttemptAt: max(max(date, createdAt), lastAttemptAt ?? createdAt)
        )
    }

    func validate(for expectedOwnerID: UUID) throws {
        guard ownerID == expectedOwnerID else {
            throw PendingPersonalCancellationStoreError.ownerMismatch
        }
        guard
            requestBody == (try? Self.encodeBody(
                challengeID: challengeID,
                requestID: requestID
            )),
            createdAt.timeIntervalSinceReferenceDate.isFinite,
            attemptCount >= 0,
            (attemptCount == 0) == (lastAttemptAt == nil)
        else {
            throw PendingPersonalCancellationStoreError.invalidRecord
        }
        if let lastAttemptAt {
            guard
                lastAttemptAt.timeIntervalSinceReferenceDate.isFinite,
                lastAttemptAt >= createdAt
            else {
                throw PendingPersonalCancellationStoreError.invalidRecord
            }
        }
    }

    private static func encodeBody(
        challengeID: UUID,
        requestID: UUID
    ) throws -> Data {
        struct Body: Encodable {
            let challengeID: UUID
            let requestID: UUID

            enum CodingKeys: String, CodingKey {
                case challengeID = "challenge_id"
                case requestID = "request_id"
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(
            Body(challengeID: challengeID, requestID: requestID)
        )
    }
}

protocol PendingPersonalCancellationStore: AnyObject, Sendable {
    func load(for ownerID: UUID) async throws
        -> PendingPersonalCancellationSubmission?
    func save(_ submission: PendingPersonalCancellationSubmission) async throws
    func remove(for ownerID: UUID) async throws
}

enum PendingPersonalCancellationStoreError:
    LocalizedError, Equatable, Sendable
{
    case applicationSupportUnavailable
    case corruptData
    case unsupportedVersion(Int)
    case wrongEnvelopeKind
    case ownerMismatch
    case conflictingRecord
    case invalidRecord
    case unavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Protected app storage is unavailable."
        case .corruptData:
            "The saved cancellation retry could not be read safely."
        case .unsupportedVersion:
            "The saved cancellation retry uses an unsupported version."
        case .wrongEnvelopeKind:
            "The saved request is not a personal cancellation request."
        case .ownerMismatch:
            "The saved cancellation retry belongs to another account."
        case .conflictingRecord:
            "The saved cancellation retry conflicts with this request."
        case .invalidRecord:
            "The saved cancellation retry failed validation."
        case .unavailable:
            "Protected cancellation storage could not be accessed."
        }
    }
}

private struct PendingPersonalCancellationEnvelope:
    Codable, Equatable, Sendable
{
    static let currentVersion = 1
    static let currentKind = "personal_cancellation_v1"

    let kind: String
    let version: Int
    let submission: PendingPersonalCancellationSubmission
}

actor FilePendingPersonalCancellationStore:
    PendingPersonalCancellationStore
{
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func applicationSupport() throws
        -> FilePendingPersonalCancellationStore
    {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw PendingPersonalCancellationStoreError
                .applicationSupportUnavailable
        }
        return FilePendingPersonalCancellationStore(
            directoryURL: applicationSupport
                .appendingPathComponent("GameTime", isDirectory: true)
                .appendingPathComponent(
                    "PendingPersonalCancellations",
                    isDirectory: true
                )
        )
    }

    func load(for ownerID: UUID) throws
        -> PendingPersonalCancellationSubmission?
    {
        let url = fileURL(for: ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let envelope = try decoder().decode(
                PendingPersonalCancellationEnvelope.self,
                from: Data(contentsOf: url)
            )
            guard envelope.kind
                == PendingPersonalCancellationEnvelope.currentKind
            else {
                throw PendingPersonalCancellationStoreError.wrongEnvelopeKind
            }
            guard envelope.version
                == PendingPersonalCancellationEnvelope.currentVersion
            else {
                throw PendingPersonalCancellationStoreError.unsupportedVersion(
                    envelope.version
                )
            }
            try envelope.submission.validate(for: ownerID)
            return envelope.submission
        } catch let error as PendingPersonalCancellationStoreError {
            throw error
        } catch is DecodingError {
            throw PendingPersonalCancellationStoreError.corruptData
        } catch {
            throw PendingPersonalCancellationStoreError.unavailable
        }
    }

    func save(_ submission: PendingPersonalCancellationSubmission) throws {
        try submission.validate(for: submission.ownerID)
        do {
            try prepareDirectory()
            if let existing = try load(for: submission.ownerID) {
                try validateUpdate(from: existing, to: submission)
            }
            let envelope = PendingPersonalCancellationEnvelope(
                kind: PendingPersonalCancellationEnvelope.currentKind,
                version: PendingPersonalCancellationEnvelope.currentVersion,
                submission: submission
            )
            let data = try encoder().encode(envelope)
            let url = fileURL(for: submission.ownerID)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try excludeFromBackup(url)
        } catch let error as PendingPersonalCancellationStoreError {
            throw error
        } catch {
            throw PendingPersonalCancellationStoreError.unavailable
        }
    }

    func remove(for ownerID: UUID) throws {
        let url = fileURL(for: ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw PendingPersonalCancellationStoreError.unavailable
        }
    }

    private func fileURL(for ownerID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(ownerID.uuidString.lowercased()).json"
        )
    }

    private func validateUpdate(
        from existing: PendingPersonalCancellationSubmission,
        to submission: PendingPersonalCancellationSubmission
    ) throws {
        guard
            existing.ownerID == submission.ownerID,
            existing.challengeID == submission.challengeID,
            existing.requestID == submission.requestID,
            existing.requestBody == submission.requestBody,
            existing.createdAt == submission.createdAt,
            submission.attemptCount >= existing.attemptCount
        else {
            throw PendingPersonalCancellationStoreError.conflictingRecord
        }
        if submission.attemptCount == existing.attemptCount {
            guard submission.lastAttemptAt == existing.lastAttemptAt else {
                throw PendingPersonalCancellationStoreError.conflictingRecord
            }
            return
        }
        guard
            submission.attemptCount == existing.attemptCount + 1,
            let lastAttemptAt = submission.lastAttemptAt,
            lastAttemptAt >= (existing.lastAttemptAt ?? existing.createdAt)
        else {
            throw PendingPersonalCancellationStoreError.conflictingRecord
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try excludeFromBackup(directoryURL)
    }

    private func excludeFromBackup(_ url: URL) throws {
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        do {
            try protectedURL.setResourceValues(values)
        } catch {
            throw PendingPersonalCancellationStoreError.unavailable
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

actor EphemeralPendingPersonalCancellationStore:
    PendingPersonalCancellationStore
{
    private var submissions:
        [UUID: PendingPersonalCancellationSubmission] = [:]

    func load(for ownerID: UUID) throws
        -> PendingPersonalCancellationSubmission?
    {
        let submission = submissions[ownerID]
        try submission?.validate(for: ownerID)
        return submission
    }

    func save(_ submission: PendingPersonalCancellationSubmission) throws {
        try submission.validate(for: submission.ownerID)
        if let existing = submissions[submission.ownerID],
            existing.challengeID != submission.challengeID
                || existing.requestID != submission.requestID
                || existing.requestBody != submission.requestBody
                || existing.createdAt != submission.createdAt
        {
            throw PendingPersonalCancellationStoreError.conflictingRecord
        }
        submissions[submission.ownerID] = submission
    }

    func remove(for ownerID: UUID) {
        submissions[ownerID] = nil
    }
}
