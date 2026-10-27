import Foundation
import XCTest

@testable import CaptureCore

final class CaptureInboxRouteClientTests: XCTestCase {
    func testAnswersEmitRepeatedFlagsBeforeDelimiter() async throws {
        let record = temporaryRecordURL()
        let client = try makeClient(record: record)
        let draft = "link inbox task"

        _ = try await client.capture(
            draft,
            readClipboard: false,
            priorityRollSeed: "stable-seed",
            inboxRouteAnswers: [
                CaptureInboxRouteSubmission(key: "mac_inbox.md#^route-task", destination: "health.md"),
                CaptureInboxRouteSubmission(key: "gkeep_inbox.md#^gkeep-task"),
            ],
            inboxRouteCapabilityAdvertised: true
        )

        let calls = try recordText(record)
        XCTAssertTrue(
            calls.contains(
                "argv=capture --format json --no-clip --inbox-route mac_inbox.md#^route-task=health.md"
            ))
        XCTAssertTrue(calls.contains("--inbox-route gkeep_inbox.md#^gkeep-task= -- \(draft)"))
        XCTAssertTrue(calls.contains("BOB_PRIORITY_ROLL_SEED=stable-seed"))
        XCTAssertEqual(calls.components(separatedBy: "argv=capture").count - 1, 1)
    }

