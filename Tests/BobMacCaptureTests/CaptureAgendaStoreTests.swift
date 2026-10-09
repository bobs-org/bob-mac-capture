import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureAgendaStoreTests: XCTestCase {
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

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail(
                    "Condition not met before timeout",
                    file: file,
                    line: line
                )
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func makeClient(
        environment: [String: String] = [:],
        recordURL: URL? = nil
    ) throws -> BobProcessClient {
        var full = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        for (key, value) in environment {
            full[key] = value
        }
        if let recordURL {
            full["FAKE_BOB_RECORD_PATH"] = recordURL.path
        }
        return BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: full
        )
    }

    private func makeStore(
        environment: [String: String] = [:],
        recordURL: URL? = nil,
        workspaceCenter: NotificationCenter? = nil,
        defaultCenter: NotificationCenter? = nil
    ) throws -> CaptureAgendaStore {
        CaptureAgendaStore(
            processClient: try makeClient(
                environment: environment,
                recordURL: recordURL
            ),
            vaultRootPath: "/vault",
            today: { "2026-08-28" },
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter ?? NotificationCenter()
        )
    }

    private func recordArgv(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url) else {
            return []
        }
        return text.split(separator: "\n").map(String.init).filter {
            $0.hasPrefix("argv=")
        }
    }

    private func isStale(_ status: CaptureAgendaStoreStatus) -> Bool {
        if case .stale = status {
            return true
        }
        return false
    }

    // MARK: - Refresh and publish

    func testRefreshPublishesTodaySnapshotAndCount() async throws {
        let store = try makeStore()
        store.refresh(reason: .show)
        await waitUntil { store.currentTaskLinkCount == 3 }
        XCTAssertEqual(store.snapshot?.date, "2026-08-28")
        XCTAssertEqual(store.snapshot?.currentTaskLinkCount, 3)
        XCTAssertEqual(store.status, .ready)
        XCTAssertNotNil(store.lastRefreshedAt)
    }

    func testUnchangedBytesPublishNothing() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = try makeStore(recordURL: recordURL)
        var published: [Int] = []
        let cancellable = store.$snapshot.sink {
            published.append($0?.pomodoros.count ?? -1)
        }
        store.refresh(reason: .show)
        await waitUntil { store.currentTaskLinkCount == 3 }
        store.refresh(reason: .show)
        await waitUntil(timeout: 10) {
            self.recordArgv(recordURL).count == 2
        }
        try? await Task.sleep(nanoseconds: 300_000_000)
        // One subscribe emission plus the first snapshot; the identical
        // second fetch publishes nothing.
        XCTAssertEqual(published, [-1, 4])
        XCTAssertNotNil(cancellable)
    }

    func testConcurrentTriggersCoalesceToOneFollowUp() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = try makeStore(
            environment: ["FAKE_BOB_DELAY_SECONDS": "1"],
            recordURL: recordURL
        )
        store.refresh(reason: .show)
        store.refresh(reason: .watcher)
        store.refresh(reason: .submit)
        await waitUntil(timeout: 10) {
            self.recordArgv(recordURL).filter {
                $0.contains("--tasks")
            }.count == 2
        }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(
            recordArgv(recordURL).filter { $0.contains("--tasks") }.count,
            2
        )
        XCTAssertEqual(store.status, .ready)
    }

    func testFailureKeepsSnapshotAndNilsCount() async throws {
        let store = try makeStore()
        store.refresh(reason: .show)
        await waitUntil { store.currentTaskLinkCount == 3 }
        store.processClient = try makeClient(
            environment: ["FAKE_BOB_AGENDA_FAIL": "1"]
        )
        store.refresh(reason: .show)
        await waitUntil { self.isStale(store.status) }
        XCTAssertEqual(store.snapshot?.date, "2026-08-28")
        XCTAssertNil(store.currentTaskLinkCount)
    }

    func testYesterdaySnapshotStaysHidden() async throws {
        let store = try makeStore(
            environment: ["FAKE_BOB_AGENDA_FIXTURE": "agenda-yesterday.json"]
        )
        store.refresh(reason: .show)
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.currentTaskLinkCount)
        XCTAssertEqual(store.status, .loading)
    }

    // MARK: - Old bob fallback

    func testUnsupportedFallsBackAndStaysUntilReset() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = try makeStore(
            environment: [
                "FAKE_BOB_AGENDA_UNSUPPORTED": "1",
                "FAKE_BOB_POMODOROS_FIXTURE": "pomodoros-current-3.json",
            ],
            recordURL: recordURL
        )
        store.refresh(reason: .show)
        await waitUntil { store.currentTaskLinkCount == 3 }
        XCTAssertNil(store.snapshot)
        XCTAssertEqual(store.status, .unsupported)
        store.refresh(reason: .show)
        await waitUntil(timeout: 10) {
            self.recordArgv(recordURL).filter {
                !$0.contains("--tasks")
            }.count == 2
        }
        // The plain lane ran twice; `--tasks` was never retried.
        XCTAssertEqual(
            recordArgv(recordURL).filter { $0.contains("--tasks") }.count,
            1
        )
        // A reset with a supporting bob retries `--tasks` fresh.
        store.processClient = try makeClient(recordURL: recordURL)
        store.reset()
        await waitUntil(timeout: 10) { store.status == .ready }
        XCTAssertEqual(
            recordArgv(recordURL).filter { $0.contains("--tasks") }.count,
            2
        )
    }

    // MARK: - Watcher batches

    func testIrrelevantBatchSpawnsNothing() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = try makeStore(recordURL: recordURL)
        store.vaultDidChange(
            VaultChangeBatch(paths: ["/vault/.git/index"], flags: [])
        )
        store.vaultDidChange(
            VaultChangeBatch(
                paths: ["/vault/.obsidian/workspace.json"],
                flags: []
            )
        )
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(recordArgv(recordURL), [])
        store.vaultDidChange(
            VaultChangeBatch(paths: ["/vault/inbox.md"], flags: [])
        )
        await waitUntil { store.currentTaskLinkCount == 3 }
    }

    func testShowRefreshSpawnsExactlyOneAgendaCall() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let store = try makeStore(recordURL: recordURL)
        store.refresh(reason: .show)
        await waitUntil { store.status == .ready }
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(
            recordArgv(recordURL).filter { $0.contains("--tasks") }.count,
            1
        )
    }

    // MARK: - Client replacement

    func testNilClientDiscardsLateResult() async throws {
        let store = try makeStore(
            environment: ["FAKE_BOB_DELAY_SECONDS": "1"]
        )
        store.refresh(reason: .show)
        store.processClient = nil
        XCTAssertNil(store.currentTaskLinkCount)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertNil(store.snapshot)
        XCTAssertNil(store.currentTaskLinkCount)
    }

    // MARK: - System observers

    func testWakeAndDayChangeRefresh() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let workspaceCenter = NotificationCenter()
        let defaultCenter = NotificationCenter()
        let store = try makeStore(
            recordURL: recordURL,
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter
        )
        workspaceCenter.post(
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        await waitUntil(timeout: 10) {
            self.recordArgv(recordURL).filter {
                $0.contains("--tasks")
            }.count == 1
        }
        defaultCenter.post(name: .NSCalendarDayChanged, object: nil)
        await waitUntil(timeout: 10) {
            self.recordArgv(recordURL).filter {
                $0.contains("--tasks")
            }.count == 2
        }
    }

    // MARK: - Model derivation

    func testModelDerivesCountFromStore() async throws {
        let store = try makeStore()
        let model = CapturePanelModel()
        model.agendaStore = store
        store.refresh(reason: .show)
        await waitUntil { model.currentPomodoroTaskLinkCount == 3 }
        XCTAssertTrue(model.closeTaskCommaArmed)
    }
}
