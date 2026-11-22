import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// card_ui: requirement sections render first with Bob copy, depth glyphs,
/// folds, consequences and summaries; Ctrl+X / Ctrl+Shift+X / Ctrl+Shift+T /
/// Space / Tab / Ctrl+J wire through router, controller and reason UI while
/// ordinary offers, text focus, mark-all and Esc stay intact.
@MainActor
final class CapturePullInRequirementCardTests: XCTestCase {
    private static let ownerA = "Tasks.md#^ship@aaa111"
    private static let ownerB = "Tasks.md#^docs@bbb222"

    private func makeReq(
        key: String,
        n: Int,
        owner: String,
        path: String,
        depth: Int,
        text: String,
        pending: Int = 0,
        met: String = "Met copy",
        drop: String = "Drop copy",
        carry: String = "Carry copy",
        carryPulled: String = "Pull copy"
    ) -> CaptureRequirementRow {
        let offer = CaptureRequirementOffer(key: key, n: n, group: "requirements", selected: false)
        let detail = CaptureRequirementDetail(
            ownerKey: owner,
            path: CaptureRequirementSiblingPath(rawValue: path)!,
            depth: depth,
            parentKey: nil,
            text: text,
            line: 1,
            state: "pending",
            pendingDescendants: pending)
        let cons = CaptureRequirementConsequences(
            met: met, drop: drop, carry: carry, carryPulled: carryPulled)
        return CaptureRequirementRow(offer: offer, req: detail, consequences: cons)
    }

    private func makeGroup(
        ownerKey: String,
        ownerText: String,
        rows: [CaptureRequirementRow],
        title: String? = nil,
        scope: String? = nil,
        why: String? = nil,
        history: String? = nil,
        footer: String? = nil
    ) -> CapturePullInGroup {
        let owner = CaptureRequirementOwner(
            taskKey: "Tasks.md#^ship", key: ownerKey, path: "Tasks.md",
            blockID: "ship", line: 1, text: ownerText)
        let copy = CapturePullInGroupCopy(
            title: title ?? "Requirements · “\(ownerText)”",
            why: why ?? "Met when it closes",
            tag: nil, fold: nil, glyph: "⌗⌗",
            scope: scope ?? "\(rows.count) reqs",
            history: history, footer: footer, hint: nil)
        return CapturePullInGroup(
            group: "requirements", kind: "requirements", owner: owner,
            rows: rows, copy: copy)
    }

    private func makeState(
        reqRows: [CaptureRequirementRow],
        groups: [CapturePullInGroup],
        ordinary: [CapturePullInChoiceRow] = [],
        highlighted: String? = nil
    ) -> CapturePullInChoiceState {
        let pullIn = CapturePullIn(
            supported: true, offerCount: ordinary.count, choice: "explicit",
            pickedCount: 0, groups: groups,
            close: CapturePullInClose(supported: true),
            jump: CapturePullInJump(supported: true),
            reqs: CapturePullInRequirementCapability(supported: true, pending: reqRows.count))
        return CapturePullInChoiceState(
            draftSnapshot: "draft", processClientIdentity: "id",
            openAfterCapture: false, priorityRollSeed: "seed",
            generation: 1, requestID: nil, pullIn: pullIn,
            rows: ordinary, highlightedKey: highlighted)
    }

    func testDepthGlyphsFollowMarkerRule() {
        XCTAssertEqual(CapturePullInChoiceSection.depthGlyph(for: 1), "⌗⌗")
        XCTAssertEqual(CapturePullInChoiceSection.depthGlyph(for: 2), "⌗⌗⌗")
        XCTAssertEqual(CapturePullInChoiceSection.depthGlyph(for: 3), "⌗⌗⌗⌗")
        XCTAssertEqual(CapturePullInChoiceSection.depthGlyph(for: 5), "⌗⌗⌗⌗")
    }

