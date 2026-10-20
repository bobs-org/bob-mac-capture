import AppKit
import SwiftUI
import XCTest

@testable import BobMacCapture
@testable import CaptureCore

/// Hosted Capture round trip through the real coordinator paths: a nonempty
/// draft with a non-end caret, a template origin, and an error survive a
/// Capture -> Refs -> Capture hop, and the backing NSTextView keeps the
/// original non-end caret after return.
@MainActor
final class CapturePanelSwitchHostedTests: XCTestCase {
    func testSwitchAwayAndBackPreservesDraftCaretTemplateAndError() async throws {
        let model = CapturePanelModel()
        model.plainDraft = "Call bank @Cash and @Home"
        let insertion = try XCTUnwrap(
            attributedStringIndex(in: model.attributedDraft, utf8Offset: 10)
        )
        let selection = AttributedTextSelection(insertionPoint: insertion)
        model.editorSelection = selection
        model.templateOrigin = "weekly-review"
        model.errorMessage = "Capture failed"

        let captureController = CapturePanelController(model: model)
        let capturePanel = captureController.makePanelIfNeeded()
        defer { capturePanel.orderOut(nil) }

        captureController.show()
        guard let editorBefore = waitForEditor(in: capturePanel) else {
            XCTFail("capture editor did not appear before timeout")
            return
        }
        // Drive the backing view to the model's non-end caret so the round
        // trip asserts the real AppKit selection, not just the model value.
        let expectedRange = NSRange(
            location: (editorBefore.string as NSString).length > 10 ? 10 : 0,
            length: 0
        )
        editorBefore.setSelectedRange(expectedRange)
        XCTAssertNotEqual(expectedRange.location, (editorBefore.string as NSString).length)

        var refsVisible = false
        let coordinator = BobPanelCoordinator(
            isCaptureVisible: { captureController.isVisible },
            isRefsVisible: { refsVisible },
            closeCaptureRetainingDraft: { model.closeRetainingDraft() },
            presentCapture: { captureController.show() },
            presentRefs: { refsVisible = true },
            hideRefs: { refsVisible = false }
        )

        // Capture -> Refs: only the destination is visible.
        XCTAssertEqual(coordinator.switchPanels(from: .capture), .refs)
        XCTAssertFalse(captureController.isVisible)
        XCTAssertTrue(refsVisible)

        // Refs -> Capture: only the destination is visible.
        XCTAssertEqual(coordinator.switchPanels(from: .refs), .capture)
        XCTAssertTrue(captureController.isVisible)
        XCTAssertFalse(refsVisible)

        guard let editorAfter = waitForEditor(in: capturePanel) else {
            XCTFail("capture editor did not reappear before timeout")
            return
        }

        XCTAssertEqual(model.plainDraft, "Call bank @Cash and @Home")
        XCTAssertEqual(model.editorSelection, selection)
        XCTAssertEqual(model.templateOrigin, "weekly-review")
        XCTAssertEqual(model.errorMessage, "Capture failed")
        XCTAssertEqual(editorAfter.selectedRange(), expectedRange)
    }

    private func waitForEditor(in panel: NSPanel, timeout: TimeInterval = 5) -> NSTextView? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            panel.contentView?.layoutSubtreeIfNeeded()
            if let editor = findEditor(in: panel.contentView) {
                return editor
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return findEditor(in: panel.contentView)
    }

    private func findEditor(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let textView = view as? NSTextView, textView.isEditable {
            return textView
        }
        for subview in view.subviews {
            if let found = findEditor(in: subview) {
                return found
            }
        }
        return nil
    }
}
