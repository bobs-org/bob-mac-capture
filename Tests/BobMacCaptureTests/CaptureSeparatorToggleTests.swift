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
            event: keyEvent(characters: typed, modifiers: typed == "|" ? .shift : []),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        let selection = textView.selectedRange()
        textView.insertText(typed, replacementRange: selection)
        model.plainDraft = textView.string
        let caretUTF16 = textView.selectedRange().location
        let caretUTF8 = utf8Offset(in: textView.string, utf16Offset: caretUTF16)
            ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
    }

    private func relationCandidate(from: Bool = false) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: from ? "~~tasks:source" : "~tasks:target",
            taskRef: from ? "2:bbbb2222" : "1:aaaa1111",
            blockID: from ? "source" : "target",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: from ? "Source" : "Target",
            group: "open",
            notePath: "tasks.md",
            locator: "tasks"
        )
    }

    private func installRelationPicker(
        on model: CapturePanelModel,
        from: Bool = false,
        draft: String? = nil
    ) {
        let direction: DependencyPickerDirection = from ? .linkedFrom : .linksTo
        model.installRelationPickerForPreviews(
            candidates: [relationCandidate(from: from)],
            draft: draft ?? (from ? "New task ~~" : "New task ~"),
            replacement: CaptureRange(start: 9, end: from ? 11 : 10),
            owner: DependencyOwner(kind: "new_task", text: "New task"),
            direction: direction
        )
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
        // Native undo lives on the window: a windowless text view has no
        // undo manager, so undo and redo would silently do nothing.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = makeTextView("Do work @file:id")
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 16, length: 0))
        XCTAssertNotNil(textView.undoManager)
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
        // History stays intact: the swap undoes again, then the typed key.
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Do work @file:id^")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Do work @file:id")

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

    // MARK: - Completion after an untoggled separator

    func testTypedColonAfterRouteOpensLinkPickerThroughKeyIntent() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("@file")
        wireNativeApply(model, textView: textView)

        typeSeparator(":", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        guard case .blockID = model.picker?.source else {
            XCTFail("expected a block-ID picker source")
            return
        }
        XCTAssertEqual(model.statusText, "Pick a task or type a new ID — press Tab to browse")
        XCTAssertEqual(model.plainDraft, "@file:")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 6 --format json -- @file:"))
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 6 --format json -- @file:"))
    }

    func testTypedCaretAsWholeItemOpensActiveTaskPickerThroughKeyIntent() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.pickerVisible }

        XCTAssertEqual(model.statusText, "Pick an active task — press Tab to browse")
    }

    func testCompletionWaitsForRewriteThenOpensPicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.3"]
        )
        let textView = makeTextView("@file")
        wireNativeApply(model, textView: textView)

        typeSeparator(":", into: textView, model: model)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.pickerVisible)
        let early = (try? String(contentsOf: recordURL)) ?? ""
        XCTAssertFalse(early.contains("argv=capture-complete"))

        await waitUntil { model.pickerVisible }
        XCTAssertEqual(model.plainDraft, "@file:")
    }

    func testDelayedAcceptedToggleSupersedesGatedCompletion() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"]
        )
        let textView = makeTextView("Do work @file:id")
        wireNativeApply(model, textView: textView)

        typeSeparator("^", into: textView, model: model)
        await waitUntil { model.plainDraft == "Do work @file^id" }
        try await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(model.plainDraft, "Do work @file^id")
        XCTAssertNil(model.picker)
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("capture-complete --all-tasks --cursor 17"))
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

    func testAcceptedRelationAndTypedPipeGluesAndOpensLabelCard() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        installRelationPicker(on: model)
        model.acceptPickerRow(id: "tasks.md|1:aaaa1111", submitAfterInsert: false)

        let textView = makeTextView(model.plainDraft)
        wireNativeApply(model, textView: textView)
        typeSeparator("|", into: textView, model: model)

        await waitUntil {
            model.relationLabelPromptVisible
                && model.plainDraft == "New task ~tasks:target|"
        }
        XCTAssertEqual(textView.string, "New task ~tasks:target|")
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linksTo)
        XCTAssertEqual(model.relationLabelPrompt?.targetText, "Target")
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 22, end: 23))
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 24 --format json -- New task ~tasks:target |"))
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 23 --format json -- New task ~tasks:target|"))
    }

    func testAcceptedLinkedFromAndTypedPipeOpensCardWithCorrectDirection() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        installRelationPicker(on: model, from: true)
        model.acceptPickerRow(id: "tasks.md|2:bbbb2222", submitAfterInsert: false)

        let textView = makeTextView(model.plainDraft)
        wireNativeApply(model, textView: textView)
        typeSeparator("|", into: textView, model: model)

        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.plainDraft, "New task ~~tasks:source|")
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linkedFrom)
        XCTAssertEqual(model.relationLabelSentence, "“Source” → “New task”")
    }

    func testPipeWithoutSpaceStillOpensCardAndRequestsCompletion() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("New task ~tasks:target")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|")
        XCTAssertEqual(textView.string, "New task ~tasks:target|")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 23 --format json -- New task ~tasks:target|"))
        XCTAssertTrue(record.contains("capture-complete --all-tasks --cursor 23"))
    }

    func testNativeUndoRestoresTheLiteralSpaceBeforePipe() async throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }

        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        installRelationPicker(on: model)
        model.acceptPickerRow(id: "tasks.md|1:aaaa1111", submitAfterInsert: false)
        let textView = makeTextView(model.plainDraft)
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { textView.string == "New task ~tasks:target|" }
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "New task ~tasks:target |")

        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertEqual(textView.string, "New task ~tasks:target |")
    }

    func testRelationLabelCommitPreservesFollowingRouteText() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("New task ~tasks:target @work")
        textView.setSelectedRange(NSRange(location: 22, length: 0))
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 22, end: 23))
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 9, end: 22))
        // Mid-draft caret must request completion at the pipe (23), not end of draft (29).
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains(
                "argv=capture-complete --all-tasks --cursor 23 --format json -- New task ~tasks:target| @work"
            ) == true
        }
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("capture-complete --all-tasks --cursor 29"))
        model.updateRelationLabelPromptLabel("follow")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "follow" }) == true
        }
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|follow @work")
    }

    func testShiftReturnLabelCommitPreservesFollowingTextMidDraft() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        installRelationPicker(on: model, draft: "New task ~ @work")
        model.openRelationLabelPromptFromPickerRow(id: "tasks.md|1:aaaa1111")

        XCTAssertTrue(model.relationLabelPromptVisible)
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 22, end: 22))
        await waitUntil { model.relationLabelPrompt?.suggestions.isEmpty == false }
        model.updateRelationLabelPromptLabel("follow")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "follow" }) == true
        }
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|follow @work")
    }

    func testLeadingRelationPipeOpensWithNarrowRangeAndCommitsSee() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("~tasks:target Fix it")
        textView.setSelectedRange(NSRange(location: 13, length: 0))
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 0, end: 13))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 13, end: 14))
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linksTo)
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Fix it")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 14 --format json -- ~tasks:target| Fix it"))
        model.updateRelationLabelPromptLabel("see")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "see" }) == true
        }
        // The synthetic probe uses a larger replacement (13..25); the card must keep the narrow original.
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 13, end: 14))
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "~tasks:target|see Fix it")
    }

    func testDependencyTailCommitPreservesSuffixByteForByte() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Fix it ~tasks:target &tasks:source")
        textView.setSelectedRange(NSRange(location: 20, length: 0))
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 7, end: 20))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 20, end: 21))
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Fix it")
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains(
                "argv=capture-complete --all-tasks --cursor 21 --format json -- Fix it ~tasks:target| &tasks:source"
            ) == true
        }
        model.updateRelationLabelPromptLabel("see")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "see" }) == true
        }
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 20, end: 21))
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "Fix it ~tasks:target|see &tasks:source")
    }

    func testShiftReturnDependencyTailMidDraftPreservesSuffix() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        model.installRelationPickerForPreviews(
            candidates: [relationCandidate()],
            draft: "Fix it ~ &tasks:source",
            replacement: CaptureRange(start: 7, end: 8),
            owner: DependencyOwner(kind: "new_task", text: "Fix it"),
            direction: .linksTo
        )
        model.openRelationLabelPromptFromPickerRow(id: "tasks.md|1:aaaa1111")

        XCTAssertTrue(model.relationLabelPromptVisible)
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 7, end: 20))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 20, end: 20))
        await waitUntil { model.relationLabelPrompt?.suggestions.isEmpty == false }
        model.updateRelationLabelPromptLabel("see")
        await waitUntil {
            model.relationLabelPrompt?.suggestions.contains(where: { $0.typed && $0.label == "see" }) == true
        }
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "Fix it ~tasks:target|see &tasks:source")
    }

    func testQuotedNotePipeOpensWithEntireTokenRange() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("Fix ~\"My Note\":target")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 4, end: 21))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 21, end: 22))
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linksTo)
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Fix")
    }

    func testNonAsciiDraftPipeOpensAndConvertsCaret() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let textView = makeTextView("Hi 🧪 ~tasks:target")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 8, end: 21))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 21, end: 22))
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Hi 🧪")
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains(
                "argv=capture-complete --all-tasks --cursor 22 --format json -- Hi 🧪 ~tasks:target|"
            ) == true
        }
    }

    func testIncomingFromPipeOpensWithCorrectDirection() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("Fix ~~tasks:source")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.tokenRange, CaptureRange(start: 4, end: 18))
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 18, end: 19))
        XCTAssertEqual(model.relationLabelPrompt?.direction, .linkedFrom)
        XCTAssertEqual(model.relationLabelPrompt?.ownerText, "Fix")
    }

    func testEmptyLabelReturnWithFollowingTailDropsOnlyPipeSuffix() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("New task ~tasks:target @work")
        textView.setSelectedRange(NSRange(location: 22, length: 0))
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        XCTAssertEqual(model.relationLabelPrompt?.labelRange, CaptureRange(start: 22, end: 23))
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target @work")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 22)
        XCTAssertEqual(model.statusText, "Inserted relation without a label")
    }

    func testEmptyLabelReturnDropsPipeAndLeavesBareRelation() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("New task ~tasks:target")
        wireNativeApply(model, textView: textView)

        typeSeparator("|", into: textView, model: model)
        await waitUntil { model.relationLabelPromptVisible }
        model.submitRelationLabelPrompt()

        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 22)
        XCTAssertEqual(model.statusText, "Inserted relation without a label")
    }

    func testOlderBobRelationLabelResponseUsesLegacyFallback() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(extra: ["FAKE_BOB_RELATION_OLD": "1"])
        let textView = makeTextView("New task ~tasks:target|")
        wireNativeApply(model, textView: textView)

        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        await waitUntil { model.relationLabelPromptVisible }

        XCTAssertEqual(model.relationLabelPrompt?.direction, .linksTo)
        XCTAssertNil(model.completionResponse)
    }
}
