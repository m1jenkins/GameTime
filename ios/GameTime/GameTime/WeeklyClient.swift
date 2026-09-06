import Foundation

enum WeeklyReviewReason: String, Codable, CaseIterable, Sendable {
    case wrongTotal = "wrong_total", sourceProblem = "source_problem", wrongResult = "wrong_result"
    var title: String {
        switch self { case .wrongTotal: "My steps are wrong"; case .sourceProblem: "My step updates are missing"; case .wrongResult: "My result is wrong" }
    }
}
enum WeeklySupportReason: String, Codable, CaseIterable, Sendable {
    case correction, privacy, unwantedContact = "unwanted_contact", exitHelp = "exit_help"
    var title: String {
        switch self { case .correction: "Correct a saved result"; case .privacy: "Privacy concern"; case .unwantedContact: "Unwanted contact"; case .exitHelp: "Help leaving a challenge" }
    }
}
enum WeeklyExitKind: String, Codable, Sendable { case decline, cancel, withdrawal, injury }
enum WeeklyFollowDecision: String, Codable, Sendable { case accept, decline, unfollow }
enum WeeklyMutation: Codable, Equatable, Sendable {
    case create(WeeklyPreview)
    case accept(UUID, digest: String)
    case join(UUID, digest: String)
    case exit(UUID, kind: WeeklyExitKind)
    case review(UUID, revision: Int, reason: WeeklyReviewReason)
    case support(UUID, reason: WeeklySupportReason)
    case pause(Bool)
    case pilotConsent(Bool)
    case progress(UUID, day: String, steps: Int)
    case share(UUID, friendID: UUID, enabled: Bool)
    case follow(UUID, ownerID: UUID, offerID: UUID, decision: WeeklyFollowDecision)
    var rpc: String {
        switch self {
        case .create: "create_weekly_friend_v1"
        case .accept: "accept_weekly_v1"
        case .join: "join_weekly_cohort_v1"
        case .exit: "exit_weekly_v1"
        case .review: "file_weekly_review_v1"
        case .support: "submit_weekly_support_v1"
        case .pause: "set_weekly_entry_pause_v1"
        case .pilotConsent: "set_weekly_pilot_consent_v1"
        case .progress: "record_weekly_progress_v1"
        case .share: "set_weekly_sharing_v1"
        case .follow: "respond_weekly_follow_v1"
        }
    }
    var challengeID: UUID? {
        switch self { case .create, .pause, .pilotConsent: nil; case .accept(let id, _), .join(let id, _), .exit(let id, _), .review(let id, _, _), .support(let id, _), .progress(let id, _, _), .share(let id, _, _), .follow(let id, _, _, _): id }
    }
    var summary: String {
        switch self {
        case .create: "Create a weekly friend challenge"
        case .accept: "Accept a weekly invitation"
        case .join: "Join the community week"
        case .exit: "Leave this weekly challenge"
        case .review: "Ask us to review a weekly result"
        case .support: "Save your support request"
        case .pause(let paused): paused ? "Pause new weekly entries" : "Allow new weekly entries"
        case .pilotConsent(let enabled): enabled ? "Allow optional local study records" : "Remove optional local study records"
        case .progress: "Save a practice step update"
        case .share(_, _, let enabled): enabled ? "Offer selected practice progress" : "Stop sharing practice progress"
        case .follow(_, _, _, let decision): decision == .accept ? "Follow selected practice progress" : "Stop following practice progress"
        }
    }
    func body(requestID: UUID) throws -> Data {
        var p: [String: WeeklyJSON] = ["p_request_id": .string(requestID.uuidString.lowercased())]
        if let challengeID { p["p_challenge_id"] = .string(challengeID.uuidString.lowercased()) }
        switch self {
        case .create(let preview):
            p["p_terms"] = preview.terms.raw; p["p_expected_terms_digest"] = .string(preview.termsDigest); p["p_consent"] = .bool(true)
        case .accept(_, let digest), .join(_, let digest): p["p_expected_terms_digest"] = .string(digest); p["p_consent"] = .bool(true)
        case .exit(_, let kind): p["p_kind"] = .string(kind.rawValue)
        case .review(_, let revision, let reason): p["p_notice_revision"] = .integer(revision); p["p_reason"] = .string(reason.rawValue)
        case .support(_, let reason): p["p_reason"] = .string(reason.rawValue)
        case .pause(let paused): p["p_paused"] = .bool(paused)
        case .pilotConsent(let enabled): p["p_enabled"] = .bool(enabled)
        case .progress(_, let day, let steps): p["p_day"] = .string(day); p["p_steps"] = .integer(steps)
        case .share(_, let friend, let enabled): p["p_friend_id"] = .string(friend.uuidString.lowercased()); p["p_enabled"] = .bool(enabled)
        case .follow(_, let owner, let offer, let decision): p["p_owner_id"] = .string(owner.uuidString.lowercased()); p["p_offer_id"] = .string(offer.uuidString.lowercased()); p["p_decision"] = .string(decision.rawValue)
        }
        return try WeeklyJSON.data(.object(p))
    }
}

