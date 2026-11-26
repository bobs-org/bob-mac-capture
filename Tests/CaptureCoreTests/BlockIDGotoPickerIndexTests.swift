import XCTest

@testable import CaptureCore

/// Tests for the scoped Go To browse in `BlockIDPickerIndex`: selectable Go
/// rows, exact preselect, the archived section, the no-match info row, and
/// the hidden New ID rows. Rows are built by hand; the generated
/// `block-id-goto-*.json` fixtures cover the wire shape.
final class BlockIDGotoPickerIndexTests: XCTestCase {
    private func gotoRow(
        _ id: String,
        line: Int,
        notePath: String = "bob.md",
        target: String = "/vault/bob.md",
        kind: String = "task",
        text: String? = nil,
        symbol: String? = "*",
        name: String? = "Next",
        section: String? = "Tasks",
        archived: Bool = false
    ) -> CaptureGotoRow {
        CaptureGotoRow(
            blockID: id,
            notePath: notePath,
            target: target,
            line: line,
            ref: "\(line):aaaa1111",
            targetKind: kind,
            text: text ?? "Task \(id)",
            statusSymbol: kind == "task" ? symbol : nil,
            statusName: kind == "task" ? name : nil,
            statusType: kind == "task" ? "TODO" : nil,
            section: section,
            closed: nil,
            archived: archived,
            draft: nil,
            reason: nil
        )
    }

    private func gotoField(
        rows: [CaptureGotoRow],
        noteExists: Bool = true,
        archivePath: String? = "done/bob_done.md",
        eligible: Bool = true
    ) -> CaptureBlockIDField {
        CaptureBlockIDField(
            route: "bob",
            relativeTarget: "bob.md",
            noteExists: noteExists,
            marker: "^",
            intent: .new,
            body: "",
            allowedCharacter: "[A-Za-z0-9-]",
            allowedDescription: "A-Z, a-z, 0-9 or '-'",
            suggestions: [],
            used: [],
            goto: CaptureBlockIDGoto(
                eligible: eligible,
                notePath: "bob.md",
                target: "/vault/bob.md",
                archivePath: archivePath,
                rows: rows
            )
        )
    }

    private func browse(
        rows: [CaptureGotoRow],
        noteExists: Bool = true,
        eligible: Bool = true
    ) -> BlockIDPickerIndex {
        BlockIDPickerIndex(
            field: gotoField(rows: rows, noteExists: noteExists, eligible: eligible),
            candidates: [],
            route: "bob"
        )
    }

    private var livingRows: [CaptureGotoRow] {
        [
            gotoRow("focus", line: 8, text: "Review the focus area"),
            gotoRow("follow-up", line: 12),
            gotoRow("focus-ring", line: 20, kind: "heading", text: "Focus ring"),
        ]
    }

    // MARK: - Browse shape

