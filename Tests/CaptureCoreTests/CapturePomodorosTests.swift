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
        XCTAssertEqual(
            response.dayFile,
            "/tmp/bob-mac-capture-pomodoros/vault/2026/20260828.md"
        )
        XCTAssertEqual(response.pomodoros[0].ref, "2:4a0bbe15")
        XCTAssertEqual(response.pomodoros[0].state, .open)
        XCTAssertTrue(response.pomodoros[0].isCurrent)
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
        XCTAssertEqual(
            response.dayFile,
            "/tmp/bob-mac-capture-pomodoros/vault/2026/20260828.md"
        )
        XCTAssertEqual(response.pomodoros[0].ref, "2:34e1da67")
        XCTAssertEqual(response.pomodoros[0].state, .open)
        XCTAssertFalse(response.pomodoros[0].isCurrent)
    }

    func testLegacyResponseWithoutCountDecodesNil() throws {
        let response = try JSONDecoder().decode(
            CapturePomodorosResponse.self,
            from: fixture("pomodoros-legacy-no-count.json")
        )
        XCTAssertNil(response.currentTaskLinkCount)
        XCTAssertEqual(
            response.dayFile,
            "/tmp/bob-mac-capture-pomodoros/vault/2026/20260828.md"
        )
        XCTAssertEqual(response.pomodoros[0].ref, "2:4a0bbe15")
        XCTAssertEqual(response.pomodoros[0].state, .open)
    }

    func testLegacyPayloadWithoutDayFileRefOrStateDecodesDefaults() throws {
        let response = try JSONDecoder().decode(
            CapturePomodorosResponse.self,
            from: Data(
                """
                {"ok":true,"schema_version":1,"pomodoros":[{"line":2,"is_current":true}]}
                """.utf8
            )
        )
        XCTAssertNil(response.dayFile)
        XCTAssertNil(response.pomodoros[0].ref)
        XCTAssertEqual(response.pomodoros[0].state, .other)
        XCTAssertNil(response.currentTaskLinkCount)
    }

    func testUnknownStateDecodesAsOther() throws {
        let response = try JSONDecoder().decode(
            CapturePomodorosResponse.self,
            from: Data(
                """
                {"ok":true,"schema_version":1,"pomodoros":[{"line":2,"state":"paused"}]}
                """.utf8
            )
        )
        XCTAssertEqual(response.pomodoros[0].state, .other)
    }
}
