#if DEBUG
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import GameTime

/// Native, model-backed renders. Fixture responses never report mutation success.
/// These supplement the authenticated touch journeys; they are not VoiceOver proof.
@MainActor final class CobaltRenderedTests: XCTestCase {
    func testHomeHierarchyAtCurrentCompactDarkAndAccessibilitySizes() async throws {
        let italic = try XCTUnwrap(UIFont(name: "BarlowCondensed-BlackItalic", size: 48))
        XCTAssertTrue(italic.fontDescriptor.symbolicTraits.contains(.traitItalic), "The display face must render a real italic font")
        let fixture = CobaltFixture(); defer { fixture.clean() }
        fixture.rows = [fixture.row("personal_exercise_goal_v1"),
                        fixture.row("friend_steps_leaderboard_v1"),
                        fixture.row("personal_distance_goal_v1", status: "scheduled")]
        try await fixture.start()
        for (name, width, height, scheme, type) in [
            ("home", 430.0, 932.0, ColorScheme.light, DynamicTypeSize.large),
            ("home-compact", 375.0, 812.0, .light, .large),
            ("home-dark", 430.0, 932.0, .dark, .large),
            ("home-accessibility", 375.0, 812.0, .light, .accessibility3)
        ] {
            try await capture(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {})
                .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, type),
                name: name, width: width, height: height,
                // The iOS 18 OCR model reads the white condensed G as C. The
                // named font is checked above; UI tests check the actual header
                // label. Keep the visual header anchor and all metric checks.
                required: ["home", "home-dark"].contains(name) ? ["New challenge", "42,850", "95", "20 km", "Your next goal"] : ["New challenge"])
        }
    }

    func testAllMetricsAndCommunityPrivacyRenderFromValidatedRows() async throws {
        let fixture = CobaltFixture(); defer { fixture.clean() }
        for policy in ChallengeV1Policy.all {
            let row = fixture.row(policy.id)
            fixture.rows = [row]; try await fixture.start()
            let required = policy.metric == .timed ? ["km"] : [policy.metric == .steps ? "steps" : policy.metric == .exercise ? "min" : "km"]
            try await capture(NavigationStack { ChallengeV1Detail(store: fixture.store, id: row.id) },
                              name: policy.id, height: 3000, required: required,
                              forbidden: policy.mode == .community ? ["Maya", "Jordan", "4 people joined"] : [])
            if policy.mode == .personal || policy.competition == .leaderboard {
                XCTAssertEqual(row.members.allSatisfy { $0.target == nil }, !policy.hasTarget)
            }
        }
    }

    func testCommunityDelayedCountsInDetailAndJoin() async throws {
        let fixture = CobaltFixture(); defer { fixture.clean() }
        var row = fixture.row("community_steps_goal_v1")
        let snapshot = ChallengeInstant(date: row.serverTime.date.addingTimeInterval(-900))
        row.counts = .init(joined: 5, state: "available", asOf: snapshot)
        fixture.rows = [row]; try await fixture.start()
        try await capture(NavigationStack { ChallengeV1Detail(store: fixture.store, id: row.id) },
                          name: "community-mature-detail", height: 2400,
                          required: ["5 people joined", "15 minutes ago", "assigned moderator", "Report unsafe behavior"], forbidden: ["Maya", "Jordan"])
        let community = ChallengeV1Community(id: row.id, terms: .object(["common_target": .integer(50000)]), digest: "fixture", serverTime: row.serverTime, joinedCount: 5, counts: row.counts)
        try await capture(NavigationStack { ChallengeCommunityJoin(store: fixture.store, community: community) },
                          name: "community-mature-join", required: ["5 people joined", "Join community challenge"])
        row.counts = .init(joined: nil, state: "threshold", asOf: nil)
        fixture.rows = [row]; try await fixture.start()
        try await capture(NavigationStack { ChallengeV1Detail(store: fixture.store, id: row.id) },
                          name: "community-threshold-detail", height: 2400,
                          required: ["Participant totals stay hidden"], forbidden: ["5 people joined", "Maya", "Jordan"])
    }

    func testUnknownCorrectedTiedRedactedAndRecoveryPresentation() async throws {
        let fixture = CobaltFixture(); defer { fixture.clean() }
        let row = fixture.row("friend_steps_leaderboard_v1", edge: true)
        fixture.rows = [row]; try await fixture.start()
        try await capture(NavigationStack { ChallengeV1Detail(store: fixture.store, id: row.id) },
                          name: "leaderboard-unknown-tied-departed", height: 3200,
                          required: ["No update yet", "Former participant", "Activity hidden"], forbidden: ["Private name"])
        fixture.rows = []; try await fixture.start()
        try await capture(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}),
                          name: "home-empty", required: ["No challenges yet", "Explore challenges"])
        fixture.rows = [row]; try await fixture.start()
        let request = ChallengeV1Request(actor: fixture.actor, payload: .object(["op": .string("leave"), "id": .string(row.id.uuidString.lowercased()), "revision": .integer(1)]))
        try await fixture.store.requests.save(request)
        await fixture.store.refresh()
        fixture.fail = true; await fixture.store.refresh()
        try await capture(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}),
                          name: "home-stale-recovery", height: 2200,
                          required: ["Retry saved action", "Last saved view", "No update yet"])
        fixture.store.setActor(fixture.actor)
        try await capture(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}),
                          name: "home-loading", required: ["Loading your challenges"])
        await fixture.store.refresh()
        try await capture(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}),
                          name: "home-unavailable", required: ["Refresh to try again"])
    }

    private func capture<V: View>(_ view: V, name: String, width: CGFloat = 430, height: CGFloat = 932,
                                 required: [String] = [], forbidden: [String] = []) async throws {
        let host = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(300))
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { host.view.layer.render(in: $0.cgContext) }
        let cg = try XCTUnwrap(image.cgImage)
        var lines: [String] = []
        for y in stride(from: 0, to: cg.height, by: 550) {
            let tile = try XCTUnwrap(cg.cropping(to: CGRect(x: 0, y: y, width: cg.width, height: min(700, cg.height - y))))
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            request.customWords = ["GameTime"]
            request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
            try VNImageRequestHandler(cgImage: tile).perform([request])
            lines += (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        let text = lines.joined(separator: " ").lowercased()
        // Vision may split the condensed wordmark into "Game Time". Ignore
        // OCR whitespace for presence checks, including privacy exclusions.
        let searchable = text.filter { !$0.isWhitespace }
        let attachment = XCTAttachment(image: image); attachment.name = "cobalt-" + name; attachment.lifetime = .keepAlways; add(attachment)
        let transcription = XCTAttachment(string: text); transcription.name = "cobalt-" + name + "-text"; transcription.lifetime = .keepAlways; add(transcription)
        for value in required { XCTAssertTrue(searchable.contains(value.lowercased().filter { !$0.isWhitespace }), "Missing rendered text: \(value)") }
        for value in forbidden { XCTAssertFalse(searchable.contains(value.lowercased().filter { !$0.isWhitespace }), "Private text rendered: \(value)") }
    }
}

