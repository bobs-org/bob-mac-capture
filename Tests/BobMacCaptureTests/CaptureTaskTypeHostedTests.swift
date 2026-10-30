import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Hosted task-type menu: completion, accept, hide, refused rows, and
/// the colon rewrite path. Injects Bob's additive contract; Swift only
/// presents it.
@MainActor
final class CaptureTaskTypeHostedTests: XCTestCase {
    func testBareLeadingTrailingAndChildMarkersOpenTaskTypeMenu() async throws {
        let model = try makeModel()
        for draft in ["t:", "t:fix Fix it", "Fix the parser t:"] {
            model.plainDraft = draft
            model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
            await waitUntil { model.completionResponse?.context == "task_type" }
            XCTAssertEqual(model.selectedCompletionIndex, 0, draft)
            XCTAssertNotNil(model.taskTypeMenuPresentation(), draft)
        }

        let child = "Parent task\n- check the lexer t:fi"
        model.plainDraft = child
        model.editorTextDidChange(cursorUTF8Offset: child.utf8.count)
        await waitUntil { model.completionResponse?.context == "task_type" }
        XCTAssertEqual(model.completionResponse?.query, "fi")
    }

    func testMidlineProseDoesNotOpenTaskTypeMenu() async throws {
        let model = try makeModel()
        let draft = "Ask about t:fix today"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertNotEqual(model.completionResponse?.context, "task_type")
    }

    func testColonInTColonSurvivesRewriteAndOpensMenu() async throws {
        let model = try makeModel()
        model.noteSeparatorToggleIntent(
            typed: ":",
            text: "t",
            selectedRange: NSRange(location: 1, length: 0)
        )
        model.plainDraft = "t:"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.completionResponse?.context == "task_type" }
        XCTAssertEqual(model.plainDraft, "t:")
        XCTAssertEqual(model.completionResponse?.query, "")
    }

    func testAcceptReplacesWholeTokenAndPlacesCursor() {
        let model = CapturePanelModel()
        let draft = "Fix the parser t:"
        let start = draft.utf8.count - 2
        let candidate = CaptureCompletionCandidate(
            replacement: "t:fix ",
            cursorAfter: start + 6,
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
            query: "",
            subject: "new"
        )
        model.selectedCompletionIndex = 0
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "Fix the parser t:fix ")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), start + 6)
        XCTAssertNil(model.completionResponse)
    }

    func testLiteralAcceptUsesBobReplacement() {
        let model = CapturePanelModel()
        let draft = "Fix it t:"
        let start = draft.utf8.count - 2
        let candidate = CaptureCompletionCandidate(
            replacement: "t:\"DEEP WORK\" ",
            cursorAfter: start + 14,
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
            query: "",
            subject: "new"
        )
        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "Fix it t:\"DEEP WORK\" ")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), start + 14)
    }

    func testRefusedRowAcceptanceIsNoOp() {
        let model = CapturePanelModel()
        let draft = "Fix it t:fixs"
        let candidate = CaptureCompletionCandidate(
            replacement: "t:fixs",
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
            replacement: "t:fix ",
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
            replacement: "t:write ",
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
            replacement: "t:fixs",
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
            replacement: "t:fix",
            name: "FIX",
            origin: "configured",
            key: "fix",
            effect: "set"
        )
        model.plainDraft = "Fix it t:fix"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 12,
            replacement: CaptureRange(start: 7, end: 12),
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
            replacement: "t:fix ",
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
        model.plainDraft = "t:"
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: 2,
            replacement: CaptureRange(start: 0, end: 2),
            context: "task_type",
            candidates: candidates,
            query: "",
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
