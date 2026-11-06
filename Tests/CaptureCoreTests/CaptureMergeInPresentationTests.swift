import Foundation
import XCTest

@testable import CaptureCore

/// Pure presentation coverage for the merge-in band: count copy, stable
/// identity, duplicate titles, consequence de-duplication, blocked targets,
/// pending calm copy, and refusal rewrites.
final class CaptureMergeInPresentationTests: XCTestCase {
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

    private func failure(_ name: String) throws -> CaptureCommandFailure {
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        guard case .failure(let failure) = try JSONDecoder().decode(
            CaptureCommandResponse.self, from: data
        ) else {
            XCTFail("expected a failed Bob response in \(name)")
            throw NSError(domain: "CaptureMergeInPresentationTests", code: 1)
        }
        return failure
    }

    func testSingleSourceSingularCopy() throws {
        let presentation = try XCTUnwrap(
            CaptureMergeInPresentation(capture: success("capture-merge-in-complete-one.json"))
        )
        XCTAssertEqual(presentation.count, 1)
        XCTAssertEqual(presentation.headerText, "⤵ Merging in 1 task")
        XCTAssertEqual(presentation.primaryActionTitle, "Capture & merge 1 task")
        XCTAssertEqual(
            presentation.statusLineText,
            "Would create “New outcome” and merge 1 task into it · mac_inbox.md"
        )
        XCTAssertEqual(
            presentation.notificationTitle,
            "Created “New outcome” · merged 1 task"
        )
        XCTAssertTrue(presentation.notificationBody.contains("Bare source"))
        XCTAssertTrue(presentation.notificationBody.contains("Ready → Cancelled"))
        XCTAssertTrue(presentation.notificationBody.contains("title only"))
        XCTAssertNil(presentation.disclosureLabel)
    }

    func testTwoAndFiveSourcePluralCopyAndDisclosure() throws {
        let two = try XCTUnwrap(
            CaptureMergeInPresentation(capture: success("capture-merge-in-complete-two.json"))
        )
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two.headerText, "⤵ Merging in 2 tasks")
        XCTAssertEqual(two.primaryActionTitle, "Capture & merge 2 tasks")
        XCTAssertNil(two.disclosureLabel)

        let five = try XCTUnwrap(
            CaptureMergeInPresentation(capture: success("capture-merge-in-complete-five.json"))
        )
        XCTAssertEqual(five.count, 5)
        XCTAssertEqual(five.headerText, "⤵ Merging in 5 tasks")
        XCTAssertEqual(five.disclosureLabel, "Show all 5")
        XCTAssertEqual(five.sourceRows.count, 5)
    }

    func testStableIdentityKeepsDuplicateTitlesDistinct() throws {
        let presentation = try XCTUnwrap(
            CaptureMergeInPresentation(
                capture: success("capture-merge-in-complete-duplicate-titles.json")
            )
        )
        XCTAssertEqual(presentation.count, 2)
        XCTAssertEqual(presentation.sourceRows[0].title.text, "Repeated title")
        XCTAssertEqual(presentation.sourceRows[1].title.text, "Repeated title")
        XCTAssertNotEqual(presentation.sourceRows[0].stableID, presentation.sourceRows[1].stableID)
        XCTAssertTrue(presentation.sourceRows[0].stableID.contains("rep1"))
        XCTAssertTrue(presentation.sourceRows[1].stableID.contains("rep2"))
    }

    func testConsequencesDeduplicateByKindAndKeys() throws {
        let base = try success("capture-merge-in-complete-two.json")
        let presentation = try XCTUnwrap(CaptureMergeInPresentation(capture: base))
        let kinds = presentation.consequences.map(\.kind)
        XCTAssertTrue(kinds.contains("dependent"))
        XCTAssertTrue(kinds.contains("link_pruned"))
        XCTAssertEqual(
            presentation.consequences.filter { $0.kind == "dependent" }.count, 1
        )

        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: JSONEncoder().encode(base)
            ) as? [String: Any]
        )
        var merges = try XCTUnwrap(object["merges"] as? [[String: Any]])
        var first = merges[0]
        var consequences = try XCTUnwrap(first["consequences"] as? [[String: Any]])
        consequences.append(try XCTUnwrap(consequences.first))
        first["consequences"] = consequences
        merges[0] = first
        object["merges"] = merges
        let doubled = try JSONDecoder().decode(
            CaptureCommandSuccess.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let deduped = try XCTUnwrap(CaptureMergeInPresentation(capture: doubled))
        XCTAssertEqual(deduped.consequences.count, presentation.consequences.count)
    }

    func testBlockedTargetKeepsBandAndStatus() throws {
        let presentation = try XCTUnwrap(
            CaptureMergeInPresentation(
                capture: success("capture-merge-in-complete-blocked-target.json")
            )
        )
        XCTAssertEqual(presentation.count, 1)
        XCTAssertEqual(presentation.destination.statusName, "Blocked")
        XCTAssertTrue(presentation.statusLineText.contains("New target"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("Blocked"))
    }

    func testTransferKindNeverBuildsMergeInBand() throws {
        let transfer = try success("capture-transfer-merge.json")
        XCTAssertNil(CaptureMergeInPresentation(capture: transfer))
    }

    func testPendingShowsPromptAndResolvedSourcesWithoutSubmit() throws {
        let pending = try XCTUnwrap(
            failure("capture-merge-in-pending-second.json").mergeInPending
        )
        let presentation = try XCTUnwrap(
            CaptureMergeInPendingPresentation(pending: pending)
        )
        XCTAssertFalse(presentation.canSubmit)
        XCTAssertEqual(presentation.sourceRows.count, 1)
        XCTAssertEqual(presentation.sourceRows[0].title?.text, "Alpha task")
        XCTAssertTrue(presentation.accessibilitySummary.contains("type + to pick"))
    }

    func testPendingSourceErrorStaysVisible() throws {
        let pending = try XCTUnwrap(
            failure("capture-merge-in-pending-error.json").mergeInPending
        )
        let presentation = try XCTUnwrap(
            CaptureMergeInPendingPresentation(pending: pending)
        )
        XCTAssertEqual(presentation.sourceRows.count, 1)
        XCTAssertNotNil(presentation.sourceRows[0].errorMessage)
    }

    func testRefusalKeepsBobMessageAndRewriteButtons() throws {
        let parseData = try Data(
            contentsOf: fixtures.appendingPathComponent(
                "capture-merge-in-parse-rewrite-spacing.json"
            )
        )
        let parse = try JSONDecoder().decode(CaptureParseResponse.self, from: parseData)
        let rewrites = parse.diagnostics.compactMap(\.rewrite)
        XCTAssertEqual(rewrites.count, 1)

        let refusal = try XCTUnwrap(
            CaptureMergeInRefusalPresentation(
                failure: failure("capture-merge-in-refusal-duplicate.json"),
                rewrites: rewrites
            )
        )
        XCTAssertTrue(refusal.message.text.contains("twice on this line"))
        XCTAssertEqual(refusal.rewrites.count, 1)
        XCTAssertEqual(refusal.rewrites[0].label, "Add spaces")
    }
}
