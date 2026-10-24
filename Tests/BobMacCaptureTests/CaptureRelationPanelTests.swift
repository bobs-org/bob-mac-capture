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
                    replacement: "",
                    disabledReason: "label contains a forbidden character"
                )
            ],
            suggestionAuthoredLabel: "a (b)"
        )
        XCTAssertFalse(model.relationLabelPromptCanSubmit)
        XCTAssertNil(model.relationLabelInsertsText)
        model.submitRelationLabelPrompt()
        XCTAssertNotNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertEqual(
            model.relationLabelPrompt?.errorMessage,
            "label contains a forbidden character"
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

    func testRelationCardNavigationSelectsByKeyWithoutChangingQuery() {
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
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "follow-up of")
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "")
        model.cycleRelationLabelSuggestionForward()
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "see")
        model.cycleRelationLabelSuggestionBackward()
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "follow-up of")
        model.acceptRelationLabelSuggestion()
        XCTAssertNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|\"follow-up of\"")
    }

    func testRelationCardNavigationWrapsThroughTheField() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            suggestions: [
                suggestionCandidate(label: "inspired by", count: 3),
                suggestionCandidate(label: "implements", count: 2),
            ]
        )
        model.cycleRelationLabelSuggestionForward()
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "inspired by")
        model.cycleRelationLabelSuggestionForward()
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "implements")
        model.cycleRelationLabelSuggestionForward()
        XCTAssertNil(model.relationLabelPrompt?.selectedKey)
        model.cycleRelationLabelSuggestionBackward()
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "implements")
    }

    func testRelationCardTabWithoutSelectionAcceptsTheTopMatch() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            suggestions: [
                suggestionCandidate(label: "inspired by", count: 3),
                suggestionCandidate(label: "implements", count: 2),
            ]
        )
        model.acceptRelationLabelSuggestion()
        XCTAssertNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|\"inspired by\"")
    }

    func testRelationCardTabWithoutMatchKeepsCardOpenAndShowsHint() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "missing",
            suggestions: [suggestionCandidate(label: "inspired by", count: 3)]
        )
        model.acceptRelationLabelSuggestion()
        XCTAssertTrue(model.relationLabelPromptVisible)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertEqual(
            model.relationLabelPrompt?.errorMessage,
            "No matching labels · type a relation name"
        )
    }

    func testRelationCardSlowAndFastNavigationChooseTheSameKey() async {
        func makeModel() -> CapturePanelModel {
            let model = CapturePanelModel()
            model.installRelationLabelPromptForPreviews(
                suggestions: [
                    suggestionCandidate(label: "inspired by", count: 3),
                    suggestionCandidate(label: "implements", count: 2),
                    suggestionCandidate(label: "duplicate of", count: 1),
                ]
            )
            return model
        }
        let fast = makeModel()
        let slow = makeModel()
        for _ in 0..<2 {
            fast.cycleRelationLabelSuggestionForward()
        }
        for _ in 0..<2 {
            slow.cycleRelationLabelSuggestionForward()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertEqual(fast.relationLabelPrompt?.selectedKey, "implements")
        XCTAssertEqual(slow.relationLabelPrompt?.selectedKey, fast.relationLabelPrompt?.selectedKey)
        XCTAssertEqual(slow.relationLabelPrompt?.authoredLabel, "")
    }

    func testRelationCardFiltersAndRanksCatalogLocally() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "imple",
            suggestions: [
                suggestionCandidate(label: "Alpha implements", count: 1),
                suggestionCandidate(label: "Implement this", count: 2),
                suggestionCandidate(label: "imPlement safely", count: 3),
                CaptureCompletionCandidate(
                    replacement: "|hidden label",
                    label: "hidden label",
                    count: 10,
                    hidden: true
                ),
            ]
        )
        XCTAssertEqual(
            model.relationLabelPromptRows.compactMap(\.label),
            ["Implement this", "imPlement safely", "Alpha implements"]
        )
        model.updateRelationLabelPromptLabel(" IM  PLE ")
        XCTAssertNil(model.relationLabelPrompt?.selectedKey)
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, " IM  PLE ")
        XCTAssertEqual(
            model.relationLabelPromptRows.compactMap(\.label),
            ["Implement this", "imPlement safely", "Alpha implements"]
        )
    }

    func testRelationCardCatalogRefreshKeepsSelectionByKey() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            suggestions: [
                suggestionCandidate(label: "inspired by", count: 3),
                suggestionCandidate(label: "implements", count: 2),
            ]
        )
        model.selectRelationLabelSuggestion(key: "implements")
        XCTAssertTrue(
            model.applyRelationLabelCatalog(
                relationLabelResponse(
                    query: "",
                    candidates: [
                        suggestionCandidate(label: "implements", count: 2),
                        suggestionCandidate(label: "inspired by", count: 3),
                    ]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target"
            )
        )
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "implements")
        XCTAssertTrue(
            model.applyRelationLabelCatalog(
                relationLabelResponse(
                    query: "",
                    candidates: [suggestionCandidate(label: "inspired by", count: 3)]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target"
            )
        )
        XCTAssertNil(model.relationLabelPrompt?.selectedKey)
    }

    func testRelationCardFakeBobCatalogDoesNotCollapseDuringNavigation() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("relation-card-\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: recordURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: recordURL) }

        let model = CapturePanelModel(
            processClient: try relationLabelClient(chooser: true, recordPath: recordURL.path)
        )
        model.installRelationLabelPromptForPreviews()
        await waitUntil { model.relationLabelPrompt?.catalogLoaded == true }
        XCTAssertEqual(
            model.relationLabelPromptRows.compactMap(\.label),
            ["inspired by", "implements", "duplicate of"]
        )

        model.cycleRelationLabelSuggestionForward()
        model.cycleRelationLabelSuggestionForward()
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "implements")
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "")
        let recorded = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertEqual(recorded.components(separatedBy: "argv=capture-complete").count - 1, 1)

        model.acceptRelationLabelSuggestion()
        XCTAssertNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|implements")
    }

    func testRelationCardKeysNavigateAndAccept() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(relationLabelPromptVisible: true)
        func event(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )!
        }
        XCTAssertEqual(router.command(for: event(45, modifiers: .control), context: context), .cycleRelationLabelSuggestionForward)
        XCTAssertEqual(router.command(for: event(125), context: context), .cycleRelationLabelSuggestionForward)
        XCTAssertEqual(router.command(for: event(35, modifiers: .control), context: context), .cycleRelationLabelSuggestionBackward)
        XCTAssertEqual(router.command(for: event(126), context: context), .cycleRelationLabelSuggestionBackward)
        XCTAssertEqual(router.command(for: event(48), context: context), .acceptRelationLabelSuggestion)
        XCTAssertEqual(router.command(for: event(48, modifiers: .shift), context: context), .consumeKey)
        XCTAssertEqual(router.command(for: event(36), context: context), .submitRelationLabelPrompt)
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

    private func relationLabelClient(
        delaySeconds: String? = nil,
        chooser: Bool = false,
        recordPath: String? = nil
    ) throws -> BobProcessClient {
        var environment = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        if let delaySeconds {
            environment["FAKE_BOB_DELAY_SECONDS"] = delaySeconds
        }
        if chooser {
            environment["FAKE_BOB_RELATION_LABEL_CHOOSER"] = "1"
        }
        if let recordPath {
            environment["FAKE_BOB_RECORD_PATH"] = recordPath
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
    /// response arrives. The stale `|old` row must never commit; bob's later
    /// typed `|new` is the only insertion.
    func testRelationLabelSubmitCommitsAuthoredLabelWhileResponsePending() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "new",
            suggestions: [
                typedCandidate(label: "old", replacement: "|old"),
                suggestionCandidate(label: "follow-up of", count: 4),
            ],
            suggestionAuthoredLabel: "old",
            pendingSubmit: true
        )
        XCTAssertNil(model.relationLabelInsertsText)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertTrue(
            model.applyRelationLabelSuggestions(
                relationLabelResponse(
                    query: "new",
                    candidates: [typedCandidate(label: "new", replacement: "|new")]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: "new"
            )
        )
        XCTAssertNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|new")
    }

    /// Immediate Return before any response: the card stays open until bob
    /// supplies a typed row, then that replacement commits.
    func testRelationLabelSubmitWithNoSuggestionsCommitsAuthoredLabel() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "new",
            pendingSubmit: true
        )
        XCTAssertNotNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertTrue(
            model.applyRelationLabelSuggestions(
                relationLabelResponse(
                    query: "new",
                    candidates: [typedCandidate(label: "new", replacement: "|new")]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: "new"
            )
        )
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
    /// the stale `Inserts` line and a later typed row for `new` commits `|new`.
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
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertTrue(
            model.applyRelationLabelSuggestions(
                relationLabelResponse(
                    query: "new",
                    candidates: [typedCandidate(label: "new", replacement: "|new")]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: "new"
            )
        )
        model.submitRelationLabelPrompt()
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|new")
    }

    /// A delayed response for a previous request is dropped: rows and tag
    /// stay where the current input left them.
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
        model.updateRelationLabelPromptLabel("new")
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
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
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

    /// Bob's typed row is the replacement source, including collapsed
    /// whitespace and a trailing colon.
    func testRelationLabelNormalizedWhitespaceUsesBobReplacement() {
        let model = CapturePanelModel()
        let authored = "  follow-up   of: "
        model.installRelationLabelPromptForPreviews(
            authoredLabel: authored,
            pendingSubmit: true
        )
        XCTAssertTrue(
            model.applyRelationLabelSuggestions(
                relationLabelResponse(
                    query: authored,
                    candidates: [
                        typedCandidate(
                            label: "follow-up of",
                            replacement: "|\"follow-up of\""
                        )
                    ]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: authored
            )
        )
        XCTAssertNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|\"follow-up of\"")
    }

    /// Empty replacement on a disabled typed row refuses and leaves the
    /// authored input visible.
    func testRelationLabelDisabledEmptyReplacementRefuses() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "a (b)",
            pendingSubmit: true
        )
        XCTAssertTrue(
            model.applyRelationLabelSuggestions(
                relationLabelResponse(
                    query: "a (b)",
                    candidates: [
                        typedCandidate(
                            label: "a (b)",
                            replacement: "",
                            disabledReason: "label contains a forbidden character"
                        )
                    ]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: "a (b)"
            )
        )
        XCTAssertNotNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertEqual(
            model.relationLabelPrompt?.errorMessage,
            "label contains a forbidden character"
        )
        XCTAssertEqual(model.relationLabelPrompt?.pendingSubmit, false)
    }

    func testRelationLabelTooLongUsesBobDisabledReason() {
        let model = CapturePanelModel()
        let authored = String(repeating: "a", count: 41)
        model.installRelationLabelPromptForPreviews(
            authoredLabel: authored,
            pendingSubmit: true
        )
        XCTAssertTrue(
            model.applyRelationLabelSuggestions(
                relationLabelResponse(
                    query: authored,
                    candidates: [
                        typedCandidate(
                            label: authored,
                            replacement: "",
                            disabledReason: "label can't exceed 40 characters"
                        )
                    ]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: authored
            )
        )
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertEqual(
            model.relationLabelPrompt?.errorMessage,
            "label can't exceed 40 characters"
        )
    }

    func testRelationLabelEmptyAfterCollapseUsesBobDisabledReason() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: ":",
            pendingSubmit: true
        )
        XCTAssertTrue(
            model.applyRelationLabelSuggestions(
                relationLabelResponse(
                    query: ":",
                    candidates: [
                        typedCandidate(
                            label: "",
                            replacement: "",
                            disabledReason: "label can't be empty"
                        )
                    ]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: ":"
            )
        )
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertEqual(
            model.relationLabelPrompt?.errorMessage,
            "label can't be empty"
        )
    }

    /// Delayed response with an immediate Return: the card stays open until
    /// bob's typed `|new` lands, and that is the only insertion.
    func testRelationLabelImmediateReturnBeatsDelayedResponse() async throws {
        let model = CapturePanelModel(
            processClient: try relationLabelClient(delaySeconds: "1"),
            debounceNanoseconds: 9_000_000_000
        )
        model.installRelationLabelPromptForPreviews(authoredLabel: "old")
        model.updateRelationLabelPromptLabel("new")
        model.submitRelationLabelPrompt()
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertNotNil(model.relationLabelPrompt)
        XCTAssertEqual(model.relationLabelPrompt?.pendingSubmit, true)
        await waitUntil { model.relationLabelPrompt == nil }
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

    /// Editing after Return cancels the pending submit, so a late `|new`
    /// must not insert.
    func testRelationLabelEditAfterReturnCancelsPendingSubmit() async throws {
        let model = CapturePanelModel(
            processClient: try relationLabelClient(delaySeconds: "1"),
            debounceNanoseconds: 9_000_000_000
        )
        model.installRelationLabelPromptForPreviews(authoredLabel: "old")
        model.updateRelationLabelPromptLabel("new")
        model.submitRelationLabelPrompt()
        XCTAssertEqual(model.relationLabelPrompt?.pendingSubmit, true)
        model.updateRelationLabelPromptLabel("newer")
        XCTAssertEqual(model.relationLabelPrompt?.pendingSubmit, false)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertNotNil(model.relationLabelPrompt)
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "newer")
    }

    func testRelationLabelDismissThenReopenDoesNotInsertStaleLabel() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "new",
            pendingSubmit: true
        )
        model.cancelRelationLabelPrompt()
        XCTAssertFalse(model.relationLabelPromptVisible)
        XCTAssertFalse(
            model.applyRelationLabelSuggestions(
                relationLabelResponse(
                    query: "new",
                    candidates: [typedCandidate(label: "new", replacement: "|new")]
                ),
                generation: 0,
                draftSnapshot: "New task ~tasks:target",
                authoredLabel: "new"
            )
        )
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        model.installRelationLabelPromptForPreviews(authoredLabel: "new")
        XCTAssertEqual(model.relationLabelPrompt?.pendingSubmit, false)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
    }

    func testRelationLabelRepeatedReturnDoesNotSynthesizeWhilePending() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(authoredLabel: "new")
        model.submitRelationLabelPrompt()
        model.submitRelationLabelPrompt()
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target")
        XCTAssertNotNil(model.relationLabelPrompt)
        XCTAssertEqual(
            model.relationLabelPrompt?.errorMessage,
            "Bob is not resolved. Check Settings and Recheck Bob."
        )
    }
}
