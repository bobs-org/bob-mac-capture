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
        themes: CapturePlanBudgetMeter(count: 1, cap: 5, over: false),
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
      router.command(for: keyEvent(36, modifiers: .shift), context: context), .chooseNoPullInOffers)
    XCTAssertEqual(
      router.command(for: keyEvent(36, modifiers: .command), context: context), .consumeKey)
    XCTAssertEqual(router.command(for: keyEvent(36, repeat: true), context: context), .consumeKey)
    XCTAssertEqual(router.command(for: keyEvent(53), context: context), .cancelPullInChoice)
    XCTAssertEqual(
      router.command(for: keyEvent(33, modifiers: .control), context: context), .cancelPullInChoice)
    XCTAssertEqual(router.command(for: keyEvent(126), context: context), .previousPullInOffer)
    XCTAssertEqual(router.command(for: keyEvent(125), context: context), .nextPullInOffer)
    XCTAssertEqual(
      router.command(for: keyEvent(45, modifiers: .control), context: context), .nextPullInOffer)
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
      router.command(for: keyEvent(45, modifiers: [.control, .shift]), context: focusedContext),
      nil)
    XCTAssertEqual(
      router.command(for: keyEvent(45, modifiers: .command), context: focusedContext), nil)
    XCTAssertEqual(router.command(for: keyEvent(45), context: focusedContext), nil)
    XCTAssertEqual(router.command(for: keyEvent(35), context: focusedContext), nil)
    let completionContext = CaptureKeyRoutingContext(
      pullInChoiceVisible: true, pickerVisible: true, completionVisible: true)
    XCTAssertEqual(
      router.command(for: keyEvent(45, modifiers: .control), context: completionContext),
      .nextPullInOffer)
    XCTAssertEqual(
      router.command(for: keyEvent(35, modifiers: .control), context: completionContext),
      .previousPullInOffer)
    XCTAssertEqual(router.command(for: keyEvent(49), context: context), .togglePullInOffer)
    XCTAssertEqual(router.command(for: keyEvent(49, repeat: true), context: context), .consumeKey)
    XCTAssertEqual(
      router.command(
        for: keyEvent(49),
        context: CaptureKeyRoutingContext(
          pullInChoiceVisible: true, pullInFilterFocused: true, pullInFilterIsEmpty: true)),
      .togglePullInOffer)
    XCTAssertEqual(
      router.command(
        for: keyEvent(49),
        context: CaptureKeyRoutingContext(
          pullInChoiceVisible: true, pullInFilterFocused: true, pullInFilterIsEmpty: false)),
      nil)
    XCTAssertEqual(
      router.command(
        for: keyEvent(49, repeat: true),
        context: CaptureKeyRoutingContext(
          pullInChoiceVisible: true, pullInFilterFocused: true, pullInFilterIsEmpty: true)),
      .consumeKey)
    XCTAssertEqual(
      router.command(for: keyEvent(0, modifiers: .command), context: context), .markAllPullInOffers)
    XCTAssertEqual(
      router.command(
        for: keyEvent(0, modifiers: .command),
        context: CaptureKeyRoutingContext(pullInChoiceVisible: true, pullInFilterFocused: true)),
      .markAllPullInOffers)

    let promptWins = CaptureKeyRoutingContext(
      taskIDPromptVisible: true,
      pullInChoiceVisible: true
    )
    XCTAssertEqual(router.command(for: keyEvent(36), context: promptWins), .submitTaskIDPrompt)
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
    let maxList = 2 * padding + header
      + CGFloat(CapturePanelLayout.pullInMaxVisibleRows) * row
    XCTAssertEqual(twentyPolicy.listViewportHeight, maxList, accuracy: 0.001)
    let minList = 2 * padding + header
      + CGFloat(CapturePanelLayout.pullInMinVisibleRows) * row
    XCTAssertEqual(
      twentyPolicy.minimumVisibleHeight, bar + 1 + minList, accuracy: 0.001)
    XCTAssertEqual(twentyPolicy.idealHeight, bar + 1 + maxList, accuracy: 0.001)

    let budgeted = choiceState(
      offers: [offer(n: 1, group: "hand_off")],
      planBudget: CapturePlanBudget(
        status: "ok",
        themes: CapturePlanBudgetMeter(count: 1, cap: 5, over: false),
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
    let finished = row(n: 1, group: "project_finished", trigger: "project_empty", hideRemoved: true)
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
  }

  func testContextTextCoversOneThreeAndNoCauses() {
    func causedOffer(
      n: Int, notePath: String, blockID: String, text: String
    ) -> TaskCompleteUnblocked {
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
        unblockedBy: [
          TaskCompleteUnblockedCause(notePath: notePath, blockID: blockID, text: text)
        ],
        offer: TaskCompleteOffer(
          key: "key-\(n)",
          n: n,
          group: "hand_off",
          destination: TaskCompleteOfferDestination(dayFile: "20261013.md")
        )
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
    XCTAssertNil(empty.projectedLinksCapsuleText)
    XCTAssertNil(empty.projectedLinksDeltaText)

    let budgeted = choiceState(
      offers: offers(count: 3),
      planBudget: CapturePlanBudget(
        status: "ok",
        themes: CapturePlanBudgetMeter(count: 1, cap: 5, over: false),
        links: CapturePlanBudgetMeter(count: 4, cap: 10, over: false)
      )
    )
    XCTAssertEqual(budgeted.projectedLinksCapsuleText, "Links 5/10")
    XCTAssertEqual(budgeted.projectedLinksDeltaText, "+1")

    var over = choiceState(
      offers: offers(count: 2),
      planBudget: CapturePlanBudget(
        status: "over",
        themes: CapturePlanBudgetMeter(count: 1, cap: 5, over: false),
        links: CapturePlanBudgetMeter(count: 4, cap: 5, over: false)
      )
    )
    over.markAll()
    XCTAssertTrue(over.projectedLinksOverCap)
    XCTAssertEqual(over.projectedLinksCapsuleText, "Links 6/5")
    XCTAssertEqual(over.projectedLinksDeltaText, "+2")
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
    XCTAssertEqual(items.map { $0.keys }, ["⌃N ⌃P", "space", "⌘A", "esc"])
    XCTAssertEqual(items.map { $0.action }, ["Move", "Mark", "All", "Back"])
    let label = CapturePullInChoiceFooter.accessibilityText
    for phrase in ["Control-N", "Space", "Command-A", "Return", "Shift-Return", "Escape"] {
      XCTAssertTrue(label.contains(phrase), "Footer label mentions \(phrase)")
    }
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
