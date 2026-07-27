import Foundation

struct PendingDuelSubmission: Codable, Equatable, Sendable {
    let ownerID: UUID
    let terms: DuelTerms
    let createdAt: Date
    let attemptCount: Int
    let lastAttemptAt: Date?

    enum CodingKeys: String, CodingKey {
        case ownerID
        case terms
        case createdAtBitPattern
        case attemptCount
        case lastAttemptAtBitPattern
    }

    init(
        ownerID: UUID,
        terms: DuelTerms,
        createdAt: Date = Date(),
        attemptCount: Int = 0,
        lastAttemptAt: Date? = nil
    ) {
        self.ownerID = ownerID
        self.terms = terms
        self.createdAt = createdAt
        self.attemptCount = attemptCount
        self.lastAttemptAt = lastAttemptAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ownerID = try container.decode(UUID.self, forKey: .ownerID)
        terms = try container.decode(DuelTerms.self, forKey: .terms)
        createdAt = Date(
            timeIntervalSinceReferenceDate: Double(
                bitPattern: try container.decode(
                    UInt64.self,
                    forKey: .createdAtBitPattern
                )
            )
        )
        attemptCount = try container.decode(Int.self, forKey: .attemptCount)
        if let bitPattern = try container.decodeIfPresent(
            UInt64.self,
            forKey: .lastAttemptAtBitPattern
        ) {
            lastAttemptAt = Date(
                timeIntervalSinceReferenceDate: Double(bitPattern: bitPattern)
            )
        } else {
            lastAttemptAt = nil
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ownerID, forKey: .ownerID)
        try container.encode(terms, forKey: .terms)
        try container.encode(
            createdAt.timeIntervalSinceReferenceDate.bitPattern,
            forKey: .createdAtBitPattern
        )
        try container.encode(attemptCount, forKey: .attemptCount)
        try container.encodeIfPresent(
            lastAttemptAt?.timeIntervalSinceReferenceDate.bitPattern,
            forKey: .lastAttemptAtBitPattern
        )
    }

    func recordingAttempt(at date: Date = Date()) throws
        -> PendingDuelSubmission
    {
        guard attemptCount < Int.max else {
            throw PendingDuelStoreError.invalidRecord(
                "The attempt counter overflowed."
            )
        }
        return PendingDuelSubmission(
            ownerID: ownerID,
            terms: terms,
            createdAt: createdAt,
            attemptCount: attemptCount + 1,
            lastAttemptAt: max(
                max(date, createdAt),
                lastAttemptAt ?? createdAt
            )
        )
    }

    func validate(for expectedOwnerID: UUID) throws {
        guard ownerID == expectedOwnerID else {
            throw PendingDuelStoreError.ownerMismatch
        }
        guard ownerID != terms.inviteeID else {
            throw PendingDuelStoreError.invalidRecord(
                "The owner and opponent must be different people."
            )
        }
        let cleanTitle = terms.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard cleanTitle == terms.title, (1...80).contains(cleanTitle.count) else {
            throw PendingDuelStoreError.invalidRecord(
                "The saved title is invalid."
            )
        }
        guard terms.targetValue.isFinite, terms.targetValue > 0 else {
            throw PendingDuelStoreError.invalidRecord(
                "The saved target is invalid."
            )
        }
        guard (100...1_000_000).contains(terms.stakeAmountCents) else {
            throw PendingDuelStoreError.invalidRecord(
                "The saved test pledge is invalid."
            )
        }
        guard terms.endsAt > terms.startsAt else {
            throw PendingDuelStoreError.invalidRecord(
                "The saved contest window is invalid."
            )
        }
        guard
            terms.startsAt.isCanonicalMillisecondTimestamp,
            terms.endsAt.isCanonicalMillisecondTimestamp
        else {
            throw PendingDuelStoreError.invalidRecord(
                "The saved contest timestamps are not canonical."
            )
        }
        guard TimeZone(identifier: terms.timezone) != nil else {
            throw PendingDuelStoreError.invalidRecord(
                "The saved timezone is invalid."
            )
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PendingDuelStoreError.invalidRecord(
                "The saved creation time is invalid."
            )
        }
        guard attemptCount >= 0 else {
            throw PendingDuelStoreError.invalidRecord(
                "The saved attempt count is invalid."
            )
        }
        guard (attemptCount == 0) == (lastAttemptAt == nil) else {
            throw PendingDuelStoreError.invalidRecord(
                "The saved attempt state is inconsistent."
            )
        }
        if let lastAttemptAt {
            guard
                lastAttemptAt.timeIntervalSinceReferenceDate.isFinite,
                lastAttemptAt >= createdAt
            else {
                throw PendingDuelStoreError.invalidRecord(
                    "The saved attempt time is invalid."
                )
            }
        }
    }
}

