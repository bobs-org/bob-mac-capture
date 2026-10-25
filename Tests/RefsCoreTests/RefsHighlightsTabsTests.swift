import Foundation
import XCTest

@testable import CaptureCore
@testable import RefsCore

/// Golden tests for the pure Highlights tab snapshot, matcher, ranker, and session.
final class RefsHighlightsTabsTests: XCTestCase {
    private let vaultRoot = URL(fileURLWithPath: "/fixture-vault")

    private func item(
        _ id: String,
        _ path: String,
        kind: RefKind = .paper,
        title: String? = nil,
        state: RefState = .ready
    ) -> RefItem {
        let stem = String(path.split(separator: "/").last ?? "")
            .replacingOccurrences(of: ".pdf", with: "")
        return RefItem(
            id: id,
            link: "[[\(id)]]",
            rawTitle: title ?? stem,
            stem: stem,
            kind: kind,
            state: state,
            isBlocked: false,
            pdfPath: path
        )
    }

    private func tab(
        _ name: String,
        window: Int = 0,
        ordinal: Int = 0,
        itemID: String? = nil,
        candidates: [String] = [],
        current: Bool = false,
        match: RefsOpenTabMatch = .none,
        page: String? = nil
    ) -> RefsOpenTab {
        RefsOpenTab(
            rowID: itemID ?? "highlights-tab:\(name)",
            itemID: itemID,
            candidateIDs: candidates,
            fileName: name,
            windowOrdinal: window,
            tabOrdinal: ordinal,
            isCurrent: current,
            pageCaption: page,
            documentPath: nil,
            match: match
        )
    }

    func testPageCaptionParsesEnDashAndHyphen() {
        XCTAssertEqual(
            HighlightsWindowTitle.pageCaption(fromTitle: "fixture.pdf – Page 5 of 25"),
            "p. 5/25"
        )
        XCTAssertEqual(
            HighlightsWindowTitle.pageCaption(fromTitle: "fixture.pdf - Page 2 of 8"),
            "p. 2/8"
        )
        XCTAssertNil(HighlightsWindowTitle.pageCaption(fromTitle: "fixture.pdf"))
    }

    func testPageNumberParsesDashVariantsAndNoSuffix() {
        XCTAssertEqual(
            HighlightsWindowTitle.pageNumber(fromTitle: "fixture.pdf – Page 5 of 25"),
            5
        )
        XCTAssertEqual(
            HighlightsWindowTitle.pageNumber(fromTitle: "fixture.pdf - Page 2 of 8"),
            2
        )
        XCTAssertEqual(
            HighlightsWindowTitle.pageNumber(fromTitle: "fixture.pdf — Page 7 of 9"),
            7
        )
        XCTAssertNil(HighlightsWindowTitle.pageNumber(fromTitle: "fixture.pdf"))
    }

    func testUnavailableReaderReturnsNameFreeFailure() async {
        let reader = UnavailableHighlightsTabsReader()
        XCTAssertFalse(reader.isTrusted())
        let readResult = await reader.read()
        let selectResult = await reader.select(
            HighlightsTabTarget(fileName: "fixture.pdf", windowOrdinal: 0)
        )
        XCTAssertEqual(readResult, .failed("Highlights tabs aren't available in this build"))
        XCTAssertEqual(selectResult, .failed("Highlights tabs aren't available in this build"))
    }

