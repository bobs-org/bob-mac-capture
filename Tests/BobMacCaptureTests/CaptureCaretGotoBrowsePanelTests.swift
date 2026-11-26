import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Panel tests for the scoped Go To browse (mac-browse): the picker opens
/// with Go rows over the miss card, Return and clicks land, Tab completes,
/// and body text falls back to today's mint composer.
@MainActor
final class CaptureCaretGotoBrowsePanelTests: XCTestCase {
    private func model(
        draft: String,
        parseFixture: String,
        completeFixture: String,
        extraEnvironment: [String: String] = [:]
    ) throws -> CapturePanelModel {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_PARSE_FIXTURE": parseFixture,
            "FAKE_BOB_CAPTURE_COMPLETE_FIXTURE": completeFixture,
        ]
        environment.merge(extraEnvironment) { _, replacement in replacement }
        let client = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: environment
        )
        let model = CapturePanelModel(
            processClient: client,
            debounceNanoseconds: 5_000_000
        )
        model.plainDraft = draft
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        return model
    }

    private func browseModel() throws -> CapturePanelModel {
        try model(
            draft: "@bob^foc",
            parseFixture: "task-caret-goto-parse-partial.json",
            completeFixture: "block-id-goto-partial.json"
        )
    }

    func testBrowseOpensOverMissCardWithPrefixSelected() async throws {
        let model = try browseModel()
        await waitUntil { model.pickerVisible }

        // The partial ID matches nothing exactly: the calm miss card sits
        // behind the picker while the prefix row leads the browse.
        await waitUntil { model.caretGoto?.status == .missingBlockID }
        XCTAssertEqual(model.picker?.filterText, "foc")
        let presentation = try XCTUnwrap(model.pickerPresentation)
        XCTAssertEqual(
            presentation.sections.map { $0.title },
            ["Go To · bob.md", "Archived · done/bob_done.md"]
        )
        XCTAssertEqual(
            presentation.orderedRowIDs,
            ["goto:bob.md:focus", "goto:done/bob_done.md:archived-focus"]
        )
        XCTAssertEqual(model.picker?.selectedRowID, "goto:bob.md:focus")
        let row = try XCTUnwrap(presentation.row(id: "goto:bob.md:focus"))
        XCTAssertNotNil(row.taskGotoDestination)
        XCTAssertEqual(row.insertion, "focus")
    }

    func testReturnLandsFromBrowseRow() async throws {
        let model = try browseModel()
        await waitUntil { model.pickerVisible }

        var opened: [URL] = []
        var dismissed = 0
        model.taskGotoOpener = { url, reply in
            opened.append(url)
            reply(true)
        }
        model.panelDismisser = { dismissed += 1 }

        model.acceptSelectedPickerRow(submitAfterInsert: false)
        await waitUntil { dismissed == 1 }

        XCTAssertEqual(
            opened,
            [
                ObsidianOpenURL.taskGotoURL(
                    path: "/tmp/bob-caret-goto-fixture-vault/vault/bob.md",
                    line: 8,
                    ref: "8:ed4da41c",
                    blockID: "focus"
                )!,
            ]
        )
        XCTAssertEqual(model.plainDraft, "")
        // No capture runs for a read-only landing.
        XCTAssertNil(model.lastSuccess)
    }

    func testControlReturnAndClickLand() async throws {
        let model = try browseModel()
        await waitUntil { model.pickerVisible }

        var opened: [URL] = []
        model.taskGotoOpener = { url, reply in
            opened.append(url)
            reply(true)
        }

        // Control-Return is accept-and-submit-and-open for block-ID rows;
        // the browse still lands read-only instead of capturing.
        model.acceptSelectedPickerRowAndSubmitAndOpen()
        await waitUntil { opened.count == 1 }
        XCTAssertEqual(model.plainDraft, "")

        let clicked = try browseModel()
        await waitUntil { clicked.pickerVisible }
        var clickedOpened: [URL] = []
        clicked.taskGotoOpener = { url, reply in
            clickedOpened.append(url)
            reply(true)
        }
        clicked.acceptPickerRow(id: "goto:bob.md:focus", submitAfterInsert: false)
        await waitUntil { clickedOpened.count == 1 }
        XCTAssertEqual(clickedOpened, opened)
    }

    func testTabCompletesIntoTheDraft() async throws {
        let model = try browseModel()
        await waitUntil { model.pickerVisible }

        model.completeSelectedBlockIDGotoRow()

        XCTAssertEqual(model.plainDraft, "@bob^focus")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), "@bob^focus".utf8.count)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Inserted @bob^focus")
    }

    func testNoMatchRowNeverDispatches() async throws {
        let model = try browseModel()
        await waitUntil { model.pickerVisible }

        model.updatePickerFilter("zzz-no-such-id")
        let presentation = try XCTUnwrap(model.pickerPresentation)
        XCTAssertEqual(presentation.orderedRowIDs, [])
        let row = try XCTUnwrap(presentation.row(id: "goto-empty:zzz-no-such-id"))
        XCTAssertFalse(row.isSelectable)

        var opened = 0
        model.taskGotoOpener = { _, completion in
            opened += 1
            completion(true)
        }
        model.acceptSelectedPickerRow(submitAfterInsert: false)
        XCTAssertEqual(opened, 0)
        XCTAssertTrue(model.pickerVisible)
    }

    func testArchivedRowLandsInTheArchive() async throws {
        let model = try model(
            draft: "@bob^archived",
            parseFixture: "task-caret-goto-parse-archived-partial.json",
            completeFixture: "block-id-goto-archived.json"
        )
        await waitUntil { model.pickerVisible }

        let presentation = try XCTUnwrap(model.pickerPresentation)
        XCTAssertTrue(
            presentation.orderedRowIDs.contains("goto:done/bob_done.md:archived-focus")
        )

        var opened: [URL] = []
        model.taskGotoOpener = { url, reply in
            opened.append(url)
            reply(true)
        }
        model.acceptPickerRow(id: "goto:done/bob_done.md:archived-focus", submitAfterInsert: false)
        await waitUntil { opened.count == 1 }
        XCTAssertEqual(
            opened,
            [
                ObsidianOpenURL.taskGotoURL(
                    path: "/tmp/bob-caret-goto-fixture-vault/vault/done/bob_done.md",
                    line: 7,
                    ref: "7:96f239f1",
                    blockID: "archived-focus"
                )!,
            ]
        )
        XCTAssertEqual(model.plainDraft, "")
    }

    func testEmptyFilterHidesArchivedSection() async throws {
        let model = try model(
            draft: "@bob^",
            parseFixture: "task-caret-goto-parse-empty.json",
            completeFixture: "block-id-goto-empty.json"
        )
        await waitUntil { model.pickerVisible }

        let presentation = try XCTUnwrap(model.pickerPresentation)
        XCTAssertEqual(presentation.sections.map { $0.title }, ["Go To · bob.md"])
        XCTAssertEqual(presentation.orderedRowIDs, ["goto:bob.md:focus"])
        XCTAssertEqual(model.picker?.selectedRowID, "goto:bob.md:focus")
    }

    func testMintDraftKeepsTodaysComposerWithNoRedFlash() async throws {
        let model = try model(
            draft: "Fix it @bob^new-id",
            parseFixture: "task-caret-goto-parse-mint.json",
            completeFixture: "block-id-goto-mint.json",
            extraEnvironment: [
                "FAKE_BOB_CAPTURE_DRY_RUN_STDOUT": dryRunMintFixture(),
            ]
        )
        await waitUntil { model.pickerVisible }

        XCTAssertNil(model.caretGoto)
        guard case .blockID = model.picker?.source else {
            XCTFail("expected a block-ID picker source")
            return
        }
        // Today's New ID composer: the new-ID row is selectable, no Go rows.
        XCTAssertTrue(
            model.pickerPresentation?.orderedRowIDs.contains("new:new-id") == true
        )
        XCTAssertFalse(
            model.pickerPresentation?.orderedRowIDs.contains { $0.hasPrefix("goto:") } == true
        )
        // The mint dry run succeeds: a calm preview, never a red flash.
        await waitUntil {
            if case .ready = model.previewState {
                return true
            }
            return false
        }
        XCTAssertNil(model.errorMessage)
    }

    private func dryRunMintFixture() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: packageRoot
                .appendingPathComponent("Tests/Fixtures/capture-dry-run-mint-new-id.json"),
            encoding: .utf8
        )
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot = source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return packageRoot.appendingPathComponent("Tests/Fixtures/fake-bob").path
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
