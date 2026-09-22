#if DEBUG
import SwiftUI
import UIKit
import Vision
import XCTest
import GameTimeCore
@testable import GameTime

/// Exercises the native create-to-invite route with an in-memory service. No
/// local or hosted server is contacted, and every person and receipt is fictional.
@MainActor final class ChallengeCreationFlowTests: XCTestCase {
    func testGoalAndAgreementRenderFromTheCreationDraft() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        await fixture.start()
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_distance_goal_v1"), zone: "America/Los_Angeles")
        await draft.initialize(store: fixture.store, health: nil)
        draft.target = "20"
        let goal = try await capture(ChallengeV1Create(store: fixture.store, draft: draft), name: "native-create-goal")
        XCTAssertTrue(goal.contains("20"))
        XCTAssertTrue(goal.contains("km"))
        XCTAssertTrue(goal.contains("continue"))
        XCTAssertTrue(fixture.client.requests.isEmpty, "Opening and editing a goal does not save it")

        let reviewed = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_distance_goal_v1"), zone: "America/Los_Angeles")
        await reviewed.initialize(store: fixture.store, health: nil)
        reviewed.target = "20"
        fixture.client.agreement = try fixture.agreement(reviewed)
        await reviewed.review(store: fixture.store)
        XCTAssertEqual(reviewed.step, .review)
        let personal = try await capture(ChallengeV1Create(store: fixture.store, draft: reviewed), name: "native-personal-agreement")
        XCTAssertTrue(personal.contains("i have read the complete rules") && personal.contains("and agree"), personal)
        XCTAssertFalse(reviewed.consent, "The reviewed agreement still needs explicit consent")

