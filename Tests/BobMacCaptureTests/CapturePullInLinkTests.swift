import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Key contract and model wiring for the Pull-In reason `LINK` band
/// (`bob capture-complete --links-only` in the recall band's slot).
///
/// The fetch itself is covered by `BobProcessClientTests` (flags, decode,
/// fail-open) and `PullInLinkStateTests` (reducer, byte ranges); these
/// tests pin the router mapping and the model splice/close semantics.
final class CapturePullInLinkTests: XCTestCase {
    private func keyEvent(
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        repeat isRepeat: Bool = false
    ) -> NSEvent {
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

    private func linkContext(canAccept: Bool = true) -> CaptureKeyRoutingContext {
        CaptureKeyRoutingContext(
            pullInChoiceVisible: true,
            pullInReasonFocused: true,
            pullInLinkOpen: true,
            pullInLinkCanAccept: canAccept
        )
    }

    func testRouterMapsLinkKeysWhileBandIsOpen() {
        let router = CaptureKeyCommandRouter()
        let context = linkContext()
        XCTAssertEqual(
            router.command(for: keyEvent(36), context: context),
            .acceptPullInLink)
        XCTAssertEqual(
            router.command(for: keyEvent(76), context: context),
            .acceptPullInLink)
        XCTAssertEqual(
            router.command(for: keyEvent(48), context: context),
            .acceptPullInLinkFromTab)
        XCTAssertEqual(
            router.command(for: keyEvent(53), context: context),
            .closePullInLinkBand)
        XCTAssertEqual(
            router.command(
                for: keyEvent(33, modifiers: .control), context: context),
            .closePullInLinkBand)
        XCTAssertEqual(
            router.command(for: keyEvent(125), context: context),
            .movePullInLinkNext)
        XCTAssertEqual(
            router.command(for: keyEvent(126), context: context),
            .movePullInLinkPrevious)
        XCTAssertEqual(
            router.command(
                for: keyEvent(45, modifiers: .control), context: context),
            .movePullInLinkNext)
        XCTAssertEqual(
            router.command(
                for: keyEvent(35, modifiers: .control), context: context),
            .movePullInLinkPrevious)
        // Shift+Tab passes through to the host; held keys consume;
        // modified Return passes through; Ctrl+J never pins.
        XCTAssertNil(
            router.command(
                for: keyEvent(48, modifiers: .shift), context: context))
        XCTAssertEqual(
            router.command(for: keyEvent(36, repeat: true), context: context),
            .consumeKey)
        XCTAssertEqual(
            router.command(for: keyEvent(48, repeat: true), context: context),
            .consumeKey)
        XCTAssertNil(
            router.command(
                for: keyEvent(36, modifiers: .control), context: context))
        XCTAssertEqual(
            router.command(
                for: keyEvent(38, modifiers: .control), context: context),
            .consumeKey)
        // Recall keys stay quiet while the band owns the slot.
        XCTAssertNotEqual(
            router.command(
                for: keyEvent(45, modifiers: .control), context: context),
            .recallNextPullInReason)
    }

    func testRouterTabPassesThroughWithoutSelection() {
        let router = CaptureKeyCommandRouter()
        let context = linkContext(canAccept: false)
        // Zero rows (or no selection): Tab passes to the host, Return
        // closes the band instead of confirming.
        XCTAssertNil(router.command(for: keyEvent(48), context: context))
        XCTAssertEqual(
            router.command(for: keyEvent(36), context: context),
            .acceptPullInLink)
        XCTAssertEqual(
            router.command(for: keyEvent(53), context: context),
            .closePullInLinkBand)
    }

    func testRouterFallsBackToRecallWithoutBand() {
        let router = CaptureKeyCommandRouter()
        let reason = CaptureKeyRoutingContext(
            pullInChoiceVisible: true, pullInReasonFocused: true)
        XCTAssertEqual(
            router.command(for: keyEvent(36), context: reason),
            .confirmPullInReason)
        XCTAssertEqual(
            router.command(for: keyEvent(53), context: reason),
            .restorePullInReason)
        XCTAssertEqual(
            router.command(
                for: keyEvent(45, modifiers: .control), context: reason),
            .recallNextPullInReason)
        XCTAssertNil(router.command(for: keyEvent(48), context: reason))
    }

    @MainActor
    private func modelWithReason() -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installPullInChoiceForPreviews(
            offers: offers(count: 3),
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 3,
                close: CapturePullInClose(supported: true)
            ),
            draft: "draft"
        )
        model.beginPullInCancelForHighlight()
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
        return model
    }

    @MainActor
    private func openNoteBand(on model: CapturePanelModel) {
        model.updatePullInReasonText("fix [[sas", caretUTF16: 9)
        XCTAssertTrue(
            model.pullInLink.receive(
                text: "fix [[sas",
                cursorUTF8: 9,
                context: .wikilinkNote,
                replacement: CaptureRange(start: 6, end: 9),
                candidates: noteCandidates(),
                opensWithoutSelection: false,
                generation: model.pullInLink.generation
            )
        )
        XCTAssertTrue(model.pullInLinkBandVisible)
    }

    private func noteCandidates() -> [CaptureCompletionCandidate] {
        [
            CaptureCompletionCandidate(
                replacement: "sase]]", cursorAfter: 12, path: "sase.md",
                name: "sase"),
            CaptureCompletionCandidate(
                replacement: "sase_cleanup]]", cursorAfter: 21,
                path: "sase_cleanup.md", name: "sase_cleanup"),
        ]
    }

    @MainActor
    func testLinkBandHiddenUntilBobResponds() {
        let model = modelWithReason()
        XCTAssertFalse(model.pullInLinkBandVisible)
        model.updatePullInReasonText("fix [[sas", caretUTF16: 9)
        XCTAssertEqual(model.pullInLink.text, "fix [[sas")
        XCTAssertFalse(model.pullInLinkBandVisible)
    }

    @MainActor
    func testReceiveOpensBandAndAcceptSplicesAtBytes() {
        let model = modelWithReason()
        openNoteBand(on: model)
        XCTAssertEqual(model.pullInLink.selectedIndex, 1)

        let edit = model.pullInReasonLinkEdit(
            fieldText: "fix [[sas", caretUTF16: 9)
        XCTAssertEqual(edit?.range, NSRange(location: 6, length: 3))
        XCTAssertEqual(edit?.insertion, "sase]]")
        XCTAssertEqual(edit?.newText, "fix [[sase]]")
        XCTAssertEqual(edit?.caretUTF16, 12)

        guard let edit else {
            XCTFail("Missing link edit")
            return
        }
        model.didAcceptPullInLink(edit)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, "fix [[sase]]")
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
    }

    @MainActor
    func testDetailPreviewNamesExactLink() {
        let model = modelWithReason()
        openNoteBand(on: model)
        XCTAssertEqual(model.pullInLinkDetailPreview, "[[sase]]")
    }

    @MainActor
    func testStaleCaretClosesInsteadOfSplicing() {
        let model = modelWithReason()
        openNoteBand(on: model)
        XCTAssertNil(
            model.pullInReasonLinkEdit(fieldText: "fix [[sas!", caretUTF16: 10))
        XCTAssertNil(
            model.pullInReasonLinkEdit(fieldText: "fix [[sas", caretUTF16: 8))
    }

    @MainActor
    func testZeroRowsKeepBandOpenWithNoSelection() {
        let model = modelWithReason()
        model.updatePullInReasonText("plain reason", caretUTF16: 12)
        XCTAssertTrue(
            model.pullInLink.receive(
                text: "plain reason",
                cursorUTF8: 12,
                context: .wikilinkNote,
                replacement: CaptureRange(start: 12, end: 12),
                candidates: [],
                opensWithoutSelection: false,
                generation: model.pullInLink.generation
            )
        )
        XCTAssertTrue(model.pullInLinkBandVisible)
        XCTAssertNil(model.pullInLink.selectedCandidate)
        XCTAssertNil(
            model.pullInReasonLinkEdit(fieldText: "plain reason", caretUTF16: 12))

        // Return closes the band and never confirms the Pull-In.
        XCTAssertTrue(model.closePullInLinkBand())
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
        XCTAssertTrue(model.pullInChoice?.verdicts.isEmpty ?? false)
    }

    @MainActor
    func testEscClosesBandOnlyThenBacksOut() {
        let model = modelWithReason()
        openNoteBand(on: model)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, "fix [[sas")

        model.restorePullInReasonFromKeyboard()
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, "fix [[sas")
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)

        // Only the next Esc runs today's back-out.
        model.restorePullInReasonFromKeyboard()
        XCTAssertNil(model.pullInChoice?.activeReasonKey)
    }

    @MainActor
    func testConfirmAndRestoreResetLinkState() {
        let model = modelWithReason()
        openNoteBand(on: model)

        model.confirmPullInReason()
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertNil(model.pullInChoice?.activeReasonKey)

        let reopened = modelWithReason()
        openNoteBand(on: reopened)
        reopened.restorePullInReason()
        XCTAssertFalse(reopened.pullInLinkBandVisible)
        XCTAssertNil(reopened.pullInChoice?.activeReasonKey)
    }

    @MainActor
    func testClickInsertsRowAndKeepsReasonOpen() {
        let model = modelWithReason()
        openNoteBand(on: model)
        let second = noteCandidates()[1].id

        model.insertPullInLinkRow(id: second)
        XCTAssertEqual(
            model.pullInChoice?.activeReasonText, "fix [[sase_cleanup]]")
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)

        model.insertPullInLinkRow(id: "unknown")
        XCTAssertEqual(
            model.pullInChoice?.activeReasonText, "fix [[sase_cleanup]]")
    }

    @MainActor
    func testActiveReasonNotePathFeedsSourceNote() {
        let model = modelWithReason()
        XCTAssertEqual(model.pullInChoice?.activeReasonNotePath, "sase.md")
    }

    @MainActor
    func testMoveSelectionAnnouncesAndClamps() {
        let model = modelWithReason()
        openNoteBand(on: model)
        XCTAssertTrue(model.movePullInLinkSelection(by: 1))
        XCTAssertEqual(model.pullInLink.selectedIndex, 2)
        XCTAssertTrue(model.movePullInLinkSelection(by: 1))
        XCTAssertEqual(model.pullInLink.selectedIndex, 2)
    }

    // MARK: - Tasks mode (`((`) and the NAME stage

    private static let tasksText = "Superseded by ((api do"

    /// bob's `wikilink_task` rows: the first is the Pull-In row's own task
    /// (`subject`), the second is identified, the third ID-less.
    private func taskCandidates(
        subject: PullInLinkSubject?
    ) -> [CaptureCompletionCandidate] {
        let ownPath = subject?.notePath ?? "sase.md"
        let ownID = subject?.blockID ?? "task-1"
        return [
            CaptureCompletionCandidate(
                replacement: "[[sase#^\(ownID)]]", taskRef: "1:aaaa", blockID: ownID,
                statusSymbol: " ", statusName: "Ready", statusType: "TODO",
                text: "Own task", cursorAfter: 30, linkTarget: "sase",
                group: "in_this_note", notePath: ownPath, locator: "sase"),
            CaptureCompletionCandidate(
                replacement: "[[api#^api-docs]]", taskRef: "2:bbbb", blockID: "api-docs",
                statusSymbol: "/", statusName: "In Progress", statusType: "IN_PROGRESS",
                text: "Write the API docs", cursorAfter: 31, linkTarget: "api",
                group: "in_progress", notePath: "projects/api.md", locator: "api"),
            CaptureCompletionCandidate(
                replacement: "", taskRef: "3:cccc", requiresBlockID: true,
                statusSymbol: " ", statusName: "Ready", statusType: "TODO",
                text: "Publish the API docs site", linkTarget: "api",
                blockIDSuggestions: ["publish-api-docs", "api-docs-site"],
                group: "open", notePath: "projects/api.md", locator: "api"),
        ]
    }

    @MainActor
    private func openTasksBand(on model: CapturePanelModel) {
        model.updatePullInReasonText(Self.tasksText, caretUTF16: 22)
        XCTAssertTrue(
            model.pullInLink.receive(
                text: Self.tasksText,
                cursorUTF8: 22,
                context: .wikilinkTask,
                replacement: CaptureRange(start: 14, end: 22),
                candidates: taskCandidates(subject: model.pullInChoice?.activeReasonSubject),
                opensWithoutSelection: false,
                generation: model.pullInLink.generation
            )
        )
        XCTAssertTrue(model.pullInLinkBandVisible)
    }

    private func namingContext() -> CaptureKeyRoutingContext {
        CaptureKeyRoutingContext(
            pullInChoiceVisible: true,
            pullInReasonFocused: false,
            pullInLinkOpen: true,
            pullInLinkCanAccept: true,
            pullInLinkNaming: true
        )
    }

    func testRouterOwnsTheNameStageKeys() {
        let router = CaptureKeyCommandRouter()
        let context = namingContext()
        // Return writes and links, with or without Control, Command, or
        // Option; Shift+Return and a held Return never reach the offer list.
        XCTAssertEqual(
            router.command(for: keyEvent(36), context: context), .commitPullInLinkName)
        XCTAssertEqual(
            router.command(for: keyEvent(76), context: context), .commitPullInLinkName)
        for modifier: NSEvent.ModifierFlags in [.control, .command, .option] {
            XCTAssertEqual(
                router.command(for: keyEvent(36, modifiers: modifier), context: context),
                .commitPullInLinkName)
        }
        XCTAssertEqual(
            router.command(for: keyEvent(36, modifiers: .shift), context: context),
            .consumeKey)
        XCTAssertEqual(
            router.command(for: keyEvent(36, repeat: true), context: context),
            .consumeKey)
        // Esc and Ctrl+[ go back one layer; a held Esc is consumed.
        XCTAssertEqual(
            router.command(for: keyEvent(53), context: context), .cancelPullInLinkName)
        XCTAssertEqual(
            router.command(for: keyEvent(33, modifiers: .control), context: context),
            .cancelPullInLinkName)
        XCTAssertEqual(
            router.command(for: keyEvent(53, repeat: true), context: context), .consumeKey)
        // Tab, Down, and Ctrl+N cycle forward; Shift+Tab, Up, and Ctrl+P back.
        XCTAssertEqual(
            router.command(for: keyEvent(48), context: context), .cyclePullInLinkNameForward)
        XCTAssertEqual(
            router.command(for: keyEvent(125), context: context), .cyclePullInLinkNameForward)
        XCTAssertEqual(
            router.command(for: keyEvent(45, modifiers: .control), context: context),
            .cyclePullInLinkNameForward)
        XCTAssertEqual(
            router.command(for: keyEvent(48, modifiers: .shift), context: context),
            .cyclePullInLinkNameBackward)
        XCTAssertEqual(
            router.command(for: keyEvent(126), context: context), .cyclePullInLinkNameBackward)
        XCTAssertEqual(
            router.command(for: keyEvent(35, modifiers: .control), context: context),
            .cyclePullInLinkNameBackward)
        // Ctrl+J never pins; text keys stay with the ID field.
        XCTAssertEqual(
            router.command(for: keyEvent(38, modifiers: .control), context: context),
            .consumeKey)
        XCTAssertNil(router.command(for: keyEvent(0), context: context))
        XCTAssertNil(router.command(for: keyEvent(51), context: context))
    }

    @MainActor
    func testControllerReturnWithZeroRowsClosesTheBandWithoutConfirming() {
        let model = modelWithReason()
        model.updatePullInReasonText("plain reason", caretUTF16: 12)
        XCTAssertTrue(
            model.pullInLink.receive(
                text: "plain reason", cursorUTF8: 12, context: .wikilinkTask,
                replacement: CaptureRange(start: 12, end: 12), candidates: [],
                opensWithoutSelection: false, generation: model.pullInLink.generation))
        XCTAssertTrue(model.pullInLinkBandVisible)

        // Return with nothing to insert (here also no editor to splice
        // through) closes the band and stops: the Pull-In is never
        // confirmed while the band was open.
        let controller = CapturePanelController(model: model)
        XCTAssertTrue(controller.perform(.acceptPullInLink))
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, "plain reason")
        XCTAssertTrue(model.pullInChoice?.verdicts.isEmpty ?? false)
    }

    @MainActor
    func testControllerReturnOnTheSubjectRowStaysPutAndTabPassesThrough() {
        let model = modelWithReason()
        openTasksBand(on: model)
        // The first row is the Pull-In row's own task: Return on it neither
        // inserts nor confirms, and the band stays put.
        let controller = CapturePanelController(model: model)
        XCTAssertTrue(controller.perform(.acceptPullInLink))
        XCTAssertTrue(model.pullInLinkBandVisible)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, Self.tasksText)
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
        XCTAssertTrue(model.pullInChoice?.verdicts.isEmpty ?? false)

        // Tab on it passes through to the host and leaves the band alone.
        XCTAssertFalse(controller.perform(.acceptPullInLinkFromTab))
        XCTAssertTrue(model.pullInLinkBandVisible)
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)

        // Tab on a row that would insert, with no editor to splice through,
        // closes the band like a stale edit and passes through.
        XCTAssertTrue(model.movePullInLinkSelection(by: 1))
        XCTAssertFalse(controller.perform(.acceptPullInLinkFromTab))
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
    }

    @MainActor
    func testReasonRowsOwnTaskIsTheSubjectAndDetailExplainsIt() throws {
        let model = modelWithReason()
        let subject = try XCTUnwrap(model.pullInChoice?.activeReasonSubject)
        XCTAssertEqual(subject.notePath, "sase.md")
        XCTAssertTrue(subject.blockID.hasPrefix("task-"), subject.blockID)
        openTasksBand(on: model)
        XCTAssertEqual(
            model.pullInLink.selectedAction,
            .disabled(reason: "The task this prompt is about", badge: "this prompt"))
        XCTAssertEqual(model.pullInLinkDetailLine, "⊘ The task this prompt is about")
        model.rejectPullInLinkRow()
        XCTAssertTrue(model.pullInLinkBandVisible)

        // A click on it inserts nothing either.
        model.insertPullInLinkRow(id: model.pullInLink.candidates[0].id)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, Self.tasksText)
        XCTAssertTrue(model.pullInLinkBandVisible)
    }

    @MainActor
    func testTaskRowAcceptSplicesBobsLinkOverTheOpenerRange() {
        let model = modelWithReason()
        openTasksBand(on: model)
        XCTAssertTrue(model.movePullInLinkSelection(by: 1))
        XCTAssertEqual(model.pullInLinkDetailLine, "↵ [[api#^api-docs]]")
        XCTAssertEqual(model.pullInLinkDetailPreview, "[[api#^api-docs]]")

        let edit = model.pullInReasonLinkEdit(fieldText: Self.tasksText, caretUTF16: 22)
        XCTAssertEqual(edit?.range, NSRange(location: 14, length: 8))
        XCTAssertEqual(edit?.insertion, "[[api#^api-docs]]")
        XCTAssertEqual(edit?.newText, "Superseded by [[api#^api-docs]]")
        XCTAssertEqual(edit?.caretUTF16, 31)
    }

    @MainActor
    func testReturnOnAnIDLessRowOpensNameWithoutTouchingTheReason() {
        let model = modelWithReason()
        openTasksBand(on: model)
        XCTAssertTrue(model.movePullInLinkSelection(by: 1))
        XCTAssertTrue(model.movePullInLinkSelection(by: 1))
        XCTAssertEqual(
            model.pullInLinkDetailLine,
            "↵ names it ^publish-api-docs in projects/api.md, then links it")

        // A raced caret opens nothing.
        XCTAssertFalse(model.beginPullInLinkName(fieldText: Self.tasksText, caretUTF16: 21))
        XCTAssertFalse(model.pullInLinkNaming)

        XCTAssertTrue(model.beginPullInLinkName(fieldText: Self.tasksText, caretUTF16: 22))
        XCTAssertTrue(model.pullInLinkNaming)
        XCTAssertEqual(model.pullInLink.name?.authoredID, "publish-api-docs")
        XCTAssertEqual(
            model.pullInLinkDetailLine,
            "↵ adds ^publish-api-docs, then links [[api#^publish-api-docs]]")
        XCTAssertEqual(model.pullInChoice?.activeReasonText, Self.tasksText)
        XCTAssertEqual(model.focusRequest.target, .taskIDPromptBlockID)

        // Focus moving into the ID field is not a blur of the reason: it
        // neither confirms nor restores the Pull-In.
        model.pullInReasonFieldDidBlur()
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
        XCTAssertTrue(model.pullInLinkNaming)
        XCTAssertTrue(model.pullInChoice?.verdicts.isEmpty ?? false)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, Self.tasksText)

        // The reason is not refetched or re-aimed under the stage.
        model.updatePullInReasonCaret(21)
        XCTAssertTrue(model.pullInLinkNaming)
        XCTAssertEqual(model.pullInLink.cursorUTF8, 22)
    }

    @MainActor
    func testNameStageEscapeReturnsToTheListThenLaterEscapeClosesTheBand() {
        let model = modelWithReason()
        openTasksBand(on: model)
        _ = model.movePullInLinkSelection(by: 1)
        _ = model.movePullInLinkSelection(by: 1)
        let selected = model.pullInLink.selectedID
        XCTAssertTrue(model.beginPullInLinkName(fieldText: Self.tasksText, caretUTF16: 22))

        model.updatePullInLinkNameID("pub-1")
        model.cyclePullInLinkNameSuggestion(forward: true)
        XCTAssertEqual(model.pullInLink.name?.authoredID, "publish-api-docs")

        XCTAssertTrue(model.cancelPullInLinkName())
        XCTAssertFalse(model.pullInLinkNaming)
        XCTAssertTrue(model.pullInLinkBandVisible)
        XCTAssertEqual(model.pullInLink.selectedID, selected)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, Self.tasksText)
        XCTAssertFalse(model.cancelPullInLinkName())

        // One layer per press: the next Esc closes the band, the next backs
        // out of the reason.
        model.restorePullInReasonFromKeyboard()
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
    }

    @MainActor
    func testClickOnAnIDLessRowOpensNameAndAnIdentifiedRowInserts() {
        let model = modelWithReason()
        openTasksBand(on: model)
        model.insertPullInLinkRow(id: model.pullInLink.candidates[2].id)
        XCTAssertTrue(model.pullInLinkNaming)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, Self.tasksText)
        XCTAssertTrue(model.cancelPullInLinkName())

        model.insertPullInLinkRow(id: model.pullInLink.candidates[1].id)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, "Superseded by [[api#^api-docs]]")
        XCTAssertFalse(model.pullInLinkBandVisible)
    }

    @MainActor
    private func modelNamingATask(
        record: URL, environment: [String: String] = [:]
    ) -> CapturePanelModel {
        var env = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": record.path,
        ]
        for (key, value) in environment { env[key] = value }
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: URL(fileURLWithPath: #filePath)
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .deletingLastPathComponent()
                    .appendingPathComponent("Tests/Fixtures/fake-bob").path,
                environment: env),
            debounceNanoseconds: 0
        )
        model.installPullInChoiceForPreviews(
            offers: offers(count: 3),
            pullIn: CapturePullIn(
                supported: true, offerCount: 3, close: CapturePullInClose(supported: true)),
            draft: "draft")
        model.beginPullInCancelForHighlight()
        openTasksBand(on: model)
        _ = model.movePullInLinkSelection(by: 1)
        _ = model.movePullInLinkSelection(by: 1)
        XCTAssertTrue(model.beginPullInLinkName(fieldText: Self.tasksText, caretUTF16: 22))
        return model
    }

    @MainActor
    private func waitFor(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline, !condition() {
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(condition(), "Timed out waiting for model state")
    }

    @MainActor
    func testNameCommitWritesTheIDThenSplicesBobsReplacement() async throws {
        let record = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = modelNamingATask(record: record)
        var applied: [PullInReasonLinkEdit] = []
        model.applyPullInLinkEdit = { edit in
            applied.append(edit)
            return true
        }

        model.commitPullInLinkName()
        XCTAssertEqual(model.pullInLink.name?.isSaving, true)
        // Keys during the write change nothing.
        model.updatePullInLinkNameID("changed")
        XCTAssertEqual(model.pullInLink.name?.authoredID, "publish-api-docs")
        XCTAssertTrue(model.cancelPullInLinkName())
        XCTAssertTrue(model.pullInLinkNaming)

        try await waitFor { !model.pullInLinkNaming }
        // bob's `wikilink_replacement` is spliced verbatim (the fake bob
        // spells the target as the vault path), never rebuilt from the
        // display-only `link_target`.
        let link = "[[projects/api#^publish-api-docs]]"
        XCTAssertEqual(model.pullInChoice?.activeReasonText, "Superseded by \(link)")
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
        XCTAssertTrue(model.pullInChoice?.verdicts.isEmpty ?? false)
        let edit = try XCTUnwrap(applied.first)
        XCTAssertEqual(applied.count, 1)
        XCTAssertEqual(edit.range, NSRange(location: 14, length: 8))
        XCTAssertEqual(edit.insertion, link)
        XCTAssertEqual(edit.caretUTF16, 14 + link.utf16.count)

        // The ID is written by the exact vault path and task ref, never a
        // lowercased route; an open task passes no `--allow-closed`.
        let calls = try String(contentsOf: record)
        XCTAssertTrue(
            calls.contains(
                "argv=capture-task-id --note-path projects/api.md --task-ref 3:cccc "
                    + "--block-id publish-api-docs --format json"),
            calls)
        XCTAssertFalse(calls.contains("--allow-closed"), calls)
    }

    @MainActor
    func testNameCommitRefusesAnInvalidIDWithoutSpawningBob() throws {
        let record = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = modelNamingATask(record: record)
        model.updatePullInLinkNameID("bad id")
        model.commitPullInLinkName()
        XCTAssertEqual(model.pullInLink.name?.isSaving, false)
        XCTAssertEqual(
            model.pullInLink.name?.errorMessage, "Use only letters, numbers, and hyphens.")
        XCTAssertTrue(model.pullInLinkNaming)
        XCTAssertFalse(
            (try? String(contentsOf: record))?.contains("capture-task-id") ?? false)
    }

    @MainActor
    func testNameCommitFailureKeepsTheStageOpenWithBobsReason() async throws {
        let record = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = modelNamingATask(record: record)
        // The fake bob refuses `deep-fix` as a duplicate ID.
        model.updatePullInLinkNameID("deep-fix")
        model.commitPullInLinkName()
        try await waitFor { model.pullInLink.name?.isSaving == false }
        XCTAssertTrue(model.pullInLinkNaming)
        XCTAssertNotNil(model.pullInLink.name?.errorMessage)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, Self.tasksText)
        XCTAssertEqual(
            model.pullInLinkDetailLine,
            "⊘ \(model.pullInLink.name?.errorMessage ?? "")")
        // Esc still returns to the list afterwards.
        XCTAssertTrue(model.cancelPullInLinkName())
        XCTAssertFalse(model.pullInLinkNaming)
    }

    @MainActor
    func testNameCommitWithAnOldBobNeverInsertsAndKeepsTheStage() async throws {
        let record = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = modelNamingATask(
            record: record, environment: ["FAKE_BOB_WIKILINK_OLD": "1"])
        model.commitPullInLinkName()
        try await waitFor { model.pullInLink.name?.isSaving == false }
        XCTAssertEqual(
            model.pullInLink.name?.errorMessage,
            "This Bob is too old for (( links. Update Bob first.")
        XCTAssertEqual(model.pullInChoice?.activeReasonText, Self.tasksText)
    }

    @MainActor
    func testNameCommitNeverInsertsOverAChangedReason() async throws {
        let record = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = modelNamingATask(record: record)
        var applied = 0
        model.applyPullInLinkEdit = { _ in
            applied += 1
            return true
        }
        model.commitPullInLinkName()
        // The reason is edited while the write is in flight.
        model.updatePullInReasonText(Self.tasksText + "!", caretUTF16: 23)

        try await waitFor { !model.pullInLinkNaming }
        XCTAssertEqual(applied, 0)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, Self.tasksText + "!")
        XCTAssertFalse(model.pullInLinkBandVisible)
        XCTAssertTrue(model.statusText.contains("the reason changed"), model.statusText)
        XCTAssertTrue(model.statusText.contains("^publish-api-docs"), model.statusText)
    }

    @MainActor
    func testClosedRowsNamePassAllowClosed() async throws {
        let record = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = modelNamingATask(record: record)
        _ = model.cancelPullInLinkName()
        let closed = CaptureCompletionCandidate(
            replacement: "", taskRef: "7:dddd", requiresBlockID: true,
            statusSymbol: "x", statusName: "Done", statusType: "DONE",
            text: "Shipped", linkTarget: "api", blockIDSuggestions: ["shipped"],
            group: "completed", notePath: "projects/api.md", locator: "api")
        XCTAssertTrue(
            model.pullInLink.receive(
                text: Self.tasksText, cursorUTF8: 22, context: .wikilinkTask,
                replacement: CaptureRange(start: 14, end: 22), candidates: [closed],
                opensWithoutSelection: false, generation: model.pullInLink.generation))
        XCTAssertTrue(model.beginPullInLinkName(fieldText: Self.tasksText, caretUTF16: 22))
        model.commitPullInLinkName()
        try await waitFor { !model.pullInLinkNaming }
        let calls = try String(contentsOf: record)
        XCTAssertTrue(calls.contains("--task-ref 7:dddd --block-id shipped"), calls)
        XCTAssertTrue(calls.contains("--allow-closed"), calls)
    }

    private func offers(count: Int) -> [TaskCompleteUnblocked] {
        (1...count).map { n in
            TaskCompleteUnblocked(
                notePath: "sase.md",
                blockID: "task-\(n)",
                line: n,
                text: "Task \(n)",
                previousStatusSymbol: "?",
                previousStatusName: "Blocked",
                statusSymbol: " ",
                statusName: "Ready",
                notLinked: "not_selected",
                offer: TaskCompleteOffer(
                    key: "opaque#\(n)^suffix",
                    n: n,
                    group: n.isMultiple(of: 2) ? "hand_off" : "project",
                    project: n.isMultiple(of: 2) ? nil : "projects/sase_foo.md",
                    destination: TaskCompleteOfferDestination(
                        dayFile: "20261013.md",
                        entryName: "FOCUS",
                        entryRole: "current"
                    ),
                    close: TaskCompleteOfferClose(complete: true, cancel: true)
                )
            )
        }
    }
}
