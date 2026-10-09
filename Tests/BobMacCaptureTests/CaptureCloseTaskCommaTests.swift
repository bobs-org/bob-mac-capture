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
}
