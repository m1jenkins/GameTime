#if DEBUG
import GameTimeCore
import XCTest
@testable import GameTime

@MainActor
final class SourceInvestigationTests: XCTestCase {
    func testNoReadBeforeExplicitOptInAndClearRevokesOptIn() async {
        var calls = 0
        let store = SourceInvestigationStore(read: { actor, metric, window, now in
            calls += 1
            return WeeklySourceCapture(accountID: actor, metric: metric, window: window,
                                       observedAt: now, state: .successfulQuery, records: [])
        })
        let window = DateInterval(start: Date().addingTimeInterval(-60), duration: 30)
        await store.refresh(metric: .steps, window: window)
        XCTAssertEqual(calls, 0)
        store.optIn()
        await store.refresh(metric: .steps, window: window)
        XCTAssertEqual(calls, 1)
        XCTAssertNotNil(store.capture)
        XCTAssertEqual(store.assessment?.supportsConfirmedMiss, false)
        store.clear()
        XCTAssertNil(store.capture)
        XCTAssertNil(store.assessment)
        await store.refresh(metric: .steps, window: window)
        XCTAssertEqual(calls, 1)
    }

    func testLateReadCannotRestoreClearedOrChangedSession() async {
        var continuation: CheckedContinuation<Void, Never>?
        let store = SourceInvestigationStore(read: { actor, metric, window, now in
            await withCheckedContinuation { continuation = $0 }
            return WeeklySourceCapture(accountID: actor, metric: metric, window: window,
                                       observedAt: now, state: .successfulQuery, records: [])
        })
        store.optIn()
        let task = Task { await store.refresh(metric: .steps,
            window: DateInterval(start: Date().addingTimeInterval(-60), duration: 30)) }
        while continuation == nil { await Task.yield() }
        store.clear()
        store.optIn()
        continuation?.resume()
        await task.value
        XCTAssertNil(store.capture)
        XCTAssertNil(store.assessment)
        XCTAssertFalse(store.busy)
    }
}
#endif
