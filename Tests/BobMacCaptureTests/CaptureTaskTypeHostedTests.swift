import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Hosted task-type menu: completion, accept, hide, refused rows, and
/// the retired `t:` prose path. Injects Bob's additive contract; Swift only
/// presents it.
@MainActor
final class CaptureTaskTypeHostedTests: XCTestCase {
    func testBareLeadingTrailingAndChildMarkersOpenTaskTypeMenu() async throws {
        let model = try makeModel()
        for draft in ["#f", "#fix Fix it", "Fix the parser #f"] {
            model.plainDraft = draft
            model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
            await waitUntil { model.completionResponse?.context == "task_type" }
            XCTAssertEqual(model.selectedCompletionIndex, 0, draft)
            XCTAssertNotNil(model.taskTypeMenuPresentation(), draft)
        }

        let child = "Parent task\n- check the lexer #fi"
        model.plainDraft = child
        model.editorTextDidChange(cursorUTF8Offset: child.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_type" }
        XCTAssertEqual(model.completionResponse?.query, "fi")
    }

    func testMidlineProseDoesNotOpenTaskTypeMenu() async throws {
        let model = try makeModel()
        let draft = "Ask about #fix today"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNotEqual(model.completionResponse?.context, "task_type")
    }

    func testBareHashRequestsTaskTypeCompletion() async throws {
        let model = try makeModel()
        let draft = "jot idea #"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_type" }
        XCTAssertEqual(model.completionResponse?.query, "")
        XCTAssertNil(model.selectedCompletionIndex)
        XCTAssertEqual(
            model.taskTypeMenuPresentation()?.selectedFooter,
            CaptureCompletionMenu.unselectedFooterHint
        )
    }

    func testUnselectedMenuTabTakesTheFirstRow() async throws {
        let model = try makeModel()
        let draft = "jot idea #"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_type" }
        XCTAssertNil(model.selectedCompletionIndex)

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "jot idea #build")
        XCTAssertNil(model.completionResponse)
    }

    func testUnselectedMenuDownSelectsTheFirstRowWithoutInserting() async throws {
        let model = try makeModel()
        let draft = "jot idea #"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_type" }

        model.selectNextCompletion()
        XCTAssertEqual(model.selectedCompletionIndex, 0)
        XCTAssertEqual(model.plainDraft, draft)
        XCTAssertEqual(model.completionResponse?.context, "task_type")
    }

    func testUnselectedMenuUpSelectsTheLastRow() async throws {
        let model = try makeModel()
        let draft = "jot idea #"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_type" }

        model.selectPreviousCompletion()
        let lastIndex = try XCTUnwrap(model.completionResponse).candidates.count - 1
        XCTAssertEqual(model.selectedCompletionIndex, lastIndex)
        XCTAssertEqual(model.plainDraft, draft)
    }

