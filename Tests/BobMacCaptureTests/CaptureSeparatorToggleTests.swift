import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureSeparatorToggleTests: XCTestCase {
    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags = [],
        keyCode: UInt16 = 41
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }

    private func makeTextView(_ text: String) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    private func wireNativeApply(_ model: CapturePanelModel, textView: NSTextView) {
        model.applyNativeRewriteEdit = { edit in
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: textView
            )
        }
    }

    private func typeSeparator(
        _ typed: String,
        into textView: NSTextView,
        model: CapturePanelModel
    ) {
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: typed),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        let selection = textView.selectedRange()
        textView.insertText(typed, replacementRange: selection)
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
    }

    private func processClient(
        recordURL: URL? = nil,
        extra: [String: String] = [:]
    ) throws -> BobProcessClient {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        if let recordURL {
            environment["FAKE_BOB_RECORD_PATH"] = recordURL.path
        }
        for (key, value) in extra {
            environment[key] = value
        }
        return BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: environment
        )
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
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

    // MARK: - Intent

    func testIntentRecordsCollapsedColonAndCaret() {
        let model = CapturePanelModel()
        let textView = makeTextView("Do work @file:id")
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^"),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        textView.insertText("^", replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        XCTAssertEqual(model.plainDraft, "Do work @file:id^")
    }

    func testIntentDeclinesCommandControlOptionAndSelection() {
        let model = CapturePanelModel()
        let textView = makeTextView("Do work @file:id")
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^", modifiers: .command),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^", modifiers: .control),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^", modifiers: .option),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        textView.setSelectedRange(NSRange(location: 0, length: 2))
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^"),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        model.plainDraft = "Do work @file:id^"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        XCTAssertNotEqual(model.statusText, "Changed @file:id to @file^id")
    }

    func testIntentDeclinesModalFieldsAndMarkedText() {
        let model = CapturePanelModel()
        let textView = makeTextView("Do work @file:id")
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^"),
            firstResponder: textView,
            model: model,
            modalFieldActive: true
        )
        textView.setMarkedText(
            "^",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: (textView.string as NSString).length, length: 0)
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "^"),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        textView.unmarkText()
        model.plainDraft = "Do work @file:id^"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        XCTAssertNotEqual(model.statusText, "Changed @file:id to @file^id")
    }

    // MARK: - Native apply

    func testCaretKeySwitchesColonMarkerThroughNativeInsert() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil {
            model.plainDraft == "Do work @file^id"
                && model.statusText == "Changed @file:id to @file^id"
        }

        XCTAssertEqual(textView.string, "Do work @file^id")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 16, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 16)
        XCTAssertNil(model.completionResponse)
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 17 --format json -- Do work @file:id^"))
        XCTAssertFalse(record.contains("capture-complete --all-tasks --cursor 17"))
    }

    func testColonKeySwitchesCaretMarkerThroughNativeInsert() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("Do work @file^id")
        wireNativeApply(model, textView: textView)

        typeSeparator(":", into: textView, model: model)
        await waitUntil {
            model.plainDraft == "Do work @file:id"
                && model.statusText == "Changed @file^id to @file:id"
        }

        XCTAssertEqual(textView.string, "Do work @file:id")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 16)
    }

    func testPickerAcceptedIDThenToggle() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("@file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.plainDraft == "@file^id" }

        XCTAssertEqual(textView.string, "@file^id")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 8)
        XCTAssertNil(model.picker)
    }

    func testUnicodeDraftConvertsCursorToNativeRange() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("Hi 🧪 @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.plainDraft == "Hi 🧪 @file^id" }

        XCTAssertEqual(textView.string, "Hi 🧪 @file^id")
        let expectedUTF16 = ("Hi 🧪 @file^id" as NSString).length
        XCTAssertEqual(textView.selectedRange(), NSRange(location: expectedUTF16, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), "Hi 🧪 @file^id".utf8.count)
    }

    func testNativeUndoAndRedoDoNotRetriggerAssist() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { textView.string == "Do work @file^id" }

        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Do work @file:id^")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(textView.string, "Do work @file:id^")

        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "Do work @file^id")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(textView.string, "Do work @file^id")

        let record = try String(contentsOf: recordURL)
        let rewriteCount = record.components(separatedBy: "argv=capture-rewrite").count - 1
        XCTAssertEqual(rewriteCount, 1)
    }

    func testSubsequentTypingAfterToggleDoesNotRetrigger() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.plainDraft == "Do work @file^id" }

        textView.insertText(" ", replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 80_000_000)

        XCTAssertEqual(model.plainDraft, "Do work @file^id ")
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-rewrite").count - 1, 1)
    }

    func testNoOpAndFailureLeaveLiteralText() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("hello")
        wireNativeApply(model, textView: textView)
        typeSeparator(":", into: textView, model: model)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.plainDraft, "hello:")
        XCTAssertEqual(textView.string, "hello:")

        let failing = CapturePanelModel(debounceNanoseconds: 0)
        failing.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_FAIL": "1"])
        let failingView = makeTextView("Do work @file:id")
        wireNativeApply(failing, textView: failingView)
        typeSeparator("^", into: failingView, model: failing)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(failing.plainDraft, "Do work @file:id^")
        XCTAssertEqual(failingView.string, "Do work @file:id^")
    }

    func testMalformedRangesDoNotMutateDraft() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_MALFORMED": "1"])
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)
        typeSeparator("^", into: textView, model: model)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.plainDraft, "Do work @file:id^")
        XCTAssertEqual(textView.string, "Do work @file:id^")
    }

    func testDelayedResponseIgnoredAfterEditCaretSubmitAndClientChange() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)
        typeSeparator("^", into: textView, model: model)

        model.plainDraft = "other"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        model.plainDraft = "Do work @file:id^"
        model.editorTextDidChange(cursorUTF8Offset: model.plainDraft.utf8.count)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(model.plainDraft, "Do work @file:id^")

        let caretModel = CapturePanelModel(debounceNanoseconds: 0)
        caretModel.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let caretView = makeTextView("Do work @file:id")
        wireNativeApply(caretModel, textView: caretView)
        typeSeparator("^", into: caretView, model: caretModel)
        caretModel.editorSelectionDidChange(cursorUTF8Offset: 0)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(caretModel.plainDraft, "Do work @file:id^")

        let submitModel = CapturePanelModel(debounceNanoseconds: 0)
        submitModel.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let submitView = makeTextView("Do work @file:id")
        wireNativeApply(submitModel, textView: submitView)
        typeSeparator("^", into: submitView, model: submitModel)
        submitModel.submit(openAfterCapture: false)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertNotEqual(submitModel.statusText, "Changed @file:id to @file^id")

        let clientModel = CapturePanelModel(debounceNanoseconds: 0)
        clientModel.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let clientView = makeTextView("Do work @file:id")
        wireNativeApply(clientModel, textView: clientView)
        typeSeparator("^", into: clientView, model: clientModel)
        clientModel.setProcessClient(try processClient())
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(clientModel.plainDraft, "Do work @file:id^")

        let dismissModel = CapturePanelModel(debounceNanoseconds: 0)
        dismissModel.processClient = try processClient(extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"])
        let dismissView = makeTextView("Do work @file:id")
        wireNativeApply(dismissModel, textView: dismissView)
        typeSeparator("^", into: dismissView, model: dismissModel)
        dismissModel.prepareForDismissal()
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertEqual(dismissModel.plainDraft, "Do work @file:id^")
    }

    func testNativeApplyDeclinesMarkedTextAndMissingEditor() {
        let textView = makeTextView("Do work @file:id^")
        textView.setMarkedText(
            "x",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 17, length: 0)
        )
        let edit = CaptureNativeRewriteEdit(
            replacementRange: NSRange(location: 8, length: 9),
            replacementText: "@file^id",
            resultingSelection: NSRange(location: 16, length: 0),
            expectedDraft: "Do work @file:id^",
            resultingDraft: "Do work @file^id"
        )
        XCTAssertFalse(
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: textView
            )
        )
        textView.unmarkText()
        XCTAssertFalse(
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: nil
            )
        )
    }

    func testWithoutNativeApplierLeavesLiteralToggleText() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        model.noteSeparatorToggleIntent(
            typed: "^",
            text: "Do work @file:id",
            selectedRange: NSRange(location: 16, length: 0)
        )
        model.plainDraft = "Do work @file:id^"
        model.editorTextDidChange(cursorUTF8Offset: 17)
        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(model.plainDraft, "Do work @file:id^")
    }
}
