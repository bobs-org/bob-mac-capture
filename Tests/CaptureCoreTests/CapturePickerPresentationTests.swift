import XCTest

@testable import CaptureCore

final class CapturePickerPresentationTests: XCTestCase {
    // MARK: - Fixture

    private func fixtureCandidates() -> [CaptureCompletionCandidate] {
        func task(
            _ replacement: String,
            route: String = "sase",
            blockID: String,
            symbol: String,
            statusName: String? = nil,
            text: String,
            pomodoro: ActiveTaskPomodoro? = nil
        ) -> CaptureCompletionCandidate {
            CaptureCompletionCandidate(
                replacement: replacement,
                route: route,
                blockID: blockID,
                statusSymbol: symbol,
                statusName: statusName,
                text: text,
                section: "Next & In Progress",
                pomodoro: pomodoro
            )
        }
        func pomodoro(
            line: Int,
            name: String? = nil,
            timeRange: String? = nil,
            isCurrent: Bool = false
        ) -> ActiveTaskPomodoro {
            ActiveTaskPomodoro(line: line, name: name, timeRange: timeRange, isCurrent: isCurrent)
        }
        let sase53 = pomodoro(line: 53, name: "SASE")
        let sase68 = pomodoro(line: 68, name: "SASE")
        let decks = pomodoro(line: 61, name: "DECKS")
        let later = pomodoro(line: 100, name: "LATER")
        return [
            task("sase:deep-fix", blockID: "deep-fix", symbol: "/", statusName: "In Progress", text: "Fix `deep` bug from [[ref/chat/ux|UX chat]]", pomodoro: sase53),
            task("sase:card-blocks", blockID: "card-blocks", symbol: "*", statusName: "Next", text: "Add support for \u{201C}card blocks\u{201D}", pomodoro: sase53),
            task("sase:tui-cli", blockID: "tui-cli", symbol: "/", statusName: "In Progress", text: "Bug bash and improve sase TUI command-mode panel", pomodoro: sase68),
            task("sase:recovery-panel", blockID: "recovery-panel", symbol: "/", statusName: "In Progress", text: "Read and act on core_schema_skew_outage_recovery_ux!", pomodoro: sase68),
            task("sase:dep-empty", blockID: "dep-empty", symbol: "*", statusName: "Next", text: "Delete every empty page", pomodoro: decks),
            task("sase:queue-weights", blockID: "queue-weights", symbol: "*", statusName: "Next", text: "Rebalance queue weights", pomodoro: decks),
            task("sase:later-cleanup", blockID: "later-cleanup", symbol: "*", statusName: "Next", text: "Archive [[ref/chat/old]] LATER items", pomodoro: later),
            task("bob:later-bob", route: "bob", blockID: "later-bob", symbol: "*", statusName: "Next", text: "File bob receipts", pomodoro: later),
            task("sase:sudo-fix", blockID: "sudo-fix", symbol: "/", statusName: "In Progress", text: "Repair `sudo` gate prompt", pomodoro: pomodoro(line: 70, name: "BUGS", timeRange: "0900-0930", isCurrent: true)),
            task("sase:gate-review", blockID: "gate-review", symbol: "*", statusName: "Next", text: "Review gate decisions", pomodoro: pomodoro(line: 80, name: "SUDO")),
            task("sase:planned-thing", blockID: "planned-thing", symbol: "*", statusName: "Next", text: "Draft the unnamed plan", pomodoro: pomodoro(line: 90)),
            task("sase:fix-claude-monitors", blockID: "fix-claude-monitors", symbol: "/", statusName: "In Progress", text: "Watch fix-claude-monitors rollout"),
            task("sase:prefix-cache", blockID: "prefix-cache", symbol: "*", statusName: "Next", text: "Audit the prefix cache"),
            task("sase:cafe-note", blockID: "cafe-note", symbol: "?", statusName: "Open", text: "Review Caf\u{E9} menu copy"),
            // Duplicate replacement: dropped, so row IDs stay unique.
            task("sase:deep-fix", blockID: "deep-fix", symbol: "/", statusName: "In Progress", text: "Duplicate replacement", pomodoro: sase53),
        ]
    }

