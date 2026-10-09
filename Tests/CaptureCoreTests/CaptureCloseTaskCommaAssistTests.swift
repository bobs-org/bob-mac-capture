import XCTest

@testable import CaptureCore

final class CaptureCloseTaskCommaAssistTests: XCTestCase {
    private func snapshot(
        draft: String,
        spans: [(Int, Int, String)]
    ) -> CaptureParseSnapshot {
        CaptureParseSnapshot(
            draft: draft,
            spans: spans.map { CaptureSpan(start: $0.0, end: $0.1, kind: $0.2) }
        )
    }

    private func collapsed(_ text: String) -> NSRange {
        NSRange(location: (text as NSString).length, length: 0)
    }

    private func expectEdit(
        typed: String,
        text: String,
        spans: [(Int, Int, String)],
        count: Int?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let edit = CaptureCloseTaskCommaAssist.edit(
            typed: typed,
            text: text,
            selectedRange: collapsed(text),
            snapshot: snapshot(draft: text, spans: spans),
            taskLinkCount: count
        )
        XCTAssertNotNil(edit, file: file, line: line)
        XCTAssertEqual(edit?.replacementText, "," + typed, file: file, line: line)
        XCTAssertEqual(
            edit?.replacementRange,
            NSRange(location: (text as NSString).length, length: 0),
            file: file,
            line: line
        )
        XCTAssertEqual(
            edit?.resultingSelection,
            NSRange(location: (text as NSString).length + 2, length: 0),
            file: file,
            line: line
        )
    }

    private func expectNil(
        typed: String,
        text: String,
        spans: [(Int, Int, String)],
        count: Int?,
        selectedRange: NSRange? = nil,
        snapshotDraft: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let snapshot = snapshot(
            draft: snapshotDraft ?? text,
            spans: spans
        )
        XCTAssertNil(
            CaptureCloseTaskCommaAssist.edit(
                typed: typed,
                text: text,
                selectedRange: selectedRange ?? collapsed(text),
                snapshot: snapshot,
                taskLinkCount: count
            ),
            file: file,
            line: line
        )
    }

    func testInsertsCommaAfterInProgressNumber() {
        expectEdit(
            typed: "2",
            text: "=x1",
            spans: [(0, 2, "pomodoro_close"), (2, 3, "pomodoro_close_in_progress")],
            count: 3
        )
    }

    func testInsertsCommaAfterParkNumber() {
        expectEdit(
            typed: "2",
            text: "=*1",
            spans: [(0, 1, "pomodoro_close"), (1, 3, "pomodoro_close_park")],
            count: 3
        )
    }

    func testInsertsCommaAfterCompleteNumber() {
        expectEdit(
            typed: "2",
            text: "=!1",
            spans: [(0, 1, "pomodoro_close"), (1, 3, "pomodoro_close_complete")],
            count: 3
        )
    }

    func testInsertsCommaInsideCompleteSpan() {
        expectEdit(
            typed: "4",
            text: "=x2!1",
            spans: [
                (0, 2, "pomodoro_close"),
                (2, 3, "pomodoro_close_in_progress"),
                (3, 5, "pomodoro_close_complete"),
            ],
            count: 4
        )
    }

    func testInsertsCommaAtEndOfParkSpan() {
        expectEdit(
            typed: "5",
            text: "=x2!1,4*3",
            spans: [
                (0, 2, "pomodoro_close"),
                (2, 3, "pomodoro_close_in_progress"),
                (3, 7, "pomodoro_close_complete"),
                (7, 9, "pomodoro_close_park"),
            ],
            count: 5
        )
    }

    func testInsertsCommaInDropSpan() {
        expectEdit(
            typed: "6",
            text: "=x2!1,4*3~5",
            spans: [
                (0, 2, "pomodoro_close"),
                (2, 3, "pomodoro_close_in_progress"),
                (3, 7, "pomodoro_close_complete"),
                (7, 9, "pomodoro_close_park"),
                (9, 11, "pomodoro_close_drop"),
            ],
            count: 6
        )
    }

    func testInsertsCommaInLinkClose() {
        expectEdit(
            typed: "2",
            text: "^bob:foo=x1",
            spans: [
                (0, 4, "active_task_route"),
                (5, 8, "active_task_block_id"),
                (8, 10, "pomodoro_close"),
                (10, 11, "pomodoro_close_in_progress"),
            ],
            count: 3
        )
    }

    func testInsertsCommaInNewTaskLinkClose() {
        expectEdit(
            typed: "2",
            text: "Draft docs @bob:draft-docs=x1",
            spans: [
                (11, 15, "pomodoro_route"),
                (16, 26, "pomodoro_block_id"),
                (26, 28, "pomodoro_close"),
                (28, 29, "pomodoro_close_in_progress"),
            ],
            count: 3
        )
    }

    func testInsertsCommaWithMultilineOffsets() {
        expectEdit(
            typed: "4",
            text: "hello\n\n=x3",
            spans: [(7, 9, "pomodoro_close"), (9, 10, "pomodoro_close_in_progress")],
            count: 4
        )
    }

