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
        XCTAssertEqual(decoded.subBullets, [])
    }

    func testParseResponseDecodesSubBulletsWhenPresent() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "Prepare launch\\n- confirm owner\\n- attach checklist",
              "body": "Prepare launch",
              "mode": "task",
              "needs": [],
              "spans": [],
              "diagnostics": [],
              "sub_bullets": ["confirm owner", "attach checklist"]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureParseResponse.self, from: data)

        XCTAssertEqual(decoded.subBullets, ["confirm owner", "attach checklist"])
    }

    func testParseResponseDecodesEmptySubBulletsArray() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "Prepare launch",
              "body": "Prepare launch",
              "mode": "task",
              "needs": [],
              "spans": [],
              "diagnostics": [],
              "sub_bullets": []
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureParseResponse.self, from: data)

        XCTAssertEqual(decoded.subBullets, [])
    }

    func testCaptureCommandResponseDecodesRealSuccessShapeWithNoSchemaVersion() throws {
        let data = Data(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/home/bryan/bob/cash.md","text":"Call bank",
             "task_line":"- [ ] #task Call bank [created::2026-08-13]","kind":"task",
             "created":"2026-08-13","scheduled":null,"placement":"inserted","future_key":"ignored"}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertTrue(decoded.ok)
        XCTAssertEqual(success.routeLabel, "cash.md")
        XCTAssertEqual(success.target, "/home/bryan/bob/cash.md")
        XCTAssertNil(success.clip)
        XCTAssertNil(success.scheduleLog)
        XCTAssertEqual(success.subBullets, [])
    }

    func testCaptureCommandResponseDecodesSubBulletsWhenPresent() throws {
        let data = Data(
            """
            {"ok":true,"dry_run":false,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/home/bryan/bob/cash.md","text":"Prepare launch",
             "task_line":"- [ ] #task Prepare launch [created::2026-08-14]","kind":"task",
             "created":"2026-08-14","scheduled":null,"placement":"inserted",
             "sub_bullets":["  - confirm owner","  - attach checklist"]}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertEqual(success.subBullets, ["  - confirm owner", "  - attach checklist"])
    }

    func testCaptureCommandResponseDecodesUnknownAdditiveTopLevelKeys() throws {
        let data = Data(
            """
            {"ok":true,"dry_run":false,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/home/bryan/bob/cash.md","text":"Prepare launch",
             "task_line":"- [ ] #task Prepare launch [created::2026-08-14]","kind":"task",
             "created":"2026-08-14","scheduled":null,"placement":"inserted",
             "future_field":{"nested":true}}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertEqual(success.subBullets, [])
    }

    func testCaptureCommandResponseDecodesRealFailureShape() throws {
        let data = Data(
            #"{"error":"clipboard command xclip exited with 1","ok":false}"#.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .failure(let failure) = decoded else {
            return XCTFail("Expected a failed response")
        }
        XCTAssertFalse(decoded.ok)
        XCTAssertEqual(failure.error, "clipboard command xclip exited with 1")
    }

    func testObsidianOpenURLRoundTripsAbsolutePath() throws {
        let path = "/Users/bryan/bob/cash & notes #1.md"
        let url = try XCTUnwrap(ObsidianOpenURL.url(forAbsolutePath: path))

        XCTAssertEqual(url.scheme, "obsidian")
        XCTAssertEqual(url.host, "open")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let decodedPath = components.queryItems?.first { $0.name == "path" }?.value
        XCTAssertEqual(decodedPath, path)
    }

    func testObsidianOpenURLReturnsNilForEmptyPath() {
        XCTAssertNil(ObsidianOpenURL.url(forAbsolutePath: ""))
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

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertEqual(success.taskLine, "- [ ] #task buy milk [created::2026-08-14]")
        XCTAssertEqual(success.routeLabel, "mac_inbox.md")
        XCTAssertEqual(success.placement, "created")
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

    func testCompletionResponseDecodesWikilinkMetadataWarningsAndCursorAfter() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "cursor": 4,
              "replacement": { "start": 2, "end": 4 },
              "context": "wikilink_note",
              "candidates": [
                {
                  "replacement": "Artificial Intelligence|AI]]",
                  "cursor_after": 30,
                  "path": "Artificial Intelligence.md",
                  "name": "Artificial Intelligence",
                  "alias": "AI",
                  "match_kind": "exact_alias",
                  "future_key": true
                }
              ],
              "warnings": ["skipped unreadable note"],
              "future_key": "ignored"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)

        XCTAssertEqual(decoded.context, "wikilink_note")
        XCTAssertEqual(decoded.warnings, ["skipped unreadable note"])
        XCTAssertEqual(decoded.candidates.first?.cursorAfter, 30)
        XCTAssertEqual(decoded.candidates.first?.path, "Artificial Intelligence.md")
        XCTAssertEqual(decoded.candidates.first?.alias, "AI")
        XCTAssertEqual(decoded.candidates.first?.matchKind, "exact_alias")
    }

    func testCompletionResponseDecodesWikilinkHeadingAndBlockMetadata() throws {
        let headingData = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "cursor": 12,
              "replacement": { "start": 10, "end": 12 },
              "context": "wikilink_heading",
              "candidates": [
                {
                  "replacement": "Design]]",
                  "cursor_after": 18,
                  "path": "sase.md",
                  "heading": "Design",
                  "level": 1,
                  "match_kind": "prefix"
                }
              ]
            }
            """.utf8
        )
        let blockData = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "cursor": 12,
              "replacement": { "start": 10, "end": 12 },
              "context": "wikilink_block",
              "candidates": [
                {
                  "replacement": "^next-step]]",
                  "cursor_after": 22,
                  "path": "sase.md",
                  "block_id": "next-step",
                  "preview": "Plan the next step",
                  "match_kind": "prefix"
                }
              ]
            }
            """.utf8
        )

        let heading = try JSONDecoder().decode(CaptureCompletionResponse.self, from: headingData)
        let block = try JSONDecoder().decode(CaptureCompletionResponse.self, from: blockData)

        XCTAssertEqual(heading.candidates.first?.heading, "Design")
        XCTAssertEqual(heading.candidates.first?.level, 1)
        XCTAssertEqual(block.candidates.first?.blockID, "next-step")
        XCTAssertEqual(block.candidates.first?.preview, "Plan the next step")
    }

    func testAttributedStringUtf8OffsetRoundTripsCollapsedCaret() throws {
        let text = AttributedString("a 🧪 cafe\u{301}")
        let plain = String(text.characters)
        let target = try XCTUnwrap(plain.range(of: "cafe"))
        let offset = plain[..<target.lowerBound].utf8.count

        let index = try XCTUnwrap(attributedStringIndex(in: text, utf8Offset: offset))

        XCTAssertEqual(utf8Offset(in: text, at: index), offset)
        XCTAssertNil(attributedStringIndex(in: text, utf8Offset: 3))
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
