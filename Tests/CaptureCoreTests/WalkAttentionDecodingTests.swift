import XCTest

@testable import CaptureCore

final class WalkAttentionDecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> WalkAttentionSnapshot {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(
            WalkAttentionSnapshot.self,
            from: Data(contentsOf: url)
        )
    }

    func testAllFixtureDecodesThreeFamiliesInOrder() throws {
        let snapshot = try fixture("walks-all.json")
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.date, "2026-11-17")
        XCTAssertEqual(snapshot.walks.count, 3)
        XCTAssertEqual(snapshot.walks.map(\.family), [.review, .lanes, .bank])
        XCTAssertTrue(snapshot.walks.allSatisfy { $0.available && $0.attention })
        XCTAssertEqual(snapshot.walks[0].tier, "next")
        XCTAssertEqual(snapshot.walks[0].count, 18)
        XCTAssertEqual(snapshot.walks[1].tier, "over")
        XCTAssertNil(snapshot.walks[1].count)
        XCTAssertEqual(snapshot.walks[2].tier, "waiting")
        XCTAssertEqual(snapshot.walks[2].count, 3)
    }

    func testClearFixtureHasNoAttention() throws {
        let snapshot = try fixture("walks-clear.json")
        XCTAssertEqual(snapshot.walks.count, 3)
        XCTAssertTrue(snapshot.walks.allSatisfy { $0.available && !$0.attention })
        XCTAssertTrue(snapshot.walks.allSatisfy { $0.tier == nil && $0.label == nil })
    }

    func testBankUnavailableKeepsSiblings() throws {
        let snapshot = try fixture("walks-bank-unavailable.json")
        XCTAssertEqual(snapshot.walks.count, 3)
        XCTAssertTrue(snapshot.walks[0].available)
        XCTAssertTrue(snapshot.walks[1].available)
        XCTAssertFalse(snapshot.walks[2].available)
        XCTAssertFalse(snapshot.walks[2].attention)
        XCTAssertNotNil(snapshot.walks[2].reason)
    }

    func testMissingOptionalFieldsDecodeWithDefaults() throws {
        let snapshot = try JSONDecoder().decode(
            WalkAttentionSnapshot.self,
            from: Data(#"{"walks": [{"family": "s"}]}"#.utf8)
        )
        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertNil(snapshot.date)
        XCTAssertEqual(snapshot.walks.count, 1)
        let entry = snapshot.walks[0]
        XCTAssertEqual(entry.family, .review)
        XCTAssertEqual(entry.name, "")
        XCTAssertFalse(entry.available)
        XCTAssertFalse(entry.attention)
        XCTAssertNil(entry.tier)
        XCTAssertNil(entry.label)
        XCTAssertNil(entry.reason)
        XCTAssertNil(entry.count)
    }

    func testReviewCountPrefersWalkAndFallsBackToCommitments() throws {
        let snapshot = try JSONDecoder().decode(
            WalkAttentionSnapshot.self,
            from: Data(
                #"{"walks":[{"family":"s","counts":{"walk":3,"commitments":1}},{"family":"s","counts":{"commitments":2}}]}"#.utf8
            )
        )
        XCTAssertEqual(snapshot.walks.map(\.count), [3, 2])
    }

    func testUnknownFamilyDecodesThenPresentationIgnoresIt() throws {
        let snapshot = try JSONDecoder().decode(
            WalkAttentionSnapshot.self,
            from: Data(
                #"{"date": "2026-11-17", "walks": [{"family": "zzz", "available": true, "attention": true, "tier": "new", "label": "Zed"}]}"#.utf8
            )
        )
        XCTAssertEqual(snapshot.walks[0].family, .other("zzz"))
        // Presentation drops unknown families, never throws.
        let marks = CaptureAgendaPresentation.makeWalkMarks(walks: snapshot, today: "2026-11-17")
        XCTAssertTrue(marks.isEmpty)
    }
}
