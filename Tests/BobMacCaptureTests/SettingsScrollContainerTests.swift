import AppKit
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Hosted tests for the Settings scroll container: a tall synthetic
/// columns form in a fixed-height window, driven through the anchor's
/// ungated path with instant motion.
@available(macOS 26.0, *)
@MainActor
final class SettingsScrollContainerTests: XCTestCase {
    private enum KeyCode {
        static let d: UInt16 = 2
        static let u: UInt16 = 32
    }

    func testControlDMovesByHalfTheViewportAndBack() {
        let harness = makeHarness()
        defer { harness.window.close() }
        settle(harness.window)
        let anchor = tryUnwrapAnchor(harness.window)
        let start = settingsOffset(in: harness.window)
        let viewport = settingsViewportHeight(in: harness.window)
        XCTAssertGreaterThan(viewport, 0)

        XCTAssertNil(
            anchor.processKeyEvent(
                keyEvent(keyCode: KeyCode.d, modifiers: .control)
            )
        )
        let half = start + viewport / 2
        XCTAssertEqual(
            settingsOffset(in: harness.window), half, accuracy: 2,
            settingsDiagnostics(in: harness.window)
        )

        XCTAssertNil(
            anchor.processKeyEvent(
                keyEvent(keyCode: KeyCode.d, modifiers: .control)
            )
        )
        XCTAssertEqual(
            settingsOffset(in: harness.window), start + viewport, accuracy: 2,
            settingsDiagnostics(in: harness.window)
        )

        XCTAssertNil(
            anchor.processKeyEvent(
                keyEvent(keyCode: KeyCode.u, modifiers: .control)
            )
        )
        XCTAssertEqual(
            settingsOffset(in: harness.window), half, accuracy: 2,
            settingsDiagnostics(in: harness.window)
        )
    }

    func testRepeatedControlDClampsAtTheBottomAndControlUAtTheTop() {
        let harness = makeHarness()
        defer { harness.window.close() }
        settle(harness.window)
        let anchor = tryUnwrapAnchor(harness.window)
        let maxOffset = settingsMaxOffset(in: harness.window)
        for _ in 0..<40 {
            XCTAssertNil(
                anchor.processKeyEvent(
                    keyEvent(keyCode: KeyCode.d, modifiers: .control)
                )
            )
        }
        XCTAssertEqual(
            settingsOffset(in: harness.window), maxOffset, accuracy: 2,
            settingsDiagnostics(in: harness.window)
        )
        XCTAssertNil(
            anchor.processKeyEvent(
                keyEvent(keyCode: KeyCode.d, modifiers: .control)
            )
        )
        XCTAssertEqual(
            settingsOffset(in: harness.window), maxOffset, accuracy: 2,
            settingsDiagnostics(in: harness.window)
        )

        for _ in 0..<40 {
            XCTAssertNil(
                anchor.processKeyEvent(
                    keyEvent(keyCode: KeyCode.u, modifiers: .control)
                )
            )
        }
        let minOffset = settingsMinOffset(in: harness.window)
        XCTAssertEqual(
            settingsOffset(in: harness.window), minOffset, accuracy: 2,
            settingsDiagnostics(in: harness.window)
        )
        XCTAssertNil(
            anchor.processKeyEvent(
                keyEvent(keyCode: KeyCode.u, modifiers: .control)
            )
        )
        XCTAssertEqual(
            settingsOffset(in: harness.window), minOffset, accuracy: 2,
            settingsDiagnostics(in: harness.window)
        )
    }

    func testPlainDReturnsTheEventUnchanged() {
        let harness = makeHarness()
        defer { harness.window.close() }
        settle(harness.window)
        let anchor = tryUnwrapAnchor(harness.window)
        let event = keyEvent(keyCode: KeyCode.d, modifiers: [])
        XCTAssertTrue(anchor.processKeyEvent(event) === event)
    }

