import XCTest

@testable import CaptureCore

final class CapturePomodoroStartPresentationTests: XCTestCase {
    func testInitReturnsNilWithoutStartSummary() throws {
        let success = try decodeCaptureSuccess(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/tmp/bob/cash.md","text":"Call bank",
             "task_line":"- [ ] #task Call bank [created::2026-08-14]","kind":"task",
             "created":"2026-08-14","scheduled":null,"placement":"inserted"}
            """
        )

        XCTAssertNil(CapturePomodoroStartPresentation(capture: success))
    }

    func testDryRunPreviewUsesWouldStartWithExistingEntry() throws {
        let success = try decodeCaptureSuccess(startJSON(dryRun: true, created: false, name: nil))

        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))

        XCTAssertEqual(presentation.pomodoroName, "next session")
        XCTAssertEqual(presentation.sessionText, "0930-0945 (15m)")
        XCTAssertEqual(presentation.destinationText, "sase.md · line 12")
        XCTAssertEqual(
            presentation.statusText,
            "Would start next session 0930-0945 (15m) at line 12"
        )
        XCTAssertTrue(presentation.accessibilitySummary.contains("uses existing entry"))
        XCTAssertEqual(presentation.notificationDetail, presentation.statusText)
    }

    func testNamedCreatedEntryReportsCreatedState() throws {
        let success = try decodeCaptureSuccess(startJSON(dryRun: true, created: true, name: "deep"))

        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))

        XCTAssertEqual(presentation.pomodoroName, "deep")
        XCTAssertEqual(presentation.sessionText, "0930-0955 (25m)")
        XCTAssertEqual(presentation.destinationText, "sase.md · line 14")
        XCTAssertEqual(
            presentation.statusText,
            "Would start deep 0930-0955 (25m) (created) at line 14"
        )
        XCTAssertTrue(presentation.accessibilitySummary.contains("created new entry"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("0930 to 0955"))
    }

    func testCommittedCaptureUsesStartedVerb() throws {
        let success = try decodeCaptureSuccess(startJSON(dryRun: false, created: false, name: "deep"))

        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))

        XCTAssertFalse(presentation.isDryRun)
        XCTAssertTrue(presentation.statusText.hasPrefix("Started deep 0930-0955 (25m)"))
    }

    func testSessionStartGateRequiresWholeItemKind() throws {
        let session = try decodeCaptureSuccess(
            sessionStartJSON(dryRun: true, name: "CAPTURE", tasks: "[]")
        )
        XCTAssertTrue(CapturePomodoroStartPresentation.isSessionStart(session))

        let linkStart = try decodeCaptureSuccess(startJSON(dryRun: true, created: false, name: "deep"))
        XCTAssertFalse(CapturePomodoroStartPresentation.isSessionStart(linkStart))

        let plain = try decodeCaptureSuccess(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/tmp/bob/cash.md","text":"Call bank",
             "task_line":"- [ ] #task Call bank [created::2026-08-14]","kind":"task",
             "created":"2026-08-14","scheduled":null,"placement":"inserted"}
            """
        )
        XCTAssertFalse(CapturePomodoroStartPresentation.isSessionStart(plain))
    }

    func testSessionStartCardTitleAndFooterAction() throws {
        let preview = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: true, name: "CAPTURE", tasks: "[]")
                )
            )
        )
        XCTAssertEqual(preview.title, "Start CAPTURE")
        XCTAssertEqual(preview.primaryActionTitle, "Start")

        let committed = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: false, name: "CAPTURE", tasks: "[]")
                )
            )
        )
        XCTAssertEqual(committed.title, "Started CAPTURE")
    }

    func testUnnamedEmptyStartReadsNextSessionAndNothingQueued() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: true, name: nil, tasks: "[]")
                )
            )
        )

        XCTAssertEqual(presentation.pomodoroName, "next session")
        XCTAssertEqual(presentation.title, "Start next session")
        XCTAssertEqual(
            presentation.statusText,
            "Would start next session 0945-1010 (25m) at line 4"
        )
        XCTAssertEqual(presentation.destinationText, "2026/20260928.md · line 4")
        XCTAssertTrue(presentation.taskRows.isEmpty)
        XCTAssertEqual(presentation.emptyText, "Nothing queued")
        XCTAssertEqual(presentation.notificationBody, "0945-1010 (25m) · Nothing queued")
        XCTAssertTrue(presentation.accessibilitySummary.contains("nothing queued"))
    }

    func testQueuedTaskRowsMapStatusGlyphsAndLocators() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: true, name: "CAPTURE", tasks: "[\(queuedTasksJSON)]")
                )
            )
        )

        XCTAssertEqual(presentation.taskRows.map(\.glyph), [.inProgress, .ready, .other, .unresolved])
        XCTAssertEqual(
            presentation.taskRows.map(\.taskText),
            [
                "Stop capture from the panel",
                "Plain ready task",
                "Blocked follow-up",
                "[[bob#^gone]]",
            ]
        )
        XCTAssertEqual(
            presentation.taskRows.map(\.locatorText),
            ["bob ^capture-stop", "bob ^ready", "bob ^blocked", "bob ^gone"]
        )
        XCTAssertEqual(presentation.visibleTaskRows.count, 4)
        XCTAssertEqual(presentation.overflowTaskCount, 0)
        XCTAssertEqual(
            presentation.taskRows.last?.warning,
            "bob.md has no task with block ID ^gone"
        )
        XCTAssertEqual(
            presentation.notificationBody,
            "0945-1010 (25m) · 4 queued tasks"
        )
        XCTAssertEqual(presentation.batchSuffix, " (started CAPTURE 0945-1010)")
        XCTAssertEqual(presentation.notificationTitle, "Started CAPTURE")
    }

    func testSingleQueuedTaskUsesSingularNotificationBody() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: false, name: "CAPTURE", tasks: "[\(readyTaskJSON)]")
                )
            )
        )

        XCTAssertEqual(presentation.notificationBody, "0945-1010 (25m) · 1 queued task")
    }

    func testTaskRowOverflowCountsBeyondCloseCardCap() throws {
        let rows = (0..<8).map { index in
            """
            {"block_link":"[[bob#^task-\(index)]]","embedded":false,"ledger_line":\(5 + index),
             "resolved":true,"relative_target":"bob.md","block_id":"task-\(index)",
             "text":"Task \(index)","status_symbol":" ","status_name":"Ready","warning":null}
            """
        }.joined(separator: ",")
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: true, name: "CAPTURE", tasks: "[\(rows)]")
                )
            )
        )

        XCTAssertEqual(presentation.taskRows.count, 8)
        XCTAssertEqual(
            presentation.visibleTaskRows.count,
            CapturePomodoroClosePresentation.maxVisibleTaskRows
        )
        XCTAssertEqual(
            presentation.overflowTaskCount,
            8 - CapturePomodoroClosePresentation.maxVisibleTaskRows
        )
    }

    func testLinkStartWithoutTasksKeepsEmptyLineup() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    startJSON(dryRun: true, created: false, name: "deep")
                )
            )
        )

        XCTAssertTrue(presentation.taskRows.isEmpty)
        XCTAssertEqual(presentation.notificationTitle, "Started deep")
    }

    private var readyTaskJSON: String {
        """
        {"block_link":"[[bob#^ready]]","embedded":false,"ledger_line":6,
         "resolved":true,"relative_target":"bob.md","block_id":"ready",
         "text":"Plain ready task","status_symbol":" ","status_name":"Ready","warning":null}
        """
    }

    private var queuedTasksJSON: String {
        """
        {"block_link":"[[bob#^capture-stop]]","embedded":false,"ledger_line":5,
         "resolved":true,"relative_target":"bob.md","block_id":"capture-stop",
         "text":"Stop capture from the panel","status_symbol":"/","status_name":"In Progress",
         "warning":null},
        \(readyTaskJSON),
        {"block_link":"[[bob#^blocked]]","embedded":false,"ledger_line":7,
         "resolved":true,"relative_target":"bob.md","block_id":"blocked",
         "text":"Blocked follow-up","status_symbol":"?","status_name":"Blocked","warning":null},
        {"block_link":"[[bob#^gone]]","embedded":false,"ledger_line":8,
         "resolved":false,"relative_target":"bob.md","block_id":"gone",
         "text":null,"status_symbol":null,"status_name":null,
         "warning":"bob.md has no task with block ID ^gone"}
        """
    }

    func testEveryStartFixtureDecodes() throws {
        for name in [
            "pomodoro-start-next.json",
            "pomodoro-start-timed.json",
            "pomodoro-start-empty.json",
            "pomodoro-start-switch.json",
            "pomodoro-start-named-existing.json",
            "pomodoro-start-named-created.json",
            "pomodoro-start-named-again.json",
            "pomodoro-start-drop.json",
            "pomodoro-start-drop-empty.json",
            "pomodoro-start-drop-named.json",
            "pomodoro-start-override-restart.json",
            "pomodoro-start-override-swap-kept.json",
            "pomodoro-start-override-swap-fresh-created.json",
            "pomodoro-start-override-idle.json",
        ] {
            let success = try decodeFixture(name)
            XCTAssertNotNil(
                success.pomodoroStart
                    ?? success.captures.first(where: { $0.pomodoroStart != nil })?.pomodoroStart,
                name
            )
        }
        for name in [
            "pomodoro-start-running.json",
            "pomodoro-start-none.json",
            "pomodoro-start-named-still-running.json",
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
        for name in [
            "pomodoro-start-parse.json",
            "pomodoro-start-parse-counted.json",
            "pomodoro-start-parse-near-miss.json",
            "pomodoro-start-drop-parse.json",
            "pomodoro-start-drop-parse-named.json",
        ] {
            let response = try JSONDecoder().decode(
                CaptureParseResponse.self,
                from: Data(fixtureText(name).utf8)
            )
            XCTAssertEqual(response.mode, "pomodoro_start", name)
        }
        for name in [
            "pomodoro-start-named-parse.json",
            "pomodoro-start-named-parse-query.json",
            "pomodoro-start-named-parse-existing.json",
            "pomodoro-start-named-parse-created.json",
            "pomodoro-start-named-parse-again.json",
        ] {
            let response = try JSONDecoder().decode(
                CaptureParseResponse.self,
                from: Data(fixtureText(name).utf8)
            )
            XCTAssertEqual(response.mode, "pomodoro_start", name)
        }
        for name in [
            "pomodoro-start-named-parse-chain.json",
            "pomodoro-start-named-parse-chain-query.json",
        ] {
            let response = try JSONDecoder().decode(
                CaptureParseResponse.self,
                from: Data(fixtureText(name).utf8)
            )
            XCTAssertEqual(response.items.last?.mode, "pomodoro_start", name)
        }
        for name in [
            "pomodoro-start-named-parse-incomplete.json",
            "pomodoro-start-named-parse-counted.json",
        ] {
            let response = try JSONDecoder().decode(
                CaptureParseResponse.self,
                from: Data(fixtureText(name).utf8)
            )
            XCTAssertEqual(response.mode, "incomplete", name)
            XCTAssertEqual(response.needs, ["pomodoro_name"], name)
            XCTAssertNotNil(response.pomodoroStart, name)
        }
        do {
            let response = try JSONDecoder().decode(
                CaptureParseResponse.self,
                from: Data(fixtureText("pomodoro-start-named-parse-near-miss.json").utf8)
            )
            XCTAssertEqual(response.mode, "pomodoro_start")
            XCTAssertEqual(response.diagnostics.first?.code, "invalid_pomodoro_start")
        }
    }

    func testNamedIncompleteFixtureParsesNameSpans() throws {
        let response = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-start-named-parse.json").utf8)
        )
        XCTAssertEqual(response.body, "=3#bugs")
        XCTAssertEqual(response.section, "bugs")
        XCTAssertEqual(response.spans.map(\.kind), ["pomodoro_start", "pomodoro_name"])
    }

    func testCreatedDryRunShowsNewBadgeAndNewSessionBody() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(capture: decodeFixture("pomodoro-start-named-created.json"))
        )

        XCTAssertTrue(presentation.createdPomodoro)
        XCTAssertEqual(presentation.createdBadgeText, "New")
        XCTAssertEqual(presentation.notificationBody, "0905–0930 (25m) · New session")
        XCTAssertTrue(presentation.accessibilitySummary.contains("new session"))
        XCTAssertNil(presentation.teachingHint)
    }

    func testCreatedCommitShowsCreatedBadge() throws {
        let summary = try XCTUnwrap(decodeFixture("pomodoro-start-named-created.json").pomodoroStart)
        let committed = CapturePomodoroStartPresentation(
            summary: summary,
            dryRun: false,
            relativeTarget: "2026/20260710.md",
            captureText: "=#review"
        )
        XCTAssertEqual(committed.createdBadgeText, "Created")
        XCTAssertEqual(committed.notificationBody, "0905–0930 (25m) · New session")
        XCTAssertTrue(committed.accessibilitySummary.contains("new session"))
        XCTAssertNil(committed.teachingHint)
    }

    func testExistingNamedStartTeachesDropOnly() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(capture: decodeFixture("pomodoro-start-named-existing.json"))
        )

        XCTAssertFalse(presentation.createdPomodoro)
        XCTAssertNil(presentation.createdBadgeText)
        let hint = try XCTUnwrap(presentation.teachingHint)
        XCTAssertEqual(hint.text, "Type ~2 to drop task 2")
        XCTAssertTrue(
            hint.tokens.contains { $0.text == "~2" && $0.category == .pomodoroStartDrop }
        )
        XCTAssertEqual(presentation.notificationBody, "0905-0930 (25m) · 2 queued tasks")
        XCTAssertFalse(presentation.accessibilitySummary.contains("new session"))
    }

    func testBareStartTeachesDropAndHashNameAndJoinsAccessibilitySummary() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(capture: decodeFixture("pomodoro-start-next.json"))
        )

        let hint = try XCTUnwrap(presentation.teachingHint)
        XCTAssertEqual(hint.text, "Type ~2 to drop task 2 · #name to start a specific Pomodoro")
        XCTAssertTrue(
            hint.tokens.contains { $0.text == "~2" && $0.category == .pomodoroStartDrop }
        )
        XCTAssertTrue(
            hint.tokens.contains { $0.text == "#name" && $0.category == .section }
        )
        XCTAssertTrue(
            presentation.accessibilitySummary.contains(
                "Type ~2 to drop task 2 · #name to start a specific Pomodoro"
            )
        )
    }

    func testStillRunningFixtureTeachesOneLineSwitch() throws {
        let raw = try fixtureText("pomodoro-start-named-still-running.json")
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(raw.utf8)
        )
        guard case .failure(let failure) = response else {
            return XCTFail("expected failed Bob response")
        }
        XCTAssertTrue(failure.error.contains("is still running"), failure.error)
        XCTAssertTrue(failure.error.contains("=x =#deep-work"), failure.error)
    }

    func testDropFixtureMergesKeptAndDroppedInLineupOrder() throws {
        let success = try decodeFixture("pomodoro-start-drop.json")
        let summary = try XCTUnwrap(success.pomodoroStart)
        XCTAssertEqual(summary.drop, [2])
        XCTAssertEqual(summary.dropped.map(\.index), [2] as [Int?])
        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))

        XCTAssertEqual(presentation.taskRows.map(\.index), [1, 2, 3] as [Int?])
        XCTAssertEqual(presentation.taskRows.map(\.isDropped), [false, true, false])
        XCTAssertEqual(presentation.taskRows.map(\.glyph), [.next, .dropped, .next])
        XCTAssertEqual(
            presentation.taskRows.map(\.badgeSymbolName),
            ["1.circle", "2.circle.fill", "3.circle"] as [String?]
        )
        XCTAssertEqual(presentation.taskRows.map(\.isDimmed), [false, true, false])
        XCTAssertEqual(presentation.taskRows.map(\.isStruck), [false, true, false])
        XCTAssertNil(presentation.taskRows[0].caption)
        XCTAssertEqual(presentation.taskRows[1].caption, "stays Next · with 1 nested line")
        XCTAssertNil(presentation.taskRows[2].caption)
        XCTAssertNil(presentation.teachingHint)
        XCTAssertEqual(presentation.dropSummary, "Dropped 2")
        XCTAssertEqual(
            presentation.statusText,
            "Would start CAPTURE 0945-1010 (25m) at line 5 · drops 2"
        )
        XCTAssertEqual(
            presentation.notificationBody,
            "0945-1010 (25m) · 2 queued tasks · dropped 2"
        )
        XCTAssertTrue(
            presentation.accessibilitySummary.contains("Task 1, Stop capture from the panel, queued")
        )
        XCTAssertTrue(
            presentation.accessibilitySummary.contains(
                "Task 2, Capture support for web URLs #now, drops from today"
            )
        )
        XCTAssertTrue(
            presentation.accessibilitySummary.contains("Task 3, Restart axe, queued")
        )
        XCTAssertTrue(presentation.accessibilitySummary.contains("Dropped 2"))
    }

    func testCommittedDropReadsDroppedVerb() throws {
        let summary = try XCTUnwrap(decodeFixture("pomodoro-start-drop.json").pomodoroStart)
        let committed = CapturePomodoroStartPresentation(
            summary: summary,
            dryRun: false,
            relativeTarget: "2026/20260930.md",
            captureText: "=~2"
        )
        XCTAssertEqual(
            committed.statusText,
            "Started CAPTURE 0945-1010 (25m) at line 5 · dropped 2"
        )
        XCTAssertEqual(
            committed.notificationBody,
            "0945-1010 (25m) · 2 queued tasks · dropped 2"
        )
        XCTAssertEqual(committed.dropSummary, "Dropped 2")
    }

    func testDropAllFixtureSummarizesNothingLeftQueued() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(capture: decodeFixture("pomodoro-start-drop-empty.json"))
        )

        XCTAssertTrue(presentation.taskRows.allSatisfy(\.isDropped))
        XCTAssertEqual(presentation.taskRows.map(\.index), [1, 2, 3] as [Int?])
        XCTAssertEqual(presentation.dropSummary, "Dropped 1, 2, 3 · nothing left queued")
        XCTAssertEqual(presentation.emptyText, "Nothing queued")
        XCTAssertEqual(
            presentation.notificationBody,
            "0945-1010 (25m) · Nothing queued · dropped 1, 2, 3"
        )
        XCTAssertTrue(presentation.statusText.contains("· drops 1, 2, 3"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("nothing queued"))
    }

    func testNamedDropFixtureShowsSummaryWithoutHint() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(capture: decodeFixture("pomodoro-start-drop-named.json"))
        )

        XCTAssertNil(presentation.teachingHint)
        XCTAssertEqual(presentation.dropSummary, "Dropped 2")
        XCTAssertEqual(
            presentation.notificationBody,
            "0945-1010 (25m) · 2 queued tasks · dropped 2"
        )
    }

    func testSingleRowHintDropsIt() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: true, name: "CAPTURE", tasks: "[\(readyTaskJSON)]")
                )
            )
        )

        XCTAssertEqual(
            presentation.teachingHint?.text,
            "Type ~1 to drop it · #name to start a specific Pomodoro"
        )
    }

    func testBareEmptyStartKeepsNameHint() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(capture: decodeFixture("pomodoro-start-empty.json"))
        )

        XCTAssertEqual(
            presentation.teachingHint?.text,
            "Type #name to start a specific Pomodoro"
        )
        XCTAssertNil(presentation.dropSummary)
    }

    func testUnnumberedRowsRenderWithoutBadges() throws {
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: true, name: "CAPTURE", tasks: "[\(queuedTasksJSON)]")
                )
            )
        )

        XCTAssertTrue(presentation.taskRows.allSatisfy { $0.index == nil })
        XCTAssertTrue(presentation.taskRows.allSatisfy { $0.badgeSymbolName == nil })
        XCTAssertTrue(presentation.taskRows.allSatisfy { !$0.usesNumericBadgeFallback })
        XCTAssertTrue(presentation.taskRows.allSatisfy { !$0.isDimmed })
        XCTAssertTrue(presentation.taskRows.allSatisfy { !$0.isStruck })
        XCTAssertTrue(presentation.taskRows.allSatisfy { $0.caption == nil })
        XCTAssertEqual(presentation.visibleTaskRows.count, 4)
        XCTAssertEqual(presentation.overflowTaskCount, 0)
    }

    func testNumberedRowsNeverHideUnderMore() throws {
        func numberedTask(_ index: Int) -> String {
            """
            {"block_link":"[[bob#^task-\(index)]]","embedded":false,"ledger_line":\(4 + index),
             "index":\(index),"resolved":true,"relative_target":"bob.md","block_id":"task-\(index)",
             "text":"Task \(index)","status_symbol":" ","status_name":"Ready","warning":null}
            """
        }
        let numbered = (1...8).map(numberedTask).joined(separator: ",")
        let allNumbered = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: true, name: "CAPTURE", tasks: "[\(numbered)]")
                )
            )
        )
        XCTAssertEqual(allNumbered.visibleTaskRows.count, 8)
        XCTAssertEqual(allNumbered.overflowTaskCount, 0)

        let sixNumbered = (1...6).map(numberedTask).joined(separator: ",")
        let twoUnnumbered = (9...10).map { index in
            """
            {"block_link":"[[bob#^task-\(index)]]","embedded":false,"ledger_line":\(4 + index),
             "resolved":true,"relative_target":"bob.md","block_id":"task-\(index)",
             "text":"Task \(index)","status_symbol":" ","status_name":"Ready","warning":null}
            """
        }.joined(separator: ",")
        let mixed = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(
                        dryRun: true,
                        name: "CAPTURE",
                        tasks: "[\(sixNumbered),\(twoUnnumbered)]"
                    )
                )
            )
        )
        // Six numbered rows always show; the two unnumbered rows hide once
        // they exceed the `6 − numbered` allowance (here zero).
        XCTAssertEqual(mixed.visibleTaskRows.count, 6)
        XCTAssertEqual(mixed.overflowTaskCount, 2)
    }

    func testBadgeFallsBackToCapsuleAboveFifty() throws {
        let row = """
        {"block_link":"[[bob#^big]]","embedded":false,"ledger_line":60,
         "index":51,"resolved":true,"relative_target":"bob.md","block_id":"big",
         "text":"Big","status_symbol":" ","status_name":"Ready","warning":null}
        """
        let presentation = try XCTUnwrap(
            CapturePomodoroStartPresentation(
                capture: decodeCaptureSuccess(
                    sessionStartJSON(dryRun: true, name: "CAPTURE", tasks: "[\(row)]")
                )
            )
        )
        XCTAssertNil(presentation.taskRows.first?.badgeSymbolName)
        XCTAssertTrue(presentation.taskRows.first?.usesNumericBadgeFallback == true)
    }

    func testDropParseFixturesDecodeModesSpansAndNeeds() throws {
        let valid = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-start-drop-parse.json").utf8)
        )
        XCTAssertEqual(valid.mode, "pomodoro_start")
        XCTAssertEqual(valid.spans.map(\.kind), ["pomodoro_start", "pomodoro_start_drop"])
        XCTAssertEqual(valid.pomodoroStart?.drop, [2])
        XCTAssertTrue(valid.diagnostics.isEmpty)

        let named = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-start-drop-parse-named.json").utf8)
        )
        XCTAssertEqual(named.mode, "pomodoro_start")
        XCTAssertEqual(named.section, "bugs")
        XCTAssertEqual(named.pomodoroStart?.drop, [1])
        XCTAssertTrue(named.spans.map(\.kind).contains("pomodoro_start_drop"))

        for name in [
            "pomodoro-start-drop-parse-incomplete.json",
            "pomodoro-start-drop-parse-incomplete-comma.json",
        ] {
            let response = try JSONDecoder().decode(
                CaptureParseResponse.self,
                from: Data(fixtureText(name).utf8)
            )
            XCTAssertEqual(response.mode, "incomplete", name)
            XCTAssertEqual(response.needs, ["pomodoro_start_task"], name)
            XCTAssertTrue(
                response.spans.map(\.kind).contains("interactive_placeholder"),
                name
            )
        }

        let invalid = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-start-drop-parse-invalid.json").utf8)
        )
        XCTAssertEqual(invalid.mode, "pomodoro_start")
        XCTAssertEqual(invalid.diagnostics.first?.code, "invalid_pomodoro_start")

        let chain = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-start-drop-parse-chain.json").utf8)
        )
        XCTAssertEqual(chain.items.map(\.mode), ["pomodoro_close", "pomodoro_start"])
        XCTAssertEqual(chain.items.last?.pomodoroStart?.drop, [2])
    }

    func testOverrideRestartFixtureRewordsCardFooterAndNotification() throws {
        let success = try decodeFixture("pomodoro-start-override-restart.json")
        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertTrue(CapturePomodoroStartPresentation.isSessionStart(success))
        XCTAssertEqual(presentation.variant, .restart)
        XCTAssertEqual(presentation.title, "Restart CAPTURE")
        XCTAssertEqual(
            presentation.statusText,
            "Would restart CAPTURE 0920-0945 → 0935-1000 (25m) at line 5"
        )
        XCTAssertEqual(presentation.restartWasText, "was 0920–0945")
        XCTAssertNil(presentation.demotedText)
        XCTAssertFalse(presentation.takesOverLedger)
        XCTAssertNil(presentation.takesOverBadgeText)
        XCTAssertNil(presentation.idleCaption)
        XCTAssertEqual(presentation.primaryActionTitle, "Restart")
        XCTAssertEqual(presentation.notificationTitle, "Restarted CAPTURE")
        XCTAssertEqual(presentation.notificationBody, "0935–1000 (25m) · 2 queued")
        XCTAssertEqual(presentation.batchSuffix, " (restarted CAPTURE 0935-1000)")
    }

    func testOverrideRestartCommitUsesRestartedVerb() throws {
        let summary = try XCTUnwrap(decodeFixture("pomodoro-start-override-restart.json").pomodoroStart)
        let committed = CapturePomodoroStartPresentation(
            summary: summary,
            dryRun: false,
            relativeTarget: "2026/20261009.md",
            captureText: "=="
        )

        XCTAssertEqual(committed.variant, .restart)
        XCTAssertEqual(committed.title, "Restarted CAPTURE")
        XCTAssertEqual(
            committed.statusText,
            "Restarted CAPTURE 0920-0945 → 0935-1000 (25m) at line 5"
        )
        XCTAssertEqual(committed.primaryActionTitle, "Restart")
    }

    func testOverrideSwapKeptFixtureTakesOverLedger() throws {
        let success = try decodeFixture("pomodoro-start-override-swap-kept.json")
        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))

        XCTAssertEqual(presentation.variant, .swap)
        XCTAssertTrue(presentation.takesOverLedger)
        XCTAssertEqual(presentation.takesOverBadgeText, "Takes over")
        XCTAssertEqual(presentation.title, "Swap in BUGS")
        XCTAssertEqual(
            presentation.statusText,
            "Would swap in BUGS 0920-0945 (takes over CAPTURE) at line 5"
        )
        XCTAssertEqual(presentation.demotedText, "CAPTURE → first future · keeps 2 Task Links")
        XCTAssertNil(presentation.restartWasText)
        XCTAssertNil(presentation.idleCaption)
        XCTAssertEqual(presentation.primaryActionTitle, "Swap")
        XCTAssertEqual(presentation.notificationTitle, "Swapped in BUGS")
        XCTAssertEqual(presentation.notificationBody, "0920–0945 · CAPTURE back to first future")
        XCTAssertEqual(presentation.batchSuffix, " (swapped in BUGS 0920-0945)")
    }

    func testOverrideSwapFreshCreatedFixtureShowsNewBadge() throws {
        let success = try decodeFixture("pomodoro-start-override-swap-fresh-created.json")
        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))

        XCTAssertEqual(presentation.variant, .swap)
        XCTAssertFalse(presentation.takesOverLedger)
        XCTAssertNil(presentation.takesOverBadgeText)
        XCTAssertEqual(presentation.createdBadgeText, "New")
        XCTAssertEqual(presentation.title, "Swap in PLAN")
        XCTAssertEqual(
            presentation.statusText,
            "Would swap in PLAN 0935-0950 (15m) (created) at line 5"
        )
        XCTAssertEqual(presentation.demotedText, "CAPTURE → first future · keeps 2 Task Links")
        XCTAssertEqual(presentation.notificationTitle, "Swapped in PLAN")
        XCTAssertEqual(presentation.notificationBody, "0935–0950 · CAPTURE back to first future")
        XCTAssertEqual(presentation.batchSuffix, " (swapped in PLAN 0935-0950)")
        XCTAssertEqual(presentation.primaryActionTitle, "Swap")
    }

    func testOverrideIdleFixtureStartsLikePlainStartWithCaption() throws {
        let success = try decodeFixture("pomodoro-start-override-idle.json")
        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))

        XCTAssertEqual(presentation.variant, .idleStart)
        XCTAssertEqual(presentation.title, "Start BUGS")
        XCTAssertEqual(
            presentation.statusText,
            "Would start BUGS 0935-1000 (25m) at line 3"
        )
        XCTAssertEqual(presentation.idleCaption, "Nothing was running — starts like =")
        XCTAssertNil(presentation.restartWasText)
        XCTAssertNil(presentation.demotedText)
        XCTAssertEqual(presentation.primaryActionTitle, "Start")
        XCTAssertEqual(presentation.notificationTitle, "Started BUGS")
        XCTAssertEqual(presentation.notificationBody, "0935-1000 (25m) · Nothing queued")
        XCTAssertTrue(
            presentation.accessibilitySummary.contains("Nothing was running — starts like =")
        )
    }

    func testOlderBobWithoutOverrideDecodesAsPlainStart() throws {
        let success = try decodeCaptureSuccess(sessionStartJSON(dryRun: true, name: "CAPTURE", tasks: "[]"))
        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))

        XCTAssertNil(success.pomodoroStart?.overrideOutcome)
        XCTAssertEqual(presentation.variant, .start)
        XCTAssertFalse(presentation.takesOverLedger)
        XCTAssertNil(presentation.takesOverBadgeText)
        XCTAssertNil(presentation.idleCaption)
        XCTAssertNil(presentation.restartWasText)
        XCTAssertNil(presentation.demotedText)
        XCTAssertEqual(presentation.title, "Start CAPTURE")
        XCTAssertEqual(presentation.primaryActionTitle, "Start")
    }

    func testUnknownOverrideActionDecodesAsPlainStart() throws {
        let success = try decodeCaptureSuccess(
            """
            {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"",
             "relative_target":"2026/20261009.md","target":"/tmp/bob/2026/20261009.md",
             "text":"==","task_line":"- [ ] (**0935-1000** [t:: 25m]) — CAPTURE",
             "kind":"pomodoro_start","created":"2026-10-09","scheduled":null,
             "placement":"started",
             "pomodoro_start":{"start":"0935","end":"1000","duration_minutes":25,
              "offset_units":0,"pomodoro_name":"CAPTURE","pomodoro_line":5,
              "created_pomodoro":false,"time_range":"(**0935-1000** [t:: 25m])",
              "tasks":[],
              "override":{"action":"teleport","ledger":"fresh"}}}
            """
        )

        XCTAssertNil(success.pomodoroStart?.overrideOutcome)
        let presentation = try XCTUnwrap(CapturePomodoroStartPresentation(capture: success))
        XCTAssertEqual(presentation.variant, .start)
        XCTAssertEqual(presentation.title, "Start CAPTURE")
    }

    func testOverrideParseFixturesCarrySpecFlag() throws {
        let swap = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-start-override-parse.json").utf8)
        )
        XCTAssertEqual(swap.mode, "pomodoro_start")
        XCTAssertEqual(swap.pomodoroStart?.isOverride, true)

        let restart = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-start-override-parse-restart.json").utf8)
        )
        XCTAssertEqual(restart.mode, "pomodoro_start")
        XCTAssertEqual(restart.pomodoroStart?.isOverride, true)

        let incomplete = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(fixtureText("pomodoro-start-override-parse-incomplete.json").utf8)
        )
        XCTAssertEqual(incomplete.mode, "incomplete")
        XCTAssertEqual(incomplete.needs, ["pomodoro_name"])
        XCTAssertEqual(incomplete.pomodoroStart?.isOverride, true)
    }

    private func sessionStartJSON(dryRun: Bool, name: String?, tasks: String) -> String {
        let nameValue = name.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "ok": true,
          "dry_run": \(dryRun ? "true" : "false"),
          "routed": false,
          "route": null,
          "route_label": "",
          "relative_target": "2026/20260928.md",
          "target": "/tmp/bob/2026/20260928.md",
          "text": "=",
          "task_line": "- [ ] (**0945-1010** [t:: 25m]) — CAPTURE",
          "kind": "pomodoro_start",
          "created": "2026-09-28",
          "scheduled": null,
          "placement": "started",
          "pomodoro_start": {
            "start": "0945",
            "end": "1010",
            "duration_minutes": 25,
            "offset_units": 0,
            "pomodoro_name": \(nameValue),
            "pomodoro_line": 4,
            "created_pomodoro": false,
            "time_range": "(**0945-1010** [t:: 25m])",
            "tasks": \(tasks)
          }
        }
        """
    }

    private func startJSON(dryRun: Bool, created: Bool, name: String?) -> String {
        let nameValue = name.map { "\"\($0)\"" } ?? "null"
        return """
        {
          "ok": true,
          "dry_run": \(dryRun ? "true" : "false"),
          "routed": true,
          "route": "sase",
          "route_label": "sase.md",
          "relative_target": "sase.md",
          "target": "/tmp/bob/sase.md",
          "text": "Do work",
          "task_line": "- [*] #task Do work [created::2026-08-14] ^outline",
          "kind": "pomodoro_task",
          "created": "2026-08-14",
          "scheduled": null,
          "placement": "inserted",
          "block_id": "outline",
          "pomodoro_start": {
            "start": "0930",
            "end": "\(created ? "0955" : (name == nil ? "0945" : "0955"))",
            "duration_minutes": \(created || name != nil ? 25 : 15),
            "offset_units": \(created || name != nil ? 2 : 0),
            "pomodoro_name": \(nameValue),
            "pomodoro_line": \(created ? 14 : 12),
            "created_pomodoro": \(created ? "true" : "false"),
            "time_range": "(**0930-0955** [t:: 25m])"
          }
        }
        """
    }

    private enum CaptureFixtureError: Error {
        case expectedSuccess
    }

    private func decodeCaptureSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(json.utf8))
        guard case .success(let success) = decoded else {
            throw CaptureFixtureError.expectedSuccess
        }
        return success
    }

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(fixtureText(name).utf8)
        )
        guard case .success(let success) = response else {
            XCTFail("expected successful Bob response for \(name)")
            throw CaptureFixtureError.expectedSuccess
        }
        return success
    }

    private func fixtureText(_ name: String) throws -> String {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }
}
