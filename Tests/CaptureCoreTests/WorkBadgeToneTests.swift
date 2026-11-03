import Foundation
import XCTest

@testable import CaptureCore

final class WorkBadgeToneTests: XCTestCase {
    func testBoundaryVectorsAtCap100UseExactComparisons() {
        assertTone(.grey, count: 0, cap: 100)
        assertTone(.blue, count: 1, cap: 100)
        assertTone(.blue, count: 39, cap: 100)
        assertTone(.green, count: 40, cap: 100)
        assertTone(.green, count: 59, cap: 100)
        assertTone(.yellow, count: 60, cap: 100)
        assertTone(.yellow, count: 79, cap: 100)
        assertTone(.orange, count: 80, cap: 100)
        assertTone(.orange, count: 99, cap: 100)
        assertTone(.magenta, count: 100, cap: 100)
        assertTone(.red, count: 101, cap: 100)
        assertTone(.red, count: 250, cap: 100)
    }

    func testBoundaryVectorsAtCap15DoNotRoundPercentages() {
        assertTone(.grey, count: 0, cap: 15)
        assertTone(.blue, count: 5, cap: 15)
        assertTone(.green, count: 6, cap: 15)
        assertTone(.green, count: 8, cap: 15)
        assertTone(.yellow, count: 9, cap: 15)
        assertTone(.yellow, count: 11, cap: 15)
        assertTone(.orange, count: 12, cap: 15)
        assertTone(.orange, count: 14, cap: 15)
        assertTone(.magenta, count: 15, cap: 15)
        assertTone(.red, count: 16, cap: 15)
    }

    func testDefaultAndSmallCapsHitEveryBand() {
        assertTone(.grey, count: 0, cap: 10)
        assertTone(.blue, count: 3, cap: 10)
        assertTone(.green, count: 4, cap: 10)
        assertTone(.green, count: 5, cap: 10)
        assertTone(.yellow, count: 6, cap: 10)
        assertTone(.yellow, count: 7, cap: 10)
        assertTone(.orange, count: 8, cap: 10)
        assertTone(.orange, count: 9, cap: 10)
        assertTone(.magenta, count: 10, cap: 10)
        assertTone(.red, count: 11, cap: 10)

        assertTone(.grey, count: 0, cap: 1)
        assertTone(.magenta, count: 1, cap: 1)
        assertTone(.red, count: 2, cap: 1)
        assertTone(.green, count: 1, cap: 2)
        assertTone(.magenta, count: 2, cap: 2)
        assertTone(.blue, count: 1, cap: 3)
        assertTone(.yellow, count: 2, cap: 3)
        assertTone(.magenta, count: 3, cap: 3)
        assertTone(.blue, count: 1, cap: 5)
        assertTone(.green, count: 2, cap: 5)
        assertTone(.yellow, count: 3, cap: 5)
        assertTone(.orange, count: 4, cap: 5)
        assertTone(.magenta, count: 5, cap: 5)
        assertTone(.red, count: 6, cap: 5)
        assertTone(.yellow, count: 10, cap: 15)
        assertTone(.magenta, count: 10, cap: 10)
    }

    func testThirteenLinkCapBoundaries() {
        assertTone(.yellow, count: 9, cap: 13)
        assertTone(.magenta, count: 13, cap: 13)
    }

    func testInvalidInputsAreUnavailable() {
        XCTAssertNil(WorkBadgeTone(count: -1, cap: 10))
        XCTAssertNil(WorkBadgeTone(count: 3, cap: 0))
        XCTAssertNil(WorkBadgeTone(count: 3, cap: -1))
    }

    func testLightAndDarkPaletteIsPinnedForEveryTone() {
        let expected: [WorkBadgeTone: (light: String, dark: String)] = [
            .grey: ("#5c5c5c", "#b3b3b3"),
            .blue: ("#086ddd", "#027aff"),
            .green: ("#08b94e", "#44cf6e"),
            .yellow: ("#e0ac00", "#e0de71"),
            .orange: ("#ec7500", "#e9973f"),
            .magenta: ("#923675", "#e5a9d8"),
            .red: ("#e93147", "#fb464c"),
        ]

        for tone in WorkBadgeTone.allCases {
            XCTAssertEqual(tone.lightHex, expected[tone]?.light)
            XCTAssertEqual(tone.darkHex, expected[tone]?.dark)
            XCTAssertEqual(tone.spokenName, tone.rawValue)
        }
    }

    func testTodayBadgeTextAndTone() {
        let yellow = TodayBadgePresentation(count: 9, cap: 13)
        XCTAssertEqual(yellow.text, "TODAY 9/13")
        XCTAssertEqual(yellow.tone, .yellow)

        let empty = TodayBadgePresentation(count: 0, cap: 7)
        XCTAssertEqual(empty.text, "TODAY 0/7")
        XCTAssertEqual(empty.tone, .grey)

        let unavailable = TodayBadgePresentation(count: 3, cap: 0)
        XCTAssertEqual(unavailable.text, "TODAY –")
        XCTAssertNil(unavailable.tone)
        XCTAssertEqual(TodayBadgePresentation(count: -1, cap: 10).text, "TODAY –")
    }

    func testTodayBadgeSpokenTextBranches() {
        XCTAssertEqual(
            TodayBadgePresentation(count: 3, cap: 10).spokenText,
            "TODAY 3 of 10 links"
        )
        XCTAssertEqual(
            TodayBadgePresentation(count: 10, cap: 10).spokenText,
            "TODAY 10 of 10 links, at cap"
        )
        XCTAssertEqual(
            TodayBadgePresentation(count: 11, cap: 10).spokenText,
            "TODAY 11 of 10 links, over cap"
        )
        XCTAssertEqual(
            TodayBadgePresentation(count: 3, cap: 0).spokenText,
            "TODAY unavailable"
        )
    }

    func testTodayBadgeHelpText() {
        XCTAssertEqual(
            TodayBadgePresentation(count: 9, cap: 13).helpText,
            "9 of 13 Task Links in today's open Pomodoros"
        )
        XCTAssertEqual(
            TodayBadgePresentation(count: 0, cap: 0).helpText,
            "Today's Task Link budget is unavailable"
        )
    }

    private func assertTone(
        _ expected: WorkBadgeTone,
        count: Int,
        cap: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(WorkBadgeTone(count: count, cap: cap), expected, file: file, line: line)
    }
}
