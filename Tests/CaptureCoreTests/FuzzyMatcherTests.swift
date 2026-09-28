import XCTest

@testable import CaptureCore

final class FuzzyMatcherTests: XCTestCase {
    func testQuerySplitsOnWhitespaceAndFoldsTokens() {
        XCTAssertEqual(FuzzyQuery("  q   weight ").tokens, ["q", "weight"])
        XCTAssertEqual(FuzzyQuery("TUI").tokens, ["tui"])
        XCTAssertTrue(FuzzyQuery("").isEmpty)
        XCTAssertTrue(FuzzyQuery("   ").isEmpty)
    }

    func testQueryStripsOneLeadingCaretFromFirstToken() {
        XCTAssertEqual(FuzzyQuery("^dee").tokens, ["dee"])
        XCTAssertEqual(FuzzyQuery("^sase:dee").tokens, ["sase:dee"])
        XCTAssertEqual(FuzzyQuery("^dee ^foo").tokens, ["dee", "^foo"])
        XCTAssertTrue(FuzzyQuery("^").isEmpty)
    }

    func testCaseAndDiacriticInsensitivity() {
        XCTAssertNotNil(FuzzyMatcher.match(token: "cafe", in: FuzzyField("Café")))
        XCTAssertNotNil(FuzzyMatcher.match(token: "CAFÉ", in: FuzzyField("cafe")))
        XCTAssertEqual(
            FuzzyMatcher.match(token: "TUI", in: FuzzyField("tui panel"))?.positions,
            [0, 1, 2]
        )
        XCTAssertEqual(
            FuzzyMatcher.match(token: "tui", in: FuzzyField("TUI panel"))?.positions,
            [0, 1, 2]
        )
    }

    func testConsecutiveBeatsScattered() {
        let tight = FuzzyMatcher.match(token: "deep", in: FuzzyField("Fix deep bug from UX chat"))
        let scattered = FuzzyMatcher.match(token: "deep", in: FuzzyField("Delete every empty page"))
        XCTAssertNotNil(tight)
        XCTAssertNotNil(scattered)
        XCTAssertGreaterThan(tight!.score, scattered!.score)
    }

    func testBoundaryStartBeatsMidWordMatch() {
        let boundary = FuzzyMatcher.match(token: "fix", in: FuzzyField("fix-claude-monitors"))
        let midWord = FuzzyMatcher.match(token: "fix", in: FuzzyField("prefix"))
        XCTAssertEqual(boundary?.positions, [0, 1, 2])
        XCTAssertEqual(midWord?.positions, [3, 4, 5])
        XCTAssertGreaterThan(boundary!.score, midWord!.score)
    }

    func testTokenMatchesRouteBlockID() {
        let match = FuzzyMatcher.match(token: "sase:dee", in: FuzzyField("sase:deep-fix"))
        XCTAssertEqual(match?.positions, [0, 1, 2, 3, 4, 5, 6, 7])
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(FuzzyMatcher.match(token: "zzz", in: FuzzyField("abc")))
        XCTAssertNil(FuzzyMatcher.match(token: "longtoken", in: FuzzyField("short")))
        XCTAssertNil(FuzzyMatcher.match(token: "a", in: FuzzyField("")))
    }

    func testPositionsAreCorrectAndAscending() {
        let match = FuzzyMatcher.match(token: "dee", in: FuzzyField("Fix deep bug"))
        XCTAssertEqual(match?.positions, [4, 5, 6])
        XCTAssertEqual(match?.positions, match?.positions.sorted())
    }

    func testTiesPreferEarliestEndThenEarliestStart() {
        XCTAssertEqual(
            FuzzyMatcher.match(token: "ab", in: FuzzyField("ab ab"))?.positions,
            [0, 1]
        )
        XCTAssertEqual(
            FuzzyMatcher.match(token: "a", in: FuzzyField(" a a"))?.positions,
            [1]
        )
    }

    func testOnlyFirst256CharactersAreSearchable() {
        let field = FuzzyField(String(repeating: "a", count: 300) + "b")
        XCTAssertEqual(field.count, 256)
        XCTAssertNil(FuzzyMatcher.match(token: "b", in: field))
        XCTAssertEqual(FuzzyMatcher.match(token: "a", in: field)?.positions, [0])
    }

    func testGapPenaltyGrowsWithSkippedCharacters() {
        let adjacent = FuzzyMatcher.match(token: "ac", in: FuzzyField("ac"))
        let gapped = FuzzyMatcher.match(token: "ac", in: FuzzyField("a---c"))
        XCTAssertNotNil(adjacent)
        XCTAssertNotNil(gapped)
        XCTAssertGreaterThan(adjacent!.score, gapped!.score)
    }
}
