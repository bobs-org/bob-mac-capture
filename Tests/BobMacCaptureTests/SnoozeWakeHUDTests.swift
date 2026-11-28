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

    func testHUDHoverPausesCountdownAndResumesWithoutRestarting() async {
        let hud = makeController()
        defer { hud.dismiss() }
        let presentation = makePresentation(count: 1, overCap: false)
        hud.show(batch: presentation.batch, presentation: presentation)
        XCTAssertEqual(hud.secondsRemaining, 12, accuracy: 0.5)
        try? await Task.sleep(nanoseconds: 700_000_000)
        let beforeHover = hud.secondsRemaining
        XCTAssertLessThan(beforeHover, 11.7)
        hud.setHovered(true)
        try? await Task.sleep(nanoseconds: 800_000_000)
        let paused = hud.secondsRemaining
        XCTAssertEqual(paused, beforeHover, accuracy: 0.4)
        XCTAssertNotEqual(paused, 12, accuracy: 0.5)
        hud.setHovered(false)
        try? await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertLessThan(hud.secondsRemaining, paused - 0.25)
    }

    func testOneAnnouncementPerNewOrOrderedInWakeNoneOnSilentRestore() {
        var announcements: [String] = []
        let hud = makeController()
        hud.announcementSink = { announcements.append($0) }
        defer { hud.dismiss() }
        let first = makePresentation(count: 1, overCap: false)
        hud.show(batch: first.batch, presentation: first)
        XCTAssertEqual(announcements.count, 1)
        hud.show(batch: first.batch, presentation: first)
        XCTAssertEqual(announcements.count, 1)
        hud.restore(batch: first.batch, presentation: first)
        XCTAssertEqual(announcements.count, 1)
        hud.dismiss()
        hud.show(batch: first.batch, presentation: first)
        XCTAssertEqual(announcements.count, 2)
        let second = makePresentation(count: 2, overCap: false)
        hud.show(batch: second.batch, presentation: second)
        XCTAssertEqual(announcements.count, 3)
    }

    func testOpaqueFallbackUnderInjectedReduceTransparency() {
        let hud = makeController(reduceTransparency: { true })
        defer { hud.dismiss() }
        let presentation = makePresentation(count: 1, overCap: false)
        hud.show(batch: presentation.batch, presentation: presentation)
        XCTAssertTrue(hud.opaqueFallbackActive)
        let glass = makeController(reduceTransparency: { false })
        defer { glass.dismiss() }
        glass.show(batch: presentation.batch, presentation: presentation)
        XCTAssertFalse(glass.opaqueFallbackActive)
    }

    func testPartialPlus15mKeepsRefusedTaskWithBobWordsAndDoesNotRetrySuccess() async throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("snooze-hud-partial-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let (client, logURL) = try makeCountingAddClient(vaultRoot: vault.path)
        let hud = makeController(
            processClient: client, vaultRoot: vault.path, today: "2026-01-02")
        defer { hud.dismiss() }
        let presentation = makePresentation(
            count: 2, overCap: false, vaultRoot: vault.path)
        hud.show(batch: presentation.batch, presentation: presentation)
        _ = try hud.probePress("snooze15")
        try await waitUntil {
            hud.currentState?.isSnoozing == false && hud.currentState?.feedback != nil
        }
        XCTAssertEqual(hud.currentState?.batch.rows.count, 1)
        XCTAssertEqual(hud.currentState?.batch.rows.first?.blockID, "^task-1")
        let feedback = try XCTUnwrap(hud.currentState?.feedback)
        XCTAssertTrue(feedback.contains("task cannot be snoozed after midnight"), feedback)
        let log = try String(contentsOf: logURL)
        let addLines = log.split(separator: "\n").filter { $0.hasPrefix("argv=") }
        XCTAssertEqual(addLines.count, 2)
        XCTAssertTrue(addLines.contains(where: { $0.contains("tasks.md:^task-0") }))
        XCTAssertTrue(addLines.contains(where: { $0.contains("tasks.md:^task-1") }))
    }

    func testRefusedPlus15mKeepsTaskWithBobWords() async throws {
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("snooze-hud-refuse-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let client = try makeClient(
            vaultRoot: vault.path,
            extra: [
                "FAKE_BOB_SNOOZE_ADD_ERROR_JSON":
                    #"{"ok":false,"error":{"kind":"invalid_time","message":"task cannot be snoozed after midnight"}}"#
            ]
        )
        let hud = makeController(
            processClient: client, vaultRoot: vault.path, today: "2026-01-02")
        defer { hud.dismiss() }
        let presentation = makePresentation(
            count: 1, overCap: false, vaultRoot: vault.path)
        hud.show(batch: presentation.batch, presentation: presentation)
        _ = try hud.probePress("snooze15")
        try await waitUntil {
            hud.currentState?.isSnoozing == false && hud.currentState?.feedback != nil
        }
        XCTAssertEqual(hud.currentState?.batch.rows.count, 1)
        XCTAssertEqual(
            hud.currentState?.feedback, "task cannot be snoozed after midnight")
    }

    func testOpenSinkRecordsURLInsteadOfLaunching() throws {
        var opened: [URL] = []
        let vault = FileManager.default.temporaryDirectory
            .appendingPathComponent("snooze-hud-open-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vault, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vault) }
        let hud = SnoozeWakeHUDController(
            processClient: { nil },
            vaultRoot: { vault.path },
            today: { "2026-01-02" },
            refreshAgenda: {},
            chimeEnabled: { false },
            reduceMotion: { true },
            reduceTransparency: { false },
            openURL: { url in
                opened.append(url)
                return true
            },
            playChime: { false }
        )
        hud.openSinkEnabled = true
        defer { hud.dismiss() }
        let presentation = makePresentation(
            count: 1, overCap: false, vaultRoot: vault.path)
        hud.show(batch: presentation.batch, presentation: presentation)
        _ = try hud.probePress("open")
        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(hud.lastOpenedURLs.count, 1)
        XCTAssertTrue(hud.lastOpenedURLs[0].contains("bob-goto-task"))
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

    private func makeController(
        processClient: BobProcessClient? = nil,
        vaultRoot: String = "/tmp",
        today: String = "2026-01-02",
        reduceMotion: @escaping () -> Bool = { true },
        reduceTransparency: @escaping () -> Bool = { false }
    ) -> SnoozeWakeHUDController {
        SnoozeWakeHUDController(
            processClient: { processClient },
            vaultRoot: { vaultRoot },
            today: { today },
            refreshAgenda: {},
            chimeEnabled: { false },
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            openURL: { _ in true },
            playChime: { true }
        )
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot =
            source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return
            packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func listJSON(vaultRoot: String, count: Int) -> String {
        let rows = (0..<count).map { index in
            """
            {"line":\(index + 4),"route":"tasks.md","block_id":"^task-\(index)",\
            "title":"Snoozed task \(index + 1)","target":"1532","state":"woken",\
            "woke_at":"15:32","wake_notice_eligible":true}
            """
        }.joined(separator: ",")
        return
            """
            {"schema_version":1,"wake_notice_version":1,"vault_root":"\(vaultRoot)",\
            "date":"2026-01-02","now":"2026-01-02T15:32:10-05:00",\
            "rows":[\(rows)],"next_wake_at":null,"plan":{"count":1,"cap":10,"over":false}}
            """
    }

    private func makeClient(vaultRoot: String, extra: [String: String] = [:]) throws
        -> BobProcessClient
    {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_SNOOZE_LIST_JSON": listJSON(vaultRoot: vaultRoot, count: 2),
        ]
        for (key, value) in extra {
            environment[key] = value
        }
        return BobProcessClient(
            executablePath: try fakeBobPath(), environment: environment)
    }

    private func makeCountingAddClient(vaultRoot: String) throws -> (
        BobProcessClient, URL
    ) {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("snooze-add-shim-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let logURL = directory.appendingPathComponent("add.log")
        let countURL = directory.appendingPathComponent("count")
        let listURL = directory.appendingPathComponent("list.json")
        try Data("0".utf8).write(to: countURL)
        try Data().write(to: logURL)
        try Data(listJSON(vaultRoot: vaultRoot, count: 2).utf8).write(to: listURL)
        let wrapper = directory.appendingPathComponent("shim-bob")
        let fake = try fakeBobPath()
        let script = """
            #!/bin/bash
            set -euo pipefail
            LOG="\(logURL.path)"
            COUNT="\(countURL.path)"
            FAKE="\(fake)"
            if [ "${1:-}" = "snooze" ] && [ "${2:-}" = "add" ]; then
              n=$(($(cat "$COUNT") + 1))
              printf '%s\\n' "$n" >"$COUNT"
              printf 'argv=%s\\n' "$*" >>"$LOG"
              if [ "$n" -eq 1 ]; then
                printf '%s\\n' '{"schema_version":1,"date":"2026-01-02","now":"2026-01-02T15:32:00-05:00","status":"added","task":{"route":"tasks.md","block_id":"^task-0","title":"Snoozed task 1"},"target":{"time":"15:47","at":"2026-01-02T15:47:00-05:00"},"lane":"next","daily_file":"2026/20260102.md","plan":{"count":1,"cap":10,"over":false},"dry_run":false}'
                exit 0
              fi
              printf '%s\\n' '{"ok":false,"error":{"kind":"invalid_time","message":"task cannot be snoozed after midnight"}}'
              exit 2
            fi
            export FAKE_BOB_SNOOZE_LIST_JSON_FILE="\(listURL.path)"
            exec "$FAKE" "$@"
            """
        try script.write(to: wrapper, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: wrapper.path)
        let client = BobProcessClient(
            executablePath: wrapper.path,
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        return (client, logURL)
    }

    private func waitUntil(
        timeout: TimeInterval = 5, _ condition: @escaping () -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("condition not met before timeout")
    }

    private func makePresentation(
        count: Int,
        overCap: Bool,
        plan: (Int, Int)? = nil,
        vaultRoot: String = "/vault/example"
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
            vaultRoot: vaultRoot,
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
