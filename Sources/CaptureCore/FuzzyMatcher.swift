import Foundation

/// Splits raw picker filter text into folded match tokens. Whitespace separates
/// tokens, empty tokens are dropped, and one leading `^` is stripped from the
/// first token so a filter seeded from the draft (`^dee`) behaves like the bare
/// text (`dee`). An empty token list means "no filter" (the grouped view).
public struct FuzzyQuery: Equatable, Sendable {
    public let tokens: [String]

    public init(_ raw: String) {
        var parts = raw.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if var first = parts.first, first.hasPrefix("^") {
            first.removeFirst()
            if first.isEmpty {
                parts.removeFirst()
            } else {
                parts[0] = first
            }
        }
        self.tokens = parts.map { FuzzyMatcher.folded($0) }.filter { !$0.isEmpty }
    }

    public var isEmpty: Bool {
        tokens.isEmpty
    }
}

/// A searchable field with one folded character and one boundary bonus per
/// `Character` of the original text, so matching stays index-aligned with the
/// display string and highlight offsets map directly onto it. Only the first
/// `FuzzyMatcher.maxFieldLength` characters are searchable.
public struct FuzzyField: Sendable {
    /// Folded characters of the searchable prefix, index-aligned with the
    /// original text.
    let folded: [Character]
    /// Boundary bonus per character offset (see `FuzzyMatcher` constants).
    let boundaryBonus: [Int]

    public init(_ text: String) {
        let chars = Array(text.prefix(FuzzyMatcher.maxFieldLength))
        self.folded = chars.map { FuzzyMatcher.foldedCharacter($0) }
        self.boundaryBonus = chars.indices.map { index in
            FuzzyMatcher.boundaryBonus(at: index, in: chars)
        }
    }

    public var isEmpty: Bool {
        folded.isEmpty
    }

    public var count: Int {
        folded.count
    }
}

/// The optimal alignment of one query token inside a field: the total score
/// and the ascending `Character` offsets of each matched token character.
public struct FuzzyFieldMatch: Equatable, Sendable {
    public let score: Int
    public let positions: [Int]

    public init(score: Int, positions: [Int]) {
        self.score = score
        self.positions = positions
    }
}

/// Pure subsequence fuzzy matcher over folded characters. Every token
/// character must match in order; leading and trailing unmatched text is free.
public enum FuzzyMatcher: Sendable {
    /// Points per matched token character.
    public static let matchPoints = 16
    /// Boundary bonus for a match at the very start of the field.
    public static let startBoundaryBonus = 10
    /// Boundary bonus after whitespace or a non-alphanumeric separator.
    public static let separatorBoundaryBonus = 8
    /// Boundary bonus at a lowercase-to-uppercase or letter-to-digit
    /// transition (in either direction for letters and digits).
    public static let transitionBoundaryBonus = 6
    /// Bonus when a match directly follows the previous matched character.
    public static let consecutiveBonus = 8
    /// Gap penalty to open a run of skipped characters between matches.
    public static let gapOpenPenalty = 3
    /// Gap penalty per additional skipped character after the first.
    public static let gapExtendPenalty = 1
    /// Only the first this many characters of a field are searchable.
    public static let maxFieldLength = 256

    /// Returns the optimal alignment of `token` in `field`, or nil when the
    /// token's characters do not appear in order. Runs in O(m*n) time for a
    /// token of m characters and a field of n characters using an affine gap
    /// penalty. Ties prefer the earliest end position, then the earliest
    /// start.
    public static func match(token: String, in field: FuzzyField) -> FuzzyFieldMatch? {
        let wanted = folded(token).map { $0 }
        let needed = wanted.count
        guard needed > 0 else {
            return FuzzyFieldMatch(score: 0, positions: [])
        }
        let available = field.folded.count
        guard needed <= available else {
            return nil
        }

        // dpPrev[j] is the best score aligning the previous token prefix with
        // token character (i - 1) landing exactly on field offset j, plus the
        // start offset of that alignment for tie-breaking. link[i][j] is the
        // previous field offset (or -1 for "starts here").
        var dpPrev = [Int?](repeating: nil, count: available)
        var startPrev = [Int](repeating: 0, count: available)
        var link = [[Int]](
            repeating: [Int](repeating: -2, count: available),
            count: needed
        )

        for i in 0..<needed {
            var dpCurr = [Int?](repeating: nil, count: available)
            var startCurr = [Int](repeating: 0, count: available)
            // Best (dpPrev[k] + k, startPrev[k]) over eligible gap sources
            // k <= j - 2, so a gap of g >= 1 skipped characters costs
            // gapOpenPenalty + (g - 1) * gapExtendPenalty.
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
                    // Leading unmatched text is free; the first matched
                    // character's boundary bonus counts double.
                    base = matchPoints + 2 * field.boundaryBonus[j]
                } else {
                    base = matchPoints + field.boundaryBonus[j]
                }
                var best: Int?
                var bestStart = j
                var bestLink = -1
                if i == 0 {
                    best = base
                } else {
                    if j > 0, let adjacent = dpPrev[j - 1] {
                        best = adjacent + base + consecutiveBonus
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

        // Trailing unmatched text is free: the best alignment may end
        // anywhere. Scan end offsets ascending so ties keep the earliest end,
        // then the earliest start.
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

    /// Folds one character for comparison: case, diacritics, and width are
    /// ignored. Falls back to the lowercased character when folding does not
    /// produce exactly one character, keeping field indices 1:1 with the
    /// original text.
    static func foldedCharacter(_ c: Character) -> Character {
        let folded = String(c).folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: nil
        )
        if folded.count == 1, let single = folded.first {
            return single
        }
        return c.lowercased().first ?? c
    }

    /// Folds a whole token with the same per-character rule as fields.
    static func folded(_ text: String) -> String {
        text.map { String(foldedCharacter($0)) }.joined()
    }

    /// Boundary bonus for the character at `index`: field start wins over a
    /// separator, which wins over a case or letter-digit transition.
    static func boundaryBonus(at index: Int, in chars: [Character]) -> Int {
        if index == 0 {
            return startBoundaryBonus
        }
        let previous = chars[index - 1]
        let current = chars[index]
        if previous.isWhitespace || !(previous.isLetter || previous.isNumber) {
            return separatorBoundaryBonus
        }
        if previous.isLowercase && current.isUppercase {
            return transitionBoundaryBonus
        }
        if (previous.isLetter && current.isNumber) || (previous.isNumber && current.isLetter) {
            return transitionBoundaryBonus
        }
        return 0
    }
}
