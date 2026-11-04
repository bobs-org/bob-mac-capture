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
                links: CapturePlanBudgetMeter(count: 4, cap: 5, over: false)
            ),
            draft: "!sase_foo:root"
        )
        let view = CapturePanelView(model: model)

        for (name, width) in [
            ("capture-pull-in-choice-wide", CGFloat(760)),
            (
                "capture-pull-in-choice-minimum",
                CGFloat(CapturePanelLayout.panelMinimumContentWidth)
            ),
        ] {
            try RenderFixtureWriter.write(view, name: name, width: width, appearance: .aqua)
            try RenderFixtureWriter.write(view, name: name, width: width, appearance: .darkAqua)
        }
    }

    func testRenderOpenCard() throws {
        try writeCardFixtures(name: "capture-pull-in-choice-open") { model in
            model.installPullInChoiceForPreviews(
                offers: [
                    cardOffer(
                        n: 1, text: "Re-launch all failed agents", cause: "Fix apollo machine"),
                    cardOffer(n: 2, text: "Book flights", cause: "Fix apollo machine"),
                    cardOffer(n: 3, text: "Ship the outcome", cause: "Fix apollo machine"),
                ],
                pullIn: CapturePullIn(supported: true, offerCount: 3),
                planBudget: CapturePlanBudget(
                    status: "ok",
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
                    cardOffer(
                        n: 2,
                        text: "Ship the outcome",
                        group: "project",
                        project: projectPath,
                        cause: "Create the project",
                        trigger: "project_created"
                    ),
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
                            folded: CapturePullInFolded(
                                hidden: 5, alreadyPlanned: 3, subProjects: 2)
                        )
                    ]
                ),
                draft: "!task with dependents"
            )
        }
    }

    func testRenderKeepMovingCard() throws {
        try writeCardFixtures(name: "capture-pull-in-choice-keep-moving") { model in
            model.installPullInChoiceForPreviews(
                offers: [
                    cardOffer(
                        n: 1,
                        text: "Ship the badge renderer",
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
                            folded: CapturePullInFolded(blocked: 2, scheduled: 1, hidden: 3)
                        )
                    ]
                ),
                draft: "!sase_badges:t"
            )
        }
    }

    func testRenderNotePullPreviewAndChoiceCards() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(contentsOf: fixtures.appendingPathComponent("note-pull-np1.json"))
        guard case .success(let success) = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: data
        ), let notePull = success.notePull,
           let preview = CaptureNotePullPresentation(
               notePull: notePull,
               group: success.pullIn?.groups.first
           ), let pullIn = success.pullIn
        else {
            return XCTFail("Expected the real-bob note-pull fixture")
        }
        let model = CapturePanelModel()
        model.installPullInChoiceForPreviews(
            offers: notePull.successors,
            pullIn: pullIn,
            draft: "@sase"
        )
        let choice = try XCTUnwrap(model.pullInChoice)
        let view = VStack(spacing: 12) {
            CaptureNotePullPreviewCard(presentation: preview)
            CapturePullInChoiceCard(model: model, choice: choice, previewMode: true)
            CapturePullInChoiceFooter(model: model)
        }
        .padding(18)
        for width in [CGFloat(760), CGFloat(CapturePanelLayout.panelMinimumContentWidth)] {
            try RenderFixtureWriter.write(
                view,
                name: "capture-note-pull-preview-and-choice",
                width: width,
                appearance: .aqua
            )
            try RenderFixtureWriter.write(
                view,
                name: "capture-note-pull-preview-and-choice",
                width: width,
                appearance: .darkAqua
            )
        }
    }

    func testRenderRelationCard() throws {
        try writeCardFixtures(name: "capture-pull-in-choice-relation") { model in
            model.installPullInChoiceForPreviews(
                offers: [
                    TaskCompleteUnblocked(
                        notePath: "agents.md",
                        blockID: "evaluate",
                        line: 1,
                        text: "Prepare evaluation prompt",
                        previousStatusSymbol: " ",
                        previousStatusName: "Ready",
                        statusSymbol: " ",
                        statusName: "Ready",
                        unblockedBy: [
                            TaskCompleteUnblockedCause(
                                notePath: "agents.md",
                                blockID: "implement",
                                text: "Send implementation prompt"
                            )
                        ],
                        notLinked: "not_selected",
                        offer: TaskCompleteOffer(
                            key: "agents.md#^evaluate",
                            n: 1,
                            group: "relation",
                            after: "agents.md#^implement",
                            destination: TaskCompleteOfferDestination(
                                dayFile: "20261102.md",
                                entryName: "BUILD",
                                entryRole: "created"
                            )
                        ),
                        trigger: "relation",
                        relation: CaptureRelationMetadata(
                            label: "starts after",
                            key: "starts after",
                            event: "parked",
                            after: [
                                CaptureRelationTarget(
                                    notePath: "agents.md",
                                    blockID: "implement",
                                    text: "Send implementation prompt"
                                )
                            ]
                        )
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
                            copy: CapturePullInGroupCopy(
                                title: "Starts after “Send implementation prompt”",
                                why:
                                    "“Send implementation prompt” is parked · Pending, off today's plan",
                                tag: "your links · not dependents",
                                glyph: "relation"
                            )
                        )
                    ],
                    copy: CapturePullInCopy(
                        title: "Starts after “Send implementation prompt”",
                        capsule: "Starts after",
                        glyph: "relation"
                    )
                ),
                draft: "x*"
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
}

/// Shared by the pull-in choice design and model tests.
extension XCTestCase {
    func cardOffer(
        n: Int,
        text: String,
        group: String = "hand_off",
        project: String? = nil,
        cause: String? = nil,
        trigger: String? = nil,
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
            trigger: trigger,
            hideRemoved: hideRemoved
        )
    }
}
