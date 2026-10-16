import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Golden tests for the tab-close contracts: session close outcomes,
/// the closed-tab stack, the after-removal selection rule, and close copy.
final class RefsTabCloseTests: XCTestCase {
    private func openTab(
        _ name: String,
        window: Int = 0,
        ordinal: Int = 0
    ) -> RefsOpenTab {
        RefsOpenTab(
            rowID: "highlights-tab:\(name)",
            itemID: nil,
            candidateIDs: [],
            fileName: name,
            windowOrdinal: window,
            tabOrdinal: ordinal,
            isCurrent: false,
            pageCaption: nil,
            documentPath: nil,
            match: .none
        )
    }

    private func snapshot(_ names: [String], current: String? = nil) -> HighlightsTabsSnapshot {
        HighlightsTabsSnapshot(
            windows: [.init(
                isMain: true,
                tabs: names.map {
                    .init(fileName: $0, isSelected: $0 == current)
                }
            )],
            highlightsIsFrontmost: true
        )
    }

    private func closedEntry(_ name: String, itemID: String? = nil) -> RefsClosedTab {
        RefsClosedTab(
            title: name,
            fileName: name,
            url: URL(fileURLWithPath: "/fixture-vault/lib/\(name)"),
            itemID: itemID
        )
    }

    private func listing(_ ids: String...) -> RefsListing {
        RefsListing(
            mode: .browse,
            scope: .all,
            sections: [RefsSection(kind: nil, ids: ids)],
            orderedIDs: ids,
            matches: [:],
            totalCount: ids.count,
            openCount: 0
        )
    }

    func testDocumentCountCoversZeroWindowsEmptyWindowsAndTwoWindows() {
        XCTAssertEqual(
            HighlightsTabsSnapshot(windows: [], highlightsIsFrontmost: false).documentCount,
            0
        )
        XCTAssertEqual(
            HighlightsTabsSnapshot(
                windows: [.init(isMain: true, tabs: [])],
                highlightsIsFrontmost: false
            ).documentCount,
            0
        )
        XCTAssertEqual(
            HighlightsTabsSnapshot(
                windows: [
                    .init(isMain: true, tabs: [
                        .init(fileName: "one.pdf", isSelected: true),
                        .init(fileName: "two.pdf", isSelected: false),
                    ]),
                    .init(isMain: false, tabs: [
                        .init(fileName: "three.pdf", isSelected: true),
                    ]),
                ],
                highlightsIsFrontmost: true
            ).documentCount,
            3
        )
    }

    func testDefaultsKeepBareConformersCompiling() async {
        let target = HighlightsTabTarget(fileName: "fixture.pdf", windowOrdinal: 0)
        let bare = BareTabsReader()
        let bareClose = await bare.close(target)
        XCTAssertEqual(
            bareClose,
            .failed("Closing Highlights tabs isn't available in this build")
        )
        let bareQuit = await bare.quitIfNoDocuments()
        XCTAssertFalse(bareQuit)

        let unavailable = UnavailableHighlightsTabsReader()
        let unavailableClose = await unavailable.close(target)
        XCTAssertEqual(
            unavailableClose,
            .failed("Closing Highlights tabs isn't available in this build")
        )
        let unavailableQuit = await unavailable.quitIfNoDocuments()
        XCTAssertFalse(unavailableQuit)
    }

    @MainActor
    func testCloseWithTabsRemainingUpdatesSnapshotAndPushesReopen() async {
        let remaining = snapshot(["kept.pdf", "current.pdf"], current: "current.pdf")
        let now = Date(timeIntervalSince1970: 7)
        let reader = FakeCloseTabsReader(
            closeResult: .closed(remaining),
            quitResult: true
        )
        let session = HighlightsTabsSession(reader: reader, now: { now })
        let entry = closedEntry("gone.pdf")

        let outcome = await session.close(openTab("gone.pdf"), reopen: entry)

        XCTAssertEqual(outcome, .closed(remaining: remaining))
        XCTAssertEqual(session.lastSnapshot, remaining)
        XCTAssertEqual(session.recency.lastActive("current.pdf"), now)
        XCTAssertEqual(reader.quitCount, 0)
        XCTAssertEqual(reader.closeTargets, [
            HighlightsTabTarget(fileName: "gone.pdf", windowOrdinal: 0)
        ])
    }

