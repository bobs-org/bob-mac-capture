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
        themes: [CapturePomodoroThemeRef] = [],
        slug: String? = "fix",
        selectable: Bool = true,
        startToken: String? = nil
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
            selectable: selectable,
            startToken: startToken,
            themes: themes
        )
    }

    private func makeSnapshot(
        date: String? = "2026-08-28",
        summary: CaptureAgendaCompletedSummary = CaptureAgendaCompletedSummary(
            count: 1,
            minutes: 160
        ),
        entries: [CaptureAgendaPomodoro] = [],
        warnings: [String] = [],
        planBudget: CapturePlanBudget? = nil
    ) -> CaptureAgendaSnapshot {
        CaptureAgendaSnapshot(
            ok: true,
            schemaVersion: 1,
            date: date,
            completedSummary: summary,
            pomodoros: entries,
            warnings: warnings,
            planBudget: planBudget
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
        XCTAssertNil(presentation.planBudgetRow)
        XCTAssertEqual(presentation.titleRow.text, "Today · Fri 28 Aug")
        XCTAssertEqual(presentation.summaryText, "1 done · 2h 40m")
        XCTAssertEqual(presentation.titleRow.accessoryText, "1 done · 2h 40m")
    }

    func testTitleShowsOffClockChipAfterWorkedSummary() {
        let summary = CaptureAgendaCompletedSummary(
            count: 1,
            minutes: 160,
            offClock: CaptureAgendaOffClockSummary(count: 1, minutes: 60)
        )
        let presentation = present(makeSnapshot(summary: summary))

        XCTAssertEqual(presentation.titleRow.accessoryText, "1 done · 2h 40m")
        XCTAssertEqual(presentation.titleRow.titleOffClockText, "◌ 1h off-clock")
        XCTAssertEqual(presentation.titleRow.key.titleOffClockText, "◌ 1h off-clock")
        XCTAssertTrue(
            presentation.titleRow.accessibilityLabel?.contains(
                "1 done · 2h 40m, 1h off-clock"
            ) == true
        )
    }

    func testPomodoroTypeColorsUseTypeWordingForVoiceOver() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(
                line: 5,
                themes: [CapturePomodoroThemeRef(key: "fix", name: "FIX", hue: .blue)]
            ),
        ]))

        XCTAssertTrue(presentation.groups[0].headerRow.accessibilityLabel?.contains("types") == true)
        XCTAssertFalse(presentation.groups[0].headerRow.accessibilityLabel?.contains("themes") == true)
    }

    func testLegacyAgendaFixtureKeepsItsCurrentRowsWithoutBudget() throws {
        let snapshot = try fixture("agenda-current.json")
        let presentation = present(snapshot)

        XCTAssertNil(snapshot.planBudget)
        XCTAssertNil(presentation.planBudgetRow)
        XCTAssertEqual(presentation.state, .agenda)
        XCTAssertEqual(presentation.groups.count, 4)
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

    func testStaleMarksTitleRow() {
        let fresh = present(makeSnapshot(entries: [
            makeEntry(line: 5, items: [makeItem(ledgerLine: 6)]),
        ]))
        XCTAssertFalse(fresh.isStale)
        XCTAssertEqual(fresh.titleRow.accessoryText, "1 done · 2h 40m")

        let snapshot = makeSnapshot(entries: [
            makeEntry(line: 5, items: [makeItem(ledgerLine: 6)]),
        ])
        let stale = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: nil,
            locale: locale,
            isStale: true
        )
        XCTAssertTrue(stale.isStale)
        XCTAssertEqual(
            stale.titleRow.accessoryText,
            "1 done · 2h 40m · \(CaptureAgendaPresentation.staleSuffix)"
        )
        XCTAssertTrue(
            stale.titleRow.accessibilityLabel?.contains(
                CaptureAgendaPresentation.staleSuffix
            ) == true
        )
    }

    func testStaleWithoutSummaryShowsSuffixAlone() {
        let snapshot = makeSnapshot(
            summary: CaptureAgendaCompletedSummary(),
            entries: [makeEntry(line: 5, items: [makeItem(ledgerLine: 6)])]
        )
        let stale = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: nil,
            locale: locale,
            isStale: true
        )
        XCTAssertEqual(
            stale.titleRow.accessoryText,
            CaptureAgendaPresentation.staleSuffix
        )
    }

    func testLiveCountdownFollowsCurrentEndsAt() {
        let timed = present(makeSnapshot(entries: [
            makeEntry(line: 5, endsAt: "2026-08-28T08:30"),
        ]))
        XCTAssertTrue(timed.hasLiveCountdown)

        let untimed = present(makeSnapshot(entries: [
            makeEntry(
                line: 5,
                startsAt: nil,
                endsAt: nil
            ),
        ]))
        XCTAssertFalse(untimed.hasLiveCountdown)

        let nextOnly = present(makeSnapshot(entries: [
            makeEntry(line: 5, role: .next, endsAt: "2026-08-28T09:30"),
        ]))
        XCTAssertFalse(nextOnly.hasLiveCountdown)
    }

    func testLoadingFactoryShowsQuietLine() {
        let loading = CaptureAgendaPresentation.loading(
            today: today,
            locale: locale
        )
        XCTAssertEqual(loading.state, .loading)
        XCTAssertTrue(loading.groups.isEmpty)
        XCTAssertFalse(loading.isStale)
        XCTAssertFalse(loading.hasLiveCountdown)
        XCTAssertNil(loading.planBudgetRow)
        XCTAssertEqual(loading.titleRow.text, "Today · Fri 28 Aug")
        XCTAssertEqual(loading.stateRow?.text, "Loading today…")
    }

    func testDateMismatchShowsLoading() {
        let presentation = present(makeSnapshot(
            date: "2026-08-27",
            entries: [makeEntry(line: 5, items: [makeItem(ledgerLine: 6)])],
            planBudget: CapturePlanBudget(
                status: "ok",
                links: CapturePlanBudgetMeter(count: 8, cap: 10, over: false)
            )
        ))
        XCTAssertEqual(presentation.state, .loading)
        XCTAssertTrue(presentation.groups.isEmpty)
        XCTAssertNil(presentation.planBudgetRow)
        XCTAssertEqual(presentation.stateRow?.text, "Loading today…")
    }

    func testEmptyAgendaStates() {
        let planned = present(makeSnapshot(entries: []))
        XCTAssertEqual(planned.state, .noOpen)
        XCTAssertEqual(planned.stateRow?.text, "No Pomodoros planned · =NAME starts one")

        let missing = present(makeSnapshot(
            entries: [],
            warnings: ["Bob daily note does not exist: /vault/2026/20260828.md"]
        ))
        XCTAssertEqual(missing.state, .noDailyNote)
        XCTAssertEqual(missing.stateRow?.text, "No daily note for today yet")

        let missingSection = present(makeSnapshot(
            entries: [],
            warnings: ["Bob daily note has no Pomodoros section: /vault/2026/20260828.md"]
        ))
        XCTAssertEqual(missingSection.state, .noDailyNote)
        XCTAssertEqual(missingSection.stateRow?.text, "No daily note for today yet")
    }

    func testBudgetRowUsesSavedCountsWithoutProposalDetails() {
        let budget = CapturePlanBudget(
            status: "ok",
            links: CapturePlanBudgetMeter(count: 8, cap: 10, over: false),
            warnings: [CapturePlanBudgetWarning(code: "theme_cap", message: "proposal warning")]
        )
        let presentation = present(makeSnapshot(entries: [], planBudget: budget))
        guard let row = presentation.planBudgetRow else {
            return XCTFail("Expected the saved budget row")
        }

        XCTAssertEqual(presentation.state, .noOpen)
        XCTAssertEqual(presentation.stateRow?.text, "No Pomodoros planned · =NAME starts one")
        XCTAssertEqual(row.kind, .planBudget)
        XCTAssertEqual(row.text, "TODAY 8/10")
        XCTAssertEqual(row.key.text, "TODAY 8/10")
        XCTAssertEqual(row.accessibilityLabel, "Plan budget: TODAY 8 of 10 links")
        XCTAssertNil(row.planBudget?.destinationRowText)
        XCTAssertTrue(row.planBudget?.warningTexts.isEmpty == true)
        XCTAssertEqual(row.planBudget?.today.tone, .orange)
    }

    func testEmptyLedgerShowsZeroBudgetMeters() {
        let presentation = present(makeSnapshot(
            entries: [],
            planBudget: CapturePlanBudget(
                status: "ok",
                links: CapturePlanBudgetMeter(count: 0, cap: 7, over: false)
            )
        ))

        XCTAssertEqual(presentation.state, .noOpen)
        XCTAssertEqual(presentation.planBudgetRow?.text, "TODAY 0/7")
        XCTAssertEqual(presentation.stateRow?.text, "No Pomodoros planned · =NAME starts one")
    }

    func testBudgetUnavailableWarningKeepsTheReadableEmptyAgendaState() {
        let presentation = present(makeSnapshot(
            entries: [],
            warnings: ["plan budget unavailable: invalid plan config"]
        ))

        XCTAssertEqual(presentation.state, .noOpen)
        XCTAssertEqual(presentation.stateRow?.text, "No Pomodoros planned · =NAME starts one")
        XCTAssertNil(presentation.planBudgetRow)
    }

    func testBudgetRowsRepublishOverStateChangesAndKeyCountsAndCaps() throws {
        func row(count: Int = 8, cap: Int = 10) throws -> CaptureAgendaRow {
            let snapshot = makeSnapshot(
                entries: [],
                planBudget: CapturePlanBudget(
                    status: "ok",
                    links: CapturePlanBudgetMeter(count: count, cap: cap, over: count > cap)
                )
            )
            return try XCTUnwrap(present(snapshot).planBudgetRow)
        }

        let within = try row()
        let over = try row(count: 11)
        XCTAssertNotEqual(within.key, over.key)
        XCTAssertNotEqual(within, over)
        XCTAssertNotEqual(within.key, try row(count: 2).key)
        XCTAssertNotEqual(within.key, try row(cap: 4).key)
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
        XCTAssertFalse(presentation.groups[0].headerRow.hintDimmed)
        XCTAssertEqual(presentation.groups[1].headerRow.accessoryText, "= starts it")
        XCTAssertFalse(presentation.groups[1].headerRow.hintDimmed)
        XCTAssertEqual(presentation.groups[2].headerRow.accessoryText, "=#later")
        XCTAssertTrue(presentation.groups[2].headerRow.hintDimmed)
        XCTAssertNil(presentation.groups[3].headerRow.accessoryText)
        XCTAssertFalse(presentation.groups[3].headerRow.hintDimmed)
    }

    func testLaterHeaderUsesStartTokenAndDimsHint() {
        let bare = present(makeSnapshot(entries: [
            makeEntry(
                line: 20,
                name: "LATER",
                role: .later,
                startsAt: nil,
                endsAt: nil,
                slug: "later",
                startToken: "=later"
            ),
        ]))
        XCTAssertEqual(bare.groups[0].headerRow.accessoryText, "=later")
        XCTAssertTrue(bare.groups[0].headerRow.hintDimmed)

        let hashed = present(makeSnapshot(entries: [
            makeEntry(
                line: 20,
                name: "DEEP WORK",
                role: .later,
                startsAt: nil,
                endsAt: nil,
                slug: "deep-work",
                startToken: "=#deep-work"
            ),
        ]))
        XCTAssertEqual(hashed.groups[0].headerRow.accessoryText, "=#deep-work")
        XCTAssertTrue(hashed.groups[0].headerRow.hintDimmed)

        let legacy = present(makeSnapshot(entries: [
            makeEntry(
                line: 20,
                name: "LATER",
                role: .later,
                startsAt: nil,
                endsAt: nil,
                slug: "later"
            ),
        ]))
        XCTAssertEqual(legacy.groups[0].headerRow.accessoryText, "=#later")
        XCTAssertTrue(legacy.groups[0].headerRow.hintDimmed)

        let hidden = present(makeSnapshot(entries: [
            makeEntry(
                line: 30,
                name: "HIDDEN",
                role: .later,
                startsAt: nil,
                endsAt: nil,
                slug: "hidden",
                selectable: false,
                startToken: "=hidden"
            ),
        ]))
        XCTAssertNil(hidden.groups[0].headerRow.accessoryText)
        XCTAssertFalse(hidden.groups[0].headerRow.hintDimmed)
    }

    func testFoldedLaterHeaderKeepsHintDimmed() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(
                line: 20,
                name: "LATER",
                role: .later,
                startsAt: nil,
                endsAt: nil,
                notes: [makeLine("note")],
                slug: "later",
                startToken: "=later"
            ),
        ]))
        let group = presentation.groups[0]
        let folded = CaptureAgendaFitPlanner.headerWithNotesChip(group: group)
        XCTAssertEqual(folded.accessoryText, "=later")
        XCTAssertTrue(group.headerRow.hintDimmed)
        XCTAssertTrue(folded.hintDimmed)
        XCTAssertEqual(folded.notesChip, "1 notes")
    }

    func testAgendaPomodoroDecodesStartToken() throws {
        let json = Data(
            """
            {"line":20,"name":"LATER","role":"later","slug":"later","selectable":true,"start_token":"=later"}
            """.utf8
        )
        let entry = try JSONDecoder().decode(CaptureAgendaPomodoro.self, from: json)
        XCTAssertEqual(entry.startToken, "=later")

        let older = Data(
            """
            {"line":20,"name":"LATER","role":"later","slug":"later","selectable":true}
            """.utf8
        )
        let legacy = try JSONDecoder().decode(CaptureAgendaPomodoro.self, from: older)
        XCTAssertNil(legacy.startToken)
    }

    func testPomodoroEntryDecodesStartToken() throws {
        let json = Data(
            """
            {"ref":"1:abc","line":1,"state":"open","status_symbol":" ","name":"BUGS","slug":"bugs","selectable":true,"placeholder":false,"is_current":false,"child_count":0,"start_token":"=bugs"}
            """.utf8
        )
        let entry = try JSONDecoder().decode(CapturePomodoroEntry.self, from: json)
        XCTAssertEqual(entry.startToken, "=bugs")

        let hashed = Data(
            """
            {"ref":"1:abc","line":1,"state":"open","status_symbol":" ","name":"DEEP WORK","slug":"deep-work","selectable":true,"placeholder":false,"is_current":false,"child_count":0,"start_token":"=#deep-work"}
            """.utf8
        )
        let hashedEntry = try JSONDecoder().decode(CapturePomodoroEntry.self, from: hashed)
        XCTAssertEqual(hashedEntry.startToken, "=#deep-work")

        let older = Data(
            """
            {"ref":"1:abc","line":1,"state":"open","status_symbol":" ","slug":"bugs","selectable":false,"placeholder":false,"is_current":false,"child_count":0}
            """.utf8
        )
        let legacy = try JSONDecoder().decode(CapturePomodoroEntry.self, from: older)
        XCTAssertNil(legacy.startToken)
        XCTAssertFalse(legacy.selectable)
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
            "Multiple open timed sessions — close one so `x` knows which is running"
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

    func testRottenLogRendersHeaderEntriesAndChip() {
        let lines = [
            makeLine("🥀 Rotten log", kind: .logMarker, log: .rotten),
            makeLine("Oct 16 — no reason given · kept 2×", depth: 2, log: .rotten),
            makeLine("plain child"),
        ]
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, items: [makeItem(ledgerLine: 4, lines: lines)]),
        ]))
        let task = presentation.groups[0].tasks[0]
        XCTAssertEqual(
            task.fullRows.map(\.kind),
            [.taskHeadline, .logHeader, .logEntry, .childLine]
        )
        XCTAssertEqual(task.fullRows[1].text, "🥀 Rotten log")
        XCTAssertEqual(task.fullRows[1].accessibilityLabel, "Rotten log")
        XCTAssertEqual(task.noLogsRows.map(\.kind), [.taskHeadline, .childLine])
        XCTAssertEqual(task.noLogsRows[0].accessoryText, "🥀 1")
        XCTAssertEqual(
            task.noLogsRows[0].accessoryAccessibilityLabel,
            "Show rotten log, 1 entries"
        )
    }

    func testLogChipsOrderWorkScheduleThenRotten() {
        let lines = [
            makeLine("🛠️ Work log", kind: .logMarker, log: .work),
            makeLine("Aug 27 — research", depth: 2, log: .work),
            makeLine("🗓 Schedule log", kind: .logMarker, log: .schedule),
            makeLine("Aug 28 — deferred", depth: 2, log: .schedule),
            makeLine("🥀 Rotten log", kind: .logMarker, log: .rotten),
            makeLine("Oct 16 — kept", depth: 2, log: .rotten),
            makeLine(
                "Oct 09 — kept",
                depth: 2,
                log: .rotten
            ),
        ]
        XCTAssertEqual(
            CaptureAgendaPresentation.logChips(lines: lines),
            ["⚒ 1", "🗓 1", "🥀 2"]
        )
        XCTAssertEqual(
            CaptureAgendaPresentation.accessibilityChip("🥀 2"),
            "Show rotten log, 2 entries"
        )
    }

    func testUnknownLogKindFoldsToGenericHeaderWithoutChip() {
        let lines = [
            makeLine("Mystery log", kind: .logMarker, log: .other("nap")),
            makeLine("a nested line", depth: 2, log: .other("nap")),
        ]
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, items: [makeItem(ledgerLine: 4, lines: lines)]),
        ]))
        let task = presentation.groups[0].tasks[0]
        XCTAssertEqual(task.fullRows[1].kind, .logHeader)
        XCTAssertEqual(task.fullRows[1].text, "Mystery log")
        XCTAssertEqual(task.fullRows[2].kind, .childLine)
        XCTAssertNil(task.noLogsRows[0].accessoryText)
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
        XCTAssertEqual(task.fullRows[0].lineLimit, 1)
    }

    func testNilIndexOmitsPositionalNumber() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, items: [makeItem(ledgerLine: 4, index: nil)]),
        ]))
        XCTAssertEqual(
            presentation.groups[0].tasks[0].fullRows[0].accessibilityLabel,
            "Task, Todo, Task title"
        )
    }

    func testOneLineRowOmitsZeroHiddenChip() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, items: [makeItem(ledgerLine: 4)]),
        ]))
        let oneLine = presentation.groups[0].tasks[0].oneLineRow
        XCTAssertNil(oneLine.accessoryText)
        XCTAssertNil(oneLine.accessoryAccessibilityLabel)
    }

    func testFoldedHeaderKeepsTimeAndChipsNotesSeparately() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(
                line: 3,
                notes: [makeLine("epic on test"), makeLine("another note")],
                items: [makeItem(ledgerLine: 4)]
            ),
        ]))
        let group = presentation.groups[0]
        XCTAssertEqual(group.sessionNotesChip, "2 notes")
        let folded = CaptureAgendaFitPlanner.headerWithNotesChip(group: group)
        XCTAssertEqual(folded.accessoryText, group.headerRow.accessoryText)
        XCTAssertEqual(folded.notesChip, "2 notes")
        XCTAssertEqual(folded.key.notesChip, "2 notes")
        XCTAssertNotEqual(folded, group.headerRow)
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

    // MARK: - Icon links

    private let keepDentist =
        "Call dentist [💡](https://keep.google.com/u/0/#NOTE/example \"Open in Google Keep\")"
    private let keepNoTooltip =
        "Hardware store [💡](https://keep.google.com/u/0/#NOTE/store)"
    private let keepLongDestination =
        "https://keep.google.com/u/0/#NOTE/" + String(repeating: "x", count: 90)
    private var keepLongTitle: String {
        "Call dentist [💡](\(keepLongDestination) \"Open in Google Keep\")"
    }

    func testKeepSourceLinksCollapseInNowNextAndLater() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, name: "NOW", items: [
                makeItem(
                    ledgerLine: 4,
                    text: keepDentist,
                    lines: [
                        makeLine(
                            "Follow up [💡](https://keep.google.com/u/0/#NOTE/child \"Open in Google Keep\")"
                        ),
                    ],
                    ledgerNotes: [
                        makeLine(
                            "From Keep [💡](https://keep.google.com/u/0/#NOTE/note \"Open in Google Keep\")"
                        ),
                    ]
                ),
            ]),
            makeEntry(line: 10, name: "NEXT", role: .next, items: [
                makeItem(ledgerLine: 11, blockID: "store", text: keepNoTooltip),
            ]),
            makeEntry(line: 20, name: "LATER", role: .later, items: [
                makeItem(ledgerLine: 21, blockID: "later", text: keepDentist),
            ]),
        ]))
        XCTAssertEqual(presentation.groups.map(\.role), [.current, .next, .later])

        let now = presentation.groups[0].tasks[0]
        XCTAssertEqual(now.title, keepDentist)
        XCTAssertEqual(now.fullRows[0].text, keepDentist)
        XCTAssertEqual(now.noLogsRows[0].text, keepDentist)
        XCTAssertEqual(now.oneLineRow.text, keepDentist)
        XCTAssertEqual(now.fullRows[0].numberBadge, 1)
        for row in [now.fullRows[0], now.noLogsRows[0], now.oneLineRow] {
            let parsed = CaptureAgendaInlineText(parsing: row.text)
            XCTAssertEqual(parsed.text, "Call dentist 💡")
            XCTAssertEqual(parsed.segments.map(\.kind), [.plain, .link])
        }
        XCTAssertEqual(
            now.fullRows[0].accessibilityLabel,
            "Task 1, Todo, Call dentist 💡"
        )
        XCTAssertEqual(now.fullRows[1].kind, .ledgerNote)
        XCTAssertEqual(
            now.fullRows[1].text,
            "From Keep [💡](https://keep.google.com/u/0/#NOTE/note \"Open in Google Keep\")"
        )
        XCTAssertEqual(now.fullRows[1].accessibilityLabel, "From Keep 💡")
        XCTAssertEqual(now.fullRows[2].kind, .childLine)
        XCTAssertEqual(now.fullRows[2].accessibilityLabel, "Follow up 💡")

        let next = presentation.groups[1].tasks[0]
        XCTAssertEqual(
            CaptureAgendaInlineText(parsing: next.fullRows[0].text).text,
            "Hardware store 💡"
        )
        XCTAssertEqual(
            next.fullRows[0].accessibilityLabel,
            "Task 1, Todo, Hardware store 💡"
        )

        let later = presentation.groups[2].tasks[0]
        XCTAssertEqual(
            CaptureAgendaInlineText(parsing: later.fullRows[0].text).text,
            "Call dentist 💡"
        )
        XCTAssertEqual(
            later.fullRows[0].accessibilityLabel,
            "Task 1, Todo, Call dentist 💡"
        )
    }

    func testKeepSourceLinkOnDuplicateAndCompletedTasks() {
        let presentation = present(makeSnapshot(entries: [
            makeEntry(line: 3, name: "NOW", items: [
                makeItem(ledgerLine: 4, text: keepDentist),
                makeItem(
                    ledgerLine: 5,
                    blockID: "done",
                    text: keepNoTooltip,
                    statusType: "DONE",
                    statusName: "Done"
                ),
            ]),
            makeEntry(line: 10, name: "NEXT", role: .next, items: [
                makeItem(ledgerLine: 11, text: keepDentist),
            ]),
        ]))
        let duplicate = presentation.groups[1].tasks[0].fullRows[0]
        XCTAssertEqual(duplicate.kind, .duplicate)
        XCTAssertEqual(duplicate.text, "\(keepDentist) ↑ in NOW")
        XCTAssertEqual(duplicate.numberBadge, 1)
        XCTAssertEqual(
            CaptureAgendaInlineText(parsing: duplicate.text).text,
            "Call dentist 💡 ↑ in NOW"
        )
        XCTAssertEqual(
            duplicate.accessibilityLabel,
            "Task 1, Todo, Call dentist 💡, already shown"
        )

        let struck = presentation.groups[0].tasks[1].fullRows[0]
        XCTAssertEqual(struck.kind, .struck)
        XCTAssertEqual(struck.text, keepNoTooltip)
        XCTAssertEqual(
            CaptureAgendaInlineText(parsing: struck.text).text,
            "Hardware store 💡"
        )
        XCTAssertEqual(
            struck.accessibilityLabel,
            "Task 1, Done, Hardware store 💡, completed"
        )
    }

    func testOneRowProjectsIconLinksBeforeTruncation() {
        let presentation = present(
            makeSnapshot(entries: [
                makeEntry(
                    line: 20, name: "CALLS", role: .later,
                    items: [
                        makeItem(ledgerLine: 21, blockID: "long", text: keepLongTitle)
                    ])
            ]))
        let rawJoined = "CALLS · \(keepLongTitle)"
        XCTAssertGreaterThan(rawJoined.count, CaptureAgendaLayoutMetrics.maxOneRowLength)
        let oneRow = presentation.groups[0].oneRowRow
        XCTAssertEqual(oneRow.text, "CALLS · Call dentist 💡")
        XCTAssertLessThanOrEqual(oneRow.text.count, CaptureAgendaLayoutMetrics.maxOneRowLength)
        XCTAssertFalse(oneRow.text.contains("https://"))
        XCTAssertFalse(oneRow.text.contains("Open in Google Keep"))
        XCTAssertEqual(oneRow.key.text, oneRow.text)
    }

    func testOneRowProjectsCalendarIconBeforeTruncation() {
        let longCalendarTitle =
            "Call dentist [📅](https://example.test/event?eid=example"
            + "&details="
            + String(repeating: "x", count: 100) + " \"Open in Google Calendar\")"
        let presentation = present(
            makeSnapshot(entries: [
                makeEntry(
                    line: 20, name: "LATER", role: .later,
                    items: [
                        makeItem(ledgerLine: 21, blockID: "calendar", text: longCalendarTitle)
                    ])
            ]))
        let rawJoined = "LATER · \(longCalendarTitle)"
        XCTAssertGreaterThan(rawJoined.count, CaptureAgendaLayoutMetrics.maxOneRowLength)
        let oneRow = presentation.groups[0].oneRowRow
        XCTAssertEqual(oneRow.text, "LATER · Call dentist 📅")
        XCTAssertLessThanOrEqual(oneRow.text.count, CaptureAgendaLayoutMetrics.maxOneRowLength)
        XCTAssertFalse(oneRow.text.contains("https://"))
    }

    func testLightbulbFixtureProjectsKeepLinks() throws {
        let snapshot = try fixture("agenda-lightbulb.json")
        let presentation = present(snapshot)
        XCTAssertEqual(presentation.groups.map(\.role), [.current, .next, .later])
        let nowTitle = presentation.groups[0].tasks[0].fullRows[0]
        XCTAssertEqual(
            CaptureAgendaInlineText(parsing: nowTitle.text).text,
            "Call dentist 💡"
        )
        XCTAssertEqual(
            nowTitle.accessibilityLabel,
            "Task 1, Todo, Call dentist 💡"
        )
        XCTAssertFalse(presentation.groups[2].oneRowRow.text.contains("https://"))
    }

    func testCalendarFixtureRowsProjectBadgesAndPreserveMetadata() throws {
        let presentation = present(try fixture("agenda-events.json"))
        let tasks = presentation.groups.flatMap(\.tasks)
        let standup = try XCTUnwrap(tasks.first { $0.title.contains("Standup") })
        let lunch = try XCTUnwrap(tasks.first { $0.title.contains("Lunch with Kelly") })

        let standupRow = try XCTUnwrap(standup.fullRows.first)
        XCTAssertEqual(
            CaptureAgendaInlineText(parsing: standupRow.text).text,
            "Standup 📅 📹 📍"
        )
        XCTAssertEqual(
            standupRow.accessibilityLabel,
            "Task 1, Next, **0930-1000** Standup 📅 📹 📍"
        )
        XCTAssertEqual(standupRow.numberBadge, 1)
        XCTAssertEqual(standupRow.statusGlyph, "*")

        let lunchRow = try XCTUnwrap(lunch.fullRows.first)
        XCTAssertEqual(
            CaptureAgendaInlineText(parsing: lunchRow.text).text,
            "Lunch with Kelly 📅 #untracked"
        )
        XCTAssertEqual(
            lunchRow.accessibilityLabel,
            "Task 2, Todo, **1200-1300** Lunch with Kelly 📅 #untracked"
        )
        XCTAssertEqual(lunchRow.numberBadge, 2)
        XCTAssertEqual(lunchRow.statusGlyph, " ")

        let standupDisplay = CaptureAgendaInlineText(parsing: standupRow.text).text
        let lunchDisplay = CaptureAgendaInlineText(parsing: lunchRow.text).text
        let standupAccessibility = try XCTUnwrap(standupRow.accessibilityLabel)
        let lunchAccessibility = try XCTUnwrap(lunchRow.accessibilityLabel)
        for text in [
            standupDisplay,
            lunchDisplay,
            standupAccessibility,
            lunchAccessibility,
        ] {
            XCTAssertFalse(text.contains("]("))
            XCTAssertFalse(text.contains("https://"))
            XCTAssertFalse(text.contains("Open in Google Calendar"))
            XCTAssertFalse(text.contains("Join call"))
        }
    }
}
