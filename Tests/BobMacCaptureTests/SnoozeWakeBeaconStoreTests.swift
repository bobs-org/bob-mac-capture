import CaptureCore
import Foundation
import UserNotifications
import XCTest

@testable import BobMacCapture

@MainActor
final class SnoozeWakeBeaconStoreTests: XCTestCase {
    private func makeStore() -> (SnoozeWakeBeaconStore, UserDefaults, String) {
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (SnoozeWakeBeaconStore(defaults: defaults), defaults, suiteName)
    }

    private func woken() -> Date {
        CaptureRFC3339Date.date(from: "2026-11-26T15:32:00-05:00")!
    }

    func testSaveAndActiveFiltersExpiryAndVault() {
        let (store, _, _) = makeStore()
        let now = woken().addingTimeInterval(10)
        store.save(
            wakeID: "w1", taskKeys: ["a"], taskCount: 1,
            deliveredAt: now, wokenAt: woken(),
            date: "2026-11-26", vaultRoot: "/tmp/vault")
        store.save(
            wakeID: "w2", taskKeys: ["b"], taskCount: 2,
            deliveredAt: now, wokenAt: woken(),
            date: "2026-11-26", vaultRoot: "/other/vault")
        let active = store.activeEntries(
            today: "2026-11-26", vaultRoot: "/tmp/vault", now: now)
        XCTAssertEqual(active.map(\.wakeID), ["w1"])
    }

    func testBeaconExpiryIsSixtyMinutes() {
        let (store, _, _) = makeStore()
        let deliveredAt = woken().addingTimeInterval(10)
        store.save(
            wakeID: "w1", taskKeys: ["a"], taskCount: 1,
            deliveredAt: deliveredAt, wokenAt: woken(),
            date: "2026-11-26", vaultRoot: "/tmp/vault")
        let before = deliveredAt.addingTimeInterval(60 * 60 - 10)
        XCTAssertEqual(
            store.activeEntries(
                today: "2026-11-26", vaultRoot: "/tmp/vault", now: before
            ).map(\.wakeID), ["w1"])
        let after = deliveredAt.addingTimeInterval(60 * 60 + 10)
        XCTAssertTrue(
            store.activeEntries(
                today: "2026-11-26", vaultRoot: "/tmp/vault", now: after
            ).isEmpty)
    }

    func testBeaconRestoresAcrossRestartWhenNotificationRecordIsDenied() {
        let (store, defaults, _) = makeStore()
        let deliveredAt = woken().addingTimeInterval(10)
        XCTAssertFalse(
            NotificationService.canPostSnoozeWakeRecord(
                authorizationStatus: .denied))
        store.save(
            wakeID: "denied-record",
            taskKeys: ["tasks.md#^a"],
            taskCount: 1,
            deliveredAt: deliveredAt,
            wokenAt: woken(),
            date: "2026-11-26",
            vaultRoot: "/tmp/vault"
        )

        let afterRestart = SnoozeWakeBeaconStore(defaults: defaults).activeEntries(
            today: "2026-11-26",
            vaultRoot: "/tmp/vault",
            now: deliveredAt.addingTimeInterval(30)
        )
        XCTAssertEqual(afterRestart.map(\.wakeID), ["denied-record"])
        XCTAssertEqual(afterRestart.first?.taskCount, 1)
    }

    func testRemoveAndBounded() {
        let (store, _, _) = makeStore()
        let now = woken().addingTimeInterval(10)
        for index in 0..<(SnoozeWakeBeaconStore.maxEntries + 5) {
            store.save(
                wakeID: "w\(index)", taskKeys: ["k"], taskCount: 1,
                deliveredAt: now, wokenAt: woken(),
                date: "2026-11-26", vaultRoot: "/tmp/vault")
        }
        let active = store.activeEntries(
            today: "2026-11-26", vaultRoot: "/tmp/vault", now: now)
        XCTAssertLessThanOrEqual(active.count, SnoozeWakeBeaconStore.maxEntries)
        store.remove(wakeID: active.first!.wakeID)
        let after = store.activeEntries(
            today: "2026-11-26", vaultRoot: "/tmp/vault", now: now)
        XCTAssertEqual(after.count, active.count - 1)
    }

    func testRemoveAllForVaultKeepsOtherVaults() {
        let (store, _, _) = makeStore()
        let now = woken().addingTimeInterval(10)
        store.save(
            wakeID: "old-vault", taskKeys: ["a"], taskCount: 1,
            deliveredAt: now, wokenAt: woken(),
            date: "2026-11-26", vaultRoot: "/tmp/old-vault")
        store.save(
            wakeID: "other-vault", taskKeys: ["b"], taskCount: 1,
            deliveredAt: now, wokenAt: woken(),
            date: "2026-11-26", vaultRoot: "/tmp/other-vault")

        store.removeAll(vaultRoot: "/tmp/old-vault")

        XCTAssertEqual(
            store.activeEntries(
                today: "2026-11-26", vaultRoot: "/tmp/other-vault", now: now
            ).map(\.wakeID), ["other-vault"])
    }
}
