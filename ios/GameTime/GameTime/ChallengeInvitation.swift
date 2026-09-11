import Foundation
import Observation

/// Opaque locator only. No challenge details are fetched before authentication.
enum ChallengeInvitation {
    static func token(from text: String) -> String? {
        guard let url = URL(string: text), url.scheme == "gametime-beta", url.host == "challenge-invite",
              url.user == nil, url.password == nil, url.port == nil, url.query == nil, url.fragment == nil else { return nil }
        let value = String(url.path.dropFirst())
        guard value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { return nil }
        return value
    }
}

@MainActor @Observable final class ChallengeInvitationIntent {
    private let file: URL
    var link = ""
    var message: String?
    init(directory: URL? = nil) {
        let root = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("GameTime/ChallengeInvitation")
        file = root.appendingPathComponent("pending.txt")
        if let data = try? Data(contentsOf: file), data.count < 1024, let saved = String(data: data, encoding: .utf8), ChallengeInvitation.token(from: saved) != nil { link = saved }
    }
    func receive(_ url: URL) {
        guard ChallengeInvitation.token(from: url.absoluteString) != nil else { return }
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
}
