import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

/// Rendered-image review for the idle agenda: one PNG per agenda
/// fixture at full and minimum panel widths, in both appearances.
/// `BOB_MAC_CAPTURE_RENDER_DIR` points at a writable directory; when
/// set, writes the PNGs at scale 2. Inspect the PNGs with an image
/// reader and iterate on spacing, contrast, wrapping, fold rows, and
/// card alignment against the epic plan's visual design. Follows
/// `TaskBlockDesignTests`.
@MainActor
final class CaptureAgendaDesignTests: XCTestCase {
    func testRenderAgendaStatesToPNG() throws {
        guard let renderDir = ProcessInfo.processInfo.environment[
            "BOB_MAC_CAPTURE_RENDER_DIR"
        ], !renderDir.isEmpty else {
            throw XCTSkip(
                "Set BOB_MAC_CAPTURE_RENDER_DIR to render the agenda review images."
            )
        }
        let directory = URL(fileURLWithPath: renderDir, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        // The heavy fixture renders folded at the 533 pt budget; the
        // rest render unfolded.
        let cases: [(base: String, budget: Double)] = [
            ("agenda-current", 2_000),
            ("agenda-nothing-running", 2_000),
            ("agenda-heavy", 533),
            ("agenda-empty", 2_000),
            ("agenda-multiple-timed", 2_000),
        ]
        for (base, budget) in cases {
            let snapshot = try agendaSnapshot(base + ".json")
            let presentation = CaptureAgendaPresentation(
                snapshot: snapshot,
                today: snapshot.date ?? "",
                now: nil
            )
            try render(presentation: presentation, base: base, budget: budget)
        }
        // The stale marker on the title row's right, and the overdue
        // countdown: the current entry ends 08:30, so 08:38 reads
        // "overdue 8m" in orange.
        let current = try agendaSnapshot("agenda-current.json")
        try render(
            presentation: CaptureAgendaPresentation(
                snapshot: current,
                today: current.date ?? "",
                now: nil,
                isStale: true
            ),
            base: "agenda-current-stale",
            budget: 2_000
        )
        let overdueNow = Calendar.current.date(
            from: DateComponents(
                year: 2_026,
                month: 8,
                day: 28,
                hour: 8,
                minute: 38
            )
        )
        try render(
            presentation: CaptureAgendaPresentation(
                snapshot: current,
                today: current.date ?? "",
                now: overdueNow,
                locale: Locale(identifier: "en_US_POSIX")
            ),
            base: "agenda-current-overdue",
            budget: 2_000
        )
    }

    private func render(
        presentation: CaptureAgendaPresentation,
        base: String,
        budget: Double
    ) throws {
        for width in [760, 620] as [CGFloat] {
            let rowsWidth = width - 36
                - 2 * CGFloat(CaptureAgendaLayoutMetrics.panePadding)
            let measurer = CaptureAgendaRowMeasurer()
            let plan = CaptureAgendaHeightResolver.resolve(
                presentation: presentation,
                budget: budget,
                expanded: [],
                width: rowsWidth,
                measurer: measurer
            )
            let pane = CaptureAgendaPaneView(
                plan: plan,
                presentation: presentation
            )
            for appearance in [
                NSAppearance.Name.aqua,
                NSAppearance.Name.darkAqua,
            ] {
                try RenderFixtureWriter.write(
                    pane,
                    name: "agenda-\(base)-\(Int(width))",
                    width: width - 36,
                    appearance: appearance
                )
            }
        }
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
