import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureCloseTaskCommaTests: XCTestCase {
    private func closeSnapshot(
        draft: String = "=x1"
    ) -> CaptureParseSnapshot {
        CaptureParseSnapshot(
            draft: draft,
            spans: [
                CaptureSpan(start: 0, end: 2, kind: "pomodoro_close"),
                CaptureSpan(
                    start: 2,
                    end: 3,
                    kind: "pomodoro_close_in_progress"
                ),
            ]
        )
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

    // MARK: - Router

    func testRouterMapsDigitToInsertCloseTaskNumberWhenArmed() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(closeTaskCommaArmed: true)
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 19, characters: "2"),
                context: context
            ),
            .insertCloseTaskNumber("2")
        )
    }

    func testRouterDeclinesDigitWhenDisarmed() {
        let router = CaptureKeyCommandRouter()
        XCTAssertNil(
            router.command(
                for: keyEvent(keyCode: 19, characters: "2"),
                context: CaptureKeyRoutingContext(
                    closeTaskCommaArmed: false
                )
            )
        )
    }

    func testRouterDeclinesDigitWithCommandControlOrOption() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(closeTaskCommaArmed: true)
        XCTAssertNil(
            router.command(
                for: keyEvent(
                    keyCode: 19,
                    modifiers: .command,
                    characters: "2"
                ),
                context: context
            )
        )
        XCTAssertNil(
            router.command(
                for: keyEvent(
                    keyCode: 19,
                    modifiers: .control,
                    characters: "2"
                ),
                context: context
            )
        )
        XCTAssertNil(
            router.command(
                for: keyEvent(
                    keyCode: 19,
                    modifiers: .option,
                    characters: "2"
                ),
                context: context
            )
        )
    }

    func testRouterDeclinesZero() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(closeTaskCommaArmed: true)
        XCTAssertNil(
            router.command(
                for: keyEvent(keyCode: 29, characters: "0"),
                context: context
            )
        )
    }

    func testRouterLeavesPickerStashAndPromptDigitsAlone() {
        let router = CaptureKeyCommandRouter()
        let digit = keyEvent(keyCode: 19, characters: "2")
        assertNotCloseTaskNumber(
            router.command(
                for: digit,
                context: CaptureKeyRoutingContext(
                    pickerVisible: true,
                    closeTaskCommaArmed: true
                )
            )
        )
        assertNotCloseTaskNumber(
            router.command(
                for: digit,
                context: CaptureKeyRoutingContext(
                    stashPickerVisible: true,
                    stashEntryCount: 3,
                    closeTaskCommaArmed: true
                )
            )
        )
        assertNotCloseTaskNumber(
            router.command(
                for: digit,
                context: CaptureKeyRoutingContext(
                    taskIDPromptVisible: true,
                    closeTaskCommaArmed: true
                )
            )
        )
    }

    private func assertNotCloseTaskNumber(
        _ command: CaptureKeyCommand?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .insertCloseTaskNumber = command {
            XCTFail(
                "stash/picker/prompt must own digits, not the close assist",
                file: file,
                line: line
            )
        }
    }

    // MARK: - Controller helper

    func testInsertCloseTaskNumberInsertsComma() {
        let model = CapturePanelModel()
        model.setCurrentPomodoroTaskLinkCountForTests(3)
        model.setCloseListParseSnapshotForTests(closeSnapshot())

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "=x1"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertTrue(
            CapturePanelController.insertCloseTaskNumberInEditableTextView(
                "2",
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "=x1,2")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 5, length: 0))
    }

    func testInsertCloseTaskNumberDeclinesWithoutChangingText() {
        let model = CapturePanelModel()
        model.setCurrentPomodoroTaskLinkCountForTests(nil)
        model.setCloseListParseSnapshotForTests(closeSnapshot())

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "=x1"
        textView.setSelectedRange(NSRange(location: 3, length: 0))

        XCTAssertFalse(
            CapturePanelController.insertCloseTaskNumberInEditableTextView(
                "2",
                firstResponder: textView,
                model: model
            )
        )
        XCTAssertEqual(textView.string, "=x1")
    }

    func testInsertCloseTaskNumberDeclinesWhileComposing() {
        let model = CapturePanelModel()
        model.setCurrentPomodoroTaskLinkCountForTests(3)
        model.setCloseListParseSnapshotForTests(closeSnapshot())

        let textView = NSTextView()
        textView.isEditable = true
        textView.string = "=x1"
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.setMarkedText(
            "2",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 3, length: 0)
        )

        XCTAssertFalse(
            CapturePanelController.insertCloseTaskNumberInEditableTextView(
                "2",
                firstResponder: textView,
                model: model
            )
        )
        textView.unmarkText()
    }

    // MARK: - Model

    func testStaleSnapshotNeverArmsEdit() {
        let model = CapturePanelModel()
        model.setCurrentPomodoroTaskLinkCountForTests(3)
        model.setCloseListParseSnapshotForTests(closeSnapshot(draft: "=x"))

        XCTAssertNil(
            model.closeTaskCommaEdit(
                typed: "2",
                text: "=x1",
                selectedRange: NSRange(location: 3, length: 0)
            )
        )
    }

    func testLegacyResponseLeavesAssistDisarmed() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(
                "Fixtures/pomodoros-legacy-no-count.json"
            )
        // Fixture lives in CaptureCoreTests; BobMacCaptureTests has no
        // copy, so a missing file still proves the safe default: without
        // a count the assist stays off.
        if let data = try? Data(contentsOf: url) {
            let response = try JSONDecoder().decode(
                CapturePomodorosResponse.self,
                from: data
            )
            modelSeedAndAssertDisarmed(count: response.currentTaskLinkCount)
        } else {
            modelSeedAndAssertDisarmed(count: nil)
        }
    }

    private func modelSeedAndAssertDisarmed(count: Int?) {
        let model = CapturePanelModel()
        model.setCurrentPomodoroTaskLinkCountForTests(count)
        XCTAssertFalse(model.closeTaskCommaArmed)
    }

    // MARK: - Count refresh (fake-bob)

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
                XCTFail(
                    "Condition not met before timeout",
                    file: file,
                    line: line
                )
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    // The count now flows through the agenda store: the helper wires a
    // store with a pinned today (the agenda fixtures are dated
    // 2026-08-28) and refreshes it, exactly as the panel show path does.
    private func refreshModel(
        agendaFixture: String? = nil,
        agendaFails: Bool = false,
        unsupported: Bool = false,
        pomodorosFixture: String? = nil
    ) throws -> CapturePanelModel {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
        ]
        if let agendaFixture {
            environment["FAKE_BOB_AGENDA_FIXTURE"] = agendaFixture
        }
        if agendaFails {
            environment["FAKE_BOB_AGENDA_FAIL"] = "1"
        }
        if unsupported {
            environment["FAKE_BOB_AGENDA_UNSUPPORTED"] = "1"
        }
        if let pomodorosFixture {
            environment["FAKE_BOB_POMODOROS_FIXTURE"] = pomodorosFixture
        }
        let store = CaptureAgendaStore(
            processClient: BobProcessClient(
                executablePath: try fakeBobPath(),
                environment: environment
            ),
            vaultRootPath: "/tmp",
            today: { "2026-08-28" }
        )
        let model = CapturePanelModel()
        model.agendaStore = store
        store.refresh(reason: .show)
        return model
    }

    func testRefreshArmsAssistWithDefaultFixture() async throws {
        let model = try refreshModel()
        await waitUntil { model.closeTaskCommaArmed }
        XCTAssertEqual(model.currentPomodoroTaskLinkCount, 3)
        XCTAssertTrue(model.closeTaskCommaArmed)
    }

    func testRefreshLeavesAssistDisarmedForLargeCount() async throws {
        let model = try refreshModel(
            agendaFixture: "agenda-current-12.json"
        )
        await waitUntil { model.currentPomodoroTaskLinkCount == 12 }
        XCTAssertEqual(model.currentPomodoroTaskLinkCount, 12)
        XCTAssertFalse(model.closeTaskCommaArmed)
    }

    func testRefreshLeavesAssistDisarmedForLegacyResponse() async throws {
        // An old bob without `--tasks` falls back to the plain lane, so
        // the legacy plain fixture still drives the count through it.
        let model = try refreshModel(
            unsupported: true,
            pomodorosFixture: "pomodoros-legacy-no-count.json"
        )
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(model.currentPomodoroTaskLinkCount)
        XCTAssertFalse(model.closeTaskCommaArmed)
    }

    func testRefreshLeavesAssistDisarmedWhenNoneRunning() async throws {
        let model = try refreshModel(
            agendaFixture: "agenda-nothing-running.json"
        )
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(model.currentPomodoroTaskLinkCount)
        XCTAssertFalse(model.closeTaskCommaArmed)
    }

    func testRefreshFailureLeavesAssistDisarmed() async throws {
        let model = try refreshModel(agendaFails: true)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(model.currentPomodoroTaskLinkCount)
        XCTAssertFalse(model.closeTaskCommaArmed)
    }

    func testFailingRefreshAfterSuccessClearsCount() async throws {
        let model = try refreshModel()
        await waitUntil { model.closeTaskCommaArmed }
        model.agendaStore?.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_AGENDA_FAIL": "1",
            ]
        )
        model.agendaStore?.refresh(reason: .show)
        await waitUntil { !model.closeTaskCommaArmed }
        XCTAssertNil(model.currentPomodoroTaskLinkCount)
        XCTAssertFalse(model.closeTaskCommaArmed)
    }

    // MARK: - Key-driven assist parse

    private func keyDrivenModel() throws -> CapturePanelModel {
        // A very long debounce keeps the debounced analysis parse from
        // running, so only the immediate assist parse can feed the edit.
        let model = CapturePanelModel(debounceNanoseconds: 9_000_000_000)
        model.processClient = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        return model
    }

    func testKeyDrivenAssistParseServesCommaEdit() async throws {
        let model = try keyDrivenModel()
        model.setCurrentPomodoroTaskLinkCountForTests(3)
        // The digit lands through the editor binding, which never clears
        // the pending request; the plainDraft setter does, so request after
        // assigning the draft to reach editorTextDidChange with it pending.
        model.plainDraft = "=x1"
        model.requestCloseListAssistParse()
        model.editorTextDidChange(cursorUTF8Offset: "=x1".utf8.count)
        await waitUntil {
            model.closeTaskCommaEdit(
                typed: "2",
                text: "=x1",
                selectedRange: NSRange(location: 3, length: 0)
            ) != nil
        }
        let edit = model.closeTaskCommaEdit(
            typed: "2",
            text: "=x1",
            selectedRange: NSRange(location: 3, length: 0)
        )
        XCTAssertEqual(edit?.replacementText, ",2")
    }

    func testAssistParseDoesNotRunWithoutKeyRequest() async throws {
        let model = try keyDrivenModel()
        model.setCurrentPomodoroTaskLinkCountForTests(3)
        model.plainDraft = "=x1"
        model.editorTextDidChange(cursorUTF8Offset: "=x1".utf8.count)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(
            model.closeTaskCommaEdit(
                typed: "2",
                text: "=x1",
                selectedRange: NSRange(location: 3, length: 0)
            )
        )
    }

    func testAssistParseDoesNotRunWhileDisarmed() async throws {
        let model = try keyDrivenModel()
        // Same binding-order note as above: request after the draft so the
        // pending flag survives to editorTextDidChange, where disarm blocks.
        model.plainDraft = "=x1"
        model.requestCloseListAssistParse()
        model.editorTextDidChange(cursorUTF8Offset: "=x1".utf8.count)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertNil(
            model.closeTaskCommaEdit(
                typed: "2",
                text: "=x1",
                selectedRange: NSRange(location: 3, length: 0)
            )
        )
    }

    func testInsertCloseTaskNumberRequestsAssistParseOnBothPaths() {
        let armed = CapturePanelModel()
        armed.setCurrentPomodoroTaskLinkCountForTests(3)
        armed.setCloseListParseSnapshotForTests(closeSnapshot())
        let acceptView = NSTextView()
        acceptView.isEditable = true
        acceptView.string = "=x1"
        acceptView.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertTrue(
            CapturePanelController.insertCloseTaskNumberInEditableTextView(
                "2",
                firstResponder: acceptView,
                model: armed
            )
        )
        XCTAssertTrue(armed.closeListAssistParsePendingForTests)

        let declined = CapturePanelModel()
        declined.setCurrentPomodoroTaskLinkCountForTests(nil)
        declined.setCloseListParseSnapshotForTests(closeSnapshot())
        let declineView = NSTextView()
        declineView.isEditable = true
        declineView.string = "=x1"
        declineView.setSelectedRange(NSRange(location: 3, length: 0))
        XCTAssertFalse(
            CapturePanelController.insertCloseTaskNumberInEditableTextView(
                "2",
                firstResponder: declineView,
                model: declined
            )
        )
        XCTAssertTrue(declined.closeListAssistParsePendingForTests)
    }

    // MARK: - Provenance-aware Backspace

    private func assistedView(
        model: CapturePanelModel,
        text: String,
        caret: Int,
        snapshot: CaptureParseSnapshot,
        count: Int? = 3
    ) -> NSTextView {
        model.setCurrentPomodoroTaskLinkCountForTests(count)
        model.setCloseListParseSnapshotForTests(snapshot)
        let view = NSTextView()
        view.isEditable = true
        view.string = text
        view.setSelectedRange(NSRange(location: caret, length: 0))
        return view
    }

    private func insert(
        _ digit: String,
        view: NSTextView,
        model: CapturePanelModel
    ) -> Bool {
        CapturePanelController.insertCloseTaskNumberInEditableTextView(
            digit,
            firstResponder: view,
            model: model
        )
    }

    private func backspace(view: NSTextView, model: CapturePanelModel) -> Bool {
        CapturePanelController.deleteCloseTaskCommaInEditableTextView(
            firstResponder: view,
            model: model
        )
    }

    func testBackspaceRemovesAssistedPair() {
        let model = CapturePanelModel()
        let view = assistedView(model: model, text: "=x1", caret: 3, snapshot: closeSnapshot())
        XCTAssertTrue(insert("2", view: view, model: model))
        XCTAssertEqual(view.string, "=x1,2")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertTrue(backspace(view: view, model: model))
        XCTAssertEqual(view.string, "=x1")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 0))
        XCTAssertTrue(model.closeCommaProvenanceForTests().entries.isEmpty)
    }

    func testBackspaceRepeatedPairsDeleteInnermostFirst() {
        let model = CapturePanelModel()
        let first = assistedView(model: model, text: "=x1", caret: 3, snapshot: closeSnapshot())
        XCTAssertTrue(insert("2", view: first, model: model))
        XCTAssertEqual(first.string, "=x1,2")
        // Fresh spans authorize the next digit at the new end.
        model.setCloseListParseSnapshotForTests(
            CaptureParseSnapshot(
                draft: "=x1,2",
                spans: [
                    CaptureSpan(start: 0, end: 2, kind: "pomodoro_close"),
                    CaptureSpan(start: 2, end: 5, kind: "pomodoro_close_in_progress"),
                ]
            )
        )
        first.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertTrue(insert("3", view: first, model: model))
        XCTAssertEqual(first.string, "=x1,2,3")
        XCTAssertEqual(first.selectedRange(), NSRange(location: 7, length: 0))
        XCTAssertTrue(backspace(view: first, model: model))
        XCTAssertEqual(first.string, "=x1,2")
        XCTAssertEqual(first.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertTrue(backspace(view: first, model: model))
        XCTAssertEqual(first.string, "=x1")
        XCTAssertEqual(first.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testBackspaceMiddlePairBeforeBang() {
        let model = CapturePanelModel()
        let snapshot = CaptureParseSnapshot(
            draft: "=x1!3",
            spans: [
                CaptureSpan(start: 0, end: 2, kind: "pomodoro_close"),
                CaptureSpan(start: 2, end: 3, kind: "pomodoro_close_in_progress"),
                CaptureSpan(start: 3, end: 5, kind: "pomodoro_close_complete"),
            ]
        )
        let view = assistedView(model: model, text: "=x1!3", caret: 3, snapshot: snapshot)
        XCTAssertTrue(insert("2", view: view, model: model))
        XCTAssertEqual(view.string, "=x1,2!3")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 5, length: 0))
        XCTAssertTrue(backspace(view: view, model: model))
        XCTAssertEqual(view.string, "=x1!3")
        XCTAssertEqual(view.selectedRange(), NSRange(location: 3, length: 0))
    }

    func testBackspaceUnicodePrefix() {
        let model = CapturePanelModel()
        let draft = "🎉=x1"
        let nsLength = (draft as NSString).length
        let snapshot = CaptureParseSnapshot(
            draft: draft,
            spans: [
                CaptureSpan(start: 0, end: 6, kind: "pomodoro_close"),
                CaptureSpan(start: 6, end: 7, kind: "pomodoro_close_in_progress"),
            ]
        )
        let view = assistedView(model: model, text: draft, caret: nsLength, snapshot: snapshot)
        XCTAssertTrue(insert("2", view: view, model: model))
        XCTAssertEqual(view.string, "🎉=x1,2")
        XCTAssertTrue(backspace(view: view, model: model))
        XCTAssertEqual(view.string, draft)
    }

    func testBackspaceDeclinesForManualComma() {
        let model = CapturePanelModel()
        model.setCurrentPomodoroTaskLinkCountForTests(3)
        let view = NSTextView()
        view.isEditable = true
        view.string = "=x1,2"
        view.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertFalse(backspace(view: view, model: model))
        XCTAssertEqual(view.string, "=x1,2")
    }

    func testBackspaceDeclinesForNoncollapsedSelection() {
        let model = CapturePanelModel()
        let view = assistedView(model: model, text: "=x1", caret: 3, snapshot: closeSnapshot())
        XCTAssertTrue(insert("2", view: view, model: model))
        view.setSelectedRange(NSRange(location: 4, length: 1))
        XCTAssertFalse(backspace(view: view, model: model))
        XCTAssertEqual(view.string, "=x1,2")
    }

    func testBackspaceDeclinesWhileComposing() {
        let model = CapturePanelModel()
        let view = assistedView(model: model, text: "=x1", caret: 3, snapshot: closeSnapshot())
        XCTAssertTrue(insert("2", view: view, model: model))
        view.setSelectedRange(NSRange(location: 5, length: 0))
        view.setMarkedText(
            "x",
            selectedRange: NSRange(location: 0, length: 1),
            replacementRange: NSRange(location: 5, length: 0)
        )
        XCTAssertFalse(backspace(view: view, model: model))
        view.unmarkText()
    }

    func testBackspaceLeavesEmptyBulletDeletionIntact() {
        let model = CapturePanelModel()
        let view = NSTextView()
        view.isEditable = true
        view.string = "Parent\n- \nChild"
        view.setSelectedRange(NSRange(location: 9, length: 0))
        // No provenance, so the comma helper declines and the bullet helper owns it.
        XCTAssertFalse(backspace(view: view, model: model))
        XCTAssertTrue(
            CapturePanelController.deleteEmptyBulletRowInEditableTextView(
                firstResponder: view,
                model: model
            )
        )
    }

    func testProvenanceSurvivesEditBeforePair() {
        let model = CapturePanelModel()
        let view = assistedView(model: model, text: "=x1", caret: 3, snapshot: closeSnapshot())
        XCTAssertTrue(insert("2", view: view, model: model))
        // Ordinary typing before the pair shifts it; Backspace still finds it.
        model.attributedDraft = AttributedString("A=x1,2")
        model.editorTextDidChange(cursorUTF8Offset: "A=x1,2".utf8.count)
        let shifted = NSTextView()
        shifted.isEditable = true
        shifted.string = "A=x1,2"
        shifted.setSelectedRange(NSRange(location: 6, length: 0))
        XCTAssertTrue(backspace(view: shifted, model: model))
        XCTAssertEqual(shifted.string, "A=x1")
    }

    func testProvenanceInvalidatedWhenPairReplaced() {
        let model = CapturePanelModel()
        let view = assistedView(model: model, text: "=x1", caret: 3, snapshot: closeSnapshot())
        XCTAssertTrue(insert("2", view: view, model: model))
        model.attributedDraft = AttributedString("=x1;2")
        model.editorTextDidChange(cursorUTF8Offset: "=x1;2".utf8.count)
        let edited = NSTextView()
        edited.isEditable = true
        edited.string = "=x1;2"
        edited.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertFalse(backspace(view: edited, model: model))
    }

    func testProvenanceClearedOnProgrammaticReset() {
        let model = CapturePanelModel()
        let view = assistedView(model: model, text: "=x1", caret: 3, snapshot: closeSnapshot())
        XCTAssertTrue(insert("2", view: view, model: model))
        model.plainDraft = "=x1,2"
        let reset = NSTextView()
        reset.isEditable = true
        reset.string = "=x1,2"
        reset.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertFalse(backspace(view: reset, model: model))
    }

    func testUndoDoesNotResurrectStaleProvenance() {
        let model = CapturePanelModel()
        let view = assistedView(model: model, text: "=x1", caret: 3, snapshot: closeSnapshot())
        XCTAssertTrue(insert("2", view: view, model: model))
        XCTAssertTrue(backspace(view: view, model: model))
        XCTAssertEqual(view.string, "=x1")
        // Native undo restores the text without provenance; a second
        // Backspace must stay native instead of deleting a stale pair.
        model.attributedDraft = AttributedString("=x1,2")
        model.editorTextDidChange(cursorUTF8Offset: "=x1,2".utf8.count)
        let undone = NSTextView()
        undone.isEditable = true
        undone.string = "=x1,2"
        undone.setSelectedRange(NSRange(location: 5, length: 0))
        XCTAssertFalse(backspace(view: undone, model: model))
        XCTAssertEqual(undone.string, "=x1,2")
    }

    func testRouterKeepsModalBackspaceRouting() {
        let router = CaptureKeyCommandRouter()
        let delete = keyEvent(keyCode: 51)
        XCTAssertEqual(
            router.command(for: delete, context: CaptureKeyRoutingContext()),
            .deleteBackward
        )
        XCTAssertNil(
            router.command(
                for: keyEvent(keyCode: 51, modifiers: .shift),
                context: CaptureKeyRoutingContext()
            )
        )
        // Picker, stash, and prompt digits never reach the editor helper.
        let pickerDelete = router.command(
            for: delete,
            context: CaptureKeyRoutingContext(pickerVisible: true, pickerFilterIsEmpty: true)
        )
        XCTAssertNotEqual(pickerDelete, .deleteBackward)
    }

    // MARK: - Count and assist-parse lifecycle

    private func delayedClient(
        agendaFixture: String? = nil,
        delaySeconds: String
    ) throws -> BobProcessClient {
        var environment = ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        environment["FAKE_BOB_DELAY_SECONDS"] = delaySeconds
        if let agendaFixture {
            environment["FAKE_BOB_AGENDA_FIXTURE"] = agendaFixture
        }
        return BobProcessClient(executablePath: try fakeBobPath(), environment: environment)
    }

    private func storeWithModel(
        processClient: BobProcessClient?
    ) -> (CapturePanelModel, CaptureAgendaStore) {
        let store = CaptureAgendaStore(
            processClient: processClient,
            vaultRootPath: "/tmp",
            today: { "2026-08-28" }
        )
        let model = CapturePanelModel()
        model.agendaStore = store
        return (model, store)
    }

    func testOldCountNeverPublishesAfterNilClient() async throws {
        let (model, store) = storeWithModel(
            processClient: try delayedClient(delaySeconds: "1")
        )
        // Clearing the client must invalidate the delayed refresh so the
        // late success cannot re-arm the assist.
        store.refresh(reason: .show)
        store.processClient = nil
        XCTAssertNil(model.currentPomodoroTaskLinkCount)
        // The delayed old request finishes here; it must not re-arm.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertNil(model.currentPomodoroTaskLinkCount)
        XCTAssertFalse(model.closeTaskCommaArmed)
    }

    func testOldCountNeverPublishesAfterReplacement() async throws {
        let (model, store) = storeWithModel(
            processClient: try delayedClient(delaySeconds: "2")
        )
        store.refresh(reason: .show)
        let replacement = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: [
                "HOME": "/tmp",
                "PATH": "/usr/bin:/bin",
                "FAKE_BOB_AGENDA_FIXTURE": "agenda-current-12.json",
            ]
        )
        store.processClient = replacement
        // The replacement fetch keeps a visible panel fresh.
        store.refresh(reason: .show)
        await waitUntil { model.currentPomodoroTaskLinkCount == 12 }
        XCTAssertEqual(model.currentPomodoroTaskLinkCount, 12)
        // The delayed old count (3) finishes here and must not overwrite 12.
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        XCTAssertEqual(model.currentPomodoroTaskLinkCount, 12)
    }

    func testOldAssistParseNeverPublishesAfterReplacement() async throws {
        // Long debounce isolates the immediate assist parse, like keyDrivenModel.
        let model = CapturePanelModel(debounceNanoseconds: 9_000_000_000)
        model.setProcessClient(try delayedClient(delaySeconds: "1"))
        model.setCurrentPomodoroTaskLinkCountForTests(3)
        // Same binding order as testKeyDrivenAssistParseServesCommaEdit:
        // assign the draft before requesting so the pending flag survives.
        model.plainDraft = "=x1"
        model.requestCloseListAssistParse()
        model.editorTextDidChange(cursorUTF8Offset: "=x1".utf8.count)
        let replacement = BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: ["HOME": "/tmp", "PATH": "/usr/bin:/bin"]
        )
        model.setProcessClient(replacement)
        // The count now flows through the store: attach it and refresh
        // with the replacement client (default 3-link agenda fixture), so
        // the assist re-arms while the old parse is still in flight.
        let store = CaptureAgendaStore(
            processClient: replacement,
            vaultRootPath: "/tmp",
            today: { "2026-08-28" }
        )
        model.agendaStore = store
        store.refresh(reason: .show)
        // The delayed old parse finishes here; it must not publish a
        // snapshot. A nil edit while armed proves the snapshot stayed nil
        // rather than disarm.
        await waitUntil { model.closeTaskCommaArmed }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertNil(
            model.closeTaskCommaEdit(
                typed: "2",
                text: "=x1",
                selectedRange: NSRange(location: 3, length: 0)
            )
        )
    }
}
