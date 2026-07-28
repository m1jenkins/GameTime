import Foundation

// MARK: - Persisted challenge requests

struct PendingChallengeSubmission: Codable, Equatable, Sendable {
    let ownerID: UUID
    let terms: ChallengeTerms
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
        terms: ChallengeTerms,
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
        terms = try container.decode(ChallengeTerms.self, forKey: .terms)
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
        -> PendingChallengeSubmission
    {
        guard attemptCount < Int.max else {
            throw PendingChallengeStoreError.invalidRecord(
                "The attempt counter overflowed."
            )
        }
        return PendingChallengeSubmission(
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
            throw PendingChallengeStoreError.ownerMismatch
        }
        guard !terms.inviteeIDs.isEmpty else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved challenge has no invited friends."
            )
        }
        guard terms.inviteeIDs.count <= ChallengeTerms.maximumInvitees else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved challenge exceeds the roster limit."
            )
        }
        guard Set(terms.inviteeIDs).count == terms.inviteeIDs.count else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved challenge contains duplicate invitees."
            )
        }
        guard !terms.inviteeIDs.contains(ownerID) else {
            throw PendingChallengeStoreError.invalidRecord(
                "The challenge author cannot invite themselves."
            )
        }
        let cleanTitle = terms.title.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard cleanTitle == terms.title, (1...80).contains(cleanTitle.count) else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved title is invalid."
            )
        }
        guard terms.targetValue.isFinite, terms.targetValue > 0 else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved target is invalid."
            )
        }
        guard (100...1_000_000).contains(terms.stakeAmountCents) else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved test pledge is invalid."
            )
        }
        guard terms.endsAt > terms.startsAt else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved contest window is invalid."
            )
        }
        guard
            terms.startsAt.isCanonicalMillisecondTimestamp,
            terms.endsAt.isCanonicalMillisecondTimestamp
        else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved contest timestamps are not canonical."
            )
        }
        guard TimeZone(identifier: terms.timezone) != nil else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved timezone is invalid."
            )
        }
        guard createdAt.timeIntervalSinceReferenceDate.isFinite else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved creation time is invalid."
            )
        }
        guard attemptCount >= 0 else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved attempt count is invalid."
            )
        }
        guard (attemptCount == 0) == (lastAttemptAt == nil) else {
            throw PendingChallengeStoreError.invalidRecord(
                "The saved attempt state is inconsistent."
            )
        }
        if let lastAttemptAt {
            guard
                lastAttemptAt.timeIntervalSinceReferenceDate.isFinite,
                lastAttemptAt >= createdAt
            else {
                throw PendingChallengeStoreError.invalidRecord(
                    "The saved attempt time is invalid."
                )
            }
        }
    }
}

protocol PendingChallengeStore: AnyObject, Sendable {
    func load(for ownerID: UUID) async throws -> PendingChallengeSubmission?
    func save(_ submission: PendingChallengeSubmission) async throws
    func remove(for ownerID: UUID) async throws
}

enum PendingChallengeStoreError: LocalizedError, Equatable, Sendable {
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
            "The saved challenge retry could not be read safely."
        case .unsupportedVersion:
            "The saved challenge retry was created by an unsupported app version."
        case .ownerMismatch:
            "The saved challenge retry belongs to a different account."
        case .conflictingRecord:
            "The saved challenge retry conflicts with an existing request."
        case .invalidRecord:
            "The saved challenge retry failed validation."
        case .unavailable:
            "Protected app storage could not be accessed."
        }
    }
}

struct PendingChallengeStoreEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let submission: PendingChallengeSubmission
}

private struct PendingStoreVersion: Decodable {
    let version: Int
}

struct LegacyPendingDuelStoreEnvelope: Codable, Equatable, Sendable {
    static let legacyVersion = 1

    let version: Int
    let submission: LegacyPendingDuelSubmission
}

struct LegacyPendingDuelSubmission: Codable, Equatable, Sendable {
    let ownerID: UUID
    let terms: LegacyDuelTerms
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
        terms: LegacyDuelTerms,
        createdAt: Date,
        attemptCount: Int,
        lastAttemptAt: Date?
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
        terms = try container.decode(LegacyDuelTerms.self, forKey: .terms)
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

