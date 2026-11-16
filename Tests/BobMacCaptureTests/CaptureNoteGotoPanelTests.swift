import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Go To Notes panel wiring: grammar snapshots, reserved keys, chip recovery,
/// read-only dispatch, and stale task-picker replies.
@MainActor
final class CaptureNoteGotoPanelTests: XCTestCase {
    func testFastDraftOpensFilteredCatalogIncludingViews() async throws {
        let (model, recordURL) = try noteGotoModel()
        model.plainDraft = "//monthly"
        model.editorTextDidChange(cursorUTF8Offset: 9)
        await waitUntil { model.pickerVisible }

        XCTAssertTrue(model.pickerSourceIsNoteGoto)
        XCTAssertEqual(model.picker?.filterText, "monthly")
        XCTAssertEqual(model.pickerPresentation?.orderedRowIDs, ["Views/Monthly.base"])
        XCTAssertTrue(model.picker?.candidates.contains { $0.kind == "view" } ?? false)
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-complete"))
        XCTAssertFalse(record.contains("argv=capture --"))
    }

    func testSlashContinuationFromTasksOpensNotes() async throws {
        let (model, _) = try noteGotoModel()
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible && model.pickerSourceIsTaskGoto }
        XCTAssertTrue(model.pickerOperatorContinuationKeys.contains("/"))

