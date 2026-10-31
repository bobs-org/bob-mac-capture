import Foundation
import XCTest

@testable import CaptureCore

final class CaptureLineCaseToggleTests: XCTestCase {
    func testLowercaseLineWithMidCaretBecomesUpper() {
        let text = "hello"
        let edit = CaptureLineCaseToggle.edit(
            in: text,
            selectedRange: NSRange(location: 2, length: 0)
        )
        XCTAssertEqual(edit?.replacementText, "HELLO")
        XCTAssertEqual(edit?.replacementRange, NSRange(location: 0, length: 5))
        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 2, length: 0))
    }

    func testUpperLineBecomesLower() {
        let edit = CaptureLineCaseToggle.edit(
            in: "HELLO",
            selectedRange: NSRange(location: 0, length: 0)
        )
        XCTAssertEqual(edit?.replacementText, "hello")
        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 0, length: 0))
    }

    func testMixedLineUppercasesThenLowercasesOnSecondApplication() {
        let first = CaptureLineCaseToggle.edit(
            in: "Hello",
            selectedRange: NSRange(location: 1, length: 3)
        )
        XCTAssertEqual(first?.replacementText, "HELLO")
        XCTAssertEqual(first?.resultingSelection, NSRange(location: 1, length: 3))

        let after = apply(first!, to: "Hello")
        let second = CaptureLineCaseToggle.edit(
            in: after,
            selectedRange: first!.resultingSelection
        )
        XCTAssertEqual(second?.replacementText, "hello")
        XCTAssertEqual(apply(second!, to: after), "hello")
    }

    func testOnlyCaretsLineChangesInMultilineDraft() {
        let text = "alpha\nbeta\ngamma"
        let edit = CaptureLineCaseToggle.edit(
            in: text,
            selectedRange: NSRange(location: 8, length: 0)
        )
        XCTAssertEqual(edit?.replacementRange, NSRange(location: 6, length: 4))
        XCTAssertEqual(edit?.replacementText, "BETA")
        XCTAssertEqual(apply(edit!, to: text), "alpha\nBETA\ngamma")
        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 8, length: 0))
    }

    func testCRLFTerminatorStaysByteIdentical() {
        let text = "hello\r\nworld"
        let edit = CaptureLineCaseToggle.edit(
            in: text,
            selectedRange: NSRange(location: 1, length: 0)
        )
        XCTAssertEqual(edit?.replacementText, "HELLO")
        XCTAssertEqual(edit?.replacementRange, NSRange(location: 0, length: 5))
        let result = apply(edit!, to: text)
        XCTAssertEqual(result, "HELLO\r\nworld")
        XCTAssertEqual(Array(result.utf8), Array("HELLO\r\nworld".utf8))
    }

    func testTwoLineSelectionUsesOneDirectionAndRemapsSelection() {
        let text = "hello\nWORLD"
        let selection = NSRange(location: 2, length: 7)
        let edit = CaptureLineCaseToggle.edit(in: text, selectedRange: selection)
        XCTAssertEqual(edit?.replacementText, "HELLO\nWORLD")
        XCTAssertEqual(edit?.replacementRange, NSRange(location: 0, length: 11))
        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 2, length: 7))
        XCTAssertEqual(apply(edit!, to: text), "HELLO\nWORLD")

        let second = CaptureLineCaseToggle.edit(
            in: "HELLO\nWORLD",
            selectedRange: edit!.resultingSelection
        )
        XCTAssertEqual(second?.replacementText, "hello\nworld")
    }

    func testSelectionEndingAtLineStartExcludesThatLine() {
        let text = "hello\nworld"
        let edit = CaptureLineCaseToggle.edit(
            in: text,
            selectedRange: NSRange(location: 0, length: 6)
        )
        XCTAssertEqual(edit?.replacementText, "HELLO")
        XCTAssertEqual(edit?.replacementRange, NSRange(location: 0, length: 5))
        XCTAssertEqual(apply(edit!, to: text), "HELLO\nworld")
    }

    func testEszettLengthGrowthMapsCaretAtEndAndAfterPrefix() {
        let text = "straße"
        let atEnd = CaptureLineCaseToggle.edit(
            in: text,
            selectedRange: NSRange(location: 6, length: 0)
        )
        XCTAssertEqual(atEnd?.replacementText, "STRASSE")
        XCTAssertEqual(atEnd?.resultingSelection, NSRange(location: 7, length: 0))
        XCTAssertEqual(apply(atEnd!, to: text), "STRASSE")

        let afterPrefix = CaptureLineCaseToggle.edit(
            in: text,
            selectedRange: NSRange(location: 4, length: 0)
        )
        XCTAssertEqual(afterPrefix?.replacementText, "STRASSE")
        XCTAssertEqual(afterPrefix?.resultingSelection, NSRange(location: 4, length: 0))
    }

    func testEmojiAndSurrogatePairsStayIntactWithCaretMapping() {
        let text = "hi👋z"
        let afterGreeting = CaptureLineCaseToggle.edit(
            in: text,
            selectedRange: NSRange(location: 2, length: 0)
        )
        XCTAssertEqual(afterGreeting?.replacementText, "HI👋Z")
        XCTAssertEqual(afterGreeting?.resultingSelection, NSRange(location: 2, length: 0))
        XCTAssertEqual(apply(afterGreeting!, to: text), "HI👋Z")

        let afterEmoji = CaptureLineCaseToggle.edit(
            in: text,
            selectedRange: NSRange(location: 4, length: 0)
        )
        XCTAssertEqual(afterEmoji?.resultingSelection, NSRange(location: 4, length: 0))

        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: text,
                selectedRange: NSRange(location: 3, length: 0)
            )
        )
    }

    func testUncasedSpansGiveNil() {
        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: "",
                selectedRange: NSRange(location: 0, length: 0)
            )
        )
        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: "   ",
                selectedRange: NSRange(location: 1, length: 0)
            )
        )
        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: "- 123",
                selectedRange: NSRange(location: 2, length: 0)
            )
        )
        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: "-",
                selectedRange: NSRange(location: 1, length: 0)
            )
        )
        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: "hello\n",
                selectedRange: NSRange(location: 6, length: 0)
            )
        )
    }

    func testOutOfBoundsRangesGiveNil() {
        let text = "hello"
        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: text,
                selectedRange: NSRange(location: -1, length: 0)
            )
        )
        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: text,
                selectedRange: NSRange(location: 6, length: 0)
            )
        )
        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: text,
                selectedRange: NSRange(location: 0, length: 6)
            )
        )
        XCTAssertNil(
            CaptureLineCaseToggle.edit(
                in: text,
                selectedRange: NSRange(location: 2, length: -1)
            )
        )
    }

    func testCaptureSyntaxLineIsUppercasedLiterally() {
        let text = "- x1 @inbox fix bug"
        let edit = CaptureLineCaseToggle.edit(
            in: text,
            selectedRange: NSRange(location: 8, length: 0)
        )
        XCTAssertEqual(edit?.replacementText, "- X1 @INBOX FIX BUG")
        XCTAssertEqual(apply(edit!, to: text), "- X1 @INBOX FIX BUG")
        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 8, length: 0))
    }

    private func apply(_ edit: CaptureLineCaseEdit, to text: String) -> String {
        let result = NSMutableString(string: text)
        result.replaceCharacters(in: edit.replacementRange, with: edit.replacementText)
        return String(result)
    }
}
