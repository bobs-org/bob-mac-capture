import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureMergeInPanelTests: XCTestCase {
    func testCompleteSingleItemAnnouncesSettledSourcesOnce() async throws {
        let record = temporaryURL()
        let parse = try parseFixture("capture-merge-in-parse-two.json")
        let model = try makeModel(
            record: record,
            parseFixture: "capture-merge-in-parse-two.json",
            dryRunFixture: "capture-merge-in-complete-two.json"
        )
        model.plainDraft = parse.input
        model.editorTextDidChange(cursorUTF8Offset: parse.input.utf8.count)
        await waitUntil {
            self.isReady(model)
                && model.mergeInPresentation != nil
                && model.mergeInAnnouncementTick == 1
        }

        let presentation = try XCTUnwrap(model.mergeInPresentation)
        XCTAssertEqual(model.primaryActionTitle, "Capture & merge 2 tasks")
        XCTAssertTrue(model.primaryActionEnabled)
        XCTAssertEqual(model.statusText, presentation.statusLineText)
        XCTAssertEqual(model.mergeInAnnouncement, presentation.settledAnnouncement)
        XCTAssertEqual(model.mergeInAnnouncementTick, 1)

        model.preview()
        await waitUntil { !model.isPreviewing && self.isReady(model) }
        XCTAssertEqual(model.mergeInAnnouncementTick, 1)

        model.plainDraft = "Revised outcome < @inbox+aaa @inbox+bbb"
        model.preview()
        await waitUntil { !model.isPreviewing && self.isReady(model) }
        XCTAssertEqual(model.mergeInAnnouncementTick, 1)
    }

    func testMixedBulkKeepsCaptureActionWithoutMergeBandOrAnnouncement() async throws {
        let record = temporaryURL()
        let parse = try parseFixture("capture-merge-in-parse-bulk-mixed.json")
        let model = try makeModel(
            record: record,
            parseFixture: "capture-merge-in-parse-bulk-mixed.json",
            dryRunFixture: "capture-merge-in-complete-task-list.json"
        )
        model.plainDraft = parse.input
        model.editorTextDidChange(cursorUTF8Offset: parse.input.utf8.count)
        await waitUntil { self.isReady(model) && model.previewResults.count == 2 }

        XCTAssertEqual(model.primaryActionTitle, "Capture")
        XCTAssertNil(model.mergeInPresentation)
        XCTAssertEqual(model.mergeInAnnouncementTick, 0)
    }

    func testChangedSourceSetAnnouncesOnce() async throws {
        let record = temporaryURL()
        let parse = try parseFixture("capture-merge-in-parse-two.json")
        let model = try makeModel(
            record: record,
            parseFixture: "capture-merge-in-parse-two.json",
            dryRunFixture: "capture-merge-in-complete-one.json",
            dryRunNextFixture: "capture-merge-in-complete-two.json"
        )
        model.plainDraft = parse.input
        model.editorTextDidChange(cursorUTF8Offset: parse.input.utf8.count)
        await waitUntil { self.isReady(model) && model.mergeInAnnouncementTick == 1 }
        XCTAssertEqual(model.mergeInPresentation?.count, 1)

        model.preview()
        await waitUntil {
            !model.isPreviewing
                && self.isReady(model)
                && model.mergeInPresentation?.count == 2
                && model.mergeInAnnouncementTick == 2
        }
        XCTAssertEqual(model.mergeInAnnouncementTick, 2)
    }

    func testLabelDrivenMergeBuildsSingleSourceBand() async throws {
        let record = temporaryURL()
        let parse = try parseFixture("capture-merge-in-parse-one.json")
        let model = try makeModel(
            record: record,
            parseFixture: "capture-merge-in-parse-one.json",
            dryRunFixture: "capture-merge-in-complete-label.json"
        )
        model.plainDraft = parse.input
        model.editorTextDidChange(cursorUTF8Offset: parse.input.utf8.count)
        await waitUntil { self.isReady(model) && model.mergeInPresentation != nil }

        XCTAssertEqual(model.primaryActionTitle, "Capture & merge 1 task")
        XCTAssertEqual(model.mergeInPresentation?.count, 1)
    }

    func testRefusalDisablesSubmitAndExplicitRewriteClearsIt() async throws {
        let record = temporaryURL()
        let parse = try parseFixture("capture-merge-in-parse-rewrite-spacing.json")
        let refusal =
            #"{"ok":false,"code":"merge_in_arrow_spacing","error":"capture item 1 starting on line 1: put spaces around <: New task < @a+x"}"#
        let model = try makeModel(
            record: record,
            parseFixture: "capture-merge-in-parse-rewrite-spacing.json",
            dryRunOutput: refusal,
            dryRunExit: "1"
        )
        model.plainDraft = parse.input
        model.editorTextDidChange(cursorUTF8Offset: parse.input.utf8.count)
        await waitUntil {
            !model.isPreviewing && model.mergeInRefusalPresentation != nil
        }

        XCTAssertEqual(model.mergeInRefusalPresentation?.rewrites.map(\.label), ["Add spaces"])
        XCTAssertFalse(model.primaryActionEnabled)
        let message = try XCTUnwrap(model.mergeInRefusalPresentation?.message.text)
        model.submit(openAfterCapture: false)
        XCTAssertEqual(model.plainDraft, "text<@inbox+aaa")
        XCTAssertEqual(model.statusText, message)
        let recorded = try String(contentsOf: record, encoding: .utf8)
        XCTAssertFalse(
            recorded.split(separator: "\n").contains {
                $0.hasPrefix("argv=capture ") && !$0.contains("--dry-run")
            })

        let rewrite = try XCTUnwrap(model.mergeInRefusalPresentation?.rewrites.first)
        XCTAssertTrue(model.applyDiagnosticRewrite(rewrite))
        XCTAssertEqual(model.plainDraft, "text < @inbox+aaa")
        XCTAssertNil(model.mergeInRefusalPresentation)
    }

    func testExecutableSwitchInvalidatesPendingTargetTitle() async throws {
        let record = temporaryURL()
        let pending =
            #"{"ok":false,"error":"pick tasks to merge in after <","code":"incomplete_merge_in","merge_in_pending":{"item":1,"need":"merge_in_source","sources":[{"block_id":"aaa","line":5,"marker":"@inbox+aaa","mergeable":true,"path":"inbox.md","status_name":"Ready","status_symbol":" ","title":"Alpha task"}]}}"#
        let model = try makeModel(
            record: record,
            parseFixture: "capture-merge-in-parse-pending-plus.json",
            dryRunOutput: pending,
            dryRunExit: "1"
        )
        let draft = try parseFixture("capture-merge-in-parse-pending-plus.json").input
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.currentMergeInPending != nil }

        XCTAssertEqual(model.currentMergeInPendingTargetTitle, "New outcome")
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        XCTAssertNil(model.currentMergeInPending)
        XCTAssertNil(model.currentMergeInPendingTargetTitle)
    }

    private func makeModel(
        record: URL,
        parseFixture: String,
        dryRunFixture: String? = nil,
        dryRunNextFixture: String? = nil,
        dryRunOutput: String? = nil,
        dryRunExit: String = "0"
    ) throws -> CapturePanelModel {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": record.path,
            "FAKE_BOB_PARSE_FIXTURE": parseFixture,
            "FAKE_BOB_CAPTURE_DRY_RUN_EXIT": dryRunExit,
        ]
        if let dryRunFixture {
            environment["FAKE_BOB_CAPTURE_DRY_RUN_FIRST_FIXTURE"] = dryRunFixture
            environment["FAKE_BOB_CAPTURE_DRY_RUN_NEXT_FIXTURE"] =
                dryRunNextFixture ?? dryRunFixture
        }
        if let dryRunOutput {
            environment["FAKE_BOB_CAPTURE_DRY_RUN_STDOUT"] = dryRunOutput
        }
        return CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: environment
            ),
            debounceNanoseconds: 0
        )
    }

    private func parseFixture(_ name: String) throws -> CaptureParseResponse {
        try JSONDecoder().decode(CaptureParseResponse.self, from: fixtureData(name))
    }

    private func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureDirectory.appendingPathComponent(name))
    }

    private var fixtureDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures", isDirectory: true)
    }

    private func fakeBobPath() throws -> String {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func isReady(_ model: CapturePanelModel) -> Bool {
        if case .ready = model.previewState { return true }
        return false
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
