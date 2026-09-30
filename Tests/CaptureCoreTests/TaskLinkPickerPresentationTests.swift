import XCTest

@testable import CaptureCore

/// Tests for the `:` task-link picker index, using a JSON sample shaped like
/// the plan's worked example: one queued, one In Progress, one `#now`, and
/// five note rows (four ID-less).
final class TaskLinkPickerPresentationTests: XCTestCase {
    /// The eight worked-example candidates in Bob's canonical order.
    private func workedExampleJSON() -> String {
        """
        [
          {
            "replacement": "@sase:deep-fix",
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
            "pomodoro": {"line": 5, "name": "BUGS", "time_range": null, "is_current": false},
            "now": false
          },
          {
            "replacement": "@sase:outline",
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
            "group": "in_progress",
            "now": false
          },
          {
            "replacement": "@sase:blog",
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
            "group": "now",
            "now": true
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
            "group": "note",
            "now": false
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
            "scheduled": "2026-10-03",
            "pulls_forward": true,
            "now": false
          },
          {
            "replacement": "@bob:polish",
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
            "group": "note",
            "now": false
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
            "group": "note",
            "now": false
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
            "group": "note",
            "now": false
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
        try TaskLinkPickerIndex(candidates: workedExampleCandidates()).presentation(filter: filter)
    }

    // MARK: - Decoding

    func testDecodingReadsNewFields() throws {
        let candidates = try workedExampleCandidates()
        let queued = try XCTUnwrap(candidates.first)
        XCTAssertEqual(queued.replacement, "@sase:deep-fix")
        XCTAssertEqual(queued.taskRef, "7:aaaa1111")
        XCTAssertEqual(queued.noteKind, "project")
        XCTAssertEqual(queued.blockIDSuggestions, [])
        XCTAssertEqual(queued.group, "queued")
        XCTAssertNil(queued.scheduled)
        XCTAssertFalse(queued.pullsForward)

        let dentist = candidates[4]
        XCTAssertEqual(dentist.noteKind, "area")
        XCTAssertEqual(dentist.blockIDSuggestions, ["book-dentist"])
        XCTAssertEqual(dentist.scheduled, "2026-10-03")
        XCTAssertTrue(dentist.pullsForward)
        XCTAssertTrue(dentist.requiresBlockID)
    }

    func testDecodingDefaultsWhenKeysAbsent() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement": "@sase:deep-fix", "route": "sase", "block_id": "deep-fix"}
            """.utf8)
        )
        XCTAssertNil(candidate.noteKind)
        XCTAssertEqual(candidate.blockIDSuggestions, [])
        XCTAssertNil(candidate.group)
        XCTAssertNil(candidate.scheduled)
        XCTAssertFalse(candidate.pullsForward)
    }

    func testTaskLinkContextRawValue() {
        XCTAssertEqual(CaptureCompletionContext(rawContext: "task_link"), .taskLink)
        XCTAssertNil(CaptureCompletionContext(rawContext: "task_linnk"))
    }

    func testTaskLinkInlineRowReadsAsTask() throws {
        let candidates = try workedExampleCandidates()
        let content = completionRowContent(
            for: candidates[0],
            context: "task_link",
            query: ""
        )
        XCTAssertEqual(content.contextLabel, "Task")
        XCTAssertEqual(content.primaryText, "Fix deep bug")
        XCTAssertEqual(content.secondaryText, "sase:deep-fix · Bugs")
    }

    // MARK: - Grouped view

    func testGroupedSectionOrderTitlesAndSubtitles() throws {
        let presentation = try workedExamplePresentation()
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.countText, "8 tasks")
        XCTAssertEqual(
            presentation.sections.map(\.id),
            ["pomodoro-5", "unqueued-in-progress", "now", "note-mac_inbox", "note-health", "note-bob", "note-sase"]
        )
        XCTAssertEqual(
            presentation.sections.map(\.kind),
            [.pomodoro, .unqueuedInProgress, .now, .note, .note, .note, .note]
        )
        XCTAssertEqual(
            presentation.sections.map(\.title),
            ["BUGS", "In Progress", "This Week's Bets", "mac_inbox.md", "health.md", "bob.md", "sase.md"]
        )
        XCTAssertEqual(
            presentation.sections.map(\.subtitle),
            [nil, nil, nil, "Inbox", "Area", "Project", "Project"]
        )
        let queued = try XCTUnwrap(presentation.sections.first)
        XCTAssertEqual(queued.ordinal, 1)
        XCTAssertFalse(queued.isCurrent)
    }

    func testGroupedRowsFollowBobOrderWithRouteRefKeys() throws {
        let presentation = try workedExamplePresentation()
        XCTAssertEqual(
            presentation.orderedRowIDs,
            [
                "sase|7:aaaa1111",
                "sase|11:bbbb2222",
                "sase|12:cccc3333",
                "mac_inbox|1:dddd4444",
                "health|3:eeee5555",
                "bob|2:ffff6666",
                "bob|3:gggg7777",
                "sase|9:hhhh8888",
            ]
        )
    }

    func testGroupedVisibleRowBudgetClamps() throws {
        let presentation = try workedExamplePresentation()
        // 8 rows + 7 headers, clamped to 11.
        XCTAssertEqual(presentation.visibleRowBudget, 11)

        let empty = TaskLinkPickerIndex(candidates: []).presentation(filter: "")
        XCTAssertEqual(empty.visibleRowBudget, 4)
        XCTAssertEqual(empty.countText, "0 tasks")
        XCTAssertEqual(empty.emptyState?.title, "No open tasks")
        XCTAssertEqual(empty.emptyState?.message, "No open tasks in your area or project notes.")
    }

    func testFourIDLessRowsStayDistinct() throws {
        let presentation = try workedExamplePresentation()
        let pending = presentation.orderedRowIDs.compactMap { presentation.rowsByID[$0]?.pendingBlockID }
        XCTAssertEqual(pending.count, 4)
        XCTAssertEqual(
            pending.map(\.route),
            ["mac_inbox", "health", "bob", "sase"]
        )
        let rows = try presentation.orderedRowIDs.map { try XCTUnwrap(presentation.rowsByID[$0]) }
        for row in rows where row.pendingBlockID != nil {
            XCTAssertNil(row.insertion)
            XCTAssertTrue(row.isSelectable)
        }
        let identified = try XCTUnwrap(presentation.rowsByID["sase|7:aaaa1111"])
        XCTAssertEqual(identified.insertion, "@sase:deep-fix")
        XCTAssertNil(identified.pendingBlockID)
    }

    func testIDLessLocatorShowsRoutePlusFirstSuggestion() throws {
        let presentation = try workedExamplePresentation()
        let flaky = try XCTUnwrap(presentation.rowsByID["sase|9:hhhh8888"])
        XCTAssertEqual(flaky.route, "sase")
        XCTAssertEqual(flaky.blockID, "fix-flaky-gkeep")
        XCTAssertEqual(flaky.pendingBlockID?.suggestions, ["fix-flaky-gkeep", "flaky-gkeep-test"])
        XCTAssertEqual(flaky.pendingBlockID?.taskRef, "9:hhhh8888")
    }

    func testDepthOnlyInNoteSections() throws {
        let presentation = try workedExamplePresentation()
        let nested = try XCTUnwrap(presentation.rowsByID["bob|3:gggg7777"])
        XCTAssertEqual(nested.depth, 1)
        let sibling = try XCTUnwrap(presentation.rowsByID["bob|2:ffff6666"])
        XCTAssertEqual(sibling.depth, 0)
        let queued = try XCTUnwrap(presentation.rowsByID["sase|7:aaaa1111"])
        XCTAssertEqual(queued.depth, 0)

        let filtered = try workedExamplePresentation(filter: "bob")
        for id in filtered.orderedRowIDs {
            XCTAssertEqual(try XCTUnwrap(filtered.rowsByID[id]).depth, 0)
        }
    }

    func testNowBadgeAndPomodoroSummary() throws {
        let presentation = try workedExamplePresentation()
        let bet = try XCTUnwrap(presentation.rowsByID["sase|12:cccc3333"])
        XCTAssertEqual(bet.badgeText, "NOW")
        let queued = try XCTUnwrap(presentation.rowsByID["sase|7:aaaa1111"])
        XCTAssertNil(queued.badgeText)
        XCTAssertEqual(queued.detail.summary, "Queued in BUGS (#1)")
        XCTAssertEqual(queued.detail.insertionPrefix, "@")
        XCTAssertEqual(queued.detail.statusText, "Next")
        let inbox = try XCTUnwrap(presentation.rowsByID["mac_inbox|1:dddd4444"])
        XCTAssertEqual(inbox.detail.summary, "Not in a Pomodoro")
    }

    func testGroupedRowsOmitPomodoroChip() throws {
        let presentation = try workedExamplePresentation()
        for id in presentation.orderedRowIDs {
            XCTAssertNil(try XCTUnwrap(presentation.rowsByID[id]).chipText)
        }
    }

    func testGroupPrecedenceSurvivesShuffledInput() throws {
        var candidates = try workedExampleCandidates()
        candidates.reverse()
        let presentation = TaskLinkPickerIndex(candidates: candidates).presentation(filter: "")
        XCTAssertEqual(
            presentation.sections.map(\.id),
            ["pomodoro-5", "unqueued-in-progress", "now", "note-sase", "note-bob", "note-health", "note-mac_inbox"]
        )
    }

    func testMissingOrUnknownGroupFallsBackToNote() throws {
        let candidates = try workedExampleCandidates()
        // Re-decode the queued row with an unknown group: it lands in its
        // note section instead of vanishing.
        let regrouped = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement": "@sase:deep-fix", "ref": "7:aaaa1111", "route": "sase",
             "note_kind": "project", "block_id": "deep-fix", "text": "Fix deep bug",
             "status_symbol": "*", "status_name": "Next", "group": "later"}
            """.utf8)
        )
        var mixed = candidates
        mixed[0] = regrouped
        XCTAssertEqual(mixed[0].group, "later")
        let presentation = TaskLinkPickerIndex(candidates: mixed).presentation(filter: "")
        XCTAssertFalse(presentation.sections.map(\.id).contains("pomodoro-5"))
        let note = try XCTUnwrap(presentation.sections.first { $0.id == "note-sase" })
        XCTAssertTrue(note.rows.map(\.id).contains("sase|7:aaaa1111"))
    }

    func testDuplicateRouteRefDedupes() throws {
        var candidates = try workedExampleCandidates()
        candidates.append(candidates[0])
        let presentation = TaskLinkPickerIndex(candidates: candidates).presentation(filter: "")
        XCTAssertEqual(presentation.totalCount, 8)
        XCTAssertEqual(presentation.orderedRowIDs.count, 8)
    }

    // MARK: - Filtered view

    func testFilteredRankingSaseDeep() throws {
        let presentation = try workedExamplePresentation(filter: "sase deep")
        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertEqual(presentation.countText, "1 of 8")
        XCTAssertEqual(presentation.orderedRowIDs, ["sase|7:aaaa1111"])
    }

    func testFilteredRankingFlaky() throws {
        let presentation = try workedExamplePresentation(filter: "flaky")
        XCTAssertEqual(presentation.orderedRowIDs, ["sase|9:hhhh8888"])
    }

    func testFilteredRankingSubsequence() throws {
        let presentation = try workedExamplePresentation(filter: "dntst")
        XCTAssertEqual(presentation.orderedRowIDs, ["health|3:eeee5555"])
    }

    func testFilteredRankingMultiTokenAND() throws {
        let presentation = try workedExamplePresentation(filter: "sase out")
        XCTAssertEqual(presentation.orderedRowIDs, ["sase|11:bbbb2222"])
    }

    func testFilteredHighlightsCoverTextRouteAndBlockID() throws {
        let presentation = try workedExamplePresentation(filter: "sase deep")
        let row = try XCTUnwrap(presentation.rowsByID["sase|7:aaaa1111"])
        // "deep" inside "Fix deep bug".
        XCTAssertTrue(row.textMatchRanges.contains(4..<8))
        XCTAssertFalse(row.routeMatchRanges.isEmpty)
        // Filtered rows show a Pomodoro chip only when queued.
        XCTAssertEqual(row.chipText, "BUGS")
        XCTAssertEqual(row.depth, 0)
    }

    func testFilteredChipOnlyWhenQueued() throws {
        let presentation = try workedExamplePresentation(filter: "sase")
        XCTAssertFalse(presentation.orderedRowIDs.isEmpty)
        let queued = try XCTUnwrap(presentation.rowsByID["sase|7:aaaa1111"])
        XCTAssertEqual(queued.chipText, "BUGS")
        let note = try XCTUnwrap(presentation.rowsByID["sase|9:hhhh8888"])
        XCTAssertNil(note.chipText)
    }

    func testFilteredTiesKeepBobOrder() throws {
        // Every "sase" route row matches the route field alone at the same
        // weight, so ties fall back to Bob order.
        let presentation = try workedExamplePresentation(filter: "sase")
        XCTAssertEqual(
            presentation.orderedRowIDs,
            ["sase|7:aaaa1111", "sase|11:bbbb2222", "sase|12:cccc3333", "sase|9:hhhh8888"]
        )
    }

    func testNoMatchesEmptyState() throws {
        let presentation = try workedExamplePresentation(filter: "zzz-no-such-task")
        XCTAssertEqual(presentation.orderedRowIDs, [])
        XCTAssertEqual(presentation.countText, "0 of 8")
        XCTAssertEqual(presentation.emptyState?.title, "No matches")
    }

    func testNoMatchesEmptyStateUsesOpenTasks() throws {
        let presentation = try workedExamplePresentation(filter: "zzz-no-such-task")
        XCTAssertEqual(
            presentation.emptyState?.message,
            "No open tasks match “zzz-no-such-task” — Esc clears the filter."
        )
    }

    // MARK: - Queries

    func testSeedQueryWithLeadingColon() throws {
        let seeded = try workedExamplePresentation(filter: ":dee")
        let bare = try workedExamplePresentation(filter: "dee")
        XCTAssertEqual(seeded.orderedRowIDs, bare.orderedRowIDs)
        XCTAssertEqual(seeded.orderedRowIDs, ["sase|7:aaaa1111"])
    }

    func testBareColonShowsGroupedView() throws {
        let presentation = try workedExamplePresentation(filter: ":")
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.orderedRowIDs.count, 8)
    }

    func testFuzzyQuerySigils() {
        // The default still strips `^`, leaving `:` alone.
        XCTAssertEqual(FuzzyQuery("^dee").tokens, ["dee"])
        XCTAssertEqual(FuzzyQuery(":dee").tokens, [":dee"])
        // The task-link index strips `:` instead.
        XCTAssertEqual(FuzzyQuery(":dee", leadingSigil: ":").tokens, ["dee"])
        XCTAssertEqual(FuzzyQuery(":sase out", leadingSigil: ":").tokens, ["sase", "out"])
        XCTAssertTrue(FuzzyQuery(":", leadingSigil: ":").isEmpty)
        XCTAssertEqual(FuzzyQuery("^dee", leadingSigil: ":").tokens, ["^dee"])
    }

    // MARK: - Schedule

    func testScheduledTextFormatting() {
        XCTAssertEqual(TaskLinkPickerIndex.formattedScheduledDate("2026-10-03", currentYear: 2026), "Oct 3")
        XCTAssertEqual(TaskLinkPickerIndex.formattedScheduledDate("2027-01-09", currentYear: 2026), "Jan 9, 2027")
        XCTAssertEqual(TaskLinkPickerIndex.formattedScheduledDate("not-a-date", currentYear: 2026), "not-a-date")
    }

    func testScheduledTextAndPullForward() throws {
        let index = TaskLinkPickerIndex(candidates: try workedExampleCandidates())
        let presentation = index.presentation(filter: "")
        let dentist = try XCTUnwrap(presentation.rowsByID["health|3:eeee5555"])
        // Pinned against the same formatter so the row stays correct outside
        // the sample's calendar year; exact shapes are pinned below.
        let rendered = TaskLinkPickerIndex.formattedScheduledDate("2026-10-03")
        XCTAssertEqual(dentist.scheduledText, rendered)
        XCTAssertTrue(dentist.pullsForward)
        XCTAssertEqual(
            index.pullForwardLine(for: dentist),
            "Scheduled \(rendered) — linking pulls it forward"
        )
        let queued = try XCTUnwrap(presentation.rowsByID["sase|7:aaaa1111"])
        XCTAssertNil(queued.scheduledText)
        XCTAssertFalse(queued.pullsForward)
        XCTAssertNil(index.pullForwardLine(for: queued))
    }

    // MARK: - Detail lines

    func testIdentifiedActionLine() throws {
        let index = TaskLinkPickerIndex(candidates: try workedExampleCandidates())
        let presentation = index.presentation(filter: "")
        let row = try XCTUnwrap(presentation.rowsByID["sase|7:aaaa1111"])
        XCTAssertEqual(
            index.actionLine(for: row),
            "↩ inserts @sase:deep-fix · ⇧↩ adds = to start it"
        )
    }

    func testIDLessActionLine() throws {
        let index = TaskLinkPickerIndex(candidates: try workedExampleCandidates())
        let presentation = index.presentation(filter: "")
        let row = try XCTUnwrap(presentation.rowsByID["sase|9:hhhh8888"])
        XCTAssertEqual(
            index.actionLine(for: row),
            "↩ adds ^fix-flaky-gkeep to sase.md, then inserts @sase:fix-flaky-gkeep"
        )
    }

    func testIDLessActionLineWithoutSuggestions() throws {
        let candidate = try JSONDecoder().decode(
            CaptureCompletionCandidate.self,
            from: Data("""
            {"replacement": "", "ref": "1:zzzz9999", "route": "sase",
             "block_id": null, "requires_block_id": true,
             "block_id_suggestions": [], "text": "Nameless chore",
             "status_symbol": " ", "status_name": "Todo", "group": "note"}
            """.utf8)
        )
        let index = TaskLinkPickerIndex(candidates: [candidate])
        let presentation = index.presentation(filter: "")
        let row = try XCTUnwrap(presentation.rowsByID["sase|1:zzzz9999"])
        XCTAssertNil(row.blockID)
        XCTAssertEqual(index.actionLine(for: row), "↩ names this task, then inserts its link")
    }

    // MARK: - Source and need

    func testTaskLinkSourceStrings() {
        let source = CapturePickerSource.taskLink
        XCTAssertEqual(source.triggerByte, 58)
        XCTAssertEqual(source.filterPlaceholder, "Search tasks by text, note, or ^id")
        XCTAssertEqual(source.filterAccessibilityLabel, "Search open tasks")
        XCTAssertEqual(source.scopeSymbolText, ":")
        XCTAssertEqual(source.scopeCaption, "Open Tasks")
        XCTAssertEqual(source.chipLabel, "Browse open tasks")
        XCTAssertEqual(source.chipIcon, "magnifyingglass")
        XCTAssertEqual(source.chipHelp, "Reopen the Task Link Picker for the : item (Tab).")
        XCTAssertEqual(source.chipAccessibilityLabel, "Browse open tasks")
        XCTAssertEqual(source.cardAccessibilityLabel, "Task link picker")
        XCTAssertEqual(
            source.cardAccessibilityHint,
            "Arrow keys move, Return inserts the task link, Shift-Return inserts it and starts its session, Escape cancels."
        )
        XCTAssertEqual(source.appearedAnnouncementPrefix, "Open tasks")
        XCTAssertEqual(source.pickerUsedDefaultsKey, "org.bobs.bob-mac-capture.task-link-picker-used")
    }

    func testTaskLinkKeyHints() {
        XCTAssertEqual(
            CapturePickerSource.taskLink.keyHintItems().map(\.keys),
            ["↑↓", "↩", "⇧↩", "⌘↩", "esc"]
        )
        XCTAssertEqual(
            CapturePickerSource.taskLink.keyHintItems().map(\.action),
            ["Move", "Link", "Link & Start", "Link & Capture", "Clear / Cancel"]
        )
        XCTAssertEqual(
            CapturePickerSource.taskLink.keyHintsAccessibilityLabel,
            "Picker keys: up and down to move, Return to link, Shift Return to link and start, Command Return to link and capture, Escape to clear or cancel."
        )
    }

    func testTaskLinkNeedStatus() {
        XCTAssertEqual(
            CapturePickerNeed.taskLink.statusText,
            "Pick any open task — press Tab to browse"
        )
    }
}
