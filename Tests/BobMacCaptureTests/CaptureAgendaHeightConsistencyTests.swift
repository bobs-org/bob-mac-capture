import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Height-consistency proof: the hosted fitting size of the rendered
/// plan equals the planner's total within 2 pt, for the current,
/// heavy-folded, and expanded fixtures at both panel content widths.
/// The views and the measurer share every constant through
/// `CaptureAgendaLayoutMetrics` and the same row views, so this
/// guards the contract both sides rely on.
@MainActor
final class CaptureAgendaHeightConsistencyTests: XCTestCase {
    func testPlansMatchRenderedHeight() throws {
        for width in [724, 584] as [CGFloat] {
            try assertConsistent(
                fixture: "agenda-current.json",
                contentWidth: width,
                budget: 2_000,
                expanded: []
            )
            try assertConsistent(
                snapshot: budgetedSnapshot(
                    "agenda-current.json",
                    links: CapturePlanBudgetMeter(count: 8, cap: 10, over: false)
                ),
                fixture: "agenda-current-budget",
                contentWidth: width,
                budget: 2_000,
                expanded: []
            )
            try assertConsistent(
                snapshot: budgetedSnapshot(
                    "agenda-heavy.json",
                    links: CapturePlanBudgetMeter(count: 12, cap: 10, over: true)
                ),
                fixture: "agenda-heavy-budget",
                contentWidth: width,
                budget: 533,
                expanded: []
            )
            try assertConsistent(
                snapshot: budgetedSnapshot(
                    "agenda-empty.json",
                    links: CapturePlanBudgetMeter(count: 0, cap: 10, over: false)
                ),
                fixture: "agenda-empty-budget",
                contentWidth: width,
                budget: 2_000,
                expanded: []
            )
            try assertConsistent(
                fixture: "agenda-heavy.json",
                contentWidth: width,
                budget: 533,
                expanded: []
            )
            try assertConsistent(
                fixture: "agenda-lightbulb.json",
                contentWidth: width,
                budget: 2_000,
                expanded: []
            )
            try assertConsistent(
                fixture: "agenda-events.json",
                contentWidth: width,
                budget: 2_000,
                expanded: []
            )
            try assertConsistent(
                fixture: "agenda-homes.json",
                contentWidth: width,
                budget: 2_000,
                expanded: []
            )
            try assertConsistent(
                fixture: "agenda-headline.json",
                contentWidth: width,
                budget: 2_000,
                expanded: []
            )
            let lightbulb = try agendaSnapshot("agenda-lightbulb.json")
            let lightbulbPresentation = CaptureAgendaPresentation(
                snapshot: lightbulb,
                today: lightbulb.date ?? "",
                now: nil
            )
            var lightbulbExpanded: Set<CaptureAgendaUnitID> = []
            if let first = lightbulbPresentation.groups.first?.tasks.first {
                lightbulbExpanded.insert(first.id)
            }
            try assertConsistent(
                fixture: "agenda-lightbulb.json",
                contentWidth: width,
                budget: 2_000,
                expanded: lightbulbExpanded
            )
            try assertConsistent(
                fixture: "agenda-lightbulb.json",
                contentWidth: width,
                budget: 180,
                expanded: []
            )
            let snapshot = try agendaSnapshot("agenda-current.json")
            let presentation = CaptureAgendaPresentation(
                snapshot: snapshot,
                today: snapshot.date ?? "",
                now: nil
            )
            var expanded: Set<CaptureAgendaUnitID> = [.strip]
            if let first = presentation.groups.first?.tasks.first {
                expanded.insert(first.id)
            }
            try assertConsistent(
                fixture: "agenda-current.json",
                contentWidth: width,
                budget: 2_000,
                expanded: expanded
            )
        }
    }

