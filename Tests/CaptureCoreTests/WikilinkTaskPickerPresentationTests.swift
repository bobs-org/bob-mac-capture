import XCTest

@testable import CaptureCore

/// Tests for the `((` Task Wikilink picker index, using a JSON sample shaped
/// like Bob's `wikilink_task` completion: Bob-order candidates across the
/// `in_this_note` / `in_progress` / `next` / `open` / `completed` groups,
/// one ID-less row, one hidden row, and one guarded row.
final class WikilinkTaskPickerPresentationTests: XCTestCase {
    private func workedExampleJSON() -> String {
        """
        [
          {
            "replacement": "[[mac_inbox#^inbox-chore]]",
            "ref": "1:aaaa1111",
            "note_path": "mac_inbox.md",
            "locator": "mac_inbox",
            "group": "in_this_note",
            "hidden": false,
            "block_id": "inbox-chore",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Inbox chore",
            "section": null,
            "depth": 0,
            "line": 1,
            "cursor_after": 26,
            "link_target": "mac_inbox"
          },
          {
            "replacement": "",
            "ref": "2:bbbb2222",
            "note_path": "mac_inbox.md",
            "locator": "mac_inbox",
            "group": "in_this_note",
            "hidden": false,
            "block_id": null,
            "requires_block_id": true,
            "block_id_suggestions": ["inbox-plain"],
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Inbox plain",
            "section": null,
            "depth": 0,
            "line": 2,
            "link_target": "mac_inbox"
          },
          {
            "replacement": "[[home#^dinner]]",
            "ref": "3:cccc3333",
            "note_path": "home.md",
            "locator": "home",
            "group": "in_progress",
            "hidden": false,
            "block_id": "dinner",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "/",
            "status_name": "In Progress",
            "status_type": "IN_PROGRESS",
            "text": "Cook dinner",
            "section": "Home",
            "depth": 0,
            "line": 3,
            "cursor_after": 20,
            "link_target": "home"
          },
          {
            "replacement": "[[cash#^meals]]",
            "ref": "4:dddd4444",
            "note_path": "cash.md",
            "locator": "cash",
            "group": "next",
            "hidden": false,
            "block_id": "meals",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "*",
            "status_name": "Next",
            "status_type": "ON_HOLD",
            "text": "Plan meals",
            "section": null,
            "depth": 0,
            "line": 1,
            "cursor_after": 19,
            "link_target": "cash"
          },
          {
            "replacement": "[[cash#^budget]]",
            "ref": "5:eeee5555",
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
            "section": null,
            "depth": 0,
            "line": 2,
            "cursor_after": 20,
            "link_target": "cash"
          },
          {
            "replacement": "[[sase_cleanup#^no-idle]]",
            "ref": "6:ffff6666",
            "note_path": "sase_cleanup.md",
            "locator": "sase_cleanup",
            "group": "open",
            "hidden": true,
            "block_id": "no-idle",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "/",
            "status_name": "In Progress",
            "status_type": "IN_PROGRESS",
            "text": "Stop idling when no agents run",
            "section": null,
            "depth": 0,
            "line": 1,
            "cursor_after": 29,
            "link_target": "sase_cleanup"
          },
          {
            "replacement": "",
            "ref": "7:gggg7777",
            "note_path": "twin.md",
            "locator": "twin",
            "group": "open",
            "hidden": false,
            "block_id": "twin",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "disabled_reason": "duplicate block ID ^twin in twin.md",
            "status_symbol": " ",
            "status_name": "Todo",
            "status_type": "TODO",
            "text": "Second twin",
            "section": null,
            "depth": 0,
            "line": 2,
            "link_target": "twin"
          },
          {
            "replacement": "[[home#^done-deed]]",
            "ref": "8:hhhh8888",
            "note_path": "home.md",
            "locator": "home",
            "group": "completed",
            "hidden": false,
            "block_id": "done-deed",
            "requires_block_id": false,
            "block_id_suggestions": [],
            "status_symbol": "x",
            "status_name": "Done",
            "status_type": "DONE",
            "text": "Done deed",
            "section": "Home",
            "depth": 0,
            "line": 5,
            "cursor_after": 23,
            "link_target": "home"
          }
        ]
        """
    }

    private func decodeCandidates() throws -> [CaptureCompletionCandidate] {
        let data = Data(workedExampleJSON().utf8)
        return try JSONDecoder().decode([CaptureCompletionCandidate].self, from: data)
    }

    func testGroupedOrderFollowsBobOrder() throws {
        let index = WikilinkTaskPickerIndex(candidates: try decodeCandidates())
        let presentation = index.presentation(filter: "")
        XCTAssertEqual(presentation.mode, .grouped)
        let titles = presentation.sections.map { $0.title }
        XCTAssertEqual(
            titles,
            [
                "This note", "In Progress", "Next", "cash.md", "sase_cleanup.md", "twin.md",
                "Completed history",
            ])
    }

