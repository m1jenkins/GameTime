import Foundation
import GameTimeCore
import SwiftUI
import XCTest
@testable import GameTime

@MainActor final class ChallengeHealthFlowStoreTests: XCTestCase {
    func testUnlockOpportunityWorksBeforeSavedHealthConnectionsCanBeReadAndStopsOnSignOut() async throws {
        let permission = HealthKitChallengeHealthPermissionService()
        var updates = 0
        permission.updates(for: [], active: true) { updates += 1 }
        defer { permission.updates(for: [], active: false, perform: {}) }
        try await Task.sleep(for: .milliseconds(100))
        let before = updates
        NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertGreaterThan(updates, before, "Locked connection state must not suppress unlock recovery")
        permission.updates(for: [], active: false, perform: {})
        try await Task.sleep(for: .milliseconds(25))
        let stopped = updates
        NotificationCenter.default.post(name: UIApplication.protectedDataDidBecomeAvailableNotification, object: nil)
        try await Task.sleep(for: .milliseconds(25))
        XCTAssertEqual(updates, stopped)
    }
    func testLaunchRecoversSignedReadinessWithoutListedChallengesOrPendingWork() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let binding = try h.binding(); h.loseReadinessResponse = true
        await h.flow.checkReadiness(binding, connect: true)
        XCTAssertFalse(h.flow.canConsent(binding))
        XCTAssertEqual(try h.coordinator.readinessStore.load(actor: h.actor).pending.count, 1)
        XCTAssertTrue(h.store.challenges.isEmpty)
        XCTAssertTrue(try h.cache.pending(actor: h.actor).isEmpty)
        await h.flow.refresh()
        XCTAssertTrue(try h.coordinator.readinessStore.load(actor: h.actor).pending.isEmpty)
        XCTAssertEqual(h.signed, 1); XCTAssertEqual(h.readinessSent, 2)
        XCTAssertEqual(h.requests.count, 1, "Recovery never reads Health or creates another fact")
    }
    func testReceivedLeaderboardCreationAndHealthCopyAtLargeTextInLightAndDark() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let binding = try h.binding()
        await h.flow.checkReadiness(binding, connect: true)
        for scheme in [ColorScheme.light, .dark] {
            for metric in ChallengeV1Policy.Metric.allCases {
                let policy = ChallengeV1Policy(rawValue: "friend_\(metric.rawValue)_leaderboard_v1")!
                let text = try await capture(ChallengeV1Create(store: h.store, initialPolicy: policy)
                    .environment(\.challengeHealthFlow, h.flow).environment(\.colorScheme, scheme)
                    .environment(\.dynamicTypeSize, .accessibility3), name: "d141-leaderboard-\(metric.rawValue)-\(scheme)")
                // At the largest text size, a viewport boundary can bisect
                // GameTime. Vision retains that partial word before the next
                // page's complete line. Check both exact clauses in order.
                let savedBy = try XCTUnwrap(text.range(of: "saved by"), text)
                let deadline = try XCTUnwrap(text.range(of: "gametime by the deadline wins"), text)
                XCTAssertLessThanOrEqual(savedBy.upperBound, deadline.lowerBound,
                                         "The saved-result source must precede its deadline: \(text)")
                XCTAssertTrue(text.contains("continue")); XCTAssertFalse(text.contains("suggestion"))
            }
            let text = try await capture(NavigationStack {
                ScrollView { VStack(alignment: .leading, spacing: 20) {
                    Text("Activity minutes").font(.largeTitle)
                    Text(ChallengeHealthCopy.source("apple_watch_exercise_credit_v2"))
                    ChallengeHealthStatusView(flow: h.flow, binding: binding, readiness: true)
                }.padding(SignalTheme.contentInset) }.background(SignalTheme.canvas)
            }.environment(\.colorScheme, scheme).environment(\.dynamicTypeSize, .accessibility3), name: "p9-health-credit-readiness-\(scheme)")
            XCTAssertTrue(text.contains("indirectly derived credit may count"))
            XCTAssertTrue(text.contains("activity found")); XCTAssertTrue(text.contains("refresh activity check"))
        }
    }
    func testPrivatePersonalStepsCreateHidesUnsupportedChallengeChoices() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let text = try await capture(
            ChallengeV1Create(store: h.store, personalStepsOnly: true),
            name: "private-personal-steps-create"
        )
        XCTAssertTrue(text.contains("your goal"))
        XCTAssertTrue(text.contains("steps"))
        XCTAssertTrue(text.contains("over 7 days"))
        XCTAssertFalse(text.contains("choose your challenge"))
        XCTAssertFalse(text.contains("with friends"))
        XCTAssertFalse(text.contains("activity minutes"))
        XCTAssertFalse(text.contains("running distance"))
    }
    private func capture<V: View>(_ view: V, name: String) async throws -> String {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow), host = UIHostingController(rootView: view)
        let window = UIWindow(windowScene: scene); window.frame = CGRect(x: 0, y: 0, width: 375, height: 812)
        window.rootViewController = host; window.makeKeyAndVisible(); host.view.frame = window.bounds
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(250))
        return try await captureMountedSignal(window, controller: host, name: name, test: self)
    }
    func testReceivedLeaderboardsUseAllFourAdaptersAndKeepMissingScoresUnknown() async throws {
        for metric in ChallengeV1Policy.Metric.allCases {
            let h = try FlowHarness(); defer { h.remove() }
            let policy = ChallengeV1Policy(rawValue: "friend_\(metric.rawValue)_leaderboard_v2")!
            let id = try h.addActivity(policy: policy.id)
            let source = try XCTUnwrap(ChallengeHealthBindingMapper.selectedSource(metric))
            try h.cache.connect(actor: h.actor, source: source.identifier)
            await h.flow.refresh(id)
            let row = try XCTUnwrap(h.client.rows[id])
            XCTAssertEqual(h.uploads.count, 1)
            XCTAssertEqual(row.own(h.actor)?.fact?.state, "value")
            XCTAssertNotNil(row.savedScore(try XCTUnwrap(row.own(h.actor))))
            XCTAssertFalse(h.flow.states[id]?.pendingDelivery ?? true)
            XCTAssertNotNil(h.flow.states[id]?.lastServerUpdate)
            h.mode = .empty
            await h.flow.refresh(id)
            XCTAssertEqual(h.client.rows[id]?.own(h.actor)?.fact?.state, "unresolved")
            XCTAssertNil(h.client.rows[id]?.own(h.actor)?.fact?.value)
        }
    }
    func testReceivedLeaderboardFirstScoreAtCutoffAndExactRecoveryAfterCutoff() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let id = try h.addActivity(policy: "friend_steps_leaderboard_v2")
        try h.cache.connect(actor: h.actor, source: "apple_watch_steps_v1")
        let row = try XCTUnwrap(h.client.rows[id])
        h.now = row.config.correctionsBy.date; h.client.now = h.now
        h.loseUploadResponse = true
        await h.flow.refresh(id)
        XCTAssertEqual(h.uploads.count, 1, "First score is allowed at the correction cutoff")
        XCTAssertTrue(h.flow.states[id]?.pendingDelivery ?? false)
        XCTAssertNotNil(h.flow.states[id]?.message, "Lost acknowledgement must offer recovery/review")
        XCTAssertNil(h.flow.states[id]?.lastServerUpdate, "Do not claim success before confirmation")
        let request = try XCTUnwrap(h.uploads.first)
        h.now = h.now.addingTimeInterval(1); h.client.now = h.now
        await h.flow.refresh(id)
        XCTAssertEqual(h.uploads.count, 2)
        XCTAssertEqual(h.uploads.last?.exactBytes, request.exactBytes)
        XCTAssertEqual(h.requests.count, 1, "After cutoff, recover exact bytes without reading new activity")
        XCTAssertTrue(try h.coordinator.uploadStore.load(actor: h.actor).pending.isEmpty)
        XCTAssertNotNil(h.flow.states[id]?.lastServerUpdate)
        XCTAssertFalse(h.flow.states[id]?.pendingDelivery ?? true)
        XCTAssertNil(h.flow.states[id]?.message)
    }
    func testOldLeaderboardCannotReadOrUpload() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let id = try h.addActivity(policy: "friend_steps_leaderboard_v1")
        try h.cache.connect(actor: h.actor, source: "apple_watch_steps_v1")
        await h.flow.refresh(id)
        XCTAssertTrue(h.uploads.isEmpty); XCTAssertTrue(h.requests.isEmpty)
        XCTAssertThrowsError(try ChallengeHealthBindingMapper.activity(XCTUnwrap(h.client.rows[id]), actor: h.actor))
    }
    func testReceivedLeaderboardSavedScoreDeadlineAndRefreshRender() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let id = try h.addActivity(policy: "friend_steps_leaderboard_v2")
        try h.cache.connect(actor: h.actor, source: "apple_watch_steps_v1")
        await h.flow.refresh(id)
        let text = try await capture(NavigationStack { ChallengeV1Detail(store: h.store, id: id) }, name: "d141-saved-score")
        XCTAssertTrue(text.contains("your saved score"))
        XCTAssertTrue(text.contains("last saved update"))
        XCTAssertTrue(text.contains("save activity by"))
        XCTAssertTrue(text.contains("refresh"))
        XCTAssertFalse(text.contains("leaderboard — not available yet"))
    }
    func testPrivateTimedLeaderboardHasNoGoalTimeCopy() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let id = try h.addActivity(policy: "friend_timed_leaderboard_v2", socialHidden: true)
        try h.cache.connect(actor: h.actor, source: "apple_workout_outdoor_timed_v1")
        await h.flow.refresh(id)
        let row = try XCTUnwrap(h.client.rows[id])
        let text = try await capture(SignalFeaturedChallenge(row: row, actor: h.actor), name: "d141-private-timed")
        XCTAssertTrue(text.contains("fastest eligible saved run"))
        XCTAssertFalse(text.contains("under your agreed time"))
        XCTAssertNil(ChallengePresentation.rank(try XCTUnwrap(row.own(h.actor)), in: row, actor: h.actor))
    }
    func testAllSevenReadinessStatesAndPermissionIsNotReadiness() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let binding = try h.binding()
        func captureStatus(_ name: String) async throws {
            let text = try await capture(NavigationStack {
                ScrollView { ChallengeHealthStatusView(flow: h.flow, binding: binding, readiness: true)
                    .buttonStyle(SignalSecondaryButtonStyle()).padding(SignalTheme.contentInset) }
                    .background(SignalTheme.canvas).navigationTitle("Your activity")
            }, name: "creation-health-" + name)
            XCTAssertTrue(text.contains(ChallengeHealthCopy.title(h.flow.state(for: binding).readiness).lowercased()))
        }
        XCTAssertEqual(h.flow.state(for: binding).readiness, .notConnected)
        try await captureStatus("notConnected")
        h.permission.supported = false
        await h.flow.checkReadiness(binding, connect: true)
        XCTAssertEqual(h.flow.state(for: binding).readiness, .unsupported)
        try await captureStatus("unsupported")
        h.permission.supported = true
        h.mode = .empty
        await h.flow.checkReadiness(binding, connect: true)
        XCTAssertEqual(h.flow.state(for: binding).readiness, .noEligibleDataYet)
        try await captureStatus("noEligibleDataYet")
        XCTAssertFalse(h.flow.canConsent(binding)); XCTAssertEqual(h.signed, 0)
        h.mode = .failure
        await h.flow.checkReadiness(binding)
        XCTAssertEqual(h.flow.state(for: binding).readiness, .temporarilyUnavailable)
        try await captureStatus("temporarilyUnavailable")
        h.mode = .truncated
        await h.flow.checkReadiness(binding)
        XCTAssertEqual(h.flow.state(for: binding).readiness, .staleOrIncomplete)
        try await captureStatus("staleOrIncomplete")
        h.mode = .value; h.holdRead = true
        let checking = Task { await h.flow.checkReadiness(binding) }
        while h.heldRead == nil { await Task.yield() }
        XCTAssertEqual(h.flow.state(for: binding).readiness, .checking)
        try await captureStatus("checking")
        h.heldRead?.resume(); h.heldRead = nil
        await checking.value
        XCTAssertEqual(h.flow.state(for: binding).readiness, .ready)
        try await captureStatus("ready")
        XCTAssertTrue(h.flow.canConsent(binding)); XCTAssertEqual(h.signed, 1)
        h.now = h.now.addingTimeInterval(301)
        XCTAssertFalse(h.flow.canConsent(binding))
        let strict = try h.binding(source: .appleWatchExerciseV1)
        await h.flow.checkReadiness(strict, connect: true)
        XCTAssertEqual(h.flow.state(for: strict).readiness, .unsupported)
        XCTAssertEqual(h.signed, 1)
    }

    func testReadinessDeliveryFailureUsesSpecificRecoveryMessageAndKeepsSavedRequest() async throws {
        XCTAssertEqual(
            ChallengeHealthCopy.explanation(.temporarilyUnavailable, timed: false),
            "Check your connection and try Refresh. Missing activity doesn’t count against you."
        )

        let cases: [(ChallengeHealthReadinessClientError, String)] = [
            (.refused, "We couldn’t confirm your activity setup. Refresh your challenge and try again."),
            (.storage, "We couldn’t save this activity check on your phone. Unlock your phone and try Refresh."),
            (.unavailable, "We couldn’t finish checking your activity right now. Check your connection and try Refresh."),
        ]

        for (failure, message) in cases {
            let h = try FlowHarness(); defer { h.remove() }
            let binding = try h.binding()
            h.readinessFailure = failure

            await h.flow.checkReadiness(binding, connect: true)

            XCTAssertEqual(h.flow.state(for: binding).readiness, .temporarilyUnavailable)
            XCTAssertEqual(h.flow.state(for: binding).message, message)
            XCTAssertEqual(try h.coordinator.readinessStore.load(actor: h.actor).pending.count, 1)
        }
    }

    func testPlanningAndReadinessUseSeparateReadersAndWindows() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let binding = try h.binding()
        await h.flow.suggest(binding, policy: ChallengeV1Policy(rawValue: "personal_steps_goal_v1")!, days: 7)
        XCTAssertEqual(h.flow.suggestions[binding.challengeID], 2751)
        XCTAssertFalse(h.flow.canConsent(binding)); XCTAssertEqual(h.signed, 0)
        await h.flow.checkReadiness(binding)
        XCTAssertEqual(h.readers.count, 2)
        XCTAssertEqual(h.requests.map(\.purpose), [.suggestionHistory, .readinessHistory])
        XCTAssertEqual(h.requests.map { $0.queryWindow.interval.duration }, [28 * 86400, 30 * 86400])
        XCTAssertTrue(h.flow.canConsent(binding))
        let timed = try h.binding(source: .appleWorkoutOutdoorTimedV1, distance: 5_000_000)
        await h.flow.checkReadiness(timed, connect: true)
        XCTAssertTrue(h.flow.canConsent(timed))
        let changed = try h.binding(id: timed.challengeID, source: .appleWorkoutOutdoorTimedV1, distance: 10_000_000)
        XCTAssertFalse(h.flow.canConsent(changed))
        XCTAssertEqual(h.requests.last?.queryWindow.interval.duration, 90 * 86400)
    }

    func testCancellationDuringSigningAndActorSwitchCannotPersistOrConsent() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let binding = try h.binding(); h.holdSign = true
        let checking = Task { await h.flow.checkReadiness(binding, connect: true) }
        while h.heldSign == nil { await Task.yield() }
        h.flow.cancel(binding.challengeID)
        h.heldSign?.resume(); h.heldSign = nil
        await checking.value
        XCTAssertFalse(h.flow.canConsent(binding))
        XCTAssertTrue(try h.coordinator.readinessStore.load(actor: h.actor).pending.isEmpty)
        XCTAssertEqual(h.readinessSent, 0)
        h.holdRead = true
        let waiting = Task { await h.flow.checkReadiness(binding) }
        while h.heldRead == nil { await Task.yield() }
        h.auth.actor = UUID(); h.flow.setActor(h.auth.actor)
        h.heldRead?.resume(); h.heldRead = nil
        await waiting.value
        XCTAssertTrue(h.flow.states.isEmpty)
        XCTAssertEqual(h.readinessSent, 0)
    }

    func testSameActorNewSessionAndExpiryFenceNativeCompletions() async throws {
        for expires in [false, true] {
            let h = try FlowHarness(); defer { h.remove() }
            let binding = try h.binding(); h.holdRead = true
            let waiting = Task { await h.flow.checkReadiness(binding, connect: true) }
            while h.heldRead == nil { await Task.yield() }
            h.sessionIdentity = expires ? nil : "replacement-session"
            h.heldRead?.resume(); h.heldRead = nil
            await waiting.value
            XCTAssertTrue(h.flow.states.isEmpty)
            XCTAssertEqual(h.signed, 0); XCTAssertFalse(h.flow.canConsent(binding))
            h.sessionIdentity = "recovered-session"
            await h.flow.authenticationRecovered(actor: h.actor)
            await h.flow.checkReadiness(binding)
            XCTAssertTrue(h.flow.canConsent(binding))
        }
    }

    func testSimultaneousChallengesRelaunchAndDisappearanceCannotLeakOrKeepPositive() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let first = try h.addActivity(), second = try h.addActivity()
        try h.cache.connect(actor: h.actor, source: "apple_watch_steps_v1")
        async let a: Void = h.flow.refresh(first)
        async let b: Void = h.flow.refresh(second)
        _ = await (a, b)
        XCTAssertEqual(Set(h.uploads.map(\.challengeID)), [first, second])
        XCTAssertEqual(h.readers.count, 2)
        XCTAssertEqual(h.client.rows[first]?.own(h.actor)?.fact?.value, 10001)
        let restored = try FlowHarness(actor: h.actor, directory: h.directory)
        restored.client.rows = h.client.rows; restored.mode = .empty
        await restored.flow.refresh(first)
        XCTAssertEqual(restored.requests.count, 1, "A restored baseline still needs a fresh bounded read")
        XCTAssertEqual(restored.client.rows[first]?.own(h.actor)?.fact?.state, "unresolved")
        XCTAssertNil(restored.flow.states[first]?.localValue)
        XCTAssertTrue(restored.client.rows[second]?.own(h.actor)?.fact?.value == 10001)
        restored.flow.setActor(UUID())
        XCTAssertTrue(restored.flow.states.isEmpty)
        XCTAssertTrue(try restored.cache.pending(actor: UUID()).isEmpty)
    }

    func testCorruptComparisonAndUnavailableWorkCacheCreateUnresolvedReplacements() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let id = try h.addActivity()
        try h.cache.connect(actor: h.actor, source: "apple_watch_steps_v1")
        await h.flow.refresh(id)
        let request = try XCTUnwrap(h.requests.last)
        let file = h.cache.directory.appendingPathComponent(h.actor.uuidString.lowercased()).appendingPathComponent(try h.cache.key(request) + ".json")
        try Data("corrupt".utf8).write(to: file)
        h.flow.cancelAll()
        await h.flow.refresh(id)
        XCTAssertEqual(h.client.rows[id]?.own(h.actor)?.fact?.state, "unresolved")
        XCTAssertNil(h.flow.states[id]?.localValue)
        try Data("unavailable".utf8).write(to: file.deletingLastPathComponent().appendingPathComponent("work.json"))
        let before = h.requests.count
        await h.flow.refresh(id)
        XCTAssertEqual(h.requests.count, before, "Unavailable local state cannot be used as a new baseline")
        XCTAssertEqual(h.uploads.last?.revision, 3)
        XCTAssertEqual(h.client.rows[id]?.own(h.actor)?.fact?.state, "unresolved")
    }

    func testSuspensionStopsReadsAndCutoffRecoversWithoutNewFacts() async throws {
        let h = try FlowHarness(); defer { h.remove() }
        let id = try h.addActivity()
        try h.cache.connect(actor: h.actor, source: "apple_watch_steps_v1")
        await h.flow.refresh(id)
        h.client.suspended = true
        await h.flow.refresh(id)
        XCTAssertTrue(h.flow.suspended); XCTAssertTrue(h.flow.states.isEmpty)
        XCTAssertEqual(h.requests.count, 1)
        h.client.suspended = false; h.flow.restrict(false)
        h.now = h.now.addingTimeInterval(4 * 86400)
        h.client.now = h.now
        await h.flow.refresh(id)
        XCTAssertEqual(h.requests.count, 1); XCTAssertEqual(h.uploads.count, 1)
        XCTAssertTrue(try h.cache.pending(actor: h.actor).isEmpty)
    }
}