        let friend = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"), zone: "America/Los_Angeles")
        await friend.initialize(store: fixture.store, health: nil)
        await friend.review(store: fixture.store)
        let challenge = try await capture(ChallengeV1Create(store: fixture.store, draft: friend), name: "native-create-challenge")
        XCTAssertTrue(challenge.contains("full challenge rules"))
        XCTAssertTrue(challenge.contains("20"))
        XCTAssertTrue(fixture.client.requests.isEmpty, "Review does not create the lobby or send invitations")
    }

    func testGoalUnitsStayBesideTheirValuesAndContinueStaysVisibleWhileScrolling() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        await fixture.start()
        let health = try fixture.healthFlow()
        defer { health.setActor(nil) }
        for (metric, target, name) in [(ChallengeV1Policy.Metric.steps, "800", "native-private-personal-steps"),
                                       (.distance, "20", "native-distance-goal-layout")] {
            let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_\(metric.rawValue)_goal_v1"),
                personalStepsOnly: metric == .steps, zone: "America/Los_Angeles")
            await draft.initialize(store: fixture.store, health: health)
            draft.target = target
            let mounted = try mount(ChallengeV1Create(store: fixture.store, draft: draft)
                .environment(\.challengeHealthFlow, health)
                .environment(\.colorScheme, .light).environment(\.dynamicTypeSize, .large))
            defer { mounted.close() }
            try await Task.sleep(for: .milliseconds(250))
            let first = try viewport(mounted, name: name + "-visible")
            let value = try XCTUnwrap(first.frame(matching: "\\b\(target)\\b"), first.text)
            let unit = try XCTUnwrap(first.frame(matching: metric == .steps ? "\\bsteps\\b" : "\\bkm\\b", beside: value), first.text)
            XCTAssertGreaterThanOrEqual(unit.minX, value.maxX - 2, "The unit belongs beside its editable number")
            XCTAssertTrue(unit.minY < value.maxY && unit.maxY > value.minY,
                          "The unit and value must share a line, rather than placing the unit in the footer")
            let originalAction = try XCTUnwrap(first.frame(matching: "\\bcontinue\\b"), first.text)
            XCTAssertTrue(mounted.window.bounds.contains(originalAction), "The full primary action must be visible without scrolling")
            let originalButtonBottom = try XCTUnwrap(first.primaryFillBottom(below: originalAction.maxY))
            XCTAssertLessThan(originalButtonBottom, first.size.height - 1,
                              "The button's filled lower edge, not only its label, must fit inside the viewport")
            XCTAssertGreaterThan(originalAction.minY, value.maxY)
            XCTAssertTrue(first.text.contains("your dates"), first.text)
            XCTAssertTrue(first.text.contains("find a suggestion on this phone"), first.text)
            XCTAssertEqual(draft.target, target, "Rendering must preserve the exact editable value")
            if metric == .steps {
                XCTAssertTrue(first.text.contains("outdoor runs"))
                XCTAssertTrue(first.text.contains("steps"))
                XCTAssertFalse(first.text.contains("activity minutes"))
                XCTAssertFalse(first.text.contains("running distance"))
                XCTAssertEqual(draft.policy.id, "personal_steps_goal_v1")
            }
            _ = try await captureMountedSignal(mounted.window, controller: mounted.host, name: name, test: self)

            // A realistic long recovery message creates scrollable content at
            // the same viewport size. The primary action must stay docked while
            // the content moves, rather than merely happen to fit on page one.
            draft.error = Array(repeating: "We couldn’t refresh your goal. Check your connection and try again.", count: 12).joined(separator: " ")
            try await Task.sleep(for: .milliseconds(120))
            mounted.host.view.layoutIfNeeded()
            let scroll = try XCTUnwrap(verticalScroll(in: mounted.host.view))
            let bottom = max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
            XCTAssertGreaterThan(bottom, scroll.contentOffset.y + 1, "The acceptance case must actually scroll")
            scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            try await Task.sleep(for: .milliseconds(120))
            let scrolled = try viewport(mounted, name: name + "-scrolled-recovery")
            let scrolledAction = try XCTUnwrap(scrolled.frame(matching: "\\bcontinue\\b"), scrolled.text)
            XCTAssertEqual(scrolledAction.midY, originalAction.midY, accuracy: 2,
                           "Continue must remain fixed while recovery content scrolls")
            XCTAssertEqual(scrolledAction.midX, originalAction.midX, accuracy: 2)
            XCTAssertTrue(mounted.window.bounds.contains(scrolledAction))
            let scrolledButtonBottom = try XCTUnwrap(scrolled.primaryFillBottom(below: scrolledAction.maxY))
            XCTAssertEqual(scrolledButtonBottom, originalButtonBottom, accuracy: 2)
            XCTAssertLessThan(scrolledButtonBottom, scrolled.size.height - 1)
        }
        XCTAssertEqual(fixture.healthReader.reads, 0, "Displaying the suggestion action never reads Health")
        XCTAssertEqual(fixture.healthPermission.connections, 0, "Displaying a goal never asks for Health access")
        XCTAssertTrue(fixture.client.requests.isEmpty, "Visual inspection never creates a goal or sends an invitation")
    }

    func testSuccessfulFriendCreationOpensInvitationsWithoutClaimingTheyWereSent() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        await fixture.start()
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"), zone: "America/Los_Angeles")
        await draft.initialize(store: fixture.store, health: nil)
        await draft.review(store: fixture.store)
        fixture.client.row = try fixture.row(draft)
        fixture.client.receipt = .init(id: fixture.id, status: "lobby_open")
        await draft.submit(store: fixture.store)
        XCTAssertEqual(draft.receipt?.id, fixture.id)
        XCTAssertNil(fixture.store.pending)
        XCTAssertEqual(fixture.client.requests.map { $0.payload["op"]?.string }, ["create"])

        let text = try await capture(ChallengeV1Create(store: fixture.store, draft: draft), name: "native-invite-friends")
        XCTAssertTrue(text.contains("invite friends"), text)
        XCTAssertFalse(text.contains("invitations sent"), "A lobby receipt cannot report invitation delivery")
        XCTAssertFalse(text.contains("challenge ready"), "A lobby is not an agreed or scheduled challenge")
        XCTAssertEqual(fixture.client.requests.count, 1, "Opening the next screen never sends an invitation")
    }

    func testUnconfirmedCreationKeepsItsExactRequestAndDoesNotOpenInvitations() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        await fixture.start()
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_steps_goal_v1"), zone: "UTC")
        await draft.initialize(store: fixture.store, health: nil)
        await draft.review(store: fixture.store)
        fixture.client.row = try fixture.row(draft)
        fixture.client.failSubmission = true
        await draft.submit(store: fixture.store)
        let request = try XCTUnwrap(fixture.store.pending)
        XCTAssertNil(draft.receipt)
        let mounted = try mount(ChallengeV1Create(store: fixture.store, draft: draft))
        defer { mounted.close() }
        let pending = try await captureMountedSignal(mounted.window, controller: mounted.host, name: "native-create-pending", test: self)
        XCTAssertTrue(pending.contains("retry saved action"))
        XCTAssertFalse(pending.contains("exact friend username"))

        fixture.client.failSubmission = false
        fixture.client.receipt = .init(id: fixture.id, status: "lobby_open")
        await draft.submit(store: fixture.store)
        XCTAssertEqual(fixture.client.requests, [request, request])
        XCTAssertEqual(draft.receipt?.id, fixture.id)
        XCTAssertNil(fixture.store.pending)
    }

    func testMountedInvitationsRemovePeopleAfterStaleReadsAndAccountChanges() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"),
            now: try ChallengeInstant("2026-09-26T12:00:00Z").date, zone: "UTC")
        fixture.client.row = try fixture.row(draft, friends: ["Sam Rivera", "Jordan Park"])
        await fixture.start()
        let mounted = try mount(NavigationStack {
            ChallengeCreationInviteView(store: fixture.store, challengeID: fixture.id)
        }.environment(\.colorScheme, .light))
        defer { mounted.close() }
        try await Task.sleep(for: .milliseconds(250))
        let populated = try await captureMountedSignal(mounted.window, controller: mounted.host,
            name: "native-invite-populated", test: self)
        XCTAssertTrue(populated.contains("sam rivera"))
        XCTAssertTrue(populated.contains("waiting for roster selection"))

        fixture.client.failReads = true
        await fixture.store.refresh()
        await fixture.store.loadDetail(fixture.id)
        let stale = try await captureMountedSignal(mounted.window, controller: mounted.host,
            name: "native-invite-stale", test: self)
        XCTAssertTrue(stale.contains("refresh your challenge"))
        XCTAssertFalse(stale.contains("sam rivera"))
        XCTAssertFalse(stale.contains("jordan park"))
        XCTAssertFalse(stale.contains("done inviting"), "An old roster cannot be confirmed")

        fixture.client.failReads = false
        await fixture.store.refresh()
        await fixture.store.loadDetail(fixture.id)
        let restored = try await captureMountedSignal(mounted.window, controller: mounted.host,
            name: "native-invite-restored", test: self)
        XCTAssertTrue(restored.contains("sam rivera"))
        fixture.auth.actor = UUID(); fixture.store.setActor(fixture.auth.actor)
        let changed = try await captureMountedSignal(mounted.window, controller: mounted.host,
            name: "native-invite-account-changed", test: self)
        XCTAssertFalse(changed.contains("sam rivera"))
        XCTAssertFalse(changed.contains("jordan park"))
        XCTAssertFalse(changed.contains("done inviting"))
        XCTAssertTrue(fixture.client.requests.isEmpty, "Viewing and refreshing never send invitations")
    }

    func testConfirmationShowsSavedLobbyFactsWithoutInventingAgreementOrDelivery() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"),
            now: try ChallengeInstant("2026-09-26T12:00:00Z").date, zone: "America/Los_Angeles")
        fixture.client.row = try fixture.row(draft, friends: ["Sam Rivera", "Jordan Park", "Priya Shah"], ownTarget: 20_000_000)
        await fixture.start()
        for (name, scheme, size) in [("native-create-confirm", ColorScheme.light, DynamicTypeSize.large),
                                     ("native-create-confirm-dark-accessibility", .dark, .accessibility3)] {
            let text = try await capture(NavigationStack {
                ChallengeCreationInviteView(store: fixture.store, challengeID: fixture.id, showingConfirmation: true)
            }, name: name, scheme: scheme, size: size)
            XCTAssertTrue(text.contains("challenge locked in"), text)
            XCTAssertTrue(text.contains("runs"), text)
            XCTAssertTrue(text.contains("simulated"), text)
            XCTAssertTrue(text.contains("go to home"), text)
            XCTAssertTrue(text.contains("view goal"), text)
            XCTAssertFalse(text.contains("view lobby"))
            XCTAssertFalse(text.contains("what counts"))
            XCTAssertFalse(text.contains("full rules"))
            XCTAssertFalse(text.contains("invitations sent"))
            XCTAssertFalse(text.contains("challenge ready"))
            XCTAssertFalse(text.contains("agreed"))
        }
        XCTAssertTrue(fixture.client.requests.isEmpty, "Confirmation does not select a roster, freeze rules or grant consent")
    }

    func testLockedInCopyStatesTheGoalOnce() throws {
        XCTAssertNil(ChallengeCreationSuccessCopy.stakeLine(cents: 0))
        XCTAssertEqual(ChallengeCreationSuccessCopy.stakeLine(cents: 2_000), "$20 simulated · fee $0")
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"),
            now: try ChallengeInstant("2026-09-22T12:00:00-07:00").date, zone: "America/Los_Angeles")
        draft.start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24)))
        draft.days = "7"
        let row = try fixture.row(draft, ownTarget: 50_000)
        let locale = Locale(identifier: "en_US")
        XCTAssertEqual(ChallengeCreationSuccessCopy.summary(row, locale: locale), "September steps · Sep 24–30")
        XCTAssertEqual(ChallengeCreationSuccessCopy.stake(row), "$20 simulated · fee $0")
    }

    func testPersonalLockedInScreenOffersHomeWithoutRestatingTheAgreement() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"),
            now: try ChallengeInstant("2026-09-22T12:00:00-07:00").date, zone: "America/Los_Angeles")
        draft.start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 24)))
        draft.days = "7"
        fixture.client.row = try fixture.row(draft, ownTarget: 50_000)
        await fixture.start()
        let mounted = try mount(ChallengeCreationSuccess(store: fixture.store, challengeID: fixture.id)
            .environment(\.locale, Locale(identifier: "en_US"))
            .environment(\.colorScheme, .light))
        defer { mounted.close() }
        try await Task.sleep(for: .milliseconds(250))
        let seen = try viewport(mounted, name: "native-create-locked-in")
        XCTAssertTrue(seen.text.contains("challenge locked in"), seen.text)
        XCTAssertTrue(seen.text.contains("september steps"), seen.text)
        XCTAssertTrue(seen.text.contains("sep 24"), seen.text)
        XCTAssertTrue(seen.text.contains("go to home"), seen.text)
        XCTAssertTrue(seen.text.contains("view goal"), seen.text)
        XCTAssertTrue(seen.text.contains("simulated"), seen.text)
        XCTAssertFalse(seen.text.contains("what counts"))
        XCTAssertFalse(seen.text.contains("full rules"))
        XCTAssertFalse(seen.text.contains("week starts"))
        XCTAssertTrue(fixture.client.requests.isEmpty, "Showing the saved goal does not submit another action")
    }

    func testInvitationAcknowledgmentRequiresItsCompleteLobbyReceipt() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        try await fixture.startLobby()
        let draft = ChallengeCreationInvitationDraft(challengeID: fixture.id)
        for receipt in [ChallengeV1Receipt(saved: true),
                        .init(id: UUID(), revision: 2, status: "lobby_open"),
                        .init(id: fixture.id, status: "lobby_open"),
                        .init(id: fixture.id, revision: 0, status: "lobby_open"),
                        .init(id: fixture.id, revision: 2, status: "scheduled")] {
            fixture.client.receipt = receipt
            draft.username = "  @Sam_Rivera  "
            let accepted = await draft.invite(store: fixture.store)
            XCTAssertFalse(accepted)
            XCTAssertFalse(draft.invitationSaved)
            XCTAssertEqual(draft.username, "  @Sam_Rivera  ", "An unrelated or incomplete receipt cannot clear entered text")
        }
        fixture.client.receipt = .init(id: fixture.id, revision: 2, status: "lobby_open")
        let accepted = await draft.invite(store: fixture.store)
        XCTAssertTrue(accepted)
        XCTAssertTrue(draft.invitationSaved)
        XCTAssertEqual(draft.username, "")
        XCTAssertTrue(fixture.client.requests.allSatisfy {
            $0.payload["op"]?.string == "invite"
                && $0.payload["username"]?.string == "Sam_Rivera"
                && $0.payload["id"]?.string == fixture.id.uuidString.lowercased()
                && $0.payload["revision"]?.integer == 1
        }, "The action sends only an exact username against the displayed lobby revision")
    }

    func testInvitationRetryUsesExactRequestAndPreservesNewerEnteredName() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        try await fixture.startLobby()
        let draft = ChallengeCreationInvitationDraft(challengeID: fixture.id)
        draft.username = "Sam_Rivera"
        fixture.client.failSubmission = true
        let first = await draft.invite(store: fixture.store)
        XCTAssertFalse(first)
        XCTAssertFalse(draft.invitationSaved)
        let request = try XCTUnwrap(fixture.store.pending)
        XCTAssertEqual(draft.username, "Sam_Rivera")

        draft.username = "Priya_Shah"
        let blocked = await draft.invite(store: fixture.store)
        XCTAssertFalse(blocked)
        XCTAssertEqual(fixture.client.requests, [request], "A pending invitation cannot be replaced by a new username")
        fixture.client.failSubmission = false
        fixture.client.receipt = .init(id: fixture.id, revision: 2, status: "lobby_open")
        let retried = await draft.retry(store: fixture.store)
        XCTAssertTrue(retried)
        XCTAssertTrue(draft.invitationSaved)
        XCTAssertEqual(draft.username, "Priya_Shah", "Completing the older action cannot discard a new name")
        XCTAssertEqual(fixture.client.requests, [request, request])
        XCTAssertNil(fixture.store.pending)
    }

    func testRetryCannotAcknowledgeAnotherActionOrAnotherChallenge() async throws {
        for otherChallenge in [false, true] {
            let fixture = CreationFlowFixture()
            defer { fixture.clean() }
            try await fixture.startLobby()
            let draft = ChallengeCreationInvitationDraft(challengeID: fixture.id)
            draft.username = "Sam_Rivera"
            let requestID = otherChallenge ? UUID() : fixture.id
            fixture.client.failSubmission = true
            await fixture.store.submit(op: otherChallenge ? "invite" : "target", fields: [
                "id": .string(requestID.uuidString.lowercased()), "revision": .integer(1),
                "username": .string("Sam_Rivera"), "target": .integer(20_000_000)
            ])
            let pending = try XCTUnwrap(fixture.store.pending)
            fixture.client.failSubmission = false
            fixture.client.receipt = .init(id: requestID, revision: 2, status: "lobby_open")
            let acknowledged = await draft.retry(store: fixture.store)
            XCTAssertFalse(acknowledged)
            XCTAssertFalse(draft.invitationSaved)
            XCTAssertEqual(draft.username, "Sam_Rivera")
            XCTAssertEqual(fixture.client.requests, [pending, pending])
        }
    }

    func testAccountChangeWhileInvitingCannotAcknowledgeOrEraseTheOldRequest() async throws {
        let fixture = CreationFlowFixture()
        defer { fixture.clean() }
        try await fixture.startLobby()
        fixture.client.holdSubmission = true
        let draft = ChallengeCreationInvitationDraft(challengeID: fixture.id)
        draft.username = "Sam_Rivera"
        let task = Task { await draft.invite(store: fixture.store) }
        defer { fixture.client.held?.resume(throwing: ChallengeV1Error.unavailable); fixture.client.held = nil }
        let deadline = Date().addingTimeInterval(2)
        while fixture.client.held == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(1)) }
        let response = try XCTUnwrap(fixture.client.held)
        fixture.client.held = nil
        let request = try XCTUnwrap(fixture.store.pending)
        fixture.auth.actor = UUID(); fixture.store.setActor(fixture.auth.actor)
        response.resume(returning: .init(id: fixture.id, revision: 2, status: "lobby_open"))
        let acknowledged = await task.value
        XCTAssertFalse(acknowledged)
        XCTAssertFalse(draft.invitationSaved)
        XCTAssertNil(fixture.store.lastReceipt)
        let saved = try await fixture.store.requests.load(fixture.actor)
        XCTAssertEqual(saved, request, "The old account retains its recoverable request")
        draft.reset()
        XCTAssertEqual(draft.username, "")
        XCTAssertFalse(draft.invitationSaved)
    }

    private func capture<V: View>(_ view: V, name: String,
                                 scheme: ColorScheme = .light, size: DynamicTypeSize = .large) async throws -> String {
        let mounted = try mount(view.environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size))
        defer { mounted.close() }
        try await Task.sleep(for: .milliseconds(250))
        return try await captureMountedSignal(mounted.window, controller: mounted.host, name: name, test: self)
    }

    private func viewport(_ mounted: CreationFlowMounted, name: String) throws -> CreationFlowViewport {
        mounted.host.view.setNeedsLayout(); mounted.host.view.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        let image = UIGraphicsImageRenderer(size: mounted.window.bounds.size, format: format).image { _ in
            mounted.host.view.drawHierarchy(in: mounted.host.view.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = name
        attachment.lifetime = .keepAlways; add(attachment)
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
        request.customWords = ["km", "steps", "Continue"]
        try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
        return .init(observations: request.results ?? [], size: mounted.window.bounds.size, image: image)
    }

    private func verticalScroll(in view: UIView) -> UIScrollView? {
        guard !view.isHidden, view.alpha > 0 else { return nil }
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
           scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom > scroll.bounds.height + 1 { return scroll }
        return view.subviews.lazy.compactMap { self.verticalScroll(in: $0) }.first
    }

    private func mount<V: View>(_ view: V) throws -> CreationFlowMounted {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: AnyView(view))
        let container = UIViewController()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = container
        container.addChild(host); container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.widthAnchor.constraint(equalToConstant: 390),
            host.view.heightAnchor.constraint(equalToConstant: 844)
        ])
        host.didMove(toParent: container)
        window.makeKeyAndVisible(); container.view.layoutIfNeeded()
        let inheritedInsets = host.view.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0,
            bottom: 34 - inheritedInsets.bottom, right: 0)
        container.view.layoutIfNeeded()
        XCTAssertEqual(host.view.bounds.size, CGSize(width: 390, height: 844))
        XCTAssertEqual(host.view.safeAreaInsets.top, container.view.safeAreaInsets.top, accuracy: 1)
        XCTAssertEqual(host.view.safeAreaInsets.bottom, 34, accuracy: 1)
        return .init(window: window, host: host, previous: previous)
    }
}

