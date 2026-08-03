import Observation
import UIKit
import UserNotifications

struct PushDeviceRegistration: Equatable, Sendable {
  let deviceToken: String
  let environment: PushTokenEnvironment
  let bundleID: String
}

struct PushStandingsDestination: Equatable, Sendable {
  let contestID: UUID
  let sendsComebackReaction: Bool
}

@MainActor
@Observable
final class PushNotificationCoordinator: NSObject,
  UNUserNotificationCenterDelegate
{
  nonisolated static let leadLostCategory = "GAMETIME_LEAD_LOST"
  nonisolated static let comebackAction = "GAMETIME_COMEBACK_ACTION"

  private(set) var deviceRegistration: PushDeviceRegistration?
  private(set) var pendingDestination: PushStandingsDestination?

  @ObservationIgnored private var environment: PushTokenEnvironment?
  @ObservationIgnored private var bundleID: String?
  @ObservationIgnored private var isConfigured = false

  nonisolated static func pushEnvironment(
    for appEnvironment: AppEnvironment
  ) -> PushTokenEnvironment? {
    _ = appEnvironment
    // Social push categories are dormant while Personal V1 is the only
    // reachable product model.
    return nil
  }

  func configure(
    environment: AppEnvironment,
    bundleID: String?
  ) async {
    guard
      !isConfigured,
      let pushEnvironment = Self.pushEnvironment(for: environment),
      let bundleID
    else {
      return
    }
    isConfigured = true
    self.environment = pushEnvironment
    self.bundleID = bundleID

    let reaction = UNNotificationAction(
      identifier: Self.comebackAction,
      title: "I’m coming back",
      options: [.foreground]
    )
    let category = UNNotificationCategory(
      identifier: Self.leadLostCategory,
      actions: [reaction],
      intentIdentifiers: []
    )
    let center = UNUserNotificationCenter.current()
    center.delegate = self
    center.setNotificationCategories([category])

    do {
      let granted = try await center.requestAuthorization(
        options: [.alert, .badge, .sound]
      )
      guard granted else { return }
      UIApplication.shared.registerForRemoteNotifications()
    } catch {
      // Permission remains user-controlled. The app continues to expose
      // standings and reactions without treating push as correctness.
    }
  }

  func didRegister(deviceToken: Data) {
    guard let environment, let bundleID else { return }
    deviceRegistration = PushDeviceRegistration(
      deviceToken: deviceToken.map { String(format: "%02x", $0) }.joined(),
      environment: environment,
      bundleID: bundleID
    )
  }

  func consumeDestination() {
    pendingDestination = nil
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .list, .sound]
  }

  nonisolated func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse
  ) async {
    _ = (center, response)
  }
}

@MainActor
final class GameTimeAppDelegate: NSObject, UIApplicationDelegate {
  @MainActor weak var pushCoordinator: PushNotificationCoordinator?
  let personalHealthBackgroundDelivery =
    PersonalHealthBackgroundDeliveryCoordinator()

  nonisolated static func shouldStartPersonalHealthBackgroundDelivery(
    environmentValue: String?
  ) -> Bool {
    environmentValue?.lowercased() == AppEnvironment.staging.rawValue
  }

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions:
      [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    _ = (application, launchOptions)
    let environmentValue = Bundle.main.object(
      forInfoDictionaryKey: "GAMETIME_ENV"
    ) as? String
    if Self.shouldStartPersonalHealthBackgroundDelivery(
      environmentValue: environmentValue
    ) {
      // Apple requires observer queries to be installed during launch so a
      // HealthKit wake can be delivered before SwiftUI finishes mounting.
      personalHealthBackgroundDelivery.start()
    }
    return true
  }

  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    Task { @MainActor [weak self] in
      self?.pushCoordinator?.didRegister(deviceToken: deviceToken)
    }
  }

  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: any Error
  ) {
    // Registration is best effort and will be requested again on a future
    // app launch. Do not expose token or provider detail in product logs.
  }
}