    func testInsertsCommaInMiddleOfList() {
        // Caret after `2` in `=x2!1`: end of the in-progress span,
        // before `!`. Span shapes copied from `bob capture-parse`.
        let text = "=x2!1"
        let spans = [
            (0, 2, "pomodoro_close"),
            (2, 3, "pomodoro_close_in_progress"),
            (3, 5, "pomodoro_close_complete"),
        ]
        let edit = CaptureCloseTaskCommaAssist.edit(
            typed: "3",
            text: text,
            selectedRange: NSRange(location: 3, length: 0),
            snapshot: snapshot(draft: text, spans: spans),
            taskLinkCount: 4
        )
        XCTAssertEqual(edit?.replacementText, ",3")
        XCTAssertEqual(edit?.replacementRange, NSRange(location: 3, length: 0))
        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 5, length: 0))
    }

    func testMultibytePrefixConvertsUTF16CaretToUTF8() {
        // `é` is 2 bytes in UTF-8 but 1 unit in UTF-16. The caret at
        // UTF-16 4 is UTF-8 6, inside the manually built [5, 6) list
        // span. A naive UTF-16 comparison would miss it.
        expectEdit(
            typed: "2",
            text: "é =x1",
            spans: [(5, 6, "pomodoro_close_in_progress")],
            count: 3
        )
    }

    func testDeclinesWithoutKnownCount() {
        expectNil(
            typed: "2",
            text: "=x1",
            spans: [(0, 2, "pomodoro_close"), (2, 3, "pomodoro_close_in_progress")],
            count: nil
        )
    }

    func testDeclinesWithTenOrMoreLinks() {
        expectNil(
            typed: "2",
            text: "=x1",
            spans: [(0, 2, "pomodoro_close"), (2, 3, "pomodoro_close_in_progress")],
            count: 10
        )
        expectNil(
            typed: "2",
            text: "=x1",
            spans: [(0, 2, "pomodoro_close"), (2, 3, "pomodoro_close_in_progress")],
            count: 12
        )
    }

    func testDeclinesZeroAndNonDigits() {
        let spans = [(0, 2, "pomodoro_close"), (2, 3, "pomodoro_close_in_progress")]
        expectNil(typed: "0", text: "=x1", spans: spans, count: 3)
        expectNil(typed: "x", text: "=x1", spans: spans, count: 3)
        expectNil(typed: "12", text: "=x1", spans: spans, count: 3)
        expectNil(typed: "", text: "=x1", spans: spans, count: 3)
    }

    func testDeclinesFirstDigitOfGroup() {
        // The byte before the caret is a sigil or `x`, not a digit.
        expectNil(
            typed: "1",
            text: "=x",
            spans: [(0, 2, "pomodoro_close")],
            count: 3
        )
        expectNil(
            typed: "1",
            text: "=x2!",
            spans: [
                (0, 2, "pomodoro_close"),
                (2, 3, "pomodoro_close_in_progress"),
                (3, 4, "pomodoro_close_complete"),
            ],
            count: 3
        )
        expectNil(
            typed: "1",
            text: "=*",
            spans: [(0, 1, "pomodoro_close")],
            count: 3
        )
    }

    func testDeclinesAfterCommaAndZero() {
        expectNil(
            typed: "2",
            text: "=x1,",
            spans: [
                (0, 2, "pomodoro_close"),
                (2, 3, "pomodoro_close_in_progress"),
                (3, 4, "interactive_placeholder"),
            ],
            count: 3
        )
        expectNil(
            typed: "2",
            text: "=x0",
            spans: [(0, 2, "pomodoro_close"), (2, 3, "pomodoro_close_in_progress")],
            count: 3
        )
    }

    func testDeclinesWithoutListSpan() {
        // Inline Work Log number and bullet numbers carry no list span.
        expectNil(
            typed: "2",
            text: "=x 1",
            spans: [(0, 2, "pomodoro_close"), (3, 4, "interactive_placeholder")],
            count: 3
        )
        expectNil(
            typed: "2",
            text: "=x1\n- 1 did",
            spans: [(5, 6, "pomodoro_close_log_index")],
            count: 3
        )
        // Lexically malformed lists report only `pomodoro_close`.
        expectNil(
            typed: "2",
            text: "=x1,1",
            spans: [(0, 2, "pomodoro_close")],
            count: 3
        )
    }

    func testDeclinesStaleSnapshotAndSelection() {
        let spans = [(0, 2, "pomodoro_close"), (2, 3, "pomodoro_close_in_progress")]
        expectNil(
            typed: "2",
            text: "=x1",
            spans: spans,
            count: 3,
            snapshotDraft: "=x"
        )
        expectNil(
            typed: "2",
            text: "=x1",
            spans: spans,
            count: 3,
            selectedRange: NSRange(location: 3, length: 1)
        )
        XCTAssertNil(
            CaptureCloseTaskCommaAssist.edit(
                typed: "2",
                text: "=x1",
                selectedRange: collapsed("=x1"),
                snapshot: nil,
                taskLinkCount: 3
            )
        )
    }

    func testIsArmed() {
        XCTAssertFalse(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: nil))
        XCTAssertTrue(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 0))
        XCTAssertTrue(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 9))
        XCTAssertFalse(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 10))
        XCTAssertFalse(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 12))
    }
}
