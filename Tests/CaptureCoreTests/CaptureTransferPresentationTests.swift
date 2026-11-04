import Foundation
import XCTest

@testable import CaptureCore

/// Tests for capture `>` transfer presentation from recorded Bob responses.
final class CaptureTransferPresentationTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func success(_ name: String) throws -> CaptureCommandSuccess {
        try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: Data(contentsOf: fixtures.appendingPathComponent(name))
        )
    }

    private func parse(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(contentsOf: fixtures.appendingPathComponent(name))
        )
    }

    func testMoveFixtureBuildsMovesBandAndRepairCopy() throws {
        let capture = try success("capture-transfer-move.json")
        XCTAssertEqual(capture.kind, "task_move")
        XCTAssertEqual(capture.moves.count, 1)
        XCTAssertEqual(capture.moves[0].sourcePath, "inbox.md")
        XCTAssertEqual(capture.moves[0].destinationPath, "db.md")
        XCTAssertEqual(capture.moves[0].title, "Benchmark logical replication")
        XCTAssertEqual(capture.repairedFiles.first?.linkCount, 1)

        let presentation = try XCTUnwrap(CaptureTransferMovePresentation(capture: capture))
        XCTAssertEqual(presentation.headerText, "↪ Moves 1 task into db.md")
        XCTAssertTrue(presentation.rows[0].text.contains("inbox.md:5 → db.md"))
        XCTAssertTrue(presentation.rows[0].text.contains("Benchmark logical replication"))
        XCTAssertEqual(presentation.repairFooterText, "1 link repaired in 1 note")
        XCTAssertEqual(presentation.primaryActionTitle, "Move")
        XCTAssertEqual(presentation.notificationTitle, "Would move 1 task into db.md")
        XCTAssertTrue(
            presentation.previewAccessibilitySummary.contains("Benchmark logical replication")
        )
    }

    func testMergeFixtureBuildsMergesBandFromBobConsequence() throws {
        let capture = try success("capture-transfer-merge.json")
        XCTAssertEqual(capture.kind, "task_merge")
        XCTAssertEqual(capture.moves, [])
        XCTAssertEqual(capture.merges.count, 1)
        XCTAssertEqual(capture.merges[0].source.title, "Benchmark logical replication")
        XCTAssertEqual(capture.merges[0].target.title, "Upgrade Postgres")
        XCTAssertEqual(capture.merges[0].outcome, "merged")

        let presentation = try XCTUnwrap(CaptureTransferMergePresentation(capture: capture))
        XCTAssertEqual(presentation.targetLabel, "Upgrade Postgres")
        XCTAssertEqual(presentation.headerText, "⤵ Merges 1 task into Upgrade Postgres")
        XCTAssertEqual(
            presentation.rows[0].text,
            "⊘ Benchmark logical replication  inbox.md:5 · Unknown → Cancelled · 1 notes moved"
        )
        XCTAssertEqual(presentation.primaryActionTitle, "Merge")
        XCTAssertEqual(
            presentation.notificationTitle,
            "Would merge 1 task into Upgrade Postgres"
        )
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("Unknown → Cancelled"))
    }

    func testRecordedBobTransferSpansUseRouteAndArrowStyles() throws {
        let examples = [
            ("capture-parse-transfer-move.json", "task_move"),
            ("capture-parse-transfer-merge.json", "task_merge"),
        ]
        for (fixture, mode) in examples {
            let response = try parse(fixture)
            XCTAssertEqual(response.mode, mode)
            let spans = Dictionary(uniqueKeysWithValues: response.spans.map { ($0.kind, $0) })
            XCTAssertEqual(
                captureSemanticCategory(forSpan: try XCTUnwrap(spans["transfer_source"])),
                .route
            )
            XCTAssertEqual(
                captureSemanticCategory(forSpan: try XCTUnwrap(spans["transfer_arrow"])),
                .interactivePlaceholder
            )
            XCTAssertEqual(
                captureSemanticCategory(forSpan: try XCTUnwrap(spans["transfer_destination"])),
                .route
            )
        }
    }

    func testIncompleteTransferDestinationRequestsCompletion() throws {
        let response = try parse("capture-parse-transfer-incomplete.json")
        XCTAssertEqual(response.mode, "incomplete")
        XCTAssertTrue(response.needs.contains("transfer_destination"))
        let destination = try XCTUnwrap(response.spans.first { $0.kind == "transfer_destination" })
        XCTAssertEqual(captureSemanticCategory(forSpan: destination), .route)
    }

    func testOlderBobResponseDefaultsTransferFieldsToEmpty() throws {
        let capture = try success("project-note-successors.json")
        XCTAssertEqual(capture.moves, [])
        XCTAssertEqual(capture.merges, [])
        XCTAssertEqual(capture.repairedFiles, [])
        XCTAssertNil(CaptureTransferMovePresentation(capture: capture))
        XCTAssertNil(CaptureTransferMergePresentation(capture: capture))
    }
}
