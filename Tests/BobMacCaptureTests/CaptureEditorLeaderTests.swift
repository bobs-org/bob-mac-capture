import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureEditorLeaderTests: XCTestCase {
    func testHintStringMatchesKeyboardDocs() {
        XCTAssertEqual(
            CapturePanelModel.editorLeaderStatusHint,
            "⌃G · U toggle line case · esc cancel"
        )
    }

    func testPrepareForDismissalClearsEditorLeader() {
        let model = CapturePanelModel()
        model.armEditorLeader()
        XCTAssertTrue(model.editorLeaderPending)
        model.prepareForDismissal()
        XCTAssertFalse(model.editorLeaderPending)
    }

    func testControlGUTogglesLinePreservesSelectionAndClearsLeader() {
        let (model, controller, textView, panel) = makeHostedEditor(text: "Hello")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 1, length: 3))

        XCTAssertNil(controller.routeKeyDown(controlG()))
        XCTAssertTrue(model.editorLeaderPending)
        XCTAssertNil(controller.routeKeyDown(keyEvent(keyCode: 32, characters: "u")))
        XCTAssertFalse(model.editorLeaderPending)
        XCTAssertEqual(textView.string, "HELLO")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 1, length: 3))
    }

    func testToggleLineCaseUndoRestoresOriginalLine() {
        let (model, controller, textView, panel) = makeHostedEditor(text: "Hello")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        XCTAssertNotNil(textView.undoManager)

        XCTAssertNil(controller.routeKeyDown(controlG()))
        XCTAssertNil(controller.routeKeyDown(keyEvent(keyCode: 32, characters: "u")))
        XCTAssertEqual(textView.string, "HELLO")
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Hello")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 2, length: 0))
        XCTAssertFalse(model.editorLeaderPending)
    }

    func testStaleLeaderAfterSelectionChangeDoesNotConsumeU() {
        let (model, controller, textView, panel) = makeHostedEditor(text: "Hello")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertNil(controller.routeKeyDown(controlG()))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        let passed = controller.routeKeyDown(keyEvent(keyCode: 32, characters: "u"))
        XCTAssertNotNil(passed)
        XCTAssertEqual(textView.string, "Hello")
        XCTAssertFalse(model.editorLeaderPending)
    }

    func testPrepareForDismissalDropsArmedLeader() {
        let (model, controller, textView, panel) = makeHostedEditor(text: "Hello")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertNil(controller.routeKeyDown(controlG()))
        XCTAssertTrue(model.editorLeaderPending)
        model.prepareForDismissal()
        XCTAssertFalse(model.editorLeaderPending)
        let passed = controller.routeKeyDown(keyEvent(keyCode: 32, characters: "u"))
        XCTAssertNotNil(passed)
        XCTAssertEqual(textView.string, "Hello")
    }

    func testWindowDidResignKeyDropsArmedLeader() {
        let (model, controller, textView, panel) = makeHostedEditor(text: "Hello")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertNil(controller.routeKeyDown(controlG()))
        XCTAssertTrue(model.editorLeaderPending)
        controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification))
        XCTAssertFalse(model.editorLeaderPending)
        let passed = controller.routeKeyDown(keyEvent(keyCode: 32, characters: "u"))
        XCTAssertNotNil(passed)
        XCTAssertEqual(textView.string, "Hello")
    }

    func testStrayKeyBeepsAndLeavesTextUnchanged() {
        let (model, controller, textView, panel) = makeHostedEditor(text: "Hello")
        defer { panel.orderOut(nil) }
        var beepCount = 0
        controller.beep = { beepCount += 1 }
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertNil(controller.routeKeyDown(controlG()))
        XCTAssertNil(controller.routeKeyDown(keyEvent(keyCode: 7, characters: "x")))
        XCTAssertEqual(beepCount, 1)
        XCTAssertEqual(textView.string, "Hello")
        XCTAssertFalse(model.editorLeaderPending)
    }

    func testSubmittingAndLockedEditorPreventArming() {
        let (model, controller, textView, panel) = makeHostedEditor(text: "Hello")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        model.isSubmitting = true
        XCTAssertNotNil(controller.routeKeyDown(controlG()))
        XCTAssertFalse(model.editorLeaderPending)
        XCTAssertFalse(controller.perform(.armEditorLeader))
        model.isSubmitting = false

        model.setEditorInputLockedForTests(true)
        XCTAssertNotNil(controller.routeKeyDown(controlG()))
        XCTAssertFalse(model.editorLeaderPending)
        XCTAssertFalse(controller.perform(.armEditorLeader))
        model.setEditorInputLockedForTests(false)

        XCTAssertTrue(controller.perform(.armEditorLeader))
        XCTAssertTrue(model.editorLeaderPending)
    }

    func testToggleLineCaseConsumesNoOpWithoutEditing() {
        let model = CapturePanelModel()
        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "- 123"
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        XCTAssertTrue(
            CapturePanelController.toggleLineCaseInEditableTextView(
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "- 123")
    }

    private func makeHostedEditor(
        text: String
    ) -> (CapturePanelModel, CapturePanelController, NSTextView, NSPanel) {
        let model = CapturePanelModel()
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.string = text
        panel.contentView = textView
        XCTAssertTrue(panel.makeFirstResponder(textView))
        return (model, controller, textView, panel)
    }

    private func controlG() -> NSEvent {
        keyEvent(keyCode: 5, modifiers: .control, characters: "\u{7}")
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = ""
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
}
