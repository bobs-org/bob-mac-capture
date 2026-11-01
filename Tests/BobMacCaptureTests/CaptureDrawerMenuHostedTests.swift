import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Hosted `@route+id#` drawer menu: unselected open on an empty query, best-row
/// preselection on a typed one, the consequence footer, and the no-op on a
/// refused row. Bob authors the rows; Swift only presents them. The empty-query
/// menu is generated from raw Bob output (see `Tests/Fixtures/drawer-fixtures-README.md`).
@MainActor
final class CaptureDrawerMenuHostedTests: XCTestCase {
    func testEmptyQueryOpensTheDrawerMenuWithNothingSelected() async throws {
        let model = try makeModel()
        let draft = "Postgres 17 minimum @foo+bar#"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "drawer" }

        XCTAssertTrue(model.completionVisible)
        XCTAssertTrue(model.completionResponse?.opensWithoutSelection == true)
        XCTAssertNil(model.selectedCompletionIndex)
        let menu = try XCTUnwrap(model.drawerMenuPresentation())
        XCTAssertEqual(menu.groups.map(\.title), ["On this task", "Recent"])
        XCTAssertEqual(menu.headerCaption, "^bar Upgrade Postgres (foo)")
        XCTAssertEqual(menu.footer, CaptureCompletionMenu.unselectedFooterHint)
        XCTAssertEqual(model.plainDraft, draft, "opening the menu never edits the draft")
    }

    func testTypedQueryPreselectsTheBestMatchAndHighlightsIt() async throws {
        let model = try makeModel()
        let draft = "Postgres 17 minimum @foo+bar#req"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "drawer" }

        XCTAssertEqual(model.selectedCompletionIndex, 0)
        let menu = try XCTUnwrap(model.drawerMenuPresentation())
        XCTAssertEqual(menu.rows.first?.title, "REQUIREMENTS")
        XCTAssertEqual(menu.rows.first?.queryMatchRange, 0..<3)
    }

    func testProjectTaskMenuUsesItsH2Drawers() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtureURL("drawer-complete-project-empty.json"))
        )

        XCTAssertEqual(response.context, "drawer")
        XCTAssertEqual(response.target?.blockID, "prj")
        XCTAssertEqual(response.candidates.first?.title, "Requirements")
        XCTAssertEqual(response.candidates.first?.consequence, "Adds to ## Requirements")
    }

    func testNonDrawerContextsHaveNoDrawerPresentation() async throws {
        let model = try makeModel()
        XCTAssertNil(model.drawerMenuPresentation())
        let draft = "jot idea @foo#"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "section" }
        XCTAssertNil(model.drawerMenuPresentation())
    }

    func testDownThenTabWalksTheRowsWithoutEditingUntilAccepted() throws {
        let model = CapturePanelModel()
        try installDrawerMenu(on: model, fixture: "drawer-complete-empty.json")
        XCTAssertNil(model.selectedCompletionIndex)

        model.selectNextCompletion()
        XCTAssertEqual(model.selectedCompletionIndex, 0)
        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar#")

        model.selectNextCompletion()
        XCTAssertEqual(model.selectedCompletionIndex, 1)
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar#future-work")
        XCTAssertNil(model.completionResponse)
    }

    func testFooterShowsBobsConsequenceForTheSelectedRowAndTheHintWhenNone() throws {
        let model = CapturePanelModel()
        try installDrawerMenu(on: model, fixture: "drawer-complete-empty.json")

        XCTAssertEqual(
            model.drawerMenuPresentation()?.footer, CaptureCompletionMenu.unselectedFooterHint)

        model.selectedCompletionIndex = 0
        XCTAssertEqual(
            model.drawerMenuPresentation()?.footer, "Adds after \"fast disk\" in REQUIREMENTS")

        model.selectedCompletionIndex = 2
        XCTAssertEqual(
            model.drawerMenuPresentation()?.footer, "Creates ACCEPTANCE under ^bar")
    }

    func testReturnOnARefusedRowIsANoOpAndKeepsTheMenuOpen() throws {
        let model = CapturePanelModel()
        try installDrawerMenu(
            on: model,
            fixture: "drawer-complete-typed-reserved.json",
            draft: "Postgres 17 minimum @foo+bar#tasks"
        )

        XCTAssertTrue(model.acceptSelectedCompletion())

        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar#tasks")
        XCTAssertEqual(model.completionResponse?.context, "drawer")
        XCTAssertTrue(model.completionVisible)
        XCTAssertEqual(
            model.drawerMenuPresentation()?.footer,
            "`TASKS` is managed by Bob; name the drawer something else")
    }

    func testAcceptingTheNewRowSplicesBobsReplacementAndCursor() throws {
        let model = CapturePanelModel()
        try installDrawerMenu(
            on: model,
            fixture: "drawer-complete-typed-none.json",
            draft: "Postgres 17 minimum @foo+bar#perf"
        )
        XCTAssertEqual(model.selectedCompletionIndex, 0)

        XCTAssertTrue(model.acceptSelectedCompletion())

        // The row's replacement starts at the `#`, so the splice never doubles it.
        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar#perf")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 33)
        XCTAssertNil(model.completionResponse)
    }

    func testEscapeClosesTheDrawerMenuAndKeepsTheDraft() throws {
        let model = CapturePanelModel()
        try installDrawerMenu(on: model, fixture: "drawer-complete-empty.json")

        model.dismissCompletion()

        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.drawerMenuPresentation())
        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar#")
    }

    // MARK: - Helpers

    /// Installs a decoded fixture the way a landed `capture-complete` would, with
    /// the selection Bob's `initial_selection` asks for.
    private func installDrawerMenu(
        on model: CapturePanelModel,
        fixture: String,
        draft: String = "Postgres 17 minimum @foo+bar#"
    ) throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtureURL(fixture))
        )
        model.plainDraft = draft
        model.completionResponse = response
        model.selectedCompletionIndex = CaptureCompletionMenu.initialSelectedIndex(
            for: response,
            queryIsEmpty: response.opensWithoutSelection
        )
    }

    private func makeModel() throws -> CapturePanelModel {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
            ]
        )
        return model
    }

    private func fixtureURL(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
    }

    private func fakeBobPath() throws -> String {
        fixtureURL("fake-bob").path
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