@MainActor private struct CreationFlowViewport {
    let observations: [VNRecognizedTextObservation]
    let size: CGSize
    let image: UIImage
    var text: String { observations.compactMap { $0.topCandidates(1).first?.string.lowercased() }.joined(separator: " ") }
    func frame(matching pattern: String, beside other: CGRect? = nil) -> CGRect? {
        for observation in observations {
            guard let text = observation.topCandidates(1).first,
                  let range = text.string.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                  let bounds = try? text.boundingBox(for: range)?.boundingBox else { continue }
            let result = CGRect(x: bounds.minX * size.width, y: (1 - bounds.maxY) * size.height,
                                width: bounds.width * size.width, height: bounds.height * size.height)
            if let other, !(result.minY < other.maxY && result.maxY > other.minY) { continue }
            // When Vision reads the value and unit as one line ("800 steps"),
            // it estimates the unit's box and can overlap the value. Measure
            // the pixels beside the value instead of trusting that estimate.
            if let other, result.minX < other.maxX - 2 { continue }
            return result
        }
        if let other { return croppedFrame(matching: pattern, beside: other) }
        return nil
    }
    private func croppedFrame(matching pattern: String, beside value: CGRect) -> CGRect? {
        // Whole-screen OCR can omit a small unit beside an athletic-size value.
        // Inspect those actual pixels independently, retaining their position
        // in the viewport so this still verifies a literal, inline unit.
        let region = CGRect(x: max(0, value.maxX - 2), y: max(0, value.minY - 8),
            width: max(0, size.width - value.maxX + 2), height: value.height + 24)
            .intersection(CGRect(origin: .zero, size: size)).integral
        guard region.width > 0, region.height > 0,
              let crop = image.cgImage?.cropping(to: region) else { return nil }
        let enlargedSize = CGSize(width: region.width * 3, height: region.height * 3)
        let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
        let enlarged = UIGraphicsImageRenderer(size: enlargedSize, format: format).image { context in
            context.cgContext.interpolationQuality = .high
            UIImage(cgImage: crop).draw(in: CGRect(origin: .zero, size: enlargedSize))
        }
        guard let cg = enlarged.cgImage else { return nil }
        let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
        request.customWords = ["km", "steps"]
        do { try VNImageRequestHandler(cgImage: cg).perform([request]) }
        catch { return nil }
        for observation in request.results ?? [] {
            guard let text = observation.topCandidates(1).first,
                  let range = text.string.range(of: pattern, options: [.regularExpression, .caseInsensitive]),
                  let bounds = try? text.boundingBox(for: range)?.boundingBox else { continue }
            let result = CGRect(x: region.minX + bounds.minX * region.width,
                y: region.minY + (1 - bounds.maxY) * region.height,
                width: bounds.width * region.width, height: bounds.height * region.height)
            guard result.minY < value.maxY, result.maxY > value.minY else { continue }
            return result
        }
        return nil
    }
    func primaryFillBottom(below labelBottom: CGFloat) -> CGFloat? {
        guard let cg = image.cgImage else { return nil }
        let width = cg.width, height = cg.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        UIColor(SignalCreationTheme.accent).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let expected = [red, green, blue].map { Int(($0 * 255).rounded()) }
        let x = width / 2
        var bottom: Int?
        for y in max(0, Int(labelBottom))..<height {
            let offset = (y * width + x) * 4
            if (0..<3).allSatisfy({ abs(Int(pixels[offset + $0]) - expected[$0]) < 8 }) { bottom = y }
        }
        return bottom.map(CGFloat.init)
    }
}

