import AppKit
import CaptureCore
import Foundation
import XCTest

@testable import BobMacCapture

/// Complete picker panel wiring: accept, Shift-Return chaining,
/// continuation keys, ID prompt, marker highlight, and key routing.
@MainActor
final class CaptureTaskCompletePanelTests: XCTestCase {
    private func identifiedCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "!sase:deep-fix",
            taskRef: "1:41d049f2",
            blockID: "deep-fix",
            requiresBlockID: false,
            statusSymbol: "*",
            statusName: "Next",
            statusType: "ON_HOLD",
            text: "Fix deep bug",
            group: "today",
            notePath: "sase.md",
            locator: "sase",
            today: TaskCompleteToday(
                role: "running",
                pomodoro: TaskCompleteTodayPomodoro(line: 2, name: "CAPTURE", timeRange: "0920-0950", status: "running"),
                sessions: 1
            )
        )
    }

    private func idlessCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "3:f5826a74",
            requiresBlockID: true,
            statusSymbol: " ",
            statusName: "Ready",
            statusType: "TODO",
            text: "No id yet",
            blockIDSuggestions: ["no-id-yet"],
            group: "open",
            notePath: "sase.md",
            locator: "sase"
        )
    }

    private func disabledCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "",
            taskRef: "4:39f413d7",
            blockID: "water",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Ready",
            statusType: "TODO",
            text: "Water plants",
            group: "open",
            notePath: "sase.md",
            locator: "sase",
            disabledReason: "Recurring — complete it in Obsidian so Tasks writes the next occurrence",
            hidden: false,
            recurring: true
        )
    }

    private func installPicker() -> CapturePanelModel {
        let model = CapturePanelModel()
        model.installTaskCompletePickerForPreviews(
            candidates: [identifiedCandidate(), idlessCandidate(), disabledCandidate()],
            draft: "!",
            replacement: CaptureRange(start: 0, end: 1)
        )
        return model
    }

    func testAcceptInsertsBobReplacement() {
        let model = installPicker()
        XCTAssertTrue(model.pickerVisible)
        model.acceptPickerRow(id: "sase.md|1:41d049f2", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "!sase:deep-fix")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Inserted !sase:deep-fix")
    }

    func testShiftReturnChainsNextItem() {
        let model = installPicker()
        model.acceptPickerRowAndContinue(id: "sase.md|1:41d049f2")
        XCTAssertEqual(model.plainDraft, "!sase:deep-fix\n\n!")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(model.statusText.contains("pick the next task"))
    }

    func testAcceptDisabledKeepsPickerOpen() {
        let model = installPicker()
        model.acceptPickerRow(id: "sase.md|4:39f413d7", submitAfterInsert: false)
        XCTAssertEqual(model.plainDraft, "!")
        XCTAssertTrue(model.pickerVisible)
        XCTAssertEqual(model.statusText, "Recurring — complete it in Obsidian so Tasks writes the next occurrence")
    }

    func testAcceptIdlessOpensCompletePrompt() {
        let model = installPicker()
        model.acceptPickerRow(id: "sase.md|3:f5826a74", submitAfterInsert: false)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(model.taskIDPromptVisible)
        XCTAssertTrue(model.taskIDPromptIsTaskComplete)
        XCTAssertFalse(model.taskIDPromptIsTaskLink)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, "no-id-yet")
    }

    func testEscapePromptReturnsToCompletePicker() {
        let model = installPicker()
        model.acceptPickerRow(id: "sase.md|3:f5826a74", submitAfterInsert: false)
        XCTAssertTrue(model.taskIDPromptVisible)
        model.cancelTaskIDPrompt()
        XCTAssertFalse(model.taskIDPromptVisible)
        XCTAssertTrue(model.pickerVisible)
        XCTAssertTrue(model.pickerSourceIsTaskComplete)
    }

    func testContinuationKeysClosePickerAndTypeKey() {
        let model = installPicker()
        XCTAssertEqual(model.pickerOperatorContinuationKeys, ["!", "["])
        model.continuePickerOperator("[")
        XCTAssertEqual(model.plainDraft, "![")
        XCTAssertFalse(model.pickerVisible)
    }

    func testContinuationKeysRequireEmptyFilter() {
        let model = CapturePanelModel()
        model.installTaskCompletePickerForPreviews(
            candidates: [identifiedCandidate()],
            filter: "fix",
            draft: "!fix",
            replacement: CaptureRange(start: 0, end: 4)
        )
        XCTAssertTrue(model.pickerOperatorContinuationKeys.isEmpty)
        model.continuePickerOperator("[")
        XCTAssertEqual(model.plainDraft, "!fix")
    }

    func testBangBangHandsOffToProse() {
        let model = installPicker()
        model.continuePickerOperator("!")
        XCTAssertEqual(model.plainDraft, "!!")
        XCTAssertFalse(model.pickerVisible)
    }

    func testMarkerHighlightCoversToken() {
        let range = CapturePanelModel.pickerMarkerHighlightRange(
            source: .taskComplete,
            replacementRange: CaptureRange(start: 0, end: 1),
            markerRange: nil
        )
        XCTAssertEqual(range, CaptureRange(start: 0, end: 1))
    }

    func testRemovePickerTriggerDeletesBangToken() {
        let model = installPicker()
        XCTAssertTrue(model.pickerVisible)
        model.removePickerTrigger()
        XCTAssertEqual(model.plainDraft, "")
        XCTAssertFalse(model.pickerVisible)
    }

    func testRouterShiftReturnContinuesForComplete() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerSourceIsTaskLink: false,
            pickerSourceIsTaskComplete: true
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .shift), context: context),
            .acceptPickerRowAndContinue
        )
    }

    func testRouterShiftReturnStartsForTaskLink() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerSourceIsTaskLink: true,
            pickerSourceIsTaskComplete: false
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 36, modifiers: .shift), context: context),
            .acceptPickerRowAndStart
        )
    }

    func testRouterContinuationKeys() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            pickerVisible: true,
            pickerFilterIsEmpty: true,
            pickerOperatorContinuationKeys: ["!", "["]
        )
        // Printable continuation is handled via characters: "[" continues.
        let bracket = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "[",
            charactersIgnoringModifiers: "[",
            isARepeat: false,
            keyCode: 33
        )!
        XCTAssertEqual(
            router.command(for: bracket, context: context),
            .continuePickerOperator("[")
        )
        let bang = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "!",
            charactersIgnoringModifiers: "!",
            isARepeat: false,
            keyCode: 18
        )!
        XCTAssertEqual(
            router.command(for: bang, context: context),
            .continuePickerOperator("!")
        )
        // Ctrl-[ keeps its escape binding even when "[" is a continuation key.
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 33, modifiers: .control, characters: "["),
                context: context
            ),
            .escapePicker
        )
    }

    func testRouterTabCyclesInCompletePrompt() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(
            taskIDPromptVisible: true,
            taskIDPromptIsTaskComplete: true
        )
        XCTAssertEqual(
            router.command(for: keyEvent(keyCode: 48, modifiers: []), context: context),
            .cycleTaskLinkSuggestionForward
        )
    }

    func testFakeBobServesCompletePicker() throws {
        let fakeBob = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/fake-bob")
        let output = try runFakeBob(fakeBob.path, args: ["capture-complete", "-c", "1", "-f", "json", "--", "!"])
        let response = try JSONDecoder().decode(CaptureCompletionResponse.self, from: Data(output.utf8))
        XCTAssertEqual(response.context, "task_complete")
        XCTAssertEqual(response.picker?.kind, "task_complete")
        XCTAssertFalse(response.candidates.isEmpty)
    }

    func testBangAutoOpensCompletePickerFromFakeBob() async throws {
        let model = try liveModel()
        model.plainDraft = "!"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }
        XCTAssertTrue(model.pickerSourceIsTaskComplete)
        XCTAssertFalse(model.picker?.candidates.isEmpty ?? true)
        XCTAssertEqual(model.picker?.filterText, "")
    }

    func testShiftReturnReopensPickerAfterChaining() async throws {
        let model = try liveModel()
        model.plainDraft = "!"
        model.editorTextDidChange(cursorUTF8Offset: 1)
        await waitUntil { model.pickerVisible }
        let firstID = try XCTUnwrap(model.pickerPresentation?.orderedRowIDs.first)
        let first = try XCTUnwrap(model.pickerPresentation?.row(id: firstID))
        let insertion = try XCTUnwrap(first.insertion)
        model.acceptPickerRowAndContinue(id: firstID)
        XCTAssertEqual(model.plainDraft, "\(insertion)\n\n!")
        XCTAssertTrue(model.statusText.contains("pick the next task"))
        await waitUntil { model.pickerVisible }
        XCTAssertTrue(model.pickerSourceIsTaskComplete)
    }

    func testIDPromptSplicesBobCompleteReplacement() async throws {
        let model = try liveModel()
        model.plainDraft = "!"
        model.editorTextDidChange(cursorUTF8Offset: 1)
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
        XCTAssertTrue(model.taskIDPromptIsTaskComplete)
        XCTAssertEqual(model.taskIDPrompt?.authoredID, authored)
        model.submitTaskIDPrompt()
        await waitUntil { !model.taskIDPromptVisible }
        // Bob's `complete_replacement` verbatim: the locator, never the file name.
        XCTAssertEqual(model.plainDraft, "!sase:\(authored)")
    }

    func testRefusalFixtureSurfacesBobError() async throws {
        let model = try liveModel()
        model.plainDraft = "!sase:cx"
        model.submit(openAfterCapture: false)
        await waitUntil { model.errorMessage != nil || model.statusText == "Capture failed" }
        let message = model.errorMessage ?? model.statusText
        XCTAssertTrue(
            message.contains("Canceled"),
            "refusal surfaces Bob's error, got: \(message)"
        )
        XCTAssertEqual(model.plainDraft, "!sase:cx")
    }

    private func liveModel() throws -> CapturePanelModel {
        CapturePanelModel(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
            ),
            debounceNanoseconds: 5_000_000
        )
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
