import XCTest

@testable import CaptureCore

final class CaptureAgendaCalendarTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let today = "2026-08-28"

    // MARK: - Builders

    private func dateAt(_ raw: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: raw) ?? Date()
    }

    private func makeRow(
        line: Int,
        title: String,
        startsAt: String? = nil,
        endsAt: String? = nil,
        durationMinutes: Int? = 30,
        phase: CaptureAgendaEventPhase? = .upcoming,
        untracked: Bool = false,
        qualifier: String? = nil,
        hue: PomodoroHomeHue? = nil,
        joinURL: String? = nil
    ) -> CaptureAgendaEventRow {
        CaptureAgendaEventRow(
            line: line,
            blockID: "event-\(line)",
            kind: .task,
            qualifier: qualifier,
            title: title,
            timeRange: nil,
            startsAt: startsAt,
            endsAt: endsAt,
            durationMinutes: durationMinutes,
            phase: phase,
            statusSymbol: " ",
            statusType: "TODO",
            untracked: untracked,
            root: nil,
            home: hue.map { CaptureAgendaEventHome(label: "job", hue: $0) },
            joinURL: joinURL,
            calendarURL: nil,
            location: nil,
            pomodoro: nil
        )
    }

    private func makeEvents(
        rows: [CaptureAgendaEventRow],
        focus: Int? = 0,
        allDay: [CaptureAgendaAllDayContext] = [],
        gap: CaptureAgendaEventGap? = nil,
        conflict: CaptureAgendaEventConflict? = nil,
        startHint: String? = nil,
        syncedAt: String? = "2026-08-28T08:02",
        refreshAt: String? = "2026-08-28T09:30"
    ) -> CaptureAgendaEvents {
        CaptureAgendaEvents(
            syncedAt: syncedAt,
            allDay: allDay,
            rows: rows,
            focus: focus,
            gap: gap,
            conflict: conflict,
            startHint: startHint,
            refreshAt: refreshAt
        )
    }

    private func makeSnapshot(events: CaptureAgendaEvents?) -> CaptureAgendaSnapshot {
        CaptureAgendaSnapshot(
            ok: true,
            schemaVersion: 1,
            date: today,
            completedSummary: CaptureAgendaCompletedSummary(),
            pomodoros: [],
            warnings: [],
            planBudget: nil,
            events: events
        )
    }

    private func present(
        _ events: CaptureAgendaEvents?,
        now: Date? = nil
    ) -> CaptureAgendaPresentation {
        CaptureAgendaPresentation(
            snapshot: makeSnapshot(events: events),
            today: today,
            now: now,
            locale: locale
        )
    }

    private func fixture() throws -> CaptureAgendaSnapshot {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/agenda-events.json")
        return try JSONDecoder().decode(CaptureAgendaSnapshot.self, from: Data(contentsOf: url))
    }

    // MARK: - Fixture band

    func testFixtureBuildsBandAfterNowGroups() throws {
        let snapshot = try fixture()
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: dateAt("2026-08-28T08:52"),
            locale: locale
        )
        let calendar = try XCTUnwrap(presentation.calendar)
        XCTAssertTrue(presentation.calendarNeedsTick)

        // "Standup at 09:30 · in 38m", "3 left · 2h 00m · ↻ 08:02".
        XCTAssertEqual(calendar.headerRow.kind, .calendarHeader)
        XCTAssertEqual(calendar.headerRow.text, "Standup at 09:30 · in 38m")
        XCTAssertEqual(
            calendar.headerRow.accessoryText,
            "3 left · 2h 00m · ↻ 08:02"
        )

        XCTAssertEqual(calendar.allDayRow?.text, "School holiday (day 2 of 3)")
        XCTAssertNil(calendar.gapRow)
        XCTAssertEqual(calendar.conflictRow?.text, "BOB runs 10m into Standup")
        XCTAssertEqual(calendar.upcomingRows.count, 3)
        XCTAssertTrue(calendar.endedRows.isEmpty)
        XCTAssertNil(calendar.expandEarlierRow)
        // Two rows hidden behind the compact chip (Class, Lunch).
        XCTAssertEqual(calendar.expandAllRow?.text, "+2")
        XCTAssertNil(calendar.clearRow)
        XCTAssertEqual(calendar.refreshAt, "2026-08-28T09:30")
        XCTAssertEqual(calendar.focusJoinURL, "https://meet.google.com/abc")

        let focus = try XCTUnwrap(calendar.focusRow)
        XCTAssertEqual(focus.text, "Standup")
        XCTAssertEqual(focus.calendar?.timeText, "09:30–10:00")
        XCTAssertEqual(focus.calendar?.countdownText, "in 38m")
        XCTAssertEqual(focus.calendar?.startHint, "=meet")
        XCTAssertEqual(focus.calendar?.joinURL, "https://meet.google.com/abc")
        XCTAssertEqual(focus.calendar?.hue, .green)
        XCTAssertFalse(focus.calendar?.untracked ?? true)

        let lunch = calendar.upcomingRows[2]
        XCTAssertEqual(lunch.calendar?.untracked, true)
        let timeless = calendar.upcomingRows[1]
        XCTAssertEqual(timeless.calendar?.dimmed, true)

        XCTAssertEqual(
            calendar.oneRowRow.text,
            "Standup at 09:30 · in 38m · then Class meeting 11:00 · +1"
        )
    }

    func testFixtureFullRowsOrder() throws {
        let snapshot = try fixture()
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: dateAt("2026-08-28T08:52"),
            locale: locale
        )
        let calendar = try XCTUnwrap(presentation.calendar)
        let kinds = calendar.fullRows(showEnded: false).map(\.kind)
        XCTAssertEqual(kinds, [
            .calendarHeader, .calendarAllDay, .calendarRail, .calendarConflict,
            .calendarRow, .calendarRow, .calendarRow,
        ])
    }

    // MARK: - Folds and expansion

    func testEndedRowsHideBehindEarlierChip() {
        let events = makeEvents(rows: [
            makeRow(line: 5, title: "Done standup", startsAt: "2026-08-28T08:00",
                endsAt: "2026-08-28T08:30", phase: .ended),
            makeRow(line: 7, title: "Standup", startsAt: "2026-08-28T09:30",
                endsAt: "2026-08-28T10:00", joinURL: "https://meet.example/j")
        ], focus: 1)
        let presentation = present(events, now: dateAt("2026-08-28T08:52"))
        guard let band = presentation.calendar else {
            XCTFail("expected a calendar band")
            return
        }
        XCTAssertEqual(band.earlierCount, 1)
        XCTAssertEqual(band.expandEarlierRow?.text, "+1 earlier")
        XCTAssertEqual(band.fullRows(showEnded: false).filter({ $0.kind == .calendarRow }).count, 1)
        XCTAssertEqual(band.fullRows(showEnded: true).filter({ $0.kind == .calendarRow }).count, 2)
        // Compact hides the one non-focus row behind "+1".
        XCTAssertEqual(band.expandAllRow?.text, "+1")
        XCTAssertEqual(band.oneRowRow.text, "Standup at 09:30 · in 38m · +1")
        XCTAssertEqual(band.focusJoinURL, "https://meet.example/j")
    }

    func testClearBandWhenEveryEventEnded() {
        let events = makeEvents(
            rows: [
                makeRow(line: 5, title: "Done standup", startsAt: "2026-08-28T08:00",
                    endsAt: "2026-08-28T08:30", phase: .ended),
            ],
            focus: nil
        )
        let presentation = present(events, now: dateAt("2026-08-28T18:00"))
        let calendar = presentation.calendar
        XCTAssertNotNil(calendar)
        XCTAssertEqual(
            calendar?.clearRow?.text,
            "Calendar clear for the rest of the day · ↻ 08:02"
        )
        XCTAssertEqual(calendar?.headerRow.text, "Calendar")
        XCTAssertFalse(presentation.calendarNeedsTick)
        XCTAssertEqual(
            calendar?.fullRows(showEnded: false).map(\.kind),
            [.calendarHeader, .calendarClear]
        )
    }

    func testNoBandWithoutEvents() {
        XCTAssertNil(present(nil).calendar)
        let empty = makeEvents(rows: [], focus: nil)
        XCTAssertNil(present(empty).calendar)
    }

    func testStampShowsWeekdayFromAnotherDay() {
        let events = makeEvents(
            rows: [
                makeRow(line: 7, title: "Standup", startsAt: "2026-08-28T09:30",
                    endsAt: "2026-08-28T10:00"),
            ],
            syncedAt: "2026-08-27T08:02"
        )
        let presentation = present(events, now: dateAt("2026-08-28T08:52"))
        XCTAssertEqual(
            presentation.calendar?.headerRow.accessoryText,
            "1 left · 30m · ↻ Thu 08:02"
        )
    }

    func testGapRowTextWithAndWithoutFit() {
        let events = makeEvents(
            rows: [
                makeRow(line: 7, title: "Standup", startsAt: "2026-08-28T09:30",
                    endsAt: "2026-08-28T10:00"),
            ],
            gap: CaptureAgendaEventGap(from: "08:52", until: "09:30", minutes: 38, fits: "=7")
        )
        let presentation = present(events, now: dateAt("2026-08-28T08:52"))
        XCTAssertEqual(presentation.calendar?.gapRow?.text, "38m free · =7 fits")

        let bare = makeEvents(
            rows: [
                makeRow(line: 7, title: "Standup", startsAt: "2026-08-28T09:30",
                    endsAt: "2026-08-28T10:00"),
            ],
            gap: CaptureAgendaEventGap(from: "09:20", until: "09:30", minutes: 10, fits: nil)
        )
        XCTAssertEqual(present(bare).calendar?.gapRow?.text, "10m free")
    }

    // MARK: - MEET time chips

    private func makeItem(
        ledgerLine: Int,
        text: String,
        event: CaptureAgendaItemEvent?
    ) -> CaptureAgendaItem {
        CaptureAgendaItem(
            index: 1,
            ledgerLine: ledgerLine,
            ledgerDepth: 1,
            marker: .plain,
            blockLink: "[[2026/20260828.md#^standup]]",
            resolution: .resolved,
            relativeTarget: "2026/20260828.md",
            line: 7,
            blockID: "standup",
            text: text,
            statusSymbol: "*",
            statusName: "Next",
            statusType: "ON_HOLD",
            lines: [],
            linesTruncated: 0,
            ledgerNotes: [],
            warning: nil,
            event: event
        )
    }

    private func meetEntry(
        items: [CaptureAgendaItem],
        name: String? = "MEET"
    ) -> CaptureAgendaPomodoro {
        CaptureAgendaPomodoro(
            line: 13,
            name: name,
            isCurrent: false,
            taskLinkCount: items.count,
            role: .next,
            startsAt: nil,
            endsAt: nil,
            retiredLinkCount: 0,
            notes: [],
            items: items,
            slug: "meet",
            selectable: true
        )
    }

    func testMeetItemWithEventShowsTimeChip() {
        let event = CaptureAgendaItemEvent(
            timeRange: "0930-1000",
            startsAt: "2026-08-28T09:30",
            endsAt: "2026-08-28T10:00",
            untracked: false,
            title: "Standup"
        )
        let item = makeItem(
            ledgerLine: 14,
            text: "**0930-1000** Standup",
            event: event
        )
        let snapshot = CaptureAgendaSnapshot(
            ok: true,
            schemaVersion: 1,
            date: today,
            completedSummary: CaptureAgendaCompletedSummary(),
            pomodoros: [meetEntry(items: [item])],
            warnings: [],
            planBudget: nil,
            events: nil
        )
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            locale: locale
        )
        guard let task = presentation.groups.first?.tasks.first else {
            XCTFail("expected a MEET task")
            return
        }
        XCTAssertEqual(task.fullRows.first?.text, "Standup")
        XCTAssertEqual(task.fullRows.first?.accessoryText, "09:30–10:00")
    }

    func testNonMeetItemKeepsBoldSpan() {
        let event = CaptureAgendaItemEvent(
            startsAt: "2026-08-28T09:30",
            endsAt: "2026-08-28T10:00",
            title: "Standup"
        )
        let item = makeItem(
            ledgerLine: 14,
            text: "**0930-1000** Standup",
            event: event
        )
        let snapshot = CaptureAgendaSnapshot(
            ok: true,
            schemaVersion: 1,
            date: today,
            completedSummary: CaptureAgendaCompletedSummary(),
            pomodoros: [meetEntry(items: [item], name: "BOB")],
            warnings: [],
            planBudget: nil,
            events: nil
        )
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            locale: locale
        )
        guard let task = presentation.groups.first?.tasks.first else {
            XCTFail("expected a BOB task")
            return
        }
        XCTAssertEqual(task.fullRows.first?.text, "**0930-1000** Standup")
        XCTAssertNil(task.fullRows.first?.accessoryText)
    }
}
