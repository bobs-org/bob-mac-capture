import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif
import XCTest

@testable import RefsCore

final class RefsPanelGeometryTests: XCTestCase {
    func testMacBookPanelFrameAndWideInspectorGeometry() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 870)
        XCTAssertEqual(RefsPanelGeometry.panelSize(visible: visible), CGSize(width: 1344, height: 798))
        XCTAssertEqual(
            RefsPanelGeometry.panelFrame(visible: visible),
            CGRect(x: 48, y: 36, width: 1344, height: 798)
        )
        XCTAssertEqual(RefsPanelGeometry.listWidth(panelWidth: 1344), 560)
        XCTAssertEqual(RefsPanelGeometry.inspectorColumnWidth(panelWidth: 1344), 767.5)

        let layout = RefsPanelGeometry.inspectorLayout(panelWidth: 1344)
        XCTAssertEqual(layout.mode, .wide)
        XCTAssertEqual(layout.columnWidth, 767.5)
        XCTAssertEqual(layout.padding, 24)
        XCTAssertEqual(layout.contentWidth, 719.5)
        XCTAssertEqual(layout.imageMaxHeight, 420)
    }

    func testPanelCapsLargeDisplaysAndCentersReadableInspector() {
        let visible = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        XCTAssertEqual(
            RefsPanelGeometry.panelSize(visible: visible),
            CGSize(width: 1440, height: 1000)
        )
        XCTAssertEqual(
            RefsPanelGeometry.panelFrame(visible: visible),
            CGRect(x: 560, y: 208, width: 1440, height: 1000)
        )
        let layout = RefsPanelGeometry.inspectorLayout(panelWidth: 1440)
        XCTAssertEqual(layout.mode, .wide)
        XCTAssertEqual(layout.contentWidth, 720)
    }

    func testWidthThresholdsKeepCompactAndWideLayoutsPredictable() {
        let at1280 = RefsPanelGeometry.inspectorLayout(panelWidth: 1184)
        XCTAssertEqual(RefsPanelGeometry.listWidth(panelWidth: 1184), 560)
        XCTAssertEqual(at1280.columnWidth, 607.5)
        XCTAssertEqual(at1280.mode, .wide)

        let at880 = RefsPanelGeometry.inspectorLayout(panelWidth: 880)
        XCTAssertEqual(RefsPanelGeometry.listWidth(panelWidth: 880), 458)
        XCTAssertEqual(at880.columnWidth, 405.5)
        XCTAssertEqual(at880.mode, .compact)
        XCTAssertEqual(at880.padding, 18)
        XCTAssertEqual(at880.contentWidth, 369.5)
        XCTAssertEqual(at880.imageMaxHeight, 260)

        let smallScreen = RefsPanelGeometry.panelSize(
            visible: CGRect(x: 0, y: 0, width: 1024, height: 640)
        )
        XCTAssertEqual(smallScreen, CGSize(width: 928, height: 568))
        XCTAssertEqual(RefsPanelGeometry.inspectorLayout(panelWidth: 928).mode, .compact)
        XCTAssertTrue(RefsPanelGeometry.showsInspector(panelWidth: 760))
        XCTAssertFalse(RefsPanelGeometry.showsInspector(panelWidth: 759.9))
    }

    func testTinyVisibleFrameNeverProducesNegativeSizes() {
        let visible = CGRect(x: 10, y: 20, width: 40, height: 20)
        XCTAssertEqual(RefsPanelGeometry.panelSize(visible: visible), .zero)
        XCTAssertEqual(RefsPanelGeometry.panelFrame(visible: visible), CGRect(x: 30, y: 30, width: 0, height: 0))
        XCTAssertEqual(RefsPanelGeometry.inspectorColumnWidth(panelWidth: 0), 0)
        XCTAssertEqual(RefsPanelGeometry.inspectorLayout(panelWidth: -50).contentWidth, 0)
    }
}
