import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Relation-label card and old-Bob capability gate: suggestions, typed row,
/// invalid labels, Escape, and the submit-twice warning.
@MainActor
final class CaptureRelationPanelTests: XCTestCase {
    private func typedCandidate(
        label: String,
        replacement: String,
        disabledReason: String? = nil
    ) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: replacement,
            label: label,
            disabledReason: disabledReason,
            typed: true
        )
    }

    private func suggestionCandidate(label: String, count: Int) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: label.contains(" ") ? "|\"\(label)\"" : "|\(label)",
            label: label,
            count: count
        )
    }

    func testRelationCardShowsSuggestionsAndLiveSentence() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            draft: "New task ~tasks:target",
            tokenRange: CaptureRange(start: 9, end: 22),
            direction: .linksTo,
            ownerText: "New task",
            targetText: "Target",
            authoredLabel: "fol",
            suggestions: [
                typedCandidate(label: "fol", replacement: "|fol"),
                suggestionCandidate(label: "follow-up of", count: 4),
            ]
        )
        XCTAssertTrue(model.relationLabelPromptVisible)
        XCTAssertEqual(model.relationLabelSentence, "“New task” — fol → “Target”")
        XCTAssertEqual(model.relationLabelInsertsText, "Inserts |fol")
        XCTAssertTrue(model.relationLabelPromptCanSubmit)
    }

    func testRelationCardFromDirectionSentence() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            direction: .linkedFrom,
            ownerText: "Write outline",
            targetText: "Ship the sase blog",
            authoredLabel: "next step"
        )
        XCTAssertEqual(
            model.relationLabelSentence,
            "“Ship the sase blog” — next step → “Write outline”"
        )
    }

    func testRelationCardInvalidLabelBlocksSubmit() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "a (b)",
            suggestions: [
                typedCandidate(
                    label: "a (b)",
                    replacement: "|a (b)",
                    disabledReason: "Labels cannot contain parentheses"
                )
            ]
        )
        XCTAssertFalse(model.relationLabelPromptCanSubmit)
        model.submitRelationLabelPrompt()
        XCTAssertNotNil(model.relationLabelPrompt)
        XCTAssertEqual(
            model.relationLabelPrompt?.errorMessage,
            "Labels cannot contain parentheses"
        )
    }

    func testRelationCardEscapeReturnsToPickerWhenStaged() {
        let model = CapturePanelModel()
        let picker = CapturePickerState(
            source: .linksTo,
            draftSnapshot: "New task ~",
            replacementRange: CaptureRange(start: 9, end: 10),
            restoreCursor: 10,
            candidates: [],
            warnings: [],
            filterText: "",
            selectedRowID: nil,
            visibleRowBudget: 5,
            snapshotIsPartial: false
        )
        model.installRelationLabelPromptForPreviews(returnPicker: picker)
        XCTAssertTrue(model.relationLabelPromptVisible)
        model.cancelRelationLabelPrompt()
        XCTAssertFalse(model.relationLabelPromptVisible)
        XCTAssertNotNil(model.picker)
    }

    func testRelationCardEscapeWithoutPickerReturnsToEditor() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews()
        model.cancelRelationLabelPrompt()
        XCTAssertFalse(model.relationLabelPromptVisible)
        XCTAssertNil(model.picker)
    }

    func testRelationCardTabCyclesSuggestions() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [
                typedCandidate(label: "fol", replacement: "|fol"),
                suggestionCandidate(label: "follow-up of", count: 4),
                suggestionCandidate(label: "see", count: 1),
            ]
        )
        model.cycleRelationLabelSuggestionForward()
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "follow-up of")
        model.cycleRelationLabelSuggestionForward()
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "see")
        model.cycleRelationLabelSuggestionBackward()
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "follow-up of")
    }

    func testOldBobCapabilityWarningRequiresTwoSubmits() {
        let model = CapturePanelModel()
        model.installRelationCapabilityForPreviews(draft: "Fix it ~sase:retry", hasGrammar: false)
        XCTAssertEqual(
            model.relationCapabilityWarning,
            "This bob predates ~ links; ~ text would be captured literally · update bob"
        )
        // First submit only shows the warning; it must not dispatch.
        model.submit(openAfterCapture: false)
        XCTAssertEqual(
            model.relationCapabilityWarning,
            "This bob predates ~ links; ~ text would be captured literally · update bob"
        )
    }

    func testNewBobHasNoCapabilityWarning() {
        let model = CapturePanelModel()
        model.installRelationCapabilityForPreviews(draft: "Fix it ~sase:retry", hasGrammar: true)
        XCTAssertNil(model.relationCapabilityWarning)
    }

    func testShiftReturnOpensRelationCard() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerSourceIsRelation: true,
            pickerVisible: true
        )
        // Shift-Return is keyCode 36 with .shift.
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .shift,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 36
        )!
        XCTAssertEqual(router.command(for: event, context: context), .openRelationLabelPrompt)
    }
}