    func migrated() -> PendingChallengeSubmission {
        PendingChallengeSubmission(
            ownerID: ownerID,
            terms: terms.migrated(),
            createdAt: createdAt,
            attemptCount: attemptCount,
            lastAttemptAt: lastAttemptAt
        )
    }
}

struct LegacyDuelTerms: Codable, Equatable, Sendable {
    let requestID: UUID
    let title: String
    let inviteeID: UUID
    let metric: ContestMetric
    let cadence: ContestCadence
    let targetValue: Double
    let stakeAmountCents: Int
    let startsAt: Date
    let endsAt: Date
    let timezone: String
    let charityID: UUID
    let tieBreak: ContestTieBreak

    enum CodingKeys: String, CodingKey {
        case requestID
        case title
        case inviteeID
        case metric
        case cadence
        case targetValue
        case stakeAmountCents
        case startsAtBitPattern
        case endsAtBitPattern
        case timezone
        case charityID
        case tieBreak
    }

    init(
        requestID: UUID,
        title: String,
        inviteeID: UUID,
        metric: ContestMetric,
        cadence: ContestCadence,
        targetValue: Double,
        stakeAmountCents: Int,
        startsAt: Date,
        endsAt: Date,
        timezone: String,
        charityID: UUID,
        tieBreak: ContestTieBreak
    ) {
        self.requestID = requestID
        self.title = title
        self.inviteeID = inviteeID
        self.metric = metric
        self.cadence = cadence
        self.targetValue = targetValue
        self.stakeAmountCents = stakeAmountCents
        self.startsAt = startsAt.canonicalizedToMilliseconds()
        self.endsAt = endsAt.canonicalizedToMilliseconds()
        self.timezone = timezone
        self.charityID = charityID
        self.tieBreak = tieBreak
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        title = try container.decode(String.self, forKey: .title)
        inviteeID = try container.decode(UUID.self, forKey: .inviteeID)
        metric = try container.decode(ContestMetric.self, forKey: .metric)
        cadence = try container.decode(ContestCadence.self, forKey: .cadence)
        targetValue = try container.decode(Double.self, forKey: .targetValue)
        stakeAmountCents = try container.decode(
            Int.self,
            forKey: .stakeAmountCents
        )
        startsAt = Date(
            timeIntervalSinceReferenceDate: Double(
                bitPattern: try container.decode(
                    UInt64.self,
                    forKey: .startsAtBitPattern
                )
            )
        )
        endsAt = Date(
            timeIntervalSinceReferenceDate: Double(
                bitPattern: try container.decode(
                    UInt64.self,
                    forKey: .endsAtBitPattern
                )
            )
        )
        timezone = try container.decode(String.self, forKey: .timezone)
        charityID = try container.decode(UUID.self, forKey: .charityID)
        tieBreak = try container.decode(
            ContestTieBreak.self,
            forKey: .tieBreak
        )
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(title, forKey: .title)
        try container.encode(inviteeID, forKey: .inviteeID)
        try container.encode(metric, forKey: .metric)
        try container.encode(cadence, forKey: .cadence)
        try container.encode(targetValue, forKey: .targetValue)
        try container.encode(stakeAmountCents, forKey: .stakeAmountCents)
        try container.encode(
            startsAt.timeIntervalSinceReferenceDate.bitPattern,
            forKey: .startsAtBitPattern
        )
        try container.encode(
            endsAt.timeIntervalSinceReferenceDate.bitPattern,
            forKey: .endsAtBitPattern
        )
        try container.encode(timezone, forKey: .timezone)
        try container.encode(charityID, forKey: .charityID)
        try container.encode(tieBreak, forKey: .tieBreak)
    }

    func migrated() -> ChallengeTerms {
        ChallengeTerms(
            requestID: requestID,
            title: title,
            inviteeIDs: [inviteeID],
            metric: metric,
            cadence: cadence,
            targetValue: targetValue,
            stakeAmountCents: stakeAmountCents,
            startsAt: startsAt,
            endsAt: endsAt,
            timezone: timezone,
            charityID: charityID,
            tieBreak: tieBreak
        )
    }
}

