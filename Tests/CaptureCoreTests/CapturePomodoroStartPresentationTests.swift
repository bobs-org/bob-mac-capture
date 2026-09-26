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
        XCTAssertEqual(presentation.destinationText, "next session · line 12")
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
        XCTAssertEqual(presentation.destinationText, "deep · line 14 · created entry")
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
}
