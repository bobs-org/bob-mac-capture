import Foundation
import XCTest

@testable import CaptureCore

/// The `drawer` menu: groups, Bob-authored counts and consequences, refusals,
/// and the unselected open. `drawer-complete-*` fixtures are raw Bob output
/// (see `Tests/Fixtures/drawer-fixtures-README.md`).
final class CapturePlaceMenuPresentationTests: XCTestCase {
    // MARK: - Real Bob output

    func testRawBobRowsAndCountsRenderWithoutSwiftInference() throws {
        let response = try completion("drawer-complete-empty.json")
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertEqual(menu.headerCaption, "^bar Upgrade Postgres (foo.md)")
        XCTAssertEqual(menu.groups.map(\.title), ["On this task", "Recent"])
        XCTAssertEqual(
            menu.rows.map(\.title),
            ["REQUIREMENTS", "FUTURE WORK", "ACCEPTANCE", "MOTIVATION"])
        XCTAssertEqual(menu.rows.map(\.kind), [.task, .task, .recent, .recent])
        XCTAssertEqual(response.candidates.map(\.entryCount), [3, 1, 0, 0])
        XCTAssertEqual(menu.rows.map(\.detail), response.candidates.map(\.detail))
        XCTAssertEqual(menu.rows.map(\.creates), [false, false, true, true])
        XCTAssertEqual(menu.footer, "⏎ choose · ⎋ close")
    }

    func testTypedQueryEmphasizesTheMatchedPrefix() throws {
        let response = try completion("drawer-complete-typed-match.json")
        let menu = CapturePlaceMenuPresentation(
            response: response, selectedIndex: 0, query: "req")

        XCTAssertEqual(menu.rows.map(\.title), ["REQUIREMENTS", "REQ"])
        XCTAssertEqual(menu.rows.first?.queryMatchRange, 0..<3)
        XCTAssertTrue(menu.rows[1].isRefused)
    }

    func testMissingTargetReturnsNoRowsAndStillNamesTheTask() throws {
        let response = try completion("drawer-complete-missing-target.json")
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertTrue(menu.rows.isEmpty)
        XCTAssertTrue(menu.groups.isEmpty)
        XCTAssertEqual(menu.headerCaption, "^nope  (foo.md)")
        XCTAssertFalse(response.warnings.isEmpty)
    }

    func testPlainTaskOffersRecentDrawers() throws {
        let response = try completion("drawer-complete-plain-task.json")
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertEqual(menu.groups.map(\.title), ["Recent"])
        XCTAssertEqual(menu.rows.map(\.title), ["ACCEPTANCE", "MOTIVATION", "REQUIREMENTS"])
        XCTAssertEqual(menu.rows.map(\.kind), [.recent, .recent, .recent])
        XCTAssertEqual(
            menu.listAccessibilityLabel, "Drawer, ^plain Plain task (foo.md), 3 drawers")
    }

    func testBulletDrawerTypedQueryUsesBobRowsAndContinuation() throws {
        let response = try completion("drawer-bullet-complete-existing-typed.json")
        let menu = CapturePlaceMenuPresentation(
            response: response, selectedIndex: 0, query: "req")

        XCTAssertEqual(menu.headerCaption, "^bar Upgrade Postgres (foo.md)")
        XCTAssertEqual(menu.rows.first?.title, "REQUIREMENTS")
        XCTAssertEqual(menu.rows.first?.queryMatchRange, 0..<3)
        XCTAssertEqual(response.candidates.first?.replacement, "REQUIREMENTS\n  - ")
    }

    func testProjectTaskUsesH2DrawersAndBobConsequence() throws {
        let response = try completion("drawer-complete-project-empty.json")
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: 0)