actor FilePendingChallengeStore: PendingChallengeStore {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func applicationSupport() throws -> FilePendingChallengeStore {
        guard
            let applicationSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            throw PendingChallengeStoreError.applicationSupportUnavailable
        }
        return FilePendingChallengeStore(
            directoryURL:
                applicationSupport
                .appendingPathComponent("GameTime", isDirectory: true)
                .appendingPathComponent(
                    // Keep the M8.2a location so installed alpha builds find
                    // and migrate their version-1 single-invitee records.
                    "PendingDuelSubmissions",
                    isDirectory: true
                )
        )
    }

    func load(for ownerID: UUID) throws -> PendingChallengeSubmission? {
        let url = fileURL(for: ownerID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: url)
            let storedVersion = try decoder().decode(
                PendingStoreVersion.self,
                from: data
            ).version
            let submission: PendingChallengeSubmission

            switch storedVersion {
            case LegacyPendingDuelStoreEnvelope.legacyVersion:
                let legacyEnvelope = try decoder().decode(
                    LegacyPendingDuelStoreEnvelope.self,
                    from: data
                )
                submission = legacyEnvelope.submission.migrated()
                try submission.validate(for: ownerID)
                try writeEnvelope(submission, to: url)
            case PendingChallengeStoreEnvelope.currentVersion:
                let envelope = try decoder().decode(
                    PendingChallengeStoreEnvelope.self,
                    from: data
                )
                submission = envelope.submission
            default:
                throw PendingChallengeStoreError.unsupportedVersion(
                    storedVersion
                )
            }

            try submission.validate(for: ownerID)
            return submission
        } catch let error as PendingChallengeStoreError {
            throw error
        } catch is DecodingError {
            throw PendingChallengeStoreError.corruptData
        } catch {
            throw PendingChallengeStoreError.unavailable(
                String(describing: error)
            )
        }
    }

    func save(_ submission: PendingChallengeSubmission) throws {
        try submission.validate(for: submission.ownerID)
        do {
            try prepareDirectory()
            let url = fileURL(for: submission.ownerID)
            if FileManager.default.fileExists(atPath: url.path) {
                guard let existing = try load(for: submission.ownerID) else {
                    throw PendingChallengeStoreError.corruptData
                }
                try validateUpdate(from: existing, to: submission)
            }
            try writeEnvelope(submission, to: url)
        } catch let error as PendingChallengeStoreError {
            throw error
        } catch {
            throw PendingChallengeStoreError.unavailable(
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
            throw PendingChallengeStoreError.unavailable(
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
        from existing: PendingChallengeSubmission,
        to submission: PendingChallengeSubmission
    ) throws {
        guard
            existing.ownerID == submission.ownerID,
            existing.terms == submission.terms,
            existing.createdAt == submission.createdAt,
            submission.attemptCount >= existing.attemptCount
        else {
            throw PendingChallengeStoreError.conflictingRecord
        }

        if submission.attemptCount == existing.attemptCount {
            guard submission.lastAttemptAt == existing.lastAttemptAt else {
                throw PendingChallengeStoreError.conflictingRecord
            }
            return
        }

        guard
            submission.attemptCount == existing.attemptCount + 1,
            let lastAttemptAt = submission.lastAttemptAt,
            lastAttemptAt >= (existing.lastAttemptAt ?? existing.createdAt)
        else {
            throw PendingChallengeStoreError.conflictingRecord
        }
    }

    private func writeEnvelope(
        _ submission: PendingChallengeSubmission,
        to url: URL
    ) throws {
        let envelope = PendingChallengeStoreEnvelope(
            version: PendingChallengeStoreEnvelope.currentVersion,
            submission: submission
        )
        let data = try encoder().encode(envelope)
        try data.write(
            to: url,
            options: [.atomic, .completeFileProtection]
        )
        try excludeFromBackup(url)
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
