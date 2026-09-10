import XCTest

@testable import CaptureCore

final class CaptureTogglePresentationTests: XCTestCase {
    func testInitReturnsNilForANonToggleCapture() throws {
        let success = try decodeCaptureSuccess(
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
              "task_line": "- [ ] #task Do work ^new-id",
              "kind": "task",
              "created": "2026-08-14",
              "placement": "inserted",
              "block_id": "new-id"
            }
            """
        )

        XCTAssertNil(CaptureTogglePresentation(capture: success))
    }

    func testNextDirectionInsertsFreshLinkWithNoChips() throws {
        let success = try decodeCaptureSuccess(Self.nextDirectionJSON())

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.direction, .next)
        XCTAssertFalse(presentation.isDryRun)
        XCTAssertEqual(presentation.routeDestinationLabel, "cash.md \u{00b7} ^goog-exit")
        XCTAssertEqual(presentation.dayFileDestinationLabel, "2026/20260910.md")
        XCTAssertTrue(presentation.dayFileChanged)
        XCTAssertEqual(presentation.previousStatusMarker, "[ ]")
        XCTAssertEqual(presentation.statusMarker, "[*]")
        XCTAssertEqual(presentation.addedLinkText, "[[cash#^goog-exit]]")
        XCTAssertNil(presentation.removedLinksText)
        XCTAssertEqual(presentation.chips, [])
        XCTAssertEqual(presentation.primaryActionTitle, "Set Next")
        XCTAssertTrue(presentation.statusText.hasPrefix("Set Next \u{2192}"))
        XCTAssertTrue(presentation.voiceOverAnnouncement.contains("linked to today's Pomodoro"))
        XCTAssertEqual(presentation.notificationTitle, "Set Next")
        XCTAssertTrue(presentation.notificationBody.contains("+ [[cash#^goog-exit]]"))
    }

    func testNextDirectionUnderDryRunUsesWouldSetPrefixButKeepsFooterVerbStable() throws {
        let success = try decodeCaptureSuccess(Self.nextDirectionJSON(dryRun: true))

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertTrue(presentation.statusText.hasPrefix("Would Set Next \u{2192}"))
        XCTAssertEqual(presentation.primaryActionTitle, "Set Next")
    }

    func testNextDirectionAlreadyLinkedStillShowsAddedLineButChipsAlreadyLinked() throws {
        let success = try decodeCaptureSuccess(
            Self.nextDirectionJSON(pomodoroAlreadyLinked: true)
        )

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.addedLinkText, "[[cash#^goog-exit]]")
        XCTAssertEqual(presentation.chips, ["already linked"])
        XCTAssertFalse(presentation.dayFileChanged)
        XCTAssertFalse(presentation.voiceOverAnnouncement.contains("linked to today's Pomodoro"))
    }

    func testNextDirectionWithLaterDuplicateCleanupReportsRemovedLinks() throws {
        let success = try decodeCaptureSuccess(
            Self.nextDirectionJSON(removedPomodoroLinks: 2)
        )

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.removedLinksText, "removed 2 later Pomodoro task links")
        XCTAssertTrue(presentation.dayFileChanged)
    }

    func testNextDirectionWithNamedPomodoroAddsUnderSuffixToDayFileLabel() throws {
        let success = try decodeCaptureSuccess(
            Self.nextDirectionJSON(pomodoroName: "CODING")
        )

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.dayFileDestinationLabel, "2026/20260910.md \u{00b7} under CODING")
    }

    func testNextDirectionWithPullForwardAndScheduleLogAddsBothChipsInOrder() throws {
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
              "text": "",
              "task_line": "- [*] #task Finish Google Exit Packet! ^goog-exit",
              "kind": "task_toggle",
              "created": "2026-09-10",
              "placement": "toggled",
              "block_id": "goog-exit",
              "day_file": "/tmp/bob/2026/20260910.md",
              "block_link": "[[cash#^goog-exit]]",
              "toggle_direction": "next",
              "previous_task_line": "- [?] #task Finish Google Exit Packet! [scheduled::2026-09-20] ^goog-exit",
              "status_symbol": "*",
              "status_name": "Next",
              "previous_status_symbol": "?",
              "previous_status_name": "Blocked",
              "creates_pomodoro": false,
              "pomodoro_already_linked": false,
              "removed_pomodoro_links": 0,
              "removed_scheduled": "2026-09-20",
              "pomodoro_selector_unused": false,
              "schedule_log": { "reason": "pulled into today's Pomodoro", "lines": ["  _2026-09-20 \u{2192} 2026-09-10_ \u{00b7} \u{1f345} pulled into today's Pomodoro"] }
            }
            """
        )

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.chips, ["removed future schedule", "logged schedule change"])
    }

    func testOpenDirectionAlwaysReportsRemovedLinksEvenWhenZero() throws {
        let success = try decodeCaptureSuccess(Self.openDirectionJSON(removedPomodoroLinks: 0))

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.direction, .open)
        XCTAssertNil(presentation.addedLinkText)
        XCTAssertEqual(presentation.removedLinksText, "removed 0 Pomodoro task links")
        XCTAssertFalse(presentation.dayFileChanged)
        XCTAssertEqual(presentation.primaryActionTitle, "Set Open")
    }

    func testOpenDirectionWithRemovalsMarksDayFileChanged() throws {
        let success = try decodeCaptureSuccess(Self.openDirectionJSON(removedPomodoroLinks: 1))

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.removedLinksText, "removed 1 Pomodoro task link")
        XCTAssertTrue(presentation.dayFileChanged)
    }

    func testOpenDirectionWithUnusedPomodoroSelectorAddsChipNamingIt() throws {
        let success = try decodeCaptureSuccess(
            Self.openDirectionJSON(pomodoroSelectorUnused: true, pomodoroName: "CODING")
        )

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.chips, ["#CODING not used when clearing"])
        // The `#name` selector never selects anything on an un-toggle, so no `under`
        // suffix should leak into the day file label the way it does for `next`.
        XCTAssertEqual(presentation.dayFileDestinationLabel, "2026/20260910.md")
    }

    func testOpenDirectionWithUnusedPomodoroSelectorAndNoNameFallsBackToGenericChip() throws {
        let success = try decodeCaptureSuccess(
            Self.openDirectionJSON(pomodoroSelectorUnused: true)
        )

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.chips, ["#name not used when clearing"])
    }

    func testMarkerFallsBackToUnknownBracketWhenStatusSymbolIsAbsent() throws {
        let success = CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: true,
            routeLabel: "cash.md",
            relativeTarget: "cash.md",
            target: "/tmp/bob/cash.md",
            text: "",
            taskLine: "- [*] #task Finish Google Exit Packet! ^goog-exit",
            kind: "task_toggle",
            created: "2026-09-10",
            placement: "toggled",
            toggleDirection: "next"
        )

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.previousStatusMarker, "[?]")
        XCTAssertEqual(presentation.statusMarker, "[?]")
        XCTAssertEqual(presentation.previousTaskLine, presentation.taskLine)
    }

    func testRelativeDayFileLabelFallsBackToAbsolutePathWhenPrefixesDoNotShareARoot() throws {
        let success = CaptureCommandSuccess(
            ok: true,
            dryRun: false,
            routed: true,
            routeLabel: "cash.md",
            relativeTarget: "cash.md",
            target: "/tmp/bob/cash.md",
            text: "",
            taskLine: "- [*] #task Finish Google Exit Packet! ^goog-exit",
            kind: "task_toggle",
            created: "2026-09-10",
            placement: "toggled",
            dayFile: "/elsewhere/2026/20260910.md",
            toggleDirection: "next"
        )

        let presentation = try XCTUnwrap(CaptureTogglePresentation(capture: success))

        XCTAssertEqual(presentation.dayFileDestinationLabel, "/elsewhere/2026/20260910.md")
    }

    // MARK: - Fixtures

    private static func nextDirectionJSON(
        dryRun: Bool = false,
        pomodoroAlreadyLinked: Bool = false,
        removedPomodoroLinks: Int = 0,
        pomodoroName: String? = nil
    ) -> String {
        let pomodoroNameField = pomodoroName.map { ", \"pomodoro_name\": \"\($0)\"" } ?? ""
        return """
        {
          "ok": true,
          "dry_run": \(dryRun),
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
          "day_file": "/tmp/bob/2026/20260910.md",
          "block_link": "[[cash#^goog-exit]]",
          "toggle_direction": "next",
          "previous_task_line": "- [ ] #task Finish Google Exit Packet! ^goog-exit",
          "status_symbol": "*",
          "status_name": "Next",
          "previous_status_symbol": " ",
          "previous_status_name": "Ready",
          "creates_pomodoro": false,
          "pomodoro_already_linked": \(pomodoroAlreadyLinked),
          "removed_pomodoro_links": \(removedPomodoroLinks),
          "pomodoro_selector_unused": false\(pomodoroNameField)
        }
        """
    }

    private static func openDirectionJSON(
        removedPomodoroLinks: Int = 0,
        pomodoroSelectorUnused: Bool = false,
        pomodoroName: String? = nil
    ) -> String {
        let pomodoroNameField = pomodoroName.map { ", \"pomodoro_name\": \"\($0)\"" } ?? ""
        return """
        {
          "ok": true,
          "dry_run": false,
          "routed": true,
          "route": "cash",
          "route_label": "cash.md",
          "relative_target": "cash.md",
          "target": "/tmp/bob/cash.md",
          "text": "",
          "task_line": "- [ ] #task Finish Google Exit Packet! ^goog-exit",
          "kind": "task_toggle",
          "created": "2026-09-10",
          "placement": "toggled",
          "block_id": "goog-exit",
          "day_file": "/tmp/bob/2026/20260910.md",
          "block_link": "[[cash#^goog-exit]]",
          "toggle_direction": "open",
          "previous_task_line": "- [*] #task Finish Google Exit Packet! ^goog-exit",
          "status_symbol": " ",
          "status_name": "Ready",
          "previous_status_symbol": "*",
          "previous_status_name": "Next",
          "creates_pomodoro": false,
          "pomodoro_already_linked": false,
          "removed_pomodoro_links": \(removedPomodoroLinks),
          "pomodoro_selector_unused": \(pomodoroSelectorUnused)\(pomodoroNameField)
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
}
