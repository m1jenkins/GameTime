/// Namespace for portable GameTime client logic.
///
/// This module is deliberately free of Apple framework imports. That is not
/// stylistic: it is what allows the client's domain logic to be compiled and
/// tested on Linux CI, where no Apple SDK exists. Anything that must import
/// HealthKit, CoreLocation, DeviceCheck, or SwiftUI belongs in the app target,
/// behind a protocol declared here.
public enum GameTimeCore {
    /// Minimum supported OS, mirroring `Package.swift`.
    ///
    /// See DECISIONS.md for why iOS 18 rather than 17 or 26.
    public static let minimumIOSVersion = "18.0"
}
