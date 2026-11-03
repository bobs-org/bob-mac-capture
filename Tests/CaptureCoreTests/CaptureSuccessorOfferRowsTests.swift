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

    func testRelationOffersHeldRowsAndCheckStateCoverEveryPayloadLocation() throws {
        let json = #"""
            {
              "ok": true, "dry_run": true, "routed": false, "route_label": "",
              "relative_target": "day.md", "target": "/tmp/day.md", "text": "batch",
              "task_line": "- [ ] Task", "kind": "batch", "created": "2026-11-02",
              "placement": "batch",
              "relation_successors": [{"text":"item-level","offer":{"key":"opaque:item"}}],
              "relation_held": [{"text":"item held","reason":"hidden","relation":{"label":"starts after"}}],
              "relation_check": "checked",
              "task_complete": {
                "relation_successors": [{"text":"task-complete"}],
                "relation_held": [{"text":"task held","reason":"already_started"}],
                "relation_check": "checked"
              },
              "relation_completes": [{"task_complete": {
                "relation_successors": [{"text":"nested-complete"}],
                "relation_held": [{"text":"nested held","reason":"waits_for"}],
                "relation_check": "checked"
              }}],
              "pomodoro_close": {
                "relation_successors": [{"text":"pomodoro-close"}],
                "relation_held": [{"text":"pomodoro held","reason":"blocked"}],
                "relation_check": "unavailable"
              }
            }
            """#

        guard case .success(let success) = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(json.utf8)
        ) else {
            return XCTFail("Expected capture success")
        }

        XCTAssertEqual(
            success.allRelationSuccessors.map(\.text),
            ["item-level", "task-complete", "nested-complete", "pomodoro-close"]
        )
        XCTAssertEqual(
            success.allRelationHeld.map(\.text),
            ["item held", "task held", "nested held", "pomodoro held"]
        )
        XCTAssertEqual(success.allRelationCheck, "unavailable")
        XCTAssertEqual(success.allRelationSuccessors.first?.offer?.key, "opaque:item")
        XCTAssertEqual(success.allRelationHeld.first?.relation?.label, "starts after")
    }

    func testBatchRootMirrorDoesNotDoubleCountNormalizedCaptureRows() throws {
        let json = #"""
            {
              "ok": true, "dry_run": true, "routed": false, "route_label": "",
              "relative_target": "day.md", "target": "/tmp/day.md", "text": "batch",
              "task_line": "- [ ] First", "kind": "batch", "created": "2026-11-02",
              "placement": "batch",
              "relation_successors": [{"text":"legacy root mirror"}],
              "captures": [{
                "ok": true, "dry_run": true, "routed": false, "route_label": "",
                "relative_target": "day.md", "target": "/tmp/day.md", "text": "First",
                "task_line": "- [ ] First", "kind": "task", "created": "2026-11-02",
                "placement": "appended",
                "relation_successors": [{"text":"canonical item"}]
              }]
            }
            """#

        guard case .success(let success) = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(json.utf8)
        ) else {
            return XCTFail("Expected capture success")
        }

        XCTAssertEqual(success.allRelationSuccessors.map(\.text), ["canonical item"])
    }

    func testOlderBobHasEmptyRelationArraysAndNoCheckState() {
        let success = CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: false,
            routeLabel: "",
            relativeTarget: "day.md",
            target: "/tmp/day.md",
            text: "plain",
            taskLine: "- [ ] Task",
            kind: "task",
            created: "2026-11-02",
            placement: "appended"
        )

        XCTAssertTrue(success.allRelationSuccessors.isEmpty)
        XCTAssertTrue(success.allRelationHeld.isEmpty)
        XCTAssertNil(success.allRelationCheck)
    }
}
