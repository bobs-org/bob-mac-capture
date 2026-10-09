import AppKit
import Foundation
import XCTest

@testable import BobMacCapture
@testable import RefsCore

/// Inspector tests: the loader cancels on selection changes and
/// caches `ref show` results, the show-failure path keeps the basic
/// column, the ⌘K menu varies with `urls` and `audio`, and copies
/// write the expected pasteboard strings.
@MainActor
final class RefsInspectorLoaderTests: XCTestCase {
    func testLoaderCancelsStaleSelectionLoads() async throws {
        let fixtures = makeFixtures()
        let loader = RefsInspectorLoader(
            library: fixtures.library,
            intrinsics: fixtures.intrinsics
        )

        loader.request(fixtures.chat)
        loader.request(fixtures.paper)
        await waitForContent(loader, id: fixtures.paper.id)

        XCTAssertNil(loader.content(for: fixtures.chat.id))
        XCTAssertNotNil(loader.content(for: fixtures.paper.id))
        XCTAssertEqual(fixtures.fetcher.showPaths, [fixtures.paper.id])
    }

    func testLoaderCachesShowResults() async throws {
        let fixtures = makeFixtures()
        let loader = RefsInspectorLoader(
            library: fixtures.library,
            intrinsics: fixtures.intrinsics
        )

        loader.request(fixtures.paper)
        await waitForContent(loader, id: fixtures.paper.id)
        XCTAssertEqual(fixtures.fetcher.showPaths.count, 1)

        loader.request(fixtures.paper)
        await waitForCalls(fixtures.intrinsics, count: 2)
        XCTAssertEqual(fixtures.fetcher.showPaths.count, 1)
    }

    func testLoaderFeedsSignalsBack() async throws {
        let fixtures = makeFixtures()
        let loader = RefsInspectorLoader(
            library: fixtures.library,
            intrinsics: fixtures.intrinsics
        )

        loader.request(fixtures.paper)
        await waitForContent(loader, id: fixtures.paper.id)

        XCTAssertEqual(
            fixtures.library.signals.pageCounts[fixtures.paper.id],
            22
        )
        XCTAssertEqual(
            fixtures.library.signals.outlineHeadings[fixtures.paper.id],
            ["Method", "Results"]
        )
    }

    func testShowFailureKeepsBasicContent() async throws {
        let fixtures = makeFixtures()
        fixtures.fetcher.showError = RefsTestError.boom
        let loader = RefsInspectorLoader(
            library: fixtures.library,
            intrinsics: fixtures.intrinsics
        )

        loader.request(fixtures.paper)
        await waitForContent(loader, id: fixtures.paper.id)

        let content = try XCTUnwrap(loader.content(for: fixtures.paper.id))
        XCTAssertTrue(content.showFailed)
        XCTAssertEqual(content.notes, [])
        // The basic column still fills: pages and the outline land even
        // when `ref show` fails.
        XCTAssertEqual(content.pageCount, 22)
        XCTAssertEqual(content.outline, ["Method", "Results"])
    }

    func testActionsMenuVariesWithURLsAndAudio() throws {
        let fixtures = makeFixtures()

        let chatSections = RefsActionsMenu.sections(
            for: fixtures.chat,
            audioURL: nil
        )
        XCTAssertEqual(chatSections.count, 3)
        XCTAssertEqual(
            chatSections[1],
            [.copyWikiLink, .copyPDFPath]
        )

        let paperURL = fixtures.library.audioURL(for: fixtures.paper)
        XCTAssertNotNil(paperURL)
        let paperSections = RefsActionsMenu.sections(
            for: fixtures.paper,
            audioURL: paperURL
        )
        XCTAssertTrue(paperSections[1].contains(.copyWikiLink))
        XCTAssertTrue(paperSections[1].contains(.copyPDFPath))
        XCTAssertTrue(paperSections[1].contains(
            .openSourceURL(URL(string: "https://example.com/post")!)
        ))
        XCTAssertTrue(paperSections[1].contains(.openNarration(paperURL!)))
    }

