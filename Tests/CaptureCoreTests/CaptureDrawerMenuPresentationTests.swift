import Foundation
import XCTest

@testable import CaptureCore

/// The `drawer` menu: groups, Bob-authored counts and consequences, refusals,
/// and the unselected open. `drawer-complete-*` fixtures are raw Bob output;
/// `drawer-contract-*` fixtures overlay the plan fields this Bob does not emit
/// yet (see `Tests/Fixtures/drawer-fixtures-README.md`).
final class CaptureDrawerMenuPresentationTests: XCTestCase {
    // MARK: - Real Bob output

    func testRealBobTaskRowsGroupUnderOnThisTaskWithNoSwiftCounts() throws {
        let response = try completion("drawer-complete-empty.json")
        let menu = CaptureDrawerMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertEqual(menu.headerCaption, "^bar Upgrade Postgres (foo)")
        XCTAssertEqual(menu.groups.map(\.title), ["On this task"])
        XCTAssertEqual(menu.rows.map(\.title), ["REQUIREMENTS", "FUTURE WORK"])
        XCTAssertEqual(menu.rows.map(\.kind), [.task, .task])
        // This Bob sends `group: "drawers"` and an empty `detail`; the app shows no
        // count of its own where Bob supplied none.
        XCTAssertEqual(menu.rows.map(\.detail), [nil, nil])
        XCTAssertEqual(menu.rows.map(\.consequence), [nil, nil])
        XCTAssertEqual(menu.footer, CaptureCompletionMenu.unselectedFooterHint)
    }

    func testSelectedRowWithoutAConsequenceShowsTheSelectedKeyHint() throws {
        let response = try completion("drawer-complete-empty.json")
        let menu = CaptureDrawerMenuPresentation(response: response, selectedIndex: 0)

        XCTAssertEqual(menu.footer, CaptureDrawerMenuPresentation.selectedFooterHint)
    }

    func testTypedQueryEmphasizesTheMatchedPrefix() throws {
        let response = try completion("drawer-complete-typed-match.json")
        let menu = CaptureDrawerMenuPresentation(
            response: response, selectedIndex: 0, query: "req")

        XCTAssertEqual(menu.rows.map(\.title), ["REQUIREMENTS"])
        XCTAssertEqual(menu.rows.first?.queryMatchRange, 0..<3)
    }

    func testMissingTargetReturnsNoRowsAndStillNamesTheTask() throws {
        let response = try completion("drawer-complete-missing-target.json")
        let menu = CaptureDrawerMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertTrue(menu.rows.isEmpty)
        XCTAssertTrue(menu.groups.isEmpty)
        XCTAssertEqual(menu.headerCaption, "^nope (foo)")
        XCTAssertFalse(response.warnings.isEmpty)
    }

    func testPlainTaskHasNoDrawerRows() throws {
        let response = try completion("drawer-complete-plain-task.json")
        let menu = CaptureDrawerMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertTrue(menu.rows.isEmpty)
        XCTAssertEqual(menu.listAccessibilityLabel, "Drawer suggestions, 0 results")
    }

    // MARK: - Contract fixtures (synthetic overlays)

    func testEmptyQueryOpensWithOnThisTaskAndRecentGroupsAndNothingSelected() throws {
        let response = try completion("drawer-contract-complete-empty.json")
        XCTAssertTrue(response.opensWithoutSelection)
        XCTAssertNil(
            CaptureCompletionMenu.initialSelectedIndex(for: response, queryIsEmpty: true))

        let menu = CaptureDrawerMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertEqual(menu.groups.map(\.title), ["On this task", "Recent"])
        XCTAssertEqual(menu.groups.map(\.kind), [.task, .recent])
        XCTAssertEqual(
            menu.rows.map(\.title), ["REQUIREMENTS", "FUTURE WORK", "ACCEPTANCE", "MOTIVATION"])
        XCTAssertEqual(menu.rows.map(\.detail).prefix(2), ["3 notes", "1 note"])
        XCTAssertEqual(menu.rows[3].detail, "used in 3 notes · 3 days ago")
        XCTAssertEqual(menu.rows.map(\.creates), [false, false, true, true])
        XCTAssertEqual(menu.footer, CaptureCompletionMenu.unselectedFooterHint)
    }

    func testFooterShowsBobsConsequenceForTheSelectedRow() throws {
        let response = try completion("drawer-contract-complete-empty.json")

        let task = CaptureDrawerMenuPresentation(response: response, selectedIndex: 0)
        XCTAssertEqual(task.footer, "Adds after \"fast disk\" in REQUIREMENTS")

        let recent = CaptureDrawerMenuPresentation(response: response, selectedIndex: 3)
        XCTAssertEqual(recent.footer, "Creates MOTIVATION under ^bar")
    }

