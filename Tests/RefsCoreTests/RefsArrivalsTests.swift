import Foundation
import XCTest

@testable import RefsCore

/// Arrival tracking: the baseline only grows, pending batches pick a
/// target, and qualification uses the NEW `added` window alone.
final class RefsArrivalsTests: XCTestCase {
    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    static let now: Date = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: "2026-10-08T12:00:00Z")!
    }()

    func signals() -> RefsSignals {
        RefsSignals(now: Self.now, calendar: Self.utcCalendar)
    }

    func item(id: String, added: String?) -> RefItem {
        RefItem(
            id: id,
            link: "[[\(id)]]",
            rawTitle: id,
            stem: id,
            kind: .chat,
            state: .ready,
            isBlocked: false,
            pdfPath: "lib/\(id).pdf",
            added: added.flatMap(RefDay.init(parsing:)),
            addedSource: added == nil ? nil : "created"
        )
    }

    func lookup(_ items: [RefItem]) -> (String) -> RefItem? {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return { byID[$0] }
    }

    func testSeededBaselineMakesNewIDsPendingAndRepeatedObserveIsNoOp() {
        var tracker = RefsArrivalTracker(knownIDs: ["a"])
        XCTAssertFalse(tracker.hasPending)
        tracker.observe(["a", "b"])
        XCTAssertTrue(tracker.hasPending)
        let afterFirst = tracker
        tracker.observe(["a", "b"])
        XCTAssertEqual(tracker, afterFirst)
    }

    func testVanishedThenReturnedIDIsNeverPending() {
        var tracker = RefsArrivalTracker(knownIDs: ["a"])
        tracker.observe(["a"])
        tracker.observe([])
        tracker.observe(["a"])
        XCTAssertFalse(tracker.hasPending)
        XCTAssertNil(
            tracker.target(
                orderedIDs: ["a"],
                item: lookup([item(id: "a", added: "2026-10-08")]),
                signals: signals()
            )
        )
    }

    func testEmptySeedEstablishesBaselineOnFirstNonEmptyObserve() {
        var tracker = RefsArrivalTracker(knownIDs: [String]())
        tracker.observe([])
        XCTAssertFalse(tracker.hasPending)
        tracker.observe(["a", "b"])
        XCTAssertFalse(tracker.hasPending)
        tracker.observe(["a", "b", "c"])
        XCTAssertTrue(tracker.hasPending)
        XCTAssertEqual(
            tracker.target(
                orderedIDs: ["c", "a"],
                item: lookup([
                    item(id: "a", added: "2026-10-08"),
                    item(id: "c", added: "2026-10-08"),
                ]),
                signals: signals()
            ),
            "c"
        )
    }

    func testMarkSeenDropsPendingAndNeverSeedsTheBaseline() {
        var tracker = RefsArrivalTracker(knownIDs: [String]())
        tracker.markSeen(["ghost"])
        tracker.observe(["a", "b"])
        XCTAssertFalse(tracker.hasPending)

        tracker = RefsArrivalTracker(knownIDs: ["a"])
        tracker.observe(["a", "b"])
        XCTAssertTrue(tracker.hasPending)
        tracker.markSeen(["b"])
        XCTAssertFalse(tracker.hasPending)
        tracker.observe(["a", "b"])
        XCTAssertFalse(tracker.hasPending)
        tracker.observe(["a", "b", "c"])
        XCTAssertTrue(tracker.hasPending)
        tracker.clearPending()
        XCTAssertFalse(tracker.hasPending)
    }

    func testQualificationUsesTheAddedWindowAndIgnoresNilAdded() {
        var tracker = RefsArrivalTracker(knownIDs: ["old"])
        tracker.observe(["old", "fresh", "edge", "stale", "undated"])
        let items = [
            item(id: "fresh", added: "2026-10-08"),
            item(id: "edge", added: "2026-10-05"),
            item(id: "stale", added: "2026-10-04"),
            item(id: "undated", added: nil),
        ]
        let itemFor = lookup(items)
        let signals = signals()
        XCTAssertTrue(tracker.hasQualifying(item: itemFor, signals: signals))
        XCTAssertEqual(
            tracker.target(
                orderedIDs: ["stale", "undated", "fresh"],
                item: itemFor,
                signals: signals
            ),
            "fresh"
        )
        XCTAssertEqual(
            tracker.target(orderedIDs: ["edge"], item: itemFor, signals: signals),
            "edge"
        )
        XCTAssertNil(
            tracker.target(orderedIDs: ["stale", "undated"], item: itemFor, signals: signals)
        )

        var onlyStale = RefsArrivalTracker(knownIDs: ["a"])
        onlyStale.observe(["a", "stale"])
        XCTAssertFalse(
            onlyStale.hasQualifying(
                item: lookup([item(id: "stale", added: "2026-10-04")]),
                signals: signals
            )
        )
        var onlyNil = RefsArrivalTracker(knownIDs: ["a"])
        onlyNil.observe(["a", "undated"])
        XCTAssertFalse(
            onlyNil.hasQualifying(
                item: lookup([item(id: "undated", added: nil)]),
                signals: signals
            )
        )
    }

    func testLatestBatchWinsThenEarliestListingPositionAndUnlistedIDsAreIgnored() {
        var tracker = RefsArrivalTracker(knownIDs: ["a"])
        let items = [
            item(id: "b", added: "2026-10-08"),
            item(id: "c", added: "2026-10-08"),
            item(id: "d", added: "2026-10-08"),
        ]
        let itemFor = lookup(items)
        let signals = signals()
        tracker.observe(["a", "b", "c"])
        tracker.observe(["a", "b", "c", "d"])
        XCTAssertEqual(
            tracker.target(orderedIDs: ["c", "b", "d"], item: itemFor, signals: signals),
            "d"
        )
        XCTAssertEqual(
            tracker.target(orderedIDs: ["d", "b"], item: itemFor, signals: signals),
            "d"
        )

        var sameBatch = RefsArrivalTracker(knownIDs: ["a"])
        sameBatch.observe(["a", "b", "c"])
        XCTAssertEqual(
            sameBatch.target(orderedIDs: ["c", "b"], item: itemFor, signals: signals),
            "c"
        )
        XCTAssertEqual(
            sameBatch.target(orderedIDs: ["b", "c"], item: itemFor, signals: signals),
            "b"
        )
        XCTAssertNil(
            sameBatch.target(orderedIDs: ["a"], item: itemFor, signals: signals)
        )
    }
}
