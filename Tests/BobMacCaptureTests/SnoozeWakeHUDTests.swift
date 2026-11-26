import AppKit
import CaptureCore
import SwiftUI
import XCTest

@testable import BobMacCapture

@MainActor
final class SnoozeWakeHUDTests: XCTestCase {
    func testHUDPanelIsInteractiveWithoutTakingKeyOrMain() {
        let panel = SnoozeWakeHUDController.makePanel()

        XCTAssertTrue(panel.styleMask.contains(.borderless))
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertFalse(panel.ignoresMouseEvents)
        XCTAssertTrue(panel.acceptsMouseMovedEvents)

        let host = FirstMouseHostingView(rootView: EmptyView())
        XCTAssertTrue(host.acceptsFirstMouse(for: nil))
    }

    func testTopCenterPlacementUsesThePointerDisplayAndVisibleBounds() {
        let visible = NSRect(x: -1200, y: 50, width: 1000, height: 700)
        let frame = GlassPanelHost.frame(
            size: NSSize(width: 560, height: 180),
            placement: .topCenter(in: visible, inset: 18)
        )

        XCTAssertEqual(frame.width, 560)
        XCTAssertEqual(frame.midX, visible.midX)
        XCTAssertEqual(frame.maxY, visible.maxY - 18)
        XCTAssertTrue(visible.contains(frame))
    }

    func testTaskOpenURLUsesAValidatedVaultRelativeRoute() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("snooze-hud-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let row = SnoozeWakeListRow(
            line: 7,
            route: "Projects/Email Dan.md",
            blockID: "^email-dan",
            title: "Email Dan",
            target: "1532",
            state: "woken",
            wokeAt: "15:32",
            wakeNoticeEligible: true
        )

        let url = try XCTUnwrap(
            SnoozeWakeHUDController.validatedTaskURL(row: row, vaultRoot: root.path)
        )
        XCTAssertEqual(url.scheme, "obsidian")
        XCTAssertEqual(url.host, "bob-goto-task")
        XCTAssertTrue(url.absoluteString.contains("path="))
        XCTAssertTrue(url.absoluteString.contains("line=7"))
        XCTAssertNil(
            SnoozeWakeHUDController.validatedRoute("../outside.md", vaultRoot: root.path)
        )
        XCTAssertNil(
            SnoozeWakeHUDController.validatedRoute("/outside.md", vaultRoot: root.path)
        )
    }

    func testHUDRenderFixturesForSingleBatchAndOpaqueFallback() throws {
        let single = makePresentation(count: 1, overCap: false)
        try render(single, name: "snooze-wake-hud-single")

        let batch = makePresentation(count: 5, overCap: true)
        try render(batch, name: "snooze-wake-hud-batch-over-cap")
        try render(
            batch,
            name: "snooze-wake-hud-opaque-fallback",
            opaque: true
        )
    }

    private func render(
        _ presentation: SnoozeWakeNoticePresentation,
        name: String,
        opaque: Bool = false
    ) throws {
        let state = SnoozeWakeHUDState(
            batch: presentation.batch,
            presentation: presentation
        )
        let view = SnoozeWakeHUDView(
            state: state,
            reduceMotion: true,
            onOpen: { _ in },
            onSnooze: {},
            onDismiss: {},
            onHover: { _ in }
        )
        .padding(20)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(opaque ? Color(nsColor: .windowBackgroundColor) : Color.primary.opacity(0.08))
        }
        for appearance in [NSAppearance.Name.aqua, NSAppearance.Name.darkAqua] {
            try RenderFixtureWriter.write(
                view,
                name: name,
                width: 560,
                appearance: appearance
            )
        }
    }

    private func makePresentation(
        count: Int,
        overCap: Bool
    ) -> SnoozeWakeNoticePresentation {
        let rows = (0..<count).map { index in
            SnoozeWakeListRow(
                line: index + 4,
                route: "tasks.md",
                blockID: "^task-\(index)",
                title: "Snoozed task \(index + 1) with a title that can wrap onto another line",
                target: "1532",
                state: "woken",
                wokeAt: "15:32",
                wakeNoticeEligible: true
            )
        }
        let instant = CaptureRFC3339Date.date(from: "2026-11-13T15:32:00-05:00")!
        let batch = SnoozeWakeNoticeBatch(
            wakeID: "wake-\(count)",
            wokenAt: instant,
            date: "2026-11-13",
            rows: rows,
            vaultRoot: "/vault/example",
            receiptTasks: rows.map { row in
                SnoozeWakeReceiptTask(
                    title: row.title,
                    route: row.route,
                    blockID: row.blockID,
                    target: row.target,
                    wokeAt: row.wokeAt,
                    destination: "WRITE",
                    line: row.line
                )
            }
        )
        return SnoozeWakeNoticePresentation(
            batch: batch,
            listBudget: SnoozeWakeLinkPlan(count: count, cap: 3, over: overCap)
        )
    }
}
