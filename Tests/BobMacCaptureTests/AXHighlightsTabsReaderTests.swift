import AppKit
import XCTest

@testable import BobMacCapture
@testable import RefsCore

/// The live reader never launches Highlights when its configured process is absent.
final class AXHighlightsTabsReaderTests: XCTestCase {
    func testUnknownBundleIDIsNotRunningForReadAndSelect() async {
        let identifier = "org.example.highlights-tabs-test-\(UUID().uuidString)"
        let reader = AXHighlightsTabsReader(bundleIdentifier: { identifier })
        let target = HighlightsTabTarget(fileName: "sample.pdf", windowOrdinal: 0)

        let readResult = await reader.read()
        let selectResult = await reader.select(target)
        let closeResult = await reader.close(target)
        let quit = await reader.quitIfNoDocuments()

        XCTAssertEqual(readResult, .notRunning)
        XCTAssertEqual(selectResult, .notRunning)
        XCTAssertEqual(closeResult, .notRunning)
        XCTAssertEqual(closeResult, matchingCloseResult(from: readResult))
        XCTAssertNotEqual(
            closeResult,
            .failed("Closing Highlights tabs isn't available in this build")
        )
        XCTAssertTrue(quit)
        XCTAssertTrue(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: identifier
            ).isEmpty
        )
    }

    private func matchingCloseResult(
        from readResult: HighlightsTabsReadResult
    ) -> HighlightsTabCloseResult {
        switch readResult {
        case .notRunning:
            return .notRunning
        case .notTrusted:
            return .notTrusted
        case .failed(let reason):
            return .failed(reason)
        case .snapshot:
            return .failed("unknown bundle should not yield a snapshot")
        }
    }
}
