import XCTest

@testable import CaptureCore

final class CaptureAgendaModelsTests: XCTestCase {
    private static let agendaFixtures = [
        "agenda-current.json",
        "agenda-empty.json",
        "agenda-heavy.json",
        "agenda-multiple-timed.json",
        "agenda-no-daily-note.json",
        "agenda-nothing-running.json",
        "agenda-yesterday.json",
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

        let missingNote = try decodeFixture("agenda-no-daily-note.json")
        XCTAssertTrue(missingNote.pomodoros.isEmpty)
        XCTAssertNil(missingNote.currentTaskLinkCount)

        let multiple = try decodeFixture("agenda-multiple-timed.json")
        XCTAssertEqual(multiple.pomodoros.map(\.role), [.open, .open, .next])
        XCTAssertEqual(multiple.pomodoros[0].startsAt, "2026-08-28T08:00")

        let heavy = try decodeFixture("agenda-heavy.json")
        XCTAssertEqual(heavy.pomodoros.count, 25)
        XCTAssertTrue(heavy.pomodoros.allSatisfy({ !$0.items.isEmpty }))
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
