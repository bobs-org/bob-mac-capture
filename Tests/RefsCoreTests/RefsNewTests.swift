import Foundation
import XCTest

@testable import RefsCore

/// NEW is Mac-local presentation state: Ready/Next only, arrived within
/// three local days when unmarked and unopened, or a `new` mark still in
/// force. ⌥N stores the smallest mark that produces the flipped state.
final class RefsNewTests: XCTestCase {
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

    func signals(
        opens: [RefsOpenEvent] = [],
        newMarks: [RefsNewMarkEntry] = [],
        lastUsed: [String: Date] = [:],
        now: Date = RefsNewTests.now
    ) -> RefsSignals {
        RefsSignals(
            opens: RefsOpenStats(events: opens, now: now),
            newMarks: RefsNewMarks(entries: newMarks),
            externalLastUsed: lastUsed,
            now: now,
            calendar: Self.utcCalendar
        )
    }

    func item(
        id: String,
        state: RefState = .ready,
        added: String? = "2026-10-08",
        addedAt: Date? = nil,
        annotations: Int = 0
    ) -> RefItem {
        RefItem(
            id: id,
            link: "[[\(id)]]",
            rawTitle: id,
            stem: id,
            kind: .chat,
            state: state,
            isBlocked: false,
            pdfPath: "lib/\(id).pdf",
            added: added.flatMap(RefDay.init(parsing:)),
            addedSource: added == nil ? nil : "created",
            addedAt: addedAt,
            annotationCount: annotations
        )
    }

    func testArrivedReadyWithinTheWindowIsNew() {
        let fresh = item(id: "fresh")
        let edge = item(id: "edge", added: "2026-10-05")
        let signals = signals()

        XCTAssertEqual(RefsRanker.newness(fresh, signals: signals), .arrived)
        XCTAssertEqual(RefsRanker.newness(edge, signals: signals), .arrived)
        XCTAssertTrue(RefsRanker.isNew(fresh, signals: signals))
        XCTAssertTrue(RefsRanker.arrivedNew(fresh, signals: signals))
    }

    func testFourDaysOutAndOpenedOrAnnotatedRowsAreNotArrived() {
        let old = item(id: "old", added: "2026-10-04")
        let annotated = item(id: "ann", annotations: 1)
        let reading = item(id: "read", state: .reading)
        let opened = item(id: "opened")
        let openedSignals = signals(
            opens: [RefsOpenEvent(path: "opened", at: Self.now.addingTimeInterval(-60))]
        )

        XCTAssertFalse(RefsRanker.arrivedNew(old, signals: signals()))
        XCTAssertFalse(RefsRanker.arrivedNew(annotated, signals: signals()))
        XCTAssertFalse(RefsRanker.arrivedNew(reading, signals: signals()))
        XCTAssertFalse(RefsRanker.arrivedNew(opened, signals: openedSignals))
        XCTAssertNil(RefsRanker.newness(old, signals: signals()))
        XCTAssertNil(RefsRanker.newness(reading, signals: signals()))
    }

    func testSeenMarkHidesArrivalAndNewMarkLiftsAnOldRow() {
        let fresh = item(id: "fresh")
        let old = item(id: "old", added: "2026-08-01")
        let markAt = Self.now.addingTimeInterval(-30)
        let marked = signals(newMarks: [
            RefsNewMarkEntry(path: "fresh", state: .seen, at: Self.now),
            RefsNewMarkEntry(path: "old", state: .new, at: markAt),
        ])

        XCTAssertNil(RefsRanker.newness(fresh, signals: marked))
        XCTAssertEqual(RefsRanker.newness(old, signals: marked), .marked(markAt))
        XCTAssertTrue(RefsRanker.arrivedNew(fresh, signals: signals()))
    }

    func testOpenAfterANewMarkClearsNewness() {
        let marked = item(id: "row", added: "2026-08-01")
        let markAt = Self.now.addingTimeInterval(-120)
        let later = signals(
            opens: [RefsOpenEvent(path: "row", at: Self.now.addingTimeInterval(-30))],
            newMarks: [RefsNewMarkEntry(path: "row", state: .new, at: markAt)]
        )
        let earlier = signals(
            opens: [RefsOpenEvent(path: "row", at: Self.now.addingTimeInterval(-180))],
            newMarks: [RefsNewMarkEntry(path: "row", state: .new, at: markAt)]
        )

        XCTAssertNil(RefsRanker.newness(marked, signals: later))
        XCTAssertEqual(RefsRanker.newness(marked, signals: earlier), .marked(markAt))
    }

