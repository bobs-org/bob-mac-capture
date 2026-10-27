import Foundation
import XCTest

@testable import CaptureCore

// Real-bob fixtures for inbox routing (`bob capture --inbox-route`).
// Generated with bob-cli master (route-apply landed) against a sandbox vault;
// each success fixture stores the `--dry-run -f json` response with
// `dry_run` reset to false so fake-bob can serve either tense:
//
//   BOB=target/debug/bob; VAULT=/tmp/bob-mac-capture-inbox-route/vault
//   export BOB_CONFIG_FILE=/definitely/missing/bob-cli-test-config.yml
//   export BOB_WEB_CLIP_ADAPTER=/definitely/missing/bob-cli-test-web-clip-adapter
//   export BOB_DAY_FILE=$VAULT/20261024.md BOB_NOW="2026-10-24 09:30:00"
//   # vault: inbox.md, mac_inbox.md + gkeep_inbox.md areas under inbox,
//   # health.md + errands.md areas, app.md wip project, dev.md area,
//   # 20261024.md day file with one WORK Pomodoro
//   $BOB capture -b $VAULT -f json --dry-run -- '@mac_inbox:route-task'  # inbox-route-preview-one.json
//   $BOB capture -b $VAULT -f json --dry-run -- '@mac_inbox:route-task   # inbox-route-preview-two.json
//     <blank line>@gkeep_inbox:gkeep-task'
//   $BOB capture -b $VAULT -f json --dry-run -i '1=health' -- '@mac_inbox:route-task'  # inbox-route-moved.json
//   $BOB capture -b $VAULT -f json --dry-run -i keep -- '@mac_inbox:route-task'        # inbox-route-kept.json
//   $BOB capture -b $VAULT -f json --require-inbox-route-choice -- '@mac_inbox:route-task'  # inbox-route-choice-required.json (ok:false)
//   $BOB capture -b $VAULT -f json --dry-run -i '1=mac_inbox' -- '@mac_inbox:route-task'    # inbox-route-refused.json (ok:false)
//   $BOB capture -b $VAULT -f json --dry-run -i '9=health' -- '@mac_inbox:route-task'       # inbox-route-stale.json (ok:false)
//   # pull-in plus route: dev.md holds prereq ^prereq and Blocked dependent ^dep;
//   $BOB capture -b $VAULT -f json --dry-run -- '!dev:prereq               # inbox-route-pullin.json
//     <blank line>@mac_inbox:route-task'
final class CaptureInboxRouteDecodingTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    private func decodeResponse(_ json: String) throws -> CaptureCommandResponse {
        try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(json.utf8))
    }

    func testPreviewWithOneCandidateDecodesDestinations() throws {
        let data = try fixture("inbox-route-preview-one.json")
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            return XCTFail("Expected capture success")
        }
        let route = try XCTUnwrap(success.inboxRoute)
        XCTAssertTrue(route.supported)
        XCTAssertEqual(route.candidateCount, 1)
        XCTAssertEqual(route.routedCount, 0)
        XCTAssertEqual(route.keptCount, 0)
        let candidate = try XCTUnwrap(route.candidates.first)
        XCTAssertEqual(candidate.key, "mac_inbox.md#^route-task")
        XCTAssertEqual(candidate.n, 1)
        XCTAssertEqual(candidate.notePath, "mac_inbox.md")
        XCTAssertEqual(candidate.inbox, "mac_inbox")
        XCTAssertEqual(candidate.blockID, "route-task")
        XCTAssertEqual(candidate.text, "Route me")
        XCTAssertEqual(candidate.previousStatusSymbol, " ")
        XCTAssertEqual(candidate.previousStatusName, "Ready")
        XCTAssertEqual(candidate.statusSymbol, "*")
        XCTAssertEqual(candidate.statusName, "Next")
        XCTAssertNil(candidate.answer)
        XCTAssertEqual(candidate.outcome, "pending")
        XCTAssertNil(candidate.moved)
        let destinations = try XCTUnwrap(route.destinations)
        XCTAssertEqual(destinations.count, 3)
        XCTAssertTrue(destinations.contains(where: { $0.relativePath == "health.md" }))
        XCTAssertFalse(destinations.contains(where: { $0.relativePath == "mac_inbox.md" }))
        XCTAssertFalse(destinations.contains(where: { $0.relativePath == "gkeep_inbox.md" }))
        let health = try XCTUnwrap(destinations.first(where: { $0.relativePath == "health.md" }))
        XCTAssertEqual(health.label, "health")
        XCTAssertEqual(health.kind, "area")
        XCTAssertFalse(health.blocked)
        let app = try XCTUnwrap(destinations.first(where: { $0.relativePath == "app.md" }))
        XCTAssertEqual(app.kind, "project")
        XCTAssertEqual(app.status, "wip")
    }

    func testPreviewWithTwoCandidatesNumbersByNotePath() throws {
        let data = try fixture("inbox-route-preview-two.json")
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            return XCTFail("Expected capture success")
        }
        let route = try XCTUnwrap(success.inboxRoute)
        XCTAssertEqual(route.candidateCount, 2)
        XCTAssertEqual(route.candidates.count, 2)
        XCTAssertEqual(route.candidates.map(\.n), [1, 2])
        let keys = Set(route.candidates.map(\.key))
        XCTAssertTrue(keys.contains("mac_inbox.md#^route-task"))
        XCTAssertTrue(keys.contains("gkeep_inbox.md#^gkeep-task"))
    }

    func testMovedSuccessDecodesAnswerAndLanding() throws {
        let data = try fixture("inbox-route-moved.json")
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            return XCTFail("Expected capture success")
        }
        let route = try XCTUnwrap(success.inboxRoute)
        XCTAssertEqual(route.routedCount, 1)
        let candidate = try XCTUnwrap(route.candidates.first)
        XCTAssertEqual(candidate.outcome, "moved")
        XCTAssertEqual(candidate.answer?.action, "move")
        XCTAssertEqual(candidate.answer?.destination, "health.md")
        let moved = try XCTUnwrap(candidate.moved)
        XCTAssertEqual(moved.destination, "health.md")
        XCTAssertEqual(moved.blockID, "route-task")
        XCTAssertEqual(moved.previousBlockID, "route-task")
        XCTAssertEqual(moved.fresh, "2026-10-24")
    }

    func testKeptSuccessDecodesKeepAnswer() throws {
        let data = try fixture("inbox-route-kept.json")
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            return XCTFail("Expected capture success")
        }
        let route = try XCTUnwrap(success.inboxRoute)
        XCTAssertEqual(route.keptCount, 1)
        let candidate = try XCTUnwrap(route.candidates.first)
        XCTAssertEqual(candidate.outcome, "kept")
        XCTAssertEqual(candidate.answer?.action, "keep")
        XCTAssertNil(candidate.answer?.destination)
        XCTAssertNil(candidate.moved)
    }

    func testPullInPlusRouteDraftCarriesBothPayloads() throws {
        let data = try fixture("inbox-route-pullin.json")
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)
        guard case .success(let success) = response else {
            return XCTFail("Expected capture success")
        }
        XCTAssertNotNil(success.inboxRoute)
        XCTAssertEqual(success.inboxRoute?.candidateCount, 1)
        XCTAssertNotNil(success.pullIn)
    }

    func testChoiceRequiredRefusalCarriesCandidatesAndDestinations() throws {
        let data = try fixture("inbox-route-choice-required.json")
        let failure = try JSONDecoder().decode(CaptureCommandFailure.self, from: data)
        XCTAssertEqual(failure.code, "inbox_route_choice_required")
        let route = try XCTUnwrap(failure.inboxRoute)
        XCTAssertTrue(route.supported)
        XCTAssertEqual(route.candidateCount, 1)
        XCTAssertEqual(route.candidates.first?.key, "mac_inbox.md#^route-task")
        XCTAssertNotNil(route.destinations)
        XCTAssertNil(failure.refused)
    }

    func testRefusedRefusalNamesCandidateDestinationAndMessage() throws {
        let data = try fixture("inbox-route-refused.json")
        let failure = try JSONDecoder().decode(CaptureCommandFailure.self, from: data)
        XCTAssertEqual(failure.code, "inbox_route_refused")
        XCTAssertNotNil(failure.inboxRoute)
        let refused = try XCTUnwrap(failure.refused)
        XCTAssertEqual(refused.key, "mac_inbox.md#^route-task")
        XCTAssertEqual(refused.n, 1)
        XCTAssertEqual(refused.destination, "mac_inbox.md")
        XCTAssertFalse(refused.message.isEmpty)
    }

    func testStaleErrorCarriesCandidateList() throws {
        let data = try fixture("inbox-route-stale.json")
        let failure = try JSONDecoder().decode(CaptureCommandFailure.self, from: data)
        XCTAssertEqual(failure.code, "inbox_route_stale")
        XCTAssertEqual(failure.inboxRoute?.candidateCount, 1)
        XCTAssertNil(failure.refused)
    }

    func testOldBobWithoutInboxRouteDecodesAsNil() throws {
        guard
            case .success(let success) = try decodeResponse(
                """
                {"ok":true,"dry_run":true,"routed":true,"route_label":"cash.md",
                 "relative_target":"cash.md","target":"/tmp/bob/cash.md","text":"t",
                 "task_line":"- [ ] #task t","kind":"task","created":"2026-10-24",
                 "placement":"inserted"}
                """
            )
        else {
            return XCTFail("Expected capture success")
        }
        XCTAssertNil(success.inboxRoute)

        let failure = try JSONDecoder().decode(
            CaptureCommandFailure.self,
            from: Data(#"{"ok":false,"error":"old Bob"}"#.utf8)
        )
        XCTAssertNil(failure.inboxRoute)
        XCTAssertNil(failure.refused)
    }

    func testMalformedInboxRouteDegradesToNil() throws {
        guard
            case .success(let success) = try decodeResponse(
                """
                {"ok":true,"dry_run":true,"routed":true,"route_label":"cash.md",
                 "relative_target":"cash.md","target":"/tmp/bob/cash.md","text":"t",
                 "task_line":"- [ ] #task t","kind":"task","created":"2026-10-24",
                 "placement":"inserted","inbox_route":"nope"}
                """
            )
        else {
            return XCTFail("Expected capture success")
        }
        XCTAssertNil(success.inboxRoute)

        let failure = try JSONDecoder().decode(
            CaptureCommandFailure.self,
            from: Data(
                """
                {"ok":false,"error":"x","code":"inbox_route_refused",
                 "inbox_route":[1,2],"refused":"nope"}
                """.utf8
            )
        )
        XCTAssertEqual(failure.code, "inbox_route_refused")
        XCTAssertNil(failure.inboxRoute)
        XCTAssertNil(failure.refused)
    }

    func testMalformedCandidateRowDegradesThatRowButKeepsTheCapture() throws {
        guard
            case .success(let success) = try decodeResponse(
                """
                {"ok":true,"dry_run":true,"routed":true,"route_label":"cash.md",
                 "relative_target":"cash.md","target":"/tmp/bob/cash.md","text":"t",
                 "task_line":"- [ ] #task t","kind":"task","created":"2026-10-24",
                 "placement":"inserted",
                 "inbox_route":{"supported":true,"candidate_count":2,"routed_count":0,
                   "kept_count":0,"candidates":[{"key":42},{"key":"mac_inbox.md#^ok","n":2}]}}
                """
            )
        else {
            return XCTFail("Expected capture success")
        }
        // One malformed row degrades that row to its defaults, never the
        // capture or its sibling.
        let route = try XCTUnwrap(success.inboxRoute)
        XCTAssertEqual(route.candidates.count, 2)
        XCTAssertEqual(route.candidates[0].key, "")
        XCTAssertEqual(route.candidates[1].key, "mac_inbox.md#^ok")
    }
}
