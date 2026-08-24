import AppKit
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class BlockIDFieldFocusTests: XCTestCase {
    func testClaimsImmediatelyWhenAlreadyInWindow() {
        let window = makeWindow()
        let field = makeBlockIDField()
        window.contentView?.addSubview(field)

        field.requestFirstResponder()

        XCTAssertTrue(field.holdsFirstResponder)
    }

    func testClaimsOnEntryWhenArmedBeforeWindow() {
        let window = makeWindow()
        let field = makeBlockIDField()

        field.requestFirstResponder()
        window.contentView?.addSubview(field)

        XCTAssertTrue(field.holdsFirstResponder)
    }

    func testTakesFocusAwayFromAnotherResponder() {
        let window = makeWindow()
        let other = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        let field = makeBlockIDField(frame: NSRect(x: 0, y: 32, width: 120, height: 24))
        window.contentView?.addSubview(other)
        window.contentView?.addSubview(field)

        XCTAssertTrue(window.makeFirstResponder(other))
        field.requestFirstResponder()

        XCTAssertTrue(field.holdsFirstResponder)
        let otherStillHoldsFocus = other.currentEditor().map { editor in
            guard let responder = window.firstResponder else {
                return false
            }
            return editor === responder
        } ?? false
        XCTAssertFalse(otherStillHoldsFocus)
    }

    func testReleasesOnTeardown() {
        let window = makeWindow()
        let field = makeBlockIDField()
        window.contentView?.addSubview(field)
        field.requestFirstResponder()
        XCTAssertTrue(field.holdsFirstResponder)

        field.removeFromSuperview()

        if let responder = window.firstResponder as? NSView {
            XCTAssertFalse(responder === field || responder.isDescendant(of: field))
        }
    }

    func testBlockIDFocusOrphanTruthTable() {
        let contentView = FocusableView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        let window = makeWindow(contentView: contentView)

        _ = window.makeFirstResponder(window)
        XCTAssertTrue(CapturePanelController.blockIDFocusIsOrphaned(in: window))

        XCTAssertTrue(window.makeFirstResponder(contentView))
        XCTAssertTrue(CapturePanelController.blockIDFocusIsOrphaned(in: window))

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 120, height: 24))
        contentView.addSubview(textField)
        XCTAssertTrue(window.makeFirstResponder(textField))
        XCTAssertFalse(CapturePanelController.blockIDFocusIsOrphaned(in: window))

        let button = FocusableButton(title: "Cancel", target: nil, action: nil)
        button.frame = NSRect(x: 0, y: 32, width: 80, height: 24)
        contentView.addSubview(button)
        XCTAssertTrue(window.makeFirstResponder(button))
        XCTAssertFalse(CapturePanelController.blockIDFocusIsOrphaned(in: window))
    }

    func testFindBlockIDField() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        let nested = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 60))
        let field = makeBlockIDField()
        root.addSubview(nested)
        nested.addSubview(field)

        XCTAssertTrue(CapturePanelController.findBlockIDField(in: root) === field)
        XCTAssertNil(CapturePanelController.findBlockIDField(in: NSView()))
        XCTAssertNil(CapturePanelController.findBlockIDField(in: nil))
    }

    func testHostedFieldIsReachableFromController() {
        let window = makeWindow()
        let hosted = NSHostingView(
            rootView: HostedBlockIDFieldHarness(
                focusRequest: CapturePanelFocusRequest(sequence: 1, target: .taskIDPromptBlockID)
            )
        )
        hosted.frame = window.contentView?.bounds ?? .zero
        window.contentView = hosted
        window.contentView?.layoutSubtreeIfNeeded()

        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        XCTAssertNotNil(CapturePanelController.findBlockIDField(in: window.contentView))
    }

    private func makeWindow(contentView: NSView? = nil) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 120),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView ?? NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 120))
        return window
    }

    private func makeBlockIDField(frame: NSRect = NSRect(x: 0, y: 0, width: 120, height: 24)) -> BlockIDNSTextField {
        let field = BlockIDNSTextField(frame: frame)
        field.isEditable = true
        field.isSelectable = true
        field.isEnabled = true
        field.usesSingleLineMode = true
        field.setAccessibilityIdentifier(blockIDFieldAccessibilityIdentifier)
        return field
    }
}

private struct HostedBlockIDFieldHarness: View {
    @State private var text = ""
    let focusRequest: CapturePanelFocusRequest

    var body: some View {
        BlockIDField(
            text: $text,
            isEnabled: true,
            focusRequest: focusRequest,
            focusDidChange: { _ in }
        )
        .frame(width: 160, height: 24)
    }
}

private final class FocusableView: NSView {
    override var acceptsFirstResponder: Bool {
        true
    }
}

private final class FocusableButton: NSButton {
    override var acceptsFirstResponder: Bool {
        true
    }
}
