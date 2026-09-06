#if DEBUG || STAGING
import GameTimeCore
import XCTest

@testable import GameTime

final class WeeklyHealthSourceProbeTests: XCTestCase {
    @MainActor
    func testDefaultProbeCannotReadHealthOrRequestPermission() async throws {
        let probe = WeeklyHealthSourceProbe()
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for metric in WeeklySourceMetric.allCases {
            let capture = try await probe.capture(
                accountID: UUID(), metric: metric,
                window: DateInterval(start: start, duration: 60),
                observedAt: start.addingTimeInterval(120)
            )
            XCTAssertEqual(capture.state, .disabled)
            XCTAssertTrue(capture.records.isEmpty)
            do {
                try await probe.requestReadAuthorization(for: metric)
                XCTFail("A default-off probe must not request Health permission")
            } catch WeeklyHealthSourceProbe.ProbeError.disabled {
                // The guard runs before querying device availability or Health.
            }
        }
    }
}
#endif