    @MainActor
    func testCloseOfLastDocumentQuitsOnceAndReportsQuit() async {
        let empty = HighlightsTabsSnapshot(windows: [], highlightsIsFrontmost: false)
        let reader = FakeCloseTabsReader(closeResult: .closed(empty), quitResult: true)
        let session = HighlightsTabsSession(reader: reader)

        let outcome = await session.close(openTab("last.pdf"), reopen: closedEntry("last.pdf"))

        XCTAssertEqual(outcome, .closedLast(highlightsQuit: true))
        XCTAssertEqual(reader.quitCount, 1)
        XCTAssertEqual(session.lastSnapshot, empty)
    }

    @MainActor
    func testCloseOfLastDocumentReportsFailedQuit() async {
        let empty = HighlightsTabsSnapshot(windows: [], highlightsIsFrontmost: false)
        let reader = FakeCloseTabsReader(closeResult: .closed(empty), quitResult: false)
        let session = HighlightsTabsSession(reader: reader)

        let outcome = await session.close(openTab("last.pdf"), reopen: nil)

        XCTAssertEqual(outcome, .closedLast(highlightsQuit: false))
        XCTAssertEqual(reader.quitCount, 1)
        XCTAssertTrue(session.closedTabs.isEmpty)
    }

    @MainActor
    func testNotFoundBecomesAlreadyClosedWithoutPushOrQuit() async {
        let reader = FakeCloseTabsReader(closeResult: .notFound, quitResult: true)
        let session = HighlightsTabsSession(reader: reader)

        let outcome = await session.close(openTab("gone.pdf"), reopen: closedEntry("gone.pdf"))

        XCTAssertEqual(outcome, .alreadyClosed)
        XCTAssertTrue(session.closedTabs.isEmpty)
        XCTAssertEqual(reader.quitCount, 0)
        XCTAssertNil(session.lastSnapshot)
    }

    @MainActor
    func testOtherResultsPassThroughWithoutQuit() async {
        let cases: [(HighlightsTabCloseResult, HighlightsTabCloseOutcome)] = [
            (.notRunning, .notRunning),
            (.notTrusted, .notTrusted),
            (.needsAttention, .needsAttention),
            (.failed("Highlights didn't close that tab"), .failed("Highlights didn't close that tab")),
        ]
        for (closeResult, expected) in cases {
            let reader = FakeCloseTabsReader(closeResult: closeResult, quitResult: true)
            let session = HighlightsTabsSession(reader: reader)

            let outcome = await session.close(openTab("kept.pdf"), reopen: nil)

            XCTAssertEqual(outcome, expected)
            XCTAssertEqual(reader.quitCount, 0)
            XCTAssertNil(session.lastSnapshot)
            XCTAssertTrue(session.closedTabs.isEmpty)
        }
    }

    @MainActor
    func testCloseSupersedesEarlierRefresh() async {
        let oldSnapshot = snapshot(["old.pdf"], current: "old.pdf")
        let remaining = snapshot(["kept.pdf"], current: "kept.pdf")
        let barrier = CloseReadBarrier()
        let reader = FakeCloseTabsReader(
            closeResult: .closed(remaining),
            readHandler: { await barrier.read() }
        )
        let session = HighlightsTabsSession(reader: reader)

        let staleRefresh = Task { @MainActor in await session.refresh() }
        await barrier.waitUntilStarted(1)
        let outcome = await session.close(openTab("gone.pdf"), reopen: nil)
        await barrier.resolve(0, with: .snapshot(oldSnapshot))
        let staleResult = await staleRefresh.value

        XCTAssertEqual(outcome, .closed(remaining: remaining))
        XCTAssertNil(staleResult)
        XCTAssertEqual(session.lastSnapshot, remaining)
    }

