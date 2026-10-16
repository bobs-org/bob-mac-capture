import XCTest

@testable import BobMacCapture
@testable import RefsCore

/// The live reader never launches Highlights when its configured process is absent.
final class AXHighlightsTabsReaderTests: XCTestCase {
    func testUnknownBundleIDIsNotRunningForReadAndSelect() async {
        let reader = AXHighlightsTabsReader(
            bundleIdentifier: { "org.example.highlights-tabs-test-\(UUID().uuidString)" }
        )

        let readResult = await reader.read()
        let selectResult = await reader.select(
            HighlightsTabTarget(fileName: "sample.pdf", windowOrdinal: 0)
        )
        XCTAssertEqual(readResult, .notRunning)
        XCTAssertEqual(selectResult, .notRunning)
    }
}
