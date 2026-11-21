import XCTest

@testable import CaptureCore

/// Reducer contract for the Pull-In reason `LINK` band
/// (`bob capture-complete --links-only`): band visibility, selection by
/// row key, stale-generation drops, and the byte-range accept that keeps
/// a racing caret from splicing a stale range.
final class PullInLinkStateTests: XCTestCase {
    private func noteCandidates() -> [CaptureCompletionCandidate] {
        [
            CaptureCompletionCandidate(
                replacement: "sase]]", cursorAfter: 12, path: "sase.md",
                name: "sase"),
            CaptureCompletionCandidate(
                replacement: "sase_cleanup]]", cursorAfter: 21,
                path: "sase_cleanup.md", name: "sase_cleanup"),
        ]
    }

    private func openNoteBand() -> PullInLinkState {
        var state = PullInLinkState()
        state.beginReason()
        state.inputChanged(text: "fix [[sas", cursorUTF8: 9)
        XCTAssertTrue(
            state.receive(
                text: "fix [[sas", cursorUTF8: 9,
                context: .wikilinkNote,
                replacement: CaptureRange(start: 6, end: 9),
                candidates: noteCandidates(),
                opensWithoutSelection: false,
                generation: state.generation
            )
        )
        return state
    }

    func testClosedUntilBobReportsAField() {
        var state = PullInLinkState()
        XCTAssertFalse(state.isOpen)
        state.beginReason()
        state.inputChanged(text: "fix [[sas", cursorUTF8: 9)
        XCTAssertFalse(state.isOpen)
    }

    func testReceiveOpensBandAndSelectsFirstRow() {
        let state = openNoteBand()
        XCTAssertTrue(state.isOpen)
        XCTAssertEqual(state.visibleCandidates.count, 2)
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertEqual(
            state.selectedCandidate?.replacement, "sase]]")
    }

    func testEmptyFieldOpensBandWithZeroRows() {
        var state = PullInLinkState()
        state.beginReason()
        state.inputChanged(text: "plain reason", cursorUTF8: 12)
        XCTAssertTrue(
            state.receive(
                text: "plain reason", cursorUTF8: 12,
                context: .wikilinkNote,
                replacement: CaptureRange(start: 12, end: 12),
                candidates: [],
                opensWithoutSelection: false,
                generation: state.generation
            )
        )
        // Zero rows still show the band, so Return closes it instead of
        // confirming the Pull-In.
        XCTAssertTrue(state.isOpen)
        XCTAssertEqual(state.visibleCandidates.count, 0)
        XCTAssertNil(state.selectedIndex)
    }

    func testNilContextClosesBand() {
        var state = openNoteBand()
        state.inputChanged(text: "fix [[sas!", cursorUTF8: 10)
        XCTAssertTrue(
            state.receive(
                text: "fix [[sas!", cursorUTF8: 10,
                context: nil,
                replacement: CaptureRange(start: 10, end: 10),
                candidates: [],
                opensWithoutSelection: false,
                generation: state.generation
            )
        )
        XCTAssertFalse(state.isOpen)
    }

    func testOpensWithoutSelectionLeavesBandUnselected() {
        var state = PullInLinkState()
        state.beginReason()
        state.inputChanged(text: "fix [[sas", cursorUTF8: 9)
        XCTAssertTrue(
            state.receive(
                text: "fix [[sas", cursorUTF8: 9,
                context: .wikilinkNote,
                replacement: CaptureRange(start: 6, end: 9),
                candidates: noteCandidates(),
                opensWithoutSelection: true,
                generation: state.generation
            )
        )
        XCTAssertTrue(state.isOpen)
        XCTAssertNil(state.selectedIndex)
    }

