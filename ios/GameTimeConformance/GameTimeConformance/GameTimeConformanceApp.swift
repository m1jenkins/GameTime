import Foundation
import SwiftUI

@main
@MainActor
struct GameTimeConformanceApp: App {
    @StateObject private var model = ConformanceViewModel()

    var body: some Scene {
        WindowGroup {
#if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("--conformance") {
                ContentView(model: model)
            } else {
                GameTimePreviewAppView()
            }
#else
            ContentView(model: model)
#endif
        }
    }
}
