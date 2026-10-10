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
                    themes: CapturePlanBudgetMeter(count: 3, cap: 3, over: false),
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
                    themes: CapturePlanBudgetMeter(count: 4, cap: 3, over: true),
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
                    themes: CapturePlanBudgetMeter(count: 0, cap: 3, over: false),
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

    func testSavedBudgetRowStaysFlatAndHasNoExpansionTarget() throws {
        let snapshot = try budgetedSnapshot(
            "agenda-current.json",
            themes: CapturePlanBudgetMeter(count: 3, cap: 3, over: false),
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
        let rowsWidth = contentWidth
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
        themes: CapturePlanBudgetMeter,
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
                themes: themes,
                links: links
            )
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
