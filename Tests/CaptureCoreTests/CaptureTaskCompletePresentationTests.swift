import XCTest

@testable import CaptureCore

// Real-bob fixtures for the whole-item `!note:block-id` completion preview.
// Generated with bob-cli master (`execute` phase) against a sandbox vault; each
// fixture stores the `--dry-run -f json` response with `dry_run` reset to
// false so fake-bob can serve either tense:
//
//   BOB=bob; VAULT=/tmp/bob-mac-capture-task-complete/vault
//   export BOB_CONFIG_FILE=/definitely/missing/bob-cli-test-config.yml
//   export BOB_WEB_CLIP_ADAPTER=/definitely/missing/bob-cli-test-web-clip-adapter
//   export BOB_DAY_FILE=$VAULT/20261005.md BOB_NOW="2026-10-05 09:30:00"
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:fix-flaky'   # task-complete-strike.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:mv1'        # task-complete-move.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:carry'      # task-complete-dedupe.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:root'       # task-complete-subtasks.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!travel:dep'      # task-complete-unblocked.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:fin'        # task-complete-already-done.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:one        # task-complete-batch.json
//     <blank line>!sase:two'
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:ptask'       # task-complete-strike-completed.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:cx'         # task-complete-refusal.json (ok:false)
final class CaptureTaskCompletePresentationTests: XCTestCase {
    func testInitReturnsNilForANonCompleteCapture() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": true,
              "route": "sase",
              "route_label": "sase.md",
              "relative_target": "sase.md",
              "target": "/tmp/bob/sase.md",
              "text": "Do work",
              "task_line": "- [ ] #task Do work ^new-id",
              "kind": "task",
              "created": "2026-10-05",
              "placement": "inserted",
              "block_id": "new-id"
            }
            """
        )

        XCTAssertNil(CaptureTaskCompletePresentation(capture: success))
    }

    func testInitReturnsNilWhenTaskCompleteObjectIsMissing() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": true,
              "route": null,
              "route_label": "sase.md",
              "relative_target": "sase.md",
              "target": "/tmp/bob/sase.md",
              "text": "",
              "task_line": "- [x] #task Done ^fin",
              "kind": "task_complete",
              "created": "2026-10-05",
              "placement": "completed",
              "block_id": "fin"
            }
            """
        )

        XCTAssertNil(CaptureTaskCompletePresentation(capture: success))
    }

    func testStrikeFixtureHeadlineTransitionAndDestination() throws {
        let success = try decodeFixture("task-complete-strike.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

        XCTAssertFalse(presentation.isDryRun)
        XCTAssertFalse(presentation.isAlreadyDone)
        XCTAssertEqual(presentation.headline, "Complete")
        XCTAssertEqual(presentation.destinationLabel, "sase.md · ^fix-flaky")
        XCTAssertEqual(presentation.transitionText, "[*] → [x]  Fix flaky gkeep test")
        XCTAssertEqual(presentation.previewText, "Fix flaky gkeep test")
        XCTAssertEqual(presentation.primaryActionTitle, "Complete")
        XCTAssertEqual(presentation.ledgerText, "Struck its Task Link in CAPTURE")
        XCTAssertEqual(presentation.subtaskRows, [])
        XCTAssertEqual(presentation.leftOpenRows, [])
        XCTAssertEqual(presentation.unblockedRows, [])
        XCTAssertEqual(presentation.chips, [])
        XCTAssertTrue(presentation.statusText.hasPrefix("Complete → sase.md · ^fix-flaky"))
        XCTAssertEqual(presentation.notificationTitle, "Completed: Fix flaky gkeep test")
        XCTAssertTrue(presentation.notificationBody.contains("sase.md"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("sase.md · ^fix-flaky"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("[*] → [x]"))
    }

    func testDryRunTenseUsesWouldCompleteAndStrikes() throws {
        let success = try decodeDryRunFixture("task-complete-strike.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertEqual(presentation.headline, "Would complete")
        XCTAssertEqual(presentation.ledgerText, "Strikes its Task Link in CAPTURE")
        XCTAssertTrue(presentation.statusText.hasPrefix("Would complete →"))
    }

    func testCleanTextFromBobFallsBackWithoutText() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": null,
              "route_label": "sase.md",
              "relative_target": "sase.md",
              "target": "/tmp/bob/sase.md",
              "text": "",
              "task_line": "- [x] #task Fix flaky gkeep test  [completion:: 2026-10-05] ^fix-flaky",
              "kind": "task_complete",
              "created": "2026-10-05",
              "placement": "completed",
              "block_id": "fix-flaky",
              "previous_task_line": "- [*] #task Fix flaky gkeep test ^fix-flaky",
              "status_symbol": "x",
              "status_name": "Done",
              "previous_status_symbol": "*",
              "previous_status_name": "Next",
              "task_complete": {
                "raw": "!sase:fix-flaky",
                "note": "sase",
                "note_path": "sase.md",
                "block_id": "fix-flaky",
                "action": "completed",
                "completion_date": "2026-10-05",
                "subtasks": [],
                "subtasks_left_open": [],
                "unblocked": []
              }
            }
            """
        )
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))
        // Without Bob's text the local parse keeps the global-filter tag.
        XCTAssertEqual(presentation.previewText, "#task Fix flaky gkeep test")
        XCTAssertEqual(presentation.transitionText, "[*] → [x]  #task Fix flaky gkeep test")
        XCTAssertEqual(presentation.notificationTitle, "Completed: #task Fix flaky gkeep test")
    }

    func testStrikeUnderCompletedEntryNamesCompleted() throws {
        let success = try decodeFixture("task-complete-strike-completed.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))
        XCTAssertEqual(presentation.ledgerText, "Struck its Task Link in PLAN (completed) · removed empty CAPTURE")
        let dry = try decodeDryRunFixture("task-complete-strike-completed.json")
        let dryPresentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: dry))
        XCTAssertEqual(dryPresentation.ledgerText, "Strikes its Task Link in PLAN (completed) · removes empty CAPTURE")
    }

    func testNamelessEntryFallsBackToLineNumber() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": null,
              "route_label": "sase.md",
              "relative_target": "sase.md",
              "target": "/tmp/bob/sase.md",
              "text": "",
              "task_line": "- [x] #task T ^t",
              "kind": "task_complete",
              "created": "2026-10-05",
              "placement": "completed",
              "block_id": "t",
              "status_symbol": "x",
              "status_name": "Done",
              "previous_status_symbol": " ",
              "previous_status_name": "Ready",
              "task_complete": {
                "raw": "!sase:t",
                "note": "sase",
                "note_path": "sase.md",
                "block_id": "t",
                "action": "completed",
                "completion_date": "2026-10-05",
                "text": "T",
                "subtasks": [],
                "subtasks_left_open": [],
                "ledger": {
                  "day_file": "20261005.md",
                  "struck": 1,
                  "struck_in": [{"line": 2, "name": "", "status": "running"}],
                  "moved": [],
                  "deduplicated": 0,
                  "dropped": [],
                  "removed_placeholders": []
                },
                "unblocked": []
              }
            }
            """
        )
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))
        XCTAssertEqual(presentation.ledgerText, "Struck its Task Link in line 2")
    }

    func testEmptyBlockIDLocatorsOmitCaret() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": null,
              "route_label": "sase.md",
              "relative_target": "sase.md",
              "target": "/tmp/bob/sase.md",
              "text": "",
              "task_line": "- [x] #task R ^r",
              "kind": "task_complete",
              "created": "2026-10-05",
              "placement": "completed",
              "block_id": "r",
              "status_symbol": "x",
              "status_name": "Done",
              "previous_status_symbol": "?",
              "previous_status_name": "Blocked",
              "task_complete": {
                "raw": "!sase:r",
                "note": "sase",
                "note_path": "sase.md",
                "block_id": "r",
                "action": "completed",
                "completion_date": "2026-10-05",
                "text": "R",
                "subtasks": [],
                "subtasks_left_open": [{
                  "note_path": "sase.md",
                  "block_id": "",
                  "line": 3,
                  "text": "No id",
                  "status_symbol": "?",
                  "status_name": "Blocked",
                  "reason": "blocked"
                }],
                "unblocked": [{
                  "note_path": "travel.md",
                  "block_id": "",
                  "line": 2,
                  "text": "Waiter",
                  "previous_status_symbol": "?",
                  "previous_status_name": "Blocked",
                  "status_symbol": " ",
                  "status_name": "Ready"
                }]
              }
            }
            """
        )
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))
        XCTAssertEqual(presentation.leftOpenRows[0].locatorText, "sase.md")
        XCTAssertEqual(presentation.unblockedRows[0].locatorText, "travel.md")
    }

    func testSubtasksAndLeftOpenRows() throws {
        let success = try decodeFixture("task-complete-subtasks.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

        XCTAssertEqual(presentation.previewText, "Blocked root")
        XCTAssertNil(presentation.ledgerText)
        XCTAssertEqual(presentation.subtaskRows.count, 1)
        XCTAssertEqual(
            presentation.subtaskRows[0].transitionText,
            "[/] → [x]  Write the regression test"
        )
        XCTAssertEqual(presentation.subtaskRows[0].locatorText, "sase.md ^write-test")
        XCTAssertEqual(presentation.leftOpenRows.count, 1)
        XCTAssertTrue(presentation.leftOpenRows[0].displayText.contains("Blocked"))
        XCTAssertTrue(presentation.leftOpenRows[0].displayText.contains("Ask infra"))
        XCTAssertEqual(presentation.leftOpenRows[0].locatorText, "sase.md ^ask-infra")
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("closes"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("Ask infra"))
    }

    func testMoveFixtureLedgerNamesSourceAndDestination() throws {
        let success = try decodeFixture("task-complete-move.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

        XCTAssertEqual(
            presentation.ledgerText,
            "Struck its Task Link in SASE · Moved its Task Link SASE → CAPTURE, struck · removed empty SASE"
        )
        let dry = try decodeDryRunFixture("task-complete-move.json")
        let dryPresentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: dry))
        XCTAssertEqual(
            dryPresentation.ledgerText,
            "Strikes its Task Link in SASE · Moves its Task Link SASE → CAPTURE, struck · removes empty SASE"
        )
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains(presentation.ledgerText ?? ""))
    }

    func testDedupeFixtureReportsDroppedDuplicate() throws {
        let success = try decodeFixture("task-complete-dedupe.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

        XCTAssertEqual(
            presentation.ledgerText,
            "Task Link already in MORNING; dropped the SASE copy · removed empty SASE"
        )
        let dry = try decodeDryRunFixture("task-complete-dedupe.json")
        let dryPresentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: dry))
        XCTAssertEqual(
            dryPresentation.ledgerText,
            "Task Link already in MORNING; drops the SASE copy · removes empty SASE"
        )
    }

    func testUnblockedRowsCarryTransitionAndLocator() throws {
        let success = try decodeFixture("task-complete-unblocked.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

        XCTAssertEqual(presentation.previewText, "Dep root")
        XCTAssertEqual(presentation.unblockedRows.count, 1)
        XCTAssertEqual(presentation.unblockedRows[0].transitionText, "[?] → [ ]  Waiter")
        XCTAssertEqual(presentation.unblockedRows[0].locatorText, "travel.md ^waiter")
        XCTAssertTrue(presentation.notificationBody.contains("unblocked Waiter"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("unblocks"))
    }

    func testAlreadyDoneReadsNothingToChange() throws {
        let success = try decodeFixture("task-complete-already-done.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

        XCTAssertTrue(presentation.isAlreadyDone)
        XCTAssertEqual(presentation.previewText, "Finished")
        XCTAssertEqual(presentation.headline, "Already done")
        XCTAssertNil(presentation.ledgerText)
        XCTAssertEqual(presentation.statusText, "Already done — nothing to change")
        XCTAssertTrue(presentation.notificationTitle.hasPrefix("Already done:"))
        XCTAssertTrue(presentation.notificationBody.contains("nothing to change"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("Already done"))
    }

    func testBatchFixtureDecodesBothItems() throws {
        let success = try decodeFixture("task-complete-batch.json")

        XCTAssertEqual(success.captures.count, 2)
        let texts = success.captures.map { $0.taskComplete?.text }
        XCTAssertEqual(texts, ["One", "Two"])
        for item in success.captures {
            let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: item))
            XCTAssertEqual(presentation.ledgerText, "Struck its Task Link in CAPTURE")
        }
    }

    func testMalformedTaskCompleteNeverFailsTheCaptureDecode() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": true,
              "route": null,
              "route_label": "sase.md",
              "relative_target": "sase.md",
              "target": "/tmp/bob/sase.md",
              "text": "",
              "task_line": "- [x] #task Done ^fin",
              "kind": "task_complete",
              "created": "2026-10-05",
              "placement": "completed",
              "block_id": "fin",
              "task_complete": {"raw": 42, "subtasks": "nope"}
            }
            """
        )

        XCTAssertEqual(success.kind, "task_complete")
        XCTAssertNil(CaptureTaskCompletePresentation(capture: success))
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
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        return try decodeCaptureSuccess(text)
    }

    private func decodeDryRunFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        var text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        text = text.replacingOccurrences(of: "\"dry_run\":false", with: "\"dry_run\":true")
        return try decodeCaptureSuccess(text)
    }
}
