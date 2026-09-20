import Foundation
import GameTimeCore

/// Exact diagnostic bytes and only the counts needed to restore its receipt.
/// This is an owner-scoped local persistence record, never a network DTO.
struct PendingTrustedActivityDiagnostic: Codable, Equatable {
    let version: Int
    let actorID: UUID
    let requestID: UUID
    let body: Data
    let keyID: String
    let assertion: Data
    let environment: AppAttestEnvironment
    let hourCount: Int
    let sampleCount: Int
}

@MainActor
final class TrustedActivityDiagnosticFileStore {
    let directory: URL
    init(directory: URL) { self.directory = directory }
    static func applicationSupport() throws -> TrustedActivityDiagnosticFileStore {
        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw PersonalCoverageError.protectedStorageUnavailable
        }
        return Self(directory: base.appendingPathComponent("GameTime/TrustedActivityDiagnostics", isDirectory: true))
    }
    func load(actor: UUID) throws -> PendingTrustedActivityDiagnostic? {
        let file = url(actor)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        do {
            let bytes = try Data(contentsOf: file)
            guard bytes.count <= 128 * 1024 else { throw PersonalCoverageError.protectedStorageUnavailable }
            let saved = try JSONDecoder().decode(PendingTrustedActivityDiagnostic.self, from: bytes)
            try validate(saved, actor: actor)
            return saved
        } catch { throw PersonalCoverageError.protectedStorageUnavailable }
    }
    func save(_ saved: PendingTrustedActivityDiagnostic) throws {
        try validate(saved, actor: saved.actorID)
        if let old = try load(actor: saved.actorID), old != saved { throw PersonalCoverageError.conflictingPendingRequest }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var folder = directory, file = url(saved.actorID)
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try folder.setResourceValues(values)
            try JSONEncoder().encode(saved).write(to: file, options: [.atomic, .completeFileProtection])
            try file.setResourceValues(values)
        } catch { throw PersonalCoverageError.protectedStorageUnavailable }
    }
    func clear(actor: UUID) throws {
        let file = url(actor)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
    private func url(_ actor: UUID) -> URL { directory.appendingPathComponent(actor.uuidString.lowercased() + ".json") }
    private func validate(_ saved: PendingTrustedActivityDiagnostic, actor: UUID) throws {
        guard saved.version == 1, saved.actorID == actor, !saved.keyID.isEmpty,
              saved.body.count <= 64 * 1024, saved.hourCount > 0, saved.sampleCount > 0,
              (try? AssertionCounterDecoder.decode(from: saved.assertion)) != nil,
              let body = try JSONSerialization.jsonObject(with: saved.body) as? [String: Any],
              let id = body["clientDiagnosticId"] as? String, UUID(uuidString: id) == saved.requestID,
              body["trustedDeviceSampleCount"] as? Int == saved.sampleCount else {
            throw PersonalCoverageError.invalidRequest
        }
    }
}
