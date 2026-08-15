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

        let response = try await client.captureParse("Call bank @Cash+")

        XCTAssertEqual(response.body, "Call bank")
        XCTAssertEqual(response.mode, "incomplete")
        XCTAssertEqual(response.needs, ["task"])
        XCTAssertEqual(response.spans.map(\.kind), ["sub_bullet_route", "interactive_placeholder"])
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- Call bank @Cash+"))
        XCTAssertTrue(record.contains("PATH=/usr/bin:/bin"))
    }

    func testCaptureParseDecodesPlusSubBulletAndCaretIdOnlyMarkers() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )

        let subBullet = try await client.captureParse("Add context @file+parent-id")
        XCTAssertEqual(subBullet.mode, "sub_bullet")
        XCTAssertEqual(subBullet.blockID, "parent-id")
        XCTAssertEqual(subBullet.spans.map(\.kind), ["sub_bullet_route", "sub_bullet_block_id"])

        let authored = try await client.captureParse("Follow up @file^new-id")
        XCTAssertEqual(authored.mode, "task")
        XCTAssertEqual(authored.blockID, "new-id")
        XCTAssertEqual(authored.spans.map(\.kind), ["task_block_id_route", "task_block_id"])
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

    func testCaptureParseRunsBatchDraftAsOneArgvElementAndDecodesItems() async throws {
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
        let draft = "First item @Cash\n\nSecond item @notes#Ideas"

        let response = try await client.captureParse(draft)

        XCTAssertEqual(response.items.map(\.body), ["First item", "Second item"])
        XCTAssertEqual(response.items.compactMap(\.route), ["cash", "notes"])
        XCTAssertEqual(response.items[1].section, "Ideas")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-parse --format json -- \(draft)"))
        XCTAssertEqual(record.components(separatedBy: "argv=capture-parse").count - 1, 1)
    }

    func testCaptureParseDecodesTaskBlockIDMarker() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )

        let response = try await client.captureParse("idea @ma^new-id")

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
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 6 --format json -- idea @"))
    }

    func testCaptureCompleteRunsBatchDraftAsOneArgvElement() async throws {
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
        let draft = "First item @Cash\n\nSecond item @notes#Ideas"

        let response = try await client.captureComplete(draft, cursor: 36)

        XCTAssertEqual(response.context, "route")
        XCTAssertEqual(response.replacement, CaptureRange(start: 31, end: 36))
        XCTAssertEqual(response.candidates.first?.replacement, "notes")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 36 --format json -- \(draft)"))
        XCTAssertEqual(record.components(separatedBy: "argv=capture-complete").count - 1, 1)
    }

    func testCaptureCompleteAllTasksDecodesLaterBatchItemAsOneArgvElement() async throws {
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
        let draft = laterTaskBatchDraft()

        let response = try await client.captureComplete(draft, cursor: draft.utf8.count)

        XCTAssertEqual(response.context, "task")
        XCTAssertEqual(response.replacement, CaptureRange(start: 39, end: 43))
        XCTAssertEqual(response.candidates.map(\.text), ["Handoff ready", "Plan the handoff"])
        XCTAssertEqual(response.candidates.map(\.blockID), ["hand-ready", nil])
        guard response.candidates.count == 2 else {
            return
        }
        XCTAssertFalse(response.candidates[0].requiresBlockID)
        XCTAssertTrue(response.candidates[1].requiresBlockID)
        XCTAssertEqual(response.candidates[1].replacement, "")
        XCTAssertEqual(response.candidates[1].route, "file")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-complete --all-tasks --cursor 43 --format json -- \(draft)")
        )
        XCTAssertEqual(record.components(separatedBy: "argv=capture-complete").count - 1, 1)
    }

    func testCaptureCompleteTaskBlockIDMarkerCompletesRouteButNotAuthoredID() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )

        let route = try await client.captureComplete("idea @ma^new-id", cursor: 8)
        XCTAssertEqual(route.context, "route")
        XCTAssertEqual(route.replacement, CaptureRange(start: 6, end: 8))
        XCTAssertEqual(route.candidates.first?.route, "mac_inbox")

        let authoredID = try await client.captureComplete("idea @ma^new-id", cursor: 12)
        XCTAssertNil(authoredID.context)
        XCTAssertTrue(authoredID.candidates.isEmpty)
        XCTAssertEqual(authoredID.replacement, CaptureRange(start: 12, end: 12))
    }

    func testCaptureCompleteOffersTasksOnPlusSideAndNoneOnAuthoredCaretId() async throws {
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

        let plusSide = try await client.captureComplete("note @Cash+goog", cursor: 15)
        XCTAssertEqual(plusSide.context, "task")
        XCTAssertEqual(plusSide.candidates.first?.blockID, "goog-exit")
        XCTAssertFalse(plusSide.candidates.first?.requiresBlockID ?? true)
        XCTAssertEqual(plusSide.candidates[1].taskRef, "8:missingidea")
        XCTAssertTrue(plusSide.candidates[1].requiresBlockID)
        XCTAssertEqual(plusSide.candidates[1].replacement, "")

        let authoredId = try await client.captureComplete("Do work @Dev^new-id", cursor: 19)
        XCTAssertNil(authoredId.context)
        XCTAssertEqual(authoredId.candidates.count, 0)

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 15 --format json -- note @Cash+goog"))
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 19 --format json -- Do work @Dev^new-id"))
    }

    func testAssignCaptureTaskIDRunsDedicatedCommandAndDecodesSuccess() async throws {
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

        let response = try await client.assignCaptureTaskID(
            route: "file",
            taskRef: "8:missingidea",
            blockID: "new-id"
        )

        guard case .success(let success) = response else {
            return XCTFail("Expected assignment success")
        }
        XCTAssertEqual(success.schemaVersion, 1)
        XCTAssertEqual(success.route, "file")
        XCTAssertEqual(success.relativeTarget, "file.md")
        XCTAssertEqual(success.blockID, "new-id")
        XCTAssertEqual(success.task.blockID, "new-id")
        XCTAssertEqual(success.task.text, "Plan the handoff")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(
            record.contains("argv=capture-task-id --route file --task-ref 8:missingidea --block-id new-id --format json")
        )
    }

    func testAssignCaptureTaskIDDecodesJSONFailureOnNonZeroExit() async throws {
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_STDOUT": #"{"ok":false,"error":"block ID ^duplicate-id already exists in file.md"}"#,
                "FAKE_BOB_EXIT": "1",
            ]
        )

        let response = try await client.assignCaptureTaskID(
            route: "file",
            taskRef: "8:missingidea",
            blockID: "duplicate-id"
        )

        guard case .failure(let failure) = response else {
            return XCTFail("Expected assignment failure")
        }
        XCTAssertEqual(failure.error, "block ID ^duplicate-id already exists in file.md")
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

    func testLivePreviewDecodesBatchCapturesFromOneProcess() async throws {
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
        let draft = "First item @Cash\n\nSecond item @notes#Ideas"

        let response = try await client.captureLivePreview(draft, priorityRollSeed: "fixed")

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful live preview response")
        }
        XCTAssertEqual(success.normalizedCaptures.map(\.text), ["First item", "Second item"])
        XCTAssertTrue(success.normalizedCaptures.allSatisfy { $0.dryRun })
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture --dry-run --no-clip --format json -- \(draft)"))
        XCTAssertEqual(record.components(separatedBy: "argv=capture").count - 1, 1)
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

    func testCaptureSubmitDecodesAuthoredIdOnlyAndSubBulletModes() async throws {
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

        let authored = try await client.capture("Follow up @file^new-id", dryRun: false, readClipboard: true)
        guard case .success(let authoredSuccess) = authored else {
            return XCTFail("Expected authored ID capture success")
        }
        XCTAssertEqual(authoredSuccess.kind, "task")
        XCTAssertEqual(authoredSuccess.blockID, "new-id")
        XCTAssertEqual(authoredSuccess.taskLine, "- [ ] #task Follow up [created::2026-08-14] ^new-id")
        XCTAssertNil(authoredSuccess.dayFile)
        XCTAssertNil(authoredSuccess.blockLink)
        XCTAssertNil(authoredSuccess.pomodoroLinkPlacement)

        let nested = try await client.capture("Add context @file+parent-id", dryRun: false, readClipboard: true)
        guard case .success(let nestedSuccess) = nested else {
            return XCTFail("Expected sub-bullet capture success")
        }
        XCTAssertEqual(nestedSuccess.kind, "sub_bullet")
        XCTAssertEqual(nestedSuccess.blockID, "parent-id")
        XCTAssertEqual(nestedSuccess.parentText, "Parent")

        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture --format json -- Follow up @file^new-id"))
        XCTAssertTrue(record.contains("argv=capture --format json -- Add context @file+parent-id"))
    }

    func testCaptureSubmitDecodesBatchCapturesFromOneProcess() async throws {
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
        let draft = "First item @Cash\n\nSecond item @notes#Ideas"

        let response = try await client.capture(draft, dryRun: false, readClipboard: true)

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful capture response")
        }
        XCTAssertEqual(success.normalizedCaptures.map(\.relativeTarget), ["cash.md", "notes.md"])
        XCTAssertEqual(success.normalizedCaptures[1].previewBlockLines, ["- Second item", "  - nested detail"])
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture --format json -- \(draft)"))
        XCTAssertEqual(record.components(separatedBy: "argv=capture").count - 1, 1)
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

        let response = try await client.capture("idea @mac_inbox^new-id", dryRun: false, readClipboard: true)

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

    func testCapturePreviewDecodesBatchCapturesFromOneProcess() async throws {
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
        let draft = "First item @Cash\n\nSecond item @notes#Ideas"

        let response = try await client.capture(draft, dryRun: true, readClipboard: true)

        guard case .success(let success) = response else {
            return XCTFail("Expected a successful preview response")
        }
        XCTAssertTrue(success.normalizedCaptures.allSatisfy { $0.dryRun })
        XCTAssertEqual(success.normalizedCaptures.map(\.target), ["/tmp/bob/cash.md", "/tmp/bob/notes.md"])
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture --format json --dry-run -- \(draft)"))
        XCTAssertFalse(record.contains("--no-clip"))
        XCTAssertEqual(record.components(separatedBy: "argv=capture").count - 1, 1)
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

    private func laterTaskBatchDraft() -> String {
        "Plan café @Cash\n\nFile follow-up @file+hand"
    }
}