    private func fixtureIndex() -> ActiveTaskPickerIndex {
        ActiveTaskPickerIndex(candidates: fixtureCandidates())
    }

    // MARK: - Grouped view

    func testGroupedSectionOrderTitlesOrdinalsAndCounts() {
        let presentation = fixtureIndex().presentation(filter: "")
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.sections.map { $0.id }, [
            "pomodoro-53", "pomodoro-68", "pomodoro-61", "pomodoro-100",
            "pomodoro-70", "pomodoro-80", "pomodoro-90",
            "unqueued-in-progress", "unqueued-next", "other",
        ])
        XCTAssertEqual(
            presentation.sections.map { $0.title },
            ["SASE", "SASE", "DECKS", "LATER", "BUGS", "SUDO", "Unnamed Pomodoro", "In Progress", "Next", "Other"]
        )
        XCTAssertEqual(
            presentation.sections.map { $0.ordinal },
            [1, 2, 3, 4, 5, 6, 7, 0, 0, 0]
        )
        XCTAssertEqual(
            presentation.sections.map { $0.rows.count },
            [2, 2, 2, 2, 1, 1, 1, 1, 1, 1]
        )
        XCTAssertEqual(
            presentation.sections.map { $0.kind },
            [.pomodoro, .pomodoro, .pomodoro, .pomodoro, .pomodoro, .pomodoro, .pomodoro, .unqueuedInProgress, .unqueuedNext, .other]
        )
    }

    func testGroupedRowsFollowBobOrder() {
        let presentation = fixtureIndex().presentation(filter: "")
        XCTAssertEqual(
            presentation.orderedRowIDs,
            [
                "sase:deep-fix", "sase:card-blocks",
                "sase:tui-cli", "sase:recovery-panel",
                "sase:dep-empty", "sase:queue-weights",
                "sase:later-cleanup", "bob:later-bob",
                "sase:sudo-fix", "sase:gate-review",
                "sase:planned-thing",
                "sase:fix-claude-monitors", "sase:prefix-cache", "sase:cafe-note",
            ]
        )
    }

    func testDuplicateNamesStaySeparateAndCurrentEntryFormatsTime() {
        let presentation = fixtureIndex().presentation(filter: "")
        let saseSections = presentation.sections.filter { $0.title == "SASE" }
        XCTAssertEqual(saseSections.map { $0.id }, ["pomodoro-53", "pomodoro-68"])
        let bugs = presentation.sections.first { $0.id == "pomodoro-70" }
        XCTAssertEqual(bugs?.isCurrent, true)
        XCTAssertEqual(bugs?.timeRangeText, "09:00\u{2013}09:30")
    }

    func testUnnamedPlaceholderAndOtherBucket() {
        let presentation = fixtureIndex().presentation(filter: "")
        let unnamed = presentation.sections.first { $0.id == "pomodoro-90" }
        XCTAssertEqual(unnamed?.title, "Unnamed Pomodoro")
        XCTAssertEqual(unnamed?.isCurrent, false)
        XCTAssertNil(unnamed?.timeRangeText)
        let other = presentation.sections.first { $0.kind == .other }
        XCTAssertEqual(other?.rows.map { $0.id }, ["sase:cafe-note"])
        XCTAssertEqual(other?.rows.first?.glyph, .task(.blocked))
    }

    func testRowIdentityInsertionAndBobIndex() {
        let presentation = fixtureIndex().presentation(filter: "")
        let row = presentation.row(id: "sase:recovery-panel")
        XCTAssertEqual(row?.bobIndex, 3)
        XCTAssertEqual(row?.insertion, "sase:recovery-panel")
        XCTAssertEqual(row?.route, "sase")
        XCTAssertEqual(row?.blockID, "recovery-panel")
        XCTAssertEqual(row?.displayText, "Read and act on core_schema_skew_outage_recovery_ux!")
        XCTAssertEqual(row?.glyph, .task(.inProgress))
        XCTAssertEqual(presentation.row(id: "sase:prefix-cache")?.glyph, .task(.next))
    }

    func testAccessibilityLabel() {
        let presentation = fixtureIndex().presentation(filter: "")
        XCTAssertEqual(
            presentation.row(id: "sase:deep-fix")?.accessibilityLabel,
            "In Progress. Fix deep bug from UX chat. Note sase, block deep-fix. Queued in SASE, Pomodoro 1."
        )
    }

    func testPomodoroSummaries() {
        let presentation = fixtureIndex().presentation(filter: "")
        XCTAssertEqual(
            presentation.row(id: "sase:deep-fix")?.detail.summary,
            "Queued in SASE (#1)"
        )
        XCTAssertEqual(
            presentation.row(id: "sase:tui-cli")?.detail.summary,
            "Queued in SASE (#2)"
        )
        XCTAssertEqual(
            presentation.row(id: "sase:planned-thing")?.detail.summary,
            "Queued in an unnamed Pomodoro"
        )
        XCTAssertEqual(
            presentation.row(id: "sase:fix-claude-monitors")?.detail.summary,
            "Not in a Pomodoro"
        )
        XCTAssertEqual(
            presentation.row(id: "sase:sudo-fix")?.detail.summary,
            "Now \u{00B7} BUGS 09:00\u{2013}09:30"
        )
    }

    func testGroupedRowsOmitPomodoroChip() {
        let presentation = fixtureIndex().presentation(filter: "")
        XCTAssertTrue(presentation.sections.flatMap { $0.rows }.allSatisfy { $0.chipText == nil })
    }

    func testDuplicateReplacementDedupe() {
        let index = fixtureIndex()
        XCTAssertEqual(index.count, 14)
        let presentation = index.presentation(filter: "")
        XCTAssertEqual(presentation.totalCount, 14)
        XCTAssertEqual(presentation.matchCount, 14)
        XCTAssertEqual(presentation.countText, "14 tasks")
        XCTAssertEqual(Set(presentation.orderedRowIDs).count, 14)
    }

    func testGroupedVisibleRowBudgetClamps() {
        XCTAssertEqual(fixtureIndex().presentation(filter: "").visibleRowBudget, 11)
        let single = ActiveTaskPickerIndex(candidates: [fixtureCandidates()[11]])
        XCTAssertEqual(single.presentation(filter: "").visibleRowBudget, 4)
        XCTAssertEqual(single.presentation(filter: "").countText, "1 task")
    }

    // MARK: - Filtered view

    func testDirectTextMatchOutranksPomodoroNameMatch() {
        let presentation = fixtureIndex().presentation(filter: "sudo")
        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertEqual(presentation.sections.map { $0.kind }, [.matches])
        XCTAssertEqual(
            Array(presentation.orderedRowIDs.prefix(2)),
            ["sase:sudo-fix", "sase:gate-review"]
        )
        XCTAssertEqual(presentation.countText, "5 of 14")
        // Pomodoro-name matches raise the rank without highlighting.
        let pomodoroOnly = presentation.row(id: "sase:gate-review")
        XCTAssertEqual(pomodoroOnly?.textMatchRanges, [])
        XCTAssertEqual(pomodoroOnly?.routeMatchRanges, [])
        XCTAssertEqual(pomodoroOnly?.blockIDMatchRanges, [])
    }

    func testLaterSurfacesLaterTasks() {
        let presentation = fixtureIndex().presentation(filter: "later")
        XCTAssertEqual(presentation.orderedRowIDs, ["sase:later-cleanup", "bob:later-bob"])
        XCTAssertEqual(presentation.countText, "2 of 14")
    }

    func testBobSurfacesBobRoute() {
        let presentation = fixtureIndex().presentation(filter: "bob")
        XCTAssertEqual(presentation.orderedRowIDs, ["bob:later-bob"])
    }

    func testFixRanksBoundaryAboveMidWord() {
        let presentation = fixtureIndex().presentation(filter: "fix")
        let ids = presentation.orderedRowIDs
        XCTAssertEqual(ids, ["sase:deep-fix", "sase:fix-claude-monitors", "sase:sudo-fix", "sase:prefix-cache"])
    }

    func testConsecutiveBeatsScatteredEndToEnd() {
        let presentation = fixtureIndex().presentation(filter: "deep")
        XCTAssertEqual(
            Array(presentation.orderedRowIDs.prefix(2)),
            ["sase:deep-fix", "sase:dep-empty"]
        )
    }

    func testMultiTokenANDIsOrderIndependent() {
        let forward = fixtureIndex().presentation(filter: "q weight")
        let backward = fixtureIndex().presentation(filter: "weight q")
        XCTAssertEqual(forward.orderedRowIDs, ["sase:queue-weights"])
        XCTAssertEqual(forward.orderedRowIDs, backward.orderedRowIDs)
    }

    func testLeadingCaretIsIgnored() {
        let index = fixtureIndex()
        XCTAssertEqual(
            index.presentation(filter: "^dee").orderedRowIDs,
            index.presentation(filter: "dee").orderedRowIDs
        )
        XCTAssertEqual(index.presentation(filter: "^").mode, .grouped)
    }

    func testSectionOnlyMatchesTieInBobOrder() {
        let index = fixtureIndex()
        let filtered = index.presentation(filter: "next")
        XCTAssertEqual(filtered.matchCount, 14)
        XCTAssertEqual(filtered.orderedRowIDs, index.presentation(filter: "").orderedRowIDs)
        XCTAssertEqual(filtered.countText, "14 of 14")
    }

    func testHighlightRangesMapIntoTextAndLocator() {
        let presentation = fixtureIndex().presentation(filter: "sudo")
        XCTAssertEqual(
            presentation.row(id: "sase:sudo-fix")?.textMatchRanges,
            [7..<11]
        )
        let bob = fixtureIndex().presentation(filter: "bob")
        XCTAssertEqual(bob.row(id: "bob:later-bob")?.textMatchRanges, [5..<8])
        XCTAssertEqual(bob.row(id: "bob:later-bob")?.routeMatchRanges, [])
        XCTAssertEqual(bob.row(id: "bob:later-bob")?.blockIDMatchRanges, [])
    }

    func testCoalescedMergesNonzeroAndSparsePositions() {
        XCTAssertEqual(ActiveTaskMatchHighlights.coalesced([]), [])
        XCTAssertEqual(ActiveTaskMatchHighlights.coalesced([5]), [5..<6])
        XCTAssertEqual(ActiveTaskMatchHighlights.coalesced([5, 6, 7]), [5..<8])
        XCTAssertEqual(ActiveTaskMatchHighlights.coalesced([5, 10]), [5..<6, 10..<11])
        XCTAssertEqual(ActiveTaskMatchHighlights.coalesced([10, 5, 6, 6]), [5..<7, 10..<11])
    }

    func testFilteredPomodoroChips() {
        let presentation = fixtureIndex().presentation(filter: "plan")
        XCTAssertEqual(presentation.orderedRowIDs, ["sase:planned-thing"])
        XCTAssertEqual(presentation.row(id: "sase:planned-thing")?.chipText, "Planned")
        let sudo = fixtureIndex().presentation(filter: "sudo")
        XCTAssertEqual(
            sudo.row(id: "sase:sudo-fix")?.chipText,
            "Now \u{00B7} BUGS 09:00\u{2013}09:30"
        )
    }

    // MARK: - Empty states

    func testNoMatchesEmptyState() {
        let presentation = fixtureIndex().presentation(filter: "zzz-no-match")
        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertEqual(presentation.orderedRowIDs, [])
        XCTAssertEqual(presentation.matchCount, 0)
        XCTAssertEqual(presentation.countText, "0 of 14")
        XCTAssertEqual(presentation.emptyState, .noMatches(query: "zzz-no-match"))
        XCTAssertEqual(presentation.emptyState?.title, "No matches")
        XCTAssertNotNil(presentation.emptyState?.message)
    }

    func testNoActiveTasksEmptyState() {
        let presentation = ActiveTaskPickerIndex(candidates: []).presentation(filter: "")
        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.totalCount, 0)
        XCTAssertEqual(presentation.countText, "0 tasks")
        XCTAssertEqual(presentation.emptyState, .noActiveTasks)
        XCTAssertEqual(presentation.emptyState?.title, "No active tasks")
        XCTAssertEqual(presentation.visibleRowBudget, 4)
    }

    func testTimeRangeFormatting() {
        XCTAssertEqual(ActiveTaskPickerIndex.formattedTimeRange("0900-0930"), "09:00\u{2013}09:30")
        XCTAssertEqual(ActiveTaskPickerIndex.formattedTimeRange("nonsense"), "nonsense")
        XCTAssertEqual(ActiveTaskPickerIndex.formattedTimeRange("900-930"), "900-930")
        XCTAssertEqual(ActiveTaskPickerIndex.formattedTimeRange("2500-0930"), "2500-0930")
    }

    // MARK: - Navigation

    func testNavigationNextPreviousWrap() {
        let ids = fixtureIndex().presentation(filter: "").orderedRowIDs
        XCTAssertEqual(CapturePickerNavigation.next(after: ids.first!, in: ids), ids[1])
        XCTAssertEqual(CapturePickerNavigation.next(after: ids.last!, in: ids), ids.first)
        XCTAssertEqual(CapturePickerNavigation.previous(before: ids.first!, in: ids), ids.last)
        XCTAssertEqual(CapturePickerNavigation.previous(before: ids[1], in: ids), ids.first)
        XCTAssertNil(CapturePickerNavigation.next(after: "missing", in: ids))
        XCTAssertNil(CapturePickerNavigation.next(after: ids.first!, in: []))
    }

    func testNavigationPageClamps() {
        let ids = fixtureIndex().presentation(filter: "").orderedRowIDs
        XCTAssertEqual(CapturePickerNavigation.page(from: ids.first!, by: 3, in: ids), ids[3])
        XCTAssertEqual(CapturePickerNavigation.page(from: ids.first!, by: 100, in: ids), ids.last)
        XCTAssertEqual(CapturePickerNavigation.page(from: ids.last!, by: -100, in: ids), ids.first)
        XCTAssertNil(CapturePickerNavigation.page(from: "missing", by: 1, in: ids))
    }

    func testNavigationFirstLastAndResolvedSelection() {
        let ids = fixtureIndex().presentation(filter: "").orderedRowIDs
        XCTAssertEqual(CapturePickerNavigation.first(in: ids), ids.first)
        XCTAssertEqual(CapturePickerNavigation.last(in: ids), ids.last)
        XCTAssertNil(CapturePickerNavigation.first(in: []))
        XCTAssertEqual(
            CapturePickerNavigation.resolvedSelection(preferred: ids[5], in: ids),
            ids[5]
        )
        XCTAssertEqual(
            CapturePickerNavigation.resolvedSelection(preferred: "missing", in: ids),
            ids.first
        )
        XCTAssertEqual(
            CapturePickerNavigation.resolvedSelection(preferred: nil, in: ids),
            ids.first
        )
        XCTAssertNil(CapturePickerNavigation.resolvedSelection(preferred: nil, in: []))
    }

    // MARK: - Task status mapping

    func testTaskStatusMapsBobSymbols() {
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "/", name: "In Progress"), .inProgress)
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "*", name: "Next"), .next)
        XCTAssertEqual(CapturePickerTaskStatus(symbol: " ", name: "Todo"), .todo)
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "?", name: "Blocked"), .blocked)
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "x", name: "Done"), .done)
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "X", name: "Done"), .done)
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "-", name: "Canceled"), .canceled)
    }

    func testTaskStatusFallsBackToNameSymbolOrOther() {
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "~", name: "Open"), .other("Open"))
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "~", name: ""), .other("~"))
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "~", name: nil), .other("~"))
        XCTAssertEqual(CapturePickerTaskStatus(symbol: "", name: nil), .other("Other"))
        XCTAssertEqual(CapturePickerTaskStatus(symbol: nil, name: nil), .other("Other"))
    }

    func testTaskStatusDisplayNames() {
        XCTAssertEqual(CapturePickerTaskStatus.inProgress.displayName, "In Progress")
        XCTAssertEqual(CapturePickerTaskStatus.next.displayName, "Next")
        XCTAssertEqual(CapturePickerTaskStatus.todo.displayName, "Todo")
        XCTAssertEqual(CapturePickerTaskStatus.blocked.displayName, "Blocked")
        XCTAssertEqual(CapturePickerTaskStatus.done.displayName, "Done")
        XCTAssertEqual(CapturePickerTaskStatus.canceled.displayName, "Canceled")
        XCTAssertEqual(CapturePickerTaskStatus.other("Open").displayName, "Open")
    }
}
