import XCTest

@testable import CaptureCore

final class WalkAttentionPresentationTests: XCTestCase {
    private let locale = Locale(identifier: "en_US_POSIX")
    private let today = "2026-11-17"

    private func walksFixture(_ name: String) throws -> WalkAttentionSnapshot {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(
            WalkAttentionSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    private func agendaFixture(_ name: String) throws -> CaptureAgendaSnapshot {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    func testMarksAreInSelectorOrderWithCounts() throws {
        let walks = try walksFixture("walks-all.json")
        let marks = CaptureAgendaPresentation.makeWalkMarks(walks: walks, today: today)
        XCTAssertEqual(marks.map(\.family), ["s", "w", "b"])
        XCTAssertEqual(marks.map(\.tier), ["next", "over", "waiting"])
        // mark_counts = yes: s carries commitments, b carries waiting,
        // w stays a bare mark.
        XCTAssertEqual(marks[0].count, 16)
        XCTAssertNil(marks[1].count)
        XCTAssertEqual(marks[2].count, 3)
    }

    func testCalmAndUnavailableFamiliesAreFiltered() throws {
        let clear = try walksFixture("walks-clear.json")
        XCTAssertTrue(
            CaptureAgendaPresentation.makeWalkMarks(walks: clear, today: today).isEmpty)

        let bankDown = try walksFixture("walks-bank-unavailable.json")
        XCTAssertTrue(
            CaptureAgendaPresentation.makeWalkMarks(walks: bankDown, today: today).isEmpty)
    }

    func testDateGuardEmptiesOtherDayAndNil() throws {
        let walks = try walksFixture("walks-all.json")
        XCTAssertTrue(
            CaptureAgendaPresentation.makeWalkMarks(walks: walks, today: "2026-11-18").isEmpty)
        XCTAssertTrue(
            CaptureAgendaPresentation.makeWalkMarks(walks: nil, today: today).isEmpty)
    }

    func testAttentionWithoutTierOrLabelIsDropped() throws {
        let snapshot = try JSONDecoder().decode(
            WalkAttentionSnapshot.self,
            from: Data(
                #"{"date": "2026-11-17", "walks": [{"family": "s", "available": true, "attention": true}]}"#
                    .utf8
            )
        )
        XCTAssertTrue(
            CaptureAgendaPresentation.makeWalkMarks(walks: snapshot, today: today).isEmpty)
    }

    func testPresentationThreadsMarksIntoTitleRowInEveryState() throws {
        let walks = try walksFixture("walks-all.json")

        let empty = try agendaFixture("agenda-empty.json")
        let agenda = CaptureAgendaPresentation(snapshot: empty, today: "2026-08-28", walks: walks)
        // Walks fixture is dated 2026-11-17, so the date guard empties it here.
        XCTAssertTrue(agenda.walkMarks.isEmpty)
        XCTAssertTrue(agenda.titleRow.walkMarks.isEmpty)

        let sameDayAgenda = CaptureAgendaPresentation(
            snapshot: empty, today: "2026-08-28", walks: try JSONDecoder().decode(
                WalkAttentionSnapshot.self,
                from: Data(
                    #"{"date": "2026-08-28", "walks": [{"family": "b", "available": true, "attention": true, "tier": "waiting", "label": "Bank: 1 waiting", "counts": {"waiting": 1}}]}"#
                        .utf8
                )
            ))
        XCTAssertEqual(sameDayAgenda.walkMarks.map(\.family), ["b"])
        XCTAssertEqual(sameDayAgenda.titleRow.walkMarks.map(\.family), ["b"])
        XCTAssertTrue(
            sameDayAgenda.titleRow.accessibilityLabel?.contains("Walks needing attention: Bank: 1 waiting")
                == true)

        let loading = CaptureAgendaPresentation.loading(today: "2026-08-28", walks: sameDayAgenda.titleRow.walkMarks.isEmpty ? nil : nil)
        XCTAssertTrue(loading.walkMarks.isEmpty)
        let loadingWithWalks = CaptureAgendaPresentation.loading(
            today: today, walks: walks)
        XCTAssertEqual(loadingWithWalks.walkMarks.map(\.family), ["s", "w", "b"])
        XCTAssertEqual(loadingWithWalks.titleRow.walkMarks.map(\.family), ["s", "w", "b"])
    }

    func testAccessibilityLabelJoinsLabels() throws {
        let walks = try walksFixture("walks-all.json")
        let agenda = try agendaFixture("agenda-current.json")
        let presentation = CaptureAgendaPresentation(
            snapshot: agenda, today: "2026-08-28",
            walks: try JSONDecoder().decode(
                WalkAttentionSnapshot.self,
                from: Data(
                    #"{"date": "2026-08-28", "walks": [{"family": "s", "available": true, "attention": true, "tier": "next", "label": "Review: 2 due", "counts": {"walk": 2, "commitments": 2}}, {"family": "b", "available": true, "attention": true, "tier": "waiting", "label": "Bank: 1 waiting", "counts": {"waiting": 1}}]}"#
                        .utf8
                )
            ))
        _ = walks
        XCTAssertTrue(
            presentation.titleRow.accessibilityLabel?.contains(
                "Walks needing attention: Review: 2 due; Bank: 1 waiting") == true)
    }

    func testRowKeyChangesWhenMarksChange() throws {
        let agenda = try agendaFixture("agenda-current.json")
        let plain = CaptureAgendaPresentation(snapshot: agenda, today: "2026-08-28")
        let walks = try JSONDecoder().decode(
            WalkAttentionSnapshot.self,
            from: Data(
                #"{"date": "2026-08-28", "walks": [{"family": "s", "available": true, "attention": true, "tier": "next", "label": "Review: 1 due", "counts": {"walk": 1, "commitments": 1}}]}"#
                    .utf8
            )
        )
        let marked = CaptureAgendaPresentation(
            snapshot: agenda, today: "2026-08-28", walks: walks)
        XCTAssertNotEqual(plain.titleRow.key, marked.titleRow.key)
        XCTAssertEqual(marked.titleRow.key.walkMarks.map(\.family), ["s"])
        XCTAssertTrue(marked.titleRow.key.hasAccessory)
    }
}
