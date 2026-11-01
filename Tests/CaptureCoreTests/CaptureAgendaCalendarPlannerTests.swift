import XCTest

@testable import CaptureCore

final class CaptureAgendaCalendarPlannerTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let today = "2026-08-28"

    // MARK: - Builders

    private func makeItem(ledgerLine: Int, blockID: String) -> CaptureAgendaItem {
        CaptureAgendaItem(
            index: 1,
            ledgerLine: ledgerLine,
            ledgerDepth: 1,
            marker: .plain,
            blockLink: "[[tasks#^\(blockID)]]",
            resolution: .resolved,
            relativeTarget: "tasks",
            line: 1,
            blockID: blockID,
            text: blockID,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            lines: [],
            linesTruncated: 0,
            ledgerNotes: [],
            warning: nil
        )
    }

    private func makeEntry(
        line: Int,
        name: String,
        role: CaptureAgendaRole
    ) -> CaptureAgendaPomodoro {
        CaptureAgendaPomodoro(
            line: line,
            name: name,
            isCurrent: role == .current,
            taskLinkCount: 1,
            role: role,
            startsAt: role == .current ? "\(today)T08:00" : nil,
            endsAt: role == .current ? "\(today)T08:30" : nil,
            retiredLinkCount: 0,
            notes: [],
            items: [makeItem(ledgerLine: line + 1, blockID: "task-\(line)")],
            slug: name.lowercased(),
            selectable: true
        )
    }

    private func makeEventRow(
        line: Int,
        title: String,
        phase: CaptureAgendaEventPhase? = .upcoming
    ) -> CaptureAgendaEventRow {
        CaptureAgendaEventRow(
            line: line,
            kind: .task,
            title: title,
            startsAt: "\(today)T09:30",
            endsAt: "\(today)T10:00",
            durationMinutes: 30,
            phase: phase
        )
    }

    private func makePresentation(
        entries: [CaptureAgendaPomodoro],
        eventRows: [CaptureAgendaEventRow]? = nil
    ) -> CaptureAgendaPresentation {
        let events = eventRows.map {
            CaptureAgendaEvents(
                syncedAt: "\(today)T08:02",
                rows: $0,
                focus: $0.isEmpty ? nil : 0,
                refreshAt: "\(today)T09:30"
            )
        }
        let snapshot = CaptureAgendaSnapshot(
            ok: true,
            schemaVersion: 1,
            date: today,
            completedSummary: CaptureAgendaCompletedSummary(),
            pomodoros: entries,
            warnings: [],
            planBudget: nil,
            events: events
        )
        return CaptureAgendaPresentation(snapshot: snapshot, today: today, locale: locale)
    }

    private func standardEntries() -> [CaptureAgendaPomodoro] {
        [
            makeEntry(line: 3, name: "NOW", role: .current),
            makeEntry(line: 10, name: "NEXT", role: .next),
            makeEntry(line: 20, name: "LATER-A", role: .later),
            makeEntry(line: 30, name: "LATER-B", role: .later),
        ]
    }

    private func eventRows() -> [CaptureAgendaEventRow] {
        [makeEventRow(line: 7, title: "Standup")]
    }

    // MARK: - Placement

    func testCalendarSitsBetweenNowAndNextGroups() {
        let presentation = makePresentation(
            entries: standardEntries(),
            eventRows: eventRows()
        )
        let plan = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: [:],
            budget: 10_000
        )
        XCTAssertEqual(plan.calendarState, .full)
        let kinds = plan.rows.map(\.kind)
        guard let headerIndex = kinds.firstIndex(of: .calendarHeader),
            let nowHeader = kinds.firstIndex(of: .groupHeader),
            let nextHeader = kinds.dropFirst(headerIndex + 1).firstIndex(of: .groupHeader)
        else {
            XCTFail("expected Now groups, the calendar band, and a Next group")
            return
        }
        XCTAssertLessThan(nowHeader, headerIndex)
        XCTAssertLessThan(headerIndex, nextHeader)
    }

    func testCalendarFollowsTitleRowsWhenNothingRuns() {
        let presentation = makePresentation(
            entries: [makeEntry(line: 10, name: "NEXT", role: .next)],
            eventRows: eventRows()
        )
        let plan = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: [:],
            budget: 10_000
        )
        let kinds = plan.rows.map(\.kind)
        XCTAssertEqual(kinds.first, .title)
        XCTAssertEqual(kinds.dropFirst().first, .calendarHeader)
    }

    // MARK: - Ladder

    func testLadderFoldsBandAfterLaterOneRowBeforeStrip() {
        let presentation = makePresentation(
            entries: standardEntries(),
            eventRows: eventRows()
        )
        let groups = presentation.groups
        let steps = CaptureAgendaFitPlanner.ladder(groups: groups, hasCalendar: true)
        func position(_ step: CaptureAgendaFitPlanner.Step) -> Int? {
            steps.firstIndex(of: step)
        }
        let laterIndices = groups.indices.filter { groups[$0].role == .later }
        let lastLaterOneRow = laterIndices.map {
            CaptureAgendaFitPlanner.Step.group(groupIndex: $0, target: .oneRow)
        }.compactMap(position).max()
        let firstLaterStrip = laterIndices.map {
            CaptureAgendaFitPlanner.Step.group(groupIndex: $0, target: .inStrip)
        }.compactMap(position).min()
        let bandCompact = position(.calendar(.compact))
        XCTAssertNotNil(lastLaterOneRow)
        XCTAssertNotNil(firstLaterStrip)
        XCTAssertNotNil(bandCompact)
        XCTAssertLessThan(lastLaterOneRow ?? 0, bandCompact ?? 0)
        XCTAssertLessThan(bandCompact ?? 0, firstLaterStrip ?? 0)
    }

    func testLadderFoldsBandToOneRowAfterNextBeforeNow() {
        let presentation = makePresentation(
            entries: standardEntries(),
            eventRows: eventRows()
        )
        let groups = presentation.groups
        let steps = CaptureAgendaFitPlanner.ladder(groups: groups, hasCalendar: true)
        func position(_ step: CaptureAgendaFitPlanner.Step) -> Int? {
            steps.firstIndex(of: step)
        }
        let nextIndices = groups.indices.filter { groups[$0].role == .next }
        let nowOpenIndices = groups.indices.filter {
            groups[$0].role == .current || groups[$0].role == .open
        }
        let lastNextFold = nextIndices.map {
            CaptureAgendaFitPlanner.Step.group(groupIndex: $0, target: .oneLineTasks)
        }.compactMap(position).max()
        let firstNowFold = nowOpenIndices.map {
            CaptureAgendaFitPlanner.Step.group(groupIndex: $0, target: .oneLineTasks)
        }.compactMap(position).min()
        let bandOneRow = position(.calendar(.oneRow))
        XCTAssertNotNil(lastNextFold)
        XCTAssertNotNil(firstNowFold)
        XCTAssertNotNil(bandOneRow)
        XCTAssertLessThan(lastNextFold ?? 0, bandOneRow ?? 0)
        XCTAssertLessThan(bandOneRow ?? 0, firstNowFold ?? 0)
    }

    func testLadderOmitsBandStepsWithoutEvents() {
        let presentation = makePresentation(entries: standardEntries(), eventRows: nil)
        let steps = CaptureAgendaFitPlanner.ladder(
            groups: presentation.groups,
            hasCalendar: false
        )
        XCTAssertFalse(steps.contains(.calendar(.compact)))
        XCTAssertFalse(steps.contains(.calendar(.oneRow)))
    }

    func testExpandedBandPinsAtFull() {
        let presentation = makePresentation(
            entries: standardEntries(),
            eventRows: eventRows()
        )
        let plan = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: [:],
            budget: 0,
            expanded: [.calendar]
        )
        XCTAssertEqual(plan.calendarState, .full)
        XCTAssertTrue(plan.overflows)
        XCTAssertTrue(plan.rows.contains(where: { $0.kind == .calendarRow }))
    }

    func testBandNeverHidesUnderPressure() {
        let presentation = makePresentation(
            entries: standardEntries(),
            eventRows: eventRows()
        )
        let plan = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: [:],
            budget: 0
        )
        XCTAssertTrue(plan.overflows)
        // The band folds to one row but never away: the header is
        // still in the render list.
        XCTAssertEqual(plan.calendarState, .oneRow)
        XCTAssertTrue(plan.rows.contains(where: { $0.kind == .calendarHeader }))
    }

    func testEarlierExpansionRevealsEndedRows() {
        let rows = [
            makeEventRow(line: 5, title: "Done standup", phase: .ended),
            makeEventRow(line: 7, title: "Standup"),
        ]
        let presentation = makePresentation(entries: standardEntries(), eventRows: rows)
        let folded = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: [:],
            budget: 10_000
        )
        XCTAssertEqual(
            folded.rows.filter({ $0.kind == .calendarRow }).count,
            1
        )
        let expanded = CaptureAgendaFitPlanner.plan(
            presentation: presentation,
            heights: [:],
            budget: 10_000,
            expanded: [.calendarEarlier]
        )
        XCTAssertEqual(
            expanded.rows.filter({ $0.kind == .calendarRow }).count,
            2
        )
    }
}