        XCTAssertEqual(response.target?.blockID, "prj")
        XCTAssertEqual(Array(menu.rows.prefix(2).map(\.title)), ["Requirements", "Q&A"])
        XCTAssertEqual(menu.rows.first?.consequence, "Adds to ## Requirements")
    }

    // MARK: - Full drawer contract

    func testEmptyQueryOpensWithOnThisTaskAndRecentGroupsAndNothingSelected() throws {
        let response = try completion("drawer-complete-empty.json")
        XCTAssertTrue(response.opensWithoutSelection)
        XCTAssertNil(
            CaptureCompletionMenu.initialSelectedIndex(for: response, queryIsEmpty: true))

        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertEqual(menu.groups.map(\.title), ["On this task", "Recent"])
        XCTAssertEqual(menu.groups.map(\.kind), [.task, .recent])
        XCTAssertEqual(
            menu.rows.map(\.title), ["REQUIREMENTS", "FUTURE WORK", "ACCEPTANCE", "MOTIVATION"])
        XCTAssertEqual(menu.rows.map(\.detail), response.candidates.map(\.detail))
        XCTAssertEqual(menu.rows[3].detail, "used in 3 notes · last week")
        XCTAssertEqual(menu.rows.map(\.creates), [false, false, true, true])
        XCTAssertEqual(menu.footer, "⏎ choose · ⎋ close")
    }

    func testFooterShowsBobsConsequenceForTheSelectedRow() throws {
        let response = try completion("drawer-complete-empty.json")

        let task = CapturePlaceMenuPresentation(response: response, selectedIndex: 0)
        XCTAssertEqual(task.footer, "Adds after \"fast disk\" in REQUIREMENTS")

        let recent = CapturePlaceMenuPresentation(response: response, selectedIndex: 3)
        XCTAssertEqual(recent.footer, "Creates MOTIVATION under ^bar")
    }

    func testTypedQueryWithNoMatchOffersOnlyTheNewRow() throws {
        let response = try completion("drawer-complete-typed-none.json")
        XCTAssertFalse(response.opensWithoutSelection)
        XCTAssertEqual(
            CaptureCompletionMenu.initialSelectedIndex(for: response, queryIsEmpty: false), 0,
            "a typed query preselects the best row")

        let menu = CapturePlaceMenuPresentation(
            response: response, selectedIndex: 0, query: "perf")

        XCTAssertEqual(menu.groups.map(\.title), [nil])
        let row = try XCTUnwrap(menu.rows.first)
        XCTAssertTrue(row.isNew)
        XCTAssertEqual(row.label, "\u{FF0B} New drawer PERF")
        XCTAssertNil(row.queryMatchRange, "the create row has no prefix emphasis")
        XCTAssertEqual(menu.footer, "Creates PERF under ^bar")
        XCTAssertEqual(
            row.accessibilityLabel,
            "^bar Upgrade Postgres (foo.md), PERF, New, Creates PERF under ^bar")
    }

    func testTypedQueryPlacesTheMatchingRecentRowBeforeTheNewRow() throws {
        let response = try completion("drawer-complete-typed-recent.json")
        let menu = CapturePlaceMenuPresentation(
            response: response, selectedIndex: 0, query: "mot")

        XCTAssertEqual(menu.groups.map(\.kind), [.recent, .new])
        XCTAssertEqual(menu.groups.map(\.title), ["Recent", nil])
        XCTAssertEqual(menu.rows.map(\.title), ["MOTIVATION", "MOT"])
        XCTAssertEqual(menu.rows.first?.queryMatchRange, 0..<3)
    }

    func testRefusedRowShowsBobsReasonIsDisabledAndFooterRepeatsIt() throws {
        let response = try completion("drawer-complete-typed-reserved.json")
        let candidate = try XCTUnwrap(response.candidates.first)
        XCTAssertTrue(CaptureCompletionMenu.isDisabled(candidate), "Return on it is a no-op")

        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: 0)
        let row = try XCTUnwrap(menu.rows.first)

        XCTAssertTrue(row.isRefused)
        XCTAssertEqual(row.refusal, "`TASKS` is managed by Bob; name the drawer something else")
        XCTAssertEqual(menu.footer, "`TASKS` is managed by Bob; name the drawer something else")
        XCTAssertTrue(row.accessibilityLabel.contains("unavailable: `TASKS` is managed by Bob"))
    }

    func testNotebookMenuUsesBobsChromeGroupsAndEmptyHint() throws {
        let response = try completion("notebook-complete-section-bullet-empty.json")
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertEqual(response.context, "notebook_section_bullet")
        XCTAssertEqual(menu.title, "Section")
        XCTAssertEqual(menu.caption, "📓 Neovim · dev")
        XCTAssertEqual(menu.groups.map(\.title), ["In this notebook"])
        XCTAssertEqual(menu.rows.map(\.title), ["Setup"])
        XCTAssertEqual(
            menu.rows.first?.consequence, "Adds after “Unidentified guide” in ## Setup")
        XCTAssertEqual(menu.emptyHint, "Type a section name")
        XCTAssertEqual(menu.newRowPrefix, "＋ ")
        XCTAssertEqual(menu.footer, "⏎ choose · ⎋ close")
        XCTAssertEqual(menu.listAccessibilityLabel, "Section, 📓 Neovim · dev, 1 sections")
    }

    func testNotebookCreateAndDraftRowsKeepBobOrderAndIdentity() throws {
        let response = try completion("notebook-complete-section-bullet-draft.json")
        let menu = CapturePlaceMenuPresentation(
            response: response,
            selectedIndex: nil,
            query: "Wir"
        )

        XCTAssertEqual(menu.groups.map(\.title), ["Earlier in this draft"])
        XCTAssertEqual(menu.rows.map(\.index), response.candidates.indices.map { $0 })
        XCTAssertEqual(menu.rows.map(\.groupID), ["draft"])
        XCTAssertEqual(menu.rows.map(\.title), ["Wireguard"])
        XCTAssertEqual(menu.rows.first?.label, "Wireguard")
        XCTAssertEqual(menu.rows.first?.originBadge, "new")
        XCTAssertEqual(menu.rows.first?.queryMatchRange, 0..<3)
        XCTAssertTrue(menu.rows.first?.isNotebookSection == true)
        XCTAssertFalse(menu.rows.first?.creates == true)
    }

    func testNotebookCreateRowUsesBobsLabelAndPrefix() throws {
        let response = try completion("notebook-complete-section-bullet-clean-create.json")
        let menu = CapturePlaceMenuPresentation(
            response: response,
            selectedIndex: nil,
            query: "wireguard"
        )
        let row = try XCTUnwrap(menu.rows.first)

        XCTAssertEqual(row.title, "Wireguard")
        XCTAssertEqual(row.label, "＋ New section “Wireguard”")
        XCTAssertNil(row.queryMatchRange)
        XCTAssertTrue(row.creates)
    }

    func testNotebookNearMissAndRefusedRowsStayUnselected() throws {
        let nearMiss = try completion("notebook-complete-section-bullet-near-miss.json")
        XCTAssertTrue(nearMiss.opensWithoutSelection)
        XCTAssertNil(CaptureCompletionMenu.initialSelectedIndex(for: nearMiss, queryIsEmpty: false))
        XCTAssertEqual(nearMiss.candidates.first?.detail, "did you mean Setup?")
        XCTAssertFalse(CaptureCompletionMenu.isDisabled(try XCTUnwrap(nearMiss.candidates.first)))

        let refused = try completion("notebook-complete-section-bullet-refused.json")
        XCTAssertTrue(refused.opensWithoutSelection)
        XCTAssertTrue(refused.candidates.allSatisfy(CaptureCompletionMenu.isDisabled))
        let menu = CapturePlaceMenuPresentation(response: refused, selectedIndex: 0)
        XCTAssertTrue(menu.rows.first?.isRefused == true)
        XCTAssertEqual(menu.footer, refused.candidates.first?.refused)
    }

    func testRefusedRowBeforeAnEnabledRowStaysVisibleAndDoesNotBecomeTheSelection() throws {
        let data = Data(
            #"{"ok":true,"cursor":1,"replacement":{"start":0,"end":1},"context":"notebook_section_bullet","query":"g","candidates":[{"replacement":"Git\n  - ","title":"Git","kind":"notebook_section","group":"notebook","refused":"duplicate heading","detail":"1 note"},{"replacement":"Guides\n  - ","title":"Guides","kind":"notebook_section","group":"notebook","detail":"2 notes","consequence":"Adds to ## Guides"}],"place_menu":{"kind":"notebook_section","title":"Section","caption":"📓 Neovim · dev","groups":[{"id":"notebook","title":"In this notebook"}],"new_row_prefix":"＋ ","empty_hint":"Type a section name","results_label":"sections","footer_hint":"⏎ choose · ⎋ close"}}"#.utf8
        )
        let response = try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)
        XCTAssertTrue(CaptureCompletionMenu.isDisabled(response.candidates[0]))
        XCTAssertFalse(CaptureCompletionMenu.isDisabled(response.candidates[1]))
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: 1)
        XCTAssertEqual(menu.rows.map(\.title), ["Git", "Guides"])
        XCTAssertTrue(menu.rows[0].isRefused)
        XCTAssertFalse(menu.rows[1].isRefused)
        XCTAssertEqual(menu.footer, "Adds to ## Guides")
        XCTAssertTrue(menu.rows[0].accessibilityLabel.contains("unavailable:"))
    }

    func testGluedEmptyNotebookOmitsPlaceMenuChrome() throws {
        let response = try completion("notebook-complete-section-glued-empty.json")
        XCTAssertEqual(response.context, "section")
        XCTAssertTrue(response.candidates.isEmpty)
        XCTAssertNil(response.placeMenu)
        XCTAssertEqual(response.grammar, 26)
    }

    func testEmptyNotebookBulletMenuKeepsBobHintWithoutInventingRows() throws {
        let response = try completion("notebook-complete-section-empty.json")
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertTrue(response.candidates.isEmpty)
        XCTAssertEqual(response.placeMenu?.kind, "notebook_section")
        XCTAssertEqual(menu.emptyHint, "Type a section name")
        XCTAssertTrue(menu.rows.isEmpty)
        XCTAssertEqual(menu.listAccessibilityLabel, "Section, 📓 Empty notebook · dev, 0 sections, Type a section name")
    }

    func testGluedNotebookRowOmitsBulletContinuation() throws {
        let glued = try completion("notebook-complete-section-glued.json")
        XCTAssertEqual(glued.context, "section")
        XCTAssertEqual(glued.candidates.first?.replacement, "Setup")
        XCTAssertNil(glued.candidates.first?.cursorAfter)

        let bullet = try completion("notebook-complete-section-bullet-existing.json")
        XCTAssertEqual(bullet.context, "notebook_section_bullet")
        XCTAssertEqual(bullet.candidates.first?.replacement, "Setup\n  - ")
        XCTAssertEqual(bullet.candidates.first?.cursorAfter, 23)
    }

    func testBareBulletHashNeedsSectionAndExistingSectionAllowsNestedNotes() throws {
        let empty = try parse("notebook-parse-section-bullet-empty.json")
        XCTAssertEqual(empty.needs, ["section"])
        XCTAssertTrue(empty.spans.contains { $0.kind == "route" && $0.notebook == true })

        let existing = try parse("notebook-parse-section-bullet-existing.json")
        XCTAssertEqual(existing.needs, ["section_notes"])
        let section = try XCTUnwrap(existing.spans.first { $0.kind == "section" })
        XCTAssertEqual(section.sectionAction, "existing")
        XCTAssertEqual(section.title, "Setup")
    }

    func testEmptyNotebookMenuUsesBobHintAndKeepsUnknownMenuValues() throws {
        let data = Data(
            #"{"ok":true,"cursor":0,"replacement":{"start":0,"end":0},"context":"notebook_section_bullet","candidates":[],"place_menu":{"kind":"future_notebook_kind","title":"Section","caption":"Notebook","groups":[{"id":"future_group","title":"Future"}],"new_row_prefix":"＋ ","empty_hint":"Type a section name","results_label":"sections","footer_hint":"⏎ choose · ⎋ close"}}"#.utf8
        )
        let response = try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertEqual(response.placeMenu?.kind, "future_notebook_kind")
        XCTAssertEqual(menu.groups.map(\.title), [] as [String?])
        XCTAssertEqual(menu.emptyHint, "Type a section name")
        XCTAssertEqual(menu.footer, "⏎ choose · ⎋ close")
        XCTAssertEqual(menu.listAccessibilityLabel, "Section, Notebook, 0 sections, Type a section name")
    }

    func testUnknownPlaceMenuGroupAndSpanValuesStayDecodableAndVisible() throws {
        let completionData = Data(
            #"{"ok":true,"cursor":1,"replacement":{"start":0,"end":1},"context":"section","query":"x","candidates":[{"replacement":"X","title":"X","kind":"future_section_kind","group":"future_group"}],"place_menu":{"kind":"future_menu_kind","title":"Future menu","caption":"Notebook","groups":[{"id":"future_group","title":"Future group"}],"new_row_prefix":"+ ","results_label":"sections","footer_hint":"Choose"}}"#.utf8
        )
        let response = try JSONDecoder().decode(CaptureCompletionResponse.self, from: completionData)
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: 0, query: "x")

        XCTAssertEqual(response.placeMenu?.kind, "future_menu_kind")
        XCTAssertEqual(menu.groups.map(\.title), ["Future group"])
        XCTAssertEqual(menu.rows.map(\.title), ["X"])
        XCTAssertEqual(menu.rows.first?.kind, .task)

        let span = try JSONDecoder().decode(
            CaptureSpan.self,
            from: Data(#"{"start":0,"end":1,"kind":"section","notebook":true,"section_action":"future_action","title":"X"}"#.utf8)
        )
        XCTAssertTrue(span.notebook == true)
        XCTAssertEqual(span.sectionAction, "future_action")
        XCTAssertEqual(span.title, "X")
    }

    func testOldCompletionPayloadStillDecodesWithoutPlaceMenuAndKeepsDrawerFallback() throws {
        let data = Data(
            #"{"ok":true,"cursor":0,"replacement":{"start":0,"end":0},"context":"drawer","candidates":[]}"#.utf8
        )
        let response = try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertNil(response.placeMenu)
        XCTAssertEqual(menu.title, "Drawer")
        XCTAssertEqual(menu.listAccessibilityLabel, "Drawer suggestions, 0 results")
    }

    // MARK: - Pieces

    func testUnknownGroupFallsBackToTheTaskGroup() {
        XCTAssertEqual(CapturePlaceMenuPresentation.Kind(group: nil), .task)
        XCTAssertEqual(CapturePlaceMenuPresentation.Kind(group: "task"), .task)
        XCTAssertEqual(CapturePlaceMenuPresentation.Kind(group: "drawers"), .task)
        XCTAssertEqual(CapturePlaceMenuPresentation.Kind(group: "recent"), .recent)
        XCTAssertEqual(CapturePlaceMenuPresentation.Kind(group: "new"), .new)
        XCTAssertEqual(CapturePlaceMenuPresentation.Kind(group: "someday"), .task)
    }

    func testHeaderCaptionSkipsPartsBobLeftOut() {
        XCTAssertEqual(CapturePlaceMenuPresentation.caption(for: nil), "")
        XCTAssertEqual(
            CapturePlaceMenuPresentation.caption(
                for: CaptureDrawerTarget(route: "foo.md", blockID: "bar", text: "Upgrade Postgres")),
            "^bar Upgrade Postgres (foo)")
        XCTAssertEqual(
            CapturePlaceMenuPresentation.caption(
                for: CaptureDrawerTarget(route: "foo.md", blockID: nil, text: "")),
            "(foo)")
        XCTAssertEqual(
            CapturePlaceMenuPresentation.caption(
                for: CaptureDrawerTarget(
                    route: "mac_inbox.md", blockID: nil, text: "Review launch checklist")),
            "Review launch checklist (mac_inbox)")
        XCTAssertEqual(
            CapturePlaceMenuPresentation.caption(
                for: CaptureDrawerTarget(route: "dir/foo.md", blockID: "x", text: "  Spaced  ")),
            "^x Spaced (dir/foo)")
    }

    func testQueryTextDropsTheGluedHashAndLiteralQuote() {
        XCTAssertEqual(CapturePlaceMenuPresentation.queryText(fromTyped: ""), "")
        XCTAssertEqual(CapturePlaceMenuPresentation.queryText(fromTyped: "req"), "req")
        XCTAssertEqual(CapturePlaceMenuPresentation.queryText(fromTyped: "#req"), "req")
        XCTAssertEqual(CapturePlaceMenuPresentation.queryText(fromTyped: "#\"Q&A"), "Q&A")
        XCTAssertEqual(CapturePlaceMenuPresentation.queryText(fromTyped: "#"), "")
    }

    func testRowIndexIsTheCandidateIndexForSelection() throws {
        let response = try completion("drawer-complete-empty.json")
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertEqual(menu.rows.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(menu.groups.flatMap { $0.rows.map(\.index) }, [0, 1, 2, 3])
    }

    // MARK: - Fixtures

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func completion(_ name: String) throws -> CaptureCompletionResponse {
        try JSONDecoder().decode(
            CaptureCompletionResponse.self, from: Data(contentsOf: fixtureURL(name)))
    }

    private func parse(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(
            CaptureParseResponse.self, from: Data(contentsOf: fixtureURL(name)))
    }
}
