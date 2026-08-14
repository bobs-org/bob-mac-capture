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

    func testParseResponseDecodesMissingCollectionsAsEmpty() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "Call bank",
              "body": "Call bank",
              "mode": "task"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureParseResponse.self, from: data)

        XCTAssertEqual(decoded.needs, [])
        XCTAssertEqual(decoded.spans, [])
        XCTAssertEqual(decoded.diagnostics, [])
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

    func testCaptureCommandResponseDecodesHeaderlessSingleClipWithOmittedEntries() throws {
        let success = try decodeCaptureSuccess(#"{"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"mac_inbox.md","target":"/tmp/tmp.GQUVrOEvrX/vault/mac_inbox.md","text":"test","task_line":"- [ ] #task test [created::2026-07-15]","kind":"task","created":"2026-07-15","scheduled":null,"placement":"created","clip":{"header":null,"mode":"inline","lines":["\t- hello-clip"],"attachments":[]}}"#)

        XCTAssertEqual(success.clip?.header, nil)
        XCTAssertEqual(success.clip?.mode, "inline")
        XCTAssertEqual(success.clip?.lines, ["\t- hello-clip"])
        XCTAssertEqual(success.clip?.attachments, [])
        XCTAssertEqual(success.clip?.entries, [])
    }

    func testCaptureCommandResponseDecodesHeaderedClipWithOmittedEntries() throws {
        let success = try decodeCaptureSuccess(#"{"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"mac_inbox.md","target":"/tmp/tmp.GQUVrOEvrX/vault/mac_inbox.md","text":"test","task_line":"- [ ] #task test [created::2026-07-15]","kind":"task","created":"2026-07-15","scheduled":null,"placement":"created","clip":{"header":"MYNOTE","mode":"inline","lines":["\t- **MYNOTE:** hello-clip"],"attachments":[]}}"#)

        XCTAssertEqual(success.clip?.header, "MYNOTE")
        XCTAssertEqual(success.clip?.mode, "inline")
        XCTAssertEqual(success.clip?.lines, ["\t- **MYNOTE:** hello-clip"])
        XCTAssertEqual(success.clip?.entries, [])
    }

    func testCaptureCommandResponseDecodesAttachmentClipWithOmittedEntries() throws {
        let success = try decodeCaptureSuccess(#"{"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"mac_inbox.md","target":"/tmp/tmp.GQUVrOEvrX/vault/mac_inbox.md","text":"test","task_line":"- [ ] #task test [created::2026-07-15]","kind":"task","created":"2026-07-15","scheduled":null,"placement":"created","clip":{"header":null,"mode":"attachments","lines":["\t- ![[img/shot.png|400]]"],"attachments":[{"source":"/tmp/tmp.GQUVrOEvrX/shot.png","saved":"img/shot.png","kind":"image","reused":false}]}}"#)

        XCTAssertEqual(success.clip?.mode, "attachments")
        XCTAssertEqual(success.clip?.lines, ["\t- ![[img/shot.png|400]]"])
        XCTAssertEqual(success.clip?.attachments, [
            CaptureAttachmentOutput(
                source: "/tmp/tmp.GQUVrOEvrX/shot.png",
                saved: "img/shot.png",
                kind: "image",
                reused: false
            ),
        ])
        XCTAssertEqual(success.clip?.entries, [])
    }

    func testCaptureCommandResponseDecodesSnippetClipWithOmittedEntries() throws {
        let success = try decodeCaptureSuccess(#"{"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"mac_inbox.md","target":"/tmp/tmp.GQUVrOEvrX/vault/mac_inbox.md","text":"test","task_line":"- [ ] #task test [created::2026-07-15]","kind":"task","created":"2026-07-15","scheduled":null,"placement":"created","clip":{"header":null,"mode":"snippet","lines":["\t- [[file/clip-20260715-131415-heading]]"],"attachments":[],"snippet":"file/clip-20260715-131415-heading.md"}}"#)

        XCTAssertEqual(success.clip?.mode, "snippet")
        XCTAssertEqual(success.clip?.snippet, "file/clip-20260715-131415-heading.md")
        XCTAssertEqual(success.clip?.entries, [])
    }

    func testCaptureCommandResponseDecodesHistoryClipWithNestedOmittedEntries() throws {
        let success = try decodeCaptureSuccess(#"{"ok":true,"dry_run":true,"routed":false,"route":null,"route_label":"","relative_target":"mac_inbox.md","target":"/tmp/tmp.XA4h1kbsUm/vault/mac_inbox.md","text":"test","task_line":"- [ ] #task test [created::2026-07-15]","kind":"task","created":"2026-07-15","scheduled":null,"placement":"created","clip":{"header":null,"mode":"history","lines":["\t- hello-clip","\t- older one","\t- older two"],"attachments":[],"entries":[{"header":null,"mode":"inline","lines":["\t- hello-clip"],"attachments":[]},{"header":null,"mode":"lines","lines":["\t- older one","\t- older two"],"attachments":[]}]}}"#)

        XCTAssertEqual(success.clip?.mode, "history")
        XCTAssertEqual(success.clip?.entries.count, 2)
        XCTAssertEqual(success.clip?.entries[0].lines, ["\t- hello-clip"])
        XCTAssertEqual(success.clip?.entries[0].entries, [])
        XCTAssertEqual(success.clip?.entries[1].mode, "lines")
        XCTAssertEqual(success.clip?.entries[1].entries, [])
    }

    func testPreviewBlockLinesOrderAuthoredChildrenClipThenScheduleLog() throws {
        let data = Data(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"work","route_label":"work.md",
             "relative_target":"work.md","target":"/home/bryan/bob/work.md",
             "text":"Prepare the launch review",
             "task_line":"- [ ] #task Prepare the launch review [created::2026-08-14] [priority::high] [scheduled::2026-08-18]",
             "kind":"task","created":"2026-08-14","scheduled":"2026-08-18","placement":"inserted",
             "sub_bullets":["  - Confirm the rollout owner","  - Attach the final checklist"],
             "clip":{"header":null,"mode":"lines","lines":["  - clipped one","  - clipped two"],
                     "attachments":[],"entries":[]},
             "schedule_log":{"reason":"p:1 roll","lines":["  - **SCHEDULE LOG**",
                                                          "    - _2026-08-18_ — p:1 roll"]}}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertEqual(
            success.previewBlockLines,
            [
                success.taskLine,
                "  - Confirm the rollout owner",
                "  - Attach the final checklist",
                "  - clipped one",
                "  - clipped two",
                "  - **SCHEDULE LOG**",
                "    - _2026-08-18_ — p:1 roll",
            ]
        )
    }

    func testPreviewBlockLinesIsJustTheTaskLineForAPlainCapture() throws {
        let data = Data(
            """
            {"ok":true,"dry_run":true,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/home/bryan/bob/cash.md","text":"Call bank",
             "task_line":"- [ ] #task Call bank [created::2026-08-14]","kind":"task",
             "created":"2026-08-14","scheduled":null,"placement":"inserted"}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertEqual(success.previewBlockLines, [success.taskLine])
    }

    func testPreviewBlockLinesOmitsClipForNoClipLivePreview() {
        // Continuous live preview runs `--no-clip`, so `clip` is absent while the same
        // draft's explicit Preview resolves it. Only the schedule log survives.
        let success = CaptureCommandSuccess(
            ok: true,
            dryRun: true,
            routed: true,
            routeLabel: "work.md",
            relativeTarget: "work.md",
            target: "/home/bryan/bob/work.md",
            text: "Prepare the launch review",
            taskLine: "- [ ] #task Prepare the launch review [created::2026-08-14]",
            kind: "task",
            created: "2026-08-14",
            placement: "inserted",
            subBullets: ["\t- Confirm the rollout owner"],
            scheduleLog: CaptureScheduleLog(
                reason: "p:1 roll",
                lines: ["\t- **SCHEDULE LOG**"]
            )
        )

        XCTAssertEqual(
            success.previewBlockLines,
            [
                "- [ ] #task Prepare the launch review [created::2026-08-14]",
                "\t- Confirm the rollout owner",
                "\t- **SCHEDULE LOG**",
            ]
        )
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

    func testCompletionResponseDecodesMissingCandidatesAsEmpty() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "cursor": 6,
              "replacement": { "start": 6, "end": 6 },
              "context": "route"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)

        XCTAssertEqual(decoded.candidates, [])
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
        let target = try XCTUnwrap(plain.range(of: "caf"))
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

    private enum CaptureFixtureError: Error {
        case expectedSuccess
    }

    private func decodeCaptureSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(json.utf8))
        guard case .success(let success) = decoded else {
            throw CaptureFixtureError.expectedSuccess
        }
        return success
    }
}
