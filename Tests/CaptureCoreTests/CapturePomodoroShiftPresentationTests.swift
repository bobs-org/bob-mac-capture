import XCTest

@testable import CaptureCore

final class CapturePomodoroShiftPresentationTests: XCTestCase {
    func testInitReturnsNilWithoutShiftSummary() throws {
        let success = try decodeCaptureSuccess(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/tmp/bob/cash.md","text":"Call bank",
             "task_line":"- [ ] #task Call bank [created::2026-08-14]","kind":"task",
             "created":"2026-08-14","scheduled":null,"placement":"inserted"}
            """
        )

        XCTAssertNil(CapturePomodoroShiftPresentation(capture: success))
    }

    func testDryRunPreviewUsesWouldShiftWithBeforeAfterTiming() throws {
        let success = try decodeCaptureSuccess(laterJSON(dryRun: true))

        let presentation = try XCTUnwrap(CapturePomodoroShiftPresentation(capture: success))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertEqual(presentation.pomodoroName, "FOCUS")
        XCTAssertEqual(presentation.sessionText, "0900-0925 → 0915-0940 (25m), 15m later")
        XCTAssertEqual(presentation.destinationText, "FOCUS · line 3")
        XCTAssertEqual(
            presentation.statusText,
            "Would shift FOCUS 0900-0925 to 0915-0940 (25m), 15m later at line 3"
        )
        XCTAssertEqual(presentation.symbolName, "chevron.forward.2")
        XCTAssertTrue(presentation.later)
        XCTAssertTrue(presentation.accessibilitySummary.contains("Shifts FOCUS"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("15 minutes later"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("line 3"))
        XCTAssertEqual(presentation.notificationDetail, presentation.statusText)
    }

    func testEarlierShiftUsesBackwardChevron() throws {
        let success = try decodeCaptureSuccess(earlierJSON(dryRun: true))

        let presentation = try XCTUnwrap(CapturePomodoroShiftPresentation(capture: success))

        XCTAssertFalse(presentation.later)
        XCTAssertEqual(presentation.symbolName, "chevron.backward.2")
        XCTAssertEqual(presentation.sessionText, "0900-0925 → 0850-0915 (25m), 10m earlier")
        XCTAssertEqual(
            presentation.statusText,
            "Would shift FOCUS 0900-0925 to 0850-0915 (25m), 10m earlier at line 3"
        )
    }

    func testCommittedCaptureUsesShiftedVerb() throws {
        let success = try decodeCaptureSuccess(laterJSON(dryRun: false))

        let presentation = try XCTUnwrap(CapturePomodoroShiftPresentation(capture: success))

        XCTAssertFalse(presentation.isDryRun)
        XCTAssertTrue(presentation.statusText.hasPrefix("Shifted FOCUS 0900-0925"))
    }

    func testUnnamedTargetFallsBackToCurrentSession() throws {
        let success = try decodeCaptureSuccess(unnamedJSON(dryRun: true))

        let presentation = try XCTUnwrap(CapturePomodoroShiftPresentation(capture: success))

        XCTAssertEqual(presentation.pomodoroName, "current session")
        XCTAssertTrue(presentation.statusText.contains("current session"))
        XCTAssertEqual(presentation.destinationText, "current session · line 3")
    }

    private func laterJSON(dryRun: Bool) -> String {
        """
        {
          "ok": true,
          "dry_run": \(dryRun ? "true" : "false"),
          "routed": false,
          "route": null,
          "route_label": "",
          "relative_target": "2026/20260928.md",
          "target": "/tmp/bob/2026/20260928.md",
          "text": "++3",
          "task_line": "- [ ] (**0915-0940** [t:: 25m]) — FOCUS",
          "kind": "pomodoro_shift",
          "created": "2026-09-28",
          "scheduled": null,
          "placement": "toggled",
          "pomodoro_name": "FOCUS",
          "pomodoro_shift": {
            "direction": "later",
            "requested_units": 3,
            "delta_minutes": 15,
            "before_start": "0900",
            "before_end": "0925",
            "after_start": "0915",
            "after_end": "0940",
            "duration_minutes": 25,
            "pomodoro_line": 3,
            "pomodoro_name": "FOCUS",
            "time_range": "(**0915-0940** [t:: 25m])"
          }
        }
        """
    }

    private func earlierJSON(dryRun: Bool) -> String {
        """
        {
          "ok": true,
          "dry_run": \(dryRun ? "true" : "false"),
          "routed": false,
          "route": null,
          "route_label": "",
          "relative_target": "2026/20260928.md",
          "target": "/tmp/bob/2026/20260928.md",
          "text": "--2",
          "task_line": "- [ ] (**0850-0915** [t:: 25m]) — FOCUS",
          "kind": "pomodoro_shift",
          "created": "2026-09-28",
          "scheduled": null,
          "placement": "toggled",
          "pomodoro_name": "FOCUS",
          "pomodoro_shift": {
            "direction": "earlier",
            "requested_units": 2,
            "delta_minutes": -10,
            "before_start": "0900",
            "before_end": "0925",
            "after_start": "0850",
            "after_end": "0915",
            "duration_minutes": 25,
            "pomodoro_line": 3,
            "pomodoro_name": "FOCUS",
            "time_range": "(**0850-0915** [t:: 25m])"
          }
        }
        """
    }

    private func unnamedJSON(dryRun: Bool) -> String {
        """
        {
          "ok": true,
          "dry_run": \(dryRun ? "true" : "false"),
          "routed": false,
          "route": null,
          "route_label": "",
          "relative_target": "2026/20260928.md",
          "target": "/tmp/bob/2026/20260928.md",
          "text": "++1",
          "task_line": "- [ ] (**0905-0930** [t:: 25m])",
          "kind": "pomodoro_shift",
          "created": "2026-09-28",
          "scheduled": null,
          "placement": "toggled",
          "pomodoro_shift": {
            "direction": "later",
            "requested_units": 1,
            "delta_minutes": 5,
            "before_start": "0900",
            "before_end": "0925",
            "after_start": "0905",
            "after_end": "0930",
            "duration_minutes": 25,
            "pomodoro_line": 3,
            "time_range": "(**0905-0930** [t:: 25m])"
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
}
