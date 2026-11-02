import Foundation
import XCTest

@testable import CaptureCore

/// `allUnblockedRows` / `allKeepMovingRows` replace hand-written `+` chains, so the
/// order they return (task_complete → pomodoro_close → relation_completes) is the
/// contract that `pulledInSummary` relies on to name the first-seen project.
final class CaptureSuccessorOfferRowsTests: XCTestCase {
    func testRowsFollowTaskCompletePomodoroCloseRelationOrderAndSkipNilClose() throws {
        let json = #"""
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route_label": "",
              "relative_target": "day.md",
              "target": "/tmp/day.md",
              "text": "close everything",
              "task_line": "- [ ] Task",
              "kind": "batch",
              "created": "2026-11-02",
              "placement": "batch",
              "task_complete": {
                "raw": "a",
                "unblocked": [{"text": "task unblocked"}],
                "keep_moving": [{"text": "task moving"}]
              },
              "pomodoro_close": {
                "raw": "b",
                "unblocked": [{"text": "pomodoro unblocked"}],
                "keep_moving": [{"text": "pomodoro moving"}]
              },
              "relation_completes": [
                {
                  "task_complete": {
                    "raw": "c",
                    "unblocked": [{"text": "relation unblocked"}],
                    "keep_moving": [{"text": "relation moving"}]
                  }
                },
                {"task_complete": null}
              ]
            }
            """#

        guard
            case .success(let success) = try JSONDecoder().decode(
                CaptureCommandResponse.self,
                from: Data(json.utf8)
            )
        else {
            return XCTFail("Expected capture success")
        }

        XCTAssertEqual(success.relationCompletes.count, 2)
        XCTAssertNil(success.relationCompletes[1].taskComplete)
        XCTAssertEqual(
            success.allUnblockedRows.map(\.text),
            ["task unblocked", "pomodoro unblocked", "relation unblocked"]
        )
        XCTAssertEqual(
            success.allKeepMovingRows.map(\.text),
            ["task moving", "pomodoro moving", "relation moving"]
        )
    }

    func testRowsAreEmptyWithoutAnyClose() {
        let success = CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: false,
            route: "",
            routeLabel: "",
            relativeTarget: "day.md",
            target: "/tmp/day.md",
            text: "plain",
            taskLine: "- [ ] Task",
            kind: "task",
            created: "2026-11-02",
            placement: "appended"
        )
        XCTAssertTrue(success.allUnblockedRows.isEmpty)
        XCTAssertTrue(success.allKeepMovingRows.isEmpty)
    }
}
