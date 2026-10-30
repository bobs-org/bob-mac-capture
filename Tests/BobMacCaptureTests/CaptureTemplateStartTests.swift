import AppKit
import CaptureCore
import Combine
import Foundation
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureTemplateStartTests: XCTestCase {
    private func keyEvent(
        characters: String,
        modifiers: NSEvent.ModifierFlags = []
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
            keyCode: 0
        )!
    }

    private func makeTextView(_ text: String, cursor: Int = 2) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: cursor, length: 0))
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

    private func typeAt(
        _ modifiers: NSEvent.ModifierFlags = [],
        into textView: NSTextView,
        model: CapturePanelModel
    ) {
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "@", modifiers: modifiers),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        textView.insertText("@", replacementRange: textView.selectedRange())
        let selection = textView.selectedRange()
        let draft = textView.string
        let prefix = (draft as NSString).substring(to: selection.location)
        model.plainDraft = draft
        let insertion = model.attributedDraft.index(
            model.attributedDraft.startIndex,
            offsetByCharacters: prefix.count
        )
        let editorSelection = AttributedTextSelection(insertionPoint: insertion)
        model.editorSelectionDidChange(to: editorSelection)
        model.editorSelection = editorSelection
        model.editorTextDidChange(cursorUTF8Offset: prefix.utf8.count)
    }

    private func processClient(
        recordURL: URL? = nil,
        extra: [String: String] = [:]
    ) throws -> BobProcessClient {
        var environment = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
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
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot.appendingPathComponent("Tests/Fixtures/fake-bob").path
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

    func testTypingThirdAtStartsTemplateAndClosesBareAtAtCompletion() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        model.plainDraft = "@@"
        let textView = makeTextView("@@")
        wireNativeApply(model, textView: textView)

        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.completionVisible }
        XCTAssertTrue(model.templateStartHintVisible)

        typeAt(into: textView, model: model)
        await waitUntil {
            model.plainDraft == "@@template:\n"
                && model.statusText == "Started a @@template: draft"
        }

        XCTAssertEqual(textView.string, "@@template:\n")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 12, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 12)
        XCTAssertNil(model.completionResponse)
        XCTAssertFalse(model.completionVisible)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 3 --format json -- @@@"))
        XCTAssertEqual(record.components(separatedBy: "argv=capture-rewrite").count - 1, 1)
    }

    func testTypingThirdAtKeepsFollowingRowsBelowFreshTemplateLine() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        let textView = makeTextView("@@\nApply {0}")
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        await waitUntil { model.plainDraft == "@@template:\n\nApply {0}" }

        XCTAssertEqual(textView.string, "@@template:\n\nApply {0}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 12, length: 0))
        XCTAssertEqual(model.statusText, "Started a @@template: draft")
    }

    func testTypingThirdAtAtEndOfLineStartsTemplate() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        model.plainDraft = "Read {0} @@"
        let textView = makeTextView("Read {0} @@", cursor: 11)
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        await waitUntil { model.plainDraft == "@@template:\nRead {0}" }

        XCTAssertEqual(textView.string, "@@template:\nRead {0}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 20, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 20)
        XCTAssertEqual(model.statusText, "Started a @@template: draft")
        XCTAssertNil(model.completionResponse)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 12 --format json -- Read {0} @@@")
        )
    }

    func testTypingAllThreeAtSignsAtEndOfLineStartsTemplate() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        model.plainDraft = "Read {0} "
        let textView = makeTextView("Read {0} ", cursor: 9)
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        typeAt(into: textView, model: model)
        await waitUntil {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return record.contains(
                "argv=capture-rewrite --cursor 11 --format json -- Read {0} @@")
        }

        typeAt(into: textView, model: model)
        await waitUntil {
            model.plainDraft == "@@template:\nRead {0}"
                && model.statusText == "Started a @@template: draft"
        }

        XCTAssertEqual(textView.string, "@@template:\nRead {0}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 20, length: 0))
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 12 --format json -- Read {0} @@@")
        )
    }

    func testTypingThirdAtWhileSecondAtRewriteIsInFlightStartsTemplate() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"]
        )
        model.plainDraft = "Read {0} "
        let textView = makeTextView("Read {0} ", cursor: 9)
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        typeAt(into: textView, model: model)
        await waitUntil {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return record.contains(
                "argv=capture-rewrite --cursor 11 --format json -- Read {0} @@")
        }

        typeAt(into: textView, model: model)
        await waitUntil {
            model.plainDraft == "@@template:\nRead {0}"
                && model.statusText == "Started a @@template: draft"
        }

        XCTAssertEqual(textView.string, "@@template:\nRead {0}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 20, length: 0))
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 12 --format json -- Read {0} @@@")
        )
    }

    func testCaretMoveAwayClearsThirdAtIntent() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.2"]
        )
        model.plainDraft = "Read {0} "
        let textView = makeTextView("Read {0} ", cursor: 9)
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        typeAt(into: textView, model: model)
        await waitUntil {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return record.contains(
                "argv=capture-rewrite --cursor 11 --format json -- Read {0} @@")
        }
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "@"),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        model.editorSelectionDidChange(cursorUTF8Offset: 0)
        textView.insertText("@", replacementRange: textView.selectedRange())
        let cursor = textView.selectedRange().location
        model.plainDraft = textView.string
        let prefix = (textView.string as NSString).substring(to: cursor)
        let insertion = model.attributedDraft.index(
            model.attributedDraft.startIndex,
            offsetByCharacters: prefix.count
        )
        let editorSelection = AttributedTextSelection(insertionPoint: insertion)
        model.editorSelectionDidChange(to: editorSelection)
        model.editorSelection = editorSelection
        model.editorTextDidChange(cursorUTF8Offset: prefix.utf8.count)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(model.plainDraft, "Read {0} @@@")
        XCTAssertNotEqual(model.statusText, "Started a @@template: draft")
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("--cursor 12 --format json -- Read {0} @@@"))
    }

    func testTypingThirdAtAtEndOfLastLineStartsTemplate() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        model.plainDraft = "Buy milk\nRead {0} @@"
        let textView = makeTextView("Buy milk\nRead {0} @@", cursor: 20)
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        await waitUntil { model.plainDraft == "@@template:\nBuy milk\nRead {0}" }

        XCTAssertEqual(textView.string, "@@template:\nBuy milk\nRead {0}")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 29, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 29)
        XCTAssertEqual(model.statusText, "Started a @@template: draft")
    }

    func testEndOfLineTemplateStartUsesOneUndoStep() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient()
        model.plainDraft = "Read {0} @@"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = makeTextView("Read {0} @@", cursor: 11)
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        await waitUntil { textView.string == "@@template:\nRead {0}" }

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Read {0} @@@")
        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "@@template:\nRead {0}")
    }

    func testTemplateStartRecoversWhenAbsorptionFinishesFirst() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        model.plainDraft = "Buy milk @dev @"
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = makeTextView("Buy milk @dev @", cursor: 15)
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        await waitUntil { model.plainDraft == "Buy milk @@dev" }
        textView.string = model.plainDraft
        textView.setSelectedRange(
            NSRange(location: (model.plainDraft as NSString).length, length: 0)
        )

        typeAt(into: textView, model: model)
        await waitUntil { model.plainDraft == "@@template:\nBuy milk @dev" }

        XCTAssertEqual(textView.string, "@@template:\nBuy milk @dev")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 25, length: 0))
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 25)
        XCTAssertEqual(model.statusText, "Started a @@template: draft")
        XCTAssertFalse(model.completionVisible)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-rewrite --cursor 17 --format json -- Buy milk @dev @@@")
        )

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Buy milk @@dev@")
    }

    func testTemplateStartRecoveryRequiresTheAbsorbedOutputCaret() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        model.plainDraft = "Buy milk @dev @"
        let textView = makeTextView("Buy milk @dev @", cursor: 15)
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        await waitUntil { model.plainDraft == "Buy milk @@dev" }
        textView.string = model.plainDraft
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        typeAt(into: textView, model: model)
        try await Task.sleep(nanoseconds: 100_000_000)

        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-rewrite").count - 1, 1)
        XCTAssertFalse(record.contains("Buy milk @dev @@@"))
    }

    func testNativeUndoRedoPreservesTheTypedAtAndNeverCallsRewriteAgain() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(recordURL: recordURL)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let textView = makeTextView("@@")
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        await waitUntil { textView.string == "@@template:\n" }
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "@@@")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: 3)
        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(textView.string, "@@@")

        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "@@template:\n")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: 12)
        try await Task.sleep(nanoseconds: 80_000_000)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "@@@")
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "@@")
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: 2)
        try await Task.sleep(nanoseconds: 100_000_000)

        XCTAssertEqual(textView.string, "@@")
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-rewrite").count - 1, 1)
    }

    func testIntentAcceptsOptionAtAndDeclinesOtherGestures() {
        let model = CapturePanelModel()
        let textView = makeTextView("@@")
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "@", modifiers: .option),
            firstResponder: textView,
            model: model,
            modalFieldActive: false
        )
        textView.insertText("@", replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: 3)
        XCTAssertEqual(model.plainDraft, "@@@")

        for modifiers: NSEvent.ModifierFlags in [.command, .control] {
            let declinedModel = CapturePanelModel()
            let declinedView = makeTextView("@@")
            CapturePanelController.noteSeparatorToggleIntentIfEligible(
                event: keyEvent(characters: "@", modifiers: modifiers),
                firstResponder: declinedView,
                model: declinedModel,
                modalFieldActive: false
            )
            declinedView.insertText("@", replacementRange: declinedView.selectedRange())
            declinedModel.plainDraft = declinedView.string
            declinedModel.editorTextDidChange(cursorUTF8Offset: 3)
            XCTAssertEqual(declinedModel.plainDraft, "@@@")
            XCTAssertNotEqual(declinedModel.statusText, "Started a @@template: draft")
        }

        let modalModel = CapturePanelModel()
        let modalView = makeTextView("@@")
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "@"),
            firstResponder: modalView,
            model: modalModel,
            modalFieldActive: true
        )
        XCTAssertEqual(modalModel.plainDraft, "")

        let elsewhere = makeTextView("@@x", cursor: 2)
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "@"),
            firstResponder: elsewhere,
            model: modalModel,
            modalFieldActive: false
        )
        let selected = makeTextView("@@", cursor: 1)
        selected.setSelectedRange(NSRange(location: 1, length: 1))
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "@"),
            firstResponder: selected,
            model: modalModel,
            modalFieldActive: false
        )
        let composing = makeTextView("@@")
        composing.setMarkedText(
            "@",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: 2, length: 0)
        )
        CapturePanelController.noteSeparatorToggleIntentIfEligible(
            event: keyEvent(characters: "@"),
            firstResponder: composing,
            model: modalModel,
            modalFieldActive: false
        )
        composing.unmarkText()
    }

    func testBobNoOpLeavesLiteralThirdAt() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_NO_CHANGE": "1"]
        )
        let textView = makeTextView("@@")
        wireNativeApply(model, textView: textView)

        typeAt(into: textView, model: model)
        await waitUntil {
            (try? String(contentsOf: recordURL))?.contains("argv=capture-rewrite") == true
        }
        XCTAssertEqual(model.plainDraft, "@@@")
        XCTAssertEqual(textView.string, "@@@")
        XCTAssertNotEqual(model.statusText, "Started a @@template: draft")
    }

    func testTemplateStartHintRequiresBareAtAtRouteCompletionWithTemplateCandidate() {
        let model = CapturePanelModel()
        model.plainDraft = "@@"
        model.completionResponse = completion(candidates: [templateCandidate])
        XCTAssertTrue(model.templateStartHintVisible)

        model.plainDraft = "@@t"
        model.editorSelection = AttributedTextSelection(
            insertionPoint: model.attributedDraft.index(model.attributedDraft.startIndex, offsetByCharacters: 3)
        )
        XCTAssertFalse(model.templateStartHintVisible)

        model.plainDraft = "@@"
        model.editorSelection = AttributedTextSelection(
            insertionPoint: model.attributedDraft.index(model.attributedDraft.startIndex, offsetByCharacters: 1)
        )
        XCTAssertFalse(model.templateStartHintVisible)

        model.editorSelection = AttributedTextSelection(
            insertionPoint: model.attributedDraft.endIndex
        )
        model.completionResponse = completion(candidates: [
            CaptureCompletionCandidate(replacement: "mac_inbox", route: "mac_inbox", kind: "inbox")
        ])
        XCTAssertFalse(model.templateStartHintVisible)
    }

    private var templateCandidate: CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "template:",
            route: "template:",
            label: "Bulk template: one capture per row below",
            kind: "template"
        )
    }

    private func completion(candidates: [CaptureCompletionCandidate]) -> CaptureCompletionResponse {
        CaptureCompletionResponse(
            ok: true,
            cursor: 2,
            replacement: CaptureRange(start: 2, end: 2),
            context: "route",
            candidates: candidates
        )
    }
}
