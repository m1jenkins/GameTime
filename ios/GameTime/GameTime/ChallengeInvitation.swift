import Foundation
import Observation

/// Opaque locator only. No challenge details are fetched before authentication.
struct ChallengeInvitation: Equatable, Sendable {
    static let pathPrefix = "/challenge-invite/"
    let httpsOrigin: URL?
    private var formatsFixtureLinks = false

    /// No backend URL, bundle identifier or domain is inferred. Bad or missing
    /// configuration disables HTTPS intake and generation without blocking launch.
    init(httpsOrigin text: String? = nil) {
        httpsOrigin = Self.validatedOrigin(text)
    }

    /// Only explicit local previews/tests generate historical custom-scheme links.
    static let localFixture: Self = {
        var links = Self()
        links.formatsFixtureLinks = true
        return links
    }()

    var canFormat: Bool { httpsOrigin != nil || formatsFixtureLinks }

    func url(for token: String) -> URL? {
        guard Self.isValidToken(token) else { return nil }
        if let httpsOrigin {
            return URL(string: httpsOrigin.absoluteString + Self.pathPrefix + token)
        }
        guard formatsFixtureLinks else { return nil }
        return URL(string: "gametime-beta://challenge-invite/" + token)
    }

    func token(from text: String) -> String? {
        guard text.utf8.count < 1024,
              text.utf8.allSatisfy({ (33...126).contains($0) }),
              !text.contains("%"), !text.contains("\\"),
              let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), let host = parts.host?.lowercased(),
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.query == nil, parts.fragment == nil else { return nil }
        let path = parts.percentEncodedPath
        // Also reject empty ports and Foundation's repaired/ambiguous URLs.
        guard text.dropLast(path.count).lowercased() == "\(scheme)://\(host)" else { return nil }
        let prefix: String
        if scheme == "gametime-beta", host == "challenge-invite" {
            prefix = "/"
        } else {
            guard scheme == "https", let httpsOrigin, host == httpsOrigin.host else { return nil }
            prefix = Self.pathPrefix
        }
        guard path.hasPrefix(prefix) else { return nil }
        let token = String(path.dropFirst(prefix.count))
        return Self.isValidToken(token) ? token : nil
    }

    static func isValidToken(_ token: String) -> Bool {
        token.utf8.count == 64 && token.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }

    private static func validatedOrigin(_ text: String?) -> URL? {
        guard let text, text.utf8.count <= 261,
              let parts = URLComponents(string: text),
              parts.scheme?.lowercased() == "https", let host = parts.host?.lowercased(),
              host.contains("."), host.utf8.count <= 253 else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
        }), labels.last?.utf8.contains(where: { (97...122).contains($0) }) == true else { return nil }
        let origin = "https://" + host
        guard text.lowercased() == origin || text.lowercased() == origin + "/" else { return nil }
        return URL(string: origin)
    }
}

@MainActor @Observable final class ChallengeInvitationIntent {
    private let file: URL
    let links: ChallengeInvitation
    var link = ""
    var message: String?
    init(links: ChallengeInvitation = ChallengeInvitation(), directory: URL? = nil) {
        self.links = links
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GameTime/ChallengeInvitation")
        file = root.appendingPathComponent("pending.txt")
        if let data = try? Data(contentsOf: file), data.count < 1024, let saved = String(data: data, encoding: .utf8), links.token(from: saved) != nil { link = saved }
    }
    func receive(_ url: URL) {
        guard links.token(from: url.absoluteString) != nil else { return }
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(url.absoluteString.utf8).write(to: file, options: [.atomic, .completeFileProtection])
            var directory = file.deletingLastPathComponent(); var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            link = url.absoluteString; message = "Invitation saved. Sign in, confirm your age and choose Use invitation in Challenges."
        } catch { message = "We couldn’t save this invitation. Keep the link and try again after signing in." }
    }
    func clear() {
        do {
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            link = ""; message = nil
        } catch { message = "We couldn’t clear the saved invitation. Try again." }
    }
    func clear(ifMatching submittedLink: String) {
        guard link == submittedLink else { return }
        clear()
    }

    /// Used only after this device has durably accepted account deletion. The
    /// opaque invitation is intentionally not attributed to a later account.
    static func clearPersisted() throws {
        guard let root = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else { return }
        let file = root.appendingPathComponent("GameTime/ChallengeInvitation/pending.txt")
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        try FileManager.default.removeItem(at: file)
    }
}
