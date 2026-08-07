import SwiftUI

@main
struct GameTimeWatchApp: App {
    @State private var connection = WatchConnectionModel()

    var body: some Scene {
        WindowGroup {
            WatchConnectionView(connection: connection)
                .task {
                    connection.activate()
                }
        }
    }
}