@MainActor private struct CreationFlowMounted {
    let window: UIWindow
    let host: UIHostingController<AnyView>
    let previous: UIWindow?
    func close() { window.isHidden = true; previous?.makeKeyAndVisible() }
}

@MainActor private final class CreationFlowFixture {
    let actor = UUID(), id = UUID()
    let client = CreationFlowClient()
    let healthPermission = CreationFlowPermission()
    let healthReader = CreationFlowHealthReader()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("creation-flow-" + UUID().uuidString)
    lazy var auth = CreationFlowAuth(actor)
    lazy var store = ChallengeV1Store(auth: auth, client: client, requests: .init(directory: directory))

    func start() async { store.setActor(actor); await store.refresh() }
    func startLobby() async throws {
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_distance_goal_v1"),
            now: try ChallengeInstant("2026-09-26T12:00:00Z").date, zone: "UTC")
        client.row = try row(draft)
        await start()
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
    func healthFlow() throws -> ChallengeHealthFlowStore {
        let coordinator = ChallengeHealthTransportCoordinator(
            uploadStore: .init(directory: directory.appendingPathComponent("uploads")),
            readinessStore: .init(directory: directory.appendingPathComponent("readiness")))
        let session: @MainActor () -> WeeklyClientSession? = { [auth] in
            auth.actor.map { .init(actorID: $0, identity: "fictional-creation-layout") }
        }
        let sign: @MainActor (UUID, Data) async throws -> MetricSignedMaterial = { _, _ in
            XCTFail("A creation layout capture must not sign Health data")
            throw ChallengeV1Error.unavailable
        }
        let uploads = ChallengeHealthUploadClient(environment: .development, coordinator: coordinator, binding: session, sign: sign) { _, _ in
            XCTFail("A creation layout capture must not upload Health data")
            throw ChallengeV1Error.unavailable
        }
        let readiness = ChallengeHealthReadinessClient(environment: .development, coordinator: coordinator, binding: session, sign: sign) { _, _ in
            XCTFail("A creation layout capture must not submit readiness")
            throw ChallengeV1Error.unavailable
        }
        let now = try ChallengeInstant("2026-09-21T12:00:00Z").date
        let dependencies = ChallengeHealthFlowDependencies(coordinator: coordinator, uploads: uploads, readiness: readiness,
            cache: .init(directory: directory.appendingPathComponent("health-cache")), permission: healthPermission,
            reader: { [healthReader] _, _ in healthReader }, adapter: ChallengeHealthBindingMapper.adapter, now: { now })
        let flow = ChallengeHealthFlowStore(auth: auth, challenges: store, dependencies: dependencies)
        flow.setActor(actor)
        return flow
    }
    func agreement(_ draft: ChallengeCreationDraft) throws -> ChallengeV1.Agreement {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let config = try JSONDecoder().decode(ChallengeJSON.self, from: encoder.encode(XCTUnwrap(draft.window)))
        return .init(digest: String(repeating: "a", count: 64), terms: .object(["config": config]))
    }
    func row(_ draft: ChallengeCreationDraft, friends: [String] = [], ownTarget: Int? = nil) throws -> ChallengeV1 {
        let members = [ChallengeV1.Member(actorId: actor, username: "Fictional You", target: ownTarget,
            selected: true, exited: false, consented: false, fact: nil)] + friends.map {
                ChallengeV1.Member(actorId: UUID(), username: $0, target: nil,
                    selected: false, exited: false, consented: false, fact: nil)
            }
        let result = ChallengeV1(id: id, creatorId: actor, policy: draft.policy.id,
            config: try XCTUnwrap(draft.window), status: "lobby_open", revision: 1, agreementVersion: 0,
            serverTime: try ChallengeInstant("2026-09-26T12:00:00Z"), socialHidden: false, agreement: nil,
            members: members,
            notice: nil, reviews: [], final: nil)
        try result.validate(actor: actor)
        return result
    }
}

