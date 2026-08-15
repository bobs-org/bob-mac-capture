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

    func testCaptureParseRunsMultilineDraftAsOneArgvElementAndDecodesSubBullets() async throws {
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
        let draft = nestedMultilineDraft()

        let response = try await client.captureParse(draft)

        XCTAssertEqual(response.body, "Prepare launch")
        XCTAssertEqual(
            response.subBullets,
            ["confirm owner", "text owner", "attach checklist", "verify links"]
        )
        XCTAssertEqual(response.subBulletDepths, [1, 2, 1, 2])
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- \(draft)"))
    }

    func testCaptureParseDecodesTaskBlockIDMarker() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )

        let response = try await client.captureParse("idea @ma::new-id")

        XCTAssertEqual(response.mode, "task")
        XCTAssertEqual(response.route, "ma")
        XCTAssertEqual(response.blockID, "new-id")
        XCTAssertEqual(response.spans.map(\.kind), ["task_block_id_route", "task_block_id"])
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

    func testCaptureCompleteTaskBlockIDMarkerCompletesRouteButNotAuthoredID() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )

        let route = try await client.captureComplete("idea @ma::new-id", cursor: 8)
        XCTAssertEqual(route.context, "route")
        XCTAssertEqual(route.replacement, CaptureRange(start: 6, end: 8))
        XCTAssertEqual(route.candidates.first?.route, "mac_inbox")

        let authoredID = try await client.captureComplete("idea @ma::new-id", cursor: 12)
        XCTAssertNil(authoredID.context)
        XCTAssertTrue(authoredID.candidates.isEmpty)
        XCTAssertEqual(authoredID.replacement, CaptureRange(start: 12, end: 12))
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

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful live preview response")
        }
        XCTAssertTrue(success.dryRun)
        XCTAssertEqual(success.taskLine, "- [ ] #task captured [created::2026-08-14]")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- buy milk % p:1"))
        XCTAssertTrue(record.contains("BOB_PRIORITY_ROLL_SEED=fixed"))
    }

    func testCaptureSubmitDecodesSuccessResponse() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )

        let response = try await client.capture("Call bank @Cash", dryRun: false, readClipboard: true)

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful capture response")
        }
        XCTAssertFalse(success.dryRun)
        XCTAssertEqual(success.routeLabel, "cash.md")
        XCTAssertEqual(success.target, "/tmp/bob/cash.md")
        XCTAssertEqual(success.placement, "inserted")
    }

    func testCaptureSubmitDecodesSingleClipPayloadWithOmittedEntriesAsSuccess() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":true,"dry_run":false,"routed":false,"route":null,"route_label":"","relative_target":"mac_inbox.md","target":"/tmp/tmp.GQUVrOEvrX/vault/mac_inbox.md","text":"test","task_line":"- [ ] #task test [created::2026-07-15]","kind":"task","created":"2026-07-15","scheduled":null,"placement":"created","clip":{"header":null,"mode":"inline","lines":["\t- hello-clip"],"attachments":[]}}"#,
            ]
        )

        let response = try await client.capture("test %", dryRun: false, readClipboard: true)

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful capture response")
        }
        XCTAssertFalse(success.dryRun)
        XCTAssertEqual(success.clip?.mode, "inline")
        XCTAssertEqual(success.clip?.entries, [])
    }

    func testCaptureSubmitDecodesRenderedSubBulletsForMultilineDraft() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        let draft = nestedMultilineDraft()

        let response = try await client.capture(draft, dryRun: false, readClipboard: true)

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful capture response")
        }
        XCTAssertEqual(success.taskLine, "- [ ] #task Prepare launch [created::2026-08-14]")
        XCTAssertEqual(success.subBullets, renderedNestedSubBullets())
    }

    func testCaptureSubmitDecodesOrdinaryTaskWithBlockID() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )

        let response = try await client.capture("idea @mac_inbox::new-id", dryRun: false, readClipboard: true)

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful capture response")
        }
        XCTAssertEqual(success.kind, "task")
        XCTAssertEqual(success.blockID, "new-id")
        XCTAssertNil(success.dayFile)
        XCTAssertNil(success.blockLink)
        XCTAssertNil(success.pomodoroLinkPlacement)
        XCTAssertEqual(success.taskLine, "- [ ] #task idea [created::2026-08-14] ^new-id")
    }

    func testLivePreviewDecodesRenderedSubBulletsForMultilineDraft() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        let draft = nestedMultilineDraft()

        let response = try await client.captureLivePreview(draft, priorityRollSeed: "fixed")

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful live preview response")
        }
        XCTAssertTrue(success.dryRun)
        XCTAssertEqual(success.subBullets, renderedNestedSubBullets())
    }

    func testCapturePreviewRunsDryRunWithoutSuppressingClipboard() async throws {
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

        let response = try await client.capture("Call bank @Cash", dryRun: true, readClipboard: true)

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful preview response")
        }
        XCTAssertTrue(success.dryRun)

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("--dry-run"))
        XCTAssertFalse(record.contains("--no-clip"))
    }

    func testCaptureFailureDecodesActionableErrorDespiteNonZeroExit() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":false,"error":"clipboard command xclip exited with 1"}"#,
                "FAKE_BOB_EXIT": "1",
            ]
        )

        let response = try await client.capture("private captured text", dryRun: false, readClipboard: true)

        guard case .failure(let failure) = response else {
            return XCTFail("Expected a failed capture response")
        }
        XCTAssertEqual(failure.error, "clipboard command xclip exited with 1")
        XCTAssertFalse(failure.error.contains("private captured text"))
    }

    func testCaptureEmptyStdoutWithNonZeroExitThrowsProcessFailed() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": "",
                "FAKE_BOB_STDERR": "boom",
                "FAKE_BOB_EXIT": "2",
            ]
        )

        do {
            _ = try await client.capture("private captured text", dryRun: false, readClipboard: true)
            XCTFail("Expected processFailed")
        } catch BobClientError.processFailed(_, let exitStatus, let stderr) {
            XCTAssertEqual(exitStatus, 2)
            XCTAssertTrue(stderr.contains("boom"))
        }
    }

    func testCaptureMalformedJSONWithZeroExitProducesMalformedJSONError() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": "{",
            ]
        )

        do {
            _ = try await client.capture("private captured text", dryRun: false, readClipboard: true)
            XCTFail("Expected malformedJSON")
        } catch BobClientError.malformedJSON(_, let exitStatus, _, _) {
            XCTAssertEqual(exitStatus, 0)
        }
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

    func testTerminationIgnoresProcessThatHasNotLaunched() {
        let process = Process()

        BobProcessClient.terminateIfRunning(process)

        XCTAssertFalse(process.isRunning)
    }

    func testRunTerminatesAndThrowsTimedOutWhenProcessOutlivesTheTimeout() async throws {
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

        do {
            _ = try await client.run(arguments: ["capture-targets"], lane: "targets", timeout: 0.3)
            XCTFail("Expected a timedOut error")
        } catch BobClientError.timedOut(let command, let seconds) {
            XCTAssertEqual(command.last, "capture-targets")
            XCTAssertEqual(seconds, 0.3)
        }

        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline && !FileManager.default.fileExists(atPath: termURL.path) {
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: termURL.path),
            "Expected the timed-out process to be terminated, not left running"
        )
    }

    func testRunCompletesNormallyWhenFasterThanTheTimeout() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )

        let result = try await client.run(arguments: ["capture-targets"], lane: "targets", timeout: 5)

        XCTAssertEqual(result.exitStatus, 0)
        XCTAssertFalse(result.stdout.isEmpty)
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

    private func nestedMultilineDraft() -> String {
        [
            "Prepare launch",
            "- confirm owner",
            "  - text owner",
            "- attach checklist",
            "  - verify links",
        ].joined(separator: "\n")
    }

    private func renderedNestedSubBullets() -> [String] {
        [
            "  - confirm owner",
            "    - text owner",
            "  - attach checklist",
            "    - verify links",
        ]
    }
}
