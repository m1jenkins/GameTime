import Foundation
import Testing
@testable import GameTimeCore

@Suite("Challenge Health Apple Workout outdoor running adapters")
struct ChallengeHealthRealRunningAdapterTests {
  typealias F = ChallengeHealthFixtures
  private func binding(_ metric: ChallengeHealthMetric, _ policy: ChallengeHealthRealSourcePolicy) throws -> ChallengeHealthBinding {
    try ChallengeHealthBinding(actorID: F.id(1), challengeID: F.id(2), agreementVersion: 1,
      termsDigest: String(repeating: "a", count: 64), metric: metric, challengeWindow: F.window(start: 1_000, end: 2_000), realSourcePolicy: policy)
  }
  private func timedBinding(distance: Int64 = 100) throws -> ChallengeHealthBinding {
    try ChallengeHealthBinding(actorID: F.id(1), challengeID: F.id(2), agreementVersion: 1,
      termsDigest: String(repeating: "a", count: 64), metric: .timedRunElapsedSeconds,
      challengeWindow: F.window(start: 1_000, end: 2_000),
      realSourcePolicy: .appleWorkoutOutdoorTimedV1, selectedDistanceMillimeters: distance)
  }
  private func request() throws -> ChallengeHealthReadRequest {
    let b = try binding(.runningMillimeters, .appleWorkoutOutdoorDistanceV1)
    return try ChallengeHealthReadRequest(binding: b, deviceRequestID: F.id(3), queryWindow: b.challengeWindow, purpose: .challengeActivity)
  }
  private func run(_ id: Int = 10, _ start: Double = 1_100, _ end: Double = 1_160, _ value: Double = 1_500.9) -> WeeklySourceRecord {
    WeeklySourceRecord(id: F.id(id), metric: .runningDistanceMillimeters, start: F.date(start), end: F.date(end), value: value,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1", wasUserEntered: nil,
      workoutActivityType: "running", wasIndoorWorkout: false)
  }
  private func timedRequest(purpose: ChallengeHealthReadRequest.Purpose = .challengeActivity,
                            distance: Int64 = 100) throws -> ChallengeHealthReadRequest {
    let b = try timedBinding(distance: distance)
    return try ChallengeHealthReadRequest(binding: b, deviceRequestID: F.id(3),
      queryWindow: purpose == .readinessHistory
        ? F.window(start: -90 * 86_400 - 10_000, end: 1_000)
        : b.challengeWindow,
      purpose: purpose)
  }
  @Test("whole outdoor workouts floor cumulative millimetres")
  func cumulative() throws {
    let result = ChallengeHealthAppleWorkoutDistanceAdapter().evaluate(try F.snapshot([run(), run(11, 1_200, 1_260, 2_000.9)], request: request(), observed: 2_000, freshness: 2_000))
    #expect(result.activity?.integerValue == 3_501)
    #expect(result.permitsRealIngestion)
  }
  @Test("indoor, crossing, and overlap workouts never aggregate")
  func rejects() throws {
    let q = try request()
    var indoor = run(); indoor = WeeklySourceRecord(id: indoor.id, metric: indoor.metric, start: indoor.start, end: indoor.end, value: indoor.value, sourceBundleIdentifier: indoor.sourceBundleIdentifier, sourceProductType: indoor.sourceProductType, workoutActivityType: "running", wasIndoorWorkout: true)
    #expect(ChallengeHealthAppleWorkoutDistanceAdapter().evaluate(try F.snapshot([indoor], request: q, observed: 2_000, freshness: 2_000)).issues.contains(.sourceExplicitlyRejected))
    #expect(ChallengeHealthAppleWorkoutDistanceAdapter().evaluate(try F.snapshot([run(), run(11, 1_150, 1_220)], request: q, observed: 2_000, freshness: 2_000)).issues.contains(.reconciliationUnresolved))
  }
  @Test("sync corrections, visibility loss, and explicit deletions reconcile conservatively")
  func reconciliation() throws {
    let q = try request(); let adapter = ChallengeHealthAppleWorkoutDistanceAdapter()
    let old = WeeklySourceRecord(id: F.id(10), metric: .runningDistanceMillimeters, start: F.date(1_100), end: F.date(1_160), value: 2_000,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1", syncIdentifier: "sync", syncVersion: 1, workoutActivityType: "running", wasIndoorWorkout: false)
    let correction = WeeklySourceRecord(id: F.id(11), metric: .runningDistanceMillimeters, start: F.date(1_100), end: F.date(1_160), value: 1_500,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1", syncIdentifier: "sync", syncVersion: 2, workoutActivityType: "running", wasIndoorWorkout: false)
    let prior = try F.snapshot([old], request: q, observed: 1_900, freshness: 1_900)
    #expect(adapter.evaluate(try F.snapshot([correction], request: q, observed: 2_000, freshness: 2_000), replacing: prior).activity?.integerValue == 1_500)
    #expect(adapter.evaluate(try F.snapshot([], request: q, observed: 2_000, freshness: 2_000), replacing: prior).issues.contains(.lostVisibility))
    let deleted = adapter.evaluate(try F.snapshot([], request: q, observed: 2_000, freshness: 2_000, evidence: .boundedSnapshotAfterDeletion, deleted: [old.id]), replacing: prior)
    #expect(deleted.realReplacementDecision == .uploadable(.deleted))
  }

  @Test("timed runs use raw inclusive 100-to-102 percent distance and ceiling elapsed seconds")
  func timedQualificationBoundaries() throws {
    let request = try timedRequest(); let adapter = ChallengeHealthAppleWorkoutTimedAdapter()
    let lower = run(10, 1_100, 1_160.01, 100)
    let upper = run(11, 1_200, 1_259.1, 102)
    let eligible = adapter.evaluate(try F.snapshot([lower, upper], request: request,
      observed: 2_000, freshness: 2_000))
    #expect(eligible.activity?.integerValue == 60)

    for record in [run(12, 1_100, 1_160, 99.999), run(13, 1_100, 1_160, 102.001)] {
      let rejected = adapter.evaluate(try F.snapshot([record], request: request,
        observed: 2_000, freshness: 2_000))
      #expect(rejected.activity == nil)
      #expect(rejected.issues.contains(.timedQualificationUnresolved))
    }
  }

  @Test("timed runs include pauses, select the lowest elapsed whole workout, and retain equal times")
  func timedElapsedAndTies() throws {
    let request = try timedRequest(); let adapter = ChallengeHealthAppleWorkoutTimedAdapter()
    let paused = WeeklySourceRecord(id: F.id(10), metric: .runningDistanceMillimeters,
      start: F.date(1_100), end: F.date(1_200), value: 100,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1",
      wasUserEntered: false, reportedWorkoutDurationSeconds: 10,
      workoutActivityType: "running", wasIndoorWorkout: false)
    let tie = run(11, 1_300, 1_400, 101)
    let result = adapter.evaluate(try F.snapshot([paused, tie], request: request,
      observed: 2_000, freshness: 2_000))
    #expect(result.activity?.integerValue == 100)
    #expect(result.activity?.integerValue != 10)
  }

  @Test("timed readiness requires a completed 90-calendar-day comparable history")
  func timedReadinessHistory() throws {
    let binding = try timedBinding()
    let complete = try timedRequest(purpose: .readinessHistory)
    let comparable = run(10, -200, -140, 100)
    let adapter = ChallengeHealthAppleWorkoutTimedAdapter()
    let ready = adapter.evaluate(try F.snapshot([comparable], request: complete,
      observed: 1_000, freshness: 1_000))
    #expect(ready.readiness == .ready && ready.permitsRealConsent)

    let short = try ChallengeHealthReadRequest(binding: binding, deviceRequestID: F.id(4),
      queryWindow: F.window(start: -30 * 86_400 + 1_000, end: 1_000), purpose: .readinessHistory)
    let shortResult = adapter.evaluate(try F.snapshot([comparable], request: short,
      observed: 1_000, freshness: 1_000))
    #expect(shortResult.issues.contains(.historyLimited))
    #expect(shortResult.readiness != .ready)

    let futureEnded = adapter.evaluate(try F.snapshot([comparable], request: complete,
      observed: 999, freshness: 999))
    #expect(futureEnded.issues.contains(.historyLimited))
  }

  @Test("a tombstoned fastest whole timed run is replaced by the lower remaining observation")
  func timedDeletionLowersReplacement() throws {
    let request = try timedRequest(); let adapter = ChallengeHealthAppleWorkoutTimedAdapter()
    let fastest = run(10, 1_100, 1_160, 100)
    let slower = run(11, 1_300, 1_400, 100)
    let previous = try F.snapshot([fastest, slower], request: request, observed: 1_900, freshness: 1_900)
    #expect(adapter.evaluate(previous).activity?.integerValue == 60)
    let replacement = adapter.evaluate(try F.snapshot([slower], request: request,
      observed: 2_000, freshness: 2_000, evidence: .boundedSnapshotAfterDeletion,
      deleted: [fastest.id]), replacing: previous)
    #expect(replacement.activity?.integerValue == 100)
    #expect(replacement.issues.contains(.deletionObserved))
    #expect(replacement.realReplacementDecision == .uploadable(
      try ChallengeHealthReplacement.value(.init(metric: .timedRunElapsedSeconds, integerValue: 100))
    ))
  }

