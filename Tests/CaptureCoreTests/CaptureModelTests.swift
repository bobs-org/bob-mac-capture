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

    func testCaptureTargetsResponseDecodesCurrentBobCliShape() throws {
        let data = Data(
            """
            {
              "ok": true,
              "bob_dir": "/tmp/bob",
              "count": 1,
              "targets": [
                {
                  "route": "cash",
                  "name": "cash",
                  "label": "cash.md",
                  "kind": "area",
                  "is_default": false,
                  "status": null,
                  "relative_path": "cash.md"
                }
              ]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureTargetsResponse.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.bobDirectory, "/tmp/bob")
        XCTAssertEqual(decoded.targets.first?.label, "cash.md")
        XCTAssertEqual(decoded.targets.first?.kind, "area")
    }

    func testCaptureCommandResponseDecodesCurrentDryRunShape() throws {
        let data = Data(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": true,
              "route": "mac_inbox",
              "route_label": "mac_inbox.md",
              "relative_target": "mac_inbox.md",
              "target": "/tmp/bob/mac_inbox.md",
              "text": "buy milk",
              "task_line": "- [ ] #task buy milk [created::2026-08-14]",
              "kind": "task",
              "created": "2026-08-14",
              "scheduled": null,
              "placement": "created"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        XCTAssertEqual(decoded.schemaVersion, 1)
        XCTAssertEqual(decoded.taskLine, "- [ ] #task buy milk [created::2026-08-14]")
        XCTAssertEqual(decoded.routeLabel, "mac_inbox.md")
        XCTAssertEqual(decoded.placement, "created")
    }

    func testCompletionResponseDecodesRouteAndTaskCandidates() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "cursor": 8,
              "replacement": { "start": 6, "end": 8 },
              "context": "task",
              "candidates": [
                {
                  "replacement": "goog-exit",
                  "ref": "Tasks.md#^goog-exit",
                  "block_id": "goog-exit",
                  "status_symbol": "*",
                  "status_name": "in-progress",
                  "status_type": "TODO",
                  "text": "Finish Google Exit Packet!",
                  "section": "Tasks",
                  "depth": 0,
                  "child_count": 2
                }
              ]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)

        XCTAssertEqual(decoded.context, "task")
        XCTAssertEqual(decoded.replacement, CaptureRange(start: 6, end: 8))
        XCTAssertEqual(decoded.candidates.first?.taskRef, "Tasks.md#^goog-exit")
        XCTAssertEqual(decoded.candidates.first?.childCount, 2)
    }

    func testValidatedSpanRangesRejectMalformedUtf8AndOverlaps() {
        let text = "Call 🧪 @Cash"
        let routeStart = text.utf8.count - "@Cash".utf8.count
        let routeEnd = text.utf8.count

        let valid = validatedSpanRanges(
            in: text,
            spans: [CaptureSpan(start: routeStart, end: routeEnd, kind: "route")]
        )
        XCTAssertEqual(valid?.first?.span.kind, "route")
        if let first = valid?.first {
            XCTAssertEqual(String(text[first.range]), "@Cash")
        } else {
            XCTFail("Expected a valid route span")
        }

        XCTAssertNil(validatedSpanRanges(
            in: text,
            spans: [CaptureSpan(start: 6, end: 7, kind: "route")]
        ))
        XCTAssertNil(validatedSpanRanges(
            in: text,
            spans: [
                CaptureSpan(start: routeStart, end: routeEnd, kind: "route"),
                CaptureSpan(start: routeStart + 1, end: routeEnd, kind: "route"),
            ]
        ))
    }
}
