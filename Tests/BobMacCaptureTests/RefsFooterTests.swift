import XCTest

@testable import BobMacCapture

/// Footer scan status: the hints carry the ⌘S shortcut, and the status
/// decision keeps its priority order — scanning, refresh failed, the
/// scan notice, updating, updated.
final class RefsFooterTests: XCTestCase {
    func testHintsCarryScanShortcut() {
        XCTAssertEqual(
            RefsFooter.hintsText(openHint: "↵ Open in Highlights"),
            "↵ Open in Highlights  ⌘↵ Note  ⌥↵ Reveal  ⌘K Actions  "
                + "⌘S Scan  ⌘1–5 Scope  esc Close"
        )
        XCTAssertEqual(
            RefsFooter.hintsText(openHint: "↵ Open note"),
            "↵ Open note  ⌘↵ Note  ⌥↵ Reveal  ⌘K Actions  ⌘S Scan  "
                + "⌘1–5 Scope  esc Close"
        )
    }

    func testStatusPriorityOrder() {
        XCTAssertEqual(
            RefsFooter.statusPriority(
                isScanning: true,
                refreshFailed: true,
                hasScanNotice: true,
                refreshing: true
            ),
            .scanning
        )
        XCTAssertEqual(
            RefsFooter.statusPriority(
                isScanning: false,
                refreshFailed: true,
                hasScanNotice: true,
                refreshing: true
            ),
            .refreshFailed
        )
        XCTAssertEqual(
            RefsFooter.statusPriority(
                isScanning: false,
                refreshFailed: false,
                hasScanNotice: true,
                refreshing: true
            ),
            .scan
        )
        XCTAssertEqual(
            RefsFooter.statusPriority(
                isScanning: false,
                refreshFailed: false,
                hasScanNotice: false,
                refreshing: true
            ),
            .updating
        )
        XCTAssertEqual(
            RefsFooter.statusPriority(
                isScanning: false,
                refreshFailed: false,
                hasScanNotice: false,
                refreshing: false
            ),
            .updated
        )
    }
}