    func testUnselectedMenuEscapeClosesWithoutChangingTheDraft() async throws {
        let model = try makeModel()
        let draft = "jot idea #"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_type" }

        model.dismissCompletion()
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.selectedCompletionIndex)
        XCTAssertEqual(model.plainDraft, draft)
    }

    func testTypingAfterAnUnselectedMenuRanksAFreshSelection() async throws {
        let model = try makeModel()
        let draft = "jot idea #"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_type" }
        XCTAssertNil(model.selectedCompletionIndex)

        let typed = "jot idea #f"
        model.plainDraft = typed
        model.editorTextDidChange(cursorUTF8Offset: typed.utf8.count)
        await waitUntil { model.completionResponse?.query == "f" }
        XCTAssertEqual(model.completionResponse?.context, "task_type")
        XCTAssertEqual(model.selectedCompletionIndex, 0)
        XCTAssertFalse(model.completionResponse?.opensWithoutSelection == true)
    }

    func testAcceptReplacesWholeTokenAndPlacesCursor() {
        let model = CapturePanelModel()
        let draft = "Fix the parser #f"
        let start = draft.utf8.count - 2
        let candidate = CaptureCompletionCandidate(
            replacement: "#fix",
            cursorAfter: start + 4,
            name: "FIX",
            themes: [
                CapturePomodoroThemeRef(
                    key: "fix", name: "FIX", hue: .blue, hueSource: "config",
                    configured: true)
            ],
            origin: "configured",
            key: "fix",
            effect: "set"
        )
        model.plainDraft = draft
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: draft.utf8.count,
            replacement: CaptureRange(start: start, end: draft.utf8.count),
            context: "task_type",
            candidates: [candidate],
            query: "f",
            subject: "new"
        )
        model.selectedCompletionIndex = 0
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "Fix the parser #fix")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), start + 4)
        XCTAssertNil(model.completionResponse)
    }

    func testLiteralAcceptUsesBobReplacement() {
        let model = CapturePanelModel()
        let draft = "Fix it #d"
        let start = draft.utf8.count - 2
        let candidate = CaptureCompletionCandidate(
            replacement: "#\"DEEP WORK\"",
            cursorAfter: start + 12,
            name: "DEEP WORK",
            origin: "configured",
            key: "deep work",
            effect: "set"
        )
        model.plainDraft = draft
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: draft.utf8.count,
            replacement: CaptureRange(start: start, end: draft.utf8.count),
            context: "task_type",
            candidates: [candidate],
            query: "d",
            subject: "new"
        )
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "Fix it #\"DEEP WORK\"")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), start + 12)
    }

    func testRefusedRowAcceptanceIsNoOp() {
        let model = CapturePanelModel()
        let draft = "Fix it #fixs"
        let candidate = CaptureCompletionCandidate(
            replacement: "#fixs",
            name: "FIXS",
            origin: "typed",
            key: "fixs",
            effect: "set",
            refused: "type_not_configured"
        )
        model.plainDraft = draft
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: draft.utf8.count,
            replacement: CaptureRange(start: 7, end: draft.utf8.count),
            context: "task_type",
            candidates: [candidate],
            query: "fixs",
            subject: "new"
        )
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, draft)
        XCTAssertEqual(model.completionResponse?.context, "task_type")
        XCTAssertEqual(model.selectedCompletionIndex, 0)
    }

    func testConfiguredCtrlDHidesAndShowsThroughBob() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try makeModel(recordURL: recordURL)
        let candidate = CaptureCompletionCandidate(
            replacement: "#fix ",
            name: "FIX",
            themes: [
                CapturePomodoroThemeRef(
                    key: "fix", name: "FIX", hue: .blue, hueSource: "config",
                    configured: true)
            ],
            origin: "configured",
            key: "fix",
            effect: "set"
        )
        installTaskTypeCompletion(on: model, candidates: [candidate])
        XCTAssertTrue(model.completionHasSelectedHistoryTheme)
        model.toggleSelectedCompletionThemeVisibility()
        await waitUntil {
            !model.completionThemeVisibilityWriteInFlight
                && model.temporarilyHiddenThemeKey == "fix"
        }
        XCTAssertEqual(model.rowContent(for: candidate).secondaryText, "Hidden · ⌃D undo")

        model.toggleSelectedCompletionThemeVisibility()
        await waitUntil {
            !model.completionThemeVisibilityWriteInFlight
                && model.temporarilyHiddenThemeKey == nil
        }
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=themes hide FIX --via bob-mac-capture --format json"))
        XCTAssertTrue(record.contains("argv=themes unhide FIX --via bob-mac-capture --format json"))
    }

    func testInitiallyHiddenHistoryRowShowsOnFirstCtrlD() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try makeModel(recordURL: recordURL)
        let candidate = CaptureCompletionCandidate(
            replacement: "#write ",
            name: "WRITE",
            themes: [
                CapturePomodoroThemeRef(
                    key: "write", name: "WRITE", hue: .magenta, hueSource: "config",
                    configured: true)
            ],
            origin: "history",
            hidden: true,
            key: "write",
            effect: "set"
        )
        installTaskTypeCompletion(on: model, candidates: [candidate])
        let presentation = try XCTUnwrap(model.taskTypeMenuPresentation())
        XCTAssertEqual(presentation.hideKeycap, "⌃D show")
        XCTAssertTrue(presentation.rows[0].currentlyHidden)

        model.toggleSelectedCompletionThemeVisibility()
        await waitUntil {
            !model.completionThemeVisibilityWriteInFlight
                && model.temporarilyHiddenThemeKey == "write"
        }
        let shown = try XCTUnwrap(model.taskTypeMenuPresentation())
        XCTAssertEqual(shown.hideKeycap, "⌃D hide")
        XCTAssertFalse(shown.rows[0].currentlyHidden)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=themes unhide WRITE --via bob-mac-capture --format json"))
    }

    func testTypedRowDoesNotWriteVisibility() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = try makeModel(recordURL: recordURL)
        let candidate = CaptureCompletionCandidate(
            replacement: "#fixs",
            name: "FIXS",
            themes: [
                CapturePomodoroThemeRef(
                    key: "fixs", name: "FIXS", known: false, configured: false)
            ],
            origin: "typed",
            similarTo: ["FIX"],
            key: "fixs",
            effect: "set"
        )
        installTaskTypeCompletion(on: model, candidates: [candidate])
        XCTAssertFalse(model.completionHasSelectedHistoryTheme)
        XCTAssertNil(model.taskTypeMenuPresentation()?.hideKeycap)
        model.toggleSelectedCompletionThemeVisibility()
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertFalse(FileManager.default.fileExists(atPath: recordURL.path))
        XCTAssertNil(model.temporarilyHiddenThemeKey)
    }

    func testTaskTypeQueryUsesServerQueryNotReplacementSlice() throws {
        let model = CapturePanelModel()
        let candidate = CaptureCompletionCandidate(
            replacement: "#fix",
            name: "FIX",
            origin: "configured",
            key: "fix",
            effect: "set"
        )
        model.plainDraft = "Fix it #fix"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 11,
            replacement: CaptureRange(start: 7, end: 11),
            context: "task_type",
            candidates: [candidate],
            query: "fix",
            subject: "new"
        )
        let content = model.rowContent(for: candidate)
        XCTAssertEqual(content.primaryMatchRange, 0..<3)
        let presentation = try XCTUnwrap(model.taskTypeMenuPresentation())
        XCTAssertEqual(presentation.rows.first?.queryMatchRange, 0..<3)
    }

    func testDraftChangeClearsHideGhost() async throws {
        let model = try makeModel()
        let candidate = CaptureCompletionCandidate(
            replacement: "#fix ",
            name: "FIX",
            themes: [
                CapturePomodoroThemeRef(key: "fix", name: "FIX", configured: true)
            ],
            origin: "configured",
            key: "fix",
            effect: "set"
        )
        installTaskTypeCompletion(on: model, candidates: [candidate])
        model.toggleSelectedCompletionThemeVisibility()
        await waitUntil {
            !model.completionThemeVisibilityWriteInFlight
                && model.temporarilyHiddenThemeKey == "fix"
        }
        model.plainDraft = "changed"
        model.editorTextDidChange()
        XCTAssertNil(model.temporarilyHiddenThemeKey)
    }

    // MARK: - Helpers

    private func makeModel(recordURL: URL? = nil) throws -> CapturePanelModel {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_TASK_TYPE_CHOOSER": "1",
        ]
        if let recordURL {
            environment["FAKE_BOB_RECORD_PATH"] = recordURL.path
        }
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: environment
        )
        return model
    }

    private func installTaskTypeCompletion(
        on model: CapturePanelModel,
        candidates: [CaptureCompletionCandidate]
    ) {
        model.plainDraft = "#f"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 2,
            replacement: CaptureRange(start: 0, end: 2),
            context: "task_type",
            candidates: candidates,
            query: "f",
            subject: "new"
        )
        model.selectedCompletionIndex = 0
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot =
            source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return
            packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
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