    @MainActor
    func testPopClosedTabDrainsNewestFirst() async {
        let reader = FakeCloseTabsReader(
            closeResult: .closed(snapshot(["kept.pdf"], current: "kept.pdf"))
        )
        let session = HighlightsTabsSession(reader: reader)
        let first = closedEntry("first.pdf")
        let second = closedEntry("second.pdf")

        _ = await session.close(openTab("first.pdf"), reopen: first)
        _ = await session.close(openTab("second.pdf"), reopen: second)

        XCTAssertEqual(session.popClosedTab(), second)
        XCTAssertEqual(session.popClosedTab(), first)
        XCTAssertNil(session.popClosedTab())
        XCTAssertTrue(session.closedTabs.isEmpty)
    }

    func testClosedTabsPushPopOrderDedupeAndCap() {
        var stack = RefsClosedTabs()
        XCTAssertTrue(stack.isEmpty)
        XCTAssertEqual(stack.count, 0)

        let first = closedEntry("first.pdf")
        let second = closedEntry("second.pdf")
        stack.push(first)
        stack.push(second)
        XCTAssertEqual(stack.count, 2)
        XCTAssertEqual(stack.popLast(), second)
        XCTAssertEqual(stack.popLast(), first)
        XCTAssertNil(stack.popLast())

        var normalized = RefsClosedTabs()
        normalized.push(first)
        normalized.push(second)
        normalized.push(RefsClosedTab(
            title: "first.pdf",
            fileName: "first.pdf",
            url: URL(fileURLWithPath: "/fixture-vault/lib/../lib/first.pdf"),
            itemID: nil
        ))
        XCTAssertEqual(normalized.count, 2)
        XCTAssertEqual(normalized.popLast()?.url.standardizedFileURL, first.url.standardizedFileURL)
        XCTAssertEqual(normalized.popLast(), second)

        var capped = RefsClosedTabs()
        for index in 0..<(RefsClosedTabs.capacity + 1) {
            capped.push(closedEntry("paper-\(index).pdf"))
        }
        XCTAssertEqual(capped.count, RefsClosedTabs.capacity)
        XCTAssertEqual(capped.popLast(), closedEntry("paper-\(RefsClosedTabs.capacity).pdf"))
    }

    func testAfterRemovingSelectsNeighbourWithoutWrapping() {
        XCTAssertEqual(afterRemovingCheck(["aaa", "bbb", "ccc"], removing: "bbb"), "ccc")
        XCTAssertEqual(afterRemovingCheck(["aaa", "bbb", "ccc"], removing: "aaa"), "bbb")
        XCTAssertEqual(afterRemovingCheck(["aaa", "bbb", "ccc"], removing: "ccc"), "bbb")
        XCTAssertNil(afterRemovingCheck(["aaa"], removing: "aaa"))
        XCTAssertEqual(afterRemovingCheck(["aaa", "bbb"], removing: "zzz"), "aaa")
        XCTAssertNil(RefsSelectionPolicy.afterRemoving("aaa", in: listing()))
    }

    private func afterRemovingCheck(_ ids: [String], removing id: String) -> String? {
        let list = RefsListing(
            mode: .browse,
            scope: .all,
            sections: [RefsSection(kind: nil, ids: ids)],
            orderedIDs: ids,
            matches: [:],
            totalCount: ids.count,
            openCount: 0
        )
        return RefsSelectionPolicy.afterRemoving(id, in: list)
    }

