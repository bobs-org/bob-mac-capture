import Foundation
import XCTest

@testable import BobMacCapture
@testable import CaptureCore
@testable import RefsCore

/// Panel model tests against fake-bob plus a fake opener, locator, and
/// Spotlight provider: presentation, query and scope edits, frozen
/// listings under late library updates, open dispatch and banners,
/// navigation and editing, and open history.
@MainActor
final class RefsPanelModelTests: XCTestCase {
    func testPrepareSelectsFirstRowOfFirstSection() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()

        harness.model.prepareForPresentation()

        XCTAssertEqual(harness.model.query, "")
        XCTAssertEqual(harness.model.scope, .all)
        XCTAssertEqual(harness.model.selectedID, harness.model.listing.orderedIDs.first)
        XCTAssertNotNil(harness.model.selectedID)
        XCTAssertNil(harness.model.banner)
    }

    func testQueryEditRanksAndSelectsFirst() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()

        harness.model.query = "reading"
        harness.model.queryDidChange()

        guard case .search = harness.model.listing.mode else {
            XCTFail("expected search mode")
            return
        }
        XCTAssertEqual(harness.model.selectedID, harness.model.listing.orderedIDs.first)
        XCTAssertEqual(harness.model.selectedID, "ref/chat/small_reading.md")
    }

    func testScopeFiltersAndSelectsFirst() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()

        XCTAssertTrue(harness.model.perform(.setScope(.chats)))
        XCTAssertEqual(harness.model.listing.orderedIDs, ["ref/chat/small_reading.md"])
        XCTAssertEqual(harness.model.selectedID, "ref/chat/small_reading.md")
    }

    func testPresentedRefreshUpdatesContentWithoutReordering() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let before = harness.model.listing.orderedIDs
        XCTAssertTrue(before.contains("ref/papers/small_ready.md"))

        XCTAssertTrue(harness.model.perform(.select(id: "ref/papers/small_ready.md")))
        try harness.retireFixtureRow(path: "ref/papers/small_ready.md")
        harness.library.refresh(reason: .manual)
        await harness.waitForSnapshot(ids: Set(before).subtracting(["ref/papers/small_ready.md"]))

        await harness.waitForModel { model in
            model.unavailableIDs.contains("ref/papers/small_ready.md")
        }
        XCTAssertEqual(
            harness.model.listing.orderedIDs,
            before.filter { $0 != "ref/papers/small_ready.md" }
        )
        XCTAssertEqual(harness.model.selectedID, "ref/papers/small_ready.md")

        let dismissedBefore = harness.dismissed
        XCTAssertTrue(harness.model.perform(.open(.highlights)))
        XCTAssertEqual(harness.dismissed, dismissedBefore)
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        XCTAssertNotNil(harness.model.banner)
    }

    func testOpenHidesDispatchesAndRecords() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.highlights)))

        XCTAssertEqual(harness.dismissed, 1)
        XCTAssertEqual(harness.opener.highlightsOpens.count, 1)
        XCTAssertEqual(
            harness.opener.highlightsOpens.first?.pdf.path,
            harness.vault.appendingPathComponent("lib/chat/small_reading.pdf").path
        )
        XCTAssertEqual(harness.opener.highlightsOpens.first?.app, harness.highlightsURL)
        await harness.waitForOpens(id: "ref/chat/small_reading.md", count: 1)
        XCTAssertNil(harness.model.banner)
    }

    func testHighlightsErrorRepresentsWithBannerAndKeepsQuery() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()
        harness.opener.highlightsError = NSError(
            domain: "RefsPanelModelTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "busy"]
        )

        XCTAssertTrue(harness.model.perform(.open(.highlights)))

        XCTAssertEqual(harness.dismissed, 1)
        await harness.waitForModel { $0.banner != nil }
        XCTAssertEqual(harness.presented, 1)
        XCTAssertEqual(harness.model.query, "reading")
        XCTAssertEqual(harness.model.selectedID, "ref/chat/small_reading.md")
        XCTAssertTrue(harness.model.banner?.message.contains("busy") ?? false)
        XCTAssertEqual(harness.model.banner?.actions, [.tryAgain, .openInDefaultApp])
        XCTAssertEqual(harness.library.signals.opens.count("ref/chat/small_reading.md"), 0)
    }

    func testMissingPDFOpensNoteAndRecordsNothing() async throws {
        let harness = try makeHarness(missing: ["lib/chat/small_reading.pdf"])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.highlights)))

        XCTAssertEqual(harness.opener.noteOpens.count, 1)
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        XCTAssertEqual(harness.library.signals.opens.count("ref/chat/small_reading.md"), 0)
    }

    func testHighlightsNotFoundShowsBannerAndStays() async throws {
        let harness = try makeHarness(highlightsURL: nil)
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()

        XCTAssertTrue(harness.model.perform(.open(.highlights)))

        XCTAssertEqual(harness.dismissed, 0)
        XCTAssertNotNil(harness.model.banner)
        XCTAssertTrue(harness.model.banner?.message.contains("Highlights") ?? false)
        XCTAssertEqual(harness.model.banner?.actions, [.openInDefaultApp, .chooseHighlights])
        XCTAssertEqual(harness.model.query, "reading")
    }

    func testNoteAndRevealNeverRecord() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.note)))
        XCTAssertTrue(harness.model.perform(.open(.reveal)))

        XCTAssertEqual(harness.opener.noteOpens.count, 1)
        XCTAssertEqual(harness.opener.reveals.count, 1)
        XCTAssertEqual(harness.dismissed, 0)
        XCTAssertEqual(harness.library.signals.opens.count("ref/chat/small_reading.md"), 0)
    }

    func testDefaultAppOpenRecords() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.defaultApp)))

        XCTAssertEqual(harness.dismissed, 1)
        XCTAssertEqual(harness.opener.defaultAppOpens.count, 1)
        await harness.waitForOpens(id: "ref/chat/small_reading.md", count: 1)
    }

    func testEscChainOrder() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()
        XCTAssertTrue(harness.model.perform(.setScope(.chats)))
        harness.model.installForPreviews(
            items: harness.library.items,
            signals: harness.library.signals,
            query: "re",
            scope: .chats,
            selectedID: harness.model.selectedID,
            banner: RefsBanner(kind: .error, message: "boom", actions: [.retry]),
            refreshState: .idle
        )

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertNil(harness.model.banner)
        XCTAssertEqual(harness.model.query, "re")

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.model.query, "")

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.model.scope, .all)

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.dismissed, 1)
    }

    func testDeleteBackwardOnEmptyRemovesScope() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.setScope(.chats)))

        XCTAssertTrue(harness.model.perform(.deleteBackwardOnEmpty))
        XCTAssertEqual(harness.model.scope, .all)
        XCTAssertFalse(harness.model.perform(.deleteBackwardOnEmpty))

        harness.model.query = "x"
        XCTAssertTrue(harness.model.perform(.setScope(.chats)))
        XCTAssertFalse(harness.model.perform(.deleteBackwardOnEmpty))
    }

    func testNavigationWrapsAndClamps() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let ids = harness.model.listing.orderedIDs
        XCTAssertGreaterThan(ids.count, 2)

        XCTAssertTrue(harness.model.perform(.select(id: ids.last!)))
        XCTAssertTrue(harness.model.perform(.move(.next)))
        XCTAssertEqual(harness.model.selectedID, ids.first)
        XCTAssertTrue(harness.model.perform(.move(.previous)))
        XCTAssertEqual(harness.model.selectedID, ids.last)

        XCTAssertTrue(harness.model.perform(.move(.first)))
        XCTAssertEqual(harness.model.selectedID, ids.first)
        XCTAssertTrue(harness.model.perform(.move(.last)))
        XCTAssertEqual(harness.model.selectedID, ids.last)

        harness.model.visibleRowBudget = 3
        XCTAssertTrue(harness.model.perform(.move(.first)))
        XCTAssertTrue(harness.model.perform(.move(.pageDown)))
        XCTAssertEqual(harness.model.selectedID, ids[2])
        XCTAssertTrue(harness.model.perform(.move(.pageDown)))
        XCTAssertEqual(harness.model.selectedID, ids[4])
        XCTAssertTrue(harness.model.perform(.move(.pageDown)))
        XCTAssertEqual(harness.model.selectedID, ids.last)
    }

    func testSectionJumpsWorkInBrowseAndRestInSearch() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertGreaterThan(harness.model.listing.sections.count, 1)

        XCTAssertTrue(harness.model.perform(.move(.first)))
        let first = harness.model.selectedID
        XCTAssertTrue(harness.model.perform(.move(.nextSection)))
        XCTAssertNotEqual(harness.model.selectedID, first)
        let secondSectionFirst = harness.model.listing.sections[1].ids.first
        XCTAssertEqual(harness.model.selectedID, secondSectionFirst)

        harness.model.query = "small"
        harness.model.queryDidChange()
        let searchSelected = harness.model.selectedID
        XCTAssertTrue(harness.model.perform(.move(.nextSection)))
        XCTAssertEqual(harness.model.selectedID, searchSelected)
    }

    func testResetOpenHistoryClearsStats() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))
        XCTAssertTrue(harness.model.perform(.open(.highlights)))
        await harness.waitForOpens(id: "ref/chat/small_reading.md", count: 1)

        harness.library.resetOpenHistory()
        XCTAssertEqual(harness.library.signals.opens.count("ref/chat/small_reading.md"), 0)
    }

    func testRowContent() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let id = harness.model.listing.orderedIDs.first!

        let content = harness.model.rowContent(for: id)
        XCTAssertNotNil(content?.item)
        XCTAssertFalse(content?.caption.isEmpty ?? true)
        XCTAssertFalse(content?.whyHere.isEmpty ?? true)
        XCTAssertFalse(content?.isUnavailable ?? true)
        XCTAssertNil(harness.model.rowContent(for: "ref/chat/missing.md"))
    }

    func testRefreshReranks() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()

        XCTAssertTrue(harness.model.perform(.refresh))
    }

    // MARK: - Harness

    @MainActor
    fileprivate final class Harness {
        let library: RefsLibrary
        let model: RefsPanelModel
        let opener: FakeOpener
        let vault: URL
        let highlightsURL: URL?
        nonisolated(unsafe) var dismissed = 0
        nonisolated(unsafe) var presented = 0

        init(
            library: RefsLibrary,
            model: RefsPanelModel,
            opener: FakeOpener,
            vault: URL,
            highlightsURL: URL?
        ) {
            self.library = library
            self.model = model
            self.opener = opener
            self.vault = vault
            self.highlightsURL = highlightsURL
        }

        func waitForSnapshot(ids: Set<String>? = nil) async {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if library.hasSnapshot, library.lastSuccessAt != nil {
                    if let ids {
                        if Set(library.items.map(\.id)) == ids {
                            return
                        }
                    } else if !library.items.isEmpty {
                        return
                    }
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("snapshot not ready before timeout")
        }

        func waitForOpens(id: String, count: Int) async {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if library.signals.opens.count(id) == count {
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("open not recorded before timeout")
        }

        func waitForModel(_ condition: @MainActor (RefsPanelModel) -> Bool) async {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if condition(model) {
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("model condition not met before timeout")
        }
    }

    private func makeHarness(
        highlightsURL: URL? = URL(fileURLWithPath: "/Applications/Highlights.app"),
        missing: Set<String> = []
    ) throws -> Harness {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let vault = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("ref"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: vault.appendingPathComponent("lib"),
            withIntermediateDirectories: true
        )
        let library = RefsLibrary(
            fetcher: BobRefsFetcher(client: try bobClient(environment: [:])),
            snapshotStore: RefsSnapshotStore(
                fileURL: root.appendingPathComponent("refs-snapshot.json")
            ),
            openLogStore: RefsOpenLogStore(
                fileURL: root.appendingPathComponent("refs-open-log.json")
            ),
            vaultRoot: { vault },
            fileExists: { url in !missing.contains(where: { url.path.hasSuffix($0) }) },
            spotlight: FakeSpotlight(),
            now: { Date() }
        )
        let opener = FakeOpener()
        let locator = FakeLocator(appURL: highlightsURL)
        let model = RefsPanelModel(library: library, opener: opener, highlights: locator)
        let harness = Harness(
            library: library,
            model: model,
            opener: opener,
            vault: vault,
            highlightsURL: highlightsURL
        )
        model.panelDismisser = { [weak harness] in harness?.dismissed += 1 }
        model.panelPresenter = { [weak harness] in harness?.presented += 1 }
        // Kick off the snapshot refresh every test waits for: nothing in the
        // model triggers one on its own.
        library.refresh(reason: .manual)
        return harness
    }

    private func bobClient(environment: [String: String]) throws -> BobProcessClient {
        BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
                .merging(environment) { _, override in override }
        )
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }
}

private extension RefsPanelModelTests.Harness {
    func retireFixtureRow(path: String) throws {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/refs-list.json")
        )
        var document = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let refs = (document["refs"] as! [[String: Any]]).filter {
            ($0["path"] as! String) != path
        }
        document["refs"] = refs
        let retired = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try JSONSerialization.data(withJSONObject: document).write(to: retired)
        library.setFetcher(
            BobRefsFetcher(client: try client(environment: [
                "FAKE_BOB_REFS_LIST_FIXTURE": retired.path,
            ]))
        )
    }

    func client(environment: [String: String]) throws -> BobProcessClient {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return BobProcessClient(
            executablePath: packageRoot
                .appendingPathComponent("Tests/Fixtures/fake-bob")
                .path,
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
                .merging(environment) { _, override in override }
        )
    }
}

final class FakeOpener: RefsOpening, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var highlightsOpens: [(pdf: URL, app: URL)] = []
    private(set) var noteOpens: [URL] = []
    private(set) var reveals: [URL] = []
    private(set) var defaultAppOpens: [URL] = []
    var highlightsError: Error?
    var defaultAppError: Error?

    func openInHighlights(
        _ pdf: URL,
        app: URL,
        completion: @escaping (Error?) -> Void
    ) {
        lock.withLock { highlightsOpens.append((pdf, app)) }
        completion(highlightsError)
    }

    func openNote(_ url: URL) {
        lock.withLock { noteOpens.append(url) }
    }

    func reveal(_ url: URL) {
        lock.withLock { reveals.append(url) }
    }

    func openWithDefaultApp(_ url: URL, completion: @escaping (Error?) -> Void) {
        lock.withLock { defaultAppOpens.append(url) }
        completion(defaultAppError)
    }
}

struct FakeLocator: RefsHighlightsLocating, Sendable {
    var appURL: URL?

    func highlightsAppURL() -> URL? {
        appURL
    }
}
