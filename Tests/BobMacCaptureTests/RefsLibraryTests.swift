import AppKit
import Foundation
import XCTest

@testable import BobMacCapture
@testable import CaptureCore
@testable import RefsCore

/// Library refresh tests against fake-bob: cache-first paint, snapshot
/// replacement, failure and schema-mismatch keeping the last good
/// snapshot, lossy rows, the git-date pass, per-lane coalescing, Today
/// loading with a sticky last-Today, open history, missing PDFs, and
/// stale checks.
@MainActor
final class RefsLibraryTests: XCTestCase {
    func testCacheFirstPaintThenRefreshReplacesSnapshot() async throws {
        let context = try makeContext()
        let seeded = try seedSnapshot(
            context: context,
            fixture: "refs-list.json",
            dropping: ["ref/blogs/small_opened.md"]
        )
        XCTAssertEqual(seeded.records.count, 5)

        context.library.start()
        XCTAssertTrue(context.library.hasSnapshot)
        XCTAssertEqual(
            context.library.items.map(\.id).sorted(),
            seeded.records.map(\.path).sorted()
        )

        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }
        XCTAssertEqual(context.library.items.count, 6)
        guard case .idle = context.library.refreshState else {
            XCTFail("expected idle after a successful refresh")
            return
        }
    }

    func testFailureKeepsLastGoodSnapshotAndSetsFailed() async throws {
        let context = try makeContext(environment: ["FAKE_BOB_EXIT": "1"])
        let seeded = try seedSnapshot(context: context, fixture: "refs-list.json")
        let before = seeded.records.map(\.path).sorted()

        context.library.start()
        await waitUntil(timeout: 15) {
            if case .failed = context.library.refreshState {
                return true
            }
            return false
        }
        XCTAssertEqual(context.library.items.map(\.id).sorted(), before)
        XCTAssertTrue(context.library.hasSnapshot)
    }

    func testSchemaMismatchTreatedAsFailure() async throws {
        let schema3 = try fixtureURL("refs-plan-schema3.json").path
        let context = try makeContext(environment: [
            "FAKE_BOB_REFS_LIST_FIXTURE": schema3,
        ])
        let seeded = try seedSnapshot(context: context, fixture: "refs-list.json")
        let before = seeded.records.map(\.path).sorted()

        context.library.start()
        await waitUntil(timeout: 15) {
            if case .failed = context.library.refreshState {
                return true
            }
            return false
        }
        XCTAssertEqual(context.library.items.map(\.id).sorted(), before)
    }

    func testLossyRowsSurviveRefresh() async throws {
        let golden = try fixtureURL("refs-list-golden.json").path
        let context = try makeContext(environment: [
            "FAKE_BOB_REFS_LIST_FIXTURE": golden,
        ])

        context.library.refresh(reason: .manual)
        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }
        // 44 golden rows minus the title-less row skipped at decode and the
        // row without a usable PDF dropped by the catalog.
        XCTAssertEqual(context.library.items.count, 42)
    }

    func testGitPassRunsOnlyWhenNeededAndMerges() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let context = try makeContext(environment: ["FAKE_BOB_RECORD_PATH": recordURL.path])

        context.library.refresh(reason: .manual)
        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }
        // The `-g` lane starts after the snapshot publishes, so wait for
        // its invocation before asserting on the record.
        await waitUntil(timeout: 15) {
            ((try? String(contentsOf: recordURL)) ?? "")
                .contains("argv=ref list -R all -A -f json -g")
        }
        // The lane merges after the snapshot publishes, so wait for the
        // backfilled date instead of reading it mid-flight.
        await waitUntil(timeout: 15) {
            context.library.items.first {
                $0.id == "ref/blogs/small_opened.md"
            }?.added?.isoString == "2026-09-11"
        }
        let opened = context.library.items.first {
            $0.id == "ref/blogs/small_opened.md"
        }
        XCTAssertEqual(opened?.addedSource, "git")
        XCTAssertTrue(opened?.addedIsApproximate ?? false)
        let created = context.library.items.first {
            $0.id == "ref/chat/small_reading.md"
        }
        XCTAssertEqual(created?.added?.isoString, "2026-10-01")
        XCTAssertFalse(created?.addedIsApproximate ?? true)
    }

    func testGitPassFailureKeepsSnapshotAndStaysIdle() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let context = try makeContext(environment: [
            "FAKE_BOB_REFS_GIT_EXIT": "1",
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ])

        context.library.refresh(reason: .manual)
        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }
        // Wait until the `-g` lane ran, then let it finish: the snapshot
        // stays published and the state never flips to failed.
        await waitUntil(timeout: 15) {
            ((try? String(contentsOf: recordURL)) ?? "").contains("-g")
        }
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(context.library.items.count, 6)
        XCTAssertTrue(context.library.hasSnapshot)
        guard case .idle = context.library.refreshState else {
            XCTFail("a -g failure must not fail the refresh")
            return
        }
    }

    func testWakeNotificationTriggersSnapshotRefresh() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let center = NotificationCenter()
        let context = try makeContext(
            environment: ["FAKE_BOB_RECORD_PATH": recordURL.path],
            wakeCenter: center
        )

        context.library.start()
        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }
        // Settle the `-g` lane before the baseline, so only the wake
        // refresh can add a later list call.
        await waitUntil(timeout: 15) {
            context.library.items.contains {
                $0.id == "ref/blogs/small_opened.md" && $0.added != nil
            }
        }
        let launches = try String(contentsOf: recordURL)
            .components(separatedBy: "argv=ref list").count

        center.post(name: NSWorkspace.didWakeNotification, object: nil)

        await waitUntil(timeout: 15) {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return record.components(separatedBy: "argv=ref list").count > launches
        }
        context.library.stop()
    }

    func testGitPassSkippedWhenEveryRowHasAdded() async throws {
        let git = try fixtureURL("refs-list-git.json").path
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let context = try makeContext(environment: [
            "FAKE_BOB_REFS_LIST_FIXTURE": git,
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ])

        context.library.refresh(reason: .manual)
        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }

        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("-g"))
    }

    func testTriggersDuringRefreshRunExactlyOneFollowUp() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let context = try makeContext(environment: [
            "FAKE_BOB_DELAY_SECONDS": "2",
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ])

        context.library.refresh(reason: .manual)
        context.library.refresh(reason: .manual)
        context.library.refresh(reason: .manual)

        // Three triggers, two snapshot passes (the run plus one follow-up).
        // The first pass runs the plain and the git list calls; the follow-up
        // reuses the just-backfilled git dates and skips its git pass, which
        // only runs when needed.
        await waitUntil(timeout: 40) {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return record.components(separatedBy: "argv=ref list").count == 4
        }
        try? await Task.sleep(nanoseconds: 4_000_000_000)
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=ref list").count, 4)
        XCTAssertEqual(record.components(separatedBy: "argv=plan -f json").count, 3)
    }

    func testTodayLoadsAndSchemaMismatchKeepsLastToday() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let context = try makeContext(environment: ["FAKE_BOB_RECORD_PATH": recordURL.path])

        context.library.refresh(reason: .manual)
        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }
        // The Today lane runs beside the snapshot lane, so wait for the lane
        // this test asserts instead of reading it mid-flight.
        await waitUntil(timeout: 15) {
            context.library.signals.today.entries.count == 4
        }
        XCTAssertEqual(context.library.signals.today.entries.count, 4)

        let schema3 = try fixtureURL("refs-plan-schema3.json").path
        context.library.setFetcher(try planClient(
            recordURL: recordURL,
            environment: ["FAKE_BOB_PLAN_FIXTURE": schema3]
        ))
        context.library.refreshToday(reason: .manual)
        await waitUntil(timeout: 15) {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return record.components(separatedBy: "argv=plan -f json").count == 3
        }
        XCTAssertEqual(context.library.signals.today.entries.count, 4)
    }

    func testRecordOpenAndResetHistory() async throws {
        let context = try makeContext()

        context.library.refresh(reason: .manual)
        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }

        context.library.recordOpen(id: "ref/chat/small_reading.md")
        XCTAssertEqual(context.library.signals.opens.count("ref/chat/small_reading.md"), 1)
        XCTAssertNotNil(context.library.signals.opens.lastOpened("ref/chat/small_reading.md"))

        context.library.resetOpenHistory()
        XCTAssertEqual(context.library.signals.opens.count("ref/chat/small_reading.md"), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: context.openLogURL.path))
    }

    func testMissingPDFsPublishedFromFileChecks() async throws {
        let context = try makeContext(fileExists: { url in
            !url.path.hasSuffix("lib/chat/small_reading.pdf")
        })

        context.library.refresh(reason: .manual)
        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }

        XCTAssertEqual(context.library.signals.missingPDFs, ["ref/chat/small_reading.md"])
    }

    func testPdfURLNilWhenUnsafe() throws {
        let context = try makeContext()
        let item = RefItem(
            id: "ref/chat/x.md",
            link: "[[ref/chat/x]]",
            rawTitle: "X",
            stem: "x",
            kind: .chat,
            state: .reading,
            isBlocked: false,
            pdfPath: "lib/chat/x.pdf"
        )

        XCTAssertNotNil(context.library.pdfURL(for: item))
        XCTAssertEqual(
            context.library.noteURL(for: item).path,
            context.vault.appendingPathComponent("ref/chat/x.md").path
        )
        XCTAssertNil(context.library.pdfURL(for: unsafe(item: item, pdf: "/abs/x.pdf")))
        XCTAssertNil(context.library.pdfURL(for: unsafe(item: item, pdf: "../x.pdf")))
        XCTAssertNil(context.library.pdfURL(for: unsafe(item: item, pdf: "lib/../../x.pdf")))
    }

    func testRefreshIfStale() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let context = try makeContext(environment: ["FAKE_BOB_RECORD_PATH": recordURL.path])

        context.library.refreshIfStale()
        await waitUntil(timeout: 15) { context.library.lastSuccessAt != nil }
        // Both lanes record argv lines; wait for Today too so a late plan
        // call cannot land between the baseline count and the quiet check.
        await waitUntil(timeout: 15) {
            context.library.signals.today.entries.count == 4
        }
        // Settle the `-g` lane before the baseline. It starts after the
        // snapshot publishes, so a late git argv line otherwise lands inside
        // the quiet window and the counts disagree (4 vs 3).
        await waitUntil(timeout: 15) {
            context.library.items.contains {
                $0.id == "ref/blogs/small_opened.md" && $0.added != nil
            }
        }
        let staleRecord = try String(contentsOf: recordURL)
        let count = staleRecord.components(separatedBy: "argv=").count

        context.library.refreshIfStale()
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        let quietRecord = try String(contentsOf: recordURL)
        XCTAssertEqual(quietRecord.components(separatedBy: "argv=").count, count)

        context.library.markStale()
        context.library.refreshIfStale()
        await waitUntil(timeout: 15) {
            let record = (try? String(contentsOf: recordURL)) ?? ""
            return record.components(separatedBy: "argv=").count > count
        }
    }

    func testScanRunsOneScanArgv() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let context = try makeContext(environment: [
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ])
        _ = try seedSnapshot(context: context, fixture: "refs-list.json")

        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished = context.library.scanState {
                return true
            }
            return false
        }
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(
            record.components(separatedBy: "argv=ref scan -w -f json").count - 1,
            1
        )
        guard case .finished(let outcome) = context.library.scanState else {
            XCTFail("expected finished")
            return
        }
        XCTAssertEqual(outcome.kind, .succeeded)
        XCTAssertEqual(outcome.created.count, 2)
    }

    func testSecondScanMidFlightReturnsFalse() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let context = try makeContext(environment: [
            "FAKE_BOB_DELAY_SECONDS": "2",
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ])
        _ = try seedSnapshot(context: context, fixture: "refs-list.json")

        XCTAssertTrue(context.library.scan())
        XCTAssertFalse(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished = context.library.scanState {
                return true
            }
            return false
        }
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(
            record.components(separatedBy: "argv=ref scan -w -f json").count - 1,
            1
        )
    }

    func testFinishedAfterPostScanListWithNewRows() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let markerDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: markerDir,
            withIntermediateDirectories: true
        )
        let context = try makeContext(environment: [
            "FAKE_BOB_RECORD_PATH": recordURL.path,
            "FAKE_BOB_SCAN_MARKER_DIR": markerDir.path,
            "FAKE_BOB_REFS_LIST_AFTER_SCAN_FIXTURE": "refs-list-after-scan.json",
        ])
        _ = try seedSnapshot(context: context, fixture: "refs-list.json")

        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished = context.library.scanState {
                return true
            }
            return false
        }
        XCTAssertTrue(context.library.items.contains {
            $0.id == "ref/chat/omni_report.md"
        })
        XCTAssertTrue(context.library.items.contains {
            $0.id == "ref/papers/harness_notes.md"
        })
        let record = try String(contentsOf: recordURL)
        guard let scanRange = record.range(of: "argv=ref scan -w -f json"),
            let listRange = record.range(of: "argv=ref list -R all -A -f json")
        else {
            XCTFail("expected scan and post-scan list in record")
            return
        }
        XCTAssertTrue(scanRange.lowerBound < listRange.lowerBound)
    }

    func testWatcherDeferredDuringScanThenOnePostScanPass() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let context = try makeContext(environment: [
            "FAKE_BOB_DELAY_SECONDS": "2",
            "FAKE_BOB_RECORD_PATH": recordURL.path,
            "FAKE_BOB_REFS_LIST_FIXTURE": "refs-list-git.json",
        ])
        _ = try seedSnapshot(context: context, fixture: "refs-list-git.json")

        XCTAssertTrue(context.library.scan())
        context.library.handleWatcherChange()
        context.library.handleWatcherChange()
        try? await Task.sleep(nanoseconds: 500_000_000)
        let midRecord = (try? String(contentsOf: recordURL)) ?? ""
        XCTAssertFalse(midRecord.contains("argv=ref list"))
        await waitUntil(timeout: 15) {
            if case .finished = context.library.scanState {
                return true
            }
            return false
        }
        try? await Task.sleep(nanoseconds: 500_000_000)
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(
            record.components(separatedBy: "argv=ref list -R all -A -f json").count - 1,
            1
        )
    }

    func testScanMarkSetClearedAndKept() async throws {
        let context = try makeContext()
        _ = try seedSnapshot(context: context, fixture: "refs-list.json")

        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished = context.library.scanState {
                return true
            }
            return false
        }
        XCTAssertEqual(
            context.library.signals.scan?.ids,
            ["ref/chat/omni_report.md", "ref/papers/harness_notes.md"]
        )

        let nothingURL = try fixtureURL("refs-scan-nothing.json").path
        context.library.setFetcher(try scanClient(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": nothingURL,
        ]))
        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished(let outcome) = context.library.scanState,
                outcome.created.isEmpty,
                outcome.kind == .succeeded
            {
                return true
            }
            return false
        }
        XCTAssertNil(context.library.signals.scan)

        context.library.setFetcher(try scanClient(environment: [:]))
        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished(let outcome) = context.library.scanState,
                outcome.kind == .succeeded,
                !outcome.created.isEmpty
            {
                return true
            }
            return false
        }
        let markBeforeFailure = context.library.signals.scan
        XCTAssertNotNil(markBeforeFailure)

        let dirtyURL = try fixtureURL("refs-scan-dirty.json").path
        context.library.setFetcher(try scanClient(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": dirtyURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ]))
        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished(let outcome) = context.library.scanState,
                outcome.kind == .failed
            {
                return true
            }
            return false
        }
        XCTAssertEqual(context.library.signals.scan, markBeforeFailure)
    }

    func testPartialOutcomeHasCreatedAndFailures() async throws {
        let partialURL = try fixtureURL("refs-scan-partial.json").path
        let context = try makeContext(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": partialURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        _ = try seedSnapshot(context: context, fixture: "refs-list.json")

        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished(let outcome) = context.library.scanState,
                outcome.kind == .partial
            {
                return true
            }
            return false
        }
        guard case .finished(let outcome) = context.library.scanState else {
            XCTFail("expected finished")
            return
        }
        XCTAssertEqual(outcome.created.map(\.path), ["ref/chat/fresh_report.md"])
        XCTAssertEqual(outcome.failures.count, 2)
        XCTAssertNil(outcome.problem)
    }

    func testDirtyOutcomeIsFailedWithCodeAndPaths() async throws {
        let dirtyURL = try fixtureURL("refs-scan-dirty.json").path
        let context = try makeContext(environment: [
            "FAKE_BOB_REFS_SCAN_FIXTURE": dirtyURL,
            "FAKE_BOB_REFS_SCAN_EXIT": "1",
        ])
        _ = try seedSnapshot(context: context, fixture: "refs-list.json")

        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished(let outcome) = context.library.scanState,
                outcome.kind == .failed
            {
                return true
            }
            return false
        }
        guard case .finished(let outcome) = context.library.scanState else {
            XCTFail("expected finished")
            return
        }
        XCTAssertEqual(outcome.problem?.code, "dirty_targets")
        XCTAssertEqual(outcome.problem?.paths.count, 4)
    }

    func testExitTwoEmptyGivesBobTooOld() async throws {
        let context = try makeContext(environment: ["FAKE_BOB_EXIT": "2"])
        _ = try seedSnapshot(context: context, fixture: "refs-list.json")

        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished(let outcome) = context.library.scanState,
                outcome.kind == .failed
            {
                return true
            }
            return false
        }
        guard case .finished(let outcome) = context.library.scanState else {
            XCTFail("expected finished")
            return
        }
        XCTAssertEqual(outcome.problem?.code, "bob_too_old")
    }

    func testTimedOutGivesTimedOutProblem() async throws {
        let context = try makeContext()
        _ = try seedSnapshot(context: context, fixture: "refs-list.json")
        context.library.setFetcher(TimedOutRefsFetcher())

        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 15) {
            if case .finished(let outcome) = context.library.scanState,
                outcome.kind == .failed
            {
                return true
            }
            return false
        }
        guard case .finished(let outcome) = context.library.scanState else {
            XCTFail("expected finished")
            return
        }
        XCTAssertEqual(outcome.problem?.code, "timed_out")
    }

    func testNoFetcherGivesBobUnavailableAtOnce() async throws {
        let context = try makeContext()
        _ = try seedSnapshot(context: context, fixture: "refs-list.json")
        context.library.setFetcher(nil)

        XCTAssertTrue(context.library.scan())
        await waitUntil(timeout: 5) {
            if case .finished(let outcome) = context.library.scanState,
                outcome.kind == .failed
            {
                return true
            }
            return false
        }
        guard case .finished(let outcome) = context.library.scanState else {
            XCTFail("expected finished")
            return
        }
        XCTAssertEqual(outcome.problem?.code, "bob_unavailable")
    }

    // MARK: - Helpers

    private struct Context {
        let library: RefsLibrary
        let vault: URL
        let snapshotURL: URL
        let openLogURL: URL
    }

    private func makeContext(
        environment: [String: String] = [:],
        fileExists: @escaping (URL) -> Bool = { _ in true },
        spotlight: RefsSpotlightProviding = FakeSpotlight(),
        wakeCenter: NotificationCenter? = nil
    ) throws -> Context {
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
        let snapshotURL = root.appendingPathComponent("refs-snapshot.json")
        let openLogURL = root.appendingPathComponent("refs-open-log.json")
        let library = RefsLibrary(
            fetcher: BobRefsFetcher(client: try bobClient(environment: environment)),
            snapshotStore: RefsSnapshotStore(fileURL: snapshotURL),
            openLogStore: RefsOpenLogStore(fileURL: openLogURL),
            vaultRoot: { vault },
            fileExists: fileExists,
            spotlight: spotlight,
            now: { Date() },
            wakeCenter: wakeCenter ?? NSWorkspace.shared.notificationCenter
        )
        return Context(
            library: library,
            vault: vault,
            snapshotURL: snapshotURL,
            openLogURL: openLogURL
        )
    }

    @discardableResult
    private func seedSnapshot(
        context: Context,
        fixture: String,
        dropping: Set<String> = []
    ) throws -> RefsSnapshot {
        let data = try Data(contentsOf: fixtureURL(fixture))
        let response = try JSONDecoder().decode(RefsListResponse.self, from: data)
        let snapshot = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_700_000_000),
            records: response.refs.filter { !dropping.contains($0.path) }
        )
        RefsSnapshotStore(fileURL: context.snapshotURL).save(snapshot: snapshot, today: nil)
        return snapshot
    }

    private func planClient(
        recordURL: URL,
        environment: [String: String]
    ) throws -> BobRefsFetcher {
        var merged = environment
        merged["FAKE_BOB_RECORD_PATH"] = recordURL.path
        return BobRefsFetcher(client: try bobClient(environment: merged))
    }

    private func scanClient(environment: [String: String]) throws -> BobRefsFetcher {
        BobRefsFetcher(client: try bobClient(environment: environment))
    }

    private func bobClient(environment: [String: String]) throws -> BobProcessClient {
        BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
                .merging(environment) { _, override in override }
        )
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let direct = packageRoot.appendingPathComponent("Tests/Fixtures/\(name)")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        throw NSError(
            domain: "RefsLibraryTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "missing fixture \(name)"]
        )
    }

    private func unsafe(item: RefItem, pdf: String) -> RefItem {
        RefItem(
            id: item.id,
            link: item.link,
            rawTitle: item.rawTitle,
            stem: item.stem,
            kind: item.kind,
            state: item.state,
            isBlocked: item.isBlocked,
            pdfPath: pdf
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @MainActor @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
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

struct FakeSpotlight: RefsSpotlightProviding, Sendable {
    var facts: [String: RefsSpotlightFacts] = [:]

    func sweep(_ requests: [RefsSpotlightRequest]) async -> [String: RefsSpotlightFacts] {
        var result: [String: RefsSpotlightFacts] = [:]
        for request in requests {
            if let known = facts[request.id] {
                result[request.id] = known
            }
        }
        return result
    }
}

final class TimedOutRefsFetcher: RefsFetching, @unchecked Sendable {
    func list(gitDates: Bool) async throws -> RefsListResponse {
        RefsListResponse(schemaVersion: 1)
    }

    func plan() async throws -> RefsPlanResponse {
        RefsPlanResponse(schemaVersion: 2)
    }

    func show(path: String) async throws -> RefsShowResponse {
        RefsShowResponse(schemaVersion: 1, refs: [])
    }

    func scan() async throws -> RefsScanResponse {
        throw BobClientError.timedOut(command: ["bob", "ref", "scan"], seconds: 300)
    }
}
