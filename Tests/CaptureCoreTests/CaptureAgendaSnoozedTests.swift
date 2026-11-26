import XCTest

@testable import CaptureCore

final class CaptureAgendaSnoozedTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let today = "2026-08-28"

    // MARK: - Builders

    private func makeSnoozedRow(
        title: String = "Fix the sink",
        route: String = "tasks.md",
        blockID: String = "sink",
        target: String = "1900",
        wakeAt: String? = "2026-08-28T19:00:00-04:00",
        state: CaptureAgendaSnoozedState = .asleep
    ) -> CaptureAgendaSnoozedRow {
        CaptureAgendaSnoozedRow(
            title: title,
            route: route,
            blockID: blockID,
            target: target,
            wakeAt: wakeAt,
            state: state,
            notes: []
        )
    }

    private func makeSnoozed(
        rows: [CaptureAgendaSnoozedRow],
        nextWakeAt: String? = "2026-08-28T19:00:00-04:00"
    ) -> CaptureAgendaSnoozed {
        CaptureAgendaSnoozed(nextWakeAt: nextWakeAt, rows: rows)
    }

    private func makeItem(
        ledgerLine: Int,
        blockID: String = "block",
        text: String? = "Task title",
        wokeAt: String? = nil,
        snoozedTarget: String? = nil
    ) -> CaptureAgendaItem {
        CaptureAgendaItem(
            index: 1,
            ledgerLine: ledgerLine,
            ledgerDepth: 1,
            marker: .plain,
            blockLink: "[[tasks.md#^\(blockID)]]",
            resolution: .resolved,
            relativeTarget: "tasks.md",
            line: 1,
            blockID: blockID,
            text: text,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            lines: [],
            linesTruncated: 0,
            ledgerNotes: [],
            warning: nil,
            wokeAt: wokeAt,
            snoozedTarget: snoozedTarget
        )
    }

    private func makeEntry(
        line: Int,
        name: String = "FIX",
        role: CaptureAgendaRole = .current,
        items: [CaptureAgendaItem] = []
    ) -> CaptureAgendaPomodoro {
        CaptureAgendaPomodoro(
            line: line,
            name: name,
            isCurrent: role == .current,
            taskLinkCount: items.count,
            role: role,
            startsAt: "2026-08-28T08:00",
            endsAt: "2026-08-28T08:30",
            retiredLinkCount: 0,
            notes: [],
            items: items,
            slug: name.lowercased(),
            selectable: true
        )
    }

    private func makeSnapshot(
        date: String? = "2026-08-28",
        entries: [CaptureAgendaPomodoro] = [],
        snoozed: CaptureAgendaSnoozed? = nil,
        planBudget: CapturePlanBudget? = nil
    ) -> CaptureAgendaSnapshot {
        CaptureAgendaSnapshot(
            ok: true,
            schemaVersion: 1,
            date: date,
            completedSummary: CaptureAgendaCompletedSummary(),
            pomodoros: entries,
            warnings: [],
            planBudget: planBudget,
            headline: nil,
            snoozed: snoozed
        )
    }

    private func dateAt(_ clock: String) -> Date {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter.date(from: "2026-08-28 \(clock)") ?? Date()
    }

    private func isoAt(_ iso: String) -> Date {
        guard let date = CaptureAgendaPresentation.parseSnoozedWakeAt(iso) else {
            preconditionFailure("invalid ISO test instant: \(iso)")
        }
        return date
    }

    private func uniformHeights(
        _ presentation: CaptureAgendaPresentation,
        height: Double = 10
    ) -> [CaptureAgendaRowKey: Double] {
        var heights: [CaptureAgendaRowKey: Double] = [:]
        func add(_ row: CaptureAgendaRow) {
            heights[row.key] = height
        }
        add(presentation.titleRow)
        if let headline = presentation.headlineRow {
            add(headline)
        }
        if let planBudget = presentation.planBudgetRow {
            add(planBudget)
        }
        if let warning = presentation.warningRow {
            add(warning)
        }
        if let stateRow = presentation.stateRow {
            add(stateRow)
        }
        if let calendar = presentation.calendar {
            for row in calendar.allRows {
                add(row)
            }
        }
        if let snoozed = presentation.snoozed {
            for row in snoozed.allRows {
                add(row)
            }
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

    // MARK: - Band construction

    func testSnoozedOnlySnapshotShowsBandWithoutBudgetOrGroups() {
        let snoozed = makeSnoozed(rows: [
            makeSnoozedRow(title: "Later work", target: "1530", wakeAt: "2026-08-28T15:30:00-04:00"),
        ])
        let snapshot = makeSnapshot(entries: [], snoozed: snoozed)
        let now = dateAt("12:00")
        let presentation = CaptureAgendaPresentation(snapshot: snapshot, today: today, now: now)
        XCTAssertEqual(presentation.state, .noOpen)
        XCTAssertNotNil(presentation.snoozed)
        XCTAssertEqual(presentation.snoozed?.count, 1)
        XCTAssertEqual(presentation.snoozed?.headerRow.text, "Later today")
        XCTAssertEqual(presentation.snoozed?.rows.count, 1)
        XCTAssertTrue(presentation.snoozedNeedsTick)
    }

    func testPriorDaySnapshotHidesBand() {
        let snoozed = makeSnoozed(rows: [makeSnoozedRow()])
        let snapshot = makeSnapshot(date: "2026-08-27", entries: [], snoozed: snoozed)
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: dateAt("12:00")
        )
        XCTAssertEqual(presentation.state, .loading)
        XCTAssertNil(presentation.snoozed)
        XCTAssertFalse(presentation.snoozedNeedsTick)
    }

    func testOldBobWithoutSnoozedHasNoBand() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/agenda-current.json")
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(CaptureAgendaSnapshot.self, from: data)
        XCTAssertNil(snapshot.snoozed)
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: "2026-08-28",
            now: dateAt("12:00")
        )
        XCTAssertNil(presentation.snoozed)
        XCTAssertFalse(presentation.snoozedNeedsTick)
        XCTAssertNil(presentation.snoozed?.count)
    }

    func testSnoozedFixtureBuildsBandWithThreeRows() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/agenda-snoozed.json")
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(CaptureAgendaSnapshot.self, from: data)
        XCTAssertEqual(snapshot.snoozed?.rows.count, 3)
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: "2026-08-28",
            now: dateAt("12:00"),
            locale: locale
        )
        XCTAssertNotNil(presentation.snoozed)
        XCTAssertEqual(presentation.snoozed?.rows.count, 3)
        let rows = presentation.snoozed?.rows ?? []
        XCTAssertEqual(rows[0].snoozed?.state, .due)
        XCTAssertEqual(rows[0].snoozed?.trailingText, "due · waking")
        XCTAssertEqual(rows[1].snoozed?.state, .asleep)
        XCTAssertNotNil(rows[1].snoozed?.countdownText)
        XCTAssertEqual(rows[2].snoozed?.state, .blocked)
        XCTAssertEqual(rows[2].snoozed?.trailingText, "waits on prerequisites")
    }

    func testNullableTimesStayNeutral() {
        let row = makeSnoozedRow(target: "1900", wakeAt: nil, state: .asleep)
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(snoozed: makeSnoozed(rows: [row])),
            today: today,
            now: dateAt("12:00")
        )
        let built = presentation.snoozed?.rows.first
        XCTAssertEqual(built?.snoozed?.timeText, "19:00")
        XCTAssertNil(built?.snoozed?.countdownText)
    }

    func testInvalidTargetStaysNeutral() {
        let row = makeSnoozedRow(target: "99ab", wakeAt: "2026-08-28T19:00:00-04:00")
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(snoozed: makeSnoozed(rows: [row])),
            today: today,
            now: dateAt("12:00")
        )
        XCTAssertEqual(presentation.snoozed?.rows.first?.snoozed?.timeText, "")
    }

    func testUnknownStateStaysNeutral() {
        let row = CaptureAgendaSnoozedRow(
            title: "Mystery",
            route: "tasks.md",
            blockID: "myst",
            target: "1900",
            wakeAt: "2026-08-28T19:00:00-04:00",
            state: .other("someday"),
            notes: []
        )
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(snoozed: makeSnoozed(rows: [row])),
            today: today,
            now: dateAt("12:00")
        )
        let built = presentation.snoozed?.rows.first
        XCTAssertEqual(built?.snoozed?.state, .other("someday"))
        XCTAssertNil(built?.snoozed?.countdownText)
        XCTAssertNil(built?.snoozed?.trailingText)
    }

    // MARK: - Summary

    func testSummaryShowsCountAndNextTime() {
        let snoozed = makeSnoozed(
            rows: [makeSnoozedRow(), makeSnoozedRow(title: "Second", target: "2000")],
            nextWakeAt: "2026-08-28T19:00:00-04:00"
        )
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(snoozed: snoozed),
            today: today,
            now: dateAt("12:00")
        )
        XCTAssertEqual(presentation.snoozed?.summaryRow.text, "2 later · next 19:00")
        XCTAssertEqual(presentation.snoozed?.summaryRow.kind, .snoozedSummary)
    }

    func testBlockedOnlySummaryOmitsNextWake() {
        let rows = [
            makeSnoozedRow(title: "One", target: "1900", state: .blocked),
            makeSnoozedRow(title: "Two", target: "2000", state: .blocked),
        ]
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(snoozed: makeSnoozed(rows: rows, nextWakeAt: nil)),
            today: today,
            now: dateAt("12:00")
        )
        XCTAssertEqual(presentation.snoozed?.summaryRow.text, "2 later · blocked")
    }

    // MARK: - Folding

    func testSnoozeFoldsFirstBeforeGroups() {
        let entry = makeEntry(line: 3, role: .later, items: [makeItem(ledgerLine: 4)])
        let snoozed = makeSnoozed(rows: [makeSnoozedRow()])
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(entries: [entry], snoozed: snoozed),
            today: today,
            now: dateAt("12:00")
        )
        let full = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: uniformHeights(presentation),
            budget: 100_000
        )
        XCTAssertEqual(full.snoozedState, .full)
        let folded = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: uniformHeights(presentation),
            budget: full.totalHeight - 1
        )
        XCTAssertEqual(folded.snoozedState, .summary)
        XCTAssertTrue(folded.rows.contains { $0.kind == .snoozedSummary })
        XCTAssertFalse(folded.rows.contains { $0.kind == .snoozedRow })
    }

    func testSummaryPersistsAtTinyBudgets() {
        let entry = makeEntry(line: 3, role: .later, items: [makeItem(ledgerLine: 4)])
        let snoozed = makeSnoozed(rows: [makeSnoozedRow()])
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(entries: [entry], snoozed: snoozed),
            today: today,
            now: dateAt("12:00")
        )
        let result = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: uniformHeights(presentation),
            budget: 1
        )
        XCTAssertTrue(result.rows.contains { $0.kind == .snoozedSummary })
        XCTAssertEqual(result.snoozedState, .summary)
    }

    func testExpandedSnoozedPinsAtFull() {
        let entry = makeEntry(line: 3, role: .later, items: [makeItem(ledgerLine: 4)])
        let snoozed = makeSnoozed(rows: [makeSnoozedRow()])
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(entries: [entry], snoozed: snoozed),
            today: today,
            now: dateAt("12:00")
        )
        let result = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: uniformHeights(presentation),
            budget: 1,
            expanded: [.snoozed]
        )
        XCTAssertTrue(result.rows.contains { $0.kind == .snoozedRow })
        XCTAssertFalse(result.rows.contains { $0.kind == .snoozedSummary })
    }

    func testBandRendersAfterStrip() {
        let near = makeEntry(line: 20, name: "NEAR", role: .later, items: [makeItem(ledgerLine: 21)])
        let far = makeEntry(line: 30, name: "FAR", role: .later, items: [makeItem(ledgerLine: 31)])
        let snoozed = makeSnoozed(rows: [makeSnoozedRow()])
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(entries: [near, far], snoozed: snoozed),
            today: today,
            now: dateAt("12:00")
        )
        var budget = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: uniformHeights(presentation),
            budget: 100_000
        ).totalHeight
        var sawStripWithBandAfter = false
        while budget > 0 {
            budget -= 10
            let result = CaptureAgendaFitPlanner.plan(
                presentation: presentation,
                heights: uniformHeights(presentation),
                budget: budget
            )
            guard result.stripGroupIDs.count == 2 else {
                continue
            }
            let stripIndex = result.rows.firstIndex { $0.kind == .strip }
            let snoozedIndex = result.rows.firstIndex {
                $0.kind == .snoozedHeader || $0.kind == .snoozedSummary
            }
            if let strip = stripIndex, let snoozedAt = snoozedIndex, snoozedAt > strip {
                sawStripWithBandAfter = true
                break
            }
        }
        XCTAssertTrue(sawStripWithBandAfter)
    }

    // MARK: - Budget

    func testBudgetAppendsSeparateAlarmCount() {
        let budget = CapturePlanBudget(
            status: "ok",
            links: CapturePlanBudgetMeter(count: 3, cap: 10, over: false),
            warnings: []
        )
        let snoozed = makeSnoozed(rows: [
            makeSnoozedRow(state: .asleep),
            makeSnoozedRow(title: "Due", state: .due),
            makeSnoozedRow(title: "Blocked", state: .blocked),
        ])
        let snapshot = makeSnapshot(
            entries: [makeEntry(line: 3, items: [makeItem(ledgerLine: 4)])],
            snoozed: snoozed,
            planBudget: budget
        )
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: dateAt("12:00")
        )
        XCTAssertEqual(presentation.planBudgetRow?.text, "TODAY 3/10 · alarm 3")
        XCTAssertEqual(presentation.planBudgetRow?.planBudget?.today.text, "TODAY 3/10")
        XCTAssertEqual(presentation.planBudgetRow?.planBudget?.snoozedCount, 3)
    }

    func testSnoozedOnlyWithoutBudgetHasBandButNoCap() {
        let snoozed = makeSnoozed(rows: [makeSnoozedRow()])
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(entries: [], snoozed: snoozed),
            today: today,
            now: dateAt("12:00")
        )
        XCTAssertNotNil(presentation.snoozed)
        XCTAssertNil(presentation.planBudgetRow)
    }

    // MARK: - Woke accents

    func testWokeAccentAppearsInsideSixtyMinutes() {
        let item = makeItem(ledgerLine: 5, wokeAt: "15:32", snoozedTarget: "1530")
        let entry = makeEntry(line: 3, items: [item])
        let snapshot = makeSnapshot(entries: [entry])
        let now = dateAt("15:45")
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: now
        )
        let task = presentation.groups.first?.tasks.first
        XCTAssertEqual(task?.fullRows.first?.woke?.timeText, "15:32")
        XCTAssertTrue(presentation.hasActiveWokeAccent)
        XCTAssertTrue(presentation.snoozedNeedsTick)
    }

    func testWokeAccentExpiresAtSixtyMinutes() {
        let item = makeItem(ledgerLine: 5, wokeAt: "15:32", snoozedTarget: "1530")
        let entry = makeEntry(line: 3, items: [item])
        let snapshot = makeSnapshot(entries: [entry])
        let now = dateAt("16:32")
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: now
        )
        let task = presentation.groups.first?.tasks.first
        XCTAssertNil(task?.fullRows.first?.woke)
        XCTAssertFalse(presentation.hasActiveWokeAccent)
    }

    func testWokeAccentJustBeforeExpiry() {
        let item = makeItem(ledgerLine: 5, wokeAt: "15:32", snoozedTarget: "1530")
        let entry = makeEntry(line: 3, items: [item])
        let snapshot = makeSnapshot(entries: [entry])
        let now = dateAt("16:31")
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: now
        )
        XCTAssertNotNil(presentation.groups.first?.tasks.first?.fullRows.first?.woke)
    }

    func testFutureWokeNeverAccents() {
        let item = makeItem(ledgerLine: 5, wokeAt: "16:00", snoozedTarget: "1600")
        let entry = makeEntry(line: 3, items: [item])
        let snapshot = makeSnapshot(entries: [entry])
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: dateAt("15:00")
        )
        XCTAssertNil(presentation.groups.first?.tasks.first?.fullRows.first?.woke)
    }

    func testMalformedWokeNeverAccents() {
        let item = makeItem(ledgerLine: 5, wokeAt: "99:99", snoozedTarget: "9999")
        let entry = makeEntry(line: 3, items: [item])
        let snapshot = makeSnapshot(entries: [entry])
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: dateAt("15:00")
        )
        XCTAssertNil(presentation.groups.first?.tasks.first?.fullRows.first?.woke)
    }

    func testWokeAccentSurvivesOneLineFold() {
        let item = makeItem(ledgerLine: 5, wokeAt: "15:32", snoozedTarget: "1530")
        let entry = makeEntry(line: 3, items: [item])
        let snapshot = makeSnapshot(entries: [entry])
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: dateAt("15:45")
        )
        let task = presentation.groups.first?.tasks.first
        XCTAssertNotNil(task?.oneLineRow.woke)
        XCTAssertNotNil(task?.noLogsRows.first?.woke)
    }

    // MARK: - Countdowns

    func testAsleepCountdownAging() {
        let row = makeSnoozedRow(
            target: "1530",
            wakeAt: "2026-08-28T15:30:00-04:00",
            state: .asleep
        )
        let early = CaptureAgendaPresentation(
            snapshot: makeSnapshot(snoozed: makeSnoozed(rows: [row])),
            today: today,
            now: isoAt("2026-08-28T12:00:00-04:00")
        )
        XCTAssertEqual(early.snoozed?.rows.first?.snoozed?.countdownText, "in 3h 30m")
        let late = CaptureAgendaPresentation(
            snapshot: makeSnapshot(snoozed: makeSnoozed(rows: [row])),
            today: today,
            now: isoAt("2026-08-28T15:29:00-04:00")
        )
        XCTAssertEqual(late.snoozed?.rows.first?.snoozed?.countdownText, "now")
    }

    func testMinuteRepaintRunsForSnoozeWithoutPomodoroCountdown() {
        let snoozed = makeSnoozed(rows: [makeSnoozedRow()])
        let presentation = CaptureAgendaPresentation(
            snapshot: makeSnapshot(entries: [], snoozed: snoozed),
            today: today,
            now: dateAt("12:00")
        )
        XCTAssertFalse(presentation.hasLiveCountdown)
        XCTAssertFalse(presentation.calendarNeedsTick)
        XCTAssertTrue(presentation.snoozedNeedsTick)
    }
}
