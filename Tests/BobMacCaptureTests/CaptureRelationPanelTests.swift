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
            ],
            suggestionAuthoredLabel: "fol"
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
            ],
            suggestionAuthoredLabel: "a (b)"
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

    // MARK: - Relation-label race (bob-cli-al)

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

    private func relationLabelClient(delaySeconds: String? = nil) throws -> BobProcessClient {
        var environment = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        if let delaySeconds {
            environment["FAKE_BOB_DELAY_SECONDS"] = delaySeconds
        }
        return BobProcessClient(executablePath: try fakeBobPath(), environment: environment)
    }

    private func relationLabelResponse(
        query: String,
        candidates: [CaptureCompletionCandidate]
    ) -> CaptureCompletionResponse {
        CaptureCompletionResponse(
            ok: true,
            cursor: 27,
            replacement: CaptureRange(start: 22, end: 27),
            context: "relation_label",
            candidates: candidates,
            query: query
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
                XCTFail(
                    "Condition not met before timeout",
                    file: file,
                    line: line
                )
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    /// Harness scenario: typed `old`, changed to `new`, Return before the new
    /// response arrives. The stale `|old` row must never commit.
    func testRelationLabelSubmitCommitsAuthoredLabelWhileResponsePending() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "new",
            suggestions: [
                typedCandidate(label: "old", replacement: "|old"),
                suggestionCandidate(label: "follow-up of", count: 4),
            ],
            suggestionAuthoredLabel: "old"
        )
        XCTAssertNil(model.relationLabelInsertsText)
        model.submitRelationLabelPrompt()
        XCTAssertNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|new")
    }

    /// Immediate Return before any response: with no rows at all, submit
    /// still commits the current input.
    func testRelationLabelSubmitWithNoSuggestionsCommitsAuthoredLabel() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(authoredLabel: "new")
        model.submitRelationLabelPrompt()
        XCTAssertNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|new")
    }

    /// A fresh typed row still wins, with bob's quoted spelling for labels
    /// carrying a space.
    func testRelationLabelSubmitUsesFreshTypedReplacement() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "follow-up of",
            suggestions: [
                typedCandidate(
                    label: "follow-up of",
                    replacement: "|\"follow-up of\""
                ),
                suggestionCandidate(label: "see", count: 1),
            ],
            suggestionAuthoredLabel: "follow-up of"
        )
        XCTAssertEqual(model.relationLabelInsertsText, "Inserts |\"follow-up of\"")
        model.submitRelationLabelPrompt()
        XCTAssertNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|\"follow-up of\"")
    }

    /// Editing the field untags the visible rows: the card stops advertising
    /// the stale `Inserts` line and submit commits the new input.
    func testRelationLabelEditInvalidatesStaleCandidates() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "old",
            suggestions: [typedCandidate(label: "old", replacement: "|old")],
            suggestionAuthoredLabel: "old"
        )
        XCTAssertEqual(model.relationLabelInsertsText, "Inserts |old")
        model.updateRelationLabelPromptLabel("new")
        XCTAssertNil(model.relationLabelInsertsText)
        XCTAssertTrue(model.relationLabelPromptCanSubmit)
        model.submitRelationLabelPrompt()
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|new")
    }

    /// A delayed response for a previous request is dropped: rows and tag
    /// stay where the current input left them. The preview hook stages state
    /// without fetching, so generation 0 is current until the edit below.
    func testRelationLabelStaleGenerationResponseDropped() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(authoredLabel: "")
        let stale = relationLabelResponse(
            query: "",
            candidates: [typedCandidate(label: "old", replacement: "|old")]
        )
        XCTAssertTrue(
            model.applyRelationLabelSuggestions(
                stale,
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: ""
            )
        )
        XCTAssertEqual(model.relationLabelPrompt?.suggestionAuthoredLabel, "")
        model.updateRelationLabelPromptLabel("")
        XCTAssertFalse(
            model.applyRelationLabelSuggestions(
                stale,
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: ""
            )
        )
        XCTAssertEqual(model.relationLabelPrompt?.suggestions, stale.candidates)
        XCTAssertNil(model.relationLabelPrompt?.suggestionAuthoredLabel)
    }

    /// A response for a different label is dropped even when its generation
    /// still matches: the hook never fetches, so generation 0 is current.
    func testRelationLabelMismatchedLabelResponseDropped() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(authoredLabel: "new")
        let other = relationLabelResponse(
            query: "old",
            candidates: [typedCandidate(label: "old", replacement: "|old")]
        )
        XCTAssertFalse(
            model.applyRelationLabelSuggestions(
                other,
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: "old"
            )
        )
        XCTAssertTrue(model.relationLabelPrompt?.suggestions.isEmpty ?? false)
        XCTAssertNil(model.relationLabelPrompt?.suggestionAuthoredLabel)
    }

    /// Local spelling of bob's typed-row replacement: collapse, trailing
    /// colon, quotes for spaces, and nil where bob offers no typed row.
    func testRelationLabelAuthoredReplacementSpelling() {
        XCTAssertEqual(
            CapturePanelModel.relationLabelAuthoredReplacement(for: "new"),
            "|new"
        )
        XCTAssertEqual(
            CapturePanelModel.relationLabelAuthoredReplacement(for: "follow-up of"),
            "|\"follow-up of\""
        )
        XCTAssertEqual(
            CapturePanelModel.relationLabelAuthoredReplacement(for: "  follow-up   of: "),
            "|\"follow-up of\""
        )
        XCTAssertNil(CapturePanelModel.relationLabelAuthoredReplacement(for: ":"))
    }

    /// Delayed response with an immediate Return: the current input commits
    /// and the late arrival changes nothing.
    func testRelationLabelImmediateReturnBeatsDelayedResponse() async throws {
        let model = CapturePanelModel(
            processClient: try relationLabelClient(delaySeconds: "1"),
            debounceNanoseconds: 9_000_000_000
        )
        model.installRelationLabelPromptForPreviews(authoredLabel: "old")
        model.updateRelationLabelPromptLabel("new")
        model.submitRelationLabelPrompt()
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|new")
        XCTAssertNil(model.relationLabelPrompt)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|new")
        XCTAssertNil(model.relationLabelPrompt)
    }

    /// An older response arriving after a newer one is dropped: the current
    /// input's rows win and submit commits them.
    func testRelationLabelOutOfOrderResponseKeepsCurrentLabel() async throws {
        let model = CapturePanelModel(
            processClient: try relationLabelClient(delaySeconds: "2"),
            debounceNanoseconds: 9_000_000_000
        )
        model.installRelationLabelPromptForPreviews(authoredLabel: "old")
        model.updateRelationLabelPromptLabel("old")
        model.setProcessClient(try relationLabelClient())
        model.updateRelationLabelPromptLabel("new")
        await waitUntil { model.relationLabelPrompt?.suggestionAuthoredLabel == "new" }
        XCTAssertEqual(model.relationLabelInsertsText, "Inserts |new")
        model.submitRelationLabelPrompt()
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|new")
        // The delayed older response lands here and must not rewrite the draft.
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|new")
    }
}
