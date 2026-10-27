import Foundation
import XCTest

@testable import CaptureCore

final class CaptureTemplateStartTests: XCTestCase {
    func testRewriteKeystrokeAcceptsOnlyAtAtAtTheEndOfTheFirstLine() {
        for text in ["@@", "@@\nApply {0}", "@@\r\n🧪"] {
            XCTAssertTrue(CaptureTemplateStart.isRewriteKeystroke(
                typed: "@",
                text: text,
                selectedRange: NSRange(location: 2, length: 0)
            ), "\(text.debugDescription)")
        }
    }

    func testRewriteKeystrokeRejectsOtherKeysSelectionsAndFirstLines() {
        let rejected: [(String, String, NSRange)] = [
            ("@@", "@@", NSRange(location: 0, length: 0)),
            ("@@", "@@", NSRange(location: 1, length: 0)),
            ("@@", "@@", NSRange(location: 2, length: 1)),
            ("@@", "@@", NSRange(location: 1, length: 1)),
            ("@@", "@@", NSRange(location: 2, length: 0)),
            ("a", "@@", NSRange(location: 2, length: 0)),
            ("@", "@@x", NSRange(location: 2, length: 0)),
            ("@", " @@", NSRange(location: 2, length: 0)),
            ("@", "\n@@", NSRange(location: 2, length: 0)),
            ("@", "@@🧪", NSRange(location: 2, length: 0)),
        ]

        for (typed, text, selection) in rejected {
            XCTAssertFalse(CaptureTemplateStart.isRewriteKeystroke(
                typed: typed,
                text: text,
                selectedRange: selection
            ), "typed=\(typed.debugDescription), text=\(text.debugDescription), selection=\(selection)")
        }
    }

    func testHintAppliesAtOffsetTwoForBareFirstLineIncludingNewlines() {
        for draft in ["@@", "@@\nApply {0}", "@@\r\n🧪"] {
            XCTAssertTrue(
                CaptureTemplateStart.hintApplies(draft: draft, cursorUTF8Offset: 2),
                "\(draft.debugDescription)"
            )
        }
    }

    func testHintRejectsOtherOffsetsAndNonBareFirstLines() {
        for offset: Int? in [nil, 0, 1, 3] {
            XCTAssertFalse(CaptureTemplateStart.hintApplies(draft: "@@", cursorUTF8Offset: offset))
        }
        for draft in ["@@x", " @@", "\n@@", "@@🧪"] {
            XCTAssertFalse(CaptureTemplateStart.hintApplies(draft: draft, cursorUTF8Offset: 2), draft)
        }
    }
}
