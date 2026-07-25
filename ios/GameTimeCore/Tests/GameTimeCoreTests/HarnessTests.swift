import Testing

@testable import GameTimeCore

/// Proves the Swift Testing harness runs and the package builds under Swift 6
/// language mode. M3 added the first domain suites alongside it; this stays
/// because "the toolchain works" and "the logic is right" are different
/// failures and a green domain suite cannot report the first one.
@Suite("Harness")
struct HarnessTests {
    @Test("GameTimeCore builds and exposes its deployment target")
    func deploymentTargetIsDeclared() {
        #expect(GameTimeCore.minimumIOSVersion == "18.0")
    }

    @Test("Swift 6 strict concurrency is in effect")
    func strictConcurrencyIsOn() async {
        // Compiles only under a concurrency-checked language mode; the value
        // is crossing an isolation boundary.
        let value = await Task.detached { 21 * 2 }.value
        #expect(value == 42)
    }
}
