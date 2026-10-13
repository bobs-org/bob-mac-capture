import Foundation
import XCTest

@testable import CaptureCore

final class CapturePullInClientTests: XCTestCase {
    func testExplicitKeysAndNoneStayBeforeDelimiterAndPreserveDraftAndSeed() async throws {
        let record = temporaryRecordURL()
        let client = try makeClient(record: record)
        let draft = "complete task\nsecond line"

        _ = try await client.capture(
            draft,
            readClipboard: false,
            priorityRollSeed: "stable-seed",
            pullInSelection: .keys(["digest#one^suffix:2", "opaque:second#^key"]),
            pullInCapabilityAdvertised: true
        )
        _ = try await client.capture(
            draft,
            pullInSelection: CapturePullInSelection.none,
            pullInCapabilityAdvertised: true
        )

        let calls = try recordText(record)
        XCTAssertTrue(calls.contains("argv=capture --format json --no-clip --pull-in digest#one^suffix:2,opaque:second#^key -- \(draft)"))
        XCTAssertTrue(calls.contains("argv=capture --format json --pull-in none -- "))
        XCTAssertTrue(calls.contains(draft))
        XCTAssertTrue(calls.contains("BOB_PRIORITY_ROLL_SEED=stable-seed"))
        XCTAssertEqual(calls.components(separatedBy: "argv=capture").count - 1, 2)
    }

    func testExplicitSelectionRequiresMatchingCapabilityAdvertisement() async throws {
        let record = temporaryRecordURL()
        let client = try makeClient(record: record)
        do {
            _ = try await client.capture("draft", pullInSelection: .keys(["opaque:key"]))
            XCTFail("Expected capability guard")
        } catch BobClientError.unsupportedOption(let option) {
            XCTAssertEqual(option, "--pull-in")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: record.path))
    }

    func testExactOldGuardRejectionRetriesOnceAndCachesByExecutableIdentity() async throws {
        let record = temporaryRecordURL()
        let client = try makeClient(
            record: record,
            extraEnvironment: ["FAKE_BOB_GUARD_FLAG_UNSUPPORTED": "1"]
        )

        _ = try await client.capture("draft", priorityRollSeed: "same-seed", requirePullInChoice: true)
        XCTAssertTrue(client.pullInGuardKnownUnsupported)
        _ = try await client.capture("draft", priorityRollSeed: "same-seed", requirePullInChoice: true)

        let calls = try recordText(record)
        let invocations = Array(calls.components(separatedBy: "argv=capture").dropFirst())
        XCTAssertEqual(invocations.count, 3)
        XCTAssertTrue(invocations[0].contains("--require-pull-in-choice"))
        XCTAssertFalse(invocations[1].contains("--require-pull-in-choice"))
        XCTAssertFalse(invocations[2].contains("--require-pull-in-choice"))
        XCTAssertEqual(calls.components(separatedBy: "BOB_PRIORITY_ROLL_SEED=same-seed").count - 1, 3)
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
                "FAKE_BOB_GUARD_FLAG_UNSUPPORTED": "1",
            ]
        )
        _ = try await client.capture("draft", requirePullInChoice: true)
        XCTAssertTrue(client.pullInGuardKnownUnsupported)

        var contents = try Data(contentsOf: executable)
        contents.append(Data("\n# executable replaced\n".utf8))
        try contents.write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        XCTAssertFalse(client.pullInGuardKnownUnsupported)
        _ = try await client.capture("draft", requirePullInChoice: true)

        XCTAssertEqual(try recordText(record).components(separatedBy: "argv=capture").count - 1, 4)
    }

    func testStructuredRefusalStaleKeyAndUnrelatedErrorsAreNeverRetried() async throws {
        let refusal = #"{"ok":false,"error":"Choose offers","code":"pull_in_choice_required","pull_in":{"supported":true,"offer_count":1,"choice":"explicit","picked_count":0},"offers":[{"offer":{"key":"opaque:key","n":1,"group":"hand_off"}}]}"#
        let refusalRecord = temporaryRecordURL()
        let refusalClient = try makeClient(
            record: refusalRecord,
            extraEnvironment: ["FAKE_BOB_STDOUT": refusal, "FAKE_BOB_EXIT": "1"]
        )
        guard case .failure(let failure) = try await refusalClient.capture(
            "draft",
            requirePullInChoice: true
        ) else {
            return XCTFail("Expected structured refusal")
        }
        XCTAssertEqual(failure.code, "pull_in_choice_required")
        XCTAssertEqual(try recordText(refusalRecord).components(separatedBy: "argv=capture").count - 1, 1)

        let staleRecord = temporaryRecordURL()
        let staleClient = try makeClient(
            record: staleRecord,
            extraEnvironment: ["FAKE_BOB_STALE_PULL_IN": "1"]
        )
        guard case .failure(let stale) = try await staleClient.capture(
            "draft",
            requirePullInChoice: true
        ) else {
            return XCTFail("Expected stale-key refusal")
        }
        XCTAssertEqual(stale.code, "pull_in_stale")
        XCTAssertEqual(try recordText(staleRecord).components(separatedBy: "argv=capture").count - 1, 1)

        let unrelatedRecord = temporaryRecordURL()
        let unrelatedClient = try makeClient(
            record: unrelatedRecord,
            extraEnvironment: [
                "FAKE_BOB_STDOUT": "",
                "FAKE_BOB_EXIT": "2",
                "FAKE_BOB_STDERR": "error: unexpected argument '--some-other-flag' found",
            ]
        )
        do {
            _ = try await unrelatedClient.capture("draft", requirePullInChoice: true)
            XCTFail("Expected unrelated argument failure")
        } catch BobClientError.processFailed(_, let exitStatus, _) {
            XCTAssertEqual(exitStatus, 2)
        }
        XCTAssertEqual(try recordText(unrelatedRecord).components(separatedBy: "argv=capture").count - 1, 1)
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
            throw NSError(domain: "CapturePullInClientTests", code: 1)
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
        #"{"ok":true,"dry_run":false,"routed":false,"route_label":"","relative_target":"day.md","target":"/tmp/day.md","text":"task","task_line":"- [ ] Task","kind":"task","created":"2026-10-13","placement":"new"}"#
    }
}