  @Test("a tombstoned present workout and a post-observation workout stay unresolved")
  func conflictingDeletionAndFutureWorkoutFailClosed() throws {
    let request = try request(); let adapter = ChallengeHealthAppleWorkoutDistanceAdapter()
    let presentAndDeleted = run()
    let conflict = adapter.evaluate(try F.snapshot([presentAndDeleted], request: request,
      observed: 2_000, freshness: 2_000, evidence: .boundedSnapshotAfterDeletion,
      deleted: [presentAndDeleted.id]))
    #expect(conflict.issues.contains(.invalidSnapshot))
    #expect(conflict.activity == nil)

    let postObservation = run(11, 1_400, 1_600, 1_500)
    let future = adapter.evaluate(try F.snapshot([postObservation], request: request,
      observed: 1_500, freshness: 1_500))
    #expect(future.issues.contains(.boundaryUnresolved))
    #expect(future.activity == nil)
  }

  @Test("whole-workout source admission preserves exact bounds and ignores crossings")
  func wholeWorkoutSourceAndBoundaryPolicy() throws {
    let query = try request(); let adapter = ChallengeHealthAppleWorkoutDistanceAdapter()
    for distance in [100.0, 102.0] {
      let timed = try timedRequest()
      let accepted = ChallengeHealthAppleWorkoutTimedAdapter().evaluate(try F.snapshot(
        [run(10, 1_100, 1_160, distance)], request: timed, observed: 2_000, freshness: 2_000))
      #expect(accepted.activity?.integerValue == 60)
    }
    let crossingStart = run(11, 900, 1_100, 2_000)
    let crossingEnd = run(12, 1_900, 2_100, 2_000)
    let crossings = adapter.evaluate(try F.snapshot([crossingStart, crossingEnd], request: query,
      observed: 2_500, freshness: 2_500))
    #expect(crossings.activity == nil)
    #expect(!crossings.issues.contains(.boundaryUnresolved))

    let watchTwo = WeeklySourceRecord(id: F.id(13), metric: .runningDistanceMillimeters,
      start: F.date(1_300), end: F.date(1_360), value: 1_000,
      sourceBundleIdentifier: "com.apple.health.device-two", sourceProductType: "Watch8,2",
      wasUserEntered: false, workoutActivityType: "running", wasIndoorWorkout: false)
    let aggregate = adapter.evaluate(try F.snapshot([run(10, 1_100, 1_160, 1_000), watchTwo], request: query,
      observed: 2_000, freshness: 2_000))
    #expect(aggregate.activity?.integerValue == 2_000)
  }

