import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRelationSuccessorDecodingTests: XCTestCase {
    func testRealBobFixturesCoverRelationResultsAndChoiceOutcomes() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        func success(_ name: String) throws -> CaptureCommandSuccess {
            let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
            guard case .success(let response) = try JSONDecoder().decode(
                CaptureCommandResponse.self,
                from: data
            ) else {
                throw FixtureError.expectedSuccess(name)
            }
            return response
        }

        let parked = try success("relation-successor-parked-x-star.json")
        XCTAssertEqual(parked.pomodoroClose?.relationSuccessors.first?.relation?.event, "parked")
        XCTAssertEqual(parked.pullIn?.copy?.glyph, "relation")
        XCTAssertEqual(parked.pullIn?.groups.first?.copy?.title, "Starts after “Send implementation prompt”")

        let done = try success("relation-successor-done-bang.json")
        XCTAssertEqual(done.taskComplete?.relationSuccessors.first?.relation?.event, "done")

        let toggle = try success("relation-successor-pending-toggle-unlink.json")
        XCTAssertEqual(toggle.relationSuccessors.first?.offer?.group, "relation")
        XCTAssertEqual(toggle.relationCheck, "checked")

        let held = try success("relation-successor-held-only.json")
        XCTAssertTrue(held.allRelationSuccessors.isEmpty)
        XCTAssertEqual(held.allRelationHeld.first?.reason, "already_started")

        let mixed = try success("relation-successor-mixed-x-star-dependency.json")
        XCTAssertEqual(mixed.allUnblockedRows.first?.offer?.group, "hand_off")
        XCTAssertEqual(mixed.allRelationSuccessors.count, 1)
        XCTAssertEqual(mixed.pullIn?.offerCount, 2)

        let nested = try success("relation-successor-nested-complete-label.json")
        XCTAssertEqual(nested.allRelationSuccessors.first?.relation?.event, "done")

        let selected = try success("relation-successor-selected-opaque-key.json")
        XCTAssertEqual(selected.pomodoroClose?.relationSuccessors.first?.offer?.selected, true)
        XCTAssertFalse(selected.pomodoroClose?.relationSuccessors.first?.offer?.key.isEmpty ?? true)
        XCTAssertTrue(selected.taskBlocks.contains(where: \.hasRelationSuccessorRole))

        let none = try success("relation-successor-none-choice.json")
        XCTAssertEqual(none.pullIn?.choice, "none")
        XCTAssertEqual(none.pomodoroClose?.relationSuccessors.first?.offer?.selected, false)

        let refusalData = try Data(contentsOf: fixtures.appendingPathComponent(
            "relation-successor-required-choice-refusal.json"
        ))
        guard case .failure(let refusal) = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: refusalData
        ) else {
            return XCTFail("Expected real-Bob required-choice refusal")
        }
        XCTAssertEqual(refusal.code, "pull_in_choice_required")
        XCTAssertFalse(refusal.offers.isEmpty)
    }

    func testRealBobAuthoringFixturesCarryOffersCaveatsInverseAndSpans() throws {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        func completion(_ name: String) throws -> CaptureCompletionResponse {
            let data = try Data(contentsOf: fixtures.appendingPathComponent(name))
            return try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)
        }

        let offers = try completion("relation-successor-authoring-offers.json")
        XCTAssertEqual(offers.relationSuccessor?.verdict, "offers")
        XCTAssertTrue(offers.candidates.contains(where: \.offersSource))

        let parked = try completion("relation-successor-authoring-already-parked.json")
        XCTAssertEqual(parked.relationSuccessor?.verdict, "already_parked")

        let closed = try completion("relation-successor-authoring-already-closed.json")
        XCTAssertEqual(closed.relationSuccessor?.verdict, "already_closed")

        let inverse = try completion("relation-successor-authoring-inverse-hint.json")
        XCTAssertNil(inverse.relationSuccessor?.verdict)
        XCTAssertNotNil(inverse.relationSuccessor?.hint)

        let parseData = try Data(contentsOf: fixtures.appendingPathComponent(
            "relation-successor-authoring-spans.json"
        ))
        let parse = try JSONDecoder().decode(CaptureParseResponse.self, from: parseData)
        XCTAssertTrue(parse.spans.contains(where: \.offersSource))
    }

    func testRelationRowsOffersHeldRowsAndBobCopyDecodeAdditively() throws {
        let rowJSON = #"""
            {
              "text":"Prepare evaluation prompt",
              "offer":{"key":"opaque#key^suffix","n":4,"group":"relation",
                "after":"agents.md#^implement","destination":{"entry_role":"next_up"}},
              "relation":{"label":"starts after","key":"starts after","event":"parked",
                "after":[{"note_path":"agents.md","block_id":"implement","text":"Send implementation prompt"}]}
            }
            """#
        let row = try JSONDecoder().decode(TaskCompleteUnblocked.self, from: Data(rowJSON.utf8))
        XCTAssertEqual(row.offer?.key, "opaque#key^suffix")
        XCTAssertEqual(row.offer?.after, "agents.md#^implement")
        XCTAssertEqual(row.relation?.event, "parked")
        XCTAssertEqual(row.relation?.after.first?.text, "Send implementation prompt")

        let pullInJSON = #"""
            {
              "supported":true,"offer_count":1,"choice":null,"picked_count":0,
              "copy":{"title":"Pull in successors of Send implementation prompt",
                "capsule":"Starts after","glyph":"link"},
              "groups":[
                {"group":"relation","after":{"key":"opaque-after","note_path":"agents.md",
                  "block_id":"implement","text":"Send implementation prompt"},
                 "label":"starts after","event":"parked",
                 "folded":{"hidden":1,"already_planned":2,"sub_projects":3,
                   "blocked":4,"scheduled":5,"already_started":6,"waits_for":7},
                 "copy":{"title":"Starts after “Send implementation prompt”",
                   "why":"“Send implementation prompt” is parked · Pending, off today's plan",
                   "tag":"your links · not dependents","fold":"not offered · 1 already started",
                   "glyph":"link"}},
                {"group":"project_finished","copy":{"title":"Project finished","glyph":"checkmark.circle"}}
              ]
            }
            """#
        let pullIn = try JSONDecoder().decode(CapturePullIn.self, from: Data(pullInJSON.utf8))
        XCTAssertEqual(pullIn.copy?.capsule, "Starts after")
        let relationGroup = try XCTUnwrap(pullIn.groups.first)
        XCTAssertEqual(relationGroup.after?.key, "opaque-after")
        XCTAssertEqual(relationGroup.label, "starts after")
        XCTAssertEqual(relationGroup.event, "parked")
        XCTAssertEqual(relationGroup.folded?.alreadyStarted, 6)
        XCTAssertEqual(relationGroup.folded?.waitsFor, 7)
        XCTAssertEqual(relationGroup.copy?.why, "“Send implementation prompt” is parked · Pending, off today's plan")
        XCTAssertNil(pullIn.groups.last?.folded)
        XCTAssertNil(pullIn.groups.last?.project)
    }

    func testMalformedAndOlderRelationFieldsDegradeWithoutDroppingRows() throws {
        let row = try JSONDecoder().decode(
            TaskCompleteUnblocked.self,
            from: Data(#"{"text":"legacy row","relation":17,"offer":{"key":"opaque"}}"#.utf8)
        )
        XCTAssertEqual(row.text, "legacy row")
        XCTAssertEqual(row.offer?.key, "opaque")
        XCTAssertNil(row.relation)

        let held = try JSONDecoder().decode(
            CaptureRelationHeld.self,
            from: Data(#"{"text":"Held","reason":"waits_for","waits_for":"malformed","relation":{}}"#.utf8)
        )
        XCTAssertEqual(held.text, "Held")
        XCTAssertEqual(held.reason, "waits_for")
        XCTAssertNil(held.waitsFor)
        XCTAssertEqual(held.relation?.after, [])

        let pullIn = try JSONDecoder().decode(
            CapturePullIn.self,
            from: Data(#"{"supported":true,"groups":[{"group":"hand_off"}]}"#.utf8)
        )
        XCTAssertEqual(pullIn.groups.first?.group, "hand_off")
        XCTAssertNil(pullIn.copy)
        XCTAssertNil(pullIn.groups.first?.copy)
        XCTAssertNil(pullIn.groups.first?.folded)
        XCTAssertEqual(CapturePullInFolded().alreadyStarted, 0)
        XCTAssertEqual(CapturePullInFolded().waitsFor, 0)
    }

    func testCaptureCompleteSuccessorEffectsPreserveInverseHintWithoutVerdict() throws {
        let direct = #"""
            {"ok":true,"schema_version":1,"cursor":0,"replacement":{"start":0,"end":0},
             "context":"relation_label","candidates":[{"replacement":"starts after","offers_source":true}],
             "relation_successor":{"source":{"path":"agents.md","block_id":"evaluate",
               "text":"Prepare evaluation prompt","status_symbol":" ","status_name":"Ready"},
               "target":{"path":"agents.md","block_id":"implement","text":"Send implementation prompt",
                 "status_symbol":" ","status_name":"Ready"},
               "verdict":"offers","message":"🪢 Offers “Prepare evaluation prompt” when “Send implementation prompt” is parked or done · never blocks"}}
            """#
        let directResponse = try JSONDecoder().decode(CaptureCompletionResponse.self, from: Data(direct.utf8))
        XCTAssertEqual(directResponse.candidates.first?.offersSource, true)
        XCTAssertEqual(directResponse.relationSuccessor?.verdict, "offers")
        XCTAssertEqual(directResponse.relationSuccessor?.source.blockID, "evaluate")

        let inverse = #"""
            {"ok":true,"schema_version":1,"cursor":0,"replacement":{"start":0,"end":0},
             "context":"relation_label","candidates":[],
             "relation_successor":{"source":{"text":"Prepare evaluation prompt"},
               "target":{"text":"Send implementation prompt"},
               "hint":"“starts before” never offers anything · use the inverse relation"}}
            """#
        let inverseResponse = try JSONDecoder().decode(CaptureCompletionResponse.self, from: Data(inverse.utf8))
        XCTAssertNil(inverseResponse.relationSuccessor?.verdict)
        XCTAssertEqual(inverseResponse.relationSuccessor?.hint, "“starts before” never offers anything · use the inverse relation")
    }

    func testOffersSourceSpanAndTaskRoleAreTolerantAndUnknownValuesStayNeutral() throws {
        let span = try JSONDecoder().decode(
            CaptureSpan.self,
            from: Data(#"{"start":0,"end":2,"kind":"relation_label","offers_source":true}"#.utf8)
        )
        let legacySpan = try JSONDecoder().decode(
            CaptureSpan.self,
            from: Data(#"{"start":0,"end":2,"kind":"relation_label"}"#.utf8)
        )
        XCTAssertTrue(span.offersSource)
        XCTAssertFalse(legacySpan.offersSource)

        let taskBlock = try JSONDecoder().decode(
            CaptureTaskBlock.self,
            from: Data(#"{"relative_target":"agents.md","route":"agents","line":1,"roles":["relation_successor","future_role"]}"#.utf8)
        )
        XCTAssertTrue(taskBlock.hasRelationSuccessorRole)
        XCTAssertEqual(taskBlock.roles, ["relation_successor", "future_role"])

        let block = CaptureTaskBlock(
            relativeTarget: "agents.md",
            route: "agents",
            line: 1,
            text: "Parent",
            lines: [CaptureBlockLine(text: "- Prepare evaluation prompt", change: .added, reason: "relation")]
        )
        let presentation = CaptureTaskBlockPresentation(block: block, dryRun: true)
        XCTAssertTrue(presentation.rows.first?.isRelationSuccessor == true)
        let unknown = CaptureTaskBlock(
            relativeTarget: "agents.md",
            route: "agents",
            line: 1,
            text: "Parent",
            lines: [CaptureBlockLine(text: "- Future", change: .added, reason: "future_reason")]
        )
        XCTAssertFalse(CaptureTaskBlockPresentation(block: unknown, dryRun: true).rows.first?.isRelationSuccessor ?? true)
    }
}

private enum FixtureError: Error {
    case expectedSuccess(String)
}
