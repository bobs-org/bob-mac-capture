import XCTest

@testable import CaptureCore

/// Tests for the `&` dependency picker index, using a JSON sample shaped like
/// Bob's `task_dependency` completion: Bob-order candidates across the
/// `in_progress` / `next` / `open` / `completed` groups, one ID-less row, one
/// `#hide` row, one already-present row, and one guarded row.
final class DependencyPickerPresentationTests: XCTestCase {
    /// The seven worked-example candidates in Bob's canonical order.
    private func workedExampleJSON() -> String {
        """
        [
          {
            "replacement": "&sase:deep-fix",
            "ref": "7:aaaa1111",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "in_progress",
            "hidden": false,
            "block_id": "deep-fix",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "/",
            "status_name": "In Progress",
            "status_type": "in_progress",
            "text": "Fix deep bug",
            "section": "Bugs",
            "depth": 0,
            "line": 7
          },
          {
            "replacement": "&sase:outline",
            "ref": "11:bbbb2222",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "next",
            "hidden": false,
            "block_id": "outline",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "*",
            "status_name": "Next",
            "status_type": "on_hold",
            "text": "Draft outline",
            "section": "Writing",
            "depth": 0,
            "line": 11
          },
          {
            "replacement": "&cash:budget",
            "ref": "12:cccc3333",
            "note_path": "cash.md",
            "locator": "cash",
            "group": "open",
            "hidden": false,
            "block_id": "budget",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Confirm grocery budget",
            "section": "Errands",
            "depth": 0,
            "line": 12
          },
          {
            "replacement": "",
            "ref": "1:dddd4444",
            "note_path": "cash.md",
            "locator": "cash",
            "group": "open",
            "hidden": false,
            "block_id": null,
            "requires_block_id": true,
            "block_id_suggestions": ["call-bank"],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Call the bank",
            "section": null,
            "depth": 0,
            "line": 1
          },
          {
            "replacement": "&ref/chat/memo:ref",
            "ref": "20:eeee5555",
            "note_path": "ref/chat/memo.md",
            "locator": "ref/chat/memo",
            "group": "open",
            "hidden": true,
            "block_id": "ref",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Read the memo",
            "section": null,
            "depth": 0,
            "line": 20
          },
          {
            "replacement": "&cash:budget",
            "ref": "12:cccc3333",
            "note_path": "cash.md",
            "locator": "cash",
            "group": "open",
            "hidden": false,
            "block_id": "budget",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "already_dependency": true,
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Confirm grocery budget",
            "section": "Errands",
            "depth": 0,
            "line": 12
          },
          {
            "replacement": "&sase:old-ship",
            "ref": "2:ffff6666",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "completed",
            "hidden": false,
            "block_id": "old-ship",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "disabled_reason": "Completed tasks never block",
            "status_symbol": "x",
            "status_name": "Done",
            "status_type": "DONE",
            "text": "Ship old release",
            "section": null,
            "depth": 0,
            "line": 2
          }
        ]
        """
    }

    private func workedExampleCandidates() throws -> [CaptureCompletionCandidate] {
        try JSONDecoder().decode(
            [CaptureCompletionCandidate].self,
            from: Data(workedExampleJSON().utf8)
        )
    }

    private func workedExamplePresentation(filter: String = "") throws -> CapturePickerPresentation {
        try DependencyPickerIndex(candidates: workedExampleCandidates()).presentation(filter: filter)
    }

    // MARK: - Decoding

    func testDecodingReadsDependencyFields() throws {
        let candidates = try workedExampleCandidates()
        let first = try XCTUnwrap(candidates.first)
        XCTAssertEqual(first.replacement, "&sase:deep-fix")
        XCTAssertEqual(first.notePath, "sase.md")
        XCTAssertEqual(first.locator, "sase")
        XCTAssertEqual(first.group, "in_progress")
        XCTAssertFalse(first.hidden)
        XCTAssertFalse(first.alreadyDependency)
        XCTAssertNil(first.disabledReason)

        let idLess = candidates[3]
        XCTAssertEqual(idLess.notePath, "cash.md")
        XCTAssertTrue(idLess.requiresBlockID)
        XCTAssertEqual(idLess.blockIDSuggestions, ["call-bank"])

        let hidden = candidates[4]
        XCTAssertTrue(hidden.hidden)
        XCTAssertEqual(hidden.notePath, "ref/chat/memo.md")

        let guarded = candidates[6]
        XCTAssertEqual(guarded.disabledReason, "Completed tasks never block")
    }

