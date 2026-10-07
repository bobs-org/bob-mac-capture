import XCTest

@testable import CaptureCore

// Reference-item (`kind == "ref"`) decode and presentation tests. Fixture
// files under Tests/Fixtures record real bob output from bob-cli master
// (phase `capture`); inline JSON covers the tolerant-decode contract
// (present, absent, malformed) and every library verdict's byte-identical
// detail line.
//
// Recording (bob-cli checkout, debug build is enough — the JSON is identical):
//
//   BOBBIN=$CARGO_TARGET_DIR/debug/bob; R=/tmp/bob-mac-capture-ref
//   VAULT=$R/vault; STATE=$R/state; rm -rf $R; mkdir -p $VAULT $STATE/stubs
//   export XDG_STATE_HOME=$STATE BOB_NOW="2026-10-07 14:30:00"
//   export BOB_REF_JOBS_KICK=off BOB_CONFIG_FILE=/definitely/missing/bob-cli-test-config.yml
//   # Failing stubs prove dry runs never touch the network:
//   # fail-curl.sh / fail-clip.sh print to stderr and exit 1.
//   export BOB_HIGHLIGHTS_CURL=$STATE/stubs/fail-curl.sh BOB_WEB_CLIP_ADAPTER=$STATE/stubs/fail-clip.sh
//   # Seed the library notes (mirrors tests/cli/capture/ref.rs):
//   printf -- '---\ntitle: Captured Post\nstatus: ready\nsource_url: https://example.com/captured\nsource_pdf: lib/papers/captured.pdf\n---\n\n- [ ] ^ref\n' > $VAULT/ref/papers/captured.md
//   printf -- '---\ntitle: Legacy Post\nstatus: ready\nsource_url: https://example.com/legacy\n---\n\n- [ ] ^ref\n' > $VAULT/ref/blogs/legacy.md
//   # Seed intake state with a real clip (working fake curl serving article
//   # HTML for example.com plus a fake adapter copying a bare PDF and
//   # printing the canned article capture JSON), then switch back to the
//   # failing stubs before recording:
//   BOB_HIGHLIGHTS_CURL=$STATE/stubs/fake-curl.sh BOB_WEB_CLIP_ADAPTER=$STATE/stubs/fake-clip.sh \
//     $BOBBIN ref create -b $VAULT https://example.com/queued   # installs xlib/blogs/queued.pdf
//   FIX=Tests/Fixtures
//   $BOBBIN capture -b $VAULT -f json --dry-run -- 'https://example.com/post' > $FIX/ref-queued.json
//   $BOBBIN capture -b $VAULT -f json --dry-run -- 'https://example.com/captured' > $FIX/ref-in-library.json
//   $BOBBIN capture -b $VAULT -f json --dry-run -- 'https://example.com/queued' > $FIX/ref-in-intake.json
//   $BOBBIN capture -b $VAULT -f json --dry-run -- 'https://example.com/legacy' > $FIX/ref-legacy.json
//   printf 'https://example.com/post\nhttps://example.com/post' | $BOBBIN capture -b $VAULT -f json --dry-run > $FIX/ref-duplicate-batch.json
//   printf 'https://example.com/1\nhttps://example.com/2' | $BOBBIN capture -b $VAULT -f json --dry-run > $FIX/ref-url-list.json
//   printf 'buy milk\n\nhttps://example.com/2' | $BOBBIN capture -b $VAULT -f json --dry-run > $FIX/ref-mixed-batch.json
//   $BOBBIN capture-parse -f json -- 'https://example.com/post' > $FIX/capture-parse-ref.json
final class CaptureRefPresentationTests: XCTestCase {
    func testAbsentRefObjectDecodesAsNil() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "mac_inbox.md",
              "target": "/tmp/bob/mac_inbox.md",
              "text": "Do work",
              "task_line": "- [ ] #task Do work [created::2026-10-07]",
              "kind": "task",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "created"
            }
            """
        )

        XCTAssertNil(success.ref)
        XCTAssertNil(CaptureRefPresentation(capture: success))
    }

    func testMalformedRefObjectDegradesToDefaults() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "",
              "target": "",
              "text": "https://example.com/post",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "queued",
              "ref": {"raw": 42}
            }
            """
        )

        // Unknown keys degrade to defaults without failing the capture, and
        // an all-empty `ref` presents as nothing.
        XCTAssertEqual(success.ref, CaptureRef())
        XCTAssertNil(CaptureRefPresentation(capture: success))
    }

    func testMistypedRefFieldDecodesAsNil() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "",
              "target": "",
              "text": "https://example.com/post",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "queued",
              "ref": {"url": 42, "display": "example.com/post"}
            }
            """
        )

        // A mistyped scalar poisons the whole `ref` object, never the capture.
        XCTAssertNil(success.ref)
    }

    func testQueuedDryRunPresentation() throws {
        let success = try decodeCaptureSuccess(queuedJSON(dryRun: true))
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertTrue(presentation.isQueued)
        XCTAssertEqual(presentation.headline, "Save to reading queue")
        XCTAssertEqual(presentation.destinationLabel, "example.com/post")
        XCTAssertEqual(presentation.detailText, "new to your library · clips in the background")
        XCTAssertEqual(presentation.chips, ["Article"])
        XCTAssertEqual(
            presentation.fallbackHint,
            "If clipping fails, it becomes a task in mac_inbox.md."
        )
        XCTAssertEqual(presentation.primaryActionTitle, "Queue")
        XCTAssertEqual(presentation.statusText, "Would queue for clipping → reading queue")
        XCTAssertEqual(presentation.notificationTitle, "Queued for reading")
        XCTAssertEqual(presentation.notificationBody, "example.com/post → reading queue")
        XCTAssertNil(presentation.openTargetPath)
    }

    func testQueuedRealRunPresentation() throws {
        let success = try decodeCaptureSuccess(queuedJSON(dryRun: false))
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertFalse(presentation.isDryRun)
        XCTAssertTrue(presentation.isQueued)
        XCTAssertEqual(presentation.headline, "Queued for reading")
        XCTAssertEqual(presentation.destinationLabel, "example.com/post")
        XCTAssertEqual(presentation.detailText, "clipping in the background · bob ref jobs")
        XCTAssertEqual(presentation.chips, ["Article"])
        XCTAssertEqual(presentation.primaryActionTitle, "Queue")
        XCTAssertEqual(presentation.statusText, "Queued for clipping → reading queue")
        XCTAssertNil(presentation.openTargetPath)
        XCTAssertEqual(
            presentation.previewAccessibilitySummary,
            "Queued for reading: example.com/post, clipping in the background · bob ref jobs, If clipping fails, it becomes a task in mac_inbox.md."
        )
    }

    func testInLibraryPresentation() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "ref/blogs/post.md",
              "target": "/tmp/bob/ref/blogs/post.md",
              "text": "https://example.com/post",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "unchanged",
              "ref": {
                "url": "https://example.com/post",
                "cleaned_url": "https://example.com/post",
                "dedupe_key": "https://example.com/post",
                "display": "example.com/post",
                "route_hint": "article",
                "library": {
                  "verdict": "in_library",
                  "path": "ref/blogs/post.md",
                  "title": "Post Title",
                  "reading_state": "finished"
                }
              }
            }
            """
        )
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertFalse(presentation.isQueued)
        XCTAssertEqual(presentation.headline, "Already in your library")
        XCTAssertEqual(presentation.destinationLabel, "ref/blogs/post.md")
        XCTAssertEqual(presentation.detailText, "Post Title · finished")
        XCTAssertEqual(presentation.chips, ["Finished"])
        XCTAssertNil(presentation.fallbackHint)
        XCTAssertEqual(presentation.primaryActionTitle, "Done")
        XCTAssertEqual(presentation.statusText, "Already in your library: Post Title")
        XCTAssertEqual(presentation.notificationTitle, "Already in your library")
        XCTAssertEqual(presentation.notificationBody, "Post Title")
        XCTAssertEqual(presentation.openTargetPath, "/tmp/bob/ref/blogs/post.md")
    }

    func testInIntakePresentation() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "xlib/blogs/post.pdf",
              "target": "/tmp/bob/xlib/blogs/post.pdf",
              "text": "https://example.com/post.pdf",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "unchanged",
              "ref": {
                "url": "https://example.com/post.pdf",
                "cleaned_url": "https://example.com/post.pdf",
                "dedupe_key": "https://example.com/post.pdf",
                "display": "example.com/post.pdf",
                "route_hint": "pdf",
                "library": {"verdict": "in_intake", "path": "xlib/blogs/post.pdf"}
              }
            }
            """
        )
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertEqual(presentation.headline, "Already queued")
        XCTAssertEqual(presentation.destinationLabel, "xlib/blogs/post.pdf")
        XCTAssertEqual(presentation.detailText, "waiting for bob ref scan")
        XCTAssertEqual(presentation.chips, [])
        XCTAssertEqual(presentation.primaryActionTitle, "Done")
        XCTAssertEqual(presentation.statusText, "Already queued: xlib/blogs/post.pdf")
        XCTAssertEqual(presentation.openTargetPath, "/tmp/bob/xlib/blogs/post.pdf")
    }

    func testClippingPresentation() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "",
              "target": "",
              "text": "https://example.com/post",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "unchanged",
              "ref": {
                "url": "https://example.com/post",
                "cleaned_url": "https://example.com/post",
                "dedupe_key": "https://example.com/post",
                "display": "example.com/post",
                "route_hint": "article",
                "library": {"verdict": "clipping"}
              }
            }
            """
        )
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertEqual(presentation.headline, "Already clipping")
        XCTAssertEqual(presentation.destinationLabel, "example.com/post")
        XCTAssertEqual(presentation.detailText, "a pending ref job has this link · bob ref jobs")
        XCTAssertEqual(presentation.statusText, "Already clipping: example.com/post")
        XCTAssertNil(presentation.openTargetPath)
    }

    func testDuplicatePresentation() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "",
              "target": "",
              "text": "https://example.com/post",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "unchanged",
              "ref": {
                "url": "https://example.com/post",
                "cleaned_url": "https://example.com/post",
                "dedupe_key": "https://example.com/post",
                "display": "example.com/post",
                "route_hint": "article",
                "library": {"verdict": "duplicate", "message": "same link as item 1"}
              }
            }
            """
        )
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertEqual(presentation.headline, "Duplicate link")
        XCTAssertEqual(presentation.destinationLabel, "example.com/post")
        XCTAssertEqual(presentation.detailText, "same link as item 1")
        XCTAssertEqual(presentation.statusText, "Duplicate link: example.com/post")
        XCTAssertEqual(presentation.notificationTitle, "Duplicate link")
    }

    func testLegacyPresentation() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "",
              "target": "",
              "text": "https://example.com/post",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "queued",
              "ref": {
                "url": "https://example.com/post",
                "cleaned_url": "https://example.com/post",
                "dedupe_key": "https://example.com/post",
                "display": "example.com/post",
                "route_hint": "article",
                "library": {"verdict": "legacy", "path": "ref/ai/x.md"},
                "fallback": {
                  "relative_target": "mac_inbox.md",
                  "task_line": "- [ ] #task https://example.com/post [created::2026-10-07]"
                }
              }
            }
            """
        )
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertTrue(presentation.isQueued)
        XCTAssertEqual(
            presentation.detailText,
            "in your library as a legacy note (ref/ai/x.md) · a fresh copy will be clipped"
        )
        XCTAssertEqual(presentation.chips, ["Article"])
    }

    func testUnknownVerdictPresentation() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "",
              "target": "",
              "text": "https://example.com/post",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "queued",
              "ref": {
                "url": "https://example.com/post",
                "cleaned_url": "https://example.com/post",
                "dedupe_key": "https://example.com/post",
                "display": "example.com/post",
                "route_hint": "article",
                "library": {"verdict": "unknown", "message": "index locked"},
                "fallback": {
                  "relative_target": "mac_inbox.md",
                  "task_line": "- [ ] #task https://example.com/post [created::2026-10-07]"
                }
              }
            }
            """
        )
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertEqual(
            presentation.detailText,
            "library check unavailable: index locked · the clip still dedupes"
        )
        XCTAssertEqual(presentation.statusText, "Library check unavailable: index locked")
    }

    func testInitReturnsNilForNonRefKind() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "mac_inbox.md",
              "target": "/tmp/bob/mac_inbox.md",
              "text": "https://example.com/post",
              "task_line": "- [ ] #task https://example.com/post [created::2026-10-07]",
              "kind": "task",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "created"
            }
            """
        )

        XCTAssertNil(CaptureRefPresentation(capture: success))
    }

    func testInitReturnsNilWhenRefObjectIsMissing() throws {
        let success = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": true,
              "routed": false,
              "route": null,
              "route_label": "",
              "relative_target": "",
              "target": "",
              "text": "https://example.com/post",
              "task_line": "",
              "kind": "ref",
              "created": "2026-10-07",
              "scheduled": null,
              "placement": "queued"
            }
            """
        )

        XCTAssertNil(success.ref)
        XCTAssertNil(CaptureRefPresentation(capture: success))
    }

    func testRefURLSpanMapsToLinkCategory() {
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "ref_url"), .link)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "route"), .route)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: "bogus-kind"), .neutral)
    }

    func testOnlyLinkCategoryIsUnderlined() {
        XCTAssertTrue(CaptureSemanticCategory.link.isUnderlined)
        XCTAssertFalse(CaptureSemanticCategory.route.isUnderlined)
        XCTAssertFalse(CaptureSemanticCategory.blockID.isUnderlined)
        XCTAssertFalse(CaptureSemanticCategory.neutral.isUnderlined)
    }

    private func queuedJSON(dryRun: Bool) -> String {
        """
        {
          "ok": true,
          "dry_run": \(dryRun),
          "routed": false,
          "route": null,
          "route_label": "",
          "relative_target": "",
          "target": "",
          "text": "https://example.com/post?utm_source=x",
          "task_line": "",
          "kind": "ref",
          "created": "2026-10-07",
          "scheduled": null,
          "placement": "queued",
          "ref": {
            "url": "https://example.com/post?utm_source=x",
            "cleaned_url": "https://example.com/post",
            "dedupe_key": "https://example.com/post",
            "display": "example.com/post",
            "route_hint": "article",
            "library": {"verdict": "not_found"},
        \(dryRun ? "" : """
            "job": {"id": "20261007T143012-3f9a1c", "state": "pending"},
        """)
            "fallback": {
              "relative_target": "mac_inbox.md",
              "task_line": "- [ ] #task https://example.com/post?utm_source=x [created::2026-10-07]"
            }
          }
        }
        """
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

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        return try decodeCaptureSuccess(text)
    }

    private func decodeParseFixture(_ name: String) throws -> CaptureParseResponse {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        return try JSONDecoder().decode(CaptureParseResponse.self, from: Data(text.utf8))
    }

    // MARK: - Real-bob fixtures

    func testQueuedFixtureRendersTheQueuedCard() throws {
        let success = try decodeFixture("ref-queued.json")
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertTrue(presentation.isQueued)
        XCTAssertEqual(presentation.headline, "Save to reading queue")
        XCTAssertEqual(presentation.destinationLabel, "example.com/post")
        XCTAssertEqual(
            presentation.detailText,
            "new to your library · clips in the background"
        )
        XCTAssertEqual(presentation.chips, ["Article"])
        XCTAssertEqual(
            presentation.fallbackHint,
            "If clipping fails, it becomes a task in mac_inbox.md."
        )
        XCTAssertEqual(presentation.primaryActionTitle, "Queue")
        XCTAssertEqual(presentation.statusText, "Would queue for clipping → reading queue")
        XCTAssertNil(presentation.openTargetPath)
    }

    func testInLibraryFixtureRendersTheLibraryCard() throws {
        let success = try decodeFixture("ref-in-library.json")
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertFalse(presentation.isQueued)
        XCTAssertEqual(presentation.headline, "Already in your library")
        XCTAssertEqual(presentation.destinationLabel, "ref/papers/captured.md")
        XCTAssertEqual(presentation.detailText, "Captured Post · queued")
        XCTAssertEqual(presentation.chips, ["Queued"])
        XCTAssertNil(presentation.fallbackHint)
        XCTAssertEqual(presentation.primaryActionTitle, "Done")
        XCTAssertEqual(presentation.statusText, "Already in your library: Captured Post")
        XCTAssertEqual(
            presentation.openTargetPath,
            "/tmp/bob-mac-capture-ref/vault/ref/papers/captured.md"
        )
    }

    func testInIntakeFixtureRendersTheIntakeCard() throws {
        let success = try decodeFixture("ref-in-intake.json")
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertFalse(presentation.isQueued)
        XCTAssertEqual(presentation.headline, "Already queued")
        XCTAssertEqual(presentation.destinationLabel, "xlib/blogs/queued.pdf")
        XCTAssertEqual(presentation.detailText, "waiting for bob ref scan")
        XCTAssertEqual(presentation.chips, [])
        XCTAssertEqual(presentation.statusText, "Already queued: xlib/blogs/queued.pdf")
        XCTAssertEqual(
            presentation.openTargetPath,
            "/tmp/bob-mac-capture-ref/vault/xlib/blogs/queued.pdf"
        )
    }

    func testLegacyFixtureQueuesAFreshCopy() throws {
        let success = try decodeFixture("ref-legacy.json")
        let presentation = try XCTUnwrap(CaptureRefPresentation(capture: success))

        XCTAssertTrue(presentation.isQueued)
        XCTAssertEqual(presentation.headline, "Save to reading queue")
        XCTAssertEqual(presentation.destinationLabel, "example.com/legacy")
        XCTAssertEqual(
            presentation.detailText,
            "in your library as a legacy note (ref/blogs/legacy.md) · a fresh copy will be clipped"
        )
        XCTAssertEqual(presentation.chips, ["Article"])
        XCTAssertEqual(
            presentation.fallbackHint,
            "If clipping fails, it becomes a task in mac_inbox.md."
        )
    }

    func testDuplicateBatchFixtureMarksTheRepeat() throws {
        let success = try decodeFixture("ref-duplicate-batch.json")
        let captures = success.normalizedCaptures
        XCTAssertEqual(captures.count, 2)

        let first = try XCTUnwrap(CaptureRefPresentation(capture: captures[0]))
        XCTAssertTrue(first.isQueued)
        XCTAssertEqual(first.headline, "Save to reading queue")

        let second = try XCTUnwrap(CaptureRefPresentation(capture: captures[1]))
        XCTAssertFalse(second.isQueued)
        XCTAssertEqual(second.headline, "Duplicate link")
        XCTAssertEqual(second.destinationLabel, "example.com/post")
        XCTAssertEqual(second.detailText, "same link as item 1")
        XCTAssertEqual(second.primaryActionTitle, "Done")
        XCTAssertNil(second.openTargetPath)
    }

    func testURLListFixtureQueuesOneItemPerLine() throws {
        let success = try decodeFixture("ref-url-list.json")
        let captures = success.normalizedCaptures
        XCTAssertEqual(captures.count, 2)

        for capture in captures {
            let presentation = try XCTUnwrap(CaptureRefPresentation(capture: capture))
            XCTAssertTrue(presentation.isQueued)
            XCTAssertEqual(presentation.chips, ["Article"])
        }
        XCTAssertEqual(
            captures.map(\.text),
            ["https://example.com/1", "https://example.com/2"]
        )
    }

    func testMixedBatchFixtureKeepsEachItemsOwnCard() throws {
        let success = try decodeFixture("ref-mixed-batch.json")
        let captures = success.normalizedCaptures
        XCTAssertEqual(captures.count, 2)

        // The ordinary task has no reference card.
        XCTAssertNil(CaptureRefPresentation(capture: captures[0]))

        let ref = try XCTUnwrap(CaptureRefPresentation(capture: captures[1]))
        XCTAssertTrue(ref.isQueued)
        XCTAssertEqual(ref.destinationLabel, "example.com/2")
        XCTAssertEqual(ref.headline, "Save to reading queue")
    }

    func testCaptureParseRefFixtureReportsRefModeAndSpan() throws {
        let parse = try decodeParseFixture("capture-parse-ref.json")

        XCTAssertEqual(parse.mode, "ref")
        XCTAssertEqual(parse.spans.count, 1)
        let span = try XCTUnwrap(parse.spans.first)
        XCTAssertEqual(span.kind, "ref_url")
        XCTAssertEqual(span.start, 0)
        XCTAssertEqual(span.end, 24)
        XCTAssertEqual(captureSemanticCategory(forSpanKind: span.kind), .link)
    }
}
