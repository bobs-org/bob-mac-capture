import XCTest

@testable import CaptureCore

final class LogRecallCatalogTests: XCTestCase {
    private func fixture(_ name: String) throws -> LogRecallCatalog {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        return try JSONDecoder().decode(
            LogRecallCatalog.self, from: Data(contentsOf: url))
    }

    func testCancelFixtureDecodesThreePhrases() throws {
        let catalog = try fixture("log-recall-cancel.json")
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertTrue(catalog.ok)
        XCTAssertEqual(catalog.logs.count, 1)
        let log = try XCTUnwrap(catalog.logs.first)
        XCTAssertEqual(log.kind, "cancel")
        XCTAssertEqual(log.recencyPrecision, "day")
        XCTAssertEqual(log.phrasesTotal, 3)
        XCTAssertFalse(log.truncated)
        XCTAssertEqual(catalog.cancelPhrases().count, 3)
        XCTAssertEqual(catalog.cancelPhrases()[0].key, "duplicate of planning")
        XCTAssertEqual(log.excluded.machine, 1)
    }

    func testMissingOptionalFieldsDecodeWithDefaults() throws {
        let catalog = try JSONDecoder().decode(
            LogRecallCatalog.self,
            from: Data(#"{"logs": [{"kind": "cancel"}]}"#.utf8)
        )
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertTrue(catalog.ok)
        XCTAssertEqual(catalog.logs.count, 1)
        XCTAssertEqual(catalog.cancelPhrases(), [])
    }

    func testEmptyCatalogHasNoPhrases() throws {
        let catalog = try JSONDecoder().decode(
            LogRecallCatalog.self,
            from: Data(
                #"{"schema_version": 1, "ok": true, "logs": []}"#.utf8)
        )
        XCTAssertEqual(catalog.cancelPhrases(), [])
    }

    func testUnsupportedPatternMatchesOldBob() {
        XCTAssertTrue(
            BobProcessClient.isUnsupportedLogsFailure(
                stderr:
                    "error: unrecognized subcommand 'logs'\n\nUsage: bob [COMMAND]"
            ))
        XCTAssertFalse(
            BobProcessClient.isUnsupportedLogsFailure(stderr: "vault not found"))
        XCTAssertFalse(
            BobProcessClient.isUnsupportedLogsFailure(
                stderr: "error: unexpected argument '--tasks' found"))
    }
}
