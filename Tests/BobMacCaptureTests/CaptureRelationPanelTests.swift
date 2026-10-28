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
        disabledReason: String? = nil,
        key: String? = nil,
        count: Int? = nil,
        existing: Bool? = nil,
        hidden: Bool? = nil,
        hideReplacement: String? = nil
    ) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: replacement,
            label: label,
            disabledReason: disabledReason,
            hidden: hidden ?? false,
            count: count,
            typed: true,
            key: key ?? label.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased(),
            hideReplacement: hideReplacement,
            existing: existing
        )
    }

    private func suggestionCandidate(
        label: String,
        count: Int,
        key: String? = nil,
        inverse: String? = nil
    ) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: label.contains(" ") ? "|\"\(label)\"" : "|\(label)",
            label: label,
            count: count,
            key: key ?? label.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased(),
            inverse: inverse,
            hideReplacement: label.contains(" ") ? "||\"\(label)\"" : "||\(label)"
        )
    }

    private func hiddenInfo(
        key: String,
        name: String? = nil,
        count: Int = 1,
        inverse: String? = nil
    ) -> CaptureRelationLabelInfo {
        let display = name ?? key
        return CaptureRelationLabelInfo(
            key: key,
            name: display,
            count: count,
            hidden: true,
            inverse: inverse,
            replacement: display.contains(" ") ? "|\"\(display)\"" : "|\(display)",
            hideReplacement: display.contains(" ") ? "||\"\(display)\"" : "||\(display)"
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
                    hidden: true,
                    count: 10
                ),
            ]
        )
        XCTAssertEqual(
            model.relationLabelPromptRows.compactMap(\.label),
            ["Implement this", "imPlement safely", "Alpha implements"]
        )
        model.updateRelationLabelPromptLabel("  IMPLE ")
        XCTAssertNil(model.relationLabelPrompt?.selectedKey)
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "  IMPLE ")
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

    /// Ctrl+D with no selection toggles one-off; a typed `|` never enters
    /// the field; Backspace on an empty field turns one-off off; typing a
    /// new query clears ghosts.
    func testRelationCardOneOffTogglePipeAndBackspace() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [suggestionCandidate(label: "implements", count: 2)],
            suggestionAuthoredLabel: ""
        )
        XCTAssertFalse(model.relationLabelPrompt?.oneOff ?? true)
        model.toggleRelationLabelOneOff()
        XCTAssertEqual(model.relationLabelPrompt?.noticeMessage, "Type a label to make it one-off")

        model.updateRelationLabelPromptLabel("prompted|")
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "prompted")
        XCTAssertTrue(model.relationLabelPrompt?.oneOff ?? false)

        XCTAssertFalse(model.relationLabelPromptBackspace())
        model.updateRelationLabelPromptLabel("")
        XCTAssertTrue(model.relationLabelPrompt?.oneOff ?? false)
        XCTAssertTrue(model.relationLabelPromptBackspace())
        XCTAssertFalse(model.relationLabelPrompt?.oneOff ?? true)

        model.relationLabelPrompt?.ghosts["implements"] = true
        model.updateRelationLabelPromptLabel("i")
        XCTAssertTrue(model.relationLabelPrompt?.ghosts.isEmpty ?? false)
    }

    /// One-off on an existing visible label warns amber and inserts the
    /// `||` form; on a hidden label the capsule reads `one-off · hidden`
    /// with a neutral note and no warning.
    func testRelationCardOneOffWarningAndCapsule() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "inspired by",
            suggestions: [
                typedCandidate(
                    label: "inspired by",
                    replacement: "|\"inspired by\"",
                    count: 3,
                    existing: true,
                    hidden: false,
                    hideReplacement: "||\"inspired by\""
                )
            ],
            suggestionAuthoredLabel: "inspired by"
        )
        model.relationLabelPrompt?.oneOff = true
        XCTAssertEqual(model.relationLabelPromptBadgeText, "one-off · 3 links")
        XCTAssertNotNil(model.relationLabelOneOffWarning)
        XCTAssertNil(model.relationLabelAlreadyHiddenNote)
        XCTAssertEqual(model.relationLabelInsertsText, "Inserts ||\"inspired by\"")
        XCTAssertEqual(
            model.relationLabelFooterItems.map(\.keycap),
            ["↩", "⌃D", "esc"]
        )

        model.relationLabelPrompt?.suggestions = [
            typedCandidate(
                label: "duplicate of",
                replacement: "|\"duplicate of\"",
                count: 1,
                existing: true,
                hidden: true,
                hideReplacement: "||\"duplicate of\""
            )
        ]
        XCTAssertEqual(model.relationLabelPromptBadgeText, "one-off · hidden")
        XCTAssertNil(model.relationLabelOneOffWarning)
        XCTAssertNotNil(model.relationLabelAlreadyHiddenNote)
    }

    /// Ctrl+D on a row hides what Return would insert: the row stays as a
    /// ghost, the write runs on the serial pref lane, success refetches
    /// without clearing the ghost, Ctrl+D on the ghost flips it back, and
    /// a new query clears ghosts.
    func testRelationCardHideGhostUndoAndQueryClear() async throws {
        let model = CapturePanelModel(
            processClient: try relationLabelClient(chooser: true)
        )
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [
                suggestionCandidate(label: "implements", count: 2),
                suggestionCandidate(label: "inspired by", count: 3),
            ],
            suggestionAuthoredLabel: ""
        )
        model.relationLabelPrompt?.hiddenCountKnown = true
        model.relationLabelPrompt?.hiddenCount = 1
        model.relationLabelPrompt?.hiddenRows = [hiddenInfo(key: "duplicate of")]
        model.selectRelationLabelSuggestion(key: "implements")
        model.toggleRelationLabelVisibility()
        XCTAssertEqual(model.relationLabelPrompt?.ghosts["implements"], true)
        await waitUntil { model.relationLabelPrompt?.visibilityWriteID == nil }
        XCTAssertEqual(model.statusText, "Hid “implements” from relation suggestions")
        XCTAssertEqual(model.relationLabelPrompt?.ghosts["implements"], true)

        model.toggleRelationLabelVisibility()
        XCTAssertEqual(model.relationLabelPrompt?.ghosts["implements"], false)
        await waitUntil { model.relationLabelPrompt?.visibilityWriteID == nil }

        model.updateRelationLabelPromptLabel("i")
        XCTAssertTrue(model.relationLabelPrompt?.ghosts.isEmpty ?? false)
    }

    /// A failed hide restores the row with bob's message; an older bob
    /// without the `relations` group gets the update hint.
    func testRelationCardHideFailureRestoresGhost() async throws {
        var environment = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        environment["FAKE_BOB_RELATION_LABEL_CHOOSER"] = "1"
        environment["FAKE_BOB_RELATIONS_WRITE_EXIT"] = "1"
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: environment
            )
        )
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [suggestionCandidate(label: "implements", count: 2)],
            suggestionAuthoredLabel: ""
        )
        model.relationLabelPrompt?.hiddenCountKnown = true
        model.relationLabelPrompt?.hiddenCount = 1
        model.selectRelationLabelSuggestion(key: "implements")
        model.toggleRelationLabelVisibility()
        await waitUntil { model.relationLabelPrompt?.visibilityWriteID == nil }
        XCTAssertNil(model.relationLabelPrompt?.ghosts["implements"])
        XCTAssertNotNil(model.relationLabelPrompt?.errorMessage)
    }

    /// Ctrl+H toggles the Hidden section and keeps the query and selection;
    /// an older bob gets the update hint instead.
    func testRelationCardHiddenSectionToggle() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "dup",
            suggestions: [suggestionCandidate(label: "duplicate of", count: 1)],
            suggestionAuthoredLabel: "dup"
        )
        model.toggleRelationLabelHiddenSection()
        XCTAssertEqual(
            model.relationLabelPrompt?.noticeMessage,
            "Update bob to hide relation labels"
        )

        model.relationLabelPrompt?.hiddenCountKnown = true
        model.relationLabelPrompt?.hiddenCount = 1
        model.relationLabelPrompt?.hiddenRows = [hiddenInfo(key: "duplicate of")]
        model.toggleRelationLabelHiddenSection()
        XCTAssertTrue(model.relationLabelPrompt?.showHidden ?? false)
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "dup")
        XCTAssertEqual(
            model.relationLabelHiddenPromptRows.map(\.label),
            ["duplicate of"]
        )
        model.toggleRelationLabelHiddenSection()
        XCTAssertFalse(model.relationLabelPrompt?.showHidden ?? true)
        XCTAssertTrue(model.relationLabelHiddenPromptRows.isEmpty)
    }

    /// Hidden rows accept like any row: Tab walks into the open section and
    /// Return inserts the `|` form, which stays hidden.
    func testRelationCardHiddenRowAcceptsAndStaysHidden() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [suggestionCandidate(label: "implements", count: 2)],
            suggestionAuthoredLabel: ""
        )
        model.relationLabelPrompt?.hiddenCountKnown = true
        model.relationLabelPrompt?.hiddenCount = 1
        model.relationLabelPrompt?.hiddenRows = [hiddenInfo(key: "duplicate of")]
        model.relationLabelPrompt?.showHidden = true
        model.selectRelationLabelSuggestion(key: "duplicate of")
        XCTAssertEqual(model.relationLabelInsertsText, "Inserts |\"duplicate of\"")
        model.acceptRelationLabelSuggestion()
        XCTAssertNil(model.relationLabelPrompt)
        XCTAssertEqual(model.plainDraft, "New task ~tasks:target|\"duplicate of\"")
    }

    /// Router: Ctrl+D toggles visibility (auto-repeat is consumed), Ctrl+H
    /// toggles the Hidden section, and Backspace is claimed only for an
    /// empty one-off field.
    func testRelationCardKeysToggleVisibilityAndHiddenSection() {
        let router = CaptureKeyCommandRouter()
        func event(_ keyCode: UInt16, modifiers: NSEvent.ModifierFlags = [], isRepeat: Bool = false) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifiers,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: isRepeat,
                keyCode: keyCode
            )!
        }
        let context = CaptureKeyRoutingContext(relationLabelPromptVisible: true)
        XCTAssertEqual(
            router.command(for: event(2, modifiers: .control), context: context),
            .toggleRelationLabelVisibility
        )
        XCTAssertEqual(
            router.command(for: event(2, modifiers: .control, isRepeat: true), context: context),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: event(4, modifiers: .control), context: context),
            .toggleRelationLabelHiddenSection
        )
        let emptyOneOff = CaptureKeyRoutingContext(
            relationLabelPromptVisible: true,
            relationLabelPromptFieldIsEmpty: true,
            relationLabelPromptOneOff: true
        )
        XCTAssertEqual(
            router.command(for: event(51), context: emptyOneOff),
            .relationLabelPromptBackspace
        )
        let emptyPlain = CaptureKeyRoutingContext(
            relationLabelPromptVisible: true,
            relationLabelPromptFieldIsEmpty: true
        )
        XCTAssertNil(router.command(for: event(51), context: emptyPlain))
        let fullOneOff = CaptureKeyRoutingContext(
            relationLabelPromptVisible: true,
            relationLabelPromptFieldIsEmpty: false,
            relationLabelPromptOneOff: true
        )
        XCTAssertNil(router.command(for: event(51), context: fullOneOff))
    }

    // MARK: - Relation-label rename mode (Ctrl+R)

    private func renameClient(
        extraEnvironment: [String: String] = [:],
        recordPath: String? = nil
    ) throws -> BobProcessClient {
        var environment = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        environment["FAKE_BOB_RELATION_LABEL_CHOOSER"] = "1"
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        if let recordPath {
            environment["FAKE_BOB_RECORD_PATH"] = recordPath
        }
        return BobProcessClient(executablePath: try fakeBobPath(), environment: environment)
    }

    private func renameRecordURL() throws -> URL {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("relation-rename-\(UUID().uuidString).log")
        _ = FileManager.default.createFile(atPath: recordURL.path, contents: Data())
        return recordURL
    }

    /// Ctrl+R opens rename mode for the selected row with OLD prefilled,
    /// renders the dry-run counts line, and Escape returns to choose mode
    /// with the query and selection kept.
    func testRelationCardRenameOpensForSelectedRowWithPreview() async throws {
        let model = CapturePanelModel(
            processClient: try renameClient()
        )
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [suggestionCandidate(label: "inspired by", count: 3)],
            suggestionAuthoredLabel: ""
        )
        model.selectRelationLabelSuggestion(key: "inspired by")
        model.openRelationLabelRename()
        XCTAssertEqual(model.relationLabelPrompt?.rename?.oldKey, "inspired by")
        XCTAssertEqual(model.relationLabelPrompt?.rename?.oldName, "inspired by")
        XCTAssertEqual(model.relationLabelPrompt?.rename?.newName, "inspired by")
        XCTAssertEqual(model.relationLabelFieldText, "inspired by")
        await waitUntil { model.relationLabelRenamePreviewLines != nil }
        XCTAssertEqual(
            model.relationLabelRenamePreviewLines?.first,
            "2 links in 1 notes · 1 mirrors · 1 commit"
        )
        XCTAssertEqual(
            model.relationLabelRenameFooterItems.first?.label,
            "rename everywhere"
        )

        model.cancelRelationLabelPrompt()
        XCTAssertNil(model.relationLabelPrompt?.rename)
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "inspired by")
    }

    /// Ctrl+R renames the typed label when it names an existing catalog
    /// key, and stays in choose mode with a hint otherwise.
    func testRelationCardRenameTypedLabelAndMissingHint() async throws {
        let model = CapturePanelModel(
            processClient: try renameClient()
        )
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "implements",
            suggestions: [
                suggestionCandidate(label: "implements", count: 2),
                typedCandidate(
                    label: "implements",
                    replacement: "|implements",
                    count: 2,
                    existing: true,
                    hideReplacement: "||implements"
                ),
            ],
            suggestionAuthoredLabel: "implements"
        )
        model.openRelationLabelRename()
        XCTAssertEqual(model.relationLabelPrompt?.rename?.oldKey, "implements")

        model.cancelRelationLabelRename()
        model.updateRelationLabelPromptLabel("brand new")
        model.openRelationLabelRename()
        XCTAssertNil(model.relationLabelPrompt?.rename)
        XCTAssertEqual(
            model.relationLabelPrompt?.noticeMessage,
            "Select a label to rename"
        )
    }

    /// A `label_exists` refusal arms the merge confirm on the first Return
    /// and applies with `--merge` on the second.
    func testRelationCardRenameMergeArmsAndApplies() async throws {
        let recordURL = try renameRecordURL()
        defer { try? FileManager.default.removeItem(at: recordURL) }
        let model = CapturePanelModel(
            processClient: try renameClient(
                extraEnvironment: [
                    "FAKE_BOB_RELATIONS_RENAME_REFUSAL":
                        "label_exists:implements is already a relation label"
                ],
                recordPath: recordURL.path
            )
        )
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [
                suggestionCandidate(label: "inspired by", count: 3),
                suggestionCandidate(label: "implements", count: 2),
            ],
            suggestionAuthoredLabel: ""
        )
        model.selectRelationLabelSuggestion(key: "inspired by")
        model.openRelationLabelRename()
        model.updateRelationLabelRenameName("implements")
        await waitUntil { model.relationLabelPrompt?.errorMessage != nil }
        XCTAssertEqual(
            model.relationLabelPrompt?.rename?.refusalCode,
            "label_exists"
        )
        XCTAssertEqual(
            model.relationLabelRenameFooterItems.first?.label,
            "merge into “implements” (2) → 5 links"
        )

        model.submitRelationLabelPrompt()
        XCTAssertTrue(model.relationLabelPrompt?.rename?.mergeArmed ?? false)
        await waitUntil {
            model.relationLabelPrompt?.rename?.preview?.merge == true
        }
        XCTAssertEqual(
            model.relationLabelRenameFooterItems.first?.label,
            "again to merge 2 links"
        )

        model.submitRelationLabelPrompt()
        await waitUntil { model.relationLabelPrompt?.rename == nil }
        XCTAssertTrue(model.statusText.contains("Renamed “inspired by” → “implements”"))
        let recorded = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(recorded.contains("--merge"))
        XCTAssertTrue(recorded.contains("--via"))
    }

    /// A non-merge refusal renders inline and a late Return does not loop.
    func testRelationCardRenameRefusalRendersInline() async throws {
        let model = CapturePanelModel(
            processClient: try renameClient(extraEnvironment: [
                "FAKE_BOB_RELATIONS_RENAME_REFUSAL":
                    "invalid_label:that name cannot be a relation label"
            ])
        )
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [suggestionCandidate(label: "inspired by", count: 3)],
            suggestionAuthoredLabel: ""
        )
        model.selectRelationLabelSuggestion(key: "inspired by")
        model.openRelationLabelRename()
        model.updateRelationLabelRenameName("???")
        await waitUntil { model.relationLabelPrompt?.errorMessage != nil }
        XCTAssertEqual(
            model.relationLabelPrompt?.errorMessage,
            "that name cannot be a relation label"
        )
        XCTAssertNil(model.relationLabelRenamePreviewLines)
    }

    /// An older bob without the relations group gets the update hint.
    func testRelationCardRenameSkewShowsUpdateHint() async throws {
        let model = CapturePanelModel(
            processClient: try renameClient(extraEnvironment: [
                "FAKE_BOB_RELATIONS_RENAME_SKEW": "1"
            ])
        )
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [suggestionCandidate(label: "inspired by", count: 3)],
            suggestionAuthoredLabel: ""
        )
        model.selectRelationLabelSuggestion(key: "inspired by")
        model.openRelationLabelRename()
        await waitUntil { model.relationLabelPrompt?.noticeMessage != nil }
        XCTAssertEqual(
            model.relationLabelPrompt?.noticeMessage,
            "Update bob to rename relation labels"
        )
    }

    /// Apply rewrites every OLD relation in the draft from bob's
    /// `label_range`s and replacements, carries the card's suffix range,
    /// selects NEW, and reports the one commit.
    func testRelationCardRenameApplyFixesUpDraft() async throws {
        let recordURL = try renameRecordURL()
        defer { try? FileManager.default.removeItem(at: recordURL) }
        let draft = "New task ~tasks:target|inspired by plus ~tasks:other||inspired by"
        let model = CapturePanelModel(
            processClient: try renameClient(
                extraEnvironment: [
                    "FAKE_BOB_RELATION_LABEL_EXTRA":
                        "{\"label\":\"prompted by\",\"key\":\"prompted by\",\"count\":2,\"replacement\":\"|\\\"prompted by\\\"\",\"hide_replacement\":\"||\\\"prompted by\\\"\"}",
                    "FAKE_BOB_PARSE_FIXTURE": "relation-label-parse-fixup.json",
                ],
                recordPath: recordURL.path
            )
        )
        model.installRelationLabelPromptForPreviews(
            draft: draft,
            tokenRange: CaptureRange(start: 9, end: 22),
            labelRange: CaptureRange(start: 22, end: 34),
            authoredLabel: "",
            suggestions: [suggestionCandidate(label: "inspired by", count: 3)],
            suggestionAuthoredLabel: ""
        )
        model.selectRelationLabelSuggestion(key: "inspired by")
        model.openRelationLabelRename()
        model.updateRelationLabelRenameName("prompted by")
        await waitUntil {
            model.relationLabelPrompt?.rename?.preview?.toKey == "prompted by"
        }

        model.submitRelationLabelPrompt()
        await waitUntil { model.relationLabelPrompt?.rename == nil }
        XCTAssertEqual(
            model.plainDraft,
            "New task ~tasks:target|\"prompted by\" plus ~tasks:other||\"prompted by\""
        )
        XCTAssertEqual(
            model.relationLabelPrompt?.labelRange,
            CaptureRange(start: 22, end: 36)
        )
        XCTAssertEqual(model.relationLabelPrompt?.selectedKey, "prompted by")
        XCTAssertEqual(model.relationLabelPrompt?.authoredLabel, "prompted by")
        XCTAssertTrue(model.statusText.contains(
            "Renamed “inspired by” → “prompted by” · 2 links in 1 notes · 1 commit"
        ))
        let recorded = try String(contentsOf: recordURL, encoding: .utf8)
        XCTAssertTrue(recorded.contains("--via bob-mac-capture"))
        XCTAssertTrue(recorded.contains("capture-parse"))
    }

    /// Two fast renames keep the last preview, never the stale first one.
    func testRelationCardRenamePreviewKeepsLatest() async throws {
        let model = CapturePanelModel(
            processClient: try renameClient()
        )
        model.installRelationLabelPromptForPreviews(
            authoredLabel: "",
            suggestions: [suggestionCandidate(label: "inspired by", count: 3)],
            suggestionAuthoredLabel: ""
        )
        model.selectRelationLabelSuggestion(key: "inspired by")
        model.openRelationLabelRename()
        model.updateRelationLabelRenameName("prompted by")
        model.updateRelationLabelRenameName("prompted by now")
        await waitUntil {
            model.relationLabelPrompt?.rename?.previewNewName == "prompted by now"
        }
        XCTAssertEqual(
            model.relationLabelPrompt?.rename?.preview?.toKey,
            "prompted by now"
        )
    }

    /// Router: Ctrl+R opens rename mode; in rename mode Ctrl+R is consumed,
    /// Tab stays in the card, and Return submits.
    func testRelationCardKeysOpenRename() {
        let router = CaptureKeyCommandRouter()
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
        let choose = CaptureKeyRoutingContext(relationLabelPromptVisible: true)
        XCTAssertEqual(
            router.command(for: event(15, modifiers: .control), context: choose),
            .openRelationLabelRename
        )
        let rename = CaptureKeyRoutingContext(
            relationLabelPromptVisible: true,
            relationLabelRenameActive: true
        )
        XCTAssertEqual(
            router.command(for: event(15, modifiers: .control), context: rename),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: event(48), context: rename),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: event(36), context: rename),
            .submitRelationLabelPrompt
        )
        XCTAssertEqual(
            router.command(for: event(53), context: rename),
            .cancelRelationLabelPrompt
        )
    }

    func testRelationCardCancelCueDimsSourceAndShowsVerdict() {
        let model = CapturePanelModel()
        let cancel = CaptureCompletionRelationCancel(
            source: CaptureCompletionRelationCancelSource(
                path: "cash.md",
                blockID: "sell",
                text: "Sell stocks!",
                statusSymbol: " ",
                statusName: "Todo"
            ),
            verdict: "cancels",
            message: "⊘ Cancels “Sell stocks!” · Todo → Cancelled"
        )
        model.installRelationLabelPromptForPreviews(
            draft: "Sell stocks! ~invest:now|\"duplicate of\"",
            tokenRange: CaptureRange(start: 14, end: 25),
            direction: .linksTo,
            ownerText: "Sell stocks!",
            targetText: "Sell stocks now!",
            authoredLabel: "duplicate of",
            suggestions: [
                typedCandidate(
                    label: "duplicate of",
                    replacement: "|\"duplicate of\""
                ).withCancelSource(),
                suggestionCandidate(label: "duplicate of", count: 0).withCancelSource(
                    configured: true
                ),
            ],
            suggestionAuthoredLabel: "duplicate of",
            relationCancel: cancel
        )
        XCTAssertTrue(model.relationLabelDimsSource)
        XCTAssertTrue(model.relationLabelSentence.hasPrefix("⊘ "))
        XCTAssertEqual(
            model.relationLabelCancelSlot,
            CaptureRelationCancelSlot(
                text: "⊘ Cancels “Sell stocks!” · Todo → Cancelled",
                style: .cancels
            )
        )
        XCTAssertTrue(
            model.relationLabelSentenceAccessibilityLabel.contains("Cancels Sell stocks!")
        )
        XCTAssertEqual(
            model.relationLabelPromptRows.filter(\.cancelsSource).count,
            1
        )
    }

    func testRelationCardAlreadyClosedSlotIsMuted() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            ownerText: "Gone idea",
            targetText: "Sell stocks now!",
            authoredLabel: "duplicate of",
            suggestions: [
                typedCandidate(
                    label: "duplicate of",
                    replacement: "|\"duplicate of\""
                ).withCancelSource()
            ],
            suggestionAuthoredLabel: "duplicate of",
            relationCancel: CaptureCompletionRelationCancel(
                source: CaptureCompletionRelationCancelSource(text: "Gone idea"),
                verdict: "already_closed",
                message: "Already Cancelled · link only"
            )
        )
        XCTAssertFalse(model.relationLabelDimsSource)
        XCTAssertEqual(model.relationLabelCancelSlot?.style, .muted)
        XCTAssertEqual(model.relationLabelCancelSlot?.text, "Already Cancelled · link only")
    }

    func testRelationCardInverseHintIsMuted() {
        let model = CapturePanelModel()
        model.installRelationLabelPromptForPreviews(
            ownerText: "Sell stocks!",
            targetText: "Sell stocks now!",
            authoredLabel: "supersedes",
            suggestions: [
                typedCandidate(label: "supersedes", replacement: "|supersedes")
            ],
            suggestionAuthoredLabel: "supersedes",
            relationCancel: CaptureCompletionRelationCancel(
                source: CaptureCompletionRelationCancelSource(text: "Sell stocks!"),
                verdict: "cancels",
                message: "⊘ Cancels “Sell stocks!” · Todo → Cancelled",
                hint: "“supersedes” never cancels · to retire “Sell stocks now!”, use ~~ with “superseded by”"
            )
        )
        XCTAssertFalse(model.relationLabelDimsSource)
        XCTAssertEqual(model.relationLabelCancelSlot?.style, .muted)
        XCTAssertTrue(model.relationLabelCancelSlot?.text.contains("never cancels") == true)
    }

    func testSubmitHintNamesCancelCountFromDryRun() throws {
        let model = CapturePanelModel()
        XCTAssertEqual(model.primaryActionTitle, "Capture")
        let json = """
        {
          "ok": true, "dry_run": true, "routed": false,
          "route_label": "cash.md", "relative_target": "cash.md",
          "target": "/tmp/vault/cash.md", "text": "Sell stocks!",
          "task_line": "- [ ] #task Sell stocks!", "kind": "task",
          "created": "2026-10-28", "placement": "updated",
          "relation_cancels": [{
            "source": {"path": "cash.md", "line": 1, "block_id": "sell", "text": "Sell stocks!"},
            "target": {"path": "invest.md", "block_id": "now", "text": "Sell stocks now!"},
            "labels": ["duplicate of"],
            "action": "added",
            "previous_status": " ",
            "previous_status_name": "Todo",
            "cancel_log": "none",
            "pomodoro_links_removed": 0,
            "recovered": [],
            "message": "⊘ would cancel “Sell stocks!” · Todo → Cancelled"
          }]
        }
        """
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(json.utf8)
        )
        guard case .success(let capture) = response else {
            return XCTFail("expected success")
        }
        model.previewResults = [capture]
        XCTAssertEqual(model.primaryActionTitle, "Capture & cancel 1 task")
    }
}

