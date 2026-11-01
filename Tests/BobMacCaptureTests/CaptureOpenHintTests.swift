import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureOpenHintTests: XCTestCase {
    func testChipShowsWhenDraftHasNoPreviewYet() throws {
        let pending = try makeModel()
        pending.plainDraft = "Inbox task"
        XCTAssertFalse(pending.captureGrammarAllowsSubmit)
        XCTAssertTrue(pending.openHintChipVisible)

        let model = try makeModel()
        XCTAssertFalse(model.openHintChipVisible)

        model.plainDraft = "Inbox task"
        model.installCompatibleCaptureGrammarForTests()
        XCTAssertTrue(model.captureGrammarAllowsSubmit)
        XCTAssertTrue(model.openHintChipVisible)
        XCTAssertNil(model.previewOpenHintPlan)
        XCTAssertTrue(model.openHintPresentation.isAvailable)
        XCTAssertEqual(model.openHintPresentation.rows, [])
    }

    func testEmptyPreviewPlanHidesChip() throws {
        let model = try makeModel()
        model.plainDraft = "https://example.com"
        model.installCompatibleCaptureGrammarForTests()
        model.previewOpenPlan = CaptureOpenPlan(openNotes: [], captures: [])

        XCTAssertTrue(model.captureGrammarAllowsSubmit)
        XCTAssertFalse(model.openHintChipVisible)
        XCTAssertFalse(model.openHintPresentation.isAvailable)
    }

    func testNonEmptyPreviewPlanShowsChipAndDestinations() throws {
        let model = try makeModel()
        model.plainDraft = "Inbox task"
        model.installCompatibleCaptureGrammarForTests()
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

        XCTAssertTrue(model.captureGrammarAllowsSubmit)
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

        await waitForOpenHint(model)
        XCTAssertTrue(model.openHintRevealed)

        model.noteModifierFlagsChanged([])
        XCTAssertFalse(model.openHintRevealed)
    }

    func testSubmitAndDismissalClearReveal() async {
        let model = CapturePanelModel()
        model.openHintRevealDelayNanoseconds = 1_000_000
        model.plainDraft = "Inbox task"
        model.noteModifierFlagsChanged(.control)
        await waitForOpenHint(model)
        XCTAssertTrue(model.openHintRevealed)

        model.installCompatibleCaptureGrammarForTests()
        model.submit(openAfterCapture: true)
        XCTAssertFalse(model.openHintRevealed)

        model.noteModifierFlagsChanged(.control)
        await waitForOpenHint(model)
        XCTAssertTrue(model.openHintRevealed)
        model.prepareForDismissal()
        XCTAssertFalse(model.openHintRevealed)
    }

    private func waitForOpenHint(_ model: CapturePanelModel) async {
        let deadline = ContinuousClock.now + .seconds(2)
        while !model.openHintRevealed, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeModel() throws -> CapturePanelModel {
        let source = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fakeBob = source.appendingPathComponent("Tests/Fixtures/fake-bob").path
        guard FileManager.default.isExecutableFile(atPath: fakeBob) else {
            throw NSError(domain: "CaptureOpenHintTests", code: 1)
        }
        return CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: fakeBob,
                environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
            )
        )
    }
}
