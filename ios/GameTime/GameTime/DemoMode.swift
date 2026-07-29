import SwiftUI

struct DemoModeAccess: Sendable {
    let isAvailable: Bool
    let isActive: Bool
    let enter: @MainActor @Sendable () -> Void
    let exit: @MainActor @Sendable () -> Void

    static let unavailable = DemoModeAccess(
        isAvailable: false,
        isActive: false,
        enter: {},
        exit: {}
    )
}

private struct DemoModeAccessKey: EnvironmentKey {
    static let defaultValue = DemoModeAccess.unavailable
}

extension EnvironmentValues {
    var demoMode: DemoModeAccess {
        get { self[DemoModeAccessKey.self] }
        set { self[DemoModeAccessKey.self] = newValue }
    }
}
