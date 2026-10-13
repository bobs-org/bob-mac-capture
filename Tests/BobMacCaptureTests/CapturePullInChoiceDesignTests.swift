import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class CapturePullInChoiceDesignTests: XCTestCase {
  func testRenderGroupedScrollableChoiceAtSupportedWidths() throws {
    let projectPath = "projects/sase_foo.md"
    let offers = (1...20).map { number in
      TaskCompleteUnblocked(
        notePath: number.isMultiple(of: 3) ? projectPath : "travel.md",
        blockID: "offer-\(number)",
        line: number,
        text: "Successor task \(number)",
        previousStatusSymbol: "?",
        previousStatusName: "Blocked",
        statusSymbol: " ",
        statusName: "Ready",
        notLinked: "not_selected",
        offer: TaskCompleteOffer(
          key: "opaque#\(number)^suffix",
          n: number,
          group: number.isMultiple(of: 3) ? "project" : "hand_off",
          project: number.isMultiple(of: 3) ? projectPath : nil,
          destination: TaskCompleteOfferDestination(
            dayFile: "20261013.md",
            entryName: "FOCUS",
            entryRole: "current",
            fallback: false
          ),
          blockIDNeeded: number.isMultiple(of: 5)
        )
      )
    }
    let model = CapturePanelModel()
    model.installPullInChoiceForPreviews(
      offers: offers,
      stillBlocked: [
        TaskCompleteStillBlocked(
          notePath: projectPath,
          blockID: "resident",
          line: 30,
          text: "Project resident",
          statusSymbol: "?",
          statusName: "Blocked",
          reason: "project",
          project: projectPath
        )
      ],
      pullIn: CapturePullIn(
        supported: true,
        offerCount: offers.count,
        groups: [
          CapturePullInGroup(
            group: "project",
            project: projectPath,
            folded: CapturePullInFolded(hidden: 5, alreadyPlanned: 3, subProjects: 2)
          )
        ]
      ),
      planBudget: CapturePlanBudget(
        status: "warning",
        themes: CapturePlanBudgetMeter(count: 2, cap: 5, over: false),
        links: CapturePlanBudgetMeter(count: 4, cap: 5, over: false)
      ),
      draft: "!sase_foo:root"
    )
    let view = CapturePanelView(model: model)

    for (name, width) in [
      ("capture-pull-in-choice-wide", CGFloat(760)),
      ("capture-pull-in-choice-minimum", CGFloat(CapturePanelLayout.panelMinimumContentWidth)),
    ] {
      try RenderFixtureWriter.write(view, name: name, width: width, appearance: .aqua)
      try RenderFixtureWriter.write(view, name: name, width: width, appearance: .darkAqua)
    }
  }

  func testRenderOpenCard() throws {
    try writeCardFixtures(name: "capture-pull-in-choice-open") { model in
      model.installPullInChoiceForPreviews(
        offers: [
          cardOffer(n: 1, text: "Re-launch all failed agents", cause: "Fix apollo machine"),
          cardOffer(n: 2, text: "Book flights", cause: "Fix apollo machine"),
          cardOffer(n: 3, text: "Ship the outcome", cause: "Fix apollo machine"),
        ],
        pullIn: CapturePullIn(supported: true, offerCount: 3),
        planBudget: CapturePlanBudget(
          status: "ok",
          themes: CapturePlanBudgetMeter(count: 1, cap: 5, over: false),
          links: CapturePlanBudgetMeter(count: 4, cap: 10, over: false)
        ),
        draft: "!task with dependents"
      )
    }
  }

  func testRenderMarkedCardOverCap() throws {
    try writeCardFixtures(name: "capture-pull-in-choice-marked") { model in
      model.installPullInChoiceForPreviews(
        offers: [
          cardOffer(n: 1, text: "Re-launch all failed agents", cause: "First cause"),
          cardOffer(
            n: 2, text: "Book flights", cause: "First cause", blockIDNeeded: true),
          cardOffer(n: 3, text: "Ship the outcome", cause: "Second cause"),
        ],
        pullIn: CapturePullIn(supported: true, offerCount: 3),
        planBudget: CapturePlanBudget(
          status: "over",
          themes: CapturePlanBudgetMeter(count: 1, cap: 5, over: false),
          links: CapturePlanBudgetMeter(count: 9, cap: 10, over: false)
        ),
        draft: "!task with dependents"
      )
      model.togglePullInOffer("opaque#1^suffix")
      model.togglePullInOffer("opaque#2^suffix")
    }
  }

  func testRenderProjectCard() throws {
    let projectPath = "projects/sase_foo.md"
    try writeCardFixtures(name: "capture-pull-in-choice-project") { model in
      model.installPullInChoiceForPreviews(
        offers: [
          cardOffer(n: 1, text: "Book flights"),
          cardOffer(n: 2, text: "Ship the outcome", group: "project", project: projectPath),
          cardOffer(
            n: 3,
            text: "Retire the old flow",
            group: "project_finished",
            hideRemoved: true
          ),
        ],
        stillBlocked: [
          TaskCompleteStillBlocked(
            notePath: projectPath,
            blockID: "resident",
            line: 30,
            text: "Project resident",
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
        ),
        draft: "!task with dependents"
      )
    }
  }

  func testRenderFilteredCard() throws {
    try writeCardFixtures(name: "capture-pull-in-choice-filtered") { model in
      model.installPullInChoiceForPreviews(
        offers: [
          cardOffer(n: 1, text: "Re-launch all failed agents"),
          cardOffer(n: 2, text: "Book flights"),
          cardOffer(n: 3, text: "Ship the outcome"),
        ],
        pullIn: CapturePullIn(supported: true, offerCount: 3),
        draft: "!task with dependents"
      )
      model.updatePullInChoiceFilter("book")
    }
  }

  func testRenderNoMatchCard() throws {
    try writeCardFixtures(name: "capture-pull-in-choice-no-match") { model in
      model.installPullInChoiceForPreviews(
        offers: [
          cardOffer(n: 1, text: "Re-launch all failed agents"),
          cardOffer(n: 2, text: "Book flights"),
        ],
        pullIn: CapturePullIn(supported: true, offerCount: 2),
        draft: "!task with dependents"
      )
      model.updatePullInChoiceFilter("zzz")
    }
  }

  private func writeCardFixtures(
    name: String,
    configure: (CapturePanelModel) -> Void
  ) throws {
    let model = CapturePanelModel()
    configure(model)
    guard let choice = model.pullInChoice else {
      throw NSError(
        domain: "CapturePullInChoiceDesignTests",
        code: 1,
        userInfo: [
          NSLocalizedDescriptionKey: "No pull-in choice for \(name)."
        ]
      )
    }
    let view = VStack(spacing: 12) {
      CapturePullInChoiceCard(model: model, choice: choice, previewMode: true)
      CapturePullInChoiceFooter(model: model)
    }
    .padding(18)
    for width in [CGFloat(760), CGFloat(CapturePanelLayout.panelMinimumContentWidth)] {
      try RenderFixtureWriter.write(view, name: name, width: width, appearance: .aqua)
      try RenderFixtureWriter.write(view, name: name, width: width, appearance: .darkAqua)
    }
  }

  private func cardOffer(
    n: Int,
    text: String,
    group: String = "hand_off",
    project: String? = nil,
    cause: String? = nil,
    blockIDNeeded: Bool = false,
    hideRemoved: Bool = false
  ) -> TaskCompleteUnblocked {
    TaskCompleteUnblocked(
      notePath: project ?? "sase.md",
      blockID: "offer-\(n)",
      line: n,
      text: text,
      previousStatusSymbol: "?",
      previousStatusName: "Blocked",
      statusSymbol: " ",
      statusName: "Ready",
      unblockedBy: cause.map {
        [TaskCompleteUnblockedCause(notePath: "sase.md", blockID: $0, text: $0)]
      } ?? [],
      notLinked: "not_selected",
      offer: TaskCompleteOffer(
        key: "opaque#\(n)^suffix",
        n: n,
        group: group,
        project: project,
        destination: TaskCompleteOfferDestination(
          dayFile: "20261013.md",
          entryName: "FIX",
          entryRole: "next_up",
          fallback: false
        ),
        blockIDNeeded: blockIDNeeded
      ),
      hideRemoved: hideRemoved
    )
  }
}
