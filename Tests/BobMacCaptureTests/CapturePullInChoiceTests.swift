import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

final class CapturePullInChoiceTests: XCTestCase {
    func testOneSixElevenAndTwentyOffersRemainReachableInBobOrder() {
        for count in [1, 6, 11, 20] {
            var state = choiceState(offers: offers(count: count))
            let bobOrderKeys = (1...count).map { "opaque#\($0)^suffix" }
            XCTAssertEqual(state.markedKeys, [], "Offers begin unmarked for count \(count)")
            XCTAssertEqual(state.selectableKeys, bobOrderKeys)
            XCTAssertEqual(Set(state.visibleSelectableKeys), Set(bobOrderKeys))
            XCTAssertEqual(state.effectiveSelectionKeys, ["opaque#1^suffix"])
            // Arrow keys walk the grouped visible list (hand-offs, then project),
            // not bob number order, and clamp at the ends.
            state.moveHighlight(by: count + 5)
            let lastVisible = state.visibleSelectableKeys.last
            XCTAssertEqual(state.highlightedKey, lastVisible)
            XCTAssertEqual(state.effectiveSelectionKeys, lastVisible.map { [$0] } ?? [])
        }
    }

    func testMarkAllSubsetFilterAndCollapsePreserveOpaqueMarks() throws {
        var state = choiceState(offers: offers(count: 20))
        let project = try XCTUnwrap(state.sections.first(where: { $0.group == "project" }))
        let projectKey = try XCTUnwrap(project.rows.first?.offerKey)
        let handOff = try XCTUnwrap(state.sections.first(where: { $0.group == "hand_off" }))
        let handOffKey = try XCTUnwrap(handOff.rows.first?.offerKey)

        state.highlightedKey = projectKey
        state.toggleHighlighted()
        XCTAssertEqual(state.effectiveSelectionKeys, [projectKey])
        state.highlightedKey = handOffKey
        state.toggleHighlighted()
        XCTAssertEqual(
            state.effectiveSelectionKeys,
            [handOffKey, projectKey].sorted {
                state.selectableKeys.firstIndex(of: $0)! < state.selectableKeys.firstIndex(of: $1)!
            })

        state.markAll()
        XCTAssertEqual(state.effectivePickCount, 20)
        state.updateFilter("Task 19")
        XCTAssertEqual(state.visibleSelectableKeys, ["opaque#19^suffix"])
        XCTAssertEqual(state.effectivePickCount, 20, "Filtering does not discard hidden marks")

        state.updateFilter("")
        state.toggleGroup(project.id)
        XCTAssertTrue(state.visibleRows(in: project).isEmpty)
        state.updateFilter("Task 1")
        XCTAssertTrue(state.visibleRows(in: project).contains(where: { $0.text == "Task 19" }))
        XCTAssertTrue(state.visibleSelectableKeys.contains("opaque#19^suffix"))
        XCTAssertEqual(state.markedKeys.count, 20)
    }

    func testNoMatchDoesNotTurnReturnIntoChooseNoneAndBudgetIsOnlyAWarning() {
        var state = choiceState(
            offers: offers(count: 2),
            planBudget: CapturePlanBudget(
                status: "over",
                links: CapturePlanBudgetMeter(count: 4, cap: 5, over: false)
            )
        )
        XCTAssertEqual(state.projectedLinkCount, 5)
        XCTAssertFalse(state.projectedLinksOverCap)
        state.markAll()
        XCTAssertEqual(state.projectedLinkCount, 6)
        XCTAssertTrue(state.projectedLinksOverCap)

        state.markedKeys = []
        state.updateFilter("no matching offer")
        XCTAssertTrue(state.visibleSelectableKeys.isEmpty)
        XCTAssertTrue(state.effectiveSelectionKeys.isEmpty)
        XCTAssertNil(state.highlightedKey)
    }