    func testEmptyFilterListsLivingRowsInBobOrderWithNoArchivedSection() {
        let archived = gotoRow("old-focus", line: 3, notePath: "done/bob_done.md", archived: true)
        let presentation = browse(rows: livingRows + [archived]).presentation(filter: "")

        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.sections.map { $0.title }, ["Go To · bob.md"])
        XCTAssertEqual(
            presentation.orderedRowIDs,
            ["goto:bob.md:focus", "goto:bob.md:follow-up", "goto:bob.md:focus-ring"]
        )
        XCTAssertEqual(presentation.countText, "3 options")
        XCTAssertNil(presentation.emptyState)
        XCTAssertNil(presentation.blockIDStatus)
    }

    func testExactMatchPreselectsFirst() {
        let presentation = browse(rows: livingRows).presentation(filter: "focus")

        XCTAssertEqual(
            presentation.orderedRowIDs.first,
            "goto:bob.md:focus",
            "the exact match leads so Return lands on it"
        )
        // Prefix tier follows in Bob order; follow-up shares no subsequence
        // ("focus" needs a "c") and drops out.
        XCTAssertEqual(
            presentation.orderedRowIDs,
            ["goto:bob.md:focus", "goto:bob.md:focus-ring"]
        )
    }

    func testArchivedSectionAppearsOnlyWithNonEmptyFilter() {
        let archived = gotoRow("old-focus", line: 3, notePath: "done/bob_done.md", archived: true)
        let rows = livingRows + [archived]

        let empty = browse(rows: rows).presentation(filter: "")
        XCTAssertFalse(empty.sections.map { $0.title }.contains("Archived · done/bob_done.md"))

        // "old-focus" fuzzy-matches "focus", so both sections render.
        let filtered = browse(rows: rows).presentation(filter: "focus")
        XCTAssertEqual(
            filtered.sections.map { $0.title },
            ["Go To · bob.md", "Archived · done/bob_done.md"]
        )
        XCTAssertTrue(filtered.orderedRowIDs.contains("goto:done/bob_done.md:old-focus"))
    }

    func testArchivedRankedWithLivingRowsInOneOrder() {
        let archived = gotoRow("focus-old", line: 3, notePath: "done/bob_done.md", archived: true)
        let presentation = browse(rows: livingRows + [archived]).presentation(filter: "focus")

        // Exact first, then prefixes (living before archived in Bob order).
        XCTAssertEqual(
            presentation.orderedRowIDs,
            [
                "goto:bob.md:focus",
                "goto:bob.md:focus-ring",
                "goto:done/bob_done.md:focus-old",
            ]
        )
    }

    func testRowsCarryDestinationInsertionAndQuietLine() throws {
        let presentation = browse(rows: livingRows).presentation(filter: "focus")
        let row = try XCTUnwrap(presentation.row(id: "goto:bob.md:focus"))

        XCTAssertEqual(row.insertion, "focus")
        XCTAssertEqual(row.displayText, "Review the focus area")
        XCTAssertEqual(row.blockID, "focus")
        XCTAssertNil(row.route, "the section header already names the note")
        XCTAssertEqual(row.badgeText, "line 8")
        XCTAssertEqual(row.glyph, .task(CapturePickerTaskStatus(symbol: "*", name: "Next")))
        let destination = try XCTUnwrap(row.taskGotoDestination)
        XCTAssertEqual(destination.target, "/vault/bob.md")
        XCTAssertEqual(destination.notePath, "bob.md")
        XCTAssertEqual(destination.line, 8)
        XCTAssertEqual(destination.ref, "8:aaaa1111")
        XCTAssertEqual(destination.blockID, "focus")
        XCTAssertFalse(row.blockIDMatchRanges.isEmpty)
    }

    func testNonTaskRowUsesAnchorGlyphAndKindLabel() throws {
        let presentation = browse(rows: livingRows).presentation(filter: "focus-ring")
        let row = try XCTUnwrap(presentation.row(id: "goto:bob.md:focus-ring"))

        XCTAssertEqual(row.glyph, .anchor)
        XCTAssertEqual(row.detail.statusText, "Heading")
    }

    func testNoMatchYieldsOneNonSelectableInfoRow() throws {
        let presentation = browse(rows: livingRows).presentation(filter: "zzz-no-such-id")

        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertEqual(presentation.orderedRowIDs, [])
        XCTAssertNil(presentation.emptyState)
        let row = try XCTUnwrap(presentation.row(id: "goto-empty:zzz-no-such-id"))
        XCTAssertFalse(row.isSelectable)
        XCTAssertNil(row.insertion)
        XCTAssertNil(row.taskGotoDestination)
        XCTAssertEqual(
            row.displayText,
            "No ^zzz-no-such-id in bob.md — add text after the ID to create a task"
        )
    }

    func testBrowseHidesNewIDTakenNextFreeSuggestionAndUsedRows() {
        let field = gotoField(rows: livingRows)
        let index = BlockIDPickerIndex(
            field: CaptureBlockIDField(
                route: field.route,
                relativeTarget: field.relativeTarget,
                noteExists: field.noteExists,
                marker: field.marker,
                intent: field.intent,
                body: field.body,
                allowedCharacter: field.allowedCharacter,
                allowedDescription: field.allowedDescription,
                suggestions: ["focus"],
                used: [CaptureUsedBlockID(id: "focus", line: 8, isTask: true, statusSymbol: "*", statusName: "Next", text: "Review")],
                goto: field.goto
            ),
            candidates: [],
            route: "bob"
        )
        let presentation = index.presentation(filter: "focus")

        for id in presentation.orderedRowIDs {
            XCTAssertTrue(id.hasPrefix("goto:"), "no composer row may survive: \(id)")
        }
        XCTAssertNil(presentation.row(id: "new:focus"))
        XCTAssertNil(presentation.row(id: "alternative:focus"))
        XCTAssertNil(presentation.row(id: "status:focus"))
        XCTAssertNil(presentation.row(id: "suggestion:focus"))
    }

    func testEmptyNoteKeepsNewIDEmptyState() {
        let presentation = browse(rows: []).presentation(filter: "")

        XCTAssertEqual(presentation.orderedRowIDs, [])
        XCTAssertEqual(presentation.emptyState?.title, "Type a new block ID")
    }

    func testMissingNoteKeepsNoteMissingEmptyState() {
        let field = gotoField(rows: [], noteExists: false)
        let index = BlockIDPickerIndex(field: field, candidates: [], route: "bob")
        let presentation = index.presentation(filter: "")

        XCTAssertEqual(presentation.orderedRowIDs, [])
        XCTAssertEqual(presentation.emptyState?.title, "bob.md doesn't exist yet")
    }

    // MARK: - Eligibility

    func testIsGotoBrowseTracksEligibility() {
        XCTAssertTrue(browse(rows: livingRows).isGotoBrowse)
        XCTAssertFalse(browse(rows: livingRows, eligible: false).isGotoBrowse)
    }

    func testOldBobWithoutGotoKeepsTodaysComposer() {
        let field = CaptureBlockIDField(
            route: "bob",
            relativeTarget: "bob.md",
            noteExists: true,
            marker: "^",
            intent: .new,
            body: "",
            allowedCharacter: "[A-Za-z0-9-]",
            allowedDescription: "A-Z, a-z, 0-9 or '-'",
            suggestions: ["focus"]
        )
        let index = BlockIDPickerIndex(field: field, candidates: [], route: "bob")

        XCTAssertFalse(index.isGotoBrowse)
        let presentation = index.presentation(filter: "")
        XCTAssertTrue(presentation.orderedRowIDs.allSatisfy { !$0.hasPrefix("goto:") })
        XCTAssertNotNil(presentation.blockIDStatus, "the mint badge still reports availability")
    }
}
