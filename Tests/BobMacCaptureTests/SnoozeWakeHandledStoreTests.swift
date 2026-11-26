import XCTest

@testable import BobMacCapture

final class SnoozeWakeHandledStoreTests: XCTestCase {
    private func makeStore() -> (SnoozeWakeHandledStore, UserDefaults, String) {
        let suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (SnoozeWakeHandledStore(defaults: defaults), defaults, suiteName)
    }

    func testAcknowledgeAndContainsWithinDay() {
        let (store, _, _) = makeStore()
        XCTAssertFalse(store.contains("w1", day: "2026-11-26"))
        store.acknowledge("w1", day: "2026-11-26")
        XCTAssertTrue(store.contains("w1", day: "2026-11-26"))
    }

    func testIDsAreDayScoped() {
        let (store, _, _) = makeStore()
        store.acknowledge("w1", day: "2026-11-26")
        XCTAssertFalse(store.contains("w1", day: "2026-11-27"))
        XCTAssertTrue(store.handledIDs(for: "2026-11-27").isEmpty)
        XCTAssertEqual(store.handledIDs(for: "2026-11-26"), ["w1"])
    }

    func testDayChangeClearsPreviousIDs() {
        let (store, _, _) = makeStore()
        store.acknowledge("w1", day: "2026-11-26")
        store.purge(day: "2026-11-27")
        XCTAssertFalse(store.contains("w1", day: "2026-11-26"))
        XCTAssertTrue(store.handledIDs(for: "2026-11-27").isEmpty)
    }

    func testPurgeIsIdempotentForCurrentDay() {
        let (store, _, _) = makeStore()
        store.acknowledge("w1", day: "2026-11-26")
        store.purge(day: "2026-11-26")
        XCTAssertTrue(store.contains("w1", day: "2026-11-26"))
    }

    func testCollectionStaysBounded() {
        let (store, _, _) = makeStore()
        for index in 0..<400 {
            store.acknowledge("w\(index)", day: "2026-11-26")
        }
        XCTAssertLessThanOrEqual(store.handledIDs(for: "2026-11-26").count, 256)
        XCTAssertEqual(store.day, "2026-11-26")
    }

    func testPersistsAcrossInstances() {
        let (_, defaults, _) = makeStore()
        let first = SnoozeWakeHandledStore(defaults: defaults)
        first.acknowledge("w9", day: "2026-11-26")
        let second = SnoozeWakeHandledStore(defaults: defaults)
        XCTAssertTrue(second.contains("w9", day: "2026-11-26"))
    }
}
