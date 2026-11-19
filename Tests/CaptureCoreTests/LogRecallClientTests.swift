import XCTest

@testable import CaptureCore

final class LogRecallClientTests: XCTestCase {
    func testLogHistoryRecordsArgvAndDecodesCancel() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_LOGS_FIXTURE": "log-recall-cancel.json",
            ]
        )

        let catalog = try await client.logHistory()
        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.cancelPhrases().count, 3)
        XCTAssertEqual(catalog.cancelPhrases()[0].key, "duplicate of planning")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=logs list -f json -l cancel"))
    }

    func testLogHistoryUnsupportedMapsOldBobAndRemembers() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_LOGS_UNSUPPORTED": "1",
            ]
        )
        client.identityTokenProvider = { "log-recall-test-identity" }

        do {
            _ = try await client.logHistory()
            XCTFail("Expected unsupportedCommand")
        } catch BobClientError.unsupportedCommand(let command) {
            XCTAssertEqual(command, "logs list")
        } catch {
            XCTFail("Expected unsupportedCommand, got \(error)")
        }
        XCTAssertTrue(client.logHistoryKnownUnsupported)

        // Remembered per executable identity: the second call never spawns bob.
        do {
            _ = try await client.logHistory()
            XCTFail("Expected remembered unsupportedCommand")
        } catch BobClientError.unsupportedCommand(let command) {
            XCTAssertEqual(command, "logs list")
        } catch {
            XCTFail("Expected unsupportedCommand, got \(error)")
        }
    }

    func testLogHistoryFailureThrowsProcessFailed() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_LOGS_FAIL": "1",
            ]
        )

        do {
            _ = try await client.logHistory()
            XCTFail("Expected processFailed")
        } catch BobClientError.processFailed(_, let exitStatus, _) {
            XCTAssertEqual(exitStatus, 1)
        } catch {
            XCTFail("Expected processFailed, got \(error)")
        }
    }

    func testLogHistorySchemaMismatchThrows() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"schema_version": 2, "ok": true, "logs": []}"#,
            ]
        )

        do {
            _ = try await client.logHistory()
            XCTFail("Expected schemaMismatch")
        } catch BobClientError.schemaMismatch(_, let expected, let actual) {
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(actual, 2)
        } catch {
            XCTFail("Expected schemaMismatch, got \(error)")
        }
    }

    func testLogHistoryMalformedJSONThrows() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": "not json",
            ]
        )

        do {
            _ = try await client.logHistory()
            XCTFail("Expected malformedJSON")
        } catch BobClientError.malformedJSON {
        } catch {
            XCTFail("Expected malformedJSON, got \(error)")
        }
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot =
            source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fakeBob = packageRoot.appendingPathComponent("Fixtures/fake-bob")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: fakeBob.path))
        return fakeBob.path
    }
}
