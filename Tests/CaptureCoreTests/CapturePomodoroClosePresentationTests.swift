import Foundation
import XCTest

@testable import CaptureCore

final class CapturePomodoroClosePresentationTests: XCTestCase {
    func testRealBobWorkedCloseFixtureDecodesAndPresentsSessionTasksAndWorkLogs() throws {
        let success = try decodeFixture("pomodoro-close-worked.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertEqual(presentation.variant, .session)
        XCTAssertEqual(presentation.pomodoroName, "CAPTURE")
        XCTAssertEqual(presentation.sessionText, "0920-0940 (20m)")
        XCTAssertEqual(presentation.timingChip, "0920-0950 → 0920-0940 · stopped 0937 · −10m")
        XCTAssertEqual(presentation.taskRows.count, 3)
        XCTAssertEqual(presentation.taskRows[0].transitionText, "[*] → [/]  Add support for `=x` syntax!")
        XCTAssertEqual(
            presentation.taskRows[0].workLog,
            [
                "*2026-09-28* — Designed the `=x` grammar",
                "*2026-09-28* — Wrote the plan",
            ]
        )
        XCTAssertTrue(presentation.taskRows[0].carried)
        XCTAssertEqual(presentation.nextSessionText, "Next: CAPTURE · untimed · line 13 · created")
        XCTAssertEqual(presentation.notificationTitle, "Closed CAPTURE")
        XCTAssertTrue(presentation.notificationBody.contains("Work Log · *2026-09-28* — Wrote the plan"))
    }

    func testRealBobExistingTaskCloseUsesLinkVariant() throws {
        let success = try decodeFixture("pomodoro-close-link.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertEqual(presentation.variant, .linkedTask)
        XCTAssertEqual(presentation.headline, "Link task and close CAPTURE")
        XCTAssertEqual(presentation.taskRows.first?.transitionText, "[*] → [/]  Plain ready task")
        XCTAssertTrue(presentation.statusText.hasPrefix("Closed CAPTURE"))
    }

    func testRealBobNewTaskCloseUsesCreateVariant() throws {
        let success = try decodeFixture("pomodoro-close-new-task.json")
        let presentation = try XCTUnwrap(CapturePomodoroClosePresentation(capture: success))

        XCTAssertEqual(presentation.variant, .newTask)
        XCTAssertEqual(presentation.headline, "Create task and close CAPTURE")
        XCTAssertEqual(presentation.taskRows.first?.taskText, "Draft docs")
        XCTAssertTrue(presentation.accessibilitySummary.contains("Next: CAPTURE"))
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

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try decodeSuccess(String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8))
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
