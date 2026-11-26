import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class SnoozeWakeSchedulerTests: XCTestCase {
    private final class FakeClock: @unchecked Sendable {
        var now = Date(timeIntervalSince1970: 1_787_921_990)
        var today = "2026-08-28"
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot =
            source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return
            packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func client(
        environment: [String: String] = [:],
        recordURL: URL
    ) throws -> BobProcessClient {
        var full = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ]
        for (key, value) in environment {
            full[key] = value
        }
        return BobProcessClient(executablePath: try fakeBobPath(), environment: full)
    }

    private func makeStore(
        client: BobProcessClient,
        clock: FakeClock,
        workspaceCenter: NotificationCenter,
        defaultCenter: NotificationCenter
    ) -> CaptureAgendaStore {
        CaptureAgendaStore(
            processClient: client,
            vaultRootPath: "/vault",
            today: { clock.today },
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter
        )
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
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func lines(in recordURL: URL) -> [String] {
        (try? String(contentsOf: recordURL))?.split(separator: "\n").map(String.init) ?? []
    }

    private func makeScheduler(
        store: CaptureAgendaStore,
        client: BobProcessClient,
        clock: FakeClock,
        workspaceCenter: NotificationCenter,
        defaultCenter: NotificationCenter
    ) -> SnoozeWakeScheduler {
        SnoozeWakeScheduler(
            agendaStore: store,
            processClient: client,
            now: { clock.now },
            today: { clock.today },
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter
        )
    }

    func testWakeRunsWithPanelHiddenAndAgendaSettingOffThenRefreshesFacts() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let workspaceCenter = NotificationCenter()
        let defaultCenter = NotificationCenter()
        let clock = FakeClock()
        let client = try client(
            environment: [
                "FAKE_BOB_AGENDA_FIXTURE": "agenda-snoozed.json",
                "FAKE_BOB_SNOOZE_WAKE_DELAY_SECONDS": "0.2",
                "FAKE_BOB_SNOOZE_WAKE_JSON":
                    #"{"schema_version":1,"status":"woke","next_wake_at":null}"#,
            ],
            recordURL: recordURL
        )
        let store = makeStore(
            client: client,
            clock: clock,
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter
        )
        let scheduler = makeScheduler(
            store: store,
            client: client,
            clock: clock,
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter
        )
        let panel = CapturePanelModel()
        panel.agendaEnabled = false
        XCTAssertFalse(panel.panelVisible)

        store.refresh(reason: .launch)
        await waitUntil {
            store.snapshot?.date == clock.today
                && scheduler.scheduledFireDateForTesting != nil
        }
        XCTAssertEqual(
            scheduler.scheduledFireDateForTesting,
            Date(timeIntervalSince1970: 1_787_922_005)
        )

        clock.now = Date(timeIntervalSince1970: 1_787_922_005)
        scheduler.fireDueWakeForTesting()
        await waitUntil(timeout: 8) {
            !scheduler.wakeInFlightForTesting
                && self.lines(in: recordURL).filter { $0 == "argv=snooze wake -q -f json" }.count
                    == 1
                && self.lines(in: recordURL).filter {
                    $0 == "argv=capture-pomodoros --format json --tasks"
                }.count >= 2
        }

        XCTAssertNil(scheduler.scheduledFireDateForTesting)
        scheduler.stop()
    }

    func testClockChangeAfterSleepRunsOneWakeAndRetainsRetryDeadline() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let workspaceCenter = NotificationCenter()
        let defaultCenter = NotificationCenter()
        let clock = FakeClock()
        let client = try client(
            environment: [
                "FAKE_BOB_AGENDA_FIXTURE": "agenda-snoozed.json",
                "FAKE_BOB_SNOOZE_WAKE_DELAY_SECONDS": "0.4",
                "FAKE_BOB_SNOOZE_WAKE_JSON":
                    #"{"schema_version":1,"status":"deferred","next_wake_at":"2026-08-28T09:00:00-04:00"}"#,
            ],
            recordURL: recordURL
        )
        let store = makeStore(
            client: client,
            clock: clock,
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter
        )
        let scheduler = makeScheduler(
            store: store,
            client: client,
            clock: clock,
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter
        )
        store.refresh(reason: .launch)
        await waitUntil { scheduler.scheduledFireDateForTesting != nil }

        clock.now = Date(timeIntervalSince1970: 1_787_922_020)
        defaultCenter.post(name: .NSSystemClockDidChange, object: nil)
        await waitUntil { self.lines(in: recordURL).contains("argv=snooze wake -q -f json") }
        scheduler.fireDueWakeForTesting()
        defaultCenter.post(name: .NSSystemClockDidChange, object: nil)
        await waitUntil(timeout: 8) { !scheduler.wakeInFlightForTesting }

        XCTAssertEqual(
            self.lines(in: recordURL).filter { $0 == "argv=snooze wake -q -f json" }.count,
            1
        )
        XCTAssertEqual(
            scheduler.scheduledFireDateForTesting,
            Date(timeIntervalSince1970: 1_787_922_080)
        )
        scheduler.stop()
    }

    func testReconfigureDoesNotCancelOldWriteOrApplyItsReplyToNewClient() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let workspaceCenter = NotificationCenter()
        let defaultCenter = NotificationCenter()
        let clock = FakeClock()
        let oldClient = try client(
            environment: [
                "FAKE_BOB_AGENDA_FIXTURE": "agenda-snoozed.json",
                "FAKE_BOB_SNOOZE_WAKE_DELAY_SECONDS": "0.4",
                "FAKE_BOB_SNOOZE_WAKE_JSON":
                    #"{"schema_version":1,"status":"woke","next_wake_at":"2026-08-28T19:00:00-04:00"}"#,
            ],
            recordURL: recordURL
        )
        let store = makeStore(
            client: oldClient,
            clock: clock,
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter
        )
        let scheduler = makeScheduler(
            store: store,
            client: oldClient,
            clock: clock,
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter
        )
        let termURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let oldClientWithTerm = try client(
            environment: [
                "FAKE_BOB_AGENDA_FIXTURE": "agenda-snoozed.json",
                "FAKE_BOB_SNOOZE_WAKE_DELAY_SECONDS": "0.4",
                "FAKE_BOB_SNOOZE_WAKE_JSON":
                    #"{"schema_version":1,"status":"woke","next_wake_at":"2026-08-28T19:00:00-04:00"}"#,
                "FAKE_BOB_TERM_PATH": termURL.path,
            ],
            recordURL: recordURL
        )
        scheduler.reconfigure(processClient: oldClientWithTerm)
        store.processClient = oldClientWithTerm
        store.reset()
        await waitUntil { store.snapshot?.date == clock.today }
        clock.now = Date(timeIntervalSince1970: 1_787_922_005)
        scheduler.fireDueWakeForTesting()
        await waitUntil {
            self.lines(in: recordURL).filter { $0.contains("snooze wake") }.count == 1
        }

        let newClient = try client(
            environment: ["FAKE_BOB_AGENDA_FIXTURE": "agenda-current.json"],
            recordURL: recordURL
        )
        scheduler.reconfigure(processClient: newClient)
        store.processClient = newClient
        store.reset()
        await waitUntil(timeout: 8) {
            !scheduler.wakeInFlightForTesting
                && store.snapshot?.date == clock.today
                && !store.snapshot!.pomodoros.isEmpty
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: termURL.path))
        XCTAssertNil(scheduler.scheduledFireDateForTesting)
        XCTAssertEqual(
            self.lines(in: recordURL).filter { $0.contains("argv=snooze wake") }.count,
            1
        )
        scheduler.stop()
    }
}