@MainActor private final class CreationFlowPermission: ChallengeHealthPermissionService {
    let supported = true
    var connections = 0
    func connect(_ metric: ChallengeHealthMetric) async throws { connections += 1 }
}

@MainActor private final class CreationFlowHealthReader: ChallengeHealthStore {
    var reads = 0
    func read(_ request: ChallengeHealthReadRequest) async -> ChallengeHealthStoreOutcome {
        reads += 1
        return .unavailable(.protectedDataUnavailable)
    }
}

@MainActor private final class CreationFlowClient: ChallengeV1Client {
    var row: ChallengeV1?
    var agreement: ChallengeV1.Agreement?
    var receipt = ChallengeV1Receipt(saved: true)
    var requests: [ChallengeV1Request] = []
    var failSubmission = false
    var failReads = false
    var holdSubmission = false
    var held: CheckedContinuation<ChallengeV1Receipt, Error>?
    func list(actor: UUID) async throws -> [ChallengeV1] {
        if failReads { throw ChallengeV1Error.unavailable }
        return row.map { [$0] } ?? []
    }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 {
        guard !failReads, let row, row.id == id else { throw ChallengeV1Error.unavailable }
        return row
    }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        requests.append(request)
        if failSubmission { throw ChallengeV1Error.unavailable }
        if holdSubmission { return try await withCheckedThrowingContinuation { held = $0 } }
        return receipt
    }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        .init(status: "cancelled_request")
    }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        let data: Data
        switch name {
        case "challenge_access_status_v1":
            data = Data(#"{"serverTime":"2026-09-26T12:00:00Z","ageConfirmed":true,"betaAccess":true,"suspended":false}"#.utf8)
        case "challenge_community_catalog_v1": data = Data("[]".utf8)
        case "challenge_personal_preview_v1": data = try JSONEncoder().encode(XCTUnwrap(agreement))
        default: throw ChallengeV1Error.unavailable
        }
        return try JSONDecoder().decode(type, from: data)
    }
}

@MainActor private final class CreationFlowAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { try XCTUnwrap(actor) }
    func signOut() async throws { actor = nil }
}
#endif
