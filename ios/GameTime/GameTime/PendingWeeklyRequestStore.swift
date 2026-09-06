import Foundation

protocol PendingWeeklyRequestStore: AnyObject, Sendable {
    func load(for actorID: UUID) async throws -> PendingWeeklyRequest?
    func save(_ request: PendingWeeklyRequest) async throws
    func remove(for actorID: UUID, matching requestID: UUID?) async throws
}

actor FilePendingWeeklyRequestStore: PendingWeeklyRequestStore {
    private let directory: URL
    private var deletedActors: Set<UUID> = []

    init(directory: URL) { self.directory = directory }

    static func applicationSupport() throws -> FilePendingWeeklyRequestStore {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { throw WeeklyClientError.storage }
        return FilePendingWeeklyRequestStore(directory: root
            .appendingPathComponent("GameTime/PendingWeekly", isDirectory: true))
    }

    func load(for actorID: UUID) throws -> PendingWeeklyRequest? {
        guard !deletedActors.contains(actorID) else { return nil }
        let url = file(actorID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            guard data.count <= 262_144 else { throw WeeklyClientError.storage }
            let request = try JSONDecoder().decode(PendingWeeklyRequest.self, from: data)
            try request.validate(for: actorID)
            return request
        } catch { throw WeeklyClientError.storage }
    }

    func save(_ request: PendingWeeklyRequest) throws {
        guard !deletedActors.contains(request.actorID) else { throw WeeklyClientError.storage }
        try request.validate(for: request.actorID)
        do {
            if let existing = try load(for: request.actorID),
                !existing.allowsReplacement(by: request) { throw WeeklyClientError.storage }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try excludeFromBackup(directory)
            let data = try JSONEncoder().encode(request)
            try data.write(to: file(request.actorID), options: [.atomic, .completeFileProtection])
            try excludeFromBackup(file(request.actorID))
        } catch { throw WeeklyClientError.storage }
    }

    func remove(for actorID: UUID, matching requestID: UUID?) throws {
        // Deletion cleanup fences any queued writes for this store instance.
        if requestID == nil { deletedActors.insert(actorID) }
        if let requestID, try load(for: actorID)?.requestID != requestID { return }
        guard FileManager.default.fileExists(atPath: file(actorID).path) else { return }
        do { try FileManager.default.removeItem(at: file(actorID)) }
        catch { throw WeeklyClientError.storage }
    }

    private func file(_ actorID: UUID) -> URL {
        directory.appendingPathComponent("\(actorID.uuidString.lowercased()).json")
    }

    private func excludeFromBackup(_ url: URL) throws {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }
}

actor EphemeralPendingWeeklyRequestStore: PendingWeeklyRequestStore {
    private var requests: [UUID: PendingWeeklyRequest] = [:]
    func load(for actorID: UUID) -> PendingWeeklyRequest? { requests[actorID] }
    func save(_ request: PendingWeeklyRequest) throws {
        try request.validate(for: request.actorID)
        if let existing = requests[request.actorID], !existing.allowsReplacement(by: request) {
            throw WeeklyClientError.storage
        }
        requests[request.actorID] = request
    }
    func remove(for actorID: UUID, matching requestID: UUID?) {
        if requestID == nil || requests[actorID]?.requestID == requestID { requests[actorID] = nil }
    }
}
