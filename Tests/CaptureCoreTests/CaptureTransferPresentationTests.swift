import Foundation
import XCTest

@testable import CaptureCore

/// Tests the unified transfer card model against generated Bob responses.
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

    func testScreenshotMergeFixtureBuildsDraftOrderedCardRows() throws {
        let capture = try success("capture-transfer-merge.json")
        let presentation = try XCTUnwrap(CaptureTransferPresentation(capture: capture))

        XCTAssertEqual(capture.kind, "task_merge")
        XCTAssertEqual(presentation.verb, .merge)
        XCTAssertEqual(presentation.state, .planned)
        XCTAssertEqual(presentation.sourceRows.count, 2)
        XCTAssertEqual(presentation.sourceRows[0].title.text, "Add =<ch> jumper keymaps (see org)!")
        XCTAssertEqual(presentation.sourceRows[0].title.segments.map(\.kind), [.plain, .code, .plain, .link, .plain])
        XCTAssertEqual(presentation.sourceRows[0].statusName, "Next")
        XCTAssertEqual(presentation.sourceRows[0].targetStatusName, "Cancelled")
        XCTAssertEqual(presentation.sourceRows[0].locator, "work.md:5")
        XCTAssertEqual(presentation.sourceRows[0].detailText, "title only")
        XCTAssertEqual(presentation.destination.title.text, "Always add capture time to ref marker note!")
        XCTAssertEqual(presentation.destination.statusName, "Ready")
        XCTAssertEqual(presentation.destination.locator, "work.md:9")
        XCTAssertEqual(
            presentation.statusLineText,
            "Would merge 2 tasks into “Always add capture time to ref marker note!” · work.md"
        )
        XCTAssertEqual(presentation.primaryActionTitle, "Merge")
    }

    func testEnrichedMergeFixtureShowsBobConsequencesAndHandoffOffers() throws {
        let capture = try success("capture-transfer-consequences-offers.json")
        let presentation = try XCTUnwrap(CaptureTransferPresentation(capture: capture))

        let kinds = presentation.consequences.map(\.kind)
        XCTAssertTrue(kinds.contains("dependent"))
        XCTAssertTrue(kinds.contains("prerequisite_left"))
        XCTAssertTrue(kinds.contains("successor_orphaned"))
        XCTAssertEqual(kinds.filter { $0 == "link_pruned" }.count, 2)
        let dependent = try XCTUnwrap(presentation.consequences.first { $0.kind == "dependent" })
        let prerequisite = try XCTUnwrap(
            presentation.consequences.first { $0.kind == "prerequisite_left" }
        )
        let linkPruned = try XCTUnwrap(presentation.consequences.first { $0.kind == "link_pruned" })
        XCTAssertTrue(dependent.text.contains("Cut over prod"))
        XCTAssertTrue(prerequisite.text.contains("Prepare test environment"))
        XCTAssertEqual(dependent.symbol, "link")
        XCTAssertEqual(prerequisite.symbol, "exclamationmark.triangle")
        XCTAssertEqual(linkPruned.symbol, "minus.circle")
        XCTAssertEqual(capture.mergeOffers.count, 1)
        XCTAssertTrue(capture.mergeOffers.allSatisfy { $0.trigger == "merge" })
        XCTAssertTrue(capture.mergeOffers.allSatisfy { $0.offer?.mergedFrom != nil })
        XCTAssertEqual(capture.allRelationSuccessors.count, 1)
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("Pull-In offers"))
    }

    func testMoveFixtureShowsStatusDestinationSectionAndRepairs() throws {
        let capture = try success("capture-transfer-move.json")
        let presentation = try XCTUnwrap(CaptureTransferPresentation(capture: capture))

        XCTAssertEqual(presentation.verb, .move)
        XCTAssertEqual(presentation.sourceRows.count, 2)
        XCTAssertEqual(presentation.sourceRows[0].title.text, "Benchmark logical replication")
        XCTAssertEqual(presentation.sourceRows[0].statusName, "Ready")
        XCTAssertEqual(presentation.sourceRows[0].targetStatusName, "Ready")
        XCTAssertEqual(presentation.sourceRows[0].detailText, "^bench")
        XCTAssertEqual(presentation.destination.title.text, "db.md")
        XCTAssertEqual(presentation.destination.containerLabel, "› Tasks")
        XCTAssertEqual(
            presentation.statusLineText,
            "Would move 2 tasks into db.md › Tasks"
        )
        XCTAssertEqual(presentation.repairText, "1 link repaired in 1 note")
        XCTAssertEqual(presentation.primaryActionTitle, "Move")
    }

    func testDrawerAndSectionDestinationsCarryCreatedState() throws {
        let drawer = try XCTUnwrap(
            CaptureTransferPresentation(capture: success("capture-transfer-drawer-merge.json"))
        )
        XCTAssertEqual(drawer.destination.containerLabel, "› FUTURE WORK")
        XCTAssertTrue(drawer.destination.isNew)

        let section = try XCTUnwrap(
            CaptureTransferPresentation(capture: success("capture-transfer-section-merge.json"))
        )
        XCTAssertEqual(section.destination.containerLabel, "§ Future Work")
        XCTAssertTrue(section.destination.isNew)
    }

    func testUnchangedMergeUsesMutedAlreadyMergedState() throws {
        let presentation = try XCTUnwrap(
            CaptureTransferPresentation(capture: success("capture-transfer-unchanged-merge.json"))
        )
        XCTAssertEqual(presentation.state, .alreadyMerged)
        XCTAssertEqual(presentation.alreadyMergedText, "Already merged into “Upgrade Postgres to 17”")
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("Nothing to write"))
    }

    func testOlderBobUsesStyledMessageAndOmitsMissingConsequences() throws {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("capture-transfer-merge.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var merges = try XCTUnwrap(object["merges"] as? [[String: Any]])
        for index in merges.indices {
            merges[index].removeValue(forKey: "previous_status_name")
            merges[index].removeValue(forKey: "status_symbol")
            merges[index].removeValue(forKey: "status_name")
            merges[index].removeValue(forKey: "consequences")
            merges[index]["message"] = "⊘ `=<ch>` jumper keymaps (see [[org]]) · Ready → Cancelled"
            var target = try XCTUnwrap(merges[index]["target"] as? [String: Any])
            target.removeValue(forKey: "line")
            target.removeValue(forKey: "created")
            target.removeValue(forKey: "status_symbol")
            target.removeValue(forKey: "status_name")
            merges[index]["target"] = target
        }
        object["merges"] = merges
        let older = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let presentation = try XCTUnwrap(CaptureTransferPresentation(capture: older))

        XCTAssertTrue(presentation.sourceRows[0].fallback)
        XCTAssertNil(presentation.sourceRows[0].status)
        XCTAssertEqual(presentation.sourceRows[0].title.text, "⊘ =<ch> jumper keymaps (see org) · Ready → Cancelled")
        XCTAssertTrue(presentation.consequences.isEmpty)
    }

    func testMalformedMergeOfferRowsAreDroppedIndividually() throws {
        let data = try Data(contentsOf: fixtures.appendingPathComponent("capture-transfer-consequences-offers.json"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var offers = try XCTUnwrap(object["merge_offers"] as? [Any])
        offers.append(17)
        object["merge_offers"] = offers
        let capture = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertEqual(capture.mergeOffers.count, 1)
    }

    func testRecordedBobTransferSpansUseRouteAndVerbStyles() throws {
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
                captureSemanticCategory(
                    forSpan: try XCTUnwrap(spans["transfer_arrow"]),
                    mode: mode
                ),
                mode == "task_move" ? .route : .section
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

    func testNonTransferResponseHasNoTransferPresentation() throws {
        let capture = try success("project-note-successors.json")
        XCTAssertNil(CaptureTransferPresentation(capture: capture))
        XCTAssertEqual(capture.mergeOffers, [])
    }
}
