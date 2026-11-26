import Foundation
import XCTest

@testable import CaptureCore

final class CaptureRewriteResponseTests: XCTestCase {
    func testCoveringEditRejectsInvalidEditLists() {
        let unsorted = response(
            input: "abcdef",
            text: "abXdYf",
            edits: [edit(4, 5, "Y"), edit(2, 3, "X")]
        )
        let overlapping = response(
            input: "abcdef",
            text: "aXf",
            edits: [edit(1, 4, "X"), edit(3, 5, "")]
        )
        let outOfRange = response(
            input: "abc",
            text: "abc",
            edits: [edit(0, 4, "")]
        )
        let nonBoundary = response(
            input: "🧪",
            text: "x",
            edits: [edit(1, 4, "x")]
        )
        let nonReproducing = response(
            input: "abc",
            text: "different",
            edits: [edit(0, 1, "x")]
        )

        for value in [unsorted, overlapping, outOfRange, nonBoundary, nonReproducing] {
            XCTAssertNil(value.coveringEdit(in: value.input))
        }
    }

    func testDrawerLoneStarReplyDecodesAsSingleInsertion() throws {
        let response = try drawerFixtureResponse("drawer-rewrite-new-task.json")
        XCTAssertEqual(response.rule, "expand_drawer_marker")
        XCTAssertEqual(response.cursor, 20)
        XCTAssertEqual(response.edits.count, 1)
        let covering = try XCTUnwrap(response.coveringEdit(in: response.input))
        XCTAssertEqual(covering.range, CaptureRange(start: 19, end: 19))
        XCTAssertEqual(covering.replacement, "***")
    }

    func testDrawerAutopairedReplyDecodesAsSingleInsertion() throws {
        let response = try drawerFixtureResponse("drawer-rewrite-autopaired.json")
        XCTAssertEqual(response.rule, "expand_drawer_marker")
        XCTAssertEqual(response.input, "Prepare release\n- **")
        XCTAssertEqual(response.text, "Prepare release\n- ****")
        XCTAssertEqual(response.cursor, 21)
        let covering = try XCTUnwrap(response.coveringEdit(in: response.input))
        XCTAssertEqual(covering.range, CaptureRange(start: 19, end: 19))
        XCTAssertEqual(covering.replacement, "**")
    }

    func testDrawerAstralReplyKeepsByteCursor() throws {
        let response = try drawerFixtureResponse("drawer-rewrite-astral.json")
        XCTAssertEqual(response.input, "Prepare 🚀 release\n- *")
        XCTAssertEqual(response.text, "Prepare 🚀 release\n- ****")
        XCTAssertEqual(response.cursor, 25)
        XCTAssertNotNil(response.coveringEdit(in: response.input))
    }

    func testDrawerLiteralRepliesStayUnchanged() throws {
        for name in [
            "drawer-rewrite-nested-literal.json",
            "drawer-rewrite-notebook-list-literal.json",
            "drawer-rewrite-midline-literal.json",
            "drawer-rewrite-checkbox-literal.json",
            "drawer-rewrite-trailing-dep-literal.json",
        ] {
            let response = try drawerFixtureResponse(name)
            XCTAssertFalse(response.changed, name)
            XCTAssertEqual(response.text, response.input, name)
            XCTAssertEqual(response.edits, [], name)
            XCTAssertNil(response.rule, name)
        }
    }

    private func drawerFixtureResponse(_ name: String) throws -> CaptureRewriteResponse {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(
            contentsOf: fixtures.appendingPathComponent(name),
            encoding: .utf8
        )
        return try JSONDecoder().decode(CaptureRewriteResponse.self, from: Data(text.utf8))
    }

    private func response(
        input: String,
        text: String,
        edits: [CaptureRewriteEdit]
    ) -> CaptureRewriteResponse {
        CaptureRewriteResponse(
            ok: true,
            schemaVersion: 1,
            input: input,
            text: text,
            changed: true,
            edits: edits
        )
    }

    private func edit(_ start: Int, _ end: Int, _ replacement: String) -> CaptureRewriteEdit {
        CaptureRewriteEdit(
            range: CaptureRange(start: start, end: end),
            replacement: replacement
        )
    }
}
