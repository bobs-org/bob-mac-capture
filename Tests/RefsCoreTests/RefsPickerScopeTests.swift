import XCTest

@testable import RefsCore

final class RefsPickerScopeTests: XCTestCase {
    func testCountCaptionsUseSingularAndPluralNouns() {
        XCTAssertEqual(scope(.codeBlock, total: 1).countCaption, "1 CODE BLOCK")
        XCTAssertEqual(scope(.codeBlock, total: 13).countCaption, "13 CODE BLOCKS")
        XCTAssertEqual(scope(.link, total: 1).countCaption, "1 LINK")
        XCTAssertEqual(scope(.highlight, total: 9).countCaption, "9 HIGHLIGHTS")
    }

    func testOrdinalAndScopeLabelsCoverWindowedAllShownAndSingleLists() {
        let windowed = RefsPickerScope(
            noun: .codeBlock,
            total: 13,
            selectedIndex: 6,
            visibleStart: 5,
            visibleCount: 3
        )
        XCTAssertEqual(windowed.ordinalLabel, "Block 7 of 13")
        XCTAssertEqual(windowed.scopeLabel, "showing 6–8")
        XCTAssertEqual(windowed.accessibilityLabel, "Code block 7 of 13, showing 6 to 8")

        let allShown = RefsPickerScope(
            noun: .link,
            total: 3,
            selectedIndex: 1,
            visibleStart: 0,
            visibleCount: 3
        )
        XCTAssertEqual(allShown.scopeLabel, "all shown")
        XCTAssertEqual(allShown.accessibilityLabel, "Link 2 of 3, all shown")

        let single = scope(.highlight, total: 1)
        XCTAssertEqual(single.ordinalLabel, "Highlight 1 of 1")
        XCTAssertNil(single.scopeLabel)
        XCTAssertEqual(single.accessibilityLabel, "Highlight 1 of 1")
    }

    func testDigitHintsAndMissesUseVisiblePositions() {
        for visibleCount in [1, 3] {
            let windowed = RefsPickerScope(
                noun: .link,
                total: 8,
                selectedIndex: 4,
                visibleStart: 4,
                visibleCount: visibleCount
            )
            let range = visibleCount == 1 ? "1" : "1–3"
            XCTAssertEqual(windowed.digitRangeText, range)
            XCTAssertEqual(windowed.pickHint, "\(range) \(visibleCount == 1 ? "picks" : "pick")")
            let windowVerb = visibleCount == 1 ? "is" : "are"
            XCTAssertEqual(
                windowed.digitMissMessage,
                "Only \(range) \(windowVerb) showing · ↑↓ scrolls"
            )

            let allShown = RefsPickerScope(
                noun: .highlight,
                total: visibleCount,
                selectedIndex: 0,
                visibleStart: 0,
                visibleCount: visibleCount
            )
            let verb = visibleCount == 1 ? "is" : "are"
            XCTAssertEqual(allShown.digitMissMessage, "Only \(range) \(verb) listed")
        }
    }

    func testRailGeometryTracksVisibleEntriesAndSelection() throws {
        let total = 13
        let visible = 3
        for start in [0, total - visible] {
            let scope = RefsPickerScope(
                noun: .codeBlock,
                total: total,
                selectedIndex: start + visible - 1,
                visibleStart: start,
                visibleCount: visible
            )
            let geometry = try XCTUnwrap(
                RefsPickerRailGeometry.make(
                    scope: scope,
                    trackHeight: 100,
                    minimumThumbHeight: 16,
                    tickHalfHeight: 1
                )
            )
            if start == 0 {
                XCTAssertEqual(geometry.thumb.lowerBound, 0, accuracy: 0.0001)
            }
            if start == total - visible {
                XCTAssertEqual(geometry.thumb.upperBound, 100, accuracy: 0.0001)
            }
            XCTAssertTrue(geometry.thumb.contains(geometry.selectedY))

            let visibleCenters = (start..<(start + visible)).compactMap(geometry.y(forIndex:))
            XCTAssertEqual(visibleCenters.count, visible)
            XCTAssertTrue(visibleCenters.allSatisfy(geometry.thumb.contains))
            let allCenters = (0..<total).compactMap(geometry.y(forIndex:))
            XCTAssertTrue(
                zip(allCenters, allCenters.dropFirst()).allSatisfy { $0.0 < $0.1 }
            )
        }
    }

    func testRailGeometryHonorsMinimumThumbMergesTicksAndHidesWhenUnwindowed() throws {
        let unwindowed = RefsPickerScope(
            noun: .link,
            total: 3,
            selectedIndex: 1,
            visibleStart: 0,
            visibleCount: 3
        )
        XCTAssertNil(
            RefsPickerRailGeometry.make(
                scope: unwindowed,
                trackHeight: 100,
                minimumThumbHeight: 16,
                tickHalfHeight: 1
            )
        )

        let smallThumbScope = RefsPickerScope(
            noun: .link,
            total: 200,
            selectedIndex: 100,
            visibleStart: 99,
            visibleCount: 3
        )
        let smallThumb = try XCTUnwrap(
            RefsPickerRailGeometry.make(
                scope: smallThumbScope,
                trackHeight: 200,
                minimumThumbHeight: 16,
                tickHalfHeight: 1
            )
        )
        XCTAssertEqual(smallThumb.thumb.upperBound - smallThumb.thumb.lowerBound, 16)

        let tickScope = RefsPickerScope(
            noun: .link,
            total: 10,
            selectedIndex: 2,
            visibleStart: 2,
            visibleCount: 3,
            onPageIndices: [0, 1, 2, 3]
        )
        let merged = try XCTUnwrap(
            RefsPickerRailGeometry.make(
                scope: tickScope,
                trackHeight: 4,
                minimumThumbHeight: 3,
                tickHalfHeight: 1
            )
        )
        XCTAssertEqual(merged.ticks.count, 1)
    }

    private func scope(_ noun: RefsPickerNoun, total: Int) -> RefsPickerScope {
        RefsPickerScope(
            noun: noun,
            total: total,
            selectedIndex: 0,
            visibleStart: 0,
            visibleCount: total
        )
    }
}
