import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRelatedModelsTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try Data(contentsOf: root.appendingPathComponent("Fixtures/capture-related/\(name)"))
    }

    func testRepresentativeBobContractDecodesAnchorsActionsAndReplacements() throws {
        let response = try JSONDecoder().decode(
            CaptureRelatedResponse.self,
            from: fixture("recapture.json")
        )

        XCTAssertTrue(response.ok)
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.items.count, 1)
        let item = try XCTUnwrap(response.items.first)
        XCTAssertEqual(item.index, 0)
        XCTAssertEqual(item.mode, "task")
        XCTAssertEqual(item.range, CaptureRange(start: 0, end: 28))
        XCTAssertEqual(item.markerAt, 28)
        XCTAssertEqual(item.routeRange, CaptureRange(start: 24, end: 28))
        XCTAssertEqual(item.matches.count, 4)

        let exact = try XCTUnwrap(item.matches.first)
        XCTAssertEqual(exact.key, "dev.md#ups")
        XCTAssertEqual(exact.band, .sameTitle)
        XCTAssertEqual(exact.matchedRanges.first, CaptureRange(start: 0, end: 7))
        XCTAssertEqual(exact.actions, [.relate, .note, .needs, .blocks, .open, .discard])
        XCTAssertEqual(exact.defaultAction, .discard)
        XCTAssertEqual(exact.replacements?.relationTo, "~dev:ups")
        XCTAssertNil(exact.closed)
    }

    func testLinkedAndClosedRowsDecodeWithNullableFields() throws {
        let linked = try JSONDecoder().decode(
            CaptureRelatedResponse.self,
            from: fixture("linked.json")
        )
        XCTAssertEqual(linked.items.first?.linked, [
            CaptureRelatedLinked(key: "dev.md#ups", link: .relation),
        ])

        let closedJSON = #"""
            {"ok":true,"schema_version":1,"items":[{"mode":"task","matches":[{
              "band":"closed_duplicate","closed":{"status":"done","date":"2026-10-19","days_ago":1},
              "title":"Retire old printer","actions":["open","discard"]}]}]}
            """#
        let closed = try JSONDecoder().decode(
            CaptureRelatedResponse.self,
            from: Data(closedJSON.utf8)
        ).items[0].matches[0]
        XCTAssertEqual(closed.closed, CaptureRelatedClosed(status: "done", date: "2026-10-19", daysAgo: 1))
        XCTAssertEqual(closed.actions, [.open, .discard])
        XCTAssertNil(closed.blockID)
        XCTAssertFalse(closed.requiresBlockID)
    }

    func testUnknownBandsActionsAndAdditiveFieldsDecodeWithoutLosingValues() throws {
        let json = #"""
            {"ok":true,"schema_version":1,"future_response_field":true,"items":[{
              "mode":"task","future_item_field":"ignored","matches":[{
                "band":"future_band","title":"A future row","future_match_field":42,
                "actions":["future_action"],"default_action":"future_default"}]}]}
            """#
        let response = try JSONDecoder().decode(
            CaptureRelatedResponse.self,
            from: Data(json.utf8)
        )
        let match = try XCTUnwrap(response.items.first?.matches.first)
        XCTAssertEqual(match.band, .unknown("future_band"))
        XCTAssertEqual(match.actions, [.unknown("future_action")])
        XCTAssertEqual(match.defaultAction, .unknown("future_default"))
        XCTAssertTrue(match.matchedRanges.isEmpty)
        XCTAssertEqual(match.title, "A future row")
    }
}
