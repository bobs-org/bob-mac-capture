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

    private func captureFailure(_ name: String) throws -> CaptureCommandFailure {
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        guard
            case .failure(let failure) = try JSONDecoder().decode(
                CaptureCommandResponse.self, from: data)
        else {
            XCTFail("expected a failed Bob response in \(name)")
            throw NSError(domain: "CaptureTransferPresentationTests", code: 1)
        }
        return failure
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

    func testTransferLandingTaskRolesAndMoveOriginsDecode() throws {
        let merge = try success("capture-transfer-merge.json")
        XCTAssertEqual(
            merge.taskBlocks.map(\.roles),
            [["merge_target"], ["merge_source"], ["merge_source"]]
        )

        let move = try success("capture-transfer-move.json")
        XCTAssertEqual(move.taskBlocks.map(\.roles), [["moved"], ["moved"]])
        XCTAssertEqual(move.taskBlocks.first?.movedFrom?.relativeTarget, "inbox.md")
        XCTAssertEqual(move.taskBlocks.first?.movedFrom?.line, 5)
    }

    func testSectionBlocksDecodeAndDropMalformedRows() throws {
        let data = try Data(
            contentsOf: fixtures.appendingPathComponent("capture-transfer-section-merge.json")
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var sections = try XCTUnwrap(object["section_blocks"] as? [Any])
        sections.append(17)
        object["section_blocks"] = sections
        let capture = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(capture.sectionBlocks.count, 1)
        let section = try XCTUnwrap(capture.sectionBlocks.first)
        XCTAssertEqual(section.relativeTarget, "db.md")
        XCTAssertEqual(section.heading, "Future Work")
        XCTAssertTrue(section.created)
        XCTAssertEqual(section.roles, ["merge_target"])
        XCTAssertEqual(section.lines.first?.text, "## Future Work")

        let insertions = CaptureLandingBlockOrdering.sectionInsertions(
            sections: capture.sectionBlocks,
            taskBlocks: capture.taskBlocks,
            merges: capture.merges
        )
        XCTAssertEqual(insertions.count, capture.taskBlocks.count + 1)
        XCTAssertEqual(insertions[0].map(\.heading), ["Future Work"])
        XCTAssertTrue(insertions[1].isEmpty)
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

    func testSectionMergeCopyNamesPathAndSectionWithoutQuotingFileName() throws {
        let section = try XCTUnwrap(
            CaptureTransferPresentation(capture: success("capture-transfer-section-merge.json"))
        )
        XCTAssertFalse(section.destination.hasTitle)
        XCTAssertEqual(
            section.statusLineText,
            "Would merge 1 task into db.md § Future Work"
        )
        XCTAssertEqual(
            section.notificationTitle,
            "Would merge 1 task into db.md § Future Work"
        )
        XCTAssertTrue(
            section.previewAccessibilitySummary.contains("into db.md § Future Work"),
            section.previewAccessibilitySummary
        )
        XCTAssertFalse(
            section.previewAccessibilitySummary.contains("“db.md”"),
            section.previewAccessibilitySummary
        )
        XCTAssertFalse(section.statusLineText.contains("“db.md”"), section.statusLineText)
    }

    func testTitledMergeCopyIsUnchanged() throws {
        let drawer = try XCTUnwrap(
            CaptureTransferPresentation(capture: success("capture-transfer-drawer-merge.json"))
        )
        XCTAssertTrue(drawer.destination.hasTitle)
        XCTAssertEqual(
            drawer.statusLineText,
            "Would merge 1 task into “Upgrade Postgres to 17” · db.md › FUTURE WORK"
        )
        XCTAssertEqual(
            drawer.notificationTitle,
            "Would merge 1 task into “Upgrade Postgres to 17”"
        )

        let task = try XCTUnwrap(
            CaptureTransferPresentation(capture: success("capture-transfer-merge.json"))
        )
        XCTAssertTrue(task.destination.hasTitle)
        XCTAssertEqual(
            task.statusLineText,
            "Would merge 2 tasks into “Always add capture time to ref marker note!” · work.md"
        )
    }

    func testMoveRenameDetailFlagFollowsBlockIDs() throws {
        let move = try XCTUnwrap(
            CaptureTransferPresentation(capture: success("capture-transfer-move.json"))
        )
        XCTAssertEqual(move.sourceRows.count, 2)
        XCTAssertFalse(move.sourceRows[0].detailIsRename)
        XCTAssertFalse(move.sourceRows[1].detailIsRename)
        XCTAssertEqual(move.sourceRows[0].detailText, "^bench")

        let data = try Data(
            contentsOf: fixtures.appendingPathComponent("capture-transfer-move.json")
        )
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var moves = try XCTUnwrap(object["moves"] as? [[String: Any]])
        moves[0]["new_block_id"] = "bench-2"
        object["moves"] = moves
        let renamed = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let renamedPresentation = try XCTUnwrap(CaptureTransferPresentation(capture: renamed))
        XCTAssertTrue(renamedPresentation.sourceRows[0].detailIsRename)
        XCTAssertEqual(renamedPresentation.sourceRows[0].detailText, "^bench → ^bench-2")
        XCTAssertFalse(renamedPresentation.sourceRows[1].detailIsRename)
    }

    func testMoveRowsOmitSameStatusTransitionText() throws {
        let move = try XCTUnwrap(
            CaptureTransferPresentation(capture: success("capture-transfer-move.json"))
        )
        XCTAssertFalse(
            move.notificationBody.contains("Ready → Ready"), move.notificationBody)
        XCTAssertFalse(
            move.notificationBody.contains("Ready to Ready"), move.notificationBody)
        XCTAssertTrue(
            move.notificationBody.contains("Benchmark logical replication"),
            move.notificationBody)
        XCTAssertFalse(
            move.previewAccessibilitySummary.contains("Ready to Ready"),
            move.previewAccessibilitySummary)
        XCTAssertFalse(
            move.previewAccessibilitySummary.contains("Ready → Ready"),
            move.previewAccessibilitySummary)

        let merge = try XCTUnwrap(
            CaptureTransferPresentation(capture: success("capture-transfer-merge.json"))
        )
        XCTAssertTrue(
            merge.notificationBody.contains("Next → Cancelled"), merge.notificationBody)
        XCTAssertTrue(
            merge.previewAccessibilitySummary.contains("Next to Cancelled"),
            merge.previewAccessibilitySummary)
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

    func testPendingFixturesDecodeResolvedAndUnresolvedSourcesAndActiveForms() throws {
        let fixtures = [
            ("capture-transfer-pending-destination.json", "transfer_destination", nil),
            ("capture-transfer-pending-block-id.json", "block_id", "@note+task"),
            ("capture-transfer-pending-drawer.json", "drawer", "@note+task#drawer"),
            ("capture-transfer-pending-section.json", "section", "@note#section"),
        ]
        for (fixture, need, activeForm) in fixtures {
            let failure = try captureFailure(fixture)
            XCTAssertTrue(failure.code?.hasPrefix("incomplete_transfer") == true)
            let pending = try XCTUnwrap(failure.transferPending)
            XCTAssertEqual(pending.need, need, fixture)
            XCTAssertEqual(pending.sources.count, 1, fixture)
            XCTAssertEqual(pending.forms.count, 4, fixture)
            XCTAssertEqual(
                pending.forms.filter(\.active).map(\.form), activeForm.map { [$0] } ?? [], fixture)
            let presentation = try XCTUnwrap(
                CaptureTransferPendingPresentation(pending: pending), fixture)
            XCTAssertEqual(
                presentation.sourceRows.first?.title?.text, "Benchmark logical replication", fixture
            )
            XCTAssertTrue(presentation.title.contains("1 task ready"), fixture)
            XCTAssertEqual(presentation.forms.count, 4, fixture)
        }

        let typo = try XCTUnwrap(
            try captureFailure("capture-transfer-pending-typo-source.json").transferPending
        )
        let typoPresentation = try XCTUnwrap(CaptureTransferPendingPresentation(pending: typo))
        XCTAssertEqual(
            typoPresentation.sourceRows.first?.errorMessage?.text, typo.sources[0].error?.message)
        XCTAssertNil(typoPresentation.sourceRows.first?.title)
        let blockForm = try XCTUnwrap(
            typoPresentation.forms.first { $0.form == "@note+task#drawer" })
        XCTAssertEqual(blockForm.segments.map(\.part), [.route, .blockID, .section])
    }

    func testTransferRefusalPresentationUsesBobMessageAndCode() throws {
        let mergeFailure = try captureFailure("capture-transfer-refusal-open-subtasks.json")
        let merge = try XCTUnwrap(
            CaptureTransferRefusalPresentation(failure: mergeFailure, parseMode: "task_merge")
        )
        XCTAssertEqual(merge.verb, .merge)
        XCTAssertEqual(merge.verb.title, "Can't merge")
        XCTAssertTrue(merge.message.text.contains("1 open subtasks"))
        XCTAssertEqual(merge.code, "merge_source_open_subtasks")

        let unknownFailure = try captureFailure("capture-transfer-refusal-extra-text.json")
        let unknown = try XCTUnwrap(
            CaptureTransferRefusalPresentation(failure: unknownFailure, parseMode: nil)
        )
        XCTAssertEqual(unknown.verb, .transfer)
        XCTAssertEqual(unknown.verb.title, "Can't transfer")
        XCTAssertEqual(unknown.code, "transfer_extra_text")
    }

    func testNonTransferResponseHasNoTransferPresentation() throws {
        let capture = try success("project-note-successors.json")
        XCTAssertNil(CaptureTransferPresentation(capture: capture))
        XCTAssertEqual(capture.mergeOffers, [])
    }
}
