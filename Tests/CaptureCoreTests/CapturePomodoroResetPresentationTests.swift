import Foundation
import XCTest

@testable import CaptureCore

final class CapturePomodoroResetPresentationTests: XCTestCase {
    func testRealBobResetPresentsTitleDestinationAndStatus() throws {
        let success = try decodeFixture("pomodoro-reset-submitted.json")
        let presentation = try XCTUnwrap(CapturePomodoroResetPresentation(capture: success))

        XCTAssertEqual(presentation.variant, .session)
        XCTAssertEqual(presentation.title, "Reset CAPTURE")
        XCTAssertEqual(presentation.destinationText, "2026/20261009.md · line 4")
        XCTAssertEqual(presentation.entryLine, "- [ ] () — CAPTURE")
        XCTAssertNil(presentation.viaText)
        XCTAssertEqual(presentation.statusText, "Reset CAPTURE")
        XCTAssertEqual(presentation.primaryActionTitle, "Reset")
        XCTAssertEqual(presentation.notificationTitle, "Reset CAPTURE")
        XCTAssertTrue(presentation.notificationBody.contains("now the first future Pomodoro"))
        XCTAssertEqual(presentation.batchSuffix, " (reset CAPTURE)")
        XCTAssertTrue(presentation.accessibilitySummary.contains("Reset CAPTURE"))
        XCTAssertNil(success.pomodoroClose)
        XCTAssertNotNil(success.pomodoroReset)
    }

    func testDryRunResetUsesWouldVerb() throws {
        let success = try decodeFixture("pomodoro-reset-dry.json")
        let presentation = try XCTUnwrap(CapturePomodoroResetPresentation(capture: success))
        XCTAssertEqual(presentation.statusText, "Would reset CAPTURE")
        XCTAssertEqual(presentation.primaryActionTitle, "Would reset")
        XCTAssertTrue(success.dryRun)
    }

    func testLinkResetKeepsViaText() throws {
        let success = try decodeFixture("pomodoro-reset-link.json")
        let presentation = try XCTUnwrap(CapturePomodoroResetPresentation(capture: success))
        XCTAssertEqual(presentation.variant, .linkedTask)
        XCTAssertEqual(presentation.title, "Reset CAPTURE")
        XCTAssertNotNil(presentation.viaText)
        XCTAssertNil(success.pomodoroClose)
    }

    func testOldBobCloseWithoutResetDecodesWithNilReset() throws {
        // Backwards compatibility: old Bob omits `pomodoro_reset`; new app
        // still decodes and falls back to the close presentation.
        let success = try decodeFixture("pomodoro-close-blocks.json")
        XCTAssertNil(success.pomodoroReset)
        XCTAssertNotNil(success.pomodoroClose)
        XCTAssertNil(CapturePomodoroResetPresentation(capture: success))
        XCTAssertNotNil(CapturePomodoroClosePresentation(capture: success))
    }

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        try decodeSuccess(fixtureText(name))
    }

    private func fixtureText(_ name: String) throws -> String {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        return try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
    }

    private func decodeSuccess(_ json: String) throws -> CaptureCommandSuccess {
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(json.utf8))
        guard case .success(let success) = response else {
            XCTFail("expected successful Bob response")
            throw NSError(domain: "CapturePomodoroResetPresentationTests", code: 1)
        }
        return success
    }
}