    func testToggleStoresTheSmallestMark() {
        let arrived = item(id: "fresh")
        let old = item(id: "old", added: "2026-08-01")
        let reading = item(id: "read", state: .reading)

        XCTAssertEqual(
            RefsNewToggle.result(for: arrived, signals: signals(), now: Self.now),
            .apply(mark: RefsNewMark(state: .seen, at: Self.now), becomesNew: false)
        )
        XCTAssertEqual(
            RefsNewToggle.result(
                for: arrived,
                signals: signals(newMarks: [
                    RefsNewMarkEntry(path: "fresh", state: .seen, at: Self.now)
                ]),
                now: Self.now
            ),
            .apply(mark: nil, becomesNew: true)
        )
        XCTAssertEqual(
            RefsNewToggle.result(for: old, signals: signals(), now: Self.now),
            .apply(mark: RefsNewMark(state: .new, at: Self.now), becomesNew: true)
        )
        XCTAssertEqual(
            RefsNewToggle.result(
                for: old,
                signals: signals(newMarks: [
                    RefsNewMarkEntry(path: "old", state: .new, at: Self.now)
                ]),
                now: Self.now
            ),
            .apply(mark: nil, becomesNew: false)
        )
        XCTAssertEqual(
            RefsNewToggle.result(for: reading, signals: signals(), now: Self.now),
            .ineligible
        )
    }

    func testNewSincePrefersMarkThenAddedAtThenStartOfDay() {
        let marked = item(id: "m", added: "2026-08-01")
        let timed = item(
            id: "t",
            addedAt: Self.now.addingTimeInterval(-3_600)
        )
        let dayOnly = item(id: "d", added: "2026-10-07")
        let signals = signals()
        let markAt = Self.now.addingTimeInterval(-15)

        XCTAssertEqual(
            RefsRanker.newSince(marked, .marked(markAt), signals: signals),
            markAt
        )
        XCTAssertEqual(
            RefsRanker.newSince(timed, .arrived, signals: signals),
            timed.addedAt
        )
        let startOfDay = Self.utcCalendar.date(
            from: DateComponents(year: 2026, month: 10, day: 7)
        )
        XCTAssertEqual(
            RefsRanker.newSince(dayOnly, .arrived, signals: signals),
            startOfDay
        )
    }

    func testWhyHereNamesArrivalMarkAndSeenInPlace() {
        let arrived = item(id: "fresh")
        let listing = RefsRanker.listing(
            [arrived], query: "", scope: .all, signals: signals()
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(arrived, listing: listing, signals: signals()),
            "New · added Oct 8 · never opened"
        )

        let markAt = Self.now
        let markedSignals = signals(newMarks: [
            RefsNewMarkEntry(path: "fresh", state: .new, at: markAt)
        ])
        let markedListing = RefsRanker.listing(
            [arrived], query: "", scope: .all, signals: markedSignals
        )
        XCTAssertEqual(
            RefsExplanation.whyHere(arrived, listing: markedListing, signals: markedSignals),
            "New · marked Oct 8"
        )

        let seenSignals = signals(newMarks: [
            RefsNewMarkEntry(path: "fresh", state: .seen, at: markAt)
        ])
        XCTAssertEqual(
            RefsExplanation.whyHere(arrived, listing: listing, signals: seenSignals),
            "Seen · leaves New next time you open Bob Refs"
        )
    }

    func testDuplicateMarkPathsKeepTheLatestInstant() {
        let early = RefsNewMarkEntry(
            path: "row", state: .seen, at: Self.now.addingTimeInterval(-60)
        )
        let late = RefsNewMarkEntry(path: "row", state: .new, at: Self.now)
        let marks = RefsNewMarks(entries: [early, late, early])

        XCTAssertEqual(marks.mark(for: "row")?.state, .new)
        XCTAssertEqual(marks.mark(for: "row")?.at, Self.now)
    }
}
