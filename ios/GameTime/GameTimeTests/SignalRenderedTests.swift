#if DEBUG
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import GameTime

/// Native, model-backed renders. Fixture responses never report mutation success.
/// These supplement the authenticated touch journeys; they are not VoiceOver proof.
@MainActor final class SignalRenderedTests: XCTestCase {
    func testHomeHierarchyAtCurrentCompactDarkAndAccessibilitySizes() async throws {
        let fixture = SignalFixture(); defer { fixture.clean() }
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
                required: ["GameTime", "Today", "Simulated"])
        }
    }

    func testAllMetricsAndCommunityPrivacyRenderFromValidatedRows() async throws {
        let fixture = SignalFixture(); defer { fixture.clean() }
        for policy in ChallengeV1Policy.all {
            let row = fixture.row(policy.id)
            fixture.rows = [row]; try await fixture.start()
            let required = policy.metric == .timed ? ["km"] : [policy.metric == .steps ? "steps" : policy.metric == .exercise ? "min" : "km"]
            try await capture(NavigationStack { ChallengeV1Detail(store: fixture.store, id: row.id) },
                              name: policy.id, scrolls: true, required: required,
                              forbidden: policy.mode == .community ? ["Maya", "Jordan", "4 people joined"] : [])
            if policy.mode == .personal || policy.competition == .leaderboard {
                XCTAssertEqual(row.members.allSatisfy { $0.target == nil }, !policy.hasTarget)
            }
        }
    }

    func testCommunityDelayedCountsInDetailAndJoin() async throws {
        let fixture = SignalFixture(); defer { fixture.clean() }
        var row = fixture.row("community_steps_goal_v1")
        let snapshot = ChallengeInstant(date: row.serverTime.date.addingTimeInterval(-900))
        row.counts = .init(joined: 5, state: "available", asOf: snapshot)
        fixture.rows = [row]; try await fixture.start()
        try await capture(NavigationStack { ChallengeV1Detail(store: fixture.store, id: row.id) },
                          name: "community-mature-detail", scrolls: true,
                          required: ["5 people joined", "15 minutes ago", "assigned moderator", "Report unsafe behavior"], forbidden: ["Maya", "Jordan"])
        let community = ChallengeV1Community(id: row.id, terms: .object(["common_target": .integer(50000)]), digest: "fixture", serverTime: row.serverTime, joinedCount: 5, counts: row.counts)
        try await capture(NavigationStack { ChallengeCommunityJoin(store: fixture.store, community: community) },
                          name: "community-mature-join", scrolls: true, required: ["5 people joined", "Join community challenge"])
        row.counts = .init(joined: nil, state: "threshold", asOf: nil)
        fixture.rows = [row]; try await fixture.start()
        try await capture(NavigationStack { ChallengeV1Detail(store: fixture.store, id: row.id) },
                          name: "community-threshold-detail", scrolls: true,
                          required: ["Participant totals stay hidden"], forbidden: ["5 people joined", "Maya", "Jordan"])
    }

    func testUnknownCorrectedTiedRedactedAndRecoveryPresentation() async throws {
        let fixture = SignalFixture(); defer { fixture.clean() }
        let row = fixture.row("friend_steps_leaderboard_v1", edge: true)
        fixture.rows = [row]; try await fixture.start()
        try await capture(NavigationStack { ChallengeV1Detail(store: fixture.store, id: row.id) },
                          name: "leaderboard-unknown-tied-departed", scrolls: true,
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
                          name: "home-stale-recovery", scrolls: true,
                          required: ["Retry saved action", "Last saved view", "No update yet"])
        fixture.store.setActor(fixture.actor)
        try await capture(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}),
                          name: "home-loading", required: ["Loading your challenges"])
        await fixture.store.refresh()
        try await capture(ChallengeV1Shell(store: fixture.store, invitation: ChallengeInvitationIntent(), logout: {}),
                          name: "home-unavailable", required: ["Refresh to try again"])
    }

    func testTwoAndSixPeopleReflowWithLongNamesAndSolidControls() async throws {
        let fixture = SignalFixture(); defer { fixture.clean() }
        for count in [2, 6] {
            let row = fixture.row("friend_steps_leaderboard_v1", people: count)
            fixture.rows = [row]; try await fixture.start()
            for accessible in [false, true] {
                try await capture(NavigationStack { ChallengeV1Detail(store: fixture.store, id: row.id) }
                    .environment(\.dynamicTypeSize, accessible ? .accessibility3 : .large)
                    .environment(\.colorScheme, accessible ? .dark : .light),
                    name: "people-\(count)-\(accessible ? "large-dark-solid" : "compact-solid")",
                    width: 375, scrolls: true, contrast: .high,
                    required: ["You", "Maya", "Leave challenge"])
            }
        }
    }

    func testAllAgreementsKeepLongRulesAndDatesReadable() async throws {
        let fixture = SignalFixture(); defer { fixture.clean() }
        for policy in ChallengeV1Policy.all {
            let row = fixture.row(policy.id, status: "scheduled")
            try await capture(NavigationStack {
                ChallengeForm {
                    SignalChallengeHeader(row: row, actor: fixture.actor)
                    ChallengeAgreementText(policy: policy, window: row.config, minimum: policy.mode == .personal ? 1 : 2)
                }.navigationTitle("Your agreement")
            }, name: "agreement-" + policy.id, width: 375, scrolls: true,
                required: ["Starts", "Ends, not included", "Central Time", "Chicago", "No real money moves", "48 hours", "72 hours"])
        }
    }

    func testControlFallbackGeometryAndUnknownValues() async throws {
        struct Controls: View {
            var body: some View {
                VStack(spacing: 16) {
                    Button("Agree to this challenge") {}.buttonStyle(SignalPrimaryButtonStyle())
                    Button("Leave challenge", role: .destructive) {}.buttonStyle(SignalSecondaryButtonStyle())
                    Button("Start my personal goal") {}.buttonStyle(SignalPrimaryButtonStyle()).disabled(true)
                    SignalMetricValue(value: 1_000_000_000, metric: .steps)
                }.padding(24).modifier(SignalGlassGroup()).background(SignalTheme.canvas)
            }
        }
        for solid in [false, true] {
            try await capture(Controls(), name: solid ? "controls-solid" : "controls-glass",
                width: 375, contrast: solid ? .high : .normal, required: ["Agree to this challenge", "Leave challenge", "1,000,000,000"])
        }
    }

    private func capture<V: View>(_ view: V, name: String, width: CGFloat = 430, height: CGFloat = 932,
                                 scrolls: Bool = false, contrast: UIAccessibilityContrast = .normal,
                                 required: [String] = [], forbidden: [String] = []) async throws {
        let host = UIHostingController(rootView: view.frame(width: width, height: height))
        host.traitOverrides.accessibilityContrast = contrast
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: width, height: height)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(300))
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        var lines: [String] = []
        for page in 0..<40 {
            // Glass is compositor-backed. Draw the actual UIKit viewport, then
            // scroll its native content; oversized synthetic windows cannot
            // capture the compositor and CALayer.render omits glass entirely.
            let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
            let image = UIGraphicsImageRenderer(size: window.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let cg = try XCTUnwrap(image.cgImage)
            for y in stride(from: 0, to: cg.height, by: 550) {
                let tile = try XCTUnwrap(cg.cropping(to: CGRect(x: 0, y: y, width: cg.width, height: min(700, cg.height - y))))
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
                request.customWords = ["GameTime"]
                request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
                try VNImageRequestHandler(cgImage: tile).perform([request])
                lines += (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "signal-" + name + "-page-\(page)"; attachment.lifetime = .keepAlways; add(attachment)
            guard scrolls, let scroll = scrollView(in: host.view) else { break }
            let bottom = max(-scroll.adjustedContentInset.top,
                             scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            let next = min(bottom, scroll.contentOffset.y + scroll.bounds.height * 0.7)
            guard next > scroll.contentOffset.y + 1 else { break }
            scroll.setContentOffset(CGPoint(x: scroll.contentOffset.x, y: next), animated: false)
            try await Task.sleep(for: .milliseconds(120))
            host.view.layoutIfNeeded()
            XCTAssertLessThan(page, 39, "The complete route must fit the bounded scroll capture")
        }
        let text = lines.joined(separator: " ").lowercased()
        let searchable = text.filter { !$0.isWhitespace }
        let transcription = XCTAttachment(string: text)
        transcription.name = "signal-" + name + "-text"; transcription.lifetime = .keepAlways; add(transcription)
        for value in required { XCTAssertTrue(searchable.contains(value.lowercased().filter { !$0.isWhitespace }), "Missing rendered text in \(name): \(value)") }
        for value in forbidden { XCTAssertFalse(searchable.contains(value.lowercased().filter { !$0.isWhitespace }), "Private text rendered in \(name): \(value)") }
    }

    private func scrollView(in view: UIView) -> UIScrollView? {
        guard !view.isHidden, view.alpha > 0 else { return nil }
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
           scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom > scroll.bounds.height + 1 { return scroll }
        return view.subviews.lazy.compactMap { self.scrollView(in: $0) }.first
    }

}

@MainActor private final class SignalFixture: ChallengeV1Client, AuthClient {
    let actor = UUID(), maya = UUID(), jordan = UUID()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("signal-render-" + UUID().uuidString)
    var rows: [ChallengeV1] = [], fail = false
    lazy var store = ChallengeV1Store(auth: self, client: self, requests: ChallengeV1RequestStore(directory: directory), now: { 0 })
    func clean() { store.hide(); try? FileManager.default.removeItem(at: directory) }
    func start() async throws {
        for row in rows { try row.validate(actor: actor) }
        store.setActor(actor); await store.refresh(); XCTAssertNil(store.error)
    }
    func row(_ policy: String, status: String = "active", edge: Bool = false, people: Int = 3) -> ChallengeV1 {
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
        if format.mode == .friend {
            if people == 2 { members = Array(members.prefix(2)) }
            if people == 6 {
                members += ["alexandertheweekendrunner", "Taylor", "Sam"].map {
                    .init(actorId: UUID(), username: $0, target: format.hasTarget ? target : nil,
                          selected: true, exited: false, consented: true,
                          fact: .init(value: values[2], state: "complete", recordedAt: start, revision: 1))
                }
            }
        } else { members = members.filter { $0.actorId == actor } }
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
