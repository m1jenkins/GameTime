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
  private(set) var deviceRegistration: PushDeviceRegistration?
  private(set) var pendingDestination: PushStandingsDestination?

  @ObservationIgnored private var environment: PushTokenEnvironment?
  @ObservationIgnored private var bundleID: String?
  @ObservationIgnored private var isConfigured = false

  nonisolated static func pushEnvironment(
    for appEnvironment: AppEnvironment
  ) -> PushTokenEnvironment? {
    _ = appEnvironment
    // Push stays disabled until contextual consent, category preferences,
    // server suppression and delivery acceptance are implemented together.
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

    // Configuration must never prompt for permission at app launch. A future
    // user-created reminder flow owns that request after preferences are saved.
    // Do not register legacy lead-loss or comeback actions for new products.
    UNUserNotificationCenter.current().delegate = self
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
    // Ignore dormant/legacy pushes; new categories need current authorization.
    []
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
    environmentValue: String?,
    arguments: [String] = ProcessInfo.processInfo.arguments,
    processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
    isSimulator: Bool = {
      #if targetEnvironment(simulator)
      true
      #else
      false
      #endif
    }()
  ) -> Bool {
    guard
      let environment = AppEnvironment(
        rawValue: environmentValue?.lowercased() ?? ""
      )
    else {
      return false
    }
    guard !isSimulator,
      !arguments.contains("--fixture-mode"),
      !arguments.contains("--disable-health-background-delivery"),
      processEnvironment["XCTestConfigurationFilePath"] == nil,
      processEnvironment["XCTestBundlePath"] == nil
    else { return false }
    switch environment {
    case .debug, .staging, .release: return true
    }
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
