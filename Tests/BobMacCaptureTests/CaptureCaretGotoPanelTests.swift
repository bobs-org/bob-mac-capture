import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureCaretGotoPanelTests: XCTestCase {
    private func model(
        draft: String,
        recordURL: URL? = nil,
        caretFixtures: Bool = true,
        extraEnvironment: [String: String] = [:],
        stash: CanceledDraftStash? = nil
    ) throws -> (CapturePanelModel, URL) {
        let record = recordURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("caret-goto-\(UUID().uuidString).log")
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": record.path,
        ]
        if caretFixtures {
            environment["FAKE_BOB_CARET_GOTO_FIXTURES"] = "1"
        }
        environment.merge(extraEnvironment) { _, replacement in replacement }
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: environment
        )
        let model = CapturePanelModel(
            processClient: client,
            debounceNanoseconds: 5_000_000,
            canceledDraftStash: stash
        )
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        return (model, record)
    }

    func testFoundCardSkipsDryRunAndRechecksBeforeOpening() async throws {
        let (model, record) = try model(draft: "@bob^focus")
        await waitUntil { model.caretGoto?.status == .found }

        XCTAssertEqual(model.primaryActionTitle, "Go To ↗")
        XCTAssertTrue(model.primaryActionEnabled)
        XCTAssertFalse(model.openHintChipVisible)
        if case .idle = model.previewState {
        } else {
            XCTFail("caret Go To should not start a capture preview")
        }

        var opened: [URL] = []
        var completion: (@MainActor (Bool) -> Void)?
        var dismissed = 0
        model.taskGotoOpener = { url, reply in
            opened.append(url)
            completion = reply
        }
        model.panelDismisser = { dismissed += 1 }

        model.submit(openAfterCapture: false)
        await waitUntil { opened.count == 1 }
        model.submit(openAfterCapture: true)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(opened.count, 1, "overlapping Return paths dispatch once")
        let expected = try XCTUnwrap(
            ObsidianOpenURL.taskGotoURL(
                path: "/tmp/bob-caret-goto-fixture-vault/vault/bob.md",
                line: 8,
                ref: "8:ed4da41c",
                blockID: "focus"
            )
        )
        XCTAssertEqual(
            opened[0],
            expected
        )
        XCTAssertTrue(try String(contentsOf: record).contains("argv=capture-parse"))
        XCTAssertFalse(try String(contentsOf: record).contains("--dry-run"))

        completion?(true)
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testReturnBeforeFirstParseWaitsThenUsesFreshGotoPath() async throws {
        let (model, record) = try model(draft: "@bob^focus")
        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }

        model.submit(openAfterCapture: false)
        await waitUntil { opened.count == 1 }

        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(model.plainDraft, "")
        let log = try String(contentsOf: record)
        XCTAssertGreaterThanOrEqual(parseCount(in: log), 2)
        XCTAssertFalse(log.contains("--dry-run"))
    }

    func testFreshParseThatBecomesAMissUpdatesCardAndKeepsDraft() async throws {
        let (model, _) = try model(
            draft: "@bob^focus",
            extraEnvironment: [
                "FAKE_BOB_CARET_GOTO_REFRESH_FIXTURE":
                    "task-caret-goto-parse-missing-on-refresh.json",
            ]
        )
        await waitUntil { model.caretGoto?.status == .found }
        var opened = 0
        model.taskGotoOpener = { _, completion in
            opened += 1
            completion(true)
        }

        model.submit(openAfterCapture: false)
        await waitUntil { model.caretGoto?.status == .missingBlockID }

        XCTAssertEqual(opened, 0)
        XCTAssertEqual(model.plainDraft, "@bob^focus")
        XCTAssertEqual(model.primaryActionTitle, "Go To ↗")
        XCTAssertFalse(model.primaryActionEnabled)
        XCTAssertFalse(model.taskGotoDispatchInFlight)
    }

    func testMissAndDuplicateReturnDoNotDispatchButDuplicateHitDoes() async throws {
        let (miss, _) = try model(draft: "@bob^focuz")
        await waitUntil { miss.caretGoto?.status == .missingBlockID }
        var missOpens = 0
        miss.taskGotoOpener = { _, completion in
            missOpens += 1
            completion(true)
        }
        miss.submit(openAfterCapture: false)
        XCTAssertEqual(missOpens, 0)

        let (duplicate, _) = try model(draft: "@bob^duplicate")
        await waitUntil { duplicate.caretGoto?.status == .duplicateBlockID }
        var opened: [URL] = []
        duplicate.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        duplicate.submit(openAfterCapture: false)
        XCTAssertTrue(opened.isEmpty)
        let hit = try XCTUnwrap(duplicate.caretGoto?.hits.first)
        duplicate.acceptCaretGotoHit(hit)
        XCTAssertEqual(
            opened,
            [
                ObsidianOpenURL.taskGotoURL(
                    path: hit.target,
                    line: hit.line,
                    ref: hit.ref,
                    blockID: hit.blockID
                )!,
            ]
        )
    }

    func testDispatchFailureKeepsDraftAndCtrlCDoesNotStash() async throws {
        let stash = CanceledDraftStash(capacity: 10)
        let (model, _) = try model(draft: "@bob^focus", stash: stash)
        await waitUntil { model.caretGoto?.status == .found }
        model.taskGotoOpener = { _, completion in completion(false) }
        model.submit(openAfterCapture: false)
        await waitUntil { model.statusText == "Couldn't open Obsidian" }
        XCTAssertEqual(model.plainDraft, "@bob^focus")

        model.stashDraftAndClose()
        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testOldBobWithoutGotoUsesExistingTaskPreviewPath() async throws {
        let (model, record) = try model(
            draft: "@bob^focus",
            caretFixtures: false,
            extraEnvironment: [
                "FAKE_BOB_PARSE_FIXTURE": "task-caret-goto-parse-old-bob.json",
            ]
        )
        await waitUntil { model.latestParse?.mode == "task" }
        XCTAssertNil(model.caretGoto)
        XCTAssertEqual(model.primaryActionTitle, "Capture")
        await waitUntil {
            (try? String(contentsOf: record).contains("--dry-run")) == true
        }
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot.appendingPathComponent("Tests/Fixtures/fake-bob").path
    }

    private func parseCount(in log: String) -> Int {
        log.components(separatedBy: .newlines)
            .filter { $0.hasPrefix("argv=capture-parse") }
            .count
    }

    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
