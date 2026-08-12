import Foundation

protocol PersonalStepSnapshotCaching: AnyObject, Sendable {
    func load(
        ownerID: UUID,
        challengeID: UUID,
        termsFingerprint: String
    ) async throws -> PersonalStepSnapshot?
    func save(
        _ snapshot: PersonalStepSnapshot,
        ownerID: UUID
    ) async throws
    func remove(ownerID: UUID, challengeID: UUID) async throws
    func removeAll(ownerID: UUID) async throws
}

enum PersonalStepSnapshotCacheError: LocalizedError, Equatable, Sendable {
    case applicationSupportUnavailable
    case corruptData
    case invalidSnapshot
    case unavailable

    var errorDescription: String? {
        switch self {
        case .applicationSupportUnavailable, .unavailable:
            "Protected step storage is unavailable."
        case .corruptData, .invalidSnapshot:
            "Saved step progress couldn’t be read safely."
        }
    }
}

private struct PersonalStepSnapshotEnvelope: Codable, Sendable {
    static let kind = "personal_step_snapshot"
    static let version = 1

    let kind: String
    let version: Int
    let ownerID: UUID
    let snapshot: PersonalStepSnapshot

    enum CodingKeys: String, CodingKey {
        case kind
        case version
        case ownerID = "owner_id"
        case snapshot
    }
}

actor FilePersonalStepSnapshotCache: PersonalStepSnapshotCaching {
    private let directoryURL: URL

    init(directoryURL: URL) {
        self.directoryURL = directoryURL
    }

    static func applicationSupport() throws -> FilePersonalStepSnapshotCache {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            throw PersonalStepSnapshotCacheError.applicationSupportUnavailable
        }
        return FilePersonalStepSnapshotCache(
            directoryURL: applicationSupport
                .appendingPathComponent("GameTime", isDirectory: true)
                .appendingPathComponent(
                    "PersonalStepSnapshots",
                    isDirectory: true
                )
        )
    }

    func load(
        ownerID: UUID,
        challengeID: UUID,
        termsFingerprint: String
    ) throws -> PersonalStepSnapshot? {
        let url = fileURL(ownerID: ownerID, challengeID: challengeID)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let envelope = try decoder().decode(
                PersonalStepSnapshotEnvelope.self,
                from: Data(contentsOf: url)
            )
            guard envelope.kind == PersonalStepSnapshotEnvelope.kind,
                envelope.version == PersonalStepSnapshotEnvelope.version,
                envelope.ownerID == ownerID,
                envelope.snapshot.matches(
                    challengeID: challengeID,
                    termsFingerprint: termsFingerprint
                )
            else { throw PersonalStepSnapshotCacheError.invalidSnapshot }
            return envelope.snapshot
        } catch let error as PersonalStepSnapshotCacheError {
            throw error
        } catch is DecodingError {
            throw PersonalStepSnapshotCacheError.corruptData
        } catch {
            throw PersonalStepSnapshotCacheError.unavailable
        }
    }

    func save(
        _ snapshot: PersonalStepSnapshot,
        ownerID: UUID
    ) throws {
        guard snapshot.isStructurallyValid else {
            throw PersonalStepSnapshotCacheError.invalidSnapshot
        }
        do {
            try prepareDirectory()
            let envelope = PersonalStepSnapshotEnvelope(
                kind: PersonalStepSnapshotEnvelope.kind,
                version: PersonalStepSnapshotEnvelope.version,
                ownerID: ownerID,
                snapshot: snapshot
            )
            let url = fileURL(
                ownerID: ownerID,
                challengeID: snapshot.challengeID
            )
            try encoder().encode(envelope).write(
                to: url,
                options: [.atomic, .completeFileProtection]
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(values)
        } catch let error as PersonalStepSnapshotCacheError {
            throw error
        } catch {
            throw PersonalStepSnapshotCacheError.unavailable
        }
    }

    func remove(ownerID: UUID, challengeID: UUID) throws {
        let url = fileURL(ownerID: ownerID, challengeID: challengeID)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            throw PersonalStepSnapshotCacheError.unavailable
        }
    }

    func removeAll(ownerID: UUID) throws {
        guard FileManager.default.fileExists(atPath: directoryURL.path) else {
            return
        }
        do {
            let prefix = ownerID.uuidString.lowercased() + "-"
            let urls = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil
            )
            for url in urls where url.deletingPathExtension().lastPathComponent
                .hasPrefix(prefix)
            {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            throw PersonalStepSnapshotCacheError.unavailable
        }
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directoryURL
        try url.setResourceValues(values)
    }

    private func fileURL(ownerID: UUID, challengeID: UUID) -> URL {
        directoryURL.appendingPathComponent(
            "\(ownerID.uuidString.lowercased())-\(challengeID.uuidString.lowercased()).json"
        )
    }

    private func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}

actor EphemeralPersonalStepSnapshotCache: PersonalStepSnapshotCaching {
    private var snapshots: [String: PersonalStepSnapshot] = [:]

    func load(
        ownerID: UUID,
        challengeID: UUID,
        termsFingerprint: String
    ) -> PersonalStepSnapshot? {
        let snapshot = snapshots[key(ownerID, challengeID)]
        guard snapshot?.matches(
            challengeID: challengeID,
            termsFingerprint: termsFingerprint
        ) == true else { return nil }
        return snapshot
    }

    func save(_ snapshot: PersonalStepSnapshot, ownerID: UUID) throws {
        guard snapshot.isStructurallyValid else {
            throw PersonalStepSnapshotCacheError.invalidSnapshot
        }
        snapshots[key(ownerID, snapshot.challengeID)] = snapshot
    }

    func remove(ownerID: UUID, challengeID: UUID) {
        snapshots[key(ownerID, challengeID)] = nil
    }

    func removeAll(ownerID: UUID) {
        let prefix = ownerID.uuidString.lowercased() + ":"
        snapshots.keys
            .filter { $0.hasPrefix(prefix) }
            .forEach { snapshots[$0] = nil }
    }

    private func key(_ ownerID: UUID, _ challengeID: UUID) -> String {
        "\(ownerID.uuidString.lowercased()):\(challengeID.uuidString.lowercased())"
    }
}
