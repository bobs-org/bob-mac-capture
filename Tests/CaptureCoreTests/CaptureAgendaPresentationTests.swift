import XCTest

@testable import CaptureCore

final class CaptureAgendaPresentationTests: XCTestCase {
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
        index: Int? = 1,
        marker: CaptureAgendaMarker = .plain,
        blockID: String = "block",
        target: String? = "tasks.md",
        text: String? = "Task title",
        statusType: String? = "TODO",
        statusName: String? = "Todo",
        resolution: CaptureAgendaResolution = .resolved,
        lines: [CaptureAgendaLine] = [],
        ledgerNotes: [CaptureAgendaLine] = [],
        warning: String? = nil
    ) -> CaptureAgendaItem {
        CaptureAgendaItem(
            index: index,
            ledgerLine: ledgerLine,
            ledgerDepth: 1,
            marker: marker,
            blockLink: "[[\(target ?? "tasks")#^\(blockID)]]",
            resolution: resolution,
            relativeTarget: target,
            line: 1,
            blockID: blockID,
            text: text,
            statusSymbol: " ",
            statusName: statusName,
            statusType: statusType,
            lines: lines,
            linesTruncated: 0,
            ledgerNotes: ledgerNotes,
            warning: warning
        )
    }

    private func makeEntry(
        line: Int,
        name: String? = "FIX",
        role: CaptureAgendaRole = .current,
        startsAt: String? = "2026-08-28T08:00",
        endsAt: String? = "2026-08-28T08:30",
        retired: Int = 0,
        notes: [CaptureAgendaLine] = [],
        items: [CaptureAgendaItem] = [],
        slug: String? = "fix",
        selectable: Bool = true
    ) -> CaptureAgendaPomodoro {
        CaptureAgendaPomodoro(
            line: line,
            name: name,
            isCurrent: role == .current,
            taskLinkCount: items.count,
            role: role,
            startsAt: startsAt,
            endsAt: endsAt,
            retiredLinkCount: retired,
            notes: notes,
            items: items,
            slug: slug,
            selectable: selectable
        )
    }

    private func makeSnapshot(
        date: String? = "2026-08-28",
        summary: CaptureAgendaCompletedSummary = CaptureAgendaCompletedSummary(
            count: 1,
            minutes: 160
        ),
        entries: [CaptureAgendaPomodoro] = [],
        warnings: [String] = []
    ) -> CaptureAgendaSnapshot {
        CaptureAgendaSnapshot(
            ok: true,
            schemaVersion: 1,
            date: date,
            completedSummary: summary,
            pomodoros: entries,
            warnings: warnings
        )
    }

    private func present(
        _ snapshot: CaptureAgendaSnapshot,
        now: Date? = nil
    ) -> CaptureAgendaPresentation {
        CaptureAgendaPresentation(snapshot: snapshot, today: today, now: now, locale: locale)
    }

    private func fixture(_ name: String) throws -> CaptureAgendaSnapshot {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(CaptureAgendaSnapshot.self, from: Data(contentsOf: url))
    }

    // MARK: - Title and states

    func testTitleRowCarriesDateAndSummary() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 5, items: [makeItem(ledgerLine: 6)]),
        ]))
        XCTAssertEqual(presentation.state, .agenda)
        XCTAssertEqual(presentation.titleRow.text, "Today · Fri 28 Aug")
        XCTAssertEqual(presentation.summaryText, "1 done · 2h 40m")
        XCTAssertEqual(presentation.titleRow.accessoryText, "1 done · 2h 40m")
    }

    func testTitleRowNotesWhenNothingRunning() {
        let presentation = present(makeSnapshot(
            summary: CaptureAgendaCompletedSummary(),
            entries: [makeEntry(line: 5, name: "SASE", role: .next)]
        ))
        XCTAssertEqual(presentation.titleRow.text, "Today · Fri 28 Aug · Nothing running")
        XCTAssertNil(presentation.summaryText)
        XCTAssertNil(presentation.titleRow.accessoryText)
    }

    func testSummaryTable() {
        let cases: [(count: Int, minutes: Int, expected: String?)] = [
            (0, 0, nil),
            (5, 0, "5 done"),
            (5, 40, "5 done · 40m"),
            (5, 160, "5 done · 2h 40m"),
            (1, 60, "1 done · 1h 00m"),
        ]
        for (count, minutes, expected) in cases {
            XCTAssertEqual(
                CaptureAgendaClock.summaryText(count: count, minutes: minutes),
                expected,
                "count: \(count), minutes: \(minutes)"
            )
        }
    }

    func testDateMismatchShowsLoading() {
        let presentation = present(makeSnapshot(
            date: "2026-08-27",
            entries: [makeEntry(line: 5, items: [makeItem(ledgerLine: 6)])]
        ))
        XCTAssertEqual(presentation.state, .loading)
        XCTAssertTrue(presentation.groups.isEmpty)
        XCTAssertEqual(presentation.stateRow?.text, "Loading today…")
    }

    func testEmptyAgendaStates() {
        let planned = present(makeSnapshot(entries: []))
        XCTAssertEqual(planned.state, .noOpen)
        XCTAssertEqual(planned.stateRow?.text, "No Pomodoros planned · =#NAME starts one")

        let missing = present(makeSnapshot(
            entries: [],
            warnings: ["Bob daily note does not exist"]
        ))
        XCTAssertEqual(missing.state, .noDailyNote)
        XCTAssertEqual(missing.stateRow?.text, "No daily note for today yet")
    }

    // MARK: - Groups and headers

    func testGroupOrderIsCurrentNextLater() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 20, name: "LATER", role: .later, slug: "later"),
            makeEntry(line: 10, name: "NEXT", role: .next, slug: "next"),
            makeEntry(line: 3, name: "NOW", role: .current),
        ]))
        XCTAssertEqual(presentation.groups.map(\.name), ["NOW", "NEXT", "LATER"])
        XCTAssertEqual(
            presentation.groups.map(\.role),
            [.current, .next, .later]
        )
    }

    func testCompletedEntriesNeverBecomeGroups() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, name: "NOW", role: .current, items: [makeItem(ledgerLine: 4)]),
            makeEntry(line: 30, name: "DONE", role: .completed),
        ]))
        XCTAssertEqual(presentation.groups.map(\.name), ["NOW"])
    }

    func testHeaderTrailings() {
        let presentation = present(
            makeSnapshot(entries: [
                makeEntry(line: 3, name: "NOW", role: .current),
                makeEntry(line: 10, name: "NEXT", role: .next, startsAt: nil, endsAt: nil),
                makeEntry(
                    line: 20,
                    name: "LATER",
                    role: .later,
                    startsAt: nil,
                    endsAt: nil,
                    slug: "later"
                ),
                makeEntry(line: 30, name: "HIDDEN", role: .later, slug: nil, selectable: false),
            ])
        )
        XCTAssertEqual(presentation.groups[0].headerRow.accessoryText, "08:00–08:30")
        XCTAssertEqual(presentation.groups[1].headerRow.accessoryText, "= starts it")
        XCTAssertEqual(presentation.groups[2].headerRow.accessoryText, "=#later")
        XCTAssertNil(presentation.groups[3].headerRow.accessoryText)
    }

    func testCountdownJoinsTheCurrentTrailing() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        let now = CaptureAgendaClock.parseNaiveDateTime("2026-08-28T08:18", calendar: calendar)
        let presentation = present(
            makeSnapshot(entries: [makeEntry(line: 3, items: [makeItem(ledgerLine: 4)])]),
            now: now
        )
        XCTAssertEqual(presentation.groups[0].headerRow.accessoryText, "08:00–08:30 · 12m left")
    }

    func testGroupAccessibilityLabels() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, name: "FIX", items: [
                makeItem(ledgerLine: 4),
                makeItem(ledgerLine: 5),
            ]),
        ]))
        XCTAssertEqual(
            presentation.groups[0].accessibilityLabel,
            "Running Pomodoro FIX, 08:00 to 08:30, 2 tasks"
        )
    }

    func testMultipleTimedEntriesAddAWarningRow() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, name: "ONE", role: .open, slug: "one"),
            makeEntry(line: 10, name: "TWO", role: .open, slug: "two"),
        ]))
        XCTAssertEqual(presentation.groups.map(\.name), ["ONE", "TWO"])
        XCTAssertEqual(
            presentation.warningRow?.text,
            "Multiple open timed sessions — close one so `=x` knows which is running"
        )
        let single = present(makeSnapshot(entries: [
            makeEntry(line: 3, name: "NOW", items: [makeItem(ledgerLine: 4)]),
        ]))
        XCTAssertNil(single.warningRow)
    }

    // MARK: - Tasks

    func testResolvedTaskRendersHeadlineNotesAndChildren() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, items: [
                makeItem(
                    ledgerLine: 4,
                    lines: [makeLine("first child")],
                    ledgerNotes: [makeLine("epic on test")]
                ),
            ]),
        ]))
        let task = presentation.groups[0].tasks[0]
        XCTAssertEqual(task.fullRows.map(\.kind), [.taskHeadline, .ledgerNote, .childLine])
        XCTAssertEqual(task.fullRows[0].numberBadge, 1)
        XCTAssertEqual(
            task.fullRows[0].accessibilityLabel,
            "Task 1, Todo, Task title"
        )
        XCTAssertEqual(
            task.noLogsRows.map(\.kind),
            [.taskHeadline, .ledgerNote, .childLine]
        )
        XCTAssertEqual(task.oneLineRow.accessoryText, "+2 lines")
        XCTAssertEqual(task.oneLineRow.accessoryAccessibilityLabel, "Show 2 hidden lines")
    }

    func testLogSubtreesFoldIntoChips() {
        let lines = [
            makeLine("🛠️ Work log", kind: .logMarker, log: .work),
            makeLine("Aug 27 — research", depth: 2, log: .work),
            makeLine("Aug 28 — writing", depth: 2, log: .work),
            makeLine("plain child"),
        ]
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, items: [makeItem(ledgerLine: 4, lines: lines)]),
        ]))
        let task = presentation.groups[0].tasks[0]
        XCTAssertEqual(
            task.fullRows.map(\.kind),
            [.taskHeadline, .logHeader, .logEntry, .logEntry, .childLine]
        )
        XCTAssertEqual(task.fullRows[1].text, "⚒ Work log")
        XCTAssertEqual(task.noLogsRows.map(\.kind), [.taskHeadline, .childLine])
        XCTAssertEqual(task.noLogsRows[0].accessoryText, "⚒ 2")
        XCTAssertEqual(
            task.noLogsRows[0].accessoryAccessibilityLabel,
            "Show work log, 2 entries"
        )
    }

    func testDoneTasksRenderOneStruckLine() {
        for status in ["DONE", "CANCELLED"] {
            let presentation = present(makeSnapshot(entries: [
                makeEntry(line: 3, items: [
                    makeItem(ledgerLine: 4, statusType: status, lines: [makeLine("child")]),
                ]),
            ]))
            let task = presentation.groups[0].tasks[0]
            XCTAssertEqual(task.fullRows.map(\.kind), [.struck], "status: \(status)")
            XCTAssertEqual(task.noLogsRows.count, 1, "status: \(status)")
        }
    }

    func testUnresolvedItemsRenderWarningRows() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, items: [
                makeItem(
                    ledgerLine: 4,
                    text: nil,
                    statusType: nil,
                    statusName: nil,
                    resolution: .missingNote,
                    warning: "Note not found"
                ),
            ]),
        ]))
        let task = presentation.groups[0].tasks[0]
        XCTAssertEqual(task.fullRows.map(\.kind), [.warning])
        XCTAssertEqual(task.fullRows[0].text, "[[tasks.md#^block]] — Note not found")
    }

    func testRepeatsFoldToADuplicateLine() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, name: "FIX", items: [makeItem(ledgerLine: 4)]),
            makeEntry(line: 10, name: "SASE", role: .next, items: [makeItem(ledgerLine: 11)]),
        ]))
        XCTAssertEqual(presentation.groups[0].tasks[0].fullRows.map(\.kind), [.taskHeadline])
        XCTAssertEqual(presentation.groups[1].tasks[0].fullRows.map(\.kind), [.duplicate])
        XCTAssertEqual(presentation.groups[1].tasks[0].fullRows[0].text, "Task title ↑ in FIX")
    }

    func testRetiredLinesDifferBetweenNowAndLater() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, name: "FIX", retired: 2, items: [makeItem(ledgerLine: 4)]),
            makeEntry(line: 10, name: "BOB", role: .later, retired: 1, slug: "bob"),
        ]))
        XCTAssertEqual(presentation.groups[0].retiredRow?.text, "✓ 2 done this session")
        XCTAssertEqual(presentation.groups[1].retiredRow?.text, "✓ 1 done")
    }

    func testMarkerCaptionsAppearOnCurrentOnly() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, items: [
                makeItem(ledgerLine: 4, marker: .deferred),
                makeItem(ledgerLine: 5, marker: .embedded, blockID: "other"),
            ]),
            makeEntry(line: 10, name: "NEXT", role: .next, items: [
                makeItem(ledgerLine: 11, marker: .deferred, blockID: "third"),
            ]),
        ]))
        XCTAssertEqual(presentation.groups[0].tasks[0].fullRows[0].accessoryText, "deferred")
        XCTAssertEqual(
            presentation.groups[0].tasks[1].fullRows[0].accessoryText,
            "completes on close"
        )
        XCTAssertNil(presentation.groups[1].tasks[0].fullRows[0].accessoryText)
    }

    func testEmptyGroupsExplainThemselves() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 10, name: "BOB", role: .later, slug: "bob"),
        ]))
        XCTAssertEqual(presentation.groups[0].emptyRow?.text, "No linked tasks")
        XCTAssertTrue(presentation.groups[0].tasks.isEmpty)
    }

    func testRowKeysCarryKindTextDepthLimitAndAccessory() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, items: [makeItem(ledgerLine: 4)]),
        ]))
        let headline = presentation.groups[0].tasks[0].fullRows[0]
        XCTAssertEqual(headline.key.kind, .taskHeadline)
        XCTAssertEqual(headline.key.text, "Task title")
        XCTAssertEqual(headline.key.depth, 0)
        XCTAssertEqual(headline.key.lineLimit, 3)
        XCTAssertTrue(headline.key.hasAccessory)
        let oneLine = presentation.groups[0].tasks[0].oneLineRow
        XCTAssertNotEqual(oneLine.key, headline.key)
        XCTAssertEqual(oneLine.key.lineLimit, 1)
    }

    // MARK: - Countdown wording

    func testCountdownTable() {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone.current
        func now(_ raw: String) -> Date {
            guard let date = CaptureAgendaClock.parseNaiveDateTime(raw, calendar: calendar) else {
                fatalError("bad test time \(raw)")
            }
            return date
        }
        let endsAt = "2026-08-28T08:30"
        let cases: [(now: String, expected: String?)] = [
            ("2026-08-28T07:25", "1h 05m left"),
            ("2026-08-28T07:30", "1h 00m left"),
            ("2026-08-28T08:18", "12m left"),
            ("2026-08-28T08:29", "1m left"),
        ]
        for (raw, expected) in cases {
            XCTAssertEqual(
                CaptureAgendaClock.remainingText(endsAt: endsAt, now: now(raw)),
                expected,
                "now: \(raw)"
            )
        }
        XCTAssertEqual(
            CaptureAgendaClock.remainingText(endsAt: endsAt, now: now("2026-08-28T08:30")),
            "ending now"
        )
        let almostOver = now("2026-08-28T08:30").addingTimeInterval(30)
        let almostOverText = CaptureAgendaClock.remainingText(endsAt: endsAt, now: almostOver)
        XCTAssertEqual(almostOverText, "ending now")
        let overdue = now("2026-08-28T08:30").addingTimeInterval(8 * 60 + 20)
        XCTAssertEqual(CaptureAgendaClock.remainingText(endsAt: endsAt, now: overdue), "overdue 8m")
        XCTAssertNil(CaptureAgendaClock.remainingText(endsAt: nil, now: now("2026-08-28T08:18")))
        let garbage = CaptureAgendaClock.remainingText(
            endsAt: "not-a-time",
            now: now("2026-08-28T08:18")
        )
        XCTAssertNil(garbage)
    }

    // MARK: - Fixtures

    func testCurrentFixtureBuildsFourGroups() throws {
        let snapshot = try fixture("agenda-current.json")
        let presentation = present(snapshot)
        XCTAssertEqual(presentation.state, .agenda)
        XCTAssertEqual(presentation.groups.map(\.role), [.current, .next, .later, .later])
        XCTAssertEqual(presentation.groups[0].name, "FIX")
        XCTAssertEqual(presentation.groups[0].tasks.count, 3)
        XCTAssertEqual(presentation.groups[0].tasks[0].fullRows[0].text, "Deep fix")
        XCTAssertEqual(presentation.groups[0].retiredRow?.text, "✓ 1 done this session")
        XCTAssertEqual(presentation.summaryText, "1 done · 30m")
        // The deferred repeat of Deep fix folds to a duplicate line.
        XCTAssertEqual(presentation.groups[0].tasks[2].fullRows.map(\.kind), [.duplicate])
        // The missing link on Next is a warning row.
        let warned = presentation.groups[1].tasks.contains { task in
            task.fullRows.count == 1 && task.fullRows[0].kind == .warning
        }
        XCTAssertTrue(warned)
    }

    func testNothingRunningFixtureHasNoCountdown() throws {
        let snapshot = try fixture("agenda-nothing-running.json")
        let presentation = present(snapshot)
        XCTAssertEqual(presentation.groups.map(\.role), [.next, .later])
        XCTAssertTrue(presentation.titleRow.text.contains("Nothing running"))
    }

    func testMultipleTimedFixtureWarns() throws {
        let snapshot = try fixture("agenda-multiple-timed.json")
        let presentation = present(snapshot)
        XCTAssertEqual(presentation.groups.map(\.role), [.open, .open, .next])
        XCTAssertNotNil(presentation.warningRow)
    }
}
