import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Hosted `@route+id#` drawer menu: unselected open on an empty query, best-row
/// preselection on a typed one, the consequence footer, and the no-op on a
/// refused row. Bob authors the rows; Swift only presents them. The empty-query
/// menu is generated from raw Bob output (see `Tests/Fixtures/drawer-fixtures-README.md`).
@MainActor
final class CapturePlaceMenuHostedTests: XCTestCase {
    func testEmptyQueryOpensTheDrawerMenuWithNothingSelected() async throws {
        let model = try makeModel()
        let draft = "Postgres 17 minimum @foo+bar#"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "drawer" }

        XCTAssertTrue(model.completionVisible)
        XCTAssertTrue(model.completionResponse?.opensWithoutSelection == true)
        XCTAssertNil(model.selectedCompletionIndex)
        let menu = try XCTUnwrap(model.placeMenuPresentation())
        XCTAssertEqual(menu.groups.map(\.title), ["On this task", "Recent"])
        XCTAssertEqual(menu.headerCaption, "^bar Upgrade Postgres (foo.md)")
        XCTAssertEqual(menu.footer, "⏎ choose · ⎋ close")
        XCTAssertEqual(model.plainDraft, draft, "opening the menu never edits the draft")
    }

    func testTypedQueryPreselectsTheBestMatchAndHighlightsIt() async throws {
        let model = try makeModel()
        let draft = "Postgres 17 minimum @foo+bar#req"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "drawer" }

        XCTAssertEqual(model.selectedCompletionIndex, 0)
        let menu = try XCTUnwrap(model.placeMenuPresentation())
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

    func testNewTaskBulletMenuCaptionIncludesTextAndRouteWithoutBlockID() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtureURL("drawer-bullet-complete-new-task-empty.json"))
        )
        let menu = CapturePlaceMenuPresentation(response: response, selectedIndex: nil)

        XCTAssertNil(response.target?.blockID)
        XCTAssertEqual(menu.headerCaption, "New task (mac_inbox.md)")
        XCTAssertFalse(menu.rows.isEmpty)
    }

    func testNonDrawerContextsHaveNoDrawerPresentation() async throws {
        let model = try makeModel()
        XCTAssertNil(model.placeMenuPresentation())
        let draft = "jot idea @foo#"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "section" }
        XCTAssertNil(model.placeMenuPresentation())
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
            model.placeMenuPresentation()?.footer, "⏎ choose · ⎋ close")

        model.selectedCompletionIndex = 0
        XCTAssertEqual(
            model.placeMenuPresentation()?.footer, "Adds after \"fast disk\" in REQUIREMENTS")

        model.selectedCompletionIndex = 2
        XCTAssertEqual(
            model.placeMenuPresentation()?.footer, "Creates ACCEPTANCE under ^bar")
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
            model.placeMenuPresentation()?.footer,
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

    func testAcceptingBulletDrawerContinuationSplicesNewlinesAndLandsCaret() throws {
        let model = CapturePanelModel()
        let draft = "@foo+bar\n- #"
        try installDrawerMenu(
            on: model,
            fixture: "drawer-bullet-complete-existing-empty.json",
            draft: draft
        )
        let candidates = try XCTUnwrap(model.completionResponse?.candidates)
        let candidateIndex = try XCTUnwrap(
            candidates.firstIndex(where: { $0.replacement == "FUTURE WORK\n  - " })
        )
        let candidate = candidates[candidateIndex]
        model.selectedCompletionIndex = candidateIndex

        XCTAssertTrue(model.acceptSelectedCompletion())

        let accepted = "@foo+bar\n- FUTURE WORK\n  - "
        let cursorAfter = try XCTUnwrap(candidate.cursorAfter)
        XCTAssertEqual(model.plainDraft, accepted)
        XCTAssertEqual(cursorAfter, accepted.utf8.count)
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), cursorAfter)
        XCTAssertNil(model.completionResponse)
    }

    func testEscapeClosesTheDrawerMenuAndKeepsTheDraft() throws {
        let model = CapturePanelModel()
        try installDrawerMenu(on: model, fixture: "drawer-complete-empty.json")

        model.dismissCompletion()

        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.placeMenuPresentation())
        XCTAssertEqual(model.plainDraft, "Postgres 17 minimum @foo+bar#")
    }

    func testNotebookEmptyHintKeepsAnEmptyMenuVisibleAndEscapeDismissesIt() async throws {
        let model = try makeNotebookModel()
        let draft = "@dev_empty\n- #"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "notebook_section_bullet" }

        XCTAssertTrue(model.completionVisible)
        XCTAssertTrue(model.completionResponse?.candidates.isEmpty == true)
        XCTAssertNil(model.selectedCompletionIndex)
        XCTAssertEqual(model.placeMenuPresentation()?.emptyHint, "Type a section name")
        XCTAssertFalse(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, draft)

        model.dismissCompletion()
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.placeMenuPresentation())
        XCTAssertEqual(model.plainDraft, draft)
    }

    func testEmptyHintReservesAFullCompletionRowInThePlaceMenuViewport() {
        XCTAssertEqual(
            CapturePanelLayout.placeMenuViewportHeight(
                rowCount: 0,
                groupHeaderCount: 0,
                showsEmptyHint: true
            ),
            12 + CapturePanelLayout.placeMenuHeaderHeight
                + CapturePanelLayout.completionRowHeight
                + CapturePanelLayout.placeMenuFooterHeight
        )
        XCTAssertEqual(
            CapturePanelLayout.placeMenuViewportHeight(
                rowCount: 0,
                groupHeaderCount: 0,
                showsEmptyHint: false
            ),
            12 + CapturePanelLayout.placeMenuHeaderHeight
                + CapturePanelLayout.placeMenuRowHeight
                + CapturePanelLayout.placeMenuFooterHeight
        )
    }

    func testHashInsideNotebookNoteContentDoesNotRequestSectionCompletion() async throws {
        let model = try makeNotebookModel()
        let draft = "@dev_nvim\n- Existing guide\n  - #"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.latestParse?.input == draft }
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNil(model.completionResponse)
        XCTAssertFalse(model.completionVisible)
        XCTAssertNil(model.placeMenuPresentation())
        XCTAssertEqual(model.plainDraft, draft)
    }

    func testNotebookMenuSelectsExistingOrCleanCreateButLeavesNearMissAndRefusedUnselected() async throws {
        let existing = try await notebookCompletion("@dev_nvim\n- #Setup")
        XCTAssertEqual(existing.selectedCompletionIndex, 0)
        XCTAssertEqual(existing.placeMenuPresentation()?.rows.first?.title, "Setup")
        XCTAssertTrue(existing.placeMenuPresentation()?.rows.first?.isNotebookSection == true)

        let cleanCreate = try await notebookCompletion("@dev_nvim\n- #wireguard")
        XCTAssertEqual(cleanCreate.selectedCompletionIndex, 0)
        XCTAssertEqual(cleanCreate.placeMenuPresentation()?.rows.first?.creates, true)

        let nearMiss = try await notebookCompletion("@dev_nvim\n- #Setp")
        XCTAssertNil(nearMiss.selectedCompletionIndex)
        XCTAssertEqual(nearMiss.placeMenuPresentation()?.rows.first?.refusal, nil)
        XCTAssertEqual(nearMiss.placeMenuPresentation()?.rows.first?.detail, "did you mean Setup?")
        let nearDraft = nearMiss.plainDraft
        XCTAssertFalse(nearMiss.acceptSelectedCompletion())
        XCTAssertEqual(nearMiss.plainDraft, nearDraft)
        XCTAssertTrue(nearMiss.completionVisible)

        let refused = try await notebookCompletion("@dev_dup\n- #git")
        XCTAssertNil(refused.selectedCompletionIndex)
        XCTAssertTrue(refused.completionResponse?.candidates.allSatisfy(CaptureCompletionMenu.isDisabled) == true)
    }

    func testNotebookSectionAcceptanceUsesBobsReplacementAndCaret() throws {
        let model = CapturePanelModel()
        let draft = "@dev_nvim\n- #Setup"
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtureURL("notebook-complete-section-bullet-existing.json"))
        )
        model.plainDraft = draft
        model.completionResponse = response
        model.selectedCompletionIndex = 0
        let candidate = try XCTUnwrap(response.candidates.first)

        XCTAssertTrue(model.acceptSelectedCompletion())

        XCTAssertEqual(model.plainDraft, "@dev_nvim\n- #Setup\n  - ")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), candidate.cursorAfter)
        XCTAssertNil(model.completionResponse)
    }

    func testNotebookSectionAcceptanceUsesBobByteCaretForUnicodeText() throws {
        let model = CapturePanelModel()
        let draft = "@dev_nvim\n- #Café"
        let accepted = "@dev_nvim\n- #Café\n  - "
        let start = draft.utf8.count - "Café".utf8.count
        let candidate = CaptureCompletionCandidate(
            replacement: "Café\n  - ",
            kind: "notebook_section_create",
            title: "Café",
            cursorAfter: accepted.utf8.count,
            group: "new",
            creates: true
        )
        let response = CaptureCompletionResponse(
            ok: true,
            grammar: 26,
            cursor: draft.utf8.count,
            replacement: CaptureRange(start: start, end: draft.utf8.count),
            context: "notebook_section_bullet",
            candidates: [candidate],
            placeMenu: CapturePlaceMenu(
                kind: "notebook_section",
                title: "Section",
                caption: "📓 Neovim · dev",
                groups: [CapturePlaceMenuGroup(id: "new", title: "")],
                newRowPrefix: "＋ ",
                emptyHint: "Type a section name",
                resultsLabel: "sections",
                footerHint: "⏎ choose · ⎋ close"
            )
        )
        model.plainDraft = draft
        model.completionResponse = response
        model.selectedCompletionIndex = 0

        XCTAssertTrue(model.acceptSelectedCompletion())

        XCTAssertEqual(model.plainDraft, accepted)
        XCTAssertGreaterThan(accepted.utf8.count, accepted.count)
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), accepted.utf8.count)
    }

    func testGluedNotebookAcceptanceInsertsBobsSelectorWithoutContinuation() throws {
        let model = CapturePanelModel()
        let draft = "More @dev_nvim#"
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtureURL("notebook-complete-section-glued.json"))
        )
        model.plainDraft = draft
        model.completionResponse = response
        model.selectedCompletionIndex = 0

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "More @dev_nvim#Setup")
        XCTAssertNil(model.completionResponse)
    }

    func testNotebookSelectionFollowsTheSameRowThenFallsBackWhenItDisappears() async throws {
        let model = try makeNotebookModel()
        let empty = "@dev_nvim\n- #"
        model.plainDraft = empty
        model.editorTextDidChange(cursorUTF8Offset: empty.utf8.count)
        await waitUntil { model.completionResponse?.context == "notebook_section_bullet" }
        XCTAssertNil(model.selectedCompletionIndex)

        model.selectNextCompletion()
        XCTAssertEqual(model.selectedCompletionIndex, 0)
        XCTAssertEqual(model.placeMenuPresentation()?.rows.first?.title, "Setup")

        let typed = "@dev_nvim\n- #wireguard"
        model.plainDraft = typed
        model.editorTextDidChange(cursorUTF8Offset: typed.utf8.count)
        await waitUntil {
            model.completionResponse?.candidates.first?.creates == true
        }
        XCTAssertEqual(model.selectedCompletionIndex, 0)
        XCTAssertEqual(model.placeMenuPresentation()?.rows.first?.title, "Wireguard")
        XCTAssertTrue(model.placeMenuPresentation()?.rows.first?.creates == true)
    }

    func testChangingPlaceMenuDestinationClearsNotebookSelection() async throws {
        let selected = try await notebookCompletion("@dev_nvim\n- #Setup")
        XCTAssertEqual(selected.selectedCompletionIndex, 0)

        let drawer = "Postgres 17 minimum @foo+bar#"
        selected.plainDraft = drawer
        selected.editorTextDidChange(cursorUTF8Offset: drawer.utf8.count)
        await waitUntil { selected.completionResponse?.context == "drawer" }
        XCTAssertNil(selected.selectedCompletionIndex)
        XCTAssertEqual(selected.placeMenuPresentation()?.title, "Drawer")
    }

    func testGluedEmptyNotebookOmitsInventedChromeWhenBobSendsNone() async throws {
        let model = try makeNotebookModel()
        let draft = "@dev_empty#"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.latestParse?.input == draft }
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertNil(model.completionResponse?.placeMenu)
        XCTAssertNil(model.placeMenuPresentation())
        XCTAssertFalse(model.completionVisible)
        XCTAssertEqual(model.plainDraft, draft)
        if let response = model.completionResponse {
            XCTAssertEqual(response.context, "section")
            XCTAssertTrue(response.candidates.isEmpty)
        }
    }

    func testStaleNotebookReplacementRangeDismissesWithoutEditingTheDraft() throws {
        let model = CapturePanelModel()
        let draft = "@dev_nvim\n- #Setup"
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixtureURL("notebook-complete-section-bullet-existing.json"))
        )
        model.plainDraft = draft
        model.completionResponse = response
        model.selectedCompletionIndex = 0
        model.plainDraft = "a different draft"

        XCTAssertFalse(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "a different draft")
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(model.statusText, "Completion range is stale")
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

    private func makeNotebookModel() throws -> CapturePanelModel {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_NOTEBOOK_PLACE_MENU": "1",
            ]
        )
        return model
    }

    private func notebookCompletion(_ draft: String) async throws -> CapturePanelModel {
        let model = try makeNotebookModel()
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "notebook_section_bullet" }
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
