import Foundation
import XCTest

@testable import CaptureCore

final class CaptureTemplateStartTests: XCTestCase {
    func testRewriteKeystrokeAcceptsStandaloneAtAtAtAnyPhysicalLineEnd() {
        let accepted: [(String, Int)] = [
            ("@@", 2),
            ("@@\nApply {0}", 2),
            ("@@\r\n🧪", 2),
            ("Read {0} @@", 11),
            ("Buy milk\nRead {0} @@", 20),
            ("x\n@@", 4),
            (" @@", 3),
            ("Read\t@@\r\nmore", 7),
            ("Read @@\nmore", 7),
            ("🧪 @@", 5),
        ]

        for (text, cursor) in accepted {
            XCTAssertTrue(
                CaptureTemplateStart.isRewriteKeystroke(
                    typed: "@",
                    text: text,
                    selectedRange: NSRange(location: cursor, length: 0)
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
            ("@", "x@@", NSRange(location: 3, length: 0)),
            ("@", "@@@", NSRange(location: 3, length: 0)),
            ("@", "Read @@ ", NSRange(location: 7, length: 0)),
            ("@", "Read @@x", NSRange(location: 7, length: 0)),
            ("@", "Read @@", NSRange(location: 6, length: 0)),
            ("@", "@@", NSRange(location: 99, length: 0)),
            ("@", " @@", NSRange(location: 2, length: 0)),
            ("@", "\n@@", NSRange(location: 2, length: 0)),
            ("@", "@@🧪", NSRange(location: 2, length: 0)),
        ]

        for (typed, text, selection) in rejected {
            XCTAssertFalse(
                CaptureTemplateStart.isRewriteKeystroke(
                    typed: typed,
                    text: text,
                    selectedRange: selection
                ),
                "typed=\(typed.debugDescription), text=\(text.debugDescription), "
                    + "selection=\(selection)"
            )
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
        XCTAssertFalse(CaptureTemplateStart.hintApplies(draft: "x\n@@", cursorUTF8Offset: 4))
    }
}
