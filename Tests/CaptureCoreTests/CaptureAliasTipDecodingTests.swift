import Foundation
import XCTest

@testable import CaptureCore

final class CaptureAliasTipDecodingTests: XCTestCase {
    private func decode(_ json: String) throws -> CaptureRewriteResponse {
        try JSONDecoder().decode(CaptureRewriteResponse.self, from: Data(json.utf8))
    }

    private func tipJSON(where phrase: String? = "after a word") -> String {
        let whereFragment: String
        if let phrase {
            whereFragment = ", \"where\": \"\(phrase)\""
        } else {
            whereFragment = ""
        }
        return """
            {"ok": true, "schema_version": 1, \
            "input": "Buy milk @", "text": "Buy milk @", \
            "changed": false, "cursor": 10, "edits": [], \
            "sigil_alias_tip": {"id": "route_after_text", \
            "sigil": "@", "keys": ["."], \
            "range": {"start": 9, "end": 10}\(whereFragment)}}
            """
    }

    func testTipObjectDecodesWithWherePhrase() throws {
        let response = try decode(tipJSON())
        XCTAssertTrue(response.reportsSigilAliasTips)
        XCTAssertEqual(
            response.sigilAliasTip,
            CaptureSigilAliasTip(
                id: "route_after_text",
                sigil: "@",
                keys: ["."],
                range: CaptureRange(start: 9, end: 10),
                positionPhrase: "after a word"
            )
        )
    }

    func testTipWithoutWhereDecodesNilPhrase() throws {
        let response = try decode(tipJSON(where: nil))
        XCTAssertTrue(response.reportsSigilAliasTips)
        XCTAssertEqual(response.sigilAliasTip?.positionPhrase, nil)
    }

    func testExplicitNullMarksTipCapableBob() throws {
        let response = try decode(
            """
            {"ok": true, "schema_version": 1, \
            "input": "Buy milk @", "text": "Buy milk @", \
            "changed": false, "cursor": 10, "edits": [], \
            "sigil_alias_tip": null}
            """
        )
        XCTAssertTrue(response.reportsSigilAliasTips)
        XCTAssertNil(response.sigilAliasTip)
    }

    func testAbsentKeyMarksLegacyBob() throws {
        let response = try decode(
            """
            {"ok": true, "schema_version": 1, \
            "input": "Buy milk @", "text": "Buy milk @", \
            "changed": false, "cursor": 10, "edits": []}
            """
        )
        XCTAssertFalse(response.reportsSigilAliasTips)
        XCTAssertNil(response.sigilAliasTip)
    }

    func testAliasObjectDecodes() throws {
        let response = try decode(
            """
            {"ok": true, "schema_version": 1, \
            "input": "Buy milk .", "text": "Buy milk @", \
            "changed": true, "cursor": 10, "rule": "expand_sigil_alias", \
            "edits": [{"range": {"start": 9, "end": 10}, "replacement": "@"}], \
            "alias": {"id": "route_after_text", "key": ".", "sigil": "@"}}
            """
        )
        XCTAssertEqual(
            response.alias,
            CaptureRewriteAlias(id: "route_after_text", key: ".", sigil: "@")
        )
        XCTAssertFalse(response.reportsSigilAliasTips)
    }

    func testUnknownTipIDDecodesAndMapsToNilLesson() throws {
        let response = try decode(
            """
            {"ok": true, "schema_version": 1, \
            "input": "Buy milk @", "text": "Buy milk @", \
            "changed": false, "cursor": 10, "edits": [], \
            "sigil_alias_tip": {"id": "future_lesson", \
            "sigil": "@", "keys": ["."], \
            "range": {"start": 9, "end": 10}}}
            """
        )
        XCTAssertTrue(response.reportsSigilAliasTips)
        XCTAssertEqual(response.sigilAliasTip?.id, "future_lesson")
        XCTAssertNil(CaptureAliasLesson.host(for: "future_lesson"))
    }

    func testExplicitNullRoundTripsThroughEncoder() throws {
        let response = CaptureRewriteResponse(
            ok: true,
            schemaVersion: 1,
            input: "Buy milk @",
            text: "Buy milk @",
            changed: false,
            cursor: 10,
            reportsSigilAliasTips: true
        )
        let data = try JSONEncoder().encode(response)
        let raw = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(raw.contains("\"sigil_alias_tip\":null"))
        let decoded = try JSONDecoder().decode(CaptureRewriteResponse.self, from: data)
        XCTAssertTrue(decoded.reportsSigilAliasTips)
        XCTAssertNil(decoded.sigilAliasTip)
    }

    func testLessonHosts() {
        XCTAssertEqual(
            CaptureAliasLesson.host(for: "route_after_text"),
            .completionList
        )
        XCTAssertEqual(CaptureAliasLesson.host(for: "hash_menu"), .completionList)
        XCTAssertEqual(
            CaptureAliasLesson.host(for: "directive_menu"),
            .completionList
        )
        XCTAssertEqual(
            CaptureAliasLesson.host(for: "block_id_after_route"),
            .picker
        )
        XCTAssertEqual(CaptureAliasLesson.host(for: "relation"), .picker)
        XCTAssertEqual(CaptureAliasLesson.host(for: "dependency"), .picker)
        XCTAssertEqual(CaptureAliasLesson.host(for: "blocked_task"), .picker)
        XCTAssertTrue(CaptureAliasLesson.isKnown(id: "parent_task"))
        XCTAssertFalse(CaptureAliasLesson.isKnown(id: "nope"))
    }
}
