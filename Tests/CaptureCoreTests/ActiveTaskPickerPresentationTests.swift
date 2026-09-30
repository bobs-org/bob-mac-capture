import XCTest

@testable import CaptureCore

final class ActiveTaskPickerPresentationTests: XCTestCase {
    /// Real `bob capture-complete --cursor 1 -- '^'` shape for a Ready
    /// task (status symbol and type as Bob reports them). Bob no longer
    /// sends a `now` flag, so `#now` in the text is inert body text.
    private func readyCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "notes:ready-probe",
            route: "notes",
            blockID: "ready-probe",
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Try the ready task"
        )
    }

    func testReadyCandidateShowsNoBadgeAndNoBetAccessibilityLabel() throws {
        let presentation = ActiveTaskPickerIndex(candidates: [readyCandidate()])
            .presentation(filter: "")
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.countText, "1 task")
        XCTAssertEqual(presentation.sections.map(\.id), ["other"])

        let row = try XCTUnwrap(presentation.rowsByID["notes:ready-probe"])
        XCTAssertNil(row.badgeText)
        XCTAssertEqual(row.detail.statusText, "Todo")
        XCTAssertEqual(
            row.accessibilityLabel,
            "Todo. Try the ready task. Note notes, block ready-probe. Not in a Pomodoro."
        )
    }
}
