import Foundation
import HealthKit

/// Launch-time HealthKit observer used only by the Staging target. HealthKit
/// owns the wake schedule; durable metric and coverage stores own retry safety.
@MainActor
protocol PersonalHealthBackgroundDeliveryRegistering: AnyObject {
    func retryRegistration()
}

@MainActor
class PersonalHealthBackgroundDeliveryCoordinator:
    PersonalHealthBackgroundDeliveryRegistering
{
    typealias UpdateHandler = @MainActor () async -> Void

    private let healthStore: HKHealthStore
    private var observerQuery: HKObserverQuery?
    private var updateHandler: UpdateHandler?
    private var pendingLaunchCompletion: (() -> Void)?
    private(set) var isBackgroundDeliveryEnabled = false

    init(healthStore: HKHealthStore = HKHealthStore()) {
        self.healthStore = healthStore
    }

    func setUpdateHandler(_ handler: UpdateHandler?) async {
        updateHandler = handler
        guard
            let handler,
            let pendingLaunchCompletion
        else { return }
        self.pendingLaunchCompletion = nil
        await handler()
        pendingLaunchCompletion()
    }

    func start() {
        guard
            healthDataIsAvailable(),
            let steps = HKObjectType.quantityType(forIdentifier: .stepCount)
        else { return }

        if observerQuery == nil {
            observerQuery = installObserver(for: steps)
        }
        requestBackgroundDelivery(for: steps)
    }

    func retryRegistration() {
        // This is deliberately idempotent. A first launch may precede Health
        // authorization, so a completed authorization must retry enablement
        // without installing a second long-running observer query.
        start()
    }

    func healthDataIsAvailable() -> Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func installObserver(for steps: HKQuantityType) -> HKObserverQuery {
        let query = HKObserverQuery(sampleType: steps, predicate: nil) {
            [weak self] _, completion, error in
                let completionBox = HealthObserverCompletion(completion)
                let hadError = error != nil
                Task { @MainActor [weak self] in
                    guard let self else {
                        completionBox.call()
                        return
                    }
                    await self.receiveUpdate(
                        hadError: hadError,
                        completion: completionBox.call
                    )
                }
        }
        healthStore.execute(query)
        return query
    }

    func requestBackgroundDelivery(for steps: HKQuantityType) {
        healthStore.enableBackgroundDelivery(
            for: steps,
            frequency: .hourly
        ) { [weak self] enabled, error in
            Task { @MainActor [weak self] in
                self?.recordBackgroundDeliveryResult(
                    enabled: enabled,
                    hadError: error != nil
                )
            }
        }
    }

    func recordBackgroundDeliveryResult(
        enabled: Bool,
        hadError: Bool
    ) {
        isBackgroundDeliveryEnabled = enabled && !hadError
    }

    /// Kept internal so completion ordering can be proven without pretending
    /// that Simulator can deliver a real HealthKit background wake.
    func receiveUpdate(
        hadError: Bool,
        completion: @escaping () -> Void
    ) async {
        guard !hadError else {
            completion()
            return
        }
        guard let updateHandler else {
            if pendingLaunchCompletion == nil {
                pendingLaunchCompletion = completion
            } else {
                // One pending wake is sufficient because the eventual sync
                // requeries the complete eligible challenge window.
                completion()
            }
            return
        }
        await updateHandler()
        completion()
    }
}

/// HealthKit documents its observer completion handler as callable after
/// asynchronous processing. This box makes that SDK guarantee explicit across
/// Swift's actor handoff without treating arbitrary closures as Sendable.
private struct HealthObserverCompletion: @unchecked Sendable {
    let call: () -> Void

    init(_ call: @escaping () -> Void) {
        self.call = call
    }
}
