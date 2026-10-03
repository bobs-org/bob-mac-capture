import XCTest

@testable import CaptureCore

/// Tests for the `+` / `@route+` parent-task picker index. Vault empty-query
/// rows keep the colon groups; scoped empty-query rows keep document order.
/// Replacements use `@route+id`; ID-less rows stay keyed by `route|ref`.
final class ParentTaskPickerPresentationTests: XCTestCase {
    private func vaultCandidatesJSON() -> String {
        """
        [
          {
            "replacement": "@sase+deep-fix",
            "ref": "7:aaaa1111",
            "route": "sase",
            "note_kind": "project",
            "block_id": "deep-fix",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "*",
            "status_name": "Next",
            "status_type": "on_hold",
            "text": "Fix deep bug",
            "section": "Bugs",
            "depth": 0,
            "line": 7,
            "group": "queued",
            "pomodoro": {"line": 5, "name": "BUGS", "time_range": null, "is_current": false}
          },
          {
            "replacement": "@sase+outline",
            "ref": "11:bbbb2222",
            "route": "sase",
            "note_kind": "project",
            "block_id": "outline",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "/",
            "status_name": "In Progress",
            "status_type": "in_progress",
            "text": "Draft outline",
            "section": "Writing",
            "depth": 0,
            "line": 11,
            "group": "in_progress"
          },
          {
            "replacement": "@sase+blog",
            "ref": "12:cccc3333",
            "route": "sase",
            "note_kind": "project",
            "block_id": "blog",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Ship blog post #now",
            "section": "Writing",
            "depth": 0,
            "line": 12,
            "group": "note"
          },
          {
            "replacement": "",
            "ref": "1:dddd4444",
            "route": "mac_inbox",
            "note_kind": "inbox",
            "block_id": null,
            "requires_block_id": true,
            "block_id_suggestions": ["call-bank"],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Call the bank",
            "section": null,
            "depth": 0,
            "line": 1,
            "group": "note"
          },
          {
            "replacement": "",
            "ref": "3:eeee5555",
            "route": "health",
            "note_kind": "area",
            "block_id": null,
            "requires_block_id": true,
            "block_id_suggestions": ["book-dentist"],
            "status_symbol": "?",
            "status_name": "Blocked",
            "status_type": "TODO",
            "text": "Book dentist",
            "section": "Errands",
            "depth": 0,
            "line": 3,
            "group": "note",
            "scheduled": "2026-10-03"
          },
          {
            "replacement": "@bob+polish",
            "ref": "2:ffff6666",
            "route": "bob",
            "note_kind": "project",
            "block_id": "polish",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Polish capture picker",
            "section": null,
            "depth": 0,
            "line": 2,
            "group": "note"
          },
          {
            "replacement": "",
            "ref": "3:gggg7777",
            "route": "bob",
            "note_kind": "project",
            "block_id": null,
            "requires_block_id": true,
            "block_id_suggestions": ["tune-fuzzy-weights"],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Tune fuzzy weights",
            "section": null,
            "depth": 1,
            "line": 3,
            "group": "note"
          },
          {
            "replacement": "",
            "ref": "9:hhhh8888",
            "route": "sase",
            "note_kind": "project",
            "block_id": null,
            "requires_block_id": true,
            "block_id_suggestions": ["fix-flaky-gkeep", "flaky-gkeep-test"],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Fix flaky gkeep test",
            "section": "Bugs",
            "depth": 0,
            "line": 9,
            "group": "note"
          }
        ]
        """
    }

    private func vaultCandidates() throws -> [CaptureCompletionCandidate] {
        try JSONDecoder().decode(
            [CaptureCompletionCandidate].self,
            from: Data(vaultCandidatesJSON().utf8)
        )
    }

    private func vaultContext() -> ParentTaskPickerContext {
        .vault(
            markerRange: CaptureRange(start: 0, end: 1),
            actionContinuationKeys: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+"]
        )
    }

