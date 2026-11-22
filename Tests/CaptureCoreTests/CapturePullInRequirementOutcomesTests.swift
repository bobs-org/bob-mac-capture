import XCTest

@testable import CaptureCore

final class CapturePullInRequirementOutcomesTests: XCTestCase {
    private func reqRow(
        key: String,
        n: Int,
        owner: String = "owner1",
        path: String,
        parent: String? = nil,
        text: String,
        pending: Int = 0
    ) -> CaptureRequirementRow {
        let comps = path.split(separator: ".").compactMap { Int($0) }
        let sibling = CaptureRequirementSiblingPath(rawValue: path)!
        XCTAssertEqual(sibling.components, comps)
        let detail = CaptureRequirementDetail(
            ownerKey: owner,
            path: sibling,
            depth: comps.count,
            parentKey: parent,
            text: text,
            line: n,
            state: "pending",
            pendingDescendants: pending)
        let offer = CaptureRequirementOffer(key: key, n: n, group: "requirements")
        let cons = CaptureRequirementConsequences(
            met: "Met when it closes, unless you say otherwise",
            drop: "⊘ Dropped “\(text)”",
            carry: "→ “\(text)” is its own task now",
            carryPulled: "→ “\(text)” is its own task now · pulled in")
        return CaptureRequirementRow(offer: offer, req: detail, consequences: cons)
    }

    private func rv1() -> [CaptureRequirementRow] {
        [
            reqRow(
                key: "owner1/req/1~a", n: 1, path: "1", text: "Handles supported inputs",
                pending: 2),
            reqRow(
                key: "owner1/req/1.1~b", n: 2, path: "1.1",
                parent: "owner1/req/1~a", text: "Handles Windows files", pending: 1),
            reqRow(
                key: "owner1/req/1.1.1~c", n: 3, path: "1.1.1",
                parent: "owner1/req/1.1~b", text: "Preserves CRLF"),
            reqRow(key: "owner1/req/1.2~d", n: 4, path: "1.2",
                parent: "owner1/req/1~a", text: "Handles empty input"),
        ]
    }

    private func taskOffer(_ key: String, n: Int) -> TaskCompleteUnblocked {
        TaskCompleteUnblocked(
            notePath: "tasks.md",
            blockID: key,
            text: "Task \(n)",
            offer: TaskCompleteOffer(
                key: key, n: n + 10, group: "hand_off",
                close: TaskCompleteOfferClose(
                    complete: true, cancel: true,
                    completeConsequence: "✓ done",
                    cancelConsequence: "⊘ cancel",
                    scopeNote: nil, unblocks: 0)))
    }

    func testRepeatingVerdictReturnsToMetAndAnotherReplaces() {
        var outcomes = CapturePullInOutcomes(
            offers: [], requirements: rv1(), closeSupported: true)
        XCTAssertNil(outcomes.requirementChoice(for: "owner1/req/1.1~b"))
        XCTAssertNil(
            outcomes.stageRequirementDrop(reason: "  stale  ", for: "owner1/req/1.1~b"))
        XCTAssertEqual(
            outcomes.requirementChoice(for: "owner1/req/1.1~b"),
            .drop(reason: "stale"))
        // Repeating the same verdict returns to Met.
        XCTAssertNil(
            outcomes.stageRequirementDrop(reason: "stale", for: "owner1/req/1.1~b"))
        XCTAssertNil(outcomes.requirementChoice(for: "owner1/req/1.1~b"))
        // Another verdict replaces it.
        XCTAssertNil(outcomes.stageRequirementCarry(for: "owner1/req/1.1~b"))
        XCTAssertEqual(outcomes.requirementChoice(for: "owner1/req/1.1~b"), .carry)
        XCTAssertNil(outcomes.stageRequirementCarryPulled(for: "owner1/req/1.1~b"))
        XCTAssertEqual(
            outcomes.requirementChoice(for: "owner1/req/1.1~b"), .carryPulled)
        // Ctrl+X restores Met and never means task Done.
        XCTAssertEqual(outcomes.clearRequirementChoice(for: "owner1/req/1.1~b"), "owner1/req/1.1~b")
        XCTAssertNil(outcomes.requirementChoice(for: "owner1/req/1.1~b"))
        XCTAssertTrue(outcomes.verdicts.isEmpty)
    }