    func testDecodingDefaultsWhenKeysAbsent() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement": "@sase:deep-fix", "route": "sase", "block_id": "deep-fix"}
            """.utf8)
        )
        XCTAssertNil(candidate.notePath)
        XCTAssertNil(candidate.locator)
        XCTAssertFalse(candidate.alreadyDependency)
        XCTAssertNil(candidate.disabledReason)
        XCTAssertFalse(candidate.hidden)
    }

    func testAlreadyDependencyDuplicateKeyDedupes() throws {
        // The already-present row repeats the cash/budget identity: the
        // index keys on `note_path|ref`, so it collapses into one entry.
        let index = try DependencyPickerIndex(candidates: workedExampleCandidates())
        XCTAssertEqual(index.count, 6)
    }

    func testDependencyContextRawValue() {
        XCTAssertEqual(CaptureCompletionContext(rawContext: "task_dependency"), .taskDependency)
        XCTAssertNil(CaptureCompletionContext(rawContext: "task_dependenc"))
    }

    func testDependencyInlineRowReadsAsPrerequisite() throws {
        let candidates = try workedExampleCandidates()
        let content = completionRowContent(
            for: candidates[0],
            context: "task_dependency",
            query: ""
        )
        XCTAssertEqual(content.contextLabel, "Prerequisite")
        XCTAssertEqual(content.primaryText, "Fix deep bug")
        XCTAssertEqual(content.secondaryText, "sase:deep-fix · Bugs")
    }

    func testDependencyOwnerDecodes() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data("""
            {
              "ok": true, "schema_version": 1, "cursor": 30,
              "replacement": {"start": 0, "end": 9},
              "context": "task_dependency", "candidates": [],
              "query": "cash:bu",
              "owner": {"kind": "existing_task", "route": "home", "block_id": "groceries"}
            }
            """.utf8)
        )
        XCTAssertEqual(response.query, "cash:bu")
        XCTAssertEqual(response.owner?.headerText, "@home+groceries")
        XCTAssertTrue(response.owner?.isExistingTask ?? false)
    }

    func testDependencyResponseToleratesOlderBob() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data("""
            {
              "ok": true, "schema_version": 1, "cursor": 1,
              "replacement": {"start": 0, "end": 1},
              "context": "task_link", "candidates": []
            }
            """.utf8)
        )
        XCTAssertNil(response.query)
        XCTAssertNil(response.owner)
    }

    // MARK: - Grouped view

    func testGroupedSectionsFollowBobOrder() throws {
        let presentation = try workedExamplePresentation()
        XCTAssertEqual(presentation.mode, .grouped)
        let titles = presentation.sections.map { $0.title }
        XCTAssertEqual(titles, ["In Progress", "Next", "cash.md", "ref/chat/memo.md", "Completed history"])
        XCTAssertEqual(presentation.countText, "6 tasks")
    }

    func testHiddenRowsSortLastWithinSection() throws {
        let presentation = try workedExamplePresentation()
        // The hidden memo is the only row in its note section; the open
        // cash section keeps Bob order with the ID-less row in place.
        let cash = try XCTUnwrap(presentation.sections.first { $0.title == "cash.md" })
        XCTAssertEqual(cash.rows.count, 2)
        XCTAssertEqual(cash.rows[0].displayText, "Confirm grocery budget")
    }

    func testCompletedHistoryIsSeparate() throws {
        let presentation = try workedExamplePresentation()
        let history = try XCTUnwrap(presentation.sections.last)
        XCTAssertEqual(history.title, "Completed history")
        XCTAssertEqual(history.subtitle, "Non-blocking")
        XCTAssertEqual(history.rows.count, 1)
    }

    // MARK: - Rows

    func testIdentifiedRowInsertsBobReplacement() throws {
        let presentation = try workedExamplePresentation()
        let row = try XCTUnwrap(presentation.rowsByID["sase.md|7:aaaa1111"])
        XCTAssertEqual(row.insertion, "&sase:deep-fix")
        XCTAssertNil(row.pendingBlockID)
        XCTAssertNil(row.badgeText)
        XCTAssertEqual(row.detail.insertionPrefix, "&")
    }

    func testIDLessRowOpensExactPathFlow() throws {
        let presentation = try workedExamplePresentation()
        let row = try XCTUnwrap(presentation.rowsByID["cash.md|1:dddd4444"])
        XCTAssertNil(row.insertion)
        let pending = try XCTUnwrap(row.pendingBlockID)
        XCTAssertEqual(pending.route, "cash.md")
        XCTAssertEqual(pending.suggestions, ["call-bank"])
    }

    func testGuardedRowChangesNothing() throws {
        let presentation = try workedExamplePresentation()
        let row = try XCTUnwrap(presentation.rowsByID["sase.md|2:ffff6666"])
        XCTAssertNil(row.insertion)
        XCTAssertNil(row.pendingBlockID)
        XCTAssertEqual(row.badgeText, "Completed tasks never block")
    }

    func testActionLines() throws {
        let index = try DependencyPickerIndex(candidates: workedExampleCandidates())
        let presentation = index.presentation(filter: "")
        let identified = try XCTUnwrap(presentation.rowsByID["sase.md|7:aaaa1111"])
        XCTAssertEqual(index.actionLine(for: identified), "↩ inserts &sase:deep-fix · space adds another &")
        let idLess = try XCTUnwrap(presentation.rowsByID["cash.md|1:dddd4444"])
        XCTAssertEqual(index.actionLine(for: idLess), "↩ adds ^call-bank, then inserts &cash:call-bank")
        let guarded = try XCTUnwrap(presentation.rowsByID["sase.md|2:ffff6666"])
        XCTAssertEqual(index.actionLine(for: guarded), "Completed tasks never block")
    }

    // MARK: - Filtered view

    func testFilterRanksTextFirst() throws {
        let presentation = try workedExamplePresentation(filter: "&budget")
        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertEqual(presentation.matchCount, 1)
        let row = try XCTUnwrap(presentation.rowsByID["cash.md|12:cccc3333"])
        XCTAssertFalse(row.textMatchRanges.isEmpty)
    }

    func testFilterMatchesLocator() throws {
        let presentation = try workedExamplePresentation(filter: "memo")
        XCTAssertEqual(presentation.matchCount, 1)
        XCTAssertNotNil(presentation.rowsByID["ref/chat/memo.md|20:eeee5555"])
    }

    func testFilterNoMatches() throws {
        let presentation = try workedExamplePresentation(filter: "zzz-no-such-task")
        XCTAssertEqual(presentation.matchCount, 0)
        XCTAssertNotNil(presentation.emptyState)
    }

    // MARK: - Owner header

    func testOwnerlessHeaderPromptsForDependent() {
        XCTAssertEqual(
            DependencyPickerIndex.headerTitle(owner: nil, dependentText: nil),
            "Choose a prerequisite"
        )
        XCTAssertEqual(
            DependencyPickerIndex.headerSubtitle(owner: nil, dependentText: nil),
            "Then add task text or @note+id"
        )
    }

    func testExistingOwnerHeader() {
        let owner = DependencyOwner(kind: "existing_task", route: "home", blockID: "groceries")
        XCTAssertEqual(
            DependencyPickerIndex.headerTitle(owner: owner, dependentText: nil),
            "For: @home+groceries"
        )
        XCTAssertNil(DependencyPickerIndex.headerSubtitle(owner: owner, dependentText: nil))
    }
}
