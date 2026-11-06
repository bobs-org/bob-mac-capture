import Foundation
import XCTest

@testable import CaptureCore

/// Portable decoding coverage for Bob's `<` merge-in wire contract.
///
/// Fixtures come from `Scripts/generate-merge-in-preview-fixtures.sh`
/// (deterministic synthetic vaults, fixed clock, stable paths, recorded
/// CLI commit in `capture-merge-in-manifest.json`). Tests prove additive
/// compatibility, malformed-row recovery, target `created`, origin
/// preservation, rewrite byte ranges, and pending source errors without
/// touching transfer contracts.
final class CaptureMergeInDecodingTests: XCTestCase {
    private var fixtures: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func data(_ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appendingPathComponent(name))
    }

    private func parse(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(CaptureParseResponse.self, from: data(name))
    }

    private func success(_ name: String) throws -> CaptureCommandSuccess {
        try JSONDecoder().decode(CaptureCommandSuccess.self, from: data(name))
    }

    private func failure(_ name: String) throws -> CaptureCommandFailure {
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data(name))
        guard case .failure(let failure) = response else {
            XCTFail("expected a failed Bob response in \(name)")
            throw NSError(domain: "CaptureMergeInDecodingTests", code: 1)
        }
        return failure
    }

    // MARK: - Parse contract

    func testCompleteOneDecodesArrowSourceOrderAndOffsets() throws {
        let response = try parse("capture-merge-in-parse-one.json")
        XCTAssertEqual(response.grammar, 15)
        XCTAssertEqual(response.mode, "task")
        let mergeIn = try XCTUnwrap(response.mergeIn)
        XCTAssertEqual(mergeIn.arrow, CaptureMergeInArrow(start: 12, end: 13))
        XCTAssertEqual(
            mergeIn.sources,
            [
                CaptureMergeInSource(
                    start: 14, end: 24, marker: "@inbox+aaa", route: "inbox", blockID: "aaa"
                )
            ]
        )
        XCTAssertEqual(response.spans.map(\.kind), ["merge_in_arrow", "merge_in_source"])
    }

    func testCompleteTwoAndFivePreserveSourceOrder() throws {
        let two = try parse("capture-merge-in-parse-two.json")
        XCTAssertEqual(two.mergeIn?.sources.map(\.marker), ["@inbox+aaa", "@inbox+bbb"])
        XCTAssertEqual(two.mergeIn?.sources.map(\.blockID), ["aaa", "bbb"])

        let five = try parse("capture-merge-in-parse-five.json")
        XCTAssertEqual(five.mergeIn?.sources.count, 5)
        XCTAssertEqual(
            five.mergeIn?.sources.map(\.marker),
            ["@inbox+aaa", "@inbox+bbb", "@inbox+ccc", "@inbox+ddd", "@inbox+eee"]
        )
        XCTAssertTrue(five.mergeIn?.sources.allSatisfy { $0.route == "inbox" } ?? false)
    }

    func testPendingClausesKeepTaskModeWithMergeInNeed() throws {
        for name in [
            "capture-merge-in-parse-pending-terminal.json",
            "capture-merge-in-parse-pending-second.json",
            "capture-merge-in-parse-pending-plus.json",
        ] {
            let response = try parse(name)
            XCTAssertEqual(response.mode, "task", name)
            XCTAssertTrue(response.needs.contains("merge_in_source"), name)
            XCTAssertNotNil(response.mergeIn, name)
            XCTAssertTrue(response.diagnostics.isEmpty, name)
        }

        let terminal = try parse("capture-merge-in-parse-pending-terminal.json")
        XCTAssertEqual(terminal.mergeIn?.sources, [])
        XCTAssertTrue(terminal.spans.contains { $0.kind == "interactive_placeholder" })

        let second = try parse("capture-merge-in-parse-pending-second.json")
        XCTAssertEqual(second.mergeIn?.sources.map(\.marker), ["@inbox+aaa"])
    }

    func testBulkItemsCarryPerItemMergeIn() throws {
        let response = try parse("capture-merge-in-parse-bulk-mixed.json")
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.items[0].mergeIn?.sources.map(\.marker), ["@inbox+aaa"])
        XCTAssertNil(response.items[1].mergeIn)
        XCTAssertEqual(response.mergeIn?.sources.map(\.marker), ["@inbox+aaa"])
    }

    func testUnicodeOffsetsAreUTF8Bytes() throws {
        let response = try parse("capture-merge-in-parse-unicode.json")
        // "Tâche ünïcodé café " is 24 UTF-8 bytes, so the arrow sits at 24..<25.
        XCTAssertEqual(response.mergeIn?.arrow, CaptureMergeInArrow(start: 24, end: 25))
        XCTAssertEqual(response.mergeIn?.sources.first?.marker, "@inbox+aaa")
        XCTAssertEqual(response.spans.map(\.kind), ["merge_in_arrow", "merge_in_source"])
    }

    // MARK: - Diagnostic rewrites

    func testRewriteDiagnosticsCarryExactByteRanges() throws {
        let spacing = try parse("capture-merge-in-parse-rewrite-spacing.json")
        let spacingRewrite = try XCTUnwrap(
            spacing.diagnostics.first { $0.code == "merge_in_arrow_spacing" }?.rewrite
        )
        XCTAssertEqual(spacingRewrite.start, 0)
        XCTAssertEqual(spacingRewrite.end, 15)
        XCTAssertEqual(spacingRewrite.replacement, "text < @inbox+aaa")
        XCTAssertEqual(spacingRewrite.label, "Add spaces")

        let extra = try parse("capture-merge-in-parse-rewrite-extra.json")
        let extraRewrite = try XCTUnwrap(
            extra.diagnostics.first { $0.code == "merge_in_extra_text" }?.rewrite
        )
        XCTAssertEqual(extraRewrite.label, "Move before <")
        XCTAssertEqual(extraRewrite.start, 0)
        XCTAssertFalse(extraRewrite.replacement.isEmpty)

        let needsTask = try parse("capture-merge-in-parse-rewrite-needs-new-task.json")
        let needsTaskRewrite = try XCTUnwrap(
            needsTask.diagnostics.first { $0.code == "merge_in_needs_new_task" }?.rewrite
        )
        XCTAssertEqual(needsTaskRewrite.label, "Use >")
        XCTAssertEqual(needsTaskRewrite.replacement, "@inbox+bbb > @inbox+aaa")
        XCTAssertEqual(needsTaskRewrite.start, 0)
        XCTAssertEqual(needsTaskRewrite.end, 23)
    }

    func testDuplicateParseDiagnosticHasNoMergeIn() throws {
        let response = try parse("capture-merge-in-parse-refusal-duplicate.json")
        XCTAssertTrue(response.diagnostics.contains { $0.code == "duplicate_capture_target" })
        XCTAssertNil(response.mergeIn)
    }

    // MARK: - Execution contract

    func testCompleteMergesReuseTransferDescriptorAndMarkCreated() throws {
        let one = try success("capture-merge-in-complete-one.json")
        XCTAssertEqual(one.kind, "task")
        XCTAssertEqual(one.merges.count, 1)
        let merge = try XCTUnwrap(one.merges.first)
        XCTAssertEqual(merge.source.title, "Bare source")
        XCTAssertEqual(merge.target.created, true)
        XCTAssertTrue(merge.message.hasSuffix("title only"))

        let two = try success("capture-merge-in-complete-two.json")
        XCTAssertEqual(two.merges.count, 2)
        XCTAssertTrue(two.merges.allSatisfy { $0.target.created == true })
        XCTAssertTrue(two.merges.allSatisfy { $0.target.line != nil && $0.target.line! > 0 })

        let five = try success("capture-merge-in-complete-five.json")
        XCTAssertEqual(five.merges.count, 5)
    }

    func testDuplicateLongUnicodeAndTitleOnlySourcesDecode() throws {
        let dup = try success("capture-merge-in-complete-duplicate-titles.json")
        XCTAssertEqual(dup.merges.map(\.source.title), ["Repeated title", "Repeated title"])
        XCTAssertNotEqual(dup.merges[0].source.blockID, dup.merges[1].source.blockID)

        let long = try success("capture-merge-in-complete-long-title.json")
        XCTAssertGreaterThan(long.merges[0].source.title?.count ?? 0, 100)

        let unicode = try success("capture-merge-in-complete-unicode.json")
        XCTAssertTrue(unicode.merges[0].source.title?.contains("Tâche ünïcodé") ?? false)

        let titleOnly = try success("capture-merge-in-complete-title-only.json")
        XCTAssertTrue(titleOnly.merges[0].message.hasSuffix("title only"))
    }

    func testDependentConsequencesAndOffersDecode() throws {
        let two = try success("capture-merge-in-complete-two.json")
        XCTAssertTrue(two.merges.contains { !$0.consequences.isEmpty })
        XCTAssertFalse(two.mergeOffers.isEmpty)
        XCTAssertTrue(two.mergeOffers.allSatisfy { $0.trigger == "merge" })
    }

    func testBlockedTargetSuppressesOffers() throws {
        let blocked = try success("capture-merge-in-complete-blocked-target.json")
        XCTAssertEqual(blocked.kind, "task")
        XCTAssertFalse(blocked.merges.isEmpty)
        XCTAssertTrue(blocked.mergeOffers.isEmpty)
    }

    func testTaskListBulkWritesEachTarget() throws {
        let list = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: data("capture-merge-in-complete-task-list.json")
        )
        guard case .success(let capture) = list else {
            XCTFail("expected bulk success")
            return
        }
        XCTAssertEqual(capture.captures.count, 2)
        XCTAssertTrue(capture.captures.allSatisfy { $0.kind == "task" })
    }

    func testOriginsArePreservedForBothArrows() throws {
        let mergeIn = try success("capture-merge-in-complete-one.json")
        let mergeInOrigins = mergeIn.taskBlocks.flatMap(\.lines).compactMap(\.origin)
        XCTAssertEqual(mergeInOrigins, ["inbox.md#^bare"])

        let two = try success("capture-merge-in-complete-two.json")
        let twoOrigins = Set(two.taskBlocks.flatMap(\.lines).compactMap(\.origin))
        XCTAssertEqual(twoOrigins, ["inbox.md#^aaa", "inbox.md#^bbb"])

        let transfer = try success("capture-merge-in-transfer-origin.json")
        let transferOrigins = Set(transfer.taskBlocks.flatMap(\.lines).compactMap(\.origin))
        XCTAssertEqual(transferOrigins, ["inbox.md#^bbb"])
    }

    func testTaskBlockRolesMarkMergeTargetAndSource() throws {
        let one = try success("capture-merge-in-complete-one.json")
        let roles = one.taskBlocks.map(\.roles)
        XCTAssertTrue(roles.contains(["merge_target"]))
        XCTAssertTrue(roles.contains(["merge_source"]))
    }

    // MARK: - Pending and refusals

    func testPendingSecondSourceReportsMergeableRow() throws {
        let failure = try failure("capture-merge-in-pending-second.json")
        XCTAssertEqual(failure.code, "incomplete_merge_in")
        let pending = try XCTUnwrap(failure.mergeInPending)
        XCTAssertEqual(pending.item, 1)
        XCTAssertEqual(pending.need, "merge_in_source")
        XCTAssertEqual(pending.sources.count, 1)
        let source = try XCTUnwrap(pending.sources.first)
        XCTAssertEqual(source.marker, "@inbox+aaa")
        XCTAssertEqual(source.path, "inbox.md")
        XCTAssertEqual(source.mergeable, true)
        XCTAssertNil(source.error)
        XCTAssertNil(failure.transferPending)
    }

    func testPendingErrorRowCarriesSourceError() throws {
        let failure = try failure("capture-merge-in-pending-error.json")
        let source = try XCTUnwrap(failure.mergeInPending?.sources.first)
        XCTAssertFalse(source.marker.isEmpty)
        XCTAssertNotNil(source.error)
        XCTAssertFalse(source.error?.code.isEmpty ?? true)
        XCTAssertFalse(source.error?.message.isEmpty ?? true)
    }

    func testPendingUnmergeableRowCarriesClosedCode() throws {
        let failure = try failure("capture-merge-in-pending-unmergeable.json")
        let source = try XCTUnwrap(failure.mergeInPending?.sources.first)
        XCTAssertEqual(source.mergeable, false)
        XCTAssertEqual(source.mergeableCode, "merge_source_closed")
        XCTAssertFalse(source.mergeableMessage?.isEmpty ?? true)
    }

    func testRefusalsCarryCodesWithoutPending() throws {
        let duplicate = try failure("capture-merge-in-refusal-duplicate.json")
        XCTAssertEqual(duplicate.code, "duplicate_capture_target")
        XCTAssertNil(duplicate.mergeInPending)

        let missing = try failure("capture-merge-in-refusal-missing.json")
        XCTAssertEqual(missing.code, "task_not_found")
        XCTAssertNil(missing.mergeInPending)

        let alsoMarked = try failure("capture-merge-in-refusal-also-marked.json")
        XCTAssertEqual(alsoMarked.code, "merge_in_source_also_marked")
        XCTAssertNil(alsoMarked.mergeInPending)
    }

    // MARK: - Related and completion

    func testRelatedMarksMergeInSourcesAsLinked() throws {
        let response = try JSONDecoder().decode(
            CaptureRelatedResponse.self,
            from: data("capture-merge-in-related.json")
        )
        XCTAssertEqual(response.items.count, 1)
        XCTAssertEqual(
            response.items.first?.linked,
            [CaptureRelatedLinked(key: "inbox.md#aaa", link: .mergeIn)]
        )
        XCTAssertEqual(response.items.first?.matches, [])
    }

    func testCompletionSlotDecodesMergeInDetail() throws {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: data("capture-merge-in-complete-slot.json")
        )
        XCTAssertEqual(response.context, "task_parent")
        XCTAssertTrue(
            response.candidates.contains { ($0.detail ?? "").contains("merge in") }
        )
    }

    // MARK: - Additive compatibility and malformed recovery

    func testMissingMergeInKeysDecodeAsNil() throws {
        let oldParse = Data(
            """
            {"ok":true,"schema_version":1,"grammar":5,"input":"hi","body":"hi",
             "mode":"task","needs":[],"spans":[],"diagnostics":[]}
            """.utf8
        )
        let response = try JSONDecoder().decode(CaptureParseResponse.self, from: oldParse)
        XCTAssertNil(response.mergeIn)
        XCTAssertTrue(response.diagnostics.isEmpty)

        let oldFailure = Data(
            """
            {"ok":false,"error":"nope","code":"incomplete_merge_in"}
            """.utf8
        )
        let failure = try JSONDecoder().decode(CaptureCommandFailure.self, from: oldFailure)
        XCTAssertNil(failure.mergeInPending)
        XCTAssertNil(failure.transferPending)

        let oldLine = Data(
            """
            {"text":"- [ ] #task hi","depth":0,"change":"added"}
            """.utf8
        )
        let line = try JSONDecoder().decode(CapturePomodoroBlockLine.self, from: oldLine)
        XCTAssertNil(line.origin)
        XCTAssertNil(line.reason)
    }

    func testMalformedAdditiveMetadataDegradesGracefully() throws {
        let badRewrite = Data(
            """
            {"severity":"error","code":"merge_in_extra_text","message":"m",
             "range":[0,1],"rewrite":{"start":"bad","end":null}}
            """.utf8
        )
        let diagnostic = try JSONDecoder().decode(CaptureDiagnostic.self, from: badRewrite)
        XCTAssertEqual(diagnostic.code, "merge_in_extra_text")
        XCTAssertEqual(diagnostic.rewrite, CaptureDiagnosticRewrite())

        let badPending = Data(
            """
            {"ok":false,"error":"pick","code":"incomplete_merge_in",
             "merge_in_pending":{"item":1,"need":"merge_in_source",
              "sources":[{"marker":42},17]}}
            """.utf8
        )
        let failure = try JSONDecoder().decode(CaptureCommandFailure.self, from: badPending)
        // The malformed source row drops out; the envelope itself survives.
        XCTAssertEqual(failure.mergeInPending?.item, 1)
        XCTAssertEqual(failure.mergeInPending?.sources.count, 1)
        XCTAssertEqual(failure.mergeInPending?.sources.first?.marker, "")

        let badMergeIn = Data(
            """
            {"ok":true,"schema_version":1,"grammar":15,"input":"hi","body":"hi",
             "mode":"task","needs":[],"spans":[],"diagnostics":[],
             "merge_in":{"arrow":{"start":"bad"},"sources":[[1]]}}
            """.utf8
        )
        let parse = try JSONDecoder().decode(CaptureParseResponse.self, from: badMergeIn)
        XCTAssertEqual(parse.mergeIn?.arrow, CaptureMergeInArrow())
        XCTAssertEqual(parse.mergeIn?.sources, [])
    }

    func testUnknownRelatedLinkKindSurvives() throws {
        let response = try JSONDecoder().decode(
            CaptureRelatedResponse.self,
            from: Data(
                """
                {"ok":true,"schema_version":1,"items":[
                  {"mode":"task","linked":[{"key":"a.md#x","link":"future_kind"}]}]}
                """.utf8
            )
        )
        XCTAssertEqual(
            response.items.first?.linked.first?.link,
            .unknown("future_kind")
        )
    }
}
