import XCTest

@testable import CaptureCore

final class CaptureAgendaModelsTests: XCTestCase {
    private static let agendaFixtures = [
        "agenda-current.json",
        "agenda-current-12.json",
        "agenda-empty.json",
        "agenda-heavy.json",
        "agenda-multiple-timed.json",
        "agenda-no-daily-note.json",
        "agenda-nothing-running.json",
        "agenda-nothing-running-past-3.json",
        "agenda-past-12.json",
        "agenda-yesterday.json",
        "agenda-homes.json",
        "agenda-homes-legacy.json",
        "agenda-events.json",
        "agenda-events-buffered.json",
    ]

    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    private func decodeFixture(_ name: String) throws -> CaptureAgendaSnapshot {
        try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: fixture(name)
        )
    }

    func testEveryAgendaFixtureDecodes() throws {
        for name in Self.agendaFixtures {
            let snapshot = try decodeFixture(name)
            XCTAssertTrue(snapshot.ok, name)
            XCTAssertEqual(snapshot.schemaVersion, 1, name)
            switch name {
            case "agenda-nothing-running-past-3.json":
                XCTAssertEqual(snapshot.maxTaskLinkCount, 3, name)
            case "agenda-past-12.json":
                XCTAssertEqual(snapshot.maxTaskLinkCount, 12, name)
            default:
                XCTAssertNil(snapshot.maxTaskLinkCount, name)
            }
        }
    }

    func testCurrentFixtureCarriesRolesNumbersAndBlocks() throws {
        let snapshot = try decodeFixture("agenda-current.json")

        XCTAssertEqual(snapshot.date, "2026-08-28")
        XCTAssertEqual(snapshot.completedSummary.count, 1)
        XCTAssertEqual(snapshot.completedSummary.minutes, 30)
        XCTAssertEqual(snapshot.currentTaskLinkCount, 3)

        let roles = snapshot.pomodoros.map(\.role)
        XCTAssertEqual(roles, [.current, .next, .later, .later])

        let current = snapshot.pomodoros[0]
        XCTAssertEqual(current.name, "FIX")
        XCTAssertTrue(current.isCurrent)
        XCTAssertEqual(current.startsAt, "2026-08-28T08:00")
        XCTAssertEqual(current.endsAt, "2026-08-28T08:30")
        XCTAssertEqual(current.retiredLinkCount, 1)
        XCTAssertEqual(current.items.count, 3)

        let first = current.items[0]
        XCTAssertEqual(first.index, 1)
        XCTAssertEqual(first.ledgerLine, 6)
        XCTAssertEqual(first.ledgerDepth, 1)
        XCTAssertEqual(first.marker, .plain)
        XCTAssertEqual(first.resolution, .resolved)
        XCTAssertEqual(first.relativeTarget, "tasks.md")
        XCTAssertEqual(first.blockID, "deep-fix")
        XCTAssertEqual(first.text, "Deep fix")
        XCTAssertEqual(first.statusSymbol, " ")
        XCTAssertEqual(first.statusName, "Todo")
        XCTAssertEqual(first.statusType, "TODO")
        XCTAssertEqual(first.linesTruncated, 0)
        XCTAssertEqual(first.lines.count, 3)
        XCTAssertEqual(first.lines[0].kind, .bullet)
        XCTAssertNil(first.lines[0].log)
        XCTAssertEqual(first.lines[1].kind, .logMarker)
        XCTAssertEqual(first.lines[1].log, .work)
        XCTAssertEqual(first.lines[2].log, .work)
        XCTAssertNil(first.warning)

        XCTAssertEqual(current.notes.count, 1)
        XCTAssertEqual(current.notes[0].text, "epic on test")

        let missing = snapshot.pomodoros[1].items.first(where: {
            $0.resolution == .missingNote
        })
        XCTAssertNotNil(missing)
        XCTAssertEqual(missing?.blockLink, "[[missing#^gone]]")
        XCTAssertNotNil(missing?.warning)
    }

    func testYesterdayFixtureMovesOnlyTheDate() throws {
        let snapshot = try decodeFixture("agenda-yesterday.json")
        XCTAssertEqual(snapshot.date, "2026-08-27")
        XCTAssertEqual(snapshot.pomodoros.count, 4)
        XCTAssertEqual(snapshot.pomodoros.map(\.role), [.current, .next, .later, .later])
    }

    func testEmptyAndMissingNoteFixturesDecode() throws {
        let empty = try decodeFixture("agenda-empty.json")
        XCTAssertEqual(empty.date, "2026-08-28")
        XCTAssertTrue(empty.pomodoros.isEmpty)
        XCTAssertEqual(empty.completedSummary.count, 0)
        XCTAssertNil(empty.currentTaskLinkCount)
        XCTAssertNil(empty.planBudget)

        let missingNote = try decodeFixture("agenda-no-daily-note.json")
        XCTAssertTrue(missingNote.pomodoros.isEmpty)
        XCTAssertNil(missingNote.currentTaskLinkCount)
        XCTAssertNil(missingNote.planBudget)

        let multiple = try decodeFixture("agenda-multiple-timed.json")
        XCTAssertEqual(multiple.pomodoros.map(\.role), [.open, .open, .next])
        XCTAssertEqual(multiple.pomodoros[0].startsAt, "2026-08-28T08:00")

        let heavy = try decodeFixture("agenda-heavy.json")
        XCTAssertEqual(heavy.pomodoros.count, 25)
        XCTAssertTrue(heavy.pomodoros.allSatisfy({ !$0.items.isEmpty }))
    }

    func testPlanBudgetDecodesCountsCapsAndOverStateAndToleratesAbsence() throws {
        let json = """
        {
          "ok": true,
          "schema_version": 1,
          "date": "2026-08-28",
          "plan_budget": {
            "status": "ok",
            "themes": {"count": 3, "cap": 3, "over": false},
            "links": {"count": 11, "cap": 10, "over": true}
          }
        }
        """.data(using: .utf8) ?? Data()
        let snapshot = try JSONDecoder().decode(CaptureAgendaSnapshot.self, from: json)

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.planBudget?.links.count, 11)
        XCTAssertEqual(snapshot.planBudget?.links.cap, 10)
        XCTAssertEqual(snapshot.planBudget?.links.over, true)
        XCTAssertNil(snapshot.planBudget?.links.before)

        let cliSnapshot = try decodeFixture("pomodoro-start-blocks.json")
        XCTAssertEqual(cliSnapshot.planBudget?.links.count, 0)
        XCTAssertEqual(cliSnapshot.planBudget?.links.cap, 10)

        let absent = try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data(#"{"ok":true,"date":"2026-08-28"}"#.utf8)
        )
        let null = try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data(#"{"ok":true,"date":"2026-08-28","plan_budget":null}"#.utf8)
        )
        XCTAssertNil(absent.planBudget)
        XCTAssertNil(null.planBudget)
    }

    func testUnknownEnumValuesDecodeToOther() throws {
        let json = """
        {
          "ok": true,
          "schema_version": 1,
          "date": "2026-08-28",
          "completed_summary": {"count": 0, "minutes": 0},
          "pomodoros": [
            {
              "line": 3,
              "name": "FUTURE",
              "is_current": false,
              "role": "time_travel",
              "retired_link_count": 0,
              "notes": [],
              "items": [
                {
                  "ledger_line": 4,
                  "ledger_depth": 1,
                  "marker": "smoke_signal",
                  "block_link": "[[tasks#^x]]",
                  "resolution": "abducted",
                  "lines": [
                    {"text": "hi", "depth": 1, "kind": "hologram", "log": "nap"}
                  ],
                  "ledger_notes": []
                }
              ]
            }
          ]
        }
        """.data(using: .utf8) ?? Data()
        let snapshot = try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: json
        )

        XCTAssertEqual(snapshot.pomodoros[0].role, .other("time_travel"))
        let item = snapshot.pomodoros[0].items[0]
        XCTAssertEqual(item.marker, .other("smoke_signal"))
        XCTAssertEqual(item.resolution, .other("abducted"))
        XCTAssertEqual(item.lines[0].kind, .other("hologram"))
        XCTAssertEqual(item.lines[0].log, .other("nap"))
    }

    func testRottenLogDecodesAndUnknownStaysOther() throws {
        let rotten = try JSONDecoder().decode(
            CaptureAgendaLog.self,
            from: Data(#""rotten""#.utf8)
        )
        XCTAssertEqual(rotten, .rotten)
        let unknown = try JSONDecoder().decode(
            CaptureAgendaLog.self,
            from: Data(#""nap""#.utf8)
        )
        XCTAssertEqual(unknown, .other("nap"))
        let json = """
        {
          "text": "Oct 16 — kept",
          "depth": 2,
          "kind": "bullet",
          "log": "rotten"
        }
        """.data(using: .utf8) ?? Data()
        let line = try JSONDecoder().decode(CaptureAgendaLine.self, from: json)
        XCTAssertEqual(line.log, .rotten)
    }

    func testMissingFieldsDecodeToDefaults() throws {
        let json = """
        {"ok": true, "pomodoros": [{"line": 3, "items": [{}], "notes": [{}]}]}
        """.data(using: .utf8) ?? Data()
        let snapshot = try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: json
        )

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertNil(snapshot.date)
        XCTAssertEqual(snapshot.completedSummary, CaptureAgendaCompletedSummary())
        let entry = snapshot.pomodoros[0]
        XCTAssertNil(entry.name)
        XCTAssertFalse(entry.isCurrent)
        XCTAssertNil(entry.taskLinkCount)
        XCTAssertEqual(entry.role, .open)
        XCTAssertNil(entry.startsAt)
        XCTAssertNil(entry.endsAt)
        XCTAssertEqual(entry.retiredLinkCount, 0)
        let item = entry.items[0]
        XCTAssertNil(item.index)
        XCTAssertEqual(item.ledgerLine, 0)
        XCTAssertEqual(item.ledgerDepth, 1)
        XCTAssertEqual(item.marker, .plain)
        XCTAssertEqual(item.resolution, .unreadable)
        XCTAssertEqual(item.blockID, "")
        XCTAssertTrue(item.lines.isEmpty)
        XCTAssertEqual(item.linesTruncated, 0)
        XCTAssertTrue(item.ledgerNotes.isEmpty)
        XCTAssertNil(item.warning)
        XCTAssertEqual(entry.notes[0].kind, .bullet)
        XCTAssertEqual(entry.notes[0].depth, 1)
    }

    func testWarningsSlugAndSelectableDecode() throws {
        let current = try decodeFixture("agenda-current.json")
        XCTAssertTrue(current.warnings.isEmpty)
        XCTAssertEqual(current.pomodoros[0].slug, "fix")
        XCTAssertTrue(current.pomodoros[0].selectable)
        let unnamed = current.pomodoros[3]
        XCTAssertNil(unnamed.name)
        XCTAssertEqual(unnamed.slug, "")
        XCTAssertFalse(unnamed.selectable)

        let missingNote = try decodeFixture("agenda-no-daily-note.json")
        XCTAssertFalse(missingNote.warnings.isEmpty)
        XCTAssertTrue(missingNote.pomodoros.isEmpty)
    }

    func testEventsBlockDecodesOffClockFlagsAndSummary() throws {
        let snapshot = try decodeFixture("agenda-events.json")

        XCTAssertEqual(snapshot.completedSummary.offClock.count, 1)
        XCTAssertEqual(snapshot.completedSummary.offClock.minutes, 30)
        let events = try XCTUnwrap(snapshot.events)
        XCTAssertEqual(events.syncedAt, "2026-08-28T08:02")
        XCTAssertEqual(events.refreshAt, "2026-08-28T09:30")
        XCTAssertEqual(events.focus, 0)
        XCTAssertEqual(events.startHint, "=meet")
        XCTAssertEqual(events.allDay.count, 1)
        XCTAssertEqual(events.allDay[0].title, "School holiday")
        XCTAssertEqual(events.rows.count, 3)

        let standup = events.rows[0]
        XCTAssertEqual(standup.kind, .task)
        XCTAssertEqual(standup.phase, .upcoming)
        XCTAssertFalse(standup.offClock)
        XCTAssertEqual(standup.home?.label, "job")
        XCTAssertEqual(standup.home?.hue, .green)
        XCTAssertEqual(standup.joinURL, "https://meet.google.com/abc")
        XCTAssertEqual(standup.pomodoro?.line, 13)
        XCTAssertEqual(standup.pomodoro?.role, .next)

        let lunch = events.rows[2]
        XCTAssertTrue(lunch.offClock)
        XCTAssertNil(lunch.home)
        XCTAssertNil(lunch.joinURL)

        let conflict = try XCTUnwrap(events.conflict)
        XCTAssertEqual(conflict.pomodoroLine, 12)
        XCTAssertEqual(conflict.event, 0)
        XCTAssertEqual(conflict.overlapMinutes, 10)

        let timeless = events.rows[1]
        XCTAssertEqual(timeless.kind, .timedContext)
        XCTAssertEqual(timeless.qualifier, "maybe")

        let meet = snapshot.pomodoros.first(where: { $0.name == "MEET" })
        let linked = try XCTUnwrap(meet?.items.first(where: { $0.event != nil }))
        XCTAssertEqual(linked.event?.title, "Standup")
        XCTAssertFalse(linked.event?.offClock ?? true)
        let lunchItem = try XCTUnwrap(meet?.items.first(where: { $0.blockID == "lunch" }))
        XCTAssertTrue(lunchItem.event?.offClock ?? false)

        let offClockEntry = snapshot.pomodoros.first(where: { $0.name == "OFF-CLOCK BREAK" })
        XCTAssertEqual(offClockEntry?.offClock, true)
        XCTAssertEqual(offClockEntry?.homes?.offClock, true)
    }

    func testOlderPayloadsDecodeWithoutEvents() throws {
        let current = try decodeFixture("agenda-current.json")
        XCTAssertNil(current.events)
        XCTAssertEqual(current.completedSummary.offClock.count, 0)
        XCTAssertTrue(current.pomodoros.allSatisfy({ $0.offClock == nil }))
        XCTAssertTrue(current.pomodoros.allSatisfy({ $0.items.allSatisfy({ $0.event == nil }) }))

        let empty = try decodeFixture("agenda-empty.json")
        XCTAssertNil(empty.events)
    }

    func testLegacyOffClockKeysDecodeAndNewKeysTakePrecedence() throws {
        let legacy = #"""
            {
              "completed_summary": {"count": 2, "minutes": 55, "untracked_count": 3},
              "pomodoros": [
                {"line": 1, "tracked": false, "homes": {"untracked": true}},
                {"line": 2, "tracked": true},
                {"line": 3}
              ],
              "events": {"rows": [
                {"line": 1, "title": "Lunch", "untracked": true}
              ]}
            }
            """#
        let old = try JSONDecoder().decode(CaptureAgendaSnapshot.self, from: Data(legacy.utf8))
        XCTAssertEqual(old.completedSummary.offClock.count, 3)
        XCTAssertEqual(old.completedSummary.offClock.minutes, 0)
        XCTAssertEqual(old.pomodoros[0].offClock, true)
        XCTAssertEqual(old.pomodoros[0].homes?.offClock, true)
        XCTAssertEqual(old.pomodoros[1].offClock, false)
        XCTAssertNil(old.pomodoros[2].offClock)
        XCTAssertTrue(old.events?.rows.first?.offClock ?? false)
        let oldItemEvent = try JSONDecoder().decode(
            CaptureAgendaItemEvent.self,
            from: Data(#"{"untracked":true,"title":"Lunch"}"#.utf8)
        )
        XCTAssertTrue(oldItemEvent.offClock)

        let current = #"""
            {
              "completed_summary": {
                "count": 0, "minutes": 0,
                "off_clock": {"count": 1, "minutes": 25},
                "untracked_count": 9
              },
              "pomodoros": [{
                "line": 1, "off_clock": false, "tracked": false,
                "homes": {"off_clock": false, "untracked": true}
              }],
              "events": {"rows": [
                {"line": 1, "title": "Lunch", "off_clock": false, "untracked": true}
              ]}
            }
            """#
        let new = try JSONDecoder().decode(CaptureAgendaSnapshot.self, from: Data(current.utf8))
        XCTAssertEqual(new.completedSummary.offClock.count, 1)
        XCTAssertEqual(new.completedSummary.offClock.minutes, 25)
        XCTAssertEqual(new.pomodoros.first?.offClock, false)
        XCTAssertEqual(new.pomodoros.first?.homes?.offClock, false)
        XCTAssertEqual(new.events?.rows.first?.offClock, false)
        let newItemEvent = try JSONDecoder().decode(
            CaptureAgendaItemEvent.self,
            from: Data(#"{"off_clock":false,"untracked":true,"title":"Lunch"}"#.utf8)
        )
        XCTAssertFalse(newItemEvent.offClock)
    }

    func testUnknownEventEnumsDecodeToOther() throws {
        let raw =
            "{\"line\": 7, \"kind\": \"holiday\", \"phase\": \"someday\","
            + " \"title\": \"Mystery\", \"untracked\": false}"
        let payload = Data(raw.utf8)
        let row = try JSONDecoder().decode(CaptureAgendaEventRow.self, from: payload)
        XCTAssertEqual(row.kind, .other("holiday"))
        XCTAssertEqual(row.phase, .other("someday"))
    }

    func testLegacyPayloadWithoutTasksFieldsDecodesWithEmptyItems() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/pomodoros-current-3.json")
        let snapshot = try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data(contentsOf: url)
        )

        XCTAssertTrue(snapshot.ok)
        XCTAssertFalse(snapshot.pomodoros.isEmpty)
        XCTAssertNil(snapshot.date)
        XCTAssertTrue(snapshot.pomodoros.allSatisfy({ $0.items.isEmpty }))
        XCTAssertTrue(snapshot.pomodoros.allSatisfy({ $0.notes.isEmpty }))
        XCTAssertTrue(snapshot.pomodoros.allSatisfy({ $0.role == .open }))
        XCTAssertEqual(snapshot.completedSummary, CaptureAgendaCompletedSummary())
    }
}
