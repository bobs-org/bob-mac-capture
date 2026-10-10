import XCTest

@testable import CaptureCore

final class CaptureAgendaFitPlannerTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let today = "2026-08-28"

    // MARK: - Builders

    private func makeLine(
        _ text: String,
        depth: Int = 1,
        kind: CaptureAgendaLineKind = .bullet,
        log: CaptureAgendaLog? = nil
    ) -> CaptureAgendaLine {
        CaptureAgendaLine(text: text, depth: depth, kind: kind, statusSymbol: nil, log: log)
    }

    private func makeItem(
        ledgerLine: Int,
        blockID: String,
        target: String = "tasks.md",
        title: String = "Task title",
        lines: [CaptureAgendaLine] = []
    ) -> CaptureAgendaItem {
        CaptureAgendaItem(
            index: 1,
            ledgerLine: ledgerLine,
            ledgerDepth: 1,
            marker: .plain,
            blockLink: "[[\(target)#^\(blockID)]]",
            resolution: .resolved,
            relativeTarget: target,
            line: 1,
            blockID: blockID,
            text: title,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            lines: lines,
            linesTruncated: 0,
            ledgerNotes: [],
            warning: nil
        )
    }

    private func logLines(prefix: String, count: Int) -> [CaptureAgendaLine] {
        var lines = [makeLine("Work log", kind: .logMarker, log: .work)]
        for index in 0..<count {
            lines.append(makeLine("\(prefix) entry \(index)", depth: 2, log: .work))
        }
        return lines
    }

    private func makeEntry(
        line: Int,
        name: String,
        role: CaptureAgendaRole,
        items: [CaptureAgendaItem]
    ) -> CaptureAgendaPomodoro {
        CaptureAgendaPomodoro(
            line: line,
            name: name,
            isCurrent: role == .current,
            taskLinkCount: items.count,
            role: role,
            startsAt: nil,
            endsAt: nil,
            retiredLinkCount: 0,
            notes: [],
            items: items,
            slug: name.lowercased(),
            selectable: true
        )
    }

    private func makePresentation(
        entries: [CaptureAgendaPomodoro],
        planBudget: CapturePlanBudget? = nil
    ) -> CaptureAgendaPresentation {
        let snapshot = CaptureAgendaSnapshot(
            ok: true,
            schemaVersion: 1,
            date: today,
            completedSummary: CaptureAgendaCompletedSummary(),
            pomodoros: entries,
            warnings: [],
            planBudget: planBudget
        )
        return CaptureAgendaPresentation(snapshot: snapshot, today: today, locale: locale)
    }

    /// Three-group agenda: Now and Next each hold one logged task, and
    /// two Later groups hold one logged task each.
    private func standardPresentation(
        planBudget: CapturePlanBudget? = nil
    ) -> CaptureAgendaPresentation {
        makePresentation(entries: [
            makeEntry(
                line: 3,
                name: "NOW",
                role: .current,
                items: [
                    makeItem(
                        ledgerLine: 4,
                        blockID: "now",
                        lines: logLines(prefix: "now", count: 2)
                    ),
                ]
            ),
            makeEntry(
                line: 10,
                name: "NEXT",
                role: .next,
                items: [
                    makeItem(
                        ledgerLine: 11,
                        blockID: "next",
                        lines: logLines(prefix: "next", count: 2)
                    ),
                ]
            ),
            makeEntry(
                line: 20,
                name: "NEAR",
                role: .later,
                items: [
                    makeItem(
                        ledgerLine: 21,
                        blockID: "near",
                        lines: logLines(prefix: "near", count: 2)
                    ),
                ]
            ),
            makeEntry(
                line: 30,
                name: "FAR",
                role: .later,
                items: [
                    makeItem(
                        ledgerLine: 31,
                        blockID: "far",
                        lines: logLines(prefix: "far", count: 2)
                    ),
                ]
            ),
        ], planBudget: planBudget)
    }

    /// Every rendered row (at every fold level) measures the same.
    private func uniformHeights(
        _ presentation: CaptureAgendaPresentation,
        height: Double = 10
    ) -> [CaptureAgendaRowKey: Double] {
        var heights: [CaptureAgendaRowKey: Double] = [:]
        func add(_ row: CaptureAgendaRow) {
            heights[row.key] = height
        }
        add(presentation.titleRow)
        if let planBudget = presentation.planBudgetRow {
            add(planBudget)
        }
        if let warning = presentation.warningRow {
            add(warning)
        }
        if let stateRow = presentation.stateRow {
            add(stateRow)
        }
        for group in presentation.groups {
            add(group.headerRow)
            add(CaptureAgendaFitPlanner.headerWithNotesChip(group: group))
            for note in group.sessionNoteRows {
                add(note)
            }
            for task in group.tasks {
                for row in task.fullRows {
                    add(row)
                }
                for row in task.noLogsRows {
                    add(row)
                }
                add(task.oneLineRow)
            }
            if let retired = group.retiredRow {
                add(retired)
            }
            if let empty = group.emptyRow {
                add(empty)
            }
            add(group.oneRowRow)
        }
        add(presentation.stripFullRow)
        return heights
    }

    private func plan(
        _ presentation: CaptureAgendaPresentation,
        heights: [CaptureAgendaRowKey: Double]? = nil,
        budget: Double,
        expanded: Set<CaptureAgendaUnitID> = []
    ) -> CaptureAgendaPlan {
        CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: heights ?? uniformHeights(presentation),
            budget: budget,
            expanded: expanded
        )
    }

    private func state(
        of groupName: String,
        in result: CaptureAgendaPlan,
        presentation: CaptureAgendaPresentation
    ) -> CaptureAgendaGroupState? {
        guard let group = presentation.groups.first(where: { $0.name == groupName }) else {
            return nil
        }
        return result.groupStates[group.id]
    }

    // MARK: - Ladder

    func testEverythingFullFitsAHugeBudget() {
        let presentation = standardPresentation()
        let result = plan(presentation, budget: 100_000)
        XCTAssertFalse(result.overflows)
        XCTAssertEqual(result.hiddenCount, 0)
        for group in presentation.groups {
            XCTAssertEqual(result.groupStates[group.id], .full)
        }
    }

    func testFirstFoldHitsTheFarthestLaterGroup() {
        let presentation = standardPresentation()
        let full = plan(presentation, budget: 100_000)
        let result = plan(presentation, budget: full.totalHeight - 1)
        XCTAssertFalse(result.overflows)
        XCTAssertEqual(state(of: "FAR", in: result, presentation: presentation), .noLogs)
        XCTAssertEqual(state(of: "NEAR", in: result, presentation: presentation), .full)
        XCTAssertEqual(state(of: "NEXT", in: result, presentation: presentation), .full)
        XCTAssertEqual(state(of: "NOW", in: result, presentation: presentation), .full)
    }

    func testLaterFoldsToTheStripBeforeNowOrNextFold() {
        let presentation = standardPresentation()
        let full = plan(presentation, budget: 100_000)
        var sawStripWithCalmNowNext = false
        var budget = full.totalHeight
        while budget > 0 {
            budget -= 10
            let result = plan(presentation, budget: budget)
            let laterStates = presentation.groups
                .filter { $0.role == .later }
                .compactMap { result.groupStates[$0.id] }
            let nowState = state(of: "NOW", in: result, presentation: presentation)
            let nextState = state(of: "NEXT", in: result, presentation: presentation)
            if laterStates.allSatisfy({ $0 == .inStrip }) {
                XCTAssertFalse(result.overflows)
                XCTAssertEqual(result.stripGroupIDs.count, 2)
                XCTAssertTrue(nowState == .full || nowState == .noLogs)
                XCTAssertTrue(nextState == .full || nextState == .noLogs)
                sawStripWithCalmNowNext = true
                break
            }
        }
        XCTAssertTrue(sawStripWithCalmNowNext)
    }

    func testLadderOrderIsNoLogsOneLineOneRowStrip() {
        // One logged line (so noLogs saves) plus two plain children (so
        // oneLine saves more): every rung is the first fit somewhere.
        let presentation = makePresentation(entries: [
            makeEntry(
                line: 20,
                name: "ONLY",
                role: .later,
                items: [makeItem(
                    ledgerLine: 21,
                    blockID: "only",
                    lines: logLines(prefix: "only", count: 1)
                        + [makeLine("plain one"), makeLine("plain two")]
                )]
            ),
        ])
        let full = plan(presentation, budget: 100_000)
        var seen: [CaptureAgendaGroupState] = []
        var budget = full.totalHeight
        while budget > 0 {
            budget -= 5
            let result = plan(presentation, budget: budget)
            guard let only = presentation.groups.first else {
                continue
            }
            let current = result.groupStates[only.id] ?? .full
            if seen.last != current {
                seen.append(current)
            }
            if result.overflows {
                break
            }
        }
        XCTAssertEqual(seen, [.noLogs, .oneLineTasks, .oneRow, .inStrip])
    }

    func testGroupsWithNothingToFoldAreSkipped() {
        let presentation = makePresentation(entries: [
            makeEntry(line: 3, name: "NOW", role: .current, items: [
                makeItem(
                        ledgerLine: 4,
                        blockID: "now",
                        lines: logLines(prefix: "now", count: 2)
                    ),
            ]),
            makeEntry(line: 20, name: "EMPTY", role: .later, items: []),
        ])
        let full = plan(presentation, budget: 100_000)
        let result = plan(presentation, budget: full.totalHeight - 1)
        let empty = presentation.groups.first(where: { $0.name == "EMPTY" })
        XCTAssertEqual(result.groupStates[empty?.id ?? .strip], .full)
        XCTAssertTrue(result.rows.contains(where: { $0.kind == .emptyGroup }))
    }

    func testDuplicatesStayOneLineAtEveryLevel() {
        let presentation = makePresentation(entries: [
            makeEntry(line: 3, name: "NOW", role: .current, items: [
                makeItem(ledgerLine: 4, blockID: "same"),
            ]),
            makeEntry(line: 10, name: "NEXT", role: .next, items: [
                makeItem(ledgerLine: 11, blockID: "same"),
            ]),
        ])
        let result = plan(presentation, budget: 100_000)
        let dups = result.rows.filter { $0.kind == .duplicate }
        XCTAssertEqual(dups.count, 1)
        XCTAssertEqual(dups.first?.text, "Task title ↑ in NOW")
        let folded = plan(presentation, budget: 60)
        XCTAssertTrue(folded.rows.contains(where: { $0.kind == .duplicate }))
    }

    // MARK: - Expansions

    func testExpandedGroupsPinAtFullAndOverflow() {
        let presentation = standardPresentation()
        guard let far = presentation.groups.first(where: { $0.name == "FAR" }) else {
            return XCTFail("missing FAR group")
        }
        let result = plan(presentation, budget: 50, expanded: [far.id])
        XCTAssertEqual(result.groupStates[far.id], .full)
        XCTAssertTrue(result.overflows)
    }

    func testExpandedTasksStayFullInsideFoldedGroups() {
        let presentation = standardPresentation()
        guard let task = presentation.groups.first(where: { $0.name == "NEAR" })?.tasks.first else {
            return XCTFail("missing NEAR task")
        }
        guard let near = presentation.groups.first(where: { $0.name == "NEAR" }) else {
            return XCTFail("missing NEAR group")
        }
        // Walk the budget down to the first plan where NEAR folds its
        // logs, then pin its task at that same budget.
        let full = plan(presentation, budget: 100_000)
        var budget = full.totalHeight
        var foldedBudget = budget
        while budget > 0 {
            budget -= 10
            let candidate = plan(presentation, budget: budget)
            if candidate.groupStates[near.id] == .noLogs {
                foldedBudget = budget
                break
            }
        }
        let pinned = plan(presentation, budget: foldedBudget, expanded: [task.id])
        XCTAssertEqual(pinned.taskStates[task.id], .full)
        XCTAssertTrue(pinned.rows.contains(where: { $0.text == "near entry 0" }))
        XCTAssertFalse(pinned.rows.contains(where: { $0.text == "far entry 0" }))
    }

    func testExpandedStripKeepsOneRowGroups() {
        let presentation = standardPresentation()
        let full = plan(presentation, budget: 100_000)
        var budget = full.totalHeight
        var stripBudget = budget
        var reachedStrip = false
        while budget > 0 {
            budget -= 10
            let candidate = plan(presentation, budget: budget)
            if !candidate.stripGroupIDs.isEmpty {
                stripBudget = budget
                reachedStrip = true
                break
            }
        }
        XCTAssertTrue(reachedStrip)
        let expanded = plan(presentation, budget: stripBudget, expanded: [.strip])
        XCTAssertTrue(expanded.stripGroupIDs.isEmpty)
        XCTAssertFalse(expanded.rows.contains(where: { $0.kind == .strip }))
        XCTAssertTrue(expanded.rows.contains(where: { $0.kind == .groupOneRow }))
    }

    // MARK: - Strip bound, overflow, determinism

    func testStripFallsBackToFullStripHeight() {
        let presentation = standardPresentation()
        var heights = uniformHeights(presentation, height: 1)
        heights[presentation.stripFullRow.key] = 500
        let result = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: heights,
            budget: 30
        )
        XCTAssertFalse(result.stripGroupIDs.isEmpty)
        XCTAssertTrue(result.overflows)
        XCTAssertGreaterThanOrEqual(result.totalHeight, 500)
    }

    func testEmptyDaysRenderOneStateLine() {
        let snapshot = CaptureAgendaSnapshot(
            ok: true,
            schemaVersion: 1,
            date: today,
            completedSummary: CaptureAgendaCompletedSummary(),
            pomodoros: [],
            warnings: []
        )
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            locale: locale
        )
        let heights = uniformHeights(presentation, height: 10)
        let result = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: heights,
            budget: 1_000
        )
        XCTAssertFalse(result.overflows)
        XCTAssertEqual(result.rows.map(\.kind), [.title, .stateLine])
        XCTAssertEqual(result.hiddenCount, 0)
    }

    func testEmptyBudgetRowPrecedesThePlannedPomodoroLine() {
        let presentation = makePresentation(
            entries: [],
            planBudget: CapturePlanBudget(
                status: "ok",
                themes: CapturePlanBudgetMeter(count: 0, cap: 3, over: false),
                links: CapturePlanBudgetMeter(count: 0, cap: 10, over: false)
            )
        )
        let result = plan(presentation, budget: 1_000)

        XCTAssertEqual(result.rows.map(\.kind), [.title, .planBudget, .stateLine])
        XCTAssertEqual(result.hiddenCount, 0)
    }

    func testBudgetRowStaysOutsideFoldingAndContentCounts() throws {
        let budget = CapturePlanBudget(
            status: "ok",
            themes: CapturePlanBudgetMeter(count: 3, cap: 3, over: false),
            links: CapturePlanBudgetMeter(count: 8, cap: 10, over: false)
        )
        let baseline = standardPresentation()
        let withBudget = standardPresentation(planBudget: budget)
        let budgetRow = try XCTUnwrap(withBudget.planBudgetRow)
        let budgetRowHeight = 27.0
        var heights = uniformHeights(withBudget)
        heights[budgetRow.key] = budgetRowHeight

        let baselinePlan = plan(baseline, budget: 1)
        let budgetPlan = plan(withBudget, heights: heights, budget: 1 + budgetRowHeight)

        XCTAssertEqual(budgetPlan.rows.prefix(2).map(\.kind), [.title, .planBudget])
        XCTAssertEqual(budgetPlan.rows.filter { $0.kind == .planBudget }.count, 1)
        XCTAssertEqual(budgetPlan.rows.filter { $0.kind != .planBudget }, baselinePlan.rows)
        XCTAssertEqual(budgetPlan.groupStates, baselinePlan.groupStates)
        XCTAssertEqual(budgetPlan.taskStates, baselinePlan.taskStates)
        XCTAssertEqual(budgetPlan.hiddenCount, baselinePlan.hiddenCount)
        XCTAssertEqual(budgetPlan.totalHeight, baselinePlan.totalHeight + budgetRowHeight)
        XCTAssertTrue(budgetPlan.overflows)

        for fitBudget in stride(from: 1.0, through: 500.0, by: 10.0) {
            let step = plan(withBudget, budget: fitBudget)
            XCTAssertEqual(step.rows.filter { $0.kind == .planBudget }.count, 1)
        }
    }

    func testIdenticalInputsPlanIdentically() {
        let presentation = standardPresentation()
        let heights = uniformHeights(presentation)
        let first = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: heights,
            budget: 200
        )
        let second = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: heights,
            budget: 200
        )
        XCTAssertEqual(first, second)
    }

    // MARK: - Acceptance fits

    /// The report's row-height model: 19 pt per row, 15 pt per extra
    /// wrapped line, about 105 characters per line; the strip never
    /// exceeds 3 lines.
    private func acceptanceHeights(
        _ presentation: CaptureAgendaPresentation
    ) -> [CaptureAgendaRowKey: Double] {
        var heights: [CaptureAgendaRowKey: Double] = [:]
        func add(_ row: CaptureAgendaRow) {
            let limit = row.kind == .strip ? 3 : row.lineLimit
            let unwrapped = max(1, (row.text.count + 104) / 105)
            let lines = min(limit, unwrapped)
            heights[row.key] = 19 + 15 * Double(lines - 1)
        }
        add(presentation.titleRow)
        if let planBudget = presentation.planBudgetRow {
            add(planBudget)
        }
        if let warning = presentation.warningRow {
            add(warning)
        }
        for group in presentation.groups {
            add(group.headerRow)
            for note in group.sessionNoteRows {
                add(note)
            }
            for task in group.tasks {
                for row in task.fullRows {
                    add(row)
                }
                for row in task.noLogsRows {
                    add(row)
                }
                add(task.oneLineRow)
            }
            if let retired = group.retiredRow {
                add(retired)
            }
            if let empty = group.emptyRow {
                add(empty)
            }
            add(group.oneRowRow)
        }
        add(presentation.stripFullRow)
        return heights
    }

    private func acceptanceFixture(_ name: String) throws -> CaptureAgendaPresentation {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(CaptureAgendaSnapshot.self, from: data)
        return CaptureAgendaPresentation(snapshot: snapshot, today: "2026-08-28", locale: locale)
    }

    func testAcceptanceFixturesFitBothBudgets() throws {
        for name in ["agenda-current.json", "agenda-heavy.json"] {
            let presentation = try acceptanceFixture(name)
            let heights = acceptanceHeights(presentation)
            for budget in [467.0, 533.0] {
                let result = CaptureAgendaFitPlanner.plan(
                    presentation: presentation,
                    heights: heights,
                    budget: budget
                )
                XCTAssertFalse(result.overflows, "\(name) at \(budget) pt")
                XCTAssertLessThanOrEqual(result.totalHeight, budget, "\(name) at \(budget) pt")
            }
        }
    }

    func testHeavyDayKeepsNowAndNextDetailed() throws {
        let presentation = try acceptanceFixture("agenda-heavy.json")
        let heights = acceptanceHeights(presentation)
        let result = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: heights,
            budget: 533
        )
        XCTAssertFalse(result.overflows)
        for group in presentation.groups {
            guard group.role == .current || group.role == .next else {
                continue
            }
            let state = result.groupStates[group.id] ?? .full
            XCTAssertTrue(state == .full || state == .noLogs, "\(group.name) is \(state)")
        }
    }
}
