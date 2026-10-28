import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Go To picker panel wiring: dispatch, keys, ID-less open, Ctrl-C discard.
@MainActor
final class CaptureTaskGotoPanelTests: XCTestCase {
    private func identifiedCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            route: "sase",
            taskRef: "6:41d049f2",
            target: "/tmp/bob-fixture/sase.md",
            blockID: "deep-fix",
            statusSymbol: "*",
            statusName: "Next",
            text: "Fix deep bug",
            section: "Bugs",
            line: 6,
            group: "queued",
            notePath: "sase.md"
        )
    }

    private func idlessCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            route: "sase",
            taskRef: "7:446bd057",
            target: "/tmp/bob-fixture/sase.md",
            statusSymbol: " ",
            statusName: "Todo",
            text: "Fix flaky gkeep test",
            section: "Bugs",
            line: 7,
            group: "note",
            notePath: "sase.md"
        )
    }

    private func expectedURL(
        line: Int,
        ref: String,
        blockID: String? = nil
    ) -> URL {
        ObsidianOpenURL.taskGotoURL(
            path: "/tmp/bob-fixture/sase.md",
            line: line,
            ref: ref,
            blockID: blockID
        )!
    }

    private func installTwoRowPicker(filter: String = "") -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installTaskGotoPickerForPreviews(
            candidates: [identifiedCandidate(), idlessCandidate()],
            filter: filter,
            draft: "/",
            replacement: CaptureRange(start: 0, end: 1)
        )
        return model
    }

    func testNeedStatusAndSourceStrings() {
        XCTAssertEqual(
            CapturePickerNeed.taskGoto.statusText,
            "Pick a task to open — press Tab to browse"
        )
        XCTAssertEqual(CapturePickerSource.taskGoto.scopeCaption, "Go To")
        XCTAssertEqual(CapturePickerSource.taskGoto.triggerByte, 47)
    }

    func testAcceptDispatchesURLAndDismissesWithoutStash() {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        model.installTaskGotoPickerForPreviews(
            candidates: [identifiedCandidate(), idlessCandidate()],
            draft: "/",
            replacement: CaptureRange(start: 0, end: 1)
        )
        var opened: [URL] = []
        var dismissed = 0
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        model.panelDismisser = { dismissed += 1 }

        model.acceptPickerRow(id: "sase|6:41d049f2", submitAfterInsert: false)

        XCTAssertEqual(opened, [expectedURL(line: 6, ref: "6:41d049f2", blockID: "deep-fix")])
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertFalse(model.hasDraft)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertFalse(model.taskGotoDispatchInFlight)
    }

    func testCommandReturnEqualsReturnAndDoesNotCapture() {
        let model = installTwoRowPicker()
        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        model.acceptPickerRow(id: "sase|6:41d049f2", submitAfterInsert: true)
        XCTAssertEqual(opened.count, 1)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testIdlessRowOpensDirectlyWithNoPrompt() {
        let model = installTwoRowPicker()
        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        model.acceptPickerRow(id: "sase|7:446bd057", submitAfterInsert: false)
        XCTAssertEqual(opened, [expectedURL(line: 7, ref: "7:446bd057")])
        XCTAssertFalse(model.taskIDPromptVisible)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testShiftReturnDoesNothing() {
        let model = installTwoRowPicker()
        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        model.acceptPickerRowAndStart(id: "sase|6:41d049f2")
        XCTAssertTrue(opened.isEmpty)
        XCTAssertEqual(model.plainDraft, "/")
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsTaskGoto)
        XCTAssertFalse(model.pickerSourceIsTaskLink)
    }

    func testDispatchFailureKeepsPickerAndDraft() {
        let model = installTwoRowPicker()
        var dismissed = 0
        model.taskGotoOpener = { _, completion in
            completion(false)
        }
        model.panelDismisser = { dismissed += 1 }
        model.acceptPickerRow(id: "sase|6:41d049f2", submitAfterInsert: false)
        XCTAssertEqual(dismissed, 0)
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.plainDraft, "/")
        XCTAssertEqual(model.statusText, "Couldn't open Obsidian")
        XCTAssertFalse(model.taskGotoDispatchInFlight)
    }

    func testMissingDestinationKeepsPickerOpen() {
        let model = CapturePanelModel()
        model.installTaskGotoPickerForPreviews(
            candidates: [
                CaptureCompletionCandidate(
                    replacement: "",
                    route: "inbox",
                    taskRef: "1:abcd1234",
                    text: "Call the bank",
                    line: 1,
                    notePath: "Inbox.md"
                ),
            ],
            draft: "/",
            replacement: CaptureRange(start: 0, end: 1)
        )
        var opened = 0
        model.taskGotoOpener = { _, completion in
            opened += 1
            completion(true)
        }
        model.acceptPickerRow(id: "inbox|1:abcd1234", submitAfterInsert: false)
        XCTAssertEqual(opened, 0)
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.plainDraft, "/")
        XCTAssertEqual(
            model.statusText,
            "bob sent no location for this task — update bob"
        )
    }

    func testDoubleReturnDuringInFlightOpensOnce() {
        let model = installTwoRowPicker()
        var opened: [URL] = []
        var pending: (@MainActor (Bool) -> Void)?
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            pending = completion
        }
        model.acceptPickerRow(id: "sase|6:41d049f2", submitAfterInsert: false)
        XCTAssertTrue(model.taskGotoDispatchInFlight)
        model.acceptPickerRow(id: "sase|6:41d049f2", submitAfterInsert: true)
        XCTAssertEqual(opened.count, 1)
        pending?(true)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertFalse(model.taskGotoDispatchInFlight)
    }

    func testStaleDraftAcceptClosesWithoutOpening() {
        let model = installTwoRowPicker()
        var opened = 0
        model.taskGotoOpener = { _, completion in
            opened += 1
            completion(true)
        }
        model.plainDraft = "/changed"
        model.acceptPickerRow(id: "sase|6:41d049f2", submitAfterInsert: false)
        XCTAssertEqual(opened, 0)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.plainDraft, "/changed")
        XCTAssertEqual(model.statusText, "Draft changed — reopen the task picker")
    }

    func testRouterMappingsForTaskGoto() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerSourceIsTaskLink: false
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36), context: context),
            .acceptPickerRow
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48), context: context),
            .acceptPickerRow
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .command), context: context),
            .acceptPickerRowAndSubmit
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .shift), context: context),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .option), context: context),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 8, modifiers: .control), context: context),
            .stashDraftAndClose
        )
        let inFlight = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerDispatchInFlight: true
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36), context: inFlight),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 8, modifiers: .control), context: inFlight),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 0, characters: "a"), context: inFlight),
            .consumeKey
        )
    }

    func testSlashOpensGotoPickerWithOneCaptureComplete() async throws {
        let (model, recordURL) = try gotoModel()
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }

        XCTAssertTrue(model.pickerSourceIsTaskGoto)
        XCTAssertFalse(model.pickerSourceIsTaskLink)
        XCTAssertEqual(model.picker?.filterText, "")
        XCTAssertEqual(model.picker?.candidates.count, 8)
        XCTAssertNil(model.completionResponse)
        XCTAssertEqual(model.statusText, "Pick a task to open — press Tab to browse")
        XCTAssertEqual(model.previewState, .idle)
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-complete").count - 1, 1)
        XCTAssertFalse(record.contains("argv=capture --"))
        XCTAssertFalse(record.contains("argv=capture-task-id"))
    }

    func testSlashChipReopensWithoutRefetch() async throws {
        let (model, recordURL) = try gotoModel()
        model.plainDraft = "/"
        model.editorSelectionDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerChipVisible }

        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.pickerChip?.source, .taskGoto)

        model.openPickerFromChip()
        await waitUntil { model.pickerVisible }

        XCTAssertTrue(model.pickerSourceIsTaskGoto)
        XCTAssertEqual(model.picker?.candidates.count, 8)
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-complete").count - 1, 1)
    }

    func testSlashDeePresentsPartialAfterRefetchAtZero() async throws {
        let (model, recordURL) = try gotoModel()
        model.plainDraft = "/dee"
        model.editorTextDidChange(cursorUTF8Offset: 4)
        await waitUntil { model.pickerVisible }

        XCTAssertTrue(model.pickerSourceIsTaskGoto)
        XCTAssertEqual(model.picker?.filterText, "dee")
        XCTAssertEqual(model.picker?.candidates.count, 1)
        XCTAssertEqual(model.picker?.snapshotIsPartial, true)
        let record = try String(contentsOf: recordURL)
        XCTAssertEqual(record.components(separatedBy: "argv=capture-complete").count - 1, 2)
        XCTAssertTrue(record.contains("argv=capture-complete --all-tasks --cursor 0 "))
    }

    func testLiveAcceptByReturnTabAndCommandReturn() async throws {
        for submitAfter in [false, true] {
            let (model, recordURL) = try gotoModel()
            var opened: [URL] = []
            var dismissed = 0
            model.taskGotoOpener = { url, completion in
                opened.append(url)
                completion(true)
            }
            model.panelDismisser = { dismissed += 1 }
            model.plainDraft = "/"
            model.editorTextDidChange(cursorUTF8Offset: 1)
            await waitUntil { model.pickerVisible }

            model.acceptSelectedPickerRow(submitAfterInsert: submitAfter)

            XCTAssertEqual(
                opened,
                [expectedURL(line: 6, ref: "6:41d049f2", blockID: "deep-fix")]
            )
            XCTAssertEqual(dismissed, 1)
            XCTAssertEqual(model.plainDraft, "")
            XCTAssertFalse(model.hasDraft)
            XCTAssertTrue(model.stashEntries.isEmpty)
            let record = try String(contentsOf: recordURL)
            XCTAssertFalse(record.contains("argv=capture --"))
            XCTAssertFalse(record.contains("argv=capture-task-id"))
        }
    }

    func testLiveIdlessRowOpensDirectly() async throws {
        let (model, recordURL) = try gotoModel()
        var opened: [URL] = []
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }

        model.acceptPickerRow(id: "sase|7:446bd057", submitAfterInsert: false)

        XCTAssertEqual(opened, [expectedURL(line: 7, ref: "7:446bd057")])
        XCTAssertFalse(model.taskIDPromptVisible)
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("argv=capture-task-id"))
        XCTAssertFalse(record.contains("argv=capture --"))
    }

    func testLiveShiftReturnDoesNothing() async throws {
        let (model, _) = try gotoModel()
        var opened = 0
        model.taskGotoOpener = { _, completion in
            opened += 1
            completion(true)
        }
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }
        model.acceptSelectedPickerRowAndStart()
        XCTAssertEqual(opened, 0)
        XCTAssertEqual(model.plainDraft, "/")
        XCTAssertTrue(model.pickerVisible)
    }

    func testBackspaceOnEmptyFilterRemovesSlash() async throws {
        let (model, _) = try gotoModel()
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }
        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertFalse(model.hasDraft)
        XCTAssertFalse(model.pickerVisible)
    }

    func testTwoStageEscapeClearsFilterThenChips() async throws {
        let (model, _) = try gotoModel()
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }
        model.updatePickerFilter("dee")
        model.escapePicker()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.picker?.filterText, "")
        model.escapePicker()
        XCTAssertFalse(model.pickerVisible)
        await waitUntil { model.pickerChipVisible }
        XCTAssertEqual(model.pickerChip?.source, .taskGoto)
    }

    func testCtrlCOnGotoDraftDiscardsInsteadOfStashing() async throws {
        let stash = CanceledDraftStash(capacity: 10)
        let (model, _) = try gotoModel(stash: stash)
        model.plainDraft = "/dee"
        model.editorTextDidChange(cursorUTF8Offset: 4)
        await waitUntil { model.pickerVisible }
        model.stashDraftAndClose()
        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertEqual(model.statusText, "Canceled draft discarded")
    }

    func testStashDraftForTerminationDoesNotPushGotoDraft() async throws {
        let stash = CanceledDraftStash(capacity: 10)
        let (model, _) = try gotoModel(stash: stash)
        model.plainDraft = "/dee"
        model.editorTextDidChange(cursorUTF8Offset: 4)
        await waitUntil { model.pickerVisible }
        XCTAssertNil(model.stashDraftForTermination())
        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(model.plainDraft, "/dee")
        XCTAssertEqual(
            model.statusText,
            "Pick a task to open — press Tab to browse"
        )
    }

    private func gotoModel(
        recordURL: URL? = nil,
        stash: CanceledDraftStash? = nil
    ) throws -> (CapturePanelModel, URL) {
        let url = recordURL ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: [
                    "HOME": "/tmp",
                    "PATH": "/usr/bin:/bin",
                    "FAKE_BOB_RECORD_PATH": url.path,
                ]
            ),
            debounceNanoseconds: 5_000_000,
            canceledDraftStash: stash
        )
        return (model, url)
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

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = ""
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        )!
    }
}
