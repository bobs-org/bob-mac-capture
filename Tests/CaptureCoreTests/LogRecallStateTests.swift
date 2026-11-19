import XCTest

@testable import CaptureCore

final class LogRecallStateTests: XCTestCase {
    private func catalog() -> [LogRecallPhrase] {
        [
            LogRecallPhrase(
                text: "duplicate of planning", key: "duplicate of planning",
                uses: 4, lastUsed: "2026-11-18", score: 3.1, recencyRank: 0),
            LogRecallPhrase(
                text: "no longer needed", key: "no longer needed", uses: 2,
                lastUsed: "2026-11-15", score: 1.4, recencyRank: 1),
            LogRecallPhrase(
                text: "superseded by weekly review",
                key: "superseded by weekly review", uses: 1,
                lastUsed: "2026-11-02", score: 0.5, recencyRank: 2),
        ]
    }

    func testOpenStartsInDraftWithNothingSelected() {
        var state = LogRecallState()
        state.open(draft: "", catalog: catalog())
        XCTAssertFalse(state.isRecalling)
        XCTAssertNil(state.selectedKey)
        XCTAssertFalse(state.shouldShowBand)
        XCTAssertEqual(state.visibleRows, [])
    }

    func testTwoCharacterDraftRevealsBand() {
        var state = LogRecallState()
        state.open(draft: "", catalog: catalog())
        state.draftChanged("du")
        XCTAssertTrue(state.shouldShowBand)
        XCTAssertEqual(state.visibleRows.count, 1)
        XCTAssertEqual(state.visibleRows[0].phrase.key, "duplicate of planning")
    }

    func testNavigateEntersAtTopAndFills() {
        var state = LogRecallState()
        state.open(draft: "", catalog: catalog())
        let step = state.moveNext()
        XCTAssertEqual(step, .enteredTop)
        XCTAssertTrue(state.isRecalling)
        XCTAssertEqual(state.selectedKey, "duplicate of planning")
        XCTAssertEqual(state.filledText(), "duplicate of planning")
        XCTAssertEqual(state.selectedIndex, 1)
    }

    func testMoveClampsAtBottomWithoutWrap() {
        var state = LogRecallState()
        state.open(draft: "", catalog: catalog())
        _ = state.moveNext()
        _ = state.moveNext()
        _ = state.moveNext()
        XCTAssertEqual(state.selectedKey, "superseded by weekly review")
        let bump = state.moveNext()
        XCTAssertEqual(bump, .bumpedBottom)
        XCTAssertEqual(state.selectedKey, "superseded by weekly review")
    }

    func testMoveAboveTopRestoresDraft() {
        var state = LogRecallState()
        state.open(draft: "du", catalog: catalog())
        _ = state.moveNext()
        XCTAssertTrue(state.isRecalling)
        let back = state.movePrevious()
        XCTAssertEqual(back, .bumpedTop)
        XCTAssertFalse(state.isRecalling)
        XCTAssertEqual(state.draft, "du")
    }

    func testEscRestoresDraftOnceThenReleases() {
        var state = LogRecallState()
        state.open(draft: "du", catalog: catalog())
        _ = state.moveNext()
        XCTAssertTrue(state.backOut())
        XCTAssertFalse(state.isRecalling)
        XCTAssertFalse(state.backOut())
    }

    func testTypingAdoptsShownTextAsDraft() {
        var state = LogRecallState()
        state.open(draft: "", catalog: catalog())
        _ = state.moveNext()
        state.draftChanged("duplicate of planning")
        XCTAssertFalse(state.isRecalling)
        XCTAssertEqual(state.draft, "duplicate of planning")
    }

    func testBackgroundRefreshDefersWhileRecalling() {
        var state = LogRecallState()
        state.open(draft: "", catalog: catalog())
        _ = state.moveNext()
        let fresh = [
            LogRecallPhrase(
                text: "fresh reason", key: "fresh reason", uses: 1,
                lastUsed: "2026-11-19", score: 9.0, recencyRank: 0)
        ]
        let applied = state.applyCatalog(fresh, generation: state.generation)
        XCTAssertFalse(applied)
        XCTAssertEqual(state.catalog.count, 3)
        // Returning to DRAFT applies the pending catalog.
        _ = state.backOut()
        XCTAssertEqual(state.catalog, fresh)
    }

    func testStaleGenerationIsDropped() {
        var state = LogRecallState()
        state.open(draft: "", catalog: catalog())
        XCTAssertFalse(state.applyCatalog([], generation: state.generation + 99))
        XCTAssertEqual(state.catalog.count, 3)
    }

    func testClickSelectsWithoutCommitting() {
        var state = LogRecallState()
        state.open(draft: "no", catalog: catalog())
        XCTAssertTrue(state.select(key: "no longer needed"))
        XCTAssertTrue(state.isRecalling)
        XCTAssertEqual(state.filledText(), "no longer needed")
        XCTAssertFalse(state.select(key: "missing"))
    }

    func testHeaderCopy() {
        let empty = LogRecallBandPresentation.header(
            draft: "", selectedIndex: nil, total: 3)
        XCTAssertTrue(empty.title.contains("USED BEFORE"))
        XCTAssertTrue(empty.showsKeycaps)
        let matching = LogRecallBandPresentation.header(
            draft: "du", selectedIndex: nil, total: 1)
        XCTAssertTrue(matching.title.contains("matching"))
        let none = LogRecallBandPresentation.header(
            draft: "zzz", selectedIndex: nil, total: 0)
        XCTAssertTrue(none.title.contains("no match"))
        XCTAssertFalse(none.showsKeycaps)
        let recalling = LogRecallBandPresentation.header(
            draft: "du", selectedIndex: 1, total: 3)
        XCTAssertTrue(recalling.title.contains("1 of 3"))
    }

    func testDayAges() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let today = formatter.date(from: "2026-11-19")!
        XCTAssertEqual(LogRecallBandPresentation.dayAge("2026-11-19", today: today), "today")
        XCTAssertEqual(
            LogRecallBandPresentation.dayAge("2026-11-18", today: today), "yesterday")
        XCTAssertEqual(LogRecallBandPresentation.dayAge("2026-11-16", today: today), "3d")
        XCTAssertEqual(LogRecallBandPresentation.dayAge("2026-11-02", today: today), "Nov 2")
    }
}
