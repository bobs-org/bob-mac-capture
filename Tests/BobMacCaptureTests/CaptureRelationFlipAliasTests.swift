import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureRelationFlipAliasTests: XCTestCase {
    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = [],
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

    private func equalsEvent(
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(keyCode: 24, characters: "=", modifiers: modifiers, isRepeat: isRepeat)
    }

    private func dashEvent() -> NSEvent {
        keyEvent(keyCode: 27, characters: "-")
    }

    private func backspaceEvent() -> NSEvent {
        keyEvent(keyCode: 51, characters: "")
    }

    private func makeHostedEditor(
        text: String
    ) -> (CapturePanelModel, CapturePanelController, NSTextView, NSPanel) {
        let model = CapturePanelModel(debounceNanoseconds: 0)
        let controller = CapturePanelController(model: model)
        let panel = controller.makePanelIfNeeded()
        let textView = NSTextView()
        textView.isEditable = true
        textView.allowsUndo = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        model.plainDraft = text
        panel.contentView = textView
        XCTAssertTrue(panel.makeFirstResponder(textView))
        return (model, controller, textView, panel)
    }

    @discardableResult
    private func typeKey(
        _ event: NSEvent,
        into textView: NSTextView,
        model: CapturePanelModel,
        controller: CapturePanelController
    ) -> NSEvent? {
        let result = controller.routeKeyDown(event)
        guard result != nil else {
            return nil
        }
        textView.insertText(event.characters ?? "", replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        let caretUTF8 = utf8Offset(
            in: textView.string,
            utf16Offset: textView.selectedRange().location
        ) ?? textView.string.utf8.count
        model.editorTextDidChange(cursorUTF8Offset: caretUTF8)
        return result
    }

    private func processClient(
        recordURL: URL,
        extra: [String: String] = [:]
    ) throws -> BobProcessClient {
        var environment = [
            "HOME": "/tmp",
            "PATH": "/usr/bin:/bin",
            "FAKE_BOB_RECORD_PATH": recordURL.path,
        ]
        environment.merge(extra) { _, new in new }
        return BobProcessClient(
            executablePath: try fakeBobPath(),
            environment: environment
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

    private func makeRecordURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func relationCandidate() -> CaptureCompletionCandidate {
        CaptureCompletionCandidate(
            replacement: "~tasks:target",
            taskRef: "1:aaaa1111",
            blockID: "target",
            requiresBlockID: false,
            statusSymbol: " ",
            statusName: "Todo",
            text: "Target",
            group: "open",
            notePath: "tasks.md",
            locator: "tasks"
        )
    }

    private func installLinksToPicker(
        on model: CapturePanelModel,
        filter: String = "",
        draft: String = "New task ~"
    ) {
        model.installRelationPickerForPreviews(
            candidates: [relationCandidate()],
            filter: filter,
            draft: draft,
            replacement: CaptureRange(start: 9, end: draft.utf8.count),
            owner: DependencyOwner(kind: "new_task", text: "New task"),
            direction: .linksTo
        )
    }

    func testEqualsFlipsOpenLinksToPickerAndBack() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, _, panel) = makeHostedEditor(text: "New task ~")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)
        installLinksToPicker(on: model)
        XCTAssertEqual(model.picker?.source, .linksTo)

        XCTAssertNil(controller.routeKeyDown(equalsEvent()))
        XCTAssertEqual(model.plainDraft, "New task ~~")
        await waitUntil { model.picker?.source == .linkedFrom }
        XCTAssertEqual(model.picker?.filterText, "")
        XCTAssertTrue(model.pickerVisible)

        XCTAssertNil(controller.routeKeyDown(equalsEvent()))
        XCTAssertEqual(model.plainDraft, "New task ~")
        await waitUntil { model.picker?.source == .linksTo }
        XCTAssertTrue(model.pickerVisible)
    }

    func testEqualsFlipsWithFilterAndKeepsIt() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, _, panel) = makeHostedEditor(text: "New task ~")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)
        installLinksToPicker(on: model, filter: "tar")
        XCTAssertEqual(model.picker?.filterText, "tar")

        XCTAssertNil(controller.routeKeyDown(equalsEvent()))
        XCTAssertEqual(model.plainDraft, "New task ~~")
        await waitUntil { model.picker?.source == .linkedFrom }
        XCTAssertEqual(model.picker?.filterText, "tar")
        XCTAssertTrue(model.pickerVisible)
    }

    func testArmedDashEqualsFlipsInsteadOfRestoring() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)
        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Fix it ~" && model.picker?.source == .linksTo
                && model.picker?.filterText.isEmpty == true
        }
        XCTAssertNotNil(model.relationDashLiteralArm)

        XCTAssertNil(controller.routeKeyDown(equalsEvent()))
        XCTAssertEqual(model.plainDraft, "Fix it ~~")
        XCTAssertNil(model.relationDashLiteralArm)
        await waitUntil { model.picker?.source == .linkedFrom }
        XCTAssertTrue(model.pickerVisible)

        XCTAssertNil(controller.routeKeyDown(backspaceEvent()))
        XCTAssertEqual(model.plainDraft, "Fix it ~")
        await waitUntil { model.picker?.source == .linksTo }
    }

    func testEqualsInEditorOpensLinkedFromViaRewrite() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "New task ~")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)

        XCTAssertNotNil(typeKey(equalsEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "New task ~~" && model.picker?.source == .linkedFrom
        }
        XCTAssertEqual(model.plainDraft, "New task ~~")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 11 --format json -- New task ~="))
    }

    func testDashEqualsBackToBackDropsStaleDashReply() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.4"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertNotNil(typeKey(equalsEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Fix it ~~" && model.picker?.source == .linkedFrom
        }
        XCTAssertEqual(model.plainDraft, "Fix it ~~")
        let record = try String(contentsOf: recordURL)
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 8 --format json -- Fix it -"))
        XCTAssertTrue(record.contains("argv=capture-rewrite --cursor 9 --format json -- Fix it -="))
    }

    func testUndoAfterEqualsRewriteRestoresTypedSigils() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "New task ~")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(recordURL: recordURL)

        XCTAssertNotNil(typeKey(equalsEvent(), into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "New task ~~" }
        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "New task ~=")
    }

    func testOlderBobLeavesEqualsLiteralWithoutOpeningPicker() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "New task ~")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_RELATION_FLIP_UNCHANGED": "1"]
        )

        XCTAssertNotNil(typeKey(equalsEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "New task ~="
                && (try? String(contentsOf: recordURL))?.contains("argv=capture-rewrite") == true
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertEqual(textView.string, "New task ~=")
    }
}