    func testMatcherUsesResolvedPathBeforeCollisionAndMatchesNames() throws {
        let papers = item("ref/papers/shared.md", "lib/papers/shared.pdf")
        let blogs = item("ref/blogs/shared.md", "lib/blogs/shared.pdf", kind: .article)
        let unique = item("ref/papers/unique.md", "lib/papers/unique.pdf")
        let hidden = item("ref/papers/hidden.md", "lib/papers/hidden.pdf")
        let suffixed = item("ref/papers/suffix.md", "lib/papers/suffix.pdf")
        let snapshot = HighlightsTabsSnapshot(
            windows: [HighlightsTabsSnapshot.Window(
                isMain: true,
                pageCaption: "p. 5/25",
                tabs: [
                    .init(
                        fileName: "shared.pdf",
                        documentPath: "/fixture-vault/lib/blogs/shared.pdf",
                        isSelected: true
                    ),
                    .init(fileName: "unique.pdf", isSelected: false),
                    .init(fileName: "hidden", isSelected: false),
                    .init(fileName: "suffix.pdf – Page 5 of 12", isSelected: false),
                ]
            )],
            highlightsIsFrontmost: true
        )

        let matched = HighlightsTabMatcher.match(
            snapshot,
            items: [papers, blogs, unique, hidden, suffixed],
            vaultRoot: vaultRoot
        )

        XCTAssertEqual(matched.count, 4)
        XCTAssertEqual(matched[0].itemID, blogs.id)
        XCTAssertEqual(matched[0].match, .path)
        XCTAssertEqual(matched[0].pageCaption, "p. 5/25")
        XCTAssertTrue(matched[0].isCurrent)
        XCTAssertEqual(matched[1].itemID, unique.id)
        XCTAssertEqual(matched[1].match, .fileName)
        XCTAssertEqual(matched[2].itemID, hidden.id)
        XCTAssertEqual(matched[2].match, .fileName)
        XCTAssertEqual(matched[3].itemID, suffixed.id)
        XCTAssertEqual(matched[3].match, .fileName)
    }

    func testMatcherReturnsCollisionAndUnmatchedRowsWithReservedIDs() {
        let collisionA = item("ref/papers/harness.md", "lib/papers/harness_engineering.pdf")
        let collisionB = item(
            "ref/blogs/harness.md", "lib/blogs/harness_engineering.pdf", kind: .article
        )
        let snapshot = HighlightsTabsSnapshot(
            windows: [HighlightsTabsSnapshot.Window(
                isMain: true,
                tabs: [
                    .init(fileName: "harness_engineering.pdf", isSelected: true),
                    .init(fileName: "cv.pdf", isSelected: false),
                    .init(fileName: "cv.pdf", isSelected: false),
                ]
            )],
            highlightsIsFrontmost: false
        )

        let matched = HighlightsTabMatcher.match(
            snapshot,
            items: [collisionA, collisionB],
            vaultRoot: vaultRoot
        )

        XCTAssertEqual(matched.map(\.match), [.collision, .none, .none])
        XCTAssertEqual(matched[0].candidateIDs, [collisionA.id, collisionB.id].sorted())
        XCTAssertEqual(matched[0].rowID, "highlights-tab:harness_engineering.pdf")
        XCTAssertEqual(matched[1].rowID, "highlights-tab:cv.pdf")
        XCTAssertEqual(matched[2].rowID, "highlights-tab:cv.pdf#2")
        XCTAssertTrue(matched[1].target == HighlightsTabTarget(fileName: "cv.pdf", windowOrdinal: 0))
    }

