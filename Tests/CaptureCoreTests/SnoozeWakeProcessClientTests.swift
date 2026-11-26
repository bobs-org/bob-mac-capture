import Foundation
import XCTest

@testable import CaptureCore

final class SnoozeWakeProcessClientTests: XCTestCase {
    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    func testSnoozeListUsesExactArgvAndDecodesCapabilities() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "BOB_DIR": "/vault/example",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_SNOOZE_LIST_JSON": """
                    {"schema_version":1,"wake_notice_version":1,\
                    "vault_root":"/vault/example","date":"2026-10-08",\
                    "now":"2026-10-08T12:00:00-04:00",\
                    "rows":[{"line":4,"route":"tasks.md","block_id":"^job",\
                    "title":"Email Dan","target":"1530","state":"woken",\
                    "wake_notice_eligible":true}],"next_wake_at":null,\
                    "plan":{"count":1,"cap":10,"over":false}}
                    """,
            ]
        )

        let response = try await client.snoozeList()

        XCTAssertTrue(response.supportsWakeNotice)
        XCTAssertEqual(response.vaultRoot, "/vault/example")
        XCTAssertEqual(response.eligibleRows.count, 1)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=snooze -f json"))
        XCTAssertTrue(record.contains("BOB_DIR=/vault/example"))
    }

    func testSnoozeAddUsesExactArgvAndConfirmsAdded() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_SNOOZE_ADD_JSON": """
                    {"schema_version":1,"date":"2026-10-08",\
                    "now":"2026-10-08T12:00:00-04:00","status":"added",\
                    "task":{"route":"tasks.md","block_id":"^job","title":"Email Dan"},\
                    "target":{"time":"12:15","at":"2026-10-08T12:15:00-04:00"},\
                    "lane":"next","daily_file":"2026/20261008.md",\
                    "plan":{"count":1,"cap":10,"over":false},"dry_run":false}
                    """,
            ]
        )

        let response = try await client.snoozeAdd(route: "tasks.md", blockID: "^job")

        XCTAssertTrue(response.didWrite)
        XCTAssertEqual(response.snoozedUntilLabel, "12:15")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=snooze add tasks.md:^job +15m -f json"))
    }

    func testSnoozeAddMutationSurvivesAConcurrentRead() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_SNOOZE_ADD_DELAY_SECONDS": "0.4",
            ]
        )

        async let mutation = client.snoozeAdd(route: "tasks.md", blockID: "^job")
        async let read = client.snoozeList()
        let (addResponse, listResponse) = try await (mutation, read)

        XCTAssertTrue(addResponse.didWrite)
        XCTAssertEqual(listResponse.schemaVersion, 1)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=snooze add tasks.md:^job +15m -f json"))
        XCTAssertTrue(record.contains("argv=snooze -f json"))
    }

    func testSnoozeListAndAddMapOldBobToUnsupported() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_SNOOZE_UNSUPPORTED": "1",
            ]
        )

        for _ in 0..<2 {
            do {
                _ = try await client.snoozeList()
                XCTFail("Expected unsupported snooze list")
            } catch BobClientError.unsupportedCommand(let command) {
                XCTAssertEqual(command, "snooze list")
            }
            do {
                _ = try await client.snoozeAdd(route: "tasks.md", blockID: "^job")
                XCTFail("Expected unsupported snooze add")
            } catch BobClientError.unsupportedCommand(let command) {
                XCTAssertEqual(command, "snooze add")
            }
        }

        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=snooze -f json").count - 1, 1)
        XCTAssertEqual(
            record.components(separatedBy: "argv=snooze add").count - 1, 1)
        XCTAssertTrue(client.snoozeListKnownUnsupported)
        XCTAssertTrue(client.snoozeAddKnownUnsupported)
    }

    func testSnoozeListRejectsSchemaMismatchAndMalformedOutput() async throws {
        let mismatch = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_SNOOZE_LIST_JSON": #"{"schema_version":2,"rows":[]}"#,
            ]
        )
        do {
            _ = try await mismatch.snoozeList()
            XCTFail("Expected schema mismatch")
        } catch BobClientError.schemaMismatch(_, let expected, let actual) {
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(actual, 2)
        }

        let malformed = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_SNOOZE_ADD_JSON": "{",
            ]
        )
        do {
            _ = try await malformed.snoozeAdd(route: "tasks.md", blockID: "^job")
            XCTFail("Expected malformed JSON")
        } catch BobClientError.malformedJSON {
            // Expected.
        }
    }
}
