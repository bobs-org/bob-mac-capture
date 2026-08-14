import Foundation
import XCTest

@testable import CaptureCore

final class BobProcessClientTests: XCTestCase {
    func testCaptureParseRunsDirectArgvAndDecodesJSON() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )

        let response = try await client.captureParse("Call bank @Cash^")

        XCTAssertEqual(response.body, "Call bank")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- Call bank @Cash^"))
        XCTAssertTrue(record.contains("PATH=/usr/bin:/bin"))
    }

    func testCaptureCompleteRunsCursorAwareEndpoint() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )

        let response = try await client.captureComplete("idea @", cursor: 6)

        XCTAssertEqual(response.context, "route")
        XCTAssertEqual(response.candidates.first?.replacement, "today")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete --cursor 6 --format json -- idea @"))
    }

    func testLivePreviewAlwaysUsesNoClipAndPrioritySeed() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": recordURL.path,
            ]
        )

        let response = try await client.captureLivePreview("buy milk % p:1", priorityRollSeed: "fixed")

        XCTAssertTrue(response.dryRun == true)
        XCTAssertEqual(response.taskLine, "- [ ] #task captured [created::2026-08-14]")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- buy milk % p:1"))
        XCTAssertTrue(record.contains("BOB_PRIORITY_ROLL_SEED=fixed"))
    }

    func testMalformedJSONProducesActionableErrorWithoutInputText() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": "{",
            ]
        )

        do {
            _ = try await client.captureParse("private captured text")
            XCTFail("Expected malformed JSON")
        } catch {
            let description = String(describing: error)
            XCTAssertTrue(description.contains("capture-parse"))
            XCTAssertFalse(description.contains("private captured text"))
        }
    }

    func testRefreshKeepsLastGoodTargetCacheOnFailure() async throws {
        let firstClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        let failingClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_EXIT": "2",
                "FAKE_BOB_STDERR": "boom",
            ]
        )
        let cache = CaptureTargetsCache()

        let first = await cache.refresh(using: firstClient) { Date(timeIntervalSince1970: 1) }
        let second = await cache.refresh(using: failingClient) { Date(timeIntervalSince1970: 2) }

        XCTAssertEqual(first.targets?.targets.first?.route, "today")
        XCTAssertEqual(second.targets?.targets.first?.route, "today")
        XCTAssertEqual(first.targets?.targets.first?.label, "today.md")
        XCTAssertTrue(second.stale)
        XCTAssertTrue(second.errorDescription?.contains("boom") == true)
    }

    func testCancellationTerminatesProcess() async throws {
        let termURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_DELAY_SECONDS": "5",
                "FAKE_BOB_TERM_PATH": termURL.path,
            ]
        )

        let task = Task {
            try await client.captureTargets()
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        task.cancel()
        _ = try? await task.value

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && !FileManager.default.fileExists(atPath: termURL.path) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: termURL.path))
    }

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
}
