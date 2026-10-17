import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureOpenHintDesignTests: XCTestCase {
    func testRenderEditorFooterChipAtRestAndRevealed() throws {
        let plan = CaptureOpenPlan(
            openNotes: [
                CaptureOpenNote(
                    path: "/vault/inbox.md",
                    relativePath: "inbox.md",
                    role: .note,
                    label: "inbox",
                    line: 42
                ),
                CaptureOpenNote(
                    path: "/vault/2026/20261017.md",
                    relativePath: "2026/20261017.md",
                    role: .day,
                    label: "Today"
                ),
            ],
            captures: []
        )

        try writeEditorFooter(name: "capture-open-hint-rest", plan: plan, revealed: false)
        try writeEditorFooter(name: "capture-open-hint-revealed", plan: plan, revealed: true)
    }

    func testRenderPickerHintsIncludingControlReturn() throws {
        let view = CapturePickerKeyHints(source: .activeTask)
            .padding(12)
        for (suffix, width) in [
            ("wide", CGFloat(760)),
            ("minimum", CGFloat(CapturePanelLayout.panelMinimumContentWidth)),
        ] {
            try RenderFixtureWriter.write(
                view,
                name: "capture-picker-open-hints-\(suffix)",
                width: width,
                appearance: .aqua
            )
            try RenderFixtureWriter.write(
                view,
                name: "capture-picker-open-hints-\(suffix)",
                width: width,
                appearance: .darkAqua
            )
        }
    }

    func testRenderSuccessorCardOpenGlyph() throws {
        let model = CapturePanelModel()
        model.installPullInChoiceForPreviews(
            offers: [
                TaskCompleteUnblocked(
                    notePath: "sase.md",
                    blockID: "offer-1",
                    line: 1,
                    text: "Re-launch all failed agents",
                    previousStatusSymbol: "?",
                    previousStatusName: "Blocked",
                    statusSymbol: " ",
                    statusName: "Ready",
                    notLinked: "not_selected",
                    offer: TaskCompleteOffer(
                        key: "opaque#1^suffix",
                        n: 1,
                        group: "hand_off",
                        destination: TaskCompleteOfferDestination(
                            dayFile: "20261013.md",
                            entryName: "FOCUS",
                            entryRole: "current",
                            fallback: false
                        )
                    )
                )
            ],
            pullIn: CapturePullIn(supported: true, offerCount: 1),
            draft: "!task with dependents",
            openAfterCapture: true
        )
        let choice = try XCTUnwrap(model.pullInChoice)
        let view = VStack(spacing: 12) {
            CapturePullInChoiceCard(model: model, choice: choice, previewMode: true)
            CapturePullInChoiceFooter(model: model)
        }
        .padding(18)
        for (suffix, width) in [
            ("wide", CGFloat(760)),
            ("minimum", CGFloat(CapturePanelLayout.panelMinimumContentWidth)),
        ] {
            try RenderFixtureWriter.write(
                view,
                name: "capture-pull-in-choice-open-glyph-\(suffix)",
                width: width,
                appearance: .aqua
            )
            try RenderFixtureWriter.write(
                view,
                name: "capture-pull-in-choice-open-glyph-\(suffix)",
                width: width,
                appearance: .darkAqua
            )
        }
    }

    private func writeEditorFooter(
        name: String,
        plan: CaptureOpenPlan,
        revealed: Bool
    ) throws {
        let model = CapturePanelModel()
        model.plainDraft = "Inbox task"
        model.previewOpenPlan = plan
        model.openHintRevealed = revealed
        let view = CapturePanelView(model: model)
        for (suffix, width) in [
            ("wide", CGFloat(760)),
            ("minimum", CGFloat(CapturePanelLayout.panelMinimumContentWidth)),
        ] {
            try RenderFixtureWriter.write(
                view,
                name: "\(name)-\(suffix)",
                width: width,
                appearance: .aqua
            )
            try RenderFixtureWriter.write(
                view,
                name: "\(name)-\(suffix)",
                width: width,
                appearance: .darkAqua
            )
        }
    }
}
