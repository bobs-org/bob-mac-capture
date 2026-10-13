import XCTest

@testable import CaptureCore

final class CaptureLinkGuardPresentationTests: XCTestCase {
    func testInitReturnsNilWithoutLinkGuard() throws {
        let capture = try decodeFixture("pomodoro-link-dropped-one.json")

        XCTAssertNil(CaptureLinkGuardPresentation(capture: capture))
    }

    func testInitReturnsNilForASuccessfulToggle() throws {
        let capture = try decodeCaptureSuccess(
            """
            {
              "ok": true,
              "dry_run": false,
              "routed": true,
              "route": "cash",
              "route_label": "cash.md",
              "relative_target": "cash.md",
              "target": "/tmp/bob/cash.md",
              "text": "",
              "task_line": "- [*] #task Finish Google Exit Packet! ^goog-exit",
              "kind": "task_toggle",
              "created": "2026-09-10",
              "placement": "toggled",
              "block_id": "goog-exit",
              "toggle_direction": "next",
              "status_symbol": "*",
              "status_name": "Next",
              "previous_status_symbol": " ",
              "previous_status_name": "Ready"
            }
            """
        )

        XCTAssertNil(CaptureLinkGuardPresentation(capture: capture))
    }

    func testLinkGuardKindShowsWouldNotLinkOnDryRunWithBobDetailVerbatim() throws {
        let capture = try decodeFixture("link-guard-project-blocked.json")
        let presentation = try XCTUnwrap(CaptureLinkGuardPresentation(capture: capture))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertEqual(presentation.headline, "Would not link")
        XCTAssertEqual(presentation.glyphName, "lock.fill")
        XCTAssertEqual(
            presentation.detail,
            "not linked (waits on [[local.md#^prep]]; project parent.md waits on [[local.md#^prep]]) · promoted local.md#^prep · dependencies kept: its project is blocked"
        )
        XCTAssertEqual(presentation.promoted, ["local.md#^prep"])
        XCTAssertEqual(presentation.notificationTitle, "Not linked")
        XCTAssertTrue(presentation.notificationBody.contains(presentation.detail))
        XCTAssertTrue(presentation.notificationBody.contains("local.md#^prep"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.hasPrefix("Would not link"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains(presentation.detail))
    }

    func testCommittedLinkGuardUsesNotLinkedHeadline() throws {
        let capture = try decodeCaptureSuccess(Self.linkGuardJSON(dryRun: false))
        let presentation = try XCTUnwrap(CaptureLinkGuardPresentation(capture: capture))

        XCTAssertFalse(presentation.isDryRun)
        XCTAssertEqual(presentation.headline, "Not linked")
        XCTAssertEqual(presentation.notificationTitle, "Not linked")
        XCTAssertEqual(presentation.glyphName, "lock.fill")
    }

    func testTaskToggleWithoutToggleDirectionPresentsTheGuard() throws {
        let capture = try decodeFixture("task-toggle-link-guard.json")

        XCTAssertNil(CaptureTogglePresentation(capture: capture))
        let presentation = try XCTUnwrap(CaptureLinkGuardPresentation(capture: capture))
        XCTAssertEqual(presentation.headline, "Would not link")
        XCTAssertEqual(
            presentation.detail,
            "not linked (waits on [[job.md#^prep]]) · promoted job.md#^prep"
        )
        XCTAssertEqual(presentation.promoted, ["job.md#^prep"])
        XCTAssertEqual(presentation.notificationTitle, "Not linked")
    }

    private static func linkGuardJSON(dryRun: Bool) -> String {
        """
        {
          "ok": true,
          "dry_run": \(dryRun),
          "routed": true,
          "route": "child",
          "route_label": "child.md",
          "relative_target": "child.md",
          "target": "/tmp/bob/child.md",
          "text": "",
          "task_line": "- [?] #task Work ^work",
          "kind": "link_guard",
          "created": "2026-07-10",
          "placement": "unchanged",
          "block_id": "work",
          "previous_task_line": "- [?] #task Work ^work",
          "status_symbol": "?",
          "status_name": "Blocked",
          "previous_status_symbol": "?",
          "previous_status_name": "Blocked",
          "status_changed": false,
          "link_guard": {
            "reasons": ["local_dependency", "project_dependency"],
            "promoted": ["local.md#^prep"],
            "detail": "not linked (open dependency) · promoted local.md#^prep · dependencies kept: its project is blocked",
            "drop_refused": "project_blocked"
          }
        }
        """
    }

    private enum CaptureFixtureError: Error {
        case expectedSuccess
    }

    private func decodeCaptureSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let decoded = try JSONDecoder().decode(
            CaptureCommandResponse.self,
            from: Data(json.utf8)
        )
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
        let text = try String(
            contentsOf: fixtures.appendingPathComponent(name),
            encoding: .utf8
        )
        return try decodeCaptureSuccess(text)
    }
}
