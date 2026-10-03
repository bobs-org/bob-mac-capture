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
}