    private func vaultIndex() throws -> ParentTaskPickerIndex {
        ParentTaskPickerIndex(candidates: try vaultCandidates(), context: vaultContext())
    }

    private func vaultPresentation(filter: String = "") throws -> CapturePickerPresentation {
        try vaultIndex().presentation(filter: filter)
    }

    private func scopedCandidates() throws -> [CaptureCompletionCandidate] {
        try JSONDecoder().decode(
            [CaptureCompletionCandidate].self,
            from: Data("""
            [
              {
                "replacement": "goog-exit",
                "ref": "4:googexit",
                "route": "cash",
                "note_kind": "area",
                "block_id": "goog-exit",
                "requires_block_id": false,
                "status_symbol": "*",
                "status_name": "Next",
                "text": "Finish Google Exit Packet!",
                "section": "Tasks",
                "depth": 0,
                "line": 4,
                "group": "note"
              },
              {
                "replacement": "",
                "ref": "8:handoff",
                "route": "cash",
                "note_kind": "area",
                "requires_block_id": true,
                "block_id_suggestions": ["plan-handoff", "handoff"],
                "status_symbol": " ",
                "status_name": "Todo",
                "text": "Plan the handoff",
                "section": "Tasks",
                "depth": 1,
                "line": 8,
                "group": "note"
              }
            ]
            """.utf8)
        )
    }

    private func scopedContext() -> ParentTaskPickerContext {
        .note(
            route: "cash",
            noteTarget: "cash.md",
            markerRange: CaptureRange(start: 0, end: 6),
            triggerRemovalRange: CaptureRange(start: 5, end: 6)
        )
    }

    private func scopedIndex() throws -> ParentTaskPickerIndex {
        ParentTaskPickerIndex(candidates: try scopedCandidates(), context: scopedContext())
    }

    // MARK: - Decoding / context

    func testVaultContextIsLonePlusOperator() {
        let context = vaultContext()
        XCTAssertTrue(context.isVault)
        XCTAssertTrue(context.isLonePlusOperator)
        XCTAssertEqual(context.scopeToken, "+")
        XCTAssertEqual(context.noteFileName, "this note")
    }

    func testScopedContextIsNotOperatorHandoff() {
        let context = scopedContext()
        XCTAssertFalse(context.isVault)
        XCTAssertFalse(context.isLonePlusOperator)
        XCTAssertEqual(context.scopeToken, "@cash+")
        XCTAssertEqual(context.noteFileName, "cash.md")
        XCTAssertEqual(context.actionContinuationKeys, [])
    }

    func testProseTerminalVaultOmitsContinuationKeys() {
        let context = ParentTaskPickerContext.vault(markerRange: CaptureRange(start: 16, end: 17))
        XCTAssertTrue(context.isVault)
        XCTAssertFalse(context.isLonePlusOperator)
    }

    func testDecodingDropsPullsForwardAndKeepsPlusReplacement() throws {
        let candidates = try vaultCandidates()
        XCTAssertEqual(candidates[0].replacement, "@sase+deep-fix")
        XCTAssertFalse(candidates[0].pullsForward)
        XCTAssertEqual(candidates[4].scheduled, "2026-10-03")
        XCTAssertFalse(candidates[4].pullsForward)
        XCTAssertTrue(candidates[4].requiresBlockID)
    }

    func testTaskParentContextRawValue() {
        XCTAssertEqual(CaptureCompletionContext(rawContext: "task_parent"), .taskParent)
        XCTAssertNil(CaptureCompletionContext(rawContext: "task_parrent"))
    }

    // MARK: - Vault grouped view

