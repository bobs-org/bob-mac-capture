import Foundation
import XCTest

@testable import CaptureCore

final class AliasTipPolicyTests: XCTestCase {
    private let id = "route_after_text"
    private let date = Date(timeIntervalSince1970: 1_780_000_000)

    func testFirstThreeMissesAreDue() {
        var ledger = AliasTipLedger.empty
        for expectedShown in 0..<3 {
            XCTAssertTrue(ledger.isDue(id: id), "miss \(expectedShown) should be due")
            ledger.recordMiss(id: id, shown: true, date: date)
            XCTAssertEqual(ledger.lessons[id]?.tipsShown, expectedShown + 1)
        }
        XCTAssertFalse(ledger.isDue(id: id), "fourth miss needs spacing")
    }

    func testSpacedGapDoublesTwoFourEight() {
        var ledger = AliasTipLedger.empty
        for _ in 0..<3 {
            ledger.recordMiss(id: id, shown: true, date: date)
        }
        XCTAssertEqual(ledger.lessons[id]?.gap, 2)

        // Gap 2: two untipped misses before the fourth tip is due.
        ledger.recordMiss(id: id, shown: false, date: date)
        XCTAssertFalse(ledger.isDue(id: id))
        ledger.recordMiss(id: id, shown: false, date: date)
        XCTAssertTrue(ledger.isDue(id: id))
        ledger.recordMiss(id: id, shown: true, date: date)
        XCTAssertEqual(ledger.lessons[id]?.gap, 4)

        // Gap 4: four untipped misses before the fifth tip is due.
        for _ in 0..<3 {
            ledger.recordMiss(id: id, shown: false, date: date)
            XCTAssertFalse(ledger.isDue(id: id))
        }
        ledger.recordMiss(id: id, shown: false, date: date)
        XCTAssertTrue(ledger.isDue(id: id))
        ledger.recordMiss(id: id, shown: true, date: date)
        XCTAssertEqual(ledger.lessons[id]?.gap, 8)

        // Gap caps at 8.
        for _ in 0..<7 {
            ledger.recordMiss(id: id, shown: false, date: date)
            XCTAssertFalse(ledger.isDue(id: id))
        }
        ledger.recordMiss(id: id, shown: false, date: date)
        XCTAssertTrue(ledger.isDue(id: id))
        ledger.recordMiss(id: id, shown: true, date: date)
        XCTAssertEqual(ledger.lessons[id]?.gap, 8)
    }

    func testFluencyEntryAtSeventyFivePercent() {
        var ledger = AliasTipLedger.empty
        ledger.recordHit(id: id, date: date)
        ledger.recordHit(id: id, date: date)
        ledger.recordHit(id: id, date: date)
        XCTAssertFalse(ledger.isFluent(id: id))
        ledger.recordMiss(id: id, shown: false, date: date)
        XCTAssertTrue(ledger.isFluent(id: id), "3 hits of 4 chances is 75%")
        XCTAssertFalse(ledger.isDue(id: id), "fluent lessons are never due")
    }

    func testFluencyNeedsFourChances() {
        var ledger = AliasTipLedger.empty
        ledger.recordHit(id: id, date: date)
        ledger.recordHit(id: id, date: date)
        ledger.recordHit(id: id, date: date)
        XCTAssertFalse(ledger.isFluent(id: id), "three chances cannot enter fluency")
    }

    func testFluencyHysteresisExitAndLapseRestartsAtFour() {
        var ledger = AliasTipLedger.empty
        for _ in 0..<4 {
            ledger.recordHit(id: id, date: date)
        }
        XCTAssertTrue(ledger.isFluent(id: id))

        // Four misses make recent 4 hits + 4 misses = 50%: still fluent.
        for _ in 0..<4 {
            ledger.recordMiss(id: id, shown: false, date: date)
        }
        XCTAssertTrue(ledger.isFluent(id: id))

        // One more miss drops the oldest hit: 3 of 8 = 37.5%, below 50%.
        ledger.recordMiss(id: id, shown: false, date: date)
        XCTAssertFalse(ledger.isFluent(id: id))
        XCTAssertEqual(ledger.lessons[id]?.gap, AliasTipPolicy.lapseGap)
        XCTAssertEqual(ledger.lessons[id]?.missesSinceTip, 0)
    }

    func testDroppedTipCountsAsMissNotShown() {
        var ledger = AliasTipLedger.empty
        ledger.recordMiss(id: id, shown: false, date: date)
        XCTAssertEqual(ledger.lessons[id]?.tipsShown, 0)
        XCTAssertEqual(ledger.lessons[id]?.missesSinceTip, 1)
        XCTAssertEqual(ledger.lessons[id]?.recent, [.miss])
        let week = AliasTipLedger.weekKey(for: date)
        XCTAssertEqual(ledger.weeks[week]?[id]?.misses, 1)
        XCTAssertEqual(ledger.weeks[week]?[id]?.shown, 0)
    }

    func testShownTipIncrementsWeeklyShown() {
        var ledger = AliasTipLedger.empty
        ledger.recordMiss(id: id, shown: true, date: date)
        let week = AliasTipLedger.weekKey(for: date)
        XCTAssertEqual(ledger.weeks[week]?[id]?.misses, 1)
        XCTAssertEqual(ledger.weeks[week]?[id]?.shown, 1)
    }

    func testHitWithdrawalRemovesNewestHit() {
        var ledger = AliasTipLedger.empty
        ledger.recordHit(id: id, date: date)
        ledger.recordHit(id: id, date: date)
        ledger.recordMiss(id: id, shown: false, date: date)
        ledger.withdrawHit(id: id)
        XCTAssertEqual(ledger.lessons[id]?.recent, [.hit, .miss])
    }

    func testHitWithdrawalCanDropBelowFluency() {
        var ledger = AliasTipLedger.empty
        for _ in 0..<6 {
            ledger.recordHit(id: id, date: date)
        }
        ledger.recordMiss(id: id, shown: false, date: date)
        ledger.recordMiss(id: id, shown: false, date: date)
        XCTAssertTrue(ledger.isFluent(id: id))
        for _ in 0..<5 {
            ledger.withdrawHit(id: id)
        }
        XCTAssertEqual(ledger.lessons[id]?.recent, [.hit, .miss, .miss])
        XCTAssertFalse(ledger.isFluent(id: id))
    }

    func testSessionAllowsOneTipPerSession() {
        var session = AliasTipSession()
        XCTAssertTrue(session.canShow(lessonId: id))
        session.markShown()
        XCTAssertFalse(session.canShow(lessonId: id))
        XCTAssertFalse(session.canShow(lessonId: "hash_menu"))
    }

    func testSessionEscapedLessonStaysSilent() {
        var session = AliasTipSession()
        session.escape(lessonId: id)
        XCTAssertFalse(session.canShow(lessonId: id))
        XCTAssertTrue(session.canShow(lessonId: "hash_menu"))
    }

    func testIneligibleCountsPerSigil() {
        var ledger = AliasTipLedger.empty
        ledger.recordIneligible(sigil: "@")
        ledger.recordIneligible(sigil: "@")
        ledger.recordIneligible(sigil: "#")
        XCTAssertEqual(ledger.ineligible["@"], 2)
        XCTAssertEqual(ledger.ineligible["#"], 1)
    }
}