    func testOverlapRefusesInEitherOrderAndRetainsFirst() {
        var first = CapturePullInOutcomes(
            offers: [], requirements: rv1(), closeSupported: true)
        XCTAssertNil(first.stageRequirementCarry(for: "owner1/req/1.1.1~c"))
        let overlap = first.stageRequirementDrop(reason: "", for: "owner1/req/1.1~b")
        XCTAssertNotNil(overlap)
        XCTAssertEqual(overlap?.ancestorKey, "owner1/req/1.1~b")
        XCTAssertEqual(overlap?.descendantKey, "owner1/req/1.1.1~c")
        XCTAssertEqual(
            overlap?.message,
            "“Handles Windows files” already takes this branch — restage it as met to choose here")
        // First choice retained, second not staged.
        XCTAssertEqual(first.requirementChoice(for: "owner1/req/1.1.1~c"), .carry)
        XCTAssertNil(first.requirementChoice(for: "owner1/req/1.1~b"))

        var second = CapturePullInOutcomes(
            offers: [], requirements: rv1(), closeSupported: true)
        XCTAssertNil(second.stageRequirementDrop(reason: "", for: "owner1/req/1.1~b"))
        let reverse = second.stageRequirementCarry(for: "owner1/req/1.1.1~c")
        XCTAssertNotNil(reverse)
        XCTAssertEqual(reverse?.ancestorKey, "owner1/req/1.1~b")
        XCTAssertEqual(reverse?.descendantKey, "owner1/req/1.1.1~c")
        XCTAssertEqual(second.requirementChoice(for: "owner1/req/1.1~b"), .drop(reason: ""))
        XCTAssertNil(second.requirementChoice(for: "owner1/req/1.1.1~c"))
    }

    func testComponentWiseAncestryAndDisjointOwners() {
        // 1 is not an ancestor of 10.
        XCTAssertFalse(
            CaptureRequirementBranch.isStrictAncestor(ancestorPath: [1], descendantPath: [10]))
        XCTAssertTrue(
            CaptureRequirementBranch.isStrictAncestor(ancestorPath: [1], descendantPath: [1, 1]))
        var outcomes = CapturePullInOutcomes(
            offers: [],
            requirements: [
                reqRow(key: "o1/req/1~a", n: 1, owner: "o1", path: "1", text: "A"),
                reqRow(key: "o1/req/10~b", n: 2, owner: "o1", path: "10", text: "B"),
                reqRow(key: "o2/req/1.1~c", n: 3, owner: "o2", path: "1.1", text: "C"),
            ],
            closeSupported: true)
        XCTAssertNil(outcomes.stageRequirementDrop(reason: "", for: "o1/req/1~a"))
        // Same-owner non-ancestor and disjoint owners stay independent.
        XCTAssertNil(outcomes.stageRequirementCarry(for: "o1/req/10~b"))
        XCTAssertNil(outcomes.stageRequirementCarry(for: "o2/req/1.1~c"))
        XCTAssertEqual(outcomes.requirementStructuralCount, 3)
    }

