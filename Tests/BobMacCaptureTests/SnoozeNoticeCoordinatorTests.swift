import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class SnoozeNoticeCoordinatorTests: XCTestCase {
    private final class FakeClock: @unchecked Sendable {
        var now: Date
        var today: String
        init(now: Date, today: String) {
            self.now = now
            self.today = today
        }
    }

    private func wokenDate() throws -> Date {
        try XCTUnwrap(CaptureRFC3339Date.date(from: "2026-11-26T15:32:00-05:00"))
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

    private func listJSON(
        rows: String, vaultRoot: String = "/tmp/vault", wakeNoticeVersion: Int? = 1
    ) -> String {
        let version = wakeNoticeVersion.map { "\"wake_notice_version\":\($0)," } ?? ""
        return
            """
            {"schema_version":1,\(version)"vault_root":"\(vaultRoot)",\
            "date":"2026-11-26","now":"2026-11-26T15:32:10-05:00",\
            "rows":[\(rows)],"next_wake_at":null,"plan":{"count":1,"cap":10,"over":false}}
            """
    }

    private func eligibleRowJSON() -> String {
        """
        {"line":4,"route":"tasks.md","block_id":"^job","title":"Email Dan",\
        "target":"1532","state":"woken","woke_at":"15:32","wake_notice_eligible":true}
        """
    }

    private func client(environment: [String: String]) throws -> BobProcessClient {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        var full = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ]
        for (key, value) in environment {
            full[key] = value
        }
        return BobProcessClient(
            executablePath: try fakeBobPath(), environment: full)
    }

    private func goodClient() throws -> BobProcessClient {
        try client(environment: [
            "FAKE_BOB_SNOOZE_LIST_JSON": listJSON(rows: eligibleRowJSON())
        ])
    }

    private func receipt(
        wakeID: String = "w1",
        channel: SnoozeWakeNotificationChannel = .macCapture,
        vaultRoot: String? = "/tmp/vault"
    ) -> SnoozeWakeReceipt {
        SnoozeWakeReceipt(
            wakeID: wakeID,
            date: "2026-11-26",
            wokenAt: "2026-11-26T15:32:00-05:00",
            notificationChannel: channel,
            vaultRoot: vaultRoot,
            dailyFile: "2026/20261126.md",
            tasks: [
                SnoozeWakeReceiptTask(
                    title: "Email Dan",
                    route: "tasks.md",
                    blockID: "^job",
                    target: "1532",
                    wokeAt: "15:32",
                    destination: "WRITE",
                    line: 4)
            ]
        )
    }

    private func makeHarness(
        processClient: BobProcessClient?,
        idleSeconds: TimeInterval = 0,
        settings: SnoozeWakeNoticeSettings = SnoozeWakeNoticeSettings(),
        events: CaptureAgendaEvents? = nil
    ) throws -> (
        SnoozeNoticeCoordinator, FakeClock, SnoozeWakePresenceSource,
        NotificationCenter, URL, SnoozeWakeHandledStore,
        MutableBox<SnoozeWakeNoticeSettings>, MutableBox<CaptureAgendaEvents?>,
        MutableBox<Int>, MutableBox<[SnoozeWakeNoticeBatch]>, MutableBox<[String]>
    ) {
        let clock = FakeClock(now: try wokenDate().addingTimeInterval(10), today: "2026-11-26")
        let workspaceCenter = NotificationCenter()
        let defaultCenter = NotificationCenter()
        let idleBox = MutableBox(idleSeconds)
        let presence = SnoozeWakePresenceSource(
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter,
            idleSampler: { idleBox.value }
        )
        let claimDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: claimDir, withIntermediateDirectories: true, attributes: nil)
        let claimURL = claimDir.appendingPathComponent("notifier.json")
        let claim = SnoozeWakeNotifierClaim(
            claimURL: claimURL, pid: 4242, startedAt: "2026-11-26T15:32:10-05:00")
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let handledStore = SnoozeWakeHandledStore(defaults: defaults)
        let settingsBox = MutableBox(settings)
        let eventsBox = MutableBox<CaptureAgendaEvents?>(events)
        let refreshBox = MutableBox(0)
        let presentedBox = MutableBox<[SnoozeWakeNoticeBatch]>([])
        let dismissedBox = MutableBox<[String]>([])
        let observer = SnoozeWakeObserver(
            readReceipt: { nil },
            register: { _ in 42 },
            cancel: { _ in }
        )
        let coordinator = SnoozeNoticeCoordinator(
            observer: observer,
            presenceSource: presence,
            claim: claim,
            handledStore: handledStore,
            processClient: processClient,
            configuredVaultRoot: "/tmp/vault",
            today: { clock.today },
            now: { clock.now },
            settings: { settingsBox.value },
            agendaEvents: { eventsBox.value },
            requestAgendaRefresh: { refreshBox.value += 1 },
            settleDelaySeconds: 0.05,
            retryIntervalSeconds: 0.2
        )
        coordinator.onPresent = { batch, _ in presentedBox.value.append(batch) }
        coordinator.onDismiss = { dismissedBox.value.append($0) }
        return (
            coordinator, clock, presence, defaultCenter, claimURL, handledStore,
            settingsBox, eventsBox, refreshBox, presentedBox, dismissedBox
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 8,
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

    func testCannotClaimBeforePresenterAttached() async throws {
        let (coordinator, _, _, _, claimURL, _, _, _, _, _, _) = try makeHarness(
            processClient: try goodClient())
        coordinator.start()
        await waitUntil { coordinator.isCapableForTests == true }
        XCTAssertTrue(coordinator.isStartedForTests)
        XCTAssertFalse(coordinator.isClaimedForTests)
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path))
        coordinator.stop()
    }

    func testClaimsAfterPresenterAttachedWhenCapable() async throws {
        let (coordinator, _, _, _, claimURL, _, _, _, _, _, _) = try makeHarness(
            processClient: try goodClient())
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isClaimedForTests }
        XCTAssertTrue(FileManager.default.fileExists(atPath: claimURL.path))
        coordinator.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path))
    }

    func testNoClaimWhenIncapableLeavesDesktopFallback() async throws {
        let bad = try client(environment: ["FAKE_BOB_SNOOZE_UNSUPPORTED": "1"])
        let (coordinator, _, _, _, claimURL, _, _, _, _, presented, _) = try makeHarness(
            processClient: bad)
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isCapableForTests == false }
        XCTAssertFalse(coordinator.isClaimedForTests)
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimURL.path))
        coordinator.receiveForTests(receipt())
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(presented.value.isEmpty)
        XCTAssertEqual(coordinator.pendingCountForTests, 0)
        coordinator.stop()
    }

    func testActiveDeliveryShows() async throws {
        let (coordinator, _, _, _, _, _, _, _, refreshes, presented, _) = try makeHarness(
            processClient: try goodClient())
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isCapableForTests == true }
        coordinator.receiveForTests(receipt())
        await waitUntil { presented.value.count == 1 }
        XCTAssertEqual(presented.value[0].wakeID, "w1")
        XCTAssertEqual(presented.value[0].rows.count, 1)
        XCTAssertEqual(coordinator.deliveredCountForTests, 1)
        XCTAssertGreaterThanOrEqual(refreshes.value, 1)
        coordinator.stop()
    }

    func testWrongChannelIgnored() async throws {
        let (coordinator, _, _, _, _, _, _, _, _, presented, _) = try makeHarness(
            processClient: try goodClient())
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isCapableForTests == true }
        coordinator.receiveForTests(receipt(wakeID: "w-desktop", channel: .desktop))
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(presented.value.isEmpty)
        XCTAssertEqual(coordinator.pendingCountForTests, 0)
        coordinator.stop()
    }

    func testDuplicateIDsNeverReplay() async throws {
        let (coordinator, _, _, _, _, _, _, _, _, presented, _) = try makeHarness(
            processClient: try goodClient())
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isCapableForTests == true }
        coordinator.receiveForTests(receipt(wakeID: "w1"))
        coordinator.receiveForTests(receipt(wakeID: "w1"))
        await waitUntil { presented.value.count == 1 }
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(presented.value.count, 1)
        XCTAssertEqual(coordinator.deliveredCountForTests, 1)
        coordinator.stop()
    }

    func testMultipleBatchesQueueWithoutReplacing() async throws {
        let (coordinator, _, _, _, _, _, _, _, _, presented, _) = try makeHarness(
            processClient: try goodClient())
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isCapableForTests == true }
        coordinator.receiveForTests(receipt(wakeID: "w1"))
        coordinator.receiveForTests(receipt(wakeID: "w2"))
        await waitUntil { presented.value.count == 2 }
        XCTAssertEqual(presented.value.map(\.wakeID), ["w1", "w2"])
        coordinator.stop()
    }

    func testHoldWhileAwayThenDeliverOnReturn() async throws {
        let idle = MutableBox<TimeInterval>(1_000)
        let (coordinator, _, presence, defaultCenter, _, _, _, _, refreshes, presented, _) =
            try makeHarnessWithIdle(idle, processClient: try goodClient())
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isCapableForTests == true }
        coordinator.receiveForTests(receipt())
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(presented.value.isEmpty)
        XCTAssertEqual(coordinator.pendingCountForTests, 1)
        XCTAssertTrue(presence.isIdlePolling)

        idle.value = 0
        defaultCenter.post(name: .NSSystemClockDidChange, object: nil)
        await waitUntil { presented.value.count == 1 }
        XCTAssertGreaterThanOrEqual(refreshes.value, 2)
        coordinator.stop()
        XCTAssertFalse(presence.isIdlePolling)
    }

    func testMeetingHoldDelaysUntilRealEnd() async throws {
        let eventsBox = MutableBox<CaptureAgendaEvents?>(nil)
        let (coordinator, _, _, _, _, _, _, _, _, presented, _) =
            try makeHarnessWithEvents(eventsBox, processClient: try goodClient())
        eventsBox.value = CaptureAgendaEvents(rows: [
            CaptureAgendaEventRow(
                line: 7,
                kind: .task,
                title: "Standup",
                startsAt: "2026-11-26T15:31:00-05:00",
                endsAt: "2026-11-26T15:33:00-05:00",
                statusSymbol: "*",
                statusType: "ON_HOLD"
            )
        ])
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isCapableForTests == true }
        coordinator.receiveForTests(receipt())
        try? await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(presented.value.isEmpty)
        XCTAssertEqual(coordinator.pendingCountForTests, 1)

        eventsBox.value = nil
        coordinator.notifyAgendaChanged()
        await waitUntil { presented.value.count == 1 }
        coordinator.stop()
    }

    func testDisabledSettingsConsumeWithoutReplay() async throws {
        let settingsBox = MutableBox(
            SnoozeWakeNoticeSettings(
                announceWakes: false, holdWhileAway: true, holdDuringMeetings: true))
        let (coordinator, _, _, _, _, handledStore, harnessSettings, _, _, presented, dismissed) =
            try makeHarnessWithSettings(settingsBox, processClient: try goodClient())
        XCTAssertTrue(harnessSettings === settingsBox)
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isCapableForTests == true }
        coordinator.receiveForTests(receipt(wakeID: "w-off"))
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(presented.value.isEmpty)
        XCTAssertEqual(coordinator.pendingCountForTests, 0)
        XCTAssertTrue(handledStore.contains("w-off", day: "2026-11-26"))

        settingsBox.value = SnoozeWakeNoticeSettings()
        coordinator.notifySettingsChanged()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(presented.value.isEmpty)
        XCTAssertEqual(dismissed.value.filter { $0 == "w-off" }.count, 0)
        coordinator.stop()
    }

    func testLateResultsAfterStopSuppressed() async throws {
        let slow = try client(environment: [
            "FAKE_BOB_SNOOZE_LIST_JSON": listJSON(rows: eligibleRowJSON()),
            "FAKE_BOB_SNOOZE_LIST_DELAY_SECONDS": "1",
        ])
        let (coordinator, _, _, _, _, _, _, _, _, presented, _) = try makeHarness(
            processClient: slow)
        coordinator.start()
        coordinator.attachPresenter()
        coordinator.receiveForTests(receipt())
        try? await Task.sleep(nanoseconds: 200_000_000)
        coordinator.stop()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        XCTAssertTrue(presented.value.isEmpty)
    }

    func testTransientFailureRetriesOnReconfigure() async throws {
        let failing = try client(environment: [
            "FAKE_BOB_SNOOZE_LIST_JSON": listJSON(rows: eligibleRowJSON()),
            "FAKE_BOB_SNOOZE_LIST_EXIT": "1",
        ])
        let (coordinator, _, _, _, _, _, _, _, _, presented, _) = try makeHarness(
            processClient: failing)
        coordinator.start()
        coordinator.attachPresenter()
        coordinator.receiveForTests(receipt())
        await waitUntil { coordinator.pendingCountForTests == 1 }
        try? await Task.sleep(nanoseconds: 400_000_000)
        // The failed read never shows stale tasks and never marks them
        // delivered: the batch stays pending for the bounded retry.
        XCTAssertTrue(presented.value.isEmpty)
        XCTAssertEqual(coordinator.pendingCountForTests, 1)

        coordinator.reconfigure(processClient: try goodClient(), vaultRoot: "/tmp/vault")
        await waitUntil(timeout: 10) { presented.value.count == 1 }
        coordinator.stop()
    }

    func testDayPurgeClearsPending() async throws {
        // No process client: verification can never complete, so the
        // batch stays pending until the day boundary purges it.
        let (coordinator, clock, _, _, _, handledStore, _, _, _, presented, _) =
            try makeHarness(processClient: nil)
        coordinator.start()
        coordinator.receiveForTests(receipt())
        await waitUntil { coordinator.pendingCountForTests == 1 }

        clock.today = "2026-11-27"
        coordinator.notifySettingsChanged()
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(coordinator.pendingCountForTests, 0)
        XCTAssertTrue(presented.value.isEmpty)
        XCTAssertTrue(handledStore.handledIDs(for: "2026-11-27").isEmpty)
        coordinator.stop()
    }

    func testRestartDoesNotReplayAcknowledged() async throws {
        let (first, _, _, _, claimURL, handledStore, _, _, _, presented, _) = try makeHarness(
            processClient: try goodClient())
        first.start()
        first.attachPresenter()
        await waitUntil { first.isCapableForTests == true }
        first.receiveForTests(receipt(wakeID: "w1"))
        await waitUntil { presented.value.count == 1 }
        first.acknowledgeDelivered(wakeID: "w1")
        XCTAssertTrue(handledStore.contains("w1", day: "2026-11-26"))
        first.stop()

        let secondClaim = SnoozeWakeNotifierClaim(
            claimURL: claimURL, pid: 4242, startedAt: "2026-11-26T16:00:00-05:00")
        let secondObserver = SnoozeWakeObserver(
            readReceipt: { nil }, register: { _ in 43 }, cancel: { _ in })
        let secondPresented = MutableBox<[SnoozeWakeNoticeBatch]>([])
        let secondClock = FakeClock(
            now: try wokenDate().addingTimeInterval(10), today: "2026-11-26")
        let second = SnoozeNoticeCoordinator(
            observer: secondObserver,
            claim: secondClaim,
            handledStore: handledStore,
            processClient: try goodClient(),
            configuredVaultRoot: "/tmp/vault",
            today: { secondClock.today },
            now: { secondClock.now },
            settleDelaySeconds: 0.05,
            retryIntervalSeconds: 0.2
        )
        second.onPresent = { batch, _ in secondPresented.value.append(batch) }
        second.start()
        second.attachPresenter()
        await waitUntil { second.isCapableForTests == true }
        second.receiveForTests(receipt(wakeID: "w1"))
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(secondPresented.value.isEmpty)
        second.stop()
    }

    func testPanelOpenAcknowledgesDelivered() async throws {
        let (coordinator, _, _, _, _, handledStore, _, _, _, presented, dismissed) =
            try makeHarness(processClient: try goodClient())
        coordinator.start()
        coordinator.attachPresenter()
        await waitUntil { coordinator.isCapableForTests == true }
        coordinator.receiveForTests(receipt())
        await waitUntil { presented.value.count == 1 }
        coordinator.acknowledgePanelOpen()
        XCTAssertEqual(coordinator.deliveredCountForTests, 0)
        XCTAssertTrue(handledStore.contains("w1", day: "2026-11-26"))
        XCTAssertEqual(dismissed.value, ["w1"])
        coordinator.stop()
    }

    // MARK: - Harness variants

    private func makeHarnessWithIdle(
        _ idle: MutableBox<TimeInterval>, processClient: BobProcessClient?
    ) async throws -> (
        SnoozeNoticeCoordinator, FakeClock, SnoozeWakePresenceSource,
        NotificationCenter, URL, SnoozeWakeHandledStore,
        MutableBox<SnoozeWakeNoticeSettings>, MutableBox<CaptureAgendaEvents?>,
        MutableBox<Int>, MutableBox<[SnoozeWakeNoticeBatch]>, MutableBox<[String]>
    ) {
        let clock = FakeClock(now: try wokenDate().addingTimeInterval(10), today: "2026-11-26")
        let workspaceCenter = NotificationCenter()
        let defaultCenter = NotificationCenter()
        let presence = SnoozeWakePresenceSource(
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter,
            idleSampler: { idle.value }
        )
        return try buildHarness(
            clock: clock, presence: presence, defaultCenter: defaultCenter,
            idle: idle, processClient: processClient,
            settings: MutableBox(SnoozeWakeNoticeSettings()),
            events: MutableBox<CaptureAgendaEvents?>(nil)
        )
    }

    private func makeHarnessWithEvents(
        _ events: MutableBox<CaptureAgendaEvents?>, processClient: BobProcessClient?
    ) async throws -> (
        SnoozeNoticeCoordinator, FakeClock, SnoozeWakePresenceSource,
        NotificationCenter, URL, SnoozeWakeHandledStore,
        MutableBox<SnoozeWakeNoticeSettings>, MutableBox<CaptureAgendaEvents?>,
        MutableBox<Int>, MutableBox<[SnoozeWakeNoticeBatch]>, MutableBox<[String]>
    ) {
        let clock = FakeClock(now: try wokenDate().addingTimeInterval(10), today: "2026-11-26")
        let workspaceCenter = NotificationCenter()
        let defaultCenter = NotificationCenter()
        let presence = SnoozeWakePresenceSource(
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter,
            idleSampler: { 0 }
        )
        return try buildHarness(
            clock: clock, presence: presence, defaultCenter: defaultCenter,
            idle: MutableBox<TimeInterval>(0), processClient: processClient,
            settings: MutableBox(SnoozeWakeNoticeSettings()), events: events
        )
    }

    private func makeHarnessWithSettings(
        _ settings: MutableBox<SnoozeWakeNoticeSettings>, processClient: BobProcessClient?
    ) async throws -> (
        SnoozeNoticeCoordinator, FakeClock, SnoozeWakePresenceSource,
        NotificationCenter, URL, SnoozeWakeHandledStore,
        MutableBox<SnoozeWakeNoticeSettings>, MutableBox<CaptureAgendaEvents?>,
        MutableBox<Int>, MutableBox<[SnoozeWakeNoticeBatch]>, MutableBox<[String]>
    ) {
        let clock = FakeClock(now: try wokenDate().addingTimeInterval(10), today: "2026-11-26")
        let workspaceCenter = NotificationCenter()
        let defaultCenter = NotificationCenter()
        let presence = SnoozeWakePresenceSource(
            workspaceCenter: workspaceCenter,
            defaultCenter: defaultCenter,
            idleSampler: { 0 }
        )
        return try buildHarness(
            clock: clock, presence: presence, defaultCenter: defaultCenter,
            idle: MutableBox<TimeInterval>(0), processClient: processClient,
            settings: settings, events: MutableBox<CaptureAgendaEvents?>(nil)
        )
    }

    private func buildHarness(
        clock: FakeClock,
        presence: SnoozeWakePresenceSource,
        defaultCenter: NotificationCenter,
        idle: MutableBox<TimeInterval>,
        processClient: BobProcessClient?,
        settings: MutableBox<SnoozeWakeNoticeSettings>,
        events: MutableBox<CaptureAgendaEvents?>
    ) throws -> (
        SnoozeNoticeCoordinator, FakeClock, SnoozeWakePresenceSource,
        NotificationCenter, URL, SnoozeWakeHandledStore,
        MutableBox<SnoozeWakeNoticeSettings>, MutableBox<CaptureAgendaEvents?>,
        MutableBox<Int>, MutableBox<[SnoozeWakeNoticeBatch]>, MutableBox<[String]>
    ) {
        let claimDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: claimDir, withIntermediateDirectories: true, attributes: nil)
        let claimURL = claimDir.appendingPathComponent("notifier.json")
        let claim = SnoozeWakeNotifierClaim(
            claimURL: claimURL, pid: 4242, startedAt: "2026-11-26T15:32:10-05:00")
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let handledStore = SnoozeWakeHandledStore(defaults: defaults)
        let refreshBox = MutableBox(0)
        let presentedBox = MutableBox<[SnoozeWakeNoticeBatch]>([])
        let dismissedBox = MutableBox<[String]>([])
        let observer = SnoozeWakeObserver(
            readReceipt: { nil },
            register: { _ in 42 },
            cancel: { _ in }
        )
        let coordinator = SnoozeNoticeCoordinator(
            observer: observer,
            presenceSource: presence,
            claim: claim,
            handledStore: handledStore,
            processClient: processClient,
            configuredVaultRoot: "/tmp/vault",
            today: { clock.today },
            now: { clock.now },
            settings: { settings.value },
            agendaEvents: { events.value },
            requestAgendaRefresh: { refreshBox.value += 1 },
            settleDelaySeconds: 0.05,
            retryIntervalSeconds: 0.2
        )
        coordinator.onPresent = { batch, _ in presentedBox.value.append(batch) }
        coordinator.onDismiss = { dismissedBox.value.append($0) }
        _ = idle
        return (
            coordinator, clock, presence, defaultCenter, claimURL, handledStore,
            settings, events, refreshBox, presentedBox, dismissedBox
        )
    }
}

/// A mutable box so MainActor-isolated test closures can share state
/// with injected Sendable-unchecked provider closures.
final class MutableBox<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}
