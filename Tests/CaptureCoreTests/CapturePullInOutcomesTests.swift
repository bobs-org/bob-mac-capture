import XCTest

@testable import CaptureCore

final class CapturePullInOutcomesTests: XCTestCase {
    func testFallbackMarksAndVerdictsAreMutuallyExclusive() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        XCTAssertEqual(outcomes.effectiveSelectionKeys, ["offer:a"])

        outcomes.toggleMark(for: "offer:b")
        XCTAssertEqual(outcomes.effectiveSelectionKeys, ["offer:b"])

        outcomes.toggleVerdict(.done, for: "offer:a")
        XCTAssertEqual(outcomes.highlightedKey, "offer:b")
        XCTAssertEqual(outcomes.marks, Set(["offer:b"]))
        XCTAssertEqual(outcomes.effectiveSelectionKeys, ["offer:b"])

        outcomes.toggleVerdict(.cancel("  no longer needed  "), for: "offer:b")
        XCTAssertEqual(outcomes.verdicts["offer:b"], .cancel("no longer needed"))
        XCTAssertFalse(outcomes.marks.contains("offer:b"))
        XCTAssertEqual(outcomes.effectiveSelectionKeys, [])
    }

    func testSetAdvancesReplaceAdvancesAndClearStaysOnTheRow() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        XCTAssertEqual(outcomes.replaceVerdict(.done, for: "offer:a"), "offer:b")
        XCTAssertEqual(outcomes.highlightedKey, "offer:b")
        XCTAssertEqual(outcomes.replaceVerdict(.cancel("reason"), for: "offer:a"), "offer:b")
        XCTAssertEqual(outcomes.verdicts["offer:a"], .cancel("reason"))

        outcomes.highlight("offer:a")
        XCTAssertEqual(outcomes.clearVerdict(for: "offer:a"), "offer:a")
        XCTAssertEqual(outcomes.highlightedKey, "offer:a")
        XCTAssertNil(outcomes.verdicts["offer:a"])
    }

    func testSameVerdictTogglesBackToLeaveAndIneligibleRowsStayUnchanged() {
        var rows = offers()
        rows[1] = offer("offer:b", n: 2, close: nil)
        var outcomes = CapturePullInOutcomes(offers: rows, closeSupported: true)

        XCTAssertEqual(outcomes.toggleVerdict(.done, for: "offer:a"), "offer:b")
        XCTAssertEqual(outcomes.toggleVerdict(.done, for: "offer:a"), "offer:a")
        XCTAssertNil(outcomes.verdicts["offer:a"])
        XCTAssertEqual(outcomes.replaceVerdict(.cancel("x"), for: "offer:b"), "offer:a")
        XCTAssertNil(outcomes.verdicts["offer:b"])
        XCTAssertEqual(outcomes.refusalReason(for: "offer:b"), nil)
    }

    func testBulkMarksSkipRowsWithVerdicts() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        outcomes.replaceVerdict(.done, for: "offer:a")
        outcomes.setAllMarked(true)
        XCTAssertEqual(outcomes.marks, Set(["offer:b", "offer:c"]))
        XCTAssertEqual(outcomes.verdicts["offer:a"], .done)

        outcomes.toggleAllMarks()
        XCTAssertEqual(outcomes.marks, Set<String>())
        XCTAssertEqual(outcomes.verdicts["offer:a"], .done)
    }

    func testArgvSelectionUsesBobOrderAndDisablesFallbackForVerdicts() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        outcomes.toggleVerdict(.cancel("line one\nline two"), for: "offer:b")
        outcomes.toggleVerdict(.done, for: "offer:c")
        outcomes.toggleMark(for: "offer:a")

        let selection = outcomes.argvSelection()
        XCTAssertEqual(selection.pullInSelection, .keys(["offer:a"]))
        XCTAssertEqual(selection.offerVerdicts.completeKeys, ["offer:c"])
        XCTAssertEqual(
            selection.offerVerdicts.cancelOffers,
            [CapturePullInCancelOffer(key: "offer:b", reason: "line one line two")]
        )

        outcomes.toggleMark(for: "offer:a")
        XCTAssertEqual(outcomes.argvSelection().pullInSelection, .none)
    }

    func testCopyEscStateAndReseedPreserveSurvivingChoices() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        outcomes.replaceVerdict(.done, for: "offer:a")
        outcomes.replaceVerdict(.cancel("reason"), for: "offer:b")
        outcomes.toggleMark(for: "offer:c")
        XCTAssertEqual(outcomes.footerSummaryText, "pull in 1 · ✓ 1 done · ⊘ 1 cancel")
        XCTAssertEqual(outcomes.primaryLabel, "Pull In 1 · Close 2")
        XCTAssertEqual(outcomes.skipLabel, "Skip pull-ins · Close 2")
        XCTAssertTrue(outcomes.armEscDiscard())
        XCTAssertEqual(outcomes.escArmedText, "Esc again to discard 2 closes")

        XCTAssertEqual(outcomes.reseed(validKeys: ["offer:a", "offer:c"]), 1)
        XCTAssertEqual(outcomes.verdicts["offer:a"], .done)
        XCTAssertNil(outcomes.verdicts["offer:b"])
        XCTAssertEqual(outcomes.marks, Set(["offer:c"]))
        XCTAssertEqual(outcomes.highlightedKey, "offer:c")
        XCTAssertNil(outcomes.escArmedText)
    }

    func testBobDescriptorProvidesEligibilityAndConsequenceCopy() {
        let outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        XCTAssertTrue(outcomes.isEligible(.done, for: "offer:a"))
        XCTAssertTrue(outcomes.isEligible(.cancel("reason"), for: "offer:a"))
        XCTAssertEqual(
            outcomes.consequence(for: .done, rowKey: "offer:a"),
            "✓ Completes “Alpha” · Ready → Done"
        )
        XCTAssertEqual(outcomes.scopeNote(for: "offer:a"), "· its 2 open subtasks stay open")

        let unsupported = CapturePullInOutcomes(offers: offers(), closeSupported: false)
        XCTAssertFalse(unsupported.isEligible(.done, for: "offer:a"))
    }

    func testApprovedPrimaryAndSkipLabels() {
        var pullOnly = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        pullOnly.toggleMark(for: "offer:a")
        pullOnly.toggleMark(for: "offer:b")
        XCTAssertEqual(pullOnly.primaryLabel, "Pull In 2")
        XCTAssertEqual(pullOnly.skipLabel, "Skip")

        var verdictOnly = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        verdictOnly.replaceVerdict(.done, for: "offer:a")
        XCTAssertEqual(verdictOnly.primaryLabel, "Close 1")
        XCTAssertEqual(verdictOnly.skipLabel, "Skip pull-ins · Close 1")

        verdictOnly.replaceVerdict(.cancel("why"), for: "offer:b")
        XCTAssertEqual(verdictOnly.primaryLabel, "Close 2")
        XCTAssertEqual(verdictOnly.skipLabel, "Skip pull-ins · Close 2")

        var mixed = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        mixed.toggleMark(for: "offer:a")
        mixed.replaceVerdict(.done, for: "offer:b")
        XCTAssertEqual(mixed.primaryLabel, "Pull In 1 · Close 1")
        XCTAssertEqual(mixed.skipLabel, "Skip pull-ins · Close 1")
    }

    func testVisibleOrderStagingDiffersFromBobOrder() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        let visible = ["offer:c", "offer:a", "offer:b"]
        XCTAssertEqual(
            outcomes.replaceVerdict(.done, for: "offer:c", visibleOrder: visible),
            "offer:a")
        XCTAssertEqual(outcomes.highlightedKey, "offer:a")
        // Argv keeps Bob offer order regardless of staging order.
        outcomes.toggleMark(for: "offer:b")
        let selection = outcomes.argvSelection()
        XCTAssertEqual(selection.pullInSelection, .keys(["offer:b"]))
        XCTAssertEqual(selection.offerVerdicts.completeKeys, ["offer:c"])
    }

    func testRefreshPreservesChoicesAndUpdatesDescriptors() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        outcomes.replaceVerdict(.done, for: "offer:a")
        outcomes.replaceVerdict(.cancel("kept"), for: "offer:b")
        outcomes.toggleMark(for: "offer:c")
        var fresh = offers()
        fresh[0] = offer(
            "offer:a", n: 1,
            close: TaskCompleteOfferClose(
                complete: true, cancel: true,
                completeConsequence: "✓ updated",
                cancelConsequence: "⊘ updated",
                scopeNote: nil, unblocks: 5))
        XCTAssertEqual(outcomes.refresh(rows: fresh), 0)
        XCTAssertEqual(outcomes.verdicts["offer:a"], .done)
        XCTAssertEqual(outcomes.verdicts["offer:b"], .cancel("kept"))
        XCTAssertEqual(outcomes.consequence(for: .done, rowKey: "offer:a"), "✓ updated")
        XCTAssertEqual(outcomes.unblocksCount(for: "offer:a"), 5)
        XCTAssertEqual(outcomes.refresh(rows: Array(fresh.prefix(1))), 2)
        XCTAssertEqual(outcomes.verdicts["offer:a"], .done)
        XCTAssertNil(outcomes.verdicts["offer:b"])
    }

    func testJumpPinTogglesMovesAndClearsWithoutMovingHighlight() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        XCTAssertNil(outcomes.jumpKey)
        let parked = outcomes.highlightedKey

        XCTAssertTrue(outcomes.toggleJump(for: "offer:a"))
        XCTAssertEqual(outcomes.jumpKey, "offer:a")
        XCTAssertEqual(outcomes.highlightedKey, parked)

        XCTAssertTrue(outcomes.toggleJump(for: "offer:b"))
        XCTAssertEqual(outcomes.jumpKey, "offer:b")
        XCTAssertEqual(outcomes.highlightedKey, parked)

        XCTAssertTrue(outcomes.toggleJump(for: "offer:b"))
        XCTAssertNil(outcomes.jumpKey)
        XCTAssertEqual(outcomes.highlightedKey, parked)

        XCTAssertFalse(outcomes.toggleJump(for: "missing"))
        XCTAssertNil(outcomes.jumpKey)
    }

    func testJumpPinSuppressesFallbackAndArmsJumpOnlyCommit() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        XCTAssertEqual(outcomes.effectiveSelectionKeys, ["offer:a"])

        outcomes.toggleJump(for: "offer:b")
        XCTAssertEqual(outcomes.effectiveSelectionKeys, [])
        XCTAssertTrue(outcomes.canCommit)
        XCTAssertEqual(outcomes.primaryLabel, "Leave Open & Jump")
        XCTAssertEqual(outcomes.skipLabel, "Skip & Jump")
        XCTAssertEqual(outcomes.footerSummaryText, "Choose offers · ↗ “Task 2”")
        XCTAssertEqual(outcomes.jumpLabel, "Task 2")

        outcomes.toggleMark(for: "offer:a")
        XCTAssertEqual(outcomes.effectiveSelectionKeys, ["offer:a"])
        XCTAssertEqual(outcomes.primaryLabel, "Pull In 1 & Jump")
        XCTAssertEqual(outcomes.footerSummaryText, "pull in 1 · ↗ “Task 2”")

        outcomes.replaceVerdict(.done, for: "offer:c")
        XCTAssertEqual(outcomes.primaryLabel, "Apply & Jump")
        XCTAssertEqual(outcomes.skipLabel, "Skip pull-ins · Close 1 & Jump")
        XCTAssertNil(outcomes.escArmedText)
        XCTAssertTrue(outcomes.armEscDiscard())
    }

    func testJumpPinSurvivesEscDiscardAndRefreshDropsLostPin() {
        var outcomes = CapturePullInOutcomes(offers: offers(), closeSupported: true)
        outcomes.replaceVerdict(.done, for: "offer:a")
        outcomes.toggleJump(for: "offer:b")
        outcomes.discardVerdicts()
        XCTAssertNil(outcomes.verdicts["offer:a"])
        XCTAssertEqual(outcomes.jumpKey, "offer:b")

        XCTAssertEqual(outcomes.refresh(rows: Array(offers().prefix(1))), 1)
        XCTAssertNil(outcomes.jumpKey)
        XCTAssertNil(outcomes.jumpSummarySuffix)
        // The surviving row's highlight fallback returns untouched behavior.
        XCTAssertEqual(outcomes.effectiveSelectionKeys, ["offer:a"])
        XCTAssertEqual(outcomes.primaryLabel, "Pull In 1")

        outcomes.toggleJump(for: "offer:a")
        XCTAssertEqual(outcomes.refresh(rows: offers()), 0)
        XCTAssertEqual(outcomes.jumpKey, "offer:a")
        XCTAssertEqual(outcomes.jumpSummarySuffix, " · ↗ “Task 1”")
    }

    func testJumpSummaryTruncatesLongLabels() {
        let long = String(repeating: "a", count: 50)
        XCTAssertEqual(
            CapturePullInOutcomes.truncatedJumpLabel(long),
            String(repeating: "a", count: 40) + "…")
        XCTAssertEqual(CapturePullInOutcomes.truncatedJumpLabel("short"), "short")
    }

    private func offers() -> [TaskCompleteUnblocked] {
        [
            offer("offer:a", n: 1),
            offer("offer:b", n: 2),
            offer("offer:c", n: 3),
        ]
    }

    private func offer(
        _ key: String,
        n: Int,
        close: TaskCompleteOfferClose? = TaskCompleteOfferClose(
            complete: true,
            cancel: true,
            completeConsequence: "✓ Completes “Alpha” · Ready → Done",
            cancelConsequence: "⊘ Cancels “Alpha” · Ready → Cancelled",
            scopeNote: "· its 2 open subtasks stay open",
            unblocks: 2
        )
    ) -> TaskCompleteUnblocked {
        TaskCompleteUnblocked(
            notePath: "tasks.md",
            blockID: key,
            text: "Task \(n)",
            offer: TaskCompleteOffer(
                key: key,
                n: n,
                group: "hand_off",
                selected: false,
                close: close
            )
        )
    }
}
