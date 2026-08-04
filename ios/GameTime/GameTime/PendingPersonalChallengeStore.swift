import Foundation

struct PendingPersonalChallengeSubmission: Codable, Equatable, Sendable {
    let ownerID: UUID
    let request: PersonalChallengeCreationRequest
    let createdAt: Date
    let attemptCount: Int
    let lastAttemptAt: Date?

    init(
        ownerID: UUID,
        request: PersonalChallengeCreationRequest,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil
    ) {
        self.ownerID = ownerID
        self.request = request
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
    }

    func recordingAttempt(at date: Date = Date()) throws
        -> PendingPersonalChallengeSubmission
    {
        guard attemptCount < Int.max else {
            throw PendingPersonalChallengeStoreError.invalidRecord
        }
        return PendingPersonalChallengeSubmission(
            ownerID: ownerID,
            request: request,
            createdAt: createdAt,
            attemptCount: attemptCount + 1,
            lastAttemptAt: max(max(date, createdAt), lastAttemptAt ?? createdAt)
        )
    }

    func validate(for expectedOwnerID: UUID) throws {
        guard ownerID == expectedOwnerID else {
            throw PendingPersonalChallengeStoreError.ownerMismatch
        }
        guard PersonalChallengeDraft.targetRange.contains(request.targetSteps),
            PersonalChallengeDraft.allowedCommitmentAmountsMinor.contains(
                request.commitmentAmountMinor
            ),
            !request.timezone.isEmpty,
            TimeZone(identifier: request.timezone) != nil,
            createdAt.timeIntervalSinceReferenceDate.isFinite,
            attemptCount >= 0,
            (attemptCount == 0) == (lastAttemptAt == nil)
        else {
            throw PendingPersonalChallengeStoreError.invalidRecord
        }
        // A saved start is checked for shape, never for freshness. It may well
        // have passed while the record sat here; that is a submission failure
        // the flow surfaces and the owner discards, not a corrupt record to
        // refuse loading. Refusing it would strand the retry it protects.
        if let startsAt = request.startsAt {
            guard startsAt.timeIntervalSinceReferenceDate.isFinite,
                Calendar(identifier: .gregorian).component(
                    .nanosecond,
                    from: startsAt
                ) == 0
            else {
                throw PendingPersonalChallengeStoreError.invalidRecord
            }
        }
        if let lastAttemptAt {
            guard
                lastAttemptAt.timeIntervalSinceReferenceDate.isFinite,
                lastAttemptAt >= createdAt
            else {
                throw PendingPersonalChallengeStoreError.invalidRecord
            }
        }
    }
}

protocol PendingPersonalChallengeStore: AnyObject, Sendable {
    func load(for ownerID: UUID) async throws
        -> PendingPersonalChallengeSubmission?
    func save(_ submission: PendingPersonalChallengeSubmission) async throws
    func remove(for ownerID: UUID) async throws
}

enum PendingPersonalChallengeStoreError: LocalizedError, Equatable, Sendable {
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
            "The saved personal challenge retry could not be read safely."
        case .unsupportedVersion:
            "The saved personal challenge retry uses an unsupported version."
        case .wrongEnvelopeKind:
            "The saved request is not a personal-accountability request."
        case .ownerMismatch:
            "The saved personal challenge retry belongs to another account."
        case .conflictingRecord:
            "The saved personal challenge retry conflicts with this request."
        case .invalidRecord:
            "The saved personal challenge retry failed validation."
        case .unavailable:
            "Protected personal challenge storage could not be accessed."
        }
    }
}

private struct PendingPersonalChallengeEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1
    static let currentKind = "personal_accountability_v1"

    let kind: String
    let version: Int
    let submission: PendingPersonalChallengeSubmission
}

