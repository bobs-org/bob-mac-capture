import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Dependency picker panel wiring: accept, owner gate, ID prompt, keys, ranges.
@MainActor
final class CaptureDependencyPanelTests: XCTestCase {
    private func identifiedCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "&cash:budget",
            taskRef: "12:cccc3333",
            blockID: "budget",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Confirm grocery budget",
            section: "Errands",
            group: "open",
            notePath: "cash.md",
            locator: "cash"
        )
    }

    private func idlessCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "1:dddd4444",
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Todo",
            text: "Call the bank",
            blockIDSuggestions: ["call-bank"],
            group: "open",
            notePath: "cash.md",
            locator: "cash"
        )
    }

    private func alreadyCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "&cash:budget",
            taskRef: "12:cccc3333",
            blockID: "budget",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            text: "Confirm grocery budget",
            group: "open",
            notePath: "cash.md",
            locator: "cash",
            alreadyDependency: true
        )
    }

    private func blockedCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "*job:cleanup",
            taskRef: "4:aaaa1111",
            blockID: "cleanup",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Clean up",
            section: "Tasks",
            group: "open",
            notePath: "job.md",
            locator: "job"
        )
    }

    private func blockedIDlessCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "3:fe1ef85f",
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Todo",
            text: "Call the bank",
            blockIDSuggestions: ["call-bank"],
            group: "open",
            notePath: "job.md",
            locator: "job"
        )
    }

    private func installTerminalPicker(owner: DependencyOwner? = DependencyOwner(kind: "new_task")) -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installDependencyPickerForPreviews(
            candidates: [identifiedCandidate(), idlessCandidate()],
            filter: "",
            draft: "Buy Groceries! &",
            replacement: CaptureRange(start: 15, end: 16),
            owner: owner
        )
        return model
    }

    private func installBlocksPicker() -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installBlockedTaskPickerForPreviews(
            candidates: [blockedCandidate(), blockedIDlessCandidate()],
            filter: "",
            draft: "@mac_inbox+ask-kelly *",
            replacement: CaptureRange(start: 21, end: 22),
            owner: DependencyOwner(
                kind: "existing_task",
                route: "mac_inbox",
                blockID: "ask-kelly",
                text: "Ask Kelly",
                notePath: "mac_inbox.md",
                statusSymbol: " ",
                statusName: "Todo"
            )
        )
        return model
    }

    func testAcceptInsertsReplacementWithTrailingSpaceAtTerminal() {
        let model = installTerminalPicker()
        XCTAssertTrue(model.pickerVisible)
        model.acceptPickerRow(id: "cash.md|12:cccc3333", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "Buy Groceries! &cash:budget ")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 28)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Inserted &cash:budget ")
    }

    func testAcceptMidDraftPreservesSuffixWhitespace() {
        let model = CapturePanelModel()
        model.installDependencyPickerForPreviews(
            candidates: [identifiedCandidate()],
            filter: "",
            draft: "Buy Groceries! &cash @home",
            replacement: CaptureRange(start: 15, end: 20),
            owner: DependencyOwner(kind: "new_task")
        )
        model.acceptPickerRow(id: "cash.md|12:cccc3333", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "Buy Groceries! &cash:budget @home")
        XCTAssertFalse(model.pickerVisible)
    }

    func testAcceptAlreadyAddedChangesNothing() {
        let model = CapturePanelModel()
        model.installDependencyPickerForPreviews(
            candidates: [alreadyCandidate()],
            filter: "",
            draft: "Buy Groceries! &",
            replacement: CaptureRange(start: 15, end: 16),
            owner: DependencyOwner(kind: "new_task")
        )
        model.acceptPickerRow(id: "cash.md|12:cccc3333", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "Buy Groceries! &")
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Already added")
    }

    func testOwnerlessCommandReturnKeepsDraftOpen() {
        let model = installTerminalPicker(owner: nil)
        model.acceptPickerRow(id: "cash.md|12:cccc3333", submitAfterInsert: true)
        XCTAssertEqual(model.plainDraft, "Buy Groceries! &cash:budget ")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Add task text or @note+id, then capture")
    }

    func testShiftAcceptIsConsumedForDependency() {
        let model = installTerminalPicker()
        model.acceptPickerRowAndStart(id: "cash.md|12:cccc3333")
        XCTAssertEqual(model.plainDraft, "Buy Groceries! &")
        XCTAssertTrue(model.pickerVisible)
    }

    func testAcceptIdlessOpensDependencyPrompt() {
        let model = installTerminalPicker()
        model.acceptPickerRow(id: "cash.md|1:dddd4444", submitAfterInsert: false)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsDependency)
        XCTAssertFalse(model.taskIDPromptIsTaskLink)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "call-bank")
    }

    func testEscapePromptReturnsToDependencyPicker() {
        let model = installTerminalPicker()
        model.acceptPickerRow(id: "cash.md|1:dddd4444", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.cancelTaskIDPrompt()
        XCTAssertFalse(model.taskIDPromptVisible)
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsDependency)
        XCTAssertEqual(model.picker?.dependencyOwner?.kind, "new_task")
    }

    func testMarkerHighlightCoversSigil() {
        let range = CapturePanelModel.pickerMarkerHighlightRange(
            source: .dependency,
            replacementRange: CaptureRange(start: 15, end: 20),
            markerRange: nil
        )
        XCTAssertEqual(range, CaptureRange(start: 15, end: 20))
    }

    func testBlocksPickerInsertsStarReplacement() {
        let model = installBlocksPicker()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsBlockedTask)
        model.acceptPickerRow(id: "job.md|4:aaaa1111", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "@mac_inbox+ask-kelly *job:cleanup ")
        XCTAssertEqual(model.statusText, "Inserted *job:cleanup ")
        XCTAssertFalse(model.pickerVisible)
    }

    func testBlocksPickerIDlessPromptReturnsToBlocksPicker() {
        let model = installBlocksPicker()
        model.acceptPickerRow(id: "job.md|3:fe1ef85f", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsDependency)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "call-bank")
        model.cancelTaskIDPrompt()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsBlockedTask)
    }

    func testRemoveBlocksPickerTriggerDeletesStarToken() {
        let model = installBlocksPicker()
        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "@mac_inbox+ask-kelly ")
        XCTAssertFalse(model.pickerVisible)
    }

    func testBlocksIDAssignmentSplicesBobReplacement() async throws {
        let model = try liveModel()
        model.installBlockedTaskPickerForPreviews(
            candidates: [blockedIDlessCandidate()],
            filter: "",
            draft: "Ask Kelly *",
            replacement: CaptureRange(start: 10, end: 11),
            owner: DependencyOwner(kind: "new_task")
        )
        model.acceptPickerRow(id: "job.md|3:fe1ef85f", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "call-bank")

        model.submitTaskIDPrompt()
        await waitUntil { !model.taskIDPromptVisible }
        XCTAssertEqual(model.plainDraft, "Ask Kelly *job:call-bank")
    }

    func testOldBobBlocksIDAssignmentShowsExactUpdateMessage() async throws {
        let model = try liveModel()
        model.installBlockedTaskPickerForPreviews(
            candidates: [blockedIDlessCandidate()],
            filter: "",
            draft: "Ask Kelly *",
            replacement: CaptureRange(start: 10, end: 11),
            owner: DependencyOwner(kind: "new_task")
        )
        model.acceptPickerRow(id: "job.md|3:fe1ef85f", submitAfterInsert: false)
        model.updateTaskIDPromptBlockID("call-bank-old")
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt?.errorMessage != nil }

        XCTAssertEqual(
            model.taskIDPrompt?.errorMessage,
            "This Bob is too old for blocked-task picks. Update Bob first."
        )
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertEqual(model.plainDraft, "Ask Kelly *")
    }

    func testRouterShiftReturnConsumedForDependency() {
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

    func testDependencyTargetHintIsCalmAndSkipsDryRun() async throws {
        let model = try liveModel()
        let draft = "&foo:bar "
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil {
            model.statusText ==
                "⛓ What depends on \u{201C}foo:bar\u{201D}? Type a new task, or + for an existing one."
        }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.previewState, .idle)
        XCTAssertFalse(model.pickerVisible)
    }

    func testBlocksTargetHintIsCalm() async throws {
        let model = try liveModel()
        let draft = "*job:cleanup "
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil {
            model.statusText ==
                "🧱 What blocks \u{201C}job:cleanup\u{201D}? Type a new task, or + for an existing one"
        }
        XCTAssertNil(model.errorMessage)
        XCTAssertEqual(model.previewState, .idle)
    }

    func testExistingOwnerCompleteFixtureGroupsThisNote() throws {
        let data = try Data(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Fixtures", isDirectory: true)
                .appendingPathComponent("task-dependency-complete-body-exercise.json")
        )
        let decoded = try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)
        XCTAssertEqual(decoded.owner?.text, "Exercise")
        XCTAssertEqual(decoded.owner?.notePath, "body.md")
        let presentation = DependencyPickerIndex(candidates: decoded.candidates).presentation(filter: "")
        XCTAssertEqual(presentation.sections.first?.kind, .thisNote)
        XCTAssertEqual(presentation.sections.first?.title, "This note")
    }

    func testRouterTabCyclesInDependencyPrompt() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            taskIDPromptVisible: true,
            taskIDPromptIsDependency: true
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

    func testRemovePickerTriggerDeletesAmpToken() {
        let model = installTerminalPicker()
        XCTAssertTrue(model.pickerVisible)
        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "Buy Groceries! ")
        XCTAssertFalse(model.pickerVisible)
    }

    private func relationCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "~tasks:target",
            taskRef: "1:aaaa1111",
            blockID: "target",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Target",
            group: "open",
            notePath: "tasks.md",
            locator: "tasks"
        )
    }

    private func relationFromCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "~~tasks:source",
            taskRef: "2:bbbb2222",
            blockID: "source",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Source",
            group: "open",
            notePath: "tasks.md",
            locator: "tasks"
        )
    }

    private func relationIDlessCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "6:d9780564",
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Todo",
            text: "Idless source",
            blockIDSuggestions: ["idless-source"],
            group: "open",
            notePath: "tasks.md",
            locator: "tasks"
        )
    }

    private func installRelationToPicker() -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installRelationPickerForPreviews(
            candidates: [relationCandidate(), relationIDlessCandidate()],
            filter: "",
            draft: "New task ~",
            replacement: CaptureRange(start: 9, end: 10),
            owner: DependencyOwner(kind: "new_task", text: "New task"),
            direction: .linksTo
        )
        return model
    }

    private func installRelationFromPicker() -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installRelationPickerForPreviews(
            candidates: [relationFromCandidate()],
            filter: "",
            draft: "New task ~~",
            replacement: CaptureRange(start: 9, end: 11),
            owner: DependencyOwner(kind: "new_task", text: "New task"),
            direction: .linkedFrom
        )
        return model
    }

    func testRelationPickerInsertsTildeReplacement() {
        let model = installRelationToPicker()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsRelation)
        XCTAssertEqual(model.pickerOperatorContinuationKeys, ["~"])
        model.acceptPickerRow(id: "tasks.md|1:aaaa1111", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target ")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Inserted ~tasks:target ")
    }

    func testRelationFromPickerInsertsDoubleTildeReplacement() {
        let model = installRelationFromPicker()
        XCTAssertEqual(model.picker?.source, .linkedFrom)
        model.acceptPickerRow(id: "tasks.md|2:bbbb2222", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "New task ~~tasks:source ")
        XCTAssertEqual(model.statusText, "Inserted ~~tasks:source ")
    }

    func testRelationLiveFlipKeepsPickerOpen() async throws {
        let model = try liveModel()
        model.installRelationPickerForPreviews(
            candidates: [relationCandidate()],
            filter: "",
            draft: "New task ~",
            replacement: CaptureRange(start: 9, end: 10),
            owner: DependencyOwner(kind: "new_task", text: "New task"),
            direction: .linksTo
        )
        XCTAssertEqual(model.picker?.source, .linksTo)
        model.continuePickerOperator("~")
        XCTAssertEqual(model.plainDraft, "New task ~~")
        XCTAssertTrue(model.pickerVisible)
        await waitUntil { model.picker?.source == .linkedFrom }
        XCTAssertEqual(model.picker?.filterText, "")
        XCTAssertTrue(model.pickerVisible)
    }

    func testRelationBackspaceOnLinkedFromFlipsBack() async throws {
        let model = try liveModel()
        model.installRelationPickerForPreviews(
            candidates: [relationFromCandidate()],
            filter: "",
            draft: "New task ~~",
            replacement: CaptureRange(start: 9, end: 11),
            owner: DependencyOwner(kind: "new_task", text: "New task"),
            direction: .linkedFrom
        )
        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "New task ~")
        XCTAssertTrue(model.pickerVisible)
        await waitUntil { model.picker?.source == .linksTo }
    }

    func testRelationBackspaceOnLinksToRemovesToken() {
        let model = installRelationToPicker()
        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "New task ")
        XCTAssertFalse(model.pickerVisible)
    }

    func testRelationIdlessOpensPrompt() {
        let model = installRelationToPicker()
        model.acceptPickerRow(id: "tasks.md|6:d9780564", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsDependency)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "idless-source")
        model.cancelTaskIDPrompt()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsRelation)
    }

    func testRelationIDAssignmentSplicesBobReplacement() async throws {
        let model = try liveModel()
        model.installRelationPickerForPreviews(
            candidates: [relationIDlessCandidate()],
            filter: "",
            draft: "New task ~",
            replacement: CaptureRange(start: 9, end: 10),
            owner: DependencyOwner(kind: "new_task", text: "New task"),
            direction: .linksTo
        )
        model.acceptPickerRow(id: "tasks.md|6:d9780564", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.submitTaskIDPrompt()
        await waitUntil { !model.taskIDPromptVisible }
        XCTAssertEqual(model.plainDraft, "New task ~tasks:idless-source")
    }

    func testOldBobRelationIDAssignmentShowsExactUpdateMessage() async throws {
        let model = try liveModel()
        model.installRelationPickerForPreviews(
            candidates: [relationIDlessCandidate()],
            filter: "",
            draft: "New task ~",
            replacement: CaptureRange(start: 9, end: 10),
            owner: DependencyOwner(kind: "new_task", text: "New task"),
            direction: .linksTo
        )
        model.acceptPickerRow(id: "tasks.md|6:d9780564", submitAfterInsert: false)
        model.updateTaskIDPromptBlockID("idless-old")
        model.submitTaskIDPrompt()
        await waitUntil { model.taskIDPrompt?.errorMessage != nil }
        XCTAssertEqual(
            model.taskIDPrompt?.errorMessage,
            "This Bob is too old for ~ links. Update Bob first."
        )
        XCTAssertEqual(model.plainDraft, "New task ~")
    }

    func testRelationMarkerHighlightCoversDoubleTilde() {
        let range = CapturePanelModel.pickerMarkerHighlightRange(
            source: .linkedFrom,
            replacementRange: CaptureRange(start: 9, end: 11),
            markerRange: nil
        )
        XCTAssertEqual(range, CaptureRange(start: 9, end: 11))
    }

    func testRouterTildeContinuesRelationPicker() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerFilterIsEmpty: true,
            pickerOperatorContinuationKeys: ["~"]
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 50, modifiers: .shift, characters: "~"), context: context),
            .continuePickerOperator("~")
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .shift), context: context),
            .consumeKey
        )
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

    private func liveModel() throws -> CapturePanelModel {
        CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
            ),
            debounceNanoseconds: 5_000_000
        )
    }

    private func fakeBobPath() throws -> String {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot.appendingPathComponent("Tests/Fixtures/fake-bob").path
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
}
