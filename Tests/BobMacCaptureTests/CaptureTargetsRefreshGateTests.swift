import Foundation
import XCTest

@testable import BobMacCapture

final class CaptureTargetsRefreshGateTests: XCTestCase {
    func testFirstShowRuns() {
        var gate = CaptureTargetsRefreshGate(now: { Date(timeIntervalSince1970: 1_000) })
        XCTAssertTrue(gate.shouldRefresh(reason: .show))
        XCTAssertEqual(gate.lastStartedAt, Date(timeIntervalSince1970: 1_000))
    }

    func testShowInsideWindowSkips() {
        var current = Date(timeIntervalSince1970: 1_000)
        var gate = CaptureTargetsRefreshGate(now: { current })
        XCTAssertTrue(gate.shouldRefresh(reason: .show))
        current = Date(timeIntervalSince1970: 1_003)
        XCTAssertFalse(gate.shouldRefresh(reason: .show))
        // A skipped show leaves the recorded start untouched.
        XCTAssertEqual(gate.lastStartedAt, Date(timeIntervalSince1970: 1_000))
    }

    func testShowAtBoundaryRuns() {
        var current = Date(timeIntervalSince1970: 1_000)
        var gate = CaptureTargetsRefreshGate(now: { current })
        XCTAssertTrue(gate.shouldRefresh(reason: .show))
        current = Date(timeIntervalSince1970: 1_000)
            .addingTimeInterval(CaptureShowRefreshWindow.pullThrottleInterval)
        XCTAssertTrue(gate.shouldRefresh(reason: .show))
        XCTAssertEqual(gate.lastStartedAt, current)
    }

    func testShowOutsideWindowRuns() {
        var current = Date(timeIntervalSince1970: 1_000)
        var gate = CaptureTargetsRefreshGate(now: { current })
        XCTAssertTrue(gate.shouldRefresh(reason: .show))
        current = Date(timeIntervalSince1970: 1_000)
            .addingTimeInterval(CaptureShowRefreshWindow.pullThrottleInterval + 1)
        XCTAssertTrue(gate.shouldRefresh(reason: .show))
    }

    func testNonShowReasonsBypassInsideWindow() {
        var current = Date(timeIntervalSince1970: 1_000)
        var gate = CaptureTargetsRefreshGate(now: { current })
        XCTAssertTrue(gate.shouldRefresh(reason: .show))
        current = Date(timeIntervalSince1970: 1_001)
        for reason: CaptureTargetsRefreshReason in [.launch, .watcher, .recheck, .failureRecovery] {
            XCTAssertTrue(gate.shouldRefresh(reason: reason), "expected \(reason) to bypass the window")
            current = current.addingTimeInterval(0.5)
        }
    }

    func testSingleInstantDrivesSkipAndRecord() {
        var calls = 0
        var current = Date(timeIntervalSince1970: 2_000)
        var gate = CaptureTargetsRefreshGate(now: {
            calls += 1
            return current
        })
        XCTAssertTrue(gate.shouldRefresh(reason: .show))
        XCTAssertEqual(calls, 1)
        current = current.addingTimeInterval(1)
        XCTAssertFalse(gate.shouldRefresh(reason: .show))
        XCTAssertEqual(calls, 2)
    }
}
