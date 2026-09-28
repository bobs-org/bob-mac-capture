import Foundation
import XCTest

@testable import CaptureCore

final class CapturePomodoroClosePresentationTests: XCTestCase {
    func testRealBobWorkedClosePresentsSessionTimingTasksAndNext() throws {
        let success = try decodeFixture("pomodoro-close-worked.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertEqual(presentation.variant, .session)
        XCTAssertEqual(presentation.title, "Close CAPTURE")
        XCTAssertEqual(presentation.sessionText, "0920-0950 → 0920-0940 · 20m")
        XCTAssertEqual(presentation.sessionPlannedText, "0920-0950")
        XCTAssertEqual(presentation.sessionDecrementText, "→ 0920-0940 · 20m")
        XCTAssertEqual(presentation.timingText, "13m early")
        XCTAssertEqual(presentation.timingTone, .early)
        XCTAssertEqual(presentation.destinationText, "2026/20260928.md · line 5")
        XCTAssertNil(presentation.viaText)

        XCTAssertEqual(presentation.taskRows.count, 3)
        let worked = presentation.taskRows[0]
        XCTAssertEqual(worked.glyph, .transition)
        XCTAssertEqual(worked.transitionText, "[*] → [/]")
        XCTAssertEqual(worked.taskText, "Add support for `=x` syntax!")
        XCTAssertEqual(worked.locatorText, "bob.md · ^capture-stop")
        XCTAssertEqual(worked.workLogCount, 2)
        XCTAssertEqual(
            worked.workLogPreviews,
            ["Designed the `=x` grammar", "Wrote the plan"]
        )
        XCTAssertNil(worked.warning)
        XCTAssertTrue(worked.carried)
        XCTAssertNil(worked.tag)
        XCTAssertFalse(worked.isStruck)

        let deferred = presentation.taskRows[1]
        XCTAssertEqual(deferred.glyph, .deferred)
        XCTAssertEqual(deferred.transitionText, "[*] deferred")
        XCTAssertEqual(deferred.taskText, "Add capture support for web URLs!")
        XCTAssertEqual(deferred.locatorText, "bob.md · ^web-capture")
        XCTAssertTrue(deferred.workLogPreviews.isEmpty)

        let struck = presentation.taskRows[2]
        XCTAssertEqual(struck.glyph, .struck)
        XCTAssertEqual(struck.transitionText, "[x]")
        XCTAssertEqual(struck.taskText, "Restart axe")
        XCTAssertEqual(struck.locatorText, "sase.md · ^axe-restart")
        XCTAssertEqual(struck.workLogPreviews, ["Restarted axe"])
        XCTAssertTrue(struck.isStruck)

        XCTAssertEqual(presentation.notesText, "1 note stays")
        XCTAssertEqual(presentation.nextText, "Next: CAPTURE · new · carries 2 links")
        XCTAssertEqual(
            presentation.statusText,
            "Closed CAPTURE · 1 started · 3 Work Log entries"
        )
        XCTAssertEqual(presentation.primaryActionTitle, "Close")
        XCTAssertEqual(presentation.notificationTitle, "Closed CAPTURE")
        XCTAssertEqual(
            presentation.notificationBody,
            """
            CAPTURE 0920-0950 → 0920-0940 · 20m · 13m early
            3 tasks · 3 Work Log entries
            Next: CAPTURE · new · carries 2 links
            """
        )
        XCTAssertEqual(presentation.batchSuffix, " (closed CAPTURE)")
        XCTAssertTrue(presentation.accessibilitySummary.contains("Close CAPTURE"))
    }

    func testRealBobLinkCloseKeepsTitleAndTagsLinkedRow() throws {
        let success = try decodeFixture("pomodoro-close-link.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertEqual(presentation.variant, .linkedTask)
        XCTAssertEqual(presentation.title, "Close CAPTURE")
        XCTAssertEqual(presentation.viaText, "Linked bob.md · ^ready into CAPTURE")

        let linked = try XCTUnwrap(
            presentation.taskRows.first(where: { $0.taskText == "Plain ready task" })
        )
        XCTAssertEqual(linked.tag, "linked")
        XCTAssertEqual(linked.transitionText, "[*] → [/]")
        XCTAssertEqual(linked.locatorText, "bob.md · ^ready")
        XCTAssertEqual(
            presentation.taskRows.filter { $0.tag != nil }.count,
            1
        )
        XCTAssertEqual(presentation.nextText, "Next: CAPTURE · new · carries 3 links")
        XCTAssertEqual(
            presentation.statusText,
            "Closed CAPTURE · 2 started · 3 Work Log entries"
        )
    }

    func testRealBobMovedCloseReportsMovedSource() throws {
        let success = try decodeFixture("pomodoro-close-moved.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertEqual(presentation.variant, .linkedTask)
        XCTAssertEqual(presentation.viaText, "Moved from SASE")
        let moved = try XCTUnwrap(
            presentation.taskRows.first(where: { $0.taskText == "Recovery panel" })
        )
        XCTAssertEqual(moved.tag, "linked")
        XCTAssertEqual(moved.locatorText, "sase.md · ^recovery-panel")
    }

    func testRealBobNewTaskCloseTagsNewRow() throws {
        let success = try decodeFixture("pomodoro-close-new-task.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertEqual(presentation.variant, .newTask)
        XCTAssertEqual(presentation.title, "Close CAPTURE")
        XCTAssertEqual(presentation.viaText, "New task Draft docs → bob.md · ^draft-docs")
        let created = try XCTUnwrap(
            presentation.taskRows.first(where: { $0.taskText == "Draft docs" })
        )
        XCTAssertEqual(created.tag, "new")
    }

    func testDryRunPreviewUsesWouldCloseStatus() throws {
        let success = try decodePreview("pomodoro-close-worked.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertTrue(presentation.statusText.hasPrefix("Would close CAPTURE"))
        XCTAssertEqual(presentation.notificationTitle, "Closed CAPTURE")
    }

    func testTimingTones() throws {
        let early = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: try decodeFixture("pomodoro-close-worked.json"))
        )
        XCTAssertEqual(early.timingTone, .early)

        let batch = try decodeFixture("pomodoro-close-batch-adjust.json")
        let closedCapture = try XCTUnwrap(
            batch.captures.first(where: { $0.pomodoroClose != nil })
        )
        let decremented = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closedCapture)
        )
        XCTAssertEqual(decremented.timingText, "3m early")
        XCTAssertEqual(decremented.timingTone, .early)
        // The `-2` adjust already shortened the session, so the close itself
        // shows a single range with no decrement half.
        XCTAssertEqual(decremented.sessionText, "0920-0940 · 20m")
        XCTAssertNil(decremented.sessionDecrementText)

        let onTime = try presentationReplacingRemainingMinutes(in: "pomodoro-close-worked.json", with: 0)
        XCTAssertEqual(onTime.timingText, "on time")
        XCTAssertEqual(onTime.timingTone, .onTime)

        let over = try presentationReplacingRemainingMinutes(in: "pomodoro-close-worked.json", with: -7)
        XCTAssertEqual(over.timingText, "7m over")
        XCTAssertEqual(over.timingTone, .over)
    }

    func testUnnamedSessionFallsBackToSession() throws {
        let raw = try fixtureText("pomodoro-close-worked.json")
            .replacingOccurrences(of: "\"pomodoro_name\":\"CAPTURE\"", with: "\"pomodoro_name\":null")
        let success = try decodeSuccess(raw)
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertEqual(presentation.title, "Close session")
        XCTAssertEqual(presentation.notificationTitle, "Closed session")
    }

    func testEmptyCloseShowsEmptyStateAndNoNotesOrNext() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            dayRelative: "2026/20260928.md",
            planned: PomodoroCloseTiming(
                start: "0920",
                end: "0950",
                durationMinutes: 30,
                timeRange: "0920-0950"
            ),
            closed: PomodoroCloseTiming(
                start: "0920",
                end: "0950",
                durationMinutes: 30,
                timeRange: "0920-0950"
            ),
            closedAt: "0951",
            remainingMinutes: -1,
            decrementedMinutes: 0
        )
        let capture = closeCapture(summary: summary)
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: capture))

        XCTAssertTrue(presentation.taskRows.isEmpty)
        XCTAssertEqual(presentation.emptyText, "No Task Links — the session simply closes")
        XCTAssertNil(presentation.notesText)
        XCTAssertNil(presentation.nextText)
        XCTAssertEqual(presentation.sessionText, "0920-0950 · 30m")
        XCTAssertEqual(
            presentation.statusText,
            "Closed CAPTURE · 0 started · 0 Work Log entries"
        )
    }

    func testTaskRowsTruncateAfterSixWithOverflowCount() throws {
        let rows = (0..<8).map { index in
            PomodoroCloseTask(
                role: "worked",
                blockLink: "[[bob#^task-\(index)]]",
                ledgerLine: 6 + index,
                resolved: true,
                relativeTarget: "bob.md",
                blockID: "task-\(index)",
                text: "Task \(index)",
                previousStatusSymbol: "*",
                statusSymbol: "/",
                statusChanged: true
            )
        }
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: rows
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )

        XCTAssertEqual(presentation.taskRows.count, 8)
        XCTAssertEqual(presentation.visibleTaskRows.count, 6)
        XCTAssertEqual(presentation.overflowTaskCount, 2)
    }

    func testUnknownRoleDegradesToNeutralRow() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "teleported",
                    blockLink: "[[bob#^weird]]",
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "weird",
                    text: "Weird task",
                    statusSymbol: "/"
                )
            ]
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        let row = try XCTUnwrap(presentation.taskRows.first)
        XCTAssertEqual(row.glyph, .neutral)
        XCTAssertEqual(row.locatorText, "bob.md · ^weird")
    }

    func testUnresolvedRowKeepsWarningAndBlockLinkLocator() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "unresolved",
                    blockLink: "[[missing#^gone]]",
                    resolved: false,
                    warning: "left unchanged"
                )
            ]
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        let row = try XCTUnwrap(presentation.taskRows.first)
        XCTAssertEqual(row.glyph, .unresolved)
        XCTAssertEqual(row.transitionText, "[x]")
        XCTAssertEqual(row.locatorText, "[[missing#^gone]]")
        XCTAssertEqual(row.warning, "left unchanged")
    }

    func testWorkLogPreviewsStripDatePrefixAndCapAtTwo() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "worked",
                    blockLink: "[[bob#^busy]]",
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "busy",
                    text: "Busy task",
                    workLog: [
                        "*2026-09-28* — First",
                        "*2026-09-28* — Second",
                        "*2026-09-28* — Third",
                    ]
                )
            ]
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        let row = try XCTUnwrap(presentation.taskRows.first)
        XCTAssertEqual(row.workLogCount, 3)
        XCTAssertEqual(row.workLogPreviews, ["First", "Second"])
    }

    func testEmbeddedAndMentionedRoles() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "embedded",
                    blockLink: "![[bob#^embed]]",
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "embed",
                    text: "Embedded task",
                    previousStatusSymbol: "*",
                    statusSymbol: "x",
                    statusChanged: true
                ),
                PomodoroCloseTask(
                    role: "mentioned",
                    blockLink: "[[bob#^note]]",
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "note",
                    text: "Mentioned task",
                    previousStatusSymbol: "*",
                    statusSymbol: "*"
                ),
            ]
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        XCTAssertEqual(presentation.taskRows[0].glyph, .embedded)
        XCTAssertEqual(presentation.taskRows[0].transitionText, "[x] closed")
        XCTAssertEqual(presentation.taskRows[1].glyph, .transition)
        XCTAssertEqual(presentation.taskRows[1].transitionText, "[*]")
    }

    func testExistingNextSessionNamesLine() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            nextPomodoro: PomodoroCloseNext(line: 14, name: "SASE")
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        XCTAssertEqual(presentation.nextText, "Next: SASE · line 14")
    }

    func testParseSpecDecodesRawCloseToken() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-session.json").utf8)
        )
        XCTAssertEqual(response.mode, "pomodoro_close")
        XCTAssertEqual(response.pomodoroClose?.raw, "=x")
        XCTAssertEqual(response.spans.map(\.kind), ["pomodoro_close"])

        let incomplete = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-incomplete.json").utf8)
        )
        XCTAssertEqual(incomplete.mode, "incomplete")
        XCTAssertNil(incomplete.pomodoroClose)

        let link = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-link.json").utf8)
        )
        XCTAssertEqual(link.mode, "pomodoro_link")
        XCTAssertEqual(link.pomodoroClose?.raw, "=x")
    }

    func testEveryCloseFixtureDecodes() throws {
        for name in [
            "pomodoro-close-worked.json",
            "pomodoro-close-link.json",
            "pomodoro-close-new-task.json",
            "pomodoro-close-moved.json",
            "pomodoro-close-batch-adjust.json",
        ] {
            let success = try decodeFixture(name)
            XCTAssertNotNil(
                success.pomodoroClose ?? success.captures.first?.pomodoroClose,
                name
            )
        }
        for name in [
            "pomodoro-close-no-running.json",
            "pomodoro-close-incomplete.json",
            "pomodoro-close-bad-name.json",
        ] {
            let raw = try fixtureText(name)
            let response = try JSONDecoder().decode(
                CaptureCommandResponse.self,
                from: Data(raw.utf8)
            )
            guard case .failure(let failure) = response else {
                XCTFail("expected failed Bob response for \(name)")
                continue
            }
            XCTAssertFalse(failure.error.isEmpty, name)
        }
    }

    func testSparseCloseSummaryStillDecodes() throws {
        let success = try decodeSuccess(
            #"""
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "2026/20260928.md",
              "target": "/tmp/bob/2026/20260928.md",
              "text": "=x",
              "task_line": "- [x] entry",
              "kind": "pomodoro_close",
              "created": "2026-09-28",
              "scheduled": null,
              "placement": "closed",
              "pomodoro_close": {"raw": "=x"}
            }
            """#
        )
        let summary = try XCTUnwrap(success.pomodoroClose)
        XCTAssertEqual(summary.raw, "=x")
        XCTAssertEqual(summary.pomodoroLine, 0)
        XCTAssertTrue(summary.tasks.isEmpty)
        XCTAssertTrue(summary.carried.isEmpty)
        XCTAssertTrue(summary.notes.isEmpty)
        XCTAssertNil(summary.nextPomodoro)
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))
        XCTAssertEqual(presentation.title, "Close session")
    }

    func testOlderBobCaptureWithoutCloseSummaryRemainsCompatible() throws {
        let success = try decodeSuccess(
            #"""
            {
              "ok": true,
              "dry_run": true,
              "routed": true,
              "route": "cash",
              "route_label": "cash.md",
              "relative_target": "cash.md",
              "target": "/tmp/bob/cash.md",
              "text": "Call bank",
              "task_line": "- [ ] #task Call bank",
              "kind": "task",
              "created": "2026-08-14",
              "scheduled": null,
              "placement": "inserted"
            }
            """#
        )

        XCTAssertNil(success.pomodoroClose)
        XCTAssertNil(CapturePomodoroClosePresentation(capture: success))
    }

    // MARK: - Helpers

    private func closeCapture(summary: PomodoroCloseSummary) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: false,
            routeLabel: "",
            relativeTarget: "2026/20260928.md",
            target: "/tmp/bob/2026/20260928.md",
            text: "=x",
            taskLine: "- [x] entry",
            kind: "pomodoro_close",
            created: "2026-09-28",
            placement: "closed",
            pomodoroClose: summary
        )
    }

    private func presentationReplacingRemainingMinutes(
        in fixture: String,
        with minutes: Int
    ) throws -> CapturePomodoroClosePresentation {
        let raw = try fixtureText(fixture)
        let range = try XCTUnwrap(raw.range(of: "\"remaining_minutes\":13"))
        let replaced = raw.replacingCharacters(
            in: range,
            with: "\"remaining_minutes\":\(minutes)"
        )
        let success = try decodeSuccess(replaced)
        return try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))
    }

    private func decodePreview(_ name: String) throws -> CaptureCommandSuccess {
        let raw = try fixtureText(name)
            .replacingOccurrences(of: "\"dry_run\":false", with: "\"dry_run\":true")
        return try decodeSuccess(raw)
    }

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        try decodeSuccess(fixtureText(name))
    }

    private func fixtureText(_ name: String) throws -> String {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    private func decodeSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(json.utf8))
        guard case .success(let success) = response else {
            XCTFail("expected successful Bob response")
            throw NSError(domain: "CapturePomodoroClosePresentationTests", code: 1)
        }
        return success
    }
}
