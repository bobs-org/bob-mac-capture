import AppKit
import XCTest

@testable import BobMacCapture
@testable import RefsCore

/// The live reader never launches Highlights when its configured process is absent.
final class AXHighlightsTabsReaderTests: XCTestCase {
    func testUnknownBundleIDMatchesReadAcrossClose() async {
        let identifier = "org.example.highlights-tabs-test-\(UUID().uuidString)"
        let reader = AXHighlightsTabsReader(bundleIdentifier: { identifier })
        let target = HighlightsTabTarget(fileName: "sample.pdf", windowOrdinal: 0)

        let readResult = await reader.read()
        let selectResult = await reader.select(target)
        let closeResult = await reader.close(target)
        let quit = await reader.quitIfNoDocuments()

        // Trust is checked first, so ungranted CI hosts see notTrusted
        // while granted hosts see notRunning. Both are documented.
        XCTAssertTrue(readResult == .notRunning || readResult == .notTrusted)
        XCTAssertEqual(selectResult, matchingSelectResult(from: readResult))
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

    func testCloseVerificationSucceedsAfterPolls() {
        let closed = HighlightsTabsSnapshot(windows: [], highlightsIsFrontmost: false)
        let staying = HighlightsTabsSnapshot(
            windows: [HighlightsTabsSnapshot.Window(
                isMain: true,
                tabs: [HighlightsTabsSnapshot.Tab(fileName: "a.pdf", isSelected: true)]
            )],
            highlightsIsFrontmost: false
        )
        var now: UInt64 = 0
        var reads = 0
        var activations = 0
        let result = CloseVerification.run(
            beforeCount: 1,
            deadline: 100,
            now: { now },
            hasExited: { false },
            read: () -> (
                snapshot: HighlightsTabsSnapshot, titleCount: Int, hasSheet: Bool
            ) in
                reads += 1
                now += 50
                if reads < 3 {
                    return (staying, 1, false)
                }
                return (closed, 0, false)
            },
            onNeedsAttention: { activations += 1 },
            sleep: {},
            emptySnapshot: { closed }
        )
        XCTAssertEqual(result, .closed(closed))
        XCTAssertEqual(reads, 3)
        XCTAssertEqual(activations, 0)
    }

    func testCloseVerificationSheetYieldsNeedsAttentionWithOneActivate() {
        let staying = HighlightsTabsSnapshot(
            windows: [HighlightsTabsSnapshot.Window(
                isMain: true,
                tabs: [HighlightsTabsSnapshot.Tab(fileName: "a.pdf", isSelected: true)]
            )],
            highlightsIsFrontmost: false
        )
        var now: UInt64 = 0
        var activations = 0
        let result = CloseVerification.run(
            beforeCount: 1,
            deadline: 100,
            now: { now },
            hasExited: { false },
            read: {
                now += 50
                return (staying, 1, true)
            },
            onNeedsAttention: { activations += 1 },
            sleep: {},
            emptySnapshot: {
                HighlightsTabsSnapshot(windows: [], highlightsIsFrontmost: false)
            }
        )
        XCTAssertEqual(result, .needsAttention)
        XCTAssertEqual(activations, 1)
    }

    func testCloseVerificationWithoutSheetReachesBoundedFailure() {
        let staying = HighlightsTabsSnapshot(
            windows: [HighlightsTabsSnapshot.Window(
                isMain: true,
                tabs: [HighlightsTabsSnapshot.Tab(fileName: "a.pdf", isSelected: true)]
            )],
            highlightsIsFrontmost: false
        )
        var now: UInt64 = 0
        var activations = 0
        let result = CloseVerification.run(
            beforeCount: 1,
            deadline: 100,
            now: { now },
            hasExited: { false },
            read: {
                now += 50
                return (staying, 1, false)
            },
            onNeedsAttention: { activations += 1 },
            sleep: {},
            emptySnapshot: {
                HighlightsTabsSnapshot(windows: [], highlightsIsFrontmost: false)
            }
        )
        XCTAssertNil(result)
        XCTAssertEqual(activations, 0)
    }

    func testCloseVerificationExitYieldsEmptyClosedSnapshot() {
        let empty = HighlightsTabsSnapshot(windows: [], highlightsIsFrontmost: false)
        var activations = 0
        let result = CloseVerification.run(
            beforeCount: 1,
            deadline: 100,
            now: { 0 },
            hasExited: { true },
            read: { () -> (
                snapshot: HighlightsTabsSnapshot, titleCount: Int, hasSheet: Bool
            ) in
                XCTFail("exited app must not read")
                return (empty, 1, false)
            },
            onNeedsAttention: { activations += 1 },
            sleep: {},
            emptySnapshot: { empty }
        )
        XCTAssertEqual(result, .closed(empty))
        XCTAssertEqual(activations, 0)
    }

    private func matchingSelectResult(
        from readResult: HighlightsTabsReadResult
    ) -> HighlightsTabSelectResult {
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
