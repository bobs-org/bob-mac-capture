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
            draft: "Ask Kelly *",
            replacement: CaptureRange(start: 10, end: 11),
            owner: DependencyOwner(kind: "existing_task", route: "mac_inbox", blockID: "ask-kelly")
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
        XCTAssertEqual(model.plainDraft, "Ask Kelly *job:cleanup ")
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
        XCTAssertEqual(model.plainDraft, "Ask Kelly ")
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
