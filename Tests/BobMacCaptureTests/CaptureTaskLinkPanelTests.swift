import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Task Link Picker panel wiring: accept, start, ID-less prompt, keys, and ranges.
@MainActor
final class CaptureTaskLinkPanelTests: XCTestCase {
    private func identifiedCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "@sase:deep-fix",
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
            route: "sase",
            taskRef: "7:446bd057",
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Todo",
            text: "Fix flaky gkeep test",
            section: "Bugs",
            blockIDSuggestions: ["fix-flaky-gkeep", "flaky-gkeep-test"]
        )
    }

    private func installTwoRowPicker(filter: String = "") -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installTaskLinkPickerForPreviews(
            candidates: [identifiedCandidate(), idlessCandidate()],
            filter: filter,
            draft: ":",
            replacement: CaptureRange(start: 0, end: 1)
        )
        return model
    }

    func testAcceptInsertsLinkWithCaretAtEnd() {
        let model = installTwoRowPicker()
        XCTAssertTrue(model.pickerVisible)
        let rowID = "sase|6:41d049f2"
        model.acceptPickerRow(id: rowID, submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "@sase:deep-fix")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 14)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Inserted @sase:deep-fix")
    }

    func testShiftAcceptAppendsEquals() {
        let model = installTwoRowPicker()
        let rowID = "sase|6:41d049f2"
        model.acceptPickerRowAndStart(id: rowID)
        XCTAssertEqual(model.plainDraft, "@sase:deep-fix=")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 15)
        XCTAssertEqual(model.statusText, "Inserted @sase:deep-fix= — starts its session when captured")
    }

    func testAcceptIdlessOpensPromptPrefilled() {
        let model = installTwoRowPicker()
        let rowID = "sase|7:446bd057"
        model.acceptPickerRow(id: rowID, submitAfterInsert: false)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsTaskLink)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "fix-flaky-gkeep")
        XCTAssertEqual(model.taskIDPrompt?.linkSuggestions, ["fix-flaky-gkeep", "flaky-gkeep-test"])
    }

    func testTabCyclesSuggestions() {
        let model = installTwoRowPicker()
        model.acceptPickerRow(id: "sase|7:446bd057", submitAfterInsert: false)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "fix-flaky-gkeep")
        model.cycleTaskLinkSuggestion(forward: true)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "flaky-gkeep-test")
        model.cycleTaskLinkSuggestion(forward: true)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "fix-flaky-gkeep")
        model.cycleTaskLinkSuggestion(forward: false)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "flaky-gkeep-test")
    }

    func testEscapePromptReturnsToPickerWithFilter() {
        let model = installTwoRowPicker(filter: "flaky")
        XCTAssertEqual(model.picker?.filterText, "flaky")
        model.acceptPickerRow(id: "sase|7:446bd057", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.cancelTaskIDPrompt()
        XCTAssertFalse(model.taskIDPromptVisible)
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.picker?.filterText, "flaky")
        XCTAssertEqual(model.picker?.selectedRowID, "sase|7:446bd057")
    }

    func testMarkerHighlightCoversSigil() {
        let range = CapturePanelModel.pickerMarkerHighlightRange(
            source: .taskLink,
            replacementRange: CaptureRange(start: 0, end: 4),
            markerRange: nil
        )
        XCTAssertEqual(range, CaptureRange(start: 0, end: 4))
    }

    func testRouterShiftReturnMapsOnlyForTaskLink() {
        let router = CaptureKeyCommandRouter()
        let taskLinkContext = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerSourceIsTaskLink: true
        )
        let activeContext = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerSourceIsTaskLink: false
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .shift), context: taskLinkContext),
            .acceptPickerRowAndStart
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .shift), context: activeContext),
            .consumeKey
        )
    }

    func testRouterTabCyclesOnlyInLinkPrompt() {
        let router = CaptureKeyCommandRouter()
        let linkContext = CaptureKeyRoutingContext(
            taskIDPromptVisible: true,
            taskIDPromptIsTaskLink: true
        )
        let parentContext = CaptureKeyRoutingContext(taskIDPromptVisible: true)
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48, modifiers: []), context: linkContext),
            .cycleTaskLinkSuggestionForward
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48, modifiers: .shift), context: linkContext),
            .cycleTaskLinkSuggestionBackward
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48, modifiers: []), context: parentContext),
            .consumeKey
        )
    }

    func testNeedPrecedenceTaskLinkAfterActiveTask() {
        XCTAssertEqual(
            CapturePickerNeed.taskLink.statusText,
            "Pick any open task — press Tab to browse"
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
}