    func testRequirementSectionsLeadWithBobCopyAndCounts() {
        let r1 = makeReq(
            key: "k1", n: 1, owner: Self.ownerA, path: "1", depth: 1, text: "Alpha")
        let r2 = makeReq(
            key: "k2", n: 2, owner: Self.ownerB, path: "1", depth: 1, text: "Beta")
        let gA = makeGroup(
            ownerKey: Self.ownerA, ownerText: "Ship", rows: [r1],
            scope: "1 req", why: "Met when it closes", history: "Filed yesterday")
        let gB = makeGroup(ownerKey: Self.ownerB, ownerText: "Docs", rows: [r2])
        // Bob order is B then A in groups; sections must preserve Bob order.
        var state = makeState(reqRows: [r1, r2], groups: [gB, gA], highlighted: "k1")
        XCTAssertEqual(state.sections.map(\.ownerKey), [Self.ownerB, Self.ownerA])
        let first = state.sections[0]
        XCTAssertTrue(first.isRequirement)
        XCTAssertEqual(first.requirementScope, "1 reqs")
        XCTAssertEqual(state.sections[1].requirementScope, "1 req")
        XCTAssertEqual(first.selectableRequirementCount, 1)
        XCTAssertEqual(state.footerSummaryText, "reqs ✓2 ⊘0 →0")
        // Filtering keeps header match and hides nothing for header match.
        state.updateFilter("docs")
        XCTAssertEqual(state.visibleRequirementKeys, ["k2"])
        state.updateFilter("")
        // Disjoint owners never fold each other: both stay visible.
        state.stageRequirementCarry(r1.offer.key)
        XCTAssertEqual(Set(state.visibleRequirementKeys), Set(["k1", "k2"]))
        XCTAssertEqual(state.outcomes.requirementChoices[r1.offer.key], .carry)
    }

    func testSpaceStaysTabAdvancesOnRequirement() {
        let r1 = makeReq(
            key: "k1", n: 1, owner: Self.ownerA, path: "1", depth: 1, text: "One")
        let r2 = makeReq(
            key: "k2", n: 2, owner: Self.ownerA, path: "2", depth: 1, text: "Two")
        let group = makeGroup(ownerKey: Self.ownerA, ownerText: "Ship", rows: [r1, r2])
        var state = makeState(reqRows: [r1, r2], groups: [group], highlighted: "k1")
        // Space stages Carry-plus-pull and stays.
        state.toggleHighlighted()
        XCTAssertEqual(state.requirementChoice(for: "k1"), .carryPulled)
        XCTAssertEqual(state.highlightedKey, "k1")
        // Space again returns to Met (repeat returns to Met) and stays.
        state.toggleHighlighted()
        XCTAssertNil(state.requirementChoice(for: "k1"))
        XCTAssertEqual(state.highlightedKey, "k1")
        // Tab stages again then advances once to k2.
        state.toggleHighlightedAndAdvance()
        XCTAssertEqual(state.requirementChoice(for: "k1"), .carryPulled)
        XCTAssertEqual(state.highlightedKey, "k2")
    }

    func testCtrlXMetCtrlShiftTCarryAndDropReasonFlow() {
        let r1 = makeReq(
            key: "k1", n: 1, owner: Self.ownerA, path: "1", depth: 1, text: "One")
        let group = makeGroup(ownerKey: Self.ownerA, ownerText: "Ship", rows: [r1])
        var state = makeState(reqRows: [r1], groups: [group], highlighted: "k1")
        state.stageRequirementCarry(r1.offer.key)
        XCTAssertEqual(state.requirementChoice(for: "k1"), .carry)
        state.stageRequirementMet(r1.offer.key)
        XCTAssertNil(state.requirementChoice(for: "k1"))
        state.beginRequirementDrop(r1.offer.key)
        XCTAssertEqual(state.activeReasonKey, "k1")
        state.updateReasonText("  No longer  needed ")
        state.confirmRequirementDrop()
        XCTAssertEqual(state.requirementChoice(for: "k1"), .drop(reason: "No longer needed"))
        // Same Drop chord clears to Met.
        state.beginRequirementDrop(r1.offer.key)
        XCTAssertNil(state.requirementChoice(for: "k1"))
        XCTAssertNil(state.activeReasonKey)
    }