    func testAnswersWithoutCapabilityThrow() async throws {
        let record = temporaryRecordURL()
        let client = try makeClient(record: record)
        do {
            _ = try await client.capture(
                "draft",
                inboxRouteAnswers: [
                    CaptureInboxRouteSubmission(key: "opaque:key", destination: "health.md")
                ]
            )
            XCTFail("Expected capability guard")
        } catch BobClientError.unsupportedOption(let option) {
            XCTAssertEqual(option, "--inbox-route")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }

    func testEmptyKeyThrows() async throws {
        let record = temporaryRecordURL()
        let client = try makeClient(record: record)
        do {
            _ = try await client.capture(
                "draft",
                inboxRouteAnswers: [CaptureInboxRouteSubmission(key: "")],
                inboxRouteCapabilityAdvertised: true
            )
            XCTFail("Expected key guard")
        } catch BobClientError.unsupportedOption(let option) {
            XCTAssertEqual(option, "--inbox-route requires opaque candidate keys")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }

    func testRequireGuardWithoutCapabilitySendsNoGuardFlag() async throws {
        // An older bob without an `inbox_route.supported` preview gets no guard
        // flag, so it files the clean draft instead of a junk flag task.
        let record = temporaryRecordURL()
        let client = try makeClient(record: record)

        _ = try await client.capture("draft", requireInboxRouteChoice: true)

        let calls = try recordText(record)
        let invocations = Array(calls.components(separatedBy: "argv=capture").dropFirst())
        XCTAssertEqual(invocations.count, 1)
        XCTAssertFalse(invocations[0].contains("--require-inbox-route-choice"))
        XCTAssertTrue(invocations[0].contains("-- draft"))
    }

    func testRequireGuardWithCapabilitySendsGuardFlag() async throws {
        let record = temporaryRecordURL()
        let client = try makeClient(record: record)

        _ = try await client.capture(
            "draft",
            requireInboxRouteChoice: true,
            inboxRouteCapabilityAdvertised: true
        )

        let calls = try recordText(record)
        let invocations = Array(calls.components(separatedBy: "argv=capture").dropFirst())
        XCTAssertEqual(invocations.count, 1)
        XCTAssertTrue(invocations[0].contains("--require-inbox-route-choice -- draft"))
    }

    func testRememberedCapabilitySendsGuardWithoutPreviewFlag() async throws {
        // Once any decoded capture JSON carried `inbox_route.supported == true`,
        // Return sends the guard even when it beats the live preview.
        let record = temporaryRecordURL()
        let client = try makeClient(
            record: record,
            extraEnvironment: [
                "FAKE_BOB_STDOUT": "",
                "FAKE_BOB_CAPTURE_STDOUT": previewOneResponse(),
            ]
        )
        _ = try await client.captureLivePreview("preview", priorityRollSeed: "seed")
        XCTAssertTrue(client.inboxRouteCapabilityKnown)

        _ = try await client.capture("draft", requireInboxRouteChoice: true)

        let calls = try recordText(record)
        let invocations = Array(calls.components(separatedBy: "argv=capture").dropFirst())
        XCTAssertEqual(invocations.count, 2)
        XCTAssertTrue(invocations[1].contains("--require-inbox-route-choice -- draft"))
    }

    func testExactGuardRejectionRetriesOnceAndCachesByIdentity() async throws {
        let record = temporaryRecordURL()
        let client = try makeClient(
            record: record,
            extraEnvironment: ["FAKE_BOB_INBOX_ROUTE_GUARD_UNSUPPORTED": "1"]
        )

        _ = try await client.capture(
            "draft",
            readClipboard: false,
            requireInboxRouteChoice: true,
            inboxRouteCapabilityAdvertised: true
        )
        XCTAssertTrue(client.requireInboxRouteChoiceKnownUnsupported)
        _ = try await client.capture(
            "draft",
            readClipboard: false,
            requireInboxRouteChoice: true,
            inboxRouteCapabilityAdvertised: true
        )

        let calls = try recordText(record)
        let invocations = Array(calls.components(separatedBy: "argv=capture").dropFirst())
        XCTAssertEqual(invocations.count, 3)
        XCTAssertTrue(invocations[0].contains("--require-inbox-route-choice"))
        XCTAssertFalse(invocations[1].contains("--require-inbox-route-choice"))
        XCTAssertFalse(invocations[2].contains("--require-inbox-route-choice"))
    }

    func testStructuredRefusalsAreNeverRetried() async throws {
        let refusalRecord = temporaryRecordURL()
        let refusalClient = try makeClient(
            record: refusalRecord,
            extraEnvironment: ["FAKE_BOB_STDOUT": choiceRequiredResponse(), "FAKE_BOB_EXIT": "1"]
        )
        guard
            case .failure(let failure) = try await refusalClient.capture(
                "draft",
                requireInboxRouteChoice: true,
                inboxRouteCapabilityAdvertised: true
            )
        else {
            return XCTFail("Expected structured refusal")
        }
        XCTAssertEqual(failure.code, "inbox_route_choice_required")
        XCTAssertEqual(failure.inboxRoute?.candidateCount, 1)
        XCTAssertTrue(refusalClient.inboxRouteCapabilityKnown)
        XCTAssertEqual(
            try recordText(refusalRecord).components(separatedBy: "argv=capture").count - 1, 1)

        let staleRecord = temporaryRecordURL()
        let staleClient = try makeClient(
            record: staleRecord,
            extraEnvironment: ["FAKE_BOB_STALE_INBOX_ROUTE": "1"]
        )
        guard
            case .failure(let stale) = try await staleClient.capture(
                "draft",
                requireInboxRouteChoice: true,
                inboxRouteCapabilityAdvertised: true
            )
        else {
            return XCTFail("Expected stale-key refusal")
        }
        XCTAssertEqual(stale.code, "inbox_route_stale")
        XCTAssertEqual(try recordText(staleRecord).components(separatedBy: "argv=capture").count - 1, 1)

        let refusedRecord = temporaryRecordURL()
        let refusedClient = try makeClient(
            record: refusedRecord,
            extraEnvironment: ["FAKE_BOB_REFUSED_INBOX_ROUTE": "1"]
        )
        guard
            case .failure(let refused) = try await refusedClient.capture(
                "draft",
                requireInboxRouteChoice: true,
                inboxRouteCapabilityAdvertised: true
            )
        else {
            return XCTFail("Expected refused refusal")
        }
        XCTAssertEqual(refused.code, "inbox_route_refused")
        XCTAssertEqual(refused.refused?.key, "mac_inbox.md#^route-task")
        XCTAssertEqual(
            try recordText(refusedRecord).components(separatedBy: "argv=capture").count - 1, 1)
    }

    func testExecutableReplacementInvalidatesCachedGuardRejection() async throws {
        let record = temporaryRecordURL()
        let executable = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(atPath: try fakeBobPath(), toPath: executable.path)
        defer { try? FileManager.default.removeItem(at: executable) }
        let client = BobProcessClient(
            executablePath: executable.path,
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": record.path,
                "FAKE_BOB_STDOUT": successResponse(),
                "FAKE_BOB_INBOX_ROUTE_GUARD_UNSUPPORTED": "1",
            ]
        )
        _ = try await client.capture(
            "draft",
            readClipboard: false,
            requireInboxRouteChoice: true,
            inboxRouteCapabilityAdvertised: true
        )
        XCTAssertTrue(client.requireInboxRouteChoiceKnownUnsupported)

        var contents = try Data(contentsOf: executable)
        contents.append(Data("\n# executable replaced\n".utf8))
        try contents.write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        XCTAssertFalse(client.requireInboxRouteChoiceKnownUnsupported)
    }

    private func makeClient(
        record: URL,
        extraEnvironment: [String: String] = [:]
    ) throws -> BobProcessClient {
        BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_RECORD_PATH": record.path,
                "FAKE_BOB_STDOUT": successResponse(),
            ].merging(extraEnvironment) { _, override in override }
        )
    }

    private func fakeBobPath() throws -> String {
        let path = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/fake-bob")
            .path
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw NSError(domain: "CaptureInboxRouteClientTests", code: 1)
        }
        return path
    }

    private func temporaryRecordURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func recordText(_ url: URL) throws -> String {
        try String(contentsOf: url, encoding: .utf8)
    }

    private func successResponse() -> String {
        """
        {"ok":true,"dry_run":false,"routed":false,"route_label":"",
         "relative_target":"day.md","target":"/tmp/day.md","text":"task",
         "task_line":"- [ ] Task","kind":"task","created":"2026-10-13",
         "placement":"new"}
        """
    }

    private func previewOneResponse() -> String {
        """
        {"ok":true,"dry_run":true,"routed":true,
         "route_label":"mac_inbox.md","relative_target":"mac_inbox.md",
         "target":"/tmp/mac_inbox.md","text":"",
         "task_line":"- [*] #task Route me ^route-task","kind":"pomodoro_link",
         "created":"2026-10-24","placement":"linked",
         "inbox_route":{"supported":true,"candidate_count":1,"routed_count":0,
           "kept_count":0,
           "candidates":[{"key":"mac_inbox.md#^route-task","n":1,
             "note_path":"mac_inbox.md","inbox":"mac_inbox","block_id":"route-task",
             "line":6,"text":"Route me","previous_status_symbol":" ",
             "previous_status_name":"Ready","status_symbol":"*","status_name":"Next",
             "answer":null,"outcome":"pending"}]}}
        """
    }

    private func choiceRequiredResponse() -> String {
        """
        {"ok":false,"error":"this capture changes 1 inbox task; pass --inbox-route",
         "code":"inbox_route_choice_required",
         "inbox_route":{"supported":true,"candidate_count":1,"routed_count":0,
           "kept_count":0,
           "candidates":[{"key":"mac_inbox.md#^route-task","n":1,
             "note_path":"mac_inbox.md","inbox":"mac_inbox","block_id":"route-task",
             "line":6,"text":"Route me","previous_status_symbol":" ",
             "previous_status_name":"Ready","status_symbol":"*","status_name":"Next",
             "answer":null,"outcome":"pending"}]}}
        """
    }
}