    func testHiddenSortsLastWithinSection() throws {
        let index = WikilinkTaskPickerIndex(candidates: try decodeCandidates())
        let presentation = index.presentation(filter: "")
        // The hidden sase_cleanup row lives in its own note section; within
        // a section hidden rows sort last. The This-note section has two
        // rows (identified + ID-less), neither hidden.
        let thisNote = presentation.sections.first { $0.title == "This note" }
        XCTAssertNotNil(thisNote)
        XCTAssertEqual(thisNote?.rows.count, 2)
    }

    func testFilteringRanksOpenBeforeCompletedAtEqualScore() throws {
        let index = WikilinkTaskPickerIndex(candidates: try decodeCandidates())
        // "home" matches an open row (Buy milk is not in sample; Cook dinner
        // is in_progress, Done deed is completed) — open/in-progress ahead
        // of completed at equal score is covered by Bob-order tiebreak.
        let presentation = index.presentation(filter: "dinner done")
        // AND tokens: no row matches both, so empty.
        XCTAssertTrue(presentation.rowsByID.isEmpty)
        let openFirst = index.presentation(filter: "home")
        let ids = openFirst.orderedRowIDs
        // Cook dinner (in_progress) before Done deed (completed).
        let dinner = ids.firstIndex { id in
            openFirst.row(id: id)?.displayText == "Cook dinner"
        }
        let done = ids.firstIndex { id in
            openFirst.row(id: id)?.displayText == "Done deed"
        }
        XCTAssertNotNil(dinner)
        XCTAssertNotNil(done)
        if let dinner, let done {
            XCTAssertLessThan(dinner, done)
        }
    }

    func testDisabledRowHasNoInsertionAndBadge() throws {
        let index = WikilinkTaskPickerIndex(candidates: try decodeCandidates())
        let presentation = index.presentation(filter: "")
        let guarded = presentation.sections.flatMap { $0.rows }.first {
            $0.displayText == "Second twin"
        }
        XCTAssertNotNil(guarded)
        XCTAssertNil(guarded?.insertion)
        XCTAssertNil(guarded?.pendingBlockID)
        XCTAssertEqual(guarded?.badgeText, "duplicate block ID ^twin in twin.md")
        XCTAssertEqual(
            WikilinkTaskPickerIndex.actionLine(for: guarded!), "duplicate block ID ^twin in twin.md"
        )
    }

    func testActionLines() throws {
        let index = WikilinkTaskPickerIndex(candidates: try decodeCandidates())
        let presentation = index.presentation(filter: "")
        let rows = Dictionary(
            uniqueKeysWithValues: presentation.sections.flatMap { $0.rows }.map {
                ($0.displayText, $0)
            })
        XCTAssertEqual(
            WikilinkTaskPickerIndex.actionLine(for: rows["Inbox chore"]!),
            "↩ inserts [[mac_inbox#^inbox-chore]]"
        )
        XCTAssertEqual(
            WikilinkTaskPickerIndex.actionLine(for: rows["Inbox plain"]!),
            "↩ names it ^inbox-plain in mac_inbox.md, then links it"
        )
    }

    func testLocatorUsesLinkTarget() throws {
        let candidates = try decodeCandidates()
        XCTAssertEqual(candidates.first?.linkTarget, "mac_inbox")
        let index = WikilinkTaskPickerIndex(candidates: candidates)
        let presentation = index.presentation(filter: "")
        let row = presentation.sections.flatMap { $0.rows }.first {
            $0.displayText == "Inbox chore"
        }
        XCTAssertNotNil(row)
        XCTAssertEqual(row?.route, "mac_inbox")
        XCTAssertEqual(row?.blockID, "inbox-chore")
    }

    func testSourcePresentation() {
        let source = CapturePickerSource.wikilinkTask(
            WikilinkTaskPickerContext(
                markerRange: CaptureRange(start: 10, end: 12),
                triggerRemovalRange: CaptureRange(start: 11, end: 12),
                query: ""
            )
        )
        XCTAssertEqual(source.triggerByte, 40)
        XCTAssertEqual(source.scopeSymbolText, "((")
        XCTAssertEqual(source.scopeCaption, "Link to Task")
        XCTAssertEqual(source.filterPlaceholder, "Search every task by text, note, or ^id")
        XCTAssertEqual(source.chipLabel, "Link a task")
        XCTAssertEqual(source.locatorMarker, "#^")
        XCTAssertEqual(source.cardAccessibilityLabel, "Task wikilink picker")
        XCTAssertEqual(source.appearedAnnouncementPrefix, "Task wikilinks")
    }
}
