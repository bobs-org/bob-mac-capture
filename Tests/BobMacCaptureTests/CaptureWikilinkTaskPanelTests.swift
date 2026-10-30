import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Task Wikilink picker panel wiring: auto-open only on a written second
/// `(`, burst typing, and trailing `@@@`; the chip on caret moves and
/// Backspace; closed and multiword chip reopen; Escape suppression;
/// Backspace leaving `(`; accept/caret/no inline list; missing-replacement
/// no-op; filter clearing without a refetch; stale guard; the ID prompt
/// success/failure/Escape/filter-restoration/old-Bob paths; and
/// `--allow-closed` for Done and Cancelled history.
@MainActor
final class CaptureWikilinkTaskPanelTests: XCTestCase {
    private func identifiedCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "[[sase_cleanup#^no-idle]]",
            taskRef: "1:fa53e656",
            blockID: "no-idle",
            requiresBlockID: false,
            statusSymbol: "/",
            statusName: "In Progress",
            statusType: "IN_PROGRESS",
            text: "Stop idling when no agents run",
            cursorAfter: 35,
            linkTarget: "sase_cleanup",
            group: "in_progress",
            notePath: "sase_cleanup.md",
            locator: "sase_cleanup"
        )
    }

    private func idlessCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "2:c37a3d45",
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Inbox plain",
            linkTarget: "mac_inbox",
            blockIDSuggestions: ["inbox-plain"],
            group: "in_this_note",
            notePath: "mac_inbox.md",
            locator: "mac_inbox"
        )
    }

    private func historyCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "9:history000",
            requiresBlockID: true,
            statusSymbol: "x",
            statusName: "Done",
            statusType: "DONE",
            text: "Old done without id",
            linkTarget: "home",
            blockIDSuggestions: ["old-done"],
            group: "completed",
            notePath: "home.md",
            locator: "home"
        )
    }

    private func cancelledCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "6:cancelled000",
            requiresBlockID: true,
            statusSymbol: "-",
            statusName: "Cancelled",
            statusType: "CANCELLED",
            text: "Old cancelled without id",
            linkTarget: "home",
            blockIDSuggestions: ["old-cancelled"],
            group: "completed",
            notePath: "home.md",
            locator: "home"
        )
    }

    private func missingReplacementCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "3:missing000",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Replacement missing",
            linkTarget: "mac_inbox",
            group: "in_this_note",
            notePath: "mac_inbox.md",
            locator: "mac_inbox"
        )
    }

    private func disabledCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "7:gggg7777",
            blockID: "twin",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            statusType: "TODO",
            text: "Second twin",
            linkTarget: "twin",
            group: "open",
            notePath: "twin.md",
            locator: "twin",
            disabledReason: "duplicate block ID ^twin in twin.md"
        )
    }

    private func installPicker() -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installWikilinkTaskPickerForPreviews(
            candidates: [
                identifiedCandidate(), idlessCandidate(), historyCandidate(), disabledCandidate(),
            ],
            draft: "Follow up ((",
            replacement: CaptureRange(start: 10, end: 12)
        )
        return model
    }

    func testAcceptInsertsBobReplacement() {
        let model = installPicker()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsWikilinkTask)
        model.acceptPickerRow(id: "sase_cleanup.md|1:fa53e656", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "Follow up [[sase_cleanup#^no-idle]]")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Inserted [[sase_cleanup#^no-idle]]")
    }

    func testAcceptPlacesCaretAtCursorAfter() {
        let model = installPicker()
        model.acceptPickerRow(id: "sase_cleanup.md|1:fa53e656", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "Follow up [[sase_cleanup#^no-idle]]")
        XCTAssertEqual(model.collapsedSelectionUTF8Offset(), 35)
    }

    func testMarkerHighlightUsesBobDescriptor() {
        let model = installPicker()
        XCTAssertEqual(model.pickerMarkerHighlight, CaptureRange(start: 10, end: 12))
    }

    func testClosedChipReopenSeedsBobQuery() {
        let model = CapturePanelModel()
        model.installWikilinkTaskPickerForPreviews(
            candidates: [identifiedCandidate()],
            filter: "foo",
            draft: "Follow up ((foo))",
            replacement: CaptureRange(start: 10, end: 17)
        )
        XCTAssertTrue(model.pickerVisible)
        // First Escape clears the filter; second Escape parks the chip.
        model.escapePicker()
        model.escapePicker()
        XCTAssertTrue(model.pickerChipVisible)
        model.openPickerFromChip()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.picker?.filterText, "foo")
    }

    func testMultiwordChipReopenSeedsBobQuery() {
        let model = CapturePanelModel()
        model.installWikilinkTaskPickerForPreviews(
            candidates: [identifiedCandidate()],
            filter: "foo bar",
            draft: "Follow up ((foo bar))",
            replacement: CaptureRange(start: 10, end: 21)
        )
        XCTAssertTrue(model.pickerVisible)
        // First Escape clears the filter; second Escape parks the chip.
        model.escapePicker()
        model.escapePicker()
        XCTAssertTrue(model.pickerChipVisible)
        model.openPickerFromChip()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.picker?.filterText, "foo bar")
    }

    func testCancelledIdlessPromptCarriesAllowClosed() {
        let model = CapturePanelModel()
        model.installWikilinkTaskPickerForPreviews(
            candidates: [identifiedCandidate(), cancelledCandidate()],
            draft: "Follow up ((",
            replacement: CaptureRange(start: 10, end: 12)
        )
        model.acceptPickerRow(id: "home.md|6:cancelled000", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsWikilinkTask)
        if case .wikilinkTask(_, _, _, _, _, let allowClosed, _) = model.taskIDPrompt?.purpose {
            XCTAssertTrue(allowClosed)
        } else {
            XCTFail("expected wikilinkTask purpose")
        }
    }

    func testFilterClearingRevealsFullPoolLocally() {
        let model = installPicker()
        let fullCount = model.pickerPresentation?.orderedRowIDs.count ?? 0
        XCTAssertGreaterThan(fullCount, 0)
        // Narrowing then clearing the filter recomputes rows from Bob's
        // original candidate pool without another subprocess.
        model.updatePickerFilter("zzz-no-match")
        model.updatePickerFilter("")
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.pickerPresentation?.orderedRowIDs.count, fullCount)
    }

    func testMissingReplacementKeepsPickerOpen() {
        let model = CapturePanelModel()
        model.installWikilinkTaskPickerForPreviews(
            candidates: [identifiedCandidate(), missingReplacementCandidate()],
            draft: "Follow up ((",
            replacement: CaptureRange(start: 10, end: 12)
        )
        // A row with no insertable replacement and no Add block ID flow is
        // a no-op: the draft is unchanged and the picker stays open.
        model.acceptPickerRow(id: "mac_inbox.md|3:missing000", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "Follow up ((")
        XCTAssertTrue(model.pickerVisible)
    }

    func testEscapePromptRestoresFilter() {
        let model = CapturePanelModel()
        model.installWikilinkTaskPickerForPreviews(
            candidates: [identifiedCandidate(), idlessCandidate()],
            filter: "plain",
            draft: "Follow up ((",
            replacement: CaptureRange(start: 10, end: 12)
        )
        model.acceptPickerRow(id: "mac_inbox.md|2:c37a3d45", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.cancelTaskIDPrompt()
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsWikilinkTask)
        XCTAssertEqual(model.picker?.filterText, "plain")
    }

    func testSecondParenBurstAutoOpens() async throws {
        let model = try liveModel()
        model.plainDraft = "Follow up ("
        model.editorTextDidChange(cursorUTF8Offset: 11)
        await waitUntil { model.latestParse?.input == model.plainDraft }
        model.plainDraft = "Follow up (("
        model.editorTextDidChange(cursorUTF8Offset: 12)
        await waitUntil { model.pickerVisible }
        XCTAssertTrue(model.pickerSourceIsWikilinkTask)
        XCTAssertFalse(model.picker?.candidates.isEmpty ?? true)
    }

    func testTrailingTemplateCoexistsWithWikilinkTask() async throws {
        let model = try liveModel()
        model.plainDraft = "Follow up ((s @@@"
        model.editorTextDidChange(cursorUTF8Offset: 13)
        await waitUntil { model.latestParse?.input == model.plainDraft }
        // The trailing `@@@` template marker leaves the `((` parse spans
        // intact, so the picker still auto-opens on the query.
        XCTAssertEqual(
            model.latestParse?.spans.map(\.kind),
            ["wikilink_task_delimiter", "wikilink_task_query"]
        )
        await waitUntil { model.pickerVisible }
        XCTAssertTrue(model.pickerSourceIsWikilinkTask)
        XCTAssertFalse(model.picker?.candidates.isEmpty ?? true)
    }

    func testInvalidBlockIDKeepsPromptOpen() async throws {
        let model = try liveModel()
        model.plainDraft = "Follow up (("
        model.editorTextDidChange(cursorUTF8Offset: 12)
        await waitUntil { model.pickerVisible }
        let idlessID = try XCTUnwrap(
            model.pickerPresentation?.orderedRowIDs.first {
                model.pickerPresentation?.row(id: $0)?.pendingBlockID != nil
            }
        )
        model.acceptPickerRow(id: idlessID, submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.updateTaskIDPromptBlockID("not an id!!")
        model.submitTaskIDPrompt()
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertEqual(
            model.taskIDPrompt?.errorMessage, "Use only letters, numbers, and hyphens.")
    }

    func testAcceptDisabledKeepsPickerOpen() {
        let model = installPicker()
        model.acceptPickerRow(id: "twin.md|7:gggg7777", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "Follow up ((")
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.statusText, "duplicate block ID ^twin in twin.md")
    }

    func testAcceptIdlessOpensWikilinkPrompt() {
        let model = installPicker()
        model.acceptPickerRow(id: "mac_inbox.md|2:c37a3d45", submitAfterInsert: false)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsWikilinkTask)
        XCTAssertFalse(model.taskIDPromptIsTaskComplete)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "inbox-plain")
    }

    func testEscapePromptReturnsToWikilinkPicker() {
        let model = installPicker()
        model.acceptPickerRow(id: "mac_inbox.md|2:c37a3d45", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.cancelTaskIDPrompt()
        XCTAssertFalse(model.taskIDPromptVisible)
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsWikilinkTask)
    }

    func testBackspaceOnEmptyFilterLeavesOneParen() {
        let model = installPicker()
        XCTAssertEqual(model.plainDraft, "Follow up ((")
        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "Follow up (")
        XCTAssertFalse(model.pickerVisible)
    }

    func testEscapePickerSuppressesAutoOpen() {
        let model = installPicker()
        XCTAssertTrue(model.pickerVisible)
        model.escapePicker()
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(model.pickerChipVisible)
    }

    func testStaleDraftRefusesAccept() {
        let model = installPicker()
        model.plainDraft = "Follow up (( changed"
        model.acceptPickerRow(id: "sase_cleanup.md|1:fa53e656", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "Follow up (( changed")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Draft changed — reopen the task picker")
    }

    func testHistoryPromptCarriesAllowClosed() {
        let model = installPicker()
        model.acceptPickerRow(id: "home.md|9:history000", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsWikilinkTask)
        if case .wikilinkTask(_, _, _, _, _, let allowClosed, _) = model.taskIDPrompt?.purpose {
            XCTAssertTrue(allowClosed)
        } else {
            XCTFail("expected wikilinkTask purpose")
        }
    }

    func testFakeBobServesWikilinkPicker() throws {
        let fakeBob = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/fake-bob")
        let output = try runFakeBob(
            fakeBob.path,
            args: ["capture-complete", "-c", "12", "-f", "json", "--", "Follow up (("])
        let response = try JSONDecoder().decode(
            CaptureCompletionResponse.self, from: Data(output.utf8))
        XCTAssertEqual(response.context, "wikilink_task")
        XCTAssertEqual(response.picker?.kind, "wikilink_task")
        XCTAssertFalse(response.candidates.isEmpty)
        XCTAssertEqual(response.candidates.first?.linkTarget, "mac_inbox")
    }

    func testWikilinkAutoOpenFromFakeBob() async throws {
        let model = try liveModel()
        model.plainDraft = "Follow up (("
        model.editorTextDidChange(cursorUTF8Offset: 12)
        await waitUntil { model.latestParse?.input == model.plainDraft }
        XCTAssertEqual(
            model.latestParse?.spans.map(\.kind),
            ["wikilink_task_delimiter"]
        )
        await waitUntil { model.pickerVisible }
        XCTAssertTrue(model.pickerSourceIsWikilinkTask)
        XCTAssertFalse(model.picker?.candidates.isEmpty ?? true)
    }

    func testCaretMoveIntoWikilinkTaskShowsReopenChip() async throws {
        let model = try liveModel()
        model.plainDraft = "Follow up ((s"
        model.editorSelectionDidChange(cursorUTF8Offset: 13)
        await waitUntil { model.latestParse?.input == model.plainDraft }
        XCTAssertEqual(
            model.latestParse?.spans.map(\.kind),
            ["wikilink_task_delimiter", "wikilink_task_query"]
        )
        await waitUntil { model.pickerChipVisible }
        XCTAssertFalse(model.pickerVisible)
    }

    func testOlderBobWithoutTaskWikilinkParseSpansKeepsTokenPlain() async throws {
        let model = try liveModel(
            environment: ["FAKE_BOB_PARSE_FIXTURE": "capture-parse-wikilink-task-old-bob.json"]
        )
        model.plainDraft = "Follow up (("
        model.editorTextDidChange(cursorUTF8Offset: 12)
        await waitUntil { model.latestParse?.input == model.plainDraft }
        XCTAssertFalse(model.pickerVisible)
        XCTAssertFalse(model.pickerChipVisible)
    }

    func testIDPromptSplicesWikilinkReplacement() async throws {
        let model = try liveModel()
        model.plainDraft = "Follow up (("
        model.editorTextDidChange(cursorUTF8Offset: 12)
        await waitUntil { model.pickerVisible }
        let idlessID = try XCTUnwrap(
            model.pickerPresentation?.orderedRowIDs.first {
                model.pickerPresentation?.row(id: $0)?.pendingBlockID != nil
            }
        )
        let pending = try XCTUnwrap(model.pickerPresentation?.row(id: idlessID)?.pendingBlockID)
        let authored = try XCTUnwrap(pending.suggestions.first)
        model.acceptPickerRow(id: idlessID, submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsWikilinkTask)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, authored)
        model.submitTaskIDPrompt()
        await waitUntil { !model.taskIDPromptVisible }
        XCTAssertTrue(model.plainDraft.contains("[["))
        XCTAssertTrue(model.plainDraft.contains("#^\(authored)]]"))
    }

    func testOldBobKeepsPromptOpen() async throws {
        let model = try liveModel(environment: ["FAKE_BOB_WIKILINK_OLD": "1"])
        model.plainDraft = "Follow up (("
        model.editorTextDidChange(cursorUTF8Offset: 12)
        await waitUntil { model.pickerVisible }
        let idlessID = try XCTUnwrap(
            model.pickerPresentation?.orderedRowIDs.first {
                model.pickerPresentation?.row(id: $0)?.pendingBlockID != nil
            }
        )
        model.acceptPickerRow(id: idlessID, submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.submitTaskIDPrompt()
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPrompt?.errorMessage?.contains("too old") ?? false)
    }

    private func liveModel(environment: [String: String] = [:]) throws -> CapturePanelModel {
        var env = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        for (key, value) in environment {
            env[key] = value
        }
        return CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: env
            ),
            debounceNanoseconds: 5_000_000
        )
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

    private func runFakeBob(_ path: String, args: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }
}
