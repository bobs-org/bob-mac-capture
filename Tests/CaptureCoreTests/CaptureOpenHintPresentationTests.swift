import XCTest

@testable import CaptureCore

final class CaptureOpenHintPresentationTests: XCTestCase {
    func testMissingPlanIsAvailableWithGenericCopyAndNoRows() {
        let presentation = CaptureOpenHintPresentation(plan: nil)

        XCTAssertTrue(presentation.isAvailable)
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Control-Return: capture and open in Obsidian"
        )
        XCTAssertEqual(presentation.helpText, "Capture and open in Obsidian")
        XCTAssertEqual(presentation.rows, [])
        XCTAssertNil(presentation.overflowText)
    }

    func testEmptyPlanIsUnavailable() {
        let plan = CaptureOpenPlan(openNotes: [], captures: [])
        let presentation = CaptureOpenHintPresentation(plan: plan)

        XCTAssertTrue(plan.isEmpty)
        XCTAssertFalse(presentation.isAvailable)
        XCTAssertEqual(presentation.rows, [])
        XCTAssertNil(presentation.overflowText)
    }

    func testNoteAndDayRowsAndAccessibilityMatchTheExample() {
        let plan = CaptureOpenPlan(
            openNotes: [
                CaptureOpenNote(
                    path: "/vault/inbox.md",
                    relativePath: "inbox.md",
                    role: .note,
                    label: "inbox",
                    line: 42
                ),
                CaptureOpenNote(
                    path: "/vault/2026/20261017.md",
                    relativePath: "2026/20261017.md",
                    role: .day,
                    label: "Today"
                ),
            ],
            captures: []
        )
        let presentation = CaptureOpenHintPresentation(plan: plan)

        XCTAssertTrue(presentation.isAvailable)
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Control-Return: capture and open inbox at line 42 and Today in Obsidian"
        )
        XCTAssertEqual(presentation.helpText, "inbox at line 42 and Today")
        XCTAssertEqual(presentation.rows.count, 2)
        XCTAssertEqual(presentation.rows[0].symbolName, "doc.text")
        XCTAssertEqual(presentation.rows[0].label, "inbox")
        XCTAssertEqual(presentation.rows[0].detail, "line 42")
        XCTAssertEqual(presentation.rows[1].symbolName, "calendar")
        XCTAssertEqual(presentation.rows[1].label, "Today")
        XCTAssertNil(presentation.rows[1].detail)
        XCTAssertNil(presentation.overflowText)
    }

    func testCapsVisibleRowsAndReportsOverflow() {
        let notes = (1...6).map { (index: Int) in
            CaptureOpenNote(
                path: "/vault/\(index).md",
                relativePath: "\(index).md",
                role: .note,
                label: "Note \(index)",
                line: index
            )
        }
        let presentation = CaptureOpenHintPresentation(
            plan: CaptureOpenPlan(openNotes: notes, captures: [])
        )

        XCTAssertEqual(presentation.rows.count, 4)
        XCTAssertEqual(presentation.rows.map(\.label), ["Note 1", "Note 2", "Note 3", "Note 4"])
        XCTAssertEqual(presentation.overflowText, "+2 more")
        XCTAssertTrue(
            presentation.accessibilityLabel.contains("Note 5 at line 5, and Note 6 at line 6")
        )
    }

    func testEmptyLabelFallsBackAndOtherRolesUseDocSymbol() {
        let plan = CaptureOpenPlan(
            openNotes: [
                CaptureOpenNote(
                    path: "/vault/paper.pdf",
                    relativePath: "paper.pdf",
                    role: .other("pdf"),
                    label: ""
                ),
                CaptureOpenNote(
                    path: "/vault/day.md",
                    relativePath: "day.md",
                    role: .day,
                    label: ""
                ),
            ],
            captures: []
        )
        let presentation = CaptureOpenHintPresentation(plan: plan)

        XCTAssertEqual(presentation.rows[0].symbolName, "doc.text")
        XCTAssertEqual(presentation.rows[0].label, "paper.pdf")
        XCTAssertEqual(presentation.rows[1].symbolName, "calendar")
        XCTAssertEqual(presentation.rows[1].label, "Today")
        XCTAssertEqual(
            presentation.accessibilityLabel,
            "Control-Return: capture and open paper.pdf and Today in Obsidian"
        )
    }
}