    func testOverlapRefusesBothOrdersWithoutClearing() {
        let parent = makeReq(
            key: "parent", n: 1, owner: Self.ownerA, path: "1", depth: 1,
            text: "Parent", pending: 1)
        let child = makeReq(
            key: "child", n: 2, owner: Self.ownerA, path: "1.1", depth: 2, text: "Child")
        let group = makeGroup(
            ownerKey: Self.ownerA, ownerText: "Ship", rows: [parent, child])
        var state = makeState(reqRows: [parent, child], groups: [group], highlighted: "parent")
        state.stageRequirementCarry(parent.offer.key)
        XCTAssertEqual(state.requirementChoice(for: "parent"), .carry)
        state.stageRequirementCarry(child.offer.key)
        XCTAssertNil(state.requirementChoice(for: "child"))
        XCTAssertTrue(state.verdictRefusalMessage?.contains("Parent") == true)
        XCTAssertEqual(state.requirementChoice(for: "parent"), .carry)
        // Reverse order: child first, then ancestor refuses and keeps child.
        var reverse = makeState(reqRows: [parent, child], groups: [group], highlighted: "child")
        reverse.stageRequirementCarryPulled(child.offer.key)
        XCTAssertEqual(reverse.requirementChoice(for: "child"), .carryPulled)
        reverse.stageRequirementCarry(parent.offer.key)
        XCTAssertEqual(reverse.requirementChoice(for: "child"), .carryPulled)
        XCTAssertTrue(reverse.verdictRefusalMessage?.contains("Parent") == true)
    }

    func testMarkAllExcludesRequirementsAndFooterHints() {
        let req = makeReq(
            key: "req1", n: 1, owner: Self.ownerA, path: "1", depth: 1, text: "Req")
        let group = makeGroup(ownerKey: Self.ownerA, ownerText: "Ship", rows: [req])
        var state = makeState(reqRows: [req], groups: [group], highlighted: "req1")
        state.markAll()
        XCTAssertTrue(state.markedKeys.isEmpty)
        XCTAssertNil(state.requirementChoice(for: "req1"))
        let hints = CapturePullInChoiceFooter.hintItems(
            openAfterCapture: false, closeSupported: true,
            jumpSupported: true, jumpPinned: false, hasRequirements: true)
        XCTAssertTrue(hints.contains { $0.keys == "⌃X" && $0.action == "Met" })
        XCTAssertTrue(hints.contains { $0.keys == "⌃⇧T" && $0.action == "Own task" })
        XCTAssertTrue(hints.contains { $0.keys == "space" && $0.action == "Pull in" })
        let plain = CapturePullInChoiceFooter.hintItems(
            openAfterCapture: false, closeSupported: true,
            jumpSupported: true, jumpPinned: false, hasRequirements: false)
        XCTAssertTrue(plain.contains { $0.keys == "⌃X" && $0.action == "Done" })
    }

    func testReasonPromptAccessibilityAndSummary() {
        let req = makeReq(
            key: "req1", n: 3, owner: Self.ownerA, path: "1.2.1", depth: 3,
            text: "Deep task", pending: 2)
        let group = makeGroup(ownerKey: Self.ownerA, ownerText: "Ship", rows: [req])
        var state = makeState(reqRows: [req], groups: [group], highlighted: "req1")
        XCTAssertEqual(
            state.requirementAccessibility(for: "req1"),
            "requirement, level 3, will be met")
        state.stageRequirementCarryPulled("req1")
        XCTAssertEqual(
            state.requirementAccessibility(for: "req1"),
            "requirement, level 3, will be its own task and pulled in")
        XCTAssertEqual(state.outcomes.nestedGoWithItText(for: "req1"), "· 2 nested go with it")
        XCTAssertEqual(state.footerSummaryText, "reqs ✓0 ⊘0 →1")
        let text = CapturePullInChoiceFooter.intentAccessibilityText(
            isOnlyNotePull: false, hasVerdicts: true,
            jumpPinned: false, openAfterCapture: false, hasRequirements: true)
        XCTAssertTrue(text.contains("Control-Shift-T makes it its own task"))
    }

    func testRouterCarryChordActsOnlyOnRequirements() {
        let router = CaptureKeyCommandRouter()
        func event(_ code: UInt16, _ mods: NSEvent.ModifierFlags) -> NSEvent {
            NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: mods,
                timestamp: 0, windowNumber: 0, context: nil,
                characters: "", charactersIgnoringModifiers: "",
                isARepeat: false, keyCode: code)!
        }
        let context = CaptureKeyRoutingContext(
            pullInChoiceVisible: true, pullInFilterFocused: false,
            pullInFilterIsEmpty: true)
        XCTAssertEqual(
            router.command(
                for: event(17, [.control, .shift]), context: context),
            .stageRequirementCarry)
        XCTAssertEqual(
            router.command(for: event(17, .control), context: context), .consumeKey)
        XCTAssertEqual(
            router.command(for: event(7, .control), context: context), .stagePullInDone)
        XCTAssertEqual(
            router.command(
                for: event(7, [.control, .shift]), context: context), .beginPullInCancel)
    }
}