  @Test("known rejected writers are excluded while unknown provenance and negative revisions fail closed")
  func sourceRejectionAndSyncValidation() throws {
    let query = try request(); let adapter = ChallengeHealthAppleWorkoutDistanceAdapter()
    let manual = WeeklySourceRecord(id: F.id(11), metric: .runningDistanceMillimeters,
      start: F.date(1_300), end: F.date(1_360), value: 1_000,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1", wasUserEntered: true,
      workoutActivityType: "running", wasIndoorWorkout: false)
    let thirdParty = WeeklySourceRecord(id: F.id(12), metric: .runningDistanceMillimeters,
      start: F.date(1_400), end: F.date(1_460), value: 1_000,
      sourceBundleIdentifier: "com.example.runner", sourceProductType: "Watch7,1", wasUserEntered: false,
      workoutActivityType: "running", wasIndoorWorkout: false)
    let phone = WeeklySourceRecord(id: F.id(13), metric: .runningDistanceMillimeters,
      start: F.date(1_500), end: F.date(1_560), value: 1_000,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "iPhone17,1", wasUserEntered: false,
      workoutActivityType: "running", wasIndoorWorkout: false)
    let accepted = adapter.evaluate(try F.snapshot([run(), manual, thirdParty, phone], request: query,
      observed: 2_000, freshness: 2_000))
    #expect(accepted.activity?.integerValue == 1_500)
    #expect(accepted.issues.contains(.sourceExplicitlyRejected))

    let unknown = adapter.evaluate(try F.snapshot([run(), WeeklySourceRecord(id: F.id(14),
      metric: .runningDistanceMillimeters, start: F.date(1_300), end: F.date(1_360), value: 1_000,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,x", wasUserEntered: false,
      workoutActivityType: "running", wasIndoorWorkout: false)], request: query, observed: 2_000, freshness: 2_000))
    #expect(unknown.activity == nil && unknown.issues.contains(.realSourceProvenanceUnavailable))

    let negativeSync = WeeklySourceRecord(id: F.id(15), metric: .runningDistanceMillimeters,
      start: F.date(1_300), end: F.date(1_360), value: 1_000,
      sourceBundleIdentifier: "com.apple.health", sourceProductType: "Watch7,1", wasUserEntered: false,
      syncIdentifier: "bad-revision", syncVersion: -1, workoutActivityType: "running", wasIndoorWorkout: false)
    let revision = adapter.evaluate(try F.snapshot([run(), negativeSync], request: query,
      observed: 2_000, freshness: 2_000))
    #expect(revision.activity == nil && revision.issues.contains(.reconciliationUnresolved))
  }

  @Test("truncation and limited or late authorization history cannot make readiness ready")
  func boundedHistoryRequirements() throws {
    let timed = try timedRequest(purpose: .readinessHistory)
    let comparable = run(10, -200, -140, 100)
    let adapter = ChallengeHealthAppleWorkoutTimedAdapter()
    let truncated = adapter.evaluate(try F.snapshot([comparable], request: timed, observed: 1_000,
      freshness: 1_000, evidence: .truncated))
    #expect(truncated.activity == nil && truncated.issues.contains(.incompleteEvidence))
    let limited = adapter.evaluate(try F.snapshot([comparable], request: timed, observed: 1_000,
      freshness: 1_000, evidence: .limitedHistory))
    #expect(limited.readiness != .ready && limited.issues.contains(.historyLimited))
    let lateAuthorization = adapter.evaluate(try F.snapshot([comparable], request: timed, observed: 1_000,
      freshness: 1_000, earliest: 0))
    #expect(lateAuthorization.readiness != .ready && lateAuthorization.issues.contains(.historyLimited))
  }
}