    func testCopyWritesPasteboardStringsAndToasts() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        let library = RefsLibrary(
            fetcher: nil,
            snapshotStore: RefsSnapshotStore(
                fileURL: root.appendingPathComponent("refs-snapshot.json")
            ),
            openLogStore: RefsOpenLogStore(
                fileURL: root.appendingPathComponent("refs-open-log.json")
            ),
            vaultRoot: { vault },
            fileExists: { _ in true },
            spotlight: StubSpotlight(),
            now: { Date() }
        )
        let pasteboard = FakePasteboard()
        let model = RefsPanelModel(
            library: library,
            opener: StubOpener(),
            highlights: StubLocator(),
            pasteboard: pasteboard
        )
        let chat = RefItem(
            id: "ref/chat/today_report.md",
            link: "[[ref/chat/today_report]]",
            rawTitle: "Team Fit Review",
            stem: "team_fit_review",
            kind: .chat,
            state: .reading,
            isBlocked: false,
            pdfPath: "lib/chat/team_fit_review.pdf",
            parentLabel: "sase",
            isAgentReport: true
        )
        model.installForPreviews(
            items: [chat],
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: chat.id,
            banner: nil,
            refreshState: .idle
        )

        model.copyWikiLink()
        XCTAssertEqual(pasteboard.strings, ["[[ref/chat/today_report]]"])
        XCTAssertEqual(model.toast, "Copied wiki link")

        model.copyPDFPath()
        XCTAssertEqual(
            pasteboard.strings.last,
            vault.appendingPathComponent("lib/chat/team_fit_review.pdf").path
        )
        XCTAssertEqual(model.toast, "Copied PDF path")
    }

    func testShowActionsPresentsWhenARowIsSelected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let library = RefsLibrary(
            fetcher: nil,
            snapshotStore: RefsSnapshotStore(
                fileURL: root.appendingPathComponent("refs-snapshot.json")
            ),
            openLogStore: RefsOpenLogStore(
                fileURL: root.appendingPathComponent("refs-open-log.json")
            ),
            vaultRoot: { root.appendingPathComponent("vault") },
            fileExists: { _ in true },
            spotlight: StubSpotlight(),
            now: { Date() }
        )
        let model = RefsPanelModel(
            library: library,
            opener: StubOpener(),
            highlights: StubLocator()
        )
        // Nothing selected: the key passes through.
        XCTAssertFalse(model.perform(.showActions))

        let chat = RefItem(
            id: "ref/chat/today_report.md",
            link: "[[ref/chat/today_report]]",
            rawTitle: "Team Fit Review",
            stem: "team_fit_review",
            kind: .chat,
            state: .reading,
            isBlocked: false,
            pdfPath: "lib/chat/team_fit_review.pdf",
            parentLabel: "sase",
            isAgentReport: true
        )
        model.installForPreviews(
            items: [chat],
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: chat.id,
            banner: nil,
            refreshState: .idle
        )
        final class PresentationCount: @unchecked Sendable {
            var count = 0
        }
        let presented = PresentationCount()
        model.actionsPresenter = { presented.count += 1 }
        XCTAssertTrue(model.perform(.showActions))
        XCTAssertEqual(presented.count, 1)
    }

    // MARK: - Fixtures

    private struct FixtureSet {
        var library: RefsLibrary
        var fetcher: FakeRefsFetcher
        var intrinsics: StubIntrinsics
        var chat: RefItem
        var paper: RefItem
    }

    private func makeFixtures() -> FixtureSet {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        let fetcher = FakeRefsFetcher()
        let library = RefsLibrary(
            fetcher: fetcher,
            snapshotStore: RefsSnapshotStore(
                fileURL: root.appendingPathComponent("refs-snapshot.json")
            ),
            openLogStore: RefsOpenLogStore(
                fileURL: root.appendingPathComponent("refs-open-log.json")
            ),
            vaultRoot: { vault },
            fileExists: { _ in true },
            spotlight: StubSpotlight(),
            now: { Date() }
        )
        let chat = RefItem(
            id: "ref/chat/today_report.md",
            link: "[[ref/chat/today_report]]",
            rawTitle: "Team Fit Review",
            stem: "team_fit_review",
            kind: .chat,
            state: .reading,
            isBlocked: false,
            pdfPath: "lib/chat/team_fit_review.pdf",
            parentLabel: "sase",
            isAgentReport: true
        )
        let paper = RefItem(
            id: "ref/papers/harness_buy.md",
            link: "[[ref/papers/harness_buy]]",
            rawTitle: "What Does a Harness Buy You?",
            stem: "harness_buy",
            kind: .paper,
            state: .ready,
            isBlocked: false,
            pdfPath: "lib/papers/harness_buy.pdf",
            author: "Yangze Liu",
            audioPath: "lib/papers/harness_buy.m4a",
            urls: ["https://example.com/post"]
        )
        library.installSnapshotForPreviews(
            items: [chat, paper],
            signals: RefsSignals(),
            refreshState: .idle
        )
        let intrinsics = StubIntrinsics(result: RefsPDFIntrinsics(
            pageCount: 22,
            outlineHeadings: ["Method", "Results"],
            leadText: "Abstract\nWe study harness reuse.",
            wordEstimate: 22 * 230,
            thumbnailPNG: nil
        ))
        return FixtureSet(
            library: library,
            fetcher: fetcher,
            intrinsics: intrinsics,
            chat: chat,
            paper: paper
        )
    }

    private func waitForContent(
        _ loader: RefsInspectorLoader,
        id: String
    ) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if loader.content(for: id) != nil {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("inspector content not ready before timeout")
    }

    private func waitForCalls(
        _ intrinsics: StubIntrinsics,
        count: Int
    ) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if intrinsics.calls.count == count {
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("intrinsics calls not ready before timeout")
    }
}

