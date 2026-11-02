import Foundation
import XCTest

@testable import CaptureCore

final class CapturePomodoroMergePresentationTests: XCTestCase {
    func testMergePreviewUsesBobNamesAbsorbedRowsAndDuplicateCounts() throws {
        let capture = try decodeFixture("pomodoro-merge-preview.json")
        let presentation = try XCTUnwrap(CapturePomodoroMergePresentation(capture: capture))

        XCTAssertEqual(presentation.before, "BUILD")
        XCTAssertEqual(presentation.after, "BUILD + FIX + READ")
        XCTAssertEqual(presentation.destinationText, "20261102.md · line 8")
        XCTAssertEqual(presentation.absorbedRows.map(\.name), ["FIX", "READ"])
        XCTAssertEqual(presentation.absorbedRows.map(\.movedLines), [3, 1])
        XCTAssertEqual(presentation.absorbedRows.map(\.droppedDuplicates), [1, 0])
        XCTAssertEqual(presentation.primaryActionTitle, "Merge")
        XCTAssertEqual(presentation.statusText, "Would merge FIX, READ into BUILD + FIX + READ")
        XCTAssertTrue(
            presentation.notificationBody.contains("FIX · 3 lines moved · 1 duplicate dropped")
        )
    }

    func testOlderBobHasNoMergePresentation() throws {
        let capture = try decodeFixture("pomodoro-close-worked.json")

        XCTAssertNil(capture.pomodoroMerge)
        XCTAssertNil(CapturePomodoroMergePresentation(capture: capture))
    }

    private func decodeFixture(_ name: String) throws -> CaptureCommandSuccess {
        let fixtures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
        let text = try String(contentsOf: fixtures.appendingPathComponent(name), encoding: .utf8)
        let response = try JSONDecoder().decode(CaptureCommandResponse.self, from: Data(text.utf8))
        guard case .success(let success) = response else {
            throw NSError(domain: "CapturePomodoroMergePresentationTests", code: 1)
        }
        return success
    }
}
