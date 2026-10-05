import XCTest

@testable import CaptureCore

/// Tests for the `!` Complete picker index, using a JSON sample shaped like
/// Bob's `task_complete` completion: Bob-order candidates across the
/// `today` / `in_progress` / `next` / `open` groups, per-Pomodoro today
/// entries, one ID-less row, one hidden row, one recurring row, and one
/// already-selected row.
///
/// Generating fixture: `bob capture-complete -f json -- '!'` against the
/// `complete_task_complete` CLI vault (`BOB_NOW=2026-09-30 09:02:00`,
/// `BOB_DAY_FILE` pinned) yields the same wire shape; the inline sample
/// below trims it to the worked example with an added `next`, `in_progress`,
/// hidden, and already-selected rows.
final class TaskCompletePickerPresentationTests: XCTestCase {
    private func workedExampleJSON() -> String {
        """
        [
          {
            "replacement": "!sase:deep-fix",
            "ref": "1:41d049f2",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "today",
            "hidden": false,
            "block_id": "deep-fix",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "*",
            "status_name": "Next",
            "status_type": "ON_HOLD",
            "text": "Fix deep bug",
            "section": null,
            "depth": 0,
            "line": 1,
            "today": {
              "role": "running",
              "pomodoro": {"line": 2, "name": "CAPTURE", "time_range": "0920-0950", "status": "running"},
              "sessions": 1
            }
          },
          {
            "replacement": "!cash:call-bank",
            "ref": "1:b2dfa8d1",
            "note_path": "cash.md",
            "locator": "cash",
            "group": "today",
            "hidden": false,
            "block_id": "call-bank",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": " ",
            "status_name": "Ready",
            "status_type": "TODO",
            "text": "Call the bank",
            "section": null,
            "depth": 0,
            "line": 1,
            "today": {
              "role": "running",
              "pomodoro": {"line": 2, "name": "CAPTURE", "time_range": "0920-0950", "status": "running"},
              "sessions": 2
            }
          },
          {
            "replacement": "!sase:outline",
            "ref": "2:4911df91",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "today",
            "hidden": false,
            "block_id": "outline",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "/",
            "status_name": "In Progress",
            "status_type": "IN_PROGRESS",
            "text": "Draft outline",
            "section": null,
            "depth": 0,
            "line": 2,
            "today": {
              "role": "worked",
              "pomodoro": {"line": 5, "name": "PLAN", "time_range": "0800-0830", "status": "completed"},
              "sessions": 1
            }
          },
          {
            "replacement": "!sase:queued-task",
            "ref": "9:99999999",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "today",
            "hidden": false,
            "block_id": "queued-task",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": " ",
            "status_name": "Ready",
            "status_type": "TODO",
            "text": "Queued task",
            "section": null,
            "depth": 0,
            "line": 9,
            "today": {
              "role": "queued",
              "pomodoro": {"line": 8, "name": "SASE", "time_range": null, "status": "queued"},
              "sessions": 1
            }
          },
          {
            "replacement": "!cash:noted",
            "ref": "3:aaaaaaaa",
            "note_path": "cash.md",
            "locator": "cash",
            "group": "today",
            "hidden": false,
            "block_id": "noted",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": " ",
            "status_name": "Ready",
            "status_type": "TODO",
            "text": "Noted task",
            "section": null,
            "depth": 0,
            "line": 3,
            "today": {"role": "noted", "sessions": 0}
          },
          {
            "replacement": "!sase:recovery-panel",
            "ref": "4:bbbbbbbb",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "in_progress",
            "hidden": false,
            "block_id": "recovery-panel",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "/",
            "status_name": "In Progress",
            "status_type": "IN_PROGRESS",
            "text": "Recovery panel",
            "section": null,
            "depth": 0,
            "line": 4
          },
          {
            "replacement": "!sase:next-up",
            "ref": "5:cccccccc",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "next",
            "hidden": false,
            "block_id": "next-up",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "*",
            "status_name": "Next",
            "status_type": "ON_HOLD",
            "text": "Next up",
            "section": null,
            "depth": 0,
            "line": 5
          },
          {
            "replacement": "",
            "ref": "6:dddddddd",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "open",
            "hidden": false,
            "block_id": null,
            "requires_block_id": true,
            "block_id_suggestions": ["no-id-yet"],
            "status_symbol": " ",
            "status_name": "Ready",
            "status_type": "TODO",
            "text": "No id yet",
            "section": null,
            "depth": 0,
            "line": 6
          },
          {
            "replacement": "!sase:bill",
            "ref": "7:eeeeeeee",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "open",
            "hidden": false,
            "block_id": "bill",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "?",
            "status_name": "Blocked",
            "status_type": "TODO",
            "text": "Blocked bill",
            "section": null,
            "depth": 0,
            "line": 7
          },
          {
            "replacement": "",
            "ref": "8:ffffffff",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "open",
            "hidden": false,
            "block_id": "water",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "recurring": true,
            "disabled_reason": "Recurring — complete it in Obsidian so Tasks writes the next occurrence",
            "status_symbol": " ",
            "status_name": "Ready",
            "status_type": "TODO",
            "text": "Water plants",
            "section": null,
            "depth": 0,
            "line": 8
          },
          {
            "replacement": "",
            "ref": "10:eeee0000",
            "note_path": "sase.md",
            "locator": "sase",
            "group": "open",
            "hidden": false,
            "block_id": "already-picked",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "already_selected": true,
            "disabled_reason": "Already in this draft",
            "status_symbol": "*",
            "status_name": "Next",
            "status_type": "ON_HOLD",
            "text": "Already picked task",
            "section": null,
            "depth": 0,
            "line": 10
          },
          {
            "replacement": "!ref/chat/memo:ref",
            "ref": "20:11111111",
            "note_path": "ref/chat/memo.md",
            "locator": "ref/chat/memo",
            "group": "open",
            "hidden": true,
            "block_id": "ref",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": " ",
            "status_name": "Ready",
            "status_type": "TODO",
            "text": "Read the memo",
            "section": null,
            "depth": 0,
            "line": 20
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
        try TaskCompletePickerIndex(candidates: workedExampleCandidates()).presentation(filter: filter)
    }

    // MARK: - Decoding

    func testDecodingReadsTaskCompleteFields() throws {
        let candidates = try workedExampleCandidates()
        let first = try XCTUnwrap(candidates.first)
        XCTAssertEqual(first.replacement, "!sase:deep-fix")
        XCTAssertEqual(first.notePath, "sase.md")
        XCTAssertEqual(first.locator, "sase")
        XCTAssertEqual(first.group, "today")
        XCTAssertFalse(first.hidden)
        XCTAssertFalse(first.recurring)
        XCTAssertFalse(first.alreadySelected)
        XCTAssertNil(first.disabledReason)
        XCTAssertEqual(first.today?.role, "running")
        XCTAssertEqual(first.today?.pomodoro?.name, "CAPTURE")
        XCTAssertEqual(first.today?.sessions, 1)

        let sessions = candidates[1]
        XCTAssertEqual(sessions.today?.sessions, 2)

        let idLess = candidates[7]
        XCTAssertTrue(idLess.requiresBlockID)
        XCTAssertEqual(idLess.blockIDSuggestions, ["no-id-yet"])

        let recurring = candidates[9]
        XCTAssertTrue(recurring.recurring)
        XCTAssertEqual(recurring.disabledReason, "Recurring — complete it in Obsidian so Tasks writes the next occurrence")

        let selected = candidates[10]
        XCTAssertTrue(selected.alreadySelected)
        XCTAssertEqual(selected.disabledReason, "Already in this draft")

        let hidden = candidates[11]
        XCTAssertTrue(hidden.hidden)
    }

    func testDecodingDefaultsWhenKeysAbsent() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement": "!sase:x", "note_path": "sase.md", "locator": "sase", "ref": "1:abc"}
            """.utf8)
        )
        XCTAssertFalse(candidate.recurring)
        XCTAssertFalse(candidate.alreadySelected)
        XCTAssertNil(candidate.today)
        XCTAssertFalse(candidate.hidden)
    }

    func testUnknownGroupOrRoleDegradesToNoteSections() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement": "!sase:x", "note_path": "sase.md", "locator": "sase", "ref": "1:abc",
             "group": "future", "today": {"role": "someday", "sessions": 0},
             "block_id": "x", "status_symbol": " ", "status_name": "Ready", "text": "X"}
            """.utf8)
        )
        let presentation = TaskCompletePickerIndex(candidates: [candidate]).presentation(filter: "")
        XCTAssertEqual(presentation.sections.map { $0.title }, ["sase.md"])
    }

    func testTaskCompleteContextRawValue() {
        XCTAssertEqual(CaptureCompletionContext(rawContext: "task_complete"), .taskComplete)
        XCTAssertNil(CaptureCompletionContext(rawContext: "task_complet"))
    }

    func testTaskCompleteInlineRowReadsAsComplete() throws {
        let candidates = try workedExampleCandidates()
        let content = completionRowContent(
            for: candidates[0],
            context: "task_complete",
            query: ""
        )
        XCTAssertEqual(content.contextLabel, "Complete")
        XCTAssertEqual(content.primaryText, "Fix deep bug")
        XCTAssertEqual(content.secondaryText, "sase:deep-fix")
    }

    func testTaskCompleteDescriptorAndSource() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data("""
            {
              "ok": true, "schema_version": 1, "cursor": 1,
              "replacement": {"start": 0, "end": 1},
              "context": "task_complete", "candidates": [],
              "query": "", "picker": {
                "kind": "task_complete", "scope": "vault", "scope_token": "!",
                "marker_range": {"start": 0, "end": 1},
                "trigger_removal_range": {"start": 0, "end": 1},
                "action_continuation_keys": ["!", "["]
              }
            }
            """.utf8)
        )
        XCTAssertTrue(response.picker?.isTaskComplete ?? false)
        XCTAssertEqual(response.picker?.actionContinuationKeys, ["!", "["])
        let source = CapturePickerSource.taskComplete
        XCTAssertEqual(source.triggerByte, 33)
        XCTAssertEqual(source.scopeSymbolText, "!")
        XCTAssertEqual(source.scopeCaption, "Complete")
        XCTAssertEqual(source.chipLabel, "Pick a task to complete")
        XCTAssertEqual(source.pickerUsedDefaultsKey, "org.bobs.bob-mac-capture.task-complete-picker-used")
        XCTAssertEqual(CapturePickerNeed.taskComplete.statusText, "Pick a task to complete — press Tab to browse")
    }

    func testCompleteReplacementDecodes() throws {
        let response = try JSONDecoder().decode(
            CaptureTaskIDResponse.self,
            from: Data("""
            {
              "ok": true, "schema_version": 1, "dry_run": true,
              "relative_target": "sase.md", "note_path": "sase.md",
              "block_id": "no-id-yet", "complete_replacement": "!sase:no-id-yet",
              "line": 3, "ref": "3:abc",
              "task": {"ref": "3:abc", "line": 3, "block_id": "no-id-yet",
                "status_symbol": " ", "status_name": "Ready", "status_type": "TODO",
                "text": "No id yet", "depth": 0, "child_count": 0}
            }
            """.utf8)
        )
        guard case .success(let success) = response else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(success.completeReplacement, "!sase:no-id-yet")
    }

    // MARK: - Grouped view

    func testGroupedSectionsFollowBobOrder() throws {
        let presentation = try workedExamplePresentation()
        XCTAssertEqual(presentation.mode, .grouped)
        let titles = presentation.sections.map { $0.title }
        XCTAssertEqual(titles, [
            "CAPTURE",
            "🍅 PLAN",
            "UP NEXT SASE",
            "In today's note",
            "In Progress",
            "Next",
            "sase.md",
            "ref/chat/memo.md",
        ])
        let running = try XCTUnwrap(presentation.sections.first)
        XCTAssertTrue(running.isCurrent)
        XCTAssertEqual(running.timeRangeText, "09:20–09:50")
    }

    func testMostRecentWorkedFirstAndSessionsCapsule() throws {
        let presentation = try workedExamplePresentation()
        let cashToday = try XCTUnwrap(presentation.sections.first { $0.title == "CAPTURE" })
        XCTAssertEqual(cashToday.rows.count, 2)
        let sessionsRow = try XCTUnwrap(presentation.rowsByID["cash.md|1:b2dfa8d1"])
        XCTAssertEqual(sessionsRow.badgeText, "🍅 2")
    }

    func testDisabledRowsShowReasonBadge() throws {
        let presentation = try workedExamplePresentation()
        let recurring = try XCTUnwrap(presentation.rowsByID["sase.md|8:ffffffff"])
        XCTAssertNil(recurring.insertion)
        XCTAssertNil(recurring.pendingBlockID)
        XCTAssertEqual(recurring.badgeText, "Recurring — complete it in Obsidian so Tasks writes the next occurrence")
        XCTAssertFalse(recurring.isSelectable)
        let selected = try XCTUnwrap(presentation.rowsByID["sase.md|10:eeee0000"])
        XCTAssertNil(selected.insertion)
        XCTAssertEqual(selected.badgeText, "Already in this draft")
    }

    func testIDLessRowsUsePendingBlockID() throws {
        let presentation = try workedExamplePresentation()
        let row = try XCTUnwrap(presentation.rowsByID["sase.md|6:dddddddd"])
        XCTAssertNil(row.insertion)
        let pending = try XCTUnwrap(row.pendingBlockID)
        XCTAssertEqual(pending.route, "sase.md")
        XCTAssertEqual(pending.suggestions, ["no-id-yet"])
    }

    func testRowsKeyedByNotePathAndRef() throws {
        let presentation = try workedExamplePresentation()
        XCTAssertNotNil(presentation.rowsByID["sase.md|1:41d049f2"])
        XCTAssertNotNil(presentation.rowsByID["cash.md|1:b2dfa8d1"])
    }

    func testActionLines() throws {
        let index = try TaskCompletePickerIndex(candidates: workedExampleCandidates())
        let presentation = index.presentation(filter: "")
        let identified = try XCTUnwrap(presentation.rowsByID["sase.md|1:41d049f2"])
        XCTAssertTrue(index.actionLine(for: identified).contains("!sase:deep-fix"))
        XCTAssertTrue(index.actionLine(for: identified).contains("[*]"))
        let blocked = try XCTUnwrap(presentation.rowsByID["sase.md|7:eeeeeeee"])
        XCTAssertTrue(index.actionLine(for: blocked).contains("[?]"))
        let idLess = try XCTUnwrap(presentation.rowsByID["sase.md|6:dddddddd"])
        XCTAssertEqual(index.actionLine(for: idLess), "↩ adds ^no-id-yet, then inserts !sase:no-id-yet")
        let guarded = try XCTUnwrap(presentation.rowsByID["sase.md|8:ffffffff"])
        XCTAssertEqual(index.actionLine(for: guarded), "Recurring — complete it in Obsidian so Tasks writes the next occurrence")
    }

    // MARK: - Filtered view

    func testFilteredTodayAndAllSplit() throws {
        let presentation = try workedExamplePresentation(filter: "sase")
        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertEqual(presentation.sections.map { $0.title }, ["Today", "All open tasks"])
        XCTAssertTrue(presentation.sections.allSatisfy { $0.kind == .taskCompleteFiltered })
        XCTAssertTrue(presentation.rowsByID["sase.md|1:41d049f2"] != nil)
    }

    func testCompletedPomodoroSectionsCarryDoneCapsule() throws {
        let presentation = try workedExamplePresentation()
        let worked = try XCTUnwrap(presentation.sections.first { $0.title == "🍅 PLAN" })
        XCTAssertTrue(worked.showsDoneCapsule)
        let running = try XCTUnwrap(presentation.sections.first { $0.title == "CAPTURE" })
        XCTAssertFalse(running.showsDoneCapsule)
        XCTAssertTrue(running.isCurrent)
        let queued = try XCTUnwrap(presentation.sections.first { $0.title == "UP NEXT SASE" })
        XCTAssertFalse(queued.showsDoneCapsule)
    }

    func testTwoWorkedPomodorosStayMostRecentFirst() throws {
        let first = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement": "!sase:newer", "ref": "1:aa01", "note_path": "sase.md",
             "locator": "sase", "group": "today", "block_id": "newer",
             "status_symbol": " ", "status_name": "Ready", "text": "Newer",
             "today": {"role": "worked",
              "pomodoro": {"line": 9, "name": "EVENING", "time_range": "1800-1830", "status": "completed"},
              "sessions": 0}}
            """.utf8)
        )
        let second = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement": "!sase:older", "ref": "1:aa02", "note_path": "sase.md",
             "locator": "sase", "group": "today", "block_id": "older",
             "status_symbol": " ", "status_name": "Ready", "text": "Older",
             "today": {"role": "worked",
              "pomodoro": {"line": 5, "name": "PLAN", "time_range": "0800-0830", "status": "completed"},
              "sessions": 0}}
            """.utf8)
        )
        let presentation = TaskCompletePickerIndex(candidates: [first, second]).presentation(filter: "")
        let titles = presentation.sections.map { $0.title }
        XCTAssertEqual(titles, ["🍅 EVENING", "🍅 PLAN"])
        XCTAssertTrue(presentation.sections.allSatisfy { $0.showsDoneCapsule })
        XCTAssertEqual(presentation.sections.map { $0.timeRangeText }, ["18:00–18:30", "08:00–08:30"])
    }

    func testFilterNoMatches() throws {
        let presentation = try workedExamplePresentation(filter: "zzz-no-such-task")
        XCTAssertEqual(presentation.matchCount, 0)
        XCTAssertNotNil(presentation.emptyState)
    }
}
