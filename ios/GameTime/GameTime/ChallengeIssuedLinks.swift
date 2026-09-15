import Foundation

/// Locators already issued to this actor, never challenge activity or consent.
/// Keep the issuing request/challenge association when a view or app is recreated.
struct ChallengeIssuedLink: Codable, Equatable, Identifiable, Sendable {
    let actorId: UUID
    let challengeId: UUID
    let requestId: UUID
    let id: UUID
    let token: String
    let expiresAt: ChallengeInstant
}

extension ChallengeV1RequestStore {
    private struct IssuedLinksFile: Codable, Sendable {
        let version: Int
        let actorId: UUID
        let links: [ChallengeIssuedLink]
    }

    func loadIssuedLinks(_ actor: UUID) throws -> [ChallengeIssuedLink] {
        let file = issuedLinksPath(actor)
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        do {
            let data = try Data(contentsOf: file)
            guard data.count <= 2_000_000 else { throw ChallengeV1Error.storage }
            let saved = try JSONDecoder().decode(IssuedLinksFile.self, from: data)
            guard saved.version == 1, saved.actorId == actor,
                  Set(saved.links.map(\.id)).count == saved.links.count,
                  Set(saved.links.map(\.requestId)).count == saved.links.count,
                  saved.links.allSatisfy({ $0.actorId == actor && ChallengeInvitation.token(from: "gametime-beta://challenge-invite/" + $0.token) == $0.token })
            else { throw ChallengeV1Error.storage }
            return saved.links
        } catch { throw ChallengeV1Error.storage }
    }

    /// Persist before clearing the pending request. A failed local write keeps
    /// exact recovery available instead of orphaning the server-issued locator.
    func recordIssuedLinkReceipt(_ receipt: ChallengeV1Receipt, for request: ChallengeV1Request) throws -> [ChallengeIssuedLink]? {
        guard let op = request.payload["op"]?.string, ["issue_link", "revoke_link"].contains(op) else { return nil }
        var links = try loadIssuedLinks(request.actorId)
        if receipt.status == "cancelled_request" { return links }
        guard let targetText = request.payload["id"]?.string, let target = UUID(uuidString: targetText)
        else { throw ChallengeV1Error.invalidResponse }
        if op == "issue_link" {
            guard let id = receipt.id, let token = receipt.token, let expiry = receipt.expiresAt,
                  ChallengeInvitation.token(from: "gametime-beta://challenge-invite/" + token) == token
            else { throw ChallengeV1Error.invalidResponse }
            let link = ChallengeIssuedLink(actorId: request.actorId, challengeId: target, requestId: request.requestId,
                id: id, token: token, expiresAt: expiry)
            if let saved = links.first(where: { $0.id == id || $0.requestId == request.requestId }) {
                guard saved == link else { throw ChallengeV1Error.invalidResponse }
                return links
            }
            links.append(link)
        } else {
            guard receipt.revoked == true else { throw ChallengeV1Error.invalidResponse }
            links.removeAll { $0.id == target }
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(IssuedLinksFile(version: 1, actorId: request.actorId, links: links))
            guard data.count <= 2_000_000 else { throw ChallengeV1Error.storage }
            try data.write(to: issuedLinksPath(request.actorId), options: [.atomic, .completeFileProtection])
            var root = directory; var values = URLResourceValues(); values.isExcludedFromBackup = true
            try root.setResourceValues(values)
            return links
        } catch { throw ChallengeV1Error.storage }
    }

    func issuedLinksPath(_ actor: UUID) -> URL {
        directory.appendingPathComponent(actor.uuidString.lowercased() + "-issued-links.json")
    }
}
