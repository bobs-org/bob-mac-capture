import CaptureCore
import Foundation
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
}
