import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Parent-task picker panel wiring: vault/scoped accept, chip, backspace,
/// operator continuation, exact-match suppression, ID prompt, and keys.
@MainActor
final class CaptureParentTaskPanelTests: XCTestCase {
    private func identifiedCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "@sase+deep-fix",
            route: "sase",
            taskRef: "6:41d049f2",
            blockID: "deep-fix",
            requiresBlockID: false,
            statusSymbol: "*",
            statusName: "Next",
            text: "Fix deep bug",
            section: "Bugs",
            group: "queued"
        )
    }

    private func idlessCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            route: "mac_inbox",
            taskRef: "4:bf5e981c",
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Todo",
            text: "Call the bank",
            blockIDSuggestions: ["call-bank"]
        )
    }

    private func scopedIdentifiedCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "goog-exit",
            route: "cash",
            taskRef: "4:googexit",
            blockID: "goog-exit",
            requiresBlockID: false,
            statusSymbol: "*",
            statusName: "Next",
            text: "Finish Google Exit Packet!",
            section: "Tasks"
        )
    }

    private func vaultContext(
        continuationKeys: [String] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+"]
    ) -> ParentTaskPickerContext {
        .vault(
            markerRange: CaptureRange(start: 0, end: 1),
            actionContinuationKeys: continuationKeys
        )
    }

    private func scopedContext() -> ParentTaskPickerContext {
        .note(
            route: "cash",
            noteTarget: "cash.md",
            markerRange: CaptureRange(start: 0, end: 6),
            triggerRemovalRange: CaptureRange(start: 5, end: 6)
        )
    }

    private func installVaultPicker(
        filter: String = "",
        draft: String = "+",
        replacement: CaptureRange = CaptureRange(start: 0, end: 1),
        continuationKeys: [String] = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+"]
    ) -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installParentTaskPickerForPreviews(
            candidates: [identifiedCandidate(), idlessCandidate()],
            context: vaultContext(continuationKeys: continuationKeys),
            filter: filter,
            draft: draft,
            replacement: replacement
        )
        return model
    }

    private func installScopedPicker(
        filter: String = "",
        draft: String = "@cash+",
        replacement: CaptureRange = CaptureRange(start: 6, end: 6)
    ) -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installParentTaskPickerForPreviews(
            candidates: [scopedIdentifiedCandidate()],
            context: scopedContext(),
            filter: filter,
            draft: draft,
            replacement: replacement
        )
        return model
    }

    func testAcceptInsertsPlusMarkerWithCaretAtEnd() {
        let model = installVaultPicker()
        XCTAssertTrue(model.pickerVisible)
        model.acceptPickerRow(id: "sase|6:41d049f2", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "@sase+deep-fix")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 14)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Inserted @sase+deep-fix")
    }

    func testScopedAcceptInsertsIDOnly() {
        let model = installScopedPicker()
        model.acceptPickerRow(id: "cash|4:googexit", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "@cash+goog-exit")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 15)
        XCTAssertEqual(model.statusText, "Inserted goog-exit")
    }

    func testShiftReturnDoesNotStartPlusSelectedTask() {
        let model = installVaultPicker()
        model.acceptPickerRowAndStart(id: "sase|6:41d049f2")
        XCTAssertEqual(model.plainDraft, "+")
        XCTAssertTrue(model.pickerVisible)
    }

    func testAcceptIdlessOpensParentTaskPickerPrompt() {
        let model = installVaultPicker()
        model.acceptPickerRow(id: "mac_inbox|4:bf5e981c", submitAfterInsert: false)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsParentTaskPicker)
        XCTAssertTrue(model.taskIDPromptCyclesSuggestions)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "call-bank")
        XCTAssertEqual(model.taskIDPrompt?.linkSuggestions, ["call-bank"])
    }

    func testTabCyclesParentTaskSuggestions() {
        let model = CapturePanelModel()
        let pending = CaptureCompletionCandidate(
            replacement: "",
            route: "sase",
            taskRef: "7:446bd057",
            requiresBlockID: true,
            text: "Fix flaky gkeep test",
            blockIDSuggestions: ["fix-flaky-gkeep", "flaky-gkeep-test"]
        )
        model.installParentTaskPickerForPreviews(
            candidates: [pending],
            context: vaultContext(),
            filter: "flaky",
            draft: "+",
            replacement: CaptureRange(start: 0, end: 1)
        )
        model.acceptPickerRow(id: "sase|7:446bd057", submitAfterInsert: false)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "fix-flaky-gkeep")
        model.cycleTaskLinkSuggestion(forward: true)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "flaky-gkeep-test")
        model.cycleTaskLinkSuggestion(forward: false)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "fix-flaky-gkeep")
    }

    func testEscapePromptReturnsToPickerWithFilter() {
        let model = installVaultPicker(filter: "bank")
        XCTAssertEqual(model.picker?.filterText, "bank")
        model.acceptPickerRow(id: "mac_inbox|4:bf5e981c", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.cancelTaskIDPrompt()
        XCTAssertFalse(model.taskIDPromptVisible)
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.picker?.filterText, "bank")
        XCTAssertEqual(model.picker?.selectedRowID, "mac_inbox|4:bf5e981c")
    }

    func testMarkerHighlightUsesDescriptorRange() {
        let context = vaultContext()
        let range = CapturePanelModel.pickerMarkerHighlightRange(
            source: .parentTask(context),
            replacementRange: CaptureRange(start: 0, end: 1),
            markerRange: nil
        )
        XCTAssertEqual(range, context.markerRange)
    }

    func testScopedBackspaceRemovesPlusLeavingRoute() {
        let model = installScopedPicker()
        XCTAssertTrue(model.pickerVisible)
        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "@cash")
        XCTAssertFalse(model.pickerVisible)
    }

    func testVaultBackspaceRemovesBarePlus() {
        let model = installVaultPicker()
        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertFalse(model.pickerVisible)
    }

    func testOperatorContinuationInsertsDigitOnceAndCloses() {
        let model = installVaultPicker()
        XCTAssertEqual(model.pickerOperatorContinuationKeys, vaultContext().actionContinuationKeys)
        model.continuePickerOperator("2")
        XCTAssertEqual(model.plainDraft, "+2")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.pickerChip)
    }

    func testOperatorContinuationPlusKeyInsertsOnceAndCloses() {
        let model = installVaultPicker()
        model.continuePickerOperator("+")
        XCTAssertEqual(model.plainDraft, "++")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.pickerChip)
    }

    func testNumericFilterTextDoesNotContinueOperator() {
        let model = installVaultPicker()
        model.updatePickerFilter("2")
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.picker?.filterText, "2")
        XCTAssertEqual(model.plainDraft, "+")
        XCTAssertEqual(model.pickerOperatorContinuationKeys, [])
        model.continuePickerOperator("2")
        XCTAssertEqual(model.plainDraft, "+")
        XCTAssertTrue(model.pickerVisible)
    }

    func testCancelShowsChipAndReopenRestoresPicker() {
        let model = installVaultPicker()
        model.cancelPicker()
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(model.pickerChipVisible)
        XCTAssertEqual(model.pickerChip?.source.chipLabel, "Select a parent task")
        XCTAssertEqual(model.plainDraft, "+")
        model.openPickerFromChip()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsParentTask)
        XCTAssertNil(model.pickerChip)
    }

    func testOperatorContinuationIgnoredWhenFilterIsNonempty() {
        let model = installVaultPicker(filter: "bank")
        XCTAssertEqual(model.pickerOperatorContinuationKeys, [])
        model.continuePickerOperator("2")
        XCTAssertEqual(model.plainDraft, "+")
        XCTAssertTrue(model.pickerVisible)
    }

    func testScopedPickerHasNoOperatorContinuation() {
        let model = installScopedPicker()
        XCTAssertEqual(model.pickerOperatorContinuationKeys, [])
        model.continuePickerOperator("2")
        XCTAssertEqual(model.plainDraft, "@cash+")
        XCTAssertTrue(model.pickerVisible)
    }

    func testProseTerminalHasNoOperatorContinuation() {
        let model = CapturePanelModel()
        model.installParentTaskPickerForPreviews(
            candidates: [identifiedCandidate()],
            context: .vault(markerRange: CaptureRange(start: 16, end: 17)),
            draft: "Called the bank +",
            replacement: CaptureRange(start: 16, end: 17)
        )
        XCTAssertEqual(model.pickerOperatorContinuationKeys, [])
        model.continuePickerOperator("2")
        XCTAssertEqual(model.plainDraft, "Called the bank +")
        XCTAssertTrue(model.pickerVisible)
    }

    func testRouterShiftReturnIsConsumedForParentTask() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerSourceIsTaskLink: false
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .shift), context: context),
            .consumeKey
        )
    }

    func testRouterContinuesOperatorForUnmodifiedDigit() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerFilterIsEmpty: true,
            pickerOperatorContinuationKeys: ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "+"]
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 19, modifiers: [], characters: "2"),
                context: context
            ),
            .continuePickerOperator("2")
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 24, modifiers: .shift, characters: "+"),
                context: context
            ),
            .continuePickerOperator("+")
        )
        XCTAssertNil(
            router.command(
                for: keyEvent(keyCode: 19, modifiers: .command, characters: "2"),
                context: context
            )
        )
    }

    func testRouterDoesNotContinueOperatorWhenFilterHasText() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerFilterIsEmpty: false,
            pickerOperatorContinuationKeys: ["2"]
        )
        XCTAssertNil(
            router.command(
                for: keyEvent(keyCode: 19, modifiers: [], characters: "2"),
                context: context
            )
        )
    }

    func testRouterTabCyclesParentTaskPickerPrompt() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            taskIDPromptVisible: true,
            taskIDPromptCyclesSuggestions: true
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48, modifiers: []), context: context),
            .cycleTaskLinkSuggestionForward
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48, modifiers: .shift), context: context),
            .cycleTaskLinkSuggestionBackward
        )
    }

    func testNeedStatusForUnresolvedBodySelector() {
        XCTAssertEqual(
            CapturePickerNeed.taskParent.statusText,
            "Choose a task to append to — press Tab to browse"
        )
    }

    func testPlusOpensVaultPickerFromFakeBob() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = try parentTaskModel(recordURL: recordURL)
        model.plainDraft = "+"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }
        await waitUntil {
            ((try? String(contentsOf: recordURL)) ?? "").contains(
                "argv=capture --dry-run --no-clip --format json -- +\n"
            )
        }

        XCTAssertTrue(model.pickerSourceIsParentTask)
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(model.picker?.filterText, "")
        XCTAssertEqual(model.picker?.candidates.count, 8)
        XCTAssertEqual(model.focusRequest.target, .pickerFilter)
        XCTAssertTrue(model.editorInputLocked)
        if case .parentTask(let context) = model.picker?.source {
            XCTAssertTrue(context.isVault)
            XCTAssertTrue(context.isLonePlusOperator)
        } else {
            XCTFail("expected parent-task source")
        }
    }

    func testBankQuerySeedsFilterAndRefetchesAtStart() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = try parentTaskModel(recordURL: recordURL)
        model.plainDraft = "+bank"
        model.editorTextDidChange(cursorUTF8Offset: 5)
        await waitUntil { model.pickerVisible }

        XCTAssertEqual(model.picker?.filterText, "bank")
        XCTAssertEqual(model.picker?.snapshotIsPartial, false)
        XCTAssertEqual(model.picker?.candidates.count, 8)
        XCTAssertEqual(model.pickerPresentation?.mode, .filtered)
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-complete").count - 1, 2)
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 0 "))
    }

    func testProseTerminalOpensVaultPickerWithoutOperatorKeys() async throws {
        let model = try parentTaskModel()
        let draft = "Called the bank +"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.pickerVisible }

        XCTAssertEqual(model.statusText, "Choose a task to append to — press Tab to browse")
        XCTAssertEqual(model.pickerOperatorContinuationKeys, [])
        XCTAssertEqual(model.picker?.replacementRange, CaptureRange(start: 16, end: 17))
    }

    func testLaterItemProseTerminalPreservesReplacementRange() async throws {
        let model = try parentTaskModel()
        let draft = "First item\n\nCalled the bank +"
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.pickerVisible }

        XCTAssertTrue(model.pickerSourceIsParentTask)
        XCTAssertEqual(model.picker?.replacementRange, CaptureRange(start: 28, end: 29))
        XCTAssertEqual(model.pickerOperatorContinuationKeys, [])
        XCTAssertEqual(model.statusText, "Choose a task to append to — press Tab to browse")
    }

    func testPlusTwoDoesNotOpenParentTaskPicker() async throws {
        let model = try parentTaskModel()
        model.plainDraft = "+2"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.plainDraft, "+2")
        XCTAssertNil(model.completionResponse?.picker)
    }

    func testScopedCashOpensNotePicker() async throws {
        let model = try parentTaskModel()
        model.plainDraft = "@cash+"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible }

        if case .parentTask(let context) = model.picker?.source {
            XCTAssertEqual(context.scope, .note)
            XCTAssertEqual(context.noteTarget, "cash.md")
            XCTAssertFalse(context.isLonePlusOperator)
        } else {
            XCTFail("expected parent-task source")
        }
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(model.picker?.candidates.count, 2)
    }

    func testExactIdentifiedScopedTaskSuppressesAutoOpen() async throws {
        let recordURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let model = try parentTaskModel(recordURL: recordURL)
        model.plainDraft = "@cash+goog-exit"
        model.editorTextDidChange(cursorUTF8Offset: 15)
        await waitUntil {
            ((try? String(contentsOf: recordURL)) ?? "").contains(
                "argv=capture-complete --all-tasks --cursor 15 --format json -- @cash+goog-exit"
            )
        }
        try? await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.plainDraft, "@cash+goog-exit")
    }

    func testOlderBobFilePlusStaysInline() async throws {
        let model = try parentTaskModel()
        model.plainDraft = "@file+"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.completionResponse?.context == "task" }
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.completionResponse?.picker, nil)
        XCTAssertEqual(model.completionResponse?.candidates.first?.blockID, "goog-exit")
    }

    func testSelectionShowsChipNotPicker() async throws {
        let model = try parentTaskModel()
        model.plainDraft = "+"
        model.editorSelectionDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerChipVisible }
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.pickerChip?.source.chipLabel, "Select a parent task")
    }

    func testVaultIDAssignmentUsesParentReplacement() async throws {
        let model = try parentTaskModel()
        model.installParentTaskPickerForPreviews(
            candidates: [idlessCandidate()],
            context: vaultContext(),
            draft: "+",
            replacement: CaptureRange(start: 0, end: 1)
        )
        model.acceptPickerRow(id: "mac_inbox|4:bf5e981c", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.submitTaskIDPrompt()
        await waitUntil { !model.taskIDPromptVisible }
        XCTAssertEqual(model.plainDraft, "@mac_inbox+call-bank")
        XCTAssertFalse(model.pickerVisible)
    }

    func testVaultIDAssignmentWithoutParentReplacementAsksToUpdateBob() async throws {
        let model = try parentTaskModel()
        let oldBobRow = CaptureCompletionCandidate(
            replacement: "",
            route: "sase",
            taskRef: "7:446bd057",
            requiresBlockID: true,
            text: "Fix flaky gkeep test",
            blockIDSuggestions: ["fix-flaky-gkeep"]
        )
        model.installParentTaskPickerForPreviews(
            candidates: [oldBobRow],
            context: vaultContext(),
            draft: "+",
            replacement: CaptureRange(start: 0, end: 1)
        )
        model.acceptPickerRow(id: "sase|7:446bd057", submitAfterInsert: false)
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt?.errorMessage != nil }
        XCTAssertEqual(
            model.taskIDPrompt?.errorMessage,
            "This Bob is too old for parent-task picks. Update Bob first."
        )
        XCTAssertEqual(model.plainDraft, "+")
        XCTAssertTrue(model.taskIDPromptVisible)
    }

    func testScopedIDAssignmentInsertsReturnedID() async throws {
        let model = try parentTaskModel()
        let pending = CaptureCompletionCandidate(
            replacement: "",
            route: "cash",
            taskRef: "8:handoff",
            requiresBlockID: true,
            text: "Plan the handoff",
            blockIDSuggestions: ["plan-handoff"]
        )
        model.installParentTaskPickerForPreviews(
            candidates: [pending],
            context: scopedContext(),
            draft: "@cash+",
            replacement: CaptureRange(start: 6, end: 6)
        )
        model.acceptPickerRow(id: "cash|8:handoff", submitAfterInsert: false)
        model.submitTaskIDPrompt()
        await waitUntil { !model.taskIDPromptVisible }
        XCTAssertEqual(model.plainDraft, "@cash+plan-handoff")
    }

    func testChangedDraftAfterIDAssignmentKeepsPrompt() async throws {
        let model = try parentTaskModel()
        model.installParentTaskPickerForPreviews(
            candidates: [idlessCandidate()],
            context: vaultContext(),
            draft: "+",
            replacement: CaptureRange(start: 0, end: 1)
        )
        model.acceptPickerRow(id: "mac_inbox|4:bf5e981c", submitAfterInsert: false)
        model.plainDraft = "+changed"
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt?.errorMessage != nil }
        XCTAssertEqual(
            model.taskIDPrompt?.errorMessage,
            "Draft changed. Return to the task list and choose again."
        )
        XCTAssertEqual(model.plainDraft, "+changed")
    }

    private func parentTaskModel(recordURL: URL? = nil) throws -> CapturePanelModel {
        let url = recordURL ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": url.path,
                ]
            ),
            debounceNanoseconds: 5_000_000
        )
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = ""
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
