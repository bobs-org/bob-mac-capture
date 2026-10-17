import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureOpenHintTests: XCTestCase {
    func testChipShowsWhenDraftHasNoPreviewYet() {
        let model = CapturePanelModel()
        XCTAssertFalse(model.openHintChipVisible)

        model.plainDraft = "Inbox task"
        XCTAssertTrue(model.openHintChipVisible)
        XCTAssertNil(model.previewOpenHintPlan)
        XCTAssertTrue(model.openHintPresentation.isAvailable)
        XCTAssertEqual(model.openHintPresentation.rows, [])
    }

    func testEmptyPreviewPlanHidesChip() {
        let model = CapturePanelModel()
        model.plainDraft = "https://example.com"
        model.previewOpenPlan = CaptureOpenPlan(openNotes: [], captures: [])

        XCTAssertFalse(model.openHintChipVisible)
        XCTAssertFalse(model.openHintPresentation.isAvailable)
    }

    func testNonEmptyPreviewPlanShowsChipAndDestinations() {
        let model = CapturePanelModel()
        model.plainDraft = "Inbox task"
        model.previewOpenPlan = CaptureOpenPlan(
            openNotes: [
                CaptureOpenNote(
                    path: "/vault/inbox.md",
                    relativePath: "inbox.md",
                    role: .note,
                    label: "inbox",
                    line: 42
                ),
                CaptureOpenNote(
                    path: "/vault/today.md",
                    relativePath: "today.md",
                    role: .day,
                    label: "Today"
                ),
            ],
            captures: []
        )

        XCTAssertTrue(model.openHintChipVisible)
        XCTAssertEqual(
            model.openHintPresentation.accessibilityLabel,
            "Control-Return: capture and open inbox at line 42 and Today in Obsidian"
        )
        XCTAssertEqual(model.openHintPresentation.rows.count, 2)
    }

    func testLegacyPreviewResultsFillPlanWhenStoredPlanIsMissing() throws {
        let model = CapturePanelModel()
        model.plainDraft = "Call bank @Cash"
        model.previewResults = [
            CaptureCommandSuccess(
                ok: true,
                dryRun: true,
                routed: true,
                route: "Cash",
                routeLabel: "Cash.md",
                relativeTarget: "Cash.md",
                target: "/tmp/Cash.md",
                text: "Call bank",
                taskLine: "- [ ] Call bank",
                kind: "task",
                created: "2026-08-14",
                placement: "append"
            )
        ]

        let plan = try XCTUnwrap(model.previewOpenHintPlan)
        XCTAssertEqual(plan.source, .legacy)
        XCTAssertEqual(plan.notes.map(\.path), ["/tmp/Cash.md"])
        XCTAssertTrue(model.openHintChipVisible)
    }

    func testControlHeldAloneDetectionIgnoresChords() {
        XCTAssertTrue(CapturePanelModel.isControlHeldAlone(.control))
        XCTAssertFalse(CapturePanelModel.isControlHeldAlone([]))
        XCTAssertFalse(CapturePanelModel.isControlHeldAlone([.control, .shift]))
        XCTAssertFalse(CapturePanelModel.isControlHeldAlone([.control, .option]))
        XCTAssertFalse(CapturePanelModel.isControlHeldAlone([.control, .command]))
        XCTAssertFalse(CapturePanelModel.isControlHeldAlone(.command))
    }

    func testHoldingControlAloneRevealsAfterDelayAndClearsOnModifierChange() async {
        let model = CapturePanelModel()
        model.openHintRevealDelayNanoseconds = 20_000_000
        XCTAssertFalse(model.openHintRevealed)

        model.noteModifierFlagsChanged(.control)
        XCTAssertFalse(model.openHintRevealed)

        try? await Task.sleep(nanoseconds: 60_000_000)
        XCTAssertTrue(model.openHintRevealed)

        model.noteModifierFlagsChanged([])
        XCTAssertFalse(model.openHintRevealed)
    }

    func testSubmitAndDismissalClearReveal() async {
        let model = CapturePanelModel()
        model.openHintRevealDelayNanoseconds = 1_000_000
        model.plainDraft = "Inbox task"
        model.noteModifierFlagsChanged(.control)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(model.openHintRevealed)

        model.submit(openAfterCapture: true)
        XCTAssertFalse(model.openHintRevealed)

        model.noteModifierFlagsChanged(.control)
        try? await Task.sleep(nanoseconds: 20_000_000)
        XCTAssertTrue(model.openHintRevealed)
        model.prepareForDismissal()
        XCTAssertFalse(model.openHintRevealed)
    }
}
