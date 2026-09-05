import Foundation

struct DuelInvitationDestination: Decodable, Sendable {
    let challengeId: UUID
}

struct DuelInvitationLink: Codable, Equatable, Sendable {
    let challengeId: UUID
    let token: UUID
    let expiresAt: DuelInstant
    var url: URL { Self.url(token: token) }

    // Local opt-in app route. No hosted domain or universal-link entitlement.
    static func url(token: UUID) -> URL {
        URL(string: "gametime-duel://invitation/\(token.uuidString.lowercased())")!
    }

    static func token(from url: URL) -> UUID? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "gametime-duel", parts.host == "invitation",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil,
              parts.percentEncodedPath == parts.path,
              parts.path.count == 37,
              let token = UUID(uuidString: String(parts.path.dropFirst())),
              url.absoluteString == Self.url(token: token).absoluteString else { return nil }
        return token
    }
}