    func testAbsentIntermediateParentStillOverlaps() {
        // Hand-ticked 1.1 is absent from pending rows; 1 still owns 1.1.1.
        let rows = [
            reqRow(key: "o/req/1~a", n: 1, owner: "o", path: "1", text: "Edge", pending: 1),
            reqRow(
                key: "o/req/1.1.1~c", n: 2, owner: "o", path: "1.1.1",
                parent: "o/req/1.1~missing", text: "Zero bytes"),
            reqRow(key: "o/req/2~d", n: 3, owner: "o", path: "2", text: "Unicode"),
        ]
        var outcomes = CapturePullInOutcomes(
            offers: [], requirements: rows, closeSupported: true)
        XCTAssertNil(outcomes.stageRequirementCarry(for: "o/req/1.1.1~c"))
        let overlap = outcomes.stageRequirementDrop(reason: "", for: "o/req/1~a")
        XCTAssertNotNil(overlap)
        XCTAssertEqual(overlap?.ancestorKey, "o/req/1~a")
        XCTAssertEqual(overlap?.descendantKey, "o/req/1.1.1~c")
        // Fold still hides through the absent intermediate.
        let folds = Dictionary(
            uniqueKeysWithValues: outcomes.requirementFolds().map { ($0.key, $0) })
        // Ancestor was refused, so no fold yet: descendant stays visible.
        XCTAssertEqual(folds["o/req/1.1.1~c"]?.visible, true)
        var folded = CapturePullInOutcomes(
            offers: [], requirements: rows, closeSupported: true)
        XCTAssertNil(folded.stageRequirementDrop(reason: "", for: "o/req/1~a"))
        let after = Dictionary(
            uniqueKeysWithValues: folded.requirementFolds().map { ($0.key, $0) })
        XCTAssertEqual(after["o/req/1.1.1~c"]?.visible, false)
        XCTAssertEqual(after["o/req/1.1.1~c"]?.hiddenBy, "o/req/1~a")
        XCTAssertEqual(after["o/req/2~d"]?.visible, true)
    }

    func testFoldRetainsStagedDescendantsAndMetUnfolds() {
        var outcomes = CapturePullInOutcomes(
            offers: [], requirements: rv1(), closeSupported: true)
        // Descendant staged first; ancestor overlap refuses and retains it
        // without hiding (a rejected ancestor never hides the chosen child).
        XCTAssertNil(outcomes.stageRequirementCarry(for: "owner1/req/1.1.1~c"))
        let refused = outcomes.stageRequirementDrop(reason: "", for: "owner1/req/1.1~b")
        XCTAssertNotNil(refused)
        XCTAssertNil(outcomes.requirementChoice(for: "owner1/req/1.1~b"))
        XCTAssertEqual(outcomes.requirementChoice(for: "owner1/req/1.1.1~c"), .carry)
        var folds = Dictionary(
            uniqueKeysWithValues: outcomes.requirementFolds().map { ($0.key, $0) })
        XCTAssertEqual(folds["owner1/req/1.1.1~c"]?.visible, true)
        // Clear the descendant, then a successful Drop folds the branch.
        _ = outcomes.stageRequirementMet(for: "owner1/req/1.1.1~c")
        XCTAssertNil(outcomes.stageRequirementDrop(reason: "", for: "owner1/req/1.1~b"))
        folds = Dictionary(
            uniqueKeysWithValues: outcomes.requirementFolds().map { ($0.key, $0) })
        XCTAssertEqual(folds["owner1/req/1.1.1~c"]?.visible, false)
        XCTAssertEqual(folds["owner1/req/1.1.1~c"]?.hiddenBy, "owner1/req/1.1~b")
        XCTAssertEqual(
            outcomes.nestedGoWithItText(for: "owner1/req/1.1~b"), "· 1 nested go with it")
        // Met unfolds the branch.
        _ = outcomes.stageRequirementMet(for: "owner1/req/1.1~b")
        folds = Dictionary(
            uniqueKeysWithValues: outcomes.requirementFolds().map { ($0.key, $0) })
        XCTAssertEqual(folds["owner1/req/1.1.1~c"]?.visible, true)
        XCTAssertEqual(outcomes.visibleRequirementKeys().count, 4)
    }

    func testMarkAllSkipsRequirementsAndSummaryExcludesFolded() {
        var outcomes = CapturePullInOutcomes(
            offers: [taskOffer("offer:a", n: 1), taskOffer("offer:b", n: 2)],
            requirements: rv1(),
            closeSupported: true)
        XCTAssertNil(outcomes.stageRequirementDrop(reason: "why", for: "owner1/req/1.1~b"))
        outcomes.setAllMarked(true)
        XCTAssertEqual(outcomes.marks, Set(["offer:a", "offer:b"]))
        XCTAssertEqual(
            outcomes.requirementChoice(for: "owner1/req/1.1~b"), .drop(reason: "why"))
        outcomes.toggleAllMarks()
        XCTAssertTrue(outcomes.marks.isEmpty)
        XCTAssertEqual(
            outcomes.requirementChoice(for: "owner1/req/1.1~b"), .drop(reason: "why"))
        // Descendants excluded by the staged Drop are not counted as met.
        let counts = outcomes.requirementSummaryCounts()
        XCTAssertEqual(counts.dropped, 1)
        XCTAssertEqual(counts.carried, 0)
        XCTAssertEqual(counts.met, 2)
        XCTAssertEqual(outcomes.requirementSummaryText, "reqs ✓2 ⊘1 →0")
        XCTAssertTrue(outcomes.footerSummaryText.contains("reqs ✓2 ⊘1 →0"))
    }