    func testHandleKeyDownPassesThroughForAnotherWindow() {
        let harness = makeHarness()
        defer { harness.window.close() }
        settle(harness.window)
        let anchor = tryUnwrapAnchor(harness.window)
        let other = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 200),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        defer { other.close() }
        other.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let event = keyEvent(keyCode: KeyCode.d, modifiers: .control)
        XCTAssertTrue(anchor.handleKeyDown(event) === event)
    }

    func testHandleKeyDownPassesThroughWhileASheetIsAttached() {
        let harness = makeHarness()
        defer { harness.window.close() }
        settle(harness.window)
        harness.window.makeKeyAndOrderFront(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        harness.window.beginSheet(sheet)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        let anchor = tryUnwrapAnchor(harness.window)
        let event = keyEvent(keyCode: KeyCode.d, modifiers: .control)
        XCTAssertTrue(anchor.handleKeyDown(event) === event)
        harness.window.endSheet(sheet)
    }

    func testTwoPressesBeforeSettlingTargetTwoHalfViewports() {
        var recorded: [CGFloat] = []
        let harness = makeHarness(performer: { scrollView, target, _, completion in
            recorded.append(target)
            completion()
        })
        defer { harness.window.close() }
        settle(harness.window)
        let anchor = tryUnwrapAnchor(harness.window)
        let start = settingsOffset(in: harness.window)
        let viewport = settingsViewportHeight(in: harness.window)
        XCTAssertNil(
            anchor.processKeyEvent(
                keyEvent(keyCode: KeyCode.d, modifiers: .control)
            )
        )
        XCTAssertNil(
            anchor.processKeyEvent(
                keyEvent(keyCode: KeyCode.d, modifiers: .control)
            )
        )
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(recorded[0], start + viewport / 2, accuracy: 1)
        XCTAssertEqual(recorded[1], start + viewport, accuracy: 1)
    }

    func testLiveScrollTakesOverFromThePendingTarget() {
        var recorded: [CGFloat] = []
        let harness = makeHarness(performer: { scrollView, target, _, completion in
            recorded.append(target)
            completion()
        })
        defer { harness.window.close() }
        settle(harness.window)
        let anchor = tryUnwrapAnchor(harness.window)
        let otherStart = settingsOffset(in: harness.window)
        let viewport = settingsViewportHeight(in: harness.window)
        XCTAssertNil(
            anchor.processKeyEvent(
                keyEvent(keyCode: KeyCode.d, modifiers: .control)
            )
        )
        XCTAssertEqual(recorded.count, 1)
        guard let scrollView = anchor.enclosingScrollView else {
            XCTFail("settings scroll view missing")
            return
        }
        NotificationCenter.default.post(
            name: NSScrollView.willStartLiveScrollNotification,
            object: scrollView
        )
        XCTAssertNil(
            anchor.processKeyEvent(
                keyEvent(keyCode: KeyCode.d, modifiers: .control)
            )
        )
        XCTAssertEqual(recorded.count, 2)
        XCTAssertEqual(recorded[0], otherStart + viewport / 2, accuracy: 1)
        XCTAssertEqual(recorded[1], otherStart + viewport / 2, accuracy: 1)
    }

    // MARK: - Harness

    private struct Harness {
        let window: NSWindow
    }

    private func makeHarness(
        performer: SettingsScrollPerform? = nil
    ) -> Harness {
        let content = SettingsScrollContainer(
            scrollPerformer: performer ?? instantPerformer()
        ) {
            Form {
                ForEach(0..<60) { index in
                    Section("Section \(index)") {
                        Toggle(
                            "Row \(index) toggle with a long label",
                            isOn: .constant(true)
                        )
                        Text(
                            "Caption \(index) long enough to wrap fully."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.columns)
        }
        .frame(width: 620, height: 640)
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: 620, height: 640)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 620, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        return Harness(window: window)
    }

    private func instantPerformer() -> SettingsScrollPerform {
        { scrollView, target, flipped, completion in
            guard let documentView = scrollView.documentView else {
                completion()
                return
            }
            let clipView = scrollView.contentView
            let originY = RefsInspectorScrollGeometry.clipOriginY(
                forContentTopOffset: target,
                contentHeight: documentView.frame.height,
                viewportHeight: clipView.bounds.height,
                isFlipped: flipped
            )
            clipView.scroll(
                to: NSPoint(x: clipView.bounds.origin.x, y: originY)
            )
            scrollView.reflectScrolledClipView(clipView)
            completion()
        }
    }

    private func settle(_ window: NSWindow) {
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            window.contentView?.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.03))
            if settingsViewportHeight(in: window) > 0,
                settingsContentHeight(in: window)
                    > settingsViewportHeight(in: window) + 40
            {
                return
            }
        }
        XCTFail("settings container did not settle")
    }

    private func tryUnwrapAnchor(_ window: NSWindow) -> SettingsScrollKeyView {
        guard
            let anchor = SettingsScrollKeyView.findAnchor(
                in: window.contentView
            )
        else {
            XCTFail("settings scroll anchor missing")
            return SettingsScrollKeyView()
        }
        return anchor
    }

    private func settingsScrollView(in window: NSWindow) -> NSScrollView? {
        tryUnwrapAnchor(window).enclosingScrollView
    }

    private func settingsOffset(in window: NSWindow) -> CGFloat {
        guard
            let scrollView = settingsScrollView(in: window),
            let documentView = scrollView.documentView
        else {
            return 0
        }
        let clipView = scrollView.contentView
        return RefsInspectorScrollGeometry.offsetFromContentTop(
            contentHeight: documentView.frame.height,
            viewportHeight: clipView.bounds.height,
            clipOriginY: clipView.bounds.origin.y,
            isFlipped: documentView.isFlipped
        )
    }

    private func settingsViewportHeight(in window: NSWindow) -> CGFloat {
        settingsScrollView(in: window)?.contentView.bounds.height ?? 0
    }

    private func settingsContentHeight(in window: NSWindow) -> CGFloat {
        settingsScrollView(in: window)?.documentView?.frame.height ?? 0
    }

    private func settingsMaxOffset(in window: NSWindow) -> CGFloat {
        guard
            let scrollView = settingsScrollView(in: window),
            let documentView = scrollView.documentView
        else {
            return 0
        }
        let clipView = scrollView.contentView
        return RefsInspectorScrollGeometry(
            offsetY: 0,
            contentHeight: documentView.frame.height,
            viewportHeight: clipView.bounds.height,
            topInset: clipView.contentInsets.top,
            bottomInset: clipView.contentInsets.bottom
        ).maxOffset
    }

    private func settingsMinOffset(in window: NSWindow) -> CGFloat {
        guard
            let scrollView = settingsScrollView(in: window),
            let documentView = scrollView.documentView
        else {
            return 0
        }
        let clipView = scrollView.contentView
        return RefsInspectorScrollGeometry(
            offsetY: 0,
            contentHeight: documentView.frame.height,
            viewportHeight: clipView.bounds.height,
            topInset: clipView.contentInsets.top,
            bottomInset: clipView.contentInsets.bottom
        ).minOffset
    }

    private func settingsDiagnostics(in window: NSWindow) -> String {
        guard
            let scrollView = settingsScrollView(in: window),
            let documentView = scrollView.documentView
        else {
            return "lookup=nil"
        }
        let clipView = scrollView.contentView
        return "clip=\(clipView.bounds) docHeight=\(documentView.frame.height)"
            + " flipped=\(documentView.isFlipped)"
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: keyCode == KeyCode.d ? "d" : "u",
            charactersIgnoringModifiers: keyCode == KeyCode.d ? "d" : "u",
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
