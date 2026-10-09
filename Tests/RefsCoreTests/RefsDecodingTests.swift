import Foundation
import XCTest

@testable import RefsCore

/// Decoding tests for the `bob ref list` and `bob plan` envelopes. Payloads
/// mirror real bob output; the golden file is synthetic but keeps the live
/// key set and key order.
final class RefsDecodingTests: XCTestCase {
    func testGoldenEnvelopeDecodesWithOneLossySkip() throws {
        let response = try decodeGoldenList()

        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.generatedAt, "2026-10-08T09:00:00")
        XCTAssertEqual(response.refs.count, 43)
        XCTAssertEqual(response.skippedRowCount, 1)
        XCTAssertEqual(response.refs[0].path, "ref/chat/omnigent_review_notes.md")
        XCTAssertEqual(response.refs[0].title, "Field notes on the new Omnigent")
        XCTAssertFalse(response.refs[0].blocked)
    }

    func testGoldenRowsCarryBlockedKindAndIdentityFields() throws {
        let response = try decodeGoldenList()
        let byPath = Dictionary(uniqueKeysWithValues: response.refs.map { ($0.path, $0) })

        XCTAssertTrue(try XCTUnwrap(byPath["ref/docs/next_blocked_runbook.md"]).blocked)
        XCTAssertTrue(try XCTUnwrap(byPath["ref/blogs/ready_blocked_post.md"]).blocked)
        XCTAssertEqual(
            try XCTUnwrap(byPath["ref/papers/just_added_attention.md"]).refType,
            "papers"
        )
        XCTAssertNil(try XCTUnwrap(byPath["ref/chat/nulltype_note.md"]).refType)
        XCTAssertEqual(
            try XCTUnwrap(byPath["ref/papers/arxiv_row.md"]).arxiv,
            "2401.12345"
        )
        XCTAssertEqual(
            try XCTUnwrap(byPath["ref/papers/doi_row.md"]).doi,
            "10.1000/xyz123"
        )
        // A row without `blocked` (older bob) reads as not blocked.
        XCTAssertFalse(try XCTUnwrap(byPath["ref/chat/reading_deep_dive.md"]).blocked)
    }

    func testRowWithoutBlockedKeyDefaultsToFalse() throws {
        let record = try JSONDecoder().decode(
            RefRecord.self,
            from: Data("""
            {"path":"ref/chat/x.md","link":"[[ref/chat/x]]","title":"X"}
            """.utf8)
        )

        XCTAssertFalse(record.blocked)
        XCTAssertEqual(record.urls, [])
        XCTAssertEqual(record.annotationCount, 0)
        XCTAssertEqual(record.commentCount, 0)
        XCTAssertNil(record.sourcePDF)
    }

    func testUnknownFieldsAreIgnored() throws {
        let record = try JSONDecoder().decode(
            RefRecord.self,
            from: Data("""
            {"path":"ref/chat/x.md","link":"[[ref/chat/x]]","title":"X",
             "future_field":"new","era":"modern","status_sync":"ok",
             "identity":{"keys":[],"arxiv":null,"doi":null,"orcid":"0000"}}
            """.utf8)
        )

        XCTAssertEqual(record.path, "ref/chat/x.md")
    }

    func testSnapshotSyncedAtSurvivesHighlightsCounts() throws {
        let record = try JSONDecoder().decode(
            RefRecord.self,
            from: Data("""
            {"path":"ref/chat/x.md","link":"[[ref/chat/x]]","title":"X",
             "snapshot":{"synced_at":"2026-10-08T13:30:11Z","highlights_count":4}}
            """.utf8)
        )

        XCTAssertEqual(record.snapshotSyncedAt, "2026-10-08T13:30:11Z")
    }

    func testGoldenGitRowIsDatelessInPlainList() throws {
        let response = try decodeGoldenList()
        let byPath = Dictionary(uniqueKeysWithValues: response.refs.map { ($0.path, $0) })
        // Live `bob` never emits a git date in the plain list; it
        // arrives through the `-g` merge path (`gitAddedDates`).
        let git = try XCTUnwrap(byPath["ref/chat/git_added_note.md"])
        XCTAssertNil(git.added)
        XCTAssertNil(git.addedSource)
    }

    func testCacheRoundTripPreservesRecords() throws {
        let response = try decodeGoldenList()
        let snapshot = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
            records: response.refs,
            gitAddedDates: ["ref/chat/git_added_note.md": "2026-09-02"]
        )

        let data = try RefsStoreCodecs.encoder().encode(snapshot)
        let roundTripped = try RefsStoreCodecs.decoder().decode(
            RefsSnapshot.self,
            from: data
        )

        XCTAssertEqual(roundTripped, snapshot)
    }

    func testPlanResponseDecodesTodayTasks() throws {
        let data = try fixtureData("refs-plan.json")
        let response = try JSONDecoder().decode(RefsPlanResponse.self, from: data)

        XCTAssertEqual(response.schemaVersion, 2)
        XCTAssertEqual(response.todayTasks.count, 4)
        XCTAssertEqual(response.todayTasks[0].path, "ref/chat/omnigent_review_notes.md")
        XCTAssertEqual(response.todayTasks[0].blockID, "ref")
        XCTAssertEqual(response.todayTasks[0].entryName, "BLOG")
        XCTAssertEqual(response.todayTasks[3].path, "sase.md")
        XCTAssertEqual(response.todayTasks[3].blockID, "ref")
        XCTAssertEqual(response.todayTasks[3].entryName, "GTD")
    }

    func testPlanTaskWithoutBlockIDDecodesAsNil() throws {
        let task = try JSONDecoder().decode(
            RefsPlanTodayTask.self,
            from: Data("""
            {"path":"sase.md","entry_name":"GTD"}
            """.utf8)
        )

        XCTAssertEqual(task.path, "sase.md")
        XCTAssertNil(task.blockID)
        XCTAssertEqual(task.entryName, "GTD")
    }

    func testV2RowsDecodeTheirLocatedTask() throws {
        let response = try JSONDecoder().decode(
            RefsListResponse.self,
            from: fixtureData("refs-list-v2.json")
        )
        let byPath = Dictionary(uniqueKeysWithValues: response.refs.map { ($0.path, $0) })

        let live = try XCTUnwrap(byPath["ref/chat/first_essay.md"]?.task)
        XCTAssertEqual(live.path, "sase.md")
        XCTAssertEqual(live.blockID, "ref-first-essay")
        XCTAssertEqual(live.link, "[[sase#^ref-first-essay]]")
        XCTAssertEqual(live.mark, "*")
        XCTAssertFalse(live.archived)

        let archived = try XCTUnwrap(byPath["ref/papers/finished_paper.md"]?.task)
        XCTAssertEqual(archived.path, "done/sase_done.md")
        XCTAssertEqual(archived.blockID, "ref-finished-paper")
        XCTAssertTrue(archived.archived)

        let frozen = try XCTUnwrap(byPath["ref/chat/frozen_tracker.md"]?.task)
        XCTAssertEqual(frozen.path, "ref/chat/frozen_tracker.md")
        XCTAssertEqual(frozen.blockID, "ref")
        XCTAssertFalse(frozen.archived)
    }

    func testRowWithoutTaskKeyDecodesAsNilForOlderBob() throws {
        let record = try JSONDecoder().decode(
            RefRecord.self,
            from: Data("""
            {"path":"ref/chat/x.md","link":"[[ref/chat/x]]","title":"X"}
            """.utf8)
        )

        XCTAssertNil(record.task)
    }

    func testTaskRoundTripsThroughTheSnapshotCache() throws {
        let response = try JSONDecoder().decode(
            RefsListResponse.self,
            from: fixtureData("refs-list-v2.json")
        )
        let snapshot = RefsSnapshot(
            fetchedAt: Date(timeIntervalSince1970: 1_760_000_000),
            records: response.refs
        )

        let data = try RefsStoreCodecs.encoder().encode(snapshot)
        let roundTripped = try RefsStoreCodecs.decoder().decode(
            RefsSnapshot.self,
            from: data
        )

        XCTAssertEqual(roundTripped, snapshot)
    }

    func decodeGoldenList() throws -> RefsListResponse {
        try JSONDecoder().decode(
            RefsListResponse.self,
            from: fixtureData("refs-list-golden.json")
        )
    }

    func fixtureData(_ name: String) throws -> Data {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(
            contentsOf: packageRoot.appendingPathComponent("Tests/Fixtures/\(name)")
        )
    }
}
