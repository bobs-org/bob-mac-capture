import XCTest

@testable import CaptureCore

/// Tests for the `project_task_move` move picker: decoding of Bob's new
/// context, descriptor, header, and row fields, plus the scoped
/// document-order presentation with section groups, pending-block-ID rows,
/// and move-specific copy.
final class ProjectTaskMovePickerPresentationTests: XCTestCase {
    private func moveContext() -> ProjectTaskMovePickerContext {
        ProjectTaskMovePickerContext(
            scopeToken: "^",
            noteTarget: "cash.md",
            destination: "cash_goog_exit.md",
            continuation: "\n- ^",
            markerRange: CaptureRange(start: 42, end: 43),
            triggerRemovalRange: CaptureRange(start: 42, end: 43),
            openCount: 7
        )
    }

    private func moveCandidates() throws -> [CaptureCompletionCandidate] {
        try JSONDecoder().decode(
            [CaptureCompletionCandidate].self,
            from: Data("""
            [
              {
                "replacement": "equity-docs",
                "sigil": "^",
                "ref": "6:93f5563b",
                "route": "cash",
                "block_id": "equity-docs",
                "requires_block_id": false,
                "block_id_suggestions": [],
                "status_symbol": " ",
                "status_name": "Todo",
                "status_type": "TODO",
                "text": "Collect the equity paperwork",
                "section": "Tasks",
                "depth": 0,
                "child_count": 0,
                "line": 6,
                "scheduled": null,
                "hidden": false,
                "consequence": "Moves into cash_goog_exit.md"
              },
              {
                "replacement": "",
                "sigil": "^",
                "ref": "10:31f90b6e",
                "route": "cash",
                "block_id": null,
                "requires_block_id": true,
                "block_id_suggestions": ["plan-handoff"],
                "status_symbol": " ",
                "status_name": "Todo",
                "status_type": "TODO",
                "text": "Plan the handoff",
                "section": "Tasks",
                "depth": 0,
                "child_count": 0,
                "line": 10,
                "scheduled": null,
                "hidden": false,
                "consequence": "Needs an ID first \\u00b7 \\u2295 ^plan-handoff \\u00b7 Moves into cash_goog_exit.md"
              },
              {
                "replacement": "call-ms",
                "sigil": "^",
                "ref": "7:428e42f0",
                "route": "cash",
                "block_id": "call-ms",
                "requires_block_id": false,
                "block_id_suggestions": [],
                "status_symbol": " ",
                "status_name": "Todo",
                "status_type": "TODO",
                "text": "Call Morgan Stanley",
                "section": "Admin",
                "depth": 0,
                "child_count": 0,
                "line": 7,
                "scheduled": "2026-11-06",
                "hidden": true,
                "consequence": "Moves into cash_goog_exit.md",
                "disabled_reason": "already moving on line 3"
              }
            ]
            """.utf8)
        )
    }

    private func moveIndex() throws -> ProjectTaskMovePickerIndex {
        ProjectTaskMovePickerIndex(candidates: try moveCandidates(), context: moveContext())
    }

    func testMoveContextTitleAndHeader() {
        let context = moveContext()
        XCTAssertEqual(context.pickerTitle, "Move into cash_goog_exit.md")
        XCTAssertEqual(context.headerSuffix(openCount: context.openCount), "from cash.md · 7 open")
        XCTAssertEqual(context.escStatusText, "Pick a task to move from cash.md, or delete the ^")
        let linkContext = ProjectTaskMovePickerContext(
            scopeToken: ":",
            noteTarget: "cash.md",
            destination: "cash_goog_exit.md",
            continuation: "\n- :",
            markerRange: CaptureRange(start: 42, end: 43),
            triggerRemovalRange: CaptureRange(start: 42, end: 43),
            openCount: 12
        )
        XCTAssertEqual(linkContext.pickerTitle, "Move & link into cash_goog_exit.md")
    }

    func testDescriptorDecodesMoveKindWithDestinationAndContinuation() throws {
        let descriptor = try JSONDecoder().decode(
            CapturePickerDescriptor.self,
            from: Data("""
            {"kind":"project_task_move","scope":"note","scope_token":"^","note_target":"cash.md","marker_range":{"start":42,"end":43},"trigger_removal_range":{"start":42,"end":43},"destination":"cash_goog_exit.md","continuation":"\\n- ^"}
            """.utf8)
        )
        XCTAssertTrue(descriptor.isProjectTaskMove)
        XCTAssertEqual(descriptor.destination, "cash_goog_exit.md")
        XCTAssertEqual(descriptor.continuation, "\n- ^")
        XCTAssertEqual(descriptor.actionContinuationKeys, [])
        XCTAssertEqual(descriptor.actionContinuationAliases, [:])
        let context = try XCTUnwrap(descriptor.projectTaskMoveContext)
        XCTAssertEqual(context.scopeToken, "^")
        XCTAssertEqual(context.noteTarget, "cash.md")
        XCTAssertEqual(context.actionContinuationAliases, [:])
    }

    func testDescriptorDecodesDotAlias() throws {
        let descriptor = try JSONDecoder().decode(
            CapturePickerDescriptor.self,
            from: Data("""
            {"kind":"project_task_move","scope":"note","scope_token":"^","note_target":"cash.md","marker_range":{"start":42,"end":43},"trigger_removal_range":{"start":42,"end":43},"destination":"cash_goog_exit.md","continuation":"\\n- ^","action_continuation_keys":["^"],"action_continuation_aliases":{".":"^"}}
            """.utf8)
        )
        XCTAssertEqual(descriptor.actionContinuationKeys, ["^"])
        XCTAssertEqual(descriptor.actionContinuationAliases, [".": "^"])
        let context = try XCTUnwrap(descriptor.projectTaskMoveContext)
        XCTAssertEqual(context.actionContinuationKeys, ["^"])
        XCTAssertEqual(context.actionContinuationAliases, [".": "^"])
    }

