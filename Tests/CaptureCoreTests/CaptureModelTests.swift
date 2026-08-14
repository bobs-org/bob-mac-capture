import XCTest

@testable import CaptureCore

final class CaptureModelTests: XCTestCase {
    func testParseResponseDecodesUnknownAdditiveKeys() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "Call bank @Cash^",
              "body": "Call bank",
              "mode": "incomplete",
              "route": "cash",
              "needs": ["task"],
              "spans": [
                { "start": 10, "end": 15, "kind": "sub_bullet_route", "future": true }
              ],
              "diagnostics": [],
              "future_key": "ignored"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureParseResponse.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.spans, [CaptureSpan(start: 10, end: 15, kind: "sub_bullet_route")])
        XCTAssertEqual(decoded.needs, ["task"])
    }

    func testBoundedProcessTextPreservesUtf8Boundary() {
        let text = String(repeating: "a", count: 4) + "é" + String(repeating: "b", count: 10)
        let bounded = boundedProcessText(text, limit: 5)

        XCTAssertTrue(bounded.hasSuffix("..."))
        XCTAssertFalse(bounded.contains("\u{FFFD}"))
    }
}
