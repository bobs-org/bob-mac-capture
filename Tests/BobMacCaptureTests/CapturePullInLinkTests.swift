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
