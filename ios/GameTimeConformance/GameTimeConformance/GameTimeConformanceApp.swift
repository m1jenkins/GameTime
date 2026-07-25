import SwiftUI

@main
@MainActor
struct GameTimeConformanceApp: App {
    @StateObject private var model = ConformanceViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
        }
    }
}
