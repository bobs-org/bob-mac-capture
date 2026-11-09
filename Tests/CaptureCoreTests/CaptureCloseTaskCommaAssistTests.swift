import XCTest

@testable import CaptureCore

final class CaptureCloseTaskCommaAssistTests: XCTestCase {
    private func snapshot(
        draft: String,
        spans: [(Int, Int, String)],
        items: [CaptureParseSnapshot.Item] = []
    ) -> CaptureParseSnapshot {
        CaptureParseSnapshot(
            draft: draft,
            spans: spans.map { CaptureSpan(start: $0.0, end: $0.1, kind: $0.2) },
            items: items
        )
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    private func collapsed(_ text: String) -> NSRange {
        NSRange(location: (text as NSString).length, length: 0)
    }

    private func expectEdit(
        typed: String,
        text: String,
        spans: [(Int, Int, String)],
        count: Int?,
        pastCount: Int? = nil,
        items: [CaptureParseSnapshot.Item] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let edit = CaptureCloseTaskCommaAssist.edit(
            typed: typed,
            text: text,
            selectedRange: collapsed(text),
            snapshot: snapshot(draft: text, spans: spans, items: items),
            taskLinkCount: count,
            pastTaskLinkCount: pastCount
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
        pastCount: Int? = nil,
        items: [CaptureParseSnapshot.Item] = [],
        selectedRange: NSRange? = nil,
        snapshotDraft: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let snapshot = snapshot(
            draft: snapshotDraft ?? text,
            spans: spans,
            items: items
        )
        XCTAssertNil(
            CaptureCloseTaskCommaAssist.edit(
                typed: typed,
                text: text,
                selectedRange: selectedRange ?? collapsed(text),
                snapshot: snapshot,
                taskLinkCount: count,
                pastTaskLinkCount: pastCount
            ),
            file: file,
            line: line
        )
    }

    func testInsertsCommaAfterInProgressNumber() {
        expectEdit(
            typed: "2",
            text: "x1",
            spans: [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress")],
            count: 3
        )
    }

    func testInsertsCommaAfterParkNumber() {
        expectEdit(
            typed: "2",
            text: "x*1",
            spans: [(0, 1, "pomodoro_close"), (1, 3, "pomodoro_close_park")],
            count: 3
        )
    }

    func testInsertsCommaAfterCompleteNumber() {
        expectEdit(
            typed: "2",
            text: "x!1",
            spans: [(0, 1, "pomodoro_close"), (1, 3, "pomodoro_close_complete")],
            count: 3
        )
    }

    func testInsertsCommaInsideCompleteSpan() {
        expectEdit(
            typed: "4",
            text: "x2!1",
            spans: [
                (0, 1, "pomodoro_close"),
                (1, 2, "pomodoro_close_in_progress"),
                (2, 4, "pomodoro_close_complete"),
            ],
            count: 4
        )
    }

    func testInsertsCommaAtEndOfParkSpan() {
        expectEdit(
            typed: "5",
            text: "x2!1,4*3",
            spans: [
                (0, 1, "pomodoro_close"),
                (1, 2, "pomodoro_close_in_progress"),
                (2, 6, "pomodoro_close_complete"),
                (6, 8, "pomodoro_close_park"),
            ],
            count: 5
        )
    }

    func testInsertsCommaInDropSpan() {
        expectEdit(
            typed: "6",
            text: "x2!1,4*3~5",
            spans: [
                (0, 1, "pomodoro_close"),
                (1, 2, "pomodoro_close_in_progress"),
                (2, 6, "pomodoro_close_complete"),
                (6, 8, "pomodoro_close_park"),
                (8, 10, "pomodoro_close_drop"),
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
            text: "hello\n\nx3",
            spans: [(7, 8, "pomodoro_close"), (8, 9, "pomodoro_close_in_progress")],
            count: 4
        )
    }

    func testInsertsCommaInMiddleOfList() {
        // Caret after `2` in `x2!1`: end of the in-progress span,
        // before `!`. Span shapes copied from `bob capture-parse`.
        let text = "x2!1"
        let spans = [
            (0, 1, "pomodoro_close"),
            (1, 2, "pomodoro_close_in_progress"),
            (2, 4, "pomodoro_close_complete"),
        ]
        let edit = CaptureCloseTaskCommaAssist.edit(
            typed: "3",
            text: text,
            selectedRange: NSRange(location: 2, length: 0),
            snapshot: snapshot(draft: text, spans: spans),
            taskLinkCount: 4
        )
        XCTAssertEqual(edit?.replacementText, ",3")
        XCTAssertEqual(edit?.replacementRange, NSRange(location: 2, length: 0))
        XCTAssertEqual(edit?.resultingSelection, NSRange(location: 4, length: 0))
    }

    func testMultibytePrefixConvertsUTF16CaretToUTF8() {
        // `é` is 2 bytes in UTF-8 but 1 unit in UTF-16. The caret at
        // UTF-16 4 is UTF-8 5, at the end of the manually built [4, 5) list
        // span. A naive UTF-16 comparison would miss it.
        expectEdit(
            typed: "2",
            text: "é x1",
            spans: [(4, 5, "pomodoro_close_in_progress")],
            count: 3
        )
    }

    func testDeclinesWithoutKnownCount() {
        expectNil(
            typed: "2",
            text: "x1",
            spans: [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress")],
            count: nil
        )
    }

    func testDeclinesWithTenOrMoreLinks() {
        expectNil(
            typed: "2",
            text: "x1",
            spans: [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress")],
            count: 10
        )
        expectNil(
            typed: "2",
            text: "x1",
            spans: [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress")],
            count: 12
        )
    }

    func testDeclinesZeroAndNonDigits() {
        let spans = [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress")]
        expectNil(typed: "0", text: "x1", spans: spans, count: 3)
        expectNil(typed: "x", text: "x1", spans: spans, count: 3)
        expectNil(typed: "12", text: "x1", spans: spans, count: 3)
        expectNil(typed: "", text: "x1", spans: spans, count: 3)
    }

    func testSizedCloseNeverSplitsSizeDigitsButKeepsSelectionAssist() {
        // Typing `2` to make `12x` never inserts `1,2x`: the size digits live
        // inside the `pomodoro_close` span, not a list span.
        expectNil(
            typed: "2",
            text: "12x",
            spans: [(0, 3, "pomodoro_close")],
            count: 3
        )
        // Selection digits after the sized `x` keep normal comma assistance.
        expectEdit(
            typed: "2",
            text: "2x1",
            spans: [(0, 2, "pomodoro_close"), (2, 3, "pomodoro_close_in_progress")],
            count: 3
        )
    }

    func testDeclinesFirstDigitOfGroup() {
        // The byte before the caret is a sigil or `x`, not a digit.
        expectNil(
            typed: "1",
            text: "x",
            spans: [(0, 1, "pomodoro_close")],
            count: 3
        )
        expectNil(
            typed: "1",
            text: "x2!",
            spans: [
                (0, 1, "pomodoro_close"),
                (1, 2, "pomodoro_close_in_progress"),
                (2, 3, "pomodoro_close_complete"),
            ],
            count: 3
        )
        expectNil(
            typed: "1",
            text: "x*",
            spans: [(0, 1, "pomodoro_close")],
            count: 3
        )
    }

    func testDeclinesAfterCommaAndZero() {
        expectNil(
            typed: "2",
            text: "x1,",
            spans: [
                (0, 1, "pomodoro_close"),
                (1, 2, "pomodoro_close_in_progress"),
                (2, 3, "interactive_placeholder"),
            ],
            count: 3
        )
        expectNil(
            typed: "2",
            text: "x0",
            spans: [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress")],
            count: 3
        )
    }

    func testDeclinesWithoutListSpan() {
        // Inline Work Log number and bullet numbers carry no list span.
        expectNil(
            typed: "2",
            text: "x 1",
            spans: [(0, 1, "pomodoro_close"), (2, 3, "interactive_placeholder")],
            count: 3
        )
        expectNil(
            typed: "2",
            text: "x1\n- 1 did",
            spans: [(5, 6, "pomodoro_close_log_index")],
            count: 3
        )
        // Lexically malformed lists report only `pomodoro_close`.
        expectNil(
            typed: "2",
            text: "x1,1",
            spans: [(0, 1, "pomodoro_close")],
            count: 3
        )
    }

    func testDeclinesStaleSnapshotAndSelection() {
        let spans = [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress")]
        expectNil(
            typed: "2",
            text: "x1",
            spans: spans,
            count: 3,
            snapshotDraft: "x"
        )
        expectNil(
            typed: "2",
            text: "x1",
            spans: spans,
            count: 3,
            selectedRange: NSRange(location: 1, length: 1)
        )
        XCTAssertNil(
            CaptureCloseTaskCommaAssist.edit(
                typed: "2",
                text: "x1",
                selectedRange: collapsed("x1"),
                snapshot: nil,
                taskLinkCount: 3
            )
        )
    }

    func testInsertsPastCloseListsWithTheOpenEntryBound() {
        let cases: [(String, [(Int, Int, String)], Int)] = [
            ("x==1", [(0, 2, "pomodoro_past"), (2, 3, "pomodoro_close"), (3, 4, "pomodoro_close_in_progress")], 4),
            ("x=3=1", [(0, 3, "pomodoro_past"), (3, 4, "pomodoro_close"), (4, 5, "pomodoro_close_in_progress")], 5),
            ("x=build=1", [(0, 2, "pomodoro_past"), (2, 7, "pomodoro_name"), (7, 8, "pomodoro_close"), (8, 9, "pomodoro_close_in_progress")], 9),
            ("x=fix@2=*1", [(0, 2, "pomodoro_past"), (2, 5, "pomodoro_name"), (5, 7, "pomodoro_past"), (7, 8, "pomodoro_close"), (8, 10, "pomodoro_close_park")], 10),
            ("x=3!=!1", [(0, 3, "pomodoro_past"), (3, 4, "pomodoro_past_repair"), (4, 5, "pomodoro_close"), (5, 7, "pomodoro_close_complete")], 7),
            ("x=#\"DEEP WORK\"=1", [(0, 2, "pomodoro_past"), (3, 14, "pomodoro_name"), (14, 15, "pomodoro_close"), (15, 16, "pomodoro_close_in_progress")], 16),
            ("x==1 =\n- 1 did", [(0, 2, "pomodoro_past"), (2, 3, "pomodoro_close"), (3, 4, "pomodoro_close_in_progress")], 4),
        ]

        for (text, spans, caret) in cases {
            let items = [CaptureParseSnapshot.Item(
                start: 0,
                end: text.utf8.count,
                mode: CaptureCloseTaskCommaAssist.pastItemMode
            )]
            let edit = CaptureCloseTaskCommaAssist.edit(
                typed: "2",
                text: text,
                selectedRange: NSRange(location: caret, length: 0),
                snapshot: snapshot(draft: text, spans: spans, items: items),
                taskLinkCount: nil,
                pastTaskLinkCount: 3
            )
            XCTAssertEqual(edit?.replacementText, ",2", "draft: \(text)")
        }

        let text = "x==1!2"
        let edit = CaptureCloseTaskCommaAssist.edit(
            typed: "3",
            text: text,
            selectedRange: NSRange(location: 4, length: 0),
            snapshot: snapshot(
                draft: text,
                spans: [
                    (0, 2, "pomodoro_past"),
                    (2, 3, "pomodoro_close"),
                    (3, 4, "pomodoro_close_in_progress"),
                    (4, 6, "pomodoro_close_complete"),
                ],
                items: [CaptureParseSnapshot.Item(
                    start: 0,
                    end: text.utf8.count,
                    mode: CaptureCloseTaskCommaAssist.pastItemMode
                )]
            ),
            taskLinkCount: nil,
            pastTaskLinkCount: 3
        )
        XCTAssertEqual(edit?.replacementText, ",3")
        XCTAssertEqual(edit?.replacementRange, NSRange(location: 4, length: 0))
    }

    func testRoutesMixedDraftListsByTheirOwningItem() {
        let samples: [(String, [CaptureParseSnapshot.Item], [(Int, Int, String)], Int, Int)] = [
            (
                "x1 x==2",
                [
                    CaptureParseSnapshot.Item(start: 0, end: 2, mode: "pomodoro_close"),
                    CaptureParseSnapshot.Item(start: 3, end: 7, mode: "pomodoro_past"),
                ],
                [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress"), (3, 5, "pomodoro_past"), (5, 6, "pomodoro_close"), (6, 7, "pomodoro_close_in_progress")],
                2,
                7
            ),
            (
                "x1\n\nx==2",
                [
                    CaptureParseSnapshot.Item(start: 0, end: 2, mode: "pomodoro_close"),
                    CaptureParseSnapshot.Item(start: 4, end: 8, mode: "pomodoro_past"),
                ],
                [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress"), (4, 6, "pomodoro_past"), (6, 7, "pomodoro_close"), (7, 8, "pomodoro_close_in_progress")],
                2,
                8
            ),
        ]

        for (text, items, spans, runningCaret, pastCaret) in samples {
            let parsed = snapshot(draft: text, spans: spans, items: items)
            XCTAssertNil(CaptureCloseTaskCommaAssist.edit(
                typed: "2",
                text: text,
                selectedRange: NSRange(location: runningCaret, length: 0),
                snapshot: parsed,
                taskLinkCount: nil,
                pastTaskLinkCount: 3
            ))
            XCTAssertEqual(CaptureCloseTaskCommaAssist.edit(
                typed: "3",
                text: text,
                selectedRange: NSRange(location: pastCaret, length: 0),
                snapshot: parsed,
                taskLinkCount: nil,
                pastTaskLinkCount: 3
            )?.replacementText, ",3")

            XCTAssertEqual(CaptureCloseTaskCommaAssist.edit(
                typed: "2",
                text: text,
                selectedRange: NSRange(location: runningCaret, length: 0),
                snapshot: parsed,
                taskLinkCount: 3,
                pastTaskLinkCount: 12
            )?.replacementText, ",2")
            XCTAssertNil(CaptureCloseTaskCommaAssist.edit(
                typed: "3",
                text: text,
                selectedRange: NSRange(location: pastCaret, length: 0),
                snapshot: parsed,
                taskLinkCount: 3,
                pastTaskLinkCount: 12
            ))
        }
    }

    func testExistingSnapshotsWithoutItemsKeepTheRunningGate() {
        let spans = [(0, 1, "pomodoro_close"), (1, 2, "pomodoro_close_in_progress")]
        expectEdit(typed: "2", text: "x1", spans: spans, count: 3, pastCount: 12)
        expectNil(typed: "2", text: "x1", spans: spans, count: nil, pastCount: 3)
    }

    func testPastCloseListsDeclineWhenTheirBoundIsUnknownOrMultiDigit() {
        let text = "x==1"
        let spans = [(0, 2, "pomodoro_past"), (2, 3, "pomodoro_close"), (3, 4, "pomodoro_close_in_progress")]
        let items = [CaptureParseSnapshot.Item(start: 0, end: 4, mode: "pomodoro_past")]
        for count in [nil, 10, 12] as [Int?] {
            expectNil(
                typed: "2",
                text: text,
                spans: spans,
                count: nil,
                pastCount: count,
                items: items
            )
        }
    }

    func testPastBlockAndWorkLogNumbersAreNotCloseLists() {
        expectNil(
            typed: "1",
            text: "x=3",
            spans: [(0, 3, "pomodoro_past")],
            count: 3,
            pastCount: 3,
            items: [CaptureParseSnapshot.Item(start: 0, end: 3, mode: "pomodoro_past")]
        )
        expectNil(
            typed: "1",
            text: "x=build@2",
            spans: [(0, 2, "pomodoro_past"), (2, 8, "pomodoro_name")],
            count: 3,
            pastCount: 3,
            items: [CaptureParseSnapshot.Item(start: 0, end: 9, mode: "pomodoro_past")]
        )
        expectNil(
            typed: "1",
            text: "x==",
            spans: [(0, 2, "pomodoro_past"), (2, 3, "pomodoro_close")],
            count: 3,
            pastCount: 3,
            items: [CaptureParseSnapshot.Item(start: 0, end: 3, mode: "pomodoro_past")]
        )
        expectNil(
            typed: "2",
            text: "x== 1",
            spans: [(0, 2, "pomodoro_past"), (2, 3, "pomodoro_close"), (4, 5, "pomodoro_close_log_index")],
            count: 3,
            pastCount: 3,
            items: [CaptureParseSnapshot.Item(start: 0, end: 5, mode: "pomodoro_past")]
        )
        expectNil(
            typed: "0",
            text: "x==1",
            spans: [(0, 2, "pomodoro_past"), (2, 3, "pomodoro_close"), (3, 4, "pomodoro_close_in_progress")],
            count: 3,
            pastCount: 3,
            items: [CaptureParseSnapshot.Item(start: 0, end: 4, mode: "pomodoro_past")]
        )
    }

    func testSnapshotInitUsesCaptureParseItemRangesAndFallback() throws {
        let mixedParse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: fixtureData("pomodoro-past-parse-close-mix.json")
        )
        let mixed = CaptureParseSnapshot(draft: mixedParse.input, parse: mixedParse)
        XCTAssertEqual(mixed.items.map(\.mode), ["pomodoro_close", "pomodoro_past"])
        XCTAssertEqual(mixed.items.map(\.start), [0, 2])
        XCTAssertEqual(mixed.items.map(\.end), [1, 10])

        let singleParse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: fixtureData("pomodoro-past-parse-single.json")
        )
        let single = CaptureParseSnapshot(draft: singleParse.input, parse: singleParse)
        XCTAssertEqual(single.items, [CaptureParseSnapshot.Item(
            start: 0,
            end: singleParse.input.utf8.count,
            mode: "pomodoro_past"
        )])
    }

    func testIsArmed() {
        XCTAssertFalse(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: nil))
        XCTAssertTrue(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 0))
        XCTAssertTrue(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 9))
        XCTAssertFalse(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 10))
        XCTAssertFalse(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 12))
        XCTAssertTrue(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: nil, pastTaskLinkCount: 9))
        XCTAssertTrue(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 9, pastTaskLinkCount: 12))
        XCTAssertTrue(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 10, pastTaskLinkCount: 0))
        XCTAssertFalse(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: 10, pastTaskLinkCount: 12))
        XCTAssertFalse(CaptureCloseTaskCommaAssist.isArmed(taskLinkCount: nil, pastTaskLinkCount: nil))
    }
}
