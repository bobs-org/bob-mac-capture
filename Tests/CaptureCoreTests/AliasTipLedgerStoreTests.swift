import Foundation
import XCTest

@testable import CaptureCore

final class AliasTipLedgerStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "org.bobs.bob-mac-capture.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func store(now: Date = Date(timeIntervalSince1970: 1_780_000_000)) -> AliasTipLedgerStore {
        AliasTipLedgerStore(defaults: defaults, now: { now })
    }

    private func monday(ofWeek offset: Int) -> Date {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: 2026, month: 1, day: 5))!
        return Date(timeInterval: Double(offset * 7 * 24 * 3_600), since: base)
    }

    func testEmptyLedgerLoadsFresh() {
        XCTAssertEqual(store().load(), .empty)
    }

    func testRoundTripPersistsAsJSONString() {
        let store = store()
        store.recordHit(id: "route_after_text")
        store.recordMiss(id: "route_after_text", shown: true)
        let loaded = store.load()
        XCTAssertEqual(loaded.lessons["route_after_text"]?.tipsShown, 1)

        let raw = defaults.string(forKey: AliasTipLedgerStore.defaultsKey)
        XCTAssertNotNil(raw)
        XCTAssertTrue(raw!.hasPrefix("{"))
        // The blob is a JSON string, so `defaults read` stays readable.
        XCTAssertTrue(raw!.contains("route_after_text"))
    }

    func testResetClearsTheLedger() {
        let store = store()
        store.recordHit(id: "route_after_text")
        XCTAssertNotNil(defaults.string(forKey: AliasTipLedgerStore.defaultsKey))
        store.reset()
        XCTAssertNil(defaults.string(forKey: AliasTipLedgerStore.defaultsKey))
        XCTAssertEqual(store.load(), .empty)
    }

    func testCorruptBlobRecoversToEmpty() {
        defaults.set("not json {", forKey: AliasTipLedgerStore.defaultsKey)
        XCTAssertEqual(store().load(), .empty)
    }

    func testUnknownVersionResetsToEmpty() {
        let ledger = AliasTipLedger(version: 999)
        let data = try! JSONEncoder().encode(ledger)
        defaults.set(String(data: data, encoding: .utf8), forKey: AliasTipLedgerStore.defaultsKey)
        XCTAssertEqual(store().load(), .empty)
    }

    func testStoreQueriesReflectRecordedChances() {
        let store = store()
        XCTAssertTrue(store.isDue(id: "route_after_text"))
        store.recordMiss(id: "route_after_text", shown: true)
        store.recordMiss(id: "route_after_text", shown: true)
        store.recordMiss(id: "route_after_text", shown: true)
        XCTAssertFalse(store.isDue(id: "route_after_text"))
        XCTAssertFalse(store.isFluent(id: "route_after_text"))
    }

    func testStoreRecordsIneligibleSigils() {
        let store = store()
        store.recordIneligible(sigil: "@")
        store.recordIneligible(sigil: "@")
        XCTAssertEqual(store.load().ineligible["@"], 2)
    }

    func testStoreWithdrawsHits() {
        let store = store()
        let credit = store.recordHit(id: "route_after_text")
        store.withdrawHit(credit)
        XCTAssertEqual(store.load().lessons["route_after_text"]?.recent, [])
        XCTAssertEqual(
            store.load().weeks.values.first?["route_after_text"]?.hits ?? 0,
            0
        )
    }

    func testStoreWithdrawalIsIdempotentForOneCredit() {
        let store = store()
        let first = store.recordHit(id: "route_after_text")
        let second = store.recordHit(id: "route_after_text")

        store.withdrawHit(first)
        store.withdrawHit(first)

        XCTAssertEqual(
            store.load().weeks.values.first?["route_after_text"]?.hits,
            1
        )
        store.withdrawHit(second)
        XCTAssertEqual(
            store.load().weeks.values.first?["route_after_text"]?.hits ?? 0,
            0
        )
    }

    func testWeekRolloverKeepsTwelveNewestWeeks() {
        var ledger = AliasTipLedger.empty
        for week in 0..<14 {
            ledger.recordHit(id: "route_after_text", date: monday(ofWeek: week))
        }
        XCTAssertEqual(ledger.weeks.count, AliasTipPolicy.maxWeeks)
        let oldest = AliasTipLedger.weekKey(for: monday(ofWeek: 0))
        let newest = AliasTipLedger.weekKey(for: monday(ofWeek: 13))
        XCTAssertNil(ledger.weeks[oldest])
        XCTAssertNotNil(ledger.weeks[newest])
    }

    func testWeekBucketsTrackHitsMissesShown() {
        let day = monday(ofWeek: 3)
        var ledger = AliasTipLedger.empty
        ledger.recordHit(id: "route_after_text", date: day)
        ledger.recordMiss(id: "route_after_text", shown: true, date: day)
        ledger.recordMiss(id: "route_after_text", shown: false, date: day)
        let entry = ledger.weeks[AliasTipLedger.weekKey(for: day)]?["route_after_text"]
        XCTAssertEqual(entry?.hits, 1)
        XCTAssertEqual(entry?.misses, 2)
        XCTAssertEqual(entry?.shown, 1)
    }
}
