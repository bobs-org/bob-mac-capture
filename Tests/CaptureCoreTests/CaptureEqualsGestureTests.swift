import XCTest

@testable import CaptureCore

final class CaptureEqualsGestureTests: XCTestCase {
    func testWindowIs350Milliseconds() {
        XCTAssertEqual(CaptureEqualsGesture.window, 0.350)
    }

    func testFastSecondAtTheWindowBoundary() {
        let first: TimeInterval = 1.0
        XCTAssertTrue(
            CaptureEqualsGesture.isFastSecond(
                first: first,
                second: first + CaptureEqualsGesture.window
            )
        )
        XCTAssertFalse(
            CaptureEqualsGesture.isFastSecond(
                first: first,
                second: first + CaptureEqualsGesture.window + 0.001
            )
        )
    }

    func testSynthesizedZeroTimestampsNeverQualify() {
        XCTAssertFalse(CaptureEqualsGesture.isFastSecond(first: 0, second: 0.1))
        XCTAssertFalse(CaptureEqualsGesture.isFastSecond(first: 1.0, second: 0))
        XCTAssertFalse(CaptureEqualsGesture.isFastSecond(first: 0, second: 0))
    }

    func testRepeatsNeverQualify() {
        XCTAssertFalse(
            CaptureEqualsGesture.isFastSecond(
                first: 1.0,
                second: 1.1,
                isRepeat: true
            )
        )
    }

    func testEarlierSecondNeverQualifies() {
        XCTAssertFalse(CaptureEqualsGesture.isFastSecond(first: 1.0, second: 0.9))
        XCTAssertFalse(CaptureEqualsGesture.isFastSecond(first: 1.0, second: 0.1))
        XCTAssertTrue(CaptureEqualsGesture.isFastSecond(first: 1.0, second: 1.0))
    }
}