        model.continuePickerOperator("/")
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        XCTAssertEqual(model.plainDraft, "//")
    }

    func testEscapeChipReopensTheSameSearch() async throws {
        let (model, _) = try noteGotoModel()
        model.plainDraft = "//cash"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }

        model.escapePicker()
        XCTAssertEqual(model.picker?.filterText, "")
        model.escapePicker()
        XCTAssertTrue(model.pickerChipVisible)
        XCTAssertEqual(model.pickerChip?.source, .noteGoto)

        model.openPickerFromChip()
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        XCTAssertEqual(model.picker?.filterText, "cash")
        XCTAssertEqual(model.pickerPresentation?.orderedRowIDs, ["Areas/cash.md"])
    }

    func testBackspacePeelsNotesThenTasksThenBlank() async throws {
        let (model, _) = try noteGotoModel()
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }

        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "/")
        await waitUntil { model.pickerVisible && model.pickerSourceIsTaskGoto }

        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "")
        await waitUntil { !model.pickerVisible }
    }

    func testAcceptDispatchesLineLessOpenURLAndDoesNotCapture() async throws {
        let stash = CanceledDraftStash(capacity: 10)
        let (model, recordURL) = try noteGotoModel(stash: stash)
        model.plainDraft = "//cash"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        var opened: [URL] = []
        var dismissed = 0
        model.taskGotoOpener = { url, completion in
            opened.append(url)
            completion(true)
        }
        model.panelDismisser = { dismissed += 1 }

        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: true)

        XCTAssertEqual(opened.count, 1)
        let url = try XCTUnwrap(opened.first)
        XCTAssertEqual(url.scheme, "obsidian")
        XCTAssertEqual(url.host, "bob-open-notes")
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(items.first { $0.name == "count" }?.value, "1")
        XCTAssertEqual(
            items.first { $0.name == "path1" }?.value,
            "/tmp/bob-note-goto-fixture-vault/vault/Areas/cash.md"
        )
        XCTAssertNil(items.first { $0.name == "line1" })
        XCTAssertEqual(dismissed, 1)
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(stash.entries.isEmpty)
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("argv=capture --"))
    }

    func testOpenFailureKeepsPickerAndDoubleAcceptDispatchesOnce() async throws {
        let (model, _) = try noteGotoModel()
        model.plainDraft = "//cash"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        model.taskGotoOpener = { _, completion in completion(false) }
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: false)
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.plainDraft, "//cash")
        XCTAssertEqual(model.statusText, "Couldn't open Obsidian")

        var opened = 0
        var pending: (@MainActor (Bool) -> Void)?
        model.taskGotoOpener = { _, completion in
            opened += 1
            pending = completion
        }
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: false)
        model.acceptPickerRow(id: "Areas/cash.md", submitAfterInsert: true)
        XCTAssertEqual(opened, 1)
        XCTAssertTrue(model.taskGotoDispatchInFlight)
        pending?(true)
        XCTAssertFalse(model.taskGotoDispatchInFlight)
        XCTAssertFalse(model.pickerVisible)
    }

    func testCtrlCDiscardsNavigationDraftWithoutStashing() throws {
        let stash = CanceledDraftStash(capacity: 10)
        let model = CapturePanelModel(canceledDraftStash: stash)
        let (candidates, noteGoto) = try catalogFixture()
        model.installNoteGotoPickerForPreviews(
            candidates: candidates,
            noteGoto: noteGoto,
            draft: "//"
        )
        XCTAssertNil(model.stashDraftForTermination())

        model.stashDraftAndClose()

        XCTAssertTrue(stash.entries.isEmpty)
        XCTAssertEqual(model.plainDraft, "")
    }

    func testRouterReservesNotesKeysAndUsesAdvertisedTaskContinuation() {
        let router = CaptureKeyCommandRouter()
        let notes = CaptureKeyRoutingContext(
            pickerHasSelection: true,
            pickerVisible: true,
            pickerSourceIsNoteGoto: true,
            pickerFilterIsEmpty: true
        )
        XCTAssertEqual(router.command(for: keyEvent(36), context: notes), .acceptPickerRow)
        XCTAssertEqual(router.command(for: keyEvent(48), context: notes), .acceptPickerRow)
        XCTAssertEqual(
            router.command(for: keyEvent(36, modifiers: .command), context: notes),
            .acceptPickerRow
        )
        XCTAssertEqual(
            router.command(for: keyEvent(36, modifiers: .control), context: notes),
            .acceptPickerRow
        )
        XCTAssertEqual(
            router.command(for: keyEvent(36, modifiers: .shift), context: notes), .consumeKey)
        XCTAssertEqual(
            router.command(for: keyEvent(36, modifiers: .option), context: notes), .consumeKey)
        XCTAssertEqual(
            router.command(for: keyEvent(7, modifiers: .command, characters: "x"), context: notes),
            .toggleGotoArchivedNotes
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(7, modifiers: .command, characters: "x", isRepeat: true),
                context: notes
            ),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(for: keyEvent(42, characters: "\\"), context: notes), .consumeKey)
        XCTAssertEqual(
            router.command(for: keyEvent(44, characters: "/"), context: notes), .consumeKey)
        XCTAssertEqual(
            router.command(
                for: keyEvent(42, characters: "\\"),
                context: CaptureKeyRoutingContext(draftIsBlank: true)
            ),
            .openGotoFromBackslash
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(36),
                context: CaptureKeyRoutingContext(
                    pickerHasSelection: false,
                    pickerVisible: true,
                    pickerSourceIsNoteGoto: true,
                    pickerFilterIsEmpty: true
                )
            ),
            .consumeKey
        )

        let tasks = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerSourceIsTaskGoto: true,
            pickerFilterIsEmpty: true,
            pickerOperatorContinuationKeys: ["/"],
            draftIsBareGotoSigil: true
        )
        XCTAssertEqual(
            router.command(for: keyEvent(44, characters: "/"), context: tasks),
            .continuePickerOperator("/")
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(44, characters: "/"),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskGoto: true,
                    pickerFilterIsEmpty: true,
                    draftIsBareGotoSigil: true
                )
            ),
            .showNoteGotoUpgradeHint
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(42, characters: "\\"),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskGoto: true,
                    pickerFilterIsEmpty: true,
                    draftIsBareGotoSigil: true
                )
            ),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(42, characters: "\\"),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskGoto: true,
                    pickerFilterIsEmpty: true,
                    draftIsBareGotoSigil: true,
                    backslashLiteralArmed: true
                )
            ),
            .typeLiteralBackslash
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(44, characters: "/", isRepeat: true),
                context: tasks
            ),
            .consumeKey
        )
        XCTAssertEqual(
            router.command(
                for: keyEvent(44, characters: "/"),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskGoto: true,
                    pickerFilterIsEmpty: true,
                    pickerOperatorContinuationKeys: ["/"],
                    draftIsBareGotoSigil: true,
                    editorHasMarkedText: true
                )
            ),
            .consumeKey
        )
    }

    func testOldBobShowsUpgradeHintAndNeverTypesSlashIntoCapture() async throws {
        let (model, recordURL) = try noteGotoModel(
            extraEnvironment: ["FAKE_BOB_NOTE_GOTO_OLD_TASKS": "1"]
        )
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible && model.pickerSourceIsTaskGoto }
        XCTAssertTrue(model.pickerOperatorContinuationKeys.isEmpty)

        let router = CaptureKeyCommandRouter()
        XCTAssertEqual(
            router.command(
                for: keyEvent(44, characters: "/"),
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    pickerSourceIsTaskGoto: true,
                    pickerFilterIsEmpty: true,
                    pickerOperatorContinuationKeys: model.pickerOperatorContinuationKeys,
                    draftIsBareGotoSigil: true
                )
            ),
            .showNoteGotoUpgradeHint
        )

        model.showNoteGotoUpgradeHint()

        XCTAssertEqual(model.statusText, "Update bob to search notes")
        XCTAssertEqual(model.plainDraft, "/")
        let record = try String(contentsOf: recordURL)
        XCTAssertFalse(record.contains("argv=capture --"))
    }

    func testLateTasksResponseCannotReplaceNewNotesPicker() async throws {
        let recordURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let marker = URL(fileURLWithPath: recordURL.path + ".late-task")
        let (model, _) = try noteGotoModel(
            recordURL: recordURL,
            extraEnvironment: [
                "FAKE_BOB_NOTE_GOTO_TASK_DELAY_SECONDS": "0.4",
                "FAKE_BOB_NOTE_GOTO_TASK_DELAY_MARKER": marker.path,
            ]
        )
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { self.markerExists(marker) }
        model.plainDraft = "//cash"
        model.editorTextDidChange(cursorUTF8Offset: 6)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        try await Task.sleep(nanoseconds: 500_000_000)

        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsNoteGoto)
        XCTAssertEqual(model.picker?.filterText, "cash")
    }

    func testContinuationKeepsCardMountedAndServesWarmSnapshot() async throws {
        let (model, _) = try noteGotoModel()
        // Fill the warm snapshot with a validated `//` response.
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        XCTAssertFalse(model.noteGotoSnapshotStore.isEmpty)

        // Peel back to Tasks, then continue: the card must stay mounted.
        model.removePickerTrigger()
        await waitUntil { model.pickerVisible && model.pickerSourceIsTaskGoto }
        let taskBudget = model.picker?.visibleRowBudget

        model.continuePickerOperator("/")
        // Synchronous: no teardown, warm rows render before the fetch lands.
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsNoteGoto)
        XCTAssertEqual(model.picker?.draftSnapshot, "//")
        XCTAssertEqual(model.picker?.visibleRowBudget, taskBudget)
        XCTAssertTrue(model.pickerPresentation?.orderedRowIDs.contains("Areas/cash.md") ?? false)

        await waitUntil { model.statusText.hasPrefix("Go To Notes,") }
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsNoteGoto)
        XCTAssertEqual(model.picker?.visibleRowBudget, taskBudget)
    }

    func testContinuationWithoutWarmSnapshotShowsLoadingPlaceholder() async throws {
        let (model, _) = try noteGotoModel(extraEnvironment: [
            "FAKE_BOB_CAPTURE_COMPLETE_DELAY_SECONDS": "0.5",
        ])
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible && model.pickerSourceIsTaskGoto }

        // The prefetch is still in flight, so no warm rows exist yet: the
        // swap mounts the quiet loading placeholder, never a spinner.
        model.continuePickerOperator("/")
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsNoteGoto)
        XCTAssertEqual(model.pickerPresentation?.emptyState, .loadingNotes)
        XCTAssertEqual(model.pickerPresentation?.orderedRowIDs, [])

        await waitUntil { model.statusText.hasPrefix("Go To Notes,") }
        XCTAssertTrue(model.pickerPresentation?.orderedRowIDs.contains("Areas/cash.md") ?? false)
    }

    func testSwapFailureMountsUnavailableCard() async throws {
        let (model, _) = try noteGotoModel(extraEnvironment: [
            "FAKE_BOB_NOTE_GOTO_FAIL_NOTES": "1",
        ])
        model.plainDraft = "/"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible && model.pickerSourceIsTaskGoto }

        model.continuePickerOperator("/")
        XCTAssertTrue(model.pickerVisible)
        await waitUntil { model.pickerPresentation?.emptyState == .notesUnavailable }
        XCTAssertEqual(model.statusText, "Couldn't load notes")
        // The card stays mounted on the failure state; nothing is captured.
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsNoteGoto)
        XCTAssertNotEqual(
            model.pickerPresentation?.emptyState,
            .noMatches(query: "cash")
        )
    }

    func testSelectionSurvivesSwapRefresh() async throws {
        let (model, _) = try noteGotoModel(extraEnvironment: [
            "FAKE_BOB_CAPTURE_COMPLETE_DELAY_SECONDS": "0.5",
        ])
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        let first = try XCTUnwrap(model.picker?.selectedRowID)
        XCTAssertFalse(model.noteGotoSnapshotStore.isEmpty)

        // Peel to Tasks and continue back: the warm snapshot renders first.
        model.removePickerTrigger()
        await waitUntil { model.pickerVisible && model.pickerSourceIsTaskGoto }
        model.continuePickerOperator("/")
        XCTAssertTrue(model.pickerSourceIsNoteGoto)

        // Move off the first row while the real fetch is still running.
        model.selectNextPickerRow()
        let moved = try XCTUnwrap(model.picker?.selectedRowID)
        XCTAssertNotEqual(moved, first)

        // The real response replaces the warm rows but keeps the live row.
        await waitUntil { model.statusText.hasPrefix("Go To Notes,") }
        XCTAssertEqual(model.picker?.selectedRowID, moved)
    }

    func testNotesFilterTypingSpawnsNoBobProcess() async throws {
        let (model, recordURL) = try noteGotoModel()
        model.plainDraft = "//"
        model.editorTextDidChange(cursorUTF8Offset: 2)
        await waitUntil { model.pickerVisible && model.pickerSourceIsNoteGoto }
        let completionsBefore = try String(contentsOf: recordURL)
            .components(separatedBy: "\n")
            .filter { $0.contains("argv=capture-complete") }
            .count
        XCTAssertGreaterThan(completionsBefore, 0)

        model.updatePickerFilter("c")
        model.updatePickerFilter("ca")
        model.updatePickerFilter("cash")
        try await Task.sleep(nanoseconds: 200_000_000)

        let completionsAfter = try String(contentsOf: recordURL)
            .components(separatedBy: "\n")
            .filter { $0.contains("argv=capture-complete") }
            .count
        XCTAssertEqual(completionsAfter, completionsBefore)
        XCTAssertTrue(model.pickerPresentation?.orderedRowIDs.contains("Areas/cash.md") ?? false)
    }

    private func noteGotoModel(
        recordURL: URL? = nil,
        stash: CanceledDraftStash? = nil,
        extraEnvironment: [String: String] = [:]
    ) throws -> (CapturePanelModel, URL) {
        let url =
            recordURL
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": url.path,
            "FAKE_BOB_NOTE_GOTO_FIXTURES": "1",
        ]
        environment.merge(extraEnvironment) { _, replacement in replacement }
        let model = CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: environment
            ),
            debounceNanoseconds: 5_000_000,
            canceledDraftStash: stash
        )
        return (model, url)
    }

    private func catalogFixture() throws -> (
        [CaptureCompletionCandidate], CaptureCompletionNoteGoto
    ) {
        let source = URL(fileURLWithPath: #filePath)
        let fixture =
            source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/note-goto.json")
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self,
            from: Data(contentsOf: fixture)
        )
        return (response.candidates, try XCTUnwrap(response.noteGoto))
    }

    private func fakeBobPath() throws -> String {
        let source = URL(fileURLWithPath: #filePath)
        let packageRoot =
            source
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return
            packageRoot
            .appendingPathComponent("Tests/Fixtures/fake-bob")
            .path
    }

    private func markerExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
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
        _ keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags = [],
        characters: String = "",
        isRepeat: Bool = false
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
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }
}
