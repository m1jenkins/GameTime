import CryptoKit
import Foundation
import GameTimeCore

/// Private, backup-excluded comparison history. Raw snapshot/record types have
/// no serialization conformance. A restored baseline can only be compared with
/// a fresh bounded read for the exact same actor, binding, window and purpose.
@MainActor
final class ChallengeHealthComparisonCache {
    enum Failure: Error { case unavailable, corrupt, capacity }
    let directory: URL
    init(directory: URL) { self.directory = directory }
    static func applicationSupport() throws -> ChallengeHealthComparisonCache {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { throw Failure.unavailable }
        return Self(directory: root.appendingPathComponent("GameTime/ChallengeHealthComparisons", isDirectory: true))
    }
    func load(_ request: ChallengeHealthReadRequest) throws -> ChallengeHealthSnapshot? {
        let file = actorDirectory(request.binding.actorID).appendingPathComponent(try key(request) + ".json")
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let stored: StoredSnapshot = try decode(file)
        guard stored.version == 1, stored.binding == (try bindingBytes(request.binding)),
              stored.start == request.queryWindow.startMicroseconds, stored.end == request.queryWindow.endMicroseconds,
              stored.purpose == Self.purpose(request.purpose), stored.records.count <= WeeklySourceFeasibility.maximumRecords,
              let evidence = ChallengeHealthEvidence(rawValue: stored.evidence) else { throw Failure.corrupt }
        return ChallengeHealthSnapshot(request: request, records: try stored.records.map { try $0.record() },
            deletedRecordIDs: Set(stored.deleted), observedAt: stored.observed,
            sourceFreshness: stored.freshness, earliestAuthorizedSampleDate: stored.earliest, evidence: evidence)
    }
    func save(_ snapshot: ChallengeHealthSnapshot) throws {
        guard snapshot.records.count <= WeeklySourceFeasibility.maximumRecords else { throw Failure.capacity }
        let folder = actorDirectory(snapshot.request.binding.actorID)
        let file = folder.appendingPathComponent(try key(snapshot.request) + ".json")
        if FileManager.default.fileExists(atPath: folder.path), !FileManager.default.fileExists(atPath: file.path),
           try FileManager.default.contentsOfDirectory(atPath: folder.path).count >= 40 { throw Failure.capacity }
        try write(StoredSnapshot(version: 1, challengeID: snapshot.request.binding.challengeID, binding: bindingBytes(snapshot.request.binding),
            start: snapshot.request.queryWindow.startMicroseconds, end: snapshot.request.queryWindow.endMicroseconds,
            purpose: Self.purpose(snapshot.request.purpose), observed: snapshot.observedAt, freshness: snapshot.sourceFreshness,
            earliest: snapshot.earliestAuthorizedSampleDate, evidence: snapshot.evidence.rawValue,
            records: snapshot.records.map(StoredRecord.init), deleted: Array(snapshot.deletedRecordIDs)), to: file)
    }
    func connected(actor: UUID) throws -> Set<String> { Set(try state(actor).connected) }
    func connect(actor: UUID, source: String) throws {
        var state = try state(actor); state.connected = Array(Set(state.connected + [source])).sorted()
        try write(state, to: stateURL(actor))
    }
    func pending(actor: UUID) throws -> Set<UUID> { Set(try state(actor).pending) }
    func enqueue(actor: UUID, ids: Set<UUID>) throws {
        var state = try state(actor); state.pending = Array(Set(state.pending).union(ids))
        guard state.pending.count <= 64 else { throw Failure.capacity }
        try write(state, to: stateURL(actor))
    }
    func acknowledge(actor: UUID, id: UUID) throws {
        var state = try state(actor); state.pending.removeAll { $0 == id }; try write(state, to: stateURL(actor))
    }
    func retire(actor: UUID, id: UUID) throws {
        let folder = actorDirectory(actor)
        guard FileManager.default.fileExists(atPath: folder.path) else { return }
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            where file.lastPathComponent != "work.json" {
            let snapshot: StoredSnapshot = try decode(file)
            if snapshot.challengeID == id { try FileManager.default.removeItem(at: file) }
        }
    }
    func clear(actor: UUID) throws {
        let folder = actorDirectory(actor)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }
    func key(_ request: ChallengeHealthReadRequest) throws -> String {
        let scope = try bindingBytes(request.binding) + Data("|\(request.queryWindow.startMicroseconds)|\(request.queryWindow.endMicroseconds)|\(Self.purpose(request.purpose))".utf8)
        return SHA256.hash(data: scope).map { String(format: "%02x", $0) }.joined()
    }
    private func bindingBytes(_ binding: ChallengeHealthBinding) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(binding)
    }
    private static func purpose(_ purpose: ChallengeHealthReadRequest.Purpose) -> String {
        switch purpose { case .challengeActivity: "activity"; case .readinessHistory: "readiness"; case .suggestionHistory: "suggestion" }
    }
    private func actorDirectory(_ actor: UUID) -> URL { directory.appendingPathComponent(actor.uuidString.lowercased(), isDirectory: true) }
    private func stateURL(_ actor: UUID) -> URL { actorDirectory(actor).appendingPathComponent("work.json") }
    private func state(_ actor: UUID) throws -> Work {
        let file = stateURL(actor)
        guard FileManager.default.fileExists(atPath: file.path) else { return Work(version: 1, actor: actor, connected: [], pending: []) }
        let saved: Work = try decode(file)
        guard saved.version == 1, saved.actor == actor, saved.pending.count <= 64, saved.connected.count <= 8 else { throw Failure.corrupt }
        return saved
    }
    private func decode<T: Decodable>(_ file: URL) throws -> T {
        do {
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            guard (values.fileSize ?? Int.max) <= 16 * 1024 * 1024 else { throw Failure.corrupt }
            return try JSONDecoder().decode(T.self, from: Data(contentsOf: file))
        } catch { throw Failure.unavailable }
    }
    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            let bytes = try JSONEncoder().encode(value)
            guard bytes.count <= 16 * 1024 * 1024 else { throw Failure.capacity }
            var folder = url.deletingLastPathComponent(), file = url
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var resource = URLResourceValues(); resource.isExcludedFromBackup = true
            try folder.setResourceValues(resource)
            try bytes.write(to: file, options: [.atomic, .completeFileProtection])
            try file.setResourceValues(resource)
        } catch { throw Failure.unavailable }
    }
    private struct Work: Codable { let version: Int; let actor: UUID; var connected: [String]; var pending: [UUID] }
    private struct StoredSnapshot: Codable {
        let version: Int; let challengeID: UUID; let binding: Data; let start: Int64; let end: Int64; let purpose: String
        let observed: Date; let freshness: Date?; let earliest: Date?; let evidence: String
        let records: [StoredRecord]; let deleted: [UUID]
    }
    // Source/device display names, routes and OS/app versions are unnecessary
    // for disappearance and sync-revision comparison and are deliberately absent.
    private struct StoredRecord: Codable {
        let id: UUID; let metric: String; let start: Date; let end: Date; let value: Double
        let writer: String?; let product: String?; let manual: Bool?; let sync: String?; let revision: Int?
        let workout: String?; let indoor: Bool?
        init(_ record: WeeklySourceRecord) {
            id = record.id; metric = record.metric.rawValue; start = record.start; end = record.end; value = record.value
            writer = record.sourceBundleIdentifier; product = record.sourceProductType; manual = record.wasUserEntered
            sync = record.syncIdentifier; revision = record.syncVersion; workout = record.workoutActivityType; indoor = record.wasIndoorWorkout
        }
        func record() throws -> WeeklySourceRecord {
            guard let metric = WeeklySourceMetric(rawValue: metric), value.isFinite, value >= 0, start <= end else { throw Failure.corrupt }
            return WeeklySourceRecord(id: id, metric: metric, start: start, end: end, value: value,
                sourceBundleIdentifier: writer, sourceProductType: product, wasUserEntered: manual,
                syncIdentifier: sync, syncVersion: revision, workoutActivityType: workout, wasIndoorWorkout: indoor)
        }
    }
}
