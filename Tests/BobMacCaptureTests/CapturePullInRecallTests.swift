import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

final class CapturePullInRecallTests: XCTestCase {
    private func catalog() -> [LogRecallPhrase] {
        [
            LogRecallPhrase(
                text: "duplicate of planning", key: "duplicate of planning",
                uses: 4, lastUsed: "2026-11-18", score: 3.1, recencyRank: 0),
            LogRecallPhrase(
                text: "no longer needed", key: "no longer needed", uses: 2,
                lastUsed: "2026-11-15", score: 1.4, recencyRank: 1),
            LogRecallPhrase(
                text: "superseded by weekly review",
                key: "superseded by weekly review", uses: 1,
                lastUsed: "2026-11-02", score: 0.5, recencyRank: 2),
        ]
    }

    @MainActor
    private func modelWithReason() -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installPullInChoiceForPreviews(
            offers: offers(count: 3),
            pullIn: CapturePullIn(supported: true, offerCount: 3),
            draft: "draft"
        )
        model.pullInRecallCatalog = catalog()
        model.beginPullInCancelForHighlight()
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
        return model
    }

    @MainActor
    func testRecallFillsFieldAndEscRestoresDraft() {
        let model = modelWithReason()
        XCTAssertFalse(model.pullInRecall.isRecalling)

        model.recallNextPullInReason()
        XCTAssertTrue(model.pullInRecall.isRecalling)
        XCTAssertEqual(
            model.pullInChoice?.activeReasonText, "duplicate of planning")

        // Esc while RECALLING restores the draft; the prompt stays open.
        model.restorePullInReasonFromKeyboard()
        XCTAssertFalse(model.pullInRecall.isRecalling)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, "")
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
        XCTAssertEqual(model.focusRequest.target, .pullInReasonField)

        // Only the next Esc runs today's back-out.
        model.restorePullInReasonFromKeyboard()
        XCTAssertNil(model.pullInChoice?.activeReasonKey)
    }

    @MainActor
    func testRecallMovesAboveTopBackToDraft() {
        let model = modelWithReason()
        model.updatePullInReasonText("du")
        model.recallNextPullInReason()
        XCTAssertEqual(model.pullInChoice?.activeReasonText, "duplicate of planning")
        model.recallPreviousPullInReason()
        XCTAssertFalse(model.pullInRecall.isRecalling)
        XCTAssertEqual(model.pullInChoice?.activeReasonText, "du")
    }

    @MainActor
    func testRecallClampsAtBottomWithoutWrap() {
        let model = modelWithReason()
        model.recallNextPullInReason()
        model.recallNextPullInReason()
        model.recallNextPullInReason()
        XCTAssertEqual(
            model.pullInChoice?.activeReasonText,
            "superseded by weekly review")
        let seed = model.pullInRecallBumpSeed
        model.recallNextPullInReason()
        XCTAssertEqual(
            model.pullInChoice?.activeReasonText,
            "superseded by weekly review")
        XCTAssertNotEqual(model.pullInRecallBumpSeed, seed)
    }

    @MainActor
    func testReturnStagesVisibleTextAsCancelOffer() {
        let model = modelWithReason()
        model.recallNextPullInReason()
        let key = model.pullInChoice?.activeReasonKey
        model.confirmPullInReason()
        XCTAssertNil(model.pullInChoice?.activeReasonKey)
        guard let key else {
            XCTFail("Missing active reason key")
            return
        }
        guard case .cancel(let reason) = model.pullInChoice?.verdicts[key] else {
            XCTFail("Expected staged cancel verdict")
            return
        }
        XCTAssertEqual(reason, "duplicate of planning")
    }

    @MainActor
    func testRowClickFillsAndBlurDoesNotConfirm() {
        let model = modelWithReason()
        model.updatePullInReasonText("no")
        XCTAssertTrue(model.pullInRecall.shouldShowBand)
        model.selectPullInRecallRow(key: "no longer needed")
        XCTAssertTrue(model.pullInRecall.isRecalling)
        XCTAssertEqual(
            model.pullInChoice?.activeReasonText, "no longer needed")
        // The click's suppress-blur token skips the blur auto-confirm and
        // keeps the field first responder.
        model.pullInReasonFieldDidBlur()
        XCTAssertNotNil(model.pullInChoice?.activeReasonKey)
        XCTAssertEqual(model.focusRequest.target, .pullInReasonField)
    }

    @MainActor
    func testTypingAdoptsShownTextAsDraft() {
        let model = modelWithReason()
        model.recallNextPullInReason()
        XCTAssertTrue(model.pullInRecall.isRecalling)
        model.updatePullInReasonText("duplicate of planning!")
        XCTAssertFalse(model.pullInRecall.isRecalling)
        XCTAssertEqual(model.pullInRecall.draft, "duplicate of planning!")
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
                    )
                )
            )
        }
    }
}