    func testVaultGroupedSectionOrderTitlesAndSubtitles() throws {
        let presentation = try vaultPresentation()
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.countText, "8 tasks")
        XCTAssertEqual(
            presentation.sections.map(\.id),
            ["pomodoro-5", "unqueued-in-progress", "note-sase", "note-mac_inbox", "note-health", "note-bob"]
        )
        XCTAssertEqual(
            presentation.sections.map(\.title),
            ["BUGS", "In Progress", "sase.md", "mac_inbox.md", "health.md", "bob.md"]
        )
        XCTAssertEqual(
            presentation.sections.map(\.subtitle),
            [nil, nil, "Project", "Inbox", "Area", "Project"]
        )
    }

    func testVaultRowsUseRouteRefKeysAndPlusInsertions() throws {
        let presentation = try vaultPresentation()
        XCTAssertEqual(
            presentation.orderedRowIDs,
            [
                "sase|7:aaaa1111",
                "sase|11:bbbb2222",
                "sase|12:cccc3333",
                "sase|9:hhhh8888",
                "mac_inbox|1:dddd4444",
                "health|3:eeee5555",
                "bob|2:ffff6666",
                "bob|3:gggg7777",
            ]
        )
        let identified = try XCTUnwrap(presentation.rowsByID["sase|7:aaaa1111"])
        XCTAssertEqual(identified.insertion, "@sase+deep-fix")
        XCTAssertFalse(identified.pullsForward)
        XCTAssertEqual(identified.detail.insertionPrefix, "@")
        let pending = try XCTUnwrap(presentation.rowsByID["mac_inbox|1:dddd4444"])
        XCTAssertNil(pending.insertion)
        XCTAssertEqual(pending.pendingBlockID?.suggestions, ["call-bank"])
    }

    func testVaultEmptyCatalogState() {
        let presentation = ParentTaskPickerIndex(
            candidates: [],
            context: vaultContext()
        ).presentation(filter: "")
        XCTAssertEqual(presentation.emptyState?.title, "No open tasks")
        XCTAssertEqual(presentation.emptyState?.message, "No open tasks in your capture notes.")
        XCTAssertEqual(presentation.visibleRowBudget, 4)
    }

    // MARK: - Scoped document order

    func testScopedEmptyQueryKeepsDocumentOrderOneSection() throws {
        let presentation = try scopedIndex().presentation(filter: "")
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.sections.map(\.id), ["document"])
        XCTAssertEqual(presentation.sections.map(\.kind), [.matches])
        XCTAssertEqual(presentation.orderedRowIDs, ["cash|4:googexit", "cash|8:handoff"])
        XCTAssertEqual(presentation.row(id: "cash|4:googexit")?.insertion, "goog-exit")
        XCTAssertEqual(presentation.row(id: "cash|8:handoff")?.depth, 1)
        XCTAssertEqual(presentation.countText, "2 tasks")
    }

    func testScopedEmptyCatalogNamesTheNote() {
        let presentation = ParentTaskPickerIndex(
            candidates: [],
            context: scopedContext()
        ).presentation(filter: "")
        XCTAssertEqual(presentation.emptyState?.title, "No tasks in cash.md")
        XCTAssertEqual(presentation.emptyState?.message, "No open tasks in cash.md.")
    }

    // MARK: - Filtered ranking

    func testFilterUsesLeadingPlusSigilAndCombinedRoutePlusID() throws {
        let presentation = try vaultPresentation(filter: "+sase+deep")
        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertEqual(presentation.orderedRowIDs.first, "sase|7:aaaa1111")
        let row = try XCTUnwrap(presentation.rowsByID["sase|7:aaaa1111"])
        XCTAssertFalse(row.routeMatchRanges.isEmpty)
        XCTAssertFalse(row.blockIDMatchRanges.isEmpty)
    }

    func testSpacesAreANDTermsAndPreserveBobOrderOnTies() throws {
        let presentation = try vaultPresentation(filter: "sase")
        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertTrue(presentation.orderedRowIDs.allSatisfy { $0.hasPrefix("sase|") })
        XCTAssertEqual(presentation.orderedRowIDs.first, "sase|7:aaaa1111")
    }

    func testStatusFieldMatchesAtHalfWeight() throws {
        let presentation = try vaultPresentation(filter: "blocked")
        XCTAssertEqual(presentation.orderedRowIDs, ["health|3:eeee5555"])
    }

    func testNoMatchesEmptyState() throws {
        let presentation = try vaultPresentation(filter: "zzz-no-match")
        XCTAssertEqual(presentation.emptyState?.title, "No matches")
        XCTAssertEqual(
            presentation.emptyState?.message,
            "No open tasks match “zzz-no-match” — Esc clears the filter."
        )
    }

    func testDuplicateRouteRefKeysAreDropped() throws {
        var candidates = try vaultCandidates()
        candidates.append(candidates[0])
        let presentation = ParentTaskPickerIndex(
            candidates: candidates,
            context: vaultContext()
        ).presentation(filter: "")
        XCTAssertEqual(presentation.totalCount, 8)
    }

    // MARK: - Action lines

    func testIdentifiedActionLineInsertsPlusMarker() throws {
        let index = try vaultIndex()
        let row = try XCTUnwrap(index.presentation(filter: "").rowsByID["sase|7:aaaa1111"])
        XCTAssertEqual(index.actionLine(for: row), "Inserts @sase+deep-fix")
    }

    func testIDLessActionLineUsesPlusMarker() throws {
        let index = try vaultIndex()
        let row = try XCTUnwrap(index.presentation(filter: "").rowsByID["sase|9:hhhh8888"])
        XCTAssertEqual(
            index.actionLine(for: row),
            "↩ adds ^fix-flaky-gkeep to sase.md, then inserts @sase+fix-flaky-gkeep"
        )
    }

    // MARK: - Source and need

    func testVaultSourceStrings() {
        let source = CapturePickerSource.parentTask(vaultContext())
        XCTAssertEqual(source.triggerByte, 43)
        XCTAssertEqual(source.filterPlaceholder, "Search tasks by text, note, or +id")
        XCTAssertEqual(source.filterAccessibilityLabel, "Search open tasks across capture notes")
        XCTAssertEqual(source.scopeSymbolText, "+")
        XCTAssertEqual(source.scopeCaption, "All capture notes")
        XCTAssertEqual(source.chipLabel, "Select a parent task")
        XCTAssertEqual(source.chipIcon, "plus")
        XCTAssertEqual(source.cardAccessibilityLabel, "Parent task picker")
        XCTAssertEqual(source.appearedAnnouncementPrefix, "All capture notes")
        XCTAssertEqual(source.locatorMarker, "+")
        XCTAssertEqual(
            source.operatorContinuationHint,
            "Type a number or + to adjust; Esc to extend +5m"
        )
        XCTAssertEqual(
            source.pickerUsedDefaultsKey,
            "org.bobs.bob-mac-capture.parent-task-picker-used"
        )
    }

    func testScopedSourceStrings() {
        let source = CapturePickerSource.parentTask(scopedContext())
        XCTAssertEqual(source.scopeSymbolText, "@cash+")
        XCTAssertEqual(source.scopeCaption, "cash.md")
        XCTAssertEqual(source.chipLabel, "Append to a task")
        XCTAssertEqual(source.filterPlaceholder, "Filter cash.md tasks")
        XCTAssertEqual(source.cardAccessibilityLabel, "Parent task picker for cash.md")
        XCTAssertNil(source.operatorContinuationHint)
        XCTAssertEqual(source.locatorMarker, "+")
    }

    func testParentTaskKeyHintsOmitShiftReturn() {
        let source = CapturePickerSource.parentTask(vaultContext())
        XCTAssertEqual(source.keyHintItems().map(\.keys), ["↑↓", "↩", "⌘↩", "esc"])
        XCTAssertEqual(
            source.keyHintItems().map(\.action),
            ["Move", "Select Task", "Select & Capture", "Clear / Cancel"]
        )
        XCTAssertEqual(
            source.keyHintsAccessibilityLabel,
            "Picker keys: up and down to move, Return to select the task, Command Return to select and capture, Escape to clear or cancel."
        )
    }

    func testTaskParentNeedStatus() {
        XCTAssertEqual(
            CapturePickerNeed.taskParent.statusText,
            "Choose a task to append to — press Tab to browse"
        )
    }
}
