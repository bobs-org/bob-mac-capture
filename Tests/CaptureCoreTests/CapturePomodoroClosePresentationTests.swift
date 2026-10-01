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
            "pomodoro-close-select-worked.json",
            "pomodoro-close-select-complete.json",
            "pomodoro-close-select-none.json",
            "pomodoro-close-select-one.json",
        ] {
            let success = try decodeFixture(name)
            XCTAssertNotNil(
                success.pomodoroClose
                    ?? success.captures.first(where: { $0.pomodoroClose != nil })?.pomodoroClose,
                name
            )
        }
        for name in [
            "pomodoro-close-no-running.json",
            "pomodoro-start-running.json",
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

    func testSelectWorkedCloseBadgesDimmingSummaryAndHint() throws {
        let success = try decodeFixture("pomodoro-close-select-worked.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertTrue(presentation.hasSelection)
        XCTAssertNil(presentation.teachingHint)
        XCTAssertEqual(presentation.selectionSummary, "In progress 2 · Deferred 1")
        XCTAssertEqual(presentation.completedCount, 0)

        let first = presentation.taskRows[0]
        XCTAssertEqual(first.index, 1)
        XCTAssertEqual(first.outcome, .deferred)
        XCTAssertEqual(first.source, .unlisted)
        XCTAssertEqual(first.badgeSymbolName, "1.circle")
        XCTAssertFalse(first.usesNumericBadgeFallback)
        XCTAssertTrue(first.isDimmed)

        let second = presentation.taskRows[1]
        XCTAssertEqual(second.index, 2)
        XCTAssertEqual(second.outcome, .inProgress)
        XCTAssertEqual(second.source, .listed)
        XCTAssertEqual(second.badgeSymbolName, "2.circle.fill")
        XCTAssertFalse(second.isDimmed)

        let struck = presentation.taskRows[2]
        XCTAssertNil(struck.index)
        XCTAssertNil(struck.outcome)
        XCTAssertNil(struck.badgeSymbolName)
        XCTAssertFalse(struck.isDimmed)

        // No completions: the status keeps today's shape.
        XCTAssertEqual(
            presentation.statusText,
            "Closed CAPTURE · 1 started · 3 Work Log entries"
        )
        XCTAssertEqual(
            presentation.taskRows[0].accessibilityLabel,
            "Task 1, Add support for `=x` syntax!, deferred"
        )
        XCTAssertEqual(
            presentation.taskRows[1].accessibilityLabel,
            "Task 2, Add capture support for web URLs!, stays in progress, chosen"
        )
        XCTAssertTrue(presentation.accessibilitySummary.contains("In progress 2 · Deferred 1"))
    }

    func testSelectCompleteCloseStrikesRowAndCountsCompleted() throws {
        let success = try decodeFixture("pomodoro-close-select-complete.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertTrue(presentation.hasSelection)
        XCTAssertEqual(presentation.selectionSummary, "In progress 1 · Complete 2")
        XCTAssertEqual(presentation.completedCount, 1)

        let complete = presentation.taskRows[1]
        XCTAssertEqual(complete.outcome, .complete)
        XCTAssertEqual(complete.source, .listed)
        XCTAssertEqual(complete.glyph, .embedded)
        XCTAssertEqual(complete.transitionText, "[*] → [x]")
        XCTAssertTrue(complete.isStruck)
        XCTAssertFalse(complete.isDimmed)
        XCTAssertEqual(
            complete.accessibilityLabel,
            "Task 2, Add capture support for web URLs!, completes, chosen"
        )

        XCTAssertEqual(
            presentation.statusText,
            "Closed CAPTURE · 2 started · 1 completed · 3 Work Log entries"
        )
        XCTAssertTrue(
            presentation.notificationBody.contains("3 tasks · 1 completed · 3 Work Log entries")
        )
    }

    func testSelectNoneCloseShowsInProgressNone() throws {
        let success = try decodeFixture("pomodoro-close-select-none.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertTrue(presentation.hasSelection)
        XCTAssertEqual(presentation.selectionSummary, "In progress none · Deferred 1, 2")
        XCTAssertTrue(presentation.taskRows[0].isDimmed)
        XCTAssertTrue(presentation.taskRows[1].isDimmed)
    }

    func testPlainCloseWithLineupShowsTeachingHint() throws {
        let success = try decodeFixture("pomodoro-close-worked.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertFalse(presentation.hasSelection)
        XCTAssertNil(presentation.selectionSummary)
        let hint = try XCTUnwrap(presentation.teachingHint)
        XCTAssertEqual(
            hint.text,
            "=x1,2 keeps only these in progress · =x!2 completes 2 · =x~3 drops 3 · =x0 defers all · =x1 wrote the tests logs work to 1"
        )
        XCTAssertEqual(hint.tokens.first?.category, .pomodoroStart)
        XCTAssertTrue(
            hint.tokens.contains { $0.text == "1,2" && $0.category == .pomodoroCloseInProgress }
        )
        XCTAssertTrue(
            hint.tokens.contains { $0.text == "!2" && $0.category == .pomodoroCloseComplete }
        )
        XCTAssertTrue(
            hint.tokens.contains { $0.text == "~3" && $0.category == .pomodoroCloseDrop }
        )
        // Plain `=x`: every row keeps its ledger outcome, nothing dims.
        XCTAssertTrue(presentation.taskRows.allSatisfy { !$0.isDimmed })
        XCTAssertEqual(presentation.taskRows[0].badgeSymbolName, "1.circle")
        XCTAssertTrue(presentation.accessibilitySummary.contains(hint.text))
    }

    func testSingleRowHintUsesSingularWording() throws {
        let tokens = CapturePomodoroClosePresentation.hintTokens(numberedRows: 1)
        XCTAssertEqual(
            tokens.map(\.text).joined(),
            "=x!1 completes it · =x~1 drops it · =x0 defers it · =x1 wrote the tests logs work to 1"
        )
    }

    func testNumberedRowsNeverOverflow() throws {
        let numbered = (1...2).map { index in
            PomodoroCloseTask(
                role: "worked",
                blockLink: "[[bob#^task-\(index)]]",
                ledgerLine: 5 + index,
                index: index,
                resolved: true,
                relativeTarget: "bob.md",
                blockID: "task-\(index)",
                text: "Task \(index)",
                previousStatusSymbol: "*",
                statusSymbol: "/",
                statusChanged: true
            )
        }
        let unnumbered = (0..<8).map { index in
            PomodoroCloseTask(
                role: "struck",
                blockLink: "[[sase#^old-\(index)]]",
                ledgerLine: 20 + index,
                resolved: true,
                relativeTarget: "sase.md",
                blockID: "old-\(index)",
                text: "Old \(index)",
                statusSymbol: "x"
            )
        }
        let links = (1...2).map { index in
            PomodoroCloseTaskLink(
                index: index,
                ledgerLine: 5 + index,
                blockLink: "[[bob#^task-\(index)]]",
                blockID: "task-\(index)",
                marker: "plain",
                outcome: "in_progress",
                source: "listed"
            )
        }
        let summary = PomodoroCloseSummary(
            raw: "=x1,2",
            inProgress: [1, 2],
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: numbered + unnumbered,
            taskLinks: links
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )

        // The cap (6) hides only unnumbered rows: both numbered rows render.
        XCTAssertEqual(presentation.taskRows.count, 10)
        XCTAssertEqual(presentation.visibleTaskRows.count, 6)
        XCTAssertEqual(presentation.overflowTaskCount, 4)
        XCTAssertTrue(presentation.visibleTaskRows.allSatisfy { $0.index != nil || $0.role == "struck" })
        XCTAssertEqual(
            presentation.visibleTaskRows.compactMap(\.index).sorted(),
            [1, 2]
        )
    }

    func testBadgeFallsBackAboveFifty() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x51",
            inProgress: [51],
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "worked",
                    blockLink: "[[bob#^big]]",
                    ledgerLine: 6,
                    index: 51,
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "big",
                    text: "Big task",
                    previousStatusSymbol: "*",
                    statusSymbol: "/",
                    statusChanged: true
                )
            ],
            taskLinks: [
                PomodoroCloseTaskLink(
                    index: 51,
                    ledgerLine: 6,
                    blockLink: "[[bob#^big]]",
                    blockID: "big",
                    marker: "plain",
                    outcome: "in_progress",
                    source: "listed"
                )
            ]
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        let row = try XCTUnwrap(presentation.taskRows.first)
        XCTAssertNil(row.badgeSymbolName)
        XCTAssertTrue(row.usesNumericBadgeFallback)
    }

    func testOlderBobWithoutSelectionFieldsKeepsTodayCard() throws {
        let success = try decodeSuccess(
            #"""
            {
              "ok": true,
              "dry_run": false,
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
              "pomodoro_close": {
                "raw": "=x",
                "pomodoro_line": 5,
                "pomodoro_name": "CAPTURE",
                "tasks": [
                  {
                    "role": "worked",
                    "block_link": "[[bob#^capture-stop]]",
                    "ledger_line": 6,
                    "resolved": true,
                    "relative_target": "bob.md",
                    "block_id": "capture-stop",
                    "text": "Add support for `=x` syntax!",
                    "previous_status_symbol": "*",
                    "status_symbol": "/",
                    "status_changed": true,
                    "carried": true,
                    "work_log": [],
                    "work_log_created": false
                  }
                ],
                "carried": [],
                "notes": []
              }
            }
            """#
        )
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))
        XCTAssertFalse(presentation.hasSelection)
        XCTAssertNil(presentation.teachingHint)
        XCTAssertNil(presentation.selectionSummary)
        XCTAssertEqual(presentation.completedCount, 0)
        let row = try XCTUnwrap(presentation.taskRows.first)
        XCTAssertNil(row.index)
        XCTAssertNil(row.outcome)
        XCTAssertNil(row.badgeSymbolName)
        XCTAssertFalse(row.isDimmed)
        XCTAssertEqual(row.transitionText, "[*] → [/]")
        XCTAssertEqual(
            presentation.statusText,
            "Closed CAPTURE · 1 started · 0 Work Log entries"
        )
    }

    func testParseSelectSpecDecodesLists() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-select.json").utf8)
        )
        XCTAssertEqual(response.mode, "pomodoro_close")
        XCTAssertEqual(response.pomodoroClose?.raw, "=x1,3!2")
        XCTAssertEqual(response.pomodoroClose?.inProgress, [1, 3])
        XCTAssertEqual(response.pomodoroClose?.complete, [2])
        XCTAssertEqual(
            response.spans.map(\.kind),
            ["pomodoro_close", "pomodoro_close_in_progress", "pomodoro_close_complete"]
        )
    }

    func testParseIncompleteNeedsCloseTaskWithPlaceholder() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-incomplete.json").utf8)
        )
        XCTAssertEqual(response.mode, "incomplete")
        XCTAssertEqual(response.needs, ["pomodoro_close_task"])
        XCTAssertEqual(response.pomodoroClose?.inProgress, [1])
        XCTAssertEqual(response.pomodoroClose?.complete, [])
        XCTAssertEqual(
            response.spans.map(\.kind),
            ["pomodoro_close", "pomodoro_close_in_progress", "interactive_placeholder"]
        )
    }

    func testParseInvalidCloseReportsDiagnostic() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-invalid.json").utf8)
        )
        XCTAssertNil(response.pomodoroClose)
        let diagnostic = try XCTUnwrap(response.diagnostics.first)
        XCTAssertEqual(diagnostic.code, "invalid_pomodoro_close")
        XCTAssertTrue(diagnostic.message.contains("listed twice"))
    }

    func testPendingTextNamesSeparator() throws {
        XCTAssertEqual(
            CapturePomodoroClosePresentation.pendingText(separator: ","),
            "Type a task number after ,"
        )
        XCTAssertEqual(
            CapturePomodoroClosePresentation.pendingText(separator: "!"),
            "Type a task number after !"
        )
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

    func testRealBobDropNowCloseMapsDroppedOutcomeAndStaysStatusCaption() throws {
        let success = try decodeFixture("pomodoro-close-drop-now.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertTrue(presentation.hasSelection)
        XCTAssertEqual(presentation.selectionSummary, "In progress 1 · Deferred 2, 3 · Dropped 4")

        // The batch-level budget decodes alongside the close: the close
        // removed one link (4 before, 3 after) without adding a theme.
        XCTAssertEqual(success.planBudget?.status, "ok")
        XCTAssertEqual(success.planBudget?.themes.count, 1)
        XCTAssertEqual(success.planBudget?.themes.before, 1)
        XCTAssertEqual(success.planBudget?.links.count, 3)
        XCTAssertEqual(success.planBudget?.links.before, 4)

        let kept = try XCTUnwrap(presentation.taskRows.first(where: { $0.index == 3 }))
        XCTAssertNil(kept.caption)
        XCTAssertFalse(kept.isStruck)
        // Unlisted rows dim so the chosen rows stand out, dropped or not.
        XCTAssertTrue(kept.isDimmed)

        let dropped = try XCTUnwrap(presentation.taskRows.first(where: { $0.index == 4 }))
        XCTAssertEqual(dropped.outcome, .dropped)
        XCTAssertEqual(dropped.glyph, .dropped)
        XCTAssertTrue(dropped.isStruck)
        XCTAssertTrue(dropped.isDimmed)
        XCTAssertEqual(dropped.caption, "stays Ready")
        XCTAssertEqual(
            dropped.accessibilityLabel,
            "Task 4, Drop me #now, drops from today, chosen"
        )
        XCTAssertTrue(presentation.accessibilitySummary.contains("drops from today"))
    }

    func testParseDropSpecDecodesDropListAndSpan() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-drop.json").utf8)
        )
        XCTAssertEqual(response.pomodoroClose?.raw, "=x1~2")
        XCTAssertEqual(response.pomodoroClose?.inProgress, [1])
        XCTAssertEqual(response.pomodoroClose?.drop, [2])
        XCTAssertEqual(
            response.spans.map(\.kind),
            ["pomodoro_close", "pomodoro_close_in_progress", "pomodoro_close_drop"]
        )
    }

    func testTrailingNowTagIsAnOrdinaryTagError() throws {
        // Real `bob capture-parse` output: a trailing `#now` after the
        // route is the ordinary trailing-tag error, with no spans and no
        // completion needs.
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data("""
            {"ok":true,"schema_version":1,"input":"Fix it @sase^fix-it #now","body":"Fix it @sase^fix-it #now","mode":"task","route":null,"section":null,"block_id":null,"needs":[],"spans":[],"diagnostics":[{"severity":"error","code":"legacy_bullet_marker","message":"bullet section markers must be appended to an @route token; use @foo#bar instead of #bar @foo","range":[20,24]}]}
            """.utf8)
        )
        XCTAssertEqual(response.mode, "task")
        XCTAssertNil(response.route)
        XCTAssertTrue(response.needs.isEmpty)
        XCTAssertTrue(response.spans.isEmpty)
        XCTAssertEqual(response.diagnostics.map(\.code), ["legacy_bullet_marker"])
    }

    func testOlderBobWithoutDropKeepsTodayCard() throws {
        let success = try decodeFixture("pomodoro-close-worked.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))
        XCTAssertTrue(presentation.taskRows.allSatisfy { $0.caption == nil })
        XCTAssertTrue(presentation.taskRows.allSatisfy { $0.outcome != .dropped })
    }

    func testLogParseSpecDecodesEntriesAndIndexSpan() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-log.json").utf8)
        )
        XCTAssertEqual(response.mode, "pomodoro_close")
        XCTAssertEqual(
            response.spans.map(\.kind),
            ["pomodoro_close", "pomodoro_close_log_index"]
        )
        let log = try XCTUnwrap(response.pomodoroClose?.log)
        XCTAssertEqual(log, [PomodoroCloseLogEntry(index: 1, text: "wired the lexer")])
    }

    func testLogParseIncompleteNeedsLogTextWithPlaceholder() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-log-incomplete.json").utf8)
        )
        XCTAssertEqual(response.mode, "incomplete")
        XCTAssertEqual(response.needs, ["pomodoro_close_log_text"])
        XCTAssertEqual(
            response.spans.map(\.kind),
            ["pomodoro_close", "interactive_placeholder"]
        )
        XCTAssertTrue(response.pomodoroClose?.log.isEmpty == true)
    }

    func testLogParseChainSplitsCloseAndStart() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-close-parse-log-chain.json").utf8)
        )
        XCTAssertEqual(response.mode, "pomodoro_close")
        XCTAssertEqual(response.items.count, 2)
        XCTAssertEqual(response.items[0].mode, "pomodoro_close")
        XCTAssertEqual(response.items[0].pomodoroClose?.log, [PomodoroCloseLogEntry(index: 1, text: "wired it")])
        XCTAssertEqual(response.items[1].mode, "pomodoro_start")
        XCTAssertEqual(response.pomodoroClose?.log, [PomodoroCloseLogEntry(index: 1, text: "wired it")])
    }

    func testLogIndexChipKeepsWikilinkSpansInEntryText() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data("""
            {"ok":true,"schema_version":1,"input":"=x 1 see [[note]]","body":"=x 1 see [[note]]","mode":"pomodoro_close","needs":[],"spans":[{"start":0,"end":2,"kind":"pomodoro_close"},{"start":3,"end":4,"kind":"pomodoro_close_log_index"},{"start":9,"end":11,"kind":"wikilink_delimiter"},{"start":11,"end":15,"kind":"wikilink_target"},{"start":15,"end":17,"kind":"wikilink_delimiter"}],"diagnostics":[],"pomodoro_close":{"raw":"=x","log":[{"index":1,"text":"see [[note]]"}]}}
            """.utf8)
        )
        XCTAssertEqual(
            response.spans.map(\.kind),
            ["pomodoro_close", "pomodoro_close_log_index", "wikilink_delimiter", "wikilink_target", "wikilink_delimiter"]
        )
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "pomodoro_close_log_index"), .pomodoroCloseLog)
        XCTAssertEqual(response.pomodoroClose?.log, [PomodoroCloseLogEntry(index: 1, text: "see [[note]]")])
    }

    func testRealBobLogCaptureDecodesTypedWorkLog() throws {
        let success = try decodeFixture("pomodoro-close-log.json")
        let summary = try XCTUnwrap(success.pomodoroClose)
        XCTAssertEqual(summary.log, [PomodoroCloseLogEntry(index: 1, text: "wired the lexer")])
        let row = try XCTUnwrap(summary.tasks.first(where: { $0.index == 1 }))
        XCTAssertEqual(row.typedWorkLog, ["*2026-09-28* — wired the lexer"])
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))
        let presented = try XCTUnwrap(presentation.taskRows.first(where: { $0.index == 1 }))
        XCTAssertEqual(presented.typedWorkLogPreviews, ["wired the lexer"])
        XCTAssertTrue(presented.workLogPreviews.contains("Designed the `=x` grammar"))
        XCTAssertFalse(presented.workLogPreviews.contains("wired the lexer"))
        XCTAssertTrue(presented.accessibilityLabel.contains("wired the lexer"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("wired the lexer"))
    }

    func testTypedEntriesRenderFirstAndUncapped() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "worked",
                    blockLink: "[[bob#^a]]",
                    ledgerLine: 6,
                    index: 1,
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "a",
                    text: "Task",
                    previousStatusSymbol: "*",
                    statusSymbol: "/",
                    statusChanged: true,
                    workLog: [
                        "*2026-09-28* — First",
                        "*2026-09-28* — Second",
                        "*2026-09-28* — Third",
                        "*2026-09-28* — Fourth",
                    ],
                    typedWorkLog: [
                        "*2026-09-28* — Third",
                        "*2026-09-28* — Fourth",
                        "*2026-09-28* — Fifth",
                    ]
                ),
            ]
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        let row = try XCTUnwrap(presentation.taskRows.first)
        XCTAssertEqual(row.typedWorkLogPreviews, ["Third", "Fourth", "Fifth"])
        XCTAssertEqual(row.workLogPreviews, ["First", "Second"])
    }

    func testOlderBobWithoutLogDecodesAsEmpty() throws {
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
              "pomodoro_close": {
                "raw": "=x",
                "pomodoro_line": 5,
                "tasks": [
                  {"role": "worked", "block_link": "[[bob#^a]]", "work_log": ["*2026-09-28* — Old"]}
                ]
              }
            }
            """#
        )
        let summary = try XCTUnwrap(success.pomodoroClose)
        XCTAssertTrue(summary.log.isEmpty)
        XCTAssertTrue(summary.tasks.first?.typedWorkLog.isEmpty == true)
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))
        XCTAssertTrue(presentation.taskRows.first?.typedWorkLogPreviews.isEmpty == true)
        XCTAssertEqual(presentation.taskRows.first?.workLogPreviews, ["Old"])
    }

    func testPendingLogTextTeachesEscape() throws {
        XCTAssertEqual(
            CapturePomodoroClosePresentation.pendingLogText(index: 3),
            "Type the Work Log entry for task 3 — or write \\3 to keep the number"
        )
    }

    func testHintTokensIncludeLogExample() throws {
        let tokens = CapturePomodoroClosePresentation.hintTokens(numberedRows: 2)
        XCTAssertTrue(tokens.contains { $0.text == "1" && $0.category == .pomodoroCloseLog })
        XCTAssertTrue(tokens.map(\.text).joined().contains("wrote the tests logs work to 1"))
    }

    func testDuplicateTypedAndHandwrittenEntriesBothAppear() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "worked",
                    blockLink: "[[bob#^dup]]",
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "dup",
                    text: "Dup task",
                    workLog: [
                        "*2026-09-28* — Same",
                        "*2026-09-28* — Same",
                    ],
                    typedWorkLog: [
                        "*2026-09-28* — Same",
                    ]
                ),
            ]
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        let row = try XCTUnwrap(presentation.taskRows.first)
        XCTAssertEqual(row.typedWorkLogPreviews, ["Same"])
        XCTAssertEqual(row.workLogPreviews, ["Same"])
    }

    func testRepeatedTypedEntriesSubtractByOccurrenceCount() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "worked",
                    blockLink: "[[bob#^dup]]",
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "dup",
                    text: "Dup task",
                    workLog: [
                        "*2026-09-28* — Same",
                        "*2026-09-28* — Same",
                        "*2026-09-28* — Same",
                    ],
                    typedWorkLog: [
                        "*2026-09-28* — Same",
                        "*2026-09-28* — Same",
                    ]
                ),
            ]
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        let row = try XCTUnwrap(presentation.taskRows.first)
        XCTAssertEqual(row.typedWorkLogPreviews, ["Same", "Same"])
        XCTAssertEqual(row.workLogPreviews, ["Same"])
    }

    func testStrippedFallbackConsumesOneEntryPerTypedEntry() throws {
        let summary = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "worked",
                    blockLink: "[[bob#^dup]]",
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "dup",
                    text: "Dup task",
                    workLog: [
                        "*2026-09-28* — Same",
                        "*2026-09-28* — Same",
                    ],
                    typedWorkLog: ["Same"]
                ),
            ]
        )
        let presentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: summary))
        )
        let row = try XCTUnwrap(presentation.taskRows.first)
        XCTAssertEqual(row.typedWorkLogPreviews, ["Same"])
        XCTAssertEqual(row.workLogPreviews, ["Same"])

        let unmatched = PomodoroCloseSummary(
            raw: "=x",
            pomodoroLine: 5,
            pomodoroName: "CAPTURE",
            tasks: [
                PomodoroCloseTask(
                    role: "worked",
                    blockLink: "[[bob#^plain]]",
                    resolved: true,
                    relativeTarget: "bob.md",
                    blockID: "plain",
                    text: "Plain task",
                    workLog: ["*2026-09-28* — Same"],
                    typedWorkLog: ["*2026-09-28* — Other"]
                ),
            ]
        )
        let unmatchedPresentation = try XCTUnwrap(
            CapturePomodoroClosePresentation(capture: closeCapture(summary: unmatched))
        )
        let unmatchedRow = try XCTUnwrap(unmatchedPresentation.taskRows.first)
        XCTAssertEqual(unmatchedRow.typedWorkLogPreviews, ["Other"])
        XCTAssertEqual(unmatchedRow.workLogPreviews, ["Same"])
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
