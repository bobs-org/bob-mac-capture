import Foundation
import XCTest

@testable import CaptureCore

final class CaptureCaretGotoDecodingTests: XCTestCase {
    func testFoundCaretGotoAndSharedRowDecode() throws {
        let json = #"""
            {
              "ok": true,
              "schema_version": 1,
              "grammar": 31,
              "input": "@bob^focus",
              "body": "",
              "mode": "task_goto",
              "route": "bob",
              "block_id": "focus",
              "needs": [],
              "goto": {
                "status": "found",
                "route": "bob",
                "block_id": "focus",
                "note_path": "bob.md",
                "target": "/vault/bob.md",
                "archived": false,
                "landing": {
                  "block_id": "focus",
                  "note_path": "bob.md",
                  "target": "/vault/bob.md",
                  "line": 42,
                  "ref": "42:abcd1234",
                  "target_kind": "task",
                  "text": "Review focus",
                  "status_symbol": "*",
                  "status_name": "Next",
                  "status_type": "TODO",
                  "section": "Tasks",
                  "closed": null
                }
              }
            }
            """#

        let parse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(json.utf8)
        )
        let goto = try XCTUnwrap(parse.goto)
        let landing = try XCTUnwrap(goto.landing)
        XCTAssertEqual(parse.mode, "task_goto")
        XCTAssertEqual(goto.status, .found)
        XCTAssertEqual(goto.route, "bob")
        XCTAssertEqual(goto.blockID, "focus")
        XCTAssertFalse(goto.archived)
        XCTAssertEqual(landing.line, 42)
        XCTAssertEqual(landing.ref, "42:abcd1234")
        XCTAssertEqual(landing.statusName, "Next")
        XCTAssertFalse(landing.archived)
    }

    func testOlderParseWithoutGotoAndUnknownStatusDecodeTolerantly() throws {
        let old = #"{"ok":true,"schema_version":1,"input":"@bob^x","body":"","mode":"task"}"#
        let oldParse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(old.utf8)
        )
        XCTAssertNil(oldParse.goto)

        let future = #"{"ok":true,"schema_version":1,"input":"@bob^x","body":"","mode":"task_goto","goto":{"status":"future_state","route":"bob","block_id":"x"}}"#
        let futureParse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(future.utf8)
        )
        XCTAssertEqual(futureParse.goto?.status, .unknown)
    }

    func testMalformedOptionalGotoDoesNotDiscardParse() throws {
        let json = #"{"ok":true,"schema_version":1,"input":"@bob^x","body":"","mode":"task_goto","goto":{"status":false}}"#
        let parse = try JSONDecoder().decode(
            CaptureParseResponse.self,
            from: Data(json.utf8)
        )
        XCTAssertNil(parse.goto)
        XCTAssertEqual(parse.mode, "task_goto")
    }
}
