import XCTest

@testable import CaptureCore

final class CaptureEditWriteTests: XCTestCase {
    func testUnchangedDraftWritesNothing() {
        XCTAssertNil(captureWrittenByteRange(from: "@file:ready", to: "@file:ready"))
    }

    func testPureDeletionWritesNothing() {
        XCTAssertNil(captureWrittenByteRange(from: "@file:ready", to: "@file:read"))
    }

    func testTypedSeparator() {
        XCTAssertEqual(
            captureWrittenByteRange(from: "@file", to: "@file:"),
            CaptureRange(start: 5, end: 6)
        )
    }

    func testBurstIncludingSeparator() {
        XCTAssertEqual(
            captureWrittenByteRange(from: "@file", to: "@file:rea"),
            CaptureRange(start: 5, end: 9)
        )
    }

    func testInsertionIntoEmptyDraft() {
        XCTAssertEqual(
            captureWrittenByteRange(from: "", to: "@file:"),
            CaptureRange(start: 0, end: 6)
        )
    }

    func testInPlaceReplacement() {
        XCTAssertEqual(
            captureWrittenByteRange(from: "@file:ready", to: "@file:x"),
            CaptureRange(start: 6, end: 7)
        )
    }

    func testMultiBytePrefixUsesUTF8Offsets() {
        XCTAssertEqual(
            captureWrittenByteRange(from: "Hi 🧪 @file", to: "Hi 🧪 @file:"),
            CaptureRange(start: 13, end: 14)
        )
    }

    func testSeparatorMembership() {
        XCTAssertTrue(captureEditWroteSeparator(CaptureRange(start: 5, end: 9), before: 6))
        XCTAssertFalse(captureEditWroteSeparator(CaptureRange(start: 6, end: 9), before: 6))
        XCTAssertFalse(captureEditWroteSeparator(nil, before: 6))
        XCTAssertFalse(captureEditWroteSeparator(CaptureRange(start: 0, end: 1), before: 0))
    }
}
