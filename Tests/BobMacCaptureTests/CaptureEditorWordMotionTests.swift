import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureEditorWordMotionTests: XCTestCase {
    func testControlLMovesToNextBigWord() {
        let (_, controller, textView, panel) = makeHostedEditor(text: "foo bar")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertNil(controller.routeKeyDown(controlL()))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(textView.string, "foo bar")
    }

    func testControlShiftHMovesToPreviousWord() {
        let (_, controller, textView, panel) = makeHostedEditor(text: "foo-bar")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 7, length: 0))

        XCTAssertNil(controller.routeKeyDown(controlShiftH()))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 4, length: 0))
        XCTAssertEqual(textView.string, "foo-bar")
    }

    func testControlHAtStartConsumesWithoutDeleting() {
        let (_, controller, textView, panel) = makeHostedEditor(text: "foo")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertNil(controller.routeKeyDown(controlH()))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
        XCTAssertEqual(textView.string, "foo")
    }

    func testControlLAtEndConsumesWithoutMoving() {
        let (_, controller, textView, panel) = makeHostedEditor(text: "foo")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertNil(controller.routeKeyDown(controlL()))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertEqual(textView.string, "foo")
    }

    func testNonCollapsedSelectionCollapses() {
        let (_, controller, textView, panel) = makeHostedEditor(text: "foo bar baz")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 1, length: 5))

        XCTAssertNil(controller.routeKeyDown(controlL()))
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 8, length: 0))
        XCTAssertEqual(textView.string, "foo bar baz")
    }

    func testMotionsLeaveTextAndUndoUntouched() {
        let (_, controller, textView, panel) = makeHostedEditor(text: "foo bar")
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        XCTAssertNil(controller.routeKeyDown(controlL()))
        XCTAssertNil(controller.routeKeyDown(controlH()))
        XCTAssertEqual(textView.string, "foo bar")
        XCTAssertFalse(textView.undoManager?.canUndo ?? false)
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

    private func controlL() -> NSEvent {
        keyEvent(keyCode: 37, modifiers: .control, characters: "\u{c}")
    }

    private func controlH() -> NSEvent {
        keyEvent(keyCode: 4, modifiers: .control, characters: "\u{8}")
    }

    private func controlShiftH() -> NSEvent {
        keyEvent(keyCode: 4, modifiers: [.control, .shift], characters: "\u{8}")
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
