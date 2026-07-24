// swift-tools-version: 6.0
import PackageDescription

// GameTimeCore is the portable half of the client: pure Swift, no Apple
// frameworks, no I/O. Everything that can be expressed without HealthKit,
// CoreLocation, or SwiftUI lives here so that it compiles and tests on Linux
// CI as well as in Xcode.
//
// The app target (added in M8) depends on this package and holds everything
// that genuinely needs the device: HealthKit queries, CoreLocation region
// monitoring, App Attest, and the SwiftUI shell.
let package = Package(
    name: "GameTimeCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(name: "GameTimeCore", targets: ["GameTimeCore"])
    ],
    targets: [
        .target(
            name: "GameTimeCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "GameTimeCoreTests",
            dependencies: ["GameTimeCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