@MainActor private final class FlowHarness {
    enum Mode { case value, empty, truncated, failure }
    let actor: UUID, directory: URL, auth: FlowAuth, client = FlowClient(), permission = FlowPermission()
    let cache: ChallengeHealthComparisonCache, coordinator: ChallengeHealthTransportCoordinator
    var flow: ChallengeHealthFlowStore!
    var store: ChallengeV1Store!
    var now = Date(timeIntervalSince1970: 1_800_000_000)
    var mode: Mode = .value, holdRead = false, holdSign = false
    var heldRead: CheckedContinuation<Void, Never>?, heldSign: CheckedContinuation<Void, Never>?
    var readers: [FlowReader] = [], requests: [ChallengeHealthReadRequest] = [], uploads: [ChallengeHealthUploadRequest] = []
    var signed = 0, readinessSent = 0, loseReadinessResponse = false, loseUploadResponse = false
    var readinessFailure: ChallengeHealthReadinessClientError?
    var sessionIdentity: String? = "initial-session"
    init(actor: UUID = UUID(), directory: URL? = nil) throws {
        self.actor = actor; self.directory = directory ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        auth = FlowAuth(actor)
        cache = .init(directory: self.directory.appendingPathComponent("cache"))
        coordinator = .init(uploadStore: .init(directory: self.directory.appendingPathComponent("uploads")), readinessStore: .init(directory: self.directory.appendingPathComponent("readiness")))
        let session: @MainActor () -> WeeklyClientSession? = { [auth] in auth.actor.map { .init(actorID: $0, identity: "session") } }
        let sign: @MainActor (UUID, Data) async throws -> MetricSignedMaterial = { [unowned self] _, _ in
            self.signed += 1
            if self.holdSign { self.holdSign = false; await withCheckedContinuation { self.heldSign = $0 } }
            return .init(keyID: Data(repeating: 7, count: 32).base64EncodedString(), assertion: nextP9TestAssertion(), environment: .development)
        }
        let uploads = ChallengeHealthUploadClient(enabled: true, environment: .development, coordinator: coordinator, binding: session, sign: sign) { [unowned self] signed, _ in
            let wire = try ChallengeHealthUploadRequest(restoring: signed.exactBody); self.uploads.append(wire)
            try self.client.apply(wire)
            if self.loseUploadResponse { self.loseUploadResponse = false; throw URLError(.networkConnectionLost) }
            return try JSONSerialization.data(withJSONObject: ["version": "challenge_real_health_receipt_v1", "request_id": wire.requestID.uuidString.lowercased(), "challenge_id": wire.challengeID.uuidString.lowercased(), "revision": wire.revision, "accepted_at": "2027-01-15T08:00:00+00:00"])
        }
        let readiness = ChallengeHealthReadinessClient(enabled: true, environment: .development, coordinator: coordinator, binding: session, sign: sign) { [unowned self] signed, _ in
            let wire = try ChallengeHealthReadinessRequest(restoring: signed.exactBody); self.readinessSent += 1
            if self.loseReadinessResponse { self.loseReadinessResponse = false; throw URLError(.networkConnectionLost) }
            if let failure = self.readinessFailure { throw failure }
            return try JSONSerialization.data(withJSONObject: ["version": "challenge_real_health_readiness_receipt_v1", "request_id": wire.requestID.uuidString.lowercased(), "accepted_at": "2027-01-15T08:00:00+00:00"])
        }
        let store = ChallengeV1Store(auth: auth, client: client, requests: .init(directory: self.directory.appendingPathComponent("commands")))
        self.store = store
        store.setActor(actor); client.now = now
        let deps = ChallengeHealthFlowDependencies(coordinator: coordinator, uploads: uploads, readiness: readiness, cache: cache, permission: permission,
            reader: { [unowned self] _, _ in let reader = FlowReader(self); self.readers.append(reader); return reader },
            adapter: ChallengeHealthBindingMapper.adapter, now: { [unowned self] in self.now },
            actorSession: { [unowned self] in self.sessionIdentity.map { .init(actorID: self.actor, identity: $0) } })
        flow = ChallengeHealthFlowStore(auth: auth, challenges: store, dependencies: deps); flow.setActor(actor)
    }
    func binding(id: UUID = UUID(), source: ChallengeHealthRealSourcePolicy = .appleWatchAutomaticStepsV1, distance: Int64? = nil) throws -> ChallengeHealthBinding {
        try .init(actorID: actor, challengeID: id, agreementVersion: 1, termsDigest: String(repeating: "a", count: 64), metric: source.metric,
            challengeWindow: .init(startMicroseconds: ChallengeHealthFlowStore.microseconds(now), endMicroseconds: ChallengeHealthFlowStore.microseconds(now.addingTimeInterval(86400)), timeZoneIdentifier: "UTC", calendar: .gregorian), realSourcePolicy: source, selectedDistanceMillimeters: distance)
    }
    func addActivity(policy: String = "personal_steps_goal_v1", socialHidden: Bool = false) throws -> UUID {
        let format = ChallengeV1Policy(rawValue: policy)!
        let source = ChallengeHealthBindingMapper.selectedSource(format.metric)!.identifier
        let id = UUID(), start = ChallengeInstant(date: now.addingTimeInterval(-3600)), end = ChallengeInstant(date: now.addingTimeInterval(82800))
        let window = ChallengeV1.Window(startDate: "2027-01-15", days: 1, timezone: "UTC", amountCents: 100, distanceMm: format.metric == .timed ? 5_000_000 : nil, startsAt: start, endsAt: end, syncBy: .init(date: end.date.addingTimeInterval(86400)), correctionsBy: .init(date: end.date.addingTimeInterval(172800)), noticeDue: .init(date: end.date.addingTimeInterval(172800)))
        let encoder = JSONEncoder(); encoder.keyEncodingStrategy = .convertToSnakeCase
        let config = try JSONDecoder().decode(ChallengeJSON.self, from: encoder.encode(window))
        client.rows[id] = ChallengeV1(sourcePolicyVersion: source, id: id, creatorId: actor, policy: policy, config: window, status: "active", revision: 1, agreementVersion: 1, serverTime: .init(date: now), socialHidden: socialHidden,
            agreement: .init(digest: String(repeating: "a", count: 64), terms: .object(["source_policy_version": .string(source), "policy": .string(policy), "config": config, "score_rule": format.usesReceivedScores ? .string("received_by_correction_cutoff_v2") : .null])),
            members: [.init(actorId: actor, username: "local", target: format.hasTarget ? 10000 : nil, selected: true, exited: false, consented: true, fact: nil)], notice: nil, reviews: [], final: nil)
        return id
    }
    func remove() { flow.cancelAll(); try? FileManager.default.removeItem(at: directory) }
}
@MainActor private final class FlowReader: ChallengeHealthStore {
    unowned let h: FlowHarness
    init(_ h: FlowHarness) { self.h = h }
    func read(_ request: ChallengeHealthReadRequest) async -> ChallengeHealthStoreOutcome {
        h.requests.append(request)
        if h.holdRead { h.holdRead = false; await withCheckedContinuation { h.heldRead = $0 } }
        if Task.isCancelled { return .unavailable(.cancelled) }
        if h.mode == .failure { return .unavailable(.protectedDataUnavailable) }
        let start = request.queryWindow.interval.start.addingTimeInterval(1)
        let metric: WeeklySourceMetric = switch request.binding.metric {
        case .steps: .steps
        case .exerciseSeconds: .appleExerciseMinutes
        case .runningMillimeters, .timedRunElapsedSeconds: .runningDistanceMillimeters
        }
        let record = WeeklySourceRecord(id: request.binding.challengeID, metric: metric, start: start, end: start.addingTimeInterval(60), value: Double(request.binding.selectedDistanceMillimeters ?? 10001), sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1", wasUserEntered: false, workoutActivityType: metric == .runningDistanceMillimeters ? "running" : nil, wasIndoorWorkout: metric == .runningDistanceMillimeters ? false : nil)
        return .snapshot(.init(request: request, records: h.mode == .empty ? [] : [record], observedAt: h.now, sourceFreshness: h.now, evidence: h.mode == .truncated ? .truncated : .boundedSnapshot))
    }
}
@MainActor private final class FlowPermission: ChallengeHealthPermissionService {
    var supported = true
    func connect(_ metric: ChallengeHealthMetric) async throws {}
}
@MainActor private final class FlowAuth: AuthClient {
    var actor: UUID?
    init(_ actor: UUID) { self.actor = actor }
    func currentUserID() async -> UUID? { actor }
    func authStateChanges() async -> AsyncStream<AuthSnapshot> { AsyncStream { $0.finish() } }
    func signInWithApple(_ identity: AppleIdentity) async throws -> UUID { actor! }
    func signOut() async throws { actor = nil }
}
@MainActor private final class FlowClient: ChallengeV1Client {
    var rows: [UUID: ChallengeV1] = [:], suspended = false
    var now = Date()
    var appliedRequests: Set<UUID> = []
    func list(actor: UUID) async throws -> [ChallengeV1] { Array(rows.values) }
    func detail(_ id: UUID, actor: UUID) async throws -> ChallengeV1 {
        var body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(XCTUnwrap(rows[id]))) as! [String: Any]
        body["serverTime"] = ChallengeInstant(date: now).rawValue
        return try JSONDecoder().decode(ChallengeV1.self, from: JSONSerialization.data(withJSONObject: body))
    }
    func submit(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func abandon(_ request: ChallengeV1Request) async throws -> ChallengeV1Receipt { throw ChallengeV1Error.unavailable }
    func read<T: Decodable>(_ name: String, fields: [String: ChallengeJSON], actor: UUID, as type: T.Type) async throws -> T {
        let data = try JSONSerialization.data(withJSONObject: ["ageConfirmed": true, "betaAccess": true, "suspended": suspended])
        return try JSONDecoder().decode(T.self, from: data)
    }
    func apply(_ wire: ChallengeHealthUploadRequest) throws {
        guard appliedRequests.insert(wire.requestID).inserted else { return }
        var body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(XCTUnwrap(rows[wire.challengeID]))) as! [String: Any]
        var members = body["members"] as! [[String: Any]]
        let envelope = try JSONSerialization.jsonObject(with: wire.exactBytes) as! [String: Any]
        members[0]["fact"] = ["state": envelope["state"]!, "value": envelope["value"] ?? NSNull(), "recordedAt": ChallengeInstant(date: now).rawValue, "revision": wire.revision]
        body["members"] = members
        rows[wire.challengeID] = try JSONDecoder().decode(ChallengeV1.self, from: JSONSerialization.data(withJSONObject: body))
    }
}