extension CaptureCompletionCandidate {
    fileprivate func withCancelSource(configured: Bool = false) -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: replacement,
            route: route,
            label: label,
            kind: kind,
            status: status,
            title: title,
            level: level,
            taskRef: taskRef,
            target: target,
            blockID: blockID,
            requiresBlockID: requiresBlockID,
            statusSymbol: statusSymbol,
            statusName: statusName,
            statusType: statusType,
            text: text,
            section: section,
            depth: depth,
            childCount: childCount,
            cursorAfter: cursorAfter,
            path: path,
            name: name,
            alias: alias,
            matchKind: matchKind,
            heading: heading,
            preview: preview,
            requiresName: requiresName,
            line: line,
            state: state,
            timeRange: timeRange,
            placeholder: placeholder,
            isCurrent: isCurrent,
            matchCount: matchCount,
            createsPomodoro: createsPomodoro,
            themes: themes,
            origin: origin,
            lastUsed: lastUsed,
            daysUsed: daysUsed,
            similarTo: similarTo,
            nextUp: nextUp,
            planThemesAfter: planThemesAfter,
            planThemesCap: planThemesCap,
            pomodoro: pomodoro,
            noteKind: noteKind,
            blockIDSuggestions: blockIDSuggestions,
            group: group,
            scheduled: scheduled,
            pullsForward: pullsForward,
            notePath: notePath,
            locator: locator,
            alreadyDependency: alreadyDependency,
            alreadyBlocked: alreadyBlocked,
            alreadyLinked: alreadyLinked,
            existingLabel: existingLabel,
            alsoPrerequisite: alsoPrerequisite,
            disabledReason: disabledReason,
            hidden: hidden,
            recurring: recurring,
            alreadySelected: alreadySelected,
            today: today,
            taskKind: taskKind,
            count: count,
            typed: typed,
            key: key,
            inverse: inverse,
            hideReplacement: hideReplacement,
            existing: existing,
            cancelsSource: true,
            configured: configured
        )
    }
}
