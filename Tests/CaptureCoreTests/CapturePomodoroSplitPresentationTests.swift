import Foundation
import XCTest

@testable import CaptureCore

final class CapturePomodoroSplitPresentationTests: XCTestCase {
    func testSplitPreviewUsesBobNamesCreatedRowsAndLinkCounts() throws {
        let capture = try decodeFixture("pomodoro-split-preview.json")
        let presentation = try XCTUnwrap(CapturePomodoroSplitPresentation(capture: capture))

        XCTAssertEqual(presentation.before, "BUILD + FIX + READ")
        XCTAssertEqual(presentation.after, "BUILD + READ")
        XCTAssertEqual(presentation.base.name, "BUILD")
        XCTAssertEqual(presentation.destinationText, "20261102.md · line 8")
        XCTAssertEqual(presentation.createdRows.map(\.type.name), ["FIX", "READ"])
        XCTAssertEqual(presentation.createdRows.map(\.movedLinks), [2, 0])
        XCTAssertEqual(presentation.stayedLinks, 1)
        XCTAssertEqual(presentation.primaryActionTitle, "Split")
        XCTAssertEqual(presentation.statusText, "Would split BUILD + FIX + READ → BUILD + READ")
        XCTAssertTrue(presentation.notificationBody.contains("FIX · 2 links"))
        XCTAssertTrue(presentation.notificationBody.contains("READ · no links"))
        XCTAssertTrue(presentation.notificationBody.contains("1 link stays"))
    }

    func testOlderBobHasNoSplitPresentation() throws {
        let capture = try decodeFixture("pomodoro-close-worked.json")

        XCTAssertNil(capture.pomodoroSplit)
        XCTAssertNil(CapturePomodoroSplitPresentation(capture: capture))
    }

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(text.utf8))
        guard case .success(let success) = response else {
            throw NSError(domain: "CapturePomodoroSplitPresentationTests", code: 1)
        }
        return success
    }
}
