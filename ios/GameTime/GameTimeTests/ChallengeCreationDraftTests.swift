import XCTest
import SwiftUI
import Vision
@testable import GameTime

@MainActor final class ChallengeCreationDraftTests: XCTestCase {
    func testDefaultsDirectEntryAndExplicitDependentResets() {
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"))
        XCTAssertEqual(draft.step, .activity); XCTAssertEqual(draft.progress, 1); XCTAssertEqual(draft.stepCount, 2)
        XCTAssertFalse(draft.allowsTypeChange)
        XCTAssertEqual(draft.days, "7"); XCTAssertEqual(draft.dollars, "20"); XCTAssertEqual(draft.target, "")
        draft.target = "12345"; draft.days = "13"; draft.dollars = "37"
        draft.step = .review; draft.back()
        XCTAssertEqual(draft.target, "12345"); XCTAssertEqual(draft.days, "13")
        draft.metric = .timed
        XCTAssertEqual(draft.target, ""); XCTAssertEqual(draft.distance, "")
        XCTAssertEqual(draft.days, "13"); XCTAssertEqual(draft.dollars, "37")
        draft.distance = "5"; draft.target = "25:01"; draft.metric = .distance
        XCTAssertEqual(draft.distance, ""); XCTAssertEqual(draft.target, "")
        let restricted = ChallengeCreationDraft(personalStepsOnly: true)
        XCTAssertEqual(restricted.policy.id, "personal_steps_goal_v1"); XCTAssertEqual(restricted.stepCount, 2)
        XCTAssertFalse(restricted.allowsTypeChange)
        restricted.metric = .distance
        XCTAssertEqual(restricted.policy.id, "personal_distance_goal_v1")
        XCTAssertEqual(restricted.mode, .personal)
        restricted.metric = .steps
        XCTAssertEqual(restricted.policy.id, "personal_steps_goal_v1")
        XCTAssertFalse(ChallengeCreationDraft(initialPolicy: .init(rawValue: "friend_steps_goal_v1")).allowsTypeChange)
        // With a real choice, creation asks who it's for first.
        let standard = ChallengeCreationDraft()
        XCTAssertEqual(standard.step, .type)
        XCTAssertEqual(standard.firstStep, .type)
        XCTAssertFalse(standard.directEntry)
        XCTAssertEqual(standard.progress, 1)
        standard.step = .activity
        XCTAssertEqual(standard.progress, 2)
        standard.back()
        XCTAssertEqual(standard.step, .type)
        XCTAssertEqual(standard.policy.id, "friend_steps_goal_v1")
        XCTAssertTrue(standard.allowsTypeChange)
    }
    /// D142: the server's allowlist decides what can be created; the build doesn't.
    func testServerAllowedPoliciesDecideWhatCanBeCreated() throws {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        let reported = try decoder.decode(ChallengeV1Availability.self, from: Data("""
        {"restricted":true,"admission":true,"account_allowed":true,"verification_mode":"private_account",
         "policies":[{"policy":"friend_steps_goal_v1","source_policy_version":"apple_watch_steps_v1"},
                     {"policy":"friend_distance_goal_v1","source_policy_version":"apple_workout_outdoor_distance_v1"},
                     {"policy":"personal_steps_goal_v1","source_policy_version":"apple_watch_steps_v1"}],
         "links":false,"community":null}
        """.utf8))
        XCTAssertTrue(reported.accountMode)
        XCTAssertEqual(reported.links, false)
        XCTAssertNil(reported.community)
        let allowed = try XCTUnwrap(reported.creatablePolicies)
        XCTAssertEqual(allowed, ["friend_steps_goal_v1", "friend_distance_goal_v1", "personal_steps_goal_v1"])

        let draft = ChallengeCreationDraft(allowed: allowed)
        XCTAssertEqual(draft.policy.id, "friend_steps_goal_v1", "Friend goals come first when allowed")
        XCTAssertTrue(draft.allowsTypeChange)
        XCTAssertEqual(draft.step, .type, "Friends and personal goals are both open, so creation asks which")
        XCTAssertEqual(draft.metrics, [.steps, .distance])
        XCTAssertTrue(draft.permits(.personal, .goal))
        XCTAssertFalse(draft.permits(.friend, .leaderboard), "Leaderboards wait for the next build")
        draft.metric = .distance
        draft.mode = .personal
        XCTAssertEqual(draft.metrics, [.steps])
        XCTAssertEqual(draft.policy.id, "personal_steps_goal_v1", "A disallowed activity moves to an allowed one")

        let unrestricted = try decoder.decode(ChallengeV1Availability.self, from: Data("""
        {"restricted":false,"admission":false,"account_allowed":true,"verification_mode":"app_attest","policies":[]}
        """.utf8))
        XCTAssertNil(unrestricted.creatablePolicies)
        XCTAssertFalse(unrestricted.accountMode)
        XCTAssertEqual(ChallengeCreationDraft(allowed: nil).metrics.count, ChallengeV1Policy.Metric.allCases.count)

        let personalOnly = ChallengeCreationDraft(allowed: ChallengeV1Availability.privateTrialPolicies)
        XCTAssertEqual(personalOnly.mode, .personal)
        XCTAssertFalse(personalOnly.allowsTypeChange)
        XCTAssertEqual(personalOnly.step, .activity, "With only personal goals open there is nothing to ask")
    }

