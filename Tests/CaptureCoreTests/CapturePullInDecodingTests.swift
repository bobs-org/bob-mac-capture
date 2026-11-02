import Foundation
import XCTest

@testable import CaptureCore

/// Successor offer decoding is additive to capture schema v1 (SO1–SO6, SO27,
/// SO29, and fan-out): Bob owns keys and groups; the client preserves them.
final class CapturePullInDecodingTests: XCTestCase {
    func testBatchPullInAndOffersDecodeFromBothCloseForms() throws {
        let json = #"""
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route_label": "",
              "relative_target": "day.md",
              "target": "/tmp/day.md",
              "text": "complete and close",
              "task_line": "- [ ] Task",
              "kind": "batch",
              "created": "2026-10-13",
              "placement": "batch",
              "pull_in": {
                "supported": true,
                "offer_count": 2,
                "choice": null,
                "picked_count": 0,
                "groups": [
                  {"group":"project","project":"projects/sase_foo.md","folded":{"hidden":2,"already_planned":1,"sub_projects":3}},
                  {"group":"keep_moving","project":"projects/sase_foo.md","folded":{"blocked":2,"scheduled":1,"hidden":4}},
                  {"group":"future_group","project":"future.md","folded":{}}
                ]
              },
              "task_complete": {
                "raw":"!project:root",
                "unblocked":[{
                  "note_path":"projects/sase_foo.md","block_id":"resident-one","line":10,
                  "text":"Ship the readme","previous_status_symbol":"?","previous_status_name":"Blocked",
                  "status_symbol":" ","status_name":"Ready","not_linked":"not_selected",
                  "trigger":"project_empty","hide_removed":true,
                  "offer":{"key":"digest#^suffix:2","n":2,"group":"project","project":"projects/sase_foo.md",
                    "destination":{"day_file":"20261013.md","entry_name":"FOCUS","entry_role":"next_up","fallback":true},
                    "selected":false,"block_id_needed":true}
                }],
                "still_blocked":[{
                  "note_path":"projects/sase_foo.md","block_id":"resident-two","line":12,
                  "text":"Update tests","status_symbol":"?","status_name":"Blocked","reason":"project",
                  "waits_on":0,"scheduled":"2026-10-20","project":"projects/sase_foo.md","trigger":"dependency"
                }]
              },
              "pomodoro_close":{"raw":"x","unblocked":[{
                "note_path":"travel.md","block_id":"book","line":2,"text":"Book flights",
                "previous_status_symbol":"?","previous_status_name":"Blocked","status_symbol":" ",
                "status_name":"Ready","offer":{"key":"opaque:offer#11","n":1,"group":"hand_off",
                  "destination":{"day_file":"20261013.md","entry_name":"","entry_role":"current","fallback":false}}
              }]}
            }
            """#

        guard
            case .success(let response) = try JSONDecoder().decode(
                CaptureCommandResponse.self,
                from: Data(json.utf8)
            )
        else {
            return XCTFail("Expected capture success")
        }

        XCTAssertEqual(response.pullIn?.supported, true)
        XCTAssertEqual(response.pullIn?.offerCount, 2)
        XCTAssertEqual(response.pullIn?.groups.first?.folded.hidden, 2)
        XCTAssertEqual(response.pullIn?.groups.first?.folded.alreadyPlanned, 1)
        XCTAssertEqual(response.pullIn?.groups.first?.folded.subProjects, 3)
        let movingFold = try XCTUnwrap(response.pullIn?.groups.first(where: { $0.group == "keep_moving" })?.folded)
        XCTAssertEqual(movingFold.blocked, 2)
        XCTAssertEqual(movingFold.scheduled, 1)
        XCTAssertEqual(movingFold.hidden, 4)
        XCTAssertEqual(response.pullIn?.groups.last?.group, "future_group")
        XCTAssertEqual(response.taskComplete?.unblocked.first?.offer?.key, "digest#^suffix:2")
        XCTAssertEqual(response.taskComplete?.unblocked.first?.offer?.destination.entryRole, "next_up")
        XCTAssertEqual(response.taskComplete?.unblocked.first?.offer?.destination.fallback, true)
        XCTAssertEqual(response.taskComplete?.unblocked.first?.offer?.blockIDNeeded, true)
        XCTAssertEqual(response.taskComplete?.unblocked.first?.trigger, "project_empty")
        XCTAssertEqual(response.taskComplete?.unblocked.first?.hideRemoved, true)
        XCTAssertTrue(response.taskComplete?.keepMoving.isEmpty == true)
        XCTAssertEqual(response.taskComplete?.stillBlocked.first?.project, "projects/sase_foo.md")
        XCTAssertEqual(response.taskComplete?.stillBlocked.first?.trigger, "dependency")
        XCTAssertEqual(response.pomodoroClose?.unblocked.first?.offer?.key, "opaque:offer#11")
        XCTAssertTrue(response.pomodoroClose?.keepMoving.isEmpty == true)
    }

    func testKeepMovingArraysDecodeOnBothCloseSurfacesAndNestedRelationCompletes() throws {
        let row = #"{"note_path":"projects/sase_badges.md","block_id":"ship","line":5,"text":"Ship the badge renderer","previous_status_symbol":"/","previous_status_name":"Pending","status_symbol":"/","status_name":"Pending","unblocked_by":[{"note_path":"projects/sase_badges.md","block_id":"draft","text":"Draft the badge spec"}],"trigger":"last_planned","offer":{"key":"opaque:keep-moving#^ship","n":1,"group":"keep_moving","project":"projects/sase_badges.md","selected":false}}"#
        let json = """
            {"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"",
             "relative_target":"day.md","target":"/tmp/day.md","text":"",
             "task_line":"","kind":"task_complete","created":"2026-11-02",
             "placement":"updated",
             "task_complete":{"raw":"!sase_badges:draft","keep_moving":[\(row)]},
             "pomodoro_close":{"raw":"x!1","keep_moving":[]},
             "relation_completes":[{"task_complete":{"raw":"!sase_badges:draft","keep_moving":[\(row)]}}]}
            """
        guard case .success(let response) = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(json.utf8)
        ) else {
            return XCTFail("Expected capture success")
        }

        XCTAssertEqual(response.taskComplete?.keepMoving.first?.trigger, "last_planned")
        XCTAssertEqual(response.taskComplete?.keepMoving.first?.offer?.group, "keep_moving")
        XCTAssertTrue(response.pomodoroClose?.keepMoving.isEmpty == true)
        XCTAssertEqual(
            response.relationCompletes.first?.taskComplete?.keepMoving.first?.offer?.key,
            "opaque:keep-moving#^ship"
        )
    }

    func testRealBobKeepMovingFixturesDecodeForTaskAndPomodoroClose() throws {
        for (name, keyPath) in [
            ("task-complete-keep-moving.json", "task_complete"),
            ("pomodoro-close-keep-moving.json", "pomodoro_close"),
        ] {
            let fixtures = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("../Fixtures", isDirectory: true)
                .standardizedFileURL
            let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
            let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(text.utf8))
            guard case .success(let response) = decoded else {
                return XCTFail("Expected real-bob success fixture: \(name)")
            }
            let rows = keyPath == "task_complete"
                ? response.taskComplete?.keepMoving
                : response.pomodoroClose?.keepMoving
            XCTAssertFalse(rows?.isEmpty ?? true, "\(name) must contain real keep-moving rows")
            XCTAssertTrue(rows?.allSatisfy { $0.trigger == "last_planned" } == true)
        }
    }

    func testFailureRefusalKeepsTopLevelOffersAndUnknownStrings() throws {
        let json = #"""
            {"ok":false,"error":"Choose pull-in offers","code":"pull_in_choice_required",
             "pull_in":{"supported":true,"offer_count":1,"choice":"explicit","picked_count":0},
             "offers":[{"note_path":"x.md","block_id":"a","line":3,"text":"Task",
               "previous_status_symbol":"?","previous_status_name":"Blocked","status_symbol":" ","status_name":"Ready",
               "not_linked":"future_reason","trigger":"future_trigger","hide_removed":true,
               "offer":{"key":"sha256:a#1","n":7,"group":"future_group","project":"x.md",
                 "destination":{"day_file":"d.md","entry_name":"Later","entry_role":"new_role","fallback":false},
                 "selected":false,"block_id_needed":false}}]}
            """#

        let failure = try JSONDecoder().decode(CaptureCommandFailure.self, from: Data(json.utf8))
        XCTAssertEqual(failure.code, "pull_in_choice_required")
        XCTAssertEqual(failure.pullIn?.choice, "explicit")
        XCTAssertEqual(failure.offers.first?.offer?.key, "sha256:a#1")
        XCTAssertEqual(failure.offers.first?.offer?.group, "future_group")
        XCTAssertEqual(failure.offers.first?.offer?.destination.entryRole, "new_role")
        XCTAssertEqual(failure.offers.first?.notLinked, "future_reason")
        XCTAssertEqual(failure.offers.first?.trigger, "future_trigger")
        XCTAssertTrue(failure.offers.first?.hideRemoved == true)
    }

    func testLegacyAndZeroOfferCapabilitiesRemainDistinct() throws {
        let legacy = try JSONDecoder().decode(
            CaptureCommandFailure.self,
            from: Data(#"{"ok":false,"error":"old Bob"}"#.utf8)
        )
        XCTAssertNil(legacy.pullIn)
        XCTAssertTrue(legacy.offers.isEmpty)

        let zero = try JSONDecoder().decode(
            CapturePullIn.self,
            from: Data(#"{"supported":true,"offer_count":0,"choice":null,"picked_count":0}"#.utf8)
        )
        XCTAssertTrue(zero.supported)
        XCTAssertEqual(zero.offerCount, 0)
        XCTAssertTrue(zero.groups.isEmpty)

        let oldRow = try JSONDecoder().decode(
            TaskCompleteUnblocked.self,
            from: Data(#"{"text":"old row"}"#.utf8)
        )
        XCTAssertNil(oldRow.offer)
        XCTAssertNil(oldRow.trigger)
        XCTAssertFalse(oldRow.hideRemoved)
    }

    func testNewWireFieldsEncodeAndDecodeWithoutChangingOpaqueKeys() throws {
        let row = TaskCompleteUnblocked(
            notePath: "sase.md",
            blockID: "t1",
            text: "Task",
            offer: TaskCompleteOffer(
                key: "hash#caret^dup:2",
                n: 3,
                group: "hand_off",
                destination: TaskCompleteOfferDestination(
                    dayFile: "20261013.md",
                    entryName: "FOCUS",
                    entryRole: "current",
                    fallback: false
                ),
                blockIDNeeded: true
            )
        )
        let data = try JSONEncoder().encode(row)
        let decoded = try JSONDecoder().decode(TaskCompleteUnblocked.self, from: data)
        XCTAssertEqual(decoded, row)
        XCTAssertEqual(decoded.offer?.key, "hash#caret^dup:2")
    }
}
