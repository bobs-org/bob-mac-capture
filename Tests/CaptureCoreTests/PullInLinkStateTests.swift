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

    // MARK: - Tasks mode (`((`)

    private static let tasksText = "Superseded by ((api do"

    private func taskRow(
        _ text: String,
        note: String = "projects/api.md",
        blockID: String? = "api-docs",
        ref: String = "2:aaaa",
        group: String = "open",
        suggestions: [String] = [],
        disabled: String? = nil,
        symbol: String = " ",
        statusType: String = "TODO",
        hidden: Bool = false
    ) -> CaptureCompletionCandidate {
        let stem = (note as NSString).lastPathComponent.replacingOccurrences(of: ".md", with: "")
        let link = blockID.map { "[[\(stem)#^\($0)]]" } ?? ""
        let insertable = disabled == nil && !link.isEmpty
        return CaptureCompletionCandidate(
            replacement: insertable ? link : "",
            taskRef: ref,
            blockID: blockID,
            requiresBlockID: blockID == nil,
            statusSymbol: symbol,
            statusName: "Ready",
            statusType: statusType,
            text: text,
            cursorAfter: insertable ? 14 + link.utf8.count : nil,
            linkTarget: stem,
            blockIDSuggestions: suggestions,
            group: group,
            notePath: note,
            locator: stem,
            disabledReason: disabled,
            hidden: hidden
        )
    }

    private func standardTaskRows() -> [CaptureCompletionCandidate] {
        [
            taskRow("API docs overhaul", group: "in_this_note"),
            taskRow(
                "API doc lint", blockID: nil, ref: "3:bbbb", group: "in_this_note",
                suggestions: ["api-doc-lint", "api-doc"]),
            taskRow(
                "Old API doc pass", note: "done/old.md", blockID: nil, ref: "1:cccc",
                group: "completed", suggestions: ["old-api-doc"],
                disabled: "archived tasks can't get an id", symbol: "x",
                statusType: "DONE"),
            taskRow("Update API docs", note: "home.md", blockID: "home-api", ref: "1:dddd"),
        ]
    }

    private func openTasksBand(
        _ rows: [CaptureCompletionCandidate]? = nil,
        subject: PullInLinkSubject? = nil
    ) -> PullInLinkState {
        var state = PullInLinkState()
        state.beginReason(subject: subject)
        state.inputChanged(text: Self.tasksText, cursorUTF8: 22)
        XCTAssertTrue(
            state.receive(
                text: Self.tasksText, cursorUTF8: 22,
                context: .wikilinkTask,
                replacement: CaptureRange(start: 14, end: 22),
                candidates: rows ?? standardTaskRows(),
                opensWithoutSelection: false,
                generation: state.generation
            )
        )
        return state
    }

    func testTaskRowActionsFollowBobsFlags() {
        let state = openTasksBand()
        let rows = state.candidates
        XCTAssertEqual(state.rowAction(for: rows[0]), .insert(link: "[[api#^api-docs]]"))
        guard case .name(let target) = state.rowAction(for: rows[1]) else {
            return XCTFail("ID-less row names")
        }
        XCTAssertEqual(target.notePath, "projects/api.md")
        XCTAssertEqual(target.taskRef, "3:bbbb")
        XCTAssertEqual(target.suggestions, ["api-doc-lint", "api-doc"])
        XCTAssertFalse(target.allowClosed)
        XCTAssertEqual(target.linkTarget, "api")
        XCTAssertEqual(target.taskText, "API doc lint")
        XCTAssertEqual(
            state.rowAction(for: rows[2]),
            .disabled(
                reason: "archived tasks can't get an id",
                badge: "archived tasks can't get an id"))

        // A closed task outside `done/` can be named; it passes
        // `--allow-closed`.
        let closed = taskRow(
            "Shipped", blockID: nil, ref: "5:eeee", suggestions: ["shipped"],
            symbol: "x", statusType: "DONE")
        guard case .name(let closedTarget) = state.rowAction(for: closed) else {
            return XCTFail("Closed ID-less row names")
        }
        XCTAssertTrue(closedTarget.allowClosed)
    }

    func testAnIdentifiedRowWithoutALinkIsUnavailable() {
        let state = openTasksBand()
        let broken = CaptureCompletionCandidate(
            replacement: "", taskRef: "9:ffff", blockID: "x", text: "Broken",
            notePath: "a.md")
        XCTAssertEqual(
            state.rowAction(for: broken),
            .disabled(reason: "This task can't be linked", badge: "unavailable"))
    }

    func testPromptsOwnTaskIsDimmedByNotePathAndBlockID() throws {
        let subject = try XCTUnwrap(
            PullInLinkSubject(notePath: "projects/api.md", blockID: "api-docs"))
        let state = openTasksBand(subject: subject)
        XCTAssertEqual(
            state.rowAction(for: state.candidates[0]),
            .disabled(reason: "The task this prompt is about", badge: "this prompt"))
        // Same note, different task; same ID, different note: not the subject.
        XCTAssertEqual(
            state.rowAction(for: state.candidates[3]), .insert(link: "[[home#^home-api]]"))
        let sameID = taskRow("Elsewhere", note: "other/api.md", blockID: "api-docs")
        XCTAssertEqual(state.rowAction(for: sameID), .insert(link: "[[api#^api-docs]]"))
        XCTAssertNil(PullInLinkSubject(notePath: "projects/api.md", blockID: ""))
        XCTAssertNil(PullInLinkSubject(notePath: "", blockID: "api-docs"))
        // The subject lasts the session and is dropped by a plain reset.
        var reset = state
        reset.beginReason()
        XCTAssertNil(reset.subject)
    }

    func testAcceptEditInsertsBobsLinkOnlyForUsableRows() {
        var state = openTasksBand()
        let edit = state.acceptEdit(fieldText: Self.tasksText, caretUTF8: 22)
        XCTAssertEqual(edit?.text, "Superseded by [[api#^api-docs]]")
        XCTAssertEqual(edit?.caretUTF8, 31)
        XCTAssertEqual(
            state.acceptedLinkPreview(fieldText: Self.tasksText, caretUTF8: 22),
            "[[api#^api-docs]]")

        // An ID-less row and a guarded row never splice.
        _ = state.moveNext()
        XCTAssertNil(state.acceptEdit(fieldText: Self.tasksText, caretUTF8: 22))
        _ = state.moveNext()
        XCTAssertNil(state.acceptEdit(fieldText: Self.tasksText, caretUTF8: 22))
    }

    func testTabAcceptsOnlyRowsThatInsertOrName() {
        var state = openTasksBand()
        XCTAssertTrue(state.selectionCanAccept)
        _ = state.moveNext()
        XCTAssertTrue(state.selectionCanAccept)
        _ = state.moveNext()
        XCTAssertFalse(state.selectionCanAccept)
        _ = state.movePrevious()
        _ = state.movePrevious()
        _ = state.movePrevious()
        XCTAssertNil(state.selectedID)
        XCTAssertFalse(state.selectionCanAccept)
    }

    func testBeginNameOpensStageAgainstTheLiveField() {
        var state = openTasksBand()
        // An identified row never names.
        XCTAssertFalse(state.beginName(fieldText: Self.tasksText, caretUTF8: 22))
        _ = state.moveNext()
        // A raced caret or edited text opens nothing.
        XCTAssertFalse(state.beginName(fieldText: Self.tasksText, caretUTF8: 21))
        XCTAssertFalse(state.beginName(fieldText: Self.tasksText + "!", caretUTF8: 22))
        XCTAssertNil(state.name)

        XCTAssertTrue(state.beginName(fieldText: Self.tasksText, caretUTF8: 22))
        XCTAssertTrue(state.isNaming)
        XCTAssertEqual(state.name?.authoredID, "api-doc-lint")
        XCTAssertEqual(state.name?.replacement, CaptureRange(start: 14, end: 22))
        // Opening is not re-entrant.
        XCTAssertFalse(state.beginName(fieldText: Self.tasksText, caretUTF8: 22))
    }

    func testNameStageValidatesEditsAndCyclesSuggestions() throws {
        var state = openTasksBand()
        _ = state.moveNext()
        XCTAssertTrue(state.beginName(fieldText: Self.tasksText, caretUTF8: 22))
        var stage = try XCTUnwrap(state.name)

        stage.edit("bad id!")
        XCTAssertEqual(stage.validationMessage, "Use only letters, numbers, and hyphens.")
        stage.edit("")
        XCTAssertEqual(stage.validationMessage, "Enter a block ID.")
        stage.edit("Fine-ID-2")
        XCTAssertNil(stage.validationMessage)

        stage.edit("unrelated")
        XCTAssertTrue(stage.cycle(forward: true))
        XCTAssertEqual(stage.authoredID, "api-doc-lint")
        XCTAssertTrue(stage.cycle(forward: true))
        XCTAssertEqual(stage.authoredID, "api-doc")
        XCTAssertTrue(stage.cycle(forward: true))
        XCTAssertEqual(stage.authoredID, "api-doc-lint")
        XCTAssertTrue(stage.cycle(forward: false))
        XCTAssertEqual(stage.authoredID, "api-doc")

        stage.isSaving = true
        stage.edit("changed")
        XCTAssertEqual(stage.authoredID, "api-doc")
        XCTAssertFalse(stage.cycle(forward: true))
    }

    func testNameStageSpliceNeverTouchesAChangedDraft() throws {
        var state = openTasksBand()
        _ = state.moveNext()
        XCTAssertTrue(state.beginName(fieldText: Self.tasksText, caretUTF8: 22))
        let stage = try XCTUnwrap(state.name)
        let link = "[[api#^api-doc-lint]]"

        let edit = stage.splice(
            link: link, liveText: Self.tasksText, liveCaretUTF8: 22)
        XCTAssertEqual(edit?.text, "Superseded by [[api#^api-doc-lint]]")
        XCTAssertEqual(edit?.caretUTF8, 14 + link.utf8.count)

        // The reason changed, the caret moved, or bob sent nothing: insert
        // nothing over text bob never saw.
        XCTAssertNil(stage.splice(link: link, liveText: Self.tasksText + "!", liveCaretUTF8: 22))
        XCTAssertNil(stage.splice(link: link, liveText: Self.tasksText, liveCaretUTF8: 21))
        XCTAssertNil(stage.splice(link: "", liveText: Self.tasksText, liveCaretUTF8: 22))
    }

    func testCancelNameReturnsToTheListWithFilterAndSelectionIntact() {
        var state = openTasksBand()
        _ = state.moveNext()
        let selected = state.selectedID
        XCTAssertTrue(state.beginName(fieldText: Self.tasksText, caretUTF8: 22))
        XCTAssertTrue(state.cancelName())
        XCTAssertFalse(state.isNaming)
        XCTAssertEqual(state.selectedID, selected)
        XCTAssertEqual(state.candidates.count, 4)
        XCTAssertEqual(state.queryText(), "api do")
        XCTAssertFalse(state.cancelName())
    }

    func testTheNameStageOwnsTheBandUntilItEnds() {
        var state = openTasksBand()
        _ = state.moveNext()
        XCTAssertTrue(state.beginName(fieldText: Self.tasksText, caretUTF8: 22))
        let id = state.selectedID
        // A late reply never replaces the rows under the stage.
        XCTAssertFalse(
            state.receive(
                text: Self.tasksText, cursorUTF8: 22, context: .wikilinkTask,
                replacement: CaptureRange(start: 14, end: 22), candidates: [],
                opensWithoutSelection: false, generation: state.generation))
        XCTAssertNil(state.moveNext())
        XCTAssertNil(state.movePrevious())
        XCTAssertFalse(state.select(id: state.candidates[0].id))
        XCTAssertNil(state.acceptEdit(fieldText: Self.tasksText, caretUTF8: 22))
        XCTAssertEqual(state.selectedID, id)
        // Closing the band ends the stage with it.
        XCTAssertTrue(state.close())
        XCTAssertNil(state.name)
    }

    func testWindowFollowsTheSelectionThroughLongTaskLists() {
        let rows = (1...12).map {
            taskRow("Task \($0)", blockID: "task-\($0)", ref: "\($0):aaaa")
        }
        var state = openTasksBand(rows)
        XCTAssertEqual(state.visibleCandidates.map(\.text), (1...5).map { "Task \($0)" })
        for _ in 0..<7 { _ = state.moveNext() }
        XCTAssertEqual(state.selectedIndex, 8)
        XCTAssertEqual(state.visibleCandidates.map(\.text), (4...8).map { "Task \($0)" })
        XCTAssertTrue(state.visibleCandidates.contains { $0.id == state.selectedID })
        for _ in 0..<7 { _ = state.movePrevious() }
        XCTAssertEqual(state.selectedIndex, 1)
        XCTAssertEqual(state.visibleCandidates.first?.text, "Task 1")
        // A fresh reply starts at the top again.
        for _ in 0..<9 { _ = state.moveNext() }
        state.inputChanged(text: Self.tasksText, cursorUTF8: 22)
        XCTAssertTrue(
            state.receive(
                text: Self.tasksText, cursorUTF8: 22, context: .wikilinkTask,
                replacement: CaptureRange(start: 14, end: 22), candidates: rows,
                opensWithoutSelection: false, generation: state.generation))
        XCTAssertEqual(state.visibleCandidates.first?.text, "Task 1")
    }

    func testTasksDetailLinesNameWhatReturnDoes() throws {
        var state = openTasksBand()
        XCTAssertEqual(state.tasksDetailLine, "↵ [[api#^api-docs]]")
        _ = state.moveNext()
        XCTAssertEqual(
            state.tasksDetailLine,
            "↵ names it ^api-doc-lint in projects/api.md, then links it")
        _ = state.moveNext()
        XCTAssertEqual(state.tasksDetailLine, "⊘ archived tasks can't get an id")

        var subject = openTasksBand(
            subject: PullInLinkSubject(notePath: "projects/api.md", blockID: "api-docs"))
        XCTAssertEqual(subject.tasksDetailLine, "⊘ The task this prompt is about")
        _ = subject.moveNext()

        var named = openTasksBand()
        _ = named.moveNext()
        XCTAssertTrue(named.beginName(fieldText: Self.tasksText, caretUTF8: 22))
        XCTAssertEqual(
            named.tasksDetailLine, "↵ adds ^api-doc-lint, then links [[api#^api-doc-lint]]")
        named.name?.edit("bad id")
        XCTAssertEqual(named.tasksDetailLine, "⊘ Use only letters, numbers, and hyphens.")
        named.name?.edit("x-1")
        named.name?.errorMessage = "block ID ^x-1 already exists in api.md"
        XCTAssertEqual(named.tasksDetailLine, "⊘ block ID ^x-1 already exists in api.md")
        named.name?.errorMessage = nil
        named.name?.isSaving = true
        XCTAssertEqual(named.tasksDetailLine, "Adding ^x-1…")

        let empty = openTasksBand([])
        XCTAssertEqual(empty.tasksDetailLine, "↵ closes this list · nothing is inserted")
    }

    func testTasksHeaderAndHeights() throws {
        XCTAssertEqual(
            PullInLinkBandPresentation.header(selectedIndex: 1, total: 4, tasks: true),
            PullInLinkBandPresentation.Header(
                title: "LINK · tasks · 1 of 4", trailing: "↵ inserts", showsKeycaps: false))
        XCTAssertEqual(
            PullInLinkBandPresentation.header(selectedIndex: nil, total: 0, tasks: true).title,
            "LINK · tasks · no match")

        var state = openTasksBand()
        _ = state.moveNext()
        XCTAssertTrue(state.beginName(fieldText: Self.tasksText, caretUTF8: 22))
        let stage = try XCTUnwrap(state.name)
        XCTAssertEqual(
            PullInLinkBandPresentation.nameHeader(for: stage),
            PullInLinkBandPresentation.Header(
                title: "LINK · tasks › name it", trailing: "in projects/api.md",
                showsKeycaps: false))

        XCTAssertEqual(PullInLinkBandPresentation.bandHeight(for: state), 16 + 22 + 26 + 22 + 20)
        // Zero task rows still show the strip naming Return's outcome;
        // a zero-row note band does not.
        XCTAssertEqual(PullInLinkBandPresentation.bandHeight(for: openTasksBand([])), 16 + 20)
        var notes = PullInLinkState()
        notes.beginReason()
        notes.inputChanged(text: "plain", cursorUTF8: 5)
        _ = notes.receive(
            text: "plain", cursorUTF8: 5, context: .wikilinkNote,
            replacement: CaptureRange(start: 5, end: 5), candidates: [],
            opensWithoutSelection: false, generation: notes.generation)
        XCTAssertEqual(PullInLinkBandPresentation.bandHeight(for: notes), 16)
    }

    func testLinkTokenFindsATaskReplacementThatStartsWithItsOpener() {
        // A `((` replacement begins with the `[[` it inserts, so the
        // preview must scan from the insertion point forward as well.
        XCTAssertEqual(
            pullInLinkToken(in: "Superseded by [[api#^api-docs]] more", replacementStart: 14),
            "[[api#^api-docs]]")
        XCTAssertEqual(
            pullInLinkToken(in: "[[api#^api-docs]]", replacementStart: 0),
            "[[api#^api-docs]]")
        // A `[[` completion still scans back to its opener.
        XCTAssertEqual(pullInLinkToken(in: "fix [[sase]]", replacementStart: 6), "[[sase]]")
        // An earlier link never answers for a later insertion.
        XCTAssertEqual(
            pullInLinkToken(in: "[[a#^x]] and [[b#^y]]", replacementStart: 13), "[[b#^y]]")
    }

    func testTasksQueryDropsTheOpener() {
        var state = openTasksBand()
        XCTAssertEqual(state.queryText(), "api do")
        // A bare `((` has an empty query, so the group capsules show.
        state.inputChanged(text: "x ((", cursorUTF8: 4)
        _ = state.receive(
            text: "x ((", cursorUTF8: 4, context: .wikilinkTask,
            replacement: CaptureRange(start: 2, end: 4), candidates: standardTaskRows(),
            opensWithoutSelection: false, generation: state.generation)
        XCTAssertEqual(state.queryText(), "")
    }

    func testTaskRowContentGroupsCapsulesBadgesAndLocator() {
        let rows = [
            taskRow("Reply to Dana", group: "in_this_note"),
            taskRow("Second here", blockID: "second", ref: "4:aaaa", group: "in_this_note"),
            taskRow(
                "Write the API docs", blockID: nil, ref: "5:aaaa", group: "in_progress",
                suggestions: ["write-api"], symbol: "/"),
            taskRow("Quiet one", blockID: "quiet", ref: "6:aaaa", group: "open", hidden: true),
            taskRow(
                "Old one", note: "home.md", blockID: "old", ref: "7:aaaa", group: "completed",
                symbol: "x", statusType: "DONE"),
        ]
        let state = openTasksBand(rows)
        let empty = PullInTaskRowContent.rows(for: rows, state: state, query: "")
        XCTAssertEqual(
            empty.map(\.groupCapsule),
            ["this note", nil, "in progress", "open", "history"])
        XCTAssertEqual(empty[3].badge, "Hidden")
        XCTAssertTrue(empty[3].isDimmed)
        XCTAssertEqual(empty[4].badge, "Done")
        XCTAssertTrue(empty[4].isDimmed)
        XCTAssertFalse(empty[0].isDimmed)
        // The locator is the link it will insert; an ID-less row shows
        // bob's first suggestion as a suggestion.
        XCTAssertEqual(empty[0].locatorTarget, "api")
        XCTAssertEqual(empty[0].locatorID, "api-docs")
        XCTAssertFalse(empty[0].locatorIsSuggestion)
        XCTAssertEqual(empty[2].locatorID, "write-api")
        XCTAssertTrue(empty[2].locatorIsSuggestion)
        XCTAssertEqual(empty[2].status, .inProgress)

        // A query is one ranked flat list: no capsules.
        let filtered = PullInTaskRowContent.rows(for: rows, state: state, query: "api do")
        XCTAssertTrue(filtered.allSatisfy { $0.groupCapsule == nil })
        XCTAssertEqual(filtered[2].matchRanges, [10..<13, 14..<16])
    }

    func testTaskRowContentDimsAndLabelsTheSubject() throws {
        let subject = try XCTUnwrap(
            PullInLinkSubject(notePath: "projects/api.md", blockID: "api-docs"))
        let state = openTasksBand(subject: subject)
        let content = PullInTaskRowContent(
            candidate: state.candidates[0], action: state.rowAction(for: state.candidates[0]))
        XCTAssertEqual(content.badge, "this prompt")
        XCTAssertTrue(content.isDimmed)
        XCTAssertEqual(
            content.accessibilityLabel,
            "Ready, API docs overhaul, api#^api-docs, The task this prompt is about")
    }

    func testMatchRangesMarkEveryQueryTermCaseInsensitively() {
        XCTAssertEqual(
            PullInTaskRowContent.matchRanges(in: "API docs overhaul", query: "api do"),
            [0..<3, 4..<6])
        XCTAssertEqual(
            PullInTaskRowContent.matchRanges(in: "API docs overhaul", query: "DOCS"),
            [4..<8])
        XCTAssertTrue(PullInTaskRowContent.matchRanges(in: "API docs", query: "").isEmpty)
        XCTAssertTrue(PullInTaskRowContent.matchRanges(in: "API docs", query: "zzz").isEmpty)
    }
}
