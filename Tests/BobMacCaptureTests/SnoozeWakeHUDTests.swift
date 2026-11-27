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
        XCTAssertEqual(panel.sharingType, .none)

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
        XCTAssertTrue(url.absoluteString.contains("block=email-dan"))
        let missingBlock = SnoozeWakeListRow(
            line: 7,
            route: "Projects/Email Dan.md",
            blockID: nil,
            title: "Email Dan",
            target: "1532",
            state: "woken",
            wokeAt: "15:32",
            wakeNoticeEligible: true
        )
        XCTAssertNil(
            SnoozeWakeHUDController.validatedTaskURL(row: missingBlock, vaultRoot: root.path)
        )
        XCTAssertNil(
            SnoozeWakeHUDController.validatedRoute("../outside.md", vaultRoot: root.path)
        )
        XCTAssertNil(
            SnoozeWakeHUDController.validatedRoute("/outside.md", vaultRoot: root.path)
        )
    }

    func testHUDSubtitleUsesBobBudgetAndWokeTime() {
        let single = makePresentation(count: 1, overCap: false, plan: (11, 13))
        XCTAssertEqual(single.budgetText, "TODAY 11/13")
        XCTAssertEqual(single.wokeTimeText, "15:32")
        XCTAssertEqual(single.subtitleText, "woke 15:32 · in WRITE · TODAY 11/13")
        // The fixture date (01/02) must not coincide with the budget (11/13):
        // the TODAY text can only come from bob's live-link plan.
        XCTAssertEqual(single.batch.date, "2026-01-02")
        XCTAssertEqual(single.listBudget.count, 11)
        XCTAssertEqual(single.listBudget.cap, 13)

        let batch = makePresentation(count: 2, overCap: false, plan: (4, 10))
        XCTAssertEqual(batch.subtitleText, "woke 15:32 · TODAY 4/10")

        let over = makePresentation(count: 5, overCap: true, plan: (14, 13))
        XCTAssertTrue(over.isOverCap)
        XCTAssertEqual(over.subtitleText, "woke 15:32 · TODAY 14/13")
    }

    func testHUDRenderFixturesForSingleBatchAndOpaqueFallback() throws {
        let single = makePresentation(count: 1, overCap: false, plan: (11, 13))
        try render(single, name: "snooze-wake-hud-single")

        let three = makePresentation(count: 3, overCap: false, plan: (4, 10))
        try render(three, name: "snooze-wake-hud-batch-three")

        let batch = makePresentation(count: 5, overCap: true, plan: (14, 13))
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
        overCap: Bool,
        plan: (Int, Int)? = nil
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
        let instant = CaptureRFC3339Date.date(from: "2026-01-02T15:32:00-05:00")!
        let batch = SnoozeWakeNoticeBatch(
            wakeID: "wake-\(count)",
            wokenAt: instant,
            date: "2026-01-02",
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
        let budget: SnoozeWakeLinkPlan = {
            if let plan {
                return SnoozeWakeLinkPlan(count: plan.0, cap: plan.1, over: overCap)
            }
            return SnoozeWakeLinkPlan(count: count, cap: 3, over: overCap)
        }()
        return SnoozeWakeNoticePresentation(
            batch: batch,
            listBudget: budget
        )
    }
}