protocol PendingDuelStore: AnyObject, Sendable {
    func load(for ownerID: UUID) async throws -> PendingDuelSubmission?
    func save(_ submission: PendingDuelSubmission) async throws
    func remove(for ownerID: UUID) async throws
}

enum PendingDuelStoreError: LocalizedError, Equatable, Sendable {
    case applicationSupportUnavailable
    case corruptData
    case unsupportedVersion(Int)
    case ownerMismatch
    case conflictingRecord
    case invalidRecord(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable:
            "Protected app storage is unavailable."
        case .corruptData:
            "The saved duel retry could not be read safely."
        case .unsupportedVersion:
            "The saved duel retry was created by an unsupported app version."
        case .ownerMismatch:
            "The saved duel retry belongs to a different account."
        case .conflictingRecord:
            "The saved duel retry conflicts with an existing request."
        case .invalidRecord:
            "The saved duel retry failed validation."
        case .unavailable:
            "Protected app storage could not be accessed."
        }
    }
}

struct PendingDuelStoreEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let submission: PendingDuelSubmission
}

actor FilePendingDuelStore: PendingDuelStore {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func applicationSupport() throws -> FilePendingDuelStore {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw PendingDuelStoreError.applicationSupportUnavailable
        }
        return FilePendingDuelStore(
            directoryURL:
                applicationSupport
                .appendingPathComponent("GameTime", isDirectory: true)
                .appendingPathComponent(
                    "PendingDuelSubmissions",
                    isDirectory: true
                )
        )
    }

    func load(for ownerID: UUID) throws -> PendingDuelSubmission? {
        let url = fileURL(for: ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let envelope = try decoder().decode(
                PendingDuelStoreEnvelope.self,
                from: data
            )
            guard envelope.version == PendingDuelStoreEnvelope.currentVersion
            else {
                throw PendingDuelStoreError.unsupportedVersion(envelope.version)
            }
            try envelope.submission.validate(for: ownerID)
            return envelope.submission
        } catch let error as PendingDuelStoreError {
            throw error
        } catch is DecodingError {
            throw PendingDuelStoreError.corruptData
        } catch {
            throw PendingDuelStoreError.unavailable(
                String(describing: error)
            )
        }
    }

    func save(_ submission: PendingDuelSubmission) throws {
        try submission.validate(for: submission.ownerID)
        do {
            try prepareDirectory()
            let url = fileURL(for: submission.ownerID)
            if FileManager.default.fileExists(atPath: url.path) {
                guard let existing = try load(for: submission.ownerID) else {
                    throw PendingDuelStoreError.corruptData
                }
                try validateUpdate(from: existing, to: submission)
            }
            let envelope = PendingDuelStoreEnvelope(
                version: PendingDuelStoreEnvelope.currentVersion,
                submission: submission
            )
            let data = try encoder().encode(envelope)
            try data.write(
                to: url,
                options: [.atomic, .completeFileProtection]
            )
            try excludeFromBackup(url)
        } catch let error as PendingDuelStoreError {
            throw error
        } catch {
            throw PendingDuelStoreError.unavailable(
                String(describing: error)
            )
        }
    }

    func remove(for ownerID: UUID) throws {
        let url = fileURL(for: ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw PendingDuelStoreError.unavailable(
                String(describing: error)
            )
        }
    }

    func fileURL(for ownerID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(ownerID.uuidString.lowercased()).json",
            isDirectory: false
        )
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try excludeFromBackup(directoryURL)
    }

    private func validateUpdate(
        from existing: PendingDuelSubmission,
        to submission: PendingDuelSubmission
    ) throws {
        guard
            existing.ownerID == submission.ownerID,
            existing.terms == submission.terms,
            existing.createdAt == submission.createdAt,
            submission.attemptCount >= existing.attemptCount
        else {
            throw PendingDuelStoreError.conflictingRecord
        }

        if submission.attemptCount == existing.attemptCount {
            guard submission.lastAttemptAt == existing.lastAttemptAt else {
                throw PendingDuelStoreError.conflictingRecord
            }
            return
        }

        guard
            submission.attemptCount == existing.attemptCount + 1,
            let lastAttemptAt = submission.lastAttemptAt,
            lastAttemptAt >= (existing.lastAttemptAt ?? existing.createdAt)
        else {
            throw PendingDuelStoreError.conflictingRecord
        }
    }

    private func excludeFromBackup(_ url: URL) throws {
        var protectedURL = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try protectedURL.setResourceValues(values)
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
