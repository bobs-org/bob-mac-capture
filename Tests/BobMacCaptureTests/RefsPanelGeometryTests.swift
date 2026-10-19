import AppKit
import XCTest

@testable import BobMacCapture

/// Geometry and window-configuration tests: the §6 panel contract
/// (borderless non-activating glass, floating level, collection
/// behavior) plus the pure size, threshold, and position math.
@MainActor
final class RefsPanelGeometryTests: XCTestCase {
    func testPanelStyleMaskIsBorderlessNonactivating() {
        let panel = RefsPanelController.makePanel()
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    }

    func testPanelKeyAndMain() {
        let panel = RefsPanelController.makePanel()
        XCTAssertTrue(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
    }

    func testPanelLevelAndBehavior() {
        let panel = RefsPanelController.makePanel()
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level.rawValue, NSWindow.Level.floating.rawValue)
        XCTAssertTrue(
            panel.collectionBehavior.contains(.canJoinAllSpaces)
        )
        XCTAssertTrue(
            panel.collectionBehavior.contains(.fullScreenAuxiliary)
        )
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
    }

    func testPanelChromeFlags() {
        let panel = RefsPanelController.makePanel()
        XCTAssertFalse(panel.isOpaque)
        XCTAssertTrue(panel.backgroundColor?.isEqual(NSColor.clear) ?? false)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertFalse(panel.isMovableByWindowBackground)
    }

    func testSizeClampOnLargeScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1280, height: 800)
        XCTAssertEqual(
            RefsVisualTokens.panelSize(for: visible),
            NSSize(width: 1184, height: 728)
        )
    }

    func testSizeClampOnSmallScreen() {
        let visible = NSRect(x: 0, y: 0, width: 700, height: 500)
        XCTAssertEqual(
            RefsVisualTokens.panelSize(for: visible),
            NSSize(width: 604, height: 428)
        )
    }

    func testInspectorThreshold() {
        XCTAssertTrue(RefsVisualTokens.showsInspector(width: 880))
        XCTAssertTrue(RefsVisualTokens.showsInspector(width: 760))
        XCTAssertFalse(RefsVisualTokens.showsInspector(width: 759))
        XCTAssertFalse(RefsVisualTokens.showsInspector(width: 700))
    }

    func testListColumnWidth() {
        XCTAssertEqual(RefsVisualTokens.listWidth(panelWidth: 880), 458)
        // The list column caps at 560 on reading-room widths.
        XCTAssertEqual(RefsVisualTokens.listWidth(panelWidth: 1344), 560)
    }

    func testReadingRoomFrameOnMacBook() {
        // Bryan's MacBook (1440 × 870 at 0,0): 48 pt side margins,
        // 36 pt top and bottom.
        let visible = NSRect(x: 0, y: 0, width: 1440, height: 870)
        XCTAssertEqual(
            RefsVisualTokens.panelFrame(for: visible),
            NSRect(x: 48, y: 36, width: 1344, height: 798)
        )
    }

    func testCenteredPosition() {
        // A 1512 × 944 visible frame: the reading-room size,
        // centered on both axes.
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let frame = RefsVisualTokens.panelFrame(for: visible)
        XCTAssertEqual(frame.width, 1416)
        XCTAssertEqual(frame.height, 872)
        XCTAssertEqual(frame.minX, 48)
        XCTAssertEqual(frame.minY, 36)
    }

    func testFrameClampsInsideSmallVisibleFrame() {
        let visible = NSRect(x: 0, y: 0, width: 700, height: 500)
        let frame = RefsVisualTokens.panelFrame(for: visible)
        XCTAssertEqual(frame.width, 604)
        XCTAssertEqual(frame.height, 428)
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
    }

    func testTokens() {
        XCTAssertEqual(RefsVisualTokens.searchBarHeight, 52)
        XCTAssertEqual(RefsVisualTokens.sectionHeaderHeight, 26)
        XCTAssertEqual(RefsVisualTokens.rowHeight, 44)
        XCTAssertEqual(RefsVisualTokens.footerHeight, 30)
        XCTAssertEqual(RefsVisualTokens.copyCardRowHeight, 24)
        XCTAssertEqual(RefsVisualTokens.copyHUDMaxValueWidth, 380)
    }

    func testActionsAnchorSitsBelowSelectedRow() {
        // A selected row at panel-root (8, 100, 442 × 44): the menu
        // pops below its leading text. The hosting view fills the
        // content view, so the y-down row edge flips by the height.
        let hosting = NSRect(x: 0, y: 0, width: 880, height: 560)
        let point = RefsPanelController.actionsAnchor(
            rowRect: CGRect(x: 8, y: 100, width: 442, height: 44),
            hostingFrame: hosting,
            contentSize: hosting.size,
            panelWidth: 880
        )
        XCTAssertEqual(point.x, 20)
        XCTAssertEqual(point.y, 560 - 144)
    }

    func testActionsAnchorFallsBackToListCenter() {
        let hosting = NSRect(x: 0, y: 0, width: 880, height: 560)
        for rowRect: CGRect? in [nil, .zero] {
            let point = RefsPanelController.actionsAnchor(
                rowRect: rowRect,
                hostingFrame: hosting,
                contentSize: hosting.size,
                panelWidth: 880
            )
            XCTAssertEqual(point.x, 8 + round(880 * 0.52) / 2)
            XCTAssertEqual(point.y, 280)
        }
    }

    func testActionsMenuShowsOpenShortcutHints() {
        XCTAssertEqual(RefsAction.openHighlights.keyEquivalent, "\r")
        XCTAssertEqual(RefsAction.openHighlights.keyEquivalentModifierMask, [])
        XCTAssertEqual(RefsAction.openNote.keyEquivalent, "\r")
        XCTAssertEqual(RefsAction.openNote.keyEquivalentModifierMask, .command)
        XCTAssertEqual(RefsAction.reveal.keyEquivalent, "\r")
        XCTAssertEqual(RefsAction.reveal.keyEquivalentModifierMask, .option)
        XCTAssertEqual(RefsAction.refreshLibrary.keyEquivalent, "r")
        XCTAssertEqual(RefsAction.refreshLibrary.keyEquivalentModifierMask, .command)
    }
}
