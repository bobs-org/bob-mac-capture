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
}
