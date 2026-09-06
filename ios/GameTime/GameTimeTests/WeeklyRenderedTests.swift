#if DEBUG || STAGING
import SwiftUI
import UIKit
import Vision
import XCTest
@testable import GameTime

/// Rendered native fixtures, deliberately separate from the real HTTP smoke.
/// PNGs are review artifacts; they do not replace human VoiceOver checks.
@MainActor final class WeeklyRenderedTests: XCTestCase {
    func testFivePersonInvitationAndLargeTextRenderBeforeConsent() async throws {
        let row = try weeklyFixture { json in
            var roster = json["roster"] as! [[String: Any]]
            var terms = json["terms"] as! [String: Any]
            var people = terms["participants"] as! [[String: Any]]
            for index in 3...5 {
                let id = String(format: "10000000-0000-0000-0000-%012d", index)
                roster.append(["actor_id": id, "target_steps": 7000 + (index - 1) * 700, "display_name": [3: "Carmen", 4: "Dev", 5: "Ellis"][index]!])
                people.append(["participantId": id, "targetSteps": 7000 + (index - 1) * 700])
            }
            terms["participants"] = people; json["terms"] = terms; json["roster"] = roster; json["participant_count"] = 5
        }
        let model = try await makeModel(row)
        XCTAssertEqual(model.weekly.challenges.first?.roster.count, 5)
        XCTAssertTrue(model.weekly.canAccept(row.id))
        try render(NavigationStack { WeeklyDetailView(challengeID: row.id) }.environment(model), name: "five-person-invitation", height: 3200, requiredText: ["Alice", "Carmen", "Dev", "Ellis", "7,000", "7,700", "Accept this week"])
        try render(NavigationStack { WeeklyDetailView(challengeID: row.id) }.environment(model).environment(\.dynamicTypeSize, .accessibility3), name: "five-person-invitation-accessibility3", height: 6500, requiredText: ["Alice", "Carmen", "Dev", "Ellis", "Accept this week"])
    }
    func testProvisionalFinalRefundAndRecoveryRender() async throws {
        let row = try weeklyFixture { json in
            var own = json["own"] as! [String: Any]
            own["accepted_at"] = "2026-09-06T06:00:00.000000Z"; json["own"] = own
            json["accepted_count"] = 2
            json["status"] = "final"; json["server_now"] = "2026-09-23T05:00:00.000001Z"
            json["notices"] = [["revision": 1, "recorded_at": "2026-09-17T05:00:00.000000Z", "file_by": "2026-09-19T05:00:00.000000Z", "resolve_by": "2026-09-22T05:00:00.000000Z", "qualification": "unresolved"]]
            json["result"] = ["recorded_at": "2026-09-23T05:00:00.000000Z", "qualification": "refund", "reason": "fixture_only"]
            json["allocation"] = ["recorded_at": "2026-09-23T05:00:00.000000Z", "returned_cents": 2000, "bonus_cents": 0, "mode": "fictional_nonredeemable", "redeemable": false]
        }
        let queue = EphemeralPendingWeeklyRequestStore()
        var request = try PendingWeeklyRequest(actorID: row.own.actorID, operation: .support(row.id, reason: .privacy))
        request.mayHaveCommitted = true; try await queue.save(request)
        let model = try await makeModel(row, queue: queue)
        XCTAssertNotNil(model.weekly.pending)
        try render(NavigationStack { WeeklyDetailView(challengeID: row.id) }.environment(model), name: "provisional-final-refund-recovery", height: 4200, requiredText: ["Saved request", "Retry saved request", "Confirmed result", "Entry returned"], forbiddenText: ["Your invitation"])
    }
    func testCommunityCommonRulesRenderWithoutFriends() async throws {
        let row = try weeklyFixture()
        guard case .object(var raw) = row.terms.raw else { return XCTFail("Fixture terms") }
        raw.removeValue(forKey: "creatorId"); raw.removeValue(forKey: "participants")
        raw["mode"] = .string("community")
        raw["commonTargetSteps"] = .integer(12000); raw["capacity"] = .integer(10)
        raw["targetStatus"] = .string("fixture_not_launch_target")
        guard case .object(var policy) = raw["policy"] else { return XCTFail("Fixture policy") }
        policy["version"] = .string("weekly-community-steps-fixture-v1")
        raw["policy"] = .object(policy)
        let terms = try WeeklyTerms(raw: .object(raw))
        let cohort = WeeklyCohort(id: UUID(), mode: "community", terms: terms, termsDigest: row.termsDigest,
            joinBy: WeeklyInstant(date: terms.fields.startsAt.date.addingTimeInterval(-3600)), capacity: 10, participantCount: 1)
        let model = try await makeModel(row, cohorts: [cohort])
        XCTAssertTrue(model.weekly.friends.isEmpty)
        try render(NavigationStack { WeeklyCohortView(cohortID: cohort.id) }.environment(model), name: "community-common-target-solo", height: 2300, requiredText: ["12,000", "Join community week", "Joining does not share"])
    }
    func testUnacceptedFinalWeekShowsClosedInvitationAndSupport() async throws {
        let row = try weeklyFixture { json in
            json["status"] = "final"; json["server_now"] = "2026-09-23T05:00:00.000001Z"
        }
        let model = try await makeModel(row)
        XCTAssertFalse(model.weekly.canAccept(row.id)); XCTAssertFalse(model.weekly.canExit(row.id))
        XCTAssertTrue(model.weekly.canStartRequest)
        try render(NavigationStack { WeeklyDetailView(challengeID: row.id) }.environment(model), name: "unaccepted-final-closed-invitation", height: 2800,
            requiredText: ["Invitation closed", "You did not join this week", "Save support request"], forbiddenText: ["Accept this week", "Your invitation"])
    }
    private func makeModel(_ row: WeeklyChallenge, queue: (any PendingWeeklyRequestStore)? = nil, cohorts: [WeeklyCohort] = []) async throws -> AppModel {
        let auth = WeeklyTestAuth(row.own.actorID), client = WeeklyTestClient(row)
        client.cohortRows = cohorts
        let services = FixtureServicesFactory.make(weeklyClient: client, authClient: auth, pendingWeeklyRequestStore: queue, friendshipsClient: WeeklyTestFriends())
        let model = AppModel(configuration: AppConfiguration(environment: .debug, supabaseURL: URL(string: "http://127.0.0.1:56321")!, supabasePublishableKey: "fixture", contestMutationsEnabled: false, weeklyRequested: true), services: services)
        model.weekly.setActor(row.own.actorID); await model.weekly.refresh()
        XCTAssertNil(model.weekly.errorMessage)
        return model
    }
    private func render<V: View>(_ view: V, name: String, height: CGFloat, requiredText: [String], forbiddenText: [String] = []) throws {
        let controller = UIHostingController(rootView: view)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 430, height: height)
        window.rootViewController = controller; window.makeKeyAndVisible()
        controller.view.frame = window.bounds; controller.view.setNeedsLayout(); controller.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: window.bounds.size, format: format)
        let image = renderer.image { context in controller.view.layer.render(in: context.cgContext) }
        let cgImage = try XCTUnwrap(image.cgImage)
        let bytes = try XCTUnwrap(cgImage.dataProvider?.data) as Data
        XCTAssertGreaterThan(Set(bytes).count, 30, "Blank rendering is not UI evidence")
        // Recognize native-size overlapping tiles. Scaling a 6,500px canvas
        // into one OCR input can discard ordinary body text as too small.
        var recognized: [String] = []
        for y in stride(from: 0, to: cgImage.height, by: 650) {
            let rectangle = CGRect(x: 0, y: y, width: cgImage.width, height: min(800, cgImage.height - y))
            let tile = try XCTUnwrap(cgImage.cropping(to: rectangle))
            let recognition = VNRecognizeTextRequest()
            recognition.recognitionLevel = .accurate
            recognition.recognitionLanguages = ["en-US"]
            recognition.minimumTextHeight = 0.005
            try VNImageRequestHandler(cgImage: tile).perform([recognition])
            recognized += (recognition.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        let visible = recognized.joined(separator: " ").lowercased()
        for text in requiredText { XCTAssertTrue(visible.contains(text.lowercased()), "Rendered text missing: \(text)") }
        for text in forbiddenText { XCTAssertFalse(visible.contains(text.lowercased()), "Unexpected rendered text: \(text)") }
        let data = try XCTUnwrap(image.pngData()); XCTAssertGreaterThan(data.count, 10_000)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("tmp/weekly-rendered")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: directory.appendingPathComponent(name + ".png"), options: .atomic)
        let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        window.isHidden = true; previous?.makeKeyAndVisible()
    }
}
#endif
