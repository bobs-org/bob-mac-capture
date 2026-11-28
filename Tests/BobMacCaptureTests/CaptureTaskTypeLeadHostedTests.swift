import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Hosted type-lead accept: two native undo groups, one-key Backspace peel,
/// and accept-and-capture skipping the lead.
@MainActor
final class CaptureTaskTypeLeadHostedTests: XCTestCase {
    func testTabReturnAndClickInsertTheLead() {
        for gesture in ["Tab", "Return", "click"] {
            let (model, controller, textView, panel) = makeHostedEditor(draft: "#f")
            defer { panel.orderOut(nil) }
            installFixLead(on: model, textView: textView)

            accept(gesture, model: model, controller: controller)

            XCTAssertEqual(model.plainDraft, "#fix Fix ", gesture)
            XCTAssertEqual(textView.string, "#fix Fix ", gesture)
            XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 9, gesture)
            XCTAssertEqual(
                textView.selectedRange(),
                NSRange(location: 9, length: 0),
                gesture
            )
            XCTAssertNotNil(model.typeLeadPeelForTests(), gesture)
            XCTAssertNil(model.completionResponse, gesture)
        }
    }

    func testRouteBulkChildAndNonASCIILeadsInsert() {
        let cases: [(String, CaptureRange, Int, CaptureCompletionCandidate, String, Int)] = [
            (
                "@cash #f",
                CaptureRange(start: 6, end: 8),
                8,
                fixLead(replacement: "#fix ", cursorAfter: 11, insertAt: 11, cursor: 15),
                "@cash #fix Fix ",
                15
            ),
            (
                "Buy milk\n\n#f",
                CaptureRange(start: 10, end: 12),
                12,
                fixLead(replacement: "#fix ", cursorAfter: 15, insertAt: 15, cursor: 19),
                "Buy milk\n\n#fix Fix ",
                19
            ),
            (
                "#f\n  - child",
                CaptureRange(start: 0, end: 2),
                2,
                fixLead(
                    replacement: "#fix",
                    cursorAfter: 4,
                    insertAt: 4,
                    insertion: " Fix ",
                    cursor: 9
                ),
                "#fix Fix \n  - child",
                9
            ),
            (
                "#f",
                CaptureRange(start: 0, end: 2),
                2,
                fixLead(
                    replacement: "#fix ",
                    cursorAfter: 5,
                    insertAt: 5,
                    insertion: "Réparer ",
                    cursor: 5 + "Réparer ".utf8.count,
                    text: "Réparer"
                ),
                "#fix Réparer ",
                5 + "Réparer ".utf8.count
            ),
        ]
        for (draft, range, cursor, candidate, expected, expectedCursor) in cases {
            let (model, _, textView, panel) = makeHostedEditor(draft: draft)
            defer { panel.orderOut(nil) }
            installLead(
                on: model,
                textView: textView,
                draft: draft,
                range: range,
                cursor: cursor,
                candidate: candidate
            )

            XCTAssertTrue(model.acceptSelectedCompletion(), draft)
            XCTAssertEqual(model.plainDraft, expected, draft)
            XCTAssertEqual(textView.string, expected, draft)
            XCTAssertEqual(model.collapsedSelectionUTF8Offset(), expectedCursor, draft)
            XCTAssertNotNil(model.typeLeadPeelForTests(), draft)
        }
    }

    func testUndoPeelsTheLeadThenRestoresTheMarker() {
        let (model, _, textView, panel) = makeHostedEditor(draft: "#f")
        defer { panel.orderOut(nil) }
        installFixLead(on: model, textView: textView)

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(textView.string, "#fix Fix ")
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "#fix ")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "#f")
    }

    func testBackspacePeelsTheLeadAndUndoRestoresIt() async throws {
        let (model, controller, textView, panel) = makeHostedEditor(draft: "#f")
        defer { panel.orderOut(nil) }
        installFixLead(on: model, textView: textView)

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(textView.string, "#fix Fix ")
        XCTAssertTrue(panel.makeFirstResponder(textView))
        // Accept and Backspace are separate key events in production, so they
        // land in separate undo groups. Yield a runloop turn here for the same
        // boundary; otherwise the peel joins the still-open accept group.
        CapturePanelController.closeUndoGroupForNextEdit(textView)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertTrue(controller.perform(.deleteBackward))
        XCTAssertEqual(textView.string, "#fix ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertNil(model.typeLeadPeelForTests())

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "#fix Fix ")
    }

    func testTypingThenBackspaceDeletesNativelyNotTheLead() {
        let (model, controller, textView, panel) = makeHostedEditor(draft: "#f")
        defer { panel.orderOut(nil) }
        installFixLead(on: model, textView: textView)

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertTrue(panel.makeFirstResponder(textView))

        textView.insertText("x", replacementRange: textView.selectedRange())
        syncModel(model, from: textView)
        XCTAssertEqual(textView.string, "#fix Fix x")
        XCTAssertNil(model.typeLeadPeelForTests())

        nativeBackspace(controller: controller, textView: textView)
        syncModel(model, from: textView)
        XCTAssertEqual(textView.string, "#fix Fix ")
        XCTAssertNil(model.typeLeadPeelForTests())

        nativeBackspace(controller: controller, textView: textView)
        syncModel(model, from: textView)
        XCTAssertEqual(textView.string, "#fix Fix")
        XCTAssertNil(model.typeLeadPeelForTests())
    }

    func testCaretMoveAwayAndBackDisarmsThePeel() throws {
        let (model, controller, textView, panel) = makeHostedEditor(draft: "#f")
        defer { panel.orderOut(nil) }
        installFixLead(on: model, textView: textView)

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertNotNil(model.typeLeadPeelForTests())
        XCTAssertTrue(panel.makeFirstResponder(textView))

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        model.editorSelectionDidChange(cursorUTF8Offset: 0)
        XCTAssertNil(model.typeLeadPeelForTests())

        let end = (textView.string as NSString).length
        textView.setSelectedRange(NSRange(location: end, length: 0))
        let insertion = try XCTUnwrap(
            attributedStringIndex(in: model.attributedDraft, utf8Offset: 9)
        )
        model.editorSelection = AttributedTextSelection(insertionPoint: insertion)
        model.editorSelectionDidChange(cursorUTF8Offset: 9)
        XCTAssertNil(model.typeLeadPeelForTests())

        nativeBackspace(controller: controller, textView: textView)
        XCTAssertEqual(textView.string, "#fix Fix")
    }

    func testControlAndCommandReturnSkipTheLeadAndRefuse() async throws {
        let refusal = """
            {"ok":false,"code":"type_marker_needs_task","error":"`#fix` needs a task"}
            """
        for gesture in ["Control-Return", "Command-Return"] {
            let recordURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            let client = BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": recordURL.path,
                    "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": refusal,
                    "FAKE_BOB_CAPTURE_DRY_RUN_EXIT": "1",
                    "FAKE_BOB_CAPTURE_WRITE_STDOUT": refusal,
                    "FAKE_BOB_CAPTURE_WRITE_EXIT": "1",
                ]
            )
            let (model, controller, textView, panel) = makeHostedEditor(
                draft: "#f",
                processClient: client
            )
            defer { panel.orderOut(nil) }
            installFixLead(on: model, textView: textView)
            model.installCompatibleCaptureGrammarForTests()

            XCTAssertTrue(controller.perform(.acceptCompletionThenSubmitAndOpen))
            XCTAssertEqual(model.plainDraft, "#fix ", gesture)
            XCTAssertFalse(model.plainDraft.contains("Fix"), gesture)
            XCTAssertNil(model.typeLeadPeelForTests(), gesture)

            await waitUntil { model.errorCode == "type_marker_needs_task" }
            XCTAssertEqual(model.plainDraft, "#fix ", gesture)
            XCTAssertNotEqual(model.plainDraft, "", gesture)
        }
    }

    func testStaleResponseAcceptsTheMarkerOnly() {
        let (model, _, textView, panel) = makeHostedEditor(draft: "#f")
        defer { panel.orderOut(nil) }
        installFixLead(on: model, textView: textView)
        model.setCompletionDraftSnapshotForTests("stale")

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "#fix ")
        XCTAssertEqual(textView.string, "#f")
        XCTAssertNil(model.typeLeadPeelForTests())
    }

    func testResponseWithoutLeadKeepsTodaysMarkerPath() {
        let (model, _, textView, panel) = makeHostedEditor(draft: "#f")
        defer { panel.orderOut(nil) }
        installLead(
            on: model,
            textView: textView,
            draft: "#f",
            range: CaptureRange(start: 0, end: 2),
            cursor: 2,
            candidate: CaptureCompletionCandidate(
                replacement: "#fix ",
                cursorAfter: 5,
                name: "FIX",
                origin: "configured",
                key: "fix",
                effect: "set"
            )
        )

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertEqual(model.plainDraft, "#fix ")
        XCTAssertNil(model.typeLeadPeelForTests())
        XCTAssertNil(model.completionResponse)
    }

    func testAcceptDoesNotReopenTheTypeMenu() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        let (model, _, textView, panel) = makeHostedEditor(
            draft: "#f",
            processClient: client
        )
        defer { panel.orderOut(nil) }
        installFixLead(on: model, textView: textView)

        XCTAssertTrue(model.acceptSelectedCompletion())
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(model.plainDraft, "#fix Fix ")

        let deadline = Date().addingTimeInterval(0.25)
        while Date() < deadline {
            XCTAssertNil(model.completionResponse)
            XCTAssertNil(model.taskTypeMenuPresentation())
            try await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // MARK: - Helpers

    private func makeHostedEditor(
        draft: String,
        processClient: BobProcessClient? = nil
    ) -> (CapturePanelModel, CapturePanelController, NSTextView, NSPanel) {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = processClient
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = draft
        model.plainDraft = draft
        model.applyNativeRewriteEdit = { edit in
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: textView
            )
        }
        panel.contentView = textView
        XCTAssertTrue(panel.makeFirstResponder(textView))
        return (model, controller, textView, panel)
    }

    private func installFixLead(on model: CapturePanelModel, textView: NSTextView) {
        installLead(
            on: model,
            textView: textView,
            draft: "#f",
            range: CaptureRange(start: 0, end: 2),
            cursor: 2,
            candidate: fixLead()
        )
    }

    private func installLead(
        on model: CapturePanelModel,
        textView: NSTextView,
        draft: String,
        range: CaptureRange,
        cursor: Int,
        candidate: CaptureCompletionCandidate
    ) {
        model.plainDraft = draft
        if let caret = utf16Range(in: draft, start: cursor, end: cursor) {
            textView.string = draft
            textView.setSelectedRange(NSRange(location: caret.location, length: 0))
        }
        if let insertion = attributedStringIndex(
            in: model.attributedDraft,
            utf8Offset: cursor
        ) {
            model.editorSelection = AttributedTextSelection(insertionPoint: insertion)
        }
        model.completionResponse = CaptureCompletionResponse(
            ok: true,
            cursor: cursor,
            replacement: range,
            context: "task_type",
            candidates: [candidate],
            query: "f",
            subject: "new"
        )
        model.selectedCompletionIndex = 0
        model.setCompletionDraftSnapshotForTests(draft)
    }

    private func fixLead(
        replacement: String = "#fix ",
        cursorAfter: Int = 5,
        insertAt: Int = 5,
        insertion: String = "Fix ",
        cursor: Int = 9,
        text: String = "Fix"
    ) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: replacement,
            cursorAfter: cursorAfter,
            name: "FIX",
            origin: "configured",
            key: "fix",
            effect: "set",
            lead: CaptureTaskTypeLead(
                text: text,
                insertAt: insertAt,
                insertion: insertion,
                cursorAfter: cursor
            )
        )
    }

    private func accept(
        _ gesture: String,
        model: CapturePanelModel,
        controller: CapturePanelController
    ) {
        switch gesture {
        case "Tab", "Return":
            controller.perform(.acceptCompletion)
        default:
            XCTAssertTrue(model.acceptSelectedCompletion(), gesture)
        }
    }

    private func syncModel(_ model: CapturePanelModel, from textView: NSTextView) {
        model.plainDraft = textView.string
        let caretUTF8 = utf8Offset(
            in: textView.string,
            utf16Offset: textView.selectedRange().location
        ) ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
    }

    private func nativeBackspace(
        controller: CapturePanelController,
        textView: NSTextView
    ) {
        if !controller.perform(.deleteBackward) {
            textView.deleteBackward(nil)
        }
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
