import XCTest

@testable import BobMacCapture

/// Footer scan status: the hints carry the ⌘S shortcut, and the status
/// decision keeps its priority order — scanning, refresh failed, the
/// scan notice, updating, updated.
final class RefsFooterTests: XCTestCase {
    func testHintsCarryCopyAndScanShortcuts() {
        XCTAssertEqual(
            RefsFooter.hintsText(openHint: "↵ Open in Highlights"),
            "↵ Open in Highlights  ⌘↵ Note  ⌥↵ Reveal  ⌘Y Copy  ⌘K Actions  "
                + "⌘S Scan  ⌘1–5 Scope  esc Close"
        )
        XCTAssertEqual(
            RefsFooter.hintsText(openHint: "↵ Open note"),
            "↵ Open note  ⌘↵ Note  ⌥↵ Reveal  ⌘Y Copy  ⌘K Actions  ⌘S Scan  "
                + "⌘1–5 Scope  esc Close"
        )
        XCTAssertEqual(
            RefsFooter.hintVariants(openHint: "↵ Open note").map {
                $0.contains("⌘1–5 Scope")
            },
            [true, false, false]
        )
        XCTAssertFalse(
            RefsFooter.hintVariants(openHint: "↵ Open note")[2]
                .contains("⌘S Scan")
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