    func testStaleGenerationIsDropped() {
        var state = openNoteBand()
        let stale = state.generation
        state.inputChanged(text: "fix [[sasx", cursorUTF8: 10)
        XCTAssertFalse(
            state.receive(
                text: "fix [[sas", cursorUTF8: 9,
                context: .wikilinkNote,
                replacement: CaptureRange(start: 6, end: 9),
                candidates: [],
                opensWithoutSelection: false,
                generation: stale
            )
        )
        // Previous rows stay visible while the refetch is in flight.
        XCTAssertEqual(state.candidates.count, 2)
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testMoveClampsAtBottomWithoutWrap() {
        var state = openNoteBand()
        XCTAssertEqual(state.moveNext(), .moved)
        XCTAssertEqual(state.selectedIndex, 2)
        XCTAssertEqual(state.moveNext(), .bumpedBottom)
        XCTAssertEqual(state.selectedIndex, 2)
    }

    func testMoveAboveTopClearsSelectionButKeepsBand() {
        var state = openNoteBand()
        XCTAssertEqual(state.movePrevious(), .bumpedTop)
        XCTAssertTrue(state.isOpen)
        XCTAssertNil(state.selectedIndex)
        // Moving again re-enters at the top row.
        XCTAssertEqual(state.movePrevious(), .enteredTop)
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testSelectRejectsUnknownKeys() {
        var state = openNoteBand()
        XCTAssertFalse(state.select(id: "nope"))
        XCTAssertEqual(state.selectedIndex, 1)
        let second = noteCandidates()[1].id
        XCTAssertTrue(state.select(id: second))
        XCTAssertEqual(state.selectedCandidate?.path, "sase_cleanup.md")
    }

    func testCloseConsumesOnce() {
        var state = openNoteBand()
        XCTAssertTrue(state.close())
        XCTAssertFalse(state.isOpen)
        XCTAssertFalse(state.close())
    }

    func testAcceptInsertsAtBytesAndLandsCaret() {
        let state = openNoteBand()
        let edit = state.acceptEdit(fieldText: "fix [[sas", caretUTF8: 9)
        XCTAssertEqual(
            edit,
            PullInLinkAcceptEdit(text: "fix [[sase]]", caretUTF8: 12))
        XCTAssertEqual(state.acceptedLinkPreview(fieldText: "fix [[sas", caretUTF8: 9), "[[sase]]")
    }

    func testAcceptRejectsRacedCaret() {
        let state = openNoteBand()
        // The caret moved after the reply; the ranges no longer line up.
        XCTAssertNil(state.acceptEdit(fieldText: "fix [[sas", caretUTF8: 8))
        XCTAssertNil(state.acceptedLinkPreview(fieldText: "fix [[sas", caretUTF8: 8))
    }

    func testAcceptRejectsEditedText() {
        let state = openNoteBand()
        XCTAssertNil(state.acceptEdit(fieldText: "fix [[sas!", caretUTF8: 10))
    }

    func testAcceptFallsBackWhenCursorAfterIsUnusable() {
        let broken = CaptureCompletionCandidate(
            replacement: "sase]]", cursorAfter: nil, path: "sase.md",
            name: "sase")
        var state = PullInLinkState()
        state.beginReason()
        state.inputChanged(text: "fix [[sas", cursorUTF8: 9)
        XCTAssertTrue(
            state.receive(
                text: "fix [[sas", cursorUTF8: 9,
                context: .wikilinkNote,
                replacement: CaptureRange(start: 6, end: 9),
                candidates: [broken],
                opensWithoutSelection: false,
                generation: state.generation
            )
        )
        XCTAssertEqual(
            state.acceptEdit(fieldText: "fix [[sas", caretUTF8: 9),
            PullInLinkAcceptEdit(text: "fix [[sase]]", caretUTF8: 12))
    }

    func testAcceptRejectsSplitRange() {
        // `é` is two bytes in UTF-8: a byte range that splits it is not a
        // character boundary, so the accept fails instead of corrupting.
        var state = PullInLinkState()
        state.beginReason()
        state.inputChanged(text: "caf\u{E9} [[x", cursorUTF8: 8)
        XCTAssertTrue(
            state.receive(
                text: "caf\u{E9} [[x", cursorUTF8: 8,
                context: .wikilinkNote,
                replacement: CaptureRange(start: 4, end: 5),
                candidates: noteCandidates(),
                opensWithoutSelection: false,
                generation: state.generation
            )
        )
        XCTAssertNil(state.acceptEdit(fieldText: "caf\u{E9} [[x", caretUTF8: 8))
    }

    func testQueryTextReadsReplacementToCursor() {
        let state = openNoteBand()
        XCTAssertEqual(state.queryText(), "sas")
    }

    func testHeaderCopy() {
        XCTAssertEqual(
            PullInLinkBandPresentation.header(selectedIndex: 2, total: 5),
            PullInLinkBandPresentation.Header(
                title: "LINK · 2 of 5", trailing: "↵ inserts",
                showsKeycaps: false))
        XCTAssertEqual(
            PullInLinkBandPresentation.header(selectedIndex: nil, total: 3),
            PullInLinkBandPresentation.Header(
                title: "LINK · 3", trailing: "↑↓ ↵ ⇥",
                showsKeycaps: true))
        XCTAssertEqual(
            PullInLinkBandPresentation.header(selectedIndex: nil, total: 0),
            PullInLinkBandPresentation.Header(
                title: "LINK · no match", trailing: "",
                showsKeycaps: false))
    }

    func testBandHeightCountsHeaderRowsAndDetail() {
        XCTAssertEqual(
            PullInLinkBandPresentation.bandHeight(rowCount: 2, hasSelection: true),
            16 + 2 * 22 + 20)
        XCTAssertEqual(
            PullInLinkBandPresentation.bandHeight(rowCount: 0, hasSelection: false),
            16)
        XCTAssertEqual(
            PullInLinkBandPresentation.bandHeight(rowCount: 99, hasSelection: true),
            16 + 5 * 22 + 20)
    }
}