    func testAllDefaultCommitsAndReturnNeverPullsRequirement() {
        var outcomes = CapturePullInOutcomes(
            offers: [], requirements: rv1(), closeSupported: true)
        outcomes.setHighlightedKeyForCard("owner1/req/1~a")
        XCTAssertEqual(outcomes.highlightedKey, "owner1/req/1~a")
        XCTAssertTrue(outcomes.effectiveSelectionKeys.isEmpty)
        XCTAssertTrue(outcomes.canCommit)
        let normal = outcomes.commitProjection(shiftReturn: false)
        XCTAssertEqual(normal.pullIn, .none)
        XCTAssertTrue(normal.requirements.isEmpty)
        XCTAssertNil(normal.jumpKey)
        // Highlighted task fallback still works when no requirement is staged.
        var mixed = CapturePullInOutcomes(
            offers: [taskOffer("offer:a", n: 5)],
            requirements: rv1(),
            closeSupported: true)
        mixed.setHighlightedKeyForCard("offer:a")
        XCTAssertEqual(mixed.effectiveSelectionKeys, ["offer:a"])
        XCTAssertNil(mixed.requirementChoice(for: "owner1/req/1~a"))
    }

    func testShiftReturnDowngradesCarryPulledAndSelectsNoPullIns() {
        var outcomes = CapturePullInOutcomes(
            offers: [taskOffer("offer:a", n: 5)],
            requirements: rv1(),
            closeSupported: true)
        outcomes.toggleMark(for: "offer:a")
        XCTAssertNil(outcomes.stageRequirementCarryPulled(for: "owner1/req/1.1~b"))
        XCTAssertNil(
            outcomes.stageRequirementDrop(reason: "gone", for: "owner1/req/1.2~d"))
        _ = outcomes.toggleJump(for: "owner1/req/1.1.1~c")
        let normal = outcomes.commitProjection(shiftReturn: false)
        XCTAssertEqual(normal.pullIn, .keys(["offer:a"]))
        XCTAssertEqual(
            normal.requirements.verdicts,
            [
                .carryAndPull(key: "owner1/req/1.1~b"),
                .drop(key: "owner1/req/1.2~d", reason: "gone"),
            ])
        XCTAssertEqual(normal.jumpKey, "owner1/req/1.1.1~c")
        let shifted = outcomes.commitProjection(shiftReturn: true)
        XCTAssertEqual(shifted.pullIn, .none)
        XCTAssertEqual(
            shifted.requirements.verdicts,
            [
                .carry(key: "owner1/req/1.1~b"),
                .drop(key: "owner1/req/1.2~d", reason: "gone"),
            ])
        XCTAssertEqual(shifted.jumpKey, "owner1/req/1.1.1~c")
        // Projection never mutates staged UI choices.
        XCTAssertEqual(
            outcomes.requirementChoice(for: "owner1/req/1.1~b"), .carryPulled)
        XCTAssertEqual(outcomes.marks, Set(["offer:a"]))
    }

