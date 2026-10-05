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
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:big-task'   # task-complete-subtasks.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!travel:dep'      # task-complete-unblocked.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:fin'        # task-complete-already-done.json
//   $BOB capture -b $VAULT -f json --dry-run -- '!sase:one        # task-complete-batch.json
//     <blank line>!sase:two'
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
        XCTAssertEqual(presentation.transitionText, "[*] → [x]  #task Fix flaky gkeep test")
        XCTAssertEqual(presentation.previewText, "#task Fix flaky gkeep test")
        XCTAssertEqual(presentation.primaryActionTitle, "Complete")
        XCTAssertTrue(presentation.ledgerText?.contains("Struck its Task Link") == true)
        XCTAssertEqual(presentation.subtaskRows, [])
        XCTAssertEqual(presentation.leftOpenRows, [])
        XCTAssertEqual(presentation.unblockedRows, [])
        XCTAssertEqual(presentation.chips, [])
        XCTAssertTrue(presentation.statusText.hasPrefix("Complete → sase.md · ^fix-flaky"))
        XCTAssertEqual(presentation.notificationTitle, "Completed: #task Fix flaky gkeep test")
        XCTAssertTrue(presentation.notificationBody.contains("sase.md"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("sase.md · ^fix-flaky"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("[*] → [x]"))
    }

    func testDryRunTenseUsesWouldCompleteAndStrikes() throws {
        let success = try decodeDryRunFixture("task-complete-strike.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertEqual(presentation.headline, "Would complete")
        XCTAssertTrue(presentation.ledgerText?.contains("Strikes its Task Link") == true)
        XCTAssertTrue(presentation.statusText.hasPrefix("Would complete →"))
    }

    func testSubtasksAndLeftOpenRows() throws {
        let success = try decodeFixture("task-complete-subtasks.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

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

        let ledger = try XCTUnwrap(presentation.ledgerText)
        XCTAssertTrue(ledger.contains("SASE → CAPTURE"), ledger)
        XCTAssertTrue(ledger.contains("struck"), ledger)
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains(ledger))
    }

    func testDedupeFixtureReportsDroppedDuplicate() throws {
        let success = try decodeFixture("task-complete-dedupe.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

        let ledger = try XCTUnwrap(presentation.ledgerText)
        XCTAssertTrue(ledger.contains("dropped 1 duplicate"), ledger)
    }

    func testUnblockedRowsCarryTransitionAndLocator() throws {
        let success = try decodeFixture("task-complete-unblocked.json")
        let presentation = try XCTUnwrap(CaptureTaskCompletePresentation(capture: success))

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
        for item in success.captures {
            XCTAssertNotNil(CaptureTaskCompletePresentation(capture: item))
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
