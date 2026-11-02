import XCTest

@testable import CaptureCore

final class CaptureAgendaBoundaryRefreshTests: XCTestCase {
    func testPastBoundaryFiresImmediately() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let boundary = now.addingTimeInterval(-60)

        XCTAssertEqual(
            CaptureAgendaBoundaryRefresh.decision(
                refreshAt: boundary,
                lastFiredBoundary: nil,
                now: now
            ),
            .immediate
        )
    }

    func testRepeatedPastBoundaryDoesNotFireAgain() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let boundary = now.addingTimeInterval(-60)

        XCTAssertEqual(
            CaptureAgendaBoundaryRefresh.decision(
                refreshAt: boundary,
                lastFiredBoundary: boundary,
                now: now
            ),
            .none
        )
    }

    func testFutureBoundarySleepsUntilBoundary() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let boundary = now.addingTimeInterval(600)

        XCTAssertEqual(
            CaptureAgendaBoundaryRefresh.decision(
                refreshAt: boundary,
                lastFiredBoundary: nil,
                now: now
            ),
            .sleep(600)
        )
    }

    func testNewBoundaryRearmsAfterPreviousBoundaryFired() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let previousBoundary = now.addingTimeInterval(-60)
        let newBoundary = now.addingTimeInterval(-30)

        XCTAssertEqual(
            CaptureAgendaBoundaryRefresh.decision(
                refreshAt: newBoundary,
                lastFiredBoundary: previousBoundary,
                now: now
            ),
            .immediate
        )
    }
}
