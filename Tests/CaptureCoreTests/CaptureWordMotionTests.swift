import Foundation
import XCTest

@testable import CaptureCore

final class CaptureWordMotionTests: XCTestCase {
    private func expect(
        _ direction: CaptureWordMotion.Direction,
        _ unit: CaptureWordMotion.Unit,
        in text: String,
        from: Int,
        to expected: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            CaptureWordMotion.targetLocation(
                direction,
                unit,
                in: text,
                selectedRange: NSRange(location: from, length: 0)
            ),
            expected,
            "from \(from) in \(text.debugDescription)",
            file: file,
            line: line
        )
    }

    func testBigWordForwardAcrossCaptureSigils() {
        let text = "@foo#bar some-task %t"
        expect(.forward, .bigWord, in: text, from: 0, to: 9)
        expect(.forward, .bigWord, in: text, from: 9, to: 19)
        expect(.forward, .bigWord, in: text, from: 19, to: 21)
        expect(.forward, .bigWord, in: text, from: 21, to: 21)
    }

    func testBigWordBackwardAcrossCaptureSigils() {
        let text = "@foo#bar some-task %t"
        expect(.backward, .bigWord, in: text, from: 21, to: 19)
        expect(.backward, .bigWord, in: text, from: 19, to: 9)
        expect(.backward, .bigWord, in: text, from: 12, to: 9)
        expect(.backward, .bigWord, in: text, from: 9, to: 0)
        expect(.backward, .bigWord, in: text, from: 0, to: 0)
    }

    func testSmallWordForwardSplitsSigils() {
        let text = "@foo#bar some-task %t"
        let from = [0, 1, 4, 5, 9, 13, 14, 19, 20]
        let expected = [1, 4, 5, 9, 13, 14, 19, 20, 21]
        for (start, end) in zip(from, expected) {
            expect(.forward, .word, in: text, from: start, to: end)
        }
    }

    func testSmallWordBackwardSplitsSigils() {
        let text = "@foo#bar some-task %t"
        let from = [21, 20, 19, 14, 13, 9, 5, 4, 1]
        let expected = [20, 19, 14, 13, 9, 5, 4, 1, 0]
        for (start, end) in zip(from, expected) {
            expect(.backward, .word, in: text, from: start, to: end)
        }
    }

    func testEmptyLineIsAStop() {
        let text = "x1 done\n\n  - bullet one"
        expect(.forward, .bigWord, in: text, from: 3, to: 8)
        expect(.forward, .bigWord, in: text, from: 8, to: 11)
        expect(.forward, .bigWord, in: text, from: 11, to: 13)
        expect(.backward, .bigWord, in: text, from: 13, to: 11)
        expect(.backward, .bigWord, in: text, from: 11, to: 8)
        expect(.backward, .bigWord, in: text, from: 8, to: 3)
        expect(.forward, .word, in: text, from: 0, to: 3)
        expect(.forward, .word, in: text, from: 11, to: 13)
    }

    func testSpacesOnlyLineIsNotAStop() {
        expect(.forward, .bigWord, in: "foo\n   \nbar", from: 0, to: 8)
    }

    func testTrailingNewlineAndEdges() {
        expect(.forward, .bigWord, in: "foo\n", from: 0, to: 4)
        expect(.backward, .bigWord, in: "foo\n", from: 4, to: 0)
        expect(.backward, .bigWord, in: "   foo", from: 3, to: 0)
        expect(.forward, .bigWord, in: "", from: 0, to: 0)
        expect(.backward, .bigWord, in: "", from: 0, to: 0)
    }

    func testCRLFCountsAsOneCharacter() {
        let text = "foo\r\n\r\nbar"
        expect(.forward, .bigWord, in: text, from: 0, to: 5)
        expect(.forward, .bigWord, in: text, from: 5, to: 7)
        expect(.backward, .bigWord, in: text, from: 7, to: 5)
        expect(.backward, .bigWord, in: text, from: 5, to: 0)
    }

    func testEmojiIsItsOwnWord() {
        let text = "a 😀b"
        expect(.forward, .word, in: text, from: 0, to: 2)
        expect(.forward, .word, in: text, from: 2, to: 4)
        expect(.forward, .bigWord, in: text, from: 2, to: 5)
        expect(.backward, .bigWord, in: text, from: 5, to: 2)
        expect(.backward, .word, in: text, from: 5, to: 4)
    }

    func testCombiningMarkStaysWithBaseUnderscoreIsKeyword() {
        expect(.forward, .word, in: "cafe\u{301}_ok x", from: 0, to: 9)
    }

    func testBracketsArePunctuationWords() {
        let text = "[[note]]"
        expect(.forward, .word, in: text, from: 0, to: 2)
        expect(.forward, .word, in: text, from: 2, to: 6)
        expect(.forward, .word, in: text, from: 6, to: 8)
    }

    func testCJKAndHiraganaAreSeparateClasses() {
        expect(.forward, .word, in: "漢字かな", from: 0, to: 2)
    }

    func testSelectionCollapsesFromItsMovingEdge() {
        XCTAssertEqual(
            CaptureWordMotion.targetLocation(
                .forward,
                .bigWord,
                in: "foo bar baz",
                selectedRange: NSRange(location: 1, length: 5)
            ),
            8
        )
        XCTAssertEqual(
            CaptureWordMotion.targetLocation(
                .backward,
                .bigWord,
                in: "foo bar baz",
                selectedRange: NSRange(location: 1, length: 5)
            ),
            0
        )
        XCTAssertEqual(
            CaptureWordMotion.targetLocation(
                .forward,
                .bigWord,
                in: "foo bar",
                selectedRange: NSRange(location: 4, length: 3)
            ),
            7
        )
    }

    func testInvalidInputReturnsNil() {
        let text = "foo bar"
        XCTAssertNil(
            CaptureWordMotion.targetLocation(
                .forward,
                .bigWord,
                in: text,
                selectedRange: NSRange(location: -1, length: 0)
            )
        )
        XCTAssertNil(
            CaptureWordMotion.targetLocation(
                .forward,
                .bigWord,
                in: text,
                selectedRange: NSRange(location: 0, length: 8)
            )
        )
        XCTAssertNil(
            CaptureWordMotion.targetLocation(
                .forward,
                .bigWord,
                in: "a 😀b",
                selectedRange: NSRange(location: 3, length: 0)
            )
        )
        XCTAssertNil(
            CaptureWordMotion.targetLocation(
                .forward,
                .bigWord,
                in: "foo\r\n\r\nbar",
                selectedRange: NSRange(location: 4, length: 0)
            )
        )
    }
}