@MainActor private final class CobaltFixture: ChallengeV1Client, AuthClient {
    let actor = UUID(), maya = UUID(), jordan = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cobalt-render-" + UUID().uuidString)
    var rows: [ChallengeV1] = [], fail = false
    lazy var store = ChallengeV1Store(auth: self, client: self, requests: ChallengeV1RequestStore(directory: directory), now: { 0 })
    func clean() { store.hide(); try? FileManager.default.removeItem(at: directory) }
    func start() async throws {
        for row in rows { try row.validate(actor: actor) }
        store.setActor(actor); await store.refresh(); XCTAssertNil(store.error)
    }
    func row(_ policy: String, status: String = "active", edge: Bool = false) -> ChallengeV1 {
        let format = ChallengeV1Policy(rawValue: policy)!
        let start = ChallengeInstant(date: Date(timeIntervalSince1970: 1788757200 + (status == "scheduled" ? 7 * 86400 : 0)))
        let end = ChallengeInstant(date: start.date.addingTimeInterval(7 * 86400))
        let values: [Int] = format.metric == .steps ? [42850, 38620, 35400] : format.metric == .exercise ? [120 * 60, 95 * 60, 80 * 60] : format.metric == .distance ? [18_500_000, 15_300_000, 12_200_000] : [1500, 1531, 1600]
        let target = format.metric == .steps ? 50_000 : format.metric == .exercise ? 150 * 60 : format.metric == .distance ? 20_000_000 : 1800
        var members = zip([maya, actor, jordan], ["Maya", "Fictional You", "Jordan"]).enumerated().map { index, person in
            ChallengeV1.Member(actorId: person.0, username: person.1, target: format.hasTarget ? target : nil,
                               selected: true, exited: false, consented: true,
                               fact: status == "scheduled" ? nil : .init(value: values[index], state: "complete", recordedAt: start, revision: 1))
        }
        if format.mode != .friend { members = members.filter { $0.actorId == actor } }
        if edge {
            members = [members[0], .init(actorId: actor, username: "Fictional You", target: nil, selected: true, exited: false, consented: true, fact: nil),
                       .init(actorId: jordan, username: "Jordan", target: nil, selected: true, exited: false, consented: true, fact: members[0].fact),
                       .init(actorId: UUID(), username: "", target: nil, selected: true, exited: true, consented: true, fact: nil)]
        }
        return .init(counts: format.mode == .community ? .init(joined: 4) : nil, id: UUID(), creatorId: actor, policy: policy,
                     config: .init(startDate: status == "scheduled" ? "2026-09-14" : "2026-09-07", days: 7, timezone: "America/Chicago", amountCents: 2000, distanceMm: format.metric == .timed ? 5_000_000 : nil,
                                   startsAt: start, endsAt: end, syncBy: end, correctionsBy: end, noticeDue: end),
                     status: status, revision: 1, agreementVersion: 1, serverTime: start, socialHidden: format.mode == .community,
                     agreement: nil, members: members, notice: nil, reviews: [], final: nil)
    }
    func page(_ section: ChallengeV1Section, cursor: ChallengeJSON?, actor: UUID) async throws -> ChallengeV1Page {
        if fail { throw ChallengeV1Error.unavailable }
        return .init(section: section, projectionRevision: UUID(), serverTime: .init(date: Date()), expiresAt: .init(date: Date().addingTimeInterval(120)),
                     rows: rows.filter { section.includes($0, actor: actor) }, nextCursor: nil)
    }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 { if fail { throw ChallengeV1Error.unavailable }; return try XCTUnwrap(rows.first { $0.id == id }) }
    func list(actor: UUID) async throws -> [ChallengeV1] { rows }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        if name == "challenge_access_status_v1" { return ChallengeV1Access(serverTime: nil, ageConfirmed: true, betaAccess: true, suspended: false) as! T }
        if name == "challenge_community_catalog_v1" { return [ChallengeV1Community]() as! T }
        throw ChallengeV1Error.unavailable
    }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor }
    func signOut() async throws {}
}
#endif