    func testTypedQueryWithNoMatchOffersOnlyTheNewRow() throws {
        let response = try completion("drawer-contract-complete-typed-new.json")
        XCTAssertFalse(response.opensWithoutSelection)
        XCTAssertEqual(
            CaptureCompletionMenu.initialSelectedIndex(for: response, queryIsEmpty: false), 0,
            "a typed query preselects the best row")

        let menu = CaptureDrawerMenuPresentation(
            response: response, selectedIndex: 0, query: "perf")

        XCTAssertEqual(menu.groups.map(\.title), [nil])
        let row = try XCTUnwrap(menu.rows.first)
        XCTAssertTrue(row.isNew)
        XCTAssertEqual(row.label, "\u{FF0B} New drawer PERF")
        XCTAssertNil(row.queryMatchRange, "the create row has no prefix emphasis")
        XCTAssertEqual(menu.footer, "Creates PERF under ^bar")
        XCTAssertEqual(
            row.accessibilityLabel, "\u{FF0B} New drawer PERF, Creates PERF under ^bar")
    }

    func testTypedQueryPlacesTheMatchingRecentRowBeforeTheNewRow() throws {
        let response = try completion("drawer-contract-complete-typed-recent.json")
        let menu = CaptureDrawerMenuPresentation(
            response: response, selectedIndex: 0, query: "mot")

        XCTAssertEqual(menu.groups.map(\.kind), [.recent, .new])
        XCTAssertEqual(menu.groups.map(\.title), ["Recent", nil])
        XCTAssertEqual(menu.rows.map(\.title), ["MOTIVATION", "MOT"])
        XCTAssertEqual(menu.rows.first?.queryMatchRange, 0..<3)
    }

    func testRefusedRowShowsBobsReasonIsDisabledAndFooterRepeatsIt() throws {
        let response = try completion("drawer-contract-complete-refused.json")
        let candidate = try XCTUnwrap(response.candidates.first)
        XCTAssertTrue(CaptureCompletionMenu.isDisabled(candidate), "Return on it is a no-op")

        let menu = CaptureDrawerMenuPresentation(response: response, selectedIndex: 0)
        let row = try XCTUnwrap(menu.rows.first)

        XCTAssertTrue(row.isRefused)
        XCTAssertEqual(row.refusal, "TASKS is reserved for the note's task list")
        XCTAssertEqual(menu.footer, "TASKS is reserved for the note's task list")
        XCTAssertTrue(row.accessibilityLabel.contains("unavailable: TASKS is reserved"))
    }

    // MARK: - Pieces

    func testUnknownGroupFallsBackToTheTaskGroup() {
        XCTAssertEqual(CaptureDrawerMenuPresentation.Kind(group: nil), .task)
        XCTAssertEqual(CaptureDrawerMenuPresentation.Kind(group: "task"), .task)
        XCTAssertEqual(CaptureDrawerMenuPresentation.Kind(group: "drawers"), .task)
        XCTAssertEqual(CaptureDrawerMenuPresentation.Kind(group: "recent"), .recent)
        XCTAssertEqual(CaptureDrawerMenuPresentation.Kind(group: "new"), .new)
        XCTAssertEqual(CaptureDrawerMenuPresentation.Kind(group: "someday"), .task)
    }

    func testHeaderCaptionSkipsPartsBobLeftOut() {
        XCTAssertEqual(CaptureDrawerMenuPresentation.caption(for: nil), "")
        XCTAssertEqual(
            CaptureDrawerMenuPresentation.caption(
                for: CaptureDrawerTarget(route: "foo.md", blockID: "bar", text: "Upgrade Postgres")),
            "^bar Upgrade Postgres (foo)")
        XCTAssertEqual(
            CaptureDrawerMenuPresentation.caption(
                for: CaptureDrawerTarget(route: "foo.md", blockID: nil, text: "")),
            "(foo)")
        XCTAssertEqual(
            CaptureDrawerMenuPresentation.caption(
                for: CaptureDrawerTarget(route: "dir/foo.md", blockID: "x", text: "  Spaced  ")),
            "^x Spaced (dir/foo)")
    }

    func testQueryTextDropsTheGluedHashAndLiteralQuote() {
        XCTAssertEqual(CaptureDrawerMenuPresentation.queryText(fromTyped: ""), "")
        XCTAssertEqual(CaptureDrawerMenuPresentation.queryText(fromTyped: "req"), "req")
        XCTAssertEqual(CaptureDrawerMenuPresentation.queryText(fromTyped: "#req"), "req")
        XCTAssertEqual(CaptureDrawerMenuPresentation.queryText(fromTyped: "#\"Q&A"), "Q&A")
        XCTAssertEqual(CaptureDrawerMenuPresentation.queryText(fromTyped: "#"), "")
    }

    func testRowIndexIsTheCandidateIndexForSelection() throws {
        let response = try completion("drawer-contract-complete-empty.json")
        let menu = CaptureDrawerMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertEqual(menu.rows.map(\.index), [0, 1, 2, 3])
        XCTAssertEqual(menu.groups.flatMap { $0.rows.map(\.index) }, [0, 1, 2, 3])
    }

    // MARK: - Fixtures

    private func completion(_ name: String) throws -> CaptureCompletionResponse {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        return try JSONDecoder().decode(
            CaptureCompletionResponse.self, from: Data(contentsOf: url))
    }
}