    func testCloseCopyPinsEveryString() {
        XCTAssertEqual(
            RefsTabClosePresentation.toast(title: "Paper", canReopen: true),
            RefsTabCloseToast(
                title: "Closed tab", value: "Paper", detail: "⇧⌘T reopens", isLast: false)
        )
        XCTAssertEqual(
            RefsTabClosePresentation.toast(title: "Paper", canReopen: false),
            RefsTabCloseToast(title: "Closed tab", value: "Paper", detail: nil, isLast: false)
        )
        XCTAssertEqual(
            RefsTabClosePresentation.lastToast(title: "Paper", highlightsQuit: true),
            RefsTabCloseToast(
                title: "Closed the last tab", value: "Paper",
                detail: "Highlights quit", isLast: true)
        )
        XCTAssertEqual(
            RefsTabClosePresentation.lastToast(title: "Paper", highlightsQuit: false),
            RefsTabCloseToast(
                title: "Closed the last tab", value: "Paper", detail: nil, isLast: true)
        )
        XCTAssertEqual(
            RefsTabClosePresentation.announcement(title: "Paper", countText: "8 tabs"),
            "Closed Paper. 8 tabs."
        )
        XCTAssertEqual(
            RefsTabClosePresentation.announcement(title: "Paper", countText: nil),
            "Closed Paper."
        )
        XCTAssertEqual(
            RefsTabClosePresentation.lastAnnouncement(title: "Paper", highlightsQuit: true),
            "Closed Paper. Highlights quit."
        )
        XCTAssertEqual(
            RefsTabClosePresentation.lastAnnouncement(title: "Paper", highlightsQuit: false),
            "Closed Paper."
        )
        XCTAssertEqual(
            RefsTabClosePresentation.failureMessage(title: "Paper"),
            "Couldn't close “Paper” in Highlights."
        )
        XCTAssertEqual(RefsTabClosePresentation.toastHoldDuration, 2.2)
    }
}

/// A reader conformer that overrides nothing new, proving the protocol
/// extension defaults keep existing conformers compiling.
private struct BareTabsReader: HighlightsTabsReading {
    func isTrusted() -> Bool { true }
    func requestTrust() {}
    func read() async -> HighlightsTabsReadResult { .notRunning }
    func select(_ target: HighlightsTabTarget) async -> HighlightsTabSelectResult { .notFound }
}

private final class FakeCloseTabsReader: HighlightsTabsReading, @unchecked Sendable {
    private let closeResult: HighlightsTabCloseResult
    private let quitResult: Bool
    private let readHandler: (@Sendable () async -> HighlightsTabsReadResult)?
    private let lock = NSLock()
    private var targets: [HighlightsTabTarget] = []
    private var closes = 0
    private var quits = 0

    init(
        closeResult: HighlightsTabCloseResult = .notFound,
        quitResult: Bool = false,
        readHandler: (@Sendable () async -> HighlightsTabsReadResult)? = nil
    ) {
        self.closeResult = closeResult
        self.quitResult = quitResult
        self.readHandler = readHandler
    }

    /// Targets received by `close`, in call order.
    var closeTargets: [HighlightsTabTarget] {
        lock.lock()
        defer { lock.unlock() }
        return targets
    }

    /// The number of `quitIfNoDocuments` calls.
    var quitCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return quits
    }

    func isTrusted() -> Bool { true }
    func requestTrust() {}

    func read() async -> HighlightsTabsReadResult {
        guard let readHandler else {
            return .notRunning
        }
        return await readHandler()
    }

    func select(_ target: HighlightsTabTarget) async -> HighlightsTabSelectResult { .notFound }

    func close(_ target: HighlightsTabTarget) async -> HighlightsTabCloseResult {
        recordClose(target)
        return closeResult
    }

    func quitIfNoDocuments() async -> Bool {
        recordQuit()
        return quitResult
    }

    private func recordClose(_ target: HighlightsTabTarget) {
        lock.lock()
        targets.append(target)
        closes += 1
        lock.unlock()
    }

    private func recordQuit() {
        lock.lock()
        quits += 1
        lock.unlock()
    }
}

private actor CloseReadBarrier {
    private var nextID = 0
    private var continuations: [Int: CheckedContinuation<HighlightsTabsReadResult, Never>] = [:]
    private var startedCount = 0
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func read() async -> HighlightsTabsReadResult {
        await withCheckedContinuation { continuation in
            let id = nextID
            nextID += 1
            continuations[id] = continuation
            startedCount += 1
            resumeReadyWaiters()
        }
    }

    func waitUntilStarted(_ count: Int) async {
        guard startedCount < count else {
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append((count, continuation))
        }
    }

    func resolve(_ id: Int, with result: HighlightsTabsReadResult) {
        continuations.removeValue(forKey: id)?.resume(returning: result)
    }

    private func resumeReadyWaiters() {
        let ready = waiters.filter { $0.count <= startedCount }
        waiters.removeAll { $0.count <= startedCount }
        ready.forEach { $0.continuation.resume() }
    }
}
