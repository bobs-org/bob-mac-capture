import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureTemplateShelfModelTests: XCTestCase {
    func testOpeningRulesCoverPromptEmptyTemplateDraftEmptyShelfLoadingAndOldBob() async throws {
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let model = CapturePanelModel(savedTemplateShelf: shelf)

        model.presentTemplateShelf()
        XCTAssertTrue(model.isTemplateShelfPresented)
        model.dismissTemplateShelf()

        model.plainDraft = ""
        model.presentTemplateShelf()
        XCTAssertTrue(model.isTemplateShelfPresented)
        model.dismissTemplateShelf()

        model.plainDraft = "Buy milk @grocery"
        model.setParsedTemplateForTests(nil, draft: model.plainDraft)
        model.presentTemplateShelf()
        XCTAssertTrue(model.isTemplateShelfPresented, "a draft with no template opens the shelf")
        model.dismissTemplateShelf()

        model.plainDraft = "@@template:\nBuy {0}\n\n"
        model.setParsedTemplateForTests(CaptureParseTemplate(fieldCount: 1), draft: model.plainDraft)
        model.presentTemplateShelf()
        XCTAssertFalse(model.isTemplateShelfPresented)
        XCTAssertEqual(model.statusText, "This draft already has a template")

        model.plainDraft = ""
        model.setParsedTemplateForTests(nil, draft: "")
        shelf.replaceCacheForTests(templates: [])
        model.presentTemplateShelf()
        XCTAssertFalse(model.isTemplateShelfPresented)
        XCTAssertEqual(
            model.statusText,
            "No saved templates yet — capture an @@template: draft and it lands here"
        )

        let loading = SavedTemplateShelf()
        let loadingModel = CapturePanelModel(savedTemplateShelf: loading)
        loadingModel.presentTemplateShelf()
        XCTAssertFalse(loadingModel.isTemplateShelfPresented)
        XCTAssertEqual(loadingModel.statusText, "Loading saved templates…")

        let oldBob = SavedTemplateShelf()
        oldBob.replaceCacheForTests(templates: [], availability: .unsupported)
        let oldModel = CapturePanelModel(savedTemplateShelf: oldBob)
        oldModel.presentTemplateShelf()
        XCTAssertFalse(oldModel.isTemplateShelfPresented)
        XCTAssertEqual(oldModel.statusText, "Update bob to use saved templates")
        XCTAssertFalse(oldModel.savedTemplatesFooterVisible)

        let stash = CanceledDraftStash(capacity: 10)
        stash.push("retained")
        let promptModel = CapturePanelModel(
            canceledDraftStash: stash,
            savedTemplateShelf: shelf
        )
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        promptModel.installMissingTaskCompletionForPrompt()
        promptModel.acceptSelectedCompletion()
        promptModel.presentTemplateShelf()
        XCTAssertFalse(promptModel.isTemplateShelfPresented)
        XCTAssertEqual(
            promptModel.statusText,
            "Finish or cancel the block ID prompt before opening templates"
        )

        let pickerModel = CapturePanelModel(savedTemplateShelf: shelf)
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        pickerModel.picker = CapturePickerState(
            source: .taskLink,
            draftSnapshot: "note @Cash+",
            replacementRange: CaptureRange(start: 10, end: 15),
            restoreCursor: 15,
            candidates: [],
            warnings: [],
            filterText: "",
            selectedRowID: nil,
            visibleRowBudget: 4,
            snapshotIsPartial: false
        )
        pickerModel.presentTemplateShelf()
        XCTAssertFalse(pickerModel.isTemplateShelfPresented)
        XCTAssertEqual(
            pickerModel.statusText,
            "Finish or cancel the picker before opening templates"
        )
    }

    func testPickInsertsEmptyAndRowsFirstDraftsAsOneEdit() {
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        let first = Self.threeTemplates[0]

        model.presentTemplateShelf()
        model.useSelectedTemplate()

        XCTAssertEqual(model.plainDraft, first.draft)
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), first.cursor)
        XCTAssertFalse(model.isTemplateShelfPresented)

        let rowsModel = CapturePanelModel(savedTemplateShelf: shelf)
        rowsModel.plainDraft = "Acme acme https://example.com"
        rowsModel.setParsedTemplateForTests(nil, draft: rowsModel.plainDraft)
        let caret = rowsModel.plainDraft.utf8.count
        rowsModel.editorSelectionDidChange(cursorUTF8Offset: caret)
        rowsModel.presentTemplateShelf()
        rowsModel.useTemplate(at: 0)

        XCTAssertEqual(rowsModel.plainDraft, first.draft + "Acme acme https://example.com")
        XCTAssertEqual(rowsModel.collapsedSelectionUTF8Offset(), caret + first.draft.utf8.count)
    }

    func testPickThroughNativeTextViewUndoesInOneStepForEmptyAndRowsFirstDrafts() {
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let first = Self.threeTemplates[0]

        let emptyView = makeTextView("")
        let emptyModel = CapturePanelModel(savedTemplateShelf: shelf)
        wireInsert(emptyModel, textView: emptyView)
        emptyModel.presentTemplateShelf()
        emptyModel.useSelectedTemplate()
        XCTAssertEqual(emptyView.string, first.draft)
        XCTAssertEqual(emptyView.selectedRange(), utf16Selection(in: first.draft, utf8: first.cursor))
        XCTAssertTrue(emptyView.undoManager?.canUndo ?? false)
        emptyView.undoManager?.undo()
        XCTAssertEqual(emptyView.string, "")
        XCTAssertEqual(emptyView.selectedRange(), NSRange(location: 0, length: 0))

        let existing = "Acme acme https://example.com"
        let rowsView = makeTextView(existing)
        let rowsModel = CapturePanelModel(savedTemplateShelf: shelf)
        rowsModel.plainDraft = existing
        rowsModel.setParsedTemplateForTests(nil, draft: existing)
        rowsModel.editorSelectionDidChange(cursorUTF8Offset: existing.utf8.count)
        wireInsert(rowsModel, textView: rowsView)
        rowsModel.presentTemplateShelf()
        rowsModel.useTemplate(at: 0)
        XCTAssertEqual(rowsView.string, first.draft + existing)
        rowsView.undoManager?.undo()
        XCTAssertEqual(rowsView.string, existing)
        XCTAssertEqual(
            rowsView.selectedRange(),
            NSRange(location: (existing as NSString).length, length: 0)
        )
    }

    func testArmDisarmAndDeleteIncludingFailureRestoreAndLastEntryClose() async throws {
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.presentTemplateShelf()

        model.armOrConfirmTemplateDelete()
        XCTAssertEqual(model.armedDeleteTemplateID, Self.threeTemplates[0].id)
        XCTAssertEqual(model.statusText, "Press Delete again to delete template 1")

        model.selectNextTemplateEntry()
        XCTAssertNil(model.armedDeleteTemplateID)

        model.armOrConfirmTemplateDelete()
        model.escapeTemplateShelf()
        XCTAssertTrue(model.isTemplateShelfPresented)
        XCTAssertNil(model.armedDeleteTemplateID)

        let failingClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_TEMPLATES_DELETE_FIXTURE": "capture-templates-delete-error.json",
            ]
        )
        model.processClient = failingClient
        await waitUntil { shelf.templates.first?.id == "6cd8000f52eb" }
        let originalIDs = shelf.templates.map(\.id)
        model.presentTemplateShelf()
        model.armOrConfirmTemplateDelete()
        model.armOrConfirmTemplateDelete()
        XCTAssertEqual(model.templateShelfCount, 2)
        await waitUntil {
            model.templateShelfCount == 3 && model.statusText.contains("shelf locked")
        }
        XCTAssertEqual(model.savedTemplateShelf.templates.map(\.id), originalIDs)

        let lastShelf = SavedTemplateShelf()
        lastShelf.replaceCacheForTests(templates: [Self.threeTemplates[0]])
        let lastModel = CapturePanelModel(savedTemplateShelf: lastShelf)
        lastModel.presentTemplateShelf()
        lastModel.armOrConfirmTemplateDelete()
        lastModel.armOrConfirmTemplateDelete()
        XCTAssertFalse(lastModel.isTemplateShelfPresented)
        XCTAssertEqual(lastModel.statusText, "Template deleted · shelf is empty")
        XCTAssertTrue(lastShelf.isEmpty)
    }

    func testControlTAndControlSSwitchBetweenShelfAndStash() {
        let stash = CanceledDraftStash(capacity: 10)
        stash.push("retained")
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let model = CapturePanelModel(canceledDraftStash: stash, savedTemplateShelf: shelf)

        model.presentStashPicker()
        XCTAssertTrue(model.isStashPickerPresented)
        model.toggleTemplateShelf()
        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertTrue(model.isTemplateShelfPresented)

        model.switchTemplateShelfToStash()
        XCTAssertTrue(model.isStashPickerPresented)
        XCTAssertFalse(model.isTemplateShelfPresented)

        model.toggleTemplateShelf()
        model.plainDraft = "live draft"
        model.switchTemplateShelfToStash()
        XCTAssertTrue(model.isTemplateShelfPresented)
        XCTAssertFalse(model.isStashPickerPresented)
        XCTAssertEqual(
            model.statusText,
            "Capture, retain, or cancel the current draft before opening stash"
        )
    }

    func testStaleRefreshWhileOpenKeepsSelectedIdAndClampsOtherwise() {
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.presentTemplateShelf()
        model.selectNextTemplateEntry()
        XCTAssertEqual(model.selectedTemplateEntry?.id, Self.threeTemplates[1].id)

        shelf.replaceCacheForTests(templates: [
            Self.threeTemplates[1],
            Self.threeTemplates[2],
        ])
        XCTAssertEqual(model.selectedTemplateEntry?.id, Self.threeTemplates[1].id)
        XCTAssertTrue(model.isTemplateShelfPresented)

        shelf.replaceCacheForTests(templates: [Self.threeTemplates[0]])
        XCTAssertEqual(model.selectedTemplateEntry?.id, Self.threeTemplates[0].id)
        XCTAssertEqual(model.selectedTemplateIndex, 0)
    }

    func testCommandSConsumesWithoutSavingUntilCheckoutPhase() {
        let model = CapturePanelModel()
        model.saveTemplateFromKeyboard()
        XCTAssertEqual(model.statusText, "Only @@template: drafts can be saved as templates")

        model.plainDraft = "@@template:\nBuy {0}\n\n"
        model.setParsedTemplateForTests(CaptureParseTemplate(fieldCount: 1), draft: model.plainDraft)
        let tick = model.statusAnnouncementTick
        model.saveTemplateFromKeyboard()
        XCTAssertEqual(model.statusAnnouncementTick, tick)
    }

    func testPrepareForDismissalClosesTheShelf() {
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.presentTemplateShelf()
        model.prepareForDismissal()
        XCTAssertFalse(model.isTemplateShelfPresented)
    }

    private static let threeTemplates: [CaptureSavedTemplate] = [
        CaptureSavedTemplate(
            index: 1,
            id: "job",
            text: "Apply to {0}! @job^apply-{1}\n- **URL**: {2}",
            draft: "@@template:\nApply to {0}! @job^apply-{1}\n- **URL**: {2}\n\n",
            cursor: 57,
            fieldCount: 3,
            lineCount: 2,
            route: "job"
        ),
        CaptureSavedTemplate(
            index: 2,
            id: "reading",
            text: "Read {0} @reading^{1} p:2",
            draft: "@@template:\nRead {0} @reading^{1} p:2\n\n",
            cursor: 39,
            fieldCount: 2,
            lineCount: 1,
            route: "reading"
        ),
        CaptureSavedTemplate(
            index: 3,
            id: "grocery",
            text: "Buy {0} @grocery",
            draft: "@@template:\nBuy {0} @grocery\n\n",
            cursor: 30,
            fieldCount: 1,
            lineCount: 1,
            route: "grocery"
        ),
    ]

    private func makeTextView(_ text: String) -> NSTextView {
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        return textView
    }

    private func wireInsert(_ model: CapturePanelModel, textView: NSTextView) {
        model.applyTemplateInsert = { edit in
            CapturePanelController.insertSavedTemplateInEditableTextView(
                edit,
                firstResponder: textView,
                model: model
            )
        }
    }

    private func utf16Selection(in text: String, utf8: Int) -> NSRange {
        utf16Range(in: text, start: utf8, end: utf8) ?? NSRange(location: 0, length: 0)
    }

    private func fakeBobPath() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent("fake-bob")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw NSError(domain: "CaptureTemplateShelfModelTests", code: 1)
        }
        return url.path
    }

    private func waitUntil(
        timeout: Duration = .seconds(3),
        predicate: @escaping () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout
        while !predicate(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        if !predicate() {
            XCTFail("Condition not met before timeout")
        }
    }
}

extension CapturePanelModel {
    fileprivate func installMissingTaskCompletionForPrompt() {
        plainDraft = "note @Cash+goog"
        completionResponse = CaptureCompletionResponse(
            ok: true,
            schemaVersion: 1,
            cursor: 15,
            replacement: CaptureRange(start: 10, end: 15),
            context: "task",
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "goog",
                    label: "Google",
                    kind: "task",
                    requiresBlockID: true
                )
            ]
        )
        selectedCompletionIndex = 0
    }
}