    func testMutedResidentsAndFoldedProjectCountsAreNeverSelectable() throws {
        let projectPath = "projects/sase_foo.md"
        let state = choiceState(
            offers: [offer(n: 1, group: "project", project: projectPath)],
            stillBlocked: [
                TaskCompleteStillBlocked(
                    notePath: projectPath,
                    blockID: "still-waiting",
                    line: 11,
                    text: "Waiting resident",
                    statusSymbol: "?",
                    statusName: "Blocked",
                    reason: "project",
                    project: projectPath
                )
            ],
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 1,
                groups: [
                    CapturePullInGroup(
                        group: "project",
                        project: projectPath,
                        folded: CapturePullInFolded(hidden: 2, alreadyPlanned: 3, subProjects: 4)
                    )
                ]
            )
        )
        let project = try XCTUnwrap(state.sections.first(where: { $0.group == "project" }))
        XCTAssertEqual(project.title, "Project sase_foo")
        XCTAssertEqual(project.folded?.hidden, 2)
        XCTAssertEqual(project.folded?.alreadyPlanned, 3)
        XCTAssertEqual(project.folded?.subProjects, 4)
        XCTAssertEqual(project.rows.count, 2)
        XCTAssertEqual(project.rows.filter(\.isSelectable).count, 1)
        XCTAssertEqual(state.visibleSelectableKeys, ["opaque#1^suffix"])
        XCTAssertEqual(
            project.rows.first(where: { !$0.isSelectable })?.detailText,
            "stays Blocked · blocked by project sase_foo")
    }

    func testRouterOwnsChoiceKeysAndLeavesFilterTypingNative() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(pullInChoiceVisible: true, pickerVisible: true)

        XCTAssertEqual(router.command(for: keyEvent(36), context: context), .confirmPullInChoice)
        XCTAssertEqual(router.command(for: keyEvent(76), context: context), .confirmPullInChoice)
        XCTAssertEqual(
            router.command(for: keyEvent(36, modifiers: .shift), context: context),
            .chooseNoPullInOffers)
        XCTAssertEqual(
            router.command(for: keyEvent(36, modifiers: .command), context: context), .consumeKey)
        XCTAssertEqual(
            router.command(for: keyEvent(36, repeat: true), context: context), .consumeKey)
        XCTAssertEqual(router.command(for: keyEvent(53), context: context), .cancelPullInChoice)
        XCTAssertEqual(
            router.command(for: keyEvent(33, modifiers: .control), context: context),
            .cancelPullInChoice)
        XCTAssertEqual(router.command(for: keyEvent(126), context: context), .previousPullInOffer)
        XCTAssertEqual(router.command(for: keyEvent(125), context: context), .nextPullInOffer)
        XCTAssertEqual(
            router.command(for: keyEvent(45, modifiers: .control), context: context),
            .nextPullInOffer)
        XCTAssertEqual(
            router.command(for: keyEvent(35, modifiers: .control), context: context),
            .previousPullInOffer)
        XCTAssertEqual(
            router.command(for: keyEvent(45, modifiers: .control, repeat: true), context: context),
            .nextPullInOffer)
        let focusedContext = CaptureKeyRoutingContext(
            pullInChoiceVisible: true, pullInFilterFocused: true)
        XCTAssertEqual(
            router.command(for: keyEvent(45, modifiers: .control), context: focusedContext),
            .nextPullInOffer)
        XCTAssertEqual(
            router.command(for: keyEvent(35, modifiers: .control), context: focusedContext),
            .previousPullInOffer)
        XCTAssertEqual(
            router.command(
                for: keyEvent(45, modifiers: [.control, .shift]), context: focusedContext),
            nil)
        XCTAssertEqual(
            router.command(for: keyEvent(45, modifiers: .command), context: focusedContext), nil)
        XCTAssertEqual(router.command(for: keyEvent(45), context: focusedContext), nil)
        XCTAssertEqual(router.command(for: keyEvent(35), context: focusedContext), nil)
        let completionContext = CaptureKeyRoutingContext(
            completionVisible: true, pullInChoiceVisible: true, pickerVisible: true)
        XCTAssertEqual(
            router.command(for: keyEvent(45, modifiers: .control), context: completionContext),
            .nextPullInOffer)
        XCTAssertEqual(
            router.command(for: keyEvent(35, modifiers: .control), context: completionContext),
            .previousPullInOffer)
        XCTAssertEqual(router.command(for: keyEvent(49), context: context), .togglePullInOffer)
        XCTAssertEqual(
            router.command(for: keyEvent(49, repeat: true), context: context), .consumeKey)
        XCTAssertEqual(
            router.command(
                for: keyEvent(49),
                context: CaptureKeyRoutingContext(
                    pullInChoiceVisible: true, pullInFilterFocused: true, pullInFilterIsEmpty: true)
            ),
            .togglePullInOffer)
        XCTAssertEqual(
            router.command(
                for: keyEvent(49),
                context: CaptureKeyRoutingContext(
                    pullInChoiceVisible: true, pullInFilterFocused: true, pullInFilterIsEmpty: false
                )),
            nil)
        XCTAssertEqual(
            router.command(
                for: keyEvent(49, repeat: true),
                context: CaptureKeyRoutingContext(
                    pullInChoiceVisible: true, pullInFilterFocused: true, pullInFilterIsEmpty: true)
            ),
            .consumeKey)
        XCTAssertEqual(
            router.command(for: keyEvent(0, modifiers: .command), context: context),
            .markAllPullInOffers)
        XCTAssertEqual(
            router.command(
                for: keyEvent(0, modifiers: .command),
                context: CaptureKeyRoutingContext(
                    pullInChoiceVisible: true, pullInFilterFocused: true)),
            .markAllPullInOffers)

        let promptWins = CaptureKeyRoutingContext(
            taskIDPromptVisible: true,
            pullInChoiceVisible: true
        )
        XCTAssertEqual(router.command(for: keyEvent(36), context: promptWins), .submitTaskIDPrompt)
    }

    func testRouterMapsOfferCloseChordsAndReasonFieldKeys() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(pullInChoiceVisible: true)
        XCTAssertEqual(
            router.command(for: keyEvent(7, modifiers: .control), context: context),
            .stagePullInDone)
        XCTAssertEqual(
            router.command(
                for: keyEvent(7, modifiers: [.control, .shift]), context: context),
            .beginPullInCancel)
        XCTAssertEqual(
            router.command(
                for: keyEvent(7, modifiers: .control, repeat: true), context: context),
            .consumeKey)
        XCTAssertEqual(
            router.command(
                for: keyEvent(7, modifiers: [.control, .shift], repeat: true),
                context: context),
            .consumeKey)
        XCTAssertNil(router.command(for: keyEvent(7, modifiers: .command), context: context))
        XCTAssertNil(router.command(for: keyEvent(7), context: context))
        XCTAssertNil(
            router.command(
                for: keyEvent(7, modifiers: [.control, .option]), context: context))
        XCTAssertNil(
            router.command(
                for: keyEvent(7, modifiers: [.control, .command]), context: context))

        let reason = CaptureKeyRoutingContext(
            pullInChoiceVisible: true, pullInReasonFocused: true)
        XCTAssertEqual(
            router.command(for: keyEvent(36), context: reason), .confirmPullInReason)
        XCTAssertEqual(
            router.command(for: keyEvent(76), context: reason), .confirmPullInReason)
        XCTAssertEqual(
            router.command(for: keyEvent(53), context: reason), .restorePullInReason)
        XCTAssertEqual(
            router.command(for: keyEvent(33, modifiers: .control), context: reason),
            .restorePullInReason)
        XCTAssertEqual(
            router.command(for: keyEvent(36, repeat: true), context: reason), .consumeKey)
        XCTAssertNil(router.command(for: keyEvent(36, modifiers: .shift), context: reason))
        XCTAssertNil(router.command(for: keyEvent(36, modifiers: .control), context: reason))
        XCTAssertNil(router.command(for: keyEvent(49), context: reason))
        XCTAssertNil(router.command(for: keyEvent(7, modifiers: .control), context: reason))
        XCTAssertNil(router.command(for: keyEvent(0, modifiers: .command), context: reason))
    }

    @MainActor
    func testControllerDispatchMovesMarksAndCancelsOnlyTheChoice() {
        let offers = offers(count: 3)
        let model = CapturePanelModel()
        model.plainDraft = "unchanged draft"
        model.installPullInChoiceForPreviews(
            offers: offers,
            pullIn: CapturePullIn(supported: true, offerCount: offers.count),
            draft: "unchanged draft"
        )
        let controller = CapturePanelController(model: model)

        XCTAssertEqual(
            model.pullInChoice?.visibleSelectableKeys,
            ["opaque#2^suffix", "opaque#1^suffix", "opaque#3^suffix"])
        XCTAssertEqual(model.pullInChoice?.highlightedKey, "opaque#1^suffix")
        XCTAssertTrue(controller.perform(.nextPullInOffer))
        XCTAssertEqual(model.pullInChoice?.highlightedKey, "opaque#3^suffix")
        XCTAssertEqual(model.focusRequest.target, .pullInOfferList)
        XCTAssertTrue(controller.perform(.togglePullInOffer))
        XCTAssertEqual(model.pullInChoice?.markedKeys, ["opaque#3^suffix"])
        XCTAssertTrue(controller.perform(.markAllPullInOffers))
        XCTAssertEqual(model.pullInChoice?.markedKeys.count, 3)
        XCTAssertTrue(controller.perform(.cancelPullInChoice))
        XCTAssertFalse(model.pullInChoiceVisible)
        XCTAssertEqual(model.plainDraft, "unchanged draft")
        XCTAssertEqual(model.focusRequest.target, .editor)
    }

    @MainActor
    func testControllerToggleMarksImmediatelyAndArrowKeysKeepOfferListFocus() {
        let offers = offers(count: 3)
        let model = CapturePanelModel()
        model.plainDraft = "unchanged draft"
        model.installPullInChoiceForPreviews(
            offers: offers,
            pullIn: CapturePullIn(supported: true, offerCount: offers.count),
            draft: "unchanged draft"
        )
        let controller = CapturePanelController(model: model)

        XCTAssertEqual(model.pullInChoice?.highlightedKey, "opaque#1^suffix")
        XCTAssertTrue(controller.perform(.togglePullInOffer))
        XCTAssertEqual(model.pullInChoice?.markedKeys, ["opaque#1^suffix"])

        XCTAssertTrue(controller.perform(.previousPullInOffer))
        XCTAssertEqual(model.focusRequest.target, .pullInOfferList)
        XCTAssertTrue(controller.perform(.nextPullInOffer))
        XCTAssertEqual(model.focusRequest.target, .pullInOfferList)
    }

    func testHeightPolicyContentMaxMinContextAndFilterStability() {
        let bar = CapturePanelLayout.pullInBarHeight
        let context = CapturePanelLayout.pullInContextHeight
        let header = CapturePanelLayout.pullInSectionHeaderHeight
        let fold = CapturePanelLayout.pullInFoldRowHeight
        let row = CapturePanelLayout.pullInRowHeight
        let padding = CapturePanelLayout.pullInListPadding

        var one = choiceState(offers: [offer(n: 1, group: "hand_off")])
        let onePolicy = CapturePullInChoiceHeightPolicy(choice: one)
        let oneContent = 2 * padding + header + row
        XCTAssertEqual(onePolicy.listContentHeight, oneContent, accuracy: 0.001)
        XCTAssertEqual(onePolicy.listViewportHeight, oneContent, accuracy: 0.001)
        XCTAssertEqual(onePolicy.idealHeight, bar + 1 + oneContent, accuracy: 0.001)

        let projectPath = "projects/sase_foo.md"
        let mixed = choiceState(
            offers: [
                offer(n: 1, group: "hand_off"),
                offer(n: 2, group: "hand_off"),
                offer(n: 3, group: "project", project: projectPath),
            ],
            stillBlocked: [
                TaskCompleteStillBlocked(
                    notePath: projectPath,
                    blockID: "resident",
                    line: 9,
                    text: "Resident",
                    statusSymbol: "?",
                    statusName: "Blocked",
                    reason: "project",
                    project: projectPath
                )
            ],
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 3,
                groups: [
                    CapturePullInGroup(
                        group: "project",
                        project: projectPath,
                        folded: CapturePullInFolded(hidden: 5, alreadyPlanned: 3, subProjects: 2)
                    )
                ]
            )
        )
        let mixedPolicy = CapturePullInChoiceHeightPolicy(choice: mixed)
        let mixedContent = 2 * padding + 2 * header + fold + 4 * row
        XCTAssertEqual(mixedPolicy.listContentHeight, mixedContent, accuracy: 0.001)
        XCTAssertEqual(mixedPolicy.listViewportHeight, mixedContent, accuracy: 0.001)

        let twenty = choiceState(offers: offers(count: 20))
        let twentyPolicy = CapturePullInChoiceHeightPolicy(choice: twenty)
        let maxList =
            2 * padding + header
            + CGFloat(CapturePanelLayout.pullInMaxVisibleRows) * row
        XCTAssertEqual(twentyPolicy.listViewportHeight, maxList, accuracy: 0.001)
        let minList =
            2 * padding + header
            + CGFloat(CapturePanelLayout.pullInMinVisibleRows) * row
        XCTAssertEqual(
            twentyPolicy.minimumVisibleHeight, bar + 1 + minList, accuracy: 0.001)
        XCTAssertEqual(twentyPolicy.idealHeight, bar + 1 + maxList, accuracy: 0.001)

        let budgeted = choiceState(
            offers: [offer(n: 1, group: "hand_off")],
            planBudget: CapturePlanBudget(
                status: "ok",
                links: CapturePlanBudgetMeter(count: 4, cap: 10, over: false)
            )
        )
        let budgetedPolicy = CapturePullInChoiceHeightPolicy(choice: budgeted)
        XCTAssertEqual(
            budgetedPolicy.idealHeight, onePolicy.idealHeight + context, accuracy: 0.001)

        var filtered = one
        filtered.updateFilter("zzz")
        if let section = filtered.sections.first {
            filtered.toggleGroup(section.id)
        }
        XCTAssertEqual(CapturePullInChoiceHeightPolicy(choice: filtered), onePolicy)
        one.updateFilter("zzz")
        XCTAssertEqual(CapturePullInChoiceHeightPolicy(choice: one), onePolicy)
    }

    func testMetaDetailsOmitsRecoveredCaptionAndHeaderRepeat() {
        func row(
            n: Int, group: String, trigger: String?, hideRemoved: Bool
        ) -> CapturePullInChoiceRow {
            CapturePullInChoiceRow(
                offerRow: TaskCompleteUnblocked(
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
                        key: "key-\(n)",
                        n: n,
                        group: group,
                        destination: TaskCompleteOfferDestination(dayFile: "20261013.md")
                    ),
                    trigger: trigger,
                    hideRemoved: hideRemoved
                ),
                blockedRow: nil,
                group: group,
                project: nil
            )
        }
        let finished = row(
            n: 1, group: "project_finished", trigger: "project_empty", hideRemoved: true)
        XCTAssertEqual(finished.metaDetails, ["removed #hide"])
        XCTAssertFalse(finished.metaDetails.joined(separator: " ").contains("not pulled in"))
        XCTAssertNotNil(finished.detailText)
        XCTAssertTrue(finished.detailText?.contains("not pulled in") == true)
        XCTAssertEqual(
            row(n: 2, group: "hand_off", trigger: "project_empty", hideRemoved: false).metaDetails,
            ["project finished"])
        XCTAssertEqual(
            row(n: 3, group: "hand_off", trigger: "manual", hideRemoved: false).metaDetails,
            ["trigger: manual"])
        XCTAssertEqual(
            row(n: 4, group: "hand_off", trigger: nil, hideRemoved: false).metaDetails, [])
        let newProject = row(
            n: 5,
            group: "project",
            trigger: "project_created",
            hideRemoved: false
        )
        XCTAssertEqual(newProject.metaDetails, [])
        XCTAssertNil(newProject.movedFrom)
        XCTAssertFalse(newProject.detailText?.contains("trigger: project_created") == true)
        let relation = row(n: 6, group: "relation", trigger: "relation", hideRemoved: false)
        XCTAssertEqual(relation.metaDetails, [])
        XCTAssertFalse(relation.metaDetails.contains(where: { $0.contains("trigger:") }))
        XCTAssertFalse(relation.statusText.contains("→"))
    }

    func testMovedOfferRowLabelsItsParentFirst() {
        let row = CapturePullInChoiceRow(
            offerRow: TaskCompleteUnblocked(
                notePath: "cash_goog_exit.md",
                blockID: "call-ms",
                line: 13,
                text: "Call Morgan Stanley about the 401k",
                previousStatusSymbol: " ",
                previousStatusName: "Ready",
                statusSymbol: "*",
                statusName: "Next",
                offer: TaskCompleteOffer(
                    key: "cash_x.md#^call-ms",
                    n: 1,
                    group: "project",
                    project: "cash_x.md",
                    destination: TaskCompleteOfferDestination(dayFile: "20260920.md"),
                    movedFrom: "cash.md"
                ),
                trigger: "project_created"
            ),
            blockedRow: nil,
            group: "project",
            project: "cash_x.md"
        )
        XCTAssertEqual(row.movedFrom, "cash.md")
        XCTAssertEqual(row.metaDetails.first, "moved from cash.md")
        XCTAssertTrue(row.detailText?.contains("moved from cash.md") == true)
        XCTAssertTrue(row.accessibilityLabel.contains("moved from cash.md"))
    }

    func testRelationOnlyUsesBobCopyOrderAndGlyph() throws {
        let success = try fixtureSuccess("relation-successor-parked-x-star.json")
        let offer = try XCTUnwrap(success.allRelationSuccessors.first)
        let state = choiceState(offers: [offer], pullIn: success.pullIn)
        XCTAssertTrue(state.isOnlyRelation)
        XCTAssertNil(state.contextText)
        XCTAssertEqual(state.authoredCopy?.capsule, "Starts after")
        XCTAssertEqual(state.authoredCopy?.glyph, "relation")
        XCTAssertEqual(
            CapturePullInGlyph.systemImageName(for: state.authoredCopy?.glyph ?? ""),
            "link"
        )
        XCTAssertEqual(state.sections.count, 1)
        let section = try XCTUnwrap(state.sections.first)
        XCTAssertEqual(section.group, "relation")
        XCTAssertEqual(section.after?.key, "agents.md#^implement")
        XCTAssertEqual(section.label, "starts after")
        XCTAssertEqual(section.title, "Starts after “Send implementation prompt”")
        XCTAssertEqual(
            section.caption,
            "“Send implementation prompt” is parked · Pending, off today's plan"
        )
        XCTAssertEqual(section.contrastTag, "your links · not dependents")
        XCTAssertEqual(section.glyph, "link")
        XCTAssertEqual(section.rows.first?.offerKey, offer.offer?.key)
        XCTAssertEqual(section.rows.first?.after, "agents.md#^implement")
        XCTAssertFalse(section.rows.first?.accessibilityLabel.contains("trigger: relation") == true)
        XCTAssertFalse(section.rows.first?.accessibilityLabel.contains("[") == true)
    }

    func testMixedBobGroupOrderKeepsHandOffBeforeRelation() throws {
        let success = try fixtureSuccess("relation-successor-mixed-x-star-dependency.json")
        let state = choiceState(
            offers: success.allUnblockedRows + success.allRelationSuccessors,
            pullIn: success.pullIn
        )
        XCTAssertEqual(state.sections.map(\.group), ["hand_off", "relation"])
        XCTAssertEqual(state.sections.first?.title, "Hand-offs")
        XCTAssertEqual(
            state.sections.last?.title,
            "Starts after “Send implementation prompt”"
        )
        XCTAssertEqual(
            state.selectableKeys,
            [
                "agents.md#^schema-change",
                "agents.md#^evaluate",
            ])
        XCTAssertFalse(state.isOnlyRelation)
        // Bob supplies group copy, which suppresses the legacy caption.
        XCTAssertNil(state.contextText)
    }

    func testDistinctAfterKeysAndDistinctLabelsStaySeparate() {
        let first = relationOffer(
            n: 1,
            key: "s.md#^one",
            after: "s.md#^alpha",
            label: "starts after",
            target: "Alpha"
        )
        let second = relationOffer(
            n: 2,
            key: "s.md#^two",
            after: "s.md#^beta",
            label: "starts after",
            target: "Beta"
        )
        let relabeled = relationOffer(
            n: 3,
            key: "s.md#^three",
            after: "s.md#^alpha",
            label: "blocks",
            target: "Alpha"
        )
        let state = choiceState(
            offers: [first, second, relabeled],
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 3,
                groups: [
                    relationGroup(after: "s.md#^beta", label: "starts after", text: "Beta"),
                    relationGroup(after: "s.md#^alpha", label: "starts after", text: "Alpha"),
                    relationGroup(after: "s.md#^alpha", label: "blocks", text: "Alpha"),
                ]
            )
        )
        XCTAssertEqual(
            state.sections.map(\.after?.key),
            [
                "s.md#^beta",
                "s.md#^alpha",
                "s.md#^alpha",
            ])
        XCTAssertEqual(state.sections.map(\.label), ["starts after", "starts after", "blocks"])
        XCTAssertEqual(state.sections.map(\.rows.count), [1, 1, 1])
        XCTAssertNotEqual(state.sections[1].id, state.sections[2].id)
    }

    func testUnknownGlyphIsCircleAndBobCopyOverridesLocalTitle() {
        XCTAssertEqual(CapturePullInGlyph.systemImageName(for: "mystery"), "circle")
        XCTAssertEqual(CapturePullInGlyph.systemImageName(for: ""), "circle")
        XCTAssertNotEqual(CapturePullInGlyph.systemImageName(for: "relation"), "lock.open")
        let state = choiceState(
            offers: [offer(n: 1, group: "hand_off")],
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 1,
                groups: [
                    CapturePullInGroup(
                        group: "hand_off",
                        copy: CapturePullInGroupCopy(
                            title: "Custom Bob hand-offs",
                            glyph: "mystery"
                        )
                    )
                ],
                copy: CapturePullInCopy(title: "Custom card", capsule: "Custom", glyph: "mystery")
            )
        )
        XCTAssertEqual(state.sections.first?.title, "Custom Bob hand-offs")
        XCTAssertEqual(state.sections.first?.glyph, "circle")
        XCTAssertNil(state.sections.first?.caption)
        XCTAssertEqual(state.authoredCopy?.capsule, "Custom")
    }

    func testAbsentWhyDoesNotSynthesizeLegacyCaption() {
        let state = choiceState(
            offers: [
                cardOffer(
                    n: 1,
                    text: "Keep the renderer moving",
                    group: "keep_moving",
                    project: "projects/sase_badges.md",
                    cause: "Wire badges into the README",
                    trigger: "last_planned"
                )
            ],
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 1,
                groups: [
                    CapturePullInGroup(
                        group: "keep_moving",
                        project: "projects/sase_badges.md",
                        copy: CapturePullInGroupCopy(
                            title: "Keep ‹sase_badges› moving",
                            glyph: "keep_moving"
                        )
                    )
                ]
            )
        )
        XCTAssertEqual(state.sections.first?.title, "Keep ‹sase_badges› moving")
        XCTAssertNil(state.sections.first?.caption)
        XCTAssertNil(state.sections.first?.contrastTag)
        XCTAssertNil(state.sections.first?.foldText)
    }

    func testOlderNoCopyPayloadKeepsLocalFallback() {
        let state = choiceState(offers: [offer(n: 1, group: "hand_off")])
        XCTAssertEqual(state.sections.first?.title, "Hand-offs")
        XCTAssertEqual(state.sections.first?.glyph, "arrow.turn.down.right")
        XCTAssertNil(state.authoredCopy)
        XCTAssertFalse(state.isOnlyRelation)
    }

    func testGroupMetadataDoesNotCreateEmptyPerItemSections() {
        let state = choiceState(
            offers: [offer(n: 1, group: "hand_off")],
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 2,
                groups: [
                    CapturePullInGroup(
                        group: "hand_off",
                        copy: CapturePullInGroupCopy(title: "Hand-offs", glyph: "hand_off")
                    ),
                    relationGroup(
                        after: "agents.md#^implement", text: "Send implementation prompt"),
                ]
            )
        )
        XCTAssertEqual(state.sections.map(\.group), ["hand_off"])
        XCTAssertFalse(state.sections.contains(where: \.isRelation))
    }

    func testRelationAfterSuffixAndSecondReasonReachMetaAndAccessibility() {
        let multi = relationOffer(
            n: 1,
            key: "s.md#^source",
            after: "s.md#^t1",
            label: "starts after",
            target: "First",
            extraTargets: ["Second"]
        )
        XCTAssertEqual(
            CapturePullInChoiceRow(
                offerRow: multi, blockedRow: nil, group: "relation", project: nil
            ).relationAfterSuffix,
            "after “First” and “Second”"
        )
        let second = TaskCompleteUnblocked(
            notePath: "s.md",
            blockID: "dep",
            line: 2,
            text: "Dependent",
            previousStatusSymbol: "?",
            previousStatusName: "Blocked",
            statusSymbol: " ",
            statusName: "Ready",
            notLinked: "not_selected",
            offer: TaskCompleteOffer(
                key: "s.md#^dep",
                n: 2,
                group: "hand_off",
                destination: TaskCompleteOfferDestination(dayFile: "20261102.md")
            ),
            trigger: "dependency",
            relation: CaptureRelationMetadata(
                label: "starts after",
                key: "starts after",
                event: "done",
                after: [CaptureRelationTarget(notePath: "s.md", blockID: "t1", text: "First")]
            )
        )
        let row = CapturePullInChoiceRow(
            offerRow: second, blockedRow: nil, group: "hand_off", project: nil
        )
        XCTAssertEqual(row.relationSecondReason, "starts after “First”")
        XCTAssertTrue(row.metaDetails.contains("starts after “First”"))
        XCTAssertTrue(row.accessibilityLabel.contains("starts after “First”"))
        // `dependency` is the real hand-off trigger and stays visible;
        // only the raw `trigger: relation` text is suppressed.
        XCTAssertTrue(row.metaDetails.contains("trigger: dependency"))
        XCTAssertFalse(row.metaDetails.contains("trigger: relation"))
        XCTAssertTrue((row.detailText ?? "").contains("starts after “First”"))
        XCTAssertTrue((row.detailText ?? "").contains("trigger: dependency"))
    }

    func testHandOffWithSecondReasonJoinsBobGroupAndKeepsMeta() {
        let handOffPrimary = TaskCompleteUnblocked(
            notePath: "s.md",
            blockID: "h1",
            line: 1,
            text: "Hand off one",
            previousStatusSymbol: "?",
            previousStatusName: "Blocked",
            statusSymbol: " ",
            statusName: "Ready",
            notLinked: "not_selected",
            offer: TaskCompleteOffer(
                key: "s.md#^h1",
                n: 1,
                group: "hand_off",
                destination: TaskCompleteOfferDestination(dayFile: "20261102.md")
            ),
            trigger: "dependency"
        )
        let handOffWithSecond = TaskCompleteUnblocked(
            notePath: "s.md",
            blockID: "h2",
            line: 2,
            text: "Hand off two",
            previousStatusSymbol: "?",
            previousStatusName: "Blocked",
            statusSymbol: " ",
            statusName: "Ready",
            notLinked: "not_selected",
            offer: TaskCompleteOffer(
                key: "s.md#^h2",
                n: 2,
                group: "hand_off",
                destination: TaskCompleteOfferDestination(dayFile: "20261102.md")
            ),
            trigger: "dependency",
            relation: CaptureRelationMetadata(
                label: "starts after",
                key: "starts after",
                event: "done",
                after: [CaptureRelationTarget(notePath: "s.md", blockID: "t1", text: "First")]
            )
        )
        let relation = relationOffer(
            n: 3,
            key: "agents.md#^evaluate",
            after: "agents.md#^implement",
            target: "Send implementation prompt"
        )
        let bobGroups = [
            CapturePullInGroup(
                group: "hand_off",
                copy: CapturePullInGroupCopy(title: "Hand-offs", glyph: "hand_off")
            ),
            relationGroup(after: "agents.md#^implement", text: "Send implementation prompt"),
        ]
        let state = choiceState(
            offers: [handOffPrimary, handOffWithSecond, relation],
            pullIn: CapturePullIn(supported: true, offerCount: 3, groups: bobGroups)
        )
        // Secondary relation metadata must not split Bob's hand-off group.
        XCTAssertEqual(state.sections.map(\.group), ["hand_off", "relation"])
        let handOff = try! XCTUnwrap(state.sections.first)
        XCTAssertEqual(handOff.rows.count, 2)
        XCTAssertEqual(handOff.title, "Hand-offs")
        // Exact Bob order is preserved; no extra per-item sections appear.
        XCTAssertEqual(state.sections[1].title, "Starts after “Send implementation prompt”")
        XCTAssertEqual(state.sections[1].caption, "“Send implementation prompt” is parked · Pending, off today's plan")
        let second = try! XCTUnwrap(handOff.rows.first(where: { $0.offerKey == "s.md#^h2" }))
        XCTAssertTrue(second.metaDetails.contains("starts after “First”"))
        XCTAssertTrue((second.detailText ?? "").contains("starts after “First”"))
        XCTAssertTrue(second.accessibilityLabel.contains("starts after “First”"))
        // Same target with distinct labels stays distinct.
        let distinctA = relationOffer(n: 4, key: "k4", after: "s.md#^t", label: "starts after", target: "T")
        let distinctB = relationOffer(n: 5, key: "k5", after: "s.md#^t", label: "blocked by", target: "T")
        let distinctState = choiceState(
            offers: [distinctA, distinctB],
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 2,
                groups: [
                    relationGroup(after: "s.md#^t", label: "starts after", text: "T"),
                    relationGroup(after: "s.md#^t", label: "blocked by", text: "T"),
                ]
            )
        )
        XCTAssertEqual(distinctState.sections.count, 2)
        // Non-relation `why` override/absence and partial group metadata:
        // a supplied copy without `why` yields no invented caption.
        let noWhy = CapturePullInGroup(
            group: "relation",
            after: CapturePullInAfter(key: "s.md#^t", notePath: "s.md", blockID: "t", text: "T"),
            label: "starts after",
            event: "parked",
            copy: CapturePullInGroupCopy(title: "Starts after “T”", glyph: "relation")
        )
        let noWhyState = choiceState(
            offers: [relationOffer(n: 6, key: "k6", after: "s.md#^t", target: "T")],
            pullIn: CapturePullIn(supported: true, offerCount: 1, groups: [noWhy])
        )
        XCTAssertNil(noWhyState.sections.first?.caption)
        XCTAssertNil(noWhyState.contextText)
        // No-copy legacy payloads keep local fallbacks.
        let legacy = choiceState(offers: [handOffPrimary])
        XCTAssertEqual(legacy.sections.first?.title, "Hand-offs")
    }

    func testRelationCaptionAndNewFoldCountersHoldHeightWhileFiltering() {
        let header = CapturePanelLayout.pullInSectionHeaderHeight
        let captionHeader = CapturePanelLayout.pullInKeepMovingHeaderHeight
        let fold = CapturePanelLayout.pullInFoldRowHeight
        let row = CapturePanelLayout.pullInRowHeight
        let padding = CapturePanelLayout.pullInListPadding
        var state = choiceState(
            offers: [
                relationOffer(
                    n: 1,
                    key: "agents.md#^evaluate",
                    after: "agents.md#^implement",
                    target: "Send implementation prompt"
                )
            ],
            pullIn: CapturePullIn(
                supported: true,
                offerCount: 1,
                groups: [
                    CapturePullInGroup(
                        group: "relation",
                        after: CapturePullInAfter(
                            key: "agents.md#^implement",
                            notePath: "agents.md",
                            blockID: "implement",
                            text: "Send implementation prompt"
                        ),
                        label: "starts after",
                        event: "parked",
                        folded: CapturePullInFolded(alreadyStarted: 1, waitsFor: 2, hidden: 1),
                        copy: CapturePullInGroupCopy(
                            title: "Starts after “Send implementation prompt”",
                            why:
                                "“Send implementation prompt” is parked · Pending, off today's plan",
                            tag: "your links · not dependents",
                            fold: "not offered · 1 already started · 2 waiting",
                            glyph: "relation"
                        )
                    )
                ],
                copy: CapturePullInCopy(
                    title: "Starts after “Send implementation prompt”",
                    capsule: "Starts after",
                    glyph: "relation"
                )
            )
        )
        let policy = CapturePullInChoiceHeightPolicy(choice: state)
        let content = 2 * padding + captionHeader + fold + row
        XCTAssertEqual(policy.listContentHeight, content, accuracy: 0.001)
        XCTAssertEqual(
            state.sections.first?.foldText, "not offered · 1 already started · 2 waiting")
        XCTAssertNotNil(state.sections.first?.caption)
        state.updateFilter("zzz")
        if let section = state.sections.first {
            state.toggleGroup(section.id)
        }
        XCTAssertEqual(CapturePullInChoiceHeightPolicy(choice: state), policy)
        XCTAssertEqual(captionHeader - header, 20, accuracy: 0.001)
    }

    func testContextTextCoversOneThreeAndNoCauses() {
        func causedOffer(
            n: Int,
            notePath: String,
            blockID: String,
            text: String,
            group: String = "hand_off",
            project: String? = nil,
            trigger: String? = nil
        ) -> TaskCompleteUnblocked {
            TaskCompleteUnblocked(
                notePath: project ?? "sase.md",
                blockID: "task-\(n)",
                line: n,
                text: "Task \(n)",
                previousStatusSymbol: "?",
                previousStatusName: "Blocked",
                statusSymbol: " ",
                statusName: "Ready",
                unblockedBy: [
                    TaskCompleteUnblockedCause(notePath: notePath, blockID: blockID, text: text)
                ],
                notLinked: "not_selected",
                offer: TaskCompleteOffer(
                    key: "key-\(n)",
                    n: n,
                    group: group,
                    project: project,
                    destination: TaskCompleteOfferDestination(dayFile: "20261013.md")
                ),
                trigger: trigger
            )
        }
        let one = choiceState(offers: [
            causedOffer(n: 1, notePath: "a.md", blockID: "c1", text: "Fix apollo machine")
        ])
        XCTAssertEqual(one.causes.count, 1)
        XCTAssertEqual(one.contextText, "Unblocked by Fix apollo machine")
        XCTAssertFalse(one.showsRowCauses)

        let dup = choiceState(offers: [
            causedOffer(n: 1, notePath: "a.md", blockID: "c1", text: "Fix apollo machine"),
            causedOffer(n: 2, notePath: "a.md", blockID: "c1", text: "Fix apollo machine"),
        ])
        XCTAssertEqual(dup.causes.count, 1)
        XCTAssertEqual(dup.contextText, "Unblocked by Fix apollo machine")

        let three = choiceState(offers: [
            causedOffer(n: 1, notePath: "a.md", blockID: "c1", text: "First cause"),
            causedOffer(n: 2, notePath: "b.md", blockID: "c2", text: "Second cause"),
            causedOffer(n: 3, notePath: "c.md", blockID: "c3", text: "Third cause"),
        ])
        XCTAssertEqual(three.causes.count, 3)
        XCTAssertEqual(three.contextText, "Unblocked by First cause and 2 more")
        XCTAssertTrue(three.showsRowCauses)

        let projectRows = choiceState(offers: [
            causedOffer(
                n: 1,
                notePath: "cash_goog_exit.md",
                blockID: "prj",
                text: "Finish the exit packet",
                group: "project",
                project: "cash_goog_exit.md",
                trigger: "project_created"
            ),
            causedOffer(
                n: 2,
                notePath: "cash_goog_exit.md",
                blockID: "prj",
                text: "Finish the exit packet",
                group: "project",
                project: "cash_goog_exit.md",
                trigger: "project_created"
            ),
        ])
        XCTAssertTrue(projectRows.isNewProjectPrompt)
        XCTAssertEqual(projectRows.promptStatusText, "Choose tasks to pull in")
        XCTAssertEqual(projectRows.contextText, "New project · Finish the exit packet")
        XCTAssertFalse(projectRows.showsRowCauses)
        XCTAssertEqual(projectRows.sections.first?.title, "Project cash_goog_exit")
        XCTAssertTrue(projectRows.sections.first?.isNewProject == true)

        let mixed = choiceState(offers: [
            causedOffer(
                n: 1,
                notePath: "cash_goog_exit.md",
                blockID: "prj",
                text: "Finish the exit packet",
                group: "project",
                project: "cash_goog_exit.md",
                trigger: "project_created"
            ),
            causedOffer(n: 2, notePath: "sase.md", blockID: "root", text: "Fix the CLI"),
        ])
        XCTAssertFalse(mixed.isNewProjectPrompt)
        XCTAssertEqual(mixed.promptStatusText, "Choose successor offers")
        XCTAssertEqual(mixed.contextText, "Unblocked by Finish the exit packet and 1 more")
        XCTAssertTrue(mixed.showsRowCauses)

        let none = choiceState(offers: offers(count: 2))
        XCTAssertTrue(none.causes.isEmpty)
        XCTAssertNil(none.contextText)
        XCTAssertFalse(none.showsRowCauses)
    }

    func testCountTextCoversSingularPluralAndFiltered() {
        XCTAssertEqual(choiceState(offers: [offer(n: 1, group: "hand_off")]).countText, "1 offer")
        XCTAssertEqual(choiceState(offers: offers(count: 3)).countText, "3 offers")
        var filtered = choiceState(offers: offers(count: 3))
        filtered.updateFilter("zzz")
        XCTAssertEqual(filtered.countText, "0 of 3")
        filtered.updateFilter("Task 1")
        XCTAssertEqual(filtered.countText, "1 of 3")
    }

    func testEffectiveSelectionMarkedCountActionTitleAndBudgetTexts() throws {
        var state = choiceState(offers: offers(count: 3))
        let highlighted = try XCTUnwrap(state.highlightedKey)
        XCTAssertEqual(highlighted, "opaque#1^suffix")
        XCTAssertTrue(state.isEffectivelySelected("opaque#1^suffix"))
        XCTAssertFalse(state.isEffectivelySelected("opaque#2^suffix"))
        XCTAssertEqual(state.pullInActionTitle, "Pull In 1")

        state.markedKeys = ["opaque#2^suffix", "bogus"]
        XCTAssertTrue(state.isEffectivelySelected("opaque#2^suffix"))
        XCTAssertFalse(state.isEffectivelySelected("opaque#1^suffix"))
        XCTAssertEqual(state.pullInActionTitle, "Pull In 1")
        state.markedKeys = ["opaque#2^suffix", "opaque#3^suffix"]
        XCTAssertEqual(state.pullInActionTitle, "Pull In 2")

        let handOff = try XCTUnwrap(state.sections.first(where: { $0.group == "hand_off" }))
        XCTAssertEqual(state.markedCount(in: handOff), 1)
        let project = try XCTUnwrap(state.sections.first(where: { $0.group == "project" }))
        XCTAssertEqual(state.markedCount(in: project), 1)

        var empty = choiceState(offers: offers(count: 2))
        empty.updateFilter("zzz")
        XCTAssertEqual(empty.effectivePickCount, 0)
        XCTAssertEqual(empty.pullInActionTitle, "Pull In")
        XCTAssertNil(empty.projectedTodayBadge)
        XCTAssertNil(empty.projectedLinksDeltaText)

        let budgeted = choiceState(
            offers: offers(count: 3),
            planBudget: CapturePlanBudget(
                status: "ok",
                links: CapturePlanBudgetMeter(count: 4, cap: 10, over: false)
            )
        )
        XCTAssertEqual(budgeted.projectedTodayBadge?.text, "TODAY 5/10")
        XCTAssertEqual(budgeted.projectedLinksDeltaText, "+1")

        var over = choiceState(
            offers: offers(count: 2),
            planBudget: CapturePlanBudget(
                status: "over",
                links: CapturePlanBudgetMeter(count: 4, cap: 5, over: false)
            )
        )
        over.markAll()
        XCTAssertTrue(over.projectedLinksOverCap)
        XCTAssertEqual(over.projectedTodayBadge?.text, "TODAY 6/5")
        XCTAssertEqual(over.projectedLinksDeltaText, "+2")

        let atCap = choiceState(
            offers: offers(count: 2),
            planBudget: CapturePlanBudget(
                status: "ok",
                links: CapturePlanBudgetMeter(count: 9, cap: 10, over: false)
            )
        )
        XCTAssertEqual(atCap.projectedTodayBadge?.text, "TODAY 10/10")
        XCTAssertEqual(atCap.projectedTodayBadge?.tone, .magenta)
    }

    func testVerdictLabelsExclusiveOutcomesAndNoFallback() {
        var state = verdictChoiceState()
        XCTAssertEqual(state.primaryCommitLabel, "Pull In 1")
        state.toggleOfferDone("k1")
        XCTAssertEqual(state.verdicts["k1"], .done)
        XCTAssertEqual(state.primaryCommitLabel, "Pull In 1 · Close 1")
        XCTAssertEqual(state.skipCommitLabel, "Skip pull-ins · Close 1")
        XCTAssertEqual(state.footerSummaryText, "pull in 1 · ✓ 1 done")
        // Explicit marks win; once a verdict exists Return has no fallback.
        state.markedKeys = []
        XCTAssertTrue(state.effectiveSelectionKeys.isEmpty)
        XCTAssertTrue(state.canCommit)
        // Same verdict chord clears to Leave and stays on the row.
        let highlight = state.highlightedKey
        state.toggleOfferDone("k1")
        XCTAssertNil(state.verdicts["k1"])
        XCTAssertEqual(state.highlightedKey, "k1", "Clearing stays on the row")
        _ = highlight
        // Space replaces Done with Pull In.
        state.toggleOfferDone("k2")
        state.toggleOffer("k2")
        XCTAssertNil(state.verdicts["k2"])
        XCTAssertTrue(state.markedKeys.contains("k2"))
    }

    func testVisibleOrderAdvancementAndHiddenChoices() {
        var state = verdictChoiceState()
        // Card grouped order differs from Bob n-order; staging advances
        // visibly and clamps at the end.
        let visible = state.visibleSelectableKeys
        XCTAssertNotEqual(visible, state.selectableKeys)
        state.highlightedKey = visible.first
        // Clear the helper's pull-in mark so staging is verdict-only.
        state.markedKeys = []
        state.toggleOfferDone(visible.first!)
        XCTAssertEqual(state.highlightedKey, visible.dropFirst().first)
        // Filters retain hidden choices; hidden highlight never fallbacks.
        state.updateFilter("No Such Task xyz")
        XCTAssertTrue(state.visibleSelectableKeys.isEmpty)
        XCTAssertTrue(state.effectiveSelectionKeys.isEmpty)
        XCTAssertEqual(state.footerSummaryText, "✓ 1 done")
        XCTAssertTrue(state.canCommit)
        state.updateFilter("")
        // Verdicts suppress the highlight fallback even when visible.
        XCTAssertTrue(state.effectiveSelectionKeys.isEmpty)
        XCTAssertTrue(state.canCommit)
    }

    func testBulkMarkPreservesVerdictsAndBudgetCountsPullInsOnly() {
        var state = verdictChoiceState(
            planBudget: CapturePlanBudget(
                status: "ok",
                links: CapturePlanBudgetMeter(count: 4, cap: 10, over: false)))
        state.toggleOfferDone("k1")
        state.markAll()
        XCTAssertEqual(state.verdicts["k1"], .done)
        XCTAssertFalse(state.markedKeys.contains("k1"))
        XCTAssertEqual(state.projectedLinkCount, 4 + state.effectivePickCount)
        XCTAssertEqual(state.footerSummaryText.contains("✓ 1 done"), true)
    }

    func testCapabilityGateAndIneligibleRefusal() {
        var old = choiceState(offers: offers(count: 2))
        XCTAssertFalse(old.closeSupported)
        old.toggleOfferDone("opaque#1^suffix")
        XCTAssertTrue(old.verdicts.isEmpty)
        var state = verdictChoiceState()
        XCTAssertTrue(state.closeSupported)
        // Ineligible row keeps no verdict; router/model surfaces Bob's why.
        state.toggleOfferDone("muted")
        XCTAssertNil(state.verdicts["muted"])
    }

    private func verdictChoiceState(
        planBudget: CapturePlanBudget? = nil
    ) -> CapturePullInChoiceState {
        let close = TaskCompleteOfferClose(
            complete: true,
            cancel: true,
            completeConsequence: "✓ Completes “T” · Ready → Done",
            cancelConsequence: "⊘ Cancels “T” · Ready → Cancelled",
            scopeNote: nil,
            unblocks: 1)
        func offer(_ key: String, _ n: Int, _ group: String) -> TaskCompleteUnblocked {
            TaskCompleteUnblocked(
                notePath: "s.md",
                blockID: key,
                text: "Task \(n)",
                offer: TaskCompleteOffer(
                    key: key, n: n, group: group,
                    destination: TaskCompleteOfferDestination(dayFile: "20261106.md"),
                    close: close))
        }
        // Bob n-order (k1, k2) differs from grouped visible order (k2, k1).
        let offers = [offer("k1", 1, "project"), offer("k2", 2, "hand_off")]
        let rows = offers.map {
            CapturePullInChoiceRow(
                offerRow: $0, blockedRow: nil,
                group: $0.offer?.group ?? "", project: nil)
        }
        var state = CapturePullInChoiceState(
            draftSnapshot: "draft",
            processClientIdentity: "client",
            openAfterCapture: false,
            priorityRollSeed: "seed",
            generation: 1,
            requestID: nil,
            pullIn: CapturePullIn(
                supported: true, offerCount: 2,
                groups: [
                    CapturePullInGroup(group: "hand_off"),
                    CapturePullInGroup(group: "project"),
                ],
                close: CapturePullInClose(supported: true)),
            planBudget: planBudget,
            rows: rows,
            highlightedKey: "k1")
        // One pull-in mark so primary labels cover mixed state.
        state.toggleOffer("k2")
        return state
    }

    func testFilterMatchRangeIsCaseInsensitiveAndNilWhenEmpty() {
        var state = choiceState(offers: offers(count: 1))
        XCTAssertNil(state.filterMatchRange(in: "Task 1"))
        state.updateFilter("book")
        XCTAssertEqual(state.filterMatchRange(in: "Book flights"), 0..<4)
        state.updateFilter("BOOK")
        XCTAssertEqual(state.filterMatchRange(in: "Book flights"), 0..<4)
        state.updateFilter("flights")
        XCTAssertEqual(state.filterMatchRange(in: "Book flights"), 5..<12)
        state.updateFilter("zzz")
        XCTAssertNil(state.filterMatchRange(in: "Book flights"))
    }

    func testFooterContractPinsHintsAndAccessibilityText() {
        let items = CapturePullInChoiceFooter.hintItems
        XCTAssertEqual(
            items.map { $0.keys }, ["⌃N ⌃P", "space", "⌘A", "⌃X", "⌃⇧X", "esc", "⌃↩"])
        XCTAssertEqual(
            items.map { $0.action },
            ["Move", "Mark", "All", "Done", "Cancel", "Back", "Pull In & Open"])
        XCTAssertEqual(
            CapturePullInChoiceFooter.hintItems(openAfterCapture: true, closeSupported: true)
                .map { $0.keys },
            ["⌃N ⌃P", "space", "⌘A", "⌃X", "⌃⇧X", "esc"]
        )
        XCTAssertEqual(
            CapturePullInChoiceFooter.hintItems(openAfterCapture: false, closeSupported: false)
                .map { $0.keys },
            ["⌃N ⌃P", "space", "⌘A", "esc", "⌃↩"])
        let label = CapturePullInChoiceFooter.accessibilityText
        for phrase in [
            "Control-N", "Space", "Command-A", "Control-X", "Control-Shift-X", "Return",
            "Shift-Return", "Control-Return", "Escape",
        ] {
            XCTAssertTrue(label.contains(phrase), "Footer label mentions \(phrase)")
        }
        XCTAssertFalse(
            CapturePullInChoiceFooter.openIntentAccessibilityText.contains(
                "Control-Return pulls in and opens")
        )
    }

    private func fixtureSuccess(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
        guard
            case .success(let response) = try JSONDecoder().decode(
                CaptureCommandResponse.self,
                from: data
            )
        else {
            throw NSError(
                domain: "CapturePullInChoiceTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected success fixture \(name)"]
            )
        }
        return response
    }

    private func relationGroup(
        after: String,
        label: String = "starts after",
        text: String
    ) -> CapturePullInGroup {
        CapturePullInGroup(
            group: "relation",
            after: CapturePullInAfter(key: after, notePath: "s.md", blockID: "t", text: text),
            label: label,
            event: "parked",
            copy: CapturePullInGroupCopy(
                title: "\(CapturePullInChoiceSection.capitalizedLabel(label)) “\(text)”",
                why: "“\(text)” is parked · Pending, off today's plan",
                tag: "your links · not dependents",
                glyph: "relation"
            )
        )
    }

    private func relationOffer(
        n: Int,
        key: String,
        after: String,
        label: String = "starts after",
        target: String,
        extraTargets: [String] = []
    ) -> TaskCompleteUnblocked {
        let afterTargets = ([target] + extraTargets).enumerated().map { index, text in
            CaptureRelationTarget(notePath: "s.md", blockID: "t\(index + 1)", text: text)
        }
        return TaskCompleteUnblocked(
            notePath: "s.md",
            blockID: "task-\(n)",
            line: n,
            text: "Task \(n)",
            previousStatusSymbol: " ",
            previousStatusName: "Ready",
            statusSymbol: " ",
            statusName: "Ready",
            unblockedBy: [
                TaskCompleteUnblockedCause(notePath: "s.md", blockID: "t1", text: target)
            ],
            notLinked: "not_selected",
            offer: TaskCompleteOffer(
                key: key,
                n: n,
                group: "relation",
                after: after,
                destination: TaskCompleteOfferDestination(dayFile: "20261102.md")
            ),
            trigger: "relation",
            relation: CaptureRelationMetadata(
                label: label,
                key: label,
                event: "parked",
                after: afterTargets
            )
        )
    }

    private func choiceState(
        offers: [TaskCompleteUnblocked],
        stillBlocked: [TaskCompleteStillBlocked] = [],
        pullIn: CapturePullIn? = nil,
        planBudget: CapturePlanBudget? = nil
    ) -> CapturePullInChoiceState {
        let rows =
            offers.map {
                CapturePullInChoiceRow(
                    offerRow: $0,
                    blockedRow: nil,
                    group: $0.offer?.group ?? "",
                    project: $0.offer?.project
                )
            }
            + stillBlocked.map {
                CapturePullInChoiceRow(
                    offerRow: nil,
                    blockedRow: $0,
                    group: "project",
                    project: $0.project
                )
            }
        let firstKey = offers.min(by: { ($0.offer?.n ?? .max) < ($1.offer?.n ?? .max) })?.offer?.key
        return CapturePullInChoiceState(
            draftSnapshot: "draft",
            processClientIdentity: "client",
            openAfterCapture: false,
            priorityRollSeed: "seed",
            generation: 1,
            requestID: nil,
            pullIn: pullIn ?? CapturePullIn(supported: true, offerCount: offers.count),
            planBudget: planBudget,
            rows: rows,
            highlightedKey: firstKey
        )
    }

    private func offers(count: Int) -> [TaskCompleteUnblocked] {
        (1...count).map { n in
            offer(
                n: n,
                group: n.isMultiple(of: 2) ? "hand_off" : "project",
                project: n.isMultiple(of: 2) ? nil : "projects/sase_foo.md"
            )
        }
    }

    private func offer(
        n: Int,
        group: String,
        project: String? = nil
    ) -> TaskCompleteUnblocked {
        TaskCompleteUnblocked(
            notePath: project ?? "sase.md",
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
                group: group,
                project: project,
                destination: TaskCompleteOfferDestination(
                    dayFile: "20261013.md",
                    entryName: "FOCUS",
                    entryRole: "current"
                )
            )
        )
    }

    private func keyEvent(
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        repeat isRepeat: Bool = false
    ) -> NSEvent {
        let characters = keyCode == 49 ? " " : ""
        return NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }
}
