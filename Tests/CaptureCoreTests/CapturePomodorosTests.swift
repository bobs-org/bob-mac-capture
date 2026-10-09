import XCTest

@testable import CaptureCore

final class CapturePomodorosTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    func testCurrentThreeDecodesCount() throws {
        let response = try JSONDecoder().decode(
            CapturePomodorosResponse.self,
            from: fixture("pomodoros-current-3.json")
        )
        XCTAssertEqual(response.schemaVersion, 1)
        XCTAssertEqual(response.currentTaskLinkCount, 3)
    }

    func testCurrentTwelveDecodesFullCount() throws {
        let response = try JSONDecoder().decode(
            CapturePomodorosResponse.self,
            from: fixture("pomodoros-current-12.json")
        )
        XCTAssertEqual(response.currentTaskLinkCount, 12)
    }

    func testNoneRunningDecodesNilCount() throws {
        let response = try JSONDecoder().decode(
            CapturePomodorosResponse.self,
            from: fixture("pomodoros-none-running.json")
        )
        XCTAssertNil(response.currentTaskLinkCount)
    }

    func testLegacyResponseWithoutCountDecodesNil() throws {
        let response = try JSONDecoder().decode(
            CapturePomodorosResponse.self,
            from: fixture("pomodoros-legacy-no-count.json")
        )
        XCTAssertNil(response.currentTaskLinkCount)
    }
}
