import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

@MainActor
final class CaptureRelationDashAliasTests: XCTestCase {
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

    private func dashEvent(
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(keyCode: 27, characters: "-", modifiers: modifiers, isRepeat: isRepeat)
    }

    private func spaceEvent() -> NSEvent {
        keyEvent(keyCode: 49, characters: " ")
    }

    private func escapeEvent() -> NSEvent {
        keyEvent(keyCode: 53, characters: "")
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

    private func openAlias() async throws -> (
        CapturePanelModel,
        CapturePanelController,
        NSTextView,
        NSPanel,
        URL
    ) {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        model.processClient = try processClient(recordURL: recordURL)
        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Fix it ~" && model.picker?.source == .linksTo
                && model.picker?.filterText.isEmpty == true
        }
        return (model, controller, textView, panel, recordURL)
    }

    func testDashAliasOpensLinksToAndCallsRewriteBeforeCompletion() async throws {
        let (model, _, _, panel, recordURL) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertEqual(model.picker?.draftSnapshot, "Fix it ~")
        XCTAssertEqual(model.picker?.replacementRange.start, 7)
        let record = try String(contentsOf: recordURL)
        let rewrite = try XCTUnwrap(record.range(of: "argv=capture-rewrite --cursor 8 --format json -- Fix it -"))
        let complete = try XCTUnwrap(record.range(of: "argv=capture-complete --all-tasks --cursor 8 --format json -- Fix it ~"))
        XCTAssertLessThan(rewrite.lowerBound, complete.lowerBound)
    }

    func testSpaceRestoresDashAndUndoRestoresTheAliasDraft() async throws {
        let (model, controller, textView, panel, _) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertNil(typeKey(spaceEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Fix it - ")
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 9, length: 0))
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.pickerChip)
        XCTAssertNil(model.relationDashLiteralArm)

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Fix it ~")
    }

    func testSecondDashRestoresDoubleDashForTheTabEmDashSnippet() async throws {
        let (model, controller, textView, panel, _) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Fix it --")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertTrue(CapturePanelController.applySnippetExpansion(
            firstResponder: textView,
            model: model
        ))
        XCTAssertEqual(textView.string, "Fix it —")
    }

    func testEscapeRestoresDashInsteadOfShowingPickerChip() async throws {
        let (model, controller, textView, panel, _) = try await openAlias()
        defer { panel.orderOut(nil) }

        XCTAssertNil(typeKey(escapeEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Fix it -")
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.pickerChip)
    }

    func testFastSpaceRestoresDashBeforeTheCompletionReplyOpens() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_RELATION_DASH_COMPLETE_DELAY_SECONDS": "0.4"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Fix it ~" && model.relationDashLiteralArm != nil
                && !model.pickerVisible
        }
        XCTAssertNil(typeKey(spaceEvent(), into: textView, model: model, controller: controller))
        XCTAssertEqual(textView.string, "Fix it - ")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(model.pickerVisible)
    }

    func testOlderBobLeavesDashLiteralWithoutOpeningPicker() async throws {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: "Fix it ")
        defer { panel.orderOut(nil) }
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_REWRITE_RELATION_DASH_UNCHANGED": "1"]
        )

        XCTAssertNotNil(typeKey(dashEvent(), into: textView, model: model, controller: controller))
        await waitUntil {
            textView.string == "Fix it -"
                && (try? String(contentsOf: recordURL))?.contains("argv=capture-rewrite") == true
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(model.pickerVisible)
        XCTAssertNil(model.relationDashLiteralArm)
    }

    func testRouterRestoresOnlyTheArmedEmptyLinksToFilterKeys() {
        let router = CaptureKeyCommandRouter()
        var armed = CaptureKeyRoutingContext()
        armed.pickerSourceIsRelation = true
        armed.pickerVisible = true
        armed.pickerFilterIsEmpty = true
        armed.relationDashLiteralArmed = true
        XCTAssertEqual(
            router.command(for: spaceEvent(), context: armed),
            .restoreRelationDashLiteral(" ")
        )
        XCTAssertEqual(
            router.command(for: dashEvent(), context: armed),
            .restoreRelationDashLiteral("-")
        )
        XCTAssertEqual(
            router.command(for: escapeEvent(), context: armed),
            .restoreRelationDashLiteral("")
        )
        XCTAssertEqual(
            router.command(for: dashEvent(isRepeat: true), context: armed),
            .consumeKey
        )

        var filtered = CaptureKeyRoutingContext()
        filtered.pickerSourceIsRelation = true
        filtered.pickerVisible = true
        filtered.pickerFilterIsEmpty = false
        XCTAssertNil(router.command(for: spaceEvent(), context: filtered))
        XCTAssertEqual(
            router.command(
                for: keyEvent(keyCode: 50, characters: "~"),
                context: armed
            ),
            .flipRelationDirection
        )
    }

    func testEditorRaceWindowRestoresBeforePickerVisibility() {
        let router = CaptureKeyCommandRouter()
        let context = CaptureKeyRoutingContext(relationDashLiteralArmed: true)
        XCTAssertEqual(
            router.command(for: spaceEvent(), context: context),
            .restoreRelationDashLiteral(" ")
        )
        XCTAssertEqual(
            router.command(for: dashEvent(), context: context),
            .restoreRelationDashLiteral("-")
        )
    }
}
