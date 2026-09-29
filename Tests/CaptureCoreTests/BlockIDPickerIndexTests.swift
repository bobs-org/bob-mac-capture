import XCTest

@testable import CaptureCore

final class BlockIDPickerIndexTests: XCTestCase {
    // MARK: - Builders

    private func linkCandidate(
        _ replacement: String,
        symbol: String = " ",
        statusName: String = "Ready",
        text: String? = nil,
        section: String? = "Tasks",
        depth: Int = 0,
        childCount: Int = 0,
        pomodoro: ActiveTaskPomodoro? = nil,
        line: Int = 1,
        route: String = "notes"
    ) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: replacement,
            route: route,
            blockID: replacement,
            statusSymbol: symbol,
            statusName: statusName,
            text: text ?? replacement,
            section: section,
            depth: depth,
            childCount: childCount,
            line: line,
            pomodoro: pomodoro
        )
    }

    private func blockField(
        intent: CaptureBlockIDIntent = .link,
        marker: String = ":",
        route: String = "notes",
        relativeTarget: String = "notes.md",
        noteExists: Bool = true,
        body: String = "",
        allowedCharacter: String = "[A-Za-z0-9_-]",
        allowedDescription: String = "A-Z, a-z, 0-9, '_' or '-'",
        suggestions: [String] = [],
        used: [CaptureUsedBlockID] = []
    ) -> CaptureBlockIDField {
        CaptureBlockIDField(
            route: route,
            relativeTarget: relativeTarget,
            noteExists: noteExists,
            marker: marker,
            intent: intent,
            body: body,
            allowedCharacter: allowedCharacter,
            allowedDescription: allowedDescription,
            suggestions: suggestions,
            used: used
        )
    }

    private func usedID(
        _ id: String,
        line: Int,
        symbol: String? = " ",
        name: String? = "Ready",
        text: String? = nil,
        task: Bool = true
    ) -> CaptureUsedBlockID {
        CaptureUsedBlockID(
            id: id,
            line: line,
            isTask: task,
            statusSymbol: symbol,
            statusName: name,
            text: text ?? "Task \(id)"
        )
    }

    private func fixtureResponse(_ name: String) throws -> CaptureCompletionResponse {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(
            contentsOf: fixtures.appendingPathComponent(name),
            encoding: .utf8
        )
        return try JSONDecoder().decode(CaptureCompletionResponse.self, from: Data(text.utf8))
    }

    private func linkIndex(
        field: CaptureBlockIDField? = nil,
        candidates: [CaptureCompletionCandidate] = []
    ) -> BlockIDPickerIndex {
        BlockIDPickerIndex(
            field: field ?? blockField(),
            candidates: candidates,
            route: "notes"
        )
    }

    // MARK: - Link grouped view

    func testLinkGroupedSectionsHeadersCountsAndBudget() {
        let index = linkIndex(candidates: [
            linkCandidate("a1", symbol: "/", statusName: "In Progress", text: "Alpha one", section: "Next & In Progress", pomodoro: ActiveTaskPomodoro(line: 5, name: "BUGS")),
            linkCandidate("a2", symbol: "*", statusName: "Next", text: "Alpha two", section: "Next & In Progress", pomodoro: ActiveTaskPomodoro(line: 6, name: "BUGS", timeRange: "0900-0930", isCurrent: true)),
            linkCandidate("b1", symbol: "?", statusName: "Blocked", text: "Beta one", section: "Blocked", depth: 1, pomodoro: ActiveTaskPomodoro(line: 7)),
            linkCandidate("c1", text: "Top task", section: nil),
        ])

        let presentation = index.presentation(filter: "")
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(
            presentation.sections.map { $0.title },
            ["Next & In Progress", "Blocked", "Top of note"]
        )
        XCTAssertTrue(presentation.sections.allSatisfy { $0.kind == .noteHeading })
        XCTAssertEqual(
            presentation.sections.map { $0.countText },
            ["2 tasks", "1 task", "1 task"]
        )
        XCTAssertEqual(presentation.countText, "4 tasks")
        XCTAssertEqual(presentation.visibleRowBudget, 7)
        XCTAssertNil(presentation.emptyState)
    }

    func testLinkRowsCarryGlyphDepthChipLocatorDetailAndInsertion() throws {
        let index = linkIndex(candidates: [
            linkCandidate("a1", symbol: "/", statusName: "In Progress", text: "Alpha one", section: "Next & In Progress", childCount: 12, pomodoro: ActiveTaskPomodoro(line: 5, name: "BUGS")),
        ])

        let row = try XCTUnwrap(index.presentation(filter: "").row(id: "a1"))
        XCTAssertEqual(row.glyph, .task(.inProgress))
        XCTAssertEqual(row.locatorStyle, .blockOnly)
        XCTAssertEqual(row.route, "notes")
        XCTAssertEqual(row.blockID, "a1")
        XCTAssertEqual(row.insertion, "a1")
        XCTAssertEqual(row.depth, 0)
        XCTAssertEqual(row.chipText, "BUGS")
        XCTAssertEqual(row.detail.statusText, "In Progress")
        XCTAssertEqual(row.detail.section, "Next & In Progress")
        XCTAssertEqual(row.detail.summary, "Queued in BUGS (#1)")
        XCTAssertEqual(row.detail.childCount, 12)
        XCTAssertTrue(row.accessibilityLabel.contains("In Progress"))
        XCTAssertTrue(row.accessibilityLabel.contains("Alpha one"))
        XCTAssertTrue(row.accessibilityLabel.contains("Block a1"))
        XCTAssertTrue(row.accessibilityLabel.contains("Queued in BUGS (#1)"))
    }

    func testLinkCurrentAndPlannedChipsAndMissingPomodoroSummary() {
        let index = linkIndex(candidates: [
            linkCandidate("a1", text: "Current", pomodoro: ActiveTaskPomodoro(line: 6, name: "BUGS", timeRange: "0900-0930", isCurrent: true)),
            linkCandidate("b1", text: "Planned", pomodoro: ActiveTaskPomodoro(line: 7)),
            linkCandidate("c1", text: "Unqueued"),
        ])
        let presentation = index.presentation(filter: "")

        XCTAssertEqual(presentation.row(id: "a1")?.chipText, "Now · BUGS 09:00–09:30")
        XCTAssertEqual(presentation.row(id: "a1")?.detail.summary, "Now · BUGS 09:00–09:30")
        XCTAssertEqual(presentation.row(id: "b1")?.chipText, "Planned")
        XCTAssertNil(presentation.row(id: "c1")?.chipText)
        XCTAssertEqual(presentation.row(id: "c1")?.detail.summary, "Not in a Pomodoro")
    }

    // MARK: - Link filtering

    func testLinkFilteredRankingCountTextAndFixedBudget() {
        let index = linkIndex(candidates: [
            linkCandidate("a1", text: "Alpha one", section: "Next & In Progress"),
            linkCandidate("a2", text: "Alpha two", section: "Next & In Progress"),
            linkCandidate("b1", symbol: "?", statusName: "Blocked", text: "Beta one", section: "Blocked"),
            linkCandidate("c1", text: "Top task", section: nil),
        ])

        let alpha = index.presentation(filter: "alpha")
        XCTAssertEqual(alpha.mode, .filtered)
        XCTAssertEqual(alpha.orderedRowIDs, ["a1", "a2"])
        XCTAssertEqual(alpha.countText, "2 of 4")
        XCTAssertEqual(alpha.visibleRowBudget, 7)
        XCTAssertFalse(alpha.row(id: "a1")?.textMatchRanges.isEmpty ?? true)

        let blocked = index.presentation(filter: "blocked")
        XCTAssertEqual(blocked.orderedRowIDs, ["b1"])
    }

    func testLinkExactBlockIDMatchIsPinnedFirst() {
        let index = linkIndex(candidates: [
            linkCandidate("xa1y", text: "a1"),
            linkCandidate("a1", text: "zzz qqq"),
        ])

        XCTAssertEqual(index.presentation(filter: "a1").orderedRowIDs.first, "a1")
    }

    func testLinkMultiTokenANDWithNoMatchesShowsEmptyState() {
        let index = linkIndex(candidates: [
            linkCandidate("a1", text: "Alpha one", section: "Next & In Progress"),
        ])

        let presentation = index.presentation(filter: "alpha blocked")
        XCTAssertTrue(presentation.orderedRowIDs.isEmpty)
        XCTAssertEqual(presentation.emptyState?.title, "No matches")
        XCTAssertTrue(presentation.emptyState?.message.contains("alpha blocked") ?? false)
    }

    // MARK: - Link trailing New ID row

    func testLinkFilteredAvailableTokenAppendsNewIDRow() throws {
        let index = linkIndex(
            field: blockField(used: [usedID("tool", line: 18)]),
            candidates: [linkCandidate("a1", text: "Alpha one")]
        )

        let presentation = index.presentation(filter: "brandnew")
        let row = try XCTUnwrap(presentation.row(id: "blockid-new:brandnew"))
        XCTAssertTrue(row.isSelectable)
        XCTAssertEqual(row.glyph, .newID(.available))
        XCTAssertEqual(row.badgeText, "Available · add task text")
        XCTAssertEqual(row.insertion, "brandnew")
        XCTAssertEqual(presentation.orderedRowIDs.last, "blockid-new:brandnew")
        XCTAssertEqual(presentation.countText, "0 of 1")
    }

    func testLinkFilteredExactCandidateHasNoTrailingRow() {
        let index = linkIndex(
            field: blockField(),
            candidates: [linkCandidate("a1", text: "Alpha one")]
        )

        let presentation = index.presentation(filter: "a1")
        XCTAssertEqual(presentation.orderedRowIDs, ["a1"])
        XCTAssertNil(presentation.row(id: "blockid-new:a1"))
    }

    func testLinkFilteredInvalidTokenHasNoTrailingRow() {
        let index = linkIndex(
            field: blockField(),
            candidates: [linkCandidate("a1", text: "Alpha one")]
        )

        let presentation = index.presentation(filter: "a#b")
        XCTAssertTrue(presentation.orderedRowIDs.isEmpty)
        XCTAssertNotNil(presentation.emptyState)
    }

    func testLinkFilteredTakenTokenShowsNonSelectableUsedStatus() {
        let index = linkIndex(
            field: blockField(used: [usedID("brandnew", line: 9, text: "Brand new thing")]),
            candidates: [linkCandidate("a1", text: "Alpha one")]
        )

        let presentation = index.presentation(filter: "brandnew")
        let row = try! XCTUnwrap(presentation.row(id: "blockid-used:brandnew"))
        XCTAssertFalse(row.isSelectable)
        XCTAssertNil(row.insertion)
        XCTAssertEqual(row.badgeText, "Used")
        XCTAssertEqual(row.displayText, "Used by a Ready task · line 9")
        XCTAssertFalse(presentation.orderedRowIDs.contains("blockid-used:brandnew"))
    }

    func testLinkFilteredWithoutFieldHasNoTrailingRow() {
        let index = BlockIDPickerIndex(
            field: nil,
            candidates: [linkCandidate("a1", text: "Alpha one")],
            route: "notes"
        )

        let presentation = index.presentation(filter: "brandnew")
        XCTAssertTrue(presentation.orderedRowIDs.isEmpty)
        XCTAssertNil(index.blockStatus(filter: "brandnew"))
    }

    // MARK: - Link empty states

    func testLinkEmptyStatesForNoTasksMissingNoteAndNoMatches() {
        let noTasks = linkIndex(field: blockField(), candidates: [])
            .presentation(filter: "")
        XCTAssertEqual(noTasks.emptyState?.title, "No linkable tasks in notes.md")
        XCTAssertEqual(noTasks.visibleRowBudget, 4)

        let missing = linkIndex(field: blockField(noteExists: false), candidates: [])
            .presentation(filter: "")
        XCTAssertEqual(missing.emptyState?.title, "notes.md doesn't exist yet")
    }

    // MARK: - Real-bob link snapshots

    func testFixtureLinkFullGroupsByNoteHeadings() throws {
        let response = try fixtureResponse("block-id-link-full.json")
        let index = BlockIDPickerIndex(
            field: response.blockID,
            candidates: response.candidates,
            route: "notes"
        )

        let presentation = index.presentation(filter: "")
        XCTAssertEqual(
            presentation.sections.map { $0.title },
            ["Next & In Progress", "Blocked", "Tasks"]
        )
        XCTAssertEqual(
            presentation.sections.map { $0.countText },
            ["3 tasks", "2 tasks", "1 task"]
        )
        XCTAssertEqual(presentation.countText, "6 tasks")
        XCTAssertEqual(presentation.visibleRowBudget, 9)

        let tool = try XCTUnwrap(presentation.row(id: "tool"))
        XCTAssertEqual(tool.chipText, "BUGS")
        XCTAssertEqual(tool.detail.summary, "Queued in BUGS (#1)")
        XCTAssertEqual(tool.detail.statusText, "Ready")
        XCTAssertEqual(try XCTUnwrap(presentation.row(id: "nested-follow")).depth, 1)
    }

    func testFixtureLinkFilteredAddsNewIDRowForUnmatchedValidToken() throws {
        let response = try fixtureResponse("block-id-link-filtered.json")
        let index = BlockIDPickerIndex(
            field: response.blockID,
            candidates: response.candidates,
            route: "notes"
        )

        let presentation = index.presentation(filter: "rea")
        XCTAssertEqual(presentation.orderedRowIDs, ["blockid-new:rea"])
        XCTAssertEqual(presentation.countText, "0 of 6")
        XCTAssertNil(presentation.emptyState)
    }

    // MARK: - New ID composer

    private func newCaretIndex(
        suggestions: [String] = ["fix-flaky-test", "flaky-test"],
        used: [CaptureUsedBlockID] = [],
        body: String = "Fix flaky test"
    ) -> BlockIDPickerIndex {
        BlockIDPickerIndex(
            field: blockField(
                intent: .new,
                marker: "^",
                body: body,
                allowedCharacter: "[A-Za-z0-9-]",
                allowedDescription: "A-Z, a-z, 0-9 or '-'",
                suggestions: suggestions,
                used: used
            ),
            candidates: [],
            route: "notes"
        )
    }

    func testNewIDEmptyFieldShowsAllSuggestionsWithFixedBudget() {
        let index = newCaretIndex()

        let presentation = index.presentation(filter: "")
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.sections.map { $0.id }, ["suggestions"])
        XCTAssertEqual(presentation.orderedRowIDs, [
            "suggestion:fix-flaky-test", "suggestion:flaky-test",
        ])
        XCTAssertEqual(presentation.countText, "2 options")
        XCTAssertEqual(presentation.visibleRowBudget, 6)
        XCTAssertNil(presentation.emptyState)

        let first = presentation.row(id: "suggestion:fix-flaky-test")
        XCTAssertEqual(first?.glyph, .suggestion)
        XCTAssertEqual(first?.badgeText, "Available")
        XCTAssertEqual(first?.insertion, "fix-flaky-test")

        let status = index.blockStatus(filter: "")
        XCTAssertEqual(status?.availability, .unchecked)
        XCTAssertEqual(status?.usedCount, 0)
        XCTAssertEqual(status?.body, "Fix flaky test")
        XCTAssertEqual(status?.route, "notes")
        XCTAssertEqual(status?.marker, "^")
        XCTAssertFalse(status?.isProjectNote ?? true)
    }

    func testNewIDAvailableTypedIDWithFilteredSuggestionsAndInfo() throws {
        let index = newCaretIndex(used: [usedID("fix-flaky", line: 8, symbol: "/", name: "In Progress", text: "Fix flaky gkeep test")])

        let presentation = index.presentation(filter: "flaky")
        let main = try XCTUnwrap(presentation.row(id: "new:flaky"))
        XCTAssertTrue(main.isSelectable)
        XCTAssertEqual(main.glyph, .newID(.available))
        XCTAssertEqual(main.badgeText, "Available")
        XCTAssertEqual(main.insertion, "flaky")
        XCTAssertEqual(main.detail.statusText, "“Fix flaky test”")
        XCTAssertTrue(main.detail.summary.contains("New task in ▣ notes.md"))
        XCTAssertTrue(main.detail.summary.contains("^flaky is available"))

        XCTAssertEqual(
            presentation.orderedRowIDs,
            ["new:flaky", "suggestion:fix-flaky-test", "suggestion:flaky-test"]
        )
        XCTAssertEqual(presentation.countText, "3 options")

        let info = try XCTUnwrap(presentation.row(id: "info:fix-flaky"))
        XCTAssertFalse(info.isSelectable)
        XCTAssertNil(info.insertion)
        XCTAssertEqual(info.glyph, .task(.inProgress))
        XCTAssertFalse(info.blockIDMatchRanges.isEmpty)
        XCTAssertFalse(presentation.orderedRowIDs.contains("info:fix-flaky"))
    }

    func testNewIDSuggestionFilteringExcludesEqualAndRequiresMatch() {
        let index = newCaretIndex(suggestions: ["fix-flaky-test", "flaky-test", "tool-2"])

        XCTAssertEqual(
            newCaretIndex(suggestions: ["fix-flaky-test", "flaky-test", "tool-2"])
                .presentation(filter: "fix").orderedRowIDs,
            ["new:fix", "suggestion:fix-flaky-test"]
        )
        XCTAssertEqual(
            index.presentation(filter: "test").orderedRowIDs,
            ["new:test", "suggestion:fix-flaky-test", "suggestion:flaky-test"]
        )
        XCTAssertEqual(
            index.presentation(filter: "flaky-test").orderedRowIDs,
            ["new:flaky-test", "suggestion:fix-flaky-test"]
        )
    }

    func testNewIDTakenShowsStatusPlusNextFreeAlternative() throws {
        let response = try fixtureResponse("block-id-new-caret.json")
        let index = BlockIDPickerIndex(
            field: response.blockID,
            candidates: response.candidates,
            route: "notes"
        )

        let presentation = index.presentation(filter: "tool")
        let status = try XCTUnwrap(presentation.row(id: "status:tool"))
        XCTAssertFalse(status.isSelectable)
        XCTAssertNil(status.insertion)
        XCTAssertEqual(status.displayText, "^tool is already used — Add tool command to wrap calls · line 18")
        XCTAssertEqual(
            status.accessibilityLabel,
            "tool is already used on line 18 by Add tool command to wrap calls."
        )

        XCTAssertEqual(presentation.orderedRowIDs, ["alternative:tool-2"])
        let alternative = try XCTUnwrap(presentation.row(id: "alternative:tool-2"))
        XCTAssertEqual(alternative.glyph, .alternativeID)
        XCTAssertEqual(alternative.badgeText, "Next free")
        XCTAssertEqual(alternative.insertion, "tool-2")

        let info = try XCTUnwrap(presentation.row(id: "info:nested-follow"))
        XCTAssertFalse(info.isSelectable)
        XCTAssertFalse(presentation.orderedRowIDs.contains("info:nested-follow"))
    }

    func testNewIDInvalidSeedShowsDescriptionStatus() throws {
        let index = newCaretIndex()

        let presentation = index.presentation(filter: "bad id")
        let row = try XCTUnwrap(presentation.row(id: "status:bad id"))
        XCTAssertFalse(row.isSelectable)
        XCTAssertEqual(row.displayText, "“bad id” isn't a valid block ID")
        XCTAssertEqual(row.badgeText, "A-Z, a-z, 0-9 or '-'")
        XCTAssertEqual(row.accessibilityLabel, "bad id is invalid: A-Z, a-z, 0-9 or '-'.")
        XCTAssertEqual(presentation.emptyState?.title, "No options")
    }

    func testNewIDInfoRowsTakeTopFiveAndExcludeExactConflict() throws {
        let used = [
            usedID("x1", line: 11), usedID("x2", line: 12), usedID("x3", line: 13),
            usedID("x4", line: 14), usedID("x5", line: 15), usedID("x6", line: 16),
            usedID("x", line: 10),
        ]
        let index = newCaretIndex(suggestions: [], used: used, body: "")

        let presentation = index.presentation(filter: "x")
        XCTAssertEqual(presentation.orderedRowIDs, ["alternative:x-2"])
        let infoSection = try XCTUnwrap(presentation.sections.first { $0.id == "used-ids" })
        XCTAssertEqual(infoSection.title, "In use in notes.md")
        XCTAssertEqual(infoSection.countText, "5 similar")
        XCTAssertEqual(
            infoSection.rows.map { $0.id },
            ["info:x1", "info:x2", "info:x3", "info:x4", "info:x5"]
        )
        XCTAssertTrue(infoSection.rows.allSatisfy { !$0.isSelectable })
    }

    func testProjectNoteIsUncheckedWithoutInfoRows() throws {
        let response = try fixtureResponse("block-id-project-note.json")
        let index = BlockIDPickerIndex(
            field: response.blockID,
            candidates: response.candidates,
            route: "notes"
        )

        let presentation = index.presentation(filter: "x")
        XCTAssertEqual(presentation.sections.map { $0.id }, ["new-id"])
        XCTAssertEqual(presentation.orderedRowIDs, ["new:x"])
        let row = try XCTUnwrap(presentation.row(id: "new:x"))
        XCTAssertEqual(row.glyph, .newID(.unchecked))
        XCTAssertEqual(row.badgeText, "Checked on capture")
        XCTAssertTrue(row.detail.summary.contains("Names the new project note"))

        let status = try XCTUnwrap(index.blockStatus(filter: "x"))
        XCTAssertEqual(status.availability, .unchecked)
        XCTAssertTrue(status.isProjectNote)
    }

    func testNewIDEmptyStateNamesGrammarCountsAndMissingBody() {
        let emptyBody = newCaretIndex(suggestions: [], used: [], body: "")
            .presentation(filter: "")
        XCTAssertEqual(emptyBody.emptyState?.title, "Type a new block ID")
        let message = try! XCTUnwrap(emptyBody.emptyState?.message)
        XCTAssertTrue(message.contains("A-Z, a-z, 0-9 or '-'"))
        XCTAssertTrue(message.contains("0 IDs already used in notes.md"))
        XCTAssertTrue(message.contains("Add the task text after the marker."))

        let withBody = newCaretIndex(suggestions: [], used: [], body: "Do thing")
            .presentation(filter: "")
        XCTAssertFalse(try! XCTUnwrap(withBody.emptyState?.message).contains("Add the task text"))
    }

    func testAvailabilityIsExactCaseSensitiveAndGrammarDriven() {
        let index = newCaretIndex(used: [usedID("Tool", line: 4, text: "Capital")])

        XCTAssertEqual(index.availability(of: "tool"), .available)
        XCTAssertEqual(
            index.availability(of: "Tool"),
            .taken(line: 4, text: "Capital")
        )
        XCTAssertEqual(
            index.availability(of: "a_b"),
            .invalid("A-Z, a-z, 0-9 or '-'")
        )
        XCTAssertEqual(index.availability(of: ""), .unchecked)

        let colon = BlockIDPickerIndex(
            field: blockField(intent: .new, used: []),
            candidates: [],
            route: "notes"
        )
        XCTAssertEqual(colon.availability(of: "a_b"), .available)
    }
}
