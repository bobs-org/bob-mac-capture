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
        XCTAssertEqual(model.templateOrigin, first.id)
        XCTAssertEqual(model.templateShelfCount, Self.threeTemplates.count - 1)
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

        let emptyWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        emptyWindow.isReleasedWhenClosed = false
        defer { emptyWindow.close() }
        let emptyView = makeTextView("")
        emptyWindow.contentView?.addSubview(emptyView)
        emptyWindow.makeFirstResponder(emptyView)
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
        let rowsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: true
        )
        rowsWindow.isReleasedWhenClosed = false
        defer { rowsWindow.close() }
        let rowsView = makeTextView(existing)
        rowsWindow.contentView?.addSubview(rowsView)
        rowsWindow.makeFirstResponder(rowsView)
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

    func testCheckoutCountHidesOriginAndDiscardMakesItVisibleAgain() {
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.plainDraft = Self.threeTemplates[0].draft
        model.templateOrigin = Self.threeTemplates[0].id

        XCTAssertEqual(model.templateShelfCount, 2)
        XCTAssertEqual(model.templateEntries.map(\.id), ["reading", "grocery"])
        XCTAssertEqual(model.templateEntries.map(\.index), [1, 2])

        model.discardDraft()

        XCTAssertNil(model.templateOrigin)
        XCTAssertEqual(model.templateShelfCount, 3)
        XCTAssertEqual(model.templateEntries.map(\.id), ["job", "reading", "grocery"])
    }

    func testEscapeAndFailedCaptureKeepCheckoutAndSubmitCarriesOrigin() async throws {
        let shelf = SavedTemplateShelf()
        let recordURL = temporaryURL("capture-template-failure-record")
        defer { try? FileManager.default.removeItem(at: recordURL) }
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_CAPTURE_STDOUT": #"{"ok":false,"error":"capture failed","code":"capture_failed"}"#,
                "FAKE_BOB_CAPTURE_EXIT": "1",
            ]
        )
        await waitUntil { shelf.availability == .available }
        model.plainDraft = Self.threeTemplates[0].draft
        model.templateOrigin = Self.threeTemplates[0].id
        model.setParsedTemplateForTests(CaptureParseTemplate(fieldCount: 3), draft: model.plainDraft)

        model.closeRetainingDraft()
        XCTAssertEqual(model.templateOrigin, Self.threeTemplates[0].id)
        XCTAssertEqual(model.plainDraft, Self.threeTemplates[0].draft)

        model.submit(openAfterCapture: false)
        await waitUntil { !model.isSubmitting }

        XCTAssertEqual(model.templateOrigin, Self.threeTemplates[0].id)
        XCTAssertEqual(model.plainDraft, Self.threeTemplates[0].draft)
        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(record.contains("argv=capture --format json --require-pull-in-choice --template-origin job --"))
    }

    func testCurrentFreshParseWithoutTemplateReleasesCheckoutButPendingParseDoesNot() async throws {
        let shelf = SavedTemplateShelf()
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_PARSE_FIXTURE": "capture-parse-not-template.json",
            ]
        )
        let pendingModel = CapturePanelModel(
            debounceNanoseconds: 10_000_000_000,
            savedTemplateShelf: shelf
        )
        pendingModel.processClient = client
        await waitUntil { shelf.availability == .available }
        pendingModel.plainDraft = Self.threeTemplates[0].draft
        pendingModel.templateOrigin = Self.threeTemplates[0].id
        pendingModel.setParsedTemplateForTests(
            CaptureParseTemplate(fieldCount: 3),
            draft: pendingModel.plainDraft
        )

        pendingModel.plainDraft = "Buy milk @grocery"
        pendingModel.editorTextDidChange()
        XCTAssertEqual(pendingModel.templateOrigin, Self.threeTemplates[0].id)

        let currentModel = CapturePanelModel(debounceNanoseconds: 0, savedTemplateShelf: shelf)
        currentModel.processClient = client
        await waitUntil { shelf.availability == .available }
        currentModel.plainDraft = "Buy milk @grocery"
        currentModel.templateOrigin = Self.threeTemplates[0].id
        currentModel.editorTextDidChange()

        await waitUntil { currentModel.templateOrigin == nil }
    }

    func testControlCStashesDraftWithoutCheckoutAndRestoringDoesNotRestoreOrigin() throws {
        let stash = CanceledDraftStash(capacity: 10)
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let model = CapturePanelModel(canceledDraftStash: stash, savedTemplateShelf: shelf)
        model.plainDraft = Self.threeTemplates[0].draft
        model.templateOrigin = Self.threeTemplates[0].id

        model.stashDraftAndClose()

        XCTAssertNil(model.templateOrigin)
        XCTAssertEqual(model.statusText, "Canceled draft stashed · template kept")
        XCTAssertEqual(stash.entries.first?.text, Self.threeTemplates[0].draft)

        model.presentStashPicker()
        model.restoreStashEntry(id: try XCTUnwrap(stash.entries.first?.id))
        XCTAssertEqual(model.plainDraft, Self.threeTemplates[0].draft)
        XCTAssertNil(model.templateOrigin)
    }

    func testCommandSavesTemplateChecksItOutAndUsesOriginOnEdits() async throws {
        let shelf = SavedTemplateShelf()
        let recordURL = temporaryURL("capture-template-save-record")
        defer { try? FileManager.default.removeItem(at: recordURL) }
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_TEMPLATES_SAVE_FIXTURE": "capture-templates-save-new.json",
            ]
        )
        await waitUntil { shelf.availability == .available }
        model.plainDraft = Self.threeTemplates[0].draft
        model.setParsedTemplateForTests(CaptureParseTemplate(fieldCount: 3), draft: model.plainDraft)

        model.saveTemplateFromKeyboard()
        await waitUntil { !model.isSavingTemplate }

        XCTAssertEqual(model.plainDraft, Self.threeTemplates[0].draft)
        XCTAssertEqual(model.templateOrigin, "6cd8000f52eb")
        XCTAssertEqual(model.statusText, "Template saved — ⌃T to reuse")
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.templateShelfCount, 2)
        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(record.contains("argv=capture-templates save --format json -- @@template:"))
        XCTAssertFalse(record.contains("argv=capture-templates save --format json --template-origin"))

        model.templateOrigin = "6cd8000f52eb"
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_TEMPLATES_SAVE_FIXTURE": "capture-templates-save-replaced.json",
            ]
        )
        await waitUntil {
            let output = try? String(contentsOf: recordURL, encoding: .utf8)
            return (output?.components(separatedBy: "argv=capture-templates --format json").count ?? 0) >= 2
        }
        model.setParsedTemplateForTests(CaptureParseTemplate(fieldCount: 3), draft: model.plainDraft)
        model.saveTemplateFromKeyboard()
        await waitUntil { !model.isSavingTemplate && model.templateOrigin == "6cd8000f52eb" }
        XCTAssertEqual(model.statusText, "Template updated")
        let updatedRecord = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(updatedRecord.contains("argv=capture-templates save --format json --template-origin 6cd8000f52eb --"))
    }

    func testCommandSRefusalStaysInStatusAndOldBobDoesNotAttemptSave() async throws {
        let shelf = SavedTemplateShelf()
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_TEMPLATES_SAVE_FIXTURE": "capture-templates-save-invalid.json",
            ]
        )
        await waitUntil { shelf.availability == .available }
        model.plainDraft = Self.threeTemplates[0].draft
        model.setParsedTemplateForTests(CaptureParseTemplate(fieldCount: 3), draft: model.plainDraft)

        model.saveTemplateFromKeyboard()
        await waitUntil { !model.isSavingTemplate }
        XCTAssertTrue(model.statusText.contains("template"))
        XCTAssertNil(model.errorMessage)

        let oldShelf = SavedTemplateShelf()
        let oldModel = CapturePanelModel(savedTemplateShelf: oldShelf)
        oldModel.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_TEMPLATES_UNSUPPORTED": "1",
            ]
        )
        await waitUntil { oldShelf.isUnsupported }
        oldModel.plainDraft = Self.threeTemplates[0].draft
        oldModel.setParsedTemplateForTests(CaptureParseTemplate(fieldCount: 3), draft: oldModel.plainDraft)
        oldModel.saveTemplateFromKeyboard()
        XCTAssertEqual(oldModel.statusText, "Update bob to use saved templates")
        XCTAssertFalse(oldModel.isSavingTemplate)
    }

    func testSuccessfulTemplateCaptureStatusAndCheckoutSettlementAcrossOutcomes() async throws {
        let cases: [(String, String)] = [
            ("capture-template-saved-new.json", " · Template saved — ⌃T to reuse"),
            ("capture-template-saved-replaced.json", " · Template updated"),
            ("capture-template-saved-updated.json", ""),
            ("capture-template-not-saved.json", " · Template not saved: write shelf: File exists (os error 17)"),
        ]
        for (fixture, expectedSuffix) in cases {
            let shelf = SavedTemplateShelf()
            let recordURL = temporaryURL("capture-template-submit-\(fixture)")
            defer { try? FileManager.default.removeItem(at: recordURL) }
            let model = CapturePanelModel(savedTemplateShelf: shelf)
            model.processClient = BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": recordURL.path,
                    "FAKE_BOB_CAPTURE_TEMPLATE_FIXTURE": fixture,
                ]
            )
            await waitUntil { shelf.availability == .available }
            model.plainDraft = Self.threeTemplates[0].draft
            model.templateOrigin = Self.threeTemplates[0].id
            model.setParsedTemplateForTests(CaptureParseTemplate(fieldCount: 3), draft: model.plainDraft)

            model.submit(openAfterCapture: false)
            await waitUntil { !model.isSubmitting }

            XCTAssertEqual(model.plainDraft, "")
            XCTAssertNil(model.templateOrigin)
            if expectedSuffix.isEmpty {
                XCTAssertFalse(model.statusText.contains("Template saved"))
            } else {
                XCTAssertTrue(model.statusText.hasSuffix(expectedSuffix), model.statusText)
            }
            let record = try String(contentsOf: recordURL, encoding: .utf8)
            XCTAssertTrue(record.contains("--template-origin job --"))
        }
    }

    func testEditorEmptyingReleasesCheckoutAndSettingsCanClearShelf() async throws {
        let shelf = SavedTemplateShelf()
        shelf.replaceCacheForTests(templates: Self.threeTemplates)
        let model = CapturePanelModel(savedTemplateShelf: shelf)
        model.plainDraft = Self.threeTemplates[0].draft
        model.templateOrigin = Self.threeTemplates[0].id
        model.attributedDraft = AttributedString()
        model.editorTextDidChange()
        XCTAssertNil(model.templateOrigin)

        let recordURL = temporaryURL("capture-template-clear-record")
        defer { try? FileManager.default.removeItem(at: recordURL) }
        shelf.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_TEMPLATES_CLEAR_FIXTURE": "capture-templates-clear.json",
                "FAKE_BOB_TEMPLATES_LIST_FIXTURE": "capture-templates-list-empty.json",
            ]
        )
        let response = try await shelf.clearSavedTemplates()
        await waitUntil { shelf.templates.isEmpty }
        XCTAssertEqual(response?.ok, true)
        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(record.contains("argv=capture-templates clear --format json"))
    }

    func testCommandSRejectsNonTemplateAndDoublePressDoesNotStartSecondSave() async throws {
        let model = CapturePanelModel()
        model.saveTemplateFromKeyboard()
        XCTAssertEqual(model.statusText, "Only @@template: drafts can be saved as templates")

        let shelf = SavedTemplateShelf()
        let recordURL = temporaryURL("capture-template-double-save-record")
        defer { try? FileManager.default.removeItem(at: recordURL) }
        let savingModel = CapturePanelModel(savedTemplateShelf: shelf)
        savingModel.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_DELAY_SECONDS": "0.1",
            ]
        )
        await waitUntil { shelf.availability == .available }
        savingModel.plainDraft = Self.threeTemplates[0].draft
        savingModel.setParsedTemplateForTests(CaptureParseTemplate(fieldCount: 3), draft: savingModel.plainDraft)
        savingModel.saveTemplateFromKeyboard()
        savingModel.saveTemplateFromKeyboard()
        await waitUntil { !savingModel.isSavingTemplate }
        let record = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-templates save ").count - 1, 1)
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

    private func temporaryURL(_ name: String) -> URL {
        URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("bob-mac-capture-\(name)-\(UUID().uuidString)")
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
