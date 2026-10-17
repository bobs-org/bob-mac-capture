import XCTest

@testable import CaptureCore

final class CaptureTodayPomodoroGotoTests: XCTestCase {
    private func fixture(_ name: String) throws -> Data {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try Data(contentsOf: url)
    }

    private func decode(_ data: Data) throws -> CapturePomodorosResponse {
        try JSONDecoder().decode(CapturePomodorosResponse.self, from: data)
    }

    private func resolveFixture(_ name: String) throws -> CaptureTodayPomodoroGoto.Resolution {
        CaptureTodayPomodoroGoto.resolve(try decode(fixture(name)))
    }

    private func queryItems(_ url: URL) throws -> [URLQueryItem] {
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        return try XCTUnwrap(components.queryItems)
    }

    func testCurrentEntryLandsOnItsLineAndRef() throws {
        guard case .destination(let destination) = try resolveFixture("pomodoros-current-3.json")
        else {
            return XCTFail("Expected a destination")
        }
        XCTAssertEqual(destination.landing, .current)
        let items = try queryItems(destination.url)
        XCTAssertEqual(
            items.first { $0.name == "path" }?.value,
            "/tmp/bob-mac-capture-pomodoros/vault/2026/20260828.md"
        )
        XCTAssertEqual(items.first { $0.name == "line" }?.value, "2")
        XCTAssertEqual(items.first { $0.name == "ref" }?.value, "2:4a0bbe15")
    }

    func testNoneRunningLandsOnFirstOpenEntry() throws {
        guard case .destination(let destination) = try resolveFixture(
            "pomodoros-none-running.json"
        ) else {
            return XCTFail("Expected a destination")
        }
        XCTAssertEqual(destination.landing, .firstOpen)
        let items = try queryItems(destination.url)
        XCTAssertEqual(items.first { $0.name == "line" }?.value, "2")
        XCTAssertEqual(items.first { $0.name == "ref" }?.value, "2:34e1da67")
    }

    func testOnlyCompletedEntriesLandOnLastCompleted() throws {
        guard case .destination(let destination) = try resolveFixture(
            "pomodoros-all-completed.json"
        ) else {
            return XCTFail("Expected a destination")
        }
        XCTAssertEqual(destination.landing, .lastCompleted)
        let items = try queryItems(destination.url)
        XCTAssertEqual(items.first { $0.name == "line" }?.value, "6")
        XCTAssertEqual(items.first { $0.name == "ref" }?.value, "6:34e1da67")
    }

    func testEmptyListLandsOnNoteTopWithoutRef() throws {
        guard case .destination(let destination) = try resolveFixture(
            "pomodoros-no-daily-note.json"
        ) else {
            return XCTFail("Expected a destination")
        }
        XCTAssertEqual(destination.landing, .noteTop)
        let items = try queryItems(destination.url)
        XCTAssertEqual(items.first { $0.name == "line" }?.value, "1")
        XCTAssertNil(items.first { $0.name == "ref" })
        XCTAssertEqual(items.map(\.name), ["path", "line"])
    }

    func testMissingDayFileRefuses() throws {
        let response = try decode(
            Data(
                """
                {"ok":true,"schema_version":1,"pomodoros":[]}
                """.utf8
            )
        )
        guard case .refused(let refusal) = CaptureTodayPomodoroGoto.resolve(response) else {
            return XCTFail("Expected a refusal")
        }
        XCTAssertEqual(refusal, .missingDayFile)
        XCTAssertEqual(refusal.statusText, "bob sent no daily-note path — update bob")
    }

    func testEmptyDayFileRefuses() throws {
        let response = try decode(
            Data(
                """
                {"ok":true,"schema_version":1,"day_file":"","pomodoros":[]}
                """.utf8
            )
        )
        guard case .refused = CaptureTodayPomodoroGoto.resolve(response) else {
            return XCTFail("Expected a refusal")
        }
    }

    func testRelativeDayFileRefuses() throws {
        let response = try decode(
            Data(
                """
                {"ok":true,"schema_version":1,"day_file":"2026/20260828.md","pomodoros":[]}
                """.utf8
            )
        )
        guard case .refused(let refusal) = CaptureTodayPomodoroGoto.resolve(response) else {
            return XCTFail("Expected a refusal")
        }
        XCTAssertEqual(refusal, .missingDayFile)
    }

    func testMissingRefBuildsLineOnlyURL() throws {
        let response = try decode(
            Data(
                """
                {"ok":true,"schema_version":1,"day_file":"/tmp/today.md","pomodoros":[{"line":4,"is_current":true}]}
                """.utf8
            )
        )
        guard case .destination(let destination) = CaptureTodayPomodoroGoto.resolve(response)
        else {
            return XCTFail("Expected a destination")
        }
        XCTAssertEqual(destination.landing, .current)
        let items = try queryItems(destination.url)
        XCTAssertEqual(items.first { $0.name == "line" }?.value, "4")
        XCTAssertNil(items.first { $0.name == "ref" })
    }

    func testInvalidRefBuildsLineOnlyURL() throws {
        let response = try decode(
            Data(
                """
                {"ok":true,"schema_version":1,"day_file":"/tmp/today.md","pomodoros":[{"line":4,"ref":"1:ABCDEF12","is_current":true}]}
                """.utf8
            )
        )
        guard case .destination(let destination) = CaptureTodayPomodoroGoto.resolve(response)
        else {
            return XCTFail("Expected a destination")
        }
        let items = try queryItems(destination.url)
        XCTAssertEqual(items.first { $0.name == "line" }?.value, "4")
        XCTAssertNil(items.first { $0.name == "ref" })
    }

    func testDayFileWithSpaceIsPercentEncoded() throws {
        let response = try decode(
            Data(
                """
                {"ok":true,"schema_version":1,"day_file":"/tmp/bob vault/today.md","pomodoros":[]}
                """.utf8
            )
        )
        guard case .destination(let destination) = CaptureTodayPomodoroGoto.resolve(response)
        else {
            return XCTFail("Expected a destination")
        }
        XCTAssertEqual(destination.landing, .noteTop)
        XCTAssertTrue(destination.url.absoluteString.contains("%20"))
        let items = try queryItems(destination.url)
        XCTAssertEqual(items.first { $0.name == "path" }?.value, "/tmp/bob vault/today.md")
    }
}
