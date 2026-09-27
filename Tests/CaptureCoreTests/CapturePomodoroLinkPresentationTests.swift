import XCTest

@testable import CaptureCore

final class CapturePomodoroLinkPresentationTests: XCTestCase {
    func testInitReturnsNilForANonLinkCapture() throws {
        let capture = linkCapture(kind: "task", action: "linked")

        XCTAssertNil(CapturePomodoroLinkPresentation(capture: capture))
    }

    func testLinkedWithStatusChangeUsesLinkActionAndNamesDestination() throws {
        let capture = linkCapture(
            dryRun: true,
            action: "linked",
            statusSymbol: "*",
            statusName: "Next",
            previousStatusSymbol: " ",
            previousStatusName: "Todo",
            statusChanged: true,
            taskLine: "- [ ] #task Ready thing ^ready",
            blockID: "ready",
            source: nil,
            destination: PomodoroLinkEndpoint(line: 5, name: "BUGS")
        )

        let presentation = try XCTUnwrap(CapturePomodoroLinkPresentation(capture: capture))

        XCTAssertTrue(presentation.isDryRun)
        XCTAssertEqual(presentation.routeDestinationLabel, "sase.md \u{00b7} ^ready")
        XCTAssertEqual(presentation.transitionText, "[ ] \u{2192} [*]  #task Ready thing")
        XCTAssertEqual(presentation.ledgerText, "Linked under BUGS")
        XCTAssertEqual(presentation.destinationLabel, "BUGS")
        XCTAssertEqual(presentation.dayFileDestinationLabel, "2026/20260710.md \u{00b7} under BUGS")
        XCTAssertTrue(presentation.dayFileChanged)
        XCTAssertEqual(presentation.primaryActionTitle, "Link")
        XCTAssertEqual(
            presentation.statusText,
            "Would link \u{2192} sase.md \u{00b7} ^ready (Todo \u{2192} Next)"
        )
        XCTAssertEqual(presentation.notificationTitle, "Linked to BUGS")
        XCTAssertTrue(
            presentation.notificationBody.contains("Todo \u{2192} Next  sase.md · ^ready")
        )
        XCTAssertTrue(presentation.notificationBody.contains("Linked under BUGS"))
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("Linked under BUGS"))
    }

    func testAlreadyCurrentWithoutStartIsANoOpLink() throws {
        let capture = linkCapture(
            dryRun: true,
            action: "already_current",
            statusChanged: false,
            source: PomodoroLinkEndpoint(line: 5, name: "BUGS"),
            destination: PomodoroLinkEndpoint(line: 5, name: "BUGS")
        )

        let presentation = try XCTUnwrap(CapturePomodoroLinkPresentation(capture: capture))

        XCTAssertEqual(
            presentation.transitionText,
            "[*] already Next  #task Fix deep bug"
        )
        XCTAssertEqual(
            presentation.ledgerText,
            "Task Link already in BUGS; no ledger change."
        )
        XCTAssertFalse(presentation.dayFileChanged)
        XCTAssertEqual(presentation.primaryActionTitle, "Link")
        XCTAssertEqual(presentation.notificationTitle, "Already in BUGS")
        XCTAssertEqual(
            presentation.statusText,
            "Would link \u{2192} sase.md \u{00b7} ^deep-fix (Next unchanged)"
        )
    }

    func testCommittedAlreadyCurrentUsesLinkTense() throws {
        let capture = linkCapture(
            dryRun: false,
            action: "already_current",
            statusChanged: false,
            source: PomodoroLinkEndpoint(line: 5, name: "BUGS"),
            destination: PomodoroLinkEndpoint(line: 5, name: "BUGS")
        )

        let presentation = try XCTUnwrap(CapturePomodoroLinkPresentation(capture: capture))

        XCTAssertTrue(presentation.statusText.hasPrefix("Link \u{2192}"))
    }

    func testMovedWithCreatedDestinationAndStart() throws {
        let capture = linkCapture(
            dryRun: true,
            action: "moved",
            statusChanged: false,
            destinationName: "FOCUS",
            createsPomodoro: true,
            source: PomodoroLinkEndpoint(line: 5, name: "BUGS"),
            destination: PomodoroLinkEndpoint(line: 5, name: "FOCUS", timeRange: "0905-0920"),
            pomodoroStart: PomodoroStartSummary(
                start: "0905",
                end: "0920",
                durationMinutes: 15,
                offsetUnits: 0,
                pomodoroName: "FOCUS",
                pomodoroLine: 5,
                createdPomodoro: true,
                timeRange: "(**0905-0920** [t:: 15m])"
            )
        )

        let presentation = try XCTUnwrap(CapturePomodoroLinkPresentation(capture: capture))

        XCTAssertEqual(
            presentation.ledgerText,
            "Moved Task Link BUGS \u{2192} FOCUS (created FOCUS)"
        )
        XCTAssertEqual(presentation.destinationLabel, "FOCUS")
        XCTAssertTrue(presentation.dayFileChanged)
        XCTAssertEqual(presentation.primaryActionTitle, "Start")
        XCTAssertEqual(presentation.notificationTitle, "Started FOCUS")
        XCTAssertTrue(
            presentation.notificationBody
                .contains("Would start FOCUS 0905-0920 (15m) (created) at line 5")
        )
        XCTAssertTrue(
            presentation.statusText.hasPrefix("Would start \u{2192} sase.md \u{00b7} ^deep-fix")
        )
        XCTAssertTrue(presentation.previewAccessibilitySummary.contains("Starts FOCUS"))
    }

    func testMovedWithoutCreatedDestinationOmitsCreatedNote() throws {
        let capture = linkCapture(
            action: "moved",
            statusChanged: false,
            destinationName: "BUGS",
            source: PomodoroLinkEndpoint(line: 5, name: "FOCUS"),
            destination: PomodoroLinkEndpoint(line: 5, name: "BUGS")
        )

        let presentation = try XCTUnwrap(CapturePomodoroLinkPresentation(capture: capture))

        XCTAssertEqual(presentation.ledgerText, "Moved Task Link FOCUS \u{2192} BUGS")
        XCTAssertEqual(presentation.notificationTitle, "Moved to BUGS")
    }

    func testInProgressTaskStaysInProgress() throws {
        let capture = linkCapture(
            action: "linked",
            statusSymbol: "/",
            statusName: "In Progress",
            previousStatusSymbol: "/",
            previousStatusName: "In Progress",
            statusChanged: false,
            taskLine: "- [/] #task Outline talk ^outline",
            blockID: "outline",
            source: nil,
            destination: PomodoroLinkEndpoint(line: 5, name: "BUGS")
        )

        let presentation = try XCTUnwrap(CapturePomodoroLinkPresentation(capture: capture))

        XCTAssertEqual(
            presentation.transitionText,
            "[/] stays In Progress  #task Outline talk"
        )
    }

    func testAlreadyCurrentWithStartStillWritesTheDayFile() throws {
        let capture = linkCapture(
            action: "already_current",
            statusChanged: false,
            source: PomodoroLinkEndpoint(line: 5, name: "BUGS"),
            destination: PomodoroLinkEndpoint(line: 5, name: "BUGS", timeRange: "0905-0930"),
            pomodoroStart: PomodoroStartSummary(
                start: "0905",
                end: "0930",
                durationMinutes: 25,
                offsetUnits: 0,
                pomodoroName: "BUGS",
                pomodoroLine: 5,
                createdPomodoro: false,
                timeRange: "(**0905-0930** [t:: 25m])"
            )
        )

        let presentation = try XCTUnwrap(CapturePomodoroLinkPresentation(capture: capture))

        XCTAssertTrue(presentation.dayFileChanged)
        XCTAssertEqual(presentation.primaryActionTitle, "Start")
        XCTAssertEqual(presentation.notificationTitle, "Started BUGS")
    }

    private func linkCapture(
        dryRun: Bool = true,
        kind: String = "pomodoro_link",
        action: String,
        statusSymbol: String? = "*",
        statusName: String? = "Next",
        previousStatusSymbol: String? = "*",
        previousStatusName: String? = "Next",
        statusChanged: Bool? = false,
        taskLine: String = "- [*] #task Fix deep bug ^deep-fix",
        blockID: String? = "deep-fix",
        destinationName: String = "BUGS",
        createsPomodoro: Bool = false,
        source: PomodoroLinkEndpoint? = nil,
        destination: PomodoroLinkEndpoint? = nil,
        pomodoroStart: PomodoroStartSummary? = nil
    ) -> CaptureCommandSuccess {
        CaptureCommandSuccess(
            ok: true,
            dryRun: dryRun,
            routed: true,
            route: "sase",
            routeLabel: "sase.md",
            relativeTarget: "sase.md",
            target: "/tmp/bob/sase.md",
            text: "",
            taskLine: taskLine,
            kind: kind,
            created: "2026-07-10",
            placement: "linked",
            blockID: blockID,
            dayFile: "/tmp/bob/2026/20260710.md",
            blockLink: blockID.map { "[[sase#^\($0)]]" },
            previousTaskLine: taskLine,
            statusSymbol: statusSymbol,
            statusName: statusName,
            previousStatusSymbol: previousStatusSymbol,
            previousStatusName: previousStatusName,
            pomodoroName: destinationName,
            createsPomodoro: createsPomodoro,
            statusChanged: statusChanged,
            pomodoroLinkAction: action,
            pomodoroLinkSource: source,
            pomodoroLinkDestination: destination,
            pomodoroStart: pomodoroStart
        )
    }
}
