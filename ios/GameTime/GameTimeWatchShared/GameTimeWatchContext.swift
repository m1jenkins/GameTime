import Foundation

struct GameTimeWatchHandshake: Equatable, Sendable {
    let sentAt: Date
}

enum GameTimeWatchContext {
    nonisolated static let schemaVersion = 1

    nonisolated private static let schemaVersionKey = "schema_version"
    nonisolated private static let kindKey = "kind"
    nonisolated private static let sentAtKey = "sent_at"
    nonisolated private static let readyKind = "phone_ready"

    nonisolated static func ready(sentAt: Date = .now) -> [String: Any] {
        [
            schemaVersionKey: schemaVersion,
            kindKey: readyKind,
            sentAtKey: sentAt.timeIntervalSince1970,
        ]
    }

    nonisolated static func decode(
        _ applicationContext: [String: Any]
    ) -> GameTimeWatchHandshake? {
        guard
            applicationContext[schemaVersionKey] as? Int == schemaVersion,
            applicationContext[kindKey] as? String == readyKind,
            let timestamp = applicationContext[sentAtKey] as? TimeInterval,
            timestamp.isFinite,
            timestamp > 0
        else {
            return nil
        }

        return GameTimeWatchHandshake(
            sentAt: Date(timeIntervalSince1970: timestamp)
        )
    }
}
