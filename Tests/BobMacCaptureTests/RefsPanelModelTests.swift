import AppKit
import Combine
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

    func testPrepareCountsEveryPresentation() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()

        XCTAssertEqual(harness.model.presentationCount, 0)
        harness.model.prepareForPresentation()
        harness.model.selectedRowRect = CGRect(x: 1, y: 2, width: 3, height: 4)
        XCTAssertEqual(harness.model.presentationCount, 1)
        harness.model.prepareForPresentation()
        XCTAssertEqual(harness.model.presentationCount, 2)
        // A fresh presentation clears the previous show's row anchor so
        // the ⌘K menu cannot pop at a stale frame before layout lands.
        XCTAssertNil(harness.model.selectedRowRect)
    }

    func testTodayLinkUsesBobDefaultStaysOpenAndOverlaysTodayPill() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-listing.json"),
            try todayLinkFixture("refs-today-linked.json"),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }
        var completed: (RefsTodayLinkToast, String)?
        harness.model.todayLinkCompletion = { toast, title in
            XCTAssertEqual(harness.model.pomodoroName(for: path), "CURRENT")
            completed = (toast, title)
        }

        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        XCTAssertEqual(harness.model.todayLinkCard?.selectedPomodoro?.name, "CURRENT")
        harness.model.handleTodayLinkCardKey(.submit)

        await harness.waitForModel { $0.todayLinkCard == nil }
        XCTAssertEqual(harness.model.selectedID, path)
        XCTAssertEqual(fetcher.todayLinkCalls.map(\.notePath), [path, path])
        XCTAssertEqual(fetcher.todayLinkCalls.map(\.dryRun), [true, false])
        XCTAssertEqual(fetcher.todayLinkCalls.first?.selector, .automatic)
        XCTAssertEqual(completed?.0.title, "Linked under CURRENT")
        XCTAssertEqual(completed?.0.style, .linked)
        XCTAssertEqual(completed?.1, "Rename test reference")
    }

    func testDelayedListingFailureCannotUnlockFastPathWrite() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        let gate = TodayLinkResponseGate()
        fetcher.todayLinkHandler = { _, _, _ in try await gate.respond() }
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }
        var completions = 0
        harness.model.todayLinkCompletion = { _, _ in completions += 1 }

        harness.model.openTodayLinkCard()
        await gate.waitForRequests(1)
        harness.model.handleTodayLinkCardKey(.submit)
        await gate.waitForRequests(2)
        await gate.resolve(0, with: .failure(RefsTestError.boom))
        await gate.waitForCompletion(0)
        await Task.yield()
        XCTAssertEqual(harness.model.todayLinkCard?.phase, .running)
        XCTAssertTrue(harness.model.perform(.escape))
        harness.model.handleTodayLinkCardKey(.cancel)
        XCTAssertEqual(harness.model.todayLinkCard?.phase, .running)

        await gate.resolve(1, with: .success(try todayLinkFixture("refs-today-linked.json")))
        await harness.waitForModel { $0.todayLinkCard == nil }
        XCTAssertEqual(fetcher.todayLinkCalls.filter { !$0.dryRun }.count, 1)
        XCTAssertEqual(completions, 1)
    }

    func testStaleReloadBlocksOldChoicesUntilFreshRowsArrive() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        let gate = TodayLinkResponseGate()
        fetcher.todayLinkHandler = { _, _, _ in try await gate.respond() }
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.todayLinkPreviewDebounce = {}
        harness.model.openTodayLinkCard()
        await gate.waitForRequests(1)
        await gate.resolve(0, with: .success(try todayLinkFixture("refs-today-listing.json")))
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.selectTodayLinkRow(1)
        harness.model.handleTodayLinkCardKey(.submit)
        await gate.resolve(1, with: .success(try todayLinkFixture("refs-today-stale-pomodoro.json")))
        await gate.waitForRequests(3)
        XCTAssertEqual(harness.model.todayLinkCard?.phase, .reloading)
        XCTAssertEqual(harness.model.todayLinkCard?.query, "")
        XCTAssertEqual(harness.model.todayLinkCard?.pomodoros, [])
        harness.model.editTodayLinkQuery("rea")
        harness.model.handleTodayLinkCardKey(.submit)
        XCTAssertEqual(harness.model.todayLinkCard?.phase, .reloading)
        XCTAssertEqual(fetcher.todayLinkCalls.filter { !$0.dryRun }.count, 1)
        await gate.resolve(2, with: .success(try todayLinkFixture("refs-today-listing.json")))
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        XCTAssertEqual(harness.model.todayLinkCard?.query, "rea")
        XCTAssertEqual(harness.model.todayLinkCard?.selectedPomodoro?.name, "READING")
        harness.model.handleTodayLinkCardKey(.submit)
        await harness.waitForModel { $0.todayLinkCard?.phase == .running }
        XCTAssertEqual(fetcher.todayLinkCalls.last?.selector, .entry(ref: "4:ddf7159c"))
        await gate.waitForRequests(4)
        await gate.resolve(3, with: .success(try todayLinkFixture("refs-today-linked.json")))
    }

    func testBobRefusalFixturesStayRefusedWithoutSubmittingWrites() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-no-reading-task.json"),
            try todayLinkFixture("refs-today-reading-task-closed.json"),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()

        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .refused(
            message: "reference ref/papers/attention.md has no reading task",
            hint: "legacy trackerless refs cannot be planned for today"
        ) }
        XCTAssertTrue(harness.model.perform(.escape))

        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .refused(
            message: "reading task is already read", hint: nil
        ) }
        XCTAssertEqual(fetcher.todayLinkCalls.map(\.dryRun), [true, true])
    }

    func testAtoBtoAPreviewErrorsCannotReplaceLatestPreviewOrWrite() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        let gate = TodayLinkResponseGate()
        fetcher.todayLinkHandler = { _, _, _ in try await gate.respond() }
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.todayLinkPreviewDebounce = {}
        harness.model.openTodayLinkCard()
        await gate.waitForRequests(1)
        await gate.resolve(0, with: .success(try todayLinkFixture("refs-today-listing.json")))
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }

        harness.model.editTodayLinkQuery("cur")
        await gate.waitForRequests(2)
        harness.model.editTodayLinkQuery("rea")
        await gate.waitForRequests(3)
        harness.model.editTodayLinkQuery("cur")
        await gate.waitForRequests(4)
        await gate.resolve(2, with: .success(try todayLinkFixture("refs-today-listing.json")))
        await gate.resolve(3, with: .success(try todayLinkFixture("refs-today-listing.json")))
        await harness.waitForModel {
            $0.todayLinkCard?.previewPending == false
                && $0.todayLinkCard?.preview?.capture?.pomodoroName == "CURRENT"
        }
        XCTAssertEqual(harness.model.todayLinkCard?.query, "cur")
        XCTAssertEqual(harness.model.todayLinkCard?.preview?.capture?.pomodoroName, "CURRENT")

        harness.model.editTodayLinkQuery("rea")
        await gate.waitForRequests(5)
        harness.model.handleTodayLinkCardKey(.submit)
        await gate.waitForRequests(6)
        await gate.resolve(1, with: .failure(RefsTestError.boom))
        await gate.resolve(4, with: .success(try todayLinkFixture("refs-today-listing.json")))
        await gate.waitForCompletion(1)
        await gate.waitForCompletion(4)
        await Task.yield()
        XCTAssertEqual(harness.model.todayLinkCard?.phase, .running)
        XCTAssertEqual(fetcher.todayLinkCalls.last?.selector, .entry(ref: "4:ddf7159c"))
        await gate.resolve(5, with: .success(try todayLinkFixture("refs-today-linked.json")))
        await harness.waitForModel { $0.todayLinkCard == nil }
        XCTAssertEqual(fetcher.todayLinkCalls.filter { !$0.dryRun }.count, 1)
    }

    func testClosingAndReopeningDropsOutOfOrderListingResults() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        let gate = TodayLinkResponseGate()
        fetcher.todayLinkHandler = { _, _, _ in try await gate.respond() }
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        var failures: [String] = []
        harness.model.todayLinkFailureNotifier = { message, _ in failures.append(message) }

        harness.model.openTodayLinkCard()
        await gate.waitForRequests(1)
        harness.model.handleTodayLinkCardKey(.cancel)
        XCTAssertNil(harness.model.todayLinkCard)
        harness.model.openTodayLinkCard()
        await gate.waitForRequests(2)
        await gate.resolve(1, with: .success(try todayLinkFixture("refs-today-listing.json")))
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        await gate.resolve(0, with: .failure(RefsTestError.boom))
        await gate.waitForCompletion(0)
        await Task.yield()
        XCTAssertEqual(harness.model.todayLinkCard?.phase, .ready)
        XCTAssertTrue(failures.isEmpty)
    }

    func testReturnSubmitsWithoutWaitingForDebouncedPreview() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        let gate = TodayLinkResponseGate()
        fetcher.todayLinkHandler = { _, _, _ in try await gate.respond() }
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.todayLinkPreviewDebounce = {
            try await Task.sleep(for: .seconds(3_600))
        }
        harness.model.openTodayLinkCard()
        await gate.waitForRequests(1)
        await gate.resolve(0, with: .success(try todayLinkFixture("refs-today-listing.json")))
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.editTodayLinkQuery("rea")
        harness.model.handleTodayLinkCardKey(.submit)
        await gate.waitForRequests(2)
        XCTAssertEqual(fetcher.todayLinkCalls.count, 2)
        XCTAssertEqual(fetcher.todayLinkCalls.map(\.dryRun), [true, false])
        XCTAssertEqual(fetcher.todayLinkCalls.last?.selector, .entry(ref: "4:ddf7159c"))
        await gate.resolve(1, with: .success(try todayLinkFixture("refs-today-linked.json")))
        await harness.waitForModel { $0.todayLinkCard == nil }
    }

    func testFailedCardRowTapRecoversAndFailureRefocusesField() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-listing.json"),
            RefsTodayLinkResponse(
                ok: false,
                error: RefsTodayLinkFailure(
                    code: "note_changed", message: "The note changed", hint: "Try again"
                )
            ),
            try todayLinkFixture("refs-today-linked.json"),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.todayLinkPreviewDebounce = {}
        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        let beforeFocus = harness.model.todayLinkCardGeneration
        harness.model.handleTodayLinkCardKey(.submit)
        await harness.waitForModel { $0.todayLinkCard?.phase.isFailed == true }
        XCTAssertGreaterThan(harness.model.todayLinkCardGeneration, beforeFocus)
        harness.model.todayLinkRowTapped(0)
        await harness.waitForModel { $0.todayLinkCard == nil }
        XCTAssertEqual(fetcher.todayLinkCalls.filter { !$0.dryRun }.count, 2)
    }

    func testUnselectableReturnAndCommandNBeepAndHiddenWriteNotifiesOnce() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-multiple-running.json"),
            try todayLinkFixture("refs-today-linked.json"),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        var beeps = 0
        var notifications: [(RefsTodayLinkResponse, String)] = []
        harness.model.todayLinkBeep = { beeps += 1 }
        harness.model.todayLinkNotifier = { response, title in notifications.append((response, title)) }
        harness.model.panelIsVisible = { false }
        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.handleTodayLinkCardKey(.submit)
        if let command = harness.model.todayLinkCardKeyCommand(
            keyCode: 45, modifiers: [.command, .capsLock], hasMarkedText: false
        ) {
            harness.model.handleTodayLinkCardKey(command)
        }
        XCTAssertEqual(beeps, 2)
        harness.model.selectTodayLinkRow(0)
        harness.model.handleTodayLinkCardKey(.submit)
        harness.model.panelDidHide()
        await harness.waitForModel { $0.todayLinkCard == nil }
        XCTAssertEqual(notifications.count, 1)
        XCTAssertEqual(fetcher.todayLinkCalls.filter { !$0.dryRun }.count, 1)
    }

    func testTodayLinkRefreshesTaskSnapshotTodayAndDiscardsInspectorCache() async throws {
        let path = "ref/blogs/today_link_test.md"
        let original = Self.renameRecord(path: path, stem: "today_link_test")
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(schemaVersion: 1, refs: [original])
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-listing.json"),
            try todayLinkFixture("refs-today-linked.json"),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }
        let oldItem = try XCTUnwrap(harness.library.items.first)
        let cached = RefsShowRow(path: path, ownNotes: "cached before link")
        harness.model.inspectorLoader.installShowRowForPreviews(cached, for: oldItem)
        XCTAssertEqual(harness.model.inspectorLoader.cachedShowRow(for: oldItem), cached)
        let snapshotGeneration = harness.library.snapshotRefreshGeneration
        let todayGeneration = harness.library.todayRefreshGeneration
        harness.model.todayLinkCompletion = { _, _ in
            fetcher.listResponse = RefsListResponse(schemaVersion: 1, refs: [
                RefRecord(
                    path: path,
                    link: original.link,
                    title: original.title,
                    refType: original.refType,
                    status: original.status,
                    readingState: original.readingState,
                    task: RefTask(
                        path: "sase.md", blockID: "ref-attention",
                        link: "[[sase#^ref-attention]]", mark: "*"
                    ),
                    sourcePDF: original.sourcePDF
                ),
            ])
            fetcher.planResponse = RefsPlanResponse(schemaVersion: 2, todayTasks: [
                RefsPlanTodayTask(
                    path: "sase.md", blockID: "ref-attention",
                    entryName: "CURRENT", statusSymbol: "*"
                ),
            ])
        }
        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.handleTodayLinkCardKey(.submit)
        await harness.waitForModel { _ in
            harness.library.snapshotRefreshGeneration > snapshotGeneration
                && harness.library.todayRefreshGeneration > todayGeneration
                && harness.model.pomodoroName(for: path) == "CURRENT"
        }
        XCTAssertEqual(harness.library.items.first?.task?.mark, "*")
        XCTAssertEqual(harness.library.signals.today.entry(for: try XCTUnwrap(harness.library.items.first))?.pomodoroName, "CURRENT")
        XCTAssertNil(harness.model.inspectorLoader.cachedShowRow(for: oldItem))
    }

    func testTodayCardsRemainExclusiveAcrossRenameCopyAndEscapeAndRefuseOldBob() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-listing.json"),
            RefsTodayLinkResponse(
                ok: false,
                error: RefsTodayLinkFailure(
                    code: "bob_too_old", message: "Update bob", hint: "Install the latest CLI"
                )
            ),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()

        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.openCopyCard()
        XCTAssertNil(harness.model.todayLinkCard)
        XCTAssertNotNil(harness.model.copyCard)

        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .refused(
            message: "Update bob", hint: "Install the latest CLI"
        ) }
        harness.model.openRenameCard()
        XCTAssertNil(harness.model.todayLinkCard)
        XCTAssertNotNil(harness.model.renameCard)
        harness.model.openTodayLinkCard()
        XCTAssertNil(harness.model.renameCard)
        XCTAssertNotNil(harness.model.todayLinkCard)
        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertNil(harness.model.todayLinkCard)
    }

    func testHiddenTodayLinkFailureNotifiesOnce() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-listing.json"),
            RefsTodayLinkResponse(
                ok: false,
                error: RefsTodayLinkFailure(
                    code: "note_changed", message: "The note changed", hint: "Open it again"
                )
            ),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { false }
        var failures: [(String, String?)] = []
        harness.model.todayLinkFailureNotifier = { failures.append(($0, $1)) }
        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.handleTodayLinkCardKey(.submit)
        harness.model.panelDidHide()
        await harness.waitForModel { $0.todayLinkCard?.phase.isFailed == true }
        XCTAssertEqual(failures.count, 1)
        XCTAssertEqual(failures.first?.0, "The note changed")
    }

    func testGuardedWriteDoesNotInventTodayPillAndFailedRefreshKeepsValidOverlay() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-listing.json"),
            try todayLinkFixture("refs-today-link-guard.json"),
            try todayLinkFixture("refs-today-listing.json"),
            try todayLinkFixture("refs-today-linked.json"),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.handleTodayLinkCardKey(.submit)
        await harness.waitForModel { $0.todayLinkCard == nil }
        XCTAssertNil(harness.model.pomodoroName(for: path))

        fetcher.listError = RefsTestError.boom
        fetcher.planError = RefsTestError.boom
        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        let todayGeneration = harness.library.todayRefreshGeneration
        harness.model.handleTodayLinkCardKey(.submit)
        await harness.waitForModel { $0.todayLinkCard == nil }
        let item = try XCTUnwrap(harness.library.items.first)
        await harness.waitForModel { _ in
            if case .failed = harness.library.refreshState { return true }
            return false
        }
        XCTAssertEqual(harness.library.todayRefreshGeneration, todayGeneration)
        XCTAssertNil(harness.library.signals.today.entry(for: item))
        XCTAssertEqual(harness.model.pomodoroName(for: path), "CURRENT")
    }

    func testRepeatedTodayLinksEachKeepTheirOutcomeAndPill() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        let base = Self.renameRecord(path: path, stem: "today_link_test")
        let item = RefRecord(
            path: path,
            link: base.link,
            title: base.title,
            refType: base.refType,
            status: base.status,
            readingState: base.readingState,
            task: RefTask(
                path: "sase.md", blockID: "ref-attention",
                link: "[[sase#^ref-attention]]", mark: "*"
            ),
            sourcePDF: base.sourcePDF
        )
        fetcher.listResponse = RefsListResponse(schemaVersion: 1, refs: [item])
        fetcher.planResponse = RefsPlanResponse(schemaVersion: 2, todayTasks: [
            RefsPlanTodayTask(
                path: "sase.md", blockID: "ref-attention", entryName: "CURRENT", statusSymbol: "*"
            ),
        ])
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-listing.json"),
            try todayLinkFixture("refs-today-linked.json"),
            try todayLinkFixture("refs-today-listing.json"),
            try todayLinkFixture("refs-today-already-current.json"),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }
        var outcomes: [RefsTodayLinkToast.Style] = []
        harness.model.todayLinkCompletion = { toast, _ in outcomes.append(toast.style) }

        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.handleTodayLinkCardKey(.submit)
        await harness.waitForModel { $0.todayLinkCard == nil }

        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.handleTodayLinkCardKey(.submit)
        await harness.waitForModel { $0.todayLinkCard == nil }
        await harness.waitForModel { $0.pomodoroName(for: path) == "READING" }
        XCTAssertEqual(outcomes, [.linked, .already])
        XCTAssertEqual(fetcher.todayLinkCalls.filter { !$0.dryRun }.count, 2)
    }

    func testRenameUsesBobDestinationMigratesHistoryAndNotifiesWhenHidden() async throws {
        let oldPath = "ref/blogs/old_stem.md"
        let newPath = "ref/blogs/new_stem.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: oldPath, stem: "old_stem")]
        )
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [oldPath])
        harness.model.prepareForPresentation()
        let openedAt = Date().addingTimeInterval(-3_600)
        harness.openLogStore.append(RefsOpenEvent(path: oldPath, at: openedAt))
        fetcher.renameResponse = RefsRenameResponse(
            schemaVersion: 1,
            ok: true,
            from: RefsRenameLocation(path: oldPath, stem: "old_stem"),
            to: RefsRenameLocation(path: newPath, stem: "new_stem"),
            links: RefsRenameLinks(rewritten: 1, files: ["sase.md"]),
            outcome: "renamed",
            changed: true
        )
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: newPath, stem: "new_stem")]
        )
        harness.model.panelIsVisible = { false }
        var notifications: [RefsRenameResponse] = []
        harness.model.renameNotifier = { notifications.append($0) }

        harness.model.openRenameCard()
        XCTAssertEqual(harness.model.renameCard?.draftStem, "old_stem")
        harness.model.editRenameDraft("new_stem")
        harness.model.handleRenameCardKey(.submit)
        harness.model.panelDidHide()

        await harness.waitForModel { $0.renameCard == nil && $0.selectedID == newPath }
        XCTAssertEqual(fetcher.renameCalls.map(\.notePath), [oldPath])
        XCTAssertEqual(fetcher.renameCalls.map(\.name), ["new_stem"])
        XCTAssertEqual(harness.library.items.map(\.id), [newPath])
        XCTAssertEqual(harness.model.renameStatus, "Renamed → new_stem.pdf · 1 link updated")
        XCTAssertEqual(harness.library.signals.opens.count(newPath), 1)
        XCTAssertEqual(harness.library.signals.opens.count(oldPath), 0)
        XCTAssertEqual(notifications, [fetcher.renameResponse])
    }

    func testRenameKeepsRunningWhenHiddenAndShowsBobErrorsInline() async throws {
        let oldPath = "ref/blogs/old_stem.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: oldPath, stem: "old_stem")]
        )
        fetcher.renameDelayNanoseconds = 100_000_000
        fetcher.renameResponse = RefsRenameResponse(
            schemaVersion: 1,
            ok: false,
            error: RefsRenameFailure(
                code: "name_taken",
                message: "That filename is already in use.",
                hint: "Choose a different filename."
            )
        )
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [oldPath])
        harness.model.prepareForPresentation()
        var failures: [(message: String, hint: String?)] = []
        harness.model.renameFailureNotifier = { failures.append(($0, $1)) }
        harness.model.openRenameCard()
        let openedGeneration = harness.model.renameCardGeneration
        harness.model.editRenameDraft("taken")
        harness.model.handleRenameCardKey(.submit)
        harness.model.panelDidHide()

        XCTAssertTrue(harness.model.isRenaming)
        await harness.waitForModel {
            if case .failed(let message, let hint) = $0.renameCard?.phase {
                return message == "That filename is already in use."
                    && hint == "Choose a different filename."
            }
            return false
        }
        XCTAssertEqual(harness.model.renameCard?.draftStem, "taken")
        XCTAssertEqual(harness.model.selectedID, oldPath)
        // The failure lands while hidden, so it notifies, and the
        // running-to-failed transition refocuses the field.
        XCTAssertEqual(failures.count, 1)
        let failure = try XCTUnwrap(failures.first)
        XCTAssertEqual(failure.message, "That filename is already in use.")
        XCTAssertEqual(failure.hint, "Choose a different filename.")
        XCTAssertEqual(harness.model.renameCardGeneration, openedGeneration + 1)

        harness.model.prepareForPresentation()
        // The failed card is re-presented with its inline error and
        // draft instead of closed, and refocused.
        if case .failed(let message, let hint) = harness.model.renameCard?.phase {
            XCTAssertEqual(message, "That filename is already in use.")
            XCTAssertEqual(hint, "Choose a different filename.")
        } else {
            XCTFail("failed rename card was closed by prepareForPresentation")
        }
        XCTAssertEqual(harness.model.renameCard?.draftStem, "taken")
        XCTAssertEqual(harness.model.renameCardGeneration, openedGeneration + 2)
    }

    func testRenameMapsOlderBobFailureToInlineUpdateMessage() async throws {
        let oldPath = "ref/blogs/old_stem.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: oldPath, stem: "old_stem")]
        )
        fetcher.renameError = BobClientError.processFailed(
            command: ["bob", "ref", "rename"],
            exitStatus: 2,
            stderr: "unknown command"
        )
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [oldPath])
        harness.model.prepareForPresentation()
        harness.model.openRenameCard()
        harness.model.handleRenameCardKey(.submit)

        await harness.waitForModel {
            if case .failed(let message, _) = $0.renameCard?.phase {
                return message == "This bob can't rename references yet — update bob on this Mac"
            }
            return false
        }
    }

    func testRenameDuringScanFailsWithHumanBusyMessage() async throws {
        let oldPath = "ref/blogs/old_stem.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: oldPath, stem: "old_stem")]
        )
        fetcher.scanDelayNanoseconds = 500_000_000
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [oldPath])
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScanStart()
        harness.model.openRenameCard()
        harness.model.handleRenameCardKey(.submit)

        await harness.waitForModel {
            if case .failed(let message, let hint) = $0.renameCard?.phase {
                return message == "A library scan is running — try again when it finishes."
                    && hint == nil
            }
            return false
        }
    }

    func testRenameUnchangedShowsAlreadyNamedStatus() async throws {
        let oldPath = "ref/blogs/old_stem.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: oldPath, stem: "old_stem")]
        )
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [oldPath])
        harness.model.prepareForPresentation()
        fetcher.renameResponse = RefsRenameResponse(
            schemaVersion: 1,
            ok: true,
            from: RefsRenameLocation(path: oldPath, stem: "old_stem"),
            to: RefsRenameLocation(path: oldPath, stem: "old_stem"),
            links: RefsRenameLinks(rewritten: 0, files: []),
            outcome: "unchanged",
            changed: false
        )

        harness.model.openRenameCard()
        harness.model.handleRenameCardKey(.submit)

        await harness.waitForModel { $0.renameCard == nil && $0.renameStatus != nil }
        XCTAssertEqual(harness.model.renameStatus, "Already named old_stem.pdf")
        XCTAssertEqual(harness.model.selectedID, oldPath)
    }

    func testRenameStatusClearsOnNextPresentation() async throws {
        let oldPath = "ref/blogs/old_stem.md"
        let newPath = "ref/blogs/new_stem.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: oldPath, stem: "old_stem")]
        )
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [oldPath])
        await succeedRename(
            harness: harness,
            fetcher: fetcher,
            oldPath: oldPath,
            newPath: newPath,
            oldStem: "old_stem",
            newStem: "new_stem"
        )

        harness.model.prepareForPresentation()
        XCTAssertNil(harness.model.renameStatus)
    }

    func testRenameStatusClearsWhenRefreshStarts() async throws {
        let oldPath = "ref/blogs/old_stem.md"
        let newPath = "ref/blogs/new_stem.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: oldPath, stem: "old_stem")]
        )
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [oldPath])
        await succeedRename(
            harness: harness,
            fetcher: fetcher,
            oldPath: oldPath,
            newPath: newPath,
            oldStem: "old_stem",
            newStem: "new_stem"
        )

        harness.library.refresh(reason: .manual)
        await harness.waitForModel { $0.renameStatus == nil }
    }

    func testRenameStatusClearsWhenScanStarts() async throws {
        let oldPath = "ref/blogs/old_stem.md"
        let newPath = "ref/blogs/new_stem.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: oldPath, stem: "old_stem")]
        )
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [oldPath])
        await succeedRename(
            harness: harness,
            fetcher: fetcher,
            oldPath: oldPath,
            newPath: newPath,
            oldStem: "old_stem",
            newStem: "new_stem"
        )

        fetcher.scanDelayNanoseconds = 500_000_000
        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForModel { $0.renameStatus == nil && $0.isScanning }
    }

    private func succeedRename(
        harness: Harness,
        fetcher: FakeRefsFetcher,
        oldPath: String,
        newPath: String,
        oldStem: String,
        newStem: String
    ) async {
        fetcher.renameResponse = RefsRenameResponse(
            schemaVersion: 1,
            ok: true,
            from: RefsRenameLocation(path: oldPath, stem: oldStem),
            to: RefsRenameLocation(path: newPath, stem: newStem),
            links: RefsRenameLinks(rewritten: 1, files: ["sase.md"]),
            outcome: "renamed",
            changed: true
        )
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: newPath, stem: newStem)]
        )
        harness.model.prepareForPresentation()
        harness.model.openRenameCard()
        harness.model.editRenameDraft(newStem)
        harness.model.handleRenameCardKey(.submit)
        await harness.waitForModel { $0.renameStatus != nil }
    }

    func testRenameTextEditingKeysPassThroughControllerAndEscapeClosesCardFirst() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let item = try XCTUnwrap(harness.model.selectedItem)
        harness.model.installForPreviews(
            items: [item], signals: harness.model.signals, query: "", scope: .all,
            selectedID: item.id,
            banner: RefsBanner(kind: .error, message: "boom", actions: []),
            refreshState: .idle
        )
        harness.model.openRenameCard()
        let controller = RefsPanelController(model: harness.model)
        let textEvent = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "x",
            charactersIgnoringModifiers: "x",
            isARepeat: false,
            keyCode: 7
        ))
        XCTAssertTrue(controller.processKeyEvent(textEvent) === textEvent)

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertNil(harness.model.renameCard)
        XCTAssertEqual(harness.model.banner?.message, "boom")
        XCTAssertEqual(harness.model.selectedID, item.id)
    }

    func testRenameFieldPrefillsStemAndTakesFirstResponderWithTextSelected() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let controller = RefsPanelController(model: harness.model)
        controller.prewarm()
        controller.show()
        let item = try XCTUnwrap(harness.model.selectedItem)
        harness.model.openRenameCard()

        let deadline = Date().addingTimeInterval(1)
        var field: NSTextField?
        while Date() < deadline {
            controller.makePanelIfNeeded().contentView?.layoutSubtreeIfNeeded()
            field = RefsPanelController.findRenameField(
                in: controller.makePanelIfNeeded().contentView
            )
            if field?.currentEditor() != nil {
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }

        let renameField = try XCTUnwrap(field)
        let editor = try XCTUnwrap(renameField.currentEditor() as? NSTextView)
        XCTAssertEqual(renameField.stringValue, item.stem)
        XCTAssertEqual(
            editor.selectedRange(),
            NSRange(location: 0, length: item.stem.utf16.count)
        )
        controller.hide()
    }

    func testTodayLinkFailureRefocusesItsFilterField() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        fetcher.todayLinkResponses = [
            try todayLinkFixture("refs-today-listing.json"),
            RefsTodayLinkResponse(
                ok: false,
                error: RefsTodayLinkFailure(
                    code: "note_changed", message: "The note changed", hint: "Try again"
                )
            ),
        ]
        let harness = try makeRenameHarness(fetcher: fetcher)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        let controller = RefsPanelController(model: harness.model)
        controller.prewarm()
        controller.show()
        try await Task.sleep(for: .milliseconds(100))
        harness.model.panelIsVisible = { true }
        harness.model.openTodayLinkCard()
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.handleTodayLinkCardKey(.submit)
        await harness.waitForModel { $0.todayLinkCard?.phase.isFailed == true }

        let panel = controller.makePanelIfNeeded()
        let deadline = Date().addingTimeInterval(1)
        var field: NSTextField?
        while Date() < deadline {
            panel.contentView?.layoutSubtreeIfNeeded()
            field = RefsPanelController.findTodayLinkField(in: panel.contentView)
            if field?.currentEditor() != nil { break }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertNotNil(field?.currentEditor())
        controller.hide()
    }

    func testShowCopyCardConsumesTheCommandWithoutASelection() async throws {
        let harness = try makeHarness()
        harness.model.installForPreviews(
            items: [],
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: nil,
            banner: nil,
            refreshState: .idle
        )

        XCTAssertTrue(harness.model.perform(.showCopyCard))
        XCTAssertNil(harness.model.copyCard)
    }

    func testCopyCardKeepsItsFrozenItemAndCompletesAfterOneWrite() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let original = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [original],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: original.id,
            banner: nil,
            refreshState: .idle
        )
        var completions: [RefsCopyRow] = []
        harness.model.copyCompletion = { completions.append($0) }

        XCTAssertTrue(harness.model.perform(.showCopyCard))
        XCTAssertEqual(harness.model.copyCard?.item.rawTitle, "Alpha")
        let changed = RefItem(
            id: original.id,
            link: original.link,
            rawTitle: "Changed after opening",
            stem: original.stem,
            kind: original.kind,
            state: original.state,
            isBlocked: original.isBlocked,
            pdfPath: original.pdfPath
        )
        harness.model.installForPreviews(
            items: [changed],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: original.id,
            banner: nil,
            refreshState: .idle
        )

        harness.model.handleCopyCardKey(
            characters: "t",
            keyCode: 17,
            modifiers: []
        )

        XCTAssertEqual(harness.pasteboard.strings, ["Alpha"])
        XCTAssertEqual(completions.map(\.confirmationTitle), ["Copied Title"])
        XCTAssertNil(harness.model.copyCard)
    }

    func testQueuedDigitCopiesWhenTheShowLoaderReturns() async throws {
        let showFixture = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("json")
        let showJSON = #"{"ok":true,"schema_version":1,"command":"ref show","generated_at":"2026-10-14T00:00:00","refs":[{"path":"ref/chat/small_reading.md","annotations":[{"kind":"highlight","quote":"Loaded quote","comment":"Loaded comment"}]}]}"#
        try Data(showJSON.utf8).write(to: showFixture)
        defer { try? FileManager.default.removeItem(at: showFixture) }

        let harness = try makeHarness(environment: [
            "FAKE_BOB_REFS_SHOW_FIXTURE": showFixture.path,
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.copyCardNoteCapacity = 9
        let id = "ref/chat/small_reading.md"
        XCTAssertTrue(harness.model.perform(.select(id: id)))
        var completions: [RefsCopyRow] = []
        harness.model.copyCompletion = { completions.append($0) }

        harness.model.openCopyCard()
        XCTAssertEqual(harness.model.copyCard?.notes, .loading)
        harness.model.handleCopyCardKey(characters: "1", keyCode: 18, modifiers: [])
        XCTAssertEqual(harness.model.copyCard?.pending, .note(1))
        XCTAssertEqual(
            harness.model.copyCard?.message?.text,
            "Waiting for notes… esc cancels"
        )

        await harness.waitForModel { $0.copyCard == nil && harness.pasteboard.strings.count == 1 }
        XCTAssertTrue(
            harness.pasteboard.strings.first?.contains("Comment: Loaded comment") == true
        )
        XCTAssertEqual(completions.map(\.confirmationTitle), ["Copied Note 1"])
        XCTAssertEqual(harness.pasteboard.strings.count, 1)
    }

    func testCommandKFromCopyCardClosesItAndPresentsActions() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [item], signals: harness.model.signals, query: "", scope: .all,
            selectedID: item.id, banner: nil, refreshState: .idle
        )
        var actionsPresented = 0
        harness.model.actionsPresenter = { actionsPresented += 1 }
        harness.model.openCopyCard()

        harness.model.handleCopyCardKey(characters: "k", keyCode: 40, modifiers: .command)

        XCTAssertNil(harness.model.copyCard)
        XCTAssertEqual(actionsPresented, 1)
    }

    func testModelEscapeClosesCopyCardBeforeBannerQueryAndScope() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        let banner = RefsBanner(kind: .error, message: "boom", actions: [.tryAgain])
        harness.model.installForPreviews(
            items: [item], signals: harness.model.signals, query: "alpha",
            scope: .chats, selectedID: item.id, banner: banner, refreshState: .idle
        )
        harness.model.openCopyCard()

        XCTAssertTrue(harness.model.perform(.escape))

        XCTAssertNil(harness.model.copyCard)
        XCTAssertEqual(harness.model.banner, banner)
        XCTAssertEqual(harness.model.query, "alpha")
        XCTAssertEqual(harness.model.scope, .chats)
        XCTAssertEqual(harness.dismissed, 0)
    }

    func testCopyCardNoteCapacityBudgetsAllNotesGroupRows() {
        let item = Self.twoPreviewItems()[0]
        let card = RefsCopyCard(
            token: 1, item: item, absolutePDFPath: nil, pdfExists: false,
            notes: .loaded(RefsShowRow(path: item.id, annotations: [
                RefsShowAnnotation(kind: "highlight", comment: "One"),
                RefsShowAnnotation(kind: "note", comment: "Standalone"),
            ])),
            noteCapacity: 0
        )

        XCTAssertNotNil(card.catalog.row(for: .allNotes))
        XCTAssertNotNil(card.catalog.row(for: .highlightPicker))
        XCTAssertEqual(RefsPanelView.copyCardNoteCapacity(for: card, height: 300), 1)
    }

    func testCopyCardWriteFailureKeepsCardOpenAndEscapeClosesOnlyCard() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.pasteboard.failWrites = true
        var completions = 0
        harness.model.copyCompletion = { _ in completions += 1 }
        harness.model.openCopyCard()
        harness.model.handleCopyCardKey(
            characters: "w",
            keyCode: 13,
            modifiers: []
        )

        XCTAssertNotNil(harness.model.copyCard)
        XCTAssertEqual(
            harness.model.copyCard?.message?.text,
            "Couldn't copy — ↵ tries again"
        )
        XCTAssertEqual(harness.pasteboard.strings, [])
        XCTAssertEqual(completions, 0)
        let dismissedBefore = harness.dismissed
        harness.model.handleCopyCardKey(
            characters: nil,
            keyCode: 53,
            modifiers: []
        )
        XCTAssertNil(harness.model.copyCard)
        XCTAssertEqual(harness.dismissed, dismissedBefore)
    }

    func testCopyCardIsRevokedByHideAndSelectionChange() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.openCopyCard()
        harness.model.handleCopyCardKey(
            characters: "1",
            keyCode: 18,
            modifiers: []
        )
        XCTAssertEqual(harness.model.copyCard?.pending, .note(1))

        harness.model.panelDidHide()
        XCTAssertNil(harness.model.copyCard)
        harness.model.openCopyCard()

        harness.model.handleCopyCardKey(
            characters: "1",
            keyCode: 18,
            modifiers: []
        )
        harness.model.prepareForPresentation()
        XCTAssertNil(harness.model.copyCard)

        harness.model.installForPreviews(
            items: items,
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.openCopyCard()
        XCTAssertTrue(harness.model.perform(.select(id: items[1].id)))
        XCTAssertNil(harness.model.copyCard)
    }

    func testControllerConsumesCardKeysAndCopiesTheRequestedRow() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.openCopyCard()
        // Keep the test focused on event routing; the live controller's
        // copy callback is covered by the app's HUD path.
        harness.model.copyCompletion = { _ in }
        let controller = RefsPanelController(model: harness.model)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))

        XCTAssertNil(controller.processKeyEvent(event))
        XCTAssertEqual(harness.pasteboard.strings, ["[[ref/chat/alpha]]"])
    }

    func testCopyAlternatesSeedFlagsClickAndResetOnHide() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let item = try XCTUnwrap(harness.model.selectedItem)
        harness.model.openCopyCard(optionHeld: true)
        XCTAssertTrue(harness.model.copyAlternatesActive)
        let card = try XCTUnwrap(harness.model.copyCard)
        let row = try XCTUnwrap(card.catalog.row(for: .wikiLink))
        let keys = card.rows.map(\.key)
        harness.model.updateCopyModifiers([])
        XCTAssertFalse(harness.model.copyAlternatesActive)
        harness.model.updateCopyModifiers([.option, .shift])
        XCTAssertEqual(harness.model.copyCard?.rows.map(\.key), keys)
        XCTAssertEqual(harness.model.copyCard?.selectedKey, card.selectedKey)
        var copied: RefsCopyRow?
        harness.model.copyCompletion = { copied = $0 }
        harness.model.copyCardRowTapped(row)
        XCTAssertEqual(copied, row.resolved(alternate: true))
        XCTAssertEqual(
            harness.pasteboard.strings,
            [RefsCopyFormat.titledWikiLink(link: item.link, title: item.rawTitle)])
        XCTAssertFalse(harness.model.copyAlternatesActive)
        harness.model.updateCopyModifiers(.option)
        XCTAssertFalse(harness.model.copyAlternatesActive)
        harness.model.openCopyCard(optionHeld: true)
        harness.model.panelDidHide()
        XCTAssertFalse(harness.model.copyAlternatesActive)
    }

    func testControllerFlagsAreGatedAndFailedAlternateRetriesAfterRelease() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.openCopyCard(optionHeld: false)
        let controller = RefsPanelController(model: harness.model)
        // No key panel: a flags event must pass through without changing the model.
        let flags = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged, location: .zero, modifierFlags: .option,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58
            ))
        XCTAssertTrue(controller.handleKeyDown(flags) === flags)
        XCTAssertFalse(harness.model.copyAlternatesActive)
        XCTAssertTrue(controller.processKeyEvent(flags) === flags)
        XCTAssertTrue(harness.model.copyAlternatesActive)
        let row = try XCTUnwrap(harness.model.copyCard?.catalog.row(for: .wikiLink))
        harness.pasteboard.failWrites = true
        harness.model.handleCopyCardKey(characters: "w", keyCode: 13, modifiers: .option)
        harness.model.updateCopyModifiers([])
        harness.pasteboard.failWrites = false
        var copied: RefsCopyRow?
        harness.model.copyCompletion = { copied = $0 }
        harness.model.handleCopyCardKey(characters: nil, keyCode: 36, modifiers: [])
        XCTAssertEqual(copied, row.resolved(alternate: true))
        XCTAssertEqual(harness.pasteboard.strings.count, 1)
        XCTAssertNil(harness.model.copyCard)
    }

    func testFlagsChangedWhileCopyCardIsClosedDoesNotPublish() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let controller = RefsPanelController(model: harness.model)
        var published = 0
        let subscription = harness.model.objectWillChange.sink { published += 1 }
        let flags = try XCTUnwrap(NSEvent.keyEvent(
            with: .flagsChanged, location: .zero, modifierFlags: .option,
            timestamp: 0, windowNumber: 0, context: nil,
            characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 58
        ))

        XCTAssertTrue(controller.processKeyEvent(flags) === flags)
        XCTAssertEqual(published, 0)
        withExtendedLifetime(subscription) {}
    }

    func testOptionPickerClickCopiesQuote() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let item = try XCTUnwrap(harness.model.selectedItem)
        harness.model.inspectorLoader.installShowRowForPreviews(
            RefsShowRow(
                path: item.id,
                annotations: [
                    RefsShowAnnotation(
                        kind: "highlight", quote: "Raw\nquote", comment: "My comment")
                ]), for: item
        )
        harness.model.openCopyCard(optionHeld: false)
        harness.model.handleCopyCardKey(characters: "h", keyCode: 4, modifiers: [])
        harness.model.updateCopyModifiers(.option)
        harness.model.copyCardPickerRowTapped(1)
        XCTAssertEqual(harness.pasteboard.strings, ["Raw\nquote"])
    }

    func testCardFreezesResolvedNoteAndExistingNarrationPaths() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = RefItem(
            id: "ref/chat/alpha.md", link: "[[ref/chat/alpha]]", rawTitle: "Alpha",
            stem: "alpha", kind: .chat, state: .ready, isBlocked: false,
            pdfPath: "lib/alpha.pdf", audioPath: "lib/alpha.m4a"
        )
        harness.model.installForPreviews(
            items: [item], signals: harness.model.signals, query: "", scope: .all,
            selectedID: item.id, banner: nil, refreshState: .idle
        )
        let pdf = harness.vault.appendingPathComponent(item.pdfPath)
        let audio = harness.vault.appendingPathComponent("lib/alpha.m4a")
        try Data("pdf".utf8).write(to: pdf)
        harness.model.openCopyCard(optionHeld: false)
        XCTAssertNil(harness.model.copyCard?.catalog.row(for: .pdfFile)?.alternate)
        try Data("audio".utf8).write(to: audio)
        // Late filesystem changes do not change the frozen card.
        XCTAssertNil(harness.model.copyCard?.catalog.row(for: .pdfFile)?.alternate)
        harness.model.openCopyCard(optionHeld: true)
        let card = try XCTUnwrap(harness.model.copyCard)
        XCTAssertEqual(
            card.catalog.row(for: .notePath)?.alternate?.payload,
            .text(RefsCopyFormat.abbreviatedPath(
                harness.vault.appendingPathComponent(item.id).path,
                homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path)))
        XCTAssertEqual(
            card.catalog.row(for: .obsidianLink)?.payload,
            ObsidianOpenURL.url(forAbsolutePath: harness.vault.appendingPathComponent(item.id).path)
                .map { .text($0.absoluteString) })
        XCTAssertEqual(
            card.catalog.row(for: .pdfPath)?.payload,
            .text(RefsCopyFormat.abbreviatedPath(
                pdf.path,
                homeDirectoryPath: FileManager.default.homeDirectoryForCurrentUser.path)))
        XCTAssertEqual(card.catalog.row(for: .pdfFile)?.alternate?.payload, .fileURL(audio))
        try FileManager.default.removeItem(at: audio)
        var copies = 0
        harness.model.copyCompletion = { _ in copies += 1 }
        harness.model.handleCopyCardKey(characters: "f", keyCode: 3, modifiers: .option)
        XCTAssertEqual(copies, 0)
        XCTAssertTrue(harness.model.copyCard?.message?.isError == true)
        XCTAssertNotNil(harness.model.copyCard)
    }

    func testCopyCardHOpensPickerAndEscapeReturnsToCard() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.inspectorLoader.installShowRowForPreviews(
            RefsShowRow(path: item.id, annotations: Self.pickerAnnotations()),
            for: item
        )
        harness.model.openCopyCard()

        harness.model.handleCopyCardKey(characters: "h", keyCode: 4, modifiers: [])
        XCTAssertEqual(harness.model.copyCard?.highlightPicker?.entries.count, 3)
        XCTAssertNotNil(harness.model.copyCard)

        harness.model.handleCopyCardKey(characters: nil, keyCode: 53, modifiers: [])
        XCTAssertNil(harness.model.copyCard?.highlightPicker)
        XCTAssertNotNil(harness.model.copyCard)
        XCTAssertEqual(harness.pasteboard.strings, [])
    }

    func testCopyCardPickerDigitAndAllCopy() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let item = Self.twoPreviewItems()[0]
        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.inspectorLoader.installShowRowForPreviews(
            RefsShowRow(path: item.id, annotations: Self.pickerAnnotations()),
            for: item
        )
        var completions: [RefsCopyRow] = []
        harness.model.copyCompletion = { completions.append($0) }
        harness.model.openCopyCard()
        harness.model.handleCopyCardKey(characters: "h", keyCode: 4, modifiers: [])
        harness.model.handleCopyCardKey(characters: "1", keyCode: 18, modifiers: [])

        XCTAssertEqual(completions.map(\.confirmationTitle), ["Copied Highlight · p. 11"])
        XCTAssertEqual(harness.pasteboard.strings.count, 1)
        XCTAssertTrue(
            harness.pasteboard.strings.first?.contains("> Uncommented quote") == true
        )
        XCTAssertNil(harness.model.copyCard)

        harness.model.installForPreviews(
            items: [item],
            signals: harness.model.signals,
            query: "",
            scope: .all,
            selectedID: item.id,
            banner: nil,
            refreshState: .idle
        )
        harness.model.inspectorLoader.installShowRowForPreviews(
            RefsShowRow(path: item.id, annotations: Self.pickerAnnotations()),
            for: item
        )
        completions = []
        harness.model.copyCompletion = { completions.append($0) }
        harness.model.openCopyCard()
        harness.model.handleCopyCardKey(characters: "h", keyCode: 4, modifiers: [])
        harness.model.handleCopyCardKey(characters: "a", keyCode: 0, modifiers: [])

        XCTAssertEqual(completions.map(\.confirmationTitle), ["Copied 3 Highlights"])
        XCTAssertEqual(harness.pasteboard.strings.count, 2)
        XCTAssertTrue(
            harness.pasteboard.strings.dropFirst().first?.contains("Note: Standalone") == true
        )
        XCTAssertTrue(
            harness.pasteboard.strings.dropFirst().first?.contains("Comment: Keep this") == true
        )
        XCTAssertNil(harness.model.copyCard)
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
        // A vanished id keeps its index in the frozen listing, marked
        // unavailable (§5.5); a fresh listing drops it.
        XCTAssertEqual(harness.model.listing.orderedIDs, before)
        XCTAssertTrue(
            harness.model.listing.unavailableIDs.contains(
                "ref/papers/small_ready.md"
            )
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

    func testTypingInSearchFieldReachesModel() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()

        // The field exactly as the search bar wires it: typing must set
        // the query before the re-rank, or the next update wipes it.
        let field = RefsSearchBar(model: harness.model).makeFilterField()
        let coordinator = field.makeCoordinator()
        coordinator.controlTextDidChange(
            Notification(
                name: NSControl.textDidChangeNotification,
                object: NSTextField(string: "omni")
            )
        )

        XCTAssertEqual(harness.model.query, "omni")
        guard case .search = harness.model.listing.mode else {
            XCTFail("expected search mode after typing")
            return
        }
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
        // The error re-shows through the representer, which keeps the
        // query, scope, frozen listing, selection, and pending open; the
        // plain presenter (a full reset) must not run.
        XCTAssertEqual(harness.represented, 1)
        XCTAssertEqual(harness.presented, 0)
        XCTAssertEqual(harness.model.query, "reading")
        XCTAssertEqual(harness.model.selectedID, "ref/chat/small_reading.md")
        XCTAssertTrue(harness.model.banner?.message.contains("busy") ?? false)
        XCTAssertEqual(harness.model.banner?.actions, [.tryAgain, .openInDefaultApp])
        XCTAssertEqual(harness.library.signals.opens.count("ref/chat/small_reading.md"), 0)

        // Try Again re-dispatches the surviving pending open.
        harness.model.performBannerAction(.tryAgain)
        XCTAssertEqual(harness.opener.highlightsOpens.count, 2)
    }

    func testDefaultAppErrorRepresentsAndTryAgainRedispatches() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.query = "reading"
        harness.model.queryDidChange()
        harness.opener.defaultAppError = NSError(
            domain: "RefsPanelModelTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "copy-me-busy"]
        )
        XCTAssertTrue(harness.model.perform(.select(id: "ref/chat/small_reading.md")))

        XCTAssertTrue(harness.model.perform(.open(.defaultApp)))

        XCTAssertEqual(harness.dismissed, 1)
        await harness.waitForModel { $0.banner != nil }
        XCTAssertEqual(harness.represented, 1)
        XCTAssertEqual(harness.presented, 0)
        XCTAssertEqual(harness.model.query, "reading")
        XCTAssertEqual(harness.model.selectedID, "ref/chat/small_reading.md")
        XCTAssertTrue(harness.model.banner?.message.contains("copy-me-busy") ?? false)
        XCTAssertEqual(harness.model.banner?.actions, [.tryAgain, .copyDiagnostic])

        harness.model.performBannerAction(.tryAgain)
        XCTAssertEqual(harness.opener.defaultAppOpens.count, 2)

        harness.model.performBannerAction(.copyDiagnostic)
        XCTAssertEqual(harness.pasteboard.strings.count, 1)
        XCTAssertTrue(
            harness.pasteboard.strings.first?.contains("copy-me-busy") == true
        )
    }

    func testUnavailableRowKeepsTitleRefusesOpensAndKeepsNavigation() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let before = harness.model.listing.orderedIDs
        let vanished = "ref/papers/small_ready.md"
        XCTAssertTrue(before.contains(vanished))
        let vanishedIndex = before.firstIndex(of: vanished)!

        XCTAssertTrue(harness.model.perform(.select(id: vanished)))
        try harness.retireFixtureRow(path: vanished)
        harness.library.refresh(reason: .manual)
        await harness.waitForModel { $0.unavailableIDs.contains(vanished) }

        // The vanished id keeps its index with its last known title.
        XCTAssertEqual(harness.model.listing.orderedIDs, before)
        let content = try XCTUnwrap(harness.model.rowContent(for: vanished))
        XCTAssertTrue(content.isUnavailable)
        XCTAssertEqual(content.title, "Small Ready Paper")
        XCTAssertEqual(content.caption, "No longer in your library")

        // Every open target refuses with the message and opens nothing.
        for target in [RefsOpenTarget.highlights, .note, .reveal, .defaultApp] {
            XCTAssertTrue(harness.model.perform(.open(target)))
        }
        XCTAssertTrue(harness.model.perform(.activate(id: vanished)))
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        XCTAssertTrue(harness.opener.noteOpens.isEmpty)
        XCTAssertTrue(harness.opener.reveals.isEmpty)
        XCTAssertTrue(harness.opener.defaultAppOpens.isEmpty)
        XCTAssertEqual(harness.dismissed, 0)
        XCTAssertTrue(
            harness.model.banner?.message.contains("no longer in your library") ?? false
        )

        // Navigation keeps the selection, and down moves to the next row.
        XCTAssertEqual(harness.model.selectedID, vanished)
        XCTAssertTrue(harness.model.perform(.move(.next)))
        XCTAssertEqual(
            harness.model.selectedID,
            before[(vanishedIndex + 1) % before.count]
        )
    }

    func testRefreshReordersFromNewDataKeepingSelection() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let kept = "ref/chat/small_reading.md"
        XCTAssertTrue(harness.model.perform(.select(id: kept)))
        let bumped = "ref/papers/small_ready.md"
        let beforeIndex = harness.model.listing.orderedIDs.firstIndex(of: bumped)!
        XCTAssertGreaterThan(beforeIndex, 0)

        // New data: the paper was added today, so it joins Just added.
        try harness.serveAddedVariant(path: bumped, added: todayDateString())
        harness.model.perform(.refresh)
        await harness.waitForModel { $0.listing.orderedIDs.first == bumped }

        XCTAssertEqual(harness.model.selectedID, kept)
        XCTAssertTrue(harness.model.unavailableIDs.isEmpty)
    }

    func testOpenRefreshesTodayWithoutRefreshingSnapshot() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let harness = try makeHarness(environment: [
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ])
        await harness.waitForSnapshot()
        await harness.waitForModel { _ in
            harness.library.signals.today.taskEntries.count == 4
        }
        // Settle the `-g` lane before the baseline, so no late git-date
        // call can land between the counts below.
        await harness.waitForModel { _ in
            harness.library.items.contains {
                $0.id == "ref/blogs/small_opened.md" && $0.added != nil
            }
        }
        let listsBefore = argvCount(recordURL, prefix: "argv=ref list")
        let plansBefore = argvCount(recordURL, prefix: "argv=plan -f json")

        harness.model.refreshForOpen()
        await harness.waitForModel { _ in
            argvCount(recordURL, prefix: "argv=plan -f json") > plansBefore
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        harness.model.refreshForOpen()
        await harness.waitForModel { _ in
            argvCount(recordURL, prefix: "argv=plan -f json") > plansBefore + 1
        }

        // Two opens ran two Today refreshes and no new snapshot refresh.
        XCTAssertEqual(argvCount(recordURL, prefix: "argv=ref list"), listsBefore)
    }

    func testCopyDiagnosticOnLoadFailedCopiesRefreshFailure() async throws {
        let harness = try makeHarness(environment: ["FAKE_BOB_EXIT": "1"])
        await harness.waitForModel { _ in
            if case .failed = harness.library.refreshState {
                return true
            }
            return false
        }

        harness.model.performBannerAction(.copyDiagnostic)

        guard case .failed(let message, _) = harness.library.refreshState else {
            XCTFail("expected a failed refresh")
            return
        }
        XCTAssertEqual(harness.pasteboard.strings, [message])
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
            banner: RefsBanner(kind: .error, message: "boom", actions: [.tryAgain]),
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
        let secondSection = try XCTUnwrap(harness.model.listing.sections.dropFirst().first)
        let secondSectionFirst = secondSection.ids.first
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

    func testScanConsumedWhileRunning() async throws {
        let harness = try makeHarness(environment: [
            "FAKE_BOB_DELAY_SECONDS": "2",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        XCTAssertTrue(harness.model.isScanning)
        XCTAssertTrue(harness.model.perform(.scan))
        XCTAssertTrue(harness.model.isScanning)
        await harness.waitForScan()
        XCTAssertNotNil(harness.model.scanNotice)
    }

    func testVisibleBrowseSelectsFirstCreated() async throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let harness = try makeHarness(environment: [
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        guard let notice = harness.model.scanNotice else {
            XCTFail("expected scan notice")
            return
        }
        XCTAssertEqual(notice.kind, .succeeded)
        XCTAssertFalse(notice.created.isEmpty)
        let firstSection = harness.model.listing.sections.first
        XCTAssertEqual(firstSection?.kind, .justScanned)
        XCTAssertEqual(
            harness.model.selectedID,
            "ref/chat/omni_report.md"
        )
        XCTAssertTrue(harness.model.listing.orderedIDs.contains(
            "ref/papers/harness_notes.md"
        ))
    }

    func testScrollInspectorPublishesRepeatedAndAlternatingCommands() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let snapshot = PanelSnapshot(harness.model)
        var received: [RefsInspectorScrollDirection] = []
        let cancellable = harness.model.inspectorScrolls.sink {
            received.append($0)
        }

        XCTAssertTrue(harness.model.perform(.scrollInspector(.down)))
        XCTAssertTrue(harness.model.perform(.scrollInspector(.down)))
        XCTAssertTrue(harness.model.perform(.scrollInspector(.up)))
        XCTAssertTrue(harness.model.perform(.scrollInspector(.down)))

        XCTAssertEqual(received, [.down, .down, .up, .down])
        snapshot.assertUnchanged(harness.model)
        XCTAssertEqual(harness.dismissed, 0)
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        _ = cancellable
    }

    func testRevealReturnsFalseWithoutHydratedContent() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [:]
        )
        XCTAssertFalse(harness.model.revealMoreInspectorNotes())
    }

    func testRevealReturnsFalseWhenNothingHidden() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [items[0].id: RefsInspectorContent(
                notes: Self.twoNotes()
            )]
        )
        XCTAssertFalse(harness.model.revealMoreInspectorNotes())
    }

    func testRevealEmitsRangeAndGeneration() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [items[0].id: RefsInspectorContent(
                notes: Self.eightNotes()
            )]
        )
        var received: [RefsInspectorNotesReveal] = []
        let cancellable = harness.model.inspectorNoteReveals.sink {
            received.append($0)
        }
        XCTAssertTrue(harness.model.revealMoreInspectorNotes())
        XCTAssertEqual(received.count, 1)
        let firstReveal = try XCTUnwrap(received.first)
        XCTAssertEqual(firstReveal.id, items[0].id)
        XCTAssertEqual(firstReveal.generation, 1)
        XCTAssertEqual(firstReveal.range, 3..<6)
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).visibleCount(total: 8),
            6
        )
        XCTAssertTrue(harness.model.revealMoreInspectorNotes())
        XCTAssertEqual(received.count, 2)
        let secondReveal = try XCTUnwrap(received.dropFirst().first)
        XCTAssertEqual(secondReveal.range, 6..<8)
        XCTAssertEqual(secondReveal.generation, 2)
        XCTAssertFalse(harness.model.revealMoreInspectorNotes())
        _ = cancellable
    }

    func testRevealResetsOnSelectionChangeAndPresentation() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [
                items[0].id: RefsInspectorContent(notes: Self.eightNotes()),
                items[1].id: RefsInspectorContent(notes: Self.eightNotes()),
            ]
        )
        XCTAssertTrue(harness.model.revealMoreInspectorNotes())
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).generation,
            1
        )
        XCTAssertTrue(harness.model.perform(.move(.next)))
        XCTAssertEqual(harness.model.selectedID, items[1].id)
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[1].id).generation,
            0
        )
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).visibleCount(total: 8),
            3
        )
        XCTAssertTrue(harness.model.perform(.move(.previous)))
        XCTAssertEqual(harness.model.selectedID, items[0].id)
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).generation,
            0
        )
        XCTAssertTrue(harness.model.revealMoreInspectorNotes())
        harness.model.prepareForPresentation()
        let current = harness.model.selectedID!
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: current).generation,
            0
        )
    }

    func testNotesPageSizeClampsAndSeedsFreshPages() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.notesPageSize = 0
        XCTAssertEqual(harness.model.notesPageSize, 1)
        harness.model.notesPageSize = 99
        XCTAssertEqual(harness.model.notesPageSize, 20)
        harness.model.notesPageSize = 5
        let items = Self.twoPreviewItems()
        harness.model.installForPreviews(
            items: items,
            signals: RefsSignals(),
            query: "",
            scope: .all,
            selectedID: items[0].id,
            banner: nil,
            refreshState: .idle,
            inspector: [items[0].id: RefsInspectorContent(
                notes: Self.eightNotes()
            )]
        )
        // installForPreviews keeps the explicitly set page size: a fresh
        // page shows 5, not the default 3.
        XCTAssertEqual(
            harness.model.inspectorNotesPage(for: items[0].id).visibleCount(total: 8),
            5
        )
    }

    func testScrollInspectorConsumesWithoutSubscriberOrSelection() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.installForPreviews(
            items: [],
            signals: RefsSignals(),
            query: "keep",
            scope: .papers,
            selectedID: nil,
            banner: RefsBanner(
                kind: .warning,
                message: "stay",
                actions: [.copyDiagnostic]
            ),
            refreshState: .idle
        )
        let snapshot = PanelSnapshot(harness.model)

        XCTAssertNil(harness.model.selectedID)
        XCTAssertTrue(harness.model.perform(.scrollInspector(.down)))
        XCTAssertTrue(harness.model.perform(.scrollInspector(.up)))
        snapshot.assertUnchanged(harness.model)
        XCTAssertEqual(harness.dismissed, 0)
    }

    func testVisibleSelectionMovedKeepsUserSelection() async throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let harness = try makeHarness(environment: [
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        XCTAssertTrue(harness.model.perform(.select(id: "ref/papers/small_ready.md")))
        await harness.waitForScan()
        XCTAssertEqual(harness.model.selectedID, "ref/papers/small_ready.md")
    }

    func testVisibleSearchKeepsQueryAndSelection() async throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let harness = try makeHarness(environment: [
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }
        harness.model.query = "reading"
        harness.model.queryDidChange()
        let selectedBefore = harness.model.selectedID

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertEqual(harness.model.query, "reading")
        XCTAssertEqual(harness.model.selectedID, selectedBefore)
        guard let notice = harness.model.scanNotice else {
            XCTFail("expected notice")
            return
        }
        let footer = RefsScanPresentation.footerText(notice, searchMode: true)
        XCTAssertTrue(footer.contains(" · esc shows them"))
    }

    func testHiddenNotifierAndPrepareShowsPending() async throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let harness = try makeHarness(environment: [
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { false }
        var notified: [RefsScanOutcome] = []
        harness.model.scanNotifier = { notified.append($0) }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertEqual(notified.count, 1)
        XCTAssertNil(harness.model.banner)
        harness.model.prepareForPresentation()
        XCTAssertEqual(
            harness.model.selectedID,
            "ref/chat/omni_report.md"
        )
        XCTAssertEqual(harness.model.listing.sections.first?.kind, .justScanned)
    }

    func testHiddenNothingNewDoesNotNotify() async throws {
        let nothingURL = try harnessFixtureURL("refs-scan-nothing.json").path
        let harness = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": nothingURL,
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { false }
        var notified = 0
        harness.model.scanNotifier = { _ in notified += 1 }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertEqual(notified, 0)
    }

    func testNoticeClearsOnHideAfterSeen() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertNotNil(harness.model.scanNotice)
        harness.model.panelDidHide()
        XCTAssertNil(harness.model.scanNotice)
    }

    func testPartialAndFailedBanners() async throws {
        let partialURL = try harnessFixtureURL("refs-scan-partial.json").path
        let partial = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": partialURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await partial.waitForSnapshot()
        partial.model.prepareForPresentation()
        partial.model.panelIsVisible = { true }

        XCTAssertTrue(partial.model.perform(.scan))
        await partial.waitForScan()
        XCTAssertEqual(partial.model.banner?.kind, .warning)
        XCTAssertEqual(partial.model.banner?.actions, [.copyDiagnostic])
        XCTAssertTrue(partial.model.banner?.message.contains("couldn't be scanned") ?? false)
        partial.model.performBannerAction(.copyDiagnostic)
        XCTAssertFalse(partial.pasteboard.strings.isEmpty)
        XCTAssertTrue(
            partial.pasteboard.strings.first?.contains("bob ref scan") == true
        )

        let dirtyURL = try harnessFixtureURL("refs-scan-dirty.json").path
        let failed = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": dirtyURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await failed.waitForSnapshot()
        failed.model.prepareForPresentation()
        failed.model.panelIsVisible = { true }

        XCTAssertTrue(failed.model.perform(.scan))
        await failed.waitForScan()
        XCTAssertEqual(failed.model.banner?.kind, .error)
        XCTAssertEqual(failed.model.banner?.actions, [.scanAgain, .copyDiagnostic])
        XCTAssertTrue(failed.model.banner?.message.contains("couldn't scan") ?? false)
    }

    func testScanAgainStartsScanAndEscDismissesFirst() async throws {
        let dirtyURL = try harnessFixtureURL("refs-scan-dirty.json").path
        let harness = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": dirtyURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertNotNil(harness.model.banner)
        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertNil(harness.model.banner)
        harness.model.performBannerAction(.scanAgain)
        await harness.waitForScanStart()
        XCTAssertTrue(harness.model.isScanning)
        await harness.waitForScan()
    }

    func testHiddenPartialAndFailedNotify() async throws {
        let partialURL = try harnessFixtureURL("refs-scan-partial.json").path
        let partial = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": partialURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await partial.waitForSnapshot()
        partial.model.prepareForPresentation()
        partial.model.panelIsVisible = { false }
        var partialNotified = 0
        partial.model.scanNotifier = { _ in partialNotified += 1 }
        XCTAssertTrue(partial.model.perform(.scan))
        await partial.waitForScan()
        XCTAssertEqual(partialNotified, 1)
        partial.model.prepareForPresentation()
        XCTAssertEqual(partial.model.banner?.kind, .warning)

        let dirtyURL = try harnessFixtureURL("refs-scan-dirty.json").path
        let failed = try makeHarness(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": dirtyURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        await failed.waitForSnapshot()
        failed.model.prepareForPresentation()
        failed.model.panelIsVisible = { false }
        var failedNotified = 0
        failed.model.scanNotifier = { _ in failedNotified += 1 }
        XCTAssertTrue(failed.model.perform(.scan))
        await failed.waitForScan()
        XCTAssertEqual(failedNotified, 1)
        failed.model.prepareForPresentation()
        XCTAssertEqual(failed.model.banner?.kind, .error)
        XCTAssertEqual(failed.model.banner?.actions, [.scanAgain, .copyDiagnostic])
    }

    @MainActor
    private struct PanelSnapshot {
        let query: String
        let scope: RefScope
        let selectedID: String?
        let listing: RefsListing
        let banner: RefsBanner?

        init(_ model: RefsPanelModel) {
            query = model.query
            scope = model.scope
            selectedID = model.selectedID
            listing = model.listing
            banner = model.banner
        }

        func assertUnchanged(_ model: RefsPanelModel) {
            XCTAssertEqual(model.query, query)
            XCTAssertEqual(model.scope, scope)
            XCTAssertEqual(model.selectedID, selectedID)
            XCTAssertEqual(model.listing, listing)
            XCTAssertEqual(model.banner, banner)
        }
    }

    private static func twoPreviewItems() -> [RefItem] {
        [
            RefItem(
                id: "ref/chat/alpha.md",
                link: "[[ref/chat/alpha]]",
                rawTitle: "Alpha",
                stem: "alpha",
                kind: .chat,
                state: .ready,
                isBlocked: false,
                pdfPath: "lib/chat/alpha.pdf"
            ),
            RefItem(
                id: "ref/chat/beta.md",
                link: "[[ref/chat/beta]]",
                rawTitle: "Beta",
                stem: "beta",
                kind: .chat,
                state: .ready,
                isBlocked: false,
                pdfPath: "lib/chat/beta.pdf"
            ),
        ]
    }

    private static func renameRecord(path: String, stem: String) -> RefRecord {
        RefRecord(
            path: path,
            link: "[[\(path.replacingOccurrences(of: ".md", with: ""))]]",
            title: "Rename test reference",
            refType: "blogs",
            status: "ready",
            readingState: "queued",
            sourcePDF: "lib/blogs/\(stem).pdf"
        )
    }

    private static func eightNotes() -> [RefsShowAnnotation] {
        (1...8).map { index in
            RefsShowAnnotation(
                pageLabel: "\(index)",
                kind: "highlight",
                quote: "Quote \(index)",
                comment: "Comment \(index)"
            )
        }
    }

    func testTabsAndLibraryPresentationSourcesResetTheFilter() async throws {
        let reader = FakeTabsReader(isTrusted: false)
        let harness = try makeHarness(tabsReader: reader, isAdHocSigned: true)
        await harness.waitForSnapshot()

        harness.model.setQuery("keep")
        harness.model.perform(.setScope(.papers))
        harness.model.prepareForPresentation(source: .highlightsTabs)

        XCTAssertTrue(harness.model.tabsFilter)
        XCTAssertEqual(harness.model.query, "")
        XCTAssertEqual(harness.model.scope, .all)
        XCTAssertEqual(harness.model.tabsState, .needsPermission(adHoc: true))
        XCTAssertEqual(reader.readCount, 0)

        harness.model.prepareForPresentation(source: .library)

        XCTAssertFalse(harness.model.tabsFilter)
        XCTAssertEqual(harness.model.tabsState, .off)
        XCTAssertEqual(harness.model.query, "")
        XCTAssertEqual(harness.model.scope, .all)
    }

    func testTabsToggleKeepsQueryAndScopeAndEscapePeelsTabsBeforeScope() async throws {
        let reader = FakeTabsReader(isTrusted: false)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        harness.model.setQuery("harness")
        harness.model.perform(.setScope(.papers))

        XCTAssertTrue(harness.model.perform(.toggleTabs))
        XCTAssertTrue(harness.model.tabsFilter)
        XCTAssertEqual(harness.model.query, "harness")
        XCTAssertEqual(harness.model.scope, .papers)

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.model.query, "")
        XCTAssertTrue(harness.model.tabsFilter)
        XCTAssertEqual(harness.model.scope, .papers)
        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertFalse(harness.model.tabsFilter)
        XCTAssertEqual(harness.model.scope, .papers)
        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.model.scope, .all)

        harness.model.perform(.setScope(.papers))
        harness.model.perform(.toggleTabs)
        XCTAssertTrue(harness.model.perform(.deleteBackwardOnEmpty))
        XCTAssertFalse(harness.model.tabsFilter)
        XCTAssertEqual(harness.model.scope, .papers)
        XCTAssertTrue(harness.model.perform(.deleteBackwardOnEmpty))
        XCTAssertEqual(harness.model.scope, .all)
    }

    func testNewestToggleSelectsFirstAndKeepsMembership() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        let rankedIDs = Set(harness.model.listing.orderedIDs)
        XCTAssertFalse(rankedIDs.isEmpty)
        XCTAssertEqual(harness.model.listOrder, .ranked)

        XCTAssertTrue(harness.model.perform(.toggleNewest))
        XCTAssertEqual(harness.model.listOrder, .newest)
        XCTAssertEqual(harness.model.listing.order, .newest)
        XCTAssertEqual(Set(harness.model.listing.orderedIDs), rankedIDs)
        XCTAssertEqual(
            harness.model.selectedID,
            harness.model.listing.orderedIDs.first
        )

        harness.model.setQuery("small")
        let searchIDs = Set(harness.model.listing.orderedIDs)
        XCTAssertFalse(searchIDs.isEmpty)
        XCTAssertTrue(harness.model.perform(.toggleNewest))
        XCTAssertEqual(harness.model.listOrder, .ranked)
        XCTAssertEqual(Set(harness.model.listing.orderedIDs), searchIDs)
        XCTAssertTrue(harness.model.perform(.toggleNewest))
        XCTAssertEqual(harness.model.listOrder, .newest)
        XCTAssertEqual(Set(harness.model.listing.orderedIDs), searchIDs)
        XCTAssertEqual(
            harness.model.selectedID,
            harness.model.listing.orderedIDs.first
        )
    }

    func testNewestAndTabsAreExclusiveAndKeepQueryAndScope() async throws {
        let reader = FakeTabsReader(isTrusted: false)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        harness.model.setQuery("harness")
        harness.model.perform(.setScope(.papers))

        XCTAssertTrue(harness.model.perform(.toggleTabs))
        XCTAssertTrue(harness.model.tabsFilter)
        XCTAssertEqual(harness.model.listOrder, .ranked)

        XCTAssertTrue(harness.model.perform(.toggleNewest))
        XCTAssertFalse(harness.model.tabsFilter)
        XCTAssertEqual(harness.model.listOrder, .newest)
        XCTAssertEqual(harness.model.query, "harness")
        XCTAssertEqual(harness.model.scope, .papers)

        XCTAssertTrue(harness.model.perform(.toggleTabs))
        XCTAssertTrue(harness.model.tabsFilter)
        XCTAssertEqual(harness.model.listOrder, .ranked)
        XCTAssertEqual(harness.model.query, "harness")
        XCTAssertEqual(harness.model.scope, .papers)
    }

    func testNewestEscapeAndBackspaceAndPresentationReset() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.setQuery("small")
        harness.model.perform(.setScope(.papers))
        XCTAssertTrue(harness.model.perform(.toggleNewest))

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.model.query, "")
        XCTAssertEqual(harness.model.listOrder, .newest)
        XCTAssertEqual(harness.model.scope, .papers)

        XCTAssertTrue(harness.model.perform(.escape))
        XCTAssertEqual(harness.model.listOrder, .ranked)
        XCTAssertEqual(harness.model.scope, .papers)

        XCTAssertTrue(harness.model.perform(.toggleNewest))
        XCTAssertTrue(harness.model.perform(.deleteBackwardOnEmpty))
        XCTAssertEqual(harness.model.listOrder, .ranked)
        XCTAssertEqual(harness.model.scope, .papers)
        XCTAssertTrue(harness.model.perform(.deleteBackwardOnEmpty))
        XCTAssertEqual(harness.model.scope, .all)

        XCTAssertTrue(harness.model.perform(.toggleNewest))
        harness.model.prepareForPresentation()
        XCTAssertEqual(harness.model.listOrder, .ranked)
        XCTAssertEqual(harness.model.query, "")
        XCTAssertEqual(harness.model.scope, .all)
    }

    func testRefreshKeepsSelectionInNewest() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        XCTAssertTrue(harness.model.perform(.toggleNewest))
        let kept = "ref/chat/small_reading.md"
        XCTAssertTrue(harness.model.perform(.select(id: kept)))
        let generation = harness.library.snapshotRefreshGeneration

        XCTAssertTrue(harness.model.perform(.refresh))
        await harness.waitForModel { model in
            harness.library.snapshotRefreshGeneration > generation
                && model.selectedID == kept
                && model.listing.order == .newest
        }
        XCTAssertEqual(harness.model.selectedID, kept)
        XCTAssertEqual(harness.model.listing.order, .newest)
    }

    func testVisibleScanSelectsFirstCreatedInNewest() async throws {
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let harness = try makeHarness(environment: [
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        await harness.waitForSnapshot()
        harness.model.prepareForPresentation()
        harness.model.panelIsVisible = { true }
        XCTAssertTrue(harness.model.perform(.toggleNewest))

        XCTAssertTrue(harness.model.perform(.scan))
        await harness.waitForScan()
        XCTAssertEqual(harness.model.listOrder, .newest)
        XCTAssertEqual(harness.model.listing.order, .newest)
        XCTAssertEqual(
            harness.model.selectedID,
            "ref/chat/omni_report.md"
        )
        XCTAssertTrue(harness.model.listing.orderedIDs.contains(
            "ref/papers/harness_notes.md"
        ))
    }

    func testSyntheticTabsSurviveLibraryPublicationAndBlockNoteActions() async throws {
        let harness = try makeHarness()
        await harness.waitForSnapshot()
        let tabName = "outside_library.pdf"
        let snapshot = HighlightsTabsSnapshot(
            windows: [HighlightsTabsSnapshot.Window(
                isMain: true,
                tabs: [HighlightsTabsSnapshot.Tab(
                    fileName: tabName,
                    isSelected: true
                )]
            )],
            highlightsIsFrontmost: false
        )
        harness.model.installTabsForPreviews(
            snapshot: snapshot,
            state: .loaded,
            frontmost: false
        )
        let rowID = "highlights-tab:\(tabName)"
        XCTAssertEqual(harness.model.selectedID, rowID)
        XCTAssertEqual(harness.model.rowContent(for: rowID)?.caption, "Not in your library")

        XCTAssertTrue(harness.model.perform(.open(.note)))
        XCTAssertEqual(
            harness.model.banner?.message,
            "“\(tabName)” isn't in your library."
        )
        XCTAssertTrue(harness.model.perform(.showCopyCard))
        XCTAssertEqual(
            harness.model.banner?.message,
            "“\(tabName)” isn't in your library."
        )
        XCTAssertTrue(harness.model.perform(.showRenameCard))
        XCTAssertTrue(harness.model.perform(.showTodayLinkCard))
        XCTAssertNil(harness.model.todayLinkCard)
        XCTAssertEqual(
            harness.model.banner?.message,
            "“\(tabName)” isn't in your library."
        )

        harness.library.installSnapshotForPreviews(
            items: harness.library.items,
            signals: harness.library.signals,
            refreshState: .idle
        )
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(harness.model.listing.orderedIDs.contains(rowID))
        XCTAssertFalse(harness.model.unavailableIDs.contains(rowID))
        XCTAssertEqual(harness.model.rowContent(for: rowID)?.isUnavailable, false)
    }

    func testMatchedTabSwitchDoesNotRecordAnOpen() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: false
        )))

        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }
        XCTAssertEqual(harness.model.selectedID, item.id)
        XCTAssertTrue(harness.model.perform(.open(.highlights)))
        await harness.waitForModel { _ in !harness.opener.highlightsOpens.isEmpty }
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(harness.opener.highlightsOpens.count, 1)
        XCTAssertTrue(harness.openLogStore.load().isEmpty)
        XCTAssertEqual(harness.library.signals.opens.count(item.id), 0)
    }

    func testUnmatchedSwitchSelectsTheTabAndShowsClosedBanner() async throws {
        let reader = FakeTabsReader(isTrusted: true, selectResult: .notFound)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let fileName = "external_notes.pdf"
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            fileNames: [fileName],
            frontmost: false
        )))

        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }
        XCTAssertTrue(harness.model.perform(.open(.highlights)))
        await harness.waitForModel { $0.banner?.message == "That tab was closed in Highlights." }

        XCTAssertEqual(reader.selectedTargets, [HighlightsTabTarget(
            fileName: fileName,
            windowOrdinal: 0
        )])
        XCTAssertEqual(harness.dismissed, 1)
        XCTAssertEqual(harness.represented, 1)
    }

    func testHeldEnterOpensWhenFirstTabSnapshotLands() async throws {
        let reader = FakeTabsReader(isTrusted: true, readDelayNanoseconds: 80_000_000)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: false
        )))

        harness.model.prepareForPresentation(source: .highlightsTabs)
        XCTAssertEqual(harness.model.tabsState, .loading)
        XCTAssertTrue(harness.model.listing.orderedIDs.isEmpty)
        XCTAssertTrue(harness.model.perform(.open(.highlights)))
        await harness.waitForModel { _ in !harness.opener.highlightsOpens.isEmpty }

        XCTAssertEqual(harness.opener.highlightsOpens.count, 1)
        XCTAssertTrue(harness.openLogStore.load().isEmpty)
        XCTAssertEqual(harness.library.signals.opens.count(item.id), 0)
    }

    func testHeldEnterIsDroppedAfterQueryEditAndFailedRead() async throws {
        let reader = FakeTabsReader(
            isTrusted: true,
            readDelayNanoseconds: 80_000_000
        )
        reader.setNextResult(.failed("Temporary read failure"))
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()

        harness.model.prepareForPresentation(source: .highlightsTabs)
        XCTAssertTrue(harness.model.perform(.open(.highlights)))
        harness.model.setQuery("cancel")
        await harness.waitForModel {
            if case .failed = $0.tabsState { return true }
            return false
        }

        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        if case .failed(_, let hasStaleRows) = harness.model.tabsState {
            XCTAssertFalse(hasStaleRows)
        } else {
            XCTFail("expected failed tab state")
        }
    }

    func testTabsRefreshTakesAnotherSnapshotAndKeepsSelection() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let items = Array(harness.library.items.prefix(2))
        guard items.count == 2 else {
            XCTFail("fixture needs two references")
            return
        }
        let first = Self.tabsSnapshot(items, vault: harness.vault, frontmost: false)
        reader.setNextResult(.snapshot(first))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }
        let keepID = items[1].id
        XCTAssertTrue(harness.model.perform(.select(id: keepID)))

        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            Array(items.reversed()),
            vault: harness.vault,
            frontmost: true
        )))
        XCTAssertTrue(harness.model.perform(.refresh))
        await harness.waitForModel {
            $0.tabsSession.lastSnapshot?.highlightsIsFrontmost == true
        }

        XCTAssertEqual(harness.model.selectedID, keepID)
        XCTAssertEqual(reader.readCount, 2)
    }

    func testSupersededTabRefreshDoesNotReplaceNewSnapshot() async throws {
        let reader = FakeTabsReader(
            isTrusted: true,
            readDelayNanoseconds: 200_000_000
        )
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            fileNames: ["older_snapshot.pdf"],
            frontmost: false
        )))

        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { _ in reader.readCount == 1 }
        reader.setReadDelay(0)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            fileNames: [URL(fileURLWithPath: item.pdfPath).lastPathComponent],
            frontmost: true
        )))
        XCTAssertTrue(harness.model.perform(.refresh))
        await harness.waitForModel {
            $0.tabsSession.lastSnapshot?.highlightsIsFrontmost == true
        }
        try? await Task.sleep(nanoseconds: 250_000_000)

        XCTAssertEqual(harness.model.tabsState, .loaded)
        XCTAssertEqual(harness.model.tabsListing?.tabs.keys.sorted(), [item.id])
        XCTAssertTrue(harness.model.tabsSession.lastSnapshot?.highlightsIsFrontmost == true)
        XCTAssertEqual(reader.readCount, 2)
    }

    func testCloseRemovesRowSelectsItsNeighbourAndReopensWithoutRecordingOpen() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let items = Array(harness.library.items.prefix(3))
        guard items.count == 3 else {
            XCTFail("fixture needs three references")
            return
        }
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            items,
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }

        let orderedIDs = harness.model.listing.orderedIDs
        let targetID = try XCTUnwrap(orderedIDs.dropFirst().first)
        let neighbour = RefsSelectionPolicy.afterRemoving(
            targetID,
            in: harness.model.listing
        )
        let target = try XCTUnwrap(items.first { $0.id == targetID })
        reader.setNextCloseResults([
            .closed(Self.tabsSnapshot(
                items.filter { $0.id != targetID },
                vault: harness.vault,
                frontmost: false
            )),
        ])
        var toasts: [RefsTabCloseToast] = []
        harness.model.panelIsVisible = { true }
        harness.model.tabCloseCompletion = { toasts.append($0) }

        XCTAssertTrue(harness.model.perform(.select(id: targetID)))
        XCTAssertTrue(harness.model.canCloseSelectedTab)
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        XCTAssertFalse(harness.model.listing.orderedIDs.contains(targetID))
        XCTAssertEqual(harness.model.selectedID, neighbour)
        await harness.waitForModel {
            $0.tabsState == .loaded && reader.closeTargets.count == 1
        }

        XCTAssertEqual(reader.closeTargets, [HighlightsTabTarget(
            fileName: URL(fileURLWithPath: target.pdfPath).lastPathComponent,
            windowOrdinal: 0
        )])
        XCTAssertEqual(harness.model.tabsSession.closedTabs.count, 1)
        XCTAssertTrue(harness.openLogStore.load().isEmpty)
        XCTAssertEqual(harness.library.signals.opens.count(targetID), 0)
        XCTAssertEqual(toasts.first?.title, "Closed tab")

        XCTAssertTrue(harness.model.perform(.reopenClosedTab))
        await harness.waitForModel { _ in !harness.opener.highlightsOpens.isEmpty }
        XCTAssertEqual(harness.opener.highlightsOpens.map { $0.pdf }, [
            harness.vault.appendingPathComponent(target.pdfPath),
        ])
        XCTAssertTrue(harness.openLogStore.load().isEmpty)
        XCTAssertEqual(harness.library.signals.opens.count(targetID), 0)
    }

    func testRapidClosesReachReaderOneAtATimeInPressOrder() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        reader.setCloseDelay(30_000_000)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let items = Array(harness.library.items.prefix(3))
        guard items.count == 3 else {
            XCTFail("fixture needs three references")
            return
        }
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            items,
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }

        let firstID = try XCTUnwrap(harness.model.listing.orderedIDs.first)
        let secondID = try XCTUnwrap(
            RefsSelectionPolicy.afterRemoving(firstID, in: harness.model.listing)
        )
        let firstItem = try XCTUnwrap(items.first { $0.id == firstID })
        let secondItem = try XCTUnwrap(items.first { $0.id == secondID })
        reader.setNextCloseResults([
            .closed(Self.tabsSnapshot(
                items.filter { $0.id != firstID },
                vault: harness.vault,
                frontmost: false
            )),
            .closed(Self.tabsSnapshot([], vault: harness.vault, frontmost: false)),
        ])
        var toasts: [RefsTabCloseToast] = []
        harness.model.tabCloseCompletion = { toasts.append($0) }

        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        XCTAssertEqual(harness.model.selectedID, secondID)
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        XCTAssertFalse(harness.model.listing.orderedIDs.contains(firstID))
        XCTAssertFalse(harness.model.listing.orderedIDs.contains(secondID))

        await harness.waitForModel { $0.tabsState == .noDocuments }
        XCTAssertEqual(reader.closeTargets.map(\.fileName), [
            URL(fileURLWithPath: firstItem.pdfPath).lastPathComponent,
            URL(fileURLWithPath: secondItem.pdfPath).lastPathComponent,
        ])
        XCTAssertEqual(reader.maxConcurrentCloses, 1)
        XCTAssertEqual(reader.quitCount, 1)
        XCTAssertEqual(harness.model.tabsSession.closedTabs.count, 2)
        XCTAssertEqual(toasts.map(\.title), ["Closed the last tab"])
        XCTAssertTrue(harness.model.perform(.reopenClosedTab))
        XCTAssertTrue(harness.model.perform(.reopenClosedTab))
        XCTAssertEqual(harness.opener.highlightsOpens.map { $0.pdf }, [
            harness.vault.appendingPathComponent(secondItem.pdfPath),
            harness.vault.appendingPathComponent(firstItem.pdfPath),
        ])
        XCTAssertTrue(harness.openLogStore.load().isEmpty)
        XCTAssertEqual(toasts.last?.title, "Closed the last tab")
    }

    func testCloseWorkerStopsWhenQueueEmptiesAndRestartsOnceForSecondBatch() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let items = Array(harness.library.items.prefix(3))
        guard items.count == 3 else {
            XCTFail("fixture needs three references")
            return
        }
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            items,
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }

        let firstID = try XCTUnwrap(harness.model.listing.orderedIDs.first)
        reader.setNextCloseResults([
            .closed(Self.tabsSnapshot(
                items.filter { $0.id != firstID },
                vault: harness.vault,
                frontmost: false
            )),
        ])
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel { $0.isCloseIdleForTests && reader.closeTargets.count == 1 }
        let launchesAfterFirst = harness.model.closeWorkerLaunchCountForTests
        XCTAssertEqual(launchesAfterFirst, 1)
        // An idle queue must not chain empty workers.
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(harness.model.isCloseIdleForTests)
        XCTAssertEqual(harness.model.closeWorkerLaunchCountForTests, launchesAfterFirst)

        let secondID = try XCTUnwrap(harness.model.listing.orderedIDs.first)
        let thirdID = try XCTUnwrap(
            RefsSelectionPolicy.afterRemoving(secondID, in: harness.model.listing)
        )
        let secondItem = try XCTUnwrap(items.first { $0.id == secondID })
        let thirdItem = try XCTUnwrap(items.first { $0.id == thirdID })
        reader.setNextCloseResults([
            .closed(Self.tabsSnapshot(
                items.filter { $0.id != firstID && $0.id != secondID },
                vault: harness.vault,
                frontmost: false
            )),
            .closed(Self.tabsSnapshot([], vault: harness.vault, frontmost: false)),
        ])
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel { $0.isCloseIdleForTests && reader.closeTargets.count == 3 }
        XCTAssertEqual(harness.model.closeWorkerLaunchCountForTests, launchesAfterFirst + 1)
        XCTAssertEqual(reader.closeTargets.map(\.fileName), [
            URL(fileURLWithPath: items.first { $0.id == firstID }!.pdfPath).lastPathComponent,
            URL(fileURLWithPath: secondItem.pdfPath).lastPathComponent,
            URL(fileURLWithPath: thirdItem.pdfPath).lastPathComponent,
        ])
        XCTAssertEqual(reader.maxConcurrentCloses, 1)
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(harness.model.isCloseIdleForTests)
        XCTAssertEqual(harness.model.closeWorkerLaunchCountForTests, launchesAfterFirst + 1)
    }

    func testCloseBlockedWhileRenameWriteRunsThenWorksAfterSettlement() async throws {
        let path = "ref/blogs/rename_guard_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "rename_guard_test")]
        )
        fetcher.renameDelayNanoseconds = 300_000_000
        fetcher.renameResponse = RefsRenameResponse(
            schemaVersion: 1,
            ok: true,
            from: RefsRenameLocation(path: path, stem: "rename_guard_test"),
            to: RefsRenameLocation(path: path, stem: "rename_guard_test"),
            links: RefsRenameLinks(rewritten: 0, files: []),
            outcome: "renamed",
            changed: false
        )
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeRenameHarness(fetcher: fetcher, tabsReader: reader)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        let item = try XCTUnwrap(harness.library.items.first)
        harness.model.installTabsForPreviews(
            snapshot: Self.tabsSnapshot([item], vault: harness.vault, frontmost: false),
            state: .loaded,
            frontmost: false
        )
        let rowID = item.id
        XCTAssertTrue(harness.model.canCloseTab(id: rowID))

        harness.model.openRenameCard()
        harness.model.editRenameDraft("rename_guard_test")
        harness.model.handleRenameCardKey(.submit)
        await harness.waitForModel { $0.isRenaming }
        XCTAssertFalse(harness.model.canCloseTab(id: rowID))
        XCTAssertFalse(harness.model.canCloseSelectedTab)

        let selectedBefore = harness.model.selectedID
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        XCTAssertTrue(harness.model.perform(.closeTab(id: rowID)))
        XCTAssertTrue(reader.closeTargets.isEmpty)
        XCTAssertTrue(harness.model.listing.orderedIDs.contains(rowID))
        XCTAssertEqual(harness.model.selectedID, selectedBefore)

        await harness.waitForModel { !$0.isRenaming }
        XCTAssertTrue(harness.model.canCloseTab(id: rowID))
        reader.setNextCloseResults([.closed(Self.tabsSnapshot(
            [],
            vault: harness.vault,
            frontmost: false
        ))])
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel { $0.isCloseIdleForTests && reader.closeTargets.count == 1 }
        XCTAssertFalse(harness.model.listing.orderedIDs.contains(rowID))
    }

    func testCloseBlockedWhileTodayLinkWriteRunsThenWorksAfterSettlement() async throws {
        let path = "ref/blogs/today_link_test.md"
        let fetcher = FakeRefsFetcher()
        fetcher.listResponse = RefsListResponse(
            schemaVersion: 1,
            refs: [Self.renameRecord(path: path, stem: "today_link_test")]
        )
        let gate = TodayLinkResponseGate()
        fetcher.todayLinkHandler = { _, _, _ in try await gate.respond() }
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeRenameHarness(fetcher: fetcher, tabsReader: reader)
        await harness.waitForSnapshot(ids: [path])
        harness.model.prepareForPresentation()
        let item = try XCTUnwrap(harness.library.items.first)
        harness.model.installTabsForPreviews(
            snapshot: Self.tabsSnapshot([item], vault: harness.vault, frontmost: false),
            state: .loaded,
            frontmost: false
        )
        let rowID = item.id
        harness.model.todayLinkPreviewDebounce = {}
        harness.model.openTodayLinkCard()
        await gate.waitForRequests(1)
        await gate.resolve(0, with: .success(try todayLinkFixture("refs-today-listing.json")))
        await harness.waitForModel { $0.todayLinkCard?.phase == .ready }
        harness.model.handleTodayLinkCardKey(.submit)
        await harness.waitForModel { $0.isLinkingToday }
        XCTAssertFalse(harness.model.canCloseTab(id: rowID))

        let selectedBefore = harness.model.selectedID
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        XCTAssertTrue(harness.model.perform(.closeTab(id: rowID)))
        XCTAssertTrue(reader.closeTargets.isEmpty)
        XCTAssertTrue(harness.model.listing.orderedIDs.contains(rowID))
        XCTAssertEqual(harness.model.selectedID, selectedBefore)

        await gate.waitForRequests(2)
        await gate.resolve(1, with: .success(try todayLinkFixture("refs-today-linked.json")))
        await harness.waitForModel { !$0.isLinkingToday }
        XCTAssertTrue(harness.model.canCloseTab(id: rowID))
        reader.setNextCloseResults([.closed(Self.tabsSnapshot(
            [],
            vault: harness.vault,
            frontmost: false
        ))])
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel { $0.isCloseIdleForTests && reader.closeTargets.count == 1 }
        XCTAssertFalse(harness.model.listing.orderedIDs.contains(rowID))
    }

    func testFailedCloseRestoresAndSelectsRowWithFailureBanner() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }
        reader.setNextCloseResults([.failed("close failed")])
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel {
            $0.listing.orderedIDs.contains(item.id)
                && $0.selectedID == item.id
                && $0.banner?.message
                    == RefsTabClosePresentation.failureMessage(title: item.title.text)
                && $0.tabsState != .loading
        }
        XCTAssertTrue(harness.model.perform(.reopenClosedTab))
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
    }

    func testAlreadyClosedRemovesRowAndRefreshesWithoutBanner() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }
        reader.setNextCloseResults([.notFound])
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [],
            vault: harness.vault,
            frontmost: false
        )))

        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel {
            $0.tabsState == .noDocuments
                && !$0.listing.orderedIDs.contains(item.id)
        }
        XCTAssertNil(harness.model.banner)
        XCTAssertFalse(harness.model.listing.orderedIDs.contains(item.id))
    }

    func testSyntheticTabClosesWithoutNoteWarningAndReopensKnownPath() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let url = URL(fileURLWithPath: "/tmp/outside_library.pdf")
        let snapshot = HighlightsTabsSnapshot(
            windows: [HighlightsTabsSnapshot.Window(
                isMain: true,
                tabs: [HighlightsTabsSnapshot.Tab(
                    fileName: url.lastPathComponent,
                    documentPath: url.path,
                    isSelected: true
                )]
            )],
            highlightsIsFrontmost: false
        )
        harness.model.installTabsForPreviews(
            snapshot: snapshot,
            state: .loaded,
            frontmost: false
        )
        let rowID = "highlights-tab:\(url.lastPathComponent)"
        reader.setNextCloseResults([.closed(Self.tabsSnapshot(
            [],
            vault: harness.vault,
            frontmost: false
        ))])

        XCTAssertTrue(harness.model.canCloseTab(id: rowID))
        XCTAssertTrue(harness.model.perform(.closeTab(id: rowID)))
        await harness.waitForModel { $0.tabsState == .noDocuments }
        XCTAssertNil(harness.model.banner)

        XCTAssertTrue(harness.model.perform(.reopenClosedTab))
        await harness.waitForModel { _ in !harness.opener.highlightsOpens.isEmpty }
        XCTAssertEqual(harness.opener.highlightsOpens.first?.pdf, url)
        XCTAssertTrue(harness.openLogStore.load().isEmpty)
    }

    func testCloseTabActionsAppearOnlyForMatchedTabsRows() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }

        let firstActions = try XCTUnwrap(harness.model.actionsSections().first)
        XCTAssertEqual(Array(firstActions.prefix(2)), [.openHighlights, .closeTab])
        XCTAssertEqual(RefsAction.closeTab.title, "Close Tab")
        XCTAssertEqual(RefsAction.closeTab.keyEquivalent, "x")
        XCTAssertEqual(RefsAction.closeTab.keyEquivalentModifierMask, .control)

        reader.setNextCloseResults([.closed(Self.tabsSnapshot(
            [],
            vault: harness.vault,
            frontmost: false
        ))])
        harness.model.performAction(.closeTab)
        await harness.waitForModel { $0.tabsState == .noDocuments }
        XCTAssertEqual(reader.closeTargets.count, 1)

        XCTAssertTrue(harness.model.perform(.setTabsFilter(false)))
        XCTAssertFalse(harness.model.actionsSections().flatMap { $0 }.contains(.closeTab))

        // A stale close is a consumed no-op and never scrolls.
        var scrolls: [RefsInspectorScrollDirection] = []
        let scrollSubscription = harness.model.inspectorScrolls.sink {
            scrolls.append($0)
        }
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        XCTAssertTrue(scrolls.isEmpty)
        XCTAssertTrue(reader.closeTargets.count == 1)
        withExtendedLifetime(scrollSubscription) {}
    }

    func testCloseSelectsPreviousNeighbourOnLastRowAndClearsOnlyRow() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let items = Array(harness.library.items.prefix(2))
        guard items.count == 2 else {
            XCTFail("fixture needs two references")
            return
        }
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            items,
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }

        let lastID = try XCTUnwrap(harness.model.listing.orderedIDs.last)
        let previous = RefsSelectionPolicy.afterRemoving(
            lastID,
            in: harness.model.listing
        )
        XCTAssertTrue(harness.model.perform(.select(id: lastID)))
        reader.setNextCloseResults([
            .closed(Self.tabsSnapshot(
                items.filter { $0.id != lastID },
                vault: harness.vault,
                frontmost: false
            )),
            .closed(Self.tabsSnapshot([], vault: harness.vault, frontmost: false)),
        ])
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        XCTAssertEqual(harness.model.selectedID, previous)
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel { $0.tabsState == .noDocuments }
        XCTAssertTrue(harness.model.listing.orderedIDs.isEmpty)
        XCTAssertNil(harness.model.selectedID)
        XCTAssertEqual(reader.quitCount, 1)
    }

    func testClosedLastHidesPanelAndShowsLastToast() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }
        reader.setNextCloseResults([
            .closed(Self.tabsSnapshot([], vault: harness.vault, frontmost: false)),
        ])
        var toasts: [RefsTabCloseToast] = []
        harness.model.panelIsVisible = { true }
        harness.model.tabCloseCompletion = { toasts.append($0) }

        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel { $0.tabsState == .noDocuments }
        XCTAssertEqual(harness.dismissed, 1)
        XCTAssertEqual(toasts.map(\.title), ["Closed the last tab"])
        XCTAssertEqual(toasts.first?.isLast, true)
        XCTAssertEqual(reader.quitCount, 1)
        XCTAssertTrue(harness.openLogStore.load().isEmpty)
        XCTAssertEqual(harness.library.signals.opens.count(item.id), 0)
    }

    func testNeedsAttentionHidesPanelWithoutBanner() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }
        reader.setNextCloseResults([.needsAttention])
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: true
        )))
        harness.model.panelIsVisible = { true }

        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel { $0.tabsSession.lastSnapshot?.highlightsIsFrontmost == true }
        XCTAssertEqual(harness.dismissed, 1)
        XCTAssertNil(harness.model.banner)
    }

    func testNotTrustedCloseShowsPermissionState() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }
        reader.setNextCloseResults([.notTrusted])

        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        await harness.waitForModel {
            if case .needsPermission = $0.tabsState { return true }
            return false
        }
        XCTAssertTrue(harness.model.listing.orderedIDs.isEmpty)
    }

    func testClosingRowIsNotResurrectedByInFlightRefresh() async throws {
        let reader = FakeTabsReader(
            isTrusted: true,
            readDelayNanoseconds: 80_000_000
        )
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        let items = Array(harness.library.items.prefix(2))
        guard items.count == 2 else {
            XCTFail("fixture needs two references")
            return
        }
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            items,
            vault: harness.vault,
            frontmost: false
        )))
        harness.model.prepareForPresentation(source: .highlightsTabs)
        await harness.waitForModel { $0.tabsState == .loaded }

        let targetID = try XCTUnwrap(harness.model.listing.orderedIDs.first)
        reader.setNextResult(.snapshot(Self.tabsSnapshot(
            items,
            vault: harness.vault,
            frontmost: true
        )))
        XCTAssertTrue(harness.model.perform(.refresh))
        reader.setNextCloseResults([
            .closed(Self.tabsSnapshot(
                items.filter { $0.id != targetID },
                vault: harness.vault,
                frontmost: false
            )),
        ])
        XCTAssertTrue(harness.model.perform(.closeSelectedTab))
        XCTAssertFalse(harness.model.listing.orderedIDs.contains(targetID))
        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertFalse(harness.model.listing.orderedIDs.contains(targetID))
        await harness.waitForModel {
            $0.tabsState == .loaded && !$0.listing.orderedIDs.contains(targetID)
        }
    }

    func testReopenOnEmptyStackIsANoOp() async throws {
        let reader = FakeTabsReader(isTrusted: true)
        let harness = try makeHarness(tabsReader: reader)
        await harness.waitForSnapshot()
        XCTAssertTrue(harness.model.perform(.reopenClosedTab))
        XCTAssertTrue(harness.opener.highlightsOpens.isEmpty)
        XCTAssertTrue(harness.openLogStore.load().isEmpty)
    }

    func testInstallTabsForPreviewsCanHideClosingRows() async throws {
        let harness = try makeHarness(tabsReader: FakeTabsReader(isTrusted: true))
        await harness.waitForSnapshot()
        let item = try XCTUnwrap(harness.library.items.first)
        let snapshot = Self.tabsSnapshot(
            [item],
            vault: harness.vault,
            frontmost: false
        )
        harness.model.installTabsForPreviews(
            snapshot: snapshot,
            state: .loaded,
            frontmost: false
        )
        XCTAssertTrue(harness.model.canCloseTab(id: item.id))
        harness.model.installTabsForPreviews(
            snapshot: snapshot,
            state: .loaded,
            frontmost: false,
            closingIDs: [item.id]
        )
        XCTAssertFalse(harness.model.listing.orderedIDs.contains(item.id))
        XCTAssertFalse(harness.model.canCloseTab(id: item.id))
    }

    private static func tabsSnapshot(
        _ items: [RefItem],
        vault: URL,
        frontmost: Bool
    ) -> HighlightsTabsSnapshot {
        let tabs = items.enumerated().map { index, item in
            HighlightsTabsSnapshot.Tab(
                fileName: URL(fileURLWithPath: item.pdfPath).lastPathComponent,
                documentPath: index == 0 ? vault.appendingPathComponent(item.pdfPath).path : nil,
                isSelected: index == 0
            )
        }
        return HighlightsTabsSnapshot(
            windows: tabs.isEmpty ? [] : [HighlightsTabsSnapshot.Window(
                isMain: true,
                pageCaption: "p. 1/4",
                tabs: tabs
            )],
            highlightsIsFrontmost: frontmost
        )
    }

    private static func tabsSnapshot(
        fileNames: [String],
        frontmost: Bool
    ) -> HighlightsTabsSnapshot {
        HighlightsTabsSnapshot(
            windows: fileNames.isEmpty ? [] : [HighlightsTabsSnapshot.Window(
                isMain: true,
                tabs: fileNames.enumerated().map { index, fileName in
                    HighlightsTabsSnapshot.Tab(
                        fileName: fileName,
                        isSelected: index == 0
                    )
                }
            )],
            highlightsIsFrontmost: frontmost
        )
    }

    private static func pickerAnnotations() -> [RefsShowAnnotation] {
        [
            RefsShowAnnotation(
                pageLabel: "Page 11",
                kind: "highlight",
                quote: "Uncommented quote",
                link: "[[ref/chat/alpha#^h-1]]"
            ),
            RefsShowAnnotation(
                pageLabel: "Page 12",
                kind: "highlight",
                quote: "Commented quote",
                comment: "Keep this",
                link: "[[ref/chat/alpha#^h-2]]"
            ),
            RefsShowAnnotation(
                pageLabel: "Page 13",
                kind: "note",
                comment: "Standalone",
                link: "[[ref/chat/alpha#^n-1]]"
            ),
        ]
    }

    private static func twoNotes() -> [RefsShowAnnotation] {
        (1...2).map { index in
            RefsShowAnnotation(
                pageLabel: "\(index)",
                kind: "highlight",
                quote: "Quote \(index)",
                comment: "Comment \(index)"
            )
        }
    }

    // MARK: - Harness

    @MainActor
    fileprivate final class Harness {
        let library: RefsLibrary
        let model: RefsPanelModel
        let opener: FakeOpener
        let pasteboard: FakePasteboard
        let openLogStore: RefsOpenLogStore
        let vault: URL
        let highlightsURL: URL?
        nonisolated(unsafe) var dismissed = 0
        nonisolated(unsafe) var presented = 0
        nonisolated(unsafe) var represented = 0

        init(
            library: RefsLibrary,
            model: RefsPanelModel,
            opener: FakeOpener,
            pasteboard: FakePasteboard,
            openLogStore: RefsOpenLogStore,
            vault: URL,
            highlightsURL: URL?
        ) {
            self.library = library
            self.model = model
            self.opener = opener
            self.pasteboard = pasteboard
            self.openLogStore = openLogStore
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

        func waitForScan() async {
            let deadline = Date().addingTimeInterval(15)
            while Date() < deadline {
                if model.scanNotice != nil, !model.isScanning {
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("scan did not finish before timeout")
        }

        func waitForScanStart() async {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                if model.isScanning {
                    return
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            XCTFail("scan did not start before timeout")
        }
    }

    private func makeHarness(
        highlightsURL: URL? = URL(fileURLWithPath: "/Applications/Highlights.app"),
        missing: Set<String> = [],
        environment: [String: String] = [:],
        tabsReader: FakeTabsReader? = nil,
        isAdHocSigned: Bool = false
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
        let openLogStore = RefsOpenLogStore(
            fileURL: root.appendingPathComponent("refs-open-log.json")
        )
        let library = RefsLibrary(
            fetcher: BobRefsFetcher(client: try bobClient(environment: environment)),
            snapshotStore: RefsSnapshotStore(
                fileURL: root.appendingPathComponent("refs-snapshot.json")
            ),
            openLogStore: openLogStore,
            vaultRoot: { vault },
            fileExists: { url in !missing.contains(where: { url.path.hasSuffix($0) }) },
            spotlight: FakeSpotlight(),
            now: { Date() }
        )
        let opener = FakeOpener()
        let pasteboard = FakePasteboard()
        let locator = FakeLocator(appURL: highlightsURL)
        let model = RefsPanelModel(
            library: library,
            opener: opener,
            highlights: locator,
            pasteboard: pasteboard,
            tabs: tabsReader.map { HighlightsTabsSession(reader: $0) },
            isAdHocSigned: { isAdHocSigned }
        )
        let harness = Harness(
            library: library,
            model: model,
            opener: opener,
            pasteboard: pasteboard,
            openLogStore: openLogStore,
            vault: vault,
            highlightsURL: highlightsURL
        )
        model.panelDismisser = { [weak harness] in harness?.dismissed += 1 }
        model.tabCloseDismisser = { [weak harness] in harness?.dismissed += 1 }
        model.panelPresenter = { [weak harness] in harness?.presented += 1 }
        // The error re-show path keeps every bit of panel state, like the
        // real coordinator-backed representer.
        model.panelRepresenter = { [weak harness] in harness?.represented += 1 }
        // Kick off the snapshot refresh every test waits for: nothing in the
        // model triggers one on its own.
        library.refresh(reason: .manual)
        return harness
    }

    private func makeRenameHarness(
        fetcher: FakeRefsFetcher,
        tabsReader: FakeTabsReader? = nil
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
        let openLogStore = RefsOpenLogStore(
            fileURL: root.appendingPathComponent("refs-open-log.json")
        )
        let library = RefsLibrary(
            fetcher: fetcher,
            snapshotStore: RefsSnapshotStore(
                fileURL: root.appendingPathComponent("refs-snapshot.json")
            ),
            openLogStore: openLogStore,
            vaultRoot: { vault },
            fileExists: { _ in true },
            spotlight: FakeSpotlight(),
            now: { Date() }
        )
        let opener = FakeOpener()
        let pasteboard = FakePasteboard()
        let model = RefsPanelModel(
            library: library,
            opener: opener,
            highlights: FakeLocator(appURL: nil),
            pasteboard: pasteboard,
            tabs: tabsReader.map { HighlightsTabsSession(reader: $0) }
        )
        let harness = Harness(
            library: library,
            model: model,
            opener: opener,
            pasteboard: pasteboard,
            openLogStore: openLogStore,
            vault: vault,
            highlightsURL: nil
        )
        model.tabCloseDismisser = { [weak harness] in harness?.dismissed += 1 }
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

    private func todayLinkFixture(_ name: String) throws -> RefsTodayLinkResponse {
        try JSONDecoder().decode(
            RefsTodayLinkResponse.self,
            from: Data(contentsOf: harnessFixtureURL(name))
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

    /// Serves a `refs-list.json` variant with one row's `added` rewritten,
    /// so a refresh re-ranks from visibly new data.
    func serveAddedVariant(path: String, added: String) throws {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let data = try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/refs-list.json")
        )
        var document = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let refs = (document["refs"] as! [[String: Any]]).map { row -> [String: Any] in
            guard (row["path"] as! String) == path else {
                return row
            }
            var edited = row
            edited["added"] = added
            edited["added_source"] = "created"
            return edited
        }
        document["refs"] = refs
        let variant = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try JSONSerialization.data(withJSONObject: document).write(to: variant)
        library.setFetcher(
            BobRefsFetcher(client: try client(environment: [
                "FAKE_BOB_REFS_LIST_FIXTURE": variant.path,
            ]))
        )
    }
}

private func harnessFixtureURL(_ name: String) throws -> URL {
    let source = URL(fileURLWithPath: #filePath)
    let packageRoot = source
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let direct = packageRoot.appendingPathComponent("Tests/Fixtures/\(name)")
    guard FileManager.default.fileExists(atPath: direct.path) else {
        throw NSError(
            domain: "RefsPanelModelTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"]
        )
    }
    return direct
}

/// Today's date as `YYYY-MM-DD`, the `added` form `bob` emits.
private func todayDateString() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter.string(from: Date())
}

/// How many fake-bob invocations start with `prefix` in a record file.
private func argvCount(_ recordURL: URL, prefix: String) -> Int {
    let record = (try? String(contentsOf: recordURL)) ?? ""
    return record.components(separatedBy: prefix).count - 1
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

final class FakeTabsReader: HighlightsTabsReading, @unchecked Sendable {
    private let lock = NSLock()
    private var trusted: Bool
    private var nextResult: HighlightsTabsReadResult?
    private var defaultResult: HighlightsTabsReadResult = .failed("No fake result")
    private var selectResult: HighlightsTabSelectResult
    private var readDelayNanoseconds: UInt64
    private var closeResults: [HighlightsTabCloseResult] = []
    private var closeDelayNanoseconds: UInt64 = 0
    private var closedTargets: [HighlightsTabTarget] = []
    private var activeCloses = 0
    private var maxCloses = 0
    private var quitResult = true
    private var quits = 0
    private var reads = 0
    private var targets: [HighlightsTabTarget] = []

    init(
        isTrusted: Bool,
        selectResult: HighlightsTabSelectResult = .selected,
        readDelayNanoseconds: UInt64 = 0
    ) {
        trusted = isTrusted
        self.selectResult = selectResult
        self.readDelayNanoseconds = readDelayNanoseconds
    }

    var readCount: Int {
        lock.withLock { reads }
    }

    var selectedTargets: [HighlightsTabTarget] {
        lock.withLock { targets }
    }

    var closeTargets: [HighlightsTabTarget] {
        lock.withLock { closedTargets }
    }

    var maxConcurrentCloses: Int {
        lock.withLock { maxCloses }
    }

    var quitCount: Int {
        lock.withLock { quits }
    }

    func setNextResult(_ result: HighlightsTabsReadResult) {
        lock.withLock {
            nextResult = result
        }
    }

    func setReadDelay(_ delay: UInt64) {
        lock.withLock {
            readDelayNanoseconds = delay
        }
    }

    func setNextCloseResults(_ results: [HighlightsTabCloseResult]) {
        lock.withLock {
            closeResults = results
        }
    }

    func setCloseDelay(_ delay: UInt64) {
        lock.withLock {
            closeDelayNanoseconds = delay
        }
    }

    func isTrusted() -> Bool {
        lock.withLock { trusted }
    }

    func requestTrust() {
        lock.withLock {
            trusted = true
        }
    }

    func read() async -> HighlightsTabsReadResult {
        let (result, delay) = lock.withLock { () -> (HighlightsTabsReadResult, UInt64) in
            reads += 1
            let result = nextResult ?? defaultResult
            nextResult = nil
            return (result, readDelayNanoseconds)
        }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        return result
    }

    func select(_ target: HighlightsTabTarget) async -> HighlightsTabSelectResult {
        lock.withLock {
            targets.append(target)
            return selectResult
        }
    }

    func close(_ target: HighlightsTabTarget) async -> HighlightsTabCloseResult {
        let (result, delay) = lock.withLock { () -> (HighlightsTabCloseResult, UInt64) in
            closedTargets.append(target)
            activeCloses += 1
            maxCloses = max(maxCloses, activeCloses)
            let result = closeResults.isEmpty
                ? HighlightsTabCloseResult.failed("No fake close result")
                : closeResults.removeFirst()
            return (result, closeDelayNanoseconds)
        }
        if delay > 0 {
            try? await Task.sleep(nanoseconds: delay)
        }
        lock.withLock {
            activeCloses -= 1
        }
        return result
    }

    func quitIfNoDocuments() async -> Bool {
        lock.withLock {
            quits += 1
            return quitResult
        }
    }
}

private actor TodayLinkResponseGate {
    private var requestCount = 0
    private var pending: [Int: CheckedContinuation<RefsTodayLinkResponse, Error>] = [:]
    private var completed: Set<Int> = []

    func respond() async throws -> RefsTodayLinkResponse {
        let index = requestCount
        requestCount += 1
        do {
            let response = try await withCheckedThrowingContinuation { continuation in
                pending[index] = continuation
            }
            markCompleted(index)
            return response
        } catch {
            markCompleted(index)
            throw error
        }
    }

    @discardableResult
    func waitForRequests(
        _ count: Int,
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while requestCount < count {
            guard ContinuousClock.now < deadline else {
                XCTFail("expected \(count) today-link requests before timeout", file: file, line: line)
                return false
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @discardableResult
    func waitForCompletion(
        _ index: Int,
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !completed.contains(index) {
            guard ContinuousClock.now < deadline else {
                XCTFail("today-link request \(index) did not complete before timeout", file: file, line: line)
                return false
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    @discardableResult
    func resolve(
        _ index: Int,
        with result: Result<RefsTodayLinkResponse, Error>,
        timeout: Duration = .seconds(5),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while pending[index] == nil {
            guard ContinuousClock.now < deadline else {
                XCTFail("today-link request \(index) was not ready to resolve before timeout", file: file, line: line)
                return false
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        pending.removeValue(forKey: index)?.resume(with: result)
        return true
    }

    private func markCompleted(_ index: Int) {
        completed.insert(index)
    }
}