    func testBusiestTitleWithWalkMarksStaysOnOneLineAtBothWidths() throws {
        let base = try agendaSnapshot("agenda-current.json")
        let snapshot = CaptureAgendaSnapshot(
            ok: base.ok,
            schemaVersion: base.schemaVersion,
            date: base.date,
            completedSummary: CaptureAgendaCompletedSummary(
                count: base.completedSummary.count,
                minutes: base.completedSummary.minutes,
                offClock: CaptureAgendaOffClockSummary(count: 2, minutes: 45)
            ),
            pomodoros: base.pomodoros,
            warnings: base.warnings,
            planBudget: base.planBudget,
            events: base.events,
            maxTaskLinkCount: base.maxTaskLinkCount,
            headline: base.headline
        )
        let walks = WalkAttentionSnapshot(
            date: snapshot.date,
            walks: [
                WalkAttention(
                    family: .review,
                    name: "review",
                    available: true,
                    attention: true,
                    tier: "next",
                    label: "Review: 16 due · 16 commitments — NEXT first",
                    count: 16
                ),
                WalkAttention(
                    family: .lanes,
                    name: "lanes",
                    available: true,
                    attention: true,
                    tier: "over",
                    label: "Lanes over limit: NEXT 16/15"
                ),
                WalkAttention(
                    family: .bank,
                    name: "bank",
                    available: true,
                    attention: true,
                    tier: "waiting",
                    label: "Bank: 3 waiting · oldest Tue Nov 3",
                    count: 3
                ),
            ]
        )
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: snapshot.date ?? "",
            isStale: true,
            walks: walks
        )

        XCTAssertNotNil(presentation.titleRow.titleOffClockText)
        XCTAssertTrue(presentation.titleRow.accessoryText?.contains("Couldn't refresh") == true)
        XCTAssertEqual(presentation.titleRow.walkMarks.count, 3)