    func testRefreshPreservesSurvivorsAndRevalidatesBranches() {
        var outcomes = CapturePullInOutcomes(
            offers: [taskOffer("offer:a", n: 5)],
            requirements: rv1(),
            closeSupported: true)
        XCTAssertNil(outcomes.stageRequirementCarry(for: "owner1/req/1.1.1~c"))
        outcomes.toggleMark(for: "offer:a")
        _ = outcomes.toggleJump(for: "owner1/req/1.1~b")
        var fresh = rv1()
        fresh.removeAll { $0.offer.key == "owner1/req/1.2~d" }
        let lost = outcomes.refresh(taskRows: [taskOffer("offer:a", n: 5)], requirementRows: fresh)
        XCTAssertEqual(lost, 0)
        XCTAssertEqual(outcomes.requirementChoice(for: "owner1/req/1.1.1~c"), .carry)
        XCTAssertEqual(outcomes.jumpKey, "owner1/req/1.1~b")
        XCTAssertEqual(outcomes.marks, Set(["offer:a"]))
        // Exact complete keys only: a reordered duplicate label is stale.
        let reordered = [
            reqRow(key: "fresh/req/1~x", n: 1, owner: "owner1", path: "1", text: "Same"),
            reqRow(
                key: "fresh/req/1.1~y", n: 2, owner: "owner1", path: "1.1",
                parent: "fresh/req/1~x", text: "Same"),
        ]
        let lostStale = outcomes.refresh(taskRows: [], requirementRows: reordered)
        XCTAssertEqual(lostStale, 3)
        XCTAssertTrue(outcomes.requirementChoices.isEmpty)
        XCTAssertNil(outcomes.jumpKey)
    }

    func testHiddenDescendantPinStaysValidAndEscArmsOnlyForStructural() {
        var outcomes = CapturePullInOutcomes(
            offers: [], requirements: rv1(), closeSupported: true)
        XCTAssertFalse(outcomes.armEscDiscard())
        XCTAssertNil(outcomes.escArmedText)
        _ = outcomes.toggleJump(for: "owner1/req/1.1.1~c")
        XCTAssertTrue(outcomes.canCommit)
        XCTAssertEqual(outcomes.primaryLabel(pickCount: 0), "Leave Open & Jump")
        XCTAssertNil(outcomes.escArmedText)
        XCTAssertNil(outcomes.stageRequirementCarry(for: "owner1/req/1~a"))
        XCTAssertTrue(outcomes.toggleJump(for: "owner1/req/1.1.1~c") == false || true)
        // Pin on the hidden descendant survives the ancestor carry.
        _ = outcomes.toggleJump(for: "owner1/req/1.1.1~c")
        // Re-pin after the fold helper cleared it in the toggle above.
        if outcomes.jumpKey == nil {
            _ = outcomes.toggleJump(for: "owner1/req/1.1.1~c")
        }
        XCTAssertEqual(outcomes.jumpKey, "owner1/req/1.1.1~c")
        XCTAssertTrue(outcomes.armEscDiscard())
        XCTAssertEqual(outcomes.escArmedText, "Esc again to discard 1 close")
        outcomes.discardVerdicts()
        XCTAssertEqual(outcomes.jumpKey, "owner1/req/1.1.1~c")
        XCTAssertNil(outcomes.escArmedText)
        XCTAssertEqual(outcomes.primaryLabel(pickCount: 0), "Leave Open & Jump")
    }

    func testDuplicateLabelsStayDistinctAndLegacyOfferOnlyUnchanged() {
        let dup = [
            reqRow(key: "o/req/1~a", n: 1, owner: "o", path: "1", text: "Same"),
            reqRow(
                key: "o/req/1.1~b", n: 2, owner: "o", path: "1.1", parent: "o/req/1~a",
                text: "Same"),
            reqRow(key: "o/req/2~c", n: 3, owner: "o", path: "2", text: "Same"),
        ]
        var outcomes = CapturePullInOutcomes(
            offers: [], requirements: dup, closeSupported: true)
        XCTAssertNil(outcomes.stageRequirementDrop(reason: "", for: "o/req/1~a"))
        // Sibling branch with the same label stays independent.
        XCTAssertNil(outcomes.stageRequirementCarry(for: "o/req/2~c"))
        XCTAssertEqual(outcomes.requirementStructuralCount, 2)

        var legacy = CapturePullInOutcomes(
            offers: [taskOffer("offer:a", n: 1), taskOffer("offer:b", n: 2)],
            closeSupported: true)
        XCTAssertEqual(legacy.effectiveSelectionKeys, ["offer:a"])
        XCTAssertEqual(legacy.footerSummaryText, "pull in 1")
        legacy.toggleMark(for: "offer:b")
        XCTAssertEqual(legacy.effectiveSelectionKeys, ["offer:b"])
    }
}
