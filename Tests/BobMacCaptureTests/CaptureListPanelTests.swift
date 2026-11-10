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

    // MARK: - Hosted native undo

    private func makeTextView(_ text: String) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    private func makeHostedTextView(_ text: String) -> (NSTextView, NSWindow) {
        // Native undo lives on the window: a windowless text view has no undo
        // manager, so undo and redo would silently do nothing.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        window.isReleasedWhenClosed = false
        let textView = makeTextView(text)
        window.contentView?.addSubview(textView)
        window.makeFirstResponder(textView)
        return (textView, window)
    }

    private func wireNativeApply(_ model: CapturePanelModel, textView: NSTextView) {
        model.applyNativeRewriteEdit = { edit in
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: textView
            )
        }
    }

    private func installHostedPrompt(
        _ name: String,
        textView: NSTextView,
        caret: Int,
        markerLine: Int,
        filter: String = ""
    ) throws -> CapturePanelModel {
        let model = CapturePanelModel()
        wireNativeApply(model, textView: textView)
        model.installBlockIDPickerForPreviews(
            field: try field(name),
            candidates: [],
            context: "project_task_block_id",
            replacement: CaptureRange(start: caret, end: caret),
            filter: filter,
            draft: textView.string,
            scopeLineNumber: markerLine
        )
        return model
    }

    private func assertOneNativeUndoStep(
        textView: NSTextView,
        model: CapturePanelModel,
        from before: String,
        to after: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(textView.string, after, file: file, line: line)
        XCTAssertEqual(model.plainDraft, after, file: file, line: line)
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), after.utf8.count, file: file, line: line)
        XCTAssertTrue(textView.undoManager?.canUndo ?? false, file: file, line: line)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, before, file: file, line: line)
        model.plainDraft = textView.string
        XCTAssertEqual(model.plainDraft, before, file: file, line: line)
        XCTAssertTrue(textView.undoManager?.canRedo ?? false, file: file, line: line)
        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, after, file: file, line: line)
        model.plainDraft = textView.string
        XCTAssertEqual(model.plainDraft, after, file: file, line: line)
    }

    func testNestedAcceptIsOneNativeUndoStep() throws {
        let (textView, window) = makeHostedTextView(nestedDraft)
        defer { window.close() }
        let model = try installHostedPrompt(
            "list-complete-nested.json",
            textView: textView,
            caret: 51,
            markerLine: 3
        )

        model.acceptPickerRow(id: "suggestion:fix-flaky-gkeep", submitAfterInsert: false)

        XCTAssertEqual(
            model.statusText,
            "Inserted :fix-flaky-gkeep on \u{2018}Fix flaky gkeep test\u{2019}"
        )
        XCTAssertFalse(model.pickerVisible)
        assertOneNativeUndoStep(
            textView: textView,
            model: model,
            from: nestedDraft,
            to: nestedAccepted
        )
    }

    func testSameLineAcceptIsOneNativeUndoStep() throws {
        let draft = "@dev\n- Fix flaky gkeep test :"
        let after = "@dev\n- Fix flaky gkeep test :fix-flaky-gkeep"
        let (textView, window) = makeHostedTextView(draft)
        defer { window.close() }
        let model = try installHostedPrompt(
            "list-complete-same-line.json",
            textView: textView,
            caret: 29,
            markerLine: 2
        )

        model.acceptPickerRow(id: "suggestion:fix-flaky-gkeep", submitAfterInsert: false)

        XCTAssertEqual(model.statusText, "Inserted :fix-flaky-gkeep")
        assertOneNativeUndoStep(textView: textView, model: model, from: draft, to: after)
    }

    func testOwnerIDReplacementIsOneNativeUndoStep() throws {
        let draft = "@dev\n- Fix flaky gkeep test :old-id\n  - repro on CI first :"
        let (textView, window) = makeHostedTextView(draft)
        defer { window.close() }
        let model = try installHostedPrompt(
            "list-complete-nested-owner-id.json",
            textView: textView,
            caret: 59,
            markerLine: 3
        )

        model.acceptPickerRow(id: "suggestion:fix-flaky-gkeep", submitAfterInsert: false)

        assertOneNativeUndoStep(textView: textView, model: model, from: draft, to: nestedAccepted)
    }

    func testTypeThroughRemainderIsOneNativeUndoStep() throws {
        let draft = "@dev\n- Fix flaky gkeep test :"
        let (textView, window) = makeHostedTextView(draft)
        defer { window.close() }
        let model = try installHostedPrompt(
            "list-complete-same-line.json",
            textView: textView,
            caret: 29,
            markerLine: 2
        )
        model.updatePickerFilter("fix Fix")

        let after = "@dev\n- Fix flaky gkeep test :fix Fix"
        XCTAssertEqual(model.plainDraft, after)
        XCTAssertEqual(textView.string, after)
        assertOneNativeUndoStep(textView: textView, model: model, from: draft, to: after)
    }

    func testTypeThroughSeparatorRewriteHasItsOwnNativeUndoStep() async throws {
        let draft = "@dev\n- Fix flaky gkeep test :"
        let (textView, window) = makeHostedTextView(draft)
        defer { window.close() }
        let model = try installHostedPrompt(
            "list-complete-same-line.json",
            textView: textView,
            caret: 29,
            markerLine: 2
        )
        model.setProcessClient(
            BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
            )
        )

        model.updatePickerFilter("new-id.")

        let after = "@dev\n- Fix flaky gkeep test ^new-id"
        for _ in 0..<100 where model.plainDraft != after {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertEqual(textView.string, after)
        XCTAssertEqual(model.statusText, "Changed :new-id to ^new-id")
        XCTAssertFalse(model.pickerVisible)

        textView.undoManager?.undo()
        let literal = "@dev\n- Fix flaky gkeep test :new-id."
        XCTAssertEqual(textView.string, literal)
        model.plainDraft = textView.string
        XCTAssertEqual(model.plainDraft, literal)
    }

    func testProjectNoteNestedIsOneNativeUndoStep() throws {
        let draft = "Finish it @cash^goog-exit@\n- Draft the memo\n  - outline first :"
        let after = "Finish it @cash^goog-exit@\n- Draft the memo :draft-memo\n  - outline first"
        let (textView, window) = makeHostedTextView(draft)
        defer { window.close() }
        let model = try installHostedPrompt(
            "list-complete-project-note-nested.json",
            textView: textView,
            caret: 63,
            markerLine: 3
        )

        model.acceptPickerRow(id: "suggestion:draft-memo", submitAfterInsert: false)

        XCTAssertEqual(
            model.statusText,
            "Inserted :draft-memo on \u{2018}Draft the memo\u{2019}"
        )
        assertOneNativeUndoStep(textView: textView, model: model, from: draft, to: after)
    }

    func testOlderBobFallbackIsOneNativeUndoStep() throws {
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
        let after = draft + "draft-memo"
        let (textView, window) = makeHostedTextView(draft)
        defer { window.close() }
        let model = CapturePanelModel()
        wireNativeApply(model, textView: textView)
        model.installBlockIDPickerForPreviews(
            field: older,
            candidates: [],
            context: "project_task_block_id",
            replacement: CaptureRange(start: 63, end: 63),
            draft: draft,
            scopeLineNumber: 3
        )

        model.acceptPickerRow(id: "suggestion:draft-memo", submitAfterInsert: false)

        assertOneNativeUndoStep(textView: textView, model: model, from: draft, to: after)
    }

    func testUnrelatedTypingHistorySurvivesTheSplice() async throws {
        let (textView, window) = makeHostedTextView(nestedDraft)
        defer { window.close() }
        textView.insertText(" ", replacementRange: textView.selectedRange())
        // Typing and the picker accept run on separate key events in
        // production, so they land in separate undo groups. Yield a runloop
        // turn here for the same boundary; otherwise both inserts coalesce
        // into one group and the first undo skips the typed draft.
        textView.breakUndoCoalescing()
        try await Task.sleep(nanoseconds: 80_000_000)
        let typed = textView.string
        XCTAssertEqual(typed, nestedDraft + " ")
        let model = try installHostedPrompt(
            "list-complete-nested.json",
            textView: textView,
            caret: typed.utf8.count,
            markerLine: 3
        )

        model.acceptPickerRow(id: "suggestion:fix-flaky-gkeep", submitAfterInsert: false)

        let after = nestedAccepted + " "
        XCTAssertEqual(textView.string, after)
        XCTAssertEqual(model.plainDraft, after)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, typed)
        XCTAssertTrue(textView.undoManager?.canUndo ?? false)
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, nestedDraft)
        textView.undoManager?.redo()
        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, after)
    }

    func testHostedStaleDraftIsNeverSpliced() throws {
        let textView = makeTextView(nestedDraft)
        let model = try installHostedPrompt(
            "list-complete-nested.json",
            textView: textView,
            caret: 51,
            markerLine: 3
        )
        textView.string = "@dev\n- Something else"
        model.plainDraft = "@dev\n- Something else"

        model.acceptPickerRow(id: "suggestion:fix-flaky-gkeep", submitAfterInsert: false)

        XCTAssertEqual(textView.string, "@dev\n- Something else")
        XCTAssertEqual(model.plainDraft, "@dev\n- Something else")
        XCTAssertEqual(model.statusText, "Draft changed \u{2014} reopen the task picker")
    }

    // MARK: - Section picks

    private func completion(_ name: String) throws -> CaptureCompletionResponse {
        try JSONDecoder().decode(CaptureCompletionResponse.self, from: fixtureData(name))
    }

    private func installSectionCompletion(
        on model: CapturePanelModel,
        fixture: String,
        draft: String
    ) throws {
        let response = try completion(fixture)
        model.plainDraft = draft
        model.completionResponse = response
        model.selectedCompletionIndex = CaptureCompletionMenu.initialSelectedIndex(
            for: response,
            queryIsEmpty: false
        )
    }

    func testSectionNeedIsACalmIncompleteState() throws {
        XCTAssertEqual(
            CapturePanelModel.pickerNeed(in: try parse("list-parse-section-incomplete.json")),
            .section
        )
        XCTAssertEqual(
            CapturePickerNeed.section.statusText,
            "Finish the quoted section name \u{2014} pick a section"
        )
    }

    func testSectionAcceptInsertsBobsReplacementVerbatim() throws {
        let model = CapturePanelModel()
        try installSectionCompletion(on: model, fixture: "list-complete-section.json", draft: "@sase#Fu")

        XCTAssertTrue(model.acceptSelectedCompletion())

        XCTAssertEqual(model.plainDraft, "@sase#future-work")
        XCTAssertNil(model.completionResponse)
    }

    func testSectionAcceptOnAHeaderWithBulletsInsertsVerbatim() throws {
        let model = CapturePanelModel()
        let draft = "@sase#Fu\n- boom"
        try installSectionCompletion(on: model, fixture: "list-complete-section-with-bullets.json", draft: draft)

        XCTAssertTrue(model.acceptSelectedCompletion())

        XCTAssertEqual(model.plainDraft, "@sase#future-work\n- boom")
    }

    func testPartialQuotedSectionAcceptCoversTheOpeningQuote() throws {
        let model = CapturePanelModel()
        try installSectionCompletion(
            on: model,
            fixture: "list-complete-section-partial-quote.json",
            draft: "@sase#\"Fu"
        )

        XCTAssertTrue(model.acceptSelectedCompletion())

        XCTAssertEqual(model.plainDraft, "@sase#future-work")
    }

    func testPartialQuotedSectionWithBulletsInsertsVerbatim() throws {
        let model = CapturePanelModel()
        let draft: String = "@sase#\"Fu\n- boom"
        try installSectionCompletion(
            on: model,
            fixture: "list-complete-section-partial-quote-with-bullets.json",
            draft: draft
        )

        XCTAssertTrue(model.acceptSelectedCompletion())

        XCTAssertEqual(model.plainDraft, "@sase#future-work\n- boom")
    }
}
