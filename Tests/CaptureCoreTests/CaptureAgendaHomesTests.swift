import XCTest

@testable import CaptureCore

final class CaptureAgendaHomesTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let today = "2026-08-28"

    private func fixture(_ name: String) throws -> CaptureAgendaSnapshot {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    private func present(_ snapshot: CaptureAgendaSnapshot) -> CaptureAgendaPresentation {
        CaptureAgendaPresentation(
            snapshot: snapshot,
            today: today,
            now: nil,
            locale: locale
        )
    }

    func testHomesFixtureDecodesNamedUnnamedUnlinkedAndParts() throws {
        let snapshot = try fixture("agenda-homes.json")
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.pomodoros.count, 4)

        let namedSuppressed = snapshot.pomodoros[0]
        XCTAssertEqual(namedSuppressed.name, "BOB")
        XCTAssertEqual(namedSuppressed.homes?.state, .forecast)
        XCTAssertEqual(namedSuppressed.homes?.kind, .work)
        XCTAssertEqual(namedSuppressed.homes?.label, "bob")
        XCTAssertNil(namedSuppressed.homes?.chip)
        XCTAssertEqual(namedSuppressed.homes?.hue, .orange)
        XCTAssertEqual(namedSuppressed.homes?.parts.count, 1)
        XCTAssertEqual(namedSuppressed.homes?.parts[0].kind, .project)
        XCTAssertEqual(namedSuppressed.homes?.parts[0].areaLabel, "gtd")
        XCTAssertNil(namedSuppressed.homes?.parts[0].minutes)

        let namedChip = snapshot.pomodoros[1]
        XCTAssertEqual(namedChip.name, "HACK")
        XCTAssertEqual(namedChip.homes?.chip, "bob · dev +1")
        XCTAssertEqual(namedChip.homes?.hue, .orange)

        let unnamed = snapshot.pomodoros[2]
        XCTAssertNil(unnamed.name)
        XCTAssertEqual(unnamed.homes?.label, "sase")
        XCTAssertEqual(unnamed.homes?.chip, "sase")

        let unlinked = snapshot.pomodoros[3]
        XCTAssertNil(unlinked.name)
        XCTAssertEqual(unlinked.homes?.kind, .unlinked)
        XCTAssertEqual(unlinked.homes?.label, "")
        XCTAssertNil(unlinked.homes?.chip)
        XCTAssertNil(unlinked.homes?.hue)
        XCTAssertEqual(unlinked.homes?.parts, [])
    }

    func testLegacyPayloadOmitsHomesAndKeepsUntitled() throws {
        let snapshot = try fixture("agenda-homes-legacy.json")
        XCTAssertNil(snapshot.pomodoros[0].homes)
        let presentation = present(snapshot)
        XCTAssertEqual(presentation.groups[0].name, "Untitled Pomodoro")
        XCTAssertFalse(presentation.groups[0].headerRow.nameIsDerived)
        XCTAssertNil(presentation.groups[0].headerRow.homeChip)
        XCTAssertEqual(
            presentation.groups[0].accessibilityLabel,
            "Next Pomodoro Untitled Pomodoro, 0 tasks"
        )
    }

    func testPresentationUsesDerivedLabelChipAndSpokenFor() throws {
        let presentation = present(try fixture("agenda-homes.json"))
        XCTAssertEqual(presentation.groups.map(\.name), [
            "BOB", "HACK", "sase", "Untitled Pomodoro",
        ])
        XCTAssertEqual(presentation.groups.map(\.stripName), presentation.groups.map(\.name))

        let bob = presentation.groups[0]
        XCTAssertFalse(bob.headerRow.nameIsDerived)
        XCTAssertNil(bob.headerRow.homeChip)
        XCTAssertEqual(bob.headerRow.accessibilityLabel, "Header, BOB")
        XCTAssertEqual(
            bob.accessibilityLabel,
            "Running Pomodoro BOB, 08:00 to 08:30, 0 tasks"
        )

        let hack = presentation.groups[1]
        XCTAssertFalse(hack.headerRow.nameIsDerived)
        XCTAssertEqual(hack.headerRow.homeChip, "bob · dev +1")
        XCTAssertEqual(hack.headerRow.homeHue, .orange)
        XCTAssertEqual(hack.oneRowRow.homeChip, "bob · dev +1")
        XCTAssertEqual(hack.headerRow.accessibilityLabel, "Header, HACK, for bob · dev +1")
        XCTAssertEqual(
            hack.accessibilityLabel,
            "Next Pomodoro HACK, for bob · dev +1, 0 tasks"
        )

        let sase = presentation.groups[2]
        XCTAssertTrue(sase.headerRow.nameIsDerived)
        XCTAssertNil(sase.headerRow.homeChip)
        XCTAssertEqual(sase.headerRow.text, "sase")
        XCTAssertTrue(sase.oneRowRow.nameIsDerived)
        XCTAssertEqual(sase.headerRow.accessibilityLabel, "Header, for sase")
        XCTAssertEqual(sase.accessibilityLabel, "Later Pomodoro for sase, 0 tasks")

        let unlinked = presentation.groups[3]
        XCTAssertFalse(unlinked.headerRow.nameIsDerived)
        XCTAssertEqual(unlinked.headerRow.text, "Untitled Pomodoro")
        XCTAssertNil(unlinked.headerRow.homeChip)

        XCTAssertEqual(presentation.stripFullRow.text, "Later · sase · Untitled Pomodoro")

        let notes = CaptureAgendaPomodoro(
            line: 40,
            name: "HACK",
            role: .next,
            notes: [CaptureAgendaLine(text: "keep")],
            homes: CaptureAgendaHomes(
                state: .forecast,
                kind: .work,
                label: "bob · dev +1",
                chip: "bob · dev +1",
                hue: .orange
            )
        )
        let withNotes = present(
            CaptureAgendaSnapshot(ok: true, date: today, pomodoros: [notes])
        )
        let folded = CaptureAgendaFitPlanner.headerWithNotesChip(group: withNotes.groups[0])
        XCTAssertEqual(folded.homeChip, "bob · dev +1")
        XCTAssertEqual(folded.homeHue, .orange)
        XCTAssertEqual(folded.notesChip, "1 notes")
    }

    func testUnknownHomesEnumsDecodeToOtherAndHuePaletteIsPinned() throws {
        let json = """
        {
          "ok": true,
          "schema_version": 1,
          "date": "2026-08-28",
          "pomodoros": [{
            "line": 3,
            "role": "next",
            "homes": {
              "state": "maybe",
              "kind": "mixed",
              "label": "x",
              "chip": "x",
              "hue": "chartreuse",
              "parts": [{
                "key": "x.md",
                "label": "x",
                "kind": "galaxy",
                "hue": "chartreuse",
                "tasks": 1,
                "share": 100
              }]
            }
          }]
        }
        """.data(using: .utf8) ?? Data()
        let snapshot = try JSONDecoder().decode(CaptureAgendaSnapshot.self, from: json)
        let homes = try XCTUnwrap(snapshot.pomodoros[0].homes)
        XCTAssertEqual(homes.state, .other("maybe"))
        XCTAssertEqual(homes.kind, .other("mixed"))
        XCTAssertEqual(homes.hue, .other("chartreuse"))
        XCTAssertEqual(homes.parts[0].kind, .other("galaxy"))
        XCTAssertNil(homes.hue?.lightHex)
        XCTAssertEqual(PomodoroHomeHue.blue.lightHex, "#2a78d6")
        XCTAssertEqual(PomodoroHomeHue.blue.darkHex, "#3987e5")
        XCTAssertEqual(PomodoroHomeHue.orange.lightHex, "#eb6834")
        XCTAssertEqual(PomodoroHomeHue.orange.darkHex, "#d95926")
        XCTAssertEqual(PomodoroHomeHue.aqua.lightHex, "#1baf7a")
        XCTAssertEqual(PomodoroHomeHue.yellow.lightHex, "#eda100")
        XCTAssertEqual(PomodoroHomeHue.magenta.lightHex, "#e87ba4")
        XCTAssertEqual(PomodoroHomeHue.green.lightHex, "#008300")
        XCTAssertEqual(PomodoroHomeHue.violet.lightHex, "#6250d6")
        XCTAssertEqual(PomodoroHomeHue.red.lightHex, "#e34948")
        XCTAssertEqual(PomodoroHomeHue.violet.darkHex, "#9085e9")
        XCTAssertEqual(PomodoroHomeHue.red.darkHex, "#e66767")
    }

    func testExistingAgendaFixtureStillDecodesWithoutHomes() throws {
        let snapshot = try fixture("agenda-current.json")
        XCTAssertTrue(snapshot.pomodoros.allSatisfy { $0.homes == nil })
    }
}
