import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class SnoozeWakePresenceSourceTests: XCTestCase {
    private func makeSource(
        idleSeconds: TimeInterval = 0,
        workspaceCenter: NotificationCenter? = nil,
        defaultCenter: NotificationCenter? = nil,
        distributedCenter: DistributedNotificationCenter? = nil
    ) -> (SnoozeWakePresenceSource, NotificationCenter, NotificationCenter) {
        let workspace = workspaceCenter ?? NotificationCenter()
        let center = defaultCenter ?? NotificationCenter()
        let source = SnoozeWakePresenceSource(
            workspaceCenter: workspace,
            defaultCenter: center,
            distributedCenter: distributedCenter,
            idleSampler: { idleSeconds }
        )
        return (source, workspace, center)
    }

    func testInitialPresenceIsPresent() {
        let (source, _, _) = makeSource()
        source.start()
        let presence = source.currentPresence()
        XCTAssertFalse(presence.isAway)
        XCTAssertTrue(presence.awaySignals.isEmpty)
        XCTAssertFalse(source.isIdlePolling)
        source.stop()
    }

    func testIdleThresholdBoundary() {
        for (idle, expectAway) in [(179.9, false), (180.0, true)] as [(TimeInterval, Bool)] {
            let (source, _, _) = makeSource(idleSeconds: idle)
            source.start()
            XCTAssertEqual(
                source.currentPresence().isAway, expectAway, "idle=\(idle)")
            source.stop()
        }
    }

    func testScreenLockHoldsUntilUnlock() async throws {
        let (source, _, _) = makeSource()
        var changes = 0
        source.onChange = { changes += 1 }
        source.start()

        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.apple.screenIsLocked"), object: nil)
        let lockedDeadline = Date().addingTimeInterval(5)
        while !source.currentPresence().screenLocked, Date() < lockedDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertTrue(source.currentPresence().screenLocked)
        XCTAssertTrue(source.currentPresence().isAway)

        DistributedNotificationCenter.default().post(
            name: Notification.Name("com.apple.screenIsUnlocked"), object: nil)
        let unlockedDeadline = Date().addingTimeInterval(5)
        while source.currentPresence().screenLocked, Date() < unlockedDeadline {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertFalse(source.currentPresence().isAway)
        XCTAssertGreaterThanOrEqual(changes, 2)
        source.stop()
    }

    func testDisplaySleepAndSessionSignalsHoldIndependently() {
        let (source, workspace, _) = makeSource()
        source.start()

        workspace.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        XCTAssertTrue(source.currentPresence().isAway)

        workspace.post(name: NSWorkspace.screensDidWakeNotification, object: nil)
        XCTAssertFalse(source.currentPresence().isAway)

        workspace.post(name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        XCTAssertTrue(source.currentPresence().isAway)

        workspace.post(name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        XCTAssertFalse(source.currentPresence().isAway)
        source.stop()
    }

    func testDayAndClockChangesFireOnChange() {
        let (source, _, center) = makeSource()
        var changes = 0
        source.onChange = { changes += 1 }
        source.start()

        center.post(name: .NSCalendarDayChanged, object: nil)
        center.post(name: .NSSystemClockDidChange, object: nil)
        XCTAssertEqual(changes, 2)
        source.stop()
    }

    func testIdlePollingRunsOnlyWhileHeld() {
        let (source, _, _) = makeSource()
        source.start()
        XCTAssertFalse(source.isIdlePolling)
        source.setIdlePollingActive(true)
        XCTAssertTrue(source.isIdlePolling)
        source.setIdlePollingActive(false)
        XCTAssertFalse(source.isIdlePolling)
        source.stop()
        XCTAssertFalse(source.isIdlePolling)
    }

    func testIdlePollTickFiresOnChange() async {
        let (source, _, _) = makeSource()
        var changes = 0
        source.onChange = { changes += 1 }
        source.start()
        source.setIdlePollingActive(true)
        let deadline = Date().addingTimeInterval(6)
        while changes == 0, Date() < deadline {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertGreaterThan(changes, 0)
        source.setIdlePollingActive(false)
        source.stop()
    }
}
