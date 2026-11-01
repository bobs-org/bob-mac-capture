import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Hosted `%` directive menu: unselected open, Tab/Down/Escape, and
/// disabled-row consume. Bob authors the rows; Swift only presents them.
@MainActor
final class CaptureDirectiveMenuHostedTests: XCTestCase {
    func testBarePercentOpensAnUnselectedDirectiveMenu() async throws {
        let model = try makeModel()
        let draft = "jot idea %"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.completionResponse?.context == "directive" }
        XCTAssertTrue(model.completionResponse?.opensWithoutSelection == true)
        XCTAssertNil(model.selectedCompletionIndex)
        XCTAssertEqual(model.completionResponse?.candidates.first?.token, "%c")
    }

    func testTabTakesTheFirstDirectiveRow() {
        let model = CapturePanelModel()
        installBarePercentMenu(on: model)
        XCTAssertNil(model.selectedCompletionIndex)

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "jot idea %c")
        XCTAssertNil(model.completionResponse)
    }

    func testDownSelectsTheFirstDirectiveRowWithoutInserting() {
        let model = CapturePanelModel()
        installBarePercentMenu(on: model)

        model.selectNextCompletion()
        XCTAssertEqual(model.selectedCompletionIndex, 0)
        XCTAssertEqual(model.plainDraft, "jot idea %")
        XCTAssertEqual(model.completionResponse?.context, "directive")
    }

    func testDisabledDirectiveRowConsumesAcceptance() {
        let model = CapturePanelModel()
        let draft = "https://example.com/essay %"
        let start = draft.utf8.count - 1
        let disabled = CaptureCompletionCandidate(
            replacement: "",
            token: "%l",
            summary: "Queue this URL with companion audio",
            detail: "No `highlights.listen_command` is configured.",
            cursorAfter: start,
            name: "Listen",
            disabledReason: "Configure `highlights.listen_command` to enable companion audio."
        )
        model.plainDraft = draft
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: draft.utf8.count,
            replacement: CaptureRange(start: start, end: draft.utf8.count),
            context: "directive",
            candidates: [disabled],
            initialSelection: "none",
            query: ""
        )
        model.selectedCompletionIndex = nil

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, draft)
        XCTAssertEqual(model.completionResponse?.context, "directive")
        XCTAssertEqual(model.selectedCompletionIndex, 0)
    }

    func testEscapeClosesTheDirectiveMenu() {
        let model = CapturePanelModel()
        installBarePercentMenu(on: model)
        model.dismissCompletion()
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(model.plainDraft, "jot idea %")
    }

    func testUnicodePrefixDirectiveAcceptanceUsesUTF8Offsets() {
        let model = CapturePanelModel()
        let draft = "café %"
        let start = draft.utf8.count - 1
        model.plainDraft = draft
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: draft.utf8.count,
            replacement: CaptureRange(start: start, end: draft.utf8.count),
            context: "directive",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "%c",
                    token: "%c",
                    summary: "Paste clipboard content",
                    cursorAfter: start + 2,
                    name: "Clip"
                )
            ],
            initialSelection: "none",
            query: ""
        )
        model.selectedCompletionIndex = nil

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "café %c")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), start + 2)
    }

    func testCancelTaskIDPromptRestoresAnUnselectedChooser() {
        let model = CapturePanelModel()
        let draft = "note @Cash+goog"
        let missing = CaptureCompletionCandidate(
            replacement: "",
            route: "cash",
            taskRef: "8:missing",
            requiresBlockID: true,
            text: "Plan the handoff"
        )
        model.plainDraft = draft
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: draft.utf8.count,
            replacement: CaptureRange(start: 11, end: 15),
            context: "task",
            candidates: [missing],
            query: "goog"
        )
        model.taskIDPrompt = CaptureTaskIDPromptState(
            candidate: missing,
            draftSnapshot: draft,
            replacementRange: CaptureRange(start: 11, end: 15),
            selectedCompletionIndex: nil,
            authoredID: "new-id",
            isSaving: false,
            errorMessage: nil
        )

        model.cancelTaskIDPrompt()

        XCTAssertNil(model.taskIDPrompt)
        XCTAssertEqual(model.plainDraft, draft)
        XCTAssertTrue(model.completionVisible)
        XCTAssertNil(model.selectedCompletionIndex)
    }

    private func installBarePercentMenu(on model: CapturePanelModel) {
        let draft = "jot idea %"
        let start = draft.utf8.count - 1
        model.plainDraft = draft
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: draft.utf8.count,
            replacement: CaptureRange(start: start, end: draft.utf8.count),
            context: "directive",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "%c",
                    token: "%c",
                    summary: "Paste clipboard content",
                    cursorAfter: start + 2,
                    name: "Clip"
                ),
                CaptureCompletionCandidate(
                    replacement: "%n",
                    token: "%n",
                    summary: "Add a note to a Pomodoro",
                    cursorAfter: start + 2,
                    name: "Pomodoro note"
                ),
            ],
            initialSelection: "none",
            query: ""
        )
        model.selectedCompletionIndex = nil
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
