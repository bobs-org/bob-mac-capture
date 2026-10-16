import AppKit
import Foundation
import SwiftUI
import XCTest

@testable import BobMacCapture
@testable import RefsCore

@MainActor
final class RefsCopyComponentsTests: XCTestCase {
    func testFakePasteboardRecordsPayloadsAndCanFail() {
        let pasteboard = FakePasteboard()
        XCTAssertTrue(pasteboard.write(.text("[[ref/chat/a]]")))
        let file = URL(fileURLWithPath: "/vault/lib/chat/a.pdf")
        XCTAssertTrue(pasteboard.write(.fileURL(file)))
        XCTAssertEqual(
            pasteboard.payloads,
            [.text("[[ref/chat/a]]"), .fileURL(file)]
        )
        XCTAssertEqual(pasteboard.strings, ["[[ref/chat/a]]"])

        pasteboard.copy("legacy")
        XCTAssertEqual(pasteboard.strings.last, "legacy")

        pasteboard.failWrites = true
        XCTAssertFalse(pasteboard.write(.text("nope")))
        XCTAssertEqual(pasteboard.strings.last, "legacy")
        XCTAssertEqual(pasteboard.payloads.count, 3)
    }

    func testHUDFrameCentersOnHost() {
        let host = NSRect(x: 100, y: 200, width: 880, height: 560)
        let size = NSSize(width: 240, height: 48)
        let frame = RefsCopyHUDController.frame(centeredOn: host, size: size)
        XCTAssertEqual(frame.width, 240)
        XCTAssertEqual(frame.height, 48)
        XCTAssertEqual(frame.midX, host.midX)
        XCTAssertEqual(frame.midY, host.midY)
        XCTAssertEqual(frame.origin.x, 100 + (880 - 240) / 2)
        XCTAssertEqual(frame.origin.y, 200 + (560 - 48) / 2)
    }

    func testHUDPanelNeverTakesKey() {
        let panel = RefsCopyHUDController.makePanel()
        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.isFloatingPanel)
        XCTAssertEqual(panel.level.rawValue, NSWindow.Level.floating.rawValue)
        XCTAssertTrue(panel.collectionBehavior.contains(.canJoinAllSpaces))
        XCTAssertTrue(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        XCTAssertTrue(panel.collectionBehavior.contains(.transient))
        XCTAssertTrue(panel.collectionBehavior.contains(.ignoresCycle))
        XCTAssertFalse(panel.isOpaque)
        XCTAssertFalse(panel.hasShadow)
    }

    func testClosedTabToastStyleUsesCloseGlyph() {
        XCTAssertEqual(RefsGlassToastStyle.closedTab.symbolName, "xmark.square.fill")
        XCTAssertEqual(RefsGlassToastStyle.closedTab.color, .secondary)
        let withDetail = RefsTabClosePresentation.toast(
            title: "Attention Is All You Need",
            canReopen: true
        )
        let withoutDetail = RefsTabClosePresentation.toast(
            title: "Attention Is All You Need",
            canReopen: false
        )
        XCTAssertEqual(withDetail.detail, "⇧⌘T reopens")
        XCTAssertNil(withoutDetail.detail)
        let lastQuit = RefsTabClosePresentation.lastToast(
            title: "Attention Is All You Need",
            highlightsQuit: true
        )
        let lastOpen = RefsTabClosePresentation.lastToast(
            title: "Attention Is All You Need",
            highlightsQuit: false
        )
        XCTAssertEqual(lastQuit.detail, "Highlights quit")
        XCTAssertNil(lastOpen.detail)
        _ = RefsGlassToastView(
            title: withoutDetail.title,
            value: withoutDetail.value,
            detail: withoutDetail.detail,
            style: .closedTab,
            previewMode: true
        )
        _ = RefsGlassToastView(
            title: lastOpen.title,
            value: lastOpen.value,
            detail: lastOpen.detail,
            style: .closedTab,
            previewMode: true
        )
    }

    func testCopyCardMetricsMatchTokens() {
        let metrics = RefsVisualTokens.copyCardMetrics
        XCTAssertEqual(metrics.headerHeight, 44)
        XCTAssertEqual(metrics.rowHeight, 24)
        XCTAssertEqual(metrics.separatorHeight, 9)
        XCTAssertEqual(metrics.notesHeaderHeight, 22)
        XCTAssertEqual(metrics.messageLineHeight, 20)
        XCTAssertEqual(metrics.verticalPadding, 36)
        XCTAssertEqual(RefsVisualTokens.copyCardPickerRowHeight, 36)
        XCTAssertEqual(RefsVisualTokens.copyCardKeycapSize, 18)
        XCTAssertEqual(RefsVisualTokens.copyCardLabelWidth, 92)
        XCTAssertEqual(RefsVisualTokens.copyHUDMaxValueWidth, 380)
    }
}
