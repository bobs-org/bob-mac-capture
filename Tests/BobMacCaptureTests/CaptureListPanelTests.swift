import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Lists under a lone `@file` header, as the panel wires them: accepting a
/// block-ID prompt through Bob's splice, the owner caption, the quiet lone
/// header state, and the newline that starts the first bullet. Fixtures are raw
/// Bob replies from `Scripts/generate-list-fixtures.sh`.
@MainActor
final class CaptureListPanelTests: XCTestCase {
    private let nestedDraft = "@dev\n- Fix flaky gkeep test\n  - repro on CI first :"
    private let nestedAccepted =
        "@dev\n- Fix flaky gkeep test :fix-flaky-gkeep\n  - repro on CI first"

    private func fixtureData(_ name: String) throws -> Data {
        try Data(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent(name))
    }

    private func field(_ name: String) throws -> CaptureBlockIDField {
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: fixtureData(name)
        )
        return try XCTUnwrap(response.blockID)
    }

    private func parse(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(CaptureParseResponse.self, from: fixtureData(name))
    }

    private func installPrompt(
        _ name: String,
        draft: String,
        caret: Int,
        markerLine: Int,
        filter: String = ""
    ) throws -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installBlockIDPickerForPreviews(
            field: try field(name),
            candidates: [],
            context: "project_task_block_id",
            replacement: CaptureRange(start: caret, end: caret),
            filter: filter,
            draft: draft,
            scopeLineNumber: markerLine
        )
        return model
    }

    // MARK: - Accept with the splice

    func testNestedAcceptWritesTheIDOntoTheOwnerLineAndKeepsTheCaretWhereTyping() throws {
        let model = try installPrompt(
            "list-complete-nested.json",
            draft: nestedDraft,
            caret: 51,
            markerLine: 3
        )
        XCTAssertTrue(model.pickerVisible)

        model.acceptPickerRow(id: "suggestion:fix-flaky-gkeep", submitAfterInsert: false)

        XCTAssertEqual(model.plainDraft, nestedAccepted)
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), nestedAccepted.utf8.count)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(
            model.statusText,
            "Inserted :fix-flaky-gkeep on \u{2018}Fix flaky gkeep test\u{2019}"
        )
    }

    func testTypedIDSplicesLikeASuggestion() throws {
        let model = try installPrompt(
            "list-complete-nested.json",
            draft: nestedDraft,
            caret: 51,
            markerLine: 3,
            filter: "gkeep-fix"
        )

        model.acceptPickerRow(id: "new:gkeep-fix", submitAfterInsert: false)

        XCTAssertEqual(
            model.plainDraft,
            "@dev\n- Fix flaky gkeep test :gkeep-fix\n  - repro on CI first"
        )
    }

    func testSameLineAcceptKeepsTheOrdinaryInsertionAndAnnouncement() throws {
        let draft = "@dev\n- Fix flaky gkeep test :"
        let model = try installPrompt(
            "list-complete-same-line.json",
            draft: draft,
            caret: 29,
            markerLine: 2
        )

        model.acceptPickerRow(id: "suggestion:fix-flaky-gkeep", submitAfterInsert: false)

        XCTAssertEqual(model.plainDraft, "@dev\n- Fix flaky gkeep test :fix-flaky-gkeep")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), model.plainDraft.utf8.count)
        XCTAssertEqual(model.statusText, "Inserted :fix-flaky-gkeep")
    }

    func testAcceptReplacesTheOwnersExistingID() throws {
        let draft = "@dev\n- Fix flaky gkeep test :old-id\n  - repro on CI first :"
        let model = try installPrompt(
            "list-complete-nested-owner-id.json",
            draft: draft,
            caret: 59,
            markerLine: 3
        )

        model.acceptPickerRow(id: "suggestion:fix-flaky-gkeep", submitAfterInsert: false)

        XCTAssertEqual(model.plainDraft, nestedAccepted)
    }

    func testProjectNoteNestedPromptSplicesOntoTheOwnerBullet() throws {
        let draft = "Finish it @cash^goog-exit@\n- Draft the memo\n  - outline first :"
        let model = try installPrompt(
            "list-complete-project-note-nested.json",
            draft: draft,
            caret: 63,
            markerLine: 3
        )

        model.acceptPickerRow(id: "suggestion:draft-memo", submitAfterInsert: false)

        XCTAssertEqual(
            model.plainDraft,
            "Finish it @cash^goog-exit@\n- Draft the memo :draft-memo\n  - outline first"
        )
        XCTAssertEqual(
            model.statusText,
            "Inserted :draft-memo on \u{2018}Draft the memo\u{2019}"
        )
    }

    func testOlderBobWithoutASpliceInsertsAtTheReplacement() throws {
        let data = Data(
            """
            {"ok":true,"schema_version":1,"cursor":63,"replacement":{"start":63,"end":63},
            "context":"project_task_block_id","candidates":[],
            "block_id":{"route":"cash_goog_exit","relative_target":"cash_goog_exit.md",
            "marker":":","marker_range":{"start":62,"end":63},"intent":"new",
            "body":"Draft the memo","allowed_character":"[A-Za-z0-9-]",
            "allowed_description":"A-Z, a-z, 0-9 or '-'","suggestions":["draft-memo"]}}
            """.utf8
        )
        let older = try XCTUnwrap(
            JSONDecoder().decode(CaptureCompletionResponse.self, from: data).blockID
        )
        let draft = "Finish it @cash^goog-exit@\n- Draft the memo\n  - outline first :"
        let model = CapturePanelModel()
        model.installBlockIDPickerForPreviews(
            field: older,
            candidates: [],
            context: "project_task_block_id",
            replacement: CaptureRange(start: 63, end: 63),
            draft: draft,
            scopeLineNumber: 3
        )

        model.acceptPickerRow(id: "suggestion:draft-memo", submitAfterInsert: false)

        XCTAssertEqual(model.plainDraft, draft + "draft-memo")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), model.plainDraft.utf8.count)
    }

    func testStaleDraftIsNeverSpliced() throws {
        let model = try installPrompt(
            "list-complete-nested.json",
            draft: nestedDraft,
            caret: 51,
            markerLine: 3
        )
        model.plainDraft = "@dev\n- Something else"

        model.acceptPickerRow(id: "suggestion:fix-flaky-gkeep", submitAfterInsert: false)

        XCTAssertEqual(model.plainDraft, "@dev\n- Something else")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Draft changed \u{2014} reopen the task picker")
    }

    // MARK: - Owner caption

    func testNestedPromptCaptionsTheOwnerTask() throws {
        let model = try installPrompt(
            "list-complete-nested.json",
            draft: nestedDraft,
            caret: 51,
            markerLine: 3
        )

        let status = model.pickerPresentation?.blockIDStatus
        XCTAssertEqual(status?.ownerCaption, "ID for \u{2018}Fix flaky gkeep test\u{2019}")
        XCTAssertEqual(
            status?.ownerOutcome,
            "Next task in \u{25A3} dev.md, linked into today's Pomodoro"
        )
        XCTAssertEqual(
            model.selectedPickerRow?.detail.statusText,
            "ID for \u{2018}Fix flaky gkeep test\u{2019}"
        )
    }

    func testSameLinePromptHasNoOwnerCaption() throws {
        let model = try installPrompt(
            "list-complete-same-line.json",
            draft: "@dev\n- Fix flaky gkeep test :",
            caret: 29,
            markerLine: 2
        )

        XCTAssertNil(model.pickerPresentation?.blockIDStatus?.ownerCaption)
        XCTAssertEqual(
            model.selectedPickerRow?.detail.statusText,
            "\u{201C}Fix flaky gkeep test\u{201D}"
        )
    }

    // MARK: - Lone header

    func testLoneHeaderIsAQuietIncompleteStateAndAListWithBulletsIsNot() throws {
        XCTAssertEqual(
            CapturePanelModel.pickerNeed(in: try parse("list-parse-header-only.json")),
            .listItem
        )
        XCTAssertNil(CapturePanelModel.pickerNeed(in: try parse("list-parse-worked.json")))
        XCTAssertNil(CapturePanelModel.pickerNeed(in: try parse("list-parse-section.json")))
    }

    func testNewlineAtTheEndOfALoneHeaderStartsTheFirstBullet() throws {
        let model = CapturePanelModel()
        model.plainDraft = "@dev"
        model.installCaptureGrammarForTests(6)
        model.latestParse = try parse("list-parse-header-only.json")

        XCTAssertEqual(model.listHeaderNewlineInsertion(caretUTF8: 4), "\n- ")
        XCTAssertNil(model.listHeaderNewlineInsertion(caretUTF8: 2))
    }

    func testNewlineStaysBareWhenTheParseIsStale() throws {
        let model = CapturePanelModel()
        model.plainDraft = "@dev"
        model.installCaptureGrammarForTests(6)
        model.latestParse = try parse("list-parse-header-only.json")
        model.plainDraft = "@dev "

        XCTAssertNil(model.listHeaderNewlineInsertion(caretUTF8: 5))
    }

    func testNewlineStaysBareOnADraftThatAlreadyHasBullets() throws {
        let worked = try parse("list-parse-worked.json")
        let model = CapturePanelModel()
        model.plainDraft = worked.input
        model.installCaptureGrammarForTests(6)
        model.latestParse = worked

        XCTAssertNil(model.listHeaderNewlineInsertion(caretUTF8: 4))
    }
}
