import XCTest

@testable import CaptureCore

final class WalkAttentionClientTests: XCTestCase {
    func testWalkAttentionRecordsArgvAndDecodesSnapshot() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_WALKS_FIXTURE": "walks-all.json",
            ]
        )

        let fetch = try await client.walkAttention()

        guard case .changed(let snapshot, let bytes) = fetch else {
            XCTFail("Expected changed fetch")
            return
        }
        XCTAssertFalse(bytes.isEmpty)
        XCTAssertEqual(snapshot.date, "2026-11-17")
        XCTAssertEqual(snapshot.walks.map(\.family), [.review, .lanes, .bank])
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=walks --format json"))
    }

    func testWalkAttentionIdenticalBytesReturnsUnchanged() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_WALKS_FIXTURE": "walks-clear.json",
            ]
        )

        let first = try await client.walkAttention()
        guard case .changed(let snapshot, let bytes) = first else {
            XCTFail("Expected changed fetch")
            return
        }
        XCTAssertEqual(snapshot.walks.count, 3)

        let second = try await client.walkAttention(previous: bytes)
        XCTAssertEqual(second, .unchanged)

        let third = try await client.walkAttention(previous: Data("stale".utf8))
        guard case .changed(let again, _) = third else {
            XCTFail("Expected changed fetch for stale bytes")
            return
        }
        XCTAssertEqual(again, snapshot)
    }

    func testWalkAttentionUsesItsOwnLane() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
                "FAKE_BOB_WALKS_FIXTURE": "walks-all.json",
                "FAKE_BOB_AGENDA_FIXTURE": "agenda-current.json",
            ]
        )

        _ = try await client.captureAgenda()
        _ = try await client.walkAttention()
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=walks --format json"))
        XCTAssertTrue(record.contains("argv=capture-pomodoros --format json --tasks"))
    }

    func testWalkAttentionUnsupportedMapsOldBob() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_WALKS_UNSUPPORTED": "1",
            ]
        )

        do {
            _ = try await client.walkAttention()
            XCTFail("Expected unsupportedCommand")
        } catch BobClientError.unsupportedCommand(let command) {
            XCTAssertEqual(command, "walks")
        } catch {
            XCTFail("Expected unsupportedCommand, got \(error)")
        }
    }

    func testWalkAttentionFailureThrowsProcessFailed() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_WALKS_FAIL": "1",
            ]
        )

        do {
            _ = try await client.walkAttention()
            XCTFail("Expected processFailed")
        } catch BobClientError.processFailed(_, let exitStatus, _) {
            XCTAssertEqual(exitStatus, 1)
        } catch {
            XCTFail("Expected processFailed, got \(error)")
        }
    }

    func testWalkAttentionSchemaMismatchThrows() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":true,"schema_version":2,"walks":[]}"#,
            ]
        )

        do {
            _ = try await client.walkAttention()
            XCTFail("Expected schemaMismatch")
        } catch BobClientError.schemaMismatch(_, let expected, let actual) {
            XCTAssertEqual(expected, 1)
            XCTAssertEqual(actual, 2)
        } catch {
            XCTFail("Expected schemaMismatch, got \(error)")
        }
    }

    func testWalkAttentionMalformedJSONThrows() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": "not json",
            ]
        )

        do {
            _ = try await client.walkAttention()
            XCTFail("Expected malformedJSON")
        } catch BobClientError.malformedJSON {
        } catch {
            XCTFail("Expected malformedJSON, got \(error)")
        }
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let fakeBob = packageRoot.appendingPathComponent("Fixtures/fake-bob")
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: fakeBob.path))
        return fakeBob.path
    }
}
