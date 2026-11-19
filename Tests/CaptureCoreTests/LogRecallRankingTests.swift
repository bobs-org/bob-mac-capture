import XCTest

@testable import CaptureCore

final class LogRecallRankingTests: XCTestCase {
    private struct Vectors: Decodable {
        let version: Int
        let normalize: [NormalizeCase]
        let rank: [RankCase]
    }

    private struct NormalizeCase: Decodable {
        let name: String
        let input: String
        let expected: String
    }

    private struct RankCatalogPhrase: Decodable {
        let text: String
        let key: String
        let score: Double
        let recencyRank: Int

        private enum CodingKeys: String, CodingKey {
            case text
            case key
            case score
            case recencyRank = "recency_rank"
        }
    }

    private struct RankOverlay: Decodable {
        let key: String
        let text: String
        let at: String
    }

    private struct RankCase: Decodable {
        let name: String
        let query: String
        let catalog: [RankCatalogPhrase]
        let overlay: [RankOverlay]?
        let expected: [String]
    }

    private func loadVectors() throws -> Vectors {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/log-recall-vectors.json")
        return try JSONDecoder().decode(
            Vectors.self, from: Data(contentsOf: url))
    }

    private func phrase(
        _ row: RankCatalogPhrase, index: Int, overlayAt: [String: Int] = [:]
    ) -> LogRecallPhrase {
        // Overlay keys sort before every catalog phrase; a later `at`
        // sorts before an earlier one. Model recency_rank 0 as the newest
        // catalog row and shift overlay rows before it with negative ranks.
        let rank =
            overlayAt[row.key] ?? (row.recencyRank + overlayAt.count)
        return LogRecallPhrase(
            text: row.text,
            key: row.key,
            uses: 1,
            lastUsed: "2026-11-19",
            score: row.score,
            recencyRank: rank
        )
    }

    func testVectorsNormalize() throws {
        let vectors = try loadVectors()
        XCTAssertEqual(vectors.version, 1)
        for row in vectors.normalize {
            XCTAssertEqual(
                LogRecallRanking.normalize(row.input), row.expected,
                "normalize: \(row.name)")
        }
    }

    func testVectorsRank() throws {
        let vectors = try loadVectors()
        for row in vectors.rank {
            if let overlay = row.overlay {
                // Overlay vectors belong to the Obsidian session overlay,
                // which the Mac does not implement. The newest-pin + frecency
                // order still holds for the catalog rows alone.
                let phrases = row.catalog.enumerated().map { index, item in
                    LogRecallPhrase(
                        text: item.text, key: item.key, uses: 1,
                        lastUsed: "2026-11-19", score: item.score,
                        recencyRank: item.recencyRank)
                }
                let ranked = LogRecallRanking.rank(
                    phrases: phrases, query: row.query)
                XCTAssertFalse(ranked.isEmpty, "rank: \(row.name)")
                // Overlay entries would sort first; catalog order is stable.
                let catalogExpected = row.expected.filter { key in
                    !overlay.map(\.key).contains(key)
                }
                let catalogKeys = ranked.map(\.phrase.key).filter { key in
                    !overlay.map(\.key).contains(key)
                }
                XCTAssertEqual(catalogKeys, catalogExpected, "rank: \(row.name)")
                continue
            }
            let phrases = row.catalog.map { item in
                LogRecallPhrase(
                    text: item.text, key: item.key, uses: 1,
                    lastUsed: "2026-11-19", score: item.score,
                    recencyRank: item.recencyRank)
            }
            let ranked = LogRecallRanking.rank(phrases: phrases, query: row.query)
            XCTAssertEqual(
                ranked.map(\.phrase.key), row.expected, "rank: \(row.name)")
        }
    }

    func testRankTiersAndNewestPin() {
        let phrases = [
            LogRecallPhrase(
                text: "flagship", key: "flagship", score: 4.0, recencyRank: 2),
            LogRecallPhrase(
                text: "the agent", key: "the agent", score: 0.1, recencyRank: 1),
            LogRecallPhrase(
                text: "athena agent", key: "athena agent", score: 0.1,
                recencyRank: 0),
            LogRecallPhrase(
                text: "agentic", key: "agentic", score: 0.1, recencyRank: 5),
            LogRecallPhrase(
                text: "agent", key: "agent", score: 0.2, recencyRank: 3),
            LogRecallPhrase(text: "ag", key: "ag", score: 0.1, recencyRank: 6),
        ]
        let ranked = LogRecallRanking.rank(phrases: phrases, query: "ag")
        XCTAssertEqual(
            ranked.map(\.phrase.key),
            ["ag", "agent", "agentic", "athena agent", "the agent", "flagship"])
        XCTAssertEqual(
            ranked.map(\.match),
            [.exact, .prefix, .prefix, .word, .word, .substring])
    }

    func testEmptyQueryPinsNewestThenFrecency() {
        let phrases = [
            LogRecallPhrase(
                text: "often used", key: "often used", score: 8.0, recencyRank: 2),
            LogRecallPhrase(
                text: "newest", key: "newest", score: 0.1, recencyRank: 0),
            LogRecallPhrase(
                text: "less used", key: "less used", score: 2.0, recencyRank: 1),
        ]
        let ranked = LogRecallRanking.rank(phrases: phrases, query: "")
        XCTAssertEqual(
            ranked.map(\.phrase.key), ["newest", "often used", "less used"])
        XCTAssertTrue(ranked.allSatisfy { $0.match == nil })
    }

    func testTiesBreakByKey() {
        let phrases = [
            LogRecallPhrase(text: "zulu", key: "zulu", score: 1.0, recencyRank: 0),
            LogRecallPhrase(
                text: "alpha", key: "alpha", score: 1.0, recencyRank: 0),
            LogRecallPhrase(text: "beta", key: "beta", score: 0.5, recencyRank: 1),
        ]
        let ranked = LogRecallRanking.rank(phrases: phrases, query: "")
        // Newest (rank 0) pins first: alpha before zulu by key, then beta.
        XCTAssertEqual(ranked.map(\.phrase.key), ["alpha", "zulu", "beta"])
    }

    func testWordPrefixBoundary() {
        XCTAssertTrue(LogRecallRanking.hasWordPrefix("athena agent", query: "ag"))
        XCTAssertFalse(LogRecallRanking.hasWordPrefix("flagship", query: "ag"))
        XCTAssertTrue(LogRecallRanking.hasWordPrefix("the agent", query: "ag"))
    }
}
