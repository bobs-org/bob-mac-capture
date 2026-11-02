import XCTest

@testable import CaptureCore

/// Buffer wings and buffer-aware cards for the Calendar band
/// (`bob-cli-fk.6`): tolerant `buffer` decoding on event rows,
/// `items[].event`, `event_run.events[]` and `event_conflict.event`,
/// hatched rail wings with buffer-aware `firstGap`, the row buffer
/// capsule with accessibility text, and buffer-aware event-run and
/// conflict captions.
final class CaptureAgendaBufferTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let today = "2026-08-28"

    private func dateAt(_ raw: String) -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return formatter.date(from: raw) ?? Date()
    }

    private func fixtureData(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    private func bufferedSnapshot() throws -> CaptureAgendaSnapshot {
        try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: fixtureData("agenda-events-buffered.json")
        )
    }

    private func makeRow(
        line: Int = 7,
        title: String = "Lunch",
        startsAt: String? = "2026-08-28T12:00",
        endsAt: String? = "2026-08-28T13:00",
        phase: CaptureAgendaEventPhase? = .upcoming,
        offClock: Bool = false,
        buffer: CaptureEventBuffer? = nil
    ) -> CaptureAgendaEventRow {
        CaptureAgendaEventRow(
            line: line,
            blockID: "event-\(line)",
            kind: .task,
            qualifier: nil,
            title: title,
            timeRange: nil,
            startsAt: startsAt,
            endsAt: endsAt,
            durationMinutes: 60,
            phase: phase,
            statusSymbol: " ",
            statusType: "TODO",
            offClock: offClock,
            root: nil,
            home: nil,
            joinURL: nil,
            calendarURL: nil,
            location: nil,
            pomodoro: nil,
            buffer: buffer
        )
    }

    // MARK: - Labels

    func testBufferLabelsMatchBobSpelling() {
        XCTAssertEqual(
            CaptureEventBuffer(beforeMinutes: 30, afterMinutes: 15).label(),
            "\u{2212}30m +15m"
        )
        XCTAssertEqual(CaptureEventBuffer(beforeMinutes: 30).label(), "\u{2212}30m")
        XCTAssertEqual(CaptureEventBuffer(afterMinutes: 15).label(), "+15m")
        XCTAssertNil(CaptureEventBuffer().label())
        XCTAssertNil(CaptureEventBuffer(beforeMinutes: 0, afterMinutes: 0).label())
    }

    func testBufferPartLabels() {
        let buffer = CaptureEventBuffer(beforeMinutes: 30, afterMinutes: 15)
        XCTAssertEqual(buffer.partLabel(.before), "\u{2212}30m")
        XCTAssertEqual(buffer.partLabel(.after), "+15m")
        XCTAssertNil(CaptureEventBuffer(afterMinutes: 15).partLabel(.before))
        XCTAssertNil(CaptureEventBuffer(beforeMinutes: 30).partLabel(.after))
    }

    func testBufferSpokenText() {
        XCTAssertEqual(
            CaptureEventBuffer(beforeMinutes: 30, afterMinutes: 15).spoken(),
            "30-minute buffer before and 15-minute buffer after"
        )
        XCTAssertEqual(
            CaptureEventBuffer(beforeMinutes: 30).spoken(),
            "30-minute buffer before"
        )
        XCTAssertEqual(
            CaptureEventBuffer(afterMinutes: 15).spoken(),
            "15-minute buffer after"
        )
        XCTAssertNil(CaptureEventBuffer().spoken())
    }

    // MARK: - Agenda decoding

    func testBufferedFixtureDecodesBuffers() throws {
        let snapshot = try bufferedSnapshot()
        let events = try XCTUnwrap(snapshot.events)
        XCTAssertEqual(events.rows.count, 3)

        let standup = events.rows[0]
        XCTAssertEqual(standup.buffer?.beforeMinutes, 0)
        XCTAssertEqual(standup.buffer?.afterMinutes, 30)
        XCTAssertEqual(standup.buffer?.timeRange, "0830-0925")
        XCTAssertEqual(standup.buffer?.startsAt, "2026-08-28T08:30")
        XCTAssertEqual(standup.buffer?.endsAt, "2026-08-28T09:25")

        let lunch = events.rows[1]
        XCTAssertTrue(lunch.offClock)
        XCTAssertEqual(lunch.buffer?.beforeMinutes, 30)
        XCTAssertEqual(lunch.buffer?.afterMinutes, 15)
        XCTAssertEqual(lunch.buffer?.label(), "\u{2212}30m +15m")

        let conflict = try XCTUnwrap(events.conflict)
        XCTAssertEqual(conflict.bufferPart, .before)
        XCTAssertEqual(conflict.overlapMinutes, 5)

        let lunchItem = try XCTUnwrap(
            snapshot.pomodoros.flatMap(\.items).first(where: { $0.event?.title == "Lunch" })
        )
        XCTAssertEqual(lunchItem.event?.buffer?.label(), "\u{2212}30m +15m")
        let standupItem = try XCTUnwrap(
            snapshot.pomodoros.flatMap(\.items).first(where: { $0.event?.title == "Standup" })
        )
        XCTAssertEqual(standupItem.event?.buffer?.label(), "+15m")
    }

    func testUnbufferedAgendaRowsDecodeBufferAsNil() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/agenda-events.json")
        let snapshot = try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data(contentsOf: url)
        )
        let events = try XCTUnwrap(snapshot.events)
        XCTAssertTrue(events.rows.allSatisfy { $0.buffer == nil })
        XCTAssertNil(events.conflict?.bufferPart)
    }

    func testMalformedBufferDecodesAsNil() throws {
        let json = """
            {"line": 4, "kind": "task", "title": "Lunch",
             "starts_at": "2026-08-28T09:40", "ends_at": "2026-08-28T10:00",
             "untracked": true, "buffer": "nope"}
            """
        let row = try JSONDecoder().decode(
            CaptureAgendaEventRow.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(row.title, "Lunch")
        XCTAssertNil(row.buffer)
    }

    func testMalformedBufferPartDecodesAsNil() throws {
        let json = """
            {"pomodoro_line": 7, "event": 1, "overlap_minutes": 5,
             "buffer_part": "middle"}
            """
        let conflict = try JSONDecoder().decode(
            CaptureAgendaEventConflict.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(conflict.overlapMinutes, 5)
        XCTAssertNil(conflict.bufferPart)
    }

    // MARK: - Capture decoding

    func testEventRunAndConflictBuffersDecode() throws {
        let json = """
            {
              "time_range":"1130-1315","start":"1130","end":"1315",
              "untracked":true,"source":"calendar",
              "events":[
                {"index":1,"title":"Lunch with Kelly","time_range":"1200-1300",
                 "line":8,"block_id":"lunch","untracked":true,
                 "buffer":{"before_minutes":30,"after_minutes":15,
                   "time_range":"1130-1315"}}
              ]
            }
            """
        let run = try JSONDecoder().decode(
            PomodoroEventRun.self,
            from: Data(json.utf8)
        )
        XCTAssertEqual(run.events.first?.buffer?.label(), "\u{2212}30m +15m")

        let conflictJSON = """
            {"event":{"title":"Lunch","time_range":"1200-1300","line":8,
               "untracked":true,
               "buffer":{"before_minutes":30,"after_minutes":15,
                 "time_range":"1130-1315"}},
             "overlap_minutes":5,"buffer_part":"before","fit":"=4"}
            """
        let conflict = try JSONDecoder().decode(
            PomodoroEventConflict.self,
            from: Data(conflictJSON.utf8)
        )
        XCTAssertEqual(conflict.bufferPart, .before)
        XCTAssertEqual(conflict.event.buffer?.label(), "\u{2212}30m +15m")
    }

    func testMalformedCaptureBuffersDecodeAsNil() throws {
        let runJSON = """
            {"time_range":"1200-1300","start":"1200","end":"1300",
             "untracked":true,"source":"calendar",
             "events":[{"index":1,"title":"Lunch","time_range":"1200-1300",
               "line":8,"untracked":true,"buffer":[1,2]}]}
            """
        let run = try JSONDecoder().decode(
            PomodoroEventRun.self,
            from: Data(runJSON.utf8)
        )
        XCTAssertEqual(run.events.count, 1)
        XCTAssertNil(run.events.first?.buffer)

        let conflictJSON = """
            {"event":{"title":"Lunch","time_range":"1200-1300","line":8,
               "untracked":true,"buffer":"nope"},
             "overlap_minutes":5,"buffer_part":"sideways"}
            """
        let conflict = try JSONDecoder().decode(
            PomodoroEventConflict.self,
            from: Data(conflictJSON.utf8)
        )
        XCTAssertNil(conflict.event.buffer)
        XCTAssertNil(conflict.bufferPart)
    }

    // MARK: - Rail

    func testRailWingsSpanBufferedRanges() throws {
        let buffer = CaptureEventBuffer(
            beforeMinutes: 30,
            afterMinutes: 15,
            timeRange: "1130-1315",
            startsAt: "2026-08-28T11:30",
            endsAt: "2026-08-28T13:15"
        )
        let row = makeRow(buffer: buffer)
        let events = CaptureAgendaEvents(rows: [row])
        let rail = try XCTUnwrap(
            CaptureAgendaPresentation.makeCalendarRail(
                events: events,
                entries: [],
                now: dateAt("2026-08-28T10:00")
            )
        )
        XCTAssertEqual(rail.events.count, 1)
        let capsule = rail.events[0]
        XCTAssertNotNil(capsule.leadingWing)
        XCTAssertNotNil(capsule.trailingWing)
        XCTAssertFalse(capsule.leadingWing?.active ?? true)
        XCTAssertFalse(capsule.trailingWing?.active ?? true)
        // The meeting capsule is strictly inside the wing-to-wing span.
        XCTAssertLessThan(capsule.leadingWing?.start ?? 1, capsule.start)
        XCTAssertGreaterThan(capsule.trailingWing?.end ?? 0, capsule.end)
    }

    func testRailWingsLightWhileBufferInProgress() throws {
        let buffer = CaptureEventBuffer(
            beforeMinutes: 30,
            afterMinutes: 15,
            timeRange: "1130-1315",
            startsAt: "2026-08-28T11:30",
            endsAt: "2026-08-28T13:15"
        )
        let row = makeRow(buffer: buffer)
        let events = CaptureAgendaEvents(rows: [row])

        let leadIn = try XCTUnwrap(
            CaptureAgendaPresentation.makeCalendarRail(
                events: events,
                entries: [],
                now: dateAt("2026-08-28T11:40")
            )
        )
        XCTAssertEqual(leadIn.events[0].leadingWing?.active, true)
        XCTAssertEqual(leadIn.events[0].trailingWing?.active, false)

        let leadOut = try XCTUnwrap(
            CaptureAgendaPresentation.makeCalendarRail(
                events: events,
                entries: [],
                now: dateAt("2026-08-28T13:05")
            )
        )
        XCTAssertEqual(leadOut.events[0].leadingWing?.active, false)
        XCTAssertEqual(leadOut.events[0].trailingWing?.active, true)

        let meeting = try XCTUnwrap(
            CaptureAgendaPresentation.makeCalendarRail(
                events: events,
                entries: [],
                now: dateAt("2026-08-28T12:30")
            )
        )
        XCTAssertEqual(meeting.events[0].leadingWing?.active, false)
        XCTAssertEqual(meeting.events[0].trailingWing?.active, false)
    }

    func testRailWithoutBufferHasNoWings() throws {
        let events = CaptureAgendaEvents(rows: [makeRow()])
        let rail = try XCTUnwrap(
            CaptureAgendaPresentation.makeCalendarRail(
                events: events,
                entries: [],
                now: dateAt("2026-08-28T10:00")
            )
        )
        XCTAssertEqual(rail.events.count, 1)
        XCTAssertNil(rail.events[0].leadingWing)
        XCTAssertNil(rail.events[0].trailingWing)
    }

    func testFirstGapUsesBufferedStarts() throws {
        let lunchBuffer = CaptureEventBuffer(
            beforeMinutes: 30,
            afterMinutes: 0,
            timeRange: "1130-1300",
            startsAt: "2026-08-28T11:30",
            endsAt: "2026-08-28T13:00"
        )
        let events = CaptureAgendaEvents(rows: [makeRow(buffer: lunchBuffer)])
        let rail = try XCTUnwrap(
            CaptureAgendaPresentation.makeCalendarRail(
                events: events,
                entries: [],
                now: dateAt("2026-08-28T10:00")
            )
        )
        // The gap ends at the buffered start (11:30), not the meeting
        // start (12:00): 90 minutes from 10:00.
        XCTAssertEqual(rail.firstGap?.minutes, 90)
    }

    // MARK: - Rows and chips

    func testBufferedRowCarriesCapsuleLabelAndHoldText() {
        let buffer = CaptureEventBuffer(
            beforeMinutes: 30,
            afterMinutes: 15,
            timeRange: "1130-1315",
            startsAt: "2026-08-28T11:30",
            endsAt: "2026-08-28T13:15"
        )
        let row = CaptureAgendaPresentation.makeCalendarEventRow(
            makeRow(buffer: buffer),
            countdown: nil,
            startHint: nil,
            now: dateAt("2026-08-28T11:40")
        )
        XCTAssertEqual(row.calendar?.bufferLabel, "\u{2212}30m +15m")
        XCTAssertEqual(row.calendar?.bufferActive, true)
        XCTAssertTrue(
            row.accessibilityLabel?.contains("30-minute buffer before") ?? false
        )
        XCTAssertTrue(
            row.accessibilityLabel?.contains("holds 11:30 to 13:15") ?? false
        )
    }

    func testUnbufferedRowHasNoCapsule() {
        let row = CaptureAgendaPresentation.makeCalendarEventRow(
            makeRow(),
            countdown: nil,
            startHint: nil,
            now: dateAt("2026-08-28T10:00")
        )
        XCTAssertNil(row.calendar?.bufferLabel)
        XCTAssertEqual(row.calendar?.bufferActive, false)
        XCTAssertFalse(row.accessibilityLabel?.contains("buffer") ?? true)
    }

    func testMeetTimeChipAppendsBufferLabel() {
        let entry = CaptureAgendaPomodoro(line: 13, name: "MEET", role: .next)
        let buffered = CaptureAgendaItem(
            ledgerLine: 14,
            blockID: "lunch",
            text: "**1200-1300** Lunch",
            event: CaptureAgendaItemEvent(
                timeRange: "1200-1300",
                startsAt: "2026-08-28T12:00",
                endsAt: "2026-08-28T13:00",
                title: "Lunch",
                buffer: CaptureEventBuffer(beforeMinutes: 30, afterMinutes: 15)
            )
        )
        XCTAssertEqual(
            CaptureAgendaPresentation.eventTimeChip(item: buffered, entry: entry),
            "12:00–13:00 \u{2212}30m +15m"
        )
        let plain = CaptureAgendaItem(
            ledgerLine: 15,
            blockID: "standup",
            text: "**0930-1000** Standup",
            event: CaptureAgendaItemEvent(
                startsAt: "2026-08-28T09:30",
                endsAt: "2026-08-28T10:00",
                title: "Standup"
            )
        )
        XCTAssertEqual(
            CaptureAgendaPresentation.eventTimeChip(item: plain, entry: entry),
            "09:30–10:00"
        )
    }

    // MARK: - Conflict rows and preview cards

    func testCalendarConflictRowUsesBufferPart() {
        let buffer = CaptureEventBuffer(beforeMinutes: 30, afterMinutes: 15)
        let row = makeRow(title: "Lunch", buffer: buffer)
        let conflict = CaptureAgendaEventConflict(
            pomodoroLine: 7,
            event: 0,
            overlapMinutes: 5,
            bufferPart: .before
        )
        let entry = CaptureAgendaPomodoro(line: 7, name: "BOB", role: .current)
        let card = CaptureAgendaPresentation.makeCalendarConflictRow(
            conflict,
            events: CaptureAgendaEvents(rows: [row]),
            entries: [entry]
        )
        XCTAssertEqual(card?.text, "BOB runs 5m into Lunch's \u{2212}30m buffer")

        let plain = CaptureAgendaPresentation.makeCalendarConflictRow(
            CaptureAgendaEventConflict(pomodoroLine: 7, event: 0, overlapMinutes: 10),
            events: CaptureAgendaEvents(rows: [makeRow(title: "Standup")]),
            entries: [entry]
        )
        XCTAssertEqual(plain?.text, "BOB runs 10m into Standup")
    }

    func testEventRunCaptionAppendsBufferLabels() {
        let run = PomodoroEventRun(
            timeRange: "1130-1315",
            start: "1130",
            end: "1315",
            offClock: true,
            source: "calendar",
            events: [
                PomodoroEventRunEvent(
                    title: "Lunch with Kelly",
                    timeRange: "1200-1300",
                    offClock: true,
                    buffer: CaptureEventBuffer(beforeMinutes: 30, afterMinutes: 15)
                )
            ]
        )
        let summary = PomodoroStartSummary(
            start: "1130",
            end: "1315",
            durationMinutes: 165,
            offsetUnits: 0,
            pomodoroName: "MEET",
            pomodoroLine: 14,
            createdPomodoro: false,
            timeRange: "(**1130-1315**)",
            eventRun: run
        )
        let presentation = CapturePomodoroStartPresentation(
            summary: summary,
            dryRun: true,
            captureText: "=meet"
        )
        let expected =
            "MEET · 11:30–13:15 · from your calendar · Lunch with Kelly "
            + "\u{2212}30m +15m · off-clock"
        XCTAssertEqual(presentation.eventRunText, expected)
    }

    func testPreviewConflictHeadlineUsesBufferPart() {
        let conflicted = CaptureEventConflictPresentation(
            PomodoroEventConflict(
                event: PomodoroEventConflictEvent(
                    title: "Lunch",
                    timeRange: "1200-1300",
                    offClock: true,
                    buffer: CaptureEventBuffer(beforeMinutes: 30, afterMinutes: 15)
                ),
                overlapMinutes: 10,
                bufferPart: .after
            ),
            sessionName: "BOB"
        )
        XCTAssertEqual(conflicted.headline, "BOB runs 10m into Lunch's +15m buffer")

        let plain = CaptureEventConflictPresentation(
            PomodoroEventConflict(
                event: PomodoroEventConflictEvent(title: "Standup", timeRange: "1200-1230"),
                overlapMinutes: 15
            ),
            sessionName: "BOB"
        )
        XCTAssertEqual(plain.headline, "BOB runs 15m into Standup")
    }
}
