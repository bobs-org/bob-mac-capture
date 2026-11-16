import XCTest

@testable import CaptureCore

final class NoteGotoRecentPresentationTests: XCTestCase {
    private func candidate(
        _ path: String,
        title: String? = nil,
        group: String? = "areas",
        kind: String = "note",
        rank: Int = 4
    ) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            detail: nil,
            kind: kind,
            matchKeys: [title ?? path],
            rank: rank,
            hue: nil,
            status: nil,
            title: title,
            depth: nil,
            group: group,
            notePath: path
        )
    }

    private func noteGoto(vaultRoot: String = "/vault") -> CaptureCompletionNoteGoto {
        CaptureCompletionNoteGoto(vaultRoot: vaultRoot, listed: 3)
    }

    func testRecentOmittedWhenEmpty() {
        let values = [
            candidate("2026/20261114.md", title: "Today", group: "today"),
            candidate("Areas/cash.md", title: "cash"),
        ]
        let presentation = NoteGotoPickerIndex(
            candidates: values,
            noteGoto: noteGoto()
        ).presentation(filter: "//")

        XCTAssertFalse(presentation.sections.map(\.title).contains("Recent"))
        XCTAssertFalse(presentation.orderedRowIDs.contains { $0.hasPrefix("recent:") })
        XCTAssertEqual(presentation.totalCount, 2)
    }

    func testRecentSitsAfterTodayBeforeInbox() {
        let values = [
            candidate("2026/20261114.md", title: "Today", group: "today"),
            candidate("mac_inbox.md", title: "inbox", group: "inbox"),
            candidate("Areas/cash.md", title: "cash"),
        ]
        let presentation = NoteGotoPickerIndex(
            candidates: values,
            noteGoto: noteGoto(),
            recentNotePaths: ["Areas/cash.md"]
        ).presentation(filter: "//")

        XCTAssertEqual(
            presentation.sections.map(\.title),
            ["Today", "Recent", "Inbox", "Areas"]
        )
        let recent = try? XCTUnwrap(presentation.sections.first { $0.title == "Recent" })
        XCTAssertEqual(recent?.rows.map(\.id), ["recent:Areas/cash.md"])
        XCTAssertEqual(recent?.id, "note-goto-group-recent")
    }

    func testRecentFirstWithoutToday() {
        let values = [
            candidate("mac_inbox.md", title: "inbox", group: "inbox"),
            candidate("Areas/cash.md", title: "cash"),
        ]
        let presentation = NoteGotoPickerIndex(
            candidates: values,
            noteGoto: noteGoto(),
            recentNotePaths: ["Areas/cash.md"]
        ).presentation(filter: "//")

        XCTAssertEqual(presentation.sections.first?.title, "Recent")
    }

    func testRecentCapsAtEightNewestFirstSkipsMissingAndTodayDuplicates() {
        var values = [candidate("2026/20261114.md", title: "Today", group: "today")]
        for index in 0..<10 {
            values.append(candidate("Notes/n\(index).md", title: "n\(index)"))
        }
        // Newest first: n9 down to n0, plus a Today duplicate, a missing path,
        // and a duplicate entry.
        let recent = [
            "Notes/n9.md", "Notes/n8.md", "missing.md", "2026/20261114.md",
            "Notes/n7.md", "Notes/n6.md", "Notes/n5.md", "Notes/n4.md",
            "Notes/n3.md", "Notes/n2.md", "Notes/n1.md", "Notes/n0.md",
            "Notes/n9.md",
        ]
        let presentation = NoteGotoPickerIndex(
            candidates: values,
            noteGoto: noteGoto(),
            recentNotePaths: recent
        ).presentation(filter: "//")

        let recentSection = try? XCTUnwrap(presentation.sections.first { $0.title == "Recent" })
        XCTAssertEqual(recentSection?.rows.count, 8)
        XCTAssertEqual(
            recentSection?.rows.map(\.id),
            [
                "recent:Notes/n9.md", "recent:Notes/n8.md", "recent:Notes/n7.md",
                "recent:Notes/n6.md", "recent:Notes/n5.md", "recent:Notes/n4.md",
                "recent:Notes/n3.md", "recent:Notes/n2.md",
            ]
        )
    }

    func testRecentRowsReuseBobPresentationWithDistinctIDs() throws {
        let values = [
            candidate("Areas/cash.md", title: "cash", group: "areas", kind: "area")
        ]
        let index = NoteGotoPickerIndex(
            candidates: values,
            noteGoto: noteGoto(vaultRoot: "/vault"),
            recentNotePaths: ["Areas/cash.md"]
        )
        let presentation = index.presentation(filter: "//")
        let bobRow = try XCTUnwrap(presentation.row(id: "Areas/cash.md"))
        let recentRow = try XCTUnwrap(presentation.row(id: "recent:Areas/cash.md"))

        XCTAssertEqual(recentRow.displayText, bobRow.displayText)
        XCTAssertEqual(recentRow.glyph, bobRow.glyph)
        XCTAssertEqual(recentRow.route, bobRow.route)
        XCTAssertEqual(
            recentRow.noteGotoDestination,
            bobRow.noteGotoDestination
        )
        XCTAssertNotNil(recentRow.noteGotoDestination)
        // The note stays in its Bob group too.
        XCTAssertTrue(presentation.orderedRowIDs.contains("Areas/cash.md"))
        XCTAssertTrue(presentation.orderedRowIDs.contains("recent:Areas/cash.md"))
    }

    func testHintCountUnchangedByRecent() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtureURL("note-goto.json"))
        )
        let plain = NoteGotoPickerIndex(
            candidates: response.candidates,
            noteGoto: try XCTUnwrap(response.noteGoto)
        ).presentation(filter: "//")
        let hintBefore = plain.sections.last?.rows.first?.displayText

        let withRecent = NoteGotoPickerIndex(
            candidates: response.candidates,
            noteGoto: try XCTUnwrap(response.noteGoto),
            recentNotePaths: ["Areas/cash.md", "Other/money.md"]
        ).presentation(filter: "//")

        XCTAssertEqual(withRecent.sections.last?.rows.first?.displayText, hintBefore)
        XCTAssertEqual(withRecent.totalCount, plain.totalCount)
        XCTAssertEqual(withRecent.matchCount, plain.matchCount)
        XCTAssertEqual(withRecent.countText, plain.countText)
    }

    func testFilteredViewIgnoresRecent() {
        let values = [
            candidate("Areas/cash.md", title: "cash"),
            candidate("Other/money.md", title: "Money plan"),
        ]
        let presentation = NoteGotoPickerIndex(
            candidates: values,
            noteGoto: noteGoto(),
            recentNotePaths: ["Areas/cash.md"]
        ).presentation(filter: "//cash")

        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertFalse(presentation.orderedRowIDs.contains { $0.hasPrefix("recent:") })
        XCTAssertEqual(presentation.orderedRowIDs, ["Areas/cash.md"])
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
    }
}
