import XCTest

@testable import CaptureCore

final class ActiveTaskPickerPresentationTests: XCTestCase {
    /// Real `bob capture-complete --cursor 1 -- '^'` shape for a Ready
    /// `#now` task (status symbol and type as Bob reports them).
    private func nowCandidate(now: Bool = true) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "notes:now-probe",
            route: "notes",
            blockID: "now-probe",
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Try the now tag #now",
            now: now
        )
    }

    func testNowCandidateShowsNowBadgeAndBetAccessibilityLabel() throws {
        let presentation = ActiveTaskPickerIndex(candidates: [nowCandidate()])
            .presentation(filter: "")
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.countText, "1 task")
        XCTAssertEqual(presentation.sections.map(\.id), ["other"])

        let row = try XCTUnwrap(presentation.rowsByID["notes:now-probe"])
        XCTAssertEqual(row.badgeText, "NOW")
        XCTAssertEqual(row.detail.statusText, "Todo")
        XCTAssertEqual(
            row.accessibilityLabel,
            "Todo. Try the now tag #now. This week's bet. Note notes, block now-probe. Not in a Pomodoro."
        )
    }

    func testCandidateWithoutNowOmitsBadgeAndBetLabel() throws {
        let presentation = ActiveTaskPickerIndex(candidates: [nowCandidate(now: false)])
            .presentation(filter: "")

        let row = try XCTUnwrap(presentation.rowsByID["notes:now-probe"])
        XCTAssertNil(row.badgeText)
        XCTAssertFalse(row.accessibilityLabel.contains("This week's bet"))
    }
}
