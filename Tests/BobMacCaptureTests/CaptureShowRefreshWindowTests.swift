import XCTest

@testable import BobMacCapture

final class CaptureShowRefreshWindowTests: XCTestCase {
    func testFirstShowNeverSkips() {
        XCTAssertFalse(
            CaptureShowRefreshWindow.shouldSkipShowTriggeredRefresh(
                lastStartedAt: nil,
                now: Date(timeIntervalSince1970: 1_000)
            )
        )
    }

    func testShowInsideWindowSkips() {
        let started = Date(timeIntervalSince1970: 1_000)
        let now = started.addingTimeInterval(CaptureShowRefreshWindow.pullThrottleInterval - 0.01)
        XCTAssertTrue(
            CaptureShowRefreshWindow.shouldSkipShowTriggeredRefresh(
                lastStartedAt: started,
                now: now
            )
        )
    }

    func testShowOutsideWindowRuns() {
        let started = Date(timeIntervalSince1970: 1_000)
        let now = started.addingTimeInterval(CaptureShowRefreshWindow.pullThrottleInterval)
        XCTAssertFalse(
            CaptureShowRefreshWindow.shouldSkipShowTriggeredRefresh(
                lastStartedAt: started,
                now: now
            )
        )
    }

    func testSharedIntervalMatchesRefsPullThrottle() {
        XCTAssertEqual(
            CaptureShowRefreshWindow.pullThrottleInterval,
            RefsLibrary.pullThrottleInterval
        )
    }
}
