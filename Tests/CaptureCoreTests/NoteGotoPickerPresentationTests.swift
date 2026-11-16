import XCTest

@testable import CaptureCore

final class NoteGotoPickerPresentationTests: XCTestCase {
    private func response() throws -> CaptureCompletionResponse {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/note-goto.json")
        return try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixture)
        )
    }

    private func index(
        _ candidates: [CaptureCompletionCandidate],
        vaultRoot: String = "/Users/example/Vault"
    ) -> NoteGotoPickerIndex {
        NoteGotoPickerIndex(
            candidates: candidates,
            noteGoto: CaptureCompletionNoteGoto(vaultRoot: vaultRoot, listed: candidates.count)
        )
    }

    private func candidate(
        _ path: String,
        title: String,
        keys: [String]? = nil,
        rank: Int = 8,
        kind: String = "note",
        detail: String? = nil,
        group: String? = nil,
        depth: Int? = nil,
        status: String? = nil,
        hue: PomodoroHomeHue? = nil
    ) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            detail: detail,
            kind: kind,
            matchKeys: keys ?? [title],
            rank: rank,
            hue: hue,
            status: status,
            title: title,
            depth: depth,
            group: group,
            notePath: path
        )
    }

    func testDecodesNoteGotoFixtureAndOldBobWithoutAdditiveFields() throws {
        let response = try response()
        XCTAssertEqual(response.context, "note_goto")
        XCTAssertEqual(
            response.noteGoto,
            CaptureCompletionNoteGoto(vaultRoot: "/Users/example/Vault", listed: 12)
        )
        let cash = try XCTUnwrap(response.candidates.first { $0.notePath == "Areas/cash.md" })
        XCTAssertEqual(cash.matchKeys, ["cash", "money"])
        XCTAssertEqual(cash.rank, 1)
        XCTAssertEqual(cash.hue, .green)

        let oldBob = Data(
            #"{"ok":true,"cursor":0,"replacement":{"start":0,"end":0},"context":"task_goto","candidates":[{"replacement":""}]}"#
                .utf8
        )
        let decoded = try JSONDecoder().decode(CaptureCompletionResponse.self, from: oldBob)
        XCTAssertNil(decoded.noteGoto)
        XCTAssertNil(decoded.candidates.first?.matchKeys)
        XCTAssertNil(decoded.candidates.first?.rank)
        XCTAssertNil(decoded.candidates.first?.hue)
    }

    func testGroupedMapUsesBobOrderAndShowsSearchHintForUngroupedNotes() throws {
        let response = try response()
        let index = NoteGotoPickerIndex(
            candidates: response.candidates,
            noteGoto: try XCTUnwrap(response.noteGoto)
        )
        let presentation = index.presentation(filter: "//")

        XCTAssertEqual(presentation.mode, .grouped)
        XCTAssertEqual(presentation.totalCount, 12)
        XCTAssertEqual(presentation.countText, "12 notes")
        XCTAssertEqual(
            presentation.sections.map(\.title),
            ["Today", "Inbox", "Areas", "Projects", "Notebooks", "Albums", ""]
        )
        XCTAssertEqual(presentation.sections.last?.kind, .noteGotoHint)
        XCTAssertEqual(
            presentation.sections.last?.rows.first?.displayText,
            "Type to search 5 more notes"
        )
        XCTAssertFalse(try XCTUnwrap(presentation.sections.last?.rows.first).isSelectable)
        XCTAssertEqual(presentation.orderedRowIDs.first, "2026/20261114.md")

        let childArea = try XCTUnwrap(presentation.row(id: "Areas/north-cash.md"))
        XCTAssertEqual(childArea.depth, 1)
        XCTAssertEqual(childArea.glyph, .noteGoto(symbol: "square.stack.3d.up", hue: .green))
        XCTAssertEqual(childArea.noteGotoSecondaryText, "Life / Money")
        XCTAssertEqual(
            childArea.accessibilityLabel,
            "Area, Cash planning, Life / Money, Areas/north-cash.md"
        )
        XCTAssertEqual(
            index.actionLine(for: try XCTUnwrap(presentation.row(id: "Areas/cash.md"))),
            "↩ Opens cash.md in Obsidian — nothing is written"
        )
        XCTAssertEqual(presentation.visibleRowBudget, 11)
    }

    func testFilteredRankingUsesPrimaryFieldsThenPathRankAndBobOrder() {
        let values = [
            candidate("Notes/rank-five.md", title: "Cash", rank: 5),
            candidate("Notes/rank-two.md", title: "Cash", rank: 2),
            candidate("Notes/bob-first.md", title: "Cash", rank: 2),
            candidate("Notes/bob-second.md", title: "Cash", rank: 2),
            candidate("Notes/cash-path.md", title: "Document", rank: 0),
        ]
        let presentation = index(values).presentation(filter: "//cash")

        XCTAssertEqual(
            presentation.orderedRowIDs,
            [
                "Notes/rank-two.md", "Notes/bob-first.md", "Notes/bob-second.md",
                "Notes/rank-five.md", "Notes/cash-path.md",
            ]
        )
        XCTAssertEqual(presentation.mode, .filtered)
        XCTAssertEqual(presentation.matchCount, 5)
        XCTAssertNil(presentation.row(id: "Notes/cash-path.md")?.badgeText)
    }

    func testFilteredSearchUsesAndTermsAliasesAndPathHighlights() throws {
        let values = [
            candidate(
                "Areas/north-cash.md",
                title: "Cash planning",
                keys: ["Cash planning", "cashflow"],
                rank: 1,
                kind: "area",
                detail: "Life / Money",
                group: "areas"
            ),
            candidate(
                "Other/ledger.md",
                title: "Family budget",
                keys: ["Family budget", "cash account"],
                rank: 8
            ),
            candidate(
                "Other/movie.md",
                title: "Favourite films",
                keys: ["Favourite films", "movie"],
                rank: 8
            ),
        ]
        let picker = index(values)
        let andRows = picker.presentation(filter: "cash north")
        XCTAssertEqual(andRows.orderedRowIDs, ["Areas/north-cash.md"])
        let andRow = try XCTUnwrap(andRows.row(id: "Areas/north-cash.md"))
        XCTAssertFalse(andRow.textMatchRanges.isEmpty)
        XCTAssertFalse(andRow.routeMatchRanges.isEmpty)

        let aliasRow = try XCTUnwrap(
            picker.presentation(filter: "cash account").row(id: "Other/ledger.md")
        )
        XCTAssertEqual(aliasRow.badgeText, "aka cash account")

        let fileStemAlias = try XCTUnwrap(
            picker.presentation(filter: "movie").row(id: "Other/movie.md")
        )
        XCTAssertNil(fileStemAlias.badgeText)
        XCTAssertTrue(
            picker.presentation(filter: "cash missing").orderedRowIDs.isEmpty
        )
    }

    func testDailyQueryPreservesNewestFirstBobOrderingAndBasesAreViewRows() throws {
        let values = [
            candidate(
                "2026/20261114.md",
                title: "November 14",
                keys: ["November 14", "2026-11-14"],
                rank: 7,
                kind: "daily"
            ),
            candidate(
                "2025/20251114.md",
                title: "November 14",
                keys: ["November 14", "2025-11-14"],
                rank: 7,
                kind: "daily"
            ),
            candidate(
                "Views/Monthly.base", title: "Monthly review", keys: ["Monthly review"],
                kind: "view"),
        ]
        let picker = index(values)
        XCTAssertEqual(
            picker.presentation(filter: "1114").orderedRowIDs,
            ["2026/20261114.md", "2025/20251114.md"]
        )
        let view = try XCTUnwrap(
            picker.presentation(filter: "monthly").row(id: "Views/Monthly.base"))
        XCTAssertEqual(view.glyph, .noteGoto(symbol: "square.grid.2x2", hue: nil))
        XCTAssertEqual(view.noteGotoDestination?.notePath, "Views/Monthly.base")
    }

    func testFourThousandRowsRemainAvailableWithoutAResultCap() {
        let values = (0..<4_000).map { index in
            candidate("Notes/note-\(index).md", title: "Note \(index)", rank: index % 9)
        }
        let picker = index(values)
        let start = Date()
        let presentation = picker.presentation(filter: "note")
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(presentation.matchCount, 4_000)
        XCTAssertEqual(presentation.orderedRowIDs.count, 4_000)
        XCTAssertLessThan(elapsed, 3.0)
    }

    func testKindGlyphTableIncludesViewAndUnknownFallback() {
        let symbols = [
            "inbox": "tray",
            "area": "square.stack.3d.up",
            "project": "hammer",
            "notebook": "book.closed",
            "album": "rectangle.stack",
            "record": "doc.richtext",
            "ref": "book",
            "daily": "calendar",
            "period": "calendar",
            "bank": "banknote",
            "mail": "envelope",
            "view": "square.grid.2x2",
            "note": "doc.text",
            "future-kind": "doc.text",
        ]
        for (kind, symbol) in symbols {
            XCTAssertEqual(NoteGotoPickerIndex.symbolName(for: kind), symbol, kind)
        }
    }

    func testCaptionsAccessibilityAndLineLessOpenURL() throws {
        XCTAssertEqual(CapturePickerSource.taskGoto.scopeCaption, "Go To · Tasks")
        XCTAssertEqual(
            CapturePickerSource.taskGoto.scopeCaption(includesClosedTasks: true),
            "Go To · Completed"
        )
        XCTAssertEqual(CapturePickerSource.taskGoto.cardAccessibilityLabel, "Go To Tasks picker")
        XCTAssertEqual(CapturePickerSource.noteGoto.triggerByte, 47)
        XCTAssertEqual(CapturePickerSource.noteGoto.scopeSymbolText, "//")
        XCTAssertEqual(CapturePickerSource.noteGoto.scopeCaption, "Go To · Notes")
        XCTAssertEqual(CapturePickerSource.noteGoto.cardAccessibilityLabel, "Go To Notes picker")
        XCTAssertEqual(
            CapturePickerNeed.noteGoto.statusText,
            "Pick a note to open — press Tab to browse"
        )
        XCTAssertEqual(CaptureCompletionContext(rawContext: "note_goto"), .noteGoto)

        let destination = try XCTUnwrap(
            CaptureNoteGotoDestination(
                vaultRoot: "/Users/bryan/Vault",
                notePath: "Other/Café + notes & more # 100%.md"
            )
        )
        let url = try XCTUnwrap(destination.openURL())
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.scheme, "obsidian")
        XCTAssertEqual(components.host, "bob-open-notes")
        let queryItems = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(queryItems.map(\.name), ["count", "path1"])
        XCTAssertEqual(queryItems.first { $0.name == "count" }?.value, "1")
        XCTAssertEqual(
            queryItems.first { $0.name == "path1" }?.value,
            "/Users/bryan/Vault/Other/Café + notes & more # 100%.md"
        )
        let encodedPath = try XCTUnwrap(
            components.percentEncodedQuery?.split(separator: "&").first { $0.hasPrefix("path1=") }
        )
        let encodedPathValue = String(encodedPath.dropFirst("path1=".count)).uppercased()
        XCTAssertTrue(
            encodedPathValue.contains("CAF%C3%A9") || encodedPathValue.contains("CAFE%CC%81")
        )
        XCTAssertTrue(encodedPathValue.contains("%20%2B%20NOTES%20%26%20MORE%20%23%20100%25.MD"))
        XCTAssertNil(queryItems.first { $0.name == "line1" })
        XCTAssertNil(
            CaptureNoteGotoDestination(vaultRoot: "/Users/bryan/Vault", notePath: "../outside.md")
        )
    }
}