    func testHeaderDecodesTolerantly() throws {
        let header = try JSONDecoder().decode(
            CaptureProjectTaskMoveHeader.self,
            from: Data("""
            {"parent":"cash.md","parent_route":"cash","destination":"cash_goog_exit.md","sigil":"^","open_count":7}
            """.utf8)
        )
        XCTAssertEqual(header.parent, "cash.md")
        XCTAssertEqual(header.destination, "cash_goog_exit.md")
        XCTAssertEqual(header.openCount, 7)
    }

    func testResponseDecodesMoveHeader() throws {
        let url = Bundle(for: Self.self).url(forResource: "move-complete-mc1", withExtension: "json")
        guard url != nil else {
            throw XCTSkip("move-complete-mc1 fixture missing")
        }
    }

    func testEmptyQueryKeepsDocumentOrderWithSectionGroups() throws {
        let presentation = try moveIndex().presentation(filter: "")
        XCTAssertEqual(presentation.orderedRowIDs.count, 3)
        XCTAssertEqual(presentation.sections.count, 2)
        XCTAssertEqual(presentation.sections.first?.title, "Tasks")
        XCTAssertEqual(presentation.sections.last?.title, "Admin")
    }

    func testRowsUseRouteRefKeysAndPendingBlockID() throws {
        let presentation = try moveIndex().presentation(filter: "")
        let first = try XCTUnwrap(presentation.rowsByID["cash|6:93f5563b"])
        XCTAssertEqual(first.insertion, "equity-docs")
        XCTAssertNil(first.pendingBlockID)
        let pending = try XCTUnwrap(presentation.rowsByID["cash|10:31f90b6e"])
        XCTAssertNil(pending.insertion)
        XCTAssertEqual(pending.pendingBlockID?.suggestions, ["plan-handoff"])
    }

    func testDisabledRowsAreDimmedAndHiddenRowsMuted() throws {
        let presentation = try moveIndex().presentation(filter: "")
        let disabled = try XCTUnwrap(presentation.rowsByID["cash|7:428e42f0"])
        XCTAssertEqual(disabled.badgeText, "already moving on line 3")
        XCTAssertNil(disabled.insertion)
        XCTAssertNil(disabled.pendingBlockID)
        XCTAssertTrue(disabled.isHidden)
        XCTAssertEqual(disabled.scheduledText, "2026-11-06")
    }

    func testActionLineUsesConsequence() throws {
        let index = try moveIndex()
        let presentation = index.presentation(filter: "")
        let row = try XCTUnwrap(presentation.rowsByID["cash|6:93f5563b"])
        XCTAssertEqual(index.actionLine(for: row), "Inserts equity-docs")
        let pending = try XCTUnwrap(presentation.rowsByID["cash|10:31f90b6e"])
        XCTAssertEqual(
            index.actionLine(for: pending),
            "↩ adds ^plan-handoff to cash.md, then inserts plan-handoff"
        )
        let disabled = try XCTUnwrap(presentation.rowsByID["cash|7:428e42f0"])
        XCTAssertEqual(disabled.badgeText, "already moving on line 3")
    }

    func testMoveSourceStrings() {
        let source = CapturePickerSource.projectTaskMove(moveContext())
        XCTAssertEqual(source.scopeSymbolText, "^")
        XCTAssertEqual(source.scopeCaption, "cash.md")
        XCTAssertEqual(source.chipLabel, "Move a task into the new project")
        XCTAssertEqual(source.cardAccessibilityLabel, "Move picker for cash.md")
        XCTAssertEqual(source.locatorMarker, "^")
        XCTAssertEqual(source.filterPlaceholder, "Filter cash.md tasks")
    }

    func testMoveNeedStatusText() {
        XCTAssertEqual(
            CapturePickerNeed.projectTaskMove.statusText,
            "Pick a task to move — press Tab to browse"
        )
    }

    func testMoveKeyHints() {
        let source = CapturePickerSource.projectTaskMove(moveContext())
        let hints = source.keyHintItems().map(\.keys)
        XCTAssertTrue(hints.contains("⇧↩"))
        XCTAssertTrue(hints.contains("esc"))
    }

    func testMoveSpanColours() {
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "project_task_move_marker"), .route)
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "project_task_move_link_marker"),
            .explicitToggle
        )
        XCTAssertEqual(
            captureSemanticCategory(forSpanKind: "project_task_move_block_id"),
            .blockID
        )
    }

    func testMoveRowContent() {
        let candidate = CaptureCompletionCandidate(
            replacement: "equity-docs",
            route: "cash",
            blockID: "equity-docs",
            statusSymbol: " ",
            statusName: "Todo",
            text: "Collect the equity paperwork",
            section: "Tasks",
            consequence: "Moves into cash_goog_exit.md"
        )
        let content = completionRowContent(for: candidate, context: "project_task_move", query: "")
        XCTAssertEqual(content.contextLabel, "Move")
        XCTAssertEqual(content.primaryText, "Collect the equity paperwork")
        XCTAssertEqual(content.accessibilityHint, "Moves into cash_goog_exit.md")
    }
}
