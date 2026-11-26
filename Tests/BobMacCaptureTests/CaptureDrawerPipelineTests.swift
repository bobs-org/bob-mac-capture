import AppKit
import CaptureCore
import XCTest

@testable import BobMacCapture

/// Bob-driven drawer star expansion and atomic Backspace, driven through the
/// real `routeKeyDown` with a hosted panel and fake-bob rewrite replies.
/// Mirrors `CaptureRequirementPipelineTests`' hosted style and the requirement
/// `*`-assist contract: Bob decides, the Mac only applies one undoable edit.
@MainActor
final class CaptureDrawerPipelineTests: XCTestCase {
    private func keyEvent(
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = [],
        timestamp: TimeInterval = 0,
        isRepeat: Bool = false
    ) -> NSEvent {
        NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: timestamp,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isRepeat,
            keyCode: keyCode
        )!
    }

    private func starEvent(
        modifiers: NSEvent.ModifierFlags = [],
        isRepeat: Bool = false
    ) -> NSEvent {
        keyEvent(keyCode: 28, characters: "*", modifiers: modifiers, isRepeat: isRepeat)
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
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.string = text
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        model.plainDraft = text
        model.applyNativeRewriteEdit = { edit in
            CapturePanelController.applySeparatorToggleInEditableTextView(
                edit,
                firstResponder: textView
            )
        }
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

    private func makeRecordURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func waitUntil(
        timeout: TimeInterval = 10,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool,
        detail: () -> String = { "" }
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Condition not met before timeout\(detail())", file: file, line: line)
                return
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func openDrawerDraft(
        _ text: String,
        extra: [String: String] = [:]
    ) throws -> (CapturePanelModel, CapturePanelController, NSTextView, NSPanel, URL) {
        let recordURL = makeRecordURL()
        let (model, controller, textView, panel) = makeHostedEditor(text: text)
        model.processClient = try processClient(recordURL: recordURL, extra: extra)
        return (model, controller, textView, panel, recordURL)
    }

    private func caretBetweenPairs(_ textView: NSTextView) -> Int {
        (textView.string as NSString).length - 2
    }

    func testStarExpandsNewTaskDrawer() async throws {
        let (model, controller, textView, panel, _) = try openDrawerDraft("Prepare release\n- ")
        defer { panel.orderOut(nil) }

        XCTAssertNotNil(
    typeKey(starEvent(), into: textView, model: model, controller: controller)
)
        await waitUntil { textView.string == "Prepare release\n- ****" }
        XCTAssertEqual(
    textView.selectedRange(),
    NSRange(location: caretBetweenPairs(textView), length: 0)
)
        XCTAssertEqual(model.plainDraft, "Prepare release\n- ****")

        textView.undoManager?.undo()
        XCTAssertEqual(textView.string, "Prepare release\n- *")
        textView.undoManager?.redo()
        XCTAssertEqual(textView.string, "Prepare release\n- ****")
    }

    func testShiftStarExpandsLikeABareStar() async throws {
        let (_, controller, textView, panel, _) = try openDrawerDraft("Prepare release\n- ")
        defer { panel.orderOut(nil) }

        XCTAssertNotNil(typeKey(
            starEvent(modifiers: [.shift]),
            into: textView,
            model: model,
            controller: controller
        ))
        await waitUntil { textView.string == "Prepare release\n- ****" }
        XCTAssertEqual(
    textView.selectedRange(),
    NSRange(location: caretBetweenPairs(textView), length: 0)
)
    }

    func testStarExpandsAcrossEligibleFamilies() async throws {
        for draft in [
            "@foo+plain\n- ",
            "Draft plan @project^draft@\n- ",
            "Create notes @parent^seed@ %n\n- ",
            "Went back @eat/nagi\n- ",
            "Prepare 🚀 release\n- ",
        ] {
            let (model, controller, textView, panel, _) = try openDrawerDraft(draft)
            defer { panel.orderOut(nil) }
            XCTAssertNotNil(
    typeKey(starEvent(), into: textView, model: model, controller: controller)
)
            await waitUntil { textView.string == draft + "***" }
            XCTAssertEqual(
                textView.selectedRange(),
                NSRange(location: caretBetweenPairs(textView), length: 0)
            )
            XCTAssertTrue(model.plainDraft.hasSuffix("****"))
        }
    }

    func testQueuedStarIsAbsorbedOnce() async throws {
        let (_, controller, textView, panel, _) = try openDrawerDraft("Prepare release\n- ")
        defer { panel.orderOut(nil) }

        XCTAssertNotNil(
    typeKey(starEvent(), into: textView, model: model, controller: controller)
)
        await waitUntil { textView.string == "Prepare release\n- ****" }

        XCTAssertNil(controller.routeKeyDown(starEvent()))
        XCTAssertEqual(textView.string, "Prepare release\n- ****")
        XCTAssertEqual(
    textView.selectedRange(),
    NSRange(location: caretBetweenPairs(textView), length: 0)
)

        XCTAssertNotNil(
    typeKey(starEvent(), into: textView, model: model, controller: controller)
)
        XCTAssertEqual(textView.string, "Prepare release\n- ******")
    }

    func testBackspaceDeletesSkeletonViaExpansionArm() async throws {
        let (_, controller, textView, panel, _) = try openDrawerDraft("Prepare release\n- ")
        defer { panel.orderOut(nil) }

        XCTAssertNotNil(
    typeKey(starEvent(), into: textView, model: model, controller: controller)
)
        await waitUntil { textView.string == "Prepare release\n- ****" }

        XCTAssertTrue(controller.perform(.deleteBackward))
        XCTAssertEqual(textView.string, "Prepare release\n- ")
    }

    func testBackspaceDeletesSkeletonViaFreshParse() async throws {
        let draft = "Prepare release\n- ****"
        let recordURL = makeRecordURL()
        let (model, _, textView, panel) = makeHostedEditor(text: draft)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PARSE_FIXTURE": "drawer-parse-empty-skeleton.json"]
        )
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: (draft as NSString).length - 2, length: 0))
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count - 2)
        await waitUntil { model.latestParse?.input == draft }
        model.cancelDrawerMarkerOvertype()

        XCTAssertTrue(CapturePanelController.deleteDrawerMarkerInEditableTextView(
            firstResponder: textView,
            model: model
        ))
        XCTAssertEqual(textView.string, "Prepare release\n- ")
    }

    func testBackspaceStaysNativeOffTheSkeleton() async throws {
        let draft = "Prepare release\n- ****"
        let recordURL = makeRecordURL()
        let (model, _, textView, panel) = makeHostedEditor(text: draft)
        model.processClient = try processClient(
            recordURL: recordURL,
            extra: ["FAKE_BOB_PARSE_FIXTURE": "drawer-parse-empty-skeleton.json"]
        )
        defer { panel.orderOut(nil) }
        textView.setSelectedRange(NSRange(location: (draft as NSString).length, length: 0))
        model.editorTextDidChange(cursorUTF8Offset: draft.utf8.count)
        await waitUntil { model.latestParse?.input == draft }

        XCTAssertFalse(CapturePanelController.deleteDrawerMarkerInEditableTextView(
            firstResponder: textView,
            model: model
        ))
        XCTAssertEqual(textView.string, draft)
    }

    func testLiteralStarsStayNative() async throws {
        for draft in [
            "@foo+bar\n  - ",
            "@dev_tools\n- ",
            "Buy 2 ",
            "Postgres 17 minimum @foo+bar\n- [ ] Buy ",
            "Fix it ",
        ] {
            let (model, controller, textView, panel, recordURL) = try openDrawerDraft(draft)
            defer { panel.orderOut(nil) }
            XCTAssertNotNil(
    typeKey(starEvent(), into: textView, model: model, controller: controller)
)
            await waitUntil(timeout: 5) { !model.rewriteInFlightForTesting }
            XCTAssertEqual(textView.string, draft + "*", draft)
            XCTAssertFalse(CapturePanelController.deleteDrawerMarkerInEditableTextView(
                firstResponder: textView,
                model: model
            ), draft)
            let record = (try? String(contentsOf: recordURL)) ?? ""
            XCTAssertFalse(
                record.contains("expand_drawer_marker"),
                "\(draft): \(record)"
            )
        }
    }

    func testStaleReplyAfterCaretMoveKeepsTypedStar() async throws {
        let (model, controller, textView, panel, _) = try openDrawerDraft(
            "Prepare release\n- ",
            extra: ["FAKE_BOB_REWRITE_DELAY_SECONDS": "0.5"]
        )
        defer { panel.orderOut(nil) }

        XCTAssertNotNil(
    typeKey(starEvent(), into: textView, model: model, controller: controller)
)
        XCTAssertEqual(textView.string, "Prepare release\n- *")
        model.editorSelectionDidChange(cursorUTF8Offset: 0)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        XCTAssertEqual(textView.string, "Prepare release\n- *")
        XCTAssertFalse(model.rewriteInFlightForTesting)
    }

    func testFailedRewriteKeepsTypedStar() async throws {
        let (model, controller, textView, panel, _) = try openDrawerDraft(
            "Prepare release\n- ",
            extra: ["FAKE_BOB_REWRITE_FAIL": "1"]
        )
        defer { panel.orderOut(nil) }

        XCTAssertNotNil(
    typeKey(starEvent(), into: textView, model: model, controller: controller)
)
        await waitUntil(timeout: 5) { !model.rewriteInFlightForTesting }
        XCTAssertEqual(textView.string, "Prepare release\n- *")
        XCTAssertFalse(CapturePanelController.deleteDrawerMarkerInEditableTextView(
            firstResponder: textView,
            model: model
        ))
    }

    func testPastedStarNeverAsksBob() async throws {
        let (model, _, textView, panel, recordURL) = try openDrawerDraft("Prepare release\n- ")
        defer { panel.orderOut(nil) }

        textView.insertText("* more", replacementRange: textView.selectedRange())
        model.plainDraft = textView.string
        model.editorTextDidChange(cursorUTF8Offset: textView.string.utf8.count)
        try? await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(textView.string, "Prepare release\n- * more")
        let record = (try? String(contentsOf: recordURL)) ?? ""
        XCTAssertFalse(record.contains("argv=capture-rewrite"), record)
    }

    func testRequirementExpansionStillApplies() async throws {
        let (_, controller, textView, panel, _) = try openDrawerDraft(
            "Ship 🧭\n- [",
            extra: ["FAKE_BOB_PARSE_FIXTURE": "capture-parse-requirement-marker.json"]
        )
        defer { panel.orderOut(nil) }

        let space = keyEvent(keyCode: 49, characters: " ")
        XCTAssertNotNil(typeKey(space, into: textView, model: model, controller: controller))
        await waitUntil { textView.string == "Ship 🧭\n- [ ] " }
        XCTAssertTrue(controller.perform(.deleteBackward))
        XCTAssertEqual(textView.string, "Ship 🧭\n- ")
    }
}