enum RefsTestError: Error {
    case boom
}

final class FakeRefsFetcher: RefsFetching, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var showPaths: [String] = []
    var showError: Error?
    var showDelayNanoseconds: UInt64 = 50_000_000

    func list(gitDates: Bool) async throws -> RefsListResponse {
        RefsListResponse(schemaVersion: 1)
    }

    func plan() async throws -> RefsPlanResponse {
        RefsPlanResponse(schemaVersion: 2)
    }

    func show(path: String) async throws -> RefsShowResponse {
        lock.withLock { showPaths.append(path) }
        try await Task.sleep(nanoseconds: showDelayNanoseconds)
        if let showError {
            throw showError
        }
        return RefsShowResponse(schemaVersion: 1, refs: [RefsShowRow(
            path: path,
            annotations: [RefsShowAnnotation(
                pageLabel: "3",
                kind: "highlight",
                quote: "The pipeline drains while the child runs.",
                comment: "Key insight for the fetcher."
            )],
            tasks: [RefsShowTask(checked: false, mark: " ", text: "Follow up.")],
            annotationsStatus: "parsed"
        )])
    }
}

final class StubIntrinsics: RefsPDFIntrinsicsProviding, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var calls: [String] = []
    var result: RefsPDFIntrinsics

    init(result: RefsPDFIntrinsics) {
        self.result = result
    }

    func intrinsics(for pdfURL: URL, id: String) async -> RefsPDFIntrinsics {
        lock.withLock { calls.append(id) }
        return result
    }
}

final class FakePasteboard: RefsPasteboardWriting, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var strings: [String] = []

    func copy(_ string: String) {
        lock.withLock { strings.append(string) }
    }
}

private struct StubOpener: RefsOpening {
    func openInHighlights(
        _ pdf: URL,
        app: URL,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }

    func openNote(_ url: URL) {}

    func reveal(_ url: URL) {}

    func openWithDefaultApp(
        _ url: URL,
        completion: @escaping (Error?) -> Void
    ) {
        completion(nil)
    }
}

private struct StubLocator: RefsHighlightsLocating {
    func highlightsAppURL() -> URL? {
        nil
    }
}

private struct StubSpotlight: RefsSpotlightProviding {
    func sweep(
        _ requests: [RefsSpotlightRequest]
    ) async -> [String: RefsSpotlightFacts] {
        [:]
    }
}
