import XCTest

@testable import CaptureCore

final class CapturePomodoroAdjustPresentationTests: XCTestCase {
    func testInitReturnsNilWithoutAdjustSummary() throws {
        let success = try decodeCaptureSuccess(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/tmp/bob/cash.md","text":"Call bank",
             "task_line":"- [ ] #task Call bank [created::2026-08-14]","kind":"task",
             "created":"2026-08-14","scheduled":null,"placement":"inserted"}
            """
        )

        XCTAssertNil(CapturePomodoroAdjustPresentation(capture: success))
    }

    func testDryRunPreviewUsesWouldAdjustWithBeforeAfterTiming() throws {
        let success = try decodeCaptureSuccess(adjustJSON(dryRun: true))

        let presentation = try XCTUnwrap(CapturePomodoroAdjustPresentation(capture: success))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertEqual(presentation.pomodoroName, "FOCUS")
        XCTAssertEqual(presentation.sessionText, "0900-0930 (30m) → 0900-0955 (55m), +25m")
        XCTAssertEqual(presentation.destinationText, "FOCUS · line 3")
        XCTAssertEqual(
            presentation.statusText,
            "Would adjust FOCUS 0900-0930 (30m) to 0900-0955 (55m), +25m at line 3"
        )
        XCTAssertFalse(presentation.clamped)
        XCTAssertTrue(presentation.accessibilitySummary.contains("Adjusts FOCUS"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("plus 25 minutes"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("line 3"))
        XCTAssertEqual(presentation.notificationDetail, presentation.statusText)
    }

    func testClampedSubtractionReportsRequestedVersusApplied() throws {
        let success = try decodeCaptureSuccess(clampedJSON(dryRun: true))

        let presentation = try XCTUnwrap(CapturePomodoroAdjustPresentation(capture: success))

        XCTAssertTrue(presentation.clamped)
        XCTAssertEqual(presentation.sessionText, "0900-0910 (10m) → 0900-0900 (0m), -10m")
        XCTAssertEqual(
            presentation.statusText,
            "Would adjust FOCUS 0900-0910 (10m) to 0900-0900 (0m), -10m at line 3 (requested -45m in 9 units clamped)"
        )
        XCTAssertTrue(presentation.accessibilitySummary.contains("requested minus 45 minutes"))
        XCTAssertTrue(presentation.accessibilitySummary.contains("clamped to minus 10 minutes"))
    }

    func testCommittedCaptureUsesAdjustedVerb() throws {
        let success = try decodeCaptureSuccess(adjustJSON(dryRun: false))

        let presentation = try XCTUnwrap(CapturePomodoroAdjustPresentation(capture: success))

        XCTAssertFalse(presentation.isDryRun)
        XCTAssertTrue(presentation.statusText.hasPrefix("Adjusted FOCUS 0900-0930 (30m)"))
    }

    func testUnnamedTargetFallsBackToCurrentSession() throws {
        let success = try decodeCaptureSuccess(unnamedJSON(dryRun: true))

        let presentation = try XCTUnwrap(CapturePomodoroAdjustPresentation(capture: success))

        XCTAssertEqual(presentation.pomodoroName, "current session")
        XCTAssertTrue(presentation.statusText.contains("current session"))
        XCTAssertEqual(presentation.destinationText, "current session · line 3")
    }

    private func adjustJSON(dryRun: Bool) -> String {
        """
        {
          "ok": true,
          "dry_run": \(dryRun ? "true" : "false"),
          "routed": false,
          "route": null,
          "route_label": "",
          "relative_target": "day.md",
          "target": "/tmp/bob/day.md",
          "text": "+5",
          "task_line": "- [ ] (**0900-0955** [t:: 55m]) — FOCUS",
          "kind": "pomodoro_adjust",
          "created": "2026-08-14",
          "scheduled": null,
          "placement": "toggled",
          "pomodoro_name": "FOCUS",
          "pomodoro_adjust": {
            "direction": "plus",
            "requested_units": 5,
            "requested_minutes": 25,
            "delta_minutes": 25,
            "before_start": "0900",
            "before_end": "0930",
            "before_duration_minutes": 30,
            "after_start": "0900",
            "after_end": "0955",
            "after_duration_minutes": 55,
            "pomodoro_line": 3,
            "pomodoro_name": "FOCUS",
            "time_range": "(**0900-0955** [t:: 55m])",
            "clamped": false
          }
        }
        """
    }

    private func clampedJSON(dryRun: Bool) -> String {
        """
        {
          "ok": true,
          "dry_run": \(dryRun ? "true" : "false"),
          "routed": false,
          "route": null,
          "route_label": "",
          "relative_target": "day.md",
          "target": "/tmp/bob/day.md",
          "text": "-9",
          "task_line": "- [ ] (**0900-0900** [t:: 0m]) — FOCUS",
          "kind": "pomodoro_adjust",
          "created": "2026-08-14",
          "scheduled": null,
          "placement": "toggled",
          "pomodoro_name": "FOCUS",
          "pomodoro_adjust": {
            "direction": "minus",
            "requested_units": 9,
            "requested_minutes": -45,
            "delta_minutes": -10,
            "before_start": "0900",
            "before_end": "0910",
            "before_duration_minutes": 10,
            "after_start": "0900",
            "after_end": "0900",
            "after_duration_minutes": 0,
            "pomodoro_line": 3,
            "pomodoro_name": "FOCUS",
            "time_range": "(**0900-0900** [t:: 0m])",
            "clamped": true
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
          "relative_target": "day.md",
          "target": "/tmp/bob/day.md",
          "text": "+1",
          "task_line": "- [ ] (**0900-0935** [t:: 35m])",
          "kind": "pomodoro_adjust",
          "created": "2026-08-14",
          "scheduled": null,
          "placement": "toggled",
          "pomodoro_adjust": {
            "direction": "plus",
            "requested_units": 1,
            "requested_minutes": 5,
            "delta_minutes": 5,
            "before_start": "0900",
            "before_end": "0930",
            "before_duration_minutes": 30,
            "after_start": "0900",
            "after_end": "0935",
            "after_duration_minutes": 35,
            "pomodoro_line": 3,
            "time_range": "(**0900-0935** [t:: 35m])",
            "clamped": false
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
