import Foundation

/// Client-side ranking for the `USED BEFORE` band. Matches Design §2 of
/// `docs/log-recall.md` without an overlay: the Mac trusts bob's
/// `recency_rank` and `score` and never parses dates to rank.
///
/// Shared vectors live at `Tests/Fixtures/log-recall-vectors.json`
/// (byte-identical to bob-cli `tests/fixtures/log_recall/vectors.json`);
/// `LogRecallRankingTests` runs every vector.
public enum LogRecallRanking {
    /// Frecency half-life in days, matching bob's `HALF_LIFE_DAYS`.
    public static let halfLifeDays = 7.0

    /// `key = lowercase(collapse_whitespace(NFC(text)))`.
    public static func normalize(_ text: String) -> String {
        let nfc = text.precomposedStringWithCanonicalMapping
        let lowered = nfc.lowercased()
        return
            lowered
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Ranked row: the phrase plus its match tier (nil for an empty query).
    public struct Ranked: Equatable, Sendable {
        public let phrase: LogRecallPhrase
        public let match: LogRecallMatch?

        public init(phrase: LogRecallPhrase, match: LogRecallMatch? = nil) {
            self.phrase = phrase
            self.match = match
        }
    }

    /// Rank `phrases` against `query` (the field draft, normalized here).
    public static func rank(
        phrases: [LogRecallPhrase], query: String?
    ) -> [Ranked] {
        guard let query else {
            return sortAll(phrases).map { Ranked(phrase: $0) }
        }
        let normalized = normalize(query)
        if normalized.isEmpty {
            return sortAll(phrases).map { Ranked(phrase: $0) }
        }
        var exact: [LogRecallPhrase] = []
        var prefix: [LogRecallPhrase] = []
        var word: [LogRecallPhrase] = []
        var substring: [LogRecallPhrase] = []
        for phrase in phrases {
            if phrase.key == normalized {
                exact.append(phrase)
            } else if phrase.key.hasPrefix(normalized) {
                prefix.append(phrase)
            } else if hasWordPrefix(phrase.key, query: normalized) {
                word.append(phrase)
            } else if phrase.key.contains(normalized) {
                substring.append(phrase)
            }
        }
        var result: [Ranked] = []
        for (tier, rows) in [
            (LogRecallMatch.exact, exact), (.prefix, prefix), (.word, word),
            (.substring, substring),
        ] {
            for phrase in sortTier(rows) {
                result.append(Ranked(phrase: phrase, match: tier))
            }
        }
        return result
    }

    /// Word-prefix: `q` starts at a word boundary — the char before is not
    /// alphanumeric and the char at that position is alphanumeric.
    /// `ag` finds `athena agent`.
    static func hasWordPrefix(_ text: String, query: String) -> Bool {
        guard !query.isEmpty else { return false }
        var searchFrom = text.startIndex
        while searchFrom < text.endIndex,
            let range = text.range(
                of: query, options: [], range: searchFrom..<text.endIndex)
        {
            if range.lowerBound == text.startIndex {
                return true
            }
            let before = text[text.index(before: range.lowerBound)]
            let at = text[range.lowerBound]
            let beforeIsAlnum = before.isLetter || before.isNumber
            let atIsAlnum = at.isLetter || at.isNumber
            if !beforeIsAlnum, atIsAlnum {
                return true
            }
            searchFrom = text.index(after: range.lowerBound)
        }
        return false
    }

    static func sortAll(_ phrases: [LogRecallPhrase]) -> [LogRecallPhrase] {
        sortTier(phrases)
    }

    /// Within a tier the single newest matching phrase is pinned first;
    /// the rest sort by `score` descending, `recency_rank` ascending, `key`
    /// ascending. "Newest" is the lowest bob-provided `recency_rank`.
    static func sortTier(_ phrases: [LogRecallPhrase]) -> [LogRecallPhrase] {
        let newest = phrases.map(\.recencyRank).min()
        return phrases.sorted { left, right in
            let leftPinned = left.recencyRank == newest
            let rightPinned = right.recencyRank == newest
            if leftPinned != rightPinned {
                return leftPinned && !rightPinned
            }
            if left.score != right.score {
                return left.score > right.score
            }
            if left.recencyRank != right.recencyRank {
                return left.recencyRank < right.recencyRank
            }
            return left.key < right.key
        }
    }
}
