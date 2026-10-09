import AppKit
import XCTest

@testable import BobMacCapture

/// Geometry and window-configuration tests: the §6 panel contract
/// (borderless non-activating glass, floating level, collection
/// behavior) plus the pure size, threshold, and position math.
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
        XCTAssertTrue(panel.backgroundColor?.isEqual(.clear) ?? false)
        XCTAssertTrue(panel.hasShadow)
        XCTAssertFalse(panel.hidesOnDeactivate)
        XCTAssertFalse(panel.isReleasedWhenClosed)
        XCTAssertFalse(panel.isMovableByWindowBackground)
    }

    func testSizeClampOnLargeScreen() {
        let visible = NSRect(x: 0, y: 0, width: 1280, height: 800)
        XCTAssertEqual(
            RefsVisualTokens.panelSize(for: visible),
            NSSize(width: 880, height: 560)
        )
    }

    func testSizeClampOnSmallScreen() {
        let visible = NSRect(x: 0, y: 0, width: 700, height: 500)
        XCTAssertEqual(
            RefsVisualTokens.panelSize(for: visible),
            NSSize(width: 620, height: 420)
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
    }

    func testTopEdgePosition() {
        // A 1512 × 944 visible frame: the top edge sits 16% of the
        // height below the top, centered horizontally.
        let visible = NSRect(x: 0, y: 0, width: 1512, height: 944)
        let frame = RefsVisualTokens.panelFrame(for: visible)
        XCTAssertEqual(frame.width, 880)
        XCTAssertEqual(frame.height, 560)
        XCTAssertEqual(frame.minX, 316)
        XCTAssertEqual(frame.maxY, 944 - round(944 * 0.16))
    }

    func testFrameClampsInsideSmallVisibleFrame() {
        let visible = NSRect(x: 0, y: 0, width: 700, height: 500)
        let frame = RefsVisualTokens.panelFrame(for: visible)
        XCTAssertEqual(frame.width, 620)
        XCTAssertEqual(frame.height, 420)
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
    }
}
