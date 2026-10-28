import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Live-panel regression coverage for editor wrapping. The hidden SwiftUI sizer
/// and the backing NSTextView must agree about how many visual lines fit.
@MainActor
final class CaptureEditorWrapHeightTests: XCTestCase {
    private var controller: CapturePanelController?

    private func visibleFrame(for panel: NSPanel) -> NSRect? {
        panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame
    }

    /// Bounded settle: SwiftUI can need more than one layout pass to publish
    /// measured editor height and update the hosted NSTextView.
    private func settlePanel(_ panel: NSPanel, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        var last: CGFloat = -1_000_000
        while Date() < deadline {
            panel.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
            panel.contentView?.layoutSubtreeIfNeeded()
            let height = panel.frame.height
            if abs(height - last) < 0.5 {
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
                panel.contentView?.layoutSubtreeIfNeeded()
                return
            }
            last = height
        }
    }

    private func editableTextViews(in view: NSView?) -> [NSTextView] {
        guard let view else {
            return []
        }
        var out: [NSTextView] = []
        if let textView = view as? NSTextView, textView.isEditable {
            out.append(textView)
        }
        for subview in view.subviews {
            out.append(contentsOf: editableTextViews(in: subview))
        }
        return out
    }

    private func makePanel() throws -> (CapturePanelModel, NSPanel) {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        let controller = CapturePanelController(model: model)
        self.controller = controller
        let panel = controller.makePanelIfNeeded()
        guard visibleFrame(for: panel) != nil else {
            throw XCTSkip("no visible frame on this host")
        }
        panel.orderFrontRegardless()
        settlePanel(panel)
        return (model, panel)
    }

    private func assertEditorShowsWholeDraft(
        panel: NSPanel,
        label: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let editors = editableTextViews(in: panel.contentView)
        guard editors.count == 1, let textView = editors.first else {
            XCTFail(
                "Expected one editable NSTextView, found \(editors.count) (\(label))", file: file,
                line: line)
            return
        }
        guard
            let textLayoutManager = textView.textLayoutManager,
            let documentRange = textLayoutManager.textContentManager?.documentRange,
            let scrollView = textView.enclosingScrollView
        else {
            XCTFail(
                "Editor is missing TextKit layout or enclosing scroll view (\(label))", file: file,
                line: line)
            return
        }
        textLayoutManager.ensureLayout(for: documentRange)
        let contentHeight = textLayoutManager.usageBoundsForTextContainer.height
        let visibleHeight = scrollView.contentView.bounds.height
        let clipOrigin = scrollView.contentView.bounds.origin.y
        let info =
            "\(label): panelContentWidth=\(panel.contentLayoutRect.width) "
            + "textViewFrame=\(textView.frame) contentHeight=\(contentHeight) "
            + "visibleHeight=\(visibleHeight) clipOrigin=\(clipOrigin)"
        XCTAssertLessThanOrEqual(contentHeight, visibleHeight + 0.5, info, file: file, line: line)
        XCTAssertEqual(clipOrigin, 0, accuracy: 0.5, info, file: file, line: line)
    }

    func testScreenshotDraftShowsBothWrappedLines() throws {
        let (model, panel) = try makePanel()
        model.plainDraft =
            "Make it so all themes need to be configured (or a warning shows)! @bob:configure-themes"
        settlePanel(panel)

        assertEditorShowsWholeDraft(panel: panel, label: "screenshot draft")
    }

    func testLineLengthsAroundWrapBoundaryNeverClip() throws {
        let (model, panel) = try makePanel()
        let widths = [
            CapturePanelLayout.panelInitialContentWidth,
            CapturePanelLayout.panelMinimumContentWidth,
        ]
        let advance = ("x" as NSString).size(
            withAttributes: [
                .font: NSFont.monospacedSystemFont(
                    ofSize: NSFont.systemFontSize,
                    weight: .regular
                )
            ]
        ).width

        for width in widths {
            panel.setContentSize(
                NSSize(width: width, height: panel.contentLayoutRect.height)
            )
            settlePanel(panel)
            let editorWidth = width - 2 * CapturePanelLayout.rootPadding
            let wrap = CapturePanelLayout.editorTextWrapWidth(editorWidth: editorWidth)
            let boundary = Int(wrap / advance)
            for count in (boundary - 1)...(boundary + 2) {
                model.plainDraft = String(repeating: "x", count: count)
                settlePanel(panel)
                assertEditorShowsWholeDraft(
                    panel: panel,
                    label: "character width \(width), count \(count)"
                )
            }

            for count in (boundary - 1)...(boundary + 2) {
                let words = String(repeating: "word ", count: (count + 4) / 5)
                model.plainDraft = String(words.prefix(count))
                settlePanel(panel)
                assertEditorShowsWholeDraft(
                    panel: panel,
                    label: "word width \(width), count \(count)"
                )
            }
        }
    }
}