    func testCanonicalInputsAndInvalidValuesRemainEditable() {
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"))
        for (metric, input, value) in [(ChallengeV1Policy.Metric.steps,"1000000000",1000000000),(.exercise,"150:01",9001),(.distance,"12.345678",12345678),(.timed,"25:01",1501)] {
            draft.metric = metric; draft.target = input; draft.distance = "5.000001"
            XCTAssertTrue(draft.validate(.activity)); XCTAssertEqual(metric.parse(draft.target), value)
        }
        draft.target = "25:60"; XCTAssertFalse(draft.validate(.activity)); XCTAssertEqual(draft.target, "25:60")
        for invalid in ["0","501","1.5","-1","99999999999999999999999"] {
            draft.dollars = invalid; XCTAssertFalse(draft.validate(.amount)); XCTAssertEqual(draft.dollars, invalid)
        }
        draft.dollars = "500"; XCTAssertTrue(draft.validate(.amount)); XCTAssertEqual(draft.config["amount_cents"]?.integer, 50000)
        draft.days = "31"; XCTAssertFalse(draft.validate(.dates)); XCTAssertEqual(draft.days,"31")
    }
    func testWindowUsesFullLocalDaysAcrossDSTAndZoneIDsStayExact() throws {
        let date = try ChallengeInstant("2026-10-30T12:00:00Z").date
        let draft = ChallengeCreationDraft(now: date, zone: "America/Los_Angeles")
        draft.days = "1"
        let window = try XCTUnwrap(draft.window)
        XCTAssertEqual(window.startDate,"2026-11-01"); XCTAssertEqual(window.timezone,"America/Los_Angeles")
        XCTAssertEqual(window.endsAt.microseconds-window.startsAt.microseconds,25*3600*1000000)
        XCTAssertTrue(SignalTimeZone.name(window.timezone).contains("Los Angeles"))
    }
    func testTimedDistanceDisclosurePreservesExactUpperBoundary() {
        XCTAssertEqual(ChallengeTimedDistanceCopy.range(5_000_000), "5 km to 5.1 km")
        XCTAssertEqual(ChallengeTimedDistanceCopy.range(5_000_001), "5.000001 km to 5.10000102 km")
        XCTAssertEqual(ChallengeTimedDistanceCopy.range(1), "0.000001 km to 0.00000102 km")
    }
    func testStalePreviewAndFailureCannotRestoreEditedOrClosedDraft() async throws {
        let h = Harness(); defer { h.remove() }
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"))
        draft.target = "10000"
        let first = Task { await draft.readPreview(store: h.store) }
        while h.client.continuation == nil { await Task.yield() }
        draft.target = "12000"
        h.client.continuation?.resume(returning: try h.agreement(draft)); h.client.continuation = nil
        let firstResult = await first.value; XCTAssertFalse(firstResult); XCTAssertNil(draft.preview); XCTAssertFalse(draft.consent)
        let second = Task { await draft.readPreview(store: h.store) }
        while h.client.continuation == nil { await Task.yield() }
        draft.close(); h.client.continuation?.resume(throwing: ChallengeV1Error.unavailable); h.client.continuation = nil
        let secondResult = await second.value; XCTAssertFalse(secondResult); XCTAssertNil(draft.error)
    }
    func testInitializeOnceAndDateBoundsPreserveCalendarDayAcrossZoneChange() async throws {
        let h = Harness(); defer { h.remove() }
        await h.store.refresh()
        let draft = ChallengeCreationDraft(zone: "America/Los_Angeles")
        await draft.initialize(store: h.store, health: nil)
        XCTAssertEqual(draft.startDate, "2026-10-03")
        draft.start = draft.calendar.date(byAdding: .day, value: 3, to: draft.start)!
        await draft.initialize(store: h.store, health: nil)
        XCTAssertEqual(draft.startDate, "2026-10-06")
        draft.zone = "Pacific/Auckland"
        XCTAssertEqual(draft.startDate, "2026-10-06")
        XCTAssertTrue(draft.validate(.dates))
        draft.start = draft.allowedDates.lowerBound.addingTimeInterval(-86400)
        XCTAssertFalse(draft.validate(.dates))
    }
    func testCombinedGoalDatesReviewAndAmountEditRequireFreshAgreement() async throws {
        let h = Harness(); defer { h.remove() }
        await h.store.refresh()
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"))
        await draft.initialize(store: h.store, health: nil)
        draft.target = "12345"; draft.days = "31"
        await draft.advance(store: h.store)
        XCTAssertEqual(draft.step, .activity); XCTAssertNotNil(draft.error)
        XCTAssertNil(h.client.continuation, "Invalid dates cannot request an agreement")
        draft.days = "7"
        let first = Task { await draft.advance(store: h.store) }
        while h.client.continuation == nil { await Task.yield() }
        h.client.continuation?.resume(returning: try h.agreement(draft)); h.client.continuation = nil
        await first.value
        XCTAssertEqual(draft.step, .review); XCTAssertFalse(draft.needsReview)
        XCTAssertEqual(draft.dollars, "20"); XCTAssertFalse(draft.consent)
        draft.consent = true; draft.dollars = "21"
        XCTAssertEqual(draft.step, .review); XCTAssertTrue(draft.needsReview); XCTAssertFalse(draft.consent)
        let changed = Task { await draft.review(store: h.store) }
        while h.client.continuation == nil { await Task.yield() }
        h.client.continuation?.resume(returning: try h.agreement(draft)); h.client.continuation = nil
        await changed.value
        XCTAssertFalse(draft.needsReview); XCTAssertFalse(draft.consent)
        XCTAssertEqual(draft.window?.amountCents, 2100)
        draft.back()
        XCTAssertEqual(draft.step, .activity); XCTAssertEqual(draft.target, "12345")
        XCTAssertEqual(draft.days, "7"); XCTAssertEqual(draft.dollars, "21")
    }
    func testPendingRecoveryUsesExactRequestAndReceiptPolicy() async throws {
        let h = Harness(); defer { h.remove() }
        let draft = ChallengeCreationDraft()
        let payload: [String: ChallengeJSON] = ["policy": .string("personal_steps_goal_v1"), "config": draft.config, "target": .integer(12345)]
        _ = await h.store.submit(op: "personal_commit", fields: payload)
        let pending = try XCTUnwrap(h.store.pending)
        h.client.submitResult = .init(id: UUID(), status: "scheduled")
        await draft.submit(store: h.store)
        XCTAssertNil(h.store.pending); XCTAssertEqual(draft.receipt, h.client.submitResult)
        XCTAssertEqual(draft.savedPolicy?.mode, .personal)
        XCTAssertEqual(h.client.requests.count, 2)
        XCTAssertEqual(try h.client.requests[0].body, try h.client.requests[1].body)
        XCTAssertEqual(h.client.requests[1].requestId, pending.requestId)
        await draft.submit(store: h.store)
        XCTAssertEqual(h.client.requests.count, 2, "A second tap cannot submit a saved draft")
    }
    func testBackWhilePreviewLoadsCannotJumpToReview() async throws {
        let h = Harness(); defer { h.remove() }
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"))
        draft.target = "12345"; draft.step = .activity
        let work = Task { await draft.advance(store: h.store) }
        while h.client.continuation == nil { await Task.yield() }
        draft.back()
        h.client.continuation?.resume(returning: try h.agreement(draft)); h.client.continuation = nil
        await work.value
        XCTAssertEqual(draft.step, .activity); XCTAssertEqual(draft.target, "12345")
        XCTAssertNil(draft.preview); XCTAssertFalse(draft.reading)
    }
    func testPreviewLoadingAndFailureRetainInput() async throws {
        let h = Harness(); defer { h.remove() }
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"))
        await draft.initialize(store: h.store, health: nil)
        draft.target = "12345"; draft.step = .activity
        let work = Task { await draft.advance(store: h.store) }
        while h.client.continuation == nil { await Task.yield() }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let host = UIHostingController(rootView: ChallengeV1Create(store: h.store, draft: draft).frame(width: 375, height: 812))
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(250))
        let loading = try await captureMountedSignal(window, controller: host, name: "creation-preview-loading", test: self)
        XCTAssertTrue(loading.contains("loading the rules"))
        h.client.continuation?.resume(throwing: ChallengeV1Error.unavailable); h.client.continuation = nil
        await work.value
        XCTAssertFalse(draft.reading); XCTAssertEqual(draft.target, "12345"); XCTAssertEqual(draft.step, .activity)
        XCTAssertNil(draft.preview); XCTAssertFalse(draft.consent)
        let failure = try await captureMountedSignal(window, controller: host, name: "creation-preview-failure", test: self)
        XCTAssertTrue(failure.contains("try again"))
    }
    func testCreationVisualMatrix() async throws {
        let h = Harness(); defer { h.remove() }
        await h.store.refresh()
        for (name, scheme, size, solid) in [("glass-light", ColorScheme.light, DynamicTypeSize.large, false),
                                           ("glass-dark", .dark, .large, false),
                                           ("solid-light", .light, .large, true),
                                           ("solid-large-dark", .dark, .accessibility3, true)] {
            for step in [ChallengeCreationDraft.Step.type, .activity, .review] {
                let draft = ChallengeCreationDraft()
                await draft.initialize(store: h.store, health: nil)
                draft.mode = .personal; draft.target = "12345"; draft.step = step
                let view = ChallengeV1Create(store: h.store, draft: draft)
                    .environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, size)
                let text = try await capture(view, name: "creation-\(name)-\(step)", contrast: solid ? .high : .normal,
                                             requireCompleteConsent: step == .review)
                XCTAssertTrue(text.contains(step == .review ? "full goal rules" : "continue"), "Missing action in \(name) \(step): \(text)")
            }
        }
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"))
        await draft.initialize(store: h.store, health: nil)
        draft.target = "0"; _ = draft.validate(.activity)
        let errorText = try await capture(ChallengeV1Create(store: h.store, draft: draft), name: "creation-validation-error")
        XCTAssertTrue(errorText.contains("whole number of steps"))
        _ = await h.store.submit(op: "personal_commit", fields: ["policy": .string("personal_steps_goal_v1")])
        let pendingText = try await capture(ChallengeV1Create(store: h.store, draft: draft), name: "creation-pending")
        XCTAssertTrue(pendingText.contains("last change didn"), pendingText)
        XCTAssertTrue(pendingText.contains("try again")); XCTAssertTrue(pendingText.contains("cancel it"))
        XCTAssertFalse(pendingText.contains("saved action")); XCTAssertFalse(pendingText.contains("stop waiting"))
    }
    private func capture<V: View>(_ view: V, name: String, contrast: UIAccessibilityContrast = .normal,
                                 requireCompleteConsent: Bool = false) async throws -> String {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), host = UIHostingController(rootView: view)
        let container = UIViewController()
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        host.traitOverrides.accessibilityContrast = contrast
        window.rootViewController = container
        container.addChild(host); container.view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
            host.view.topAnchor.constraint(equalTo: container.view.topAnchor),
            host.view.widthAnchor.constraint(equalToConstant: 375),
            host.view.heightAnchor.constraint(equalToConstant: 812)
        ])
        host.didMove(toParent: container)
        window.makeKeyAndVisible(); container.view.layoutIfNeeded()
        let inheritedInsets = host.view.safeAreaInsets
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 0, left: 0,
            bottom: 34 - inheritedInsets.bottom, right: 0)
        container.view.layoutIfNeeded()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(host.view.bounds.size, CGSize(width: 375, height: 812))
        XCTAssertEqual(host.view.safeAreaInsets.top, container.view.safeAreaInsets.top, accuracy: 1)
        XCTAssertEqual(host.view.safeAreaInsets.bottom, 34, accuracy: 1)
        let text = try await captureMountedSignal(window, controller: host, name: name, test: self)
        if requireCompleteConsent {
            // Inspect the complete toggle in one real viewport. Concatenating
            // overlapping scroll captures can repeat a clipped text line and
            // must not replace verification of the exact consent sentence.
            if let scroll = verticalScroll(in: host.view) {
                let bottom = max(-scroll.adjustedContentInset.top,
                    scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                scroll.setContentOffset(CGPoint(x: 0, y: bottom), animated: false)
            }
            try await Task.sleep(for: .milliseconds(120))
            host.view.layoutIfNeeded()
            let format = UIGraphicsImageRendererFormat.default(); format.scale = 1; format.opaque = true
            let image = UIGraphicsImageRenderer(size: host.view.bounds.size, format: format).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image); attachment.name = name + "-complete-consent"
            attachment.lifetime = .keepAlways; add(attachment)
            let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]; request.minimumTextHeight = 0.005
            try VNImageRequestHandler(cgImage: XCTUnwrap(image.cgImage)).perform([request])
            let consentViewport = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string.lowercased() }.joined(separator: " ")
            let consentWords = consentViewport.replacingOccurrences(of: "•", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            XCTAssertTrue(consentWords.contains("i have read the complete rules and agree"),
                          "The complete unchanged consent must be readable together in \(name): \(consentViewport)")
        }
        return text
    }
    private func verticalScroll(in view: UIView) -> UIScrollView? {
        guard !view.isHidden, view.alpha > 0 else { return nil }
        if let scroll = view as? UIScrollView, scroll.isScrollEnabled,
           scroll.contentSize.height + scroll.adjustedContentInset.top + scroll.adjustedContentInset.bottom > scroll.bounds.height + 1 { return scroll }
        return view.subviews.lazy.compactMap { self.verticalScroll(in: $0) }.first
    }
    func testAccountSwitchRejectsPreviewAndEditsDiscardConsent() async throws {
        let h = Harness(); defer { h.remove() }
        let draft = ChallengeCreationDraft(initialPolicy: .init(rawValue: "personal_steps_goal_v1"))
        draft.target = "10000"
        let pending = Task { await draft.readPreview(store: h.store) }
        while h.client.continuation == nil { await Task.yield() }
        h.store.setActor(UUID())
        h.client.continuation?.resume(returning: try h.agreement(draft)); h.client.continuation = nil
        let pendingResult = await pending.value; XCTAssertFalse(pendingResult); XCTAssertNil(draft.preview)
        let fresh = Task { await draft.readPreview(store: h.store) }
        while h.client.continuation == nil { await Task.yield() }
        h.client.continuation?.resume(returning: try h.agreement(draft)); h.client.continuation = nil
        let freshResult = await fresh.value; XCTAssertTrue(freshResult); draft.consent = true
        draft.dollars = "21"
        XCTAssertNil(draft.preview); XCTAssertFalse(draft.consent)
    }
}
@MainActor private final class Harness {
    let actor = UUID(), client = PreviewClient()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    lazy var store: ChallengeV1Store = {
        let result = ChallengeV1Store(auth: PreviewAuth(actor), client: client, requests: .init(directory: directory))
        result.setActor(actor); return result
    }()
    func remove() { try? FileManager.default.removeItem(at: directory) }
    func agreement(_ draft: ChallengeCreationDraft) throws -> ChallengeV1.Agreement {
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let json = try JSONDecoder().decode(ChallengeJSON.self, from: encoder.encode(XCTUnwrap(draft.window)))
        return .init(digest: String(repeating:"a", count:64), terms:.object(["config":json]))
    }
}
@MainActor private final class PreviewClient: ChallengeV1Client {
    var submitResult: ChallengeV1Receipt?
    var requests: [ChallengeV1Request] = []
    var continuation: CheckedContinuation<ChallengeV1.Agreement, Error>?
    func list(actor: UUID) async throws -> [ChallengeV1] { [] }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 { throw ChallengeV1Error.unavailable }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt {
        requests.append(request)
        guard let submitResult else { throw ChallengeV1Error.unavailable }
        return submitResult
    }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        if name == "challenge_access_status_v1" {
            return try JSONDecoder().decode(type, from: Data(#"{"serverTime":"2026-10-01T12:00:00Z","ageConfirmed":true,"betaAccess":true,"suspended":false}"#.utf8))
        }
        if name == "challenge_community_catalog_v1" { return try JSONDecoder().decode(type, from: Data("[]".utf8)) }
        guard name == "challenge_personal_preview_v1" else { throw ChallengeV1Error.unavailable }
        let agreement = try await withCheckedThrowingContinuation { continuation = $0 }
        return try JSONDecoder().decode(type, from: JSONEncoder().encode(agreement))
    }
}
@MainActor private final class PreviewAuth: AuthClient {
    let actor: UUID
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor }
    func signOut() async throws {}
}