        var firstTitleHeight: CGFloat?
        for contentWidth in [724, 584] as [CGFloat] {
            let rowsWidth =
                contentWidth
                - 2 * CGFloat(CaptureAgendaLayoutMetrics.panePadding)
            let titleHeight = CaptureAgendaRowMeasurer().height(
                for: presentation.titleRow,
                role: .later,
                at: rowsWidth
            )
            if let firstTitleHeight {
                XCTAssertEqual(titleHeight, firstTitleHeight, accuracy: 2)
            } else {
                firstTitleHeight = titleHeight
            }
            try assertConsistent(
                presentation: presentation,
                fixture: "agenda-current-walk-marks",
                contentWidth: contentWidth,
                budget: 2_000,
                expanded: []
            )
        }
    }

    func testSavedBudgetRowStaysFlatAndHasNoExpansionTarget() throws {
        let snapshot = try budgetedSnapshot(
            "agenda-current.json",
            links: CapturePlanBudgetMeter(count: 8, cap: 10, over: false)
        )
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: snapshot.date ?? "",
            now: nil
        )
        let rowsWidth = 724 - 2 * CGFloat(CaptureAgendaLayoutMetrics.panePadding)
        let plan = CaptureAgendaHeightResolver.resolve(
            presentation: presentation,
            budget: 2_000,
            expanded: [],
            width: rowsWidth,
            measurer: CaptureAgendaRowMeasurer()
        )
        let budgetIndex = try XCTUnwrap(plan.rows.firstIndex { $0.kind == .planBudget })
        let blocks = CaptureAgendaSections.make(rows: plan.rows, presentation: presentation)
        let flatIndices = blocks.compactMap { block -> Int? in
            guard case let .row(index) = block else {
                return nil
            }
            return index
        }
        let groupedIndices = blocks.flatMap { block -> [Int] in
            guard case let .group(_, indices, _) = block else {
                return []
            }
            return indices
        }
        let targets = CaptureAgendaChipMap.targets(
            presentation: presentation,
            plan: plan
        )

        XCTAssertTrue(flatIndices.contains(budgetIndex))
        XCTAssertFalse(groupedIndices.contains(budgetIndex))
        XCTAssertNil(targets[budgetIndex])
    }

    func testHeadlineRowStaysFlatAndHasNoExpansionTarget() throws {
        let snapshot = try agendaSnapshot("agenda-headline.json")
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: snapshot.date ?? "",
            now: nil
        )
        let headlineRow = try XCTUnwrap(presentation.headlineRow)
        XCTAssertEqual(headlineRow.kind, .headline)
        let rowsWidth = 724 - 2 * CGFloat(CaptureAgendaLayoutMetrics.panePadding)
        let plan = CaptureAgendaHeightResolver.resolve(
            presentation: presentation,
            budget: 2_000,
            expanded: [],
            width: rowsWidth,
            measurer: CaptureAgendaRowMeasurer()
        )
        let headlineIndex = try XCTUnwrap(plan.rows.firstIndex { $0.kind == .headline })
        XCTAssertEqual(plan.rows[headlineIndex].text, headlineRow.text)
        let blocks = CaptureAgendaSections.make(rows: plan.rows, presentation: presentation)
        let flatIndices = blocks.compactMap { block -> Int? in
            guard case let .row(index) = block else {
                return nil
            }
            return index
        }
        let groupedIndices = blocks.flatMap { block -> [Int] in
            guard case let .group(_, indices, _) = block else {
                return []
            }
            return indices
        }
        let targets = CaptureAgendaChipMap.targets(
            presentation: presentation,
            plan: plan
        )

        XCTAssertTrue(flatIndices.contains(headlineIndex))
        XCTAssertFalse(groupedIndices.contains(headlineIndex))
        XCTAssertNil(targets[headlineIndex])
        XCTAssertFalse(CaptureAgendaRowView.showsChip(for: headlineRow))
    }

    private func assertConsistent(
        fixture: String,
        contentWidth: CGFloat,
        budget: Double,
        expanded: Set<CaptureAgendaUnitID>
    ) throws {
        try assertConsistent(
            snapshot: agendaSnapshot(fixture),
            fixture: fixture,
            contentWidth: contentWidth,
            budget: budget,
            expanded: expanded
        )
    }

    private func assertConsistent(
        snapshot: CaptureAgendaSnapshot,
        fixture: String,
        contentWidth: CGFloat,
        budget: Double,
        expanded: Set<CaptureAgendaUnitID>
    ) throws {
        let presentation = CaptureAgendaPresentation(
            snapshot: snapshot,
            today: snapshot.date ?? "",
            now: nil
        )
        try assertConsistent(
            presentation: presentation,
            fixture: fixture,
            contentWidth: contentWidth,
            budget: budget,
            expanded: expanded
        )
    }

    private func assertConsistent(
        presentation: CaptureAgendaPresentation,
        fixture: String,
        contentWidth: CGFloat,
        budget: Double,
        expanded: Set<CaptureAgendaUnitID>
    ) throws {
        let rowsWidth =
            contentWidth
            - 2 * CGFloat(CaptureAgendaLayoutMetrics.panePadding)
        let measurer = CaptureAgendaRowMeasurer()
        let plan = CaptureAgendaHeightResolver.resolve(
            presentation: presentation,
            budget: budget,
            expanded: expanded,
            width: rowsWidth,
            measurer: measurer
        )
        let view = CaptureAgendaRowsView(
            plan: plan,
            presentation: presentation
        )
        .frame(width: rowsWidth, alignment: .topLeading)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: rowsWidth, height: 10)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(
            Double(host.fittingSize.height),
            plan.totalHeight,
            accuracy: 2,
            "\(fixture) at \(Int(contentWidth)) pt"
        )
    }

    private func budgetedSnapshot(
        _ name: String,
        links: CapturePlanBudgetMeter
    ) throws -> CaptureAgendaSnapshot {
        let snapshot = try agendaSnapshot(name)
        return CaptureAgendaSnapshot(
            ok: snapshot.ok,
            schemaVersion: snapshot.schemaVersion,
            date: snapshot.date,
            completedSummary: snapshot.completedSummary,
            pomodoros: snapshot.pomodoros,
            warnings: snapshot.warnings,
            planBudget: CapturePlanBudget(
                status: "ok",
                links: links
            ),
            events: snapshot.events,
            maxTaskLinkCount: snapshot.maxTaskLinkCount,
            headline: snapshot.headline
        )
    }

    private func agendaSnapshot(_ name: String) throws -> CaptureAgendaSnapshot {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
            .appendingPathComponent(name)
        return try JSONDecoder().decode(
            CaptureAgendaSnapshot.self,
            from: Data(contentsOf: url)
        )
    }
}
