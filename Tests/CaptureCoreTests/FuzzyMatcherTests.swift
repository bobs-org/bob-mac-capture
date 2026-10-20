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

    func testQueryStripsMultiByteRelationSigils() {
        XCTAssertEqual(FuzzyQuery("~tar", leadingSigil: "~").tokens, ["tar"])
        XCTAssertEqual(FuzzyQuery("~~sou", leadingSigil: "~~").tokens, ["sou"])
        XCTAssertTrue(FuzzyQuery("~~", leadingSigil: "~~").isEmpty)
        XCTAssertEqual(FuzzyQuery("~~sou", leadingSigil: "~").tokens, ["~sou"])
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

    func testFoldingIsIdempotent() {
        let samples = ["", "a", "Café", "TUI", "ß", "Ａ", "Éé", "Fix deep bug"]
        for sample in samples {
            let once = FuzzyMatcher.folded(sample)
            XCTAssertEqual(FuzzyMatcher.folded(once), once, sample)
        }
    }

    func testMatchAgreesWithOracleOnSeededRandomInputs() {
        var rng = LCG(seed: 2_026_101_020)
        let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -_Café")
        for _ in 0..<250 {
            let token = randomString(alphabet: alphabet, length: rng.next(in: 0...8), rng: &rng)
            let field = randomString(alphabet: alphabet, length: rng.next(in: 0...36), rng: &rng)
            let actual = FuzzyMatcher.match(token: token, in: FuzzyField(field))
            let expected = oracleMatch(token: token, in: FuzzyField(field))
            XCTAssertEqual(actual, expected, "token=\(token) field=\(field)")
        }
    }

    private func randomString(
        alphabet: [Character],
        length: Int,
        rng: inout LCG
    ) -> String {
        guard length > 0 else {
            return ""
        }
        var characters: [Character] = []
        characters.reserveCapacity(length)
        for _ in 0..<length {
            characters.append(alphabet[rng.next(in: 0...(alphabet.count - 1))])
        }
        return String(characters)
    }
}

/// Pre-fast-path DP oracle: folds the token, allocates the full table, and
/// never uses the subsequence check. Scores and positions must match `match`.
private func oracleMatch(token: String, in field: FuzzyField) -> FuzzyFieldMatch? {
    let wanted = FuzzyMatcher.folded(token).map { $0 }
    let needed = wanted.count
    guard needed > 0 else {
        return FuzzyFieldMatch(score: 0, positions: [])
    }
    let available = field.folded.count
    guard needed <= available else {
        return nil
    }

    var dpPrev = [Int?](repeating: nil, count: available)
    var startPrev = [Int](repeating: 0, count: available)
    var link = [[Int]](
        repeating: [Int](repeating: -2, count: available),
        count: needed
    )

    for i in 0..<needed {
        var dpCurr = [Int?](repeating: nil, count: available)
        var startCurr = [Int](repeating: 0, count: available)
        var runValue: Int?
        var runStart = 0
        var runSource = 0
        for j in 0..<available {
            if j - 2 >= 0, let source = dpPrev[j - 2] {
                let value = source + (j - 2)
                let runStartAtSource = startPrev[j - 2]
                if runValue == nil || value > runValue! || (value == runValue! && runStartAtSource < runStart) {
                    runValue = value
                    runStart = startPrev[j - 2]
                    runSource = j - 2
                }
            }
            guard field.folded[j] == wanted[i] else {
                continue
            }
            let base: Int
            if i == 0 {
                base = FuzzyMatcher.matchPoints + 2 * field.boundaryBonus[j]
            } else {
                base = FuzzyMatcher.matchPoints + field.boundaryBonus[j]
            }
            var best: Int?
            var bestStart = j
            var bestLink = -1
            if i == 0 {
                best = base
            } else {
                if j > 0, let adjacent = dpPrev[j - 1] {
                    best = adjacent + base + FuzzyMatcher.consecutiveBonus
                    bestStart = startPrev[j - 1]
                    bestLink = j - 1
                }
                if let run = runValue {
                    let gapped = run - j - 1 + base
                    if best == nil || gapped > best!
                        || (gapped == best! && runStart < bestStart)
                    {
                        best = gapped
                        bestStart = runStart
                        bestLink = runSource
                    }
                }
            }
            dpCurr[j] = best
            startCurr[j] = bestStart
            link[i][j] = bestLink
        }
        dpPrev = dpCurr
        startPrev = startCurr
    }

    var end: Int?
    var endScore = 0
    var endStart = 0
    for j in 0..<available {
        guard let score = dpPrev[j] else {
            continue
        }
        if end == nil || score > endScore || (score == endScore && startPrev[j] < endStart) {
            end = j
            endScore = score
            endStart = startPrev[j]
        }
    }
    guard let last = end else {
        return nil
    }

    var positions = [Int](repeating: 0, count: needed)
    var j = last
    for i in stride(from: needed - 1, through: 0, by: -1) {
        positions[i] = j
        if i > 0 {
            j = link[i][j]
        }
    }
    return FuzzyFieldMatch(score: endScore, positions: positions)
}

private struct LCG: RandomNumberGenerator {
    var seed: UInt64

    mutating func next() -> UInt64 {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1
        return seed
    }

    mutating func next(in range: ClosedRange<Int>) -> Int {
        let span = UInt64(range.upperBound - range.lowerBound + 1)
        return range.lowerBound + Int(next() % span)
    }
}
