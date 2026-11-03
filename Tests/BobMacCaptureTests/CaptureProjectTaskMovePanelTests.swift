import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Move-picker panel wiring (MM1): Shift-Return chaining, Escape calm
/// status, stale-draft guards, accept-vs-submit, one undo per accept, and
/// the ID-less Add block ID flow.
@MainActor
final class CaptureProjectTaskMovePanelTests: XCTestCase {
    private func identifiedCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "equity-docs",
            route: "cash",
            taskRef: "6:93f5563b",
            blockID: "equity-docs",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            text: "Collect the equity paperwork",
            section: "Tasks",
            consequence: "Moves into cash_goog_exit.md"
        )
    }

    private func idlessCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            route: "cash",
            taskRef: "10:31f90b6e",
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Todo",
            text: "Plan the handoff",
            section: "Tasks",
            blockIDSuggestions: ["plan-handoff"],
            consequence: "Needs an ID first · ⊕ ^plan-handoff · Moves into cash_goog_exit.md"
        )
    }

    private func moveContext() -> ProjectTaskMovePickerContext {
        ProjectTaskMovePickerContext(
            scopeToken: "^",
            noteTarget: "cash.md",
            destination: "cash_goog_exit.md",
            continuation: "\n- ^",
            markerRange: CaptureRange(start: 42, end: 43),
            triggerRemovalRange: CaptureRange(start: 42, end: 43),
            openCount: 7
        )
    }

    private func installMovePicker(
        draft: String = "Finish the exit packet @cash^goog-exit@\n- ^",
        replacement: CaptureRange = CaptureRange(start: 43, end: 43)
    ) -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installProjectTaskMovePickerForPreviews(
            candidates: [identifiedCandidate(), idlessCandidate()],
            context: moveContext(),
            draft: draft,
            replacement: replacement
        )
        return model
    }

    func testReturnInsertsIDOnly() {
        let model = installMovePicker()
        XCTAssertTrue(model.pickerVisible)
        model.acceptPickerRow(id: "cash|6:93f5563b", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "Finish the exit packet @cash^goog-exit@\n- ^equity-docs")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Inserted equity-docs")
    }

    func testShiftReturnChainsWithContinuation() {
        let model = installMovePicker()
        model.acceptPickerRowAndContinue(id: "cash|6:93f5563b")
        XCTAssertEqual(
            model.plainDraft,
            "Finish the exit packet @cash^goog-exit@\n- ^equity-docs\n- ^"
        )
    }

    func testEscapeLeavesSigilWithCalmStatus() {
        let model = installMovePicker()
        model.cancelPicker()
        XCTAssertEqual(model.plainDraft, "Finish the exit packet @cash^goog-exit@\n- ^")
        XCTAssertEqual(
            model.statusText,
            "Pick a task to move from cash.md, or delete the ^"
        )
    }

    func testAcceptIdlessOpensMovePrompt() {
        let model = installMovePicker()
        model.acceptPickerRow(id: "cash|10:31f90b6e", submitAfterInsert: false)
        XCTAssertNotNil(model.taskIDPrompt)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "plan-handoff")
    }

    func testRouterShiftReturnContinuesMove() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerHasSelection: true,
            pickerVisible: true,
            pickerSourceIsProjectTaskMove: true
        )
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\r",
            charactersIgnoringModifiers: "\r",
            isARepeat: false,
            keyCode: 36
        )
        let command = event.flatMap { router.command(for: $0, context: context) }
        XCTAssertEqual(command, .acceptPickerRowAndContinue)
    }

    func testStaleDraftRefusesAccept() {
        let model = installMovePicker()
        model.plainDraft = "Finish the exit packet @work^other@\n- ^"
        model.acceptPickerRow(id: "cash|6:93f5563b", submitAfterInsert: false)
        XCTAssertFalse(model.pickerVisible)
    }
}
