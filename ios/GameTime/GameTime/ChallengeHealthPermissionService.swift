import Foundation
import GameTimeCore
import HealthKit
import Network
import UIKit

@MainActor
final class HealthKitChallengeHealthPermissionService: ChallengeHealthPermissionService {
    private let health = HKHealthStore()
    private var observers: [HKObserverQuery] = []
    private var notification: NSObjectProtocol?
    private var monitor: NWPathMonitor?
    private var sources: Set<String> = []
    private var active = false
    private var update: (@MainActor @Sendable () -> Void)?
    var supported: Bool { HKHealthStore.isHealthDataAvailable() }

    func connect(_ metric: ChallengeHealthMetric) async throws {
        guard supported else { throw ChallengeV1Error.unavailable }
        let type: HKObjectType = switch metric {
        case .steps: HKQuantityType(.stepCount)
        case .exerciseSeconds: HKQuantityType(.appleExerciseTime)
        case .runningMillimeters, .timedRunElapsedSeconds: HKWorkoutType.workoutType()
        }
        try await health.requestAuthorization(toShare: [], read: [type])
    }
    func updates(for sources: Set<String>, active: Bool, perform: @escaping @MainActor @Sendable () -> Void) {
        update = active ? perform : nil
        guard self.sources != sources || self.active != active else { return }
        self.sources = sources; self.active = active
        for observer in observers { health.stop(observer) }; observers = []
        if let notification { NotificationCenter.default.removeObserver(notification); self.notification = nil }
        monitor?.cancel(); monitor = nil
        guard active else { return }
        // Unlock/network recovery must work even when the protected connection
        // cache could not be read at launch. These observers never read Health.
        notification = NotificationCenter.default.addObserver(forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil, queue: .main) { [weak self] _ in Task { @MainActor [weak self] in self?.update?() } }
        let monitor = NWPathMonitor(); self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor [weak self] in self?.update?() } }
        }
        monitor.start(queue: DispatchQueue(label: "GameTime.challenge-health-connectivity"))
        guard !sources.isEmpty, supported else { return }
        var types: [HKSampleType] = []
        if sources.contains("apple_watch_steps_v1") { types.append(HKQuantityType(.stepCount)) }
        if sources.contains("apple_watch_exercise_credit_v2") { types.append(HKQuantityType(.appleExerciseTime)) }
        if sources.contains(where: { $0.hasPrefix("apple_workout_outdoor_") }) { types.append(HKWorkoutType.workoutType()) }
        for type in types {
            let query = HKObserverQuery(sampleType: type, predicate: nil) { [weak self] _, completion, _ in
                // Scheduling is bounded. A network request never holds Health's completion.
                Task { @MainActor [weak self] in self?.update?() }
                completion()
            }
            observers.append(query); health.execute(query)
            health.enableBackgroundDelivery(for: type, frequency: .hourly) { _, _ in }
        }
    }
}
