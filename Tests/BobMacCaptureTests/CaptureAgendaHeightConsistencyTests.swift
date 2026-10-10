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
                fixture: "agenda-heavy.json",
                contentWidth: width,
                budget: 533,
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

    private func assertConsistent(
        fixture: String,
        contentWidth: CGFloat,
        budget: Double,
        expanded: Set<CaptureAgendaUnitID>
    ) throws {
        let snapshot = try agendaSnapshot(fixture)
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
