import XCTest

@testable import CaptureCore

final class CaptureModelTests: XCTestCase {
    func testParseResponseDecodesUnknownAdditiveKeys() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "Call bank @Cash+",
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
        XCTAssertEqual(
            decoded.spans,
            [CaptureSpan(start: 10, end: 15, kind: "sub_bullet_route")]
        )
        XCTAssertEqual(decoded.needs, ["task"])
        XCTAssertEqual(decoded.subBullets, [])
        XCTAssertEqual(decoded.subBulletDepths, [])
    }

    func testParseResponseDecodesSubBulletsAndDepthsWhenPresent() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "Prepare launch\\n- confirm owner\\n  - text owner\\n- attach checklist",
              "body": "Prepare launch",
              "mode": "task",
              "needs": [],
              "spans": [],
              "diagnostics": [],
              "sub_bullets": ["confirm owner", "text owner", "attach checklist"],
              "sub_bullet_depths": [1, 2, 1]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureParseResponse.self, from: data)

        XCTAssertEqual(
            decoded.subBullets,
            ["confirm owner", "text owner", "attach checklist"]
        )
        XCTAssertEqual(decoded.subBulletDepths, [1, 2, 1])
    }

    func testParseResponseSynthesizesDepthOneForOlderSubBulletResponses() throws {
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
        XCTAssertEqual(decoded.subBulletDepths, [1, 1])
    }

    func testParseResponseIgnoresMismatchedSubBulletDepthsSafely() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "Prepare launch\\n- confirm owner\\n  - text owner",
              "body": "Prepare launch",
              "mode": "task",
              "needs": [],
              "spans": [],
              "diagnostics": [],
              "sub_bullets": ["confirm owner", "text owner"],
              "sub_bullet_depths": [1]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureParseResponse.self, from: data)

        XCTAssertEqual(decoded.subBullets, ["confirm owner", "text owner"])
        XCTAssertEqual(decoded.subBulletDepths, [1, 1])
    }

    func testParseResponseDecodesBatchItemsWhenPresent() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "First @cash\\n\\nSecond @notes#Ideas",
              "body": "First",
              "mode": "task",
              "route": "cash",
              "needs": [],
              "spans": [],
              "diagnostics": [],
              "items": [
                {
                  "index": 1,
                  "range": { "start": 0, "end": 11 },
                  "line_start": 1,
                  "line_end": 1,
                  "body": "First",
                  "mode": "task",
                  "route": "cash",
                  "needs": []
                },
                {
                  "index": 2,
                  "range": { "start": 13, "end": 32 },
                  "line_start": 3,
                  "line_end": 3,
                  "body": "Second",
                  "mode": "bullet",
                  "route": "notes",
                  "section": "Ideas",
                  "needs": [],
                  "sub_bullets": ["nested"],
                  "sub_bullet_depths": [2]
                }
              ]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureParseResponse.self, from: data)

        XCTAssertEqual(decoded.items.count, 2)
        XCTAssertEqual(decoded.items[0].range, CaptureRange(start: 0, end: 11))
        XCTAssertEqual(decoded.items[0].lineStart, 1)
        XCTAssertEqual(decoded.items[1].mode, "bullet")
        XCTAssertEqual(decoded.items[1].section, "Ideas")
        XCTAssertEqual(decoded.items[1].subBullets, ["nested"])
        XCTAssertEqual(decoded.items[1].subBulletDepths, [2])
    }

    func testParseResponseDecodesTaskBlockIDMarkerAdditions() throws {
        let data = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "input": "idea @ma^new-id",
              "body": "idea",
              "mode": "task",
              "route": "ma",
              "block_id": "new-id",
              "needs": [],
              "spans": [
                { "start": 5, "end": 8, "kind": "task_block_id_route" },
                { "start": 9, "end": 15, "kind": "task_block_id" }
              ],
              "diagnostics": []
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureParseResponse.self, from: data)

        XCTAssertEqual(decoded.mode, "task")
        XCTAssertEqual(decoded.route, "ma")
        XCTAssertEqual(decoded.blockID, "new-id")
        XCTAssertEqual(decoded.spans.map(\.kind), ["task_block_id_route", "task_block_id"])
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
        XCTAssertEqual(decoded.subBulletDepths, [])
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
        XCTAssertEqual(decoded.subBullets, [])
        XCTAssertEqual(decoded.subBulletDepths, [])
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
        XCTAssertEqual(success.normalizedCaptures.count, 1)
    }

    func testCaptureCommandResponseDecodesOrderedMultiCaptureArray() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": "cash",
              "route_label": "cash.md",
              "relative_target": "cash.md",
              "target": "/tmp/bob/cash.md",
              "text": "First",
              "task_line": "- [ ] #task First [created::2026-08-14]",
              "kind": "task",
              "created": "2026-08-14",
              "scheduled": null,
              "placement": "inserted",
              "captures": [
                {
                  "ok": true,
                  "dry_run": false,
                  "routed": true,
                  "route": "cash",
                  "route_label": "cash.md",
                  "relative_target": "cash.md",
                  "target": "/tmp/bob/cash.md",
                  "text": "First",
                  "task_line": "- [ ] #task First [created::2026-08-14]",
                  "kind": "task",
                  "created": "2026-08-14",
                  "scheduled": null,
                  "placement": "inserted"
                },
                {
                  "ok": true,
                  "dry_run": false,
                  "routed": true,
                  "route": "notes",
                  "route_label": "notes.md",
                  "relative_target": "notes.md",
                  "target": "/tmp/bob/notes.md",
                  "text": "Second",
                  "task_line": "- Second",
                  "kind": "bullet",
                  "created": "2026-08-14",
                  "scheduled": null,
                  "placement": "appended",
                  "sub_bullets": ["  - nested detail"]
                }
              ]
            }
            """
        )

        XCTAssertEqual(success.routeLabel, "cash.md")
        XCTAssertEqual(success.captures.map(\.text), ["First", "Second"])
        XCTAssertEqual(success.normalizedCaptures.map(\.relativeTarget), ["cash.md", "notes.md"])
        XCTAssertEqual(success.normalizedCaptures[1].previewBlockLines, ["- Second", "  - nested detail"])
    }

    func testMalformedMultiCaptureArrayFailsDecode() {
        let data = Data(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": "cash",
              "route_label": "cash.md",
              "relative_target": "cash.md",
              "target": "/tmp/bob/cash.md",
              "text": "First",
              "task_line": "- [ ] #task First [created::2026-08-14]",
              "kind": "task",
              "created": "2026-08-14",
              "scheduled": null,
              "placement": "inserted",
              "captures": [
                { "ok": true, "dry_run": false }
              ]
            }
            """.utf8
        )

        XCTAssertThrowsError(try JSONDecoder().decode(CaptureCommandResponse.self, from: data))
    }

    func testCaptureCommandResponseDecodesRenderedNestedSubBulletsWhenPresent() throws {
        let data = Data(
            """
            {"ok":true,"dry_run":false,"routed":true,"route":"cash","route_label":"cash.md",
             "relative_target":"cash.md","target":"/home/bryan/bob/cash.md","text":"Prepare launch",
             "task_line":"- [ ] #task Prepare launch [created::2026-08-14]","kind":"task",
             "created":"2026-08-14","scheduled":null,"placement":"inserted",
             "sub_bullets":["  - confirm owner","    - text owner","  - attach checklist",
                            "    - verify links"]}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertEqual(success.subBullets, [
            "  - confirm owner",
            "    - text owner",
            "  - attach checklist",
            "    - verify links",
        ])
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
             "sub_bullets":["  - Confirm the rollout owner",
                            "    - Text the owner",
                            "  - Attach the final checklist",
                            "    - Verify the links"],
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
                "    - Text the owner",
                "  - Attach the final checklist",
                "    - Verify the links",
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
        XCTAssertEqual(success.normalizedCaptures.map(\.text), ["Call bank"])
    }

    func testCaptureCommandSuccessNormalizesOrderedMultiCaptureArray() throws {
        let data = Data(
            """
            {"ok":true,"dry_run":false,"routed":true,"route":"work","route_label":"work.md",
             "relative_target":"work.md","target":"/home/bryan/bob/work.md",
             "text":"Ship release","task_line":"- [ ] #task Ship release [created::2026-08-14]",
             "kind":"task","created":"2026-08-14","scheduled":null,"placement":"inserted",
             "captures":[
               {"ok":true,"dry_run":false,"routed":true,"route":"work","route_label":"work.md",
                "relative_target":"work.md","target":"/home/bryan/bob/work.md",
                "text":"Ship release","task_line":"- [ ] #task Ship release [created::2026-08-14]",
                "kind":"task","created":"2026-08-14","scheduled":null,"placement":"inserted"},
               {"ok":true,"dry_run":false,"routed":true,"route":"ideas","route_label":"ideas.md",
                "relative_target":"ideas.md","target":"/home/bryan/bob/ideas.md",
                "text":"Capture follow-up","task_line":"- Capture follow-up",
                "kind":"bullet","created":"2026-08-14","scheduled":"2026-08-19","placement":"append"}
             ]}
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertEqual(success.normalizedCaptures.map(\.text), ["Ship release", "Capture follow-up"])
        XCTAssertEqual(success.normalizedCaptures.map(\.target), [
            "/home/bryan/bob/work.md",
            "/home/bryan/bob/ideas.md",
        ])
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

    func testCaptureCommandResponseDecodesOrdinaryTaskWithBlockID() throws {
        let data = Data(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": "dev",
              "route_label": "dev.md",
              "relative_target": "dev.md",
              "target": "/tmp/bob/dev.md",
              "text": "Do work",
              "task_line": "- [ ] #task Do work [created::2026-08-14] ^new-id",
              "kind": "task",
              "created": "2026-08-14",
              "scheduled": null,
              "placement": "inserted",
              "block_id": "new-id"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertEqual(success.kind, "task")
        XCTAssertEqual(success.blockID, "new-id")
        XCTAssertEqual(success.taskLine, "- [ ] #task Do work [created::2026-08-14] ^new-id")
        XCTAssertNil(success.dayFile)
        XCTAssertNil(success.blockLink)
        XCTAssertNil(success.pomodoroLinkPlacement)
        XCTAssertNil(success.parentText)
        XCTAssertEqual(success.previewBlockLines, [success.taskLine])
    }

    func testCaptureCommandResponseDecodesSubBulletSuccess() throws {
        let data = Data(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": "file",
              "route_label": "file.md",
              "relative_target": "file.md",
              "target": "/tmp/bob/file.md",
              "text": "Add context",
              "task_line": "- Add context",
              "kind": "sub_bullet",
              "block_id": "parent-id",
              "parent_text": "Parent",
              "parent_line": 1,
              "created": "2026-08-14",
              "scheduled": null,
              "placement": "inserted"
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCommandResponse.self, from: data)

        guard case .success(let success) = decoded else {
            return XCTFail("Expected a successful response")
        }
        XCTAssertEqual(success.kind, "sub_bullet")
        XCTAssertEqual(success.blockID, "parent-id")
        XCTAssertEqual(success.parentText, "Parent")
        XCTAssertEqual(success.parentLine, 1)
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
                  "ref": "4:googexit",
                  "block_id": "goog-exit",
                  "route": "cash",
                  "requires_block_id": false,
                  "status_symbol": "*",
                  "status_name": "in-progress",
                  "status_type": "TODO",
                  "text": "Finish Google Exit Packet!",
                  "section": "Tasks",
                  "depth": 0,
                  "child_count": 2
                },
                {
                  "replacement": "",
                  "ref": "8:missing",
                  "block_id": null,
                  "route": "cash",
                  "requires_block_id": true,
                  "status_symbol": " ",
                  "status_name": "Todo",
                  "status_type": "TODO",
                  "text": "Plan handoff",
                  "section": "Tasks",
                  "depth": 1,
                  "child_count": 0
                }
              ]
            }
            """.utf8
        )

        let decoded = try JSONDecoder().decode(CaptureCompletionResponse.self, from: data)

        XCTAssertEqual(decoded.context, "task")
        XCTAssertEqual(decoded.replacement, CaptureRange(start: 6, end: 8))
        XCTAssertEqual(decoded.candidates.first?.taskRef, "4:googexit")
        XCTAssertEqual(decoded.candidates.first?.route, "cash")
        XCTAssertEqual(decoded.candidates.first?.requiresBlockID, false)
        XCTAssertEqual(decoded.candidates.first?.childCount, 2)
        XCTAssertEqual(decoded.candidates[1].taskRef, "8:missing")
        XCTAssertNil(decoded.candidates[1].blockID)
        XCTAssertTrue(decoded.candidates[1].requiresBlockID)
        XCTAssertEqual(decoded.candidates[1].replacement, "")
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

    func testCaptureTaskIDResponseDecodesVersionedSuccessAndFailure() throws {
        let successData = Data(
            """
            {
              "ok": true,
              "schema_version": 1,
              "dry_run": false,
              "route": "file",
              "relative_target": "file.md",
              "block_id": "new-id",
              "line": 8,
              "ref": "8:updated",
              "task": {
                "ref": "8:updated",
                "line": 8,
                "block_id": "new-id",
                "status_symbol": " ",
                "status_name": "Todo",
                "status_type": "TODO",
                "text": "Plan handoff",
                "section": "Tasks",
                "depth": 1,
                "child_count": 0
              }
            }
            """.utf8
        )
        let failureData = Data(#"{"ok":false,"error":"block ID ^new-id already exists in file.md"}"#.utf8)

        let successResponse = try JSONDecoder().decode(CaptureTaskIDResponse.self, from: successData)
        let failureResponse = try JSONDecoder().decode(CaptureTaskIDResponse.self, from: failureData)

        guard case .success(let success) = successResponse else {
            return XCTFail("Expected task ID success")
        }
        XCTAssertEqual(success.schemaVersion, 1)
        XCTAssertEqual(success.blockID, "new-id")
        XCTAssertEqual(success.taskRef, "8:updated")
        XCTAssertEqual(success.task.text, "Plan handoff")

        guard case .failure(let failure) = failureResponse else {
            return XCTFail("Expected task ID failure")
        }
        XCTAssertEqual(failure.error, "block ID ^new-id already exists in file.md")
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