struct PendingWeeklyRequest: Codable, Equatable, Sendable {
    let kind: String; let version: Int; let actorID: UUID; let requestID: UUID
    let operation: WeeklyMutation; let requestBody: Data
    var mayHaveCommitted: Bool
    init(actorID: UUID, requestID: UUID = UUID(), operation: WeeklyMutation) throws {
        kind = "weekly_request_v1"; version = 1; self.actorID = actorID; self.requestID = requestID
        self.operation = operation; requestBody = try operation.body(requestID: requestID); mayHaveCommitted = false
        try validate(for: actorID)
    }
    func validate(for actorID: UUID) throws {
        guard kind == "weekly_request_v1", version == 1, self.actorID == actorID,
              requestBody.count <= 131_072, requestBody == (try operation.body(requestID: requestID)) else { throw WeeklyClientError.storage }
        switch operation {
        case .create(let preview):
            try preview.terms.validate()
            guard !preview.terms.fields.isCommunity, preview.terms.fields.creatorId == actorID,
                  (2...5).contains(preview.terms.fields.participants?.count ?? 0), WeeklyModel.isDigest(preview.termsDigest) else { throw WeeklyClientError.storage }
        case .accept(_, let digest), .join(_, let digest): guard WeeklyModel.isDigest(digest) else { throw WeeklyClientError.storage }
        case .review(_, let revision, _): guard (0...Int(Int32.max)).contains(revision) else { throw WeeklyClientError.storage }
        case .progress(_, let day, let steps): guard day.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil, (0...1_000_000).contains(steps) else { throw WeeklyClientError.storage }
        case .share(_, let friend, _), .follow(_, let friend, _, _): guard friend != actorID else { throw WeeklyClientError.storage }
        case .exit, .support, .pause, .pilotConsent: break
        }
    }
    func allowsReplacement(by next: Self) -> Bool {
        actorID == next.actorID && requestID == next.requestID && operation == next.operation && requestBody == next.requestBody && (!mayHaveCommitted || next.mayHaveCommitted)
    }
}

enum WeeklyClientError: LocalizedError, Equatable, Sendable {
    case accessDenied, invalidTerms, conflict, lifecycle, accountChanged, invalidResponse, unavailable, storage
    static func sqlState(_ code: String?) -> Self {
        switch code { case "42501": .accessDenied; case "22023": .invalidTerms; case "23505": .conflict; case "55000": .lifecycle; default: .unavailable }
    }
    var definitive: Bool { [.accessDenied, .invalidTerms, .conflict, .lifecycle].contains(self) }
    var errorDescription: String? {
        switch self {
        case .accessDenied: "We couldn’t allow that weekly action. Refresh to see your current choices; your saved reviews and exits remain available."
        case .invalidTerms: "These weekly rules changed or couldn’t be used. Refresh and review them again."
        case .conflict: "This entry overlaps another week, reached a limit, or is already saved. Refresh to see what you can do next."
        case .lifecycle: "This week changed or the action’s deadline passed. Refresh to see its current status."
        case .accountChanged: "Your account changed. Return to weekly challenges after signing in."
        case .storage: "We couldn’t save your weekly request on this phone. Unlock your phone and try again."
        case .invalidResponse, .unavailable: "We couldn’t confirm your weekly update. Check your connection, refresh, or retry the same saved request."
        }
    }
}

@MainActor protocol WeeklyClient: AnyObject {
    func preview(_ draft: WeeklyDraft, actorID: UUID) async throws -> WeeklyPreview
    func list(actorID: UUID) async throws -> [WeeklyChallenge]
    func detail(id: UUID, actorID: UUID) async throws -> WeeklyChallenge
    func cohorts(actorID: UUID) async throws -> [WeeklyCohort]
    func preferences(actorID: UUID) async throws -> WeeklyPreferences
    func submit(_ request: PendingWeeklyRequest) async throws -> UUID
    func resolveRequest(_ request: PendingWeeklyRequest) async throws -> WeeklyRequestResolution
    func sharing(id: UUID, actorID: UUID) async throws -> [WeeklySharing]
    func sharedProgress(actorID: UUID) async throws -> [WeeklySharedProgress]
    func followRequests(actorID: UUID) async throws -> [WeeklyFollowRequest]
    func recordPilotEvent(actorID: UUID, challengeID: UUID?, event: String, phase: String, requestID: UUID) async throws
}
extension WeeklyClient {
    func followRequests(actorID: UUID) async throws -> [WeeklyFollowRequest] { [] }
    func sharing(id: UUID, actorID: UUID) async throws -> [WeeklySharing] { [] }
    func sharedProgress(actorID: UUID) async throws -> [WeeklySharedProgress] { [] }
    func recordPilotEvent(actorID: UUID, challengeID: UUID?, event: String, phase: String, requestID: UUID) async throws { throw WeeklyClientError.unavailable }
}
struct WeeklyRequestResolution: Decodable, Equatable, Sendable {
    let state: String
    let receiptID: UUID?
    enum CodingKeys: String, CodingKey { case state, receiptID = "receipt_id" }
}
@MainActor final class DisabledWeeklyClient: WeeklyClient {
    func preview(_ draft: WeeklyDraft, actorID: UUID) async throws -> WeeklyPreview { throw WeeklyClientError.accessDenied }
    func list(actorID: UUID) async throws -> [WeeklyChallenge] { throw WeeklyClientError.accessDenied }
    func detail(id: UUID, actorID: UUID) async throws -> WeeklyChallenge { throw WeeklyClientError.accessDenied }
    func cohorts(actorID: UUID) async throws -> [WeeklyCohort] { throw WeeklyClientError.accessDenied }
    func preferences(actorID: UUID) async throws -> WeeklyPreferences { throw WeeklyClientError.accessDenied }
    func submit(_ request: PendingWeeklyRequest) async throws -> UUID { throw WeeklyClientError.accessDenied }
    func resolveRequest(_ request: PendingWeeklyRequest) async throws -> WeeklyRequestResolution { throw WeeklyClientError.accessDenied }
}