    func testMatcherResolvesSymlinksAndRejectsPathsOutsideVault() throws {
        let fileManager = FileManager.default
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("refs-tabs-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("vault", isDirectory: true)
        let alias = base.appendingPathComponent("alias", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let libraryDirectory = root.appendingPathComponent("lib/papers", isDirectory: true)
        try fileManager.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
        XCTAssertTrue(fileManager.createFile(
            atPath: libraryDirectory.appendingPathComponent("full.pdf").path,
            contents: Data()
        ))
        try fileManager.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? fileManager.removeItem(at: base) }

        let fixture = item("ref/papers/full.md", "lib/papers/full.pdf")
        let outsideName = item("ref/papers/elsewhere.md", "lib/papers/elsewhere.pdf")
        let snapshot = HighlightsTabsSnapshot(
            windows: [HighlightsTabsSnapshot.Window(isMain: true, tabs: [
                .init(
                    fileName: "full.pdf",
                    documentPath: alias.appendingPathComponent("lib/papers/full.pdf").path,
                    isSelected: true
                ),
                .init(
                    fileName: "elsewhere.pdf",
                    documentPath: base.appendingPathComponent("-elsewhere/elsewhere.pdf").path,
                    isSelected: false
                ),
            ])],
            highlightsIsFrontmost: false
        )

        let matched = HighlightsTabMatcher.match(
            snapshot,
            items: [fixture, outsideName],
            vaultRoot: root
        )
        XCTAssertEqual(matched.count, 2)
        XCTAssertEqual(matched[0].match, .path)
        XCTAssertEqual(matched[0].itemID, fixture.id)
        XCTAssertEqual(matched[1].match, .fileName)
        XCTAssertEqual(matched[1].itemID, outsideName.id)
    }

    func testMatcherMarksMainWindowCurrentAndDeduplicatesItems() throws {
        let fixture = item("ref/papers/one.md", "lib/papers/one.pdf")
        let snapshot = HighlightsTabsSnapshot(
            windows: [
                .init(isMain: false, tabs: [
                    .init(fileName: "one.pdf", isSelected: true),
                    .init(fileName: "two.pdf", isSelected: false),
                ]),
                .init(isMain: true, tabs: [
                    .init(
                        fileName: "one.pdf",
                        documentPath: "/fixture-vault/lib/papers/one.pdf",
                        isSelected: true
                    ),
                ]),
            ],
            highlightsIsFrontmost: false
        )

        let matched = HighlightsTabMatcher.match(snapshot, items: [fixture], vaultRoot: vaultRoot)

        XCTAssertEqual(matched.count, 2)
        XCTAssertEqual(matched[0].fileName, "two.pdf")
        XCTAssertEqual(matched[0].match, .none)
        XCTAssertEqual(matched.filter { $0.itemID == fixture.id }.count, 1)
        let current = try XCTUnwrap(matched.first(where: \.isCurrent))
        XCTAssertEqual(current.itemID, fixture.id)
        XCTAssertEqual(current.windowOrdinal, 1)
        XCTAssertEqual(current.tabOrdinal, 0)
        XCTAssertNil(HighlightsTabMatcher.match(
            .init(windows: [], highlightsIsFrontmost: false), items: [fixture], vaultRoot: vaultRoot
        ).first)
    }

    func testLocatorUsesTitleAndWindowAndRejectsClosedOrAmbiguousTabs() {
        let snapshot = HighlightsTabsSnapshot(
            windows: [
                .init(isMain: true, tabs: [
                    .init(fileName: "same.pdf", isSelected: true),
                    .init(fileName: "other.pdf", isSelected: false),
                ]),
                .init(isMain: false, tabs: [
                    .init(fileName: "moved.pdf", isSelected: true),
                ]),
            ],
            highlightsIsFrontmost: false
        )

        XCTAssertEqual(
            HighlightsTabLocator.locate(.init(fileName: "other.pdf", windowOrdinal: 0), in: snapshot)?.tab,
            1
        )
        XCTAssertEqual(
            HighlightsTabLocator.locate(.init(fileName: "moved.pdf", windowOrdinal: 0), in: snapshot)?.window,
            1
        )
        XCTAssertNil(HighlightsTabLocator.locate(.init(fileName: "closed.pdf", windowOrdinal: 0), in: snapshot))
        let ambiguous = HighlightsTabsSnapshot(
            windows: [
                .init(isMain: true, tabs: [.init(fileName: "same.pdf", isSelected: true)]),
                .init(isMain: false, tabs: [.init(fileName: "same.pdf", isSelected: true)]),
            ],
            highlightsIsFrontmost: false
        )
        XCTAssertNil(HighlightsTabLocator.locate(.init(fileName: "same.pdf", windowOrdinal: 9), in: ambiguous))
    }

    func testTabsBrowseOrderScopeAndPreselection() {
        let items = [
            item("ref/papers/current.md", "lib/papers/current.pdf"),
            item("ref/papers/recent.md", "lib/papers/recent.pdf"),
            item("ref/papers/older.md", "lib/papers/older.pdf"),
            item("ref/blogs/collision.md", "lib/blogs/collision.pdf", kind: .article),
        ]
        let tabs = [
            tab("older.pdf", ordinal: 0, itemID: items[2].id, match: .fileName),
            tab("unmatched.pdf", ordinal: 1),
            tab("current.pdf", ordinal: 2, itemID: items[0].id, current: true, match: .path),
            tab("collision.pdf", ordinal: 3, candidates: [items[3].id], match: .collision),
            tab("recent.pdf", ordinal: 4, itemID: items[1].id, match: .fileName),
        ]
        var recency = RefsTabRecency()
        recency.touch(fileName: "older.pdf", at: Date(timeIntervalSince1970: 10))
        recency.touch(fileName: "recent.pdf", at: Date(timeIntervalSince1970: 30))
        let signals = RefsSignals()

        let all = RefsTabsRanker.listing(
            tabs: tabs,
            items: items,
            query: "",
            scope: .all,
            signals: signals,
            recency: recency,
            highlightsIsFrontmost: true
        )
        XCTAssertEqual(all.listing.orderedIDs, [
            items[0].id,
            items[1].id,
            items[2].id,
            tabs[3].rowID,
            tabs[1].rowID,
        ])
        XCTAssertEqual(all.listing.sections.map(\.kind), [.inHighlights])
        XCTAssertEqual(all.listing.sections[0].kind?.title, "In Highlights")
        XCTAssertEqual(all.preselectedID, items[0].id)
        XCTAssertEqual(all.currentID, items[0].id)

        let papers = RefsTabsRanker.listing(
            tabs: tabs,
            items: items,
            query: "",
            scope: .papers,
            signals: signals,
            recency: recency,
            highlightsIsFrontmost: false
        )
        XCTAssertEqual(papers.listing.orderedIDs, [items[0].id, items[1].id, items[2].id])
        XCTAssertEqual(papers.preselectedID, items[0].id)
        XCTAssertEqual(papers.currentID, items[0].id)
        XCTAssertEqual(
            RefsExplanation.whyHere(items[0], listing: all.listing, signals: signals),
            "Current tab in Highlights"
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(items[1], listing: all.listing, signals: signals),
            "Open in Highlights"
        )
    }

    func testCurrentIDNilWhenCurrentRowOutOfScope() {
        let current = item("ref/blogs/current.md", "lib/blogs/current.pdf", kind: .article)
        let other = item("ref/papers/other.md", "lib/papers/other.pdf")
        let tabs = [
            tab("current.pdf", ordinal: 0, itemID: current.id, current: true, match: .path),
            tab("other.pdf", ordinal: 1, itemID: other.id, match: .fileName),
        ]
        let result = RefsTabsRanker.listing(
            tabs: tabs,
            items: [current, other],
            query: "",
            scope: .papers,
            signals: RefsSignals(),
            recency: RefsTabRecency(),
            highlightsIsFrontmost: true
        )
        XCTAssertEqual(result.listing.orderedIDs, [other.id])
        XCTAssertEqual(result.preselectedID, other.id)
        XCTAssertNil(result.currentID)
    }

    func testMatcherSetsPageNumberOnlyOnSelectedTabs() {
        let one = item("ref/papers/one.md", "lib/papers/one.pdf")
        let two = item("ref/papers/two.md", "lib/papers/two.pdf")
        let snapshot = HighlightsTabsSnapshot(
            windows: [
                .init(
                    isMain: true,
                    pageCaption: "p. 5/25",
                    pageNumber: 5,
                    tabs: [
                        .init(fileName: "one.pdf", documentPath: "/fixture-vault/lib/papers/one.pdf", isSelected: true),
                        .init(fileName: "two.pdf", documentPath: "/fixture-vault/lib/papers/two.pdf", isSelected: false),
                    ]
                ),
                .init(
                    isMain: false,
                    pageCaption: "p. 9/10",
                    pageNumber: 9,
                    tabs: [
                        .init(fileName: "two.pdf", documentPath: "/fixture-vault/lib/papers/two.pdf", isSelected: true),
                    ]
                ),
            ],
            highlightsIsFrontmost: true
        )
        let matched = HighlightsTabMatcher.match(snapshot, items: [one, two], vaultRoot: vaultRoot)
        let selectedByWindow = Dictionary(grouping: matched, by: { $0.windowOrdinal })
        XCTAssertEqual(selectedByWindow[0]?.first(where: { $0.tabOrdinal == 0 })?.pageNumber, 5)
        XCTAssertNil(selectedByWindow[0]?.first(where: { $0.tabOrdinal == 1 })?.pageNumber)
    }

    func testTabsSearchRanksMatchedAndSyntheticTitlesAndCounts() {
        let matched = item("ref/papers/harness.md", "lib/papers/harness.pdf", title: "Harness")
        let rows = [
            tab("harness.pdf", ordinal: 0, itemID: matched.id, match: .fileName),
            tab("harness_engineering.pdf", ordinal: 1),
            tab("other.pdf", ordinal: 2),
        ]
        let result = RefsTabsRanker.listing(
            tabs: rows,
            items: [matched],
            query: "harness",
            scope: .all,
            signals: RefsSignals(),
            recency: RefsTabRecency(),
            highlightsIsFrontmost: false
        )

        XCTAssertEqual(result.listing.orderedIDs, [rows[0].rowID, rows[1].rowID])
        XCTAssertEqual(result.listing.sections.map(\.kind), [nil])
        XCTAssertEqual(result.preselectedID, rows[0].rowID)
        XCTAssertEqual(RefsTabsCount.text(shown: 9, total: 9, isSearch: false), "9 tabs")
        XCTAssertEqual(RefsTabsCount.text(shown: 1, total: 1, isSearch: false), "1 tab")
        XCTAssertEqual(RefsTabsCount.text(shown: 2, total: 9, isSearch: true), "2 of 9 tabs")
    }

    @MainActor
    func testSessionRefreshTouchesCurrentAndSelectRecordsRecency() async {
        let snapshot = HighlightsTabsSnapshot(
            windows: [.init(isMain: true, tabs: [
                .init(fileName: "current.pdf", isSelected: true),
            ])],
            highlightsIsFrontmost: true
        )
        let now = Date(timeIntervalSince1970: 42)
        let reader = FakeTabsReader(readResult: .snapshot(snapshot), selectResult: .selected)
        let session = HighlightsTabsSession(reader: reader, now: { now })

        let refreshResult = await session.refresh()
        XCTAssertEqual(refreshResult, .snapshot(snapshot))
        XCTAssertEqual(session.lastSnapshot, snapshot)
        XCTAssertEqual(session.recency.lastActive("current.pdf"), now)
        let selected = await session.select(tab("other.pdf"))
        XCTAssertEqual(selected, .selected)
        XCTAssertEqual(session.recency.lastActive("other.pdf"), now)
    }

    @MainActor
    func testSessionDropsOlderRefreshAndDoesNotReadWhenUntrusted() async {
        let oldSnapshot = HighlightsTabsSnapshot(
            windows: [.init(isMain: true, tabs: [.init(fileName: "old.pdf", isSelected: true)])],
            highlightsIsFrontmost: false
        )
        let newSnapshot = HighlightsTabsSnapshot(
            windows: [.init(isMain: true, tabs: [.init(fileName: "new.pdf", isSelected: true)])],
            highlightsIsFrontmost: false
        )
        let barrier = ReadBarrier()
        let reader = FakeTabsReader(readHandler: { await barrier.read() })
        let session = HighlightsTabsSession(reader: reader)
        let oldRefresh = Task { @MainActor in await session.refresh() }
        await barrier.waitUntilStarted(1)
        let newRefresh = Task { @MainActor in await session.refresh() }
        await barrier.waitUntilStarted(2)
        await barrier.resolve(1, with: .snapshot(newSnapshot))
        _ = await newRefresh.value
        await barrier.resolve(0, with: .snapshot(oldSnapshot))
        let staleResult = await oldRefresh.value

        XCTAssertNil(staleResult)
        XCTAssertEqual(session.lastSnapshot, newSnapshot)

        let untrustedReader = FakeTabsReader(
            trusted: false,
            readResult: .snapshot(oldSnapshot)
        )
        let untrustedSession = HighlightsTabsSession(reader: untrustedReader)
        await untrustedSession.sampleCurrentTab()
        XCTAssertEqual(untrustedReader.readCount, 0)
        XCTAssertNil(untrustedSession.recency.lastActive("old.pdf"))
    }
}

private final class FakeTabsReader: HighlightsTabsReading, @unchecked Sendable {
    private let trusted: Bool
    private let staticSelectResult: HighlightsTabSelectResult
    private let readHandler: @Sendable () async -> HighlightsTabsReadResult
    private let lock = NSLock()
    private var reads = 0

    init(
        trusted: Bool = true,
        readResult: HighlightsTabsReadResult = .notRunning,
        selectResult: HighlightsTabSelectResult = .notFound,
        readHandler: (@Sendable () async -> HighlightsTabsReadResult)? = nil
    ) {
        self.trusted = trusted
        staticSelectResult = selectResult
        self.readHandler = readHandler ?? { readResult }
    }

    var readCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return reads
    }

    func isTrusted() -> Bool { trusted }
    func requestTrust() {}

    func read() async -> HighlightsTabsReadResult {
        incrementReadCount()
        return await readHandler()
    }

    func select(_ target: HighlightsTabTarget) async -> HighlightsTabSelectResult {
        staticSelectResult
    }

    private func incrementReadCount() {
        lock.lock()
        reads += 1
        lock.unlock()
    }
}

private actor ReadBarrier {
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