actor FilePendingPersonalChallengeStore: PendingPersonalChallengeStore {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func applicationSupport() throws -> FilePendingPersonalChallengeStore {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw PendingPersonalChallengeStoreError
                .applicationSupportUnavailable
        }
        return FilePendingPersonalChallengeStore(
            directoryURL: applicationSupport
                .appendingPathComponent("GameTime", isDirectory: true)
                .appendingPathComponent(
                    "PendingPersonalChallengeSubmissions",
                    isDirectory: true
                )
        )
    }

    func load(for ownerID: UUID) throws
        -> PendingPersonalChallengeSubmission?
    {
        let url = fileURL(for: ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let envelope = try decoder().decode(
                PendingPersonalChallengeEnvelope.self,
                from: Data(contentsOf: url)
            )
            guard envelope.kind == PendingPersonalChallengeEnvelope.currentKind else {
                throw PendingPersonalChallengeStoreError.wrongEnvelopeKind
            }
            guard envelope.version == PendingPersonalChallengeEnvelope.currentVersion else {
                throw PendingPersonalChallengeStoreError.unsupportedVersion(
                    envelope.version
                )
            }
            try envelope.submission.validate(for: ownerID)
            return envelope.submission
        } catch let error as PendingPersonalChallengeStoreError {
            throw error
        } catch is DecodingError {
            throw PendingPersonalChallengeStoreError.corruptData
        } catch {
            throw PendingPersonalChallengeStoreError.unavailable
        }
    }

    func save(_ submission: PendingPersonalChallengeSubmission) throws {
        try submission.validate(for: submission.ownerID)
        do {
            try prepareDirectory()
            let url = fileURL(for: submission.ownerID)
            if FileManager.default.fileExists(atPath: url.path),
                let existing = try load(for: submission.ownerID)
            {
                try validateUpdate(from: existing, to: submission)
            }
            let envelope = PendingPersonalChallengeEnvelope(
                kind: PendingPersonalChallengeEnvelope.currentKind,
                version: PendingPersonalChallengeEnvelope.currentVersion,
                submission: submission
            )
            let data = try encoder().encode(envelope)
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try excludeFromBackup(url)
        } catch let error as PendingPersonalChallengeStoreError {
            throw error
        } catch {
            throw PendingPersonalChallengeStoreError.unavailable
        }
    }

    func remove(for ownerID: UUID) throws {
        let url = fileURL(for: ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw PendingPersonalChallengeStoreError.unavailable
        }
    }

    func fileURL(for ownerID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(ownerID.uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private func validateUpdate(
        from existing: PendingPersonalChallengeSubmission,
        to submission: PendingPersonalChallengeSubmission
    ) throws {
        guard
            existing.ownerID == submission.ownerID,
            existing.request == submission.request,
            existing.createdAt == submission.createdAt,
            submission.attemptCount >= existing.attemptCount
        else {
            throw PendingPersonalChallengeStoreError.conflictingRecord
        }
        if submission.attemptCount == existing.attemptCount {
            guard submission.lastAttemptAt == existing.lastAttemptAt else {
                throw PendingPersonalChallengeStoreError.conflictingRecord
            }
            return
        }
        guard
            submission.attemptCount == existing.attemptCount + 1,
            let lastAttemptAt = submission.lastAttemptAt,
            lastAttemptAt >= (existing.lastAttemptAt ?? existing.createdAt)
        else {
            throw PendingPersonalChallengeStoreError.conflictingRecord
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
            throw PendingPersonalChallengeStoreError.unavailable
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

actor EphemeralPendingPersonalChallengeStore: PendingPersonalChallengeStore {
    private var submissions: [UUID: PendingPersonalChallengeSubmission] = [:]

    func load(for ownerID: UUID) throws
        -> PendingPersonalChallengeSubmission?
    {
        let submission = submissions[ownerID]
        try submission?.validate(for: ownerID)
        return submission
    }

    func save(_ submission: PendingPersonalChallengeSubmission) throws {
        try submission.validate(for: submission.ownerID)
        submissions[submission.ownerID] = submission
    }

    func remove(for ownerID: UUID) {
        submissions[ownerID] = nil
    }
}
