import AppKit
import SwiftUI
import XCTest

@testable import BobMacCapture
@testable import CaptureCore

/// Typing an unconfigured Pomodoro theme must never wedge the panel.
/// Before the fix, every selection callback rewrote the editor while an
/// unconfigured theme was parsed, and the SwiftUI TextEditor echoed the
/// write back into another selection callback. On CI the unfixed test
/// hangs here and the watchdog samples the re-entrant stack.
@MainActor
final class CaptureUnconfiguredThemeHostedTests: XCTestCase {
    func testTypingUnconfiguredThemeThenMovingCaretUnderlinesWithoutFreezing() async throws {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_PARSE_FIXTURE": "capture-parse-unconfigured-theme-start.json",
            ]
        )
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        defer { panel.orderOut(nil) }

        controller.show()
        guard let editor = waitForEditor(in: panel) else {
            XCTFail("capture editor did not appear before timeout")
            return
        }

        editor.insertText("=#fo", replacementRange: NSRange(location: 0, length: 0))
        await waitUntil {
            model.plainDraft == "=#fo"
                && (model.latestParse?.spans.contains(where: { span in
                    span.kind == "pomodoro_name"
                        && span.themes.contains(where: { $0.configured == false })
                }) == true)
        }
        XCTAssertEqual(model.plainDraft, "=#fo")

        editor.setSelectedRange(NSRange(location: 0, length: 0))
        let dashed = NSUnderlineStyle([.single, .patternDash])
        await waitUntil {
            Self.underlinedStrings(in: model.attributedDraft, style: dashed) == ["fo"]
        }
        XCTAssertEqual(
            Self.underlinedStrings(in: model.attributedDraft, style: dashed),
            ["fo"]
        )

        editor.setSelectedRange(NSRange(location: 4, length: 0))
        await waitUntil {
            Self.underlinedStrings(in: model.attributedDraft, style: dashed).isEmpty
        }
        XCTAssertTrue(
            Self.underlinedStrings(in: model.attributedDraft, style: dashed).isEmpty
        )
        XCTAssertEqual(model.plainDraft, "=#fo")
    }

    private static func underlinedStrings(
        in text: AttributedString,
        style: NSUnderlineStyle
    ) -> [String] {
        text.runs.compactMap { run in
            guard run.attributes.underlineStyle == style else {
                return nil
            }
            return String(text[run.range].characters)
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 10,
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
