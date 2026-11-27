import AppKit
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Tests for the app-owned Settings panel: one reused
/// `.nonactivatingPanel` that orders in on every `show()`, titled from the
/// bundle name, closed by Command-W and nothing else. Key status itself is
/// never asserted here because CI runs headless.
@MainActor
final class SettingsWindowControllerTests: XCTestCase {
    private func makeController(
        bundleName: String = "Bob Mac Capture"
    ) -> SettingsWindowController<Text> {
        SettingsWindowController(bundleName: bundleName) {
            Text("Settings")
        }
    }

    func testShowCreatesOnePanelAndReusesIt() {
        let controller = makeController()
        let first = controller.show()
        defer { first.close() }
        let second = controller.show()
        XCTAssertTrue(first === second)
    }

    func testPanelConfigurationTakesFocusWithoutActivation() {
        let controller = makeController()
        let panel = controller.show()
        defer { panel.close() }
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertEqual(panel.level, .normal)
        XCTAssertFalse(panel.isFloatingPanel)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertFalse(panel.becomesKeyOnlyIfNeeded)
        XCTAssertTrue(panel.collectionBehavior.contains(.moveToActiveSpace))
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertEqual(panel.frameAutosaveName, "BobMacCaptureSettingsPanel")
        XCTAssertEqual(
            panel.contentMinSize.width, SettingsScrollMetrics.fixedWidth)
        XCTAssertEqual(
            panel.contentMaxSize.width, SettingsScrollMetrics.fixedWidth)
        XCTAssertEqual(
            panel.contentMinSize.height, SettingsScrollMetrics.minHeight)
    }

    func testShowOrdersMiniaturizedPanelBackIn() {
        let controller = makeController()
        let panel = controller.show()
        defer { panel.close() }
        panel.miniaturize(nil)
        // The minimize animation can outlast a fixed short spin on a busy runner.
        spinRunLoop(until: { panel.isMiniaturized })
        XCTAssertTrue(panel.isMiniaturized)

        controller.show()
        spinRunLoop(until: { !panel.isMiniaturized && panel.isVisible })
        XCTAssertFalse(panel.isMiniaturized)
        XCTAssertTrue(panel.isVisible)
    }

    /// Spins the main run loop until `condition` holds or `timeout` passes;
    /// the caller's assertions report a timeout.
    private func spinRunLoop(timeout: TimeInterval = 5, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
        }
    }

    func testShowOrdersOutPanelBackIn() {
        let controller = makeController()
        let panel = controller.show()
        defer { panel.close() }
        panel.orderOut(nil)
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertFalse(panel.isVisible)

        let shown = controller.show()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        XCTAssertTrue(panel === shown)
        XCTAssertTrue(panel.isVisible)
    }

    func testTitleDerivedFromBundleName() {
        XCTAssertEqual(
            SettingsWindowController<Text>.settingsTitle(
                bundleName: "Bob Mac Capture Accept"),
            "Bob Mac Capture Accept Settings")
        let controller = makeController(bundleName: "Bob Mac Capture Accept")
        let panel = controller.show()
        defer { panel.close() }
        XCTAssertEqual(panel.title, "Bob Mac Capture Accept Settings")
    }

    func testDefaultTitleEndsWithSettings() {
        let controller = SettingsWindowController {
            Text("Settings")
        }
        let panel = controller.show()
        defer { panel.close() }
        XCTAssertTrue(panel.title.hasSuffix(" Settings"))
    }

    func testInitialHeightStaysWithinBounds() {
        XCTAssertEqual(
            SettingsWindowController<Text>.initialHeight(visibleHeight: 900),
            820)
        XCTAssertEqual(
            SettingsWindowController<Text>.initialHeight(visibleHeight: 500),
            436)
        let def = SettingsWindowController<Text>.initialHeight()
        XCTAssertGreaterThanOrEqual(def, SettingsScrollMetrics.minHeight)
        XCTAssertLessThanOrEqual(def, SettingsScrollMetrics.maxIdealHeight)
    }

    func testCommandWClosesSettings() {
        let controller = makeController()
        let panel = controller.show()
        defer { panel.close() }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )!
        XCTAssertTrue(panel.performKeyEquivalent(with: event))
        XCTAssertFalse(panel.isVisible)
    }

    func testEscapeDoesNotCloseSettings() {
        let controller = makeController()
        let panel = controller.show()
        defer { panel.close() }
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: panel.windowNumber,
            context: nil,
            characters: "\u{1B}",
            charactersIgnoringModifiers: "\u{1B}",
            isARepeat: false,
            keyCode: 53
        )!
        XCTAssertFalse(panel.performKeyEquivalent(with: event))
        XCTAssertTrue(panel.isVisible)
    }
}
