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

    func testAllPullInOfferRowsCollectOnceAndLeaveRequirementsAside() throws {
        let json = #"""
            {
              "ok": true, "dry_run": true, "routed": false, "route_label": "",
              "relative_target": "day.md", "target": "/tmp/day.md", "text": "close",
              "task_line": "- [x] Task", "kind": "batch", "created": "2026-11-02",
              "placement": "batch",
              "task_complete": {
                "raw": "a",
                "unblocked": [{"text":"unblocked","offer":{"key":"u1","n":1}}],
                "keep_moving": [{"text":"keep moving","offer":{"key":"k1","n":2}}]
              },
              "note_pull": {
                "note": "sase.md", "route": "sase",
                "successors": [{"text":"note pull","offer":{"key":"n1","n":3,"group":"note_pull"}}]
              },
              "project_note": {
                "basename": "cash.md", "parent_route": "cash", "parent_link": "[[cash]]",
                "form": "offer",
                "successors": [{"text":"project offer","offer":{"key":"p1","n":4,"group":"project"}}]
              },
              "relation_successors": [{"text":"relation","offer":{"key":"r1","n":5,"group":"relation"}}],
              "pull_in": {
                "supported": true, "offer_count": 5,
                "reqs": {"supported": true, "pending": 1},
                "groups": [
                  {
                    "group": "requirements", "kind": "requirements",
                    "owner": {"key": "owner@hash", "task_key": "sase.md#^ship", "text": "Ship"},
                    "rows": [{
                      "offer": {"key": "owner@hash/req/1~aaaa", "n": 6, "group": "requirements"},
                      "req": {
                        "owner": "owner@hash", "path": "1", "depth": 1,
                        "text": "Handles empty input", "line": 2, "state": "pending"
                      },
                      "consequences": {
                        "met": "Met", "drop": "Drop",
                        "carry": "Carry", "carry_pulled": "Carry and pull"
                      }
                    }]
                  },
                  {"group": "hand_off"}
                ]
              }
            }
            """#
        guard
            case .success(let success) = try JSONDecoder().decode(
                CaptureCommandResponse.self, from: Data(json.utf8))
        else {
            return XCTFail("Expected capture success")
        }

        XCTAssertEqual(
            success.allPullInOfferRows.map(\.text),
            ["unblocked", "keep moving", "project offer", "note pull", "relation"]
        )
        XCTAssertEqual(
            success.allPullInOfferRows.compactMap { $0.offer?.key },
            ["u1", "k1", "p1", "n1", "r1"]
        )
        XCTAssertEqual(success.allRequirementGroups.count, 1)
        XCTAssertEqual(
            success.allRequirementGroups.first?.rows.map(\.offer.key),
            ["owner@hash/req/1~aaaa"]
        )
        XCTAssertFalse(
            success.allPullInOfferRows.contains { $0.offer?.key == "owner@hash/req/1~aaaa" })
        XCTAssertFalse(
            success.allUnblockedRows.contains { $0.offer?.key == "owner@hash/req/1~aaaa" })

        let canonical = try XCTUnwrap(success.pullInWithCanonicalRequirementGroups())
        XCTAssertEqual(canonical.groups.map(\.effectiveKind), ["requirements", "hand_off"])
        XCTAssertTrue(canonical.hasSelectableRequirements)
    }

    func testMixedFixtureKeepsRequirementRowsOutOfUnblockedCollectors() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let data = try Data(
            contentsOf: fixtures.appendingPathComponent("capture-req-close-mixed.json"))
        guard
            case .success(let mixed) = try JSONDecoder().decode(
                CaptureCommandResponse.self, from: data)
        else {
            return XCTFail("Expected mixed requirement fixture")
        }
        XCTAssertEqual(mixed.allPullInOfferRows.compactMap(\.blockID), ["docs"])
        XCTAssertEqual(mixed.allUnblockedRows.compactMap(\.blockID), ["docs"])
        XCTAssertEqual(mixed.allRequirementGroups.first?.rows.count, 3)
        XCTAssertEqual(
            Set(mixed.allPullInOfferRows.compactMap { $0.offer?.key })
                .intersection(
                    Set(mixed.allRequirementGroups.flatMap(\.rows).map(\.offer.key))),
            [])
    }
}
